local _G = _G
local L = Sku.L

---------------------------------------------------------------------------------------------------------------------------------------
-- Pending prompts ("Ausstehend")
--
-- PROBLEM. A handful of Blizzard prompts are transient FRAMES over a persistent
-- SERVER-SIDE state: the death/release dialog, a warlock/meeting-stone summon, an
-- incoming resurrect, a ready check. Sku's Local menu is gated purely on frame
-- VISIBILITY (SkuCore.interactFramesList / localWindowContributors), and the Sku
-- menu's OnHide (SkuZOptions/Core.lua) unconditionally runs StaticPopup1:Hide() so
-- that closing the menu does not leave a Blizzard window behind. Consequence: press
-- Escape out of the bags while a summon is up and the popup is hidden -> it drops out
-- of Local and is unreachable until a /reload (PLAYER_ENTERING_WORLD is the only
-- place Blizzard re-shows DEATH/CONFIRM_SUMMON). The summon itself is still perfectly
-- valid the whole time.
--
-- Note StaticPopup1:Hide() is SAFE for the state: a raw :Hide() only reaches
-- StaticPopup_OnHide, never OnCancel, so nothing is declined/released by hiding.
--
-- SOLUTION. Keep hiding the frame (unchanged), and re-offer the prompt from the
-- STATE instead. Each descriptor below answers "is this still live?" via a query API
-- and acts via the matching action API -- no frame needed. The node is rendered as a
-- child of Local by SkuOptions:MenuBuilderLocal.
--
-- THE IMPORTANT INVARIANT: pending prompts are PASSIVE. In SkuCore:CheckFrames the
-- same "is anything open" predicate does two jobs -- it keeps an open menu alive
-- (else-branch -> CloseMenu) AND it force-opens/auto-descends the menu (the SlashFunc
-- navigation block). Pending state must feed the FIRST but never the SECOND: a
-- permanently reachable prompt that also force-opened the menu would yank the menu
-- open onto itself on every bag update or menu action. CheckFrames therefore counts
-- pending for the branch, then skips the navigation when pending is the ONLY reason
-- it got there (tPendingOnly). See SkuCore/Core.lua.
--
-- DEDUP: a prompt is only offered here while its own popup is NOT currently shown,
-- so it never doubles up with the "Popup 1" frame-scrape node.
--
-- No ticker: SkuCore:UpdateLocalRootEntry() runs on every menu open
-- (SkuZOptions/Core.lua), so the node is re-evaluated whenever the user opens the
-- menu -- which is the only moment it can be seen. While a prompt's popup is visible
-- the normal frame path already drives the menu.
---------------------------------------------------------------------------------------------------------------------------------------

local function tSeconds(aValue)
	local n = tonumber(aValue)
	if not n or n <= 0 then return nil end
	return math.floor(n + 0.5)
end

-- "noch 42 Sekunden" / "42 seconds left", appended to a prompt label when we have a timer.
local function tTimeLeftSuffix(aSeconds)
	local s = tSeconds(aSeconds)
	if not s then return "" end
	if s >= 60 then
		local m = math.floor(s / 60)
		return ", " .. Sku.deEn("noch " .. m .. " Minuten", m .. " minutes left")
	end
	return ", " .. Sku.deEn("noch " .. s .. " Sekunden", s .. " seconds left")
end

-- True when ANY of the given StaticPopup dialog keys is currently on screen. Used to
-- suppress the pending entry while the real dialog is still visible (the frame-scrape
-- "Popup 1" node covers it then).
local function tAnyPopupVisible(aWhichList)
	if not _G.StaticPopup_Visible then return false end
	for _, tWhich in ipairs(aWhichList) do
		local ok, res = pcall(StaticPopup_Visible, tWhich)
		if ok and res then return true end
	end
	return false
end

-- Safe global call: several of these APIs are absent on some clients/flavours.
local function tCall(aName, ...)
	local f = _G[aName]
	if type(f) ~= "function" then return nil end
	local ok, res = pcall(f, ...)
	if not ok then return nil end
	return res
end

---------------------------------------------------------------------------------------------------------------------------------------
-- READY_CHECK initiator capture.
-- ReadyCheckFrame_OnHide (Blizzard_ReadyCheck) clears ReadyCheckFrame.initiator, so
-- once the frame is gone the name is unrecoverable from the frame. Cache it from the
-- event ourselves. Private frame (not the dispatcher): no other Sku file needs
-- READY_CHECK, same pattern as the zone-event frame in SkuCore/Core.lua.
---------------------------------------------------------------------------------------------------------------------------------------
SkuCore.pendingReadyCheckInitiator = nil

local tReadyCheckFrame = CreateFrame("Frame")
tReadyCheckFrame:RegisterEvent("READY_CHECK")
tReadyCheckFrame:RegisterEvent("READY_CHECK_FINISHED")
tReadyCheckFrame:SetScript("OnEvent", function(self, aEvent, aInitiator)
	if aEvent == "READY_CHECK" then
		SkuCore.pendingReadyCheckInitiator = aInitiator
	else
		SkuCore.pendingReadyCheckInitiator = nil
	end
end)

---------------------------------------------------------------------------------------------------------------------------------------
-- Descriptors. `active` = still live per the game's own state; `popups` = dialog keys
-- that render the same thing (suppress while any is visible); `label` = the spoken
-- headline; `actions` = the leaf children (label + func).
--
-- Every descriptor also gets a "show dialog again" leaf appended (see the builder):
-- StaticPopup_Show / the frame's own Show is what Blizzard itself calls, so it is the
-- guaranteed-working escape hatch if a direct action API ever refuses.
---------------------------------------------------------------------------------------------------------------------------------------
SkuCore.pendingPrompts = {
	--------------------------------------------------------------------------------
	-- Summon (warlock ritual, meeting stone, ...). Server keeps it for ~2 minutes.
	--------------------------------------------------------------------------------
	{
		id = "summon",
		popups = { "CONFIRM_SUMMON", "CONFIRM_SUMMON_SCENARIO", "CONFIRM_SUMMON_STARTING_AREA" },
		active = function()
			if not C_SummonInfo or not C_SummonInfo.GetSummonConfirmTimeLeft then return false end
			local ok, tLeft = pcall(C_SummonInfo.GetSummonConfirmTimeLeft)
			return ok and type(tLeft) == "number" and tLeft > 0
		end,
		label = function()
			local tWho, tWhere, tLeft
			pcall(function() tWho = C_SummonInfo.GetSummonConfirmSummoner() end)
			pcall(function() tWhere = C_SummonInfo.GetSummonConfirmAreaName() end)
			pcall(function() tLeft = C_SummonInfo.GetSummonConfirmTimeLeft() end)
			local tText = Sku.deEn("Beschwörung", "Summon")
			if tWho and tWho ~= "" then tText = tText .. " " .. Sku.deEn("von", "from") .. " " .. tWho end
			if tWhere and tWhere ~= "" then tText = tText .. " " .. Sku.deEn("nach", "to") .. " " .. tWhere end
			return tText .. tTimeLeftSuffix(tLeft)
		end,
		showDialog = function() pcall(StaticPopup_Show, "CONFIRM_SUMMON") end,
		actions = {
			{ label = function() return _G.ACCEPT or Sku.deEn("Annehmen", "Accept") end,
			  func = function() pcall(function() C_SummonInfo.ConfirmSummon() end) end },
			{ label = function() return _G.CANCEL or Sku.deEn("Ablehnen", "Decline") end,
			  func = function() pcall(function() C_SummonInfo.CancelSummon() end) end },
		},
	},

	--------------------------------------------------------------------------------
	-- Incoming resurrect. ResurrectGetOfferer() stays valid until accepted, declined
	-- or timed out server-side; hiding the popup does none of those.
	--------------------------------------------------------------------------------
	{
		id = "resurrect",
		popups = { "RESURRECT", "RESURRECT_NO_SICKNESS", "RESURRECT_NO_TIMER" },
		active = function()
			local tOfferer = tCall("ResurrectGetOfferer")
			return tOfferer ~= nil and tOfferer ~= ""
		end,
		label = function()
			local tOfferer = tCall("ResurrectGetOfferer")
			local tText = Sku.deEn("Wiederbelebung", "Resurrection")
			if tOfferer and tOfferer ~= "" then
				tText = tText .. " " .. Sku.deEn("von", "from") .. " " .. tOfferer
			end
			return tText
		end,
		showDialog = function()
			-- Mirrors Blizzard's own ShowResurrectRequest() dispatch (Shared/UIParent.lua).
			local tOfferer = tCall("ResurrectGetOfferer")
			if not tOfferer then return end
			if tCall("ResurrectHasSickness") then
				pcall(StaticPopup_Show, "RESURRECT", tOfferer)
			elseif tCall("ResurrectHasTimer") then
				pcall(StaticPopup_Show, "RESURRECT_NO_SICKNESS", tOfferer)
			else
				pcall(StaticPopup_Show, "RESURRECT_NO_TIMER", tOfferer)
			end
		end,
		actions = {
			{ label = function() return _G.ACCEPT or Sku.deEn("Annehmen", "Accept") end,
			  func = function() tCall("AcceptResurrect") end },
			{ label = function() return _G.DECLINE or Sku.deEn("Ablehnen", "Decline") end,
			  func = function() tCall("DeclineResurrect") end },
		},
	},

	--------------------------------------------------------------------------------
	-- Death / release. GetReleaseTimeRemaining() > 0, or -1 for "no timer".
	-- Suppressed while a resurrect offer is pending, because Blizzard hides DEATH in
	-- that case too (RESURRECT* declares cancels = "DEATH") -- offering "release
	-- spirit" next to an open res offer would be a trap.
	--------------------------------------------------------------------------------
	{
		id = "death",
		popups = { "DEATH" },
		active = function()
			if tCall("UnitIsDeadOrGhost", "player") ~= true then return false end
			if tCall("UnitIsGhost", "player") == true then return false end
			local tOfferer = tCall("ResurrectGetOfferer")
			if tOfferer and tOfferer ~= "" then return false end
			local tLeft = tCall("GetReleaseTimeRemaining")
			return type(tLeft) == "number" and (tLeft > 0 or tLeft == -1)
		end,
		label = function()
			local tLeft = tCall("GetReleaseTimeRemaining")
			local tText = Sku.deEn("Tod", "Death")
			if type(tLeft) == "number" and tLeft > 0 then
				tText = tText .. tTimeLeftSuffix(tLeft)
			end
			return tText
		end,
		showDialog = function() pcall(StaticPopup_Show, "DEATH") end,
		actions = {
			{ label = function() return _G.DEATH_RELEASE or Sku.deEn("Geist freigeben", "Release spirit") end,
			  func = function() tCall("RepopMe") end },
		},
		-- Self-res options (soulstone, ankh, ...) are dynamic, so they are appended at
		-- build time rather than declared. The old HasSoulstone/UseSoulstone globals are
		-- gone on this client; the live path is C_DeathInfo.GetSelfResurrectOptions ->
		-- UseSelfResurrectOption(optionType, id), exactly as Blizzard's own
		-- GameDialogDefsUtil.OnResurrectButtonClick does it.
		extraActions = function()
			local tOut = {}
			if not (C_DeathInfo and C_DeathInfo.GetSelfResurrectOptions and C_DeathInfo.UseSelfResurrectOption) then
				return tOut
			end
			local ok, tOptions = pcall(C_DeathInfo.GetSelfResurrectOptions)
			if not ok or type(tOptions) ~= "table" then return tOut end
			for _, tOption in ipairs(tOptions) do
				if type(tOption) == "table" and tOption.canUse and tOption.optionType and tOption.id then
					local tName = tOption.name or _G.USE_SOULSTONE or Sku.deEn("Selbst wiederbeleben", "Self resurrect")
					local tType, tId = tOption.optionType, tOption.id
					tOut[#tOut + 1] = {
						label = function() return tName end,
						func = function() pcall(function() C_DeathInfo.UseSelfResurrectOption(tType, tId) end) end,
					}
				end
			end
			return tOut
		end,
	},

	--------------------------------------------------------------------------------
	-- Ready check. Short-lived by design: the server finishes it after ~35s
	-- (READY_CHECK_FINISHED auto-answers AFK), so this entry is expected to vanish on
	-- its own. ReadyCheckFrame is NOT in the menu's OnHide close-list, so it normally
	-- survives an Escape -- this covers the case where it was hidden anyway.
	--------------------------------------------------------------------------------
	{
		id = "readycheck",
		popups = {},
		active = function()
			local tLeft = tCall("GetReadyCheckTimeLeft")
			if type(tLeft) ~= "number" or tLeft <= 0 then return false end
			if tCall("GetReadyCheckStatus", "player") ~= "waiting" then return false end
			local f = _G["ReadyCheckFrame"]
			if f and f.IsVisible and f:IsVisible() then return false end
			return true
		end,
		label = function()
			local tWho = SkuCore.pendingReadyCheckInitiator
			local tLeft = tCall("GetReadyCheckTimeLeft")
			local tText = L["Bereitschaft check"] or Sku.deEn("Bereitschaftscheck", "Ready check")
			if tWho and tWho ~= "" then tText = tText .. " " .. Sku.deEn("von", "from") .. " " .. tWho end
			return tText .. tTimeLeftSuffix(tLeft)
		end,
		showDialog = function()
			local f = _G["ReadyCheckFrame"]
			if f and f.Show then pcall(function() f:Show() end) end
		end,
		actions = {
			{ label = function() return _G.READY or Sku.deEn("Bereit", "Ready") end,
			  func = function() tCall("ConfirmReadyCheck", 1) end },
			{ label = function() return _G.NOT_READY or Sku.deEn("Nicht bereit", "Not ready") end,
			  func = function() tCall("ConfirmReadyCheck") end },
		},
	},
}

---------------------------------------------------------------------------------------------------------------------------------------
-- The live list: descriptors whose state says "still pending" AND whose own dialog is
-- not currently on screen.
---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore:PendingPromptList()
	local tOut = {}
	if not SkuCore.pendingPrompts then return tOut end
	for _, tPrompt in ipairs(SkuCore.pendingPrompts) do
		local ok, tActive = pcall(tPrompt.active)
		if ok and tActive == true then
			if not tAnyPopupVisible(tPrompt.popups or {}) then
				tOut[#tOut + 1] = tPrompt
			end
		end
	end
	return tOut
end

-- Cheap boolean form used by HasLocalContent / CheckFrames / the flash re-check.
function SkuCore:HasPendingPrompts()
	return #SkuCore:PendingPromptList() > 0
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Menu. One submenu per live prompt (headline = label()), its actions as leaves.
-- Called from SkuOptions:MenuBuilderLocal as the "Ausstehend" contributor's build.
---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore.PendingPromptsMenuBuilder(aParentEntry)
	local tList = SkuCore:PendingPromptList()
	for _, tPrompt in ipairs(tList) do
		local tLabel
		local ok, tRes = pcall(tPrompt.label)
		tLabel = (ok and tRes) or tPrompt.id

		SkuMenu:BuildNode(aParentEntry, {
			kind = "submenu",
			label = tLabel,
			build = function(self)
				local tActions = {}
				for _, tAction in ipairs(tPrompt.actions or {}) do
					tActions[#tActions + 1] = tAction
				end
				if tPrompt.extraActions then
					local ok2, tExtra = pcall(tPrompt.extraActions)
					if ok2 and type(tExtra) == "table" then
						for _, tAction in ipairs(tExtra) do
							tActions[#tActions + 1] = tAction
						end
					end
				end

				for _, tAction in ipairs(tActions) do
					local okL, tActionLabel = pcall(tAction.label)
					SkuMenu:BuildNode(self, {
						kind = "action",
						label = (okL and tActionLabel) or "?",
						dynamic = false,
						onAction = function()
							pcall(tAction.func)
							-- The prompt is answered: refresh Local so the entry drops out.
							if C_Timer and C_Timer.After then
								C_Timer.After(0.2, function() pcall(function() SkuCore:CheckFrames() end) end)
							end
						end,
					})
				end

				-- Escape hatch: put Blizzard's own dialog back on screen. Its Show fires
				-- the interactFramesList hook -> CheckFrames -> the menu lands on
				-- "Popup 1", which is what the user just asked for, so the force-open is
				-- wanted here.
				if tPrompt.showDialog then
					SkuMenu:BuildNode(self, {
						kind = "action",
						label = Sku.deEn("Fenster erneut anzeigen", "Show dialog again"),
						dynamic = false,
						onAction = function() pcall(tPrompt.showDialog) end,
					})
				end
			end,
		})
	end
end
