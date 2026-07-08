---------------------------------------------------------------------------------------------------------------------------------------
local MODULE_NAME = "SkuNav"
local _G = _G
local L = Sku.L

SkuNav = SkuNav or LibStub("AceAddon-3.0"):NewAddon("SkuNav", "AceConsole-3.0", "AceEvent-3.0")

SkuDrawFlag = false
SkuNav.tCoverSize = 20
SkuNav.tWpEditMode = 2
SkuNav.TrackSize = 10
SkuNav.Tracks = {
	startid = nil,
	endids = {
		[1] = nil,
	},
}
SkuNav.TrackedLevel = -1
SkuNav.TrackedLevels = {
	[-11] = -10,
	[-10] = -9,
	[-9] = -8,
	[-8] = -7,
	[-7] = -6,
	[-6] = -5,
	[-5] = -4,
	[-4] = -3,
	[-3] = -2,
	[-2] = -1,
	[-1] = "none",
	[0] = 0,
	[1] = 1,
	[2] = 2,
	[3] = 3,
	[4] = 4,
	[5] = 5,
	[6] = 6,
	[7] = 7,
	[8] = 8,
	[9] = 9,
	[10] = 10,
}

local slower = string.lower
local sfind = string.find
local ssub = string.sub
local tinsert = table.insert

SkuNav.ActionsHistory = {}

---------------------------------------------------------------------------------------------------------------------------------------
function SkuTableCopy(t, deep, seen)
	seen = seen or {}
	if t == nil then return nil end
	if seen[t] then return seen[t] end
	local nt = {}
	for k, v in pairs(t) do
		if type(v) ~= "userdata" and k ~= "frame" and k ~= 0  then
			if deep and type(v) == 'table' then
				nt[k] = SkuTableCopy(v, deep, seen)
			else
				nt[k] = v
			end
		end
	end
	seen[t] = nt
	return nt
end

------------------------------------------------------------------------------------------------------------------------
WaypointCache = {}
WaypointCacheLookupAll = {}
WaypointCacheLookupIdForCacheIndex = {}
WaypointCacheLookupCacheNameForId = {}
WaypointCacheLookupPerContintent = {}

function SkuNav:CreateWaypointCache(aAddLocalizedNames)
	SkuDrawFlag = false

	WaypointCache = {}
	WaypointCacheLookupAll = {}
	WaypointCacheLookupIdForCacheIndex = {}
	WaypointCacheLookupCacheNameForId = {}
	WaypointCacheLookupPerContintent = {}
	for i, v in pairs(SkuDB.ContinentIds) do
		WaypointCacheLookupPerContintent[i] = {}
	end

	C_Timer.After(2, function()
		--add creatures
		for i, v in pairs(SkuDB.NpcData.Names[Sku.Loc]) do		
			if SkuDB.NpcData.Data[i] then
				local tRoles
				local tName
				local tSubname
				if SkuDB.NpcData.Names[Sku.Loc][i] then
					tName = SkuDB.NpcData.Names[Sku.Loc][i][1]
					tSubname = SkuDB.NpcData.Names[Sku.Loc][i][2]
					tRoles = SkuNav:GetNpcRoles(v[1], i)
				else
					tName = SkuDB.NpcData.Data[i][1]
					tSubname = SkuDB.NpcData.Data[i][14]
					tRoles = SkuNav:GetNpcRoles(SkuDB.NpcData.Data[i][1], i)
				end			
				local tSpawns = SkuDB.NpcData.Data[i][7]
				if tSpawns then
					if not sfind(slower(tName), "trigger") then
						for is, vs in pairs(tSpawns) do
							local isUiMap = SkuNav:GetUiMapIdFromAreaId(is)
							--we don't care for stuff that isn't in the open world
							if isUiMap then
								local tData = SkuDB.InternalAreaTable[is]
								if tData then
									local tNumberOfSpawns = #vs
									local tRolesString = ""
									if not tSubname then
										if #tRoles > 0 then
											for i, v in pairs(tRoles) do
												tRolesString = tRolesString..";"..v
											end
											tRolesString = tRolesString..""
										end
									else
										tRolesString = tRolesString..";"..tSubname
									end
									for sp = 1, tNumberOfSpawns do
										local _, worldPosition = C_Map.GetWorldPosFromMapPos(isUiMap, CreateVector2D(vs[sp][1] / 100, vs[sp][2] / 100))
										if worldPosition then
											local tWorldX, tWorldY = worldPosition:GetXY()
											local tNewIndex = #WaypointCache + 1
											local tFinalName = tName..tRolesString..";"..tData.AreaName_lang[Sku.Loc]..";"..sp..";"..vs[sp][1]..";"..vs[sp][2]
											local tWpId = SkuNav:BuildWpIdFromData(2, i, sp, is)
											if not WaypointCacheLookupPerContintent[tData.ContinentID] then
												WaypointCacheLookupPerContintent[tData.ContinentID] = {}
											end
											WaypointCacheLookupPerContintent[tData.ContinentID][tNewIndex] = tFinalName
											WaypointCacheLookupAll[tFinalName] = tNewIndex
											WaypointCacheLookupIdForCacheIndex[tWpId] =  tNewIndex
											WaypointCacheLookupCacheNameForId[tFinalName] = tWpId
											WaypointCache[tNewIndex] = {
												name = tFinalName,
												role = tRolesString,
												typeId = 2,
												dbIndex = i,
												spawn = sp,
												contintentId = tData.ContinentID,
												areaId = is,
												uiMapId = isUiMap,
												worldX = tWorldX,
												worldY = tWorldY,
												createdAt = GetTime(),
												createdBy = "SkuNav",
												size = 1,
												spawnNr = sp,
												links = {
													byId = nil,
													byName = nil,
												},
											}
										end
									end
								end
							end
						end
					end
				end
			end
		end

		C_Timer.After(2, function()			
			--add objects
			
			for i, v in pairs(SkuDB.objectLookup[Sku.Loc]) do
	
				--we don't want stuff like ores, herbs, etc. as default
				if not SkuDB.objectResourceNames[Sku.Loc][v] or SkuOptions.db.profile[MODULE_NAME].showGatherWaypoints == true then
					if SkuDB.objectDataTBC[i] then
	
						--and we never want chairs, barrels, campfires, etc.
						local isOk = true
						for idToIgnore, _ in pairs(SkuDB.objectsToIgnore) do
							if SkuDB.objectDataTBC[idToIgnore] then
								if SkuDB.objectDataTBC[i][1] == SkuDB.objectDataTBC[idToIgnore][1] then
									isOk = false
								end
							end
						end

						--we never want stuff with specific strings in the name
						if isOk ~= false then
							for _, tStringToLookFor in pairs(SkuDB.objectsToIgnoreByName) do
								if sfind(slower(SkuDB.objectDataTBC[i][1]), slower(tStringToLookFor)) then
									isOk = false
								end
							end
						end
						
						local tSpawns = SkuDB.objectDataTBC[i][4]
						if isOk == true and tSpawns then
							for is, vs in pairs(tSpawns) do
								local isUiMap = SkuNav:GetUiMapIdFromAreaId(is)
								--we don't care for stuff that isn't in the open world
								if isUiMap then
									local tData = SkuDB.InternalAreaTable[is]
									if tData then
										local tNumberOfSpawns = #vs
										for sp = 1, tNumberOfSpawns do
											local _, worldPosition = C_Map.GetWorldPosFromMapPos(isUiMap, CreateVector2D(vs[sp][1] / 100, vs[sp][2] / 100))
											if worldPosition then
												local tWorldX, tWorldY = worldPosition:GetXY()
												local tNewIndex = #WaypointCache + 1
												local tRessourceType = ""
												if SkuDB.objectResourceNames[Sku.Loc][v] == 1 then
													tRessourceType = ";"..L["herbalism"]
												elseif SkuDB.objectResourceNames[Sku.Loc][v] == 2 then
													tRessourceType = ";"..L["mining"]
												end

												local tFinalName = L["OBJECT"]..";"..i..";"..v..tRessourceType..";"..tData.AreaName_lang[Sku.Loc]..";"..sp..";"..vs[sp][1]..";"..vs[sp][2]
												local tWpId = SkuNav:BuildWpIdFromData(3, i, sp, is)
												if not WaypointCacheLookupPerContintent[tData.ContinentID] then
													WaypointCacheLookupPerContintent[tData.ContinentID] = {}
												end
												WaypointCacheLookupPerContintent[tData.ContinentID][tNewIndex] = tFinalName
												WaypointCacheLookupAll[tFinalName] = tNewIndex
												WaypointCacheLookupIdForCacheIndex[tWpId] =  tNewIndex
												WaypointCacheLookupCacheNameForId[tFinalName] = tWpId										
												WaypointCache[tNewIndex] = {
													name = tFinalName,
													role = "",
													typeId = 3,
													dbIndex = i,
													spawn = sp,
													contintentId = tData.ContinentID,
													areaId = is,
													uiMapId = isUiMap,
													worldX = tWorldX,
													worldY = tWorldY,
													createdAt = GetTime(),
													createdBy = "SkuNav",
													size = 1,
													spawnNr = sp,
													links = {
														byId = nil,
														byName = nil,
													},
												}
											end
										end
									end
								end
							end
						end
					end
				end
			end

			C_Timer.After(2, function()
				--add custom
				if SkuOptions.db.global[MODULE_NAME].Waypoints then
					for tIndex, tData in ipairs(SkuOptions.db.global[MODULE_NAME].Waypoints) do
						--check if that wp was deleted
						if tData[1] ~= false then
							local tName = tData.names[Sku.Loc]

							if WaypointCacheLookupAll[tName] then
								WaypointCache[WaypointCacheLookupAll[tName]].worldX = tData.worldX
								WaypointCache[WaypointCacheLookupAll[tName]].worldY = tData.worldY
							else
								local tWaypointData = tData
								if tWaypointData then
									if tWaypointData.contintentId then
										local isUiMap = SkuNav:GetUiMapIdFromAreaId(tWaypointData.areaId)
										local tWpIndex = (#WaypointCache + 1)
										local tOldLinks = {
											byId = nil,
											byName = nil,
										}
										if WaypointCacheLookupAll[tName] then
											if WaypointCacheLookupPerContintent[WaypointCache[WaypointCacheLookupAll[tName]].contintentId] then
												WaypointCacheLookupPerContintent[WaypointCache[WaypointCacheLookupAll[tName]].contintentId][WaypointCacheLookupAll[tName]] = nil
											end
											tOldLinks = WaypointCache[WaypointCacheLookupAll[tName]].links
											tWpIndex = WaypointCacheLookupAll[tName]
										end

										WaypointCache[tWpIndex] = {
											name = tName,
											role = "",
											typeId = 1,
											dbIndex = tIndex,
											spawn = 1,
											contintentId = tWaypointData.contintentId,
											areaId = tWaypointData.areaId,
											uiMapId = isUiMap,
											worldX = tWaypointData.worldX,
											worldY = tWaypointData.worldY,
											createdAt = GetTime(),--tWaypointData.createdAt,
											createdBy = tWaypointData.createdBy,
											size = tWaypointData.size or 1,
											comments = tWaypointData.lComments or {["deDE"] = {},["enUS"] = {},},
											spawnNr = nil,
											links = tOldLinks,
										}

										WaypointCacheLookupAll[tName] = tWpIndex
										local tWpId = SkuNav:BuildWpIdFromData(1, tIndex, 1, tWaypointData.areaId)
										WaypointCacheLookupIdForCacheIndex[tWpId] =  tWpIndex
										WaypointCacheLookupCacheNameForId[tName] = tWpId										

										if not WaypointCacheLookupPerContintent[tWaypointData.contintentId] then
											WaypointCacheLookupPerContintent[tWaypointData.contintentId] = {}
										end
										WaypointCacheLookupPerContintent[tWaypointData.contintentId][tWpIndex] = tName
									end
								end
							end
						else
							--print("error: tried caching deleted custom wp", tIndex, tData)
						end
					end
				end

				SkuNav:LoadLinkDataFromProfile()
				C_Timer.NewTimer(5, function() SkuDrawFlag = true end)

				print("SkuMapper cache ready")
			end)
		end)
	end)
end

------------------------------------------------------------------------------------------------------------------------
function SkuNav:LoadLinkDataFromProfile()
	--print("LoadLinkDataFromProfile")
	if SkuOptions.db.global[MODULE_NAME].Links then
		SkuNav:CheckAndUpdateProfileLinkData()
		for tSourceWpID, tSourceWpLinks in pairs(SkuOptions.db.global[MODULE_NAME].Links) do
			if not WaypointCacheLookupIdForCacheIndex[tSourceWpID] then
				print("Error: This should not happen. NO WaypointCacheLookupIdForCacheIndex[tSourceWpID]", tSourceWpID, tSourceWpLinks)
			end
			local tSourceWpName = WaypointCache[WaypointCacheLookupIdForCacheIndex[tSourceWpID]].name
			WaypointCacheLookupCacheNameForId[tSourceWpName] = tSourceWpID

			if WaypointCacheLookupAll[tSourceWpName] then
				WaypointCache[WaypointCacheLookupAll[tSourceWpName]].links.byName = {}
				WaypointCache[WaypointCacheLookupAll[tSourceWpName]].links.byId = {}
				for tTargetWpID, tTargetWpDistance in pairs(tSourceWpLinks) do
					local tTargetWpName = WaypointCache[WaypointCacheLookupIdForCacheIndex[tTargetWpID]].name
					WaypointCacheLookupCacheNameForId[tTargetWpName] = tTargetWpID
					if WaypointCacheLookupAll[tTargetWpName] then
						WaypointCache[WaypointCacheLookupAll[tSourceWpName]].links.byName[tTargetWpName] = tTargetWpDistance
						WaypointCache[WaypointCacheLookupAll[tSourceWpName]].links.byId[WaypointCacheLookupAll[tTargetWpName]] = tTargetWpDistance
					end
				end
			end
		end
	end
	SkuNav:SaveLinkDataToProfile()
end

------------------------------------------------------------------------------------------------------------------------
function SkuNav:CheckAndUpdateProfileLinkData()
	local tDeletedCounter = 0

	if SkuOptions.db.global[MODULE_NAME].Links then
		for tSourceWpID, tSourceWpLinks in pairs(SkuOptions.db.global[MODULE_NAME].Links) do
			if not WaypointCacheLookupIdForCacheIndex[tSourceWpID] then
				local typeId, dbIndex, spawn, areaId = SkuNav:GetWpDataFromId(tSourceWpID)
				--print("UPDATED source deleted, not in db", tSourceWpID, typeId, dbIndex, spawn, areaId)
				SkuOptions.db.global[MODULE_NAME].Links[tSourceWpID] = nil
				tDeletedCounter = tDeletedCounter + 1
			else
				local tSourceWpName = WaypointCache[WaypointCacheLookupIdForCacheIndex[tSourceWpID]].name
				if SkuNav:GetWaypointData2(tSourceWpName) then
					for tTargetWpID, tTargetWpDistance in pairs(tSourceWpLinks) do
						if not WaypointCacheLookupIdForCacheIndex[tTargetWpID] then
							--print("UPDATED Target deleted, not in db", tSourceWpID, tSourceWpLinks, tSourceWpName, "-", tTargetWpID, tTargetWpDistance, WaypointCacheLookupIdForCacheIndex[tTargetWpID])
							SkuOptions.db.global[MODULE_NAME].Links[tSourceWpID][tTargetWpID] = nil
							tDeletedCounter = tDeletedCounter + 1
						else
							local tTargetWpName = WaypointCache[WaypointCacheLookupIdForCacheIndex[tTargetWpID]].name					
							if tSourceWpName == tTargetWpName then
								SkuOptions.db.global[MODULE_NAME].Links[tSourceWpID][tTargetWpID] = nil
								--print("+++UPDATED deleted", tTargetWpName, "from", tSourceWpName, "because source was linked with self")
							else
								if SkuNav:GetWaypointData2(tTargetWpName) then
									SkuOptions.db.global[MODULE_NAME].Links[tTargetWpID] = SkuOptions.db.global[MODULE_NAME].Links[tTargetWpID] or {}
									if not SkuOptions.db.global[MODULE_NAME].Links[tTargetWpID][tSourceWpID] then
										--print("+++UPDATED added", tSourceWpName, "to", tTargetWpName)
										SkuOptions.db.global[MODULE_NAME].Links[tTargetWpID][tSourceWpID] = tTargetWpDistance
									end
								else
									--print("+++UPDATED deleted", tTargetWpName, "from", tSourceWpName, "because target does not exist")
									SkuOptions.db.global[MODULE_NAME].Links[tSourceWpID][tTargetWpID] = nil
									--print("  +++UPDATED deleted", tTargetWpName, "because target does not exist")
									SkuOptions.db.global[MODULE_NAME].Links[tTargetWpID] = nil
								end
							end
						end
					end
				else
					for tTargetWpID, tTargetWpDistance in pairs(tSourceWpLinks) do
						local tTargetWpName = WaypointCache[WaypointCacheLookupIdForCacheIndex[tTargetWpID]].name										
						SkuOptions.db.global[MODULE_NAME].Links[tTargetWpID] = SkuOptions.db.global[MODULE_NAME].Links[tTargetWpID] or {}
						if not SkuOptions.db.global[MODULE_NAME].Links[tTargetWpID][tSourceWpID] then
							--print("+++UPDATED deleted", tSourceWpName, "from", tTargetWpName, "because source does not exist")
							SkuOptions.db.global[MODULE_NAME].Links[tTargetWpID][tSourceWpID] = nil
						end
					end
					--print("  +++UPDATED delted", tSourceWpName, "because source does not exist")
					SkuOptions.db.global[MODULE_NAME].Links[tSourceWpID] = nil
				end
			end
		end
	end

	if tDeletedCounter and tDeletedCounter > 0 then
		--print("Error: deletedCounter > 0; this should not happen", tDeletedCounter)
	end
end

------------------------------------------------------------------------------------------------------------------------
function SkuNav:SaveLinkDataToProfile(aWpName)
	--print("SaveLinkDataToProfile", aWpName)
	if aWpName then
		SkuOptions.db.global[MODULE_NAME].Links[WaypointCacheLookupCacheNameForId[aWpName]] = {}
		for twname, twdist in pairs(WaypointCache[WaypointCacheLookupAll[aWpName]].links.byName) do
			SkuOptions.db.global[MODULE_NAME].Links[WaypointCacheLookupCacheNameForId[aWpName]][WaypointCacheLookupCacheNameForId[twname]] = twdist
		end		
	else
		SkuOptions.db.profile[MODULE_NAME].Links = nil
		SkuOptions.db.global[MODULE_NAME].Links = {}
		for tSourceWpIndex, tSourceWpData in pairs(WaypointCache) do
			if tSourceWpData.links then
				if tSourceWpData.links.byId then
					SkuOptions.db.global[MODULE_NAME].Links[WaypointCacheLookupCacheNameForId[tSourceWpData.name]] = {}
					for twname, twdist in pairs(tSourceWpData.links.byName) do
						SkuOptions.db.global[MODULE_NAME].Links[WaypointCacheLookupCacheNameForId[tSourceWpData.name]][WaypointCacheLookupCacheNameForId[twname]] = twdist
					end
				end
			end
		end
	end
end

------------------------------------------------------------------------------------------------------------------------
function SkuNav:GetWaypointData2(aName, aIndex)
	if aName then
		return WaypointCache[WaypointCacheLookupAll[aName]]
	elseif aIndex then
		return WaypointCache[aIndex]
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:ListWaypoints2(aSort, aFilter, aAreaId, aContinentId, aExcludeRoute, aRetAsTable, aIgnoreAuto)
	aSort = aSort or false
	aFilter = aFilter or "custom;creature;object;standard"
	local tFilterTypes = {}
	if string.find(aFilter, "custom") then tFilterTypes[1] = 1 end
	if string.find(aFilter, "creature") then tFilterTypes[2] = 2 end
	if string.find(aFilter, "object") then tFilterTypes[3] = 3 end
	if string.find(aFilter, "standard") then tFilterTypes[4] = 4 end

	local UiMapId
	if aAreaId then
		UiMapId = SkuNav:GetUiMapIdFromAreaId(aAreaId)
	end

	aContinentId = aContinentId or select(3, SkuNav:GetAreaData(SkuNav:GetCurrentAreaId()))
	if not aContinentId or not WaypointCacheLookupPerContintent[aContinentId] then
		return
	end

	local tWpList = {}
	for tIndex, tName in pairs(WaypointCacheLookupPerContintent[aContinentId]) do
		--if tFilterTypes[WaypointCache[tIndex].typeId] then
			if not UiMapId or UiMapId == WaypointCache[tIndex].uiMapId then
				--tWpList[tIndex] = tName
				--if not string.find(tName, "%[DND%]") and not string.find(tName, "%(DND%)") then
					tWpList[#tWpList + 1] = tName
				--end
			end
		--end
	end

	if aSort == true then
		local tSortedList = {}
		for k, v in SkuSpairs(tWpList, function(t,a,b) return t[b] > t[a] end) do --nach wert
			tSortedList[#tSortedList+1] = v
		end
		if aRetAsTable then
			return tSortedList
		else
			return pairs(tSortedList)
		end
	end

	if aRetAsTable then
		return tWpList
	else
		return pairs(tWpList)
	end
end

--------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:DeleteWpLink(aWpAName, aWpBName)
	local tWpAIndex = WaypointCacheLookupAll[aWpAName]
	local tWpBIndex = WaypointCacheLookupAll[aWpBName]
	local tWpAData = SkuNav:GetWaypointData2(nil, tWpAIndex)
	local tWpBData = SkuNav:GetWaypointData2(nil, tWpBIndex)

	if not tWpAData or not tWpBData then
		return false
	end

	if not tWpAData.links.byId or not tWpBData.links.byId then
		return
	end
	
	if not tWpAData.links.byId[tWpBIndex] or not tWpBData.links.byId[tWpAIndex] then
		return false
	end

	local tWpAName = aWpAName
	local tWpBName = aWpBName

	if tSkuNavMMDrawCache[WaypointCacheLookupAll[tWpAName]].poolObjects and tSkuNavMMDrawCache[WaypointCacheLookupAll[tWpAName]].poolObjects.lines then
		for i1, v1 in pairs(tSkuNavMMDrawCache[WaypointCacheLookupAll[tWpAName]].poolObjects.lines) do
			ClearLineMM(v1)
		end
		tSkuNavMMDrawCache[WaypointCacheLookupAll[tWpAName]].poolObjects.lines = {}
	end
	if tSkuNavMMDrawCache[WaypointCacheLookupAll[tWpBName]].poolObjects and tSkuNavMMDrawCache[WaypointCacheLookupAll[tWpBName]].poolObjects.lines then
		for i1, v1 in pairs(tSkuNavMMDrawCache[WaypointCacheLookupAll[tWpBName]].poolObjects.lines) do
			ClearLineMM(v1)
		end
		tSkuNavMMDrawCache[WaypointCacheLookupAll[tWpBName]].poolObjects.lines = {}
	end

	WaypointCache[tWpAIndex].links.byId[tWpBIndex] = nil
	WaypointCache[tWpBIndex].links.byId[tWpAIndex] = nil
	WaypointCache[tWpAIndex].links.byName[aWpBName] = nil
	WaypointCache[tWpBIndex].links.byName[aWpAName] = nil
	
	local tWpAId = WaypointCacheLookupCacheNameForId[aWpAName]
	local tWpBId = WaypointCacheLookupCacheNameForId[aWpBName]

	SkuOptions.db.global[MODULE_NAME].Links[tWpAId][tWpBId] = nil
	SkuOptions.db.global[MODULE_NAME].Links[tWpBId][tWpAId] = nil

	SkuNav:SaveLinkDataToProfile(aWpAName)
	SkuNav:SaveLinkDataToProfile(aWpBName)

	SkuOptions.db.global["SkuNav"].hasCustomMapData = true
end

--------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:CreateWpLink(aWpAName, aWpBName)
	if aWpAName ~= aWpBName then
		local tWpAIndex = WaypointCacheLookupAll[aWpAName]
		local tWpBIndex = WaypointCacheLookupAll[aWpBName]

		local tWpAData = SkuNav:GetWaypointData2(nil, tWpAIndex)
		local tWpBData = SkuNav:GetWaypointData2(nil, tWpBIndex)

		local tDistance = SkuNav:Distance(tWpAData.worldX, tWpAData.worldY, tWpBData.worldX, tWpBData.worldY)

		WaypointCache[tWpAIndex].links.byId = WaypointCache[tWpAIndex].links.byId or {}
		WaypointCache[tWpAIndex].links.byName = WaypointCache[tWpAIndex].links.byName or {}
		WaypointCache[tWpAIndex].links.byId[tWpBIndex] = tDistance
		WaypointCache[tWpAIndex].links.byName[aWpBName] = tDistance

		WaypointCache[tWpBIndex].links.byId = WaypointCache[tWpBIndex].links.byId or {}
		WaypointCache[tWpBIndex].links.byName = WaypointCache[tWpBIndex].links.byName or {}
		WaypointCache[tWpBIndex].links.byId[tWpAIndex] = tDistance
		WaypointCache[tWpBIndex].links.byName[aWpAName] = tDistance

		local tWpAId = WaypointCacheLookupCacheNameForId[aWpAName]
		local tWpBId = WaypointCacheLookupCacheNameForId[aWpBName]

		SkuOptions.db.global[MODULE_NAME].Links[tWpAId] = SkuOptions.db.global[MODULE_NAME].Links[tWpAId] or {}
		SkuOptions.db.global[MODULE_NAME].Links[tWpAId][tWpBId] = tDistance
		SkuOptions.db.global[MODULE_NAME].Links[tWpBId] = SkuOptions.db.global[MODULE_NAME].Links[tWpBId] or {}
		SkuOptions.db.global[MODULE_NAME].Links[tWpBId][tWpAId] = tDistance

		SkuOptions.db.global["SkuNav"].hasCustomMapData = true

		SkuNav:SaveLinkDataToProfile(aWpAName)
		SkuNav:SaveLinkDataToProfile(aWpBName)
	end
end

--------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:UpdateWpLinks(aWpAName)
	local tWpAIndex = WaypointCacheLookupAll[aWpAName]
	local tWpAData = SkuNav:GetWaypointData2(nil, tWpAIndex)

	if not WaypointCache[tWpAIndex].links.byId then
		return
	end

	for tWpBIndex, _ in pairs(tWpAData.links.byId) do
		local tDistance = SkuNav:Distance(tWpAData.worldX, tWpAData.worldY, WaypointCache[tWpBIndex].worldX, WaypointCache[tWpBIndex].worldY)
		WaypointCache[tWpAIndex].links.byId[tWpBIndex] = tDistance
		WaypointCache[tWpAIndex].links.byName[WaypointCache[tWpBIndex].name] = tDistance
		WaypointCache[tWpBIndex].links.byId[tWpAIndex] = tDistance
		WaypointCache[tWpBIndex].links.byName[aWpAName] = tDistance

		local tWpAId = WaypointCacheLookupCacheNameForId[aWpAName]
		local tWpBId = WaypointCacheLookupCacheNameForId[aWpBName]

		SkuOptions.db.global[MODULE_NAME].Links[tWpAId] = SkuOptions.db.global[MODULE_NAME].Links[tWpAId] or {}
		SkuOptions.db.global[MODULE_NAME].Links[tWpAId][WaypointCacheLookupCacheNameForId[WaypointCache[tWpBIndex].name]] = tDistance
		SkuOptions.db.global[MODULE_NAME].Links[WaypointCacheLookupCacheNameForId[WaypointCache[tWpBIndex].name]] = SkuOptions.db.global[MODULE_NAME].Links[WaypointCacheLookupCacheNameForId[WaypointCache[tWpBIndex].name]] or {}
		SkuOptions.db.global[MODULE_NAME].Links[WaypointCacheLookupCacheNameForId[WaypointCache[tWpBIndex].name]][tWpAId] = tDistance
	end

	SkuOptions.db.global["SkuNav"].hasCustomMapData = true
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:GetBestMapForUnit(aUnitId)
	local tPlayerUIMap = C_Map.GetBestMapForUnit(aUnitId)

	if tPlayerUIMap == 1415 or tPlayerUIMap == 1414 then
		local tMMZoneText = GetMinimapZoneText()

		--this is because of strange areas where C_Map.GetBestMapForUnit is returning continent IDs
		if tMMZoneText == L["Timbermaw Hold"] then
			tPlayerUIMap = 1448
		elseif tMMZoneText == L["Der Südstrom"] then
			tPlayerUIMap = 1413
		elseif tMMZoneText == L["Die Höhlen des Wehklagens"] or tMMZoneText == L["Höhle der Nebel"]  then
			tPlayerUIMap = 1413
		elseif tMMZoneText == L["Schmiedevaters Grabmal"] or tMMZoneText == L["Schwarzfelsspitze"] then
			tPlayerUIMap = 1428
		else
			for i, v in pairs(SkuDB.InternalAreaTable) do
				if v.AreaName_lang[Sku.Loc] == tMMZoneText then
					tPlayerUIMap = SkuNav:GetUiMapIdFromAreaId(v.ParentAreaID)
				end
			end
		end
	end

	if tPlayerUIMap == nil then
		local tMMZoneText = GetMinimapZoneText()
		if tMMZoneText == L["Deeprun Tram"] then
			tPlayerUIMap = 2257
		end
	end

	if tPlayerUIMap == 126 then
		tPlayerUIMap = 125
	end

	return tPlayerUIMap
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:OnInitialize()
	SkuNav:RegisterEvent("PLAYER_LOGIN")
	SkuNav:RegisterEvent("PLAYER_LOGOUT")
	SkuNav:RegisterEvent("PLAYER_ENTERING_WORLD")
	SkuNav:RegisterEvent("PLAYER_LEAVING_WORLD")
	SkuNav:RegisterEvent("NEW_WMO_CHUNK")
	SkuNav:RegisterEvent("ZONE_CHANGED")
	SkuNav:RegisterEvent("ZONE_CHANGED_INDOORS")
	SkuNav:RegisterEvent("ZONE_CHANGED_NEW_AREA")

	SkuNav:History_OnInitialize()
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:GetDirectionTo(aP1x, aP1y, aP2x, aP2y)
	if aP1x == nil or aP1y == nil or aP2x == nil or aP2y == nil or GetPlayerFacing() == nil then
		return 0
	end
	if aP2x == 0 and aP2y == 0 then
		return 0
	end
		
	local ep2x = (aP2x - aP1x)
	local ep2y = (aP2y - aP1y)
	
	local Wa = math.acos(ep2x / math.sqrt(ep2x^2 + ep2y^2)) * (180 / math.pi)
	
	if ep2y > 0 then
		Wa = Wa * -1
	end
	local facing = (GetPlayerFacing() * (180 / math.pi))
	local facingfinal = facing
	if facing > 180 then
		facingfinal = (360 - facing) * -1
	end
	
	local afinal = Wa + facingfinal
	if afinal > 180 then
		afinal = afinal - 360
	elseif afinal < -180 then
		afinal = 360 + afinal
	end
	
	local uhrfloat = (afinal + 15) / 30
	local uhr = math.floor((afinal + 15) / 30)
	if uhr < 0 then
		uhr = 12 + uhr
	end
	if uhr == 0 then
		uhr = 12
	end

	return uhr, uhrfloat, afinal
end

---------------------------------------------------------------------------------------------------------------------------------------
local floor = math.floor
local sqrt = math.sqrt
function SkuNav:Distance(sx, sy, dx, dy)
	if sx and sy and dx and dy then
    	return floor(sqrt((sx - dx) ^ 2 + (sy - dy) ^ 2)), sqrt((sx - dx) ^ 2 + (sy - dy) ^ 2)
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:GetContinentNameFromContinentId(aContinentId)
	if not SkuDB.ContinentIds[aContinentId] then
		return
	end
	return SkuDB.ContinentIds[aContinentId].Name_lang[Sku.Loc]
end

---------------------------------------------------------------------------------------------------------------------------------------
local GetUiMapIdFromAreaIdCache = {}
function SkuNav:GetUiMapIdFromAreaId(aAreaId)
	if not SkuDB.InternalAreaTable[aAreaId] then
		return nil
	end
	if GetUiMapIdFromAreaIdCache[aAreaId] then
		return GetUiMapIdFromAreaIdCache[aAreaId]
	end

	local tCurrentId = aAreaId
	local tPrevId = aAreaId
	while tCurrentId > 0 do
		tPrevId = tCurrentId
		tCurrentId = SkuDB.InternalAreaTable[tCurrentId].ParentAreaID
	end

	for i, v in pairs(SkuDB.ExternalMapID) do
		if v.AreaId == tPrevId then
			GetUiMapIdFromAreaIdCache[aAreaId] = i
			return i
		end
	end
end
---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:GetAreaIdFromUiMapId(aUiMapId)
	--dprint("GetAreaIdFromUiMapId", aUiMapId)
	local rAreaId
	local tMinimapZoneText = GetMinimapZoneText()
 	if tMinimapZoneText == L["Deeprun Tram"] then --fix for strange DeeprunTram zone
		rAreaId = 2257
	else
		if SkuDB.ExternalMapID[aUiMapId] then
			rAreaId = SkuDB.ExternalMapID[aUiMapId].AreaId
		end
	end
	return rAreaId
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:GetAreaIdFromAreaName(aAreaName, aIgnoreCase)
	--dprint("GetAreaIdFromAreaName", aAreaName)
	local rAreaId
	local tPlayerUIMap = SkuNav:GetBestMapForUnit("player")
	for i, v in pairs(SkuDB.InternalAreaTable) do
		if not aIgnoreCase then
			if (v.AreaName_lang[Sku.Loc] == aAreaName) and (SkuNav:GetUiMapIdFromAreaId(i) == tPlayerUIMap) then
				rAreaId = i
			end
		else
			if (string.lower(v.AreaName_lang[Sku.Loc]) == string.lower(aAreaName)) and (SkuNav:GetUiMapIdFromAreaId(i) == tPlayerUIMap) then
				rAreaId = i
			end
		end
	end
	return rAreaId
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:GetAreaData(aAreaId)
	--dprint("GetAreaData", aAreaId)
	if not SkuDB.InternalAreaTable[aAreaId] then 
		return
	end
	return SkuDB.InternalAreaTable[aAreaId].ZoneName, SkuDB.InternalAreaTable[aAreaId].AreaName_lang[Sku.Loc], SkuDB.InternalAreaTable[aAreaId].ContinentID, SkuDB.InternalAreaTable[aAreaId].ParentAreaID, SkuDB.InternalAreaTable[aAreaId].Faction, SkuDB.InternalAreaTable[aAreaId].Flags
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:GetSubAreaIds(aAreaId)
	--dprint("GetSubAreaIds", aAreaId)
	local tAreas = {}
	for i, v in pairs(SkuDB.InternalAreaTable) do
		if v.ParentAreaID == tonumber(aAreaId) then
			tAreas[i] = i
			for i1, v1 in pairs(SkuDB.InternalAreaTable) do
				if v1.ParentAreaID == tonumber(i) then
					tAreas[i1] = i1
				end
			end
		end
	end
	return tAreas
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:GetCurrentAreaId(aUnitId, pr)
	local tMinimapZoneText = GetMinimapZoneText()
	local tAreaId

	for i, v in pairs(SkuDB.InternalAreaTable) do
		if (v.AreaName_lang[Sku.Loc] == tMinimapZoneText) and v.ParentAreaID == C_Map.GetBestMapForUnit("player") and (SkuNav:GetUiMapIdFromAreaId(i) == tPlayerUIMap) then
			tAreaId = i
			break
		end
	end

	if not tAreaId then
		local tExtMapId = SkuDB.ExternalMapID[SkuNav:GetBestMapForUnit("player")]
		if aUnitId then
			tExtMapId = SkuDB.ExternalMapID[SkuNav:GetBestMapForUnit(aUnitId)]
		end
		if tExtMapId then
			for i, v in pairs(SkuDB.InternalAreaTable) do
				if v.AreaName_lang[Sku.Loc] == tExtMapId.Name_lang[Sku.Loc] then
					tAreaId = i
					break
				end
			end
		end
	end

	if not tAreaId then
		local tMinimapZoneText = GetMinimapZoneText()
		if tMinimapZoneText == "Versteck der Defias" then --fix for Die Todesminen zone
			tAreaId = 1518
		end
	end

	return tAreaId
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:GetDistanceToWp(aWpName)
	if not SkuNav:GetWaypointData2(aWpName) then
		return nil
	end

	local tEndx, tEndy = SkuNav:GetWaypointData2(aWpName).worldX, SkuNav:GetWaypointData2(aWpName).worldY

	local x, y = UnitPosition("player")
	if x and y then
		local ep2x = (tEndx - x)
		local ep2y = (tEndy - y)
		if ep2x and ep2y then
			return SkuNav:Distance(0, 0, ep2x, ep2y)
		else
			return nil
		end
	else
		return nil
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:GetDirectionToWp(aWpName)
	if not SkuNav:GetWaypointData2(aWpName) then
		return nil
	end

	local x, y = UnitPosition("player")

	return SkuNav:GetDirectionTo(x, y, SkuNav:GetWaypointData2(aWpName).worldX, SkuNav:GetWaypointData2(aWpName).worldY)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:StartRouteRecording(aWPAName, aDeleteFlag)
	if SkuOptions.db.profile[MODULE_NAME].routeRecording == true or SkuOptions.db.profile[MODULE_NAME].routeRecordingLastWp then
		return
	end

	SkuOptions.db.profile[MODULE_NAME].routeRecording = true
	if aDeleteFlag then
		SkuOptions.db.profile[MODULE_NAME].routeRecordingDelete = true
	end
	SkuOptions.db.profile[MODULE_NAME].routeRecordingLastWp = aWPAName

	SkuOptions.tmpNpcWayPointNameBuilder_Npc = ""
	SkuOptions.tmpNpcWayPointNameBuilder_Zone = ""
	SkuOptions.tmpNpcWayPointNameBuilder_Coords = ""

	if not aDeleteFlag then
		print("Recording started: ", aWPAName)
		SkuNav:PlaySoundFile("Interface\\AddOns\\SkuMapper\\audio\\sound-on3_1.mp3")
	else
		print("Deleting started: ", aWPAName)
		SkuNav:PlaySoundFile("Interface\\AddOns\\SkuMapper\\audio\\sound-waterdrop2.mp3")
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:EndRouteRecording(aWpName, aDeleteFlag)
	--print("EndRouteRecording", aWpName, aDeleteFlag) 
	if SkuOptions.db.profile[MODULE_NAME].routeRecording == false or 
		not SkuOptions.db.profile[MODULE_NAME].routeRecordingLastWp or 
		SkuOptions.db.profile[MODULE_NAME].routeRecordingLastWp == "" 
	then
		return
	end

	if not aDeleteFlag and SkuOptions.db.profile[MODULE_NAME].routeRecordingDelete ~= true then
		if SkuNav:GetWaypointData2(aWpName) then
			--update links
			local tWpAName = aWpName
			local tWpBName = SkuOptions.db.profile[MODULE_NAME].routeRecordingLastWp
			if tWpAName ~= tWpBName then
				SkuNav:CreateWpLink(tWpAName, tWpBName)
			end
		end
	end

	if aDeleteFlag and SkuOptions.db.profile[MODULE_NAME].routeRecordingDelete == true then
		SkuNav:DeleteWpLink(aWpName, SkuOptions.db.profile[MODULE_NAME].routeRecordingLastWp)
		SkuOptions.db.profile[MODULE_NAME].routeRecordingDelete = nil
	end

	SkuOptions.db.profile[MODULE_NAME].routeRecording = false
	SkuOptions.db.profile[MODULE_NAME].routeRecordingLastWp = nil

	if not aDeleteFlag then
		print("Recording stopped:", aWPAName)
		SkuNav:PlaySoundFile("Interface\\AddOns\\SkuMapper\\audio\\sound-off2.mp3")
	else
		print("Deleting stopped:", aWPAName)
		SkuNav:PlaySoundFile("Interface\\AddOns\\SkuMapper\\audio\\sound-waterdrop1.mp3")
	end

end

---------------------------------------------------------------------------------------------------------------------------------------
local function CheckPolygons(x, y)
	local rPolyIndex = {}
	local fPlayerPosX, fPlayerPosY = UnitPosition("player")
	local _, _, tPlayerContinentID  = SkuNav:GetAreaData(SkuNav:GetCurrentAreaId())

	for i = 1, #SkuDB.Polygons.data do
		if SkuDB.Polygons.data[i].continentId == tPlayerContinentID then
			local tInPolygon = 0
			for q = 1, #SkuDB.Polygons.data[i].nodes do
				local ax, ay, bx, by = SkuDB.Polygons.data[i].nodes[q].x, SkuDB.Polygons.data[i].nodes[q].y
				if q < #SkuDB.Polygons.data[i].nodes then 
					bx, by = SkuDB.Polygons.data[i].nodes[q+1].x, SkuDB.Polygons.data[i].nodes[q+1].y
				else
					bx, by = SkuDB.Polygons.data[i].nodes[1].x, SkuDB.Polygons.data[i].nodes[1].y
				end
				if SkuNav:IntersectionPoint(fPlayerPosX, fPlayerPosY, 50000, 50000, ax, ay, bx, by) then
					tInPolygon = tInPolygon + 1
				end
			end
			if tInPolygon == 1 or (floor(tInPolygon / 2) * 2 ~= tInPolygon) then
				rPolyIndex[#rPolyIndex + 1] = i
			end
		end
	end

	return rPolyIndex
end

---------------------------------------------------------------------------------------------------------------------------------------
local tOldPolyZones = {
   [1] = {[1] = 0,},
   [2] = {[1] = 0,},
   [3] = {[1] = 0, [2] = 0, [3] = 0, [4] = 0,},
   [4] = {[1] = 0,},
}
local tdiold, tdisold = 0,0
local tCurrentDragWpName

function SkuNav:ProcessPolyZones()
	local tPolyZones = CheckPolygons(UnitPosition("player"))
	local tNewPolyZones = {
		[1] = {[1] = 0,},
		[2] = {[1] = 0,},
		[3] = {[1] = 0, [2] = 0, [3] = 0, [4] = 0,},
		[4] = {[1] = 0,},
	}
	for p = 1, #tPolyZones do
		tNewPolyZones[SkuDB.Polygons.data[tPolyZones[p]].type][SkuDB.Polygons.data[tPolyZones[p]].subtype] = tNewPolyZones[SkuDB.Polygons.data[tPolyZones[p]].type][SkuDB.Polygons.data[tPolyZones[p]].subtype] + 1
	end
	--setmetatable(tNewPolyZones, SkuPrintMT)					
	--dprint(tNewPolyZones)
	--world
	if tOldPolyZones[1][1] ~= tNewPolyZones[1][1] then
		if tNewPolyZones[1][1] == 0 then
			--dprint("world left")
		elseif tOldPolyZones[1][1] == 0 then
			--dprint("world entered")
		end
		tOldPolyZones[1][1] = tNewPolyZones[1][1] 
	end
	--fly
	if tOldPolyZones[2][1] ~= tNewPolyZones[2][1] then
		if tNewPolyZones[2][1] == 0 then
			--dprint("fly left")
		elseif tOldPolyZones[2][1] == 0 then
			--dprint("fly entered")
		end
		tOldPolyZones[2][1] = tNewPolyZones[2][1] 
	end
	--faction
	if tOldPolyZones[3][1] ~= tNewPolyZones[3][1] then
		if tNewPolyZones[3][1] == 0 then
			--dprint("alliance left")
		elseif tOldPolyZones[3][1] == 0 then
			--dprint("alliance entered")
		end
		tOldPolyZones[3][1] = tNewPolyZones[3][1] 
	end
	if tOldPolyZones[3][2] ~= tNewPolyZones[3][2] then
		if tNewPolyZones[3][2] == 0 then
			--dprint("horde left")
		elseif tOldPolyZones[3][2] == 0 then
			--dprint("horde entered")
		end
		tOldPolyZones[3][2] = tNewPolyZones[3][2] 
	end
	if tOldPolyZones[3][3] ~= tNewPolyZones[3][3] then
		if tNewPolyZones[3][3] == 0 then
			--dprint("horde left")
		elseif tOldPolyZones[3][3] == 0 then
			--dprint("horde entered")
		end
		tOldPolyZones[3][3] = tNewPolyZones[3][3] 
	end
	if tOldPolyZones[3][4] ~= tNewPolyZones[3][4] then
		if tNewPolyZones[3][4] == 0 then
			--dprint("horde left")
		elseif tOldPolyZones[3][4] == 0 then
			--dprint("horde entered")
		end
		tOldPolyZones[3][4] = tNewPolyZones[3][4] 
	end

	--other
	if tOldPolyZones[4][1] ~= tNewPolyZones[4][1] then
		if tNewPolyZones[4][1] == 0 then
			--dprint("other left")
		elseif tOldPolyZones[4][1] == 0 then
			--dprint("other entered")
		end
		tOldPolyZones[4][1] = tNewPolyZones[4][1] 
	end
end

--------------------------------------------------------------------------------------------------------------------------------------
local mouseMiddleDown = false
local mouseMiddleUp = false
local mouseLeftDown = false
local mouseLeftUp = false
local mouseRightDown = false
local mouseRightUp = false
local mouse4Down = false
local mouse4Up = false
local mouse5Down = false
local mouse5Up = false
function SkuNav:ProcessRecordingMousClickStuff()
	--rt recording per mouse click stuff
	if IsControlKeyDown() == true then
		_G["SkuNavWpDragClickTrap"]:Show()

		if mouse5Down == false then
			if IsMouseButtonDown("Button5") == true then
				mouse5Up = false
				mouse5Down = true
				SkuNav:OnMouse5Down()
			end
		elseif mouse5Down == true then
			SkuNav:OnMouse5Hold()
			if IsMouseButtonDown("Button5") ~= true then
				mouse5Down = false
				mouse5Up = true
				SkuNav:OnMouse5Up()
			end
		end

		if mouse4Down == false then
			if IsMouseButtonDown("Button4") == true then
				mouse4Up = false
				mouse4Down = true
				SkuNav:OnMouse4Down()
			end
		elseif mouse4Down == true then
			SkuNav:OnMouse4Hold()
			if IsMouseButtonDown("Button4") ~= true then
				mouse4Down = false
				mouse4Up = true
				SkuNav:OnMouse4Up()
			end
		end

		if mouseMiddleDown == false then
			if IsMouseButtonDown("MiddleButton") == true then
				mouseMiddleUp = false
				mouseMiddleDown = true
				SkuNav:OnMouseMiddleDown()
			end
		elseif mouseMiddleDown == true then
			SkuNav:OnMouseMiddleHold()
			if IsMouseButtonDown("MiddleButton") ~= true then
				mouseMiddleDown = false
				mouseMiddleUp = true
				SkuNav:OnMouseMiddleUp()
			end
		end

		if mouseLeftDown == false then
			if IsMouseButtonDown("LeftButton") == true then
				mouseLeftUp = false
				mouseLeftDown = true
				SkuNav:OnMouseLeftDown()
			end
		elseif mouseLeftDown == true then
			SkuNav:OnMouseLeftHold()
			if IsMouseButtonDown("LeftButton") ~= true then
				mouseLeftDown = false
				mouseLeftUp = true
				SkuNav:OnMouseLeftUp()
			end
		end

		if mouseRightDown == false then
			if IsMouseButtonDown("RightButton") == true then
				mouseRightUp = false
				mouseRightDown = true
				SkuNav:OnMouseRightDown()
			end
		elseif mouseRightDown == true then
			SkuNav:OnMouseRightHold()
			if IsMouseButtonDown("RightButton") ~= true then
				mouseRightDown = false
				mouseRightUp = true
				SkuNav:OnMouseRightUp()
			end

		end
	else
		mouseMiddleDown = false
		mouseMiddleUp = false
		mouseLeftDown = false
		mouseLeftUp = false
		mouseRightDown = false
		mouseRightUp = false
		_G["SkuNavWpDragClickTrap"]:Hide()
	end
end

--------------------------------------------------------------------------------------------------------------------------------------
local metapathFollowingTargetNameAnnounced = false
SkuNavMmDrawTimer = 0.2
function SkuNav:CreateSkuNavControl()
	local ttimeDegreesChangeInitial = nil
	local ttime = GetServerTime()
	local ttimeDraw = GetServerTime()
	SkuOptions.db.profile["SkuNav"].showAdvancedControls = SkuOptions.db.profile["SkuNav"].showAdvancedControls or 1

	local f = CreateFrame("Frame", "SkuMouseArea", UIParent)
	f:SetPoint("CENTER")
	f:SetSize(10, 10)
	f:SetFrameStrata("TOOLTIP")
	f:SetAlpha(0.5)
	f.tex = f:CreateTexture()
	f.tex:SetAllPoints(f)
	f.tex:SetTexture("Interface\\AddOns\\SkuMapper\\SkuNav\\assets\\circle.tga")
	f.tex:SetDrawLayer("OVERLAY")
	if SkuOptions.db.profile["SkuNav"].showAdvancedControls > 0 then
		f:Show()
	else
		f:Hide()
	end

	local f = _G["SkuNavControl"] or CreateFrame("Frame", "SkuNavControl", UIParent)
	f:SetScript("OnUpdate", function(self, time) 
		ttime = ttime + time
		ttimeDraw = ttimeDraw + time

		if SkuNav.tWpEditMode == 1 and _G["SkuNavMMMainFrameScrollFrame1"]:IsMouseOver() == true then
			if _G["SkuMouseArea"]:IsShown() ~= true then
				_G["SkuMouseArea"]:Show()
			end
			_G["SkuMouseArea"]:SetSize(SkuNav.tCoverSize * 2, SkuNav.tCoverSize * 2)
			local tCursorX, tCursorY = GetCursorPosition()
			_G["SkuMouseArea"]:SetPoint("CENTER", tCursorX - (GetScreenWidth() / 2), tCursorY - (GetScreenHeight() / 2))
		else
			if _G["SkuMouseArea"]:IsShown() ~= false then
				_G["SkuMouseArea"]:Hide()
			end
		end

		--tmp drawing rts on UIParent for debugging
		if ttimeDraw > (SkuNavMmDrawTimer or 0.2) then
			SkuNav:DrawAll(_G["Minimap"])
			ttimeDraw = 0
		end
		
		SkuWaypointWidgetCurrent = nil
		for i, v in SkuWaypointWidgetRepo:EnumerateActive() do
			if i:IsVisible() == true then
				if i:IsMouseOver() then
					if i.aText ~= SkuWaypointWidgetCurrent then
						SkuWaypointWidgetCurrent = i.aText

						GameTooltip.SkuWaypointWidgetCurrent = i.aText
						GameTooltip:ClearLines()
						GameTooltip:SetOwner(i, "ANCHOR_RIGHT")
						GameTooltip:AddLine(i.aText, 1, 1, 1)
						local tNonAutoLevel = SkuNav:GetNonAutoLevel(WaypointCacheLookupCacheNameForId[i.aText])
						if tNonAutoLevel then
							GameTooltip:AddLine("(Layer "..tNonAutoLevel..")", 0.33, 1, 0.33)
						end
						GameTooltip:AddLine("uid "..WaypointCacheLookupCacheNameForId[i.aText], 1, 0.33, 0.33)


						if _G["SkuNavZoneSelector"] and _G["SkuNavZoneSelector"]:IsShown() == true then
							GameTooltip:Hide()
						else
							GameTooltip:Show()
						end
						i:SetSize(3, 3)
						local r, g, b, t = i:GetVertexColor()
						i.oldColor = {r = r, g = g, b = b, t = t}
						i:SetColorTexture(0, 1, 1)
					else
						i:SetSize(2, 2)
						if i.oldColor then
							i:SetColorTexture(i.oldColor.r, i.oldColor.g, i.oldColor.b, i.oldColor.a)
							--i:SetColorTexture(i.oldColor)
						end
					end
				end
				if WaypointCache[WaypointCacheLookupAll[i.aText]].tackStep ~= nil then
					i:SetColorTexture(0.33, 0.33, 1, 1)
				end				
			end
		end
		
		if SkuWaypointWidgetRepoMM then
			if _G["SkuNavMMMainFrame"]:IsShown() then
				SkuWaypointWidgetCurrent = nil

				local tCursorX, tCursorY = GetCursorPosition()
				local _, _, _, tBlX, tBlY = _G["SkuNavMMMainFrame"]:GetPoint(1)
				local MMx, MMy = _G["SkuNavMMMainFrame"]:GetSize()
				--MMx = MMx + (_G["SkuNavMMMainFrameOptionsParent"]:GetWidth() or 0)

				for i, v in SkuWaypointWidgetRepoMM:EnumerateActive() do
					if i:IsVisible() == true and _G["SkuNavMMMainFrameScrollFrame1"]:IsMouseOver() then
						if i.aText and i.aText ~= "line" then
							local _, _, _, x, y = i:GetPoint(1)
							local taText = i.aText
							if string.find(taText, "\\r\\") then
								local s1, s1 = string.match(taText, "(.+)\\r\\n(.+)")
								taText = s1
							end

							i.isMode1Mouseover = nil

							if SkuNav.tWpEditMode == 1 then
								if i:IsMouseOver() then
									if taText ~= SkuWaypointWidgetCurrent then
										SkuWaypointWidgetCurrent = taText
										GameTooltip.SkuWaypointWidgetCurrent = taText
										GameTooltip:ClearLines()
										GameTooltip:SetOwner(i, "ANCHOR_RIGHT")
										GameTooltip:AddLine(taText, 1, 1, 1)
										local tNonAutoLevel = SkuNav:GetNonAutoLevel(WaypointCacheLookupCacheNameForId[taText])
										if tNonAutoLevel then
											GameTooltip:AddLine("(Layer "..tNonAutoLevel..")", 0.33, 1, 0.33)
										end
										if WaypointCacheLookupCacheNameForId[taText] then
											GameTooltip:AddLine("uid "..WaypointCacheLookupCacheNameForId[taText], 1, 0.33, 0.33)
										end
										
										if i.aComments then
											for x = 1, #i.aComments do
												GameTooltip:AddLine(i.aComments[x], 1, 1, 0)
											end
										end
										GameTooltip:Show()
									end
								end

								local tDistance = SkuNav:Distance(tCursorX, tCursorY, math.floor(((MMx/2) + tBlX + x)), math.floor(((MMy/2) + tBlY + y)))
								if tDistance < SkuNav.tCoverSize then
									local r, g, b, a = i:GetVertexColor()
									i.oldColorMo = {r = r, g = g, b = b, a = a}
									i:SetColorTexture(0, 0, 1)
									i.isMode1Mouseover = true
								else
									if i.oldColorMo then
										i:SetColorTexture(i.oldColorMo.r, i.oldColorMo.g, i.oldColorMo.b, i.oldColorMo.a)
										i.oldColorMo = nil
									end
								end
							else
								if i:IsMouseOver() then
									MMx, MMy = MMx / 2, MMy / 2
									if x > -MMx and x < MMx and y > -MMy and y < MMy then
										if taText ~= SkuWaypointWidgetCurrent then
											SkuWaypointWidgetCurrent = taText

											GameTooltip.SkuWaypointWidgetCurrent = taText
											GameTooltip:ClearLines()
											GameTooltip:SetOwner(i, "ANCHOR_RIGHT")
											GameTooltip:AddLine(taText, 1, 1, 1)
											local tNonAutoLevel = SkuNav:GetNonAutoLevel(WaypointCacheLookupCacheNameForId[taText])
											if tNonAutoLevel then
												GameTooltip:AddLine("(Layer "..tNonAutoLevel..")", 0.33, 1, 0.33)
											end

											if taText and WaypointCacheLookupCacheNameForId[taText] then
												GameTooltip:AddLine("uid "..WaypointCacheLookupCacheNameForId[taText], 1, 0.33, 0.33)
											end

											if i.aComments then
												for x = 1, #i.aComments do
													GameTooltip:AddLine(i.aComments[x], 1, 1, 0)
												end
											end
											if _G["SkuNavZoneSelector"] and _G["SkuNavZoneSelector"]:IsShown() == true then
												GameTooltip:Hide()
											else
												GameTooltip:Show()
											end										
											local r, g, b, a = i:GetVertexColor()
											i.oldColor = {r = r, g = g, b = b, a = a}
											--i.oldColor = i:GetVertexColor()
											i:SetColorTexture(0, 1, 1)
										else
											--i:SetSize(2, 2)
											if i.oldColor then
												i:SetColorTexture(i.oldColor.r, i.oldColor.g, i.oldColor.b, i.oldColor.a)
											end

										end
									end
								end
							end
						end
					end

					if WaypointCacheLookupAll[i.aText] then
						if WaypointCache[WaypointCacheLookupAll[i.aText]].tackStep ~= nil then
							i:SetColorTexture(0.33, 0.33, 1, 1)
						end
					end

				end
			end
		end

		if GameTooltip:IsShown() and not SkuWaypointWidgetCurrent and GameTooltip.SkuWaypointWidgetCurrent then
			GameTooltip.SkuWaypointWidgetCurrent = nil
			GameTooltip:Hide()
		end

		SkuNav:ProcessRecordingMousClickStuff()

		if ttime > 0.1 then
			SkuNav:ProcessPolyZones()
			ttime = 0
		end
	end)
end

--------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:OnEnable()
	if not SkuOptions.db.global[MODULE_NAME] then
		SkuOptions.db.global[MODULE_NAME] = {}
	end
	if not SkuOptions.db.global[MODULE_NAME].Waypoints then
		SkuOptions.db.profile[MODULE_NAME].Waypoints = nil
		SkuOptions.db.global[MODULE_NAME].Waypoints = {}
	end

	SkuOptions.db.profile[MODULE_NAME].routeRecording = false
	SkuOptions.db.profile[MODULE_NAME].routeRecordingLastWp = nil
	SkuOptions.db.profile[MODULE_NAME].routeRecordingDelete = nil

	SkuNav:SkuNavMMOpen()
	SkuNav:CreateSkuNavControl()
end

---------------------------------------------------------------------------------------------------------------------------------------
do
	local f = _G["SkuNavWpDragClickTrap"] or CreateFrame("Frame", "SkuNavWpDragClickTrap", _G["SkuNavMMMainFrameScrollFrame"], BackdropTemplateMixin and "BackdropTemplate" or nil)
	--f:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background", edgeFile="", tile = false, tileSize = 0, edgeSize = 32, insets = { left = 5, right = 5, top = 5, bottom = 5 }})
	--f:SetBackdropColor(0, 0, 1, 1)
	f:SetFrameStrata("DIALOG")
	f:RegisterForDrag()
	f:SetWidth(1)
	f:SetHeight(1)
	f:SetAllPoints()
	f:EnableMouse(true)
	f:Hide()
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:OnMouseLeftDown()

end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:OnMouseLeftHold()

end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:OnMouseLeftUp()
	if _G["SkuNavZoneSelector"] and _G["SkuNavZoneSelector"]:IsShown() == true then
		print("not possible. zone selector open.")
		SkuNav:PlayFailSound()
		return
	end

	--add selection end point
	if IsShiftKeyDown() == false and IsAltKeyDown() == true and SkuOptions.db.profile["SkuNav"].showAdvancedControls > 0 then
		if SkuNav.tWpEditMode == 2 then
			local tOldTracks = SkuTableCopy(SkuNav.Tracks, true)
			SkuNav:History_Generic("Select endpoint", function(self, aOldTracks)
				SkuNav.Tracks = SkuTableCopy(aOldTracks, true)
				SkuNav:RebuildTracks()
			end,
			tOldTracks
			)

			local tWaypointCacheId = WaypointCacheLookupAll[SkuWaypointWidgetCurrent]
			SkuNav.Tracks.endids[#SkuNav.Tracks.endids + 1] = tWaypointCacheId
			SkuNav:RebuildTracks()

			return
		end
	
	elseif IsShiftKeyDown() == true and IsAltKeyDown() == false then
		--Create WP
		if SkuOptions.db.profile[MODULE_NAME].routeRecordingDelete == true then
			print("not possible. link deleting in progress.")
			SkuNav:PlayFailSound()
			return
		end

		local tWy, tWx = SkuNavMMContentToWorld(SkuNavMMGetCursorPositionContent2())
		local tWpSize = 1
		--if IsShiftKeyDown() then
			--tWpSize = 5
		--end

		local tNewWpName = SkuNav:CreateWaypoint(nil, tWx, tWy, tWpSize, nil, nil, nil)
		SkuNav:History_Generic("Create Waypoint", SkuNav.DeleteWaypoint, tNewWpName, nil, nil)
		
		if tNewWpName then
			if SkuOptions.db.profile["SkuNav"].routeRecording == true and 
				SkuOptions.db.profile["SkuNav"].routeRecordingLastWp and
				SkuOptions.db.profile["SkuNav"].routeRecordingDelete ~= true
			then
				SkuNav:CreateWpLink(tNewWpName, SkuOptions.db.profile["SkuNav"].routeRecordingLastWp)
				SkuOptions.db.profile["SkuNav"].routeRecordingLastWp = tNewWpName
			end
		else
			return
		end

		SkuOptions.db.global["SkuNav"].hasCustomMapData = true
		print("Waypoint created")

	elseif IsShiftKeyDown() == true and IsAltKeyDown() == true then
		--Add comment to WP
		if SkuOptions.db.profile[MODULE_NAME].routeRecording == true or SkuOptions.db.profile[MODULE_NAME].routeRecordingDelete == true then
			print("not possible. link recording or deleting in progress.")
			SkuNav:PlayFailSound()
		else
			if SkuWaypointWidgetCurrent then
				SkuOptions:AddCommentToWp(SkuWaypointWidgetCurrent)
			end
		end

	else
		--Start/end link add
		if SkuOptions.db.profile[MODULE_NAME].routeRecordingDelete == true then
			print("not possible. link deleting in progress.")
			SkuNav:PlayFailSound()
		else
			local tWpName = SkuWaypointWidgetCurrent
			if not tWpName then
				return
			end
		
			local wpObj = SkuNav:GetWaypointData2(tWpName)
			if not wpObj then
				return
			end
		
			if SkuOptions.db.profile[MODULE_NAME].routeRecording ~= true then
				SkuNav:StartRouteRecording(tWpName)
			else
				if SkuOptions.db.profile[MODULE_NAME].routeRecordingDelete ~= true then
					SkuNav:EndRouteRecording(tWpName)
				end
			end
			SkuOptions.db.global["SkuNav"].hasCustomMapData = true
		end

	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:OnMouseRightDown()

end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:OnMouseRightHold()

end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:OnMouseRightUp()
	if _G["SkuNavZoneSelector"] and _G["SkuNavZoneSelector"]:IsShown() == true then
		print("not possible. zone selector open.")
		SkuNav:PlayFailSound()
		return
	end

	if IsAltKeyDown() then
		--Delete comments from WP
		if SkuOptions.db.profile[MODULE_NAME].routeRecording == true or SkuOptions.db.profile[MODULE_NAME].routeRecordingDelete == true then
			print("not possible. link recording or deleting in progress.")
			SkuNav:PlayFailSound()
		else

			if not SkuWaypointWidgetCurrent then
				return
			end
			local wpObj = SkuNav:GetWaypointData2(SkuWaypointWidgetCurrent)
			if not wpObj then
				return
			end

			--add to history
			SkuNav:History_Generic("Delete comments", function(self, wpName, comments)
				SkuNav:SetWaypoint(wpName, {comments = comments})
			end,
			SkuWaypointWidgetCurrent,
			wpObj.comments
			)
			
			SkuNav:SetWaypoint(SkuWaypointWidgetCurrent, {comments = 
				{
					["deDE"] = {},
					["enUS"] = {},
				}
			})
			SkuOptions.db.global["SkuNav"].hasCustomMapData = true
		end

	elseif IsShiftKeyDown() then
		--Delete WP
		if SkuOptions.db.profile[MODULE_NAME].routeRecording == true or SkuOptions.db.profile[MODULE_NAME].routeRecordingDelete == true then
			print("not possible. link recording or deleting in progress.")
			SkuNav:PlayFailSound()
		else
			if SkuWaypointWidgetCurrent then
				local wpObj = SkuNav:GetWaypointData2(SkuWaypointWidgetCurrent)
				if wpObj then
					ClearWaypointMM(tSkuNavMMDrawCache[WaypointCacheLookupAll[wpObj.name]].poolObjects)
					SkuNav:DeleteWaypoint(SkuWaypointWidgetCurrent)

					SkuOptions.db.global["SkuNav"].hasCustomMapData = true
				end
			end
		end
	else
		--Start/end link delete
		if SkuOptions.db.profile[MODULE_NAME].routeRecording == true and SkuOptions.db.profile[MODULE_NAME].routeRecordingDelete ~= true then
			print("not possible. link recording in progress.")
			SkuNav:PlayFailSound()
		else
			local tWpName = SkuWaypointWidgetCurrent
			if not tWpName then
				return
			end
		
			local wpObj = SkuNav:GetWaypointData2(tWpName)
			if not wpObj then
				return
			end
		
			if SkuOptions.db.profile[MODULE_NAME].routeRecording ~= true then
				SkuNav:StartRouteRecording(tWpName, true)
			else
				if SkuOptions.db.profile[MODULE_NAME].routeRecordingDelete == true then
					SkuNav:EndRouteRecording(tWpName, true)
				end
			end
			SkuOptions.db.global["SkuNav"].hasCustomMapData = true
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:OnMouse4Down()
	dprint("OnMouse4Down")
	if _G["SkuNavZoneSelector"] and _G["SkuNavZoneSelector"]:IsShown() == true then
		print("not possible. zone selector open.")
		SkuNav:PlayFailSound()
		return
	end
		
	--start Move WP
	if SkuOptions.db.profile[MODULE_NAME].routeRecording == true or SkuOptions.db.profile[MODULE_NAME].routeRecordingDelete == true then
		print("not possible. link recording or deleting in progress.")
		SkuNav:PlayFailSound()
	else
		local tWpName = SkuWaypointWidgetCurrent
		if tWpName then
			SkuNav.moveTmpOldUidLevel = SkuOptions.db.global[MODULE_NAME].WaypointLevels[WaypointCacheLookupCacheNameForId[tWpName]]
			--SkuOptions.db.global[MODULE_NAME].WaypointLevels[WaypointCacheLookupCacheNameForId[tWpName]] = nil
			--WaypointCacheLookupIdForCacheIndex[WaypointCacheLookupCacheNameForId[tWpName]] = nil
			local wpObj = SkuNav:GetWaypointData2(tWpName)
			if wpObj then
				tCurrentDragWpName = tWpName
				SkuOptions.db.global["SkuNav"].hasCustomMapData = true
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:OnMouse4Hold()
	if _G["SkuNavZoneSelector"] and _G["SkuNavZoneSelector"]:IsShown() == true then
		print("not possible. zone selector open.")
		SkuNav:PlayFailSound()
		return
	end
		
	--Hold Move WP
	if SkuOptions.db.profile[MODULE_NAME].routeRecording == true or SkuOptions.db.profile[MODULE_NAME].routeRecordingDelete == true then
	else
		if tCurrentDragWpName then
			local tWpData = SkuNav:GetWaypointData2(tCurrentDragWpName)
			if tWpData then
				local tDragY, tDragX = SkuNavMMContentToWorld(SkuNavMMGetCursorPositionContent2())
				if tDragX and tDragY then
					SkuNav:SetWaypoint(tCurrentDragWpName, {
						worldX = tDragX,
						worldY = tDragY,
					})
					SkuOptions.db.global["SkuNav"].hasCustomMapData = true
				end
			end
		end
		
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:OnMouse4Up()
	if _G["SkuNavZoneSelector"] and _G["SkuNavZoneSelector"]:IsShown() == true then
		print("not possible. zone selector open.")
		SkuNav:PlayFailSound()
		return
	end
		
	--End Move WP
	if SkuOptions.db.profile[MODULE_NAME].routeRecording == true or SkuOptions.db.profile[MODULE_NAME].routeRecordingDelete == true then
		print("not possible. link recording or deleting in progress.")
		SkuNav:PlayFailSound()
	else
		if tCurrentDragWpName then
			local tWpData = SkuNav:GetWaypointData2(tCurrentDragWpName)
			if tWpData then
				local tDragY, tDragX = SkuNavMMContentToWorld(SkuNavMMGetCursorPositionContent2())
				if tDragX and tDragY then
					--SkuOptions.db.global[MODULE_NAME].WaypointLevels[WaypointCacheLookupCacheNameForId[tCurrentDragWpName]] = nil
					SkuNav:SetWaypoint(tCurrentDragWpName, {
						worldX = tDragX,
						worldY = tDragY,
					})
					SkuOptions.db.global["SkuNav"].hasCustomMapData = true
					local tWpData = SkuNav:GetWaypointData2(tCurrentDragWpName)
					local tUid = SkuNav:BuildWpIdFromData(
						tWpData.typeId,
						tWpData.dbIndex,
						tWpData.spawn,
						tWpData.areaId
					)					

					SkuOptions.db.global[MODULE_NAME].WaypointLevels[tUid] = SkuNav.moveTmpOldUidLevel
					
					local tcontintentId = select(3, SkuNav:GetAreaData(SkuNav:GetAreaIdFromMapDropdown()))
					local tUiMapId = SkuNav:GetUiMapIdFromAreaId(SkuNav:GetAreaIdFromMapDropdown())
				
					for x = 1, #WaypointCache do
						if WaypointCacheLookupPerContintent[tcontintentId][x] then
							if WaypointCache[x].name == tCurrentDragWpName then
								WaypointCacheLookupIdForCacheIndex[tUid] = x
								WaypointCacheLookupCacheNameForId[tCurrentDragWpName] = tUid
							end
						end
					end
				
					SkuNav.moveTmpOldUidLevel = nil
				end
			end
		end
		_G["SkuNavWpDragClickTrap"]:Hide()
		SkuWaypointWidgetCurrent = nil
		SkuWaypointWidgetCurrentMMX = nil
		SkuWaypointWidgetCurrentMMY = nil
		tCurrentDragWpName = nil
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:OnMouseMiddleDown()

end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:OnMouseMiddleHold()

end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:OnMouseMiddleUp()
	if _G["SkuNavZoneSelector"] and _G["SkuNavZoneSelector"]:IsShown() == true then
		print("not possible. zone selector open.")
		SkuNav:PlayFailSound()
		return
	end
		
	if IsShiftKeyDown() == false and IsAltKeyDown() == true and SkuOptions.db.profile["SkuNav"].showAdvancedControls > 0 then
		if SkuNav.tWpEditMode == 2 then
			local tOldTracks = SkuTableCopy(SkuNav.Tracks, true)
			SkuNav:History_Generic("Select selection start point", function(self, aOldTracks)
				SkuNav.Tracks = SkuTableCopy(aOldTracks, true)
				SkuNav:RebuildTracks()
			end,
			tOldTracks
			)		

			local tWaypointCacheId = WaypointCacheLookupAll[SkuWaypointWidgetCurrent]
			local tWpData = SkuNav:GetWaypointData2(SkuWaypointWidgetCurrent)
			SkuNav.Tracks = {
				startid = nil,
				endids = {},
			}
			SkuNav:RebuildTracks()
			SkuNav.Tracks = {
				startid = tWaypointCacheId,
				endids = {},
			}
			SkuNav:RebuildTracks()

			return

		else
			local tcontintentId = select(3, SkuNav:GetAreaData(SkuNav:GetAreaIdFromMapDropdown()))

			--add to history
			local tOldTracks = {}
			for x = 1, #WaypointCache do
				if WaypointCache[x] and WaypointCache[x].tackStep == 99999 then
					tOldTracks[x] = true
				end
			end
			SkuNav:History_Generic("Select mouseover", function(self, aOldTracks)
				for x = 1, #WaypointCache do
					if aOldTracks[x] == true then
						WaypointCache[x].tackStep = 99999
					else
						WaypointCache[x].tackStep = nil
					end
				end
				--SkuNav:RebuildTracks()
			end,
			tOldTracks
			)		


			for i, v in SkuWaypointWidgetRepoMM:EnumerateActive() do
				if i:IsVisible() == true and _G["SkuNavMMMainFrameScrollFrame1"]:IsMouseOver() then
					if i.aText and i.aText ~= "line" then
						if i.isMode1Mouseover == true then
							for x = 1, #WaypointCache do
								if WaypointCacheLookupPerContintent[tcontintentId][x] then
									if WaypointCache[x].name == i.aText then
										if WaypointCache[x].tackStep == nil then --and WaypointCache[x].tackStart == nil and WaypointCache[x].tackend == nil
											WaypointCache[x].tackStep = 99999
										else
											WaypointCache[x].tackStep = nil
										end
									end
								end
							end
						end
					end
				end
			end

			return
		end
	end

	--Rename WP
	if SkuOptions.db.profile[MODULE_NAME].routeRecording == true or SkuOptions.db.profile[MODULE_NAME].routeRecordingDelete == true then
		print("not possible. link recording or deleting in progress.")
		SkuNav:PlayFailSound()
	else
		if SkuWaypointWidgetCurrent then
			local tOldName = SkuWaypointWidgetCurrent
			local tWpData = SkuNav:GetWaypointData2(SkuWaypointWidgetCurrent)
			if tWpData then
				if tWpData.typeId ~= 1 then
					print("only custom waypoints can be renamed")
					SkuNav:PlayFailSound()
					return
				end
				SkuOptions:EditBoxShow(tOldName, function(a, b, c) 
					local tText = SkuOptionsEditBoxEditBox:GetText() 
					if tText ~= "" then
						if SkuOptions:RenameWp(tOldName, tText) ~= false then
							SkuNav:PlaySoundFile("Interface\\AddOns\\SkuMapper\\audio\\sound-notification15.mp3")
							print("renamed")
						else
							print("renaming failed")
							SkuNav:PlayFailSound()
						end
					else
						print("renaming failed")
						print("name empty")
						SkuNav:PlayFailSound()
					end
				end)
				print("enter new name and press enter or press escape to cancel")
			else
				print("error: no wp data")
				SkuNav:PlayFailSound()
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:OnMouse5Down()

end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:OnMouse5Hold()

end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:OnMouse5Up()
	if _G["SkuNavZoneSelector"] and _G["SkuNavZoneSelector"]:IsShown() == true then
		print("not possible. zone selector open.")
		SkuNav:PlayFailSound()
		return
	end
		
	-- create poly point
	if SkuNavRecordingPoly > 0 and SkuNavRecordingPolyFor then
		local tWorldY, tWorldX = SkuNavMMContentToWorld(SkuNavMMGetCursorPositionContent2())
		SkuDB.Polygons.data[SkuNavRecordingPolyFor].nodes[#SkuDB.Polygons.data[SkuNavRecordingPolyFor].nodes + 1] = {x = tWorldX, y = tWorldY,}
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:UpdateWpName(aOldName, aNewName)
	local tAddText = {
		deDE = _G["SkuNavMMMainFrameSuffixCustomdeDEEditBoxEditBox"]:GetText(),
		enUS = _G["SkuNavMMMainFrameSuffixCustomenUSEditBoxEditBox"]:GetText(),
	}

	local tcontintentId = select(3, SkuNav:GetAreaData(SkuNav:GetCurrentAreaId()))
	local tUiMapId = SkuNav:GetUiMapIdFromAreaId(SkuNav:GetCurrentAreaId())

	for x = 1, #WaypointCache do
		if WaypointCacheLookupPerContintent[tcontintentId][x] then
			if WaypointCache[x].name == aOldName then
				local tOldCurrentLocName = WaypointCache[x].name
				local tNewCurrentLocName = aNewName

				WaypointCache[x].name = tNewCurrentLocName

				for z = 1, #WaypointCache do
					if WaypointCacheLookupPerContintent[tcontintentId][z] then
						if WaypointCache[z].links and WaypointCache[z].links.byName then
							if WaypointCache[z].links.byName[tOldCurrentLocName] then
								local tVal = WaypointCache[z].links.byName[tOldCurrentLocName]
								WaypointCache[z].links.byName[tNewCurrentLocName] = tVal
								WaypointCache[z].links.byName[tOldCurrentLocName] = nil
							end
						end
					end
				end

				local tval = WaypointCacheLookupAll[tOldCurrentLocName]
				WaypointCacheLookupAll[tNewCurrentLocName] = tval
				WaypointCacheLookupAll[tOldCurrentLocName] = nil

				local tval = WaypointCacheLookupCacheNameForId[tOldCurrentLocName]
				WaypointCacheLookupCacheNameForId[tNewCurrentLocName] = tval
				WaypointCacheLookupCacheNameForId[tOldCurrentLocName] = nil						
					
				WaypointCacheLookupPerContintent[tcontintentId][x] = tNewCurrentLocName

				local tOlddeDEName = SkuOptions.db.global[MODULE_NAME].Waypoints[WaypointCache[x].dbIndex].names.deDE
				local tNewdeDEName = aNewName
				if Sku.Loc == "enUS" then
					tNewdeDEName = "UNTRANSLATED "..tNewdeDEName
				end
				SkuOptions.db.global[MODULE_NAME].Waypoints[WaypointCache[x].dbIndex].names.deDE = tNewdeDEName

				local tOldenUSName = SkuOptions.db.global[MODULE_NAME].Waypoints[WaypointCache[x].dbIndex].names.enUS
				local tNewenUSName = aNewName
				if Sku.Loc == "deDE" then
					tNewenUSName = "UNTRANSLATED "..tNewdeDEName
				end
				SkuOptions.db.global[MODULE_NAME].Waypoints[WaypointCache[x].dbIndex].names.enUS = tNewenUSName


				SkuNav:History_Generic("Rename waypoint", function(self, tOlddeDEName, tNewdeDEName, tOldenUSName, tNewenUSName)
					if Sku.Loc == "enUS" then
						SkuNav:UpdateWpName(tNewenUSName, tOldenUSName)
						SkuOptions.db.global[MODULE_NAME].Waypoints[WaypointCache[x].dbIndex].names.deDE = tOlddeDEName
					end
	
					if Sku.Loc == "deDE" then
						SkuNav:UpdateWpName(tNewdeDEName, tOlddeDEName)
						SkuOptions.db.global[MODULE_NAME].Waypoints[WaypointCache[x].dbIndex].names.enUS = tOldenUSName					
					end
					
				end,
				tOlddeDEName,
				tNewdeDEName,
				tOldenUSName, 
				tNewenUSName
				)


				break
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:GetNonAutoLevel(aUid, aUnitName)
	if SkuOptions.db.global[MODULE_NAME].WaypointLevels == nil then
		return
	end

	if aUid == nil and aUnitName ~= nil then
		local tPlayerAreaId = SkuNav:GetCurrentAreaId()
		if not tPlayerAreaId then return end

		--dalaran fix
		if tPlayerAreaId == 100077 or tPlayerAreaId == 4613 then
			tPlayerAreaId = 4395
		end

		for i, v in pairs(SkuDB.NpcData.Names[Sku.Loc]) do
			if v[1] == aUnitName then
				if SkuDB.NpcData.Data[i] then
					if SkuDB.NpcData.Data[i][7] then
						if SkuDB.NpcData.Data[i][7][tPlayerAreaId] then
							if #SkuDB.NpcData.Data[i][7][tPlayerAreaId] == 1 then
								aUid = SkuNav:BuildWpIdFromData(2, i, 1, tPlayerAreaId)
							end
							break
						end
					end
				end
			end
		end
	end

	if aUid == nil then
		return
	end
	
	return SkuOptions.db.global[MODULE_NAME].WaypointLevels[aUid]
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:UpdateTracksNonAutoLevel()
	dprint("UpdateTracksNonAutoLevel")

	SkuOptions.db.global[MODULE_NAME].WaypointLevels = SkuOptions.db.global[MODULE_NAME].WaypointLevels or {}

	local tLevel
	if SkuNav.TrackedLevel == -1 then
		tLevel = nil
	else
		tLevel = SkuNav.TrackedLevels[SkuNav.TrackedLevel]
	end

	local tcontintentId = select(3, SkuNav:GetAreaData(SkuNav:GetAreaIdFromMapDropdown()))
	local tUiMapId = SkuNav:GetUiMapIdFromAreaId(SkuNav:GetAreaIdFromMapDropdown())

	local tUpdatedWaypointsForHistory = {}
	for x = 1, #WaypointCache do
		if WaypointCacheLookupPerContintent[tcontintentId][x] then
			if WaypointCache[x].tackStep ~= nil then
				local tUid = SkuNav:BuildWpIdFromData(
					WaypointCache[x].typeId,
					WaypointCache[x].dbIndex,
					WaypointCache[x].spawn,
					WaypointCache[x].areaId
				)
				tUpdatedWaypointsForHistory[tUid] = SkuOptions.db.global[MODULE_NAME].WaypointLevels[tUid] or -99
				SkuOptions.db.global[MODULE_NAME].WaypointLevels[tUid] = tLevel
			end
		end
	end

	SkuNav:History_Generic("Change waypoint layer value", function(self, aUpdatedWaypointsForHistory)
		for i, v in pairs(aUpdatedWaypointsForHistory) do
			if v == -99 then
				SkuOptions.db.global[MODULE_NAME].WaypointLevels[i] = nil
			else
				SkuOptions.db.global[MODULE_NAME].WaypointLevels[i] = v
			end
		end
	end,
	tUpdatedWaypointsForHistory
	)

end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:UpdateTracksNames()
	local tAddText = {
		deDE = _G["SkuNavMMMainFrameSuffixCustomdeDEEditBoxEditBox"]:GetText(),
		enUS = _G["SkuNavMMMainFrameSuffixCustomenUSEditBoxEditBox"]:GetText(),
	}

	if not _G["SkuNavMMMainFrameSuffixCustomdeDEEditBoxEditBox"]:GetText() or not _G["SkuNavMMMainFrameSuffixCustomenUSEditBoxEditBox"]:GetText() or _G["SkuNavMMMainFrameSuffixCustomdeDEEditBoxEditBox"]:GetText() == "" or _G["SkuNavMMMainFrameSuffixCustomenUSEditBoxEditBox"]:GetText() == "" then
		print("Error: no text")
		return
	end

	local tcontintentId = select(3, SkuNav:GetAreaData(SkuNav:GetCurrentAreaId()))
	local tUiMapId = SkuNav:GetUiMapIdFromAreaId(SkuNav:GetCurrentAreaId())

	local tOldNamesForHistory = {}

	for x = 1, #WaypointCache do
		if WaypointCacheLookupPerContintent[tcontintentId][x] then
			if WaypointCache[x].tackStep ~= nil then
				if string.sub(WaypointCache[x].name, 1, 5) == "auto " then
					local tOldCurrentLocName = WaypointCache[x].name
					local tNewCurrentLocName = "auto "..tAddText[Sku.Loc]..";"..string.sub(tOldCurrentLocName, 6)

					WaypointCache[x].name = tNewCurrentLocName

					for z = 1, #WaypointCache do
						if WaypointCacheLookupPerContintent[tcontintentId][z] then
							if WaypointCache[z].links and WaypointCache[z].links.byName then
								if WaypointCache[z].links.byName[tOldCurrentLocName] then
									local tVal = WaypointCache[z].links.byName[tOldCurrentLocName]
									WaypointCache[z].links.byName[tNewCurrentLocName] = tVal
									WaypointCache[z].links.byName[tOldCurrentLocName] = nil
								end
							end
						end
					end

					local tval = WaypointCacheLookupAll[tOldCurrentLocName]
					WaypointCacheLookupAll[tNewCurrentLocName] = tval
					WaypointCacheLookupAll[tOldCurrentLocName] = nil

					local tval = WaypointCacheLookupCacheNameForId[tOldCurrentLocName]
					WaypointCacheLookupCacheNameForId[tNewCurrentLocName] = tval
					WaypointCacheLookupCacheNameForId[tOldCurrentLocName] = nil						
						
					WaypointCacheLookupPerContintent[tcontintentId][x] = tNewCurrentLocName

					local tOlddeDEName = SkuOptions.db.global[MODULE_NAME].Waypoints[WaypointCache[x].dbIndex].names.deDE
					local tNewdeDEName = "auto "..tAddText["deDE"]..";"..string.sub(tOlddeDEName, 6)
					if Sku.Loc == "enUS" and SkuOptions.db.profile["SkuNav"].showAdvancedControls < 2 then
						tNewdeDEName = "UNTRANSLATED "..tNewdeDEName
					end
					SkuOptions.db.global[MODULE_NAME].Waypoints[WaypointCache[x].dbIndex].names.deDE = tNewdeDEName

					local tOldenUSName = SkuOptions.db.global[MODULE_NAME].Waypoints[WaypointCache[x].dbIndex].names.enUS
					local tNewenUSName = "auto "..tAddText["enUS"]..";"..string.sub(tOldenUSName, 6)
					if Sku.Loc == "deDE" and SkuOptions.db.profile["SkuNav"].showAdvancedControls < 2 then
						tNewenUSName = "UNTRANSLATED "..tNewenUSName
					end
					SkuOptions.db.global[MODULE_NAME].Waypoints[WaypointCache[x].dbIndex].names.enUS = tNewenUSName

					--for history
					tOldNamesForHistory[WaypointCache[x].dbIndex] = {
						tOlddeDEName = tOlddeDEName,
						tNewdeDEName = tNewdeDEName,
						tOldenUSName = tOldenUSName,
						tNewenUSName = tNewenUSName,
					}

				end
			end
		end
	end


	--add to history
	SkuNav:History_Generic("Add custom prefix", function(self, aOldNamesForHistory)
		for i, v in pairs(aOldNamesForHistory) do
			if Sku.Loc == "enUS" then
				SkuNav:UpdateWpName(v.tNewenUSName, v.tOldenUSName)
				SkuOptions.db.global[MODULE_NAME].Waypoints[i].names.deDE = v.tOlddeDEName
			end

			if Sku.Loc == "deDE" then
				SkuNav:UpdateWpName(v.tNewdeDEName, v.tOlddeDEName)
				SkuOptions.db.global[MODULE_NAME].Waypoints[i].names.enUS = v.tOldenUSName
			end
		end
	end,
	tOldNamesForHistory
	)






	
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:RebuildTracks()
	local tcontintentId = select(3, SkuNav:GetAreaData(SkuNav:GetCurrentAreaId()))
	local tUiMapId = SkuNav:GetUiMapIdFromAreaId(SkuNav:GetCurrentAreaId())

	for x = 1, #WaypointCache do
		if WaypointCacheLookupPerContintent[tcontintentId][x] then
			WaypointCache[x].tackStart = nil
			if WaypointCache[x].tackStep ~= 99999 then
				WaypointCache[x].tackStep = nil
			end
			WaypointCache[x].tackend = nil
		end
	end
	if SkuNav.Tracks.startid == nil then
		return
	end

	WaypointCache[SkuNav.Tracks.startid].tackStart = true
	WaypointCache[SkuNav.Tracks.startid].tackStep = 1

	for y = 1, #SkuNav.Tracks.endids do
		WaypointCache[SkuNav.Tracks.endids[y]].tackend = true
	end

	local tFound = true
	local tCount = 1
	while tFound == true and tCount <= SkuNav.TrackSize do
		tFound = false
		for x = 1, #WaypointCache do
			if WaypointCacheLookupPerContintent[tcontintentId][x] then
				if WaypointCache[x].uiMapId == tUiMapId and WaypointCache[x].tackStep == tCount and WaypointCache[x].tackend ~= true then
					for i, v in pairs(WaypointCache[x].links.byId) do
						if WaypointCache[i].tackStep == nil or WaypointCache[i].tackStep == 99999 then
							WaypointCache[i].tackStep = tCount + 1
							tFound = true
						end
					end
				end
			end
		end
		tCount = tCount + 1
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:IntersectionPoint(x1, y1, x2, y2, x3, y3, x4, y4)
	if x1 and y1 and x2 and y2 and x3 and y3 and x4 and y4 then
		 local d 
		 local Ua 
		 local Ub 
		 --Pre calc the denominator, if zero then both lines are parallel and there is no intersection
		 d = ((y4 - y3) * (x2 - x1) - (x4 - x3) * (y2 - y1))
		 if d ~= 0 then
			  --Solve for the simultaneous equations
			  Ua = ((x4 - x3) * (y1 - y3) - (y4 - y3) * (x1 - x3)) / d
			  Ub = ((x2 - x1) * (y1 - y3) - (y2 - y1) * (x1 - x3)) / d
		 end 
		 if Ua and Ub then
			  --Could the lines intersect?
			  if Ua >= -0.0 and Ua <= 1.0 and Ub >= -0.0 and Ub <= 1.0 then
					--Calculate the intersection point
					local x = x1 + Ua * (x2 - x1)
					local y = y1 + Ua * (y2 - y1)
					--Yes, they do
					return x, y, Ua
			  end
		 end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:OnDisable()

end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:PLAYER_LEAVING_WORLD(...)
	if SkuOptions.db.profile[MODULE_NAME].SkuNavMMMainIsCollapsed == false then
		--[[
		if _G["SkuNavMMMainFrameOptionsParent"]:IsShown() then
			_G["SkuNavMMMainFrameOptionsParent"]:SetWidth(0)
			_G["SkuNavMMMainFrameOptionsParent"]:Hide()
			_G["SkuNavMMMainFrame"]:ClearAllPoints()
			_G["SkuNavMMMainFrame"]:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", (_G["SkuNavMMMainFrame"]:GetLeft() + 300 ), (_G["SkuNavMMMainFrame"]:GetBottom()))
			_G["SkuNavMMMainFrame"]:SetWidth(_G["SkuNavMMMainFrame"]:GetWidth() - 300)

			_G["SkuNavMMMainFrameScrollFrame"]:SetPoint("TOPLEFT", _G["SkuNavMMMainFrame"], "TOPLEFT", _G["SkuNavMMMainFrameOptionsParent"]:GetWidth() + 5, -5)
			_G["SkuNavMMMainFrameScrollFrame1"]:SetPoint("TOPLEFT", _G["SkuNavMMMainFrame"], "TOPLEFT", _G["SkuNavMMMainFrameOptionsParent"]:GetWidth() + 5, -5)
			--SkuOptions.db.profile[MODULE_NAME].SkuNavMMMainIsCollapsed = true
		end
		]]
	end	
	SkuOptions.db.profile["SkuNav"].metapathFollowingMetapaths = {}
	if SkuOptions.db.global["SkuNav"].hasCustomMapData ~= true then
		SkuOptions.db.global["SkuNav"].Waypoints = {}
		SkuOptions.db.global["SkuNav"].Links = {}
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:PLAYER_LOGIN(...)
	SkuNav.MinimapFull = false
	SkuOptions.db.global["SkuNav"] = SkuOptions.db.global["SkuNav"] or {}
	if SkuOptions.db.profile["SkuNav"].showAdvancedControls == nil then
		SkuOptions.db.profile["SkuNav"].showAdvancedControls = 1
	end

	--load default data if there isn't custom data
	SkuNav:LoadDefaultMapData()

	if SkuOptions.db.global["SkuNav"].WaypointsNew then
		SkuOptions.db.global["SkuNav"].Waypoints = {}
		for x = 1, #SkuOptions.db.global["SkuNav"].WaypointsNew do
			local tData = SkuOptions.db.global["SkuNav"].WaypointsNew[x]
			SkuOptions.db.global["SkuNav"].Waypoints[x] = tData
			if SkuOptions.db.global["SkuNav"].Waypoints[x][1] ~= false then
				local en, de = string.match(SkuOptions.db.global["SkuNav"].Waypoints[x].names, "(.+)§(.+)")
				if not en or not de then
					en, de = "", ""
				end
				SkuOptions.db.global["SkuNav"].Waypoints[x].names = {}
				SkuOptions.db.global["SkuNav"].Waypoints[x].names["enUS"] = en
				SkuOptions.db.global["SkuNav"].Waypoints[x].names["deDE"] = de
			end
		end
	end

	SkuOptions.db.profile[MODULE_NAME].routeRecording = false
	SkuOptions.db.profile[MODULE_NAME].routeRecordingLastWp = nil

	SkuNav:SkuNavMMOpen()
	
	SkuNav:SkuMM_PLAYER_LOGIN()
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:PLAYER_LOGOUT()
	SkuOptions.db.global["SkuNav"].WaypointsNew = {}
	for x = 1, #SkuOptions.db.global["SkuNav"].Waypoints do
		local tdata = SkuOptions.db.global["SkuNav"].Waypoints[x]
		SkuOptions.db.global["SkuNav"].WaypointsNew[x] = tdata
		if SkuOptions.db.global["SkuNav"].Waypoints[x][1] ~= false then
			SkuOptions.db.global["SkuNav"].WaypointsNew[x].names = (SkuOptions.db.global["SkuNav"].Waypoints[x].names.enUS).."§"..(SkuOptions.db.global["SkuNav"].Waypoints[x].names.deDE)
		end
		SkuOptions.db.global["SkuNav"].Waypoints[x] = nil
	end

	SkuNav:SkuMM_PLAYER_LOGOUT()
end
---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:LoadDefaultMapData(aForce)
	if SkuOptions.db.global["SkuNav"].hasCustomMapData ~= true or aForce then
		local t = {}--SkuDB.routedata["global"]["Waypoints"]
		SkuOptions.db.global["SkuNav"].Waypoints = t
		local tl = {}--SkuDB.routedata["global"]["Links"]
		SkuOptions.db.global["SkuNav"].Links = tl
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:PLAYER_ENTERING_WORLD(aEvent, aIsInitialLogin, aIsReloadingUi)
	SkuOptions.db.profile[MODULE_NAME].metapathFollowing = false
	SkuOptions.db.profile[MODULE_NAME].routeRecording = false
	SkuOptions.db.profile["SkuNav"].waypointFilterString = ""



	SkuNav:CreateWaypointCache()

	if _G["SkuNavMMMainFrameZoneSelect"] then
		C_Timer.NewTimer(1, function()
			if SkuNav:GetCurrentAreaId() then
				_G["SkuNavMMMainFrameZoneSelect"].value = -1 --SkuNav:GetCurrentAreaId()
				_G["SkuNavMMMainFrameZoneSelect"]:SetText("Current Zone")--SkuDB.InternalAreaTable[SkuNav:GetCurrentAreaId()].AreaName_lang[Sku.Loc])	
			end
		end)
	end
	SkuNav:UpdateAutoPrefixes(aEvent)

	SkuMapperFocusOnPlayer = true
end

---------------------------------------------------------------------------------------------------------------------------------------
local function SkuSpairs(t, order)
	local keys = {}
	for k in pairs(t) do keys[#keys+1] = k end
	if order then
		table.sort(keys, function(a,b) return order(t, a, b) end)
	else
		table.sort(keys)
	end
	local i = 0
	return function()
		i = i + 1
		if keys[i] then
			return keys[i], t[keys[i]]
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:GetAreaIdFromMapDropdown()
	if _G["SkuNavMMMainFrameZoneSelect"].value == -1 then
		return SkuNav:GetCurrentAreaId()
	elseif _G["SkuNavMMMainFrameZoneSelect"].value == -2 then
		return
	else
		return _G["SkuNavMMMainFrameZoneSelect"].value
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:CreateWaypoint(aName, aX, aY, aSize, aForcename, aIsTempWaypoint, noUpdate, aCreateLinkFunc, aSilent)
	local tNameProvided = aName

	if not aX  then
		aX, aY = UnitPosition("player")
	end

	local tAreaId = SkuNav:GetCurrentAreaId()

	if not noUpdate then
		tAreaId = SkuNav:GetAreaIdFromMapDropdown()

		if not tAreaId then
			print("Error: can't click on map with current contintent selected")
			return
		end

		SkuNav:UpdateAutoPrefixes(nil, tAreaId)
	end

	aSize = aSize or 1
	local tPName = UnitName("player")
	local tPlayerContintentId = select(3, SkuNav:GetAreaData(SkuNav:GetCurrentAreaId()))

	local tSequenceNumber

	if aName == nil then
		tSequenceNumber = SkuNav:GetSequenceNumber(tAreaId)
		aName = L["auto"].." ".._G["SkuNavMMMainFrameSuffixAuto"..Sku.Loc.."EditBoxEditBox"]:GetText()..";"..tSequenceNumber
		tPName = "SkuNav"
	end

	local tZoneName, tAreaName_lang, tContinentID, tParentAreaID, tFaction, tFlags = SkuNav:GetAreaData(tAreaId)

	--add number if name already exists
	if tZoneName then
		if SkuNav:GetWaypointData2(aName) and not aForcename then
			local q = 1
			while SkuNav:GetWaypointData2(aName..q) do
				q = q + 1
			end
			aName = aName..q
		end

		local worldx, worldy = UnitPosition("player")
		if aX and aY then
			worldx, worldy = aX, aY
		end

		SkuNav:SetWaypoint(aName,  {
			["contintentId"] = tPlayerContintentId,
			["areaId"] = tAreaId,
			["worldX"] = worldx,
			["worldY"] = worldy,
			["createdAt"] = GetTime(),
			["createdBy"] = tPName,
			["size"] = aSize,
		}, aIsTempWaypoint)

		local tWpIndex = WaypointCacheLookupAll[aName]
		local tWpId = WaypointCache[tWpIndex].dbIndex

		local tUntransString = "UNTRANSLATED "
		if not noUpdate or _G["SkuNavMMMainFrameSuffixCustom"..Sku.Loc.."EditBoxEditBox"]:GetText() == "" then

			local tGetSubZoneText  = GetSubZoneText()
			local tSubZoneAreaId = SkuNav:GetAreaIdFromAreaName(tGetSubZoneText, true)
			if tSubZoneAreaId and SkuDB.InternalAreaTable[tSubZoneAreaId] then

				tUntransString = ""
			end
		end


		if Sku.Loc == "enUS" then
			if not tNameProvided then
				SkuOptions.db.global[MODULE_NAME].Waypoints[tWpId]["names"]["deDE"] = tUntransString..L["auto"].." ".._G["SkuNavMMMainFrameSuffixAuto".."deDE".."EditBoxEditBox"]:GetText()..";"..(tSequenceNumber or "")
			else
				SkuOptions.db.global[MODULE_NAME].Waypoints[tWpId]["names"]["deDE"] = "UNTRANSLATED "..aName
			end
		else
			if not tNameProvided then
				SkuOptions.db.global[MODULE_NAME].Waypoints[tWpId]["names"]["enUS"] = tUntransString..L["auto"].." ".._G["SkuNavMMMainFrameSuffixAuto".."enUS".."EditBoxEditBox"]:GetText()..";"..(tSequenceNumber or "")
			else
				SkuOptions.db.global[MODULE_NAME].Waypoints[tWpId]["names"]["enUS"] = "UNTRANSLATED "..aName
			end
		end

		if SkuNav.TrackedLevel ~= -1 then
			SkuOptions.db.global[MODULE_NAME].WaypointLevels = SkuOptions.db.global[MODULE_NAME].WaypointLevels or {}
			local tUid = SkuNav:BuildWpIdFromData(
				WaypointCache[tWpIndex].typeId,
				WaypointCache[tWpIndex].dbIndex,
				WaypointCache[tWpIndex].spawn,
				WaypointCache[tWpIndex].areaId
			)
			SkuOptions.db.global[MODULE_NAME].WaypointLevels[tUid] = SkuNav.TrackedLevels[SkuNav.TrackedLevel]
		end
	else
		aName = nil
	end

	if aName and not aIsTempWaypoint then
		if not string.find(aName, L["Einheiten;Route;"]) then
			SkuOptions.db.global["SkuNav"].hasCustomMapData = true
		end
	end

	if not aSilent then
		SkuNav:PlaySoundFile("Interface\\AddOns\\SkuMapper\\audio\\sound-notification15.mp3")
	end

	SkuNav:UpdateAutoPrefixes()

	return aName
	
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:SetWaypoint(aName, aData, aIsTempWaypoint)
	--print("SetWaypoint", aName, aData, aIsTempWaypoint)

	local tWpIndex
	local tIsNew

	if WaypointCacheLookupAll[aName] then
		if WaypointCacheLookupPerContintent[WaypointCache[WaypointCacheLookupAll[aName]].contintentId] then
			WaypointCacheLookupPerContintent[WaypointCache[WaypointCacheLookupAll[aName]].contintentId][WaypointCacheLookupAll[aName]] = nil
		end
		tWpIndex = WaypointCacheLookupAll[aName]
		if WaypointCache[tWpIndex].typeId ~= 1 then
			tIsNew = true
		end
	else
		if not string.find(aName, L["Quick waypoint"]) then
			tWpIndex = #WaypointCache + 1
			WaypointCache[tWpIndex] = {
				name = aName,
				typeId = 1,
			}
			tIsNew = true
		else
			print("ERROR - THIS SHOULD NOT HAPPEN:")
			print("tried to add quick waypoint as new waypoint", aName)
			return
		end
	end
	
	if (not aData.contintentId and not WaypointCache[tWpIndex].contintentId) == true or (not aData.contintentId and not WaypointCache[tWpIndex].contintentId) == true then
		print("ERROR - THIS SHOULD NOT HAPPEN:")
		print("SetWaypoint", aData)
		print("no areaid, nocontinentid")
		return
	end

	WaypointCache[tWpIndex].name = aName
	WaypointCache[tWpIndex].role = aData.role or WaypointCache[tWpIndex].role or ""
	WaypointCache[tWpIndex].typeId = 1
	WaypointCache[tWpIndex].spawn = 1
	WaypointCache[tWpIndex].contintentId = aData.contintentId or WaypointCache[tWpIndex].contintentId
	WaypointCache[tWpIndex].areaId = aData.areaId or WaypointCache[tWpIndex].areaId
	WaypointCache[tWpIndex].uiMapId = SkuNav:GetUiMapIdFromAreaId(aData.areaId) or WaypointCache[tWpIndex].uiMapId
	WaypointCache[tWpIndex].worldX = aData.worldX or WaypointCache[tWpIndex].worldX
	WaypointCache[tWpIndex].worldY = aData.worldY or WaypointCache[tWpIndex].worldY
	WaypointCache[tWpIndex].createdAt = GetTime()--aData.createdAt or WaypointCache[tWpIndex].createdAt or 0
	WaypointCache[tWpIndex].createdBy = aData.createdBy or WaypointCache[tWpIndex].createdBy or "SkuNav"
	WaypointCache[tWpIndex].size = aData.size or WaypointCache[tWpIndex].size or 1
	WaypointCache[tWpIndex].comments = aData.comments or WaypointCache[tWpIndex].comments or {
		["deDE"] = {},
		["enUS"] = {},
	}
	WaypointCache[tWpIndex].links = aData.links or WaypointCache[tWpIndex].links or {byId = nil, byName = nil,}

	WaypointCacheLookupAll[aName] = tWpIndex

	if not WaypointCacheLookupPerContintent[WaypointCache[tWpIndex].contintentId] then
		WaypointCacheLookupPerContintent[WaypointCache[tWpIndex].contintentId] = {}
	end
	WaypointCacheLookupPerContintent[WaypointCache[tWpIndex].contintentId][tWpIndex] = aName

	if tIsNew then
		table.insert(SkuOptions.db.global[MODULE_NAME].Waypoints, {
			["names"] = {
				[Sku.Loc] = WaypointCache[tWpIndex].name,
				[(Sku.Loc == "enUS" and "deDE" or "enUS")] = "UNTRANSLATED "..WaypointCache[tWpIndex].name,
			},
			["contintentId"] = WaypointCache[tWpIndex].contintentId,
			["areaId"] = WaypointCache[tWpIndex].areaId,
			["worldX"] = WaypointCache[tWpIndex].worldX,
			["worldY"] = WaypointCache[tWpIndex].worldY,
			["createdAt"] = GetTime(),--WaypointCache[tWpIndex].createdAt,
			["createdBy"] = WaypointCache[tWpIndex].createdBy,
			["size"] = WaypointCache[tWpIndex].size,
			["lComments"] = {
				["deDE"] = {},
				["enUS"] = {},
			},
		})

		WaypointCache[tWpIndex].dbIndex = #SkuOptions.db.global[MODULE_NAME].Waypoints

		WaypointCacheLookupCacheNameForId[aName] = SkuNav:BuildWpIdFromData(1, WaypointCache[tWpIndex].dbIndex, 1, WaypointCache[tWpIndex].areaId)

		if not string.find(WaypointCache[tWpIndex].name, L["Quick waypoint"]) then
			for i, v in pairs(Sku.Locs) do
				if v ~= Sku.Loc then
					SkuOptions.db.global[MODULE_NAME].Waypoints[WaypointCache[tWpIndex].dbIndex].names[v] = "UNTRANSLATED "..WaypointCache[tWpIndex].name
				end
			end
		end
	else
		local tWpId = WaypointCache[tWpIndex].dbIndex
		SkuOptions.db.global[MODULE_NAME].Waypoints[tWpId]["names"][Sku.Loc] = WaypointCache[tWpIndex].name

		if SkuOptions.db.global[MODULE_NAME].Waypoints[tWpId]["names"][Sku.Loc] ~= aName then
			SkuOptions.db.global[MODULE_NAME].Waypoints[tWpId]["names"][(Sku.Loc == "enUS" and "deDE" or "enUS")] = "UNTRANSLATED "..WaypointCache[tWpIndex].name
		end
		SkuOptions.db.global[MODULE_NAME].Waypoints[tWpId]["contintentId"] = WaypointCache[tWpIndex].contintentId 
		SkuOptions.db.global[MODULE_NAME].Waypoints[tWpId]["areaId"] = WaypointCache[tWpIndex].areaId
		SkuOptions.db.global[MODULE_NAME].Waypoints[tWpId]["worldX"] = WaypointCache[tWpIndex].worldX
		SkuOptions.db.global[MODULE_NAME].Waypoints[tWpId]["worldY"] = WaypointCache[tWpIndex].worldY
		SkuOptions.db.global[MODULE_NAME].Waypoints[tWpId]["createdAt"] = GetTime()--WaypointCache[tWpIndex].createdAt
		SkuOptions.db.global[MODULE_NAME].Waypoints[tWpId]["createdBy"] = WaypointCache[tWpIndex].createdBy
		SkuOptions.db.global[MODULE_NAME].Waypoints[tWpId]["size"] = WaypointCache[tWpIndex].size
		SkuOptions.db.global[MODULE_NAME].Waypoints[tWpId]["lComments"] = WaypointCache[tWpIndex].comments
	end	

	SkuNav:UpdateWpLinks(aName)
end

---------------------------------------------------------------------------------------------------------------------------------------
local GetNpcRolesCache = {}
function SkuNav:GetNpcRoles(aNpcName, aNpcId, aLocale)
	aLocale = aLocale or Sku.Loc
	if not aNpcId then
		for i, v in pairs(SkuDB.NpcData.Names[aLocale]) do
			if v[1] == aNpcName then
				aNpcId = i
				break
			end
		end
	end

	local tHasNoLocalizedData
	if not aNpcId then
		tHasNoLocalizedData = true
		for i, v in pairs(SkuDB.NpcData.Data) do
			if v[1] == aNpcName then
				aNpcId = i
				break
			end
		end
	end	

	if not GetNpcRolesCache[aLocale] then
		GetNpcRolesCache[aLocale] = {}
	end

	if GetNpcRolesCache[aLocale][aNpcId] then
		return GetNpcRolesCache[aLocale][aNpcId]
	end

	local rRoles = {}
	local tTempLocale = aLocale
	if tHasNoLocalizedData then
		tTempLocale = "enUS"
	end

	for i, v in pairs(SkuNav.NPCRolesToRecognize[tTempLocale]) do
		if SkuDB.NpcData.Data[aNpcId] then
			if bit.band(i, SkuDB.NpcData.Data[aNpcId][SkuDB.NpcData.Keys["npcFlags"]]) > 0 then
				rRoles[#rRoles+1] = v
			end
		end
	end

	GetNpcRolesCache[aLocale][aNpcId] = rRoles
	return rRoles
end

------------------------------------------------------------------------------------------------------------------------
function SkuNav:DeleteWaypoint(aWpName, aIsTempWaypoint, aSilent)
	--print("DeleteWaypoint", aWpName, aIsTempWaypoint)
	local tWpData = SkuNav:GetWaypointData2(aWpName)
	local tWpId = WaypointCacheLookupCacheNameForId[aWpName]
	
	if not tWpData then
		return false
	end

	if tWpData.typeId ~= 1 then
		print("Only custom waypoints can be deleted")
		SkuNav:PlayFailSound()
		return false
	end


	local tCacheIndex = WaypointCacheLookupAll[aWpName] 
	if not SkuOptions.db.global[MODULE_NAME].Waypoints[tWpData.dbIndex] then
		print("Error: waypoint nil in db")
		SkuNav:PlayFailSound()
	else


		--remove from links db
		--remove links in linked wps in cache
		local tLinkNames = {}
		if tWpData.links.byName then
			for name, distance in pairs(tWpData.links.byName) do
				tLinkNames[#tLinkNames + 1] = name
			end
		end
		for x = 1, #tLinkNames do


			SkuNav:DeleteWpLink(aWpName, tLinkNames[x])
		end

		--add to history
		SkuNav:History_Generic("Delete waypoint", function(self, tWpData, uid, aWpName, tCacheIndex, dbData)
			WaypointCache[tCacheIndex] = tWpData	
			WaypointCacheLookupIdForCacheIndex[uid] = tCacheIndex
			WaypointCacheLookupCacheNameForId[aWpName] = uid
			WaypointCacheLookupPerContintent[tWpData.contintentId][tCacheIndex] = aWpName
			WaypointCacheLookupAll[aWpName] = tCacheIndex
			WaypointCache[tCacheIndex] = tWpData
			SkuOptions.db.global[MODULE_NAME].Waypoints[tWpData.dbIndex] = dbData
			SkuNav:SaveLinkDataToProfile()
		end,
		tWpData,
		SkuNav:BuildWpIdFromData(WaypointCache[tCacheIndex].typeId, WaypointCache[tCacheIndex].dbIndex, WaypointCache[tCacheIndex].spawn, WaypointCache[tCacheIndex].areaId),
		aWpName,
		tCacheIndex,
		SkuOptions.db.global[MODULE_NAME].Waypoints[tWpData.dbIndex]
		)



		WaypointCacheLookupIdForCacheIndex[SkuNav:BuildWpIdFromData(WaypointCache[tCacheIndex].typeId, WaypointCache[tCacheIndex].dbIndex, WaypointCache[tCacheIndex].spawn, WaypointCache[tCacheIndex].areaId)] = nil
		WaypointCacheLookupCacheNameForId[aWpName] = nil
		WaypointCacheLookupPerContintent[tWpData.contintentId][tCacheIndex] = nil
		WaypointCacheLookupAll[aWpName] = nil
		WaypointCache[tCacheIndex] = nil

		--delete from waypoint db
		SkuOptions.db.global[MODULE_NAME].Waypoints[tWpData.dbIndex] = {false}

		if not aSilent then
			SkuNav:PlaySoundFile("Interface\\AddOns\\SkuMapper\\audio\\sound-notification15.mp3")
		end
	end
	
	SkuNav:SaveLinkDataToProfile()

	return true
end

------------------------------------------------------------------------------------------------------------------------
--id bitfield: int64, bits 1-48 used
local dbIndexBits = 20 -- 1-20, max 1,048,576 entries for all waypoints from base1-3
local areaIdBits	= 18 -- 21-38, max 262,144 entries
local spawnBits	= 10 -- 39, 48, max 1,024 entries
--dbIndexBits is splitted
local base1 		= 0			--custom waypoints 1-199,999
local base2 		= 200000		--creatures 200,000-499,999
local base3 		= 500000		--objects 500,000-999,999

------------------------------------------------------------------------------------------------------------------------
function SkuNav:BuildWpIdFromData(typeId, dbIndex, spawn, areaId)
	areaId = areaId or 1
	local tSourceId

	local tBase
	if typeId == 1 then
		tBase = base1
	elseif typeId == 2 then
		tBase = base2
	elseif typeId == 3 then
		tBase = base3
	end

	local vspawnShifted = SkuU64lshift(spawn, dbIndexBits + areaIdBits)
	local vareaIdShifted = SkuU64lshift(areaId, dbIndexBits)
	
	tSourceId = dbIndex + tBase + vareaIdShifted + vspawnShifted
	
	return tSourceId
end

------------------------------------------------------------------------------------------------------------------------
function SkuNav:GetWpDataFromId(id)
	local typeId, dbIndex, spawn, areaId

	spawn = SkuU64rshift(id, dbIndexBits + areaIdBits)
	areaId = SkuU64rshift(id - SkuU64lshift(spawn, dbIndexBits + areaIdBits), dbIndexBits)
	dbIndex = id - SkuU64lshift(areaId, dbIndexBits) - SkuU64lshift(spawn, dbIndexBits + areaIdBits)

	if dbIndex < base2 then
		typeId = 1
	elseif dbIndex < base3 then
		typeId = 2
		dbIndex = dbIndex - base2
	else
		typeId = 3
		dbIndex = dbIndex - base3
	end	

	return typeId, dbIndex, spawn, areaId
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:OnCancelRecording()
	SkuNav:EndRouteRecording(SkuOptions.db.profile[MODULE_NAME].routeRecordingLastWp)
	SkuOptions.db.profile[MODULE_NAME].routeRecordingLastWp = nil

	SkuOptions.db.profile[MODULE_NAME].routeRecording = false
	SkuOptions.db.profile[MODULE_NAME].routeRecordingDelete = false

	SkuNav:PlaySoundFile("Interface\\AddOns\\SkuMapper\\audio\\sound-notification12.mp3")
	print("Recording/deleting stopped or canceled")
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:PlayFailSound()
	SkuNav:PlaySoundFile("Interface\\AddOns\\SkuMapper\\audio\\sound-glass1.mp3", true)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:PlaySoundFile(aFileName, aIsFail)
	if SkuOptions.db.profile[MODULE_NAME].enableSounds ~= false then
		PlaySoundFile(aFileName)
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:NEW_WMO_CHUNK(aEvent)
	SkuNav:UpdateAutoPrefixes(aEvent)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:ZONE_CHANGED(aEvent)
	SkuNav:UpdateAutoPrefixes(aEvent)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:ZONE_CHANGED_INDOORS(aEvent)
	SkuNav:UpdateAutoPrefixes(aEvent)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:ZONE_CHANGED_NEW_AREA(aEvent)
	SkuNav:UpdateAutoPrefixes(aEvent)
end

---------------------------------------------------------------------------------------------------------------------------------------
local tIgnoreFirst = 0
function SkuNav:UpdateAutoPrefixes(aEvent, aZoneId)
	local tGetZoneText  = GetZoneText()
	if aZoneId then
		tGetZoneText = SkuDB.InternalAreaTable[aZoneId].AreaName_lang[Sku.Loc]
	end
	local tGetSubZoneText  = GetSubZoneText()

	if tGetSubZoneText and tGetSubZoneText ~= "" and tGetSubZoneText == tGetZoneText then
		tGetSubZoneText = ""
	end

	local tInOutTexts = {
		["deDE"] = "Drinnen",
		["enUS"] = "Inside",
	}

	if _G["SkuNavMMMainFrameSuffixAuto"..Sku.Loc.."EditBoxEditBox"] then
		local tInOut = ""
		if IsIndoors() == true then
			tInOut = tInOutTexts[Sku.Loc]..";"
		end

		if aZoneId then
			local tAutoCurrentLocaleText = tGetZoneText
			_G["SkuNavMMMainFrameSuffixAuto"..Sku.Loc.."EditBoxEditBox"]:SetText(tAutoCurrentLocaleText)
		else
			local tAutoCurrentLocaleText = tInOut..(_G["SkuNavMMMainFrameSuffixCustom"..Sku.Loc.."EditBoxEditBox"]:GetText() ~= "" and _G["SkuNavMMMainFrameSuffixCustom"..Sku.Loc.."EditBoxEditBox"]:GetText()..";" or "")..(tGetSubZoneText ~= "" and tGetSubZoneText..";" or "")..tGetZoneText
			_G["SkuNavMMMainFrameSuffixAuto"..Sku.Loc.."EditBoxEditBox"]:SetText(tAutoCurrentLocaleText)
		end


		local tZoneAreaId = SkuNav:GetAreaIdFromAreaName(tGetZoneText, true)
		local tSubZoneAreaId = SkuNav:GetAreaIdFromAreaName(tGetSubZoneText, true)
		local tOtherLoc = Sku.Loc == "enUS" and "deDE" or "enUS"

		tInOut = ""
		if IsIndoors() == true then
			tInOut = tInOutTexts[tOtherLoc]..";"
		end

		if aZoneId then
			local tGetZoneTextOtherLoc = GetZoneText()
			if SkuDB.InternalAreaTable[aZoneId] then
				tGetZoneTextOtherLoc = SkuDB.InternalAreaTable[aZoneId].AreaName_lang[tOtherLoc]
			end
			_G["SkuNavMMMainFrameSuffixAuto"..tOtherLoc.."EditBoxEditBox"]:SetText(tGetZoneTextOtherLoc)
		else
			local tGetZoneTextOtherLoc = GetZoneText()
			if tZoneAreaId and SkuDB.InternalAreaTable[tZoneAreaId] then
				tGetZoneTextOtherLoc = SkuDB.InternalAreaTable[tZoneAreaId].AreaName_lang[tOtherLoc]
			end

			local tGetSubZoneTextOtherLoc = GetSubZoneText()		
			if tSubZoneAreaId and SkuDB.InternalAreaTable[tSubZoneAreaId] then
				tGetSubZoneTextOtherLoc = SkuDB.InternalAreaTable[tSubZoneAreaId].AreaName_lang[tOtherLoc]
			end

			if tGetSubZoneTextOtherLoc and tGetSubZoneTextOtherLoc ~= "" and tGetSubZoneTextOtherLoc == tGetZoneTextOtherLoc then
				tGetSubZoneTextOtherLoc = ""
			end

			local tAutoOtherLocaleText = tInOut..(_G["SkuNavMMMainFrameSuffixCustom"..tOtherLoc.."EditBoxEditBox"]:GetText() ~= "" and _G["SkuNavMMMainFrameSuffixCustom"..tOtherLoc.."EditBoxEditBox"]:GetText()..";" or "")..(tGetSubZoneTextOtherLoc ~= "" and tGetSubZoneTextOtherLoc..";" or "")..tGetZoneTextOtherLoc
			_G["SkuNavMMMainFrameSuffixAuto"..tOtherLoc.."EditBoxEditBox"]:SetText(tAutoOtherLocaleText)
		end

	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:UpdateAutoName(aOldName, aNewName)
	--print("UpdateAutoName(aOldName, aNewName)", aOldName, aNewName)
	local tNewName = SkuNav:GetWaypointData2(aNewName)
	if tNewName then
		print("ERROR: This should not happen! Name already exists.")
		return false
	end

	local tWpData = SkuNav:GetWaypointData2(aOldName)

	if tWpData.typeId ~= 1 then
		print("only custom waypoints can be renamed")
		return
	end

	--save links
	local tLinks = {}
	if tWpData.links.byName then
		for name, distance in pairs(tWpData.links.byName) do
			tLinks[name] = distance
		end
	end

	--delete aOlddName
	SkuNav:DeleteWaypoint(aOldName, nil, true)

	--create aNewName
	SkuNav:CreateWaypoint(aNewName, tWpData.worldX, tWpData.worldY, tWpData.size, nil, nil, true, nil, true)
	SkuNav:SetWaypoint(aNewName, tWpData)
	SkuNav:History_Generic("Update Auto Name", SkuNav.DeleteWaypoint, aNewName, nil, nil)

	--create links
	for name, distance in pairs(tLinks) do
		SkuNav:CreateWpLink(aNewName, name)
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
--/script SkuNav:BatchRenameAutoToZone()
function SkuNav:BatchRenameAutoToZone()
	SkuOptions.db.global[MODULE_NAME].SequenceNumbers = SkuOptions.db.global[MODULE_NAME].SequenceNumbers or {}
	--SkuOptions.db.global[MODULE_NAME].SequenceNumbers = {}

	local tx = 0
	for x = 1, #SkuOptions.db.global["SkuNav"].Waypoints do
		local tWpData = SkuOptions.db.global["SkuNav"].Waypoints[x]
		if tWpData and tWpData.areaId and tWpData.names and SkuDB.InternalAreaTable[tWpData.areaId] then
			if string.find(tWpData.names[Sku.Loc], L["auto"]..";") then
				tx = tx + 1
				local tNameStringDe = SkuDB.InternalAreaTable[tWpData.areaId].AreaName_lang["deDE"]
				local tNameStringEn = SkuDB.InternalAreaTable[tWpData.areaId].AreaName_lang["enUS"]
				local tCurrentParent = SkuDB.InternalAreaTable[tWpData.areaId].ParentAreaID

				local tLastDe = tNameStringDe
				local tLastEn = tNameStringEn
				while not SkuDB.ContinentIds[tCurrentParent] do
					if tLastDe ~= SkuDB.InternalAreaTable[tCurrentParent].AreaName_lang["deDE"] then
						tNameStringDe = tNameStringDe..";"..SkuDB.InternalAreaTable[tCurrentParent].AreaName_lang["deDE"]
						tLastDe = SkuDB.InternalAreaTable[tCurrentParent].AreaName_lang["deDE"] 
					end
					
					if tLastEn ~= SkuDB.InternalAreaTable[tCurrentParent].AreaName_lang["enUS"] then
						tNameStringEn = tNameStringEn..";"..SkuDB.InternalAreaTable[tCurrentParent].AreaName_lang["enUS"]
						tLastEn = SkuDB.InternalAreaTable[tCurrentParent].AreaName_lang["enUS"] 
					end
					
					tCurrentParent = SkuDB.InternalAreaTable[tCurrentParent].ParentAreaID
				end

				local tSequenceNumber = SkuNav:GetSequenceNumber(tWpData.areaId)
				--print(x)

				SkuOptions.db.global["SkuNav"].Waypoints[x].names["deDE"] = "auto "..tNameStringDe..";"..tSequenceNumber
				--print(" ", SkuOptions.db.global["SkuNav"].Waypoints[x].names["deDE"])

				SkuOptions.db.global["SkuNav"].Waypoints[x].names["enUS"] = "auto "..tNameStringEn..";"..tSequenceNumber
				--print(" ", SkuOptions.db.global["SkuNav"].Waypoints[x].names["enUS"])
			end
		end
	end

	print("done:", tx)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:GetSequenceNumber(aAreaId)	
	if aAreaId == 100077 or aAreaId == 4395 or aAreaId == 4613 then
		--dalaran
		if SkuOptions.db.global[MODULE_NAME].SequenceNumbers[100077] == nil then
			SkuOptions.db.global[MODULE_NAME].SequenceNumbers[100077] = 0
		end
		SkuOptions.db.global[MODULE_NAME].SequenceNumbers[100077] = SkuOptions.db.global[MODULE_NAME].SequenceNumbers[100077] + 1
		if SkuOptions.db.global[MODULE_NAME].SequenceNumbers[4395] == nil then
			SkuOptions.db.global[MODULE_NAME].SequenceNumbers[4395] = 0
		end
		SkuOptions.db.global[MODULE_NAME].SequenceNumbers[4395] = SkuOptions.db.global[MODULE_NAME].SequenceNumbers[4395] + 1
		if SkuOptions.db.global[MODULE_NAME].SequenceNumbers[4613] == nil then
			SkuOptions.db.global[MODULE_NAME].SequenceNumbers[4613] = 0
		end
		SkuOptions.db.global[MODULE_NAME].SequenceNumbers[4613] = SkuOptions.db.global[MODULE_NAME].SequenceNumbers[4613] + 1
	else
		if SkuOptions.db.global[MODULE_NAME].SequenceNumbers[aAreaId] == nil then
			SkuOptions.db.global[MODULE_NAME].SequenceNumbers[aAreaId] = 0
		end
		SkuOptions.db.global[MODULE_NAME].SequenceNumbers[aAreaId] = SkuOptions.db.global[MODULE_NAME].SequenceNumbers[aAreaId] + 1
	end

	return SkuOptions.db.global[MODULE_NAME].SequenceNumbers[aAreaId]
end

---------------------------------------------------------------------------------------------------------------------------------------
--[[
	Ignore this. It's old stuff for creating wps with clicking on the map.
	Just here to keep it if it should be relevant in future.

	---------------------------------------------------------------------------------------------------------------------------------------
	function SkuNav:GetAreaIdFromWorldCoords(aWorldX, aWorldY, aName, aCreateLinkFunc)
		--print("SkuNav:GetAreaIdFromWorldCoords(", aWorldX, aWorldY, aName, aCreateLinkFunc)
		local tPlayerContintentId = select(3, SkuNav:GetAreaData(SkuNav:GetCurrentAreaId()))
		local aAreaIds = {}

		for i, v in pairs(SkuDB.ExternalMapID) do
			if tonumber(v.Type) == 3 then
				local name, _, tAContiId = SkuNav:GetAreaData((v.AreaId))
				if tAContiId == tPlayerContintentId then
					local uiMapID, mapPosition  = C_Map.GetMapPosFromWorldPos(tPlayerContintentId, CreateVector2D(aWorldX, aWorldY), i)
					if mapPosition.x <= 0.94 and mapPosition.x >= 0.06 and mapPosition.y <= 0.94 and mapPosition.y >= 0.06 then
						aAreaIds[#aAreaIds + 1] = SkuNav:GetAreaIdFromUiMapId(uiMapID) --or SkuNav:GetCurrentAreaId()
					end
				end
			end
		end
		
		if #aAreaIds == 0 then
			--print("---------------#aAreaIds == 0")
			aAreaIds[1] = SkuNav:GetCurrentAreaId()
		end
		--print("############## aAreaIds[1]", aAreaIds[1])
		SkuNav:ShowZoneSelector(aAreaIds, aName, aCreateLinkFunc)
	end

	---------------------------------------------------------------------------------------------------------------------------------------
	local tSelectorWidth = 200
	function SkuNav:ShowZoneSelector(aAreaIds, aName, aCreateLinkFunc)
		--print("ShowZoneSelector(aAreaIds, aName, aCreateLinkFunc)", aAreaIds, aName, aCreateLinkFunc)
		local function helper(aAreaId, aName, aCreateLinkFunc)
			--print("helper(aAreaIds, aName, aCreateLinkFunc)", aAreaId, aName, aCreateLinkFunc)
			SkuNav:SetWaypoint(aName, {areaId = aAreaId,})
			--print("pre UpdateAutoPrefixes", _G["SkuNavMMMainFrameSuffixAuto"..Sku.Loc.."EditBoxEditBox"]:GetText())
			SkuNav:UpdateAutoPrefixes(nil, aAreaId)
			--print("post UpdateAutoPrefixes", _G["SkuNavMMMainFrameSuffixAuto"..Sku.Loc.."EditBoxEditBox"]:GetText())

			SkuOptions.db.global[MODULE_NAME].SequenceNumbers = SkuOptions.db.global[MODULE_NAME].SequenceNumbers or {}
			SkuOptions.db.global[MODULE_NAME].SequenceNumbers[aAreaId] = SkuOptions.db.global[MODULE_NAME].SequenceNumbers[aAreaId] or 0
			SkuOptions.db.global[MODULE_NAME].SequenceNumbers[aAreaId] = SkuOptions.db.global[MODULE_NAME].SequenceNumbers[aAreaId] + 1
			local tNewNameLoc = L["auto"].." ".._G["SkuNavMMMainFrameSuffixAuto"..Sku.Loc.."EditBoxEditBox"]:GetText()..";"..SkuOptions.db.global[MODULE_NAME].SequenceNumbers[aAreaId]
			--print("tNewNameLoc", tNewNameLoc)
			SkuNav:UpdateAutoName(aName, tNewNameLoc)
			
			local tWP = SkuNav:GetWaypointData2(tNewNameLoc)
			local tNewName = L["auto"].." ".._G["SkuNavMMMainFrameSuffixAuto"..(Sku.Loc == "enUS" and "deDE" or "enUS").."EditBoxEditBox"]:GetText()..";"..SkuOptions.db.global[MODULE_NAME].SequenceNumbers[aAreaId]
			SkuOptions.db.global[MODULE_NAME].Waypoints[tWP.dbIndex].names[(Sku.Loc == "enUS" and "deDE" or "enUS")] = tNewName

			SkuNav:UpdateAutoPrefixes(true)

			if aCreateLinkFunc then
				aCreateLinkFunc(tNewNameLoc)
			end
		end

		if not _G["SkuNavZoneSelector"] then
			local MainFrameObj = CreateFrame("Frame", "SkuNavZoneSelector", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
			MainFrameObj:SetFrameStrata("TOOLTIP")
			MainFrameObj:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
			MainFrameObj:SetHeight(154) --275
			MainFrameObj:SetWidth(tSelectorWidth + 4)
			MainFrameObj:EnableMouse(true)
			MainFrameObj:SetScript("OnDragStart", function(self) self:StartMoving() end)
			MainFrameObj:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
			MainFrameObj:SetScript("OnShow", function(self) end)			
			MainFrameObj:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background", edgeFile="", tile = false, tileSize = 0, edgeSize = 0, insets = { left = 0, right = 0, top = 0, bottom = 0 }})
			MainFrameObj:SetBackdropColor(1, 1, 1, 1)
			MainFrameObj:SetMovable(true)
			MainFrameObj:SetClampedToScreen(true)
			MainFrameObj:RegisterForDrag("LeftButton")
			for x = 1, 10 do
				SkuNav:CreateButtonFrameTemplate("SkuNavZoneSelectorButton"..x, MainFrameObj, "Button"..x, tSelectorWidth, 17, "TOPLEFT", MainFrameObj, "TOPLEFT", 2, -(((x - 1) * 15) + 2))
			end
		end

		if #aAreaIds > 1 then
			--print("aAreaIds > 1")
			_G["SkuNavZoneSelector"]:SetHeight((#aAreaIds * 15) + 4)

			for x = 1, 10 do
				_G["SkuNavZoneSelectorButton"..x].areaId = nil
				_G["SkuNavZoneSelectorButton"..x]:Hide()
			end

			local tCurrentZoneButtonNumber = 0
			for i, aId in pairs(aAreaIds) do
				local _, tzName = SkuNav:GetAreaData(aId)
				if SkuNav:GetCurrentAreaId() == aId then
					tCurrentZoneButtonNumber = i
					_G["SkuNavZoneSelectorButton"..i]:SetText("(Current) "..tzName.." ("..aId..")")
					_G["SkuNavZoneSelectorButton"..i].Text:SetTextColor(1, 0.5, 0.5, 1)

				else
					_G["SkuNavZoneSelectorButton"..i]:SetText(tzName.." ("..aId..")")
					_G["SkuNavZoneSelectorButton"..i].Text:SetTextColor(1, 1, 1, 1)
				end

				_G["SkuNavZoneSelectorButton"..i].areaId = aId
				_G["SkuNavZoneSelectorButton"..i].waypointName = aName
				_G["SkuNavZoneSelectorButton"..i]:SetScript("OnMouseUp", function(self, button) 
					self:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background", edgeFile="", tile = false, tileSize = 0, edgeSize = 0, insets = { left = 2, right = 2, top = 2, bottom = 2 }})
					self:SetBackdropColor(0.3, 0.3, 0.3, 1)
					if self.selected == true then
						self:SetBackdropColor(0.5, 0.5, 0.5, 1)
					end
					helper(aId, aName, aCreateLinkFunc)
					_G["SkuNavZoneSelector"]:Hide()
				end)				
				_G["SkuNavZoneSelectorButton"..i]:Show()
			end

			local uiScale, x, y = UIParent:GetEffectiveScale(), GetCursorPosition()
			_G["SkuNavZoneSelector"]:ClearAllPoints()
			_G["SkuNavZoneSelector"]:SetPoint("TOP", nil, "BOTTOMLEFT", x / uiScale, (y / uiScale) + (((tCurrentZoneButtonNumber * 15) - 7) / uiScale))
			_G["SkuNavZoneSelector"]:Show()

		else
			--print("aAreaIds == 1", aAreaIds[1])
			_G["SkuNavZoneSelector"]:Hide()
			C_Timer.After(0.01, function()
				helper(aAreaIds[1], aName, aCreateLinkFunc)
			end)
		end
	end
]]

---------------------------------------------------------------------------------------------------------------------------------------
-- the below are helpers to one time clean up old lk map data for cata
---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:isOnContintentZeroOrOne(aWpData)	
	if not SkuDB.InternalAreaTable[aWpData.areaId] then
		--print("Error SkuDB.InternalAreaTable[aWpData.areaId] nil", aWpData.areaId, "missing in SkuDB.InternalAreaTable")
		return false
	end

	if aWpData.areaId == 33 then
		return true
	end
--[[
	local tKeep = {
		[493] = true, --"Moonglade",
		[1638] = true, --"ThunderBluff"
		[1497] = true, -- "Undercity"
    	[1537] = true, --"Ironforge"
	}
	if tKeep[aWpData.areaId] then
		return false
	end

	if SkuDB.InternalAreaTable[aWpData.areaId].ContinentID == 0 and SkuDB.InternalAreaTable[aWpData.areaId].ParentAreaID == 0 then
		return true
	end

	if SkuDB.InternalAreaTable[aWpData.areaId].ContinentID == 1 and SkuDB.InternalAreaTable[aWpData.areaId].ParentAreaID == 0 then
		return true
	end
]]
	return false
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:CleanUpPreCataMapData()	
	local del_1_wps, del_1_links, del_23_links = 0, 0, 0

	for i, tWpData in pairs(WaypointCache) do
		if SkuNav:isOnContintentZeroOrOne(tWpData) == true then
			--print("deleting", tWpData.areaId, tWpData.name)

			local aWpName = tWpData.name
			local tCacheIndex = WaypointCacheLookupAll[aWpName] 

			local uid = SkuNav:BuildWpIdFromData(tWpData.typeId, tWpData.dbIndex, tWpData.spawn, tWpData.areaId)
			if SkuOptions.db.global["SkuNav"].WaypointLevels[uid] then
				print(aWpName, SkuOptions.db.global["SkuNav"].WaypointLevels[uid])
				SkuOptions.db.global["SkuNav"].WaypointLevels[uid] = nil
			end
			if tWpData.typeId == 1 then
				if not SkuOptions.db.global[MODULE_NAME].Waypoints[tWpData.dbIndex] then
					print("Error: waypoint nil in db", i, tWpData.typeId, aWpName, tWpData.dbIndex)
					SkuNav:PlayFailSound()
					return
				end
				
				--delete links
				local tLinkNames = {}
				if tWpData.links.byName then
					for name, distance in pairs(tWpData.links.byName) do
						tLinkNames[#tLinkNames + 1] = name
					end
				end
				for x = 1, #tLinkNames do
					del_1_links = del_1_links + 1
					SkuNav:DeleteWpLink(aWpName, tLinkNames[x])
				end

				--delete wp
				del_1_wps = del_1_wps + 1
				WaypointCacheLookupIdForCacheIndex[SkuNav:BuildWpIdFromData(WaypointCache[tCacheIndex].typeId, WaypointCache[tCacheIndex].dbIndex, WaypointCache[tCacheIndex].spawn, WaypointCache[tCacheIndex].areaId)] = nil
				WaypointCacheLookupCacheNameForId[aWpName] = nil
				WaypointCacheLookupPerContintent[tWpData.contintentId][tCacheIndex] = nil
				WaypointCacheLookupAll[aWpName] = nil
				WaypointCache[tCacheIndex] = nil

				--delete from waypoint db
				SkuOptions.db.global[MODULE_NAME].Waypoints[tWpData.dbIndex] = {false}
				

			elseif tWpData.typeId == 2 or tWpData.typeId == 3 then
				--print("   2 or 3, links only")
				
				--delete links
				if SkuNav:isOnContintentZeroOrOne(tWpData) == true then
					local tLinkNames = {}
					if tWpData.links.byName then
						for name, distance in pairs(tWpData.links.byName) do
							tLinkNames[#tLinkNames + 1] = name
						end
					end
					for x = 1, #tLinkNames do
						del_23_links = del_23_links + 1
						SkuNav:DeleteWpLink(aWpName, tLinkNames[x])
					end
				end
			end

			
		end

	end

	SkuNav:SaveLinkDataToProfile()
	
	--tExportDataTable.WaypointLevels = SkuOptions.db.global["SkuNav"].WaypointLevels or {}

end

---------------------------------------------------------------------------------------------------------------------------------------
---test for import of bs map data
local MapWayData1=[[
/way 45.55 12.15 Durotar Main Road 1 @ Gates of Orgrimmar >
/way 45.68 13.38 Durotar Main Road 2 crossroadsRocktusk
/way 45.86 14.04 Durotar Main Road 3 crossroadsBlockade !Holgar Stormaxe
/way 46.04 14.91 Durotar Main Road 4
/way 46.41 16.11 Durotar Main Road 5
/way 45.84 16.20 Durotar Main Road 5.1
/way 45.37 16.29 Durotar Main Road 5.2 narrow 
/way 45.46 16.11 Durotar Main Road 5.3 narrow 
/way 45.56 15.89 Durotar Main Road 5.4
/way 45.68 15.84 Durotar Main Road 5.5 @ Funeral pyre end
/way 46.08 17.46 Durotar Main Road 6
/way 46.82 17.30 Durotar Main Road 6.1
/way 47.36 17.86 Durotar Main Road 6.2 end
/way 46.27 18.43 Durotar Main Road 7
/way 46.44 19.80 Durotar Main Road 8
/way 46.60 21.19 Durotar Main Road 9
/way 46.86 22.46 Durotar Main Road 10 crossroadsDrygulch1
/way 47.49 23.75 Durotar Main Road 11
/way 47.88 25.10 Durotar Main Road 12
/way 48.14 26.25 Durotar Main Road 13
/way 48.44 27.58 Durotar Main Road 14
/way 48.85 28.67 Durotar Main Road 15
/way 49.59 29.19 Durotar Main Road 16 crossroadsDrygulch2
/way 50.32 29.70 Durotar Main Road 17
/way 50.89 30.50 Durotar Main Road 18
/way 51.33 31.23 Durotar Main Road 19 crossroadsRazorwind2
/way 51.86 32.24 Durotar Main Road 20
/way 52.33 33.33 Durotar Main Road 21
/way 52.41 34.43 Durotar Main Road 22
/way 52.40 35.64 Durotar Main Road 23
/way 52.38 37.02 Durotar Main Road 24
/way 52.42 38.31 Durotar Main Road 25
/way 52.36 39.49 Durotar Main Road 26
/way 52.43 40.57 Durotar Main Road 27
/way 52.44 41.56 Durotar Main Road 28 crossroadsDeadeye2
/way 52.80 42.60 Durotar Main Road 29 @ crossroadsRazorHill Profession Trainer !Runda
/way 52.67 43.30 Durotar Main Road 30 Flight Master !Burok
/way 52.46 44.53 Durotar Main Road 31
/way 52.59 45.37 Durotar Main Road 32 crossroadsScuttle1
/way 52.82 46.56 Durotar Main Road 33
/way 53.02 47.49 Durotar Main Road 34
/way 52.71 48.31 Durotar Main Road 35
/way 52.55 49.27 Durotar Main Road 36
/way 52.59 50.24 Durotar Main Road 37
/way 52.67 51.53 Durotar Main Road 38
/way 52.67 52.74 Durotar Main Road 39
/way 52.70 53.98 Durotar Main Road 40
/way 52.84 55.05 Durotar Main Road 41
/way 53.07 56.15 Durotar Main Road 42
/way 53.28 57.16 Durotar Main Road 43 crossroadsTiragarde1
/way 53.51 58.51 Durotar Main Road 44
/way 53.68 59.69 Durotar Main Road 45
/way 53.83 60.81 Durotar Main Road 46
/way 53.91 61.65 Durotar Main Road 47
/way 53.69 62.51 Durotar Main Road 48
/way 53.37 63.48 Durotar Main Road 49
/way 53.16 64.42 Durotar Main Road 50
/way 52.96 65.48 Durotar Main Road 51
/way 52.60 66.56 Durotar Main Road 52
/way 52.29 67.44 Durotar Main Road 53
/way 51.63 68.31 Durotar Main Road 54 crossroadsSenJin
/way 50.97 68.49 Durotar Main Road 55 @ Valley of Trials Entrance > end
/way 46.38 14.02 Dranoshar Blockade 1 crossroadsBlockade
/way 46.93 13.94 Dranoshar Blockade 2
/way 47.48 13.98 Dranoshar Blockade 3
/way 48.00 14.10 Dranoshar Blockade 4
/way 48.49 14.20 Dranoshar Blockade 5
/way 48.98 14.13 Dranoshar Blockade 6
/way 49.52 13.92 Dranoshar Blockade 7
/way 49.97 13.58 Dranoshar Blockade 8
/way 50.62 12.94 Dranoshar Blockade 9 crossroadsDeadeye1
/way 51.15 12.52 Dranoshar Blockade 10
/way 51.74 12.30 Dranoshar Blockade 11
/way 52.36 12.30 Dranoshar Blockade 12
/way 53.03 11.96 Dranoshar Blockade 13
/way 53.65 11.59 Dranoshar Blockade 14
/way 53.57 12.62 Dranoshar Blockade 14.1
/way 54.04 12.90 Dranoshar Blockade 14.2
/way 54.12 13.07 Dranoshar Blockade 14.3 end
/way 54.30 11.27 Dranoshar Blockade 15
/way 54.58 11.96 Dranoshar Blockade 15.1
/way 55.00 12.55 Dranoshar Blockade 15.2
/way 55.65 13.35 Dranoshar Blockade 15.3 end
/way 54.95 11.01 Dranoshar Blockade 16 crossroadsSkullRock
/way 55.47 11.19 Dranoshar Blockade 16.1
/way 55.65 11.36 Dranoshar Blockade 16.2
/way 55.70 11.76 Dranoshar Blockade 16.3
/way 55.78 12.18 Dranoshar Blockade 16.4
/way 55.71 12.23 Dranoshar Blockade 16.5 bottom of narrow stairs keep right to ascend
/way 55.74 12.41 Dranoshar Blockade 16.6
/way 55.83 12.40 Dranoshar Blockade 16.7
/way 55.90 12.37 Dranoshar Blockade 16.8
/way 55.86 12.14 Dranoshar Blockade 16.9
/way 55.70 12.20 Dranoshar Blockade 16.10
/way 55.74 12.44 Dranoshar Blockade 16.11
/way 55.91 12.37 Dranoshar Blockade 16.12
/way 55.86 12.13 Dranoshar Blockade 16.13
/way 55.70 12.20 Dranoshar Blockade 16.14
/way 55.74 12.44 Dranoshar Blockade 16.15
/way 55.90 12.37 Dranoshar Blockade 16.16
/way 55.85 12.16 Dranoshar Blockade 16.17
/way 55.70 12.23 Dranoshar Blockade 16.18
/way 55.77 12.51 Dranoshar Blockade 16.19 top of railless tower moderate falling risk from here
/way 55.89 12.78 Dranoshar Blockade 16.20
/way 55.97 13.19 Dranoshar Blockade 16.21 @ Zeppelin to Dragon Isles wait here for horn
/way 56.04 13.49 Dranoshar Blockade 16.22 on board the zeppelin wait here for second horn before disembarking end 
/way 55.68 10.79 Dranoshar Blockade 17 entering pier falling risk
/way 56.16 10.71 Dranoshar Blockade 18
/way 56.51 10.65 Dranoshar Blockade 19
/way 56.95 10.58 Dranoshar Blockade 20
/way 57.42 10.49 Dranoshar Blockade 21
/way 57.70 10.44 Dranoshar Blockade 22
/way 57.75 10.68 Dranoshar Blockade 22.1
/way 57.78 11.16 Dranoshar Blockade 22.2 end
/way 57.71 10.16 Dranoshar Blockade 23
/way 57.69 09.68 Dranoshar Blockade 24 end
/way 53.03 45.26 Scuttle Coast 1 crossroadsScuttle1
/way 53.67 45.13 Scuttle Coast 2
/way 54.33 44.99 Scuttle Coast 3
/way 54.95 44.76 Scuttle Coast 4
/way 55.56 44.47 Scuttle Coast 5
/way 56.27 44.03 Scuttle Coast 6
/way 56.91 44.60 Scuttle Coast 7
/way 57.52 45.22 Scuttle Coast 8
/way 58.02 44.76 Scuttle Coast 9
/way 58.47 43.95 Scuttle Coast 10
/way 59.04 43.34 Scuttle Coast 11
/way 59.56 43.82 Scuttle Coast 12
/way 59.57 44.53 Scuttle Coast 13
/way 59.49 45.43 Scuttle Coast 14
/way 59.41 46.34 Scuttle Coast 15
/way 59.33 47.40 Scuttle Coast 16
/way 59.35 48.38 Scuttle Coast 17
/way 59.45 49.43 Scuttle Coast 18
/way 59.37 50.33 Scuttle Coast 19
/way 59.06 51.29 Scuttle Coast 20
/way 58.85 52.32 Scuttle Coast 21 crossroadsTiragarde2
/way 58.02 52.50 Scuttle Coast 22
/way 57.50 53.02 Scuttle Coast 23
/way 56.94 53.78 Scuttle Coast 24
/way 56.32 54.49 Scuttle Coast 25
/way 55.89 55.21 Scuttle Coast 26 crossroadsScuttle2
/way 50.85 13.36 Deadeye Shore 1 crossroadsDeadeye1
/way 51.26 14.13 Deadeye Shore 2
/way 51.73 14.85 Deadeye Shore 3
/way 52.16 15.45 Deadeye Shore 4
/way 52.58 16.01 Deadeye Shore 5
/way 53.02 16.59 Deadeye Shore 6
/way 53.29 17.25 Deadeye Shore 7
/way 53.64 17.90 Deadeye Shore 8
/way 54.11 18.32 Deadeye Shore 9
/way 54.58 18.77 Deadeye Shore 10
/way 55.03 19.24 Deadeye Shore 11
/way 55.48 19.80 Deadeye Shore 12
/way 55.90 19.92 Deadeye Shore 13
/way 56.35 20.21 Deadeye Shore 14
/way 56.76 20.59 Deadeye Shore 15
/way 57.06 21.16 Deadeye Shore 16
/way 57.45 21.66 Deadeye Shore 17
/way 57.96 22.08 Deadeye Shore 18
/way 58.43 22.64 Deadeye Shore 19
/way 58.79 23.17 Deadeye Shore 20
/way 58.62 23.86 Deadeye Shore 21
/way 58.41 24.63 Deadeye Shore 22
/way 58.24 25.60 Deadeye Shore 23
/way 58.15 26.67 Deadeye Shore 24
/way 58.07 27.74 Deadeye Shore 25
/way 57.74 28.56 Deadeye Shore 26
/way 57.26 29.23 Deadeye Shore 27
/way 56.75 29.96 Deadeye Shore 28
/way 56.21 30.72 Deadeye Shore 29
/way 55.59 31.48 Deadeye Shore 30
/way 55.15 30.65 Deadeye Shore 30.1
/way 54.74 29.83 Deadeye Shore 30.2
/way 54.19 29.66 Deadeye Shore 30.3
/way 53.55 29.44 Deadeye Shore 30.4
/way 52.81 29.35 Deadeye Shore 30.5
/way 52.86 28.80 Deadeye Shore 30.6 crossroadsDustwind end >
/way 55.10 32.37 Deadeye Shore 31
/way 54.94 33.26 Deadeye Shore 32
/way 55.07 34.20 Deadeye Shore 33
/way 55.13 34.86 Deadeye Shore 34
/way 55.43 35.65 Deadeye Shore 35
/way 55.62 36.45 Deadeye Shore 36
/way 55.57 37.31 Deadeye Shore 37
/way 55.27 38.09 Deadeye Shore 38
/way 55.01 38.91 Deadeye Shore 39
/way 54.65 39.64 Deadeye Shore 40
/way 54.15 40.66 Deadeye Shore 41
/way 53.98 41.12 Deadeye Shore 42
/way 53.43 41.17 Deadeye Shore 43
/way 52.87 41.44 Deadeye Shore 44 crossroadsDeadeye2 end
/way 47.42 21.99 Drygulch Ravine 1 crossroadsDrygulch1
/way 47.75 21.50 Drygulch Ravine 2
/way 48.32 21.26 Drygulch Ravine 3
/way 48.90 21.56 Drygulch Ravine 4
/way 49.27 22.18 Drygulch Ravine 5
/way 49.55 23.00 Drygulch Ravine 6
/way 49.69 23.54 Drygulch Ravine 7
/way 49.87 24.28 Drygulch Ravine 8
/way 50.10 25.01 Drygulch Ravine 9
/way 50.45 25.89 Drygulch Ravine 10
/way 50.32 26.74 Drygulch Ravine 10.1
/way 49.96 27.56 Drygulch Ravine 10.2
/way 49.76 28.44 Drygulch Ravine 10.3 crossroadsDrygulch2 end
/way 50.85 26.47 Drygulch Ravine 11
/way 51.36 27.08 Drygulch Ravine 12
/way 51.80 27.41 Drygulch Ravine 13
/way 52.25 27.46 Drygulch Ravine 14
/way 52.57 27.52 Drygulch Ravine 15
/way 52.79 27.70 Drygulch Ravine 16
/way 53.06 27.87 Drygulch Ravine 17
/way 53.29 27.88 Drygulch Ravine 18
/way 53.56 27.80 Drygulch Ravine 19
/way 53.92 27.75 Drygulch Ravine 20
/way 54.06 27.17 Drygulch Ravine 21
/way 54.01 26.26 Drygulch Ravine 22
/way 53.84 25.45 Drygulch Ravine 23
/way 53.78 24.92 Drygulch Ravine 24
/way 53.39 24.73 Drygulch Ravine 24.1
/way 52.76 24.21 Drygulch Ravine 24.2
/way 52.14 23.97 Drygulch Ravine 24.3
/way 51.51 23.70 Drygulch Ravine 24.4 end
/way 53.92 24.26 Drygulch Ravine 25
/way 53.99 23.21 Drygulch Ravine 26
/way 53.98 22.36 Drygulch Ravine 27
/way 53.56 21.83 Drygulch Ravine 28
/way 53.04 21.55 Drygulch Ravine 29
/way 52.48 21.32 Drygulch Ravine 30
/way 51.98 21.03 Drygulch Ravine 31
/way 51.61 20.51 Drygulch Ravine 32
/way 51.40 19.99 Drygulch Ravine 33
/way 51.39 19.09 Drygulch Ravine 34 end
/way 52.53 42.91 Razor Hill 1 crossroadsRazorHill
/way 52.26 42.55 Razor Hill 2
/way 51.96 42.06 Razor Hill 2.1 @ Mailbox
/way 51.58 41.72 Razor Hill 2.2 !Innkeeper Grosk end
/way 51.92 42.72 Razor Hill 3
/way 52.12 43.15 Razor Hill 3.1
/way 51.96 43.49 Razor Hill 3.2
/way 51.82 43.74 Razor Hill 3.3
/way 51.77 43.62 Razor Hill 3.4
/way 51.85 43.48 Razor Hill 3.5 end
/way 51.49 43.02 Razor Hill 4
/way 51.07 43.49 Razor Hill 5
/way 50.75 43.83 Razor Hill 6
/way 50.32 44.18 Razor Hill 7 crossroadsOutskirts end
/way 49.92 44.22 Razor Hill Outskirts 1 crossroadsOutskirts
/way 49.52 43.72 Razor Hill Outskirts 2
/way 49.03 43.38 Razor Hill Outskirts 3
/way 48.60 43.65 Razor Hill Outskirts 4
/way 48.09 43.43 Razor Hill Outskirts 5
/way 47.78 42.71 Razor Hill Outskirts 6
/way 48.07 42.22 Razor Hill Outskirts 7
/way 48.45 41.65 Razor Hill Outskirts 8
/way 48.73 41.08 Razor Hill Outskirts 9
/way 49.03 40.56 Razor Hill Outskirts 10 crossroadsSouthfury
/way 49.38 40.03 Razor Hill Outskirts 11 tight climb ahead go slow
/way 49.54 40.14 Razor Hill Outskirts 12
/way 49.61 40.38 Razor Hill Outskirts 13
/way 49.76 40.46 Razor Hill Outskirts 14
/way 49.80 40.32 Razor Hill Outskirts 15
/way 49.81 40.17 Razor Hill Outskirts 16
/way 49.68 40.15 Razor Hill Outskirts 17
/way 49.63 40.30 Razor Hill Outskirts 18
/way 49.73 40.40 Razor Hill Outskirts 19
/way 49.84 40.32 Razor Hill Outskirts 20
/way 49.89 40.18 Razor Hill Outskirts 21
/way 49.81 39.94 Razor Hill Outskirts 22
/way 49.71 39.95 Razor Hill Outskirts 23
/way 49.59 40.00 Razor Hill Outskirts 24 top of tower
/way 49.54 40.14 Razor Hill Outskirts 25 !Thonk use the spyglass from here four times end
/way 48.82 39.79 Southfury Watershed North 1 crossroadsSouthfury edge of Southfury quest area
/way 48.52 38.96 Southfury Watershed North 2
/way 48.20 38.05 Southfury Watershed North 3
/way 47.82 37.24 Southfury Watershed North 4
/way 47.48 36.47 Southfury Watershed North 5
/way 47.16 35.77 Southfury Watershed North 6
/way 46.79 35.07 Southfury Watershed North 7
/way 46.30 34.50 Southfury Watershed North 8 crossroadsRazorwind3
/way 45.91 33.78 Southfury Watershed North 9 crossroadsDreadmaw
/way 45.62 33.03 Southfury Watershed North 10
/way 45.25 32.22 Southfury Watershed North 11 crossroadsThunderRidge2
/way 44.84 31.84 Southfury Watershed North 12
/way 44.46 31.62 Southfury Watershed North 13
/way 44.18 31.65 Southfury Watershed North 14
/way 43.98 31.03 Southfury Watershed North 15
/way 43.53 30.77 Southfury Watershed North 16 @ Torkren Farm
/way 43.15 30.72 Southfury Watershed North 17
/way 42.70 30.60 Southfury Watershed North 18
/way 42.40 31.34 Southfury Watershed North 19 crossroadsWatershedWest
/way 42.33 32.27 Southfury Watershed North 20
/way 42.44 33.28 Southfury Watershed North 21 edge of the water
/way 42.69 34.12 Southfury Watershed North 22
/way 43.37 33.85 Southfury Watershed North 22.1
/way 44.22 34.26 Southfury Watershed North 22.2
/way 44.98 34.19 Southfury Watershed North 22.3 crossroadsDreadmaw edge of the water end
/way 42.27 35.17 Southfury Watershed North 23
/way 41.58 35.94 Southfury Watershed North 24
/way 41.19 37.03 Southfury Watershed North 25
/way 40.91 38.33 Southfury Watershed North 26 end
/way 41.65 31.69 Southfury Watershed West 1 crossroadsWatershedWest
/way 41.25 32.15 Southfury Watershed West 2 this path crosses the water
/way 40.67 32.40 Southfury Watershed West 3
/way 40.21 33.20 Southfury Watershed West 4
/way 39.38 33.04 Southfury Watershed West 5
/way 38.29 33.29 Southfury Watershed West 6
/way 37.36 34.02 Southfury Watershed West 7
/way 36.90 34.22 Southfury Watershed West 8
/way 36.52 34.68 Southfury Watershed West 9
/way 36.18 35.41 Southfury Watershed West 10
/way 35.80 36.32 Southfury Watershed West 11
/way 35.82 37.97 Southfury Watershed West 12 crossroadsEastBank1
/way 35.83 39.11 Southfury Watershed West 13
/way 35.84 40.05 Southfury Watershed West 14
/way 35.85 41.10 Southfury Watershed West 15 crossroadsWatershedWest2
/way 35.47 41.56 Southfury Watershed West 16
/way 35.08 41.96 Southfury Watershed West 17
/way 34.73 42.22 Southfury Watershed West 18 edge of Southfury quest area
/way 34.43 42.30 Southfury Watershed West 19 @ bridge to the Barrens end >
/way 36.26 41.71 Southfury Watershed South 1 crossroadsWatershedWest2
/way 36.83 41.92 Southfury Watershed South 2
/way 37.59 42.35 Southfury Watershed South 3
/way 38.28 43.28 Southfury Watershed South 4
/way 38.85 44.15 Southfury Watershed South 5
/way 39.20 45.11 Southfury Watershed South 6
/way 39.55 45.97 Southfury Watershed South 7
/way 40.30 46.95 Southfury Watershed South 8
/way 40.66 48.13 Southfury Watershed South 9
/way 41.16 49.25 Southfury Watershed South 10
/way 41.82 50.04 Southfury Watershed South 11
/way 42.65 50.09 Southfury Watershed South 12              
/way 42.32 50.56 Southfury Watershed South 12.1
/way 41.53 51.11 Southfury Watershed South 12.2
/way 40.65 51.64 Southfury Watershed South 12.3
/way 39.92 52.22 Southfury Watershed South 12.4
/way 39.34 52.92 Southfury Watershed South 12.5
/way 38.85 53.40 Southfury Watershed South 12.6
/way 38.33 53.90 Southfury Watershed South 12.7
/way 38.09 54.83 Southfury Watershed South 12.8
/way 37.75 56.03 Southfury Watershed South 12.9
/way 37.02 56.43 Southfury Watershed South 12.10 end
/way 43.51 49.58 Southfury Watershed South 13
/way 44.29 49.01 Southfury Watershed South 14
/way 44.97 48.57 Southfury Watershed South 15
/way 45.70 48.26 Southfury Watershed South 16
/way 46.47 48.04 Southfury Watershed South 17
/way 47.12 47.39 Southfury Watershed South 18
/way 47.66 46.45 Southfury Watershed South 19
/way 48.23 45.60 Southfury Watershed South 20
/way 49.02 45.12 Southfury Watershed South 21
/way 49.56 44.78 Southfury Watershed South 22 crossroadsOutskirts edge of Southfury quest area end
/way 35.20 36.72 Southfury River East Bank 1 crossroadsEastBank1
/way 34.88 36.05 Southfury River East Bank 2
/way 34.82 35.26 Southfury River East Bank 3
/way 34.78 34.49 Southfury River East Bank 4
/way 34.83 33.70 Southfury River East Bank 5
/way 34.80 32.95 Southfury River East Bank 6
/way 34.87 32.32 Southfury River East Bank 7
/way 34.97 31.73 Southfury River East Bank 8
/way 35.07 30.93 Southfury River East Bank 9
/way 35.20 30.12 Southfury River East Bank 10
/way 35.25 29.07 Southfury River East Bank 11
/way 35.69 28.54 Southfury River East Bank 12
/way 36.11 27.95 Southfury River East Bank 13
/way 36.62 27.18 Southfury River East Bank 14
/way 36.98 26.42 Southfury River East Bank 15
/way 37.30 25.47 Southfury River East Bank 16
/way 37.59 24.33 Southfury River East Bank 17
/way 37.85 23.35 Southfury River East Bank 18
/way 38.18 22.57 Southfury River East Bank 19
/way 38.66 21.60 Southfury River East Bank 20 edge of Southfury quest area crossroadsEastBank2 end
/way 45.37 12.86 Rocktusk 1 crossroadsRocktusk
/way 45.01 13.29 Rocktusk 2
/way 44.94 13.62 Rocktusk 2.1
/way 44.89 14.24 Rocktusk 2.2
/way 44.94 14.66 Rocktusk 2.3 !Shin Stonepillar end
/way 44.66 13.17 Rocktusk 3
/way 44.22 13.41 Rocktusk 4
/way 43.89 13.95 Rocktusk 5
/way 43.67 14.68 Rocktusk 6
/way 43.57 15.40 Rocktusk 7
/way 43.26 16.19 Rocktusk 8
/way 42.66 16.11 Rocktusk 8.1
/way 42.22 15.54 Rocktusk 8.2 end
/way 42.92 16.90 Rocktusk 9
/way 42.49 17.56 Rocktusk 10
/way 41.83 18.42 Rocktusk 11
/way 41.06 19.31 Rocktusk 12
/way 40.27 20.19 Rocktusk 13
/way 39.57 21.16 Rocktusk 14 crossroadsEastBank2 end
/way 46.19 22.41 Thunder Ridge 1 crossroadsDrygulch1 entering quest area
/way 45.88 23.38 Thunder Ridge 2
/way 45.65 24.64 Thunder Ridge 3
/way 45.50 25.72 Thunder Ridge 4
/way 45.45 26.86 Thunder Ridge 5
/way 45.59 27.96 Thunder Ridge 6
/way 45.61 29.12 Thunder Ridge 7
/way 45.47 30.31 Thunder Ridge 8 crossroadsRazorwind1
/way 45.39 31.21 Thunder Ridge 9 crossroadsThunderRidge2 end
/way 46.25 30.32 Razorwind Canyon 1 crossroadsRazorwind1
/way 46.98 30.45 Razorwind Canyon 2
/way 47.47 30.75 Razorwind Canyon 3
/way 47.97 31.41 Razorwind Canyon 4
/way 48.46 32.27 Razorwind Canyon 5
/way 48.59 33.01 Razorwind Canyon 6
/way 48.63 33.73 Razorwind Canyon 7
/way 47.94 33.74 Razorwind Canyon 7.1
/way 47.03 34.01 Razorwind Canyon 7.2 crossroadsRazorwind3 end
/way 49.29 33.48 Razorwind Canyon 8
/way 49.81 32.91 Razorwind Canyon 9
/way 50.36 32.13 Razorwind Canyon 10
/way 50.90 31.50 Razorwind Canyon 11 crossroadsRazorwind2 end
/way 51.80 68.62 SenJin Village 1 crossroadsSenJin
/way 52.23 69.36 SenJin Village 2
/way 52.66 70.18 SenJin Village 3
/way 53.12 70.84 SenJin Village 4
/way 53.52 71.51 SenJin Village 5
/way 53.94 72.21 SenJin Village 6
/way 54.34 72.94 SenJin Village 7
/way 54.76 73.71 SenJin Village 8 crossroadsStrand
/way 55.19 74.22 SenJin Village 9
/way 55.42 74.65 SenJin Village 10
/way 55.61 74.92 Senjin Village 11 !Lar Prowltusk
/way 55.76 75.01 SenJin Village 12
/way 55.83 74.93 SenJin Village 13
/way 56.10 74.91 SenJin Village 14
/way 56.11 74.62 SenJin Village 15 crossroadsIsles @ Mailbox
/way 55.78 74.17 SenJin Village 16
/way 55.59 73.89 SenJin Village 17
/way 55.43 73.43 SenJin Village 18 !Handler Marnlek @ SenJin Flightmaster end
/way 56.37 74.70 Road to Echo Isles 1 crossroadsIsles
/way 56.84 74.67 Road to Echo Isles 2
/way 57.29 75.04 Road to Echo Isles 3
/way 57.70 75.33 Road to Echo Isles 4
/way 58.15 75.74 Road to Echo Isles 5
/way 58.28 76.75 Road to Echo Isles 6
/way 58.42 77.78 Road to Echo Isles 7
/way 58.58 78.66 Road to Echo Isles 8 end >
/way 54.76 74.47 Darkspear Strand 1 crossroadsStrand entering quest area
/way 54.74 75.23 Darkspear Strand 2
/way 54.71 75.97 Darkspear Strand 3
/way 54.74 76.81 Darkspear Strand 4 crossroadsShoreLoop
/way 54.53 77.30 Darkspear Strand 5
/way 54.12 77.71 Darkspear Strand 6
/way 53.70 78.11 Darkspear Strand 7
/way 53.24 78.56 Darkspear Strand 8
/way 52.82 79.02 Darkspear Strand 9
/way 52.39 79.48 Darkspear Strand 10 crossroadsNorthwatch
/way 52.65 80.29 Darkspear Strand 11
/way 52.95 81.11 Darkspear Strand 12
/way 53.13 81.86 Darkspear Strand 13
/way 53.18 82.90 Darkspear Strand 14
/way 53.77 82.46 Darkspear Strand 15
/way 54.33 81.99 Darkspear Strand 16
/way 54.79 81.43 Darkspear Strand 17
/way 55.20 80.59 Darkspear Strand 18
/way 55.42 79.64 Darkspear Strand 19
/way 55.62 78.58 Darkspear Strand 20
/way 55.41 77.76 Darkspear Strand 21
/way 55.10 77.15 Darkspear Strand 22 crossroadsShoreLoop end
/way 51.96 79.33 Northwatch Foothold 1 crossroadsNorthwatch
/way 51.58 79.11 Northwatch Foothold 2
/way 51.12 79.15 Northwatch Foothold 3
/way 50.75 79.12 Northwatch Foothold 4
/way 50.36 79.20 Northwatch Foothold 5
/way 50.05 79.38 Northwatch Foothold 6
/way 49.66 79.70 Northwatch Foothold 7
/way 49.72 80.35 Northwatch Foothold 7.1
/way 49.81 81.20 Northwatch Foothold 7.2 end
/way 49.17 79.40 Northwatch Foothold 8
/way 48.59 79.30 Northwatch Foothold 9
/way 48.20 78.86 Northwatch Foothold 9.1
/way 47.86 78.30 Northwatch Foothold 9.2
/way 47.88 77.73 Northwatch Foothold 9.3 end
/way 48.43 79.75 Northwatch Foothold 10
/way 47.92 80.32 Northwatch Foothold 11
/way 47.51 80.75 Northwatch Foothold 12
/way 47.07 80.54 Northwatch Foothold 13
/way 46.64 80.19 Northwatch Foothold 14
/way 46.47 79.65 Northwatch Foothold 15
/way 46.38 79.19 Northwatch Foothold 16 end
/way 53.84 57.07 Tiragarde Keep 1 crossroadsTiragarde1
/way 58.77 56.76 Tiragarde Keep 1.1
/way 58.70 55.90 Tiragarde Keep 1.2
/way 58.66 55.13 Tiragarde Keep 1.3
/way 58.64 54.00 Tiragarde Keep 1.4
/way 58.85 53.03 Tiragarde Keep 1.5 end crossroadsTiragarde2
/way 54.25 56.59 Tiragarde Keep 2
/way 54.88 55.98 Tiragarde Keep 3
/way 55.72 55.97 Tiragarde Keep 4 crossroadsScuttle2
/way 56.09 56.77 Tiragarde Keep 5
/way 56.45 57.57 Tiragarde Keep 6
/way 56.84 58.00 Tiragarde Keep 7
/way 57.26 57.46 Tiragarde Keep 8
/way 57.82 56.99 Tiragarde Keep 9
/way 58.32 57.11 Tiragarde Keep 10
/way 58.45 58.30 Tiragarde Keep 11
/way 58.96 58.32 Tiragarde Keep 12 @ end >
/way 55.13 10.23 Skull Rock 1 crossroadsSkullRock
/way 55.00 09.70 Skull Rock 2 end >
/way 61.22 08.84 The Windrunner 1
/way 61.49 08.87 The Windrunner 2
/way 61.50 09.28 The Windrunner 3 <
/way 61.36 09.30 The Windrunner 4 return here to salute the rangers
/way 61.27 09.38 The Windrunner 5 < 
/way 61.28 09.62 The Windrunner 6
/way 61.40 09.74 The Windrunner 7 Test the catapult end
/way 37.02 51.67 Tiragarde Keep Main 1
/way 37.04 77.90 Tiragarde Keep Main 2
/way 46.32 79.43 Tiragarde Keep Main 3
/way 46.85 66.81 Tiragarde Keep Main 4
/way 47.73 50.59 Tiragarde Keep Main 5
/way 54.82 44.44 Tiragarde Keep Main 6
/way 60.03 50.18 Tiragarde Keep Main 7
/way 60.71 60.55 Tiragarde Keep Main 8
/way 49.94 59.96 Tiragarde Keep Main 9
/way 48.51 44.88 Tiragarde Keep Main 10
/way 48.44 30.61 Tiragarde Keep Main 11 
/way 38.97 30.97 Tiragarde Keep Main 11.1 end >
/way 36.60 30.44 Tiragarde Keep Side Room 1 >
/way 32.93 31.42 Tiragarde Keep Side Room 2
/way 32.59 43.10 Tiragarde Keep Side Room 3
/way 42.93 52.39 Tiragarde Keep Side Room 4 end
/way 83.39 54.02 Skull Rock 3 >
/way 82.97 44.84 Skull Rock 4
/way 75.40 47.49 Skull Rock 5
/way 70.53 50.80 Skull Rock 6
/way 68.49 47.27 Skull Rock 6.1
/way 63.22 41.22 Skull Rock 6.2
/way 58.86 36.26 Skull Rock 6.3
/way 58.27 28.73 Skull Rock 6.4
/way 54.89 23.57 Skull Rock 6.5
/way 51.38 19.71 Skull Rock 6.6
/way 48.79 22.69 Skull Rock 6.7
/way 45.15 26.93 Skull Rock 6.8
/way 42.46 33.64 Skull Rock 6.9
/way 39.55 40.72 Skull Rock 6.10
/way 34.21 37.00 Skull Rock 6.11
/way 29.38 33.12 Skull Rock 6.12
/way 23.90 32.35 Skull Rock 6.13
/way 23.68 36.61 Skull Rock 6.14
/way 20.70 42.60 Skull Rock 6.15
/way 19.46 49.05 Skull Rock 6.16
/way 20.71 60.84 Skull Rock 6.17 end
/way 69.28 58.10 Skull Rock 7
/way 65.00 62.48 Skull Rock 8
/way 62.92 69.49 Skull Rock 9
/way 60.43 73.65 Skull Rock 10
/way 57.69 78.62 Skull Rock 11
/way 56.21 72.75 Skull Rock 11.1
/way 54.06 66.46 Skull Rock 11.2
/way 51.51 57.81 Skull Rock 11.3
/way 47.84 52.60 Skull Rock 11.4
/way 44.73 54.49 Skull Rock 11.5 end
/way 56.91 84.87 Skull Rock 12
/way 53.50 88.41 Skull Rock 13
/way 49.60 91.30 Skull Rock 14
/way 45.43 91.78 Skull Rock 15
/way 42.27 88.55 Skull Rock 16
/way 36.61 89.00 Skull Rock 17
/way 32.17 87.45 Skull Rock 18
/way 26.90 85.45 Skull Rock 19
/way 23.25 81.09 Skull Rock 20
/way 23.52 72.28 Skull Rock 21
/way 28.78 68.35 Skull Rock 22
/way 37.17 64.28 Skull Rock 23
/way 35.19 72.96 Skull Rock 24  < end
/way 50.15 92.56 Dustwind Cave 1 crossroadsDustwind >
/way 48.71 85.82 Dustwind Cave 2
/way 53.70 84.23 Dustwind Cave 3
/way 56.91 79.07 Dustwind Cave 4
/way 58.09 69.41 Dustwind Cave 5
/way 54.83 67.60 Dustwind Cave 6
/way 56.63 64.72 Dustwind Cave 6.1 jump here
/way 58.25 60.77 Dustwind Cave 6.2
/way 54.77 56.84 Dustwind Cave 6.3
/way 50.81 54.13 Dustwind Cave 6.4 < end
/way 50.54 63.36 Dustwind Cave 7
/way 45.75 61.38 Dustwind Cave 8
/way 40.06 64.02 Dustwind Cave 9
/way 35.52 62.31 Dustwind Cave 10
/way 33.32 54.28 Dustwind Cave 11
/way 32.30 43.86 Dustwind Cave 12
/way 33.26 34.79 Dustwind Cave 13
/way 34.74 27.05 Dustwind Cave 14
/way 37.86 21.79 Dustwind Cave 15
/way 44.36 22.61 Dustwind Cave 16
/way 48.95 30.38 Dustwind Cave 17 end
]]

local function stripBsMapdata(inputstr)
	local sep = "\n"
	local t = {}
	for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
		str = string.gsub(str, "/way ", "")
		t[#t + 1] = {
			x = tonumber(string.sub(str, 1, 5)),
			y = tonumber(string.sub(str, 7, 11)),
			name = string.sub(str, 13),
		}
	end
	return t
 end
function SkuNav:bstest()
	local strippedBsMapdata = stripBsMapdata(MapWayData1, "\n")

	SkuOptions.db.global["SkuNav"].Waypoints = {}
	SkuOptions.db.global["SkuNav"].Links = {}
	SkuOptions.db.global["SkuNav"].WaypointsNew = {}
	SkuOptions.db.global["SkuNav"].WaypointLevels = {}
	SkuOptions.db.global["SkuNav"].SequenceNumbers = {}
	--SkuOptions.db.global["SkuNav"].hasCustomMapData = nil


	for i, v in pairs(strippedBsMapdata) do
		local _, worldPosition = C_Map.GetWorldPosFromMapPos(1411, CreateVector2D(v.x / 100, v.y / 100))
		local tWorldX, tWorldY = worldPosition:GetXY()

		print(v.x, v.y, v.name, tWorldX, tWorldY)
		SkuOptions.db.global[MODULE_NAME].WaypointsNew[#SkuOptions.db.global[MODULE_NAME].WaypointsNew + 1] = {
         ["areaId"] = 14,
         ["worldY"] = tWorldY,
         ["contintentId"] = 1,
         ["names"] = v.name.."§"..v.name,
         ["lComments"] = {
            ["enUS"] = {
            },
            ["deDE"] = {
            },
         },
         ["createdBy"] = "SkuNav",
         ["worldX"] = tWorldX,
         ["size"] = 1,
      }
	end

	--SkuNav:PLAYER_ENTERING_WORLD()
	SkuNav:PLAYER_LOGIN()
	SkuNav:CreateWaypointCache()
end

------------------------------------------------------------------------------------------------------------------