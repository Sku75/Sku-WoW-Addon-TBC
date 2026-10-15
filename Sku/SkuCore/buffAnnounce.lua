---------------------------------------------------------------------------------------------------------------------------------------
-- Announcement when the player gains a buff (campfire, food, progress buffs ...), on WoW Forever.
-- No addon may register COMBAT_LOG_EVENT_UNFILTERED there, so the combat log route (SkuChat, SPELL_AURA_APPLIED) never
-- arrives and there was no announcement when a buff was gained. UNIT_AURA is evaluated instead (addedAuras). The
-- feature is off until the player switches it on in the features menu: it speaks every buff gained out of combat,
-- mounts, forms and aspects included.
---------------------------------------------------------------------------------------------------------------------------------------
if not Sku.isForever then return end

local L = Sku.L

local BuffAnnounce = SkuCore:NewModule("BuffAnnounce")
SkuCore.BuffAnnounce = BuffAnnounce

SkuCore:RegisterToggleableModule("BuffAnnounce", function()
	return L["Buff announcements"]
end, nil, true)

-- The same buff is not announced more often than every 20 seconds (standing near a campfire switches it on repeatedly).
local MIN_REPEAT_SECONDS = 20
local gLastSpoken = {}

-- Buffs a shaman totem puts on the party come and go with every totem set and every step in or out of its range and
-- were too much, so they are left out. Aura spell ids of all vanilla ranks: SkuDB/assets/Era/spells.lua (the "<X>"
-- aura next to each "<X> Totem" rank); Grace of Air, Windwall, Tranquil Air and Mana Tide ranks 2-3 are missing
-- there and are taken from Wowhead Classic.
local tTotemAuras = {}
for _, tSpellId in ipairs({
	8076, 8162, 8163, 10441, 25362,         -- Strength of Earth
	8072, 8156, 8157, 10403, 10404, 10405,  -- Stoneskin
	8836, 10626, 25360,                     -- Grace of Air
	15108, 15109, 15110,                    -- Windwall
	25909,                                  -- Tranquil Air
	5672, 6371, 6372, 10460, 10461,         -- Healing Stream
	5677, 10491, 10493, 10494,              -- Mana Spring
	16191, 17355, 17360,                    -- Mana Tide
	8185, 10534, 10535,                     -- Fire Resistance
	8182, 10476, 10477,                     -- Frost Resistance
	10596, 10598, 10599,                    -- Nature Resistance
}) do
	tTotemAuras[tSpellId] = true
end

-- a plain frame: RegisterUnitEvent lets the game send only the player's UNIT_AURA, AceEvent would get every unit's
local tEventFrame = CreateFrame("Frame")

function BuffAnnounce:OnEnable()
	if Sku.IsEventValid("UNIT_AURA") then
		tEventFrame:RegisterUnitEvent("UNIT_AURA", "player")
	end
end

function BuffAnnounce:OnDisable()
	tEventFrame:UnregisterAllEvents()
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

local function tOnUnitAura(aFrame, aEvent, aUnit, aInfo)
	if type(aInfo) ~= "table" then return end
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
			if tIsBuff and not tTotemAuras[tAura.spellId] and type(tName) == "string" and tName ~= "" then
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
tEventFrame:SetScript("OnEvent", tOnUnitAura)
