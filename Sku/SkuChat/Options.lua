local MODULE_NAME = "SkuChat"

local L = Sku.L

local play = 2	--this is just a local constant for output type (play, true, false)
local skuTts = 3	--audio via Sku's own TTS (see SkuChat/Core.lua for the full state list)

SkuChat.CombatConfigUnitTypes = {
	--[[
	{
		text = COMBATLOG_FILTER_STRING_ME,
		type = COMBATLOG_FILTER_ME,
	},
	]]
	{
		text = COMBATLOG_FILTER_STRING_ME,
		type = COMBATLOG_FILTER_MINE,
	},
	{
		text = COMBATLOG_FILTER_STRING_MY_PET,
		type = COMBATLOG_FILTER_MY_PET,
	},
	{
		text = COMBATLOG_FILTER_STRING_FRIENDLY_UNITS,
		type = COMBATLOG_FILTER_FRIENDLY_UNITS,
	},
	{
		text = COMBATLOG_FILTER_STRING_HOSTILE_PLAYERS,
		type = COMBATLOG_FILTER_HOSTILE_PLAYERS,
	},
	{
		text = COMBATLOG_FILTER_STRING_HOSTILE_UNITS,
		type = COMBATLOG_FILTER_HOSTILE_UNITS,
	},
	{
		text = COMBATLOG_FILTER_STRING_NEUTRAL_UNITS,
		type = COMBATLOG_FILTER_NEUTRAL_UNITS,
	},
	{
		text = COMBATLOG_FILTER_STRING_UNKNOWN_UNITS,
		type = COMBATLOG_FILTER_UNKNOWN_UNITS,
	},
	--[[
	{
		text = "Everything",
		type = COMBATLOG_FILTER_EVERYTHING,
	},
	]]
}

SkuChat.CombatConfigMessageTypes = {
	{
		text = MELEE.." "..DAMAGE,
		type = {"SWING_DAMAGE"},
	},
	{
		text = MELEE.." "..MISSES,
		type = {"SWING_MISSED"},
	},
	{
		text = RANGED.." "..DAMAGE,
		type = {"RANGE_DAMAGE"},
	},
	{
		text = RANGED.." "..MISSES,
		type = {"RANGE_MISSED"},
	},
	{
		text = AURAS.." "..BENEFICIAL,
		type = {"SPELL_AURA_APPLIED", "SPELL_AURA_APPLIED_DOSE", "SPELL_AURA_REMOVED", "SPELL_AURA_REMOVED_DOSE", "SPELL_AURA_REFRESH"},
	},
	{
		text = AURAS.." "..HOSTILE,
		type = {"SPELL_AURA_APPLIED", "SPELL_AURA_APPLIED_DOSE", "SPELL_AURA_REMOVED", "SPELL_AURA_REMOVED_DOSE"},
	},
	{
		text = AURAS.." "..DISPELS,
		type = {"SPELL_STOLEN", "SPELL_DISPEL_FAILED", "SPELL_DISPEL"},
	},
	{
		text = AURAS.." "..ENCHANTS,
		type = {"ENCHANT_APPLIED", "ENCHANT_REMOVED"},
	},
	{
		text = PERIODIC.." "..DAMAGE,
		type = {"SPELL_PERIODIC_DAMAGE"},
	},
	{
		text = PERIODIC.." "..MISSES,
		type = {"SPELL_PERIODIC_MISSED"},
	},
	{
		text = PERIODIC.." "..HEALS,
		type = {"SPELL_PERIODIC_HEAL"},
	},
	{
		text = PERIODIC.." "..OTHER,
		type = {"SPELL_PERIODIC_DRAIN","SPELL_PERIODIC_LEECH"},
	},
	{
		text = SPELLS.." "..DAMAGE,
		type = {"SPELL_DAMAGE"},
	},
	{
		text = SPELLS.." "..MISSES,
		type = {"SPELL_MISSED"},
	},
	{
		text = SPELLS.." "..HEALS,
		type = {"SPELL_HEAL"},
	},
	{
		text = SPELLS.." "..POWER_GAINS,
		type = {"SPELL_ENERGIZE"},
	},
	--[[
	[5] = {
		text = SPELLS.." "..DRAINS,
		type = {"SPELL_DRAIN", "SPELL_LEECH"},
	},
	[5] = {
		text = SPELLS.." "..INTERRUPTS,
		type = {"SPELL_INTERRUPT"},
	},
	]]
	{
		text = SPELLS.." "..SPECIAL,
		type = {"SPELL_INSTAKILL", "SPELL_DURABILITY_DAMAGE", "SPELL_DURABILITY_DAMAGE_ALL"},
	},
	{
		text = SPELLS.." "..EXTRA_ATTACKS,
		type = {"SPELL_EXTRA_ATTACKS"},
	},
	{
		text = SPELLS.." "..SUMMONS,
		type = {"SPELL_SUMMON"},
	},
	{
		text = SPELLS.." "..RESURRECT,
		type = {"SPELL_RESURRECT"},
	},
	{
		text = SPELL_CASTING.." "..START,
		type = {"SPELL_CAST_START"},
	},
	{
		text = SPELL_CASTING.." "..SUCCESS,
		type = {"SPELL_CAST_SUCCESS"},
	},
	{
		text = SPELL_CASTING.." "..FAILURES,
		type = {"SPELL_CAST_FAILED"},
	},
	{
		text = OTHER.." "..KILLS,
		type = {"PARTY_KILL"},
	},
	{
		text = OTHER.." "..DEATHS,
		type = {"UNIT_DIED", "UNIT_DESTROYED", "UNIT_DISSIPATES"},
	},
	{
		text = OTHER.." "..L["Damage Split"],
		type = {"DAMAGE_SPLIT"},
	},
	{
		text = OTHER.." "..ENVIRONMENTAL_DAMAGE,
		type = {"ENVIRONMENTAL_DAMAGE"},
	},
}


SkuChat.WowTtsVoices = {
	[1] = L["def Microsoft Hedda Desktop - German"],
}

SkuChat.timeStampFormats = {
	[1] = L["No timestamp"],
	[2] = TIMESTAMP_FORMAT_HHMM,
	[3] = TIMESTAMP_FORMAT_HHMMSS,
	[4] = TIMESTAMP_FORMAT_HHMM_AMPM,
	[5] = TIMESTAMP_FORMAT_HHMMSS_AMPM,
	[6] = TIMESTAMP_FORMAT_HHMM_24HR,
	[7] = TIMESTAMP_FORMAT_HHMMSS_24HR,
}

SkuChat.DeleteTabTimes = {
	[1] = -1,
	[2] = 2,
	[3] = 5,
	[4] = 10,
	[5] = 20,
	[6] = 40,
	[7] = 90,
	[8] = 180,
}

local exampleTime = {
	year = 2010,
	month = 12,
	day = 15,
	hour = 21,
	min = 43,
	sec = 38,
}

SkuChat.options = {
	name = MODULE_NAME,
	type = "group",
	args = {
		chatSettings = {
			name = L["Chat settings"],
			order = 1,
			type = "group",
			args = {

				--short channel names
				shortenChannelNames = {
					name = L["shorten Channel Names"],
					order = 1,
					type = "toggle",
					desc = "",
				},

				--line numbers
				addLineNumbers = {
					name = L["add line numbers"],
					order = 2,
					type = "toggle",
					desc = "",
				},

				--timestamp (pre, post, off)
				timeStamp = {
					order = 3,
					name = L["add timestamps"],
					desc = "",
					type = "select",
					values = {
						[1] = SkuChat.timeStampFormats[1],
						[2] = L["Format"].." 1: "..BetterDate(SkuChat.timeStampFormats[2], time(exampleTime)),
						[3] = L["Format"].." 2: "..BetterDate(SkuChat.timeStampFormats[2], time(exampleTime)),
						[4] = L["Format"].." 3: "..BetterDate(SkuChat.timeStampFormats[3], time(exampleTime)),
						[5] = L["Format"].." 4: "..BetterDate(SkuChat.timeStampFormats[4], time(exampleTime)),
						[6] = L["Format"].." 5: "..BetterDate(SkuChat.timeStampFormats[5], time(exampleTime)),
						[7] = L["Format"].." 6: "..BetterDate(SkuChat.timeStampFormats[6], time(exampleTime)),
					},
				},

				timeStampAtLineEnd = {
					name = L["add timestamp to line end"],
					order = 4,
					type = "toggle",
					desc = "",
				},

				--go to 1st line
				firstLineOnTabSwitch = {
					name = L["go to first line on tab switch"],
					order = 5,
					type = "toggle",
					desc = "",
				},

				--delete history on login
				deleteHistoryOnLogin = {
					name = L["delete chat history on login"],
					order = 6,
					type = "toggle",
					desc = "",
				},

				--whispers in new tab
				openWhispersInNewTab = {
					name = L["show Whispers In New Tab"],
					order = 7,
					type = "toggle",
					desc = "",
					OnAction = function(self, info, val)
						C_Timer.After(0.1, function()
							if SkuSettings:Sub("SkuChat").chatSettings.openWhispersInNewTab == false then
								if SkuSettings:Sub("SkuChat").tabs[1] then
									local tTab = SkuSettings:Sub("SkuChat").tabs[1]
									tTab.messageTypes["PLAYER_MESSAGES"][6] = 2
									tTab.messageTypes["PLAYER_MESSAGES"][7] = 2
									tTab.messageTypes["CREATURE_MESSAGES"][4] = 2
									tTab.messageTypes["CREATURE_MESSAGES"][6] = 2		
								end

								for z = 1, #SkuSettings:Sub("SkuChat").tabs do
									if SkuSettings:Sub("SkuChat").tabs[z].privateMessages then
										SkuChat:DeleteTab(z)
									else
										SkuChat:InitTab(z)
									end
								end
							end
						end)
					end,
				},
				deleteWhisperTabsAfter = {
					order = 3,
					name = L["delete whisper tabs without activity after"],
					desc = "",
					type = "select",
					values = {
						[1] = L["Never"] ,
						[2] = SkuChat.DeleteTabTimes[2]..L[" Minuten"],
						[3] = SkuChat.DeleteTabTimes[3]..L[" Minuten"],
						[4] = SkuChat.DeleteTabTimes[4]..L[" Minuten"],
						[5] = SkuChat.DeleteTabTimes[5]..L[" Minuten"],
						[6] = SkuChat.DeleteTabTimes[6]..L[" Minuten"],
						[7] = SkuChat.DeleteTabTimes[7]..L[" Minuten"],
						[8] = SkuChat.DeleteTabTimes[8]..L[" Minuten"],
					},
				},
				audioOnNewMessage = {
					name = L["Audio notification on chat message"],
					order = 8,
					type = "toggle",
					desc = L["Enables / disables audio on new line"],
					OnAction = function()
						if SkuSettings:Sub("SkuChat").tabs then
							for i, v in pairs(SkuSettings:Sub("SkuChat").tabs) do
								v.audioOnNewMessage = SkuSettings:Sub("SkuChat").chatSettings.audioOnNewMessage
							end
						end
					end,
				},
				audioOnMessageEnd = {
					name = L["Audio notification on the end of chat messages"],
					desc = L["Controls whether a sound is played at the end of a chat message."],
					order = 9,
					type = "toggle",
					set = function(info,val)
						C_TTSSettings.SetSetting(Enum.TtsBoolSetting.PlaySoundSeparatingChatLineBreaks, val)
					end,
					get = function(info) 
						return C_TTSSettings.GetSetting(Enum.TtsBoolSetting.PlaySoundSeparatingChatLineBreaks)
					end,
					OnAction = function() 
						C_TTSSettings.SetSetting(Enum.TtsBoolSetting.PlaySoundSeparatingChatLineBreaks, SkuSettings:Sub("SkuChat").chatSettings.audioOnMessageEnd)
					end,
				},

			},
		},
		WowTtsVoice = {
			order = 3,
			name = L["TTS voice"],
			desc = "",
			type = "select",
			values = SkuChat.WowTtsVoices,
		},
		WowTtsSpeed = {
			order = 4,
			name = L["TTS speed"],
			desc = "",
			type = "range",
		},
		WowTtsVolume = {
			order = 5,
			name = L["TTS volume"],
			desc = "",
			type = "range",
		},
		WowTtsTags = {
			order = 5,
			name = L["TTS pause tags"],
			desc = "",
			type = "toggle",
		},
		joinSkuChannel = {
			order = 7,
			name = L["Sku Chat Channel beitreten"],
			desc = "",
			type = "toggle",
			OnAction = function()
				C_Timer.After(0.1, function()
					SkuChat:JoinOrLeaveSkuChatChannel()
				end)
			end,
		},
		neverResetQueues = {
			order = 8,
			name = L["Never reset audio queues"],
			desc = "",
			type = "toggle",
		},
		allChatViaBlizzardTts = {
			order = 9,
			name = L["All voice output via blizzard tts"],
			desc = "",
			type = "toggle",
		},
		doNotReadoutEmojis = {
			order = 20,
			name = L["Do not read out emojis"] ,
			desc = "",
			type = "toggle",
		},

	},
}

---------------------------------------------------------------------------------------------------------------------------------------
SkuChat.defaults = {
	chatSettings = {
		shortenChannelNames = false,
		openWhispersInNewTab = true,
		deleteWhisperTabsAfter = 3,
		addLineNumbers = true,
		timeStamp = 6,
		timeStampAtLineEnd = true,
		firstLineOnTabSwitch = true,
		deleteHistoryOnLogin = false,
		audioOnNewMessage = false,
		audioOnMessageEnd = false,
	},
	WowTtsVoice = 1,
	WowTtsSpeed = 3,
	WowTtsVolume = 50,
	WowTtsTags = true,
	joinSkuChannel = true,
	neverResetQueues = false,
	allChatViaBlizzardTts = false,
	doNotReadoutEmojis = false,
}

-- Settings schema for SkuChat (Sku 42 rework, W1 Phase C / W2 M-C1). All keys are
-- profile scope (the options menu only ever read/wrote SkuSettings:Sub("SkuChat",
-- ...) with no scope override). Declared here as the single source of truth
-- (scope/default/type) for the schema-managed menu generation in
-- SkuOptions:IterateOptionsArgs. audioOnMessageEnd is registered for
-- completeness but its node KEEPS its own get/set (they go through C_TTSSettings,
-- not the db), so it stays non-managed.
SkuSettings:Register("SkuChat", {
	["chatSettings.shortenChannelNames"]  = { scope = "profile", default = false, type = "boolean" },
	["chatSettings.addLineNumbers"]       = { scope = "profile", default = true,  type = "boolean" },
	["chatSettings.timeStamp"]            = { scope = "profile", default = 6,      type = "number"  },
	["chatSettings.timeStampAtLineEnd"]   = { scope = "profile", default = true,  type = "boolean" },
	["chatSettings.firstLineOnTabSwitch"] = { scope = "profile", default = true,  type = "boolean" },
	["chatSettings.deleteHistoryOnLogin"] = { scope = "profile", default = false, type = "boolean" },
	["chatSettings.openWhispersInNewTab"] = { scope = "profile", default = true,  type = "boolean" },
	["chatSettings.deleteWhisperTabsAfter"] = { scope = "profile", default = 3,   type = "number"  },
	["chatSettings.audioOnNewMessage"]    = { scope = "profile", default = false, type = "boolean" },
	["chatSettings.audioOnMessageEnd"]    = { scope = "profile", default = false, type = "boolean" },
	["WowTtsVoice"]                       = { scope = "profile", default = 1,      type = "number"  },
	["WowTtsSpeed"]                       = { scope = "profile", default = 3,      type = "number"  },
	["WowTtsVolume"]                      = { scope = "profile", default = 50,     type = "number"  },
	["WowTtsTags"]                        = { scope = "profile", default = true,  type = "boolean" },
	["joinSkuChannel"]                    = { scope = "profile", default = true,  type = "boolean" },
	["neverResetQueues"]                  = { scope = "profile", default = false, type = "boolean" },
	["allChatViaBlizzardTts"]             = { scope = "profile", default = false, type = "boolean" },
	["doNotReadoutEmojis"]                = { scope = "profile", default = false, type = "boolean" },
})

--------------------------------------------------------------------------------------------------------------------------------------
function CleanStringHelper(aString)
	--todo: remove multiple spaces, linebreaks, links, restrict length and other cleanup stuff










	if aString == " " then
		aString = ""
	end

	return aString
end

--------------------------------------------------------------------------------------------------------------------------------------
-- Build the output-mode chooser onto a message-type / channel node.
--
-- The stored value has four legacy-compatible states:
--   false     = Muted
--   true      = Text
--   play (2)  = Audio via Blizzard TTS (optionally with a per-entry voice)
--   skuTts (3)= Audio via Sku's own TTS
-- The Blizzard-TTS voice is a separate 1-based index into SkuChat.WowTtsVoices
-- (nil => use the global voice). It is persisted next to the value via the
-- aReadVoice/aWriteVoice closures so the read sites (AddMessage) stay simple.
--
-- Menu shape (FLAT):  <Node> -> Muted | Text | Sku TTS | Blizzard TTS -> <voice>*
-- The four modes are flat siblings; only "Blizzard TTS" descends (into the voice
-- list). Muted/Text/Sku TTS are self-contained leaves (own OnAction, no isSelect).
-- After any change we rebuild the enclosing list (Refresh) so the node's state
-- label + the spoken announce reflect the new value.
local function BuildOutputModeNode(aTypeNode, aTabIndex, aBaseName, aReadVal, aWriteVal, aReadVoice, aWriteVoice)
	aTypeNode.tabIndex = aTabIndex

	-- state suffix on the node label
	local tActive = aReadVal()
	local tSuffix
	if tActive == true then
		tSuffix = L["Text"]
	elseif tActive == play then
		local tVi = aReadVoice()
		local tVName = tVi and SkuChat.WowTtsVoices[tVi]
		tSuffix = L["Blizzard TTS"]..(tVName and (": "..tVName) or "")
	elseif tActive == skuTts then
		tSuffix = L["Sku TTS"]
	else
		tSuffix = L["Inactive"]
	end
	aTypeNode.name = aBaseName.." ("..tSuffix..")"

	local function Refresh()
		SkuChat:InitTab(aTabIndex)
		aTypeNode:OnUpdate(aTypeNode)
	end

	aTypeNode.dynamic = true
	aTypeNode.GetCurrentValue = function(self)
		local v = aReadVal()
		if v == true then return L["Text"] end
		if v == play then return L["Blizzard TTS"] end
		if v == skuTts then return L["Sku TTS"] end
		return L["Inactive"]
	end
	aTypeNode.BuildChildren = function(self)
		local tMuted = SkuOptions:InjectMenuItems(self, {L["Inactive"]}, SkuGenericMenuItem)
		tMuted.OnAction = function() aWriteVal(false) Refresh() end

		local tText = SkuOptions:InjectMenuItems(self, {L["Text"]}, SkuGenericMenuItem)
		tText.OnAction = function() aWriteVal(true) Refresh() end

		local tSku = SkuOptions:InjectMenuItems(self, {L["Sku TTS"]}, SkuGenericMenuItem)
		tSku.OnAction = function() aWriteVal(skuTts) aWriteVoice(nil) Refresh() end

		local tBliz = SkuOptions:InjectMenuItems(self, {L["Blizzard TTS"]}, SkuGenericMenuItem)
		tBliz.dynamic = true
		tBliz.sorting = true
		tBliz.GetCurrentValue = function(self)
			local tVi = aReadVoice()
			return tVi and SkuChat.WowTtsVoices[tVi] or nil
		end
		tBliz.BuildChildren = function(self)
			for tIdx, tVoiceName in pairs(SkuChat.WowTtsVoices) do
				local tVoiceEntry = SkuOptions:InjectMenuItems(self, {tVoiceName}, SkuGenericMenuItem)
				tVoiceEntry.OnAction = function() aWriteVal(play) aWriteVoice(tIdx) Refresh() end
			end
		end
	end
end

--------------------------------------------------------------------------------------------------------------------------------------
function SkuChat:MenuBuilder(aParentEntry)
	BN_WHISPER = L["Battle Net whisper"]

	local tSpecs = {}

	tSpecs[#tSpecs+1] = { kind = "list", label = L["Tabs"], sorting = true,
		build = function(self)
		for x = 1, #SkuSettings:Sub("SkuChat").tabs do
			local tTabEntry = SkuOptions:InjectMenuItems(self, {SkuSettings:Sub("SkuChat").tabs[x].name}, SkuGenericMenuItem)
			if SkuSettings:Sub("SkuChat").tabs[x].name == L["Combat Log"] or SkuSettings:Sub("SkuChat").tabs[x].name == L["Audio Log"] then
				tTabEntry.dynamic = false
				



			else
				tTabEntry.dynamic = true
				tTabEntry.sorting = true
				tTabEntry.tabIndex = x
				tTabEntry.BuildChildren = function(self)
					local tNewMenuSubEntry = SkuOptions:InjectMenuItems(self, {L["Channels"]}, SkuGenericMenuItem)
					tNewMenuSubEntry.dynamic = true
					tNewMenuSubEntry.sorting = true
					tNewMenuSubEntry.BuildChildren = function(self)
						local tTabIdx = x

						-- Assemble the channel list from BOTH sources, deduped by name:
						--  * EnumerateServerChannels() = the zone/server channels
						--    (General/Trade/... or localized Allgemein/Handel/...).
						--    GetChannelList() no longer returns these on current
						--    clients, which is why they went missing from the menu.
						--  * GetChannelList() = the custom / user-joined channels.
						local tOrder, tSeen = {}, {}
						local function tAdd(aName, aNumber)
							if aName and aName ~= "" and not tSeen[aName] then
								tSeen[aName] = true
								tOrder[#tOrder + 1] = {name = aName, number = aNumber}
							end
						end
						if EnumerateServerChannels then
							for _, tName in ipairs({EnumerateServerChannels()}) do
								tAdd(tName, GetChannelName(tName))   -- number is 0 if not currently joined
							end
						end
						local tChannelList = {GetChannelList()}
						for q = 1, C_ChatInfo.GetNumActiveChannels() * 3, 3 do
							tAdd(tChannelList[q + 1], tChannelList[q])
						end

						for _, tChan in ipairs(tOrder) do
							local tChanName = tChan.name
							-- ensure a persisted settings entry exists for this channel
							local tFoundC
							for y = 1, #SkuSettings:Sub("SkuChat").tabs[tTabIdx].channels do
								if SkuSettings:Sub("SkuChat").tabs[tTabIdx].channels[y].name == tChanName then
									tFoundC = true
								end
							end
							if not tFoundC then
								SkuSettings:Sub("SkuChat").tabs[tTabIdx].channels[#SkuSettings:Sub("SkuChat").tabs[tTabIdx].channels + 1] = {name = tChanName, status = false}
							end

							local function FindChannel()
								for y = 1, #SkuSettings:Sub("SkuChat").tabs[tTabIdx].channels do
									if SkuSettings:Sub("SkuChat").tabs[tTabIdx].channels[y].name == tChanName then
										return SkuSettings:Sub("SkuChat").tabs[tTabIdx].channels[y]
									end
								end
							end
							local tBaseName = tChanName
							if tChan.number and tChan.number > 0 then
								tBaseName = tChan.number.."#"..tChanName
							end
							local tTypeEntry = SkuOptions:InjectMenuItems(self, {tBaseName}, SkuGenericMenuItem)
							tTypeEntry.shortName = tChanName
							BuildOutputModeNode(tTypeEntry, tTabIdx, tBaseName,
								function() local c = FindChannel() return c and c.status end,
								function(val) local c = FindChannel() if c then c.status = val end end,
								function() local c = FindChannel() return c and c.voice end,
								function(idx) local c = FindChannel() if c then c.voice = idx end end)
						end
					end			

					local tNewMenuSubEntry = SkuOptions:InjectMenuItems(self, {L["Nachrichtentypen"]}, SkuGenericMenuItem)
					tNewMenuSubEntry.dynamic = true
					tNewMenuSubEntry.sorting = true
					tNewMenuSubEntry.BuildChildren = function(self)
						for i, v in pairs(SkuChat.ChatFrameMessageTypes) do
							if i ~= "SKU" then
								local tCatEntry = SkuOptions:InjectMenuItems(self, {_G[i]}, SkuGenericMenuItem)
								tCatEntry.dynamic = true
								tCatEntry.sorting = true
								tCatEntry.catType = i
								tCatEntry.tabIndex = x
								tCatEntry.BuildChildren = function(self)
									for w = 1, #v do
										local tBaseName = _G[v[w].type]
										if v[w].text then
											tBaseName = v[w].text
										end

										-- capture loop-locals so each closure stays bound to this entry
										local tCat, tW, tTabIdx = i, w, x
										local tTypeEntry = SkuOptions:InjectMenuItems(self, {tBaseName}, SkuGenericMenuItem)
										BuildOutputModeNode(tTypeEntry, tTabIdx, tBaseName,
											function() return SkuSettings:Sub("SkuChat").tabs[tTabIdx].messageTypes[tCat][tW] end,
											function(val) SkuSettings:Sub("SkuChat").tabs[tTabIdx].messageTypes[tCat][tW] = val end,
											function()
												local tv = SkuSettings:Sub("SkuChat").tabs[tTabIdx].messageTypeVoice
												return tv and tv[tCat] and tv[tCat][tW]
											end,
											function(idx)
												local tTab = SkuSettings:Sub("SkuChat").tabs[tTabIdx]
												tTab.messageTypeVoice = tTab.messageTypeVoice or {}
												tTab.messageTypeVoice[tCat] = tTab.messageTypeVoice[tCat] or {}
												tTab.messageTypeVoice[tCat][tW] = idx
											end)
									end
								end
							end
						end
					end

					local tNewTabEntry = SkuOptions:InjectMenuItems(self, {L["Rename"]}, SkuGenericMenuItem)
					tNewTabEntry.isSelect = true
					tNewTabEntry.OnAction = function(self, aValue, aName)
						--print("OnAction Rename", "aValue", aValue, "aName", aName, self.name, self.parent.name, self.parent.tabIndex)
						PlaySound(88)
						SkuOptions.Voice:OutputStringBTtts(L["Enter name and press ENTER key"], false, true, 0.2, nil, nil, nil, 2)
						SkuOptions:EditBoxShow(" ", function(self)
							PlaySound(89)
							local tText = CleanStringHelper(SkuOptionsEditBoxEditBox:GetText())
							if tText ~= "" then
								SkuSettings:Sub("SkuChat").tabs[SkuOptions.currentMenuPosition.tabIndex].name = tText
								SkuChat:InitTab(SkuOptions.currentMenuPosition.tabIndex)
								SkuOptions.currentMenuPosition.parent:OnUpdate(SkuOptions.currentMenuPosition.parent)
								SkuOptions.Voice:OutputStringBTtts(L["Umbenannt"], false, true, 0.2, nil, nil, nil, 2)
							end
						end)					
					end
					local tNewTabEntry = SkuOptions:InjectMenuItems(self, {L["Delete"]}, SkuGenericMenuItem)
					tNewTabEntry.isSelect = true
					tNewTabEntry.OnAction = function(self, aValue, aName)
						--print("OnAction Delete", "aValue", aValue, "aName", aName, self.name, self.parent.name)
						SkuChat:DeleteTab(self.parent.tabIndex)
						self.parent:OnUpdate(self.parent)
						SkuOptions.Voice:OutputStringBTtts(L["Deleted"], false, true, 0.2, nil, nil, nil, 2)
					end
			
					local tNewTabEntry = SkuOptions:InjectMenuItems(self, {L["set all message types and channels to inactive"]}, SkuGenericMenuItem)
					tNewTabEntry.isSelect = true
					tNewTabEntry.tabIndex = x
					tNewTabEntry.OnAction = function(self, aValue, aName)
						for i, v in pairs(SkuSettings:Sub("SkuChat").tabs[self.tabIndex].messageTypes) do
							for u = 1, #v do
								v[u] = false
							end
						end
						for i, v in pairs(SkuSettings:Sub("SkuChat").tabs[self.tabIndex].channels) do
							v.status = false
						end

						SkuChat:InitTab(self.tabIndex)
						self.parent:OnUpdate(self.parent)
					end

					local tNewTabEntry = SkuOptions:InjectMenuItems(self, {L["set all message types and channels to text"]}, SkuGenericMenuItem)
					tNewTabEntry.isSelect = true
					tNewTabEntry.tabIndex = x
					tNewTabEntry.OnAction = function(self, aValue, aName)
						for i, v in pairs(SkuSettings:Sub("SkuChat").tabs[self.tabIndex].messageTypes) do
							for u = 1, #v do
								v[u] = true
							end
						end
						for i, v in pairs(SkuSettings:Sub("SkuChat").tabs[self.tabIndex].channels) do
							v.status = true
						end

						SkuChat:InitTab(self.tabIndex)
						self.parent:OnUpdate(self.parent)
					end

					
					local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Audio notification on chat message"]}, SkuGenericMenuItem)
					tNewMenuEntry.dynamic = true
					tNewMenuEntry.isSelect = true
					tNewMenuEntry.sorting = true
					tNewMenuEntry.OnAction = function(self, aValue, aName)
						for i, v in pairs(SkuCore.outputSoundFiles) do
							if "aura;sound#"..aName == v then
								SkuSettings:Sub("SkuChat").tabs[x].audioOnNewMessage = i
							end
						end
					end
					tNewMenuEntry.BuildChildren = function(self)
						for i, v in pairs(SkuCore.outputSoundFiles) do
							tNewMenuEntry = SkuOptions:InjectMenuItems(self, {v}, SkuGenericMenuItem)
						end
					end
					tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
						for i, v in pairs(SkuCore.outputSoundFiles) do
							if SkuSettings:Sub("SkuChat").tabs[x].audioOnNewMessage == i then
								return v
							end
						end
					end
					--[[
					local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Audio notification on chat message"]}, SkuGenericMenuItem)
					tNewMenuEntry.dynamic = true
					tNewMenuEntry.isSelect = true
					tNewMenuEntry.OnAction = function(self, aValue, aName)
						if aName == L["On"] then
							SkuSettings:Sub("SkuChat").tabs[x].audioOnNewMessage = true
						elseif aName == L["Off"] then
							SkuSettings:Sub("SkuChat").tabs[x].audioOnNewMessage = false
						end
					end
					tNewMenuEntry.BuildChildren = function(self)
						tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["On"]}, SkuGenericMenuItem)
						tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Off"]}, SkuGenericMenuItem)
					end
					tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
						local tValue = L["On"]
						if SkuSettings:Sub("SkuChat").tabs[x].audioOnNewMessage == true then
							tValue = L["On"]
						else
							tValue = L["Off"]
						end
						return tValue
					end
					]]
				end
			end
		end

		local tNewTabEntry = SkuOptions:InjectMenuItems(self, {L["New Tab"]}, SkuGenericMenuItem)
		tNewTabEntry.isSelect = true
		tNewTabEntry.OnAction = function(self, aValue, aName)
			--print("OnAction New Tab", "aValue", aValue, "aName", aName, self.name, self.parent.name)
			PlaySound(88)
			SkuOptions.Voice:OutputStringBTtts(L["Enter name and press ENTER key"], false, true, 0.2, nil, nil, nil, 2)
			SkuOptions:EditBoxShow(" ", function(self)
				PlaySound(89)
				local tText = CleanStringHelper(SkuOptionsEditBoxEditBox:GetText())
				if tText ~= "" then
					local tNewIndex = SkuChat:NewTab(tText)
					SkuChat:InitTab(tNewIndex)
					SkuOptions.currentMenuPosition.parent:OnUpdate(SkuOptions.currentMenuPosition.parent)
					SkuOptions.Voice:OutputStringBTtts(L["Erstellt"], false, true, 0.2, nil, nil, nil, 2)
				end
			end)		
		end
	end }


	tSpecs[#tSpecs+1] = { kind = "list", label = L["Filters"], sorting = true, isSelect = true,
		onAction = function(self, aValue, aName)
		if aName == L["Add new entry"] then
			SkuOptions:EditBoxShow("", function() 
				local tText = SkuOptionsEditBoxEditBox:GetText()
				if tText and tText ~= "" then
					SkuSettings:Sub("SkuChat").chatSettings.filter.terms[string.lower(tText)] = true
					C_Timer.After(0.001, function()
						SkuOptions.currentMenuPosition:OnUpdate(SkuOptions.currentMenuPosition)
					end)
				end
			end,
			false,
			function() 
				SkuOptions.currentMenuPosition:OnUpdate(SkuOptions.currentMenuPosition)
			end)
			C_Timer.After(0.01, function()
				SkuOptions.Voice:OutputStringBTtts(L["Enter filter term and press enter"], {overwrite = true, wait = true, doNotOverwrite = true, engine = 2, })
			end)
		else
			if self.deleteName then
				self.deleteName = string.lower(self.deleteName)
				if SkuSettings:Sub("SkuChat").chatSettings.filter.terms[self.deleteName] then
					SkuSettings:Sub("SkuChat").chatSettings.filter.terms[self.deleteName] = nil
				end
			end
			C_Timer.After(0.001, function()
				SkuOptions.currentMenuPosition:OnUpdate(SkuOptions.currentMenuPosition)
			end)
		end
	end,
		build = function(self)
		local tEntry = SkuOptions:InjectMenuItems(self, {L["Add new entry"]}, SkuGenericMenuItem)
		tEntry.OnEnter = function(self, aValue, aName)
			self.selectTarget.deleteName = nil
		end			

		for i, v in pairs(SkuSettings:Sub("SkuChat").chatSettings.filter.terms) do
			local tEntry = SkuOptions:InjectMenuItems(self, {i}, SkuGenericMenuItem)
			tEntry.dynamic = true
			tEntry.OnEnter = function(self, aValue, aName)
				self.selectTarget.deleteName = i
			end			
			tEntry.BuildChildren = function(self)
				SkuOptions:InjectMenuItems(self, {L["Delete"]}, SkuGenericMenuItem)
			end
		end
	end }

	-- combat log
	tSpecs[#tSpecs+1] = { kind = "list", label = L["Combat Log"],
		build = function(self)
		local tEntry = SkuOptions:InjectMenuItems(self, {L["Enabled"]}, SkuGenericMenuItem)
		tEntry.dynamic = true
		tEntry.isSelect = true
		tEntry.GetCurrentValue = function(self, aValue, aName)
			if SkuSettings:Sub("SkuChat").CombatLog.enabled == true then
				return L["Yes"]
			else
				return L["No"]
			end
		end
		tEntry.OnAction = function(self, aValue, aName)
			if aName == L["No"] then
				SkuSettings:Sub("SkuChat").CombatLog.enabled = false
			elseif aName == L["Yes"] then
				SkuSettings:Sub("SkuChat").CombatLog.enabled = true
			end
			SkuChat:InitCombatLogTab()	
		end
		tEntry.BuildChildren = function(self)
			SkuOptions:InjectMenuItems(self, {L["No"]}, SkuGenericMenuItem)
			SkuOptions:InjectMenuItems(self, {L["Yes"]}, SkuGenericMenuItem)
		end		

		local tFiltersEntry = SkuOptions:InjectMenuItems(self, {L["Filters"]}, SkuGenericMenuItem)
		tFiltersEntry.dynamic = true
		tFiltersEntry.BuildChildren = function(self)
			for i, v in pairs(SkuSettings:Sub("SkuChat", nil, "global").CombatLogFilters) do
				local tName = v.name .. (v.custom == true and " ("..L["custom"]..")" or "")
				if i == SkuSettings:Sub("SkuChat").CombatLog.currentFilter then
					tName = tName.." ("..L["current filter"]..")"
				end

				local tFilterEntry = SkuOptions:InjectMenuItems(self, {tName}, SkuGenericMenuItem)
				tFilterEntry.dynamic = true
				tFilterEntry.BuildChildren = function(self)
					local tNewFilterEntry = SkuOptions:InjectMenuItems(self, {L["Select"]}, SkuGenericMenuItem)
					tNewFilterEntry.isSelect = true
					tNewFilterEntry.OnAction = function(self, aValue, aName)
						SkuSettings:Sub("SkuChat").CombatLog.currentFilter = i
						Blizzard_CombatLog_CurrentSettings = SkuSettings:Sub("SkuChat", nil, "global").CombatLogFilters[SkuSettings:Sub("SkuChat").CombatLog.currentFilter]
						Blizzard_CombatLog_ApplyFilters(Blizzard_CombatLog_CurrentSettings)

						C_Timer.After(0.001, function()
							SkuOptions.currentMenuPosition:OnUpdate(SkuOptions.currentMenuPosition)
						end)
					end

					local tEventsEntry = SkuOptions:InjectMenuItems(self, {L["Events"]}, SkuGenericMenuItem)
					tEventsEntry.dynamic = true
					tEventsEntry.BuildChildren = function(self)
						for iMainMtype, vMainMtype in pairs(SkuChat.CombatConfigMessageTypes) do
							local tEnabled = true
							for iEvent, vEvent in pairs(vMainMtype.type) do
								if v.filters[1].eventList[vEvent] ~= true then
									tEnabled = false
								end
							end
							local tMenuname = vMainMtype.text .. (tEnabled == true and " (enabled)" or "")
							local tEventEntry = SkuOptions:InjectMenuItems(self, {tMenuname}, SkuGenericMenuItem)
							tEventEntry.dynamic = true
							tEventEntry.isSelect = true
							tEventEntry.GetCurrentValue = function(self, aValue, aName)
								if tEnabled == true then
									return L["Yes"]
								else
									return L["No"]
								end
							end
							tEventEntry.OnAction = function(self, aValue, aName)
								for iEvent, vEvent in pairs(vMainMtype.type) do
									if aName == L["No"] then
										v.filters[1].eventList[vEvent] = false
										v.filters[2].eventList[vEvent] = false
									elseif aName == L["Yes"] then
										v.filters[1].eventList[vEvent] = true
										v.filters[2].eventList[vEvent] = true
									end
								end
								Blizzard_CombatLog_CurrentSettings = SkuSettings:Sub("SkuChat", nil, "global").CombatLogFilters[SkuSettings:Sub("SkuChat").CombatLog.currentFilter]
								Blizzard_CombatLog_ApplyFilters(Blizzard_CombatLog_CurrentSettings)
							
								C_Timer.After(0.001, function()
									SkuOptions.currentMenuPosition:OnUpdate(SkuOptions.currentMenuPosition)
								end)								
							end
							tEventEntry.BuildChildren = function(self)
								SkuOptions:InjectMenuItems(self, {L["No"]}, SkuGenericMenuItem)
								SkuOptions:InjectMenuItems(self, {L["Yes"]}, SkuGenericMenuItem)
							end	
					
						end
					end

					local tEventsEntry = SkuOptions:InjectMenuItems(self, {L["Source"]}, SkuGenericMenuItem)
					tEventsEntry.dynamic = true
					tEventsEntry.BuildChildren = function(self)
						for iMainMtype, vMainMtype in pairs(SkuChat.CombatConfigUnitTypes) do
							local tEnabled = true
							if v.filters[1].sourceFlags[vMainMtype.type] ~= true then
								tEnabled = false
							end

							local tMenuname = vMainMtype.text .. (tEnabled == true and " (enabled)" or "")
							local tEventEntry = SkuOptions:InjectMenuItems(self, {tMenuname}, SkuGenericMenuItem)
							tEventEntry.dynamic = true
							tEventEntry.isSelect = true
							tEventEntry.GetCurrentValue = function(self, aValue, aName)
								if tEnabled == true then
									return L["Yes"]
								else
									return L["No"]
								end
							end
							tEventEntry.OnAction = function(self, aValue, aName)
								if aName == L["No"] then
									v.filters[1].sourceFlags[vMainMtype.type] = false
								elseif aName == L["Yes"] then
									v.filters[1].sourceFlags[vMainMtype.type] = true
								end
								Blizzard_CombatLog_CurrentSettings = SkuSettings:Sub("SkuChat", nil, "global").CombatLogFilters[SkuSettings:Sub("SkuChat").CombatLog.currentFilter]
								Blizzard_CombatLog_ApplyFilters(Blizzard_CombatLog_CurrentSettings)
							
								C_Timer.After(0.001, function()
									SkuOptions.currentMenuPosition:OnUpdate(SkuOptions.currentMenuPosition)
								end)								
							end
							tEventEntry.BuildChildren = function(self)
								SkuOptions:InjectMenuItems(self, {L["No"]}, SkuGenericMenuItem)
								SkuOptions:InjectMenuItems(self, {L["Yes"]}, SkuGenericMenuItem)
							end	
					
						end
					end

					local tEventsEntry = SkuOptions:InjectMenuItems(self, {L["Destination"]}, SkuGenericMenuItem)
					tEventsEntry.dynamic = true
					tEventsEntry.BuildChildren = function(self)
						for iMainMtype, vMainMtype in pairs(SkuChat.CombatConfigUnitTypes) do
							local tEnabled = true
							if v.filters[2].destFlags[vMainMtype.type] ~= true then
								tEnabled = false
							end

							local tMenuname = vMainMtype.text .. (tEnabled == true and " (enabled)" or "")
							local tEventEntry = SkuOptions:InjectMenuItems(self, {tMenuname}, SkuGenericMenuItem)
							tEventEntry.dynamic = true
							tEventEntry.isSelect = true
							tEventEntry.GetCurrentValue = function(self, aValue, aName)
								if tEnabled == true then
									return L["Yes"]
								else
									return L["No"]
								end
							end
							tEventEntry.OnAction = function(self, aValue, aName)
								if aName == L["No"] then
									v.filters[2].destFlags[vMainMtype.type] = false
								elseif aName == L["Yes"] then
									v.filters[2].destFlags[vMainMtype.type] = true
								end
								Blizzard_CombatLog_CurrentSettings = SkuSettings:Sub("SkuChat", nil, "global").CombatLogFilters[SkuSettings:Sub("SkuChat").CombatLog.currentFilter]
								Blizzard_CombatLog_ApplyFilters(Blizzard_CombatLog_CurrentSettings)
							
								C_Timer.After(0.001, function()
									SkuOptions.currentMenuPosition:OnUpdate(SkuOptions.currentMenuPosition)
								end)								
							end
							tEventEntry.BuildChildren = function(self)
								SkuOptions:InjectMenuItems(self, {L["No"]}, SkuGenericMenuItem)
								SkuOptions:InjectMenuItems(self, {L["Yes"]}, SkuGenericMenuItem)
							end	
					
						end
					end

					if i > 3 then
						local tNewFilterEntry = SkuOptions:InjectMenuItems(self, {L["Delete this filter"]}, SkuGenericMenuItem)
						tNewFilterEntry.isSelect = true
						tNewFilterEntry.OnAction = function(self, aValue, aName)
							SkuSettings:Sub("SkuChat", nil, "global").CombatLogFilters[i] = nil

							if SkuSettings:Sub("SkuChat").CombatLog.currentFilter == i then
								SkuSettings:Sub("SkuChat").CombatLog.currentFilter = 1
							end
							
							Blizzard_CombatLog_CurrentSettings = SkuSettings:Sub("SkuChat", nil, "global").CombatLogFilters[SkuSettings:Sub("SkuChat").CombatLog.currentFilter]
							Blizzard_CombatLog_ApplyFilters(Blizzard_CombatLog_CurrentSettings)

							C_Timer.After(0.001, function()
								SkuOptions.currentMenuPosition.parent:OnUpdate(SkuOptions.currentMenuPosition)
							end)
						end
					end

				end
			end

			local tNewFilterEntry = SkuOptions:InjectMenuItems(self, {L["Add new filter"]}, SkuGenericMenuItem)
			tNewFilterEntry.isSelect = true
			tNewFilterEntry.OnAction = function(self, aValue, aName)
				SkuOptions:EditBoxShow(
					"",
					function(self)
						local tFilterName = SkuOptionsEditBoxEditBox:GetText()
						if tFilterName and tFilterName ~= "" then
							table.insert(SkuSettings:Sub("SkuChat", nil, "global").CombatLogFilters, {
								custom = true,
								name = tFilterName,
								hasQuickButton = true,
								quickButtonName = tFilterName,
								quickButtonDisplay = {
									solo = true,
									party = true,
									raid = true,
								},
								tooltip = tFilterName,
								settings = CopyTable(COMBATLOG_DEFAULT_SETTINGS),
								colors = CopyTable(COMBATLOG_DEFAULT_COLORS),
								filters = {
									[1] = {
										eventList = Blizzard_CombatLog_GenerateFullEventList(),
										sourceFlags = {
											--[COMBATLOG_FILTER_ME] = true,
											[COMBATLOG_FILTER_MINE] = true,
											[COMBATLOG_FILTER_MY_PET] = true,
											[COMBATLOG_FILTER_FRIENDLY_UNITS] = true,
											[COMBATLOG_FILTER_HOSTILE_PLAYERS] = true,
											[COMBATLOG_FILTER_HOSTILE_UNITS] = true,
											[COMBATLOG_FILTER_NEUTRAL_UNITS] = true,
											[COMBATLOG_FILTER_UNKNOWN_UNITS] = true,
											--[COMBATLOG_FILTER_EVERYTHING] = false,
										},
									},
									[2] = {
										eventList = Blizzard_CombatLog_GenerateFullEventList(),
										destFlags = {
											--[COMBATLOG_FILTER_ME] = true,
											[COMBATLOG_FILTER_MINE] = true,
											[COMBATLOG_FILTER_MY_PET] = true,
											[COMBATLOG_FILTER_FRIENDLY_UNITS] = true,
											[COMBATLOG_FILTER_HOSTILE_PLAYERS] = true,
											[COMBATLOG_FILTER_HOSTILE_UNITS] = true,
											[COMBATLOG_FILTER_NEUTRAL_UNITS] = true,
											[COMBATLOG_FILTER_UNKNOWN_UNITS] = true,
											--[COMBATLOG_FILTER_EVERYTHING] = false,
										},
									},				
								},
							})
			
							Blizzard_CombatLog_CurrentSettings = SkuSettings:Sub("SkuChat", nil, "global").CombatLogFilters[SkuSettings:Sub("SkuChat").CombatLog.currentFilter]
							Blizzard_CombatLog_ApplyFilters(Blizzard_CombatLog_CurrentSettings)
						
							C_Timer.After(0.001, function()
								SkuOptions.currentMenuPosition:OnUpdate(SkuOptions.currentMenuPosition)
							end)			
						end
					end,
					nil
				)
				PlaySound(89)
				C_Timer.After(0.1, function()
					SkuOptions.Voice:OutputStringBTtts(L["Enter name and press ENTER key"], true, true, 1, true)
				end)

			end			
		end
	end }

	--audio log
	tSpecs[#tSpecs+1] = { kind = "list", label = L["Audio Log"],
		build = function(self)
		local tEntry = SkuOptions:InjectMenuItems(self, {L["Enabled"]}, SkuGenericMenuItem)
		tEntry.dynamic = true
		tEntry.isSelect = true
		tEntry.GetCurrentValue = function(self, aValue, aName)
			if SkuSettings:Sub("SkuChat").AudioLog.enabled == true then
				return L["Yes"]
			else
				return L["No"]
			end
		end
		tEntry.OnAction = function(self, aValue, aName)
			if aName == L["No"] then
				SkuSettings:Sub("SkuChat").AudioLog.enabled = false
			elseif aName == L["Yes"] then
				SkuSettings:Sub("SkuChat").AudioLog.enabled = true
			end
			SkuChat:InitAudioLogTab()
		end
		tEntry.BuildChildren = function(self)
			SkuOptions:InjectMenuItems(self, {L["No"]}, SkuGenericMenuItem)
			SkuOptions:InjectMenuItems(self, {L["Yes"]}, SkuGenericMenuItem)
		end	
	end }


	-- W7: the chat "Optionen" entry is now the chat settings directly (chatSettings
	-- rendered with its original keyPrefix so saved values are preserved). The other
	-- SkuChat options (TTS voice/speed/volume, join channel, ...) moved to
	-- Einstellungen -> Sprachausgabe (see SkuCore:MenuBuilder).
	tSpecs[#tSpecs+1] = { kind = "list", label = L["Options"], sorting = true,
		build = function(self)
			SkuOptions:IterateOptionsArgs(SkuChat.options.args.chatSettings.args, self, SkuSettings:Sub("SkuChat"), "SkuChat", "chatSettings.")
		end }

	SkuMenu:Build(aParentEntry, tSpecs)
end