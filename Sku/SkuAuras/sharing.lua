---------------------------------------------------------------------------------------------------------------------------------------
-- SkuAuras sharing.lua  [41.05]
-- Stufe 1+2 des Auren-Teilens: benannte Sets (mit Doubletten-Pruefung) und
-- Teilen in der Gruppe ueber AceComm (versteckte Addon-Nachrichten, automatisches
-- Zerteilen). Vollstaendig isoliert und pcall-geschuetzt; aendert das bestehende
-- Auren-System NICHT. Auren bleiben name-basiert.
-- [v43.0] Stufe 4 ist erledigt, aber nicht als Uebersetzer: seit der Umstellung
-- auf Gruppen-Identitaet (enUS-Zaubername als Schluessel, siehe SkuAuras/Core.lua)
-- sind Bedingungswerte sprachfrei. Damit braucht ein geteiltes Set kein
-- Sprach-Kennzeichen mehr - das V2-Format laesst es weg - und der Aura-NAME wird
-- beim Annehmen neu abgeleitet, also in der Sprache des Empfaengers.
-- V1 wird weiter EMPFANGEN (alte Clients, alte Sets): solche Werte tragen noch
-- lokalisierte Namen, laufen ueber die Kompatibilitaetsschiene der Live-Listen
-- und behalten deshalb genau das bisherige Verhalten samt Sprach-Warnung.
---------------------------------------------------------------------------------------------------------------------------------------
local MODULE_NAME = "SkuAuras"
local L = Sku.L
local SHARE_PREFIX = "SkuAuraSetV1"
local SHARE_PREFIX_V2 = "SkuAuraSetV2"

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

-- [W6-B Bug 3] widget-safe deep copy: delegate to SkuUtil.TableCopy so aura
-- snapshots get the same frame/userdata/slot-0 skip every other copy path uses.
-- The old plain recursive copy lacked that skip, so a shared/persisted aura set
-- could snapshot live frame references. Non-tables pass through unchanged, as
-- before (SkuUtil.TableCopy expects a table).
local function tDeepCopy(aValue)
	if type(aValue) ~= "table" then return aValue end
	return SkuUtil.TableCopy(aValue, true)
end

-- [Fix Nr5] Sets accountweit: Speicher von char auf global umgestellt, damit
-- angelegte/empfangene Sets auf allen Charakteren des Accounts verfuegbar sind.
-- (Die Auren selbst bleiben charbezogen; ein Set ist nur ein Schnappschuss.)
local function tEnsure(aKey)
	if not (SkuOptions and SkuOptions.db) then return nil end
	-- Scope "global" direkt ueber Sub aufloesen. KEIN Vorab-Guard auf
	-- SkuOptions.db.global: dessen Scope-Tabelle kann je nach AceDB erst beim
	-- Zugriff entstehen; ein falsy Vorab-Guard haette das Set-Menue auf einem
	-- zweiten Charakter still leer gelassen (Sub legt die Tabelle sonst an).
	local p = SkuSettings:Sub("SkuAuras", nil, "global")
	if not p then return nil end
	p[aKey] = p[aKey] or {}
	return p[aKey]
end

local function tEnsureSets() return tEnsure("Sets") end
local function tEnsurePending() return tEnsure("PendingSets") end

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

-- [Fix Nr21] Set umbenennen (mit Doubletten-Pruefung des neuen Namens).
function SkuAuras:SetsRename(aOld, aNew)
	local sets = tEnsureSets(); if not sets then return end
	local set = sets[aOld]; if not set then return end
	aNew = strtrim(tostring(aNew or ""))
	if aNew == "" or aNew == aOld then return end
	local tFinal = tUniqueName(sets, aNew)
	sets[tFinal] = set
	sets[aOld] = nil
	return tFinal
end

-- [Fix Nr21] Set aktivieren: ersetzt die aktuellen Auren durch die des Sets.
-- Bewusst destruktiv (aktivieren = umschalten), daher im Menue mit Rueckfrage.
function SkuAuras:SetsActivate(aName)
	local sets = tEnsureSets(); local set = sets and sets[aName]
	if not set then return end
	local tSub = SkuSettings:Sub("SkuAuras", nil, "char")
	if not tSub then return end
	local tNew, tCount = {}, 0
	for auraName, auraTable in pairs(set.auraData or {}) do
		local tCopy = tDeepCopy(auraTable)
		tCopy.enabled = true
		-- [v43.0] Ein Set, das vor der Umstellung angelegt wurde, traegt noch
		-- lokalisierte Werte; heben. Der NAME bleibt wie er ist - das Set gehoert
		-- dem Nutzer und ist bereits in seiner Sprache benannt.
		pcall(function() SkuAuras:ConvertAuraValuesToGroups(tCopy) end)
		tNew[auraName] = tCopy
		tCount = tCount + 1
	end
	tSub.Auras = tNew
	pcall(function() SkuAuras:UpdateAttributesListWithCurrentAuras() end)
	tSay(string.format(L["Set aktiviert, %s Auren"], tCount))
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
	-- [v43.0] V2: kein Sprach-Kennzeichen mehr. Bewusst NUR V2 gesendet - ein
	-- zusaetzliches V1-Paket wuerde bei alten Clients Auren mit Gruppen-Werten
	-- ablegen, die sie nicht aufloesen koennen, also stillen Muell statt nichts.
	local ok, payload = pcall(function()
		return SkuOptions:Serialize("AURASET2", aName, set.auraData)
	end)
	if not ok or type(payload) ~= "string" then
		tSay(L["Set konnte nicht vorbereitet werden"])
		return
	end
	local me = (UnitName and UnitName("player")) or "?"
	pcall(SendChatMessage, me..L[" teilt Aurenset "]..aName, chan)
	pcall(function() SkuAuras:SendCommMessage(SHARE_PREFIX_V2, payload, chan) end)
	pcall(SendChatMessage, L["Teilen abgeschlossen"], chan)
	tSay(string.format(L["Aurenset %s geteilt"], aName))
end

function SkuAuras:OnAuraSetComm(aPrefix, aMessage, aDist, aSender)
	if aPrefix ~= SHARE_PREFIX and aPrefix ~= SHARE_PREFIX_V2 then return end
	if aSender and UnitName and aSender == UnitName("player") then return end
	-- [v43.0] Zwei Formate. V2 fuehrt kein loc-Feld mehr - das ist der Punkt der
	-- Umstellung, nicht ein vergessenes Feld -, deshalb bleibt loc hier nil und
	-- die Sprach-Warnung beim Annehmen entfaellt fuer V2.
	local tOk, tTag, tA, tB, tC = SkuOptions:Deserialize(aMessage)
	if not tOk then return end
	local loc, setName, auraData
	if tTag == "AURASET2" then
		setName, auraData = tA, tB
	elseif tTag == "AURASET1" then
		loc, setName, auraData = tA, tB, tC
	else
		return
	end
	if type(auraData) ~= "table" then return end
	local pending = tEnsurePending(); if not pending then return end
	local tKey = tUniqueName(pending, setName or "Set")
	pending[tKey] = { from = aSender or "?", loc = loc, auraData = auraData }
	tSay(string.format(L["Aurenset %s von %s empfangen. Unter Auren, Sets, Empfangene Sets annehmen."], tostring(setName), tostring(aSender)))
end

-- Pending-Set in die eigenen Auren uebernehmen (mit Doubletten-Pruefung).
function SkuAuras:AcceptPendingSet(aKey)
	local pending = tEnsurePending(); local p = pending and pending[aKey]
	if not p then return end
	local tAuras = SkuSettings:Sub("SkuAuras", nil, "char").Auras
	if not tAuras then return end
	-- [v43.0] Nur noch fuer V1-Pakete: die tragen lokalisierte Werte, also gilt
	-- die alte Einschraenkung weiter. V2 hat kein loc-Feld und braucht keine
	-- Warnung - seine Werte sind Gruppen-Schluessel und damit sprachfrei.
	if p.loc and p.loc ~= (Sku.Loc or "enUS") then
		tSay(L["Achtung, Set ist fuer eine andere Sprache. Auren koennten nicht ausloesen."])
	end
	local tCount = 0
	for auraName, auraTable in pairs(p.auraData) do
		local tCopy = tDeepCopy(auraTable)
		tCopy.enabled = true
		-- Werte gleicher Sprache auf Gruppen-Identitaet heben (bei einem V1-Set
		-- vom gleichen Client-Typ), dann den Namen in DIESER Sprache neu
		-- ableiten. Beides ist idempotent bzw. ein No-Op, wenn nichts zu tun ist.
		pcall(function() SkuAuras:ConvertAuraValuesToGroups(tCopy) end)
		local tName = auraName
		pcall(function() tName = SkuAuras:RelocalizedAuraName(auraName, tCopy) end)
		local tUnique = tUniqueName(tAuras, tName)
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

				-- [Fix Nr21] Set umbenennen
				local tRename = SkuOptions:InjectMenuItems(self, {L["Set umbenennen"]}, SkuGenericMenuItem)
				tRename.OnAction = function()
					pcall(function()
						SkuOptions.Voice:OutputStringBTtts(L["Neuen Namen eingeben und Enter, oder Escape zum Abbrechen"], false, true, 0.2)
						SkuOptions:EditBoxShow(tName, function()
							local tNew = strtrim(SkuOptionsEditBoxEditBox:GetText() or "")
							if tNew == "" then tSay(L["Abgebrochen"]); return end
							local tFinal = SkuAuras:SetsRename(tName, tNew)
							if tFinal then tSay(L["Set umbenannt"]) end
							C_Timer.After(0.3, function()
								pcall(function()
									local p = SkuOptions.currentMenuPosition
									while p and p.parent and p.name ~= L["Sets (teilen)"] do p = p.parent end
									if p and p.OnSelect then p:OnSelect(); SkuOptions:VocalizeCurrentMenuName() end
								end)
							end)
						end)
					end)
				end

				-- [Fix Nr21] Set aktivieren (ersetzt aktuelle Auren) mit Rueckfrage
				local tAct = SkuOptions:InjectMenuItems(self, {L["Set aktivieren"]}, SkuGenericMenuItem)
				tAct.dynamic = true
				tAct.BuildChildren = function(self)
					local tYes = SkuOptions:InjectMenuItems(self, {L["Wirklich aktivieren? Ersetzt aktuelle Auren"]}, SkuGenericMenuItem)
					tYes.OnAction = function() pcall(function() SkuAuras:SetsActivate(tName) end) end
				end

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
	pcall(function() SkuAuras:RegisterComm(SHARE_PREFIX_V2, "OnAuraSetComm") end)
end
