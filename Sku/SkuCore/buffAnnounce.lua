---------------------------------------------------------------------------------------------------------------------------------------
-- Announcement when the player gains a buff (campfire, food, progress buffs ...), on WoW Forever.
-- No addon may register COMBAT_LOG_EVENT_UNFILTERED there, so the combat log route (SkuChat, SPELL_AURA_APPLIED) never
-- arrives and there was no announcement when a buff was gained. UNIT_AURA is evaluated instead (addedAuras). The
-- feature can be switched on and off in the features menu.
---------------------------------------------------------------------------------------------------------------------------------------
if not Sku.isForever then return end

local L = Sku.L

local BuffAnnounce = SkuCore:NewModule("BuffAnnounce", "AceEvent-3.0")
SkuCore.BuffAnnounce = BuffAnnounce

SkuCore:RegisterToggleableModule("BuffAnnounce", function()
	return L["Buff announcements"]
end)

-- The same buff is not announced more often than every 20 seconds (standing near a campfire switches it on repeatedly).
local MIN_REPEAT_SECONDS = 20
local gLastSpoken = {}

function BuffAnnounce:OnEnable()
	BuffAnnounce:RegisterEvent("UNIT_AURA", "UNIT_AURA")
end

function BuffAnnounce:OnDisable()
	BuffAnnounce:UnregisterAllEvents()
end

local function tDurationText(aDuration)
	if type(aDuration) ~= "number" or aDuration <= 0 then return "" end
	if aDuration >= 3600 then
		return ", " .. math.floor(aDuration / 3600 + 0.5) .. L[" Stunden"]
	elseif aDuration >= 60 then
		return ", " .. math.floor(aDuration / 60 + 0.5) .. L[" Minuten"]
	end
	return ", " .. math.floor(aDuration + 0.5) .. L[" Sekunden"]
end

function BuffAnnounce:UNIT_AURA(aEvent, aUnit, aInfo)
	if aUnit ~= "player" or type(aInfo) ~= "table" then return end
	-- In combat even isFullUpdate can be secret; testing it would throw.
	if Sku.IsSecret(aInfo.isFullUpdate) or aInfo.isFullUpdate then return end
	local tAdded = aInfo.addedAuras
	if type(tAdded) ~= "table" then return end

	local tNow = GetTime()
	for _, tAura in ipairs(tAdded) do
		-- In combat aura values can be secret: such entries are skipped.
		if not (Sku.IsSecret(tAura.name) or Sku.IsSecret(tAura.isHelpful) or Sku.IsSecret(tAura.spellId)) then
			-- Improved Rested bonus (1229451): the game marks it as harmful, but it is a buff.
			local tIsBuff = tAura.isHelpful == true or tAura.spellId == 1229451
			local tName = tAura.name
			-- Buffs that a shaman totem gives come and go with every totem set and every step in or out of its range and
			-- were too much; every aura with "Totem" in its name is left out (the same word in German, English, French).
			if tIsBuff and type(tName) == "string" and tName ~= "" and not string.find(tName, "Totem", 1, true) then
				local tKey = tAura.spellId or tName
				if not (gLastSpoken[tKey] and (tNow - gLastSpoken[tKey]) < MIN_REPEAT_SECONDS) then
					gLastSpoken[tKey] = tNow
					local tText = L["Buff gained"] .. ": " .. tName
					if not Sku.IsSecret(tAura.duration) then
						tText = tText .. tDurationText(tAura.duration)
					end
					dprint("buffAnnounce", tText)
					SkuOptions.Voice:OutputStringBTtts(tText, false, true, 0.2)
				end
			end
		end
	end
end
