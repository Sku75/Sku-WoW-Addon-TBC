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
-- A raw :Hide() never reaches OnCancel, so for most of these nothing is
-- declined/released by hiding -- the state simply becomes invisible. The ONE exception
-- is PARTY_INVITE, whose OnHide answers the prompt itself; see the group-invite section
-- below and SkuCore:NeutralizePopupHide.
--
-- SOLUTION. Keep hiding the frame (unchanged), and re-offer the prompt from the
-- STATE instead. Each descriptor below answers "is this still live?" via a query API
-- and can put Blizzard's own dialog back on screen (showDialog) -- no frame needed
-- to KNOW about the prompt. The prompt is rendered as ONE flat node directly under
-- Local by SkuOptions:MenuBuilderLocal: the entry carries the prompt's name and
-- RIGHT/ENTER re-shows the real window, whose buttons then arrive via the normal
-- frame-scrape path. (An earlier version nested Accept/Decline action leaves under
-- an "Ausstehend" submenu; that duplicated the window's own buttons two levels deep
-- and was dropped as too much navigation overhead.)
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

-- Blizzard's StaticPopupTimeoutSec (Blizzard_StaticPopup/StaticPopup.lua) -- the group
-- invite dialog's own timeout, used as our fallback deadline when the dialog is not
-- around to read a live .timeleft from. Must be an upvalue of the event handler below.
local tInviteTimeout = 60

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
tReadyCheckFrame:RegisterEvent("PARTY_INVITE_REQUEST")
tReadyCheckFrame:RegisterEvent("PARTY_INVITE_CANCEL")
tReadyCheckFrame:SetScript("OnEvent", function(self, aEvent, ...)
	if aEvent == "READY_CHECK" then
		SkuCore.pendingReadyCheckInitiator = (...)
	elseif aEvent == "READY_CHECK_FINISHED" then
		SkuCore.pendingReadyCheckInitiator = nil
	elseif aEvent == "PARTY_INVITE_REQUEST" then
		-- args: name, tank, healer, damage, isXRealm, allowMultipleRoles, inviterGuid
		local tName = (...)
		SkuCore.pendingGroupInvite = { name = tName, expiresAt = GetTime() + tInviteTimeout }
		SkuCore.EnsureInviteHideHooks()
	elseif aEvent == "PARTY_INVITE_CANCEL" then
		SkuCore.pendingGroupInvite = nil
	end
end)

---------------------------------------------------------------------------------------------------------------------------------------
-- Group invite: the ONE prompt whose state a plain :Hide() destroys.
--
-- StaticPopupDialogs["PARTY_INVITE"].OnHide calls DeclineGroup() unless
-- dialog.inviteAccepted is set, and OnHide DOES fire on a raw frame:Hide() (XML
-- <OnHide method="OnHide"/> -> GameDialogMixin:OnHide -> StaticPopup_OnHide ->
-- dialogInfo.OnHide). So the Sku menu's OnHide (StaticPopup1:Hide()) was silently
-- DECLINING group invites every time the menu closed for any reason -- while for a
-- sighted player Escape does nothing at all to that dialog (SetupLockOnDeclineButtonAndEscape
-- sets hideOnEscape = false), so their invite just sits there.
--
-- Fix: set inviteAccepted before we hide, so Blizzard's OnHide skips the decline. The
-- invite stays live server-side and is re-offered from the cache below. This is a plain
-- field on an insecure frame -- no taint. OnShow resets inviteAccepted to nil, so a
-- later genuine show is unaffected.
--
-- There is no "is an invite pending" query API on this client, so the cache is our own:
-- seeded from PARTY_INVITE_REQUEST, dropped on PARTY_INVITE_CANCEL, on any NON-neutralised
-- hide of the dialog (= the user really answered it, or it timed out), and by its own
-- deadline. If the deadline is ever wrong, AcceptGroup() simply fails harmlessly.
---------------------------------------------------------------------------------------------------------------------------------------
SkuCore.pendingGroupInvite = nil

local tInviteHooksSet = false

-- Called before Sku hides a StaticPopup, so the hide does not answer the prompt for the
-- user. Keyed by dialog so more destructive-OnHide dialogs can be added later (see the
-- audit in the commit: LEVEL_GRANT_PROPOSED and the EQUIP_BIND family are the others,
-- but EQUIP_BIND has no skip-flag and needs a different fix).
local tNeutralizers = {
	["PARTY_INVITE"] = function(aDialog)
		aDialog.inviteAccepted = 1          -- makes Blizzard's OnHide skip DeclineGroup()
		aDialog.skuPendingNeutralized = true -- tells our own hide hook this was not an answer
		-- Refine the deadline from the dialog's live countdown when we have it.
		if type(aDialog.timeleft) == "number" and aDialog.timeleft > 0 and SkuCore.pendingGroupInvite then
			SkuCore.pendingGroupInvite.expiresAt = GetTime() + aDialog.timeleft
		end
	end,
}

-- PUBLIC: call immediately before hiding a StaticPopup frame. No-op for every dialog
-- that hides harmlessly (death, summon, resurrect, ...).
function SkuCore:NeutralizePopupHide(aFrame)
	if not aFrame or not aFrame.which then return end
	local tFunc = tNeutralizers[tostring(aFrame.which)]
	if tFunc then pcall(tFunc, aFrame) end
end

-- Drop the cache when the dialog is hidden by anything OTHER than our neutralised hide
-- (accept, decline, timeout, PARTY_INVITE_CANCEL) -- in those cases the invite is really
-- resolved and must not linger in the menu.
function SkuCore.EnsureInviteHideHooks()
	if tInviteHooksSet then return end
	for i = 1, 4 do
		local p = _G["StaticPopup" .. i]
		if p and p.HookScript then
			p:HookScript("OnHide", function(self)
				if tostring(self.which or "") ~= "PARTY_INVITE" then return end
				if self.skuPendingNeutralized then
					self.skuPendingNeutralized = nil
				else
					SkuCore.pendingGroupInvite = nil
				end
			end)
		end
	end
	tInviteHooksSet = true
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Descriptors. `active` = still live per the game's own state; `popups` = dialog keys
-- that render the same thing (suppress while any is visible); `label` = the spoken
-- headline; `showDialog` = put Blizzard's own dialog back on screen. StaticPopup_Show /
-- the frame's own Show is what Blizzard itself calls, so it is the guaranteed-working
-- path -- and the re-shown window then offers ALL its real buttons (accept/decline,
-- release, soulstone, ...) through the normal frame-scrape menu.
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
			local tText = Sku.deEn("Beschwörung", "Summon", "Invocation")
			if tWho and tWho ~= "" then tText = tText .. " " .. Sku.deEn("von", "from", "de") .. " " .. tWho end
			if tWhere and tWhere ~= "" then tText = tText .. " " .. Sku.deEn("nach", "to", "vers") .. " " .. tWhere end
			return tText .. tTimeLeftSuffix(tLeft)
		end,
		showDialog = function() pcall(StaticPopup_Show, "CONFIRM_SUMMON") end,
	},

	--------------------------------------------------------------------------------
	-- Group invite. Backed by our own cache (no query API) and only survivable because
	-- SkuCore:NeutralizePopupHide suppressed the DeclineGroup() in Blizzard's OnHide.
	--------------------------------------------------------------------------------
	{
		id = "groupinvite",
		popups = { "PARTY_INVITE" },
		active = function()
			local t = SkuCore.pendingGroupInvite
			if type(t) ~= "table" or not t.name then return false end
			if GetTime() >= (t.expiresAt or 0) then
				SkuCore.pendingGroupInvite = nil
				return false
			end
			return true
		end,
		label = function()
			local t = SkuCore.pendingGroupInvite or {}
			local tText = Sku.deEn("Gruppeneinladung", "Group invite", "Invitation de groupe")
			if t.name and t.name ~= "" then
				tText = tText .. " " .. Sku.deEn("von", "from", "de") .. " " .. t.name
			end
			return tText .. tTimeLeftSuffix((t.expiresAt or 0) - GetTime())
		end,
		showDialog = function()
			local t = SkuCore.pendingGroupInvite
			if not t or not t.name then return end
			-- Same text Blizzard builds in TBC/UIParent.lua for PARTY_INVITE_REQUEST.
			local tText = string.format(_G.INVITATION or "%s", t.name)
			pcall(StaticPopup_Show, "PARTY_INVITE", tText)
		end,
		-- No cache clearing needed here: answering via the re-shown dialog's own
		-- buttons hides it NON-neutralised, and the OnHide hook above drops
		-- SkuCore.pendingGroupInvite then.
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
			local tText = Sku.deEn("Wiederbelebung", "Resurrection", "Résurrection")
			if tOfferer and tOfferer ~= "" then
				tText = tText .. " " .. Sku.deEn("von", "from", "de") .. " " .. tOfferer
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
			local tText = Sku.deEn("Tod", "Death", "Mort")
			if type(tLeft) == "number" and tLeft > 0 then
				tText = tText .. tTimeLeftSuffix(tLeft)
			end
			return tText
		end,
		-- Release / self-res options (soulstone, ankh, ...) all live as buttons ON the
		-- re-shown DEATH dialog (Blizzard's GameDialogDefsUtil wires them), so the
		-- frame-scrape menu offers them once the window is back -- no duplicated leaves.
		showDialog = function() pcall(StaticPopup_Show, "DEATH") end,
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
			local tText = L["Bereitschaft check"] or Sku.deEn("Bereitschaftscheck", "Ready check", "Vérification de préparation")
			if tWho and tWho ~= "" then tText = tText .. " " .. Sku.deEn("von", "from", "de") .. " " .. tWho end
			return tText .. tTimeLeftSuffix(tLeft)
		end,
		-- ReadyCheckFrame is in interactFramesList, so its Show drives the menu into
		-- the window exactly like the StaticPopup prompts.
		showDialog = function()
			local f = _G["ReadyCheckFrame"]
			if f and f.Show then pcall(function() f:Show() end) end
		end,
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
-- Menu. ONE flat node per live prompt, built directly under Local by
-- SkuOptions:MenuBuilderLocal. The entry is just the prompt's name (label());
-- RIGHT or ENTER puts Blizzard's own dialog back on screen. Its Show fires the
-- interactFramesList hook -> CheckFrames (deferred 0.1s in GENERIC_OnOpen) -> the
-- menu auto-descends into the reopened window, which offers all its real buttons
-- through the normal frame-scrape path -- that force-open is exactly what the user
-- asked for here.
--
-- Node mechanics: `dynamic = true` is ONLY there to make the key handler route
-- RIGHT into OnSelect at all (it gates RIGHT on children/dynamic); the OnSelect
-- override then bypasses the whole generic descend/action machinery -- it shows
-- the dialog and leaves the cursor in place, and the deferred CheckFrames
-- re-anchors into the window a moment later. No children are ever built.
---------------------------------------------------------------------------------------------------------------------------------------
function SkuCore.PendingPromptsMenuBuilder(aParentEntry)
	local tList = SkuCore:PendingPromptList()
	for _, tPrompt in ipairs(tList) do
		local ok, tRes = pcall(tPrompt.label)
		local tLabel = (ok and tRes) or tPrompt.id

		local tEntry = SkuMenu:BuildNode(aParentEntry, {
			kind = "action",
			label = tLabel,
			dynamic = true,
		})
		if tEntry then
			tEntry.OnSelect = function(self, aEnterFlag)
				if tPrompt.showDialog then pcall(tPrompt.showDialog) end
			end
		end
	end
end
