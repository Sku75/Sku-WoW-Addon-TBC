---------------------------------------------------------------------------------------------------------------------------------------
-- SkuAuras sharing.lua  [41.05]
-- Stufe 1+2 des Auren-Teilens: benannte Sets (mit Doubletten-Pruefung) und
-- Teilen in der Gruppe ueber AceComm (versteckte Addon-Nachrichten, automatisches
-- Zerteilen). Vollstaendig isoliert und pcall-geschuetzt; aendert das bestehende
-- Auren-System NICHT. Auren bleiben name-basiert.
-- Stufe 2 zunaechst nur gleiche Clientsprache (Sprach-Kennzeichen). Der echte
-- Sprach-Uebersetzer (Stufe 4) ist spaeter ueber SkuDB.SpellDataTBC moeglich.
---------------------------------------------------------------------------------------------------------------------------------------
local MODULE_NAME = "SkuAuras"
local L = Sku.L
local SHARE_PREFIX = "SkuAuraSetV1"

local AceComm = LibStub and LibStub("AceComm-3.0", true)
if AceComm and SkuAuras and not SkuAuras.SendCommMessage then
	pcall(function() AceComm:Embed(SkuAuras) end)
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Hilfen
---------------------------------------------------------------------------------------------------------------------------------------
local function tSay(aText)
	if SkuOptions and SkuOptions.Voice then
		pcall(function() SkuOptions.Voice:OutputStringBTtts(aText, false, true, 0.2, true) end)
	end
end

local function tDeepCopy(aValue)
	if type(aValue) ~= "table" then return aValue end
	local t = {}
	for k, v in pairs(aValue) do t[k] = tDeepCopy(v) end
	return t
end

local function tEnsureSets()
	local p = SkuOptions and SkuOptions.db and SkuOptions.db.char and SkuSettings:Sub("SkuAuras", nil, "char")
	if not p then return nil end
	p.Sets = p.Sets or {}
	return p.Sets
end

local function tEnsurePending()
	local p = SkuOptions and SkuOptions.db and SkuOptions.db.char and SkuSettings:Sub("SkuAuras", nil, "char")
	if not p then return nil end
	p.PendingSets = p.PendingSets or {}
	return p.PendingSets
end

-- Name eindeutig machen: existiert er schon, aufsteigende Zahl anhaengen.
local function tUniqueName(aTbl, aBase)
	aBase = (aBase ~= nil and tostring(aBase) ~= "" and tostring(aBase)) or "Set"
	if not aTbl[aBase] then return aBase end
	local n = 2
	while aTbl[aBase.." "..n] do n = n + 1 end
	return aBase.." "..n
end

local function tGroupChannel()
	if IsInRaid and IsInRaid() then return "RAID" end
	if IsInGroup and IsInGroup() then return "PARTY" end
	return nil
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Stufe 1: Sets anlegen / loeschen
---------------------------------------------------------------------------------------------------------------------------------------
function SkuAuras:SetsCreateFromAllAuras(aName)
	local sets = tEnsureSets(); if not sets then return nil end
	local tName = tUniqueName(sets, aName)
	local tAuras = SkuSettings:Sub("SkuAuras", nil, "char").Auras or {}
	local tSnapshot, tCount = {}, 0
	for k, v in pairs(tAuras) do
		tSnapshot[k] = tDeepCopy(v)
		tCount = tCount + 1
	end
	sets[tName] = { loc = (Sku.Loc or "enUS"), auraData = tSnapshot, count = tCount }
	return tName, tCount
end

function SkuAuras:SetsDelete(aName)
	local sets = tEnsureSets(); if not sets then return end
	sets[aName] = nil
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Stufe 2: Teilen in der Gruppe (AceComm) + Empfangen
---------------------------------------------------------------------------------------------------------------------------------------
function SkuAuras:ShareSet(aName)
	local sets = tEnsureSets(); local set = sets and sets[aName]
	if not set then return end
	if not (AceComm and SkuAuras.SendCommMessage) then
		tSay(L["Teilen nicht moeglich, Kommunikationsbibliothek fehlt"])
		return
	end
	local chan = tGroupChannel()
	if not chan then
		tSay(L["Du bist in keiner Gruppe"])
		return
	end
	local ok, payload = pcall(function()
		return SkuOptions:Serialize("AURASET1", set.loc or (Sku.Loc or "enUS"), aName, set.auraData)
	end)
	if not ok or type(payload) ~= "string" then
		tSay(L["Set konnte nicht vorbereitet werden"])
		return
	end
	local me = (UnitName and UnitName("player")) or "?"
	pcall(SendChatMessage, me..L[" teilt Aurenset "]..aName, chan)
	pcall(function() SkuAuras:SendCommMessage(SHARE_PREFIX, payload, chan) end)
	pcall(SendChatMessage, L["Teilen abgeschlossen"], chan)
	tSay(string.format(L["Aurenset %s geteilt"], aName))
end

function SkuAuras:OnAuraSetComm(aPrefix, aMessage, aDist, aSender)
	if aPrefix ~= SHARE_PREFIX then return end
	if aSender and UnitName and aSender == UnitName("player") then return end
	local ok, tag, loc, setName, auraData = SkuOptions:Deserialize(aMessage)
	if not ok or tag ~= "AURASET1" or type(auraData) ~= "table" then return end
	local pending = tEnsurePending(); if not pending then return end
	local tKey = tUniqueName(pending, setName or "Set")
	pending[tKey] = { from = aSender or "?", loc = loc or "?", auraData = auraData }
	tSay(string.format(L["Aurenset %s von %s empfangen. Unter Auren, Sets, Empfangene Sets annehmen."], tostring(setName), tostring(aSender)))
end

-- Pending-Set in die eigenen Auren uebernehmen (mit Doubletten-Pruefung).
function SkuAuras:AcceptPendingSet(aKey)
	local pending = tEnsurePending(); local p = pending and pending[aKey]
	if not p then return end
	local tAuras = SkuSettings:Sub("SkuAuras", nil, "char").Auras
	if not tAuras then return end
	if p.loc and p.loc ~= (Sku.Loc or "enUS") then
		tSay(L["Achtung, Set ist fuer eine andere Sprache. Auren koennten nicht ausloesen."])
	end
	local tCount = 0
	for auraName, auraTable in pairs(p.auraData) do
		local tUnique = tUniqueName(tAuras, auraName)
		local tCopy = tDeepCopy(auraTable)
		tCopy.enabled = true
		tAuras[tUnique] = tCopy
		tCount = tCount + 1
	end
	pending[aKey] = nil
	pcall(function() SkuAuras:UpdateAttributesListWithCurrentAuras() end)
	tSay(string.format(L["Aurenset uebernommen, %s Auren"], tCount))
end

function SkuAuras:DiscardPendingSet(aKey)
	local pending = tEnsurePending(); if not pending then return end
	pending[aKey] = nil
	tSay(L["Empfangenes Set verworfen"])
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Menue "Sets (teilen)" unter Auren. Wird aus SkuAuras:MenuBuilder aufgerufen.
---------------------------------------------------------------------------------------------------------------------------------------
function SkuAuras:BuildSetsMenu(aParent)
	if not aParent then return end
	local tRoot = SkuOptions:InjectMenuItems(aParent, {L["Sets (teilen)"]}, SkuGenericMenuItem)
	tRoot.dynamic = true
	tRoot.BuildChildren = function(self)
		-- Set anlegen
		local tCreate = SkuOptions:InjectMenuItems(self, {L["Set aus aktuellen Auren anlegen"]}, SkuGenericMenuItem)
		tCreate.OnAction = function()
			pcall(function()
				SkuOptions.Voice:OutputStringBTtts(L["Namen eingeben und Enter, oder Escape zum Abbrechen"], false, true, 0.2)
				SkuOptions:EditBoxShow("", function()
					local tName = strtrim(SkuOptionsEditBoxEditBox:GetText() or "")
					if tName == "" then tSay(L["Abgebrochen"]); return end
					local tFinal, tCount = SkuAuras:SetsCreateFromAllAuras(tName)
					if tFinal then tSay(L["Set angelegt"]) end
				end)
			end)
		end

		-- vorhandene Sets
		local sets = tEnsureSets() or {}
		for tName, tSet in pairs(sets) do
			local tEntry = SkuOptions:InjectMenuItems(self, {"Set: "..tName.." ("..tostring(tSet.count or 0)..")"}, SkuGenericMenuItem)
			tEntry.dynamic = true
			tEntry.BuildChildren = function(self)
				local tShare = SkuOptions:InjectMenuItems(self, {L["An Gruppe teilen"]}, SkuGenericMenuItem)
				tShare.OnAction = function() pcall(function() SkuAuras:ShareSet(tName) end) end
				local tDel = SkuOptions:InjectMenuItems(self, {L["Set loeschen"]}, SkuGenericMenuItem)
				tDel.dynamic = true
				tDel.BuildChildren = function(self)
					local tYes = SkuOptions:InjectMenuItems(self, {L["Wirklich loeschen?"]}, SkuGenericMenuItem)
					tYes.OnAction = function()
						pcall(function() SkuAuras:SetsDelete(tName); tSay(L["Set geloescht"]) end)
						-- [41.06] nach dem Loeschen zurueck auf "Sets (teilen)" und neu aufbauen,
						-- sonst bleibt der geloeschte Eintrag stehen und Enter laeuft ins Leere (beep).
						C_Timer.After(0.3, function()
							pcall(function()
								local p = SkuOptions.currentMenuPosition
								while p and p.parent and p.name ~= L["Sets (teilen)"] do p = p.parent end
								if p and p.OnSelect then p:OnSelect(); SkuOptions:VocalizeCurrentMenuName() end
							end)
						end)
					end
				end
			end
		end

		-- empfangene Sets
		local tRecv = SkuOptions:InjectMenuItems(self, {L["Empfangene Sets"]}, SkuGenericMenuItem)
		tRecv.dynamic = true
		tRecv.BuildChildren = function(self)
			local pending = tEnsurePending() or {}
			local tEmpty = true
			for tKey, tP in pairs(pending) do
				tEmpty = false
				local tEntry = SkuOptions:InjectMenuItems(self, {tKey..L[" von  "]..tostring(tP.from or "?")}, SkuGenericMenuItem)
				tEntry.dynamic = true
				tEntry.BuildChildren = function(self)
					local tAcc = SkuOptions:InjectMenuItems(self, {L["Annehmen"]}, SkuGenericMenuItem)
					tAcc.OnAction = function() pcall(function() SkuAuras:AcceptPendingSet(tKey) end) end
					local tDis = SkuOptions:InjectMenuItems(self, {L["Verwerfen"]}, SkuGenericMenuItem)
					tDis.OnAction = function() pcall(function() SkuAuras:DiscardPendingSet(tKey) end) end
				end
			end
			if tEmpty == true then
				SkuOptions:InjectMenuItems(self, {L["keine empfangenen Sets"]}, SkuGenericMenuItem)
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Empfangs-Listener registrieren (dauerhaft bereit). pcall-geschuetzt.
---------------------------------------------------------------------------------------------------------------------------------------
if AceComm and SkuAuras and SkuAuras.RegisterComm then
	pcall(function() SkuAuras:RegisterComm(SHARE_PREFIX, "OnAuraSetComm") end)
end
