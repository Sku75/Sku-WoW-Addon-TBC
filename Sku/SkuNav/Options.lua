local MODULE_NAME = "SkuNav"
local L = Sku.L

local ssub = string.sub
local slen = string.len

SkuNav.ClickClackSoundsets = {}

-- [41.05] Fix fuer leeres "Ton fuer Klick bei Beacons"-Menue (Timing-Rennen):
-- Die Klick-Toene werden vom externen Addon SkuBeaconSoundsets erst im Event
-- PLAYER_ENTERING_WORLD registriert; SkuNav\Core.lua (geschuetzt) befuellt die
-- Liste dort aber SYNCHRON und damit oft zu frueh (leer). Dieser additive
-- Nachzieher baut die Liste kurz NACH dem Event neu auf und zeigt die Auswahl
-- darauf um. Aendert die geschuetzte Core.lua nicht; schlimmstenfalls ein No-Op.
local tCCFixFrame = CreateFrame("Frame")
tCCFixFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
tCCFixFrame:SetScript("OnEvent", function()
	C_Timer.After(2, function()
		pcall(function()
			if not (SkuOptions and SkuOptions.BeaconLib and SkuOptions.BeaconLib.GetClickClackSoundSets) then return end
			local t = {}
			t["off"] = L["Nichts"]
			for k, v in pairs(SkuOptions.BeaconLib:GetClickClackSoundSets()) do
				if type(v) == "table" and v.friendlyName then
					t[k] = v.friendlyName
				end
			end
			SkuNav.ClickClackSoundsets = t
			if SkuNav.options and SkuNav.options.args and SkuNav.options.args.clickClackSoundset then
				SkuNav.options.args.clickClackSoundset.values = t
			end
		end)
	end)
end)

SkuNav.StandardWpReachedRanges = {
   [1] = L["1 Meter"],
   [2] = L["2 Meter"],
   [3] = L["3 Meter"],
   [4] = L["Auto"],
}

SkuNav.RoutesMaxDistances = {
   [2000] = "3000 "..L["meters"],
   [4000] = "4000 "..L["meters"],
   [5000] = "5000 "..L["meters"],
   [6000] = "6000 "..L["meters"],
   [8000] = "8000 "..L["meters"],
   [20000] = L["Unlimited"],
}

local timeForVisitedToExpireValues = {L["disabled"], "1 "..L["minute"]}
for i=2, 30 do
	timeForVisitedToExpireValues[i+1] = i .. L[" Minuten"]
end


SkuNav.options = {
	name = MODULE_NAME,
	type = "group",
	args = {
		beaconVolume = {
			order = 2,
			name = L["Beacon Volume"],
			desc = "",
			type = "range",
		},
		beaconSoundSetNarrow = {
			order = 3,
			name = L["narrow beacon sound set"],
			desc = "",
			type = "select",
			values = SkuNav.BeaconSoundSetNames,
			OnAction = function(self, info, val)
				local tPlayerPosX, tPlayerPosY = UnitPosition("player")
				if not SkuOptions.BeaconLib:CreateBeacon("SkuOptions", "sampleBeacon", SkuNav.BeaconSoundSetNames[val], tPlayerPosX + 10, tPlayerPosY, -3, 0, SkuSettings:Sub("SkuNav").beaconVolume, SkuSettings:Sub("SkuNav").clickClackRange, nil, nil, nil, nil, SkuSettings:Sub("SkuNav").clickClackSoundset) then
					return
				end
				SkuOptions.BeaconLib:StartBeacon("SkuOptions", "sampleBeacon")
				C_Timer.After(1, function()
					SkuOptions.BeaconLib:DestroyBeacon("SkuOptions", "sampleBeacon")
				end)
			end,	
			set = function(info,val)
				SkuSettings:Sub("SkuNav").beaconSoundSetNarrow = SkuNav.BeaconSoundSetNames[val]
			end,
			get = function(info)
				return SkuSettings:Sub("SkuNav").beaconSoundSetNarrow
			end
		},
		beaconSoundSetWide = {
			order = 4,
			name = L["wide beacon sound set"],
			desc = "",
			type = "select",
			values = SkuNav.BeaconSoundSetNames,
			OnAction = function(self, info, val)
				local tPlayerPosX, tPlayerPosY = UnitPosition("player")
				if not SkuOptions.BeaconLib:CreateBeacon("SkuOptions", "sampleBeacon", SkuNav.BeaconSoundSetNames[val], tPlayerPosX + 10, tPlayerPosY, -3, 0, SkuSettings:Sub("SkuNav").beaconVolume, SkuSettings:Sub("SkuNav").clickClackRange, nil, nil, nil, nil, SkuSettings:Sub("SkuNav").clickClackSoundset) then
					return
				end
				SkuOptions.BeaconLib:StartBeacon("SkuOptions", "sampleBeacon")
				C_Timer.After(1, function()
					SkuOptions.BeaconLib:DestroyBeacon("SkuOptions", "sampleBeacon")
				end)
			end,				
			set = function(info,val)
				SkuSettings:Sub("SkuNav").beaconSoundSetWide = SkuNav.BeaconSoundSetNames[val]
			end,
			get = function(info)
				return SkuSettings:Sub("SkuNav").beaconSoundSetWide
			end
		},
		clickClackEnabled = {
			order = 5,
			name = L["Klick bei Beacons"],
			desc = "",
			type = "toggle",
			OnAction = function(self, info, val)
			end,
		},
		clickClackRange = {
			order = 6,
			name = L["Winkel für Klick bei Beacons"],
			desc = "",
			type = "range",
		},
		clickClackSoundset = {
			order = 7,
			name = L["Ton für Klick bei Beacons"],
			desc = "",
			type = "select",
			values = SkuNav.ClickClackSoundsets,
			OnAction = function(self, info, val)
			end,
		},
		vocalizeFullDirectionDistance = {
			order = 8,
			name = L["Detailed direction and distance"],
			desc = "",
			type = "toggle",
		},
		vocalizeZoneNames = {
			order = 9,
			name = L["Announce zone names"],
			desc = "",
			type = "toggle",
		},
		nearbyWpRange = {
			order = 10,
			name = L["Range for near route starts"],
			desc = "",
			type = "range",
		},
		standardWpReachedRange = {
			order = 11,
			name = L["Waypoint reached at"],
			desc = "",
			type = "select",
			values = SkuNav.StandardWpReachedRanges,
		},
		autoGlobalDirection = {
			order = 12,
			name = L["Auto announce global direction"],
			desc = "",
			type = "toggle",
		},
		showGlobalDirectionInWaypointLists = {
			order = 13,
			name = L["Show global direction in waypoint lists"],
			desc = "",
			type = "toggle",
		},
		trackVisited = {
			order = 14,
			name = L["Track whether waypoints were visited"],
			desc = "",
			type = "toggle",
		},
		timeForVisitedToExpire = {
			order = 15,
			name = L["visited automatically expires after"],
			desc = "",
			type = "select",
			values = timeForVisitedToExpireValues,
		},
		showGatherWaypoints = {
			order = 16,
			name = L["Show herbs and mining node waypoints"],
			desc = "",
			type = "toggle",
			OnAction = function(self, info, val)
				local t = SkuDB.routedata["global"]["Waypoints"]
				SkuDB.SessionRouteData.Waypoints = t

				local tl = SkuDB.routedata["global"]["Links"]
				SkuDB.SessionRouteData.Links = tl
				SkuNav:CreateWaypointCache()

				for x = 1, 4 do
					local tWaypointName = L["Quick waypoint"]..";"..x
					SkuNav:UpdateQuickWP(tWaypointName, true)
				end			
			end,
			set = function(info,val)
				SkuSettings:Sub("SkuNav").showGatherWaypoints = val
			end,
			get = function(info)
				return SkuSettings:Sub("SkuNav").showGatherWaypoints
			end
		},	
		showRoutesOnMinimap = {
			order = 17,
			name = L["Show routes on minimap"],
			desc = "",
			type = "toggle",
		},
		showSkuMM = {
			order = 18,
			name = L["Show extra minimap"],
			desc = "",
			type = "toggle",
		},

		tomtomWp = {
			order = 19,
			name = L["Auto sound on Tom Tom arrow"],
			desc = "",
			type = "toggle",
		},		
		
		autoNextWaypoint={
			name = L["Auto switching to next similar waypoint"],
			type = "group",
			order = 20,
			args= {
				nonVocalized = {
					order = 5,
					name = L["Don't announce waypoint switching"],
					desc = "",
					type = "toggle",
				},
				reachRange = {
					order = 10,
					name = L["Range for counting a waypoint as reached and switching to next waypoint"],
					desc = "",
					type = "range",
				},
			},
		},
		outputDistance = {
			order = 2,
			name = L["output Distance to next waypoint"],
			desc = "",
			type = "range",
		},
		routesMaxDistance = {
			order = 20,
			name = L["Maximum distance for destinations in routes list"],
			desc = "",
			type = "select",
			values = SkuNav.RoutesMaxDistances,
		},
	}
}
---------------------------------------------------------------------------------------------------------------------------------------
SkuNav.defaults = {
	enable = true,
	--[[
	includeDefaultMapWaypoints = true,
	includeDefaultInkeeperWaypoints = true,
	includeDefaultPostboxWaypoints = true,
	includeDefaultTaxiWaypoints = true,
	]]
	beaconVolume = 35,
	beaconSoundSetNarrow = "Beacon 2",
	beaconSoundSetWide = "Beacon 4",
	vocalizeFullDirectionDistance = true,
	vocalizeZoneNames = true,
	showRoutesOnMinimap = false,
	showSkuMM = false,
	nearbyWpRange = 30,
	tomtomWp = false,
	standardWpReachedRange = 4,
	clickClackEnabled = true,
	clickClackRange = 5,
	clickClackSoundset = "click",
	autoGlobalDirection = false,
	showGlobalDirectionInWaypointLists = true,
	trackVisited = true,
	timeForVisitedToExpire = 6, -- 5 minutes
	showGatherWaypoints = false,
	autoNextWaypoint = {
		nonVocalized = true,
		reachRange = 3,
	},
	outputDistance = 0,
	routesMaxDistance = 5000,
}

-- Settings schema for SkuNav (Sku 42 rework, W2 M-C1 / W1 Phase C). Single
-- source of truth (scope/default/type) for the menu's schema-managed get/set.
-- All keys profile scope (the menu's options.args only touch SkuSettings:Sub(
-- "SkuNav") -- profile). Kept nodes (beaconSoundSetNarrow/Wide transform the
-- value + play a sample beacon; showGatherWaypoints rebuilds the waypoint cache)
-- still carry inline get/set, but are declared here too for completeness.
-- Select value tables are keyed by the stored value: StandardWpReachedRanges,
-- timeForVisitedToExpireValues and RoutesMaxDistances use number keys (=> number),
-- ClickClackSoundsets and the beacon sets use string keys (=> string).
SkuSettings:Register("SkuNav", {
	["beaconVolume"]                       = { scope = "profile", default = 35,         type = "number"  },
	["beaconSoundSetNarrow"]               = { scope = "profile", default = "Beacon 2", type = "string"  },
	["beaconSoundSetWide"]                 = { scope = "profile", default = "Beacon 4", type = "string"  },
	["clickClackEnabled"]                  = { scope = "profile", default = true,       type = "boolean" },
	["clickClackRange"]                    = { scope = "profile", default = 5,          type = "number"  },
	["clickClackSoundset"]                 = { scope = "profile", default = "click",    type = "string"  },
	["vocalizeFullDirectionDistance"]      = { scope = "profile", default = true,       type = "boolean" },
	["vocalizeZoneNames"]                  = { scope = "profile", default = true,       type = "boolean" },
	["nearbyWpRange"]                      = { scope = "profile", default = 30,         type = "number"  },
	["standardWpReachedRange"]             = { scope = "profile", default = 4,          type = "number"  },
	["autoGlobalDirection"]                = { scope = "profile", default = false,      type = "boolean" },
	["showGlobalDirectionInWaypointLists"] = { scope = "profile", default = true,       type = "boolean" },
	["trackVisited"]                       = { scope = "profile", default = true,       type = "boolean" },
	["timeForVisitedToExpire"]             = { scope = "profile", default = 6,          type = "number"  },
	["showGatherWaypoints"]                = { scope = "profile", default = false,      type = "boolean" },
	["showRoutesOnMinimap"]                = { scope = "profile", default = false,      type = "boolean" },
	["showSkuMM"]                          = { scope = "profile", default = false,      type = "boolean" },
	["tomtomWp"]                           = { scope = "profile", default = false,      type = "boolean" },
	["autoNextWaypoint.nonVocalized"]      = { scope = "profile", default = true,       type = "boolean" },
	["autoNextWaypoint.reachRange"]        = { scope = "profile", default = 3,          type = "number"  },
	["outputDistance"]                     = { scope = "profile", default = 0,          type = "number"  },
	["routesMaxDistance"]                  = { scope = "profile", default = 5000,       type = "number"  },
})

local slower = string.lower
local sfind = string.find

---------------------------------------------------------------------------------------------------------------------------------------
local function SkuSpairs(t, order)
	local tSFunction = function(a,b) return order(t, a, b) end
	local keys = {}
	for k in pairs(t) do keys[#keys+1] = k end
	if order then
		table.sort(keys, tSFunction)
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
-- (string, optional<string>) -> string
function SkuNav:getAnnotatedWaypointLabel(originalLabel, id)
	--print("getAnnotatedWaypointLabel", originalLabel, id)

	local tSkuWpName = id or ssub(originalLabel, string.find(originalLabel, "#") + 1)

	--layer
	local tLayerText = SkuNav:GetLayerText(SkuNav:GetNonAutoLevel(nil, nil, tSkuWpName, nil))

	-- annotate with "visited" if visited
	if SkuNav:waypointWasVisited(tSkuWpName) then
		return L["visited"]..";"..tLayerText..originalLabel
	else 
		return tLayerText..originalLabel
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
local function SkuNav_MenuBuilder_WaypointSelectionMenu(aParent, aSortedWaypointList)
	--dprint("SkuNav_MenuBuilder_WaypointSelectionMenu")
	for i, waypointName in pairs(aSortedWaypointList) do
		local tNewMenuEntry = SkuOptions:InjectMenuItems(aParent, {SkuNav:getAnnotatedWaypointLabel(waypointName)}, SkuGenericMenuItem)
		tNewMenuEntry.dynamic = true
		tNewMenuEntry.BuildChildren = function(self)
			SkuOptions.SkuNav_MenuBuilder_WaypointSelectionMenu_NPC = nil
			SkuOptions.SkuNav_MenuBuilder_WaypointSelectionMenu_CloseRoute = nil

			--select wp
			local tNewMenuEntrySub = SkuOptions:InjectMenuItems(self, {L["Auswählen"]}, SkuGenericMenuItem)
			tNewMenuEntrySub.OnEnter = function(self)
				SkuOptions.SkuNav_MenuBuilder_WaypointSelectionMenu_NPC = waypointName
			end

			--close rts
			local tNewMenuEntrySub = SkuOptions:InjectMenuItems(self, {L["Nahe Routen"]}, SkuGenericMenuItem)
			tNewMenuEntrySub.dynamic = true
			-- Option 2: the nearby-routes list streams in as data arrives;
			-- mark it volatile so navigating the list silently re-reads it.
			tNewMenuEntrySub.volatileChildren = true
			tNewMenuEntrySub.BuildChildren = function(self)
				local tPlayX, tPlayY = UnitPosition("player")
				local tRoutesInRange = SkuNav:GetAllLinkedWPsInRangeToCoords(tPlayX, tPlayY, SkuNav.MaxMetaEntryRange)--SkuSettings:Sub("SkuNav").nearbyWpRange)
				if string.find(SkuOptions.SkuNav_MenuBuilder_WaypointSelectionMenu_NPC, "#") then
					SkuOptions.SkuNav_MenuBuilder_WaypointSelectionMenu_NPC = ssub(SkuOptions.SkuNav_MenuBuilder_WaypointSelectionMenu_NPC, string.find(SkuOptions.SkuNav_MenuBuilder_WaypointSelectionMenu_NPC, "#") + 1)
				end
				local wpTable = {SkuOptions.SkuNav_MenuBuilder_WaypointSelectionMenu_NPC}
				local tCoveredWps = {}
				local tMaxAllowedDistanceToTargetWp = 500
				local tSortedWaypointList = {}
				for k, v in SkuSpairs(tRoutesInRange, function(t,a,b) return t[b].nearestWpRange > t[a].nearestWpRange end) do --nach wert
					local tFnd = false
					for tK, tV in pairs(tSortedWaypointList) do
						if tV == v.nearestWpRange..L[";Meter"].."#"..v.nearestWP then
							tFnd = true
						end
					end
					if tFnd == false then
						table.insert(tSortedWaypointList, v.nearestWpRange..L[";Meter"].."#"..v.nearestWP)
					end
				end
				if #tSortedWaypointList == 0 then
					local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Empty;list"]}, SkuGenericMenuItem)
				else
					local tCount = 0
					for k, v in SkuSpairs(tSortedWaypointList) do
						if tCount < 10 then
							local tSkuWpName = ssub(v, string.find(v, "#") + 1)
							local tLayerText = SkuNav:GetLayerText(SkuNav:GetNonAutoLevel(nil, nil, tSkuWpName, nil))

							local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Entry point: "]..tLayerText..v}, SkuGenericMenuItem)
							tNewMenuEntry.dynamic = true
							tNewMenuEntry.filterable = true
							tNewMenuEntry.BuildChildren = function(self)
								if #tSortedWaypointList == 0 then
									local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Empty;list"]}, SkuGenericMenuItem)
								else
									local tMetapaths = SkuNav:GetAllMetaTargetsFromWp5(ssub(v, string.find(v, "#") + 1), SkuSettings:Sub("SkuNav").routesMaxDistance, SkuNav.MaxMetaWPs, nil, true)
									SkuSettings:Sub("SkuNav").metapathFollowingStart = v
									SkuSettings:Sub("SkuNav").metapathFollowingMetapaths = tMetapaths
									SkuSettings:Sub("SkuNav").metapathFollowingTarget = nil

									local tResults = {}
									for wpIndex, wpName in pairs(wpTable) do
										local tNearWps = SkuNav:GetNearestWpsWithLinksToWp(wpName, 10, tMaxAllowedDistanceToTargetWp)
										local tBestRouteWeightedLength = 100000
										for x = 1, #tNearWps do
											if tMetapaths[tNearWps[x].wpName] then
												local EndMetapathWpObj = SkuNav:GetWaypointData2(tNearWps[x].wpName)
												local tEndTargetWpObj = SkuNav:GetWaypointData2(wpName)
												local tDistToEndTargetWp = SkuNav:Distance(EndMetapathWpObj.worldX, EndMetapathWpObj.worldY, tEndTargetWpObj.worldX, tEndTargetWpObj.worldY)

												local tDirectionTargetWp = ""
												if SkuSettings:Sub("SkuNav").showGlobalDirectionInWaypointLists == true then
													local tDirectionString = SkuNav:GetDirectionToAsString(tEndTargetWpObj.worldX, tEndTargetWpObj.worldY)
													if tDirectionString then
														tDirectionTargetWp = ";"..tDirectionString
													end
												end

												if (tMetapaths[tNearWps[x].wpName].distance / SkuNav.BestRouteWeightedLengthModForMetaDistance) + tDistToEndTargetWp < tBestRouteWeightedLength then
													tBestRouteWeightedLength = (tMetapaths[tNearWps[x].wpName].distance / SkuNav.BestRouteWeightedLengthModForMetaDistance) + tDistToEndTargetWp
													tResults[wpName] = {
														metarouteIndex = tNearWps[x].wpName,
														metapathLength = tMetapaths[tNearWps[x].wpName].distance,
														distanceTargetWp = tNearWps[x].distance,
														targetWpName = wpName,
														weightedDistance = tBestRouteWeightedLength,
														direction = tDirectionTargetWp,
													}
												end
											end
										end
									end

									do -- build choices
										local tSortedList = {}
										for k,v in SkuSpairs(tResults, function(t,a,b) return t[b].weightedDistance > t[a].weightedDistance end) do
											table.insert(tSortedList, k)
										end
										if #tSortedList == 0 then
											local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Empty;list"]}, SkuGenericMenuItem)
										else
											for tK, tV in ipairs(tSortedList) do
												local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {tResults[tV].metapathLength..";"..L["plus"]..";"..tResults[tV].distanceTargetWp..L[";Meter"]..tResults[tV].direction.."#"..tV}, SkuGenericMenuItem)
												tNewMenuEntry.OnEnter = function(self, aValue, aName)
													SkuSettings:Sub("SkuNav").metapathFollowingTarget = tResults[tV].metarouteIndex
													SkuSettings:Sub("SkuNav").metapathFollowingEndTarget = tResults[tV].targetWpName
													SkuOptions.SkuNav_MenuBuilder_WaypointSelectionMenu_CloseRoute = true
												end
												tCoveredWps[tV] = true
											end
										end
									end
								end
							end
							tCount = tCount + 1
						end
					end
				end

			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:MenuBuilder(aParentEntry)
	--dprint("SkuNav:MenuBuilder", aParentEntry)
	local tSpecs = {}

	tSpecs[#tSpecs+1] = { kind = "action", label = L["Deselect all"],
		onAction = function(self, aValue, aName)
		--dprint("Route und Wegpunkt abwählen", self.name, aName)
		SkuNav:EndFollowingWpOrRt()
		SkuNav:ClearWaypointsTemporary()
		PlaySound(835)
	end }

	--wps
	tSpecs[#tSpecs+1] = { kind = "list", label = L["Waypoint"],
		build = function(self)
		--[[
		local tNewMenuEntry = SkuOptions:BuildMenuSegment_TitleBuilder(self, L["New"])
		tNewMenuEntry.OnAction = function(self, aValue, aName)
			--dprint("Wegpunkt neu OnAction", self.name, aName, self.TMPSize, self.selectTarget, self.selectTarget.name, self.selectTarget.TMPSize)
			--dprint(self.selectTarget.TMPSize)
			if SkuSettings:Sub("SkuNav").metapathFollowing == true or SkuSettings:Sub("SkuNav").selectedWaypoint ~= "" then
				SkuOptions.Voice:OutputStringBTtts(L["Error"], false, true, 0.3, true)
				SkuOptions.Voice:OutputStringBTtts(L["Active waypoint or route or recording"], false, true, 0.3, true)
				return
			end
			if aName == L["Nothing selected"] then
				return
			end

			if sfind(aName, L["Selected"]..";") > 0 then
				aName = ssub(aName, slen(L["Selected"]..";") + 1)
			end
			if SkuNav:GetWaypointData2(aName) then
				SkuOptions.Voice:OutputStringBTtts(L["nicht erstellt"], false, true, 0.3, true)
				SkuOptions.Voice:OutputStringBTtts(L["name schon vorhanden"], false, true, 0.3, true)
				return
			end

			local tRName = SkuNav:CreateWaypoint(aName, nil, nil, self.selectTarget.TMPSize or 1)
			if tRName then
				--PlaySound(835)
				SkuOptions.Voice:OutputStringBTtts(L["Wegpunkt erstellt"], false, true, 0.2)
			end
		end
]]
		local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Auswählen"]}, SkuGenericMenuItem)
		tNewMenuEntry.dynamic = true
		tNewMenuEntry.isSelect = true
		tNewMenuEntry.OnAction = function(self, aValue, aName)
			--dprint("OnAction Auswählen", self.name,aValue,  aName, SkuOptions.SkuNav_MenuBuilder_WaypointSelectionMenu_NPC, SkuSettings:Sub("SkuNav").metapathFollowingStart)
			if SkuSettings:Sub("SkuNav").routeRecording == true then
				SkuOptions.Voice:OutputStringBTtts(L["Error"], false, true, 0.3, true)
				SkuOptions.Voice:OutputStringBTtts(L["Recording in progress"], false, true, 0.3, true)
				return
			end

			if SkuSettings:Sub("SkuNav").metapathFollowing == true or SkuSettings:Sub("SkuNav").selectedWaypoint ~= "" then
				SkuNav:EndFollowingWpOrRt()
			end

			if SkuOptions.SkuNav_MenuBuilder_WaypointSelectionMenu_CloseRoute then
				--close rt
				SkuSettings:Sub("SkuNav").metapathFollowing = false
				if SkuSettings:Sub("SkuNav").metapathFollowingStart then
					if SkuSettings:Sub("SkuNav").metapathFollowingMetapaths then
						if string.find(SkuSettings:Sub("SkuNav").metapathFollowingStart, "#") then
							SkuSettings:Sub("SkuNav").metapathFollowingStart = ssub(SkuSettings:Sub("SkuNav").metapathFollowingStart, string.find(SkuSettings:Sub("SkuNav").metapathFollowingStart, "#") + 1)
						end
						SkuSettings:Sub("SkuNav").metapathFollowingMetapaths = SkuNav:GetAllMetaTargetsFromWp5(SkuSettings:Sub("SkuNav").metapathFollowingStart, SkuSettings:Sub("SkuNav").routesMaxDistance, SkuNav.MaxMetaWPs, SkuSettings:Sub("SkuNav").metapathFollowingTarget, true)--
						SkuSettings:Sub("SkuNav").metapathFollowingMetapaths[#SkuSettings:Sub("SkuNav").metapathFollowingMetapaths+1] = SkuSettings:Sub("SkuNav").metapathFollowingEndTarget
						SkuSettings:Sub("SkuNav").metapathFollowingMetapaths[SkuSettings:Sub("SkuNav").metapathFollowingEndTarget] = SkuSettings:Sub("SkuNav").metapathFollowingMetapaths[SkuSettings:Sub("SkuNav").metapathFollowingTarget]
						table.insert(SkuSettings:Sub("SkuNav").metapathFollowingMetapaths[SkuSettings:Sub("SkuNav").metapathFollowingEndTarget].pathWps, SkuSettings:Sub("SkuNav").metapathFollowingEndTarget)
						SkuSettings:Sub("SkuNav").metapathFollowingTarget = SkuSettings:Sub("SkuNav").metapathFollowingEndTarget
						
						local tBaseName = SkuNav:StripBaseNameFromWaypointName(SkuSettings:Sub("SkuNav").metapathFollowingTarget)
						if tBaseName then
							SkuNav.lastSelectedWaypointFullName = SkuSettings:Sub("SkuNav").metapathFollowingTarget
						end						
						
						SkuSettings:Sub("SkuNav").metapathFollowingCurrentWp = 1
						SkuSettings:Sub("SkuNav").metapathFollowing = true
						SkuNav:SelectWP(SkuSettings:Sub("SkuNav").metapathFollowingStart, true)
						SkuOptions.Voice:OutputStringBTtts(L["Metaroute folgen gestartet"], false, true, 0.2)
						SkuOptions:CloseMenu()
						SkuDispatcher:TriggerSkuEvent("SKU_CLOSEROUTE_STARTED")
					end
				end
			else
				--just a wp
				if aName == L["Auswählen"] and SkuOptions.SkuNav_MenuBuilder_WaypointSelectionMenu_NPC then
					local tUncleanValue = SkuOptions.SkuNav_MenuBuilder_WaypointSelectionMenu_NPC
					local tCleanValue = SkuOptions.SkuNav_MenuBuilder_WaypointSelectionMenu_NPC
					local tPos = string.find(tUncleanValue, "#")
					if tPos then
						tCleanValue = ssub(tUncleanValue,  tPos + 1)
					end
					aName = tCleanValue
				end

				if (SkuOptions.tmpNpcWayPointNameBuilder_Npc and SkuOptions.tmpNpcWayPointNameBuilder_Npc ~= "") and (SkuOptions.tmpNpcWayPointNameBuilder_Npc and SkuOptions.tmpNpcWayPointNameBuilder_Zone ~= "") then
					aName = SkuOptions.tmpNpcWayPointNameBuilder_Npc..";"..SkuOptions.tmpNpcWayPointNameBuilder_Zone..";"..aName
					SkuOptions.tmpNpcWayPointNameBuilder_Npc = ""
					SkuOptions.tmpNpcWayPointNameBuilder_Zone = ""
					SkuOptions.tmpNpcWayPointNameBuilder_Coords = ""
				end

				if SkuNav:GetWaypointData2(aName) then
					local tBaseName = SkuNav:StripBaseNameFromWaypointName(aName)
					if tBaseName then
						SkuNav.lastSelectedWaypointFullName = aName
					end

					SkuNav:SelectWP(aName)
					--dprint("auswahl", aName)
					--lastDirection = SkuNav:GetDirectionTo(worldx, worldy, SkuNav:GetWaypointData2(SkuSettings:Sub("SkuNav").selectedWaypoint).worldX, SkuNav:GetWaypointData2(SkuSettings:Sub("SkuNav").selectedWaypoint).worldY)
					--PlaySound(835)
					SkuOptions:CloseMenu()
					SkuDispatcher:TriggerSkuEvent("SKU_WAYPOINT_STARTED")
				else
					SkuOptions.Voice:OutputStringBTtts(L["Error"], false, true, 0.3, true)
					SkuOptions.Voice:OutputStringBTtts(L["Wegpunkt nicht ausgewählt"], false, true, 0.3, true)
				end
			end
		end
		tNewMenuEntry.BuildChildren = function(self)
			SkuOptions.SkuNav_MenuBuilder_WaypointSelectionMenu_CloseRoute = nil
			--recent wps 
			if #SkuSettings:Sub("SkuNav").RecentWPs > 0 then
				local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Recent"]}, SkuGenericMenuItem)
				tNewMenuEntry.dynamic = true
				tNewMenuEntry.filterable = true
				tNewMenuEntry.BuildChildren = function(self)
					for i, v in pairs(SkuSettings:Sub("SkuNav").RecentWPs) do
						--dprint("recent: ", i, v)
					end
					if #SkuSettings:Sub("SkuNav").RecentWPs == 0 then
						local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Empty;list"]}, SkuGenericMenuItem)
					else
						local tNewMenuEntry = SkuOptions:InjectMenuItems(self, SkuSettings:Sub("SkuNav").RecentWPs, SkuGenericMenuItem)
					end
				end
			end

			--wps in current map sortet by range
			local tAutoLen = slen(L["auto"]) + 1
			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Aktuelle Karte Entfernung"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.filterable = true
			tNewMenuEntry.BuildChildren = function(self)
				SkuOptions.SkuNav_MenuBuilder_WaypointSelectionMenu_CloseRoute = nil
				local tCurrentAreaId = SkuNav:GetAreaIdFromUiMapId(SkuNav:GetBestMapForUnit("player"))
				local tSubAreaIds = SkuNav:GetSubAreaIds(tCurrentAreaId)
				tSubAreaIds[tCurrentAreaId] = tCurrentAreaId

				local tWaypointList = {}
				local tListWPs = SkuNav:ListWaypoints2(true, nil, tCurrentAreaId)
				if tListWPs then
					for i, v in SkuNav:ListWaypoints2(true, nil, tCurrentAreaId) do
						local tWayP = SkuNav:GetWaypointData2(v)
						if tWayP then
							if tSubAreaIds[tonumber(tWayP.areaId)] then
								if ssub(v, 1, tAutoLen) ~= L["auto"].." " then
								--if not sfind(v, L["auto"]..";") then
								--if not sfind(v, L["Quick waypoint"]) and not sfind(v, "auto;") then
									local tWpX, tWpY = tWayP.worldX, tWayP.worldY
									local tPlayX, tPlayY = UnitPosition("player")
									local tDistance, _  = SkuNav:Distance(tPlayX, tPlayY, tWpX, tWpY)
									-- add direction to wp
									local tDirectionTargetWp = ""
									if SkuSettings:Sub("SkuNav").showGlobalDirectionInWaypointLists == true then
										local tDirectionString = SkuNav:GetDirectionToAsString(tWpX, tWpY)
										if tDirectionString then
											tDirectionTargetWp = ";"..tDirectionString
										end
									end									
									tWaypointList[v] = {distance = tDistance, direction = tDirectionTargetWp,}
								end
							end
						end
					end
				end
				for q = 1, 4 do
					local tWayP = SkuNav:GetWaypointData2(L["Quick waypoint"]..";"..q)
					if tWayP then
						if tSubAreaIds[tonumber(tWayP.areaId)] then
							local tWpX, tWpY = tWayP.worldX, tWayP.worldY
							local tPlayX, tPlayY = UnitPosition("player")
							local tDistance, _  = SkuNav:Distance(tPlayX, tPlayY, tWpX, tWpY)
							-- add direction to wp
							local tDirectionTargetWp = ""
							if SkuSettings:Sub("SkuNav").showGlobalDirectionInWaypointLists == true then
								local tDirectionString = SkuNav:GetDirectionToAsString(tWpX, tWpY)
								if tDirectionString then
									tDirectionTargetWp = ";"..tDirectionString
								end
							end									
							tWaypointList[L["Quick waypoint"]..";"..q] = {distance = tDistance, direction = tDirectionTargetWp,}
						end
					end
				end

				local tSortedWaypointList = {}
				for k,v in SkuSpairs(tWaypointList, function(t,a,b) return t[b].distance > t[a].distance end) do --nach wert
					table.insert(tSortedWaypointList, v.distance..L[";Meter"]..v.direction.."#"..k)
				end
				if #tSortedWaypointList == 0 then
					local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Empty;list"]}, SkuGenericMenuItem)
				else
					--local tNewMenuEntry = SkuOptions:InjectMenuItems(self, tSortedWaypointList, SkuGenericMenuItem)
					SkuNav_MenuBuilder_WaypointSelectionMenu(self, tSortedWaypointList)
				end
			end

			-- all wps
			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Alle aktueller Kontinent"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.filterable = true
			tNewMenuEntry.BuildChildren = function(self)
				SkuOptions.SkuNav_MenuBuilder_WaypointSelectionMenu_CloseRoute = nil
				local tPlayerContintentId = select(3, SkuNav:GetAreaData(SkuNav:GetCurrentAreaId()))
				local tWaypointList = SkuNav:ListWaypoints2(false, nil, nil, tPlayerContintentId, nil, true, true)
		
				if #tWaypointList == 0 then
					local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Empty;list"]}, SkuGenericMenuItem)
				else
					local tNewMenuEntry = SkuOptions:InjectMenuItems(self, tWaypointList, SkuGenericMenuItem)
				end
			end

			--wps in current map sortet by range with auto wps
			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Aktuelle Karte Entfernung mit Auto"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.filterable = true
			tNewMenuEntry.BuildChildren = function(self)
				SkuOptions.SkuNav_MenuBuilder_WaypointSelectionMenu_CloseRoute = nil
				local tCurrentAreaId = SkuNav:GetAreaIdFromUiMapId(SkuNav:GetBestMapForUnit("player"))
				local tSubAreaIds = SkuNav:GetSubAreaIds(tCurrentAreaId)
				tSubAreaIds[tCurrentAreaId] = tCurrentAreaId

				local tWaypointList = {}
				for i, v in SkuNav:ListWaypoints2(true, nil, tCurrentAreaId) do
					local tWayP = SkuNav:GetWaypointData2(v)
					if tWayP then
						if tSubAreaIds[tonumber(tWayP.areaId)] then
							if not sfind(v, L["Quick waypoint"]) then
								local tWpX, tWpY = tWayP.worldX, tWayP.worldY
								local tPlayX, tPlayY = UnitPosition("player")
								local tDistance, _  = SkuNav:Distance(tPlayX, tPlayY, tWpX, tWpY)
								tWaypointList[v] = tDistance
							end
						end
					end
				end

				local tSortedWaypointList = {}
				for k,v in SkuSpairs(tWaypointList, function(t,a,b) return t[b] > t[a] end) do --nach wert
					table.insert(tSortedWaypointList, v..L[";Meter"].."#"..k)
				end
				if #tSortedWaypointList == 0 then
					local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Empty;list"]}, SkuGenericMenuItem)
				else
					local tNewMenuEntry = SkuOptions:InjectMenuItems(self, tSortedWaypointList, SkuGenericMenuItem)
				end
			end
		end

		local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Abwählen"]}, SkuGenericMenuItem)
		tNewMenuEntry.OnAction = function(self, aValue, aName)
			--dprint("OnAction Aktuellen abwählen", self.name, aName)
			if SkuSettings:Sub("SkuNav").metapathFollowing == true or SkuSettings:Sub("SkuNav").routeRecording == true then
				SkuOptions.Voice:OutputStringBTtts(L["Error"], false, true, 0.3, true)
				SkuOptions.Voice:OutputStringBTtts(L["Active waypoint or route or recording"], false, true, 0.3, true)
				return
			end

			if SkuNav:GetWaypointData2(SkuSettings:Sub("SkuNav").selectedWaypoint) then
				if SkuSettings:Sub("SkuNav").selectedWaypoint ~= "" then
					if SkuOptions.BeaconLib:GetBeaconStatus("SkuOptions", SkuSettings:Sub("SkuNav").selectedWaypoint) then
						SkuOptions.BeaconLib:DestroyBeacon("SkuOptions", SkuSettings:Sub("SkuNav").selectedWaypoint)
					end
					SkuOptions.Voice:OutputStringBTtts(L["Wegpunkt abgewählt"], false, true, 0.3, true)
					--SkuSettings:Sub("SkuNav").selectedWaypoint = ""
					SkuNav:SelectWP("", true)
					SkuDispatcher:TriggerSkuEvent("SKU_NAVIGATION_STOPPED")
				end
				--PlaySound(835)
			end
		end

		local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Clear visited"]}, SkuGenericMenuItem)
		tNewMenuEntry.OnAction = function(self, aValue, aName)
			SkuNav:clearVisitedWaypoints()
			PlaySound(835)
		end

		local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Set Quick Waypoint to coordinates"]}, SkuGenericMenuItem)
		tNewMenuEntry.dynamic = true
		tNewMenuEntry.isSelect = true
		tNewMenuEntry.tQWPNumber = nil
		tNewMenuEntry.OnAction = function(self, aValue, aName)
			local tCoords = {x = nil, y = nil,}
			SkuOptions:EditBoxShow("", function(a, b, c) 
				local tText = SkuOptionsEditBoxEditBox:GetText() 
				tText = string.gsub(tText, ",", "%.")
				if self.tQWPNumber and tText ~= "" and tonumber(tText) ~= nil and tonumber(tText) > 0 and tonumber(tText) < 100 then
					tCoords.x = tonumber(tText)
					C_Timer.After(0.1, function()
						SkuOptions:EditBoxShow("", function(a, b, c) 
							local tText = SkuOptionsEditBoxEditBox:GetText() 
							tText = string.gsub(tText, ",", "%.")
							if tText ~= "" and tonumber(tText) ~= nil and tonumber(tText) > 0 and tonumber(tText) < 100 then
								tCoords.y = tonumber(tText)
								if SkuNav:GetCurrentAreaId() then
									if SkuNav:GetUiMapIdFromAreaId(SkuNav:GetCurrentAreaId()) then
										local tx, ty = SkuNav:GetWorldCoordinatesFromZone(tCoords.x / 100, tCoords.y / 100, SkuNav:GetUiMapIdFromAreaId(SkuNav:GetCurrentAreaId()))
										SkuNav:UpdateQuickWP(L["Quick waypoint"]..";"..self.tQWPNumber, false, ty, tx)
									end
								end
							else
								SkuOptions.Voice:OutputStringBTtts("y"..L[" invalid. canceled."].." "..SkuOptions.currentMenuPosition.name, true, true, 0.3, true, nil, nil, 2)
							end
						end)
						SkuOptions.Voice:OutputStringBTtts(L["enter y value"], true, true, 0.3, true, nil, nil, 2)
					end)
		
				else
					SkuOptions.Voice:OutputStringBTtts("x"..L[" invalid. canceled."].." "..SkuOptions.currentMenuPosition.name, true, true, 0.3, true, nil, nil, 2)
				end
			end)
			C_Timer.After(0.1, function()
				SkuOptions.Voice:OutputStringBTtts(L["enter x value"], true, true, 0.3, true, nil, nil, 2)
			end)
		end
		tNewMenuEntry.BuildChildren = function(self)
			for i = 1, 4 do
				local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Quick waypoint"].." "..i}, SkuGenericMenuItem)
				tNewMenuEntry.OnEnter = function(self)
					self.parent.tQWPNumber = i
				end
			end
		end

--[[
		local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Verwalten"]}, SkuGenericMenuItem)
		tNewMenuEntry.dynamic = true
		tNewMenuEntry.BuildChildren = function(self)
			--
			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Löschen"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.filterable = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.OnAction = function(self, aValue, aName, aChildName)
				--dprint("OnAction Löschen", self.name, aValue, aName, aChildName)
				if SkuSettings:Sub("SkuNav").metapathFollowing == true or SkuSettings:Sub("SkuNav").routeRecording == true then
					SkuOptions.Voice:OutputStringBTtts(L["Error"], false, true, 0.3, true)
					SkuOptions.Voice:OutputStringBTtts(L["Active waypoint or route or recording"], false, true, 0.3, true)
					return
				end
	
				if aName == L["Löschen"] then
					if SkuSettings:Sub("SkuNav").selectedWaypoint == aChildName then
						SkuNav:SelectWP("", true)
					end
					local wpObj = SkuNav:GetWaypointData2(aChildName)
					if wpObj then
						local tSuccess = SkuNav:DeleteWaypoint(aChildName)
						if tSuccess == true then
							SkuSettings:Sub("SkuNav", nil, "global").hasCustomMapData = true
							SkuOptions.Voice:OutputStringBTtts(L["Wegpunkt gelöscht"], false, true, 0.2)
						elseif tSuccess == false then
							SkuOptions.Voice:OutputStringBTtts(L["Error"], false, true, 0.3, true)
							SkuOptions.Voice:OutputStringBTtts(L["Wird in route verwendet;Erst die Route löschen"], false, true, 0.3, true)
						else
							SkuOptions.Voice:OutputStringBTtts(L["Unbekannter Fehler"], false, true, 0.3, true)
						end
					else
						SkuOptions.Voice:OutputStringBTtts(L["Unbekannter Fehler"], false, true, 0.3, true)
					end
				end
			end
			tNewMenuEntry.BuildChildren = function(self)
				local tWaypointList = {}
				local _, _, tPlayerContinentID  = SkuNav:GetAreaData(SkuNav:GetCurrentAreaId())
				for i, v in SkuNav:ListWaypoints2(false, "custom", SkuNav:GetCurrentAreaId(), tPlayerContinentID) do --aSort, aFilter, aAreaId, aContinentId, aExcludeRoute
					if not sfind(v, L["Quick waypoint"]) then
						local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {v}, SkuGenericMenuItem)
						tNewMenuEntry.dynamic = true
						tNewMenuEntry.BuildChildren = function(self)
							local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Löschen"]}, SkuGenericMenuItem)
							local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Abbrechen"]}, SkuGenericMenuItem)
						end
					end
				end
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Kommentar zuweisen"]}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.filterable = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.OnAction = function(self, aValue, aName, aChildName)
				--dprint("OnAction Kommentar zuweisen", self, aValue, aName, aChildName)
				local tWpData = SkuNav:GetWaypointData2(aName)
				if tWpData then
					if tWpData.typeId ~= 1 then
						return
					end
					SkuOptions:EditBoxShow("test", function(a, b, c) 
						local tText = SkuOptionsEditBoxEditBox:GetText() 
						if tText ~= "" then
							if not tWpData.comments or not tWpData.comments[Sku.Loc] then
								tWpData.comments = {
									["deDE"] = {},
									["enUS"] = {},
								}
							end
							tWpData.comments[Sku.Loc][#tWpData.comments[Sku.Loc] + 1] = tText
							SkuNav:SetWaypoint(aName, tWpData)
							SkuSettings:Sub("SkuNav", nil, "global").hasCustomMapData = true
							SkuOptions.Voice:OutputStringBTtts(L["Kommentar zugewiesen"], false, true, 0.3, true)
						else
							SkuOptions.Voice:OutputStringBTtts(L["Kommentar leer"], false, true, 0.3, true)
						end
					end)
					SkuOptions.Voice:OutputStringBTtts(L["Jetzt kommentar eingeben und mit ENTER abschließen oder mit ESC abbrechen"], false, true, 0.3, true)
				end
			end
			tNewMenuEntry.BuildChildren = function(self)
				local tWaypointList = {}
				local _, _, tPlayerContinentID  = SkuNav:GetAreaData(SkuNav:GetCurrentAreaId())
				for i, v in SkuNav:ListWaypoints2(false, "custom", nil, tPlayerContinentID) do --aSort, aFilter, aAreaId, aContinentId, aExcludeRoute
					if not sfind(v, L["Quick waypoint"]) then
						local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {v}, SkuGenericMenuItem)
					end
				end
			end
		end
		]]
	end }

	--rts
	tSpecs[#tSpecs+1] = { kind = "list", label = L["Route folgen"], isSelect = true,
		onAction = function(self, aValue, aName)
		dprint("OnAction", self.name, aValue, aName)

		SkuNav:ClearWaypointsTemporary()

		if SkuSettings:Sub("SkuNav").routeRecording == true then
			SkuOptions.Voice:OutputStringBTtts(L["Error"], false, true, 0.3, true)
			SkuOptions.Voice:OutputStringBTtts(L["Recording in progress"], false, true, 0.3, true)
			return
		end

		--if SkuSettings:Sub("SkuNav").metapathFollowing == true or SkuSettings:Sub("SkuNav").selectedWaypoint ~= "" then
		if SkuSettings:Sub("SkuNav").metapathFollowing == true or SkuSettings:Sub("SkuNav").selectedWaypoint ~= "" then
			SkuNav:EndFollowingWpOrRt()
		end

		SkuSettings:Sub("SkuNav").metapathFollowing = false


		SkuSettings:Sub("SkuNav").metapathFollowingStart = SkuSettings:Sub("SkuNav").metapathFollowingStartTMP
		SkuSettings:Sub("SkuNav").metapathFollowingMetapaths = SkuMetapathFollowingMetapathsTMP

		if SkuSettings:Sub("SkuNav").metapathFollowingUnitDbWaypoint == true and SkuSettings:Sub("SkuNav").metapathFollowingUnitDbWaypointData then
			if #SkuSettings:Sub("SkuNav").metapathFollowingUnitDbWaypointData < 2 then
				return
			end

			if string.find(aName, ";") then
				SkuSettings:Sub("SkuNav").metapathFollowingTargetName = ssub(aName, 1, string.find(aName, ";") - 1)
			end
			
			SkuSettings:Sub("SkuNav").metapathFollowingStart = L["Einheiten;Route;"].."1"
			SkuSettings:Sub("SkuNav").metapathFollowingTarget = L["Einheiten;Route;"]..#SkuSettings:Sub("SkuNav").metapathFollowingUnitDbWaypointData
			SkuSettings:Sub("SkuNav").metapathFollowingMetapaths = {}
			SkuSettings:Sub("SkuNav").metapathFollowingMetapaths[1] = SkuSettings:Sub("SkuNav").metapathFollowingTarget
			SkuSettings:Sub("SkuNav").metapathFollowingMetapaths[SkuSettings:Sub("SkuNav").metapathFollowingTarget] = {
				pathWps = {},
				distance = 0,
			}
				
			--build metaroute table
			for x = 1, #SkuSettings:Sub("SkuNav").metapathFollowingUnitDbWaypointData do
				--create tmp wps
				local tCurrentAreaId = SkuNav:GetAreaIdFromUiMapId(SkuNav:GetBestMapForUnit("player"))
				local isUiMap = SkuNav:GetUiMapIdFromAreaId(tCurrentAreaId)
				local _, worldPosition = C_Map.GetWorldPosFromMapPos(isUiMap, CreateVector2D(SkuSettings:Sub("SkuNav").metapathFollowingUnitDbWaypointData[x][1] / 100, SkuSettings:Sub("SkuNav").metapathFollowingUnitDbWaypointData[x][2] / 100))
				local tX, tY = worldPosition:GetXY()
				local tNameOfNewWp = SkuNav:CreateWaypoint(L["Einheiten;Route;"]..x, tX, tY, 1, true, true)
				if tNameOfNewWp then
					--add to mt rt
					SkuSettings:Sub("SkuNav").WaypointsTemporary[#SkuSettings:Sub("SkuNav").WaypointsTemporary + 1] = tNameOfNewWp
					table.insert(SkuSettings:Sub("SkuNav").metapathFollowingMetapaths[SkuSettings:Sub("SkuNav").metapathFollowingTarget].pathWps, tNameOfNewWp)
				end
			end

			local tDistance = 0
			local tDistanceToStartWp = 0
			for z = 2, #SkuSettings:Sub("SkuNav").metapathFollowingMetapaths[SkuSettings:Sub("SkuNav").metapathFollowingTarget].pathWps do
				local tWpA = SkuNav:GetWaypointData2(SkuSettings:Sub("SkuNav").metapathFollowingMetapaths[SkuSettings:Sub("SkuNav").metapathFollowingTarget].pathWps[z - 1])
				local tWpB = SkuNav:GetWaypointData2(SkuSettings:Sub("SkuNav").metapathFollowingMetapaths[SkuSettings:Sub("SkuNav").metapathFollowingTarget].pathWps[z])
				tDistance = tDistance + SkuNav:Distance(tWpA.worldX, tWpA.worldY, tWpB.worldX, tWpB.worldY)
				if tDistanceToStartWp == 0 then
					tDistanceToStartWp = tDistance
				end
			end
			SkuSettings:Sub("SkuNav").metapathFollowingMetapaths[SkuSettings:Sub("SkuNav").metapathFollowingTarget].distance = tDistance
			SkuSettings:Sub("SkuNav").metapathFollowingMetapaths[SkuSettings:Sub("SkuNav").metapathFollowingTarget].distanceToStartWp = tDistanceToStartWp

			--start follow
			SkuSettings:Sub("SkuNav").metapathFollowingCurrentWp = 1
			SkuSettings:Sub("SkuNav").metapathFollowing = true

			SkuNav:SelectWP(SkuSettings:Sub("SkuNav").metapathFollowingStart, true)
			SkuOptions.Voice:OutputStringBTtts(L["Einheiten Route folgen gestartet"], false, true, 0.2)
			SkuOptions:CloseMenu()
			SkuDispatcher:TriggerSkuEvent("SKU_UNITROUTE_STARTED")
			return
		elseif SkuSettings:Sub("SkuNav").metapathFollowingStart then
			if SkuSettings:Sub("SkuNav").metapathFollowingMetapaths then
				if string.find(SkuSettings:Sub("SkuNav").metapathFollowingStart, "#") then
					SkuSettings:Sub("SkuNav").metapathFollowingStart = ssub(SkuSettings:Sub("SkuNav").metapathFollowingStart, string.find(SkuSettings:Sub("SkuNav").metapathFollowingStart, "#") + 1)
				end
				SkuSettings:Sub("SkuNav").metapathFollowingMetapaths = SkuNav:GetAllMetaTargetsFromWp5(SkuSettings:Sub("SkuNav").metapathFollowingStart, SkuSettings:Sub("SkuNav").routesMaxDistance, SkuNav.MaxMetaWPs, aName)--
				SkuSettings:Sub("SkuNav").metapathFollowingTarget = aName
				SkuSettings:Sub("SkuNav").metapathFollowingCurrentWp = 1
				SkuSettings:Sub("SkuNav").metapathFollowing = true

				local tBaseName = SkuNav:StripBaseNameFromWaypointName(SkuSettings:Sub("SkuNav").metapathFollowingTarget)
				if tBaseName then
					SkuNav.lastSelectedWaypointFullName = SkuSettings:Sub("SkuNav").metapathFollowingTarget
				end
				
				SkuNav:SelectWP(SkuSettings:Sub("SkuNav").metapathFollowingStart, true)
				SkuOptions.Voice:OutputStringBTtts(L["Metaroute folgen gestartet"], false, true, 0.2)

				SkuOptions:CloseMenu()
				SkuDispatcher:TriggerSkuEvent("SKU_ROUTE_STARTED")
			end
		end
	end,
		build = function(self)
		local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Ziele Entfernung"]}, SkuGenericMenuItem)
		tNewMenuEntry.dynamic = true
		tNewMenuEntry.filterable = true
		tNewMenuEntry.BuildChildren = function(self)
			--SkuSettings:Sub("SkuNav").metapathFollowingMetapaths = nil
			--SkuSettings:Sub("SkuNav").metapathFollowingStart = nil
			SkuSettings:Sub("SkuNav").metapathFollowingStartTMP = nil
			SkuMetapathFollowingMetapathsTMP = nil
			local tPlayX, tPlayY = UnitPosition("player")
			local tRoutesInRange = SkuNav:GetAllLinkedWPsInRangeToCoords(tPlayX, tPlayY, SkuNav.MaxMetaEntryRange)--SkuSettings:Sub("SkuNav").nearbyWpRange)

			local tSortedWaypointList = {}
			for k, v in SkuSpairs(tRoutesInRange, function(t,a,b) return t[b].nearestWpRange > t[a].nearestWpRange end) do --nach wert
				local tFnd = false
				for tK, tV in pairs(tSortedWaypointList) do
					if tV == v.nearestWpRange..L[";Meter"].."#"..v.nearestWP then
						tFnd = true
					end
				end
				if tFnd == false then
					table.insert(tSortedWaypointList, v.nearestWpRange..L[";Meter"].."#"..v.nearestWP)
				end
			end

			if #tSortedWaypointList == 0 then
				local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Empty;list"]}, SkuGenericMenuItem)
			else
				local tCount = 0
				for k, v in SkuSpairs(tSortedWaypointList) do
					if tCount < 10 then

						local tSkuWpName = ssub(v, string.find(v, "#") + 1)
						local tLayerText = SkuNav:GetLayerText(SkuNav:GetNonAutoLevel(nil, nil, tSkuWpName, nil))

						local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Entry point: "]..tLayerText..v}, SkuGenericMenuItem)
						tNewMenuEntry.dynamic = true
						tNewMenuEntry.filterable = true
						tNewMenuEntry.BuildChildren = function(self)
							SkuSettings:Sub("SkuNav").metapathFollowingStartTMP = v
							local tMetapaths = SkuNav:GetAllMetaTargetsFromWp5(ssub(v, string.find(v, "#") + 1), SkuSettings:Sub("SkuNav").routesMaxDistance, SkuNav.MaxMetaWPs)--
							SkuMetapathFollowingMetapathsTMP = tMetapaths
							local tData = {}
							for i, v in pairs(tMetapaths) do--
								tData[i] = tMetapaths[i].distance
							end

							local tSortedList = {}
							for k,v in SkuSpairs(tData, function(t,a,b) return t[b] > t[a] end) do
								table.insert(tSortedList, k)
							end
							if #tSortedList == 0 then
								local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Empty;list"]}, SkuGenericMenuItem)
							else
								for tK, tV in ipairs(tSortedList) do
									local tDistText = tMetapaths[tV].distance..L[";Meter"]..""--
									if tMetapaths[tV].distance >= SkuSettings:Sub("SkuNav").routesMaxDistance then
										tDistText = L["weit"]
									end

									-- add direction to wp
									local tDirectionTargetWp = ""
									if SkuSettings:Sub("SkuNav").showGlobalDirectionInWaypointLists == true then
										local tWpData = SkuNav:GetWaypointData2(tV)
										local tDirectionString = SkuNav:GetDirectionToAsString(tWpData.worldX, tWpData.worldY)
										if tDirectionString then
											tDirectionTargetWp = ";"..tDirectionString
										end
									end
									tDistText = tDistText..tDirectionTargetWp									

									local tNewMenuEntry = SkuOptions:InjectMenuItems(self, { SkuNav:getAnnotatedWaypointLabel(tDistText .. "#" .. tV, tV) }, SkuGenericMenuItem) --
									tNewMenuEntry.OnEnter = function(self)
										SkuSettings:Sub("SkuNav").metapathFollowingUnitDbWaypoint = nil
										SkuSettings:Sub("SkuNav").metapathFollowingUnitDbWaypointData = nil
									end
			
								end
							end
--print("filled", debugprofilestop() - beginTime)

						end
						tCount = tCount + 1
					end
				end
			end
		end
		local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Einheiten Route"]}, SkuGenericMenuItem)
		tNewMenuEntry.dynamic = true
		tNewMenuEntry.filterable = true
		tNewMenuEntry.BuildChildren = function(self)
			SkuSettings:Sub("SkuNav").metapathFollowingUnitDbWaypoint = nil
			--SkuSettings:Sub("SkuNav").metapathFollowingMetapaths = nil
			--SkuSettings:Sub("SkuNav").metapathFollowingStart = nil
			SkuSettings:Sub("SkuNav").metapathFollowingStartTMP = nil
			SkuMetapathFollowingMetapathsTMP = nil
	
			local tCurrentAreaId = SkuNav:GetAreaIdFromUiMapId(SkuNav:GetBestMapForUnit("player"))
			tUnitDbWaypointData = {}

			local tWaypointList = {}
			for i, v in pairs(SkuDB.NpcData.Names[Sku.Loc]) do
				if SkuDB.NpcData.Data[i] then
					local tSpawns = SkuDB.NpcData.Data[i][7]
					local tCreatureDbExtraWaypoints = SkuDB.NpcData.Data[i][8]
					if tSpawns and tCreatureDbExtraWaypoints then
						if tCreatureDbExtraWaypoints[tCurrentAreaId] then
							for is, vs in pairs(tSpawns) do
								if tCurrentAreaId == is then
									local tData = SkuDB.InternalAreaTable[is]
									if tData then
										local tNumberOfSpawns = #vs
										local tSubname = SkuDB.NpcData.Names[Sku.Loc][i][2]
										local tRolesString = ""
										if not tSubname then
											local tRoles = SkuNav:GetNpcRoles(v[1], i)
											if #tRoles > 0 then
												for i, v in pairs(tRoles) do
													tRolesString = tRolesString..";"..v
												end
												tRolesString = tRolesString..""
											end
										else
											tRolesString = tRolesString..";"..tSubname
										end
										for sp = 1, 1 do
											local tWayP = SkuNav:GetWaypointData2(v[1]..tRolesString..";"..tData.AreaName_lang[Sku.Loc]..";"..sp..";"..vs[sp][1]..";"..vs[sp][2])
											if tWayP then
												local tWpX, tWpY = tWayP.worldX, tWayP.worldY
												local tPlayX, tPlayY = UnitPosition("player")
												local tDistance, _  = SkuNav:Distance(tPlayX, tPlayY, tWpX, tWpY)
												tWaypointList[v[1]..tRolesString..";"..tData.AreaName_lang[Sku.Loc]..";"..sp..";"..vs[sp][1]..";"..vs[sp][2]] = tDistance
												tUnitDbWaypointData[v[1]..tRolesString..";"..tData.AreaName_lang[Sku.Loc]..";"..sp..";"..vs[sp][1]..";"..vs[sp][2]] = tCreatureDbExtraWaypoints[tCurrentAreaId][1]
											end
										end
									end
								end
							end
						end
					end
				end
			end

			local tSortedWaypointList = {}
			for k,v in SkuSpairs(tWaypointList, function(t,a,b) return t[b] > t[a] end) do --nach wert
				table.insert(tSortedWaypointList, v..L[";Meter"].."#"..k)
			end
			if #tSortedWaypointList == 0 then
				local tNewMenuEntrySub = SkuOptions:InjectMenuItems(self, {L["Empty;list"]}, SkuGenericMenuItem)
			else
				for i, v in pairs(tSortedWaypointList) do
					local tNewMenuEntrySub = SkuOptions:InjectMenuItems(self, {v}, SkuGenericMenuItem)
					tNewMenuEntrySub.OnEnter = function(self)
						local tClearedName = self.name
						if sfind(tClearedName, "#") then
							tClearedName = ssub(tClearedName, string.find(tClearedName, "#") + 1)
						end
						if tUnitDbWaypointData[tClearedName] then
							SkuSettings:Sub("SkuNav").metapathFollowingUnitDbWaypoint = true
							SkuSettings:Sub("SkuNav").metapathFollowingUnitDbWaypointData = tUnitDbWaypointData[tClearedName]
						end
					end
				end
			end
		end
	end }

	SkuMenu:Build(aParentEntry, tSpecs)

	-- [41.02.08] Menuepunkt "Daten" vollstaendig ausgeblendet (Nutzerwunsch).
	-- RUECKBAU: dieses "if false then" und das zugehoerige "end" weiter unten entfernen.
	if false then
	local tNewMenuEntry = SkuOptions:InjectMenuItems(aParentEntry, {L["Daten"]}, SkuGenericMenuItem)
	tNewMenuEntry.dynamic = true
	tNewMenuEntry.BuildChildren = function(self)
		--[[ Import deaktiviert - nur ueber SkuMapper Tool
		local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Import"]}, SkuGenericMenuItem)
		tNewMenuEntry.OnAction = function(self, aValue, aName)
			if SkuSettings:Sub("SkuNav").metapathFollowing == true or SkuSettings:Sub("SkuNav").routeRecording == true or SkuSettings:Sub("SkuNav").selectedWaypoint ~= "" then
				SkuOptions.Voice:OutputStringBTtts(L["Error"], false, true, 0.3, true)
				SkuOptions.Voice:OutputStringBTtts(L["Active waypoint or route or recording"], false, true, 0.3, true)
				return
			end
			SkuOptions:ImportWpAndLinkData()
		end
		]]

		local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Export"]}, SkuGenericMenuItem)
		tNewMenuEntry.OnAction = function(self, aValue, aName)
			if SkuSettings:Sub("SkuNav").metapathFollowing == true or SkuSettings:Sub("SkuNav").routeRecording == true or SkuSettings:Sub("SkuNav").selectedWaypoint ~= "" then
				SkuOptions.Voice:OutputStringBTtts(L["Error"], false, true, 0.3, true)
				SkuOptions.Voice:OutputStringBTtts(L["Active waypoint or route or recording"], false, true, 0.3, true)
				return
			end
			--SkuOptions:ExportWpAndRouteData()
			SkuOptions:ExportWpAndLinkData()
		end

		--[[ Entfernt in v41.01.03: Gefaehrlicher Menuepunkt der alle benutzerdefinierten Navigationsdaten unwiderruflich loescht
		local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Alle Routen und Wegpunkte löschen"]}, SkuGenericMenuItem)
		tNewMenuEntry.OnAction = function(self, aValue, aName)
			if SkuSettings:Sub("SkuNav").metapathFollowing == true or SkuSettings:Sub("SkuNav").routeRecording == true or SkuSettings:Sub("SkuNav").selectedWaypoint ~= "" then
				SkuOptions.Voice:OutputStringBTtts(L["Error"], false, true, 0.3, true)
				SkuOptions.Voice:OutputStringBTtts(L["Active waypoint or route or recording"], false, true, 0.3, true)
				return
			end
			SkuDB.SessionRouteData.Waypoints = {}
			SkuDB.SessionRouteData.Links = {}
			SkuSettings:Sub("SkuNav", nil, "global").hasCustomMapData = nil
			--SkuNav:CreateWaypointCache()
			SkuNav:PLAYER_ENTERING_WORLD()
			SkuOptions.Voice:OutputStringBTtts(L["Alles gelöscht"], false, true, 0.3, true)
		end
		]]
	end
	end -- [41.02.08] schliesst das ausblendende "if false then" fuer "Daten"

	SkuMenu:Build(aParentEntry, {
		{ kind = "settings", label = L["Options"], filterable = true,
			args = SkuNav.options.args, db = SkuSettings:Sub("SkuNav"), module = "SkuNav" },
	})
end
