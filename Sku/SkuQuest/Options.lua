local MODULE_NAME = "SkuQuest"
local L = Sku.L
local function BuildSortedUniqueRouteWps(tRoutesInRange)
	local tSortedWaypointList = {}
	for k, v in SkuSpairs(tRoutesInRange, function(t,a,b) return t[b].nearestWpRange > t[a].nearestWpRange end) do
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
	return tSortedWaypointList
end


SkuQuest.questMarkerBeaconsTypeValues = {
	[-1] = L["schneller je näher, lauter je näher"],
	[-2] = L["schneller je näher, lauter je näher; lauter in blickrichtung"],
	[-3] = L["schneller in blickrichtung, lauter je näher"],
	[-4] = L["gleichbleibend langsam, lauter je näher"],
	[-5] = L["gleichbleibend schnell, lauter je näher"],
	[-6] = L["sehr langsam, schneller je näher, lauter je näher; lauter in blickrichtung"],
	[-7] = L["sehr langsam, schneller je näher, lauter je näher; nur in blickrichtung"],
}

SkuQuest.options = {
	name = MODULE_NAME,
	type = "group",
	args = {
		showDifficultyColors = {
			name = L["show colors for difficulty"],
			order = 1,
			type = "toggle",
			desc = "",
		},
		showGroupQuests = {
			name = L["show group members quests"],
			order = 1.2,
			type = "toggle",
			desc = "",
		},
		questMarkerBeacons ={
			name = L["quest notifications"],
			type = "group",
			order = 2,
			args= {
				availableQuests ={
					name = L["available (can be accepted)"],
					type = "group",
					order = 1,
					args= {
						enabled = {
							order = 1,
							name = L["Enabled"],
							desc = "",
							type = "toggle",
							OnAction = function(self, info, val)
								SkuQuest:UpdateZoneAvailableQuestList(true)
							end,
						},
						enableBeacons = {
							order = 1.4,
							name = L["enable Beacons"],
							desc = "",
							type = "toggle",
							OnAction = function(self, info, val)
								SkuQuest:UpdateZoneAvailableQuestList(true)
							end,
						},
						enableClickClack = {
							order = 1.5,
							name = L["Ton für Klick bei Beacons"],
							desc = "",
							type = "select",
							values = SkuNav.ClickClackSoundsets,
							OnAction = function(self, info, val)
								SkuQuest:UpdateZoneAvailableQuestList(true)
							end,
						},
						singlePing = {
							order = 1.75,
							name = L["only one beacon ping"],
							desc = "",
							type = "toggle",
							OnAction = function(self, info, val)
								SkuQuest:UpdateZoneAvailableQuestList(true)
							end,
						},

						-- beacon sound
						beaconSoundSet = {
							order = 2,
							name = L["beacon sound"],
							desc = "",
							type = "select",
							values = SkuNav.BeaconSoundSetNames,
							OnAction = function(self, info, val)
								local tPlayerPosX, tPlayerPosY = UnitPosition("player")
								tPlayerPosX, tPlayerPosY = tPlayerPosX + 6, tPlayerPosY + 6
								if not SkuOptions.BeaconLib:CreateBeacon("SkuOptions", "sampleBeacon", SkuNav.BeaconSoundSetNames[val], tPlayerPosX + 10, tPlayerPosY, -3, 0, SkuOptions.db.profile["SkuNav"].beaconVolume, SkuSettings:Sub("SkuQuest").clickClackRange) then
									return
								end
								SkuOptions.BeaconLib:StartBeacon("SkuOptions", "sampleBeacon")
								C_Timer.After(1, function()
									SkuOptions.BeaconLib:DestroyBeacon("SkuOptions", "sampleBeacon")
								end)

								SkuQuest:UpdateZoneAvailableQuestList(true)
							end,	
							set = function(info,val)
								SkuSettings:Sub("SkuQuest").questMarkerBeacons.availableQuests.beaconSoundSet = SkuNav.BeaconSoundSetNames[val]
							end,
							get = function(info)
								return SkuSettings:Sub("SkuQuest").questMarkerBeacons.availableQuests.beaconSoundSet
							end
						},				
						-- beacon type
						beaconType = {
							order = 3,
							name = L["beacon type"],
							desc = "",
							type = "select",
							values = SkuQuest.questMarkerBeaconsTypeValues,
							OnAction = function(self, info, val)
								SkuQuest:UpdateZoneAvailableQuestList(true)
							end,
							set = function(info,val)
								SkuSettings:Sub("SkuQuest").questMarkerBeacons.availableQuests.beaconType = SkuQuest.questMarkerBeaconsTypeValues[val]
							end,
							get = function(info)
								return SkuSettings:Sub("SkuQuest").questMarkerBeacons.availableQuests.beaconType
							end
						},									
						-- beacon volume
						beaconVolume = {
							order = 4,
							name = L["beacon volume"],
							desc = "",
							type = "range",
							OnAction = function(self, info, val)
								SkuQuest:UpdateZoneAvailableQuestList(true)
							end,
						},

						-- max range
						maxRange = {
							order = 5,
							name = L["max notification range"],
							desc = "",
							type = "range",
							OnAction = function(self, info, val)
								SkuQuest:UpdateZoneAvailableQuestList(true)
							end,
						},
						-- chat output
						chatNotification = {
							order = 6,
							name = L["chat notification"],
							desc = "",
							type = "toggle",
							OnAction = function(self, info, val)
								SkuQuest:UpdateZoneAvailableQuestList(true)
							end,
						},
						-- disable on
						disableOn = {
							order = 7,
							name = L["distance to quest giver for disabling quest notification"],
							desc = "",
							type = "range",
							OnAction = function(self, info, val)
								SkuQuest:UpdateZoneAvailableQuestList(true)
							end,
						},
						-- disable seen forever
						disableSeenForever = {
							order = 8,
							name = L["disable seen quest notifications forever"],
							desc = "",
							type = "toggle",
							OnAction = function(self, info, val)
								SkuQuest:UpdateZoneAvailableQuestList(true)
							end,
						},
						minLevel = {
							order = 9,
							name = L["Ignore quests x levels below your level"],
							desc = "",
							type = "range",
							OnAction = function(self, info, val)
								SkuQuest:UpdateZoneAvailableQuestList(true)
							end,
						},

					},
				},
				currentQuests ={
					name = L["current (in your log, ready to hand in)"],
					type = "group",
					order = 1,
					args= {
						enabled = {
							order = 1,
							name = L["Enabled"],
							desc = "",
							type = "toggle",
							OnAction = function(self, info, val)
								SkuQuest:UpdateZoneAvailableQuestList(true)
							end,
						},
						enableBeacons = {
							order = 1.4,
							name = L["enable Beacons"],
							desc = "",
							type = "toggle",
							OnAction = function(self, info, val)
								SkuQuest:UpdateZoneAvailableQuestList(true)
							end,
						},
						enableClickClack = {
							order = 1.5,
							name = L["Ton für Klick bei Beacons"],
							desc = "",
							type = "select",
							values = SkuNav.ClickClackSoundsets,
							OnAction = function(self, info, val)
								SkuQuest:UpdateZoneAvailableQuestList(true)
							end,
						},
						singlePing = {
							order = 1.75,
							name = L["only one beacon ping"],
							desc = "",
							type = "toggle",
							OnAction = function(self, info, val)
								SkuQuest:UpdateZoneAvailableQuestList(true)
							end,
						},

						beaconSoundSet = {
							order = 2,
							name = L["beacon sound"],
							desc = "",
							type = "select",
							values = SkuNav.BeaconSoundSetNames,
							OnAction = function(self, info, val)
								local tPlayerPosX, tPlayerPosY = UnitPosition("player")
								tPlayerPosX, tPlayerPosY = tPlayerPosX + 6, tPlayerPosY + 6
								if not SkuOptions.BeaconLib:CreateBeacon("SkuOptions", "sampleBeacon", SkuNav.BeaconSoundSetNames[val], tPlayerPosX + 10, tPlayerPosY, -3, 0, SkuOptions.db.profile["SkuNav"].beaconVolume, SkuSettings:Sub("SkuQuest").clickClackRange) then
									return
								end
								SkuOptions.BeaconLib:StartBeacon("SkuOptions", "sampleBeacon")
								C_Timer.After(1, function()
									SkuOptions.BeaconLib:DestroyBeacon("SkuOptions", "sampleBeacon")
								end)

								SkuQuest:UpdateZoneAvailableQuestList(true)
							end,	
							set = function(info,val)
								SkuSettings:Sub("SkuQuest").questMarkerBeacons.currentQuests.beaconSoundSet = SkuNav.BeaconSoundSetNames[val]
							end,
							get = function(info)
								return SkuSettings:Sub("SkuQuest").questMarkerBeacons.currentQuests.beaconSoundSet
							end
						},
						-- beacon type
						beaconType = {
							order = 3,
							name = L["beacon type"],
							desc = "",
							type = "select",
							OnAction = function(self, info, val)
								SkuQuest:UpdateZoneAvailableQuestList(true)
							end,
							values = SkuQuest.questMarkerBeaconsTypeValues,
							set = function(info,val)
								SkuSettings:Sub("SkuQuest").questMarkerBeacons.currentQuests.beaconType = SkuQuest.questMarkerBeaconsTypeValues[val]
							end,
							get = function(info)
								return SkuSettings:Sub("SkuQuest").questMarkerBeacons.currentQuests.beaconType
							end
						},							
						-- beacon volume
						beaconVolume = {
							order = 4,
							name = L["beacon volume"],
							desc = "",
							type = "range",
							OnAction = function(self, info, val)
								SkuQuest:UpdateZoneAvailableQuestList(true)
							end,
						},

						-- max range
						maxRange = {
							order = 5,
							name = L["max notification range"],
							desc = "",
							type = "range",
							OnAction = function(self, info, val)
								SkuQuest:UpdateZoneAvailableQuestList(true)
							end,
						},
						-- chat output
						chatNotification = {
							order = 6,
							name = L["chat notification"],
							desc = "",
							type = "toggle",
							OnAction = function(self, info, val)
								SkuQuest:UpdateZoneAvailableQuestList(true)
							end,
						},
						-- disable on
						disableOn = {
							order = 7,
							name = L["distance to quest giver for disabling quest notification"],
							desc = "",
							type = "range",
							OnAction = function(self, info, val)
								SkuQuest:UpdateZoneAvailableQuestList(true)
							end,
						},
						-- disable seen forever
						disableSeenForever = {
							order = 8,
							name = L["disable seen quest notifications forever"],
							desc = "",
							type = "toggle",
							OnAction = function(self, info, val)
								SkuQuest:UpdateZoneAvailableQuestList(true)
							end,
						},
						minLevel = {
							order = 9,
							name = L["Ignore quests x levels below your level"],
							desc = "",
							type = "range",
							OnAction = function(self, info, val)
								SkuQuest:UpdateZoneAvailableQuestList(true)
							end,
						},

					},
				},
			},
		},
	}
}

---------------------------------------------------------------------------------------------------------------------------------------
SkuQuest.defaults = {
	enable = true,
	showDifficultyColors = true,
	showGroupQuests = true,
	questMarkerBeacons = {
		availableQuests = {
			enabled = false,
			enableBeacons = true,
			enableClickClack = "off",
			singlePing = false,
			beaconSoundSet = "Beacon 1",
			beaconType = -7,
			beaconVolume = 40,
			maxRange = 30,
			chatNotification = true,
			disableOn = 5,
			disableSeenForever = false,
			minLevel = 5,
		},
		currentQuests = {
			enabled = false,
			enableBeacons = true,
			enableClickClack = "off",
			singlePing = false,
			beaconSoundSet = "Beacon 3",
			beaconType = -7,
			beaconVolume = 40,
			maxRange = 60,
			chatNotification = true,
			disableOn = 5,
			disableSeenForever = false,
			minLevel = 15,
		},
	},
}

---------------------------------------------------------------------------------------------------------------------------------------
-- Settings schema for SkuQuest (Sku 42 rework, W2 M-C1 / W1 Phase C). Single
-- source of truth (scope/default/type) for every settings key in the options
-- menu. All keys are profile scope (the option handlers use SkuSettings:Sub
-- with no scope arg). Dotted keys mirror the nested group/storage path. Nodes
-- whose get/set are pure storage are schema-managed (their get/set were
-- removed); beaconSoundSet/beaconType keep their get/set because they transform
-- the value (name<->id), so they are listed here but stay non-managed.
SkuSettings:Register("SkuQuest", {
	["showDifficultyColors"]                              = { scope = "profile", default = true,  type = "boolean" },
	["showGroupQuests"]                                   = { scope = "profile", default = true,  type = "boolean" },

	["questMarkerBeacons.availableQuests.enabled"]            = { scope = "profile", default = false,     type = "boolean" },
	["questMarkerBeacons.availableQuests.enableBeacons"]      = { scope = "profile", default = true,      type = "boolean" },
	["questMarkerBeacons.availableQuests.enableClickClack"]   = { scope = "profile", default = "off",     type = "string"  },
	["questMarkerBeacons.availableQuests.singlePing"]         = { scope = "profile", default = false,     type = "boolean" },
	["questMarkerBeacons.availableQuests.beaconSoundSet"]     = { scope = "profile", default = "Beacon 1", type = "string"  },
	["questMarkerBeacons.availableQuests.beaconType"]         = { scope = "profile", default = -7,        type = "number"  },
	["questMarkerBeacons.availableQuests.beaconVolume"]       = { scope = "profile", default = 40,        type = "number"  },
	["questMarkerBeacons.availableQuests.maxRange"]           = { scope = "profile", default = 30,        type = "number"  },
	["questMarkerBeacons.availableQuests.chatNotification"]   = { scope = "profile", default = true,      type = "boolean" },
	["questMarkerBeacons.availableQuests.disableOn"]          = { scope = "profile", default = 5,         type = "number"  },
	["questMarkerBeacons.availableQuests.disableSeenForever"] = { scope = "profile", default = false,     type = "boolean" },
	["questMarkerBeacons.availableQuests.minLevel"]           = { scope = "profile", default = 5,         type = "number"  },

	["questMarkerBeacons.currentQuests.enabled"]            = { scope = "profile", default = false,      type = "boolean" },
	["questMarkerBeacons.currentQuests.enableBeacons"]      = { scope = "profile", default = true,       type = "boolean" },
	["questMarkerBeacons.currentQuests.enableClickClack"]   = { scope = "profile", default = "off",      type = "string"  },
	["questMarkerBeacons.currentQuests.singlePing"]         = { scope = "profile", default = false,      type = "boolean" },
	["questMarkerBeacons.currentQuests.beaconSoundSet"]     = { scope = "profile", default = "Beacon 3", type = "string"  },
	["questMarkerBeacons.currentQuests.beaconType"]         = { scope = "profile", default = -7,         type = "number"  },
	["questMarkerBeacons.currentQuests.beaconVolume"]       = { scope = "profile", default = 40,         type = "number"  },
	["questMarkerBeacons.currentQuests.maxRange"]           = { scope = "profile", default = 60,         type = "number"  },
	["questMarkerBeacons.currentQuests.chatNotification"]   = { scope = "profile", default = true,       type = "boolean" },
	["questMarkerBeacons.currentQuests.disableOn"]          = { scope = "profile", default = 5,          type = "number"  },
	["questMarkerBeacons.currentQuests.disableSeenForever"] = { scope = "profile", default = false,      type = "boolean" },
	["questMarkerBeacons.currentQuests.minLevel"]           = { scope = "profile", default = 15,         type = "number"  },
})

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
----------------------------------------------------------------------------------------------------------------------------------------
-- Questie integration helpers (all SILENT no-ops when Questie is absent).
--
-- IMPORTANT: Questie's public functions are DOT functions (QuestieEvent.IsEventQuest,
-- QuestieDB.IsDoable, QuestieDB.GetQuest, ...). They must be called with a dot / an
-- explicit first argument, NEVER with a colon (a colon passes the wrong `self` as the
-- questId and silently breaks the call — that was the old event-filter bug). Every
-- call below goes through pcall so a Questie API change can never raise into Sku, and
-- every uncertain result biases toward SHOWING the quest rather than over-filtering.
----------------------------------------------------------------------------------------------------------------------------------------
SkuQuest._questieModuleCache = SkuQuest._questieModuleCache or {}

-- Safe, cached module import. Returns the module or nil (never errors, never caches a
-- negative so a not-yet-loaded Questie module can still resolve later).
function SkuQuest:QuestieModule(aName)
	if not _G.QuestieLoader then
		return nil
	end
	local tCache = SkuQuest._questieModuleCache
	if tCache[aName] then
		return tCache[aName]
	end
	local tOk, tMod = pcall(_G.QuestieLoader.ImportModule, _G.QuestieLoader, aName)
	if tOk and tMod then
		tCache[aName] = tMod
		return tMod
	end
	return nil
end

-- True only once Questie has FULLY finished loading. Critical for the "doable" queries:
-- QuestieDB builds its race/class memoize cache early with dummy player flags (race flag
-- 255 = "matches nothing"), and QuestiePlayer:Initialize fixes those flags only in a
-- LATER init stage. Querying IsDoable/IsDoableVerbose in that window permanently caches a
-- bogus "wrong race" verdict for every faction quest. Gating on Questie.started keeps Sku
-- from reading — or poisoning — that cache until the real flags are in place.
function SkuQuest:QuestieReady()
	return _G.Questie ~= nil and _G.Questie.started == true
end

-- Weaker date-range fallback: is the given event name active today?
-- Returns true / false / nil (nil = unknown -> callers bias to SHOW).
function SkuQuest:IsEventActiveByDate(aEventName)
	if not aEventName or aEventName == "" then
		return nil
	end
	local tQE = SkuQuest:QuestieModule("QuestieEvent")
	local tDates = tQE and tQE.eventDates
	if not tDates or not tDates[aEventName] then
		return nil
	end
	local tStartDay, tStartMonth = strsplit("/", tDates[aEventName].startDate)
	local tEndDay, tEndMonth = strsplit("/", tDates[aEventName].endDate)
	return SkuQuest:WithinDates(tonumber(tStartDay), tonumber(tStartMonth), tonumber(tEndDay), tonumber(tEndMonth))
end

-- Event-quest gate. Returns true ONLY when we are confident the quest belongs to a
-- world event that is currently INACTIVE (so it should be hidden). In every uncertain
-- case — Questie missing, calendar not loaded yet, unknown dates — it returns false
-- (SHOW). Primary source is Questie's calendar-aware IsEventActiveForQuest; the weaker
-- date range only ever confirms a hide, it never forces one.
function SkuQuest:IsEventQuestInactive(aQuestID)
	if not SkuQuest:QuestieReady() then
		return false -- Questie not fully loaded yet -> don't filter, just show
	end
	local tQE = SkuQuest:QuestieModule("QuestieEvent")
	if not tQE or not tQE.IsEventQuest or not tQE.IsEventActiveForQuest then
		return false -- no Questie event data -> never filter, just show
	end

	local tOk, tIsEvent = pcall(tQE.IsEventQuest, aQuestID)
	if not tOk or tIsEvent ~= true then
		return false -- not an event quest (or lookup failed) -> show
	end

	-- Primary: Questie's calendar-aware active flag.
	local tOkActive, tActive = pcall(tQE.IsEventActiveForQuest, aQuestID)
	if tOkActive and tActive == true then
		return false -- event is active -> show
	end

	-- Questie reports "not active"; this is ambiguous before Questie's calendar has
	-- loaded, so corroborate with the weaker date fallback and bias to SHOW.
	local tName
	local tOkName, tNameRes = pcall(tQE.GetEventNameFor, aQuestID)
	if tOkName then
		tName = tNameRes
	end
	if SkuQuest:IsEventActiveByDate(tName) == false then
		return true -- Questie AND the date range agree the event is inactive -> hide
	end
	return false -- unsure, or the date range says active -> show
end

-- "Questie says don't offer this here" gate. Returns true ONLY when Questie confidently
-- reports the quest as unavailable for a TIME / AVAILABILITY reason:
--   * an inactive world event (EVENT_INACTIVE),
--   * an out-of-rotation / limit-reached daily (INACTIVE_DAILY / MISSING_DAILY),
--   * an auto-blacklisted quest (BLACKLISTED) — Questie's blacklist covers duplicates,
--     removed-from-game quests, AND seasonal quests that aren't registered as event
--     quests (e.g. the Pilgrim's Bounty hub quest 14022, or Candy Bucket entries).
-- It deliberately does NOT act on character-gated reasons (race/class/level/reputation/
-- prerequisite) so those still bias to SHOW. Questie's own IsDoableVerbose keeps
-- HIDE_ON_MAP quests OUT of the BLACKLISTED state, so map-only hides stay visible here.
-- Silent SHOW on any uncertainty or when Questie is absent/not ready.
function SkuQuest:IsQuestieUnavailable(aQuestID)
	if not SkuQuest:QuestieReady() then
		return false
	end
	local tQDB = SkuQuest:QuestieModule("QuestieDB")
	if not tQDB or not tQDB.IsDoableVerbose or not tQDB.DoableStates then
		return false
	end
	local tOk, _tText, _tLabel, tState = pcall(tQDB.IsDoableVerbose, aQuestID, false, true, true)
	if not tOk then
		return false
	end
	local tDS = tQDB.DoableStates
	if tState == tDS.INACTIVE_DAILY
		or tState == tDS.MISSING_DAILY
		or tState == tDS.EVENT_INACTIVE
		or tState == tDS.BLACKLISTED
	then
		return true
	end
	return false
end

-- Combined status phrase for the quest tooltip, localized by Questie to the client
-- language. Questie's brief IsDoableVerbose text already folds "have I done it?" and
-- "can I do it?" into one phrase, e.g. "Verfügbar", "Verfügbar: Spieler hat Quest",
-- "Nicht verfügbar: Bereits abgeschlossen", "Nicht verfügbar: Ereignis inaktiv".
-- Returns that phrase, or nil when Questie is absent/not ready (caller then falls back
-- to the plain completed/in-log state).
function SkuQuest:GetDoableStatusText(aQuestID)
	if not SkuQuest:QuestieReady() then
		return nil
	end
	local tQDB = SkuQuest:QuestieModule("QuestieDB")
	if not tQDB or not tQDB.IsDoableVerbose then
		return nil
	end
	local tOk, tText = pcall(tQDB.IsDoableVerbose, aQuestID, false, true, true)
	if not tOk or not tText or tText == "" then
		return nil
	end
	return tText
end

----------------------------------------------------------------------------------------------------------------------------------------
-- Resolve the area/zone id a quest STARTS in (from its quest-giver creature or object),
-- mirroring the derivation used when building the zone quest lists. Returns nil for
-- item-started quests or unknown givers.
function SkuQuest:GetQuestStartZoneId(aQuestID)
	local tData = SkuDB.questDataTBC[aQuestID]
	local tStartedBy = tData and tData[SkuDB.questKeys["startedBy"]]
	if not tStartedBy then
		return nil
	end
	if tStartedBy[1] and tStartedBy[1][1] and SkuDB.NpcData.Data[tStartedBy[1][1]] then --creatures
		return SkuDB.NpcData.Data[tStartedBy[1][1]][SkuDB.NpcData.Keys['zoneID']]
	elseif tStartedBy[2] and tStartedBy[2][1] and SkuDB.objectDataTBC[tStartedBy[2][1]] then --objects
		return SkuDB.objectDataTBC[tStartedBy[2][1]][SkuDB.objectKeys["zoneID"]]
	end
	return nil
end

----------------------------------------------------------------------------------------------------------------------------------------
-- Group members' quests from Questie's party comms. QuestieComms.remoteQuestLogs is
-- keyed questId -> playerName -> objectives; this re-indexes it player-first:
--   { ["Membername"] = { [questId] = objectivesTable, ... }, ... }
-- Realm suffixes are stripped so keys match UnitName(). Members without Questie never
-- send comms, so they simply have no key here — silent empty result when Questie is
-- absent/not ready.
function SkuQuest:GetGroupMemberQuests()
	local tResult = {}
	if not SkuQuest:QuestieReady() then
		return tResult
	end
	local tQC = SkuQuest:QuestieModule("QuestieComms")
	local tLogs = tQC and tQC.remoteQuestLogs
	if type(tLogs) ~= "table" then
		dprint("groupQuests GetGroupMemberQuests: no remoteQuestLogs table (tQC=", tQC ~= nil, ")")
		return tResult
	end
	local tRawQuestCount, tRawPairCount = 0, 0
	for tQuestId, tPlayers in pairs(tLogs) do
		if type(tQuestId) == "number" and type(tPlayers) == "table" then
			tRawQuestCount = tRawQuestCount + 1
			for tPlayerName, tObjectives in pairs(tPlayers) do
				tRawPairCount = tRawPairCount + 1
				local tShortName = strsplit("-", tPlayerName)
				tResult[tShortName] = tResult[tShortName] or {}
				tResult[tShortName][tQuestId] = tObjectives
			end
		end
	end
	-- Log the re-indexed keyset so an in-game group test shows exactly which
	-- player names carry data (compare against the UnitName() member keys).
	local tKeys = {}
	for tName, tQ in pairs(tResult) do
		local tN = 0
		for _ in pairs(tQ) do tN = tN + 1 end
		tKeys[#tKeys+1] = tName.."="..tN
	end
	dprint("groupQuests GetGroupMemberQuests: rawQuests=", tRawQuestCount, "rawPairs=", tRawPairCount, "players={", table.concat(tKeys, ", "), "}")
	return tResult
end

----------------------------------------------------------------------------------------------------------------------------------------
-- Spoken progress lines for one remote quest from Questie objective data (per
-- objective: id, type "m"/"o"/"i", fulfilled, required, finished). WoW has no API to
-- read another player's quest log text, so the lines are reconstructed: target names
-- come from the Sku database, unknown targets fall back to "Ziel N".
-- Returns: text (may be ""), isComplete (true when there is at least one objective
-- and all are finished).
function SkuQuest:GetGroupQuestProgressText(aQuestID, aObjectives)
	local tLines = {}
	local tCount, tDone = 0, 0
	for tIndex, tObj in pairs(aObjectives or {}) do
		if type(tObj) == "table" then
			tCount = tCount + 1
			local tName
			if (tObj.type == "m" or tObj.type == "monster") and tObj.id and SkuDB.NpcData.Names[Sku.Loc][tObj.id] then
				tName = SkuDB.NpcData.Names[Sku.Loc][tObj.id][1]
			elseif (tObj.type == "o" or tObj.type == "object") and tObj.id then
				tName = SkuDB.objectLookup[Sku.Loc][tObj.id] or (SkuDB.objectDataTBC[tObj.id] and SkuDB.objectDataTBC[tObj.id][1])
			elseif (tObj.type == "i" or tObj.type == "item") and tObj.id then
				tName = SkuDB.itemLookup[Sku.Loc][tObj.id]
			end
			tName = tName or (L["Ziel"].." "..(tObj.index or tIndex))
			if tObj.finished == true then
				tDone = tDone + 1
				tLines[#tLines+1] = tName..": "..L["(Fertig) "]
			elseif tObj.required then
				tLines[#tLines+1] = tName..": "..tostring(tObj.fulfilled or 0).."/"..tostring(tObj.required)
			else
				tLines[#tLines+1] = tName
			end
		end
	end
	return table.concat(tLines, "\r\n"), (tCount > 0 and tCount == tDone)
end

----------------------------------------------------------------------------------------------------------------------------------------
local tStatesFriendly = {["false"] = L["No"], ["true"] = L["Yes"], ["nil"] = L["Unknown"],}
function SkuQuest:GetQuestDataStringFromDB(aQuestID, aZoneID)
	local tSections = {}

	if aQuestID then
		local i = aQuestID

		table.insert(tSections, SkuDB.questLookup[Sku.Loc][i][1]) --de name

		if aQuestID and SkuDB.questDataTBC[aQuestID] then
			if SkuDB.questDataTBC[aQuestID][SkuDB.questKeys.skuData] then
				local tTemptext = ""
				if SkuDB.questDataTBC[aQuestID][SkuDB.questKeys.skuData][1] and SkuDB.questDataTBC[aQuestID][SkuDB.questKeys.skuData][1][1] == true then
					tTemptext = L["Warning: This quest is blacklisted"]
					if SkuDB.questDataTBC[aQuestID][SkuDB.questKeys.skuData][1][2] then
						for _, blacklistComment in pairs(SkuDB.questDataTBC[aQuestID][SkuDB.questKeys.skuData][1][2][Sku.Loc]) do
							tTemptext = tTemptext.."\r\n"..blacklistComment
						end
					end
				end
				if SkuDB.questDataTBC[aQuestID][SkuDB.questKeys.skuData][2] then
					if tTemptext ~= "" then
						tTemptext = tTemptext.."\r\n"
					end
					tTemptext = tTemptext..L["Sku quest comments:"]
					for _, skuComment in pairs(SkuDB.questDataTBC[aQuestID][SkuDB.questKeys.skuData][2][Sku.Loc]) do
						tTemptext = tTemptext.."\r\n"..skuComment
					end
				end
				table.insert(tSections, tTemptext)
			end
		end

		local tCurrentQuestLogQuestsTable = {}
		local numEntries = GetNumQuestLogEntries()
		if (numEntries > 0) then
			for questLogID = 1, numEntries do
				local title, level, suggestedGroup, isHeader, isCollapsed, isComplete, frequency, questID, startEvent, displayQuestID, isOnMap, hasLocalPOI, isTask, isStory = GetQuestLogTitle(questLogID)
				tCurrentQuestLogQuestsTable[questID] = true
			end
		end
		-- One combined status line answering both "have I done it?" and "can I do it?".
		-- Prefer Questie's phrase (it already covers completed / in-log / available /
		-- block-reason); fall back to the plain completed/in-log state when Questie is
		-- unavailable.
		local tStatusText = SkuQuest:GetDoableStatusText(i)
		if not tStatusText then
			if not tCurrentQuestLogQuestsTable[aQuestID] then
				tStatusText = L["Completed"]..": "..tStatesFriendly[tostring(C_QuestLog.IsQuestFlaggedCompleted(i))] --https://wowpedia.fandom.com/wiki/API_C_QuestLog.GetAllCompletedQuestIDs
			else
				tStatusText = L["Completed: In log"]
			end
		end
		table.insert(tSections, tStatusText)

		-- The distance-sorted menu path renders the tooltip without a zone id, so derive
		-- the quest's start zone ourselves when the caller didn't pass one.
		local tZoneID = aZoneID or SkuQuest:GetQuestStartZoneId(i)
		if tZoneID and SkuDB.InternalAreaTable[tZoneID] then
			table.insert(tSections, L["Zone"]..": "..SkuDB.InternalAreaTable[tZoneID].AreaName_lang[Sku.Loc])
		else
			table.insert(tSections, L["Zone: Unknown"])
		end

		table.insert(tSections, L["Level"]..": "..SkuDB.questDataTBC[i][SkuDB.questKeys["questLevel"]].." ("..SkuDB.questDataTBC[i][SkuDB.questKeys["requiredLevel"]]..")")

		if SkuDB.questLookup[Sku.Loc][i][3] then
			table.insert(tSections, L["Objectives"].."\r\n"..(SkuDB.questLookup[Sku.Loc][i][3][1] or ""))
		else
			table.insert(tSections, L["Objectives"].."\r\n")
		end
		--table.insert(tSections, "Questtext\r\n"..questDescription

		local rRaces = {}
		local tFlagH = nil
		local tFlagA = nil
		for iR, vR in pairs(SkuDB.raceKeys) do
			if bit.band(vR, SkuDB.questDataTBC[i][SkuDB.questKeys["requiredRaces"]]) > 0 then
				table.insert(rRaces, iR)
				if iR == "ALL_HORDE" then
					tFlagH = true
				end
				if iR == "ALL_ALLIANCE" then
					tFlagA = true
				end
			end
		end
		local tRaceText = ""
		if tFlagH then
			tRaceText = tRaceText..SkuQuest.racesFriendly["ALL_HORDE"]..";"
		end
		if tFlagA then
			tRaceText = tRaceText..SkuQuest.racesFriendly["ALL_ALLIANCE"]..";"
		end
		if not tFlagA and not tFlagH then
			for i, v in pairs(rRaces) do
				--dprint(i, v)
				tRaceText = tRaceText..SkuQuest.racesFriendly[v]..";"
			end
		end
		table.insert(tSections, L["Races"]..": "..tRaceText)

		local tClasses = {}
		for iR, vR in pairs(SkuDB.classKeys) do
			if SkuDB.questDataTBC[i][SkuDB.questKeys["requiredClasses"]] then
				if bit.band(vR, SkuDB.questDataTBC[i][SkuDB.questKeys["requiredClasses"]]) > 0 then
					table.insert(tClasses, iR)
				end
			end
		end
		local tClassText = ""
		for i, v in pairs(tClasses) do
			--dprint(i, v)
			tClassText = tClassText..SkuQuest.classesFriendly[v]..";"
		end
		-- Only show the class line when the quest is actually class-restricted; it is
		-- empty for the vast majority of quests.
		if tClassText ~= "" then
			table.insert(tSections, L["Classes"]..": "..tClassText)
		end

		if SkuDB.questDataTBC[i][SkuDB.questKeys["preQuestGroup"]] then -- table: {quest(int)} - all to be completed before next in series
			local preQuestGroup = ""
			for iR, vR in pairs(SkuDB.questDataTBC[i][SkuDB.questKeys["preQuestGroup"]]) do
				preQuestGroup = preQuestGroup.."\r\n"..iR.." "..SkuDB.questLookup[Sku.Loc][vR][1]
			end
			table.insert(tSections, L["Pre Quests"]..": "..preQuestGroup)
		end
		if SkuDB.questDataTBC[i][SkuDB.questKeys["preQuestSingle"]] then -- table: {quest(int)} - one to be completed before next in series
			local preQuestSingle = ""
			for iR, vR in pairs(SkuDB.questDataTBC[i][SkuDB.questKeys["preQuestSingle"]]) do
				preQuestSingle = preQuestSingle.."\r\n"..iR.." "..SkuDB.questLookup[Sku.Loc][vR][1]
			end
			table.insert(tSections, L["Pre Quest"]..": "..preQuestSingle)
		end
		if SkuDB.questDataTBC[i][SkuDB.questKeys["inGroupWith"]] then -- table: {quest(int)} - to be completed additional to this before next in series
			local inGroupWith = ""
			for iR, vR in pairs(SkuDB.questDataTBC[i][SkuDB.questKeys["inGroupWith"]]) do
				inGroupWith = inGroupWith.."\r\n"..iR.." "..SkuDB.questLookup[Sku.Loc][vR][1]
			end
			table.insert(tSections, L["Quests group"]..": "..inGroupWith)
		end

		if SkuDB.questDataTBC[i][SkuDB.questKeys["parentQuest"]] then -- table: {quest(int)} - to be completed additional to this before next in series
			if SkuDB.questDataTBC[i][SkuDB.questKeys["parentQuest"]] then
				if SkuDB.questLookup[Sku.Loc][SkuDB.questDataTBC[i][SkuDB.questKeys["parentQuest"]]] then
					if SkuDB.questLookup[Sku.Loc][SkuDB.questDataTBC[i][SkuDB.questKeys["parentQuest"]]][1] then
						local parentQuest = ""
						parentQuest = parentQuest.."\r\n"..SkuDB.questDataTBC[i][SkuDB.questKeys["parentQuest"]].." "..SkuDB.questLookup[Sku.Loc][SkuDB.questDataTBC[i][SkuDB.questKeys["parentQuest"]]][1]
						table.insert(tSections, L["Parent quest"]..": "..parentQuest)
					end
				end
			end
		end


		--if SkuDB.questDataTBC[i][SkuDB.questKeys["parentQuest"]] then -- 
			--table.insert(tSections, "parentQuest: "..SkuDB.questDataTBC[i][SkuDB.questKeys["parentQuest"]])
		--end
		--if SkuDB.questDataTBC[i][SkuDB.questKeys["childQuests"]] then -- table: {quest(int)} - to be completed additional to this before next in series
			--local childQuests = ""
			--for iR, vR in pairs(SkuDB.questDataTBC[i][SkuDB.questKeys["childQuests"]]) do
				--childQuests = childQuests..";"..iR.."-"..vR
			--end
			--table.insert(tSections, "childQuests: "..childQuests)
		--end									

		local tFlags = {}
		for iR, vR in pairs(SkuDB.QuestFlags) do
			if SkuDB.questDataTBC[i][SkuDB.questKeys["questFlags"]] then
				--dprint(iR, vR, SkuDB.questDataTBC[i][SkuDB.questKeys["questFlags"]])
				if bit.band(vR, SkuDB.questDataTBC[i][SkuDB.questKeys["questFlags"]]) > 0 then
					table.insert(tFlags, iR)
				end
			end
		end
		local tFlagText = ""
		for i, v in pairs(tFlags) do
			tFlagText = tFlagText..SkuDB.QuestFlagsFriendly[v]..";"
		end
		table.insert(tSections, L["Attributes"]..": "..tFlagText)

		--[[
		['requiredSkill'] = 18, -- table: {skill(int), value(int)}
		['requiredMinRep'] = 19, -- table: {faction(int), value(int)}
		['requiredMaxRep'] = 20, -- table: {faction(int), value(int)}
		['requiredSourceItems'] = 21, -- table: {item(int), ...} Items that are not an objective but still needed for the quest.

		['specialFlags'] = 24, -- bitmask: 1 = Repeatable, 2 = Needs event, 4 = Monthly reset (req. 1). See https://github.com/cmangos/issues/wiki/Quest_template#specialflags

		['reputationReward'] = 26, -- table: {{FACTION,VALUE}, ...}, A list of reputation reward for factions
		]]

		-- Quest ID goes dead last: rarely useful, keep it out of the way.
		table.insert(tSections, L["Quest ID"]..": "..i)
	end

	return tSections
end

---------------------------------------------------------------------------------------------------------------------------------------
local function CreatureIdHelper(aCreatureIds, aTargetTable, aOnly3, aOnlyUiMapId)
	local _, _, tPlayerContinentID  = SkuNav.Geo:GetAreaData(SkuNav.Geo:GetCurrentAreaId())

	for i, tNpcID in pairs(aCreatureIds) do
		--dprint("CreateRtWpSubmenu", i, tNpcID)		
		local i = tNpcID
		if SkuDB.NpcData.Data[i] then
			local tSpawns = SkuDB.NpcData.Data[i][7]
			if tSpawns then
				for is, vs in pairs(tSpawns) do
					local isUiMap = SkuNav.Geo:GetUiMapIdFromAreaId(is)
					--we don't care for stuff that isn't in the open world
					if isUiMap and (not aOnlyUiMapId or aOnlyUiMapId == isUiMap ) then
						local tData = SkuDB.InternalAreaTable[is]
						if tData then
							if SkuNav.Geo:GetContinentNameFromContinentId(tData.ContinentID) then
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
										table.insert(aTargetTable[SkuDB.NpcData.Names[Sku.Loc][i][1]..tRolesString], L["Anderer Kontinent"]..";"..SkuNav.Geo:GetContinentNameFromContinentId(tData.ContinentID)..";"..tData.AreaName_lang[Sku.Loc])
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
function SkuQuest:GetResultingWps(aSubIDTable, aSubType, aQuestID, tResultWPs, aOnly3, aOnlyUiMapId)
	--dprint("GetResultingWps", aSubIDTable, aSubType, aQuestID, tResultWPs, aOnly3)
	-- [DB rework stage 3] Resolves item/creature/object chains with UNCHECKED
	-- chained indexing (e.g. itemDataTBC[id][objectDrops] at the top of the
	-- item branch). While the streamed init has not finished those families
	-- the chain head is nil -> crash. Bail out; tResultWPs stays empty and
	-- callers re-run on their next natural trigger (menu reopen,
	-- QUEST_LOG_UPDATE, the master's post-stream refresh).
	if not (Sku:IsDataReady("skudb.creatures") and Sku:IsDataReady("skudb.objects") and Sku:IsDataReady("skudb.items")) then
		return
	end
	local _, _, tPlayerContinentID  = SkuNav.Geo:GetAreaData(SkuNav.Geo:GetCurrentAreaId())
	local tCurrentAreaId = SkuNav.Geo:GetCurrentAreaId()
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
								local isUiMap = SkuNav.Geo:GetUiMapIdFromAreaId(is)
								if isUiMap and (not aOnlyUiMapId or aOnlyUiMapId == isUiMap ) then
									--if is == tCurrentAreaId then
										local tData = SkuDB.InternalAreaTable[is]
										if tData then
											if SkuNav.Geo:GetContinentNameFromContinentId(tData.ContinentID) then
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
														table.insert(tResultWPs[tObjectName], L["Anderer Kontinent"]..";"..SkuNav.Geo:GetContinentNameFromContinentId(tData.ContinentID)..";"..tData.AreaName_lang[Sku.Loc])
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
				CreatureIdHelper(SkuDB.itemDataTBC[tItemId][SkuDB.itemKeys["npcDrops"]], tResultWPs, aOnly3, aOnlyUiMapId)
			end
			if SkuDB.itemDataTBC[tItemId][SkuDB.itemKeys["itemDrops"]] then
				--dprint("item drop from item")

			end
			if SkuDB.itemDataTBC[tItemId][SkuDB.itemKeys["vendors"]] then
				CreatureIdHelper(SkuDB.itemDataTBC[tItemId][SkuDB.itemKeys["vendors"]], tResultWPs, aOnly3, aOnlyUiMapId)
			end
		end
	elseif aSubType == "object" then
			for i, tObjectId in pairs(aSubIDTable) do
			if SkuDB.objectDataTBC[tObjectId] then
				local tSpawns = SkuDB.objectDataTBC[tObjectId][4]
				if tSpawns then
					for is, vs in pairs(tSpawns) do
						local isUiMap = SkuNav.Geo:GetUiMapIdFromAreaId(is)
						--we don't care for stuff that isn't in the open world
						if isUiMap then
							local tData = SkuDB.InternalAreaTable[is]
							if tData then
								if tPlayerContinentID == tData.ContinentID then
									if (not aOnlyUiMapId) or aOnlyUiMapId == isUiMap then
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
									if (not aOnlyUiMapId) or aOnlyUiMapId == isUiMap then
										local tNumberOfSpawns = #vs
										if tNumberOfSpawns > 3 and aOnly3 == true then
											tNumberOfSpawns = 3
										end
										for sp = 1, tNumberOfSpawns do
											local tObjectName = SkuDB.objectLookup[Sku.Loc][tObjectId] or SkuDB.objectDataTBC[tObjectId][1] or L["Object name missing"]
											if not tResultWPs[tObjectName] then
												tResultWPs[tObjectName] = {}
											end
											table.insert(tResultWPs[tObjectName], L["Anderer Kontinent"]..";"..SkuNav.Geo:GetContinentNameFromContinentId(tData.ContinentID)..";"..tData.AreaName_lang[Sku.Loc])

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
		CreatureIdHelper(aSubIDTable, tResultWPs, aOnly3, aOnlyUiMapId)

	elseif aSubType == "waypoint" then
		for i, tWaypointName in pairs(aSubIDTable) do
			local tData = SkuNav:GetWaypointData2(tWaypointName)
			if tData then
				local isUiMap = SkuNav.Geo:GetUiMapIdFromAreaId(tData.areaId)
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
local function CreateRtWpSubmenu(aParent, aSubIDTable, aSubType, aQuestID)
	dprint("CreateRtWpSubmenu aSubIDTable ", aSubIDTable, " - aSubType ", aSubType, " - aQuestID ", aQuestID)
	local tResultWPs = {}
	SkuQuest:GetResultingWps(aSubIDTable, aSubType, aQuestID, tResultWPs)

	local tPlayX, tPlayY = UnitPosition("player")
	local tRoutesInRange = SkuNav:GetAllLinkedWPsInRangeToCoords(tPlayX, tPlayY, SkuNav.MaxMetaEntryRange)--SkuOptions.db.profile["SkuNav"].nearbyWpRange)
	
	local tHasContent = false
	for unitGeneralName, wpTable in pairs(tResultWPs) do
		--dprint(unitGeneralName, wpTable)
		tHasContent = true
		local tNewMenuGeneralName = SkuOptions:InjectMenuItems(aParent, {unitGeneralName}, SkuGenericMenuItem)
		tNewMenuGeneralName.dynamic = true
		tNewMenuGeneralName.BuildChildren = function(self)
			if string.find(wpTable[1], L["Anderer Kontinent"]) then
				local tNewMenuSubEntry1 = SkuOptions:InjectMenuItems(self, {wpTable[1]}, SkuGenericMenuItem)
			else
				local tCoveredWps = {}

				local tNewMenuSubEntry1 = SkuOptions:InjectMenuItems(self, {L["Route"]}, SkuGenericMenuItem)
				tNewMenuSubEntry1.dynamic = true
				tNewMenuSubEntry1.isSelect = true
				tNewMenuSubEntry1.sorting = true
				tNewMenuSubEntry1.OnAction = function(self, aValue, aName)
					--print("Route onaction", self, aValue, aName)
					if SkuOptions.db.profile["SkuNav"].routeRecording == true then
						SkuOptions.Voice:OutputStringBTtts(L["Error"], false, true, 0.3, true)
						SkuOptions.Voice:OutputStringBTtts(L["Recording in progress"], false, true, 0.3, true)
						return
					end
					if SkuOptions.db.profile["SkuNav"].metapathFollowing == true or SkuOptions.db.profile["SkuNav"].selectedWaypoint ~= "" then
						SkuNav:EndFollowingWpOrRt()
					end
					SkuOptions.db.profile["SkuNav"].metapathFollowing = false

					if SkuOptions.db.profile["SkuNav"].metapathFollowingMetapaths then
						if string.find(SkuOptions.db.profile["SkuNav"].metapathFollowingStart, "#") then
							SkuOptions.db.profile["SkuNav"].metapathFollowingStart = string.sub(SkuOptions.db.profile["SkuNav"].metapathFollowingStart, string.find(SkuOptions.db.profile["SkuNav"].metapathFollowingStart, "#") + 1)
						end
						SkuOptions.db.profile["SkuNav"].metapathFollowingMetapaths = SkuNav:GetAllMetaTargetsFromWp5(SkuOptions.db.profile["SkuNav"].metapathFollowingStart, SkuOptions.db.profile["SkuNav"].routesMaxDistance, SkuNav.MaxMetaWPs, aName)--
						if not SkuOptions.db.profile["SkuNav"].metapathFollowingTarget then
							SkuOptions.db.profile["SkuNav"].metapathFollowingTarget = aName
						end
						SkuOptions.db.profile["SkuNav"].metapathFollowingCurrentWp = 1
						SkuOptions.db.profile["SkuNav"].metapathFollowing = true

						SkuNav:SelectWP(SkuOptions.db.profile["SkuNav"].metapathFollowingStart, true)
						SkuOptions.Voice:OutputStringBTtts(L["Following metaroute"], false, true, 0.2)

						SkuOptions:CloseMenu()
						SkuDispatcher:TriggerSkuEvent("SKU_ROUTE_STARTED")
					end

				end
				tNewMenuSubEntry1.BuildChildren = function(self)
					SkuOptions.SkuNav_MenuBuilder_WaypointSelectionMenu_CloseRoute = nil
					local tSortedWaypointList = BuildSortedUniqueRouteWps(tRoutesInRange)

					if #tSortedWaypointList == 0 then
						local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Empty;list"]}, SkuGenericMenuItem)
					else
						-- Vorlage-Struktur wiederhergestellt: pro nahegelegenem Einstiegs-Wp ein
						-- "Entry point: …"-Zwischenmenü, dessen BuildChildren erst die Metapaths
						-- für GENAU diesen Einstiegspunkt setzt und die WP-Auswahl daraus baut.
						-- In der vorherigen flachen Variante wurde metapathFollowingStart/-Metapaths
						-- bereits an dieser Stelle (Route.BuildChildren) gesetzt; das hat für die
						-- Routenfortführung nicht zuverlässig funktioniert (Abbruch nach erstem
						-- Wp mit "Route folgen beendet").
						local tCount = 0
						for k, v in SkuSpairs(tSortedWaypointList) do
							if tCount < 10 then
								local tSkuWpName = string.sub(v, string.find(v, "#") + 1)
								local tLayerText = SkuNav:GetLayerText(SkuNav:GetNonAutoLevel(nil, nil, tSkuWpName, nil))

								local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Entry point: "]..tLayerText..v}, SkuGenericMenuItem)
								tNewMenuEntry.dynamic = true
								tNewMenuEntry.sorting = true
								tNewMenuEntry.BuildChildren = function(self)
									if #tSortedWaypointList == 0 then
										local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Empty;list"]}, SkuGenericMenuItem)
									else
										local tMetapaths = SkuNav:GetAllMetaTargetsFromWp5(string.sub(v, string.find(v, "#") + 1), SkuOptions.db.profile["SkuNav"].routesMaxDistance, SkuNav.MaxMetaWPs)--
										SkuOptions.db.profile["SkuNav"].metapathFollowingStart = v
										SkuOptions.db.profile["SkuNav"].metapathFollowingMetapaths = tMetapaths
										SkuOptions.db.profile["SkuNav"].metapathFollowingTarget = nil

										do -- build route choices
											local tData = {}
											for i, v in pairs(tMetapaths) do
												for wpIndex, wpName in pairs(wpTable) do
													if string.find(i, wpName) then
														tData[i] = tMetapaths[i].distance
													end
												end
											end
											local tSortedList = {}
											for k,v in SkuSpairs(tData, function(t,a,b) return t[b] > t[a] end) do --nach wert
												table.insert(tSortedList, k)
											end
											if #tSortedList == 0 then
												local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Empty;list"]}, SkuGenericMenuItem)
											else
												for tK, tV in ipairs(tSortedList) do
													for wpIndex, wpName in pairs(wpTable) do
														if string.find(tV, wpName) then
															local tDistText = tMetapaths[tV].distance..L[";Meter"]
															if tMetapaths[tV].distance >= SkuOptions.db.profile["SkuNav"].routesMaxDistance then
																--tDistText = L["weit"]
															end

															-- add direction to wp
															local tDirectionTargetWp = ""
															if SkuOptions.db.profile["SkuNav"].showGlobalDirectionInWaypointLists == true then
																local tWpData = SkuNav:GetWaypointData2(tV)
																local tDirectionString = SkuNav.Geo:GetDirectionToAsString(tWpData.worldX, tWpData.worldY)
																if tDirectionString then
																	tDirectionTargetWp = ";"..tDirectionString
																end
															end
															tDistText = tDistText..tDirectionTargetWp

															local tNewMenuEntry = SkuOptions:InjectMenuItems(self, { SkuNav:getAnnotatedWaypointLabel(tDistText .. "#" .. tV, tV) }, SkuGenericMenuItem)
															tNewMenuEntry.OnEnter = function(self, aValue, aName)
																SkuOptions.db.profile["SkuNav"].metapathFollowingTarget = tV
															end
															tCoveredWps[tV] = true
															--tHasContent = true
														end
													end
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

				local tNewMenuSubEntry1 = SkuOptions:InjectMenuItems(self, {L["Closest route"]}, SkuGenericMenuItem)
				tNewMenuSubEntry1.dynamic = true
				tNewMenuSubEntry1.isSelect = true
				tNewMenuSubEntry1.sorting = true
				tNewMenuSubEntry1.OnAction = function(self, aValue, aName)
					--dprint("OnAction", self.name, aValue, aName)
					if SkuOptions.db.profile["SkuNav"].routeRecording == true then
						SkuOptions.Voice:OutputStringBTtts(L["Error"], false, true, 0.3, true)
						SkuOptions.Voice:OutputStringBTtts(L["Recording in progress"], false, true, 0.3, true)
						return
					end
					if SkuOptions.db.profile["SkuNav"].metapathFollowing == true or SkuOptions.db.profile["SkuNav"].selectedWaypoint ~= "" then
						SkuNav:EndFollowingWpOrRt()
					end
					SkuOptions.db.profile["SkuNav"].metapathFollowing = false
					if SkuOptions.db.profile["SkuNav"].metapathFollowingStart then
						if SkuOptions.db.profile["SkuNav"].metapathFollowingMetapaths then
							if string.find(SkuOptions.db.profile["SkuNav"].metapathFollowingStart, "#") then
								SkuOptions.db.profile["SkuNav"].metapathFollowingStart = string.sub(SkuOptions.db.profile["SkuNav"].metapathFollowingStart, string.find(SkuOptions.db.profile["SkuNav"].metapathFollowingStart, "#") + 1)
							end
							SkuOptions.db.profile["SkuNav"].metapathFollowingMetapaths = SkuNav:GetAllMetaTargetsFromWp5(SkuOptions.db.profile["SkuNav"].metapathFollowingStart, SkuOptions.db.profile["SkuNav"].routesMaxDistance, SkuNav.MaxMetaWPs, SkuOptions.db.profile["SkuNav"].metapathFollowingTarget, true)--
							--setmetatable(SkuOptions.db.profile["SkuNav"].metapathFollowingMetapaths, SkuPrintMTWo)
							SkuOptions.db.profile["SkuNav"].metapathFollowingMetapaths[#SkuOptions.db.profile["SkuNav"].metapathFollowingMetapaths+1] = SkuOptions.db.profile["SkuNav"].metapathFollowingEndTarget
							SkuOptions.db.profile["SkuNav"].metapathFollowingMetapaths[SkuOptions.db.profile["SkuNav"].metapathFollowingEndTarget] = SkuOptions.db.profile["SkuNav"].metapathFollowingMetapaths[SkuOptions.db.profile["SkuNav"].metapathFollowingTarget]
							table.insert(SkuOptions.db.profile["SkuNav"].metapathFollowingMetapaths[SkuOptions.db.profile["SkuNav"].metapathFollowingEndTarget].pathWps, SkuOptions.db.profile["SkuNav"].metapathFollowingEndTarget)
							SkuOptions.db.profile["SkuNav"].metapathFollowingTarget = SkuOptions.db.profile["SkuNav"].metapathFollowingEndTarget
							SkuOptions.db.profile["SkuNav"].metapathFollowingCurrentWp = 1
							SkuOptions.db.profile["SkuNav"].metapathFollowing = true
							SkuNav:SelectWP(SkuOptions.db.profile["SkuNav"].metapathFollowingStart, true)
							SkuOptions.Voice:OutputStringBTtts(L["Metaroute folgen gestartet"], false, true, 0.2)
							SkuOptions:CloseMenu()
						end
					end
				end
				tNewMenuSubEntry1.BuildChildren = function(self)
					local tMaxAllowedDistanceToTargetWp = 500
					local tSortedWaypointList = BuildSortedUniqueRouteWps(tRoutesInRange)
					if #tSortedWaypointList == 0 then
						local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Empty;list"]}, SkuGenericMenuItem)
					else
						local tCount = 0
						for k, v in SkuSpairs(tSortedWaypointList) do
							if tCount < 10 then
								local tSkuWpName = string.sub(v, string.find(v, "#") + 1)
								local tLayerText = SkuNav:GetLayerText(SkuNav:GetNonAutoLevel(nil, nil, tSkuWpName, nil))

								local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Entry point: "]..tLayerText..v}, SkuGenericMenuItem)
								tNewMenuEntry.dynamic = true
								tNewMenuEntry.sorting = true
								tNewMenuEntry.BuildChildren = function(self)
									if #tSortedWaypointList == 0 then
										local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Empty;list"]}, SkuGenericMenuItem)
									else
										local tMetapaths = SkuNav:GetAllMetaTargetsFromWp5(string.sub(v, string.find(v, "#") + 1), SkuOptions.db.profile["SkuNav"].routesMaxDistance, SkuNav.MaxMetaWPs, nil, true)
										SkuOptions.db.profile["SkuNav"].metapathFollowingStart = v
										SkuOptions.db.profile["SkuNav"].metapathFollowingMetapaths = tMetapaths
										SkuOptions.db.profile["SkuNav"].metapathFollowingTarget = nil

										local tResults = {}
										for wpIndex, wpName in pairs(wpTable) do
											local tNearWps = SkuNav:GetNearestWpsWithLinksToWp(wpName, 10, tMaxAllowedDistanceToTargetWp)
											local tBestRouteWeightedLength = 100000
											for x = 1, #tNearWps do
												if tMetapaths[tNearWps[x].wpName] then
													local EndMetapathWpObj = SkuNav:GetWaypointData2(tNearWps[x].wpName)
													local tEndTargetWpObj = SkuNav:GetWaypointData2(wpName)
													local tDistToEndTargetWp = SkuNav.Geo:Distance(EndMetapathWpObj.worldX, EndMetapathWpObj.worldY, tEndTargetWpObj.worldX, tEndTargetWpObj.worldY)

													local tDirectionTargetWp = ""
													if SkuOptions.db.profile["SkuNav"].showGlobalDirectionInWaypointLists == true then
														local tDirectionString = SkuNav.Geo:GetDirectionToAsString(tEndTargetWpObj.worldX, tEndTargetWpObj.worldY)
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
													local tNewMenuEntry = SkuOptions:InjectMenuItems(self, { SkuNav:getAnnotatedWaypointLabel(tResults[tV].metapathLength .. ";" .. L["plus"] .. ";" .. tResults[tV].distanceTargetWp .. L[";Meter"] .. tResults[tV].direction .. "#" .. tV, tV) }, SkuGenericMenuItem)
													tNewMenuEntry.OnEnter = function(self, aValue, aName)
														SkuOptions.db.profile["SkuNav"].metapathFollowingTarget = tResults[tV].metarouteIndex
														SkuOptions.db.profile["SkuNav"].metapathFollowingEndTarget = tResults[tV].targetWpName
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
			
				local tNewMenuSubEntry1 = SkuOptions:InjectMenuItems(self, {L["Wegpunkt"]}, SkuGenericMenuItem)
				tNewMenuSubEntry1.dynamic = true
				tNewMenuSubEntry1.isSelect = true
				tNewMenuSubEntry1.sorting = true
				tNewMenuSubEntry1.OnAction = function(self, aValue, aName)
					--dprint("OnAction Wegpunkt auswählen", self.name, aValue, aName)
					if SkuSettings:Sub("SkuQuest").routeRecording == true then
						SkuOptions.Voice:OutputStringBTtts(L["Error"], false, true, 0.3, true)
						SkuOptions.Voice:OutputStringBTtts(L["Recording in progress"], false, true, 0.3, true)
						return
					end

					if SkuSettings:Sub("SkuQuest").metapathFollowing == true or SkuSettings:Sub("SkuQuest").selectedWaypoint ~= "" then
						SkuNav:EndFollowingWpOrRt()
					end

					if SkuNav:GetWaypointData2(SkuOptions.db.profile["SkuNav"].menuFollowTargetWaypoint) then
						SkuNav:SelectWP(SkuOptions.db.profile["SkuNav"].menuFollowTargetWaypoint)
						SkuOptions:CloseMenu()
					else
						SkuOptions.Voice:OutputStringBTtts(L["Error"], false, true, 0.3, true)
						SkuOptions.Voice:OutputStringBTtts(L["Wegpunkt nicht ausgewählt"], false, true, 0.3, true)
					end

				end
				tNewMenuSubEntry1.BuildChildren = function(self)
					do -- build choices
						local tPlayX, tPlayY = UnitPosition("player")

						local tResults = {}
						for wpIndex, wpName in pairs(wpTable) do
							local tWpObj = SkuNav:GetWaypointData2(wpName)
							local tDistanceTargetWp = SkuNav.Geo:Distance(tPlayX, tPlayY, tWpObj.worldX, tWpObj.worldY)

							-- add direction to wp
							local tDirectionTargetWp = ""
							if SkuOptions.db.profile["SkuNav"].showGlobalDirectionInWaypointLists == true then
								local tDirectionString = SkuNav.Geo:GetDirectionToAsString(tWpObj.worldX, tWpObj.worldY)
								if tDirectionString then
									tDirectionTargetWp = ";"..tDirectionString
								end
							end

							tResults[wpName] = {wpName = wpName, distance = tDistanceTargetWp, direction = tDirectionTargetWp,}
						end

						local tSortedList = {}
						for k,v in SkuSpairs(tResults, function(t,a,b) return t[b].distance > t[a].distance end) do
							table.insert(tSortedList, k)
						end
						if #tSortedList == 0 then
							local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Empty;list"]}, SkuGenericMenuItem)
						else
							for tK, tV in ipairs(tSortedList) do
								local tNewMenuGeneralSp = SkuOptions:InjectMenuItems(self, {SkuNav:getAnnotatedWaypointLabel(tResults[tV].distance..L[";Meter"]..tResults[tV].direction.."#"..tV, tV)}, SkuGenericMenuItem)
								tNewMenuGeneralSp.OnEnter = function(self, aValue, aName)
									SkuOptions.db.profile["SkuNav"].menuFollowTargetWaypoint = tV
								end
								--tHasContent = true
							end
						end
					end
				end
			end
		end
	end

	if tHasContent == false then
		local tNewMenuGeneralName = SkuOptions:InjectMenuItems(aParent, {L["Empty"]}, SkuGenericMenuItem)
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
			local _, taName = SkuNav.Geo:GetAreaData(zone)
			if taName then
				if SkuDB.questLookup[Sku.Loc][aQuestId] then
					tWaypoints[#tWaypoints + 1] = SkuDB.questLookup[Sku.Loc][aQuestId][1]..";"..taName..";"..L["Questziel"]..";"..data[1][1]..";"..data[1][2]
				end
			end
		end
	end

	return tWaypoints
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Sku helper: post a clickable WoW quest hyperlink into the chat
-- editbox (analog zu "Add Link to chat" bei Items). Funktioniert für
-- jede Quest-ID, egal ob aus dem Questlog oder der Questdatenbank
-- (Questie). Der User schickt den Link selbst ab.
---------------------------------------------------------------------------------------------------------------------------------------
local function tGetQuestTitleAndLevel(aQuestID)
	-- Prefer the live quest log — gibt den korrekten Level/Titel
	-- für die Quest des Spielers zurück.
	if _G.GetNumQuestLogEntries and _G.GetQuestLogTitle then
		local tNum = _G.GetNumQuestLogEntries() or 0
		for i = 1, tNum do
			local title, level, _, isHeader, _, _, _, qid = _G.GetQuestLogTitle(i)
			if not isHeader and qid == aQuestID then
				return title, level
			end
		end
	end
	-- Fallback 1: Questie-DB falls geladen (für Quests aus der
	-- Questdatenbank, die nicht im aktiven Log sind).
	if _G.QuestieLoader then
		local ok, QuestieDB = pcall(function()
			return _G.QuestieLoader:ImportModule("QuestieDB")
		end)
		if ok and QuestieDB and QuestieDB.GetQuest then
			-- QuestieDB.GetQuest is a DOT function: pass only the questId (a colon /
			-- extra `QuestieDB` first arg would land as the questId and always fail).
			local ok2, q = pcall(QuestieDB.GetQuest, aQuestID)
			if ok2 and q then
				return q.name or q.title, q.questLevel or q.level or -1
			end
		end
	end
	-- Fallback 2: SkuDB.questLookup — Sku's eigene Quest-Daten.
	if SkuDB and SkuDB.questLookup and SkuDB.questLookup[Sku.Loc]
		and SkuDB.questLookup[Sku.Loc][aQuestID] then
		local row = SkuDB.questLookup[Sku.Loc][aQuestID]
		return row[1], (row[2] and tonumber(row[2])) or -1
	end
	return nil, nil
end

local function SkuPostQuestToChat(aQuestID)
	if not aQuestID or aQuestID == 0 then return end

	local title, level = tGetQuestTitleAndLevel(aQuestID)
	if not title or title == "" then
		title = "Quest " .. tostring(aQuestID)
	end
	level = level or -1

	-- Versuche zuerst, einen serverseitig validen Quest-Hyperlink über
	-- GetQuestLink(questLogIndex) zu erzeugen. Nur solche Links werden
	-- vom WoW-Chat-System akzeptiert und beim Empfänger als klickbarer
	-- [Quest-Titel] angezeigt. Manuell konstruierte |Hquest:|h-Links
	-- werden auf Anniversary/TBC vom Server gefiltert — der Empfänger
	-- sieht dann nur den Klartext-Titel ohne Hyperlink.
	local link
	local tFromLog = false
	if _G.GetQuestLink and _G.GetNumQuestLogEntries and _G.GetQuestLogTitle then
		local tNum = _G.GetNumQuestLogEntries() or 0
		for i = 1, tNum do
			local _, _, _, isHeader, _, _, _, qid = _G.GetQuestLogTitle(i)
			if not isHeader and qid == aQuestID then
				local ok, l = pcall(_G.GetQuestLink, i)
				if ok and l and l ~= "" then
					link = l
					tFromLog = true
				end
				break
			end
		end
	end
	-- Fallback für Quests, die nicht im aktiven Log sind (z.B. aus der
	-- Questdatenbank/Questie): wir bauen den Link manuell. Er wird beim
	-- Empfänger ggf. als Klartext angezeigt, der Spieler kann ihn aber
	-- selbst zur Quest-ID nachschlagen.
	if not link then
		link = string.format("|cffffff00|Hquest:%d:%d|h[%s]|h|r",
		                     aQuestID, level, title)
	end

	-- Wir setzen Link + Quest-ID-Suffix in einem Rutsch via SetText.
	-- Items nutzen exakt diesen Weg ("Add Link to chat") und es
	-- funktioniert; Quest-Hyperlinks werden in der Editbox genauso
	-- gerendert. Falls der Server den |Hquest:|h-Link beim Senden
	-- filtert, bleibt die Klartext-ID lesbar.
	local tFullText = link .. " (Quest " .. tostring(aQuestID) .. ")"
	if _G.ChatFrame1EditBox then
		ChatFrame1EditBox:Show()
		ChatFrame1EditBox:SetFocus()
		ChatFrame1EditBox:SetText(tFullText)
		-- Cursor an den Anfang setzen, damit der User direkt einen
		-- Channel-Prefix (z. B. "/p ", "/g ", "/2 ") tippen kann.
		if ChatFrame1EditBox.SetCursorPosition then
			pcall(function() ChatFrame1EditBox:SetCursorPosition(0) end)
		end
	end
	if SkuOptions and SkuOptions.Voice and SkuOptions.Voice.OutputStringBTtts then
		local tMsg = (L["Quest"] or "Quest") .. " " .. title
			.. " " .. (L["in den Chat eingefügt"] or "in Chat eingefügt")
		if not tFromLog then
			-- Hinweis für den Nutzer: Empfänger sieht den Link evtl.
			-- nur als Klartext, da die Quest nicht im Log ist.
			tMsg = tMsg .. ". " .. (L["Hinweis: Quest nicht im Log, Link evtl. nicht klickbar"]
				or "Hinweis: Quest nicht im Log, Link evtl. nicht klickbar")
		end
		pcall(function()
			SkuOptions.Voice:OutputStringBTtts(tMsg, true, true, 0.2, nil, nil, nil, 2)
		end)
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
local function CreateQuestSubmenu(aParent, aQuestID)
	local tHasEntries
	--parent qs
	if aQuestID then
		if SkuDB.questDataTBC[aQuestID] then
			local tPreQuestTable = {}
			if SkuDB.questDataTBC[aQuestID][SkuDB.questKeys["preQuestGroup"]] then -- table: {quest(int)} - all to be completed before next in series
				local preQuestGroup = ""
				for iR, vR in pairs(SkuDB.questDataTBC[aQuestID][SkuDB.questKeys["preQuestGroup"]]) do
					tPreQuestTable[#tPreQuestTable+1] = vR
				end
			end
			if SkuDB.questDataTBC[aQuestID][SkuDB.questKeys["preQuestSingle"]] then -- table: {quest(int)} - one to be completed before next in series
				local preQuestSingle = ""
				for iR, vR in pairs(SkuDB.questDataTBC[aQuestID][SkuDB.questKeys["preQuestSingle"]]) do
					tPreQuestTable[#tPreQuestTable+1] = vR
				end
			end

			if SkuDB.questDataTBC[aQuestID][SkuDB.questKeys["parentQuest"]] then -- table: {quest(int)} - one to be completed before next in series
				local parentQuest = ""
				tPreQuestTable[#tPreQuestTable+1] = SkuDB.questDataTBC[aQuestID][SkuDB.questKeys["parentQuest"]]
			end

			if SkuDB.questDataTBC[aQuestID][SkuDB.questKeys["startedBy"]] and (SkuDB.questDataTBC[aQuestID][SkuDB.questKeys["startedBy"]][1] 
				or SkuDB.questDataTBC[aQuestID][SkuDB.questKeys["startedBy"]][2]
				or SkuDB.questDataTBC[aQuestID][SkuDB.questKeys["startedBy"]][3])
			then
				tHasEntries = true
				local tstartedBy = SkuDB.questDataTBC[aQuestID][SkuDB.questKeys["startedBy"]]
				if tstartedBy then
					local tTargets = {}
					local tTargetType = nil
					
					tTargets, tTargetType = SkuQuest:GetQuestTargetIds(aQuestID, tstartedBy)

					local tNewMenuSubEntry = SkuOptions:InjectMenuItems(aParent, {L["Annahme"]}, SkuGenericMenuItem)
					tNewMenuSubEntry.dynamic = true
					tNewMenuSubEntry.sorting = true
					tNewMenuSubEntry.BuildChildren = function(self)
						tHasEntries = true
						CreateRtWpSubmenu(self, tTargets, tTargetType, aQuestID)
						--CreateRtWpSubmenu(self, SkuDB.questDataTBC[aQuestID][SkuDB.questKeys["startedBy"]][1], "creature", aQuestID)
					end
				end
			end

			local tObjectives = SkuDB.questDataTBC[aQuestID][SkuDB.questKeys["objectives"]]
			if tObjectives then
				tHasEntries = true
				local tTargets = {}
				local tTargetType = nil

				tTargets, tTargetType = SkuQuest:GetQuestTargetIds(aQuestID, tObjectives)

				if	tTargetType then
					local tNewMenuSubEntry = SkuOptions:InjectMenuItems(aParent, {L["Ziel"]}, SkuGenericMenuItem)
					tNewMenuSubEntry.dynamic = true
					--tNewMenuSubEntry.sorting = true
					tNewMenuSubEntry.OnAction = function(self, aValue, aName)
					end
					tNewMenuSubEntry.BuildChildren = function(self)
						tHasEntries = true
						CreateRtWpSubmenu(self, tTargets, tTargetType, aQuestID)
					end
				end
			end

			if SkuDB.questDataTBC[aQuestID][SkuDB.questKeys["finishedBy"]] and (SkuDB.questDataTBC[aQuestID][SkuDB.questKeys["finishedBy"]][1] or SkuDB.questDataTBC[aQuestID][SkuDB.questKeys["finishedBy"]][2] or SkuDB.questDataTBC[aQuestID][SkuDB.questKeys["finishedBy"]][3]) then
				tHasEntries = true
				local tNewMenuSubEntry = SkuOptions:InjectMenuItems(aParent, {L["Abgabe"]}, SkuGenericMenuItem)
				tNewMenuSubEntry.dynamic = true
				tNewMenuSubEntry.sorting = true
				local tFinishedBy = SkuDB.questDataTBC[aQuestID][SkuDB.questKeys["finishedBy"]]
				if tFinishedBy and tFinishedBy then
					local tTargets = {}
					local tTargetType = nil

					tTargets, tTargetType = SkuQuest:GetQuestTargetIds(aQuestID, tFinishedBy)

					tNewMenuSubEntry.BuildChildren = function(self)
						tHasEntries = true
						CreateRtWpSubmenu(self, tTargets, tTargetType, aQuestID)
					end
				end
			end

			-- "An Chat schicken" — direkt nach "Abgabe" platziert.
			-- Fügt einen klickbaren Quest-Hyperlink + Quest-ID in die
			-- Chat-Editbox ein (analog zu "Add Link to chat" bei Items).
			do
				local tNewMenuEntryChat = SkuOptions:InjectMenuItems(aParent, {L["An Chat schicken"] or "An Chat schicken"}, SkuGenericMenuItem)
				tNewMenuEntryChat.dynamic = false
				tNewMenuEntryChat.OnAction = function()
					SkuPostQuestToChat(aQuestID)
					if _G.C_Timer and _G.C_Timer.After then
						_G.C_Timer.After(0.35, function() SkuOptions:CloseMenu() end)
					end
				end
				tHasEntries = true
			end

			-- "Share quest" — teilt die aktuell gewählte Quest mit der Gruppe
			-- (QuestLogPushQuest). Immer sichtbar, nicht mehr an Pre-Quests gekoppelt.
			do
				local tNewMenuEntryShare = SkuOptions:InjectMenuItems(aParent, {L["Share quest"]}, SkuGenericMenuItem)
				tNewMenuEntryShare.dynamic = false
				tNewMenuEntryShare.OnAction = function(self, aValue, aName)
					SkuQuest:OnSkuQuestPush()
				end
				tHasEntries = true
			end

			if #tPreQuestTable > 0 then
				tHasEntries = true
				local tNewMenuSubEntry = SkuOptions:InjectMenuItems(aParent, {L["Pre Quests"]}, SkuGenericMenuItem)
				tNewMenuSubEntry.dynamic = true
				tNewMenuSubEntry.OnAction = function(self, aValue, aName)

				end
				tNewMenuSubEntry.BuildChildren = function(self)
					for i, v in pairs(tPreQuestTable) do
						local tNewMenuSubEntry1 = SkuOptions:InjectMenuItems(self, {SkuDB.questLookup[Sku.Loc][v][1]}, SkuGenericMenuItem)
						tNewMenuSubEntry1.dynamic = true
						tNewMenuSubEntry1.OnAction = function(self, aValue, aName)
							C_Timer.NewTimer(0.1, function()
								SkuOptions:SlashFunc(Sku.MENU_ROOT..","..L["Local"]..","..L["SkuQuest,Questdatenbank,Alle"]..","..self.name)
								SkuOptions.Voice:OutputStringBTtts(self.name, true, true, 0.3, true)
							end)
						end
					end
				end

			end
		end
	end

	if not tHasEntries then
		local tNewMenuSubEntry = SkuOptions:InjectMenuItems(aParent, {L["Empty"]}, SkuGenericMenuItem)
		tNewMenuSubEntry.dynamic = false
	end
	return tHasEntries
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Öffentlicher Wrapper, damit andere Module (z. B. SkuChat) dieselbe
-- Quest-Detail-Menüstruktur (Annahme / Ziel / Abgabe / Pre Quests /
-- Share / An Chat schicken) bauen können wie das Sku-eigene Questlog.
---------------------------------------------------------------------------------------------------------------------------------------
function SkuQuest:CreateQuestSubmenu(aParent, aQuestID)
	return CreateQuestSubmenu(aParent, aQuestID)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuQuest:GetUnsortedAvailableQuestsTable()
	-- [DB rework stage 3] Cross-family reads: this resolves quest startedBy
	-- ids through NpcData.Data and objectDataTBC (chained indexing, e.g.
	-- NpcData.Data[npcId][zoneID]). In the streamed-init window "quests ready,
	-- creatures/objects not yet" that chain crashes (BugSack error on every
	-- load, seen 2026-07-06). Bail out empty instead: QUEST_LOG_UPDATE fires
	-- again soon and the master sequence runs a CheckQuestProgress refresh
	-- after the quest tail, so the lists catch up within seconds.
	if not (Sku:IsDataReady("skudb.quests") and Sku:IsDataReady("skudb.creatures") and Sku:IsDataReady("skudb.objects")) then
		tCurrentQuestLogQuestsTable = {}
		return {}, {}, tCurrentQuestLogQuestsTable
	end
	local tUiMap = SkuNav.Geo:GetAreaIdFromUiMapId(SkuNav.Geo:GetBestMapForUnit("player"))
	local tPlayX, tPlayY = UnitPosition("player")
	local tShowQuestsTable = {}

	tCurrentQuestLogQuestsTable = {}
	local numEntries = GetNumQuestLogEntries()
	if (numEntries >= 0) then
		for questLogID = 1, numEntries do
			local title, level, suggestedGroup, isHeader, isCollapsed, isComplete, frequency, questID, startEvent, displayQuestID, isOnMap, hasLocalPOI, isTask, isStory = GetQuestLogTitle(questLogID)
			tCurrentQuestLogQuestsTable[questID] = true
		end
	end
	for i, v in pairs(SkuDB.questLookup[Sku.Loc]) do
		if SkuDB.questDataTBC[i] then
			local tZoneId
			if SkuDB.questDataTBC[i][SkuDB.questKeys["startedBy"]] and SkuDB.questDataTBC[i][SkuDB.questKeys["startedBy"]][1] then --creatures
				--local tIds = SkuDB.questDataTBC[i][SkuDB.questKeys["startedBy"]][1]
				tZoneId = SkuDB.NpcData.Data[SkuDB.questDataTBC[i][SkuDB.questKeys["startedBy"]][1][1]][SkuDB.NpcData.Keys['zoneID']]
			elseif SkuDB.questDataTBC[i][SkuDB.questKeys["startedBy"]] and SkuDB.questDataTBC[i][SkuDB.questKeys["startedBy"]][2] then --objects
				--local tIds = SkuDB.questDataTBC[i][SkuDB.questKeys["startedBy"]][2][1]
				if SkuDB.objectDataTBC[SkuDB.questDataTBC[i][SkuDB.questKeys["startedBy"]][2][1]][SkuDB.objectKeys["zoneID"]] then
					tZoneId = SkuDB.objectDataTBC[SkuDB.questDataTBC[i][SkuDB.questKeys["startedBy"]][2][1]][SkuDB.objectKeys["zoneID"]]
				end
			elseif SkuDB.questDataTBC[i][SkuDB.questKeys["startedBy"]] and SkuDB.questDataTBC[i][SkuDB.questKeys["startedBy"]][3] then --items
				--local tIds = SkuDB.questDataTBC[i][SkuDB.questKeys["startedBy"]][3]
			end

			if tZoneId == tUiMap then

				local tnextQuestInChain = SkuDB.questDataTBC[i][SkuDB.questKeys["nextQuestInChain"]]
				local tOutFlag = false
				if tnextQuestInChain then
					if tCurrentQuestLogQuestsTable[tnextQuestInChain] then
						tOutFlag = true
					end
					if C_QuestLog.IsQuestFlaggedCompleted(tonumber(tnextQuestInChain)) == true then
						tOutFlag = true
					end
				end
				if (C_QuestLog.IsQuestFlaggedCompleted(i) == false)
					and (SkuDB.questDataTBC[i][SkuDB.questKeys["requiredLevel"]] <= UnitLevel("player"))
					and not tCurrentQuestLogQuestsTable[i]
					and tOutFlag ~= true
				then
					local rRaces = {}
					local tFlagH = nil
					local tFlagA = nil
					local tFlagR = nil
					local tPlayerFactionEn, tPlayerFactionLoc = UnitFactionGroup("player")
					local tPlayerclassName, tPlayerclassFilename, tPlayerclassId = UnitClass("player")
					local tmpraceName, tmpraceFile, tmpraceID = UnitRace("player")
					local tRaceName = C_CreatureInfo.GetRaceInfo(tmpraceID)
					local tCount = 0
					if SkuDB.questDataTBC[i][SkuDB.questKeys["requiredRaces"]] then
						for iR, vR in pairs(SkuDB.raceKeys) do
							if bit.band(vR, SkuDB.questDataTBC[i][SkuDB.questKeys["requiredRaces"]]) > 0 then
								if iR == "ALL_HORDE" then
									tFlagH = true
								end
								if iR == "ALL_ALLIANCE" then
									tFlagA = true
								end
								if iR ~= "ALL_HORDE" and iR ~= "ALL_ALLIANCE" then
									local tCleanRaceName = string.upper(string.gsub(iR, "_", ""))
									if tCleanRaceName == "UNDEAD" then
										tCleanRaceName = "SCOURGE"
									end
									rRaces[tCleanRaceName] = true
									tCount = tCount + 1
								end
							else
								tFlagH = true
								tFlagA = true
							end
						end
					end
					if tRaceName then
						if rRaces[string.upper(tRaceName.clientFileString)] then
							tFlagR = true
						end
					end

					if not tFlagR then
						if tCount == 0 and ((tPlayerFactionEn == "Alliance" and tFlagA) or (tPlayerFactionEn == "Horde" and tFlagH)) then
							tFlagR = true
						end
					end

					if tFlagR then
						local tClasses = {}
						local tFlagClass = nil
						if not SkuDB.questDataTBC[i][SkuDB.questKeys["requiredClasses"]] then
							tFlagClass = true
						end
						for iR, vR in pairs(SkuDB.classKeys) do
							if SkuDB.questDataTBC[i][SkuDB.questKeys["requiredClasses"]] then
								if bit.band(vR, SkuDB.questDataTBC[i][SkuDB.questKeys["requiredClasses"]]) > 0 then
									tClasses[#tClasses+1] = iR
								end
							end
						end
						for i, v in pairs(tClasses) do
							if tPlayerclassFilename == v then
								tFlagClass = true
							end
						end
						if tFlagClass == true then
							local tPreQuestsTable = {}
							if SkuDB.questDataTBC[i][SkuDB.questKeys["preQuestGroup"]] then -- table: {quest(int)} - all to be completed before next in series
								for iR, vR in pairs(SkuDB.questDataTBC[i][SkuDB.questKeys["preQuestGroup"]]) do
									tPreQuestsTable[vR] = vR
								end
							end

							local tPreQuestSingleOk = false
							local tHasPreQuestSingle = false
							if SkuDB.questDataTBC[i][SkuDB.questKeys["preQuestSingle"]] then -- table: {quest(int)} - one to be completed before next in series
								for iR, vR in pairs(SkuDB.questDataTBC[i][SkuDB.questKeys["preQuestSingle"]]) do
									tHasPreQuestSingle = true
									if C_QuestLog.IsQuestFlaggedCompleted(tonumber(vR)) == true then
										tPreQuestSingleOk = true
									end
								end
							end

							local tAllCompletedFlag = true
							for iPQ, vPQ in pairs(tPreQuestsTable) do
								if C_QuestLog.IsQuestFlaggedCompleted(tonumber(vPQ)) == false then
									tAllCompletedFlag = false
								end
							end

							if tAllCompletedFlag == true and (tHasPreQuestSingle == false or (tHasPreQuestSingle == true and  tPreQuestSingleOk == true)) then
								
								local tIsOk = true
								--dprint(i, SkuDB.questDataTBC[i][SkuDB.questKeys["requiredMinRep"]])
								if SkuDB.questDataTBC[i][SkuDB.questKeys["requiredMinRep"]] then
									local tFaction = SkuDB.questDataTBC[i][SkuDB.questKeys["requiredMinRep"]][1]
									if tFaction then
										local tMinRep = SkuDB.questDataTBC[i][SkuDB.questKeys["requiredMinRep"]][2]
										local name, description, standingId, bottomValue, topValue, earnedValue, atWarWith, canToggleAtWar, isHeader, isCollapsed, hasRep, isWatched, isChild, factionID, hasBonusRepGain, canBeLFGBonus = GetFactionInfoByID(tFaction)
										if earnedValue then
											if earnedValue < tMinRep then
												tIsOk = false
											end
										else
											tIsOk = false
										end
									end
								end
								if SkuDB.questDataTBC[i][SkuDB.questKeys["requiredMaxRep"]] then
									local tFaction = SkuDB.questDataTBC[i][SkuDB.questKeys["requiredMaxRep"]][1]
									if tFaction then
										local tMaxRep = SkuDB.questDataTBC[i][SkuDB.questKeys["requiredMaxRep"]][2]
										local name, description, standingId, bottomValue, topValue, earnedValue, atWarWith, canToggleAtWar, isHeader, isCollapsed, hasRep, isWatched, isChild, factionID, hasBonusRepGain, canBeLFGBonus = GetFactionInfoByID(tFaction)
										if earnedValue then
											if earnedValue > tMaxRep then
												tIsOk = false
											end
										else
											tIsOk = false
										end
									end
								end
									
								if SkuDB.questDataTBC[i][SkuDB.questKeys["exclusiveTo"]] then
									for x = 1, #SkuDB.questDataTBC[i][SkuDB.questKeys["exclusiveTo"]] do
										local tExQuestId = SkuDB.questDataTBC[i][SkuDB.questKeys["exclusiveTo"]][x]
										if C_QuestLog.IsQuestFlaggedCompleted(tExQuestId) == true then
											tIsOk = false
										end
										if tCurrentQuestLogQuestsTable[tExQuestId] then
											tIsOk = false
										end
									end
								end

								if tIsOk == true then
									-- Hide only what we are confident about: an event quest whose
									-- event is inactive, or a quest Questie reports as unavailable for
									-- a time/availability reason (inactive daily, or an auto-blacklisted
									-- duplicate/removed/seasonal quest such as Pilgrim's Bounty /
									-- Candy Bucket). Both gates bias to SHOW on any doubt and are
									-- silent no-ops when Questie is not installed.
									local tIsEventOk = not SkuQuest:IsEventQuestInactive(i)
									local tIsAvailableOk = not SkuQuest:IsQuestieUnavailable(i)

									if tIsEventOk and tIsAvailableOk then
										--['requiredSkill'] = 18, -- table: {skill(int), value(int)}
										--['requiredSourceItems'] = 21, -- table: {item(int), ...} Items that are not an objective but still needed for the quest.


										tShowQuestsTable[i] = {textFull = SkuQuest:GetQuestDataStringFromDB(i, tZoneId)}
									end
								end
							end
						end
					end
				end
			end
		end
	end

	local tcount = 0
	local tUnSortedTable = {}
	local tIdTable = {}
	local tPlayerTopAreaId = SkuNav.Geo:GetAreaIdFromUiMapId(tUiMap)
	for i, v in pairs(tShowQuestsTable) do
		local tDistanceToQuestGiver = 0
		if SkuDB.questDataTBC[i] and SkuDB.questDataTBC[i][SkuDB.questKeys["startedBy"]] and SkuDB.questDataTBC[i][SkuDB.questKeys["startedBy"]][1] then
			local tQuestGiverID = SkuDB.questDataTBC[i][SkuDB.questKeys["startedBy"]][1][1]
			if SkuDB.NpcData.Data[tQuestGiverID][SkuDB.NpcData.Keys["spawns"]] then
				if SkuDB.NpcData.Data[tQuestGiverID][SkuDB.NpcData.Keys["spawns"]][tUiMap] then
					local tSpawnX, tSpawnY = SkuDB.NpcData.Data[tQuestGiverID][SkuDB.NpcData.Keys["spawns"]][tUiMap][1][1], SkuDB.NpcData.Data[tQuestGiverID][SkuDB.NpcData.Keys["spawns"]][tUiMap][1][2]
					if tSpawnX ~= -1 and tSpawnY ~= -1 then
						local _, worldPosition = C_Map.GetWorldPosFromMapPos(SkuNav.Geo:GetUiMapIdFromAreaId(tUiMap), CreateVector2D(tonumber(tSpawnX) / 100, tonumber(tSpawnY) / 100))
						local tX, tY = worldPosition:GetXY()
						local tDistance, _  = SkuNav.Geo:Distance(tPlayX, tPlayY, tX, tY)
						-- UnitPosition("player") is nil in instances/raids/BGs, so Distance()
						-- returns nil there; keep listing the quest, sorted to the end.
						tDistance = tDistance or 99999
						tUnSortedTable[SkuDB.questLookup[Sku.Loc][i][1]] = {tDistance, tX, tY, i}
						tIdTable[tDistance..L[";Meter"].."#"..SkuDB.questLookup[Sku.Loc][i][1]] = i
					end
				end
			end
		elseif SkuDB.questDataTBC[i] and SkuDB.questDataTBC[i][SkuDB.questKeys["startedBy"]] and SkuDB.questDataTBC[i][SkuDB.questKeys["startedBy"]][2] then
			local tObjectID = SkuDB.questDataTBC[i][SkuDB.questKeys["startedBy"]][2][1]
			local tObjectData = SkuDB.objectDataTBC[tObjectID]
			local tObjectSpawns = tObjectData[SkuDB.objectKeys["spawns"]]
			if tObjectSpawns then
				if tObjectSpawns[tUiMap] then
					local tSpawnX, tSpawnY = tObjectSpawns[tUiMap][1][1], tObjectSpawns[tUiMap][1][2]
					if tSpawnX ~= -1 and tSpawnY ~= -1 then
						local _, worldPosition = C_Map.GetWorldPosFromMapPos(SkuNav.Geo:GetUiMapIdFromAreaId(tUiMap), CreateVector2D(tonumber(tSpawnX) / 100, tonumber(tSpawnY) / 100))
						local tX, tY = worldPosition:GetXY()
						local tDistance, _  = SkuNav.Geo:Distance(tPlayX, tPlayY, tX, tY)
						-- UnitPosition("player") is nil in instances/raids/BGs, so Distance()
						-- returns nil there; keep listing the quest, sorted to the end.
						tDistance = tDistance or 99999
						tUnSortedTable[SkuDB.questLookup[Sku.Loc][i][1]] = {tDistance, tX, tY, i}
						tIdTable[tDistance..L[";Meter"].."#"..SkuDB.questLookup[Sku.Loc][i][1]] = i
					end
				end
			end
		else
			--tUnSortedTable[SkuDB.questLookup[Sku.Loc][i][1]] = 99999
			tIdTable["99999;"..L["Meter"].."#"..SkuDB.questLookup[Sku.Loc][i][1]] = i
		end

		if not tUnSortedTable[SkuDB.questLookup[Sku.Loc][i][1]] then
			--tUnSortedTable[SkuDB.questLookup[Sku.Loc][i][1]] = 99999
			tIdTable["99999;"..L["Meter"].."#"..SkuDB.questLookup[Sku.Loc][i][1]] = i
		end
	end

	return tUnSortedTable, tIdTable, tCurrentQuestLogQuestsTable
end


---------------------------------------------------------------------------------------------------------------------------------------
local tDifficultyColors = {
	QuestDifficulty_Trivial = L["trivial"],
	QuestDifficulty_Standard = L["easy"],
	QuestDifficulty_Difficult = L["medium"],
	QuestDifficulty_VeryDifficult = L["optimal"],
	QuestDifficulty_Impossible = L["Red"],
}

function SkuQuest:MenuBuilder(aParentEntry)
	local tSpecs = {}

	--Alle
	--Zonen
	--Entfernung Questgeber
	--Level
	--tNewMenuParentEntry.isSelect = true
	tSpecs[#tSpecs+1] = { kind = "list", label = L["Aktuelle Quests"],
		onAction = function(self, aValue, aName)

		end,
		build = function(self)
		if QuestLogFrame:IsVisible() ~= true then
			ToggleQuestLog()
		end
		if (QuestLogFrame:IsVisible()) then
			ExpandQuestHeader(0)
		end

		local numEntries = GetNumQuestLogEntries()
		--numEntries = 0	
		if (numEntries == 0) then
			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Empty"]}, SkuGenericMenuItem)
		else
			local tQuestsByHeader = {}
			local tHeader = ""
			for questLogID = 1, numEntries do
				local title, level, suggestedGroup, isHeader, isCollapsed, isComplete, frequency, questID, startEvent, displayQuestID, isOnMap, hasLocalPOI, isTask, isStory = GetQuestLogTitle(questLogID)
				local tAddTitle = ""
				local tDifficultyTitle = ""
				if SkuSettings:Sub("SkuQuest").showDifficultyColors == true then
					local tDiff = GetQuestDifficultyColor(level)
					if tDiff and tDiff.font and tDifficultyColors[tDiff.font] then
						tDifficultyTitle = " ("..tDifficultyColors[tDiff.font]..")"
					else
						tDifficultyTitle = " ("..L["nodifficulty"]..")"
					end
				end

				if isComplete == 1 then
					tAddTitle = L["(Fertig) "]
				elseif isComplete == -1 then
					tAddTitle = L["(Fehlgeschlagen) "]
				end
				if suggestedGroup then
					tAddTitle = tAddTitle.."("..suggestedGroup..") "
				end
				if frequency == 2 then
					tAddTitle = tAddTitle..L["(Daily) "]
				end
				if isHeader == false then
					tQuestsByHeader[tHeader][tAddTitle..title..tDifficultyTitle] = questLogID
				else
					tQuestsByHeader[title] = {}
					tHeader = title
				end
			end
			--all
			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Alle"]}, SkuGenericMenuItem)
			tNewMenuEntry.sorting = true
			for ih, vh in pairs(tQuestsByHeader) do
				for iq, vq in pairs(vh) do
					local tNewMenuEntry1 = SkuOptions:InjectMenuItems(tNewMenuEntry, {iq}, SkuGenericMenuItem)
					tNewMenuEntry1.questLogId = vq
					tNewMenuEntry1.dynamic = true
					tNewMenuEntry1.OnAction = function(self, aValue, aName)
					end
					tNewMenuEntry1.OnEnter = function(self, aValue, aName)
						SkuOptions.currentMenuPosition.textFull = SkuQuest:GetTTSText(self.questLogId)
					end
					local questLogTitleText, level, questTag, isHeader, isCollapsed, isComplete, frequency, questID = GetQuestLogTitle(vq)
					tNewMenuEntry1.BuildChildren = function(self)
						CreateQuestSubmenu(self, questID)
					end
				end
			end
			--by zone
			for ih, vh in pairs(tQuestsByHeader) do
				local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {ih}, SkuGenericMenuItem)
				tNewMenuEntry.sorting = true
				for iq, vq in pairs(vh) do
					local tNewMenuEntry1 = SkuOptions:InjectMenuItems(tNewMenuEntry, {iq}, SkuGenericMenuItem)
					tNewMenuEntry1.questLogId = vq
					tNewMenuEntry1.dynamic = true
					tNewMenuEntry1.OnAction = function(self, aValue, aName)
					end
					tNewMenuEntry1.OnEnter = function(self, aValue, aName)
						SkuOptions.currentMenuPosition.textFull = SkuQuest:GetTTSText(self.questLogId)
					end
					local questLogTitleText, level, questTag, isHeader, isCollapsed, isComplete, frequency, questID = GetQuestLogTitle(vq)
					tNewMenuEntry1.BuildChildren = function(self)
						CreateQuestSubmenu(self, questID)
					end
				end
			end
		end
		end }

	tSpecs[#tSpecs+1] = { kind = "list", label = L["Questdatenbank"],
		onAction = function(self, aValue, aName)
		end,
		build = function(self)
		local tNewMenuSubEntry =SkuOptions:InjectMenuItems(self, {L["Start in Zone"]}, SkuGenericMenuItem)
		tNewMenuSubEntry.dynamic = true
		tNewMenuSubEntry.sorting = true
		tNewMenuSubEntry.OnAction = function(self, aValue, aName)
		end
		tNewMenuSubEntry.BuildChildren = function(self)
			local tUnSortedTable, tIdTable = SkuQuest:GetUnsortedAvailableQuestsTable()

			local tNewMenuSubEntryDist =SkuOptions:InjectMenuItems(self, {L["By distance"]}, SkuGenericMenuItem)
			tNewMenuSubEntryDist.dynamic = true
			tNewMenuSubEntryDist.sorting = true
			tNewMenuSubEntryDist.OnAction = function(self, aValue, aName)
			end
			tNewMenuSubEntryDist.BuildChildren = function(self)
				local tSortedTable = {}
				for k,v in SkuSpairs(tUnSortedTable, function(t,a,b) return t[b][1] > t[a][1] end) do --nach wert
					tSortedTable[#tSortedTable+1] = v[1]..L[";Meter"].."#"..k
				end
				if #tSortedTable > 0 then
					for iS, vS in ipairs(tSortedTable) do
						local tNewSubMenuEntry2 = SkuOptions:InjectMenuItems(self, {vS}, SkuGenericMenuItem)
						tNewSubMenuEntry2.OnEnter = function(self, aValue, aName)
							SkuOptions.currentMenuPosition.textFull = SkuQuest:GetQuestDataStringFromDB(tIdTable[vS])
						end
						CreateQuestSubmenu(tNewSubMenuEntry2, tIdTable[vS])--iS)
						tcount = tcount + 1
					end
				else
					local tNewSubMenuEntry2 = SkuOptions:InjectMenuItems(self, {L["Empty"]}, SkuGenericMenuItem)
				end
			end

			--[[
			local tNewMenuSubEntryDist =SkuOptions:InjectMenuItems(self, {"Nach Schwierigkeit"}, SkuGenericMenuItem)
			tNewMenuSubEntryDist.dynamic = true
			tNewMenuSubEntryDist.sorting = true
			]]
		end

		local tNewMenuSubEntry =SkuOptions:InjectMenuItems(self, {L["Alle"]}, SkuGenericMenuItem)
		tNewMenuSubEntry.dynamic = true
		tNewMenuSubEntry.sorting = true
		tNewMenuSubEntry.OnAction = function(self, aValue, aName)
			--SkuOptions.db:SetSProfile(aName)
		end
		tNewMenuSubEntry.BuildChildren = function(self)
			local tNameCache = {}
			for i, v in pairs(SkuDB.questLookup[Sku.Loc]) do
				if SkuDB.questDataTBC[i] then
					local tZoneId
					if SkuDB.questDataTBC[i][SkuDB.questKeys["startedBy"]] and SkuDB.questDataTBC[i][SkuDB.questKeys["startedBy"]][1] then --creatures
						--local tIds = SkuDB.questDataTBC[i][SkuDB.questKeys["startedBy"]][1]
						tZoneId = SkuDB.NpcData.Data[SkuDB.questDataTBC[i][SkuDB.questKeys["startedBy"]][1][1]][SkuDB.NpcData.Keys['zoneID']]
					elseif SkuDB.questDataTBC[i][SkuDB.questKeys["startedBy"]] and SkuDB.questDataTBC[i][SkuDB.questKeys["startedBy"]][2] then --objects
						--local tIds = SkuDB.questDataTBC[i][SkuDB.questKeys["startedBy"]][2]
						if SkuDB.objectDataTBC[SkuDB.questDataTBC[i][SkuDB.questKeys["startedBy"]][2][1]][SkuDB.objectKeys["zoneID"]] then
							tZoneId = SkuDB.objectDataTBC[SkuDB.questDataTBC[i][SkuDB.questKeys["startedBy"]][2][1]][SkuDB.objectKeys["zoneID"]]
						end
					elseif SkuDB.questDataTBC[i][SkuDB.questKeys["startedBy"]] and SkuDB.questDataTBC[i][SkuDB.questKeys["startedBy"]][3] then --items
						--local tIds = SkuDB.questDataTBC[i][SkuDB.questKeys["startedBy"]][3]
					end

					local tUniqueName = v[1]
					if not tNameCache[v[1]] then
						tNameCache[v[1]] = 0
					else
						tNameCache[v[1]] = tNameCache[v[1]] + 1
						tUniqueName = tUniqueName.." "..tNameCache[v[1]]
					end

					local tNewSubMenuEntry2 = SkuOptions:InjectMenuItems(self, {tUniqueName}, SkuGenericMenuItem)
					tNewSubMenuEntry2.OnEnter = function(self, aValue, aName)
						SkuOptions.currentMenuPosition.textFull = SkuQuest:GetQuestDataStringFromDB(i, tZoneId)
					end
					if not CreateQuestSubmenu(tNewSubMenuEntry2, i) then
						--self.dynamic = false
					end
				end
			end
		end
		end }

	-- Quests der Gruppenmitglieder aus Questies Party-Comms. Der Eintrag erscheint NUR
	-- wenn das Setting an ist, Questie fertig geladen ist und wir in einer Gruppe sind —
	-- sonst fehlt er komplett. Mitglieder ohne Questie senden keine Daten und bekommen
	-- einen erklärenden Leereintrag statt einer Questliste.
	-- [v43.1] Der Eintrag steht bewusst ZULETZT (Position 3), nicht zwischen "Aktuelle Quests"
	-- und "Questdatenbank": er kommt und geht mit der Gruppe, und würde er in der Mitte
	-- einhängen, verschöbe er die Questdatenbank je nach Gruppenstatus. So
	-- bleiben die ersten beiden Einträge immer an derselben Stelle.
	if SkuSettings:Sub("SkuQuest").showGroupQuests == true and SkuQuest:QuestieReady() and IsInGroup() then
		tSpecs[#tSpecs+1] = { kind = "list", label = L["Gruppenmitglieder"],
			onAction = function(self, aValue, aName)
			end,
			build = function(self)
			local tMembers = {}
			local tPrefix, tMax = "party", GetNumSubgroupMembers()
			if IsInRaid() then
				tPrefix, tMax = "raid", GetNumGroupMembers()
			end
			for i = 1, tMax do
				local tUnit = tPrefix..i
				if UnitExists(tUnit) and not UnitIsUnit(tUnit, "player") then
					tMembers[#tMembers+1] = UnitName(tUnit)
				end
			end
			if #tMembers == 0 then
				SkuOptions:InjectMenuItems(self, {L["Empty"]}, SkuGenericMenuItem)
				return
			end
			for _, tMemberName in ipairs(tMembers) do
				local tMemberEntry = SkuOptions:InjectMenuItems(self, {tMemberName}, SkuGenericMenuItem)
				tMemberEntry.dynamic = true
				tMemberEntry.BuildChildren = function(self)
					local tQuests = SkuQuest:GetGroupMemberQuests()[tMemberName]
					local tQuestCount = 0
					if tQuests then for _ in pairs(tQuests) do tQuestCount = tQuestCount + 1 end end
					dprint("groupQuests member BuildChildren: member=", tMemberName, "matched=", tQuests ~= nil, "questCount=", tQuestCount)
					if not tQuests or not next(tQuests) then
						dprint("groupQuests member BuildChildren: no data for", tMemberName, "-> fallback entry")
						SkuOptions:InjectMenuItems(self, {L["Keine Questie-Daten empfangen"]}, SkuGenericMenuItem)
						return
					end
					-- gleiche Struktur wie das eigene Questlog: "Alle" plus eine Liste je
					-- Zone (Zone = Startzone der Quest aus der Datenbank), aktuelle Zone
					-- zuerst, danach alphabetisch
					local tByZone = {}
					for tQuestId, tObjectives in pairs(tQuests) do
						-- Per-quest pcall: a single quest that our DB can't resolve (or a
						-- lookup that errors) must NOT abort the whole member's list and
						-- leave it silent. Log the failure and skip that one quest.
						local tOk, tErr = pcall(function()
							local tZoneId = SkuQuest:GetQuestStartZoneId(tQuestId)
							local tZoneEntry = tZoneId and SkuDB.InternalAreaTable[tZoneId]
							local tZoneName = (tZoneEntry and tZoneEntry.AreaName_lang and tZoneEntry.AreaName_lang[Sku.Loc]) or L["Unbekannte Zone"]
							local tLookup = SkuDB.questLookup[Sku.Loc][tQuestId]
							local tText, tIsComplete = SkuQuest:GetGroupQuestProgressText(tQuestId, tObjectives)
							local tLabel = tLookup and tLookup[1] or ("Quest "..tQuestId)
							if tIsComplete then
								tLabel = L["(Fertig) "]..tLabel
							end
							dprint("groupQuests   quest id=", tQuestId, "zone=", tZoneName, "label=", tLabel, "textLen=", tText and #tText or 0)
							tByZone[tZoneName] = tByZone[tZoneName] or {}
							tByZone[tZoneName][#tByZone[tZoneName]+1] = { questId = tQuestId, label = tLabel, text = tText, zoneId = tZoneId }
						end)
						if not tOk then
							dprint("groupQuests   quest id=", tQuestId, "SKIPPED, error:", tostring(tErr))
						end
					end
					local tCurrentZoneId = SkuNav.Geo:GetAreaIdFromUiMapId(SkuNav.Geo:GetBestMapForUnit("player"))
					local tCurZoneEntry = tCurrentZoneId and SkuDB.InternalAreaTable[tCurrentZoneId]
					local tCurrentZoneName = tCurZoneEntry and tCurZoneEntry.AreaName_lang and tCurZoneEntry.AreaName_lang[Sku.Loc]
					local tZoneNames = {}
					for tZoneName in pairs(tByZone) do
						if tZoneName ~= tCurrentZoneName then
							tZoneNames[#tZoneNames+1] = tZoneName
						end
					end
					table.sort(tZoneNames)
					if tCurrentZoneName and tByZone[tCurrentZoneName] then
						table.insert(tZoneNames, 1, tCurrentZoneName)
					end
					local function tAddQuestEntry(aContainer, aQuest, aNameCache)
						local tLabel = aQuest.label
						if aNameCache[tLabel] then
							aNameCache[tLabel] = aNameCache[tLabel] + 1
							tLabel = tLabel.." "..aNameCache[tLabel]
						else
							aNameCache[tLabel] = 0
						end
						local tEntry = SkuOptions:InjectMenuItems(aContainer, {tLabel}, SkuGenericMenuItem)
						tEntry.dynamic = true
						tEntry.OnEnter = function(self, aValue, aName)
							-- GetQuestDataStringFromDB returns a SECTIONS TABLE, and the menu
							-- render path (AddExtraTooltipData) accepts a string OR a section
							-- table. Build that same shape: the live per-objective progress as
							-- the first section, then the static DB sections. Skip the DB lookup
							-- for quest ids our database doesn't know (it indexes questLookup
							-- unguarded). Concatenating the table directly was the crash
							-- ("attempt to concatenate a table value") that hit every quest
							-- with objective progress.
							local tSections = {}
							if aQuest.text ~= "" then
								tSections[#tSections+1] = aQuest.text
							end
							if SkuDB.questLookup[Sku.Loc][aQuest.questId] then
								local tDbSections = SkuQuest:GetQuestDataStringFromDB(aQuest.questId, aQuest.zoneId)
								if type(tDbSections) == "table" then
									for _, tSection in ipairs(tDbSections) do
										tSections[#tSections+1] = tSection
									end
								elseif type(tDbSections) == "string" and tDbSections ~= "" then
									tSections[#tSections+1] = tDbSections
								end
							end
							SkuOptions.currentMenuPosition.textFull = tSections
						end
						tEntry.BuildChildren = function(self)
							CreateQuestSubmenu(self, aQuest.questId)
						end
					end
					--all
					local tAllEntry = SkuOptions:InjectMenuItems(self, {L["Alle"]}, SkuGenericMenuItem)
					tAllEntry.sorting = true
					local tAllNameCache = {}
					local tAllCount = 0
					for _, tZoneName in ipairs(tZoneNames) do
						for _, tQuest in ipairs(tByZone[tZoneName]) do
							tAddQuestEntry(tAllEntry, tQuest, tAllNameCache)
							tAllCount = tAllCount + 1
						end
					end
					--by zone
					for _, tZoneName in ipairs(tZoneNames) do
						local tZoneEntry = SkuOptions:InjectMenuItems(self, {tZoneName}, SkuGenericMenuItem)
						tZoneEntry.sorting = true
						local tZoneNameCache = {}
						for _, tQuest in ipairs(tByZone[tZoneName]) do
							tAddQuestEntry(tZoneEntry, tQuest, tZoneNameCache)
						end
					end
					-- Final tally: how many children this member's list actually got. If
					-- this logs zones>0 / all>0 but you still hear silence, the problem is
					-- in the menu render/vocalize layer, not the data build.
					dprint("groupQuests member BuildChildren DONE: member=", tMemberName, "zones=", #tZoneNames, "allEntries=", tAllCount, "childrenOnSelf=", self.children and #self.children or 0)
				end
			end
			end }
	end


	-- W7: quest settings moved to Einstellungen -> Sonstiges -> Quest (the quest menu
	-- is now a Local window contributor, so its options no longer belong here).

	SkuMenu:Build(aParentEntry, tSpecs)
end


----------------------------------------------------------------------------------------------------------------------------------------
-- event utilities
----------------------------------------------------------------------------------------------------------------------------------------
-- Questie owns the world-event engine: on login it reads the in-game calendar and
-- computes which events are active. Sku no longer rebuilds Questie's event-quest list
-- nor re-runs its loader (that duplicated Questie's "event active" prints and depended
-- on a broken colon call). Instead the availability filter reads Questie's result via
-- SkuQuest:IsEventQuestInactive, with SkuQuest:IsEventActiveByDate as a weaker
-- fallback. This function is kept only as the deferred-setup warm-up / compat entry
-- point and is a silent no-op when Questie is absent.
function SkuQuest:LoadEventHandler()
	SkuQuest.Event = SkuQuest:QuestieModule("QuestieEvent")
end

-- Weaker date-range fallback used by SkuQuest:IsEventActiveByDate. Mirrors Questie's
-- own _WithinDates so events that span the turn of the year (e.g. Winter Veil) are
-- handled correctly. Returns true when today is inside [start, end].
function SkuQuest:WithinDates(startDay, startMonth, endDay, endMonth)
	if (not startDay) and (not startMonth) and (not endDay) and (not endMonth) then
		return true
	end
	local date = (C_DateAndTime.GetTodaysDate or C_DateAndTime.GetCurrentCalendarTime)()
	local day = date.day or date.monthDay
	local month = date.month
	if (startMonth <= endMonth) -- event within a single calendar year
			and ((month < startMonth) or (month > endMonth)) -- too early or too late in the year
		or ((month < startMonth) and (month > endMonth)) -- event spans the year change
		or (month == startMonth and day < startDay) -- too early in the start month
		or (month == endMonth and day > endDay) then -- too late in the end month
		return false
	else
		return true
	end
end
