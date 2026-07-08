local MODULE_NAME = "SkuQuest"
local L = Sku.L


---------------------------------------------------------------------------------------------------------------------------------------
local function CreatureIdHelper(aCreatureIds, aTargetTable, aOnly3)
	local _, _, tPlayerContinentID  = SkuNav:GetAreaData(SkuNav:GetCurrentAreaId())

	for i, tNpcID in pairs(aCreatureIds) do
		--dprint("CreateRtWpSubmenu", i, tNpcID)		
		local i = tNpcID
		if SkuDB.NpcData.Data[i] then
			local tSpawns = SkuDB.NpcData.Data[i][7]
			if tSpawns then
				for is, vs in pairs(tSpawns) do
					local isUiMap = SkuNav:GetUiMapIdFromAreaId(is)
					--we don't care for stuff that isn't in the open world
					if isUiMap then
						local tData = SkuDB.InternalAreaTable[is]
						if tData then
							if SkuNav:GetContinentNameFromContinentId(tData.ContinentID) then
								if tData.ContinentID == tPlayerContinentID then
									local tNumberOfSpawns = #vs
									if tNumberOfSpawns > 3 and aOnly3 == true then
										tNumberOfSpawns = 3
									end
									if SkuDB.NpcData.Names[Sku.Loc][i] then
										local tSubname = SkuDB.NpcData.Names[Sku.Loc][i][2]
										local tRolesString = ""
										if not tSubname then
											local tRoles = SkuNav:GetNpcRoles(SkuDB.NpcData.Names[Sku.Loc][i], i)
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
											if not aTargetTable[SkuDB.NpcData.Names[Sku.Loc][i][1]..tRolesString] then
												aTargetTable[SkuDB.NpcData.Names[Sku.Loc][i][1]..tRolesString] = {}
											end
											table.insert(aTargetTable[SkuDB.NpcData.Names[Sku.Loc][i][1]..tRolesString], SkuDB.NpcData.Names[Sku.Loc][i][1]..tRolesString..";"..tData.AreaName_lang[Sku.Loc]..";"..sp..";"..vs[sp][1]..";"..vs[sp][2])
										end
									end
								else
									if SkuDB.NpcData.Names[Sku.Loc][i] then
										local tSubname = SkuDB.NpcData.Names[Sku.Loc][i][2]
										local tRolesString = ""
										if not tSubname then
											local tRoles = SkuNav:GetNpcRoles(SkuDB.NpcData.Names[Sku.Loc][i], i)
											if #tRoles > 0 then
												for i, v in pairs(tRoles) do
													tRolesString = tRolesString..";"..v
												end
												tRolesString = tRolesString..""
											end
										else
											tRolesString = tRolesString..";"..tSubname
										end
										if not aTargetTable[SkuDB.NpcData.Names[Sku.Loc][i][1]..tRolesString] then
											aTargetTable[SkuDB.NpcData.Names[Sku.Loc][i][1]..tRolesString] = {}
										end
										table.insert(aTargetTable[SkuDB.NpcData.Names[Sku.Loc][i][1]..tRolesString], L["Anderer Kontinent"]..";"..SkuNav:GetContinentNameFromContinentId(tData.ContinentID)..";"..tData.AreaName_lang[Sku.Loc])
									end

								end
							end
						end
					end
				end
			end
		end
	end
	return aTargetTable
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuQuest:GetResultingWps(aSubIDTable, aSubType, aQuestID, tResultWPs, aOnly3)
	--dprint("GetResultingWps", aSubIDTable, aSubType, aQuestID, tResultWPs, aOnly3)
	local _, _, tPlayerContinentID  = SkuNav:GetAreaData(SkuNav:GetCurrentAreaId())
	local tCurrentAreaId = SkuNav:GetCurrentAreaId()
	if aSubType == "item" then
		for i, tItemId in pairs(aSubIDTable) do
			--dprint("  i, tItemId", i, tItemId)
			if SkuDB.itemDataTBC[tItemId][SkuDB.itemKeys["objectDrops"]] then
				for x = 1, #SkuDB.itemDataTBC[tItemId][SkuDB.itemKeys["objectDrops"]] do
					--dprint("     item drops from object", x, SkuDB.itemDataTBC[tItemId][SkuDB.itemKeys["objectDrops"]][x])
					local tObjectId = SkuDB.itemDataTBC[tItemId][SkuDB.itemKeys["objectDrops"]][x]
					local tObjectData = SkuDB.objectDataTBC[tObjectId]
					if tObjectData then					
						local tObjectSpawns = tObjectData[SkuDB.objectKeys["spawns"]]
						local tObjectName = SkuDB.objectLookup[Sku.Loc][tObjectId] or SkuDB.objectDataTBC[tObjectId][1]
						if tObjectSpawns then
							for is, vs in pairs(tObjectSpawns) do
								local isUiMap = SkuNav:GetUiMapIdFromAreaId(is)
								if isUiMap then
									--if is == tCurrentAreaId then
										local tData = SkuDB.InternalAreaTable[is]
										if tData then
											if SkuNav:GetContinentNameFromContinentId(tData.ContinentID) then
												if tData.ContinentID == tPlayerContinentID then
													local tNumberOfSpawns = #vs
													if tNumberOfSpawns > 3 and aOnly3 == true then
														tNumberOfSpawns = 3
													end
													for sp = 1, tNumberOfSpawns do
														if not tResultWPs[tObjectName] then
															tResultWPs[tObjectName] = {}
														end
														table.insert(tResultWPs[tObjectName], L["OBJECT"]..";"..tObjectId..";"..tObjectName..";"..tData.AreaName_lang[Sku.Loc]..";"..sp..";"..vs[sp][1]..";"..vs[sp][2])
													end
												else
													local tNumberOfSpawns = #vs
													if tNumberOfSpawns > 3 and aOnly3 == true then
														tNumberOfSpawns = 3
													end
													for sp = 1, tNumberOfSpawns do
														if not tResultWPs[tObjectName] then
															tResultWPs[tObjectName] = {}
														end
														table.insert(tResultWPs[tObjectName], L["Anderer Kontinent"]..";"..SkuNav:GetContinentNameFromContinentId(tData.ContinentID)..";"..tData.AreaName_lang[Sku.Loc])
													end
												end
											end
										end
									--end
								end
							end
						end
					end
				end
			end
			if SkuDB.itemDataTBC[tItemId][SkuDB.itemKeys["npcDrops"]] then
				CreatureIdHelper(SkuDB.itemDataTBC[tItemId][SkuDB.itemKeys["npcDrops"]], tResultWPs, aOnly3)
			end
			if SkuDB.itemDataTBC[tItemId][SkuDB.itemKeys["itemDrops"]] then
				--dprint("item drop from item")

			end
			if SkuDB.itemDataTBC[tItemId][SkuDB.itemKeys["vendors"]] then
				CreatureIdHelper(SkuDB.itemDataTBC[tItemId][SkuDB.itemKeys["vendors"]], tResultWPs, aOnly3)
			end
		end
	elseif aSubType == "object" then
		local tWpList = {}
		for i, tObjectId in pairs(aSubIDTable) do
			if SkuDB.objectDataTBC[tObjectId] then
				local tSpawns = SkuDB.objectDataTBC[tObjectId][4]
				if tSpawns then
					for is, vs in pairs(tSpawns) do
						local isUiMap = SkuNav:GetUiMapIdFromAreaId(is)
						--we don't care for stuff that isn't in the open world
						if isUiMap then
							local tData = SkuDB.InternalAreaTable[is]
							if tData then
								if tPlayerContinentID == tData.ContinentID then
									if (not aAreaId) or aAreaId == isUiMap then
										local tNumberOfSpawns = #vs
										if tNumberOfSpawns > 3 and aOnly3 == true then
											tNumberOfSpawns = 3
										end
										for sp = 1, tNumberOfSpawns do
											local tObjectName = SkuDB.objectLookup[Sku.Loc][tObjectId] or SkuDB.objectDataTBC[tObjectId][1] or L["Object name missing"]
											if not tResultWPs[tObjectName] then
												tResultWPs[tObjectName] = {}
											end
											table.insert(tResultWPs[tObjectName], L["OBJECT"]..";"..tObjectId..";"..tObjectName..";"..tData.AreaName_lang[Sku.Loc]..";"..sp..";"..vs[sp][1]..";"..vs[sp][2])

										end
									end
								else
									if ((not aAreaId) or aAreaId == isUiMap) and SkuNav:GetContinentNameFromContinentId(tData.ContinentID) then
										local tNumberOfSpawns = #vs
										if tNumberOfSpawns > 3 and aOnly3 == true then
											tNumberOfSpawns = 3
										end
										for sp = 1, tNumberOfSpawns do
											local tObjectName = SkuDB.objectLookup[Sku.Loc][tObjectId] or SkuDB.objectDataTBC[tObjectId][1] or L["Object name missing"]
											if not tResultWPs[tObjectName] then
												tResultWPs[tObjectName] = {}
											end
											table.insert(tResultWPs[tObjectName], L["Anderer Kontinent"]..";"..SkuNav:GetContinentNameFromContinentId(tData.ContinentID)..";"..tData.AreaName_lang[Sku.Loc])

										end
									end
								end
							end
						end
					end
				end
			end
		end

	elseif aSubType == "creature" then
		CreatureIdHelper(aSubIDTable, tResultWPs, aOnly3)

	elseif aSubType == "waypoint" then
		for i, tWaypointName in pairs(aSubIDTable) do
			local tData = SkuNav:GetWaypointData2(tWaypointName)
			if tData then
				local isUiMap = SkuNav:GetUiMapIdFromAreaId(tData.areaId)
				--we don't care for stuff that isn't in the open world
				if isUiMap then
					if not tResultWPs[tWaypointName] then
						tResultWPs[tWaypointName] = {}
					end			
					if tPlayerContinentID == tData.contintentId then
						table.insert(tResultWPs[tWaypointName], tWaypointName)
					else
						table.insert(tResultWPs[tWaypointName], L["Anderer Kontinent"]..";"..tWaypointName)
					end
				end
			end
		end
	end

end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuQuest:GetQuestTargetIds(aQuestID, aList)
	local tTargets = {}
	local tTargetType = nil

	if aList[1] then --creatures
		for i, v in pairs(aList[1]) do
			if type(v) == "number" then
				tTargets[#tTargets+1] = v
			else
				tTargets[#tTargets+1] = v[1]
			end
		end
		tTargetType = "creature"

	elseif aList[2] then --objects
		for i, v in pairs(aList[2]) do
			if type(v) == "number" then
				tTargets[#tTargets+1] = v
			else
				tTargets[#tTargets+1] = v[1]
			end
		end
		tTargetType = "object"

	elseif aList[3] then --items
		for i, v in pairs(aList[3]) do
			if type(v) == "number" then
				tTargets[#tTargets+1] = v
			else
				tTargets[#tTargets+1] = v[1]
			end
		end
		tTargetType = "item"

	elseif aList[4] then--rep
		-- TO IMPLEMENT


	elseif aList[5] then--kills
		tTargets = aList[5][1]
		tTargetType = "creature"

	elseif SkuDB.questDataTBC[aQuestID][SkuDB.questKeys.triggerEnd] then--triggerEnd
		tTargets = SkuQuest:GetTriggerEndWps(aQuestID)
		tTargetType = "waypoint"
	end
	
	return tTargets, tTargetType
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuQuest:GetTriggerEndWps(aQuestId)
	local tWaypoints = {}
	if SkuDB.questDataTBC[aQuestId][SkuDB.questKeys["triggerEnd"]] ~= nil then 
		for zone, data in pairs(SkuDB.questDataTBC[aQuestId][SkuDB.questKeys["triggerEnd"]][2]) do
			local _, taName = SkuNav:GetAreaData(zone)
			if taName then
				if SkuDB.questLookup[Sku.Loc][aQuestId] then
					tWaypoints[#tWaypoints + 1] = SkuDB.questLookup[Sku.Loc][aQuestId][1]..";"..taName..";"..L["Questziel"]..";"..data[1][1]..";"..data[1][2]
				end
			end
		end
	end

	return tWaypoints
end

----------------------------------------------------------------------------------------------------------------------------------------
-- event utilities
----------------------------------------------------------------------------------------------------------------------------------------
function SkuQuest:LoadEventHandler()
	if QuestieLoader then
		SkuQuest.Event = QuestieLoader:ImportModule("QuestieEvent") 

		SkuQuest.Event.eventQuests = {}

		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8684}) -- Dreamseer the Elder
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8635}) -- Splitrock the Elder
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8883}) -- Valadar Starsong
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8713}) -- Starsong the Elder
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8867}) -- Lunar Fireworks
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8865}) -- Festive Lunar Pant Suits
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8868}) -- Elune's Blessing
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8642}) -- Silvervein the Elder
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8866}) -- Bronzebeard the Elder
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8643}) -- Highpeak the Elder
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8678}) -- Proudhorn the Elder
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8864}) -- Festive Lunar Dresses
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8670}) -- Runetotem the Elder
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8725}) -- Riversong the Elder
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8683}) -- Dawnstrider the Elder
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8879}) -- Large Rockets
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8716}) -- Starglade the Elder
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8650}) -- Snowcrown the Elder
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8876}) -- Small Rockets
		-- tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8874}) -- The Lunar Festival
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8880}) -- Cluster Rockets
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8722}) -- Meadowrun the Elder
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8652}) -- Graveborn the Elder
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8878}) -- Festive Recipes
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8873}) -- The Lunar Festival
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8720}) -- Skygleam the Elder
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8673}) -- Bloodhoof the Elder
		-- tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8875}) -- The Lunar Festival
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8862}) -- Elune's Candle
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8723}) -- Nightwind the Elder
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8681}) -- Thunderhorn the Elder
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8676}) -- Wildmane the Elder
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8651}) -- Ironband the Elder
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8863}) -- Festival Dumplings
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8672}) -- Stonespire the Elder
		-- tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8870}) -- The Lunar Festival
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8871}) -- The Lunar Festival
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8649}) -- Stormbrow the Elder
		-- tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8872}) -- The Lunar Festival
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8726}) -- Brightspear the Elder
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8877}) -- Firework Launcher
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8718}) -- Bladeswift the Elder
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8685}) -- Mistwalker the Elder
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8653}) -- Goldwell the Elder
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8671}) -- Ragetotem the Elder
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8677}) -- Darkhorn the Elder
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8882}) -- Cluster Launcher
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8714}) -- Moonstrike the Elder
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8645}) -- Obsidian the Elder
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8717}) -- Moonwarden the Elder
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8648}) -- Darkcore the Elder
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8715}) -- Bladeleaf the Elder
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8646}) -- Hammershout the Elder
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8724}) -- Morningdew the Elder
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8727}) -- Farwhisper the Elder
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8679}) -- Grimtotem the Elder
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8647}) -- Bellowrage the Elder
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8674}) -- Winterhoof the Elder
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8680}) -- Windtotem the Elder
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8686}) -- High Mountain the Elder
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8654}) -- Primestone the Elder
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8721}) -- Starweave the Elder
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8881}) -- Large Cluster Rockets
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8619}) -- Morndeep the Elder
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8688}) -- Windrun the Elder
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8682}) -- Skyseer the Elder
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8636}) -- Rumblerock the Elder
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8644}) -- Stonefort the Elder
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8675}) -- Skychaser the Elder
		tinsert(SkuQuest.Event.eventQuests, {"Lunar Festival", 8719}) -- Bladesing the Elder

		tinsert(SkuQuest.Event.eventQuests, {"Love is in the Air", 8897}) -- Dearest Colara
		tinsert(SkuQuest.Event.eventQuests, {"Love is in the Air", 8898}) -- Dearest Colara
		tinsert(SkuQuest.Event.eventQuests, {"Love is in the Air", 8899}) -- Dearest Colara
		tinsert(SkuQuest.Event.eventQuests, {"Love is in the Air", 8900}) -- Dearest Elenia
		tinsert(SkuQuest.Event.eventQuests, {"Love is in the Air", 8901}) -- Dearest Elenia
		tinsert(SkuQuest.Event.eventQuests, {"Love is in the Air", 8902}) -- Dearest Elenia
		tinsert(SkuQuest.Event.eventQuests, {"Love is in the Air", 8903}) -- Dangerous Love
		tinsert(SkuQuest.Event.eventQuests, {"Love is in the Air", 8904}) -- Dangerous Love
		tinsert(SkuQuest.Event.eventQuests, {"Love is in the Air", 8979}) -- Fenstad's Hunch
		tinsert(SkuQuest.Event.eventQuests, {"Love is in the Air", 8980}) -- Zinge's Assessment
		tinsert(SkuQuest.Event.eventQuests, {"Love is in the Air", 8981}) -- Gift Giving
		tinsert(SkuQuest.Event.eventQuests, {"Love is in the Air", 8982}) -- Tracing the Source
		tinsert(SkuQuest.Event.eventQuests, {"Love is in the Air", 8983}) -- Tracing the Source
		tinsert(SkuQuest.Event.eventQuests, {"Love is in the Air", 8984}) -- The Source Revealed
		tinsert(SkuQuest.Event.eventQuests, {"Love is in the Air", 8993}) -- Gift Giving
		tinsert(SkuQuest.Event.eventQuests, {"Love is in the Air", 9024}) -- Aristan's Hunch
		tinsert(SkuQuest.Event.eventQuests, {"Love is in the Air", 9025}) -- Morgan's Discovery
		tinsert(SkuQuest.Event.eventQuests, {"Love is in the Air", 9026}) -- Tracing the Source
		tinsert(SkuQuest.Event.eventQuests, {"Love is in the Air", 9027}) -- Tracing the Source
		tinsert(SkuQuest.Event.eventQuests, {"Love is in the Air", 9028}) -- The Source Revealed
		tinsert(SkuQuest.Event.eventQuests, {"Love is in the Air", 9029}) -- A Bubbling Cauldron

		tinsert(SkuQuest.Event.eventQuests, {"Children's Week", 171}) -- A Warden of the Alliance
		tinsert(SkuQuest.Event.eventQuests, {"Children's Week", 5502}) -- A Warden of the Horde
		tinsert(SkuQuest.Event.eventQuests, {"Children's Week", 172}) -- Children's Week
		tinsert(SkuQuest.Event.eventQuests, {"Children's Week", 1468}) -- Children's Week
		tinsert(SkuQuest.Event.eventQuests, {"Children's Week", 915}) -- You Scream, I Scream...
		tinsert(SkuQuest.Event.eventQuests, {"Children's Week", 4822}) -- You Scream, I Scream...
		tinsert(SkuQuest.Event.eventQuests, {"Children's Week", 1687}) -- Spooky Lighthouse
		tinsert(SkuQuest.Event.eventQuests, {"Children's Week", 558}) -- Jaina's Autograph
		tinsert(SkuQuest.Event.eventQuests, {"Children's Week", 925}) -- Cairne's Hoofprint
		tinsert(SkuQuest.Event.eventQuests, {"Children's Week", 1800}) -- Lordaeron Throne Room
		tinsert(SkuQuest.Event.eventQuests, {"Children's Week", 1479}) -- The Bough of the Eternals
		tinsert(SkuQuest.Event.eventQuests, {"Children's Week", 1558}) -- The Stonewrought Dam
		tinsert(SkuQuest.Event.eventQuests, {"Children's Week", 910}) -- Down at the Docks
		tinsert(SkuQuest.Event.eventQuests, {"Children's Week", 911}) -- Gateway to the Frontier

		tinsert(SkuQuest.Event.eventQuests, {"Harvest Festival", 8149}) -- Honoring a Hero
		tinsert(SkuQuest.Event.eventQuests, {"Harvest Festival", 8150}) -- Honoring a Hero

		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 8373}) -- The Power of Pine
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 1658}) -- Crashing the Wickerman Festival
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 8311}) -- Hallow's End Treats for Jesper!
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 8312}) -- Hallow's End Treats for Spoops!
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 8322}) -- Rotten Eggs
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 1657}) -- Stinking Up Southshore
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 8409}) -- Ruined Kegs
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 8357}) -- Dancing for Marzipan
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 8355}) -- Incoming Gumdrop
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 8356}) -- Flexing for Nougat
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 8358}) -- Incoming Gumdrop
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 8353}) -- Chicken Clucking for a Mint
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 8359}) -- Flexing for Nougat
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 8354}) -- Chicken Clucking for a Mint
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 8360}) -- Dancing for Marzipan

		tinsert(SkuQuest.Event.eventQuests, {"Winter Veil", 6961}) -- Great-father Winter is Here!
		tinsert(SkuQuest.Event.eventQuests, {"Winter Veil", 7021}) -- Great-father Winter is Here!
		tinsert(SkuQuest.Event.eventQuests, {"Winter Veil", 7022}) -- Greatfather Winter is Here!
		tinsert(SkuQuest.Event.eventQuests, {"Winter Veil", 7023}) -- Greatfather Winter is Here!
		tinsert(SkuQuest.Event.eventQuests, {"Winter Veil", 7024}) -- Great-father Winter is Here!
		tinsert(SkuQuest.Event.eventQuests, {"Winter Veil", 6962}) -- Treats for Great-father Winter
		tinsert(SkuQuest.Event.eventQuests, {"Winter Veil", 7025}) -- Treats for Greatfather Winter
		tinsert(SkuQuest.Event.eventQuests, {"Winter Veil", 7043}) -- You're a Mean One...
		tinsert(SkuQuest.Event.eventQuests, {"Winter Veil", 6983}) -- You're a Mean One...
		tinsert(SkuQuest.Event.eventQuests, {"Winter Veil", 6984}) -- A Smokywood Pastures' Thank You!
		tinsert(SkuQuest.Event.eventQuests, {"Winter Veil", 7045}) -- A Smokywood Pastures' Thank You!
		tinsert(SkuQuest.Event.eventQuests, {"Winter Veil", 7063}) -- The Feast of Winter Veil
		tinsert(SkuQuest.Event.eventQuests, {"Winter Veil", 7061}) -- The Feast of Winter Veil
		tinsert(SkuQuest.Event.eventQuests, {"Winter Veil", 6963}) -- Stolen Winter Veil Treats
		tinsert(SkuQuest.Event.eventQuests, {"Winter Veil", 7042}) -- Stolen Winter Veil Treats
		tinsert(SkuQuest.Event.eventQuests, {"Winter Veil", 7062}) -- The Reason for the Season
		tinsert(SkuQuest.Event.eventQuests, {"Winter Veil", 8763}) -- The Hero of the Day
		tinsert(SkuQuest.Event.eventQuests, {"Winter Veil", 8799}) -- The Hero of the Day
		tinsert(SkuQuest.Event.eventQuests, {"Winter Veil", 6964}) -- The Reason for the Season
		tinsert(SkuQuest.Event.eventQuests, {"Winter Veil", 8762}) -- Metzen the Reindeer
		tinsert(SkuQuest.Event.eventQuests, {"Winter Veil", 8746}) -- Metzen the Reindeer
		tinsert(SkuQuest.Event.eventQuests, {"Winter Veil", 8744, "25/12", "2/1"}) -- A Carefully Wrapped Present
		tinsert(SkuQuest.Event.eventQuests, {"Winter Veil", 8767, "25/12", "2/1"}) -- A Gently Shaken Gift
		tinsert(SkuQuest.Event.eventQuests, {"Winter Veil", 8768, "25/12", "2/1"}) -- A Gaily Wrapped Present
		tinsert(SkuQuest.Event.eventQuests, {"Winter Veil", 8769, "25/12", "2/1"}) -- A Ticking Present
		tinsert(SkuQuest.Event.eventQuests, {"Winter Veil", 8788, "25/12", "2/1"}) -- A Gently Shaken Gift
		tinsert(SkuQuest.Event.eventQuests, {"Winter Veil", 8803, "25/12", "2/1"}) -- A Festive Gift
		tinsert(SkuQuest.Event.eventQuests, {"Winter Veil", 8827, "25/12", "2/1"}) -- Winter's Presents
		tinsert(SkuQuest.Event.eventQuests, {"Winter Veil", 8828, "25/12", "2/1"}) -- Winter's Presents

		-- tinsert(SkuQuest.Event.eventQuests, {"-1006", 8861}) --New Year Celebrations!
		-- tinsert(SkuQuest.Event.eventQuests, {"-1006", 8860}) --New Year Celebrations!

		tinsert(SkuQuest.Event.eventQuests, {"Darkmoon Faire", 7902}) -- Vibrant Plumes
		tinsert(SkuQuest.Event.eventQuests, {"Darkmoon Faire", 7903}) -- Evil Bat Eyes
		tinsert(SkuQuest.Event.eventQuests, {"Darkmoon Faire", 8222}) -- Glowing Scorpid Blood
		tinsert(SkuQuest.Event.eventQuests, {"Darkmoon Faire", 7901}) -- Soft Bushy Tails
		tinsert(SkuQuest.Event.eventQuests, {"Darkmoon Faire", 7899}) -- Small Furry Paws
		tinsert(SkuQuest.Event.eventQuests, {"Darkmoon Faire", 7940}) -- 1200 Tickets - Orb of the Darkmoon
		tinsert(SkuQuest.Event.eventQuests, {"Darkmoon Faire", 7900}) -- Torn Bear Pelts
		tinsert(SkuQuest.Event.eventQuests, {"Darkmoon Faire", 7907}) -- Darkmoon Beast Deck
		tinsert(SkuQuest.Event.eventQuests, {"Darkmoon Faire", 7927}) -- Darkmoon Portals Deck
		tinsert(SkuQuest.Event.eventQuests, {"Darkmoon Faire", 7929}) -- Darkmoon Elementals Deck
		tinsert(SkuQuest.Event.eventQuests, {"Darkmoon Faire", 7928}) -- Darkmoon Warlords Deck
		tinsert(SkuQuest.Event.eventQuests, {"Darkmoon Faire", 7946}) -- Spawn of Jubjub
		tinsert(SkuQuest.Event.eventQuests, {"Darkmoon Faire", 8223}) -- More Glowing Scorpid Blood
		tinsert(SkuQuest.Event.eventQuests, {"Darkmoon Faire", 7934}) -- 50 Tickets - Darkmoon Storage Box
		tinsert(SkuQuest.Event.eventQuests, {"Darkmoon Faire", 7981}) -- 1200 Tickets - Amulet of the Darkmoon
		tinsert(SkuQuest.Event.eventQuests, {"Darkmoon Faire", 7943}) -- More Bat Eyes
		tinsert(SkuQuest.Event.eventQuests, {"Darkmoon Faire", 7894}) -- Copper Modulator
		tinsert(SkuQuest.Event.eventQuests, {"Darkmoon Faire", 7933}) -- 40 Tickets - Greater Darkmoon Prize
		tinsert(SkuQuest.Event.eventQuests, {"Darkmoon Faire", 7898}) -- Thorium Widget
		tinsert(SkuQuest.Event.eventQuests, {"Darkmoon Faire", 7885}) -- Armor Kits
		tinsert(SkuQuest.Event.eventQuests, {"Darkmoon Faire", 7942}) -- More Thorium Widgets
		tinsert(SkuQuest.Event.eventQuests, {"Darkmoon Faire", 7883}) -- The World's Largest Gnome!
		tinsert(SkuQuest.Event.eventQuests, {"Darkmoon Faire", 7892}) -- Big Black Mace
		tinsert(SkuQuest.Event.eventQuests, {"Darkmoon Faire", 7937}) -- Your Fortune Awaits You...
		tinsert(SkuQuest.Event.eventQuests, {"Darkmoon Faire", 7939}) -- More Dense Grinding Stones
		tinsert(SkuQuest.Event.eventQuests, {"Darkmoon Faire", 7893}) -- Rituals of Strength
		tinsert(SkuQuest.Event.eventQuests, {"Darkmoon Faire", 7891}) -- Green Iron Bracers
		tinsert(SkuQuest.Event.eventQuests, {"Darkmoon Faire", 7896}) -- Green Fireworks
		tinsert(SkuQuest.Event.eventQuests, {"Darkmoon Faire", 7884}) -- Crocolisk Boy and the Bearded Murloc
		tinsert(SkuQuest.Event.eventQuests, {"Darkmoon Faire", 7882}) -- Carnival Jerkins
		tinsert(SkuQuest.Event.eventQuests, {"Darkmoon Faire", 7897}) -- Mechanical Repair Kits
		tinsert(SkuQuest.Event.eventQuests, {"Darkmoon Faire", 7895}) -- Whirring Bronze Gizmo
		tinsert(SkuQuest.Event.eventQuests, {"Darkmoon Faire", 7941}) -- More Armor Kits
		tinsert(SkuQuest.Event.eventQuests, {"Darkmoon Faire", 7881}) -- Carnival Boots
		tinsert(SkuQuest.Event.eventQuests, {"Darkmoon Faire", 7890}) -- Heavy Grinding Stone
		tinsert(SkuQuest.Event.eventQuests, {"Darkmoon Faire", 7889}) -- Coarse Weightstone
		tinsert(SkuQuest.Event.eventQuests, {"Darkmoon Faire", 7945}) -- Your Fortune Awaits You...
		tinsert(SkuQuest.Event.eventQuests, {"Darkmoon Faire", 7935}) -- 10 Tickets - Last Month's Mutton
		tinsert(SkuQuest.Event.eventQuests, {"Darkmoon Faire", 7938}) -- Your Fortune Awaits You...
		tinsert(SkuQuest.Event.eventQuests, {"Darkmoon Faire", 7944}) -- Your Fortune Awaits You...
		tinsert(SkuQuest.Event.eventQuests, {"Darkmoon Faire", 7932}) -- 12 Tickets - Lesser Darkmoon Prize
		tinsert(SkuQuest.Event.eventQuests, {"Darkmoon Faire", 7930}) -- 5 Tickets - Darkmoon Flower
		tinsert(SkuQuest.Event.eventQuests, {"Darkmoon Faire", 7931}) -- 5 Tickets - Minor Darkmoon Prize
		tinsert(SkuQuest.Event.eventQuests, {"Darkmoon Faire", 7936}) -- 50 Tickets - Last Year's Mutton

		-- New TBC event quests

		tinsert(SkuQuest.Event.eventQuests, {"Children's Week", 10942}) -- Children's Week
		tinsert(SkuQuest.Event.eventQuests, {"Children's Week", 10943}) -- Children's Week

		tinsert(SkuQuest.Event.eventQuests, {"Darkmoon Faire", 9249}) -- 40 Tickets - Schematic: Steam Tonk Controller
		tinsert(SkuQuest.Event.eventQuests, {"Darkmoon Faire", 10938}) -- Darkmoon Blessings Deck
		tinsert(SkuQuest.Event.eventQuests, {"Darkmoon Faire", 10939}) -- Darkmoon Storms Deck
		tinsert(SkuQuest.Event.eventQuests, {"Darkmoon Faire", 10940}) -- Darkmoon Furies Deck
		tinsert(SkuQuest.Event.eventQuests, {"Darkmoon Faire", 10941}) -- Darkmoon Lunacy Deck

		--tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 11450}) -- Fire Training
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 11356}) -- Costumed Orphan Matron
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 11357}) -- Masked Orphan Matron
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 11131}) -- Stop the Fires!
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 11135}) -- The Headless Horseman
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 11220}) -- The Headless Horseman
		--tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 11219}) -- Stop the Fires!
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 11361}) -- Fire Training
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 11360}) -- Fire Brigade Practice
		--tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 11449}) -- Fire Training
		--tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 11440}) -- Fire Brigade Practice
		--tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 11439}) -- Fire Brigade Practice
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12133}) -- Smash the Pumpkin
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12135}) -- Let the Fires Come!
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12139}) -- Let the Fires Come!
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12155}) -- Smash the Pumpkin
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12286}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12331}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12332}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12333}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12334}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12335}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12336}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12337}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12338}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12339}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12340}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12341}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12342}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12343}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12344}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12345}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12346}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12347}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12348}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12349}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12350}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12351}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12352}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12353}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12354}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12355}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12356}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12357}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12358}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12359}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12360}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12361}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12362}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12363}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12364}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12365}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12366}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12367}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12368}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12369}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12370}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12371}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12373}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12374}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12375}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12376}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12377}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12378}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12379}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12380}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12381}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12382}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12383}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12384}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12385}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12386}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12387}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12388}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12389}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12390}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12391}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12392}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12393}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12394}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12395}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12396}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12397}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12398}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12399}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12400}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12401}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12402}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12403}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12404}) -- Candy Bucket
		--tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12405}) -- Candy Bucket -- doesn't exist
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12406}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12407}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12408}) -- Candy Bucket
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12409}) -- Candy Bucket
		--tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 12410}) -- Candy Bucket -- doesn't exist
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 11392}) -- Call the Headless Horseman
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 11401}) -- Call the Headless Horseman
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 11403}) -- Free at Last!
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 11404}) -- Call the Headless Horseman
		tinsert(SkuQuest.Event.eventQuests, {"Hallow's End", 11405}) -- Call the Headless Horseman

		tinsert(SkuQuest.Event.eventQuests, {"Brewfest", 11127}) -- <NYI>Thunderbrew Secrets
		tinsert(SkuQuest.Event.eventQuests, {"Brewfest", 12022}) -- Chug and Chuck!
		tinsert(SkuQuest.Event.eventQuests, {"Brewfest", 11117}) -- Catch the Wild Wolpertinger!
		tinsert(SkuQuest.Event.eventQuests, {"Brewfest", 11318}) -- Now This is Ram Racing... Almost.
		tinsert(SkuQuest.Event.eventQuests, {"Brewfest", 11409}) -- Now This is Ram Racing... Almost.
		tinsert(SkuQuest.Event.eventQuests, {"Brewfest", 11438}) -- [PH] Beer Garden B
		tinsert(SkuQuest.Event.eventQuests, {"Brewfest", 12020}) -- This One Time, When I Was Drunk...
		tinsert(SkuQuest.Event.eventQuests, {"Brewfest", 12192}) -- This One Time, When I Was Drunk...
		tinsert(SkuQuest.Event.eventQuests, {"Brewfest", 11437}) -- [PH] Beer Garden A
		--tinsert(SkuQuest.Event.eventQuests, {"Brewfest", 11454}) -- Seek the Saboteurs
		tinsert(SkuQuest.Event.eventQuests, {"Brewfest", 12420}) -- Brew of the Month Club
		tinsert(SkuQuest.Event.eventQuests, {"Brewfest", 12421}) -- Brew of the Month Club
		--tinsert(SkuQuest.Event.eventQuests, {"Brewfest", 12306}) -- Brew of the Month Club
		tinsert(SkuQuest.Event.eventQuests, {"Brewfest", 11120}) -- Pink Elekks On Parade
		tinsert(SkuQuest.Event.eventQuests, {"Brewfest", 11400}) -- Brewfest Riding Rams
		tinsert(SkuQuest.Event.eventQuests, {"Brewfest", 11442}) -- Welcome to Brewfest!
		tinsert(SkuQuest.Event.eventQuests, {"Brewfest", 11447}) -- Welcome to Brewfest!
		--tinsert(SkuQuest.Event.eventQuests, {"Brewfest", 12278}) -- Brew of the Month Club
		tinsert(SkuQuest.Event.eventQuests, {"Brewfest", 11118}) -- Pink Elekks On Parade
		tinsert(SkuQuest.Event.eventQuests, {"Brewfest", 11320}) -- [NYI] Now this is Ram Racing... Almost.
		tinsert(SkuQuest.Event.eventQuests, {"Brewfest", 11441}) -- Brewfest!
		tinsert(SkuQuest.Event.eventQuests, {"Brewfest", 11446}) -- Brewfest!
		tinsert(SkuQuest.Event.eventQuests, {"Brewfest", 12062}) -- Insult Coren Direbrew
		tinsert(SkuQuest.Event.eventQuests, {"Brewfest", 12194}) -- Say, There Wouldn't Happen to be a Souvenir This Year, Would There?
		tinsert(SkuQuest.Event.eventQuests, {"Brewfest", 12191}) -- Chug and Chuck!
		tinsert(SkuQuest.Event.eventQuests, {"Brewfest", 11293}) -- Bark for the Barleybrews!
		tinsert(SkuQuest.Event.eventQuests, {"Brewfest", 11294}) -- Bark for the Thunderbrews!
		tinsert(SkuQuest.Event.eventQuests, {"Brewfest", 11407})
		tinsert(SkuQuest.Event.eventQuests, {"Brewfest", 11412})
		tinsert(SkuQuest.Event.eventQuests, {"Brewfest", 12022})
		tinsert(SkuQuest.Event.eventQuests, {"Brewfest", 12491})
		tinsert(SkuQuest.Event.eventQuests, {"Brewfest", 12492})
		tinsert(SkuQuest.Event.eventQuests, {"Brewfest", 11118})
		tinsert(SkuQuest.Event.eventQuests, {"Brewfest", 11122})
		tinsert(SkuQuest.Event.eventQuests, {"Brewfest", 11293})
		tinsert(SkuQuest.Event.eventQuests, {"Brewfest", 11408})
		tinsert(SkuQuest.Event.eventQuests, {"Brewfest", 12191})
		tinsert(SkuQuest.Event.eventQuests, {"Brewfest", 11294})
		tinsert(SkuQuest.Event.eventQuests, {"Brewfest", 12192})
		tinsert(SkuQuest.Event.eventQuests, {"Brewfest", 11120})
		tinsert(SkuQuest.Event.eventQuests, {"Brewfest", 12020})	


		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 9324}) -- Stealing Orgrimmar's Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 9325}) -- Stealing Thunder Bluff's Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 9326}) -- Stealing the Undercity's Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 9330}) -- Stealing Stormwind's Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 9331}) -- Stealing Ironforge's Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 9332}) -- Stealing Darnassus's Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 9339}) -- A Thief's Reward
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 9365}) -- A Thief's Reward

		-- Removed in TBC
		--tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 9388}) -- Flickering Flames in Kalimdor
		--tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 9389}) -- Flickering Flames in the Eastern Kingdoms
		--tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 9319}) -- A Light in Dark Places
		--tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 9386}) -- A Light in Dark Places
		--tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 9367}) -- The Festival of Fire
		--tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 9368}) -- The Festival of Fire
		--tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 9322}) -- Wild Fires in Kalimdor
		--tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 9323}) -- Wild Fires in the Eastern Kingdoms

		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11580}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11581}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11583}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11584}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11691}) -- Summon Ahune
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11696}) -- Ahune is Here!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11731}) -- Torch Tossing
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11732}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11734}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11735}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11736}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11737}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11738}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11739}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11740}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11741}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11742}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11743}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11744}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11745}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11746}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11747}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11748}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11749}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11750}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11751}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11752}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11753}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11754}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11755}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11756}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11757}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11758}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11759}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11760}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11761}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11762}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11763}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11764}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11765}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11766}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11767}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11768}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11769}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11770}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11771}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11772}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11773}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11774}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11775}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11776}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11777}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11778}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11779}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11780}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11781}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11782}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11783}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11784}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11785}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11786}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11787}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11799}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11800}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11801}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11802}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11803}) -- Desecrate this Fire!
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11804}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11805}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11806}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11807}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11808}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11809}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11810}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11811}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11812}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11813}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11814}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11815}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11816}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11817}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11818}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11819}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11820}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11821}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11822}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11823}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11824}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11825}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11826}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11827}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11828}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11829}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11830}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11831}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11832}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11833}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11834}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11835}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11836}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11837}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11838}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11839}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11840}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11841}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11842}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11843}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11844}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11845}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11846}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11847}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11848}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11849}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11850}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11851}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11852}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11853}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11854}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11855}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11856}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11857}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11858}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11859}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11860}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11861}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11862}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11863}) -- Honor the Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11882}) -- Playing with Fire
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11886}) -- Unusual Activity
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11915}) -- Playing with Fire
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11921}) -- Midsummer
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11922}) -- Midsummer
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11923}) -- Midsummer
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11924}) -- Midsummer
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11925}) -- Midsummer
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11926}) -- Midsummer
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11933}) -- Stealing the Exodar's Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11935}) -- Stealing Silvermoon's Flame
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11954}) -- Striking Back (level 67)
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11955}) -- Ahune, the Frost Lord
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11972}) -- Shards of Ahune
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11964}) -- Incense for the Summer Scorchlings
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11966}) -- Incense for the Festival Scorchlings
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11970}) -- The Master of Summer Lore
		tinsert(SkuQuest.Event.eventQuests, {"Midsummer", 11971}) -- The Spinner of Summer Tales

		tinsert(SkuQuest.Event.eventQuests, {"Winter Veil", 11528}) -- A Winter Veil Gift

		SkuQuest.Event:Load() 

	else
		SkuQuest.Event = {
			GetEventNameFor = function()
				return nil
			end,
			IsEventQuest = function()
				return false
			end,
		}
	end

	SkuQuest.IsEventQuest = SkuQuest.Event.IsEventQuest
	SkuQuest.GetEventNameFor = SkuQuest.Event.GetEventNameFor
end

function SkuQuest:IsEventActive(aEventName)
	if not SkuQuest.Event then
		return
	end
	if not SkuQuest.Event.eventDates[aEventName] then
		return
	end

	local tStartDay, tStartMonth = strsplit("/", SkuQuest.Event.eventDates[aEventName].startDate)
	local tEndDay, tEndMonth = strsplit("/", SkuQuest.Event.eventDates[aEventName].endDate)
	dprint("  ", tStartDay, tStartMonth, "-", tEndDay, tEndMonth)
	local tResult = SkuQuest:WithinDates(tonumber(tStartDay), tonumber(tStartMonth),tonumber(tEndDay), tonumber(tEndMonth))
	return tResult
end

function SkuQuest:WithinDates(startDay, startMonth, endDay, endMonth)
	if (not startDay) and (not startMonth) and (not endDay) and (not endMonth) then
		 return true
	end
	local date = (C_DateAndTime.GetTodaysDate or C_DateAndTime.GetCurrentCalendarTime)()
	local day = date.day or date.monthDay
	local month = date.month
	if (month < startMonth) or -- Too early in the year
		 (month > endMonth) or -- Too late in the year
		 (month == startMonth and day < startDay) or -- Too early in the correct month
		 (month == endMonth and day > endDay) then -- Too late in the correct month
		 return false
	else
		 return true
	end
end

function SkuQuest:IsEventQuest()
	return false
end

function SkuQuest:GetEventNameFor()
	return nil
end
