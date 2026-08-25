---@diagnostic disable: undefined-field, undefined-doc-name
---------------------------------------------------------------------------------------------------------------------------------------
local MODULE_NAME = "SkuNav"
local _G = _G
local L = Sku.L

SkuNav = SkuNav or LibStub("AceAddon-3.0"):NewAddon("SkuNav", "AceConsole-3.0", "AceEvent-3.0")

-- Route/link data import + export (W6-B #7). Moved here from SkuZOptions/Core
-- so route (de)serialization lives with the SkuNav data model it operates on.
-- The old dead tConvert migration helper and a stale commented-out Export copy
-- were dropped. Callers: /sku import|export (SkuZOptions) and the Nav>Export
-- menu (SkuNav/Options).

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:ImportWpAndLinkData()
	PlaySound(88)
	SkuOptions.Voice:OutputStringBTtts(L["Paste data to import now"], false, true, 0.2, nil, nil, nil, 2)

	SkuOptions:EditBoxPasteShow("", function(self)
		PlaySound(89)
		local tSerializedData = strtrim(table.concat(_G["SkuOptionsEditBoxPaste"].SkuOptionsTextBuffer))

		local tImportCounterLinks = 0
		local tImportCounterWps = 0
		local tIgnoredCounterWps = 0

		if tSerializedData ~= "" then
			local tSuccess, tVersion, tLinks, tWaypoints, tSequenceNumbers, tWaypointLevels, tMapMeta = SkuOptions:Deserialize(tSerializedData)

			--if tVersion ~= 22 then
				--SkuOptions.Voice:OutputStringBTtts(L["Import fehlgeschlagen. Falsche Version."], false, true, 0.2, nil, nil, nil, 2)										
				--return
			--end
			if tSuccess ~= true then
				SkuOptions.Voice:OutputStringBTtts(L["Import fehlgeschlagen. Daten fehlerhaft."], false, true, 0.2, nil, nil, nil, 2)										
				return
			end

			SkuOptions.Voice:OutputStringBTtts(L["Import erfolgreich"], true, true, 0.2, true, nil, nil, 2)			

			--do tWaypoints 
			local tFullCounterWps = 0
			SkuDB.SessionRouteData.Waypoints = {}
			for tIndex, tWpData in ipairs(tWaypoints) do
				if not SkuDB.SessionRouteData.Waypoints[tIndex] then
					table.insert(SkuDB.SessionRouteData.Waypoints, tWpData)
					tImportCounterWps = tImportCounterWps + 1
				else
					tIgnoredCounterWps = tIgnoredCounterWps + 1
				end
				tFullCounterWps = tFullCounterWps + 1
			end


			--do tLinks
			for i, v in pairs(tLinks) do
				tImportCounterLinks = tImportCounterLinks + 1
			end
			SkuDB.SessionRouteData.Links = tLinks

			--done
			print("Version:", tVersion)
			-- 6th blob field since SkuMapper 5.0: the hand-in header. Purely
			-- informational here; the real consumer is dev/mapper/skumap.py.
			if type(tMapMeta) == "table" then
				print("Map data based on map "..tostring(tMapMeta.basedOn or "?")..", mapper "..tostring(tMapMeta.mapper or "?")..", saved "..tostring(tMapMeta.savedAt or "?")..(tMapMeta.comment and (", comment: "..tMapMeta.comment) or ""))
			end
			print(L["Links importiert:"], tImportCounterLinks)
			print(L["Wegpunkte importiert:"], tImportCounterWps)
			print(L["Wegpunkte ignoriert:"], tIgnoredCounterWps)

			--layers + sequence numbers (SkuMapper export fields 4 & 5). Sku reads
			--both from SkuDB.routedata["global"] (runtime nav ordering + re-export),
			--so apply them there. Guarded so older 3-field blobs are unaffected and
			--a missing routedata table can't error the import.
			if (tSequenceNumbers or tWaypointLevels) and SkuDB.routedata and SkuDB.routedata["global"] then
				if tSequenceNumbers then
					SkuDB.routedata["global"].SequenceNumbers = tSequenceNumbers
					local c = 0
					for _ in pairs(tSequenceNumbers) do c = c + 1 end
					print("Sequence Numbers imported", c)
				end
				if tWaypointLevels then
					SkuDB.routedata["global"].WaypointLevels = tWaypointLevels
					local c = 0
					for _ in pairs(tWaypointLevels) do c = c + 1 end
					print("Waypoint layers imported", c)
				end
			end

			SkuNav:CreateWaypointCache()

			for x = 1, 4 do
				local tWaypointName = L["Quick waypoint"]..";"..x
				SkuNav:UpdateQuickWP(tWaypointName, true)
			end

			SkuOptions.db.global["SkuNav"].hasCustomMapData = true
		end
	end)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:ExportWpAndLinkData()
	SkuNav:SaveLinkDataToProfile()

	local tExportDataTable = {
		version = (GetAddOnMetadata and GetAddOnMetadata("SkuMapper", "Version"))
			or (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("SkuMapper", "Version"))
			or "unknown",
		links = {},
		waypoints = {},
		SequenceNumbers = {},
	}

	--build Links
	tExportDataTable.links = SkuDB.SessionRouteData.Links

	--SequenceNumbers
	tExportDataTable.SequenceNumbers = SkuDB.routedata["global"].SequenceNumbers or {}
	
	--build Waypoints
	for i, v in ipairs(SkuDB.SessionRouteData.Waypoints) do
		local tWpData = SkuDB.SessionRouteData.Waypoints[i]
		if tWpData then
			tWpData.comments = nil
			tWpData.createdAt = nil
			table.insert(tExportDataTable.waypoints, tWpData)
		end
	end
	
	tExportDataTable.WaypointLevels = SkuDB.routedata["global"].WaypointLevels or {}

	--complete export
	PlaySound(88)
	local tCount = 0
	for _, _ in pairs(tExportDataTable.links) do
		tCount = tCount + 1
	end
	print("Links exported:", tCount)
	tCount = 0
	for _, _ in pairs(tExportDataTable.waypoints) do
		tCount = tCount + 1
	end
	print("Waypoints exported", tCount)
	tCount = 0
	for _, _ in pairs(tExportDataTable.SequenceNumbers) do
		tCount = tCount + 1
	end
	print("Sequence Numbers exported", tCount)
	tCount = 0
	for _, _ in pairs(tExportDataTable.WaypointLevels) do
		tCount = tCount + 1
	end
	print("Waypoint layers exported", tCount)
	
	SkuOptions:EditBoxShow(SkuOptions:Serialize(tExportDataTable.version, tExportDataTable.links, tExportDataTable.waypoints, tExportDataTable.SequenceNumbers, tExportDataTable.WaypointLevels), function(self) PlaySound(89) end)
end
