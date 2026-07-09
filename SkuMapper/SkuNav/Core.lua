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

	-- [bugfix] tPlayerUIMap was undeclared (a nil global), and the extra
	-- `ParentAreaID == C_Map.GetBestMapForUnit("player")` compared an internal
	-- parent-area index against a raw uiMapId — so this loop never matched and
	-- zone detection always fell through to the name-only fallback below. Aligned
	-- to Sku's fixed GetCurrentAreaId: match by minimap zone name + resolved
	-- uiMap, honouring aUnitId.
	local tPlayerUIMap = SkuNav:GetBestMapForUnit(aUnitId or "player")
	for i, v in pairs(SkuDB.InternalAreaTable) do
		if (v.AreaName_lang[Sku.Loc] == tMinimapZoneText) and (SkuNav:GetUiMapIdFromAreaId(i) == tPlayerUIMap) then
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
	-- Seed the editable working set from Sku's CURRENT shipped route data, so a
	-- mapper starts on top of what actually ships (not from empty, which would
	-- have wiped every existing route on the next export). Only seeds when there
	-- is no in-progress custom work (or on an explicit reset via aForce).
	--
	-- SkuDB/assets/routedata_global.lua is a byte-for-byte copy of
	-- Sku/SkuDB/assets/routedata_global.lua and only DEFINES a builder function
	-- at file load; we build the tables on demand here, then split the packed
	-- "en§de" names into the names table (mirrors Sku's own LoadDefaultMapData
	-- and this file's PLAYER_LOGIN migration). Calling the builder each time is
	-- fine: it rebuilds SkuDB.routedata fresh, so a reset yields a clean copy.
	if SkuOptions.db.global["SkuNav"].hasCustomMapData ~= true or aForce then
		if type(SkuDBBuildRouteGlobal) == "function" then
			SkuDBBuildRouteGlobal()
		end

		local tGlobal = SkuDB.routedata and SkuDB.routedata["global"]
		if tGlobal then
			if tGlobal.WaypointsNew then
				tGlobal.Waypoints = {}
				for x = 1, #tGlobal.WaypointsNew do
					local tData = tGlobal.WaypointsNew[x]
					tGlobal.Waypoints[x] = tData
					if tGlobal.Waypoints[x][1] ~= false then
						local en, de = string.match(tGlobal.Waypoints[x].names, "(.+)§(.+)")
						if not en or not de then
							en, de = "", ""
						end
						tGlobal.Waypoints[x].names = {}
						tGlobal.Waypoints[x].names["enUS"] = en
						tGlobal.Waypoints[x].names["deDE"] = de
					end
				end
				tGlobal.WaypointsNew = nil
			end

			SkuOptions.db.global["SkuNav"].Waypoints = tGlobal.Waypoints or {}
			SkuOptions.db.global["SkuNav"].Links = tGlobal.Links or {}
			SkuOptions.db.global["SkuNav"].WaypointLevels = tGlobal.WaypointLevels or {}
			SkuOptions.db.global["SkuNav"].SequenceNumbers = tGlobal.SequenceNumbers or {}
		else
			-- Route file absent (e.g. not copied in at package time) — start empty
			-- rather than erroring; the tool still runs, just without a baseline.
			SkuOptions.db.global["SkuNav"].Waypoints = {}
			SkuOptions.db.global["SkuNav"].Links = {}
		end
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
-- (removed a local SkuSpairs shadow here; it was dead — the only call site is
-- above its declaration and already resolves to the global SkuSpairs in
-- SkuZOptions/utilities.lua.)
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
