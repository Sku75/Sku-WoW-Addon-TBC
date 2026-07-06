-- W5: datengetriebene Beacon-Sound-Erkennung. Beacon-Pakete sind reine
-- Daten-Addons: sie deklarieren ihre Soundsets über TOC-Metadaten, Sku
-- registriert sie hier zentral. Format (Sets mit ";" getrennt, Felder mit "|",
-- Pfade relativ zum assets-Ordner des Pakets):
--   ## X-SkuBeaconSets: <Name>|<Unterordner>|<GradSchritt>|<MaxDistanz>|<Dateiname> ; ...
--   ## X-SkuBeaconClickClackSets: <Anzeigename>|<internerName>|<Unterordner>|<Klickdatei>|<Klackdatei> ; ...
-- Alt-Pakete mit eigenem Core.lua funktionieren unverändert weiter:
-- SkuBeacon:RegisterSoundSet ist first-wins, eine doppelte Registrierung mit
-- identischen Daten ist folgenlos. Sku hat keine harte TOC-Abhängigkeit mehr zu
-- SkuBeaconSoundsets; fehlen nach dem Einloggen sämtliche Beacon-Sounds, wird
-- das einmalig angesagt statt den Addon-Start zu verhindern.

local function RegisterBeaconPacks()
	local SkuBeacon = LibStub("SkuBeacon-1.0", true)
	if not SkuBeacon then return end
	local tGetNum = (C_AddOns and C_AddOns.GetNumAddOns) or GetNumAddOns
	local tGetInfo = (C_AddOns and C_AddOns.GetAddOnInfo) or GetAddOnInfo
	local tGetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata

	for i = 1, tGetNum() do
		local tName, _, _, tLoadable = tGetInfo(i)
		if tName and tLoadable then
			local tSets = tGetMeta(tName, "X-SkuBeaconSets")
			if tSets then
				for tEntry in string.gmatch(tSets, "[^;]+") do
					local tBase, tSub, tStep, tMaxDist, tFile = string.match(tEntry, "^%s*(.-)%s*|%s*(.-)%s*|%s*(.-)%s*|%s*(.-)%s*|%s*(.-)%s*$")
					if tBase and tBase ~= "" and tSub and tonumber(tStep) and tonumber(tMaxDist) and tFile and tFile ~= "" then
						SkuBeacon:RegisterSoundSet(tBase, "Interface\\AddOns\\"..tName.."\\assets\\"..tSub, tonumber(tStep), tonumber(tMaxDist), tFile)
						dprint("companionPacks: beacon set", tBase, "from", tName)
					else
						dprint("companionPacks: bad X-SkuBeaconSets entry in", tName, tEntry)
					end
				end
			end
			local tCcSets = tGetMeta(tName, "X-SkuBeaconClickClackSets")
			if tCcSets then
				for tEntry in string.gmatch(tCcSets, "[^;]+") do
					local tFriendly, tInternal, tSub, tClick, tClack = string.match(tEntry, "^%s*(.-)%s*|%s*(.-)%s*|%s*(.-)%s*|%s*(.-)%s*|%s*(.-)%s*$")
					if tFriendly and tFriendly ~= "" and tInternal and tInternal ~= "" and tSub and tClick and tClack then
						SkuBeacon:RegisterClickClackSoundSet(tFriendly, tInternal, "Interface\\AddOns\\"..tName.."\\assets\\"..tSub, tClick, tClack)
						dprint("companionPacks: clickclack set", tInternal, "from", tName)
					else
						dprint("companionPacks: bad X-SkuBeaconClickClackSets entry in", tName, tEntry)
					end
				end
			end
		end
	end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function(self)
	self:UnregisterAllEvents()
	RegisterBeaconPacks()
	-- Alt-Pakete registrieren ihre Sets ebenfalls bei PLAYER_ENTERING_WORLD;
	-- deshalb erst verzögert prüfen, wenn beide Wege durch sind.
	C_Timer.After(3, function()
		local tBeacon = LibStub("SkuBeacon-1.0", true)
		local tSets = tBeacon and tBeacon:GetSoundSets()
		if not tSets or #tSets == 0 then
			SkuOptions.Voice:OutputStringBTtts("Keine Beacon-Sounds gefunden. Bitte das Addon SkuBeaconSoundsets installieren.", false, true, 0.3)
		end
	end)
end)
