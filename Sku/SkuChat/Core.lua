local MODULE_NAME = "SkuChat"
local _G = _G
local L = Sku.L

SkuChat = LibStub("AceAddon-3.0"):NewAddon("SkuChat", "AceConsole-3.0", "AceEvent-3.0")

local function tClearLinkReadoutIfNoLinks(self)
	local tLineData = SkuSettings:Sub("SkuChat").tabs[SkuChat.currentTab].history[SkuSettings:Sub("SkuChat").tabs[SkuChat.currentTab].historyCurrentLine]
	if (not tLineData.itemLinks or #tLineData.itemLinks == 0)
		and (not tLineData.questLinks or #tLineData.questLinks == 0)
		and self.menuOpen == false then
		tSkuCurrentLineDatalinktTextFirstLine, tSkuCurrentLineDatalinktTextFull, tSkuCurrentLineDatalinktItemId = "", "", ""
	end
end


local play = 2	--this is just a local constant for output type (play, true, false)
-- Output-type constant for "audio via Sku's own TTS" (the pre-recorded audio-file
-- engine), as opposed to `play` (=2) which is "audio via Blizzard TTS". Both are
-- truthy so every "is this type active?" check (~= false) keeps treating them as
-- active exactly like before; only AddMessage's speak branch distinguishes them.
-- Legacy saved values stay valid: false=muted, true=text, 2=Blizzard TTS.
local skuTts = 3
local zoneChannels = {
	general = 1,
	trade = 2,
	localdefense = 22,
	worlddefense = 23,
	guildrecruitment = 25,
	lookingforgroup = 26,
}

SkuChat.defaultHistoryMax = 100
SkuChat.maxTabs = 20
SkuChat.ChatFrameMessageTypes = {
	PLAYER_MESSAGES = {
		[1] = {
			type = "SAY",
			default = true,
		},
		[2] = {
			type = "EMOTE",
			default = true,
		},
		[3] = {
			type = "YELL",
			default = true,
		},
		[4] = {
			text = GUILD_CHAT,
			type = "GUILD",
			default = play,
		},
		[5] = {
			text = OFFICER_CHAT,
			type = "OFFICER",
			default = play,
		},
		[6] = {
			type = "WHISPER",
			default = play,
		},
		[7] = {
			type = "BN_WHISPER",
			default = play,
		},
		[8] = {
			type = "PARTY",
			default = play,
		},
		[9] = {
			type = "PARTY_LEADER",
			default = play,
		},
		[10] = {
			type = "RAID",
			default = play,
		},
		[11] = {
			type = "RAID_LEADER",
			default = play,
		},
		[12] = {
			type = "RAID_WARNING",
			default = play,
		},
		[13] = {
			type = "INSTANCE_CHAT",
			default = play,
		},
		[14] = {
			type = "INSTANCE_CHAT_LEADER",
			default = play,
		},
	},

	CREATURE_MESSAGES = {
		[1] = {
			text = SAY;
			type = "MONSTER_SAY",
			default = play,
		},
		[2] = {
			text = EMOTE;
			type = "MONSTER_EMOTE",
			default = play,
		},
		[3] = {
			text = YELL;
			type = "MONSTER_YELL",
			default = play,
		},
		[4] = {
			text = WHISPER;
			type = "MONSTER_WHISPER",
			default = play,
		},
		[5] = {
			type = "MONSTER_BOSS_EMOTE",
			default = play,
		},
		[6] = {
			type = "MONSTER_BOSS_WHISPER",
			default = play,
		}
	},

	OTHER = {
		[1] = {
			text = SKILLUPS,
			type = "SKILL",
			default = true,
			},
		[2] = {
			text = ITEM_LOOT,
			type = "LOOT",
			default = true,
			},
		[3] = {
			text = MONEY_LOOT,
			type = "MONEY",
			default = true,
			},
		[4] = {
			type = "TRADESKILLS",
			default = true,
			},
		[5] = {
			type = "OPENING",
			default = true,
			},
		[6] = {
			type = "PET_INFO",
			default = true,
			},
	},

	PVP = {
		[1] = {
			text = BG_SYSTEM_HORDE,
			type = "BG_HORDE",
			default = false,
		},
		[2] = {
			text = BG_SYSTEM_ALLIANCE,
			type = "BG_ALLIANCE",
			default = false,
		},
		[3] = {
			text = BG_SYSTEM_NEUTRAL,
			type = "BG_NEUTRAL",
			default = false,
		},
	},

	SYSTEM = {
		[1] = {
			text = SYSTEM_MESSAGES,
			type = "SYSTEM",
			default = true,
		},
		[2] = {
			type = "ERRORS",
			default = true,
		},
		[3] = {
			type = "IGNORED",
			default = true,
		},
		[4] = {
			type = "CHANNEL",
			default = true,
		},
		[5] = {
			type = "TARGETICONS",
			default = true,
		},
		[6] = {
			type = "BN_INLINE_TOAST_ALERT",
			default = true,
		},
		[7] = {
			text = L["Addons"],
			type = "ADDON",
			default = play,
		},		
	},
	
	COMBAT = {
		[1] = {
			type = "COMBAT_XP_GAIN",
			default = true,
		},
		[2] = {
			type = "COMBAT_HONOR_GAIN",
			default = true,
		},
		[3] = {
			type = "COMBAT_FACTION_CHANGE",
			default = true,
		},
		[5] = {
			type = "COMBAT_MISC_INFO",
			default = true,
		},
	},

	SKU = {
		[1] = {
			type = "COMBATLOG",
			default = false,
		},
		[2] = {
			type = "AUDIOLOG",
			default = false,
		}
	},
}

SkuChat.ChatFrameDefaultTabs = {
	[L["Default"]] = {
		PLAYER_MESSAGES = {
			[1] = {
				type = "SAY",
				default = play,
			},
			[2] = {
				type = "EMOTE",
				default = play,
			},
			[3] = {
				type = "YELL",
				default = play,
			},
			[4] = {
				text = GUILD_CHAT,
				type = "GUILD",
				default = false,
			},
			[5] = {
				text = OFFICER_CHAT,
				type = "OFFICER",
				default = false,
			},
			[6] = {
				type = "WHISPER",
				default = false,
			},
			[7] = {
				type = "BN_WHISPER",
				default = false,
			},
			[8] = {
				type = "PARTY",
				default = false,
			},
			[9] = {
				type = "PARTY_LEADER",
				default = false,
			},
			[10] = {
				type = "RAID",
				default = false,
			},
			[11] = {
				type = "RAID_LEADER",
				default = false,
			},
			[12] = {
				type = "RAID_WARNING",
				default = false,
			},
			[13] = {
				type = "INSTANCE_CHAT",
				default = false,
			},
			[14] = {
				type = "INSTANCE_CHAT_LEADER",
				default = false,
			},
		},
	
		CREATURE_MESSAGES = {
			[1] = {
				text = SAY;
				type = "MONSTER_SAY",
				default = play,
			},
			[2] = {
				text = EMOTE;
				type = "MONSTER_EMOTE",
				default = play,
			},
			[3] = {
				text = YELL;
				type = "MONSTER_YELL",
				default = play,
			},
			[4] = {
				text = WHISPER;
				type = "MONSTER_WHISPER",
				default = false,
			},
			[5] = {
				type = "MONSTER_BOSS_EMOTE",
				default = false,
			},
			[6] = {
				type = "MONSTER_BOSS_WHISPER",
				default = false,
			}
		},
	
		OTHER = {
			[1] = {
				text = SKILLUPS,
				type = "SKILL",
				default = false,
				},
			[2] = {
				text = ITEM_LOOT,
				type = "LOOT",
				default = false,
				},
			[3] = {
				text = MONEY_LOOT,
				type = "MONEY",
				default = false,
				},
			[4] = {
				type = "TRADESKILLS",
				default = false,
				},
			[5] = {
				type = "OPENING",
				default = false,
				},
			[6] = {
				type = "PET_INFO",
				default = false,
				},
		},
	
		PVP = {
			[1] = {
				text = BG_SYSTEM_HORDE,
				type = "BG_HORDE",
				default = false,
			},
			[2] = {
				text = BG_SYSTEM_ALLIANCE,
				type = "BG_ALLIANCE",
				default = false,
			},
			[3] = {
				text = BG_SYSTEM_NEUTRAL,
				type = "BG_NEUTRAL",
				default = false,
			},
		},
	
		SYSTEM = {
			[1] = {
				text = SYSTEM_MESSAGES,
				type = "SYSTEM",
				default = true,
			},
			[2] = {
				type = "ERRORS",
				default = true,
			},
			[3] = {
				type = "IGNORED",
				default = true,
			},
			[4] = {
				type = "CHANNEL",
				default = true,
			},
			[5] = {
				type = "TARGETICONS",
				default = true,
			},
			[6] = {
				type = "BN_INLINE_TOAST_ALERT",
				default = true,
			},
			[7] = {
				text = L["Addons"],
				type = "ADDON",
				default = play,
			},		
		},
		
		COMBAT = {
			[1] = {
				type = "COMBAT_XP_GAIN",
				default = true,
			},
			[2] = {
				type = "COMBAT_HONOR_GAIN",
				default = true,
			},
			[3] = {
				type = "COMBAT_FACTION_CHANGE",
				default = true,
			},
			[5] = {
				type = "COMBAT_MISC_INFO",
				default = true,
			},
		},
	},
	[L["Communication"]] = {
		PLAYER_MESSAGES = {
			[1] = {
				type = "SAY",
				default = false,
			},
			[2] = {
				type = "EMOTE",
				default = false,
			},
			[3] = {
				type = "YELL",
				default = false,
			},
			[4] = {
				text = GUILD_CHAT,
				type = "GUILD",
				default = play,
			},
			[5] = {
				text = OFFICER_CHAT,
				type = "OFFICER",
				default = play,
			},
			-- Whispers moved to the dedicated L["ChatTabWhisper"] tab below; muted here
			-- so a whisper is announced once, not once per tab that carries the type.
			[6] = {
				type = "WHISPER",
				default = false,
			},
			[7] = {
				type = "BN_WHISPER",
				default = false,
			},
			[8] = {
				type = "PARTY",
				default = play,
			},
			[9] = {
				type = "PARTY_LEADER",
				default = play,
			},
			[10] = {
				type = "RAID",
				default = play,
			},
			[11] = {
				type = "RAID_LEADER",
				default = play,
			},
			[12] = {
				type = "RAID_WARNING",
				default = play,
			},
			[13] = {
				type = "INSTANCE_CHAT",
				default = play,
			},
			[14] = {
				type = "INSTANCE_CHAT_LEADER",
				default = play,
			},
		},
	
		CREATURE_MESSAGES = {
			[1] = {
				text = SAY;
				type = "MONSTER_SAY",
				default = false,
			},
			[2] = {
				text = EMOTE;
				type = "MONSTER_EMOTE",
				default = false,
			},
			[3] = {
				text = YELL;
				type = "MONSTER_YELL",
				default = false,
			},
			[4] = {
				text = WHISPER;
				type = "MONSTER_WHISPER",
				default = play,
			},
			[5] = {
				type = "MONSTER_BOSS_EMOTE",
				default = play,
			},
			[6] = {
				type = "MONSTER_BOSS_WHISPER",
				default = play,
			}
		},
	
		OTHER = {
			[1] = {
				text = SKILLUPS,
				type = "SKILL",
				default = false,
				},
			[2] = {
				text = ITEM_LOOT,
				type = "LOOT",
				default = false,
				},
			[3] = {
				text = MONEY_LOOT,
				type = "MONEY",
				default = false,
				},
			[4] = {
				type = "TRADESKILLS",
				default = false,
				},
			[5] = {
				type = "OPENING",
				default = false,
				},
			[6] = {
				type = "PET_INFO",
				default = false,
				},
		},
	
		PVP = {
			[1] = {
				text = BG_SYSTEM_HORDE,
				type = "BG_HORDE",
				default = false,
			},
			[2] = {
				text = BG_SYSTEM_ALLIANCE,
				type = "BG_ALLIANCE",
				default = false,
			},
			[3] = {
				text = BG_SYSTEM_NEUTRAL,
				type = "BG_NEUTRAL",
				default = false,
			},
		},
	
		SYSTEM = {
			[1] = {
				text = SYSTEM_MESSAGES,
				type = "SYSTEM",
				default = false,
			},
			[2] = {
				type = "ERRORS",
				default = false,
			},
			[3] = {
				type = "IGNORED",
				default = false,
			},
			[4] = {
				type = "CHANNEL",
				default = false,
			},
			[5] = {
				type = "TARGETICONS",
				default = false,
			},
			[6] = {
				type = "BN_INLINE_TOAST_ALERT",
				default = false,
			},
			[7] = {
				text = L["Addons"],
				type = "ADDON",
				default = false,
			},		
		},
		
		COMBAT = {
			[1] = {
				type = "COMBAT_XP_GAIN",
				default = false,
			},
			[2] = {
				type = "COMBAT_HONOR_GAIN",
				default = false,
			},
			[3] = {
				type = "COMBAT_FACTION_CHANGE",
				default = false,
			},
			[5] = {
				type = "COMBAT_MISC_INFO",
				default = false,
			},
		},
	},
	[L["Other"]] = {
		PLAYER_MESSAGES = {
			[1] = {
				type = "SAY",
				default = false,
			},
			[2] = {
				type = "EMOTE",
				default = false,
			},
			[3] = {
				type = "YELL",
				default = false,
			},
			[4] = {
				text = GUILD_CHAT,
				type = "GUILD",
				default = false,
			},
			[5] = {
				text = OFFICER_CHAT,
				type = "OFFICER",
				default = false,
			},
			[6] = {
				type = "WHISPER",
				default = false,
			},
			[7] = {
				type = "BN_WHISPER",
				default = false,
			},
			[8] = {
				type = "PARTY",
				default = false,
			},
			[9] = {
				type = "PARTY_LEADER",
				default = false,
			},
			[10] = {
				type = "RAID",
				default = false,
			},
			[11] = {
				type = "RAID_LEADER",
				default = false,
			},
			[12] = {
				type = "RAID_WARNING",
				default = false,
			},
			[13] = {
				type = "INSTANCE_CHAT",
				default = false,
			},
			[14] = {
				type = "INSTANCE_CHAT_LEADER",
				default = false,
			},
		},
	
		CREATURE_MESSAGES = {
			[1] = {
				text = SAY;
				type = "MONSTER_SAY",
				default = false,
			},
			[2] = {
				text = EMOTE;
				type = "MONSTER_EMOTE",
				default = false,
			},
			[3] = {
				text = YELL;
				type = "MONSTER_YELL",
				default = false,
			},
			[4] = {
				text = WHISPER;
				type = "MONSTER_WHISPER",
				default = false,
			},
			[5] = {
				type = "MONSTER_BOSS_EMOTE",
				default = false,
			},
			[6] = {
				type = "MONSTER_BOSS_WHISPER",
				default = false,
			}
		},
	
		OTHER = {
			[1] = {
				text = SKILLUPS,
				type = "SKILL",
				default = true,
				},
			[2] = {
				text = ITEM_LOOT,
				type = "LOOT",
				default = true,
				},
			[3] = {
				text = MONEY_LOOT,
				type = "MONEY",
				default = true,
				},
			[4] = {
				type = "TRADESKILLS",
				default = true,
				},
			[5] = {
				type = "OPENING",
				default = true,
				},
			[6] = {
				type = "PET_INFO",
				default = true,
				},
		},
	
		PVP = {
			[1] = {
				text = BG_SYSTEM_HORDE,
				type = "BG_HORDE",
				default = false,
			},
			[2] = {
				text = BG_SYSTEM_ALLIANCE,
				type = "BG_ALLIANCE",
				default = false,
			},
			[3] = {
				text = BG_SYSTEM_NEUTRAL,
				type = "BG_NEUTRAL",
				default = false,
			},
		},
	
		SYSTEM = {
			[1] = {
				text = SYSTEM_MESSAGES,
				type = "SYSTEM",
				default = false,
			},
			[2] = {
				type = "ERRORS",
				default = false,
			},
			[3] = {
				type = "IGNORED",
				default = false,
			},
			[4] = {
				type = "CHANNEL",
				default = false,
			},
			[5] = {
				type = "TARGETICONS",
				default = false,
			},
			[6] = {
				type = "BN_INLINE_TOAST_ALERT",
				default = false,
			},
			[7] = {
				text = L["Addons"],
				type = "ADDON",
				default = play,
			},		
		},
		
		COMBAT = {
			[1] = {
				type = "COMBAT_XP_GAIN",
				default = false,
			},
			[2] = {
				type = "COMBAT_HONOR_GAIN",
				default = false,
			},
			[3] = {
				type = "COMBAT_FACTION_CHANGE",
				default = false,
			},
			[5] = {
				type = "COMBAT_MISC_INFO",
				default = false,
			},
		},
	},
	-- Dedicated whisper tab (default tab #4 for a fresh profile). ONLY player
	-- whispers and Battle.net whispers are audible here, every other message type
	-- and every channel is muted, so a whisper is unmistakable. Whispers are muted
	-- in the Communication tab in return -- two tabs carrying the same type would
	-- make SkuChat speak every whisper twice (one AddMessage per tab frame).
	-- Monster/boss whispers stay in Communication; they are not player whispers.
	[L["ChatTabWhisper"]] = {
		PLAYER_MESSAGES = {
			[1] = {
				type = "SAY",
				default = false,
			},
			[2] = {
				type = "EMOTE",
				default = false,
			},
			[3] = {
				type = "YELL",
				default = false,
			},
			[4] = {
				text = GUILD_CHAT,
				type = "GUILD",
				default = false,
			},
			[5] = {
				text = OFFICER_CHAT,
				type = "OFFICER",
				default = false,
			},
			[6] = {
				type = "WHISPER",
				default = play,
			},
			[7] = {
				type = "BN_WHISPER",
				default = play,
			},
			[8] = {
				type = "PARTY",
				default = false,
			},
			[9] = {
				type = "PARTY_LEADER",
				default = false,
			},
			[10] = {
				type = "RAID",
				default = false,
			},
			[11] = {
				type = "RAID_LEADER",
				default = false,
			},
			[12] = {
				type = "RAID_WARNING",
				default = false,
			},
			[13] = {
				type = "INSTANCE_CHAT",
				default = false,
			},
			[14] = {
				type = "INSTANCE_CHAT_LEADER",
				default = false,
			},
		},

		CREATURE_MESSAGES = {
			[1] = {
				text = SAY;
				type = "MONSTER_SAY",
				default = false,
			},
			[2] = {
				text = EMOTE;
				type = "MONSTER_EMOTE",
				default = false,
			},
			[3] = {
				text = YELL;
				type = "MONSTER_YELL",
				default = false,
			},
			[4] = {
				text = WHISPER;
				type = "MONSTER_WHISPER",
				default = false,
			},
			[5] = {
				type = "MONSTER_BOSS_EMOTE",
				default = false,
			},
			[6] = {
				type = "MONSTER_BOSS_WHISPER",
				default = false,
			}
		},

		OTHER = {
			[1] = {
				text = SKILLUPS,
				type = "SKILL",
				default = false,
				},
			[2] = {
				text = ITEM_LOOT,
				type = "LOOT",
				default = false,
				},
			[3] = {
				text = MONEY_LOOT,
				type = "MONEY",
				default = false,
				},
			[4] = {
				type = "TRADESKILLS",
				default = false,
				},
			[5] = {
				type = "OPENING",
				default = false,
				},
			[6] = {
				type = "PET_INFO",
				default = false,
				},
		},

		PVP = {
			[1] = {
				text = BG_SYSTEM_HORDE,
				type = "BG_HORDE",
				default = false,
			},
			[2] = {
				text = BG_SYSTEM_ALLIANCE,
				type = "BG_ALLIANCE",
				default = false,
			},
			[3] = {
				text = BG_SYSTEM_NEUTRAL,
				type = "BG_NEUTRAL",
				default = false,
			},
		},

		SYSTEM = {
			[1] = {
				text = SYSTEM_MESSAGES,
				type = "SYSTEM",
				default = false,
			},
			[2] = {
				type = "ERRORS",
				default = false,
			},
			[3] = {
				type = "IGNORED",
				default = false,
			},
			[4] = {
				type = "CHANNEL",
				default = false,
			},
			[5] = {
				type = "TARGETICONS",
				default = false,
			},
			[6] = {
				type = "BN_INLINE_TOAST_ALERT",
				default = false,
			},
			[7] = {
				text = L["Addons"],
				type = "ADDON",
				default = false,
			},
		},

		COMBAT = {
			[1] = {
				type = "COMBAT_XP_GAIN",
				default = false,
			},
			[2] = {
				type = "COMBAT_HONOR_GAIN",
				default = false,
			},
			[3] = {
				type = "COMBAT_FACTION_CHANGE",
				default = false,
			},
			[5] = {
				type = "COMBAT_MISC_INFO",
				default = false,
			},
		},
	},
}


---------------------------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------------
-- start of blizzard chatframe code
-- we are just re-using and customizing that for our virtual chat frames instead of building all that from scratch


---------------------------------------------------------------------------------------------------------------------------------------
-- Table for event indexed chatFilters.
-- Format ["CHAT_MSG_SYSTEM"] = { function1, function2, function3 }
-- filter, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11 = function1 (self, event, ...) if filter then return true end return false, ... end
local chatFilters = {} 

---------------------------------------------------------------------------------------------------------------------------------------
SkuChatChatTypeGroup = {} 
SkuChatChatTypeGroup["SYSTEM"] = {
	"CHAT_MSG_SYSTEM",
	"TIME_PLAYED_MSG",
	"PLAYER_LEVEL_UP",
	"CHARACTER_POINTS_CHANGED",
	"CHAT_MSG_BN_WHISPER_PLAYER_OFFLINE",
} 
SkuChatChatTypeGroup["SAY"] = {
	"CHAT_MSG_SAY",
} 
SkuChatChatTypeGroup["EMOTE"] = {
	"CHAT_MSG_EMOTE",
	"CHAT_MSG_TEXT_EMOTE",
} 
SkuChatChatTypeGroup["YELL"] = {
	"CHAT_MSG_YELL",
} 
SkuChatChatTypeGroup["WHISPER"] = {
	"CHAT_MSG_WHISPER",
	"CHAT_MSG_WHISPER_INFORM",
	"CHAT_MSG_AFK",
	"CHAT_MSG_DND",
} 
SkuChatChatTypeGroup["PARTY"] = {
	"CHAT_MSG_PARTY",
	"CHAT_MSG_MONSTER_PARTY",
} 
SkuChatChatTypeGroup["PARTY_LEADER"] = {
	"CHAT_MSG_PARTY_LEADER",
} 
SkuChatChatTypeGroup["RAID"] = {
	"CHAT_MSG_RAID",
} 
SkuChatChatTypeGroup["RAID_LEADER"] = {
	"CHAT_MSG_RAID_LEADER",
} 
SkuChatChatTypeGroup["RAID_WARNING"] = {
	"CHAT_MSG_RAID_WARNING",
} 
SkuChatChatTypeGroup["INSTANCE_CHAT"] = {
	"CHAT_MSG_INSTANCE_CHAT",
} 
SkuChatChatTypeGroup["INSTANCE_CHAT_LEADER"] = {
	"CHAT_MSG_INSTANCE_CHAT_LEADER",
} 
SkuChatChatTypeGroup["GUILD"] = {
	"CHAT_MSG_GUILD",
	"GUILD_MOTD",
} 
SkuChatChatTypeGroup["OFFICER"] = {
	"CHAT_MSG_OFFICER",
} 
SkuChatChatTypeGroup["MONSTER_SAY"] = {
	"CHAT_MSG_MONSTER_SAY",
} 
SkuChatChatTypeGroup["MONSTER_YELL"] = {
	"CHAT_MSG_MONSTER_YELL",
} 
SkuChatChatTypeGroup["MONSTER_EMOTE"] = {
	"CHAT_MSG_MONSTER_EMOTE",
} 
SkuChatChatTypeGroup["MONSTER_WHISPER"] = {
	"CHAT_MSG_MONSTER_WHISPER",
} 
SkuChatChatTypeGroup["MONSTER_BOSS_EMOTE"] = {
	"CHAT_MSG_RAID_BOSS_EMOTE",
} 
SkuChatChatTypeGroup["MONSTER_BOSS_WHISPER"] = {
	"CHAT_MSG_RAID_BOSS_WHISPER",
} 
SkuChatChatTypeGroup["ERRORS"] = {
	"CHAT_MSG_RESTRICTED",
	"CHAT_MSG_FILTERED",
} 
SkuChatChatTypeGroup["AFK"] = {
	"CHAT_MSG_AFK",
} 
SkuChatChatTypeGroup["DND"] = {
	"CHAT_MSG_DND",
} 
SkuChatChatTypeGroup["IGNORED"] = {
	"CHAT_MSG_IGNORED",
} 
SkuChatChatTypeGroup["BG_HORDE"] = {
	"CHAT_MSG_BG_SYSTEM_HORDE",
} 
SkuChatChatTypeGroup["BG_ALLIANCE"] = {
	"CHAT_MSG_BG_SYSTEM_ALLIANCE",
} 
SkuChatChatTypeGroup["BG_NEUTRAL"] = {
	"CHAT_MSG_BG_SYSTEM_NEUTRAL",
} 
SkuChatChatTypeGroup["COMBAT_XP_GAIN"] = {
	"CHAT_MSG_COMBAT_XP_GAIN" 
}
SkuChatChatTypeGroup["COMBAT_HONOR_GAIN"] = {
	"CHAT_MSG_COMBAT_HONOR_GAIN" 
}
SkuChatChatTypeGroup["COMBAT_FACTION_CHANGE"] = {
	"CHAT_MSG_COMBAT_FACTION_CHANGE" 
} 
SkuChatChatTypeGroup["SKILL"] = {
	"CHAT_MSG_SKILL",
} 
SkuChatChatTypeGroup["LOOT"] = {
	"CHAT_MSG_LOOT",
} 
SkuChatChatTypeGroup["MONEY"] = {
	"CHAT_MSG_MONEY",
} 
SkuChatChatTypeGroup["CURRENCY"] = {
	"CHAT_MSG_CURRENCY",
} 
SkuChatChatTypeGroup["OPENING"] = {
	"CHAT_MSG_OPENING" 
} 
SkuChatChatTypeGroup["TRADESKILLS"] = {
	"CHAT_MSG_TRADESKILLS" 
} 
SkuChatChatTypeGroup["PET_INFO"] = {
	"CHAT_MSG_PET_INFO" 
} 
SkuChatChatTypeGroup["COMBAT_MISC_INFO"] = {
	"CHAT_MSG_COMBAT_MISC_INFO" 
} 
SkuChatChatTypeGroup["ACHIEVEMENT"] = {
	"CHAT_MSG_ACHIEVEMENT" 
} 
SkuChatChatTypeGroup["CHANNEL"] = {
	"CHAT_MSG_CHANNEL_JOIN",
	"CHAT_MSG_CHANNEL_LEAVE",
	"CHAT_MSG_CHANNEL_NOTICE",
	"CHAT_MSG_CHANNEL_NOTICE_USER",
	"CHAT_MSG_CHANNEL_LIST",
} 
--[[
SkuChatChatTypeGroup["COMMUNITIES_CHANNEL"] = {
	"CHAT_MSG_COMMUNITIES_CHANNEL",
}
]]
SkuChatChatTypeGroup["TARGETICONS"] = {
	"CHAT_MSG_TARGETICONS"
} 
SkuChatChatTypeGroup["BN_WHISPER"] = {
	"CHAT_MSG_BN_WHISPER",
	"CHAT_MSG_BN_WHISPER_INFORM",
} 
SkuChatChatTypeGroup["BN_INLINE_TOAST_ALERT"] = {
	"CHAT_MSG_BN_INLINE_TOAST_ALERT",
	"CHAT_MSG_BN_INLINE_TOAST_BROADCAST",
	"CHAT_MSG_BN_INLINE_TOAST_BROADCAST_INFORM",
} 
SkuChatChatTypeGroup["VOICE_TEXT"] = {
	"CHAT_MSG_VOICE_TEXT",
} 

SkuChatChatTypeGroup["COMBATLOG"] = {
	"SKU_COMBATLOG",
} 
SkuChatChatTypeGroup["AUDIOLOG"] = {
	"SKU_AUDIOLOG",
} 

---------------------------------------------------------------------------------------------------------------------------------------
SkuChatChatTypeGroupInverted = {} 
for group, values in pairs(SkuChatChatTypeGroup) do
	for _, value in pairs(values) do
		SkuChatChatTypeGroupInverted[value] = group 
	end
end

SkuChatCHAT_CATEGORY_LIST = {
	PARTY = { "PARTY_LEADER", "PARTY_GUIDE", "MONSTER_PARTY" },
	RAID = { "RAID_LEADER", "RAID_WARNING" },
	GUILD = { "GUILD_ACHIEVEMENT", "GUILD_ITEM_LOOTED" },
	WHISPER = { "WHISPER_INFORM", "AFK", "DND" },
	CHANNEL = { "CHANNEL_JOIN", "CHANNEL_LEAVE", "CHANNEL_NOTICE", "CHANNEL_USER", "CHANNEL_NOTICE_USER" },
	INSTANCE_CHAT = { "INSTANCE_CHAT_LEADER" },
	BN_WHISPER = { "BN_WHISPER_INFORM" },
} 

SkuChatCHAT_INVERTED_CATEGORY_LIST = {} 
for category, sublist in pairs(SkuChatCHAT_CATEGORY_LIST) do
	for _, item in pairs(sublist) do
		SkuChatCHAT_INVERTED_CATEGORY_LIST[item] = category 
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function MaskBattleNetNames(aString)
	if string.find(aString, "|K") then
		aString = string.gsub(aString, "|K", "$skuk1")
		aString = string.gsub(aString, "|k", "$skuk2")
	end
	return aString
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuChatChat_GetChatCategory(chatType)
	return SkuChatCHAT_INVERTED_CATEGORY_LIST[chatType] or chatType 
end

local MAX_COMMUNITY_NAME_LENGTH = 12 
local MAX_COMMUNITY_NAME_LENGTH_NO_CHANNEL = 24 
function SkuChat_TruncateToMaxLength(text, maxLength)
	local length = strlenutf8(text) 
	if ( length > maxLength ) then
		return text:sub(1, maxLength - 2).."..." 
	end

	return text 
end

function SkuChat_ResolvePrefixedChannelName(communityChannel)
	communityChannel = SkuChat:ShortenChannelName(communityChannel)

	local prefix, communityChannel = communityChannel:match("(%d+. )(.*)") 
	return prefix..SkuChat_ResolveChannelName(communityChannel) 
end

function SkuChat_GetCommunityAndStreamFromChannel(communityChannel)
	local clubId, streamId = communityChannel:match("(%d+)%:(%d+)") 
	return tonumber(clubId), tonumber(streamId) 
end

function SkuChat_ResolveChannelName(communityChannel)
	local clubId, streamId = SkuChat_GetCommunityAndStreamFromChannel(communityChannel) 
	if not clubId or not streamId then
		return communityChannel 
	end

	return SkuChat_GetCommunityAndStreamName(clubId, streamId) 
end

function SkuChat_GetCommunityAndStreamName(clubId, streamId)
	local streamInfo = C_Club.GetStreamInfo(clubId, streamId) 
	local streamName = streamInfo and SkuChat_TruncateToMaxLength(streamInfo.name, MAX_COMMUNITY_NAME_LENGTH) or "" 
	local clubInfo = C_Club.GetClubInfo(clubId) 
	if streamInfo and streamInfo.streamType == Enum.ClubStreamType.General then
		local communityName = clubInfo and SkuChat_TruncateToMaxLength(clubInfo.shortName or clubInfo.name, MAX_COMMUNITY_NAME_LENGTH_NO_CHANNEL) or "" 
		return communityName 
	else
		local communityName = clubInfo and SkuChat_TruncateToMaxLength(clubInfo.shortName or clubInfo.name, MAX_COMMUNITY_NAME_LENGTH) or "" 
		return communityName.." - "..streamName 
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuChat_OnLoad(self)
	self:RegisterEvent("PLAYER_ENTERING_WORLD") 
	self:RegisterEvent("UPDATE_CHAT_COLOR") 
	self:RegisterEvent("UPDATE_CHAT_WINDOWS") 
	self:RegisterEvent("CHAT_MSG_CHANNEL") 
	--self:RegisterEvent("CHAT_MSG_COMMUNITIES_CHANNEL") 
	self:RegisterEvent("UPDATE_INSTANCE_INFO") 
	self:RegisterEvent("UPDATE_CHAT_COLOR_NAME_BY_CLASS") 
	self:RegisterEvent("VARIABLES_LOADED") 
	self:RegisterEvent("CHAT_SERVER_DISCONNECTED") 
	self:RegisterEvent("CHAT_SERVER_RECONNECTED") 
	self:RegisterEvent("BN_CONNECTED") 
	self:RegisterEvent("BN_DISCONNECTED") 
	self:RegisterEvent("PLAYER_REPORT_SUBMITTED") 
	self:RegisterEvent("ALTERNATIVE_DEFAULT_LANGUAGE_CHANGED") 
	self:RegisterEvent("NOTIFY_CHAT_SUPPRESSED") 
	self:RegisterEvent("CHANNEL_UI_UPDATE") 

	self.defaultLanguage = GetDefaultLanguage()  --If PLAYER_ENTERING_WORLD hasn't been called yet, this is nil, but it'll be fixed whent he event is fired.
	self.alternativeDefaultLanguage = GetAlternativeDefaultLanguage() 
end

function SkuChat_RegisterForMessages(self, aTable)
	local messageGroup 
	local index = 1 
	for i = 1, #aTable do
		messageGroup = SkuChatChatTypeGroup[aTable[i]] 
		if ( messageGroup ) then
			self.messageTypeList[index] = aTable[i] 
			for index, value in pairs(messageGroup) do
				self:RegisterEvent(value) 
				if ( value == "CHAT_MSG_VOICE_TEXT" ) then
					self:RegisterEvent("VOICE_CHAT_CHANNEL_TRANSCRIBING_CHANGED") 
				end
			end
			index = index + 1 
		end
	end
end

function SkuChat_RegisterForChannels(self, ...)
	local index = 1 
	for i=1, select("#", ...), 2 do
		self.channelList[index], self.zoneChannelList[index] = select(i, ...) 
		index = index + 1 
	end
end

function SkuChat_AddMessageGroup(chatFrame, group)
	local info = SkuChatChatTypeGroup[group] 
	if ( info ) then
		tinsert(chatFrame.messageTypeList, group) 
		for index, value in pairs(info) do
			if group == "COMBATLOG" or group == "AUDIOLOG" then
				SkuDispatcher:RegisterEventCallback(value, SkuChat_SkuMessageEventHandler)
			else
				chatFrame:RegisterEvent(value) 
			end
		end
	end
end

function SkuChat_ContainsMessageGroup(chatFrame, group)
	for i, messageType in pairs(chatFrame.messageTypeList) do
		if group == messageType then
			return true 
		end
	end
	
	return false 
end

function SkuChat_AddSingleMessageType(chatFrame, messageType)
	local group = SkuChatChatTypeGroupInverted[messageType] 
	local info = SkuChatChatTypeGroup[group] 
	if ( info ) then
		if (not tContains(chatFrame.messageTypeList, group)) then
			tinsert(chatFrame.messageTypeList, group) 
		end
		for index, value in pairs(info) do
			if (value == messageType) then
				chatFrame:RegisterEvent(value) 
			end
		end
	end
end

function SkuChat_RemoveMessageGroup(chatFrame, group)
	local info = SkuChatChatTypeGroup[group] 
	if ( info ) then
		for index, value in pairs(chatFrame.messageTypeList) do
			if ( strupper(value) == strupper(group) ) then
				chatFrame.messageTypeList[index] = nil 
			end
		end
		for index, value in pairs(info) do
			chatFrame:UnregisterEvent(value) 
		end
	end
end

function SkuChat_RemoveAllMessageGroups(chatFrame)
	for index, value in pairs(chatFrame.messageTypeList) do
		for eventIndex, eventValue in pairs(SkuChatChatTypeGroup[value]) do
			chatFrame:UnregisterEvent(eventValue) 
		end
	end

	chatFrame.messageTypeList = {} 
end

function SkuChat_ContainsChannel(chatFrame, channel)
	for i, channelName in pairs(chatFrame.channelList) do
		if channel == channelName then
			return true 
		end
	end

	return false 
end

function SkuChat_CanAddChannel()
	return C_ChatInfo.GetNumActiveChannels() < MAX_WOW_CHAT_CHANNELS 
end

function SkuChat_AddChannel(chatFrame, channel)
	local channelIndex = nil 

	if channel == nil then
		return
	end

	local zoneChannel =  zoneChannels[string.lower(channel)]  --AddChatWindowChannel(chatFrame:GetID(), channel) 

	local i = 1 
	while ( chatFrame.channelList[i] ) do
		i = i + 1 
	end
	chatFrame.channelList[i] = channel 
	chatFrame.zoneChannelList[i] = zoneChannel 

	local localId = GetChannelName(channel) 
	channelIndex = localId 

	return channelIndex 
end

function SkuChat_RemoveChannel(chatFrame, channel)
	for index, value in pairs(chatFrame.channelList) do
		if ( strupper(channel) == strupper(value) ) then
			chatFrame.channelList[index] = nil 
			chatFrame.zoneChannelList[index] = nil 
		end
	end

	local localId = GetChannelName(channel) 
	return localId 
end

function SkuChat_RemoveAllChannels(chatFrame)
	chatFrame.channelList = {} 
	chatFrame.zoneChannelList = {} 
end

function SkuChat_AddPrivateMessageTarget(chatFrame, chatTarget)
	SkuChat_RemoveExcludePrivateMessageTarget(chatFrame, chatTarget) 
	if ( chatFrame.privateMessageList ) then
		chatFrame.privateMessageList[strlower(chatTarget)] = true 
	else
		chatFrame.privateMessageList = { [strlower(chatTarget)] = true } 
	end
end

function SkuChat_RemoveAllPrivateMessageTargets(chatFrame)
	if ( chatFrame.privateMessageList ) then
		chatFrame.privateMessageList = {} 
	end
end

function SkuChat_RemovePrivateMessageTarget(chatFrame, chatTarget)
	if ( chatFrame.privateMessageList ) then
		chatFrame.privateMessageList[strlower(chatTarget)] = nil 
	end
end

function SkuChat_ExcludePrivateMessageTarget(chatFrame, chatTarget)
	SkuChat_RemovePrivateMessageTarget(chatFrame, chatTarget) 
	if ( chatFrame.excludePrivateMessageList ) then
		chatFrame.excludePrivateMessageList[strlower(chatTarget)] = true 
	else
		chatFrame.excludePrivateMessageList = { [strlower(chatTarget)] = true } 
	end
end

function SkuChat_RemoveExcludePrivateMessageTarget(chatFrame, chatTarget)
	if ( chatFrame.excludePrivateMessageList ) then
		chatFrame.excludePrivateMessageList[strlower(chatTarget)] = nil 
	end
end

function SkuChat_ReceiveAllPrivateMessages(chatFrame)
	chatFrame.privateMessageList = nil 
	chatFrame.excludePrivateMessageList = nil 
end

function SkuChat_OnEvent(self, event, ...)
	-- W4 Rework B-step-2: the per-tab chat frames keep their CHAT_MSG_* event
	-- registrations alive even while SkuChat is disabled (we do not tear those
	-- frames down). Guard the single choke so a disabled SkuChat ignores all
	-- incoming chat events. No-op cost when enabled (IsEnabled() == true).
	if SkuChat.IsEnabled and not SkuChat:IsEnabled() then return end
	if ( self.customEventHandler and self.customEventHandler(self, event, ...) ) then
		return 
	end

	if ( SkuChat_ConfigEventHandler(self, event, ...) ) then
		return 
	end

	if ( SkuChat_SystemEventHandler(self, event, ...) ) then
		return
	end

	if ( SkuChat_MessageEventHandler(self, event, ...) ) then
		return
	end
end

function SkuChat_ConfigEventHandler(self, event, ...)
	--find messagetype group
	local tMessagetype = event
	for i, v in pairs(SkuChatChatTypeGroup) do
		for _, value in pairs(v) do
			if event == value then
				tMessagetype = i
			end
		end
	end

	if ( event == "PLAYER_ENTERING_WORLD" ) then
		self.defaultLanguage = GetDefaultLanguage() 
		self.alternativeDefaultLanguage = GetAlternativeDefaultLanguage() 
		return true 

	elseif ( event == "NEUTRAL_FACTION_SELECT_RESULT" ) then
		self.defaultLanguage = GetDefaultLanguage() 
		self.alternativeDefaultLanguage = GetAlternativeDefaultLanguage() 
		return true 

	elseif ( event == "ALTERNATIVE_DEFAULT_LANGUAGE_CHANGED" ) then
		self.alternativeDefaultLanguage = GetAlternativeDefaultLanguage() 
		return true 
		
	elseif ( event == "CHANNEL_UI_UPDATE" ) then
		-- Do more stuff!!!
		--SkuChat_RemoveAllMessageGroups(self)
		--SkuChat_RemoveAllChannels(self)
		--SkuChat_RegisterForMessages(self, self.messageTypeList) 
		--SkuChat_RegisterForChannels(self, GetChatWindowChannels(DEFAULT_CHAT_FRAME:GetID())) 
		return true

	elseif ( event == "UPDATE_CHAT_WINDOWS" ) then
		-- Do more stuff!!!
		--SkuChat_RemoveAllChannels(self)
		--SkuChat_RegisterForMessages(self, self.messageTypeList) 
		--SkuChat_RegisterForChannels(self, GetChatWindowChannels(DEFAULT_CHAT_FRAME:GetID())) 
		
		-- GMOTD may have arrived before this frame registered for the event
		if ( not self.checkedGMOTD and self:IsEventRegistered("GUILD_MOTD") ) then
			self.checkedGMOTD = true 
			SkuChat_DisplayGMOTD(self, GetGuildRosterMOTD()) 
		end
		return true 
	end

	local arg1, arg2, arg3, arg4 = ... 
	if ( event == "UPDATE_CHAT_COLOR" ) then
		--[[
		local info = {r = nil, g = nil, b = nil, id = nil}
		if ( info ) then
			info.r = arg2 
			info.g = arg3 
			info.b = arg4 
			SkuChat_UpdateColorByID(self, info.id, info.r, info.g, info.b) 

			if ( strupper(arg1) == "WHISPER" ) then
				info = {r = nil, g = nil, b = nil, id = nil}
				if ( info ) then
					info.r = arg2 
					info.g = arg3 
					info.b = arg4 
					SkuChat_UpdateColorByID(self, info.id, info.r, info.g, info.b) 
				end
			end
		end
		]]
		return true 

	elseif ( event == "UPDATE_CHAT_COLOR_NAME_BY_CLASS" ) then
		--[[
		local info = {r = nil, g = nil, b = nil, id = nil}
		if ( info ) then
			info.colorNameByClass = arg2 
			if ( strupper(arg1) == "WHISPER" ) then
				info = {r = nil, g = nil, b = nil, id = nil}
				if ( info ) then
					info.colorNameByClass = arg2 
				end
			end
		end
		]]
		return true 
	end
end

function SkuChat_SystemEventHandler(self, event, ...)
	--find messagetype group
	local tMessagetype = event
	for i, v in pairs(SkuChatChatTypeGroup) do
		for _, value in pairs(v) do
			if event == value then
				tMessagetype = i
			end
		end
	end

	if ( event == "TIME_PLAYED_MSG" ) then
		local arg1, arg2 = ... 
		SkuChat_DisplayTimePlayed(self, arg1, arg2) 
		return true 

	elseif ( event == "PLAYER_LEVEL_UP" ) then
		SkuChat_DisplayLevelUp(self, ...)
		return true 

	elseif ( event == "CHARACTER_POINTS_CHANGED" ) then
		local arg1 = ... 
		local info = {r = nil, g = nil, b = nil, id = nil}
		return true 

	elseif ( event == "GUILD_MOTD" ) then
		SkuChat_DisplayGMOTD(self, ...) 
		return true 

	elseif ( event == "UPDATE_INSTANCE_INFO" ) then
		--[[
		if ( RaidFrame.hasRaidInfo ) then
			local info = {r = nil, g = nil, b = nil, id = nil}
			if ( RaidFrame.slashCommand and GetNumSavedInstances() == 0 and self == DEFAULT_CHAT_FRAME) then
				self:AddMessage(tMessagetype, NO_RAID_INSTANCES_SAVED, info.r, info.g, info.b, info.id) 
				RaidFrame.slashCommand = nil 
			end
		end
		]]
		return true 

	elseif ( event == "CHAT_SERVER_DISCONNECTED" ) then
		local info = {r = nil, g = nil, b = nil, id = nil}
		local isInitialMessage = ... 
		self:AddMessage(tMessagetype, CHAT_SERVER_DISCONNECTED_MESSAGE, info.r, info.g, info.b, info.id) 
		return true 

	elseif ( event == "CHAT_SERVER_RECONNECTED" ) then
		local info = {r = nil, g = nil, b = nil, id = nil}
		self:AddMessage(tMessagetype, CHAT_SERVER_RECONNECTED_MESSAGE, info.r, info.g, info.b, info.id) 
		return true 

	elseif ( event == "BN_CONNECTED" ) then
		local info = {r = nil, g = nil, b = nil, id = nil}
		self:AddMessage(tMessagetype, BN_CHAT_CONNECTED, info.r, info.g, info.b, info.id) 

	elseif ( event == "BN_DISCONNECTED" ) then
		local info = {r = nil, g = nil, b = nil, id = nil}
		self:AddMessage(tMessagetype, BN_CHAT_DISCONNECTED, info.r, info.g, info.b, info.id) 

	elseif ( event == "NOTIFY_CHAT_SUPPRESSED" ) then
		local hyperlink = string.format("|Haadcopenconfig|h[%s]", RESTRICT_CHAT_CONFIG_HYPERLINK) 
		local message = string.format(RESTRICT_CHAT_SkuChat_FORMAT, RESTRICT_CHAT_MESSAGE_SUPPRESSED, LIGHTBLUE_FONT_COLOR:WrapTextInColorCode(hyperlink)) 
		local info = {r = nil, g = nil, b = nil, id = nil}
		self:AddMessage(tMessagetype, message, info.r, info.g, info.b, info.id) 
		return true 

	elseif ( event == "PLAYER_REPORT_SUBMITTED" ) then
		--[[
		local guid = ... 
		FCF_RemoveAllMessagesFromChanSender(self, guid) 
		]]
		return true 
	end
end

function GetColoredName(event, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12)
	local chatType = strsub(event, 10) 
	if ( strsub(chatType, 1, 7) == "WHISPER" ) then
		chatType = "WHISPER" 
	end

	if ( strsub(chatType, 1, 7) == "CHANNEL" ) then
		chatType = "CHANNEL"..arg8 
	end
	--local info = {r = nil, g = nil, b = nil, id = nil}

	--ambiguate guild chat names
	if (chatType == "GUILD") then
		arg2 = Ambiguate(arg2, "guild")
	else
		arg2 = Ambiguate(arg2, "none")
	end

	--[[
	if ( arg12 and info and Chat_ShouldColorChatByClass(info) ) then
		local localizedClass, englishClass, localizedRace, englishRace, sex = GetPlayerInfoByGUID(arg12)

		if ( englishClass ) then
			local classColorTable = RAID_CLASS_COLORS[englishClass] 
			if ( not classColorTable ) then
				return arg2 
			end
			return string.format("\124cff%.2x%.2x%.2x", classColorTable.r*255, classColorTable.g*255, classColorTable.b*255)..arg2.."\124r"
		end
	end
	]]

	return arg2 
end

function RemoveExtraSpaces(str)
	return string.gsub(str, "     +", "    ") 	--Replace all instances of 5+ spaces with only 4 spaces.
end

function RemoveNewlines(str)
	return string.gsub(str, "\n", "") 
end

function SkuChat_DisplayGMOTD(frame, gmotd)
	if ( gmotd and (gmotd ~= "") ) then
		--local info = {r = nil, g = nil, b = nil, id = nil}
		local string = format(GUILD_MOTD_TEMPLATE, gmotd) 
		frame:AddMessage(string, 1, 1, 1, 1) 
	end
end

function SkuChat_GetMobileEmbeddedTexture(r, g, b)
	r, g, b = floor(r * 255), floor(g * 255), floor(b * 255) 
	return " "--format("|TInterface\\ChatFrame\\UI-ChatIcon-ArmoryChat:14:14:0:0:16:16:0:16:0:16:%d:%d:%d|t", r, g, b) 
end

function SkuChat_CanChatGroupPerformExpressionExpansion(chatGroup)
	if chatGroup == "RAID" then
		return true 
	end

	if chatGroup == "INSTANCE_CHAT" then
		return IsInRaid(LE_PARTY_CATEGORY_INSTANCE) 
	end

	return false 
end

do
	function SkuChat_ReplaceIconAndGroupExpressions(message, noIconReplacement, noGroupReplacement)
		if message then
			message = string.gsub(message, "{", " ")
			message = string.gsub(message, "}", " ")
		end

		return message 
	end
end

function SkuChat_SkuMessageEventHandler(self, event, tMessagetype, message)
	for x = 1, #SkuSettings:Sub("SkuChat").tabs do
		if tMessagetype == "COMBATLOG" and SkuSettings:Sub("SkuChat").tabs[x].messageTypes["SKU"] and SkuSettings:Sub("SkuChat").tabs[x].messageTypes["SKU"][1] == true then
			_G[SkuSettings:Sub("SkuChat").tabs[x].frameName]:AddMessage(tMessagetype, message) 
		end
		if tMessagetype == "AUDIOLOG" and  SkuSettings:Sub("SkuChat").tabs[x].messageTypes["SKU"] and SkuSettings:Sub("SkuChat").tabs[x].messageTypes["SKU"][2] == true then
			_G[SkuSettings:Sub("SkuChat").tabs[x].frameName]:AddMessage(tMessagetype, message) 
		end
	end
	
end

function SkuChat_MessageEventHandler(self, event, ...)
	--find messagetype group
	local tMessagetype = event
	for i, v in pairs(SkuChatChatTypeGroup) do
		for _, value in pairs(v) do
			if event == value then
				tMessagetype = i
			end
		end
	end


	if ( strsub(event, 1, 8) == "CHAT_MSG" ) then
		local arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12, arg13, arg14, arg15, arg16, arg17 = ... 

		SkuNav:NavigationModeWoCoordinatesCheckTaskTrigger(arg1)

		if (arg16) then
			-- hiding sender in letterbox: do NOT even show in chat window (only shows in cinematic frame)
			return true 
		end

		local type = strsub(event, 10) 
		local info = {r = nil, g = nil, b = nil, id = nil}

		if SkuSettings:Sub("SkuChat").chatSettings.filter and SkuSettings:Sub("SkuChat").chatSettings.filter.terms then
			if arg2 == "Rhonin" then
				SkuOptions:StopSounds(15, true)
				return true
			end
			if SkuSettings:Sub("SkuChat").chatSettings.filter.terms[string.lower(arg1)] then
				return true
			end
		end

		local filter = false 
		if ( chatFilters[event] ) then
			local newarg1, newarg2, newarg3, newarg4, newarg5, newarg6, newarg7, newarg8, newarg9, newarg10, newarg11, newarg12, newarg13, newarg14 
			for _, filterFunc in next, chatFilters[event] do
				filter, newarg1, newarg2, newarg3, newarg4, newarg5, newarg6, newarg7, newarg8, newarg9, newarg10, newarg11, newarg12, newarg13, newarg14 = filterFunc(self, event, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12, arg13, arg14) 
				if ( filter ) then
					return true 
				elseif ( newarg1 ) then
					arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12, arg13, arg14 = newarg1, newarg2, newarg3, newarg4, newarg5, newarg6, newarg7, newarg8, newarg9, newarg10, newarg11, newarg12, newarg13, newarg14 
				end
			end
		end

		local coloredName = GetColoredName(event, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12, arg13, arg14) 
		local channelLength = strlen(arg4) 
		local infoType = type 

		if type == "VOICE_TEXT" and not GetCVarBool("speechToText") then
			return 

		elseif ( (type == "COMMUNITIES_CHANNEL") or ((strsub(type, 1, 7) == "CHANNEL") and (type ~= "CHANNEL_LIST") and ((arg1 ~= "INVITE") or (type ~= "CHANNEL_NOTICE_USER"))) ) then
			--print(arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12, arg13, arg14, arg15, arg16, arg17)			
			if ( arg1 == "WRONG_PASSWORD" ) then
				local staticPopup = _G[StaticPopup_Visible("CHAT_CHANNEL_PASSWORD") or ""] 
				if ( staticPopup and strupper(staticPopup.data) == strupper(arg9) ) then
					-- Don't display invalid password messages if we're going to prompt for a password (bug 102312)
					return 
				end
			end

			local found = 0 
			for index, value in pairs(self.channelList) do
				if ( channelLength > strlen(value) ) then
					-- arg9 is the channel name without the number in front...
					if ( ((arg7 > 0) and (self.zoneChannelList[index] == arg7)) or (strupper(value) == strupper(arg9)) ) then
						found = 1 
						infoType = "CHANNEL"..arg8 
						info = {r = nil, g = nil, b = nil, id = nil}
						if ( (type == "CHANNEL_NOTICE") and (arg1 == "YOU_LEFT") ) then
							self.channelList[index] = nil 
							self.zoneChannelList[index] = nil 
						end
						break 
					end
				end
			end
			if ( (found == 0) or not info ) then
				return true 
			end
		end

		local chatGroup = SkuChatChat_GetChatCategory(type) 
		local chatTarget 
		if ( chatGroup == "CHANNEL" ) then
			chatTarget = tostring(arg8) 
		elseif ( chatGroup == "WHISPER" or chatGroup == "BN_WHISPER" ) then
			if(not(strsub(arg2, 1, 2) == "|K")) then
				chatTarget = strupper(arg2) 
			else
				chatTarget = arg2 
			end
		end

		--[[
		if ( FCFManager_ShouldSuppressMessage(self, chatGroup, chatTarget) ) then
			return true 
		end
		]]

		if ( chatGroup == "WHISPER" or chatGroup == "BN_WHISPER" ) then
			if ( self.privateMessageList and not self.privateMessageList[strlower(arg2)] ) then
				return true 
			elseif ( self.excludePrivateMessageList and self.excludePrivateMessageList[strlower(arg2)]
				and ( 
					(chatGroup == "WHISPER" and GetCVar("whisperMode") ~= "popout_and_inline") or 
					(chatGroup == "BN_WHISPER" and GetCVar("whisperMode") ~= "popout_and_inline") 
				) ) then
				return true 
			end
		end

		if (self.privateMessageList) then
			-- Dedicated BN whisper windows need online/offline messages for only that player
			if ( (chatGroup == "BN_INLINE_TOAST_ALERT" or chatGroup == "BN_WHISPER_PLAYER_OFFLINE") and not self.privateMessageList[strlower(arg2)] ) then
				return true 
			end

			-- HACK to put certain system messages into dedicated whisper windows
			if ( chatGroup == "SYSTEM") then
				local matchFound = false 
				local message = strlower(arg1) 
				for playerName, _ in pairs(self.privateMessageList) do
					local playerNotFoundMsg = strlower(format(ERR_CHAT_PLAYER_NOT_FOUND_S, playerName)) 
					local charOnlineMsg = strlower(format(ERR_FRIEND_ONLINE_SS, playerName, playerName)) 
					local charOfflineMsg = strlower(format(ERR_FRIEND_OFFLINE_S, playerName)) 
					if ( message == playerNotFoundMsg or message == charOnlineMsg or message == charOfflineMsg) then
						matchFound = true 
						break 
					end
				end

				if (not matchFound) then
					return true 
				end
			end
		end

		if ( type == "SYSTEM" or type == "SKILL" or type == "CURRENCY" or type == "MONEY" or
		     type == "OPENING" or type == "TRADESKILLS" or type == "PET_INFO" or type == "TARGETICONS" or type == "BN_WHISPER_PLAYER_OFFLINE") then
			self:AddMessage(tMessagetype, arg1, info.r, info.g, info.b, info.id) 

		elseif (type == "LOOT") then
			-- Append [Share] hyperlink if this is a valid social item and you are the looter.
			-- arg5 contains the name of the player who looted
			if C_Social and (C_Social.IsSocialEnabled() and UnitName("player") == arg5) then
				local itemID, strippedItemLink = GetItemInfoFromHyperlink(arg1) 
				if (itemID and C_Social.GetLastItem() == itemID) then
					arg1 = arg1 .. " " .. Social_GetShareItemLink(strippedItemLink, true) 
				end
			end
			self:AddMessage(tMessagetype, arg1, info.r, info.g, info.b, info.id) 

		elseif ( strsub(type,1,7) == "COMBAT_" ) then
			self:AddMessage(tMessagetype, arg1, info.r, info.g, info.b, info.id) 

		elseif ( strsub(type,1,6) == "SPELL_" ) then
			self:AddMessage(tMessagetype, arg1, info.r, info.g, info.b, info.id) 

		elseif ( strsub(type,1,10) == "BG_SYSTEM_" ) then
			self:AddMessage(tMessagetype, arg1, info.r, info.g, info.b, info.id) 

		elseif ( strsub(type,1,11) == "ACHIEVEMENT" ) then
			-- Append [Share] hyperlink
			if C_Social and (arg12 == UnitGUID("player") and C_Social.IsSocialEnabled()) then
				local achieveID = GetAchievementInfoFromHyperlink(arg1) 
				if (achieveID) then
					arg1 = arg1 .. " " .. Social_GetShareAchievementLink(achieveID, true) 
				end
			end
			self:AddMessage(tMessagetype, arg1:format(SkuChat:GetPlayerLink(arg2, ("[%s]"):format(coloredName))), info.r, info.g, info.b, info.id) 

		elseif ( strsub(type,1,18) == "GUILD_ACHIEVEMENT" ) then
			local message = arg1:format(SkuChat:GetPlayerLink(arg2, ("[%s]"):format(coloredName))) 
			if C_Social and (C_Social.IsSocialEnabled()) then
				local achieveID = GetAchievementInfoFromHyperlink(arg1) 
				if (achieveID) then
					local isGuildAchievement = select(12, GetAchievementInfo(achieveID)) 
					if (isGuildAchievement) then
						message = message .. " " .. Social_GetShareAchievementLink(achieveID, true) 
					end
				end
			end
			self:AddMessage(tMessagetype, message, info.r, info.g, info.b, info.id) 

		elseif ( type == "IGNORED" ) then
			self:AddMessage(tMessagetype, format(CHAT_IGNORED, arg2), info.r, info.g, info.b, info.id) 

		elseif ( type == "FILTERED" ) then
			self:AddMessage(tMessagetype, format(CHAT_FILTERED, arg2), info.r, info.g, info.b, info.id) 

		elseif ( type == "RESTRICTED" ) then
			self:AddMessage(tMessagetype, CHAT_RESTRICTED_TRIAL, info.r, info.g, info.b, info.id) 

		elseif ( type == "CHANNEL_LIST") then
			if(channelLength > 0) then
				self:AddMessage(tMessagetype, format(_G["CHAT_"..type.."_GET"]..arg1, tonumber(arg8), arg4), info.r, info.g, info.b, info.id) 
			else
				self:AddMessage(tMessagetype, arg1, info.r, info.g, info.b, info.id) 
			end

		elseif (type == "CHANNEL_NOTICE_USER") then
			local globalstring = _G["CHAT_"..arg1.."_NOTICE_BN"] 
			if ( not globalstring ) then
				globalstring = _G["CHAT_"..arg1.."_NOTICE"] 
			end
			if not globalstring then
				GMError(("Missing global string for %q"):format("CHAT_"..arg1.."_NOTICE_BN")) 
				return 
			end
			if(arg5 ~= "") then
				-- TWO users in this notice (E.G. x kicked y)
				self:AddMessage(tMessagetype, format(globalstring, arg8, arg4, arg2, arg5), info.r, info.g, info.b, info.id) 
			elseif ( arg1 == "INVITE" ) then
				local playerLink = SkuChat:GetPlayerLink(arg2, ("[%s]"):format(arg2), arg11) 
				local accessID = ChatHistory_GetAccessID(chatGroup, chatTarget) 
				local typeID = ChatHistory_GetAccessID(infoType, chatTarget, arg12) 
				self:AddMessage(tMessagetype, format(globalstring, arg4, playerLink), info.r, info.g, info.b, info.id, accessID, typeID) 
			else
				self:AddMessage(tMessagetype, format(globalstring, arg8, arg4, arg2), info.r, info.g, info.b, info.id) 
			end
			if ( arg1 == "INVITE" and GetCVarBool("blockChannelInvites") ) then
				self:AddMessage(tMessagetype, CHAT_MSG_BLOCK_CHAT_CHANNEL_INVITE, info.r, info.g, info.b, info.id) 
			end

		elseif (type == "CHANNEL_NOTICE") then
			local globalstring 
			if ( arg1 == "TRIAL_RESTRICTED" ) then
				globalstring = CHAT_TRIAL_RESTRICTED_NOTICE_TRIAL 
			else
				globalstring = _G["CHAT_"..arg1.."_NOTICE_BN"] 
				if ( not globalstring ) then
					globalstring = _G["CHAT_"..arg1.."_NOTICE"] 
					if not globalstring then
						GMError(("Missing global string for %q"):format("CHAT_"..arg1.."_NOTICE")) 
						return 
					end
				end
			end
			local accessID = ChatHistory_GetAccessID(SkuChatChat_GetChatCategory(type), arg8) 
			local typeID = ChatHistory_GetAccessID(infoType, arg8, arg12) 
			self:AddMessage(tMessagetype, format(globalstring, arg8, SkuChat_ResolvePrefixedChannelName(arg4)), info.r, info.g, info.b, info.id, accessID, typeID) 

		elseif ( type == "BN_INLINE_TOAST_ALERT" ) then
			local globalstring = _G["BN_INLINE_TOAST_"..arg1] 
			if not globalstring then
				GMError(("Missing global string for %q"):format("BN_INLINE_TOAST_"..arg1)) 
				return 
			end

			local message 
			if ( arg1 == "FRIEND_REQUEST" ) then
				message = globalstring 

			elseif ( arg1 == "FRIEND_PENDING" ) then
				message = format(BN_INLINE_TOAST_FRIEND_PENDING, BNGetNumFriendInvites()) 

			elseif ( arg1 == "FRIEND_REMOVED" or arg1 == "BATTLETAG_FRIEND_REMOVED" ) then
				message = format(globalstring, arg2) 

			elseif ( arg1 == "FRIEND_ONLINE" or arg1 == "FRIEND_OFFLINE") then
				local _, accountName, battleTag, _, characterName, _, client = BNGetFriendInfoByID(arg13) 
				if (client and client ~= "") then
					local _, _, battleTag = BNGetFriendInfoByID(arg13) 
					characterName = BNet_GetValidatedCharacterName(characterName, battleTag, client) or "" 
					--local characterNameText = BNet_GetClientEmbeddedTexture(client, 14)..characterName 
					local characterNameText = characterName 
					local linkDisplayText = ("[%s] (%s)"):format(arg2, characterNameText) 
					local playerLink = SkuChat:GetBNPlayerLink(arg2, linkDisplayText, arg13, arg11, SkuChatChat_GetChatCategory(type), 0) 
					message = format(globalstring, playerLink) 
				else
					local linkDisplayText = ("[%s]"):format(arg2) 
					local playerLink = SkuChat:GetBNPlayerLink(arg2, linkDisplayText, arg13, arg11, SkuChatChat_GetChatCategory(type), 0) 
					message = format(globalstring, playerLink) 
				end

			else
				local linkDisplayText = ("[%s]"):format(arg2) 
				local playerLink = SkuChat:GetBNPlayerLink(arg2, linkDisplayText, arg13, arg11, SkuChatChat_GetChatCategory(type), 0) 
				message = format(globalstring, playerLink) 
			end
			self:AddMessage(tMessagetype, message, info.r, info.g, info.b, info.id) 

		elseif ( type == "BN_INLINE_TOAST_BROADCAST" ) then
			if ( arg1 ~= "" ) then
				arg1 = RemoveNewlines(RemoveExtraSpaces(arg1)) 
				local linkDisplayText = ("[%s]"):format(arg2) 
				local playerLink = SkuChat:GetBNPlayerLink(arg2, linkDisplayText, arg13, arg11, SkuChatChat_GetChatCategory(type), 0) 
				self:AddMessage(tMessagetype, format(BN_INLINE_TOAST_BROADCAST, playerLink, arg1), info.r, info.g, info.b, info.id) 
			end

		elseif ( type == "BN_INLINE_TOAST_BROADCAST_INFORM" ) then
			if ( arg1 ~= "" ) then
				arg1 = RemoveExtraSpaces(arg1) 
				self:AddMessage(tMessagetype, BN_INLINE_TOAST_BROADCAST_INFORM, info.r, info.g, info.b, info.id) 
			end

		else
			local body 

			-- Add AFK/DND flags
			local pflag 
			if(arg6 ~= "") then
				if ( arg6 == "GM" ) then
					--If it was a whisper, dispatch it to the GMChat addon.
					if ( type == "WHISPER" ) then
						return 
					end
					--Add Blizzard Icon, this was sent by a GM
					pflag = "Blizzard Gamemaster (approved by Sku): " 
				elseif ( arg6 == "DEV" ) then
					--Add Blizzard Icon, this was sent by a Dev
					pflag = "Blizzard Gamemaster (approved by Sku): " 
				else
					pflag = _G["CHAT_FLAG_"..arg6] 
				end
			else
				pflag = "" 
			end

			if ( type == "WHISPER_INFORM" and GMSkuChat_IsGM and GMSkuChat_IsGM(arg2) ) then
				return 
			end

			local showLink = 1 
			if ( strsub(type, 1, 7) == "MONSTER" or strsub(type, 1, 9) == "RAID_BOSS") then
				showLink = nil 
			else
				arg1 = gsub(arg1, "%%", "%%%%") 
			end

			-- Search for icon links and replace them with texture links.
			arg1 = SkuChat_ReplaceIconAndGroupExpressions(arg1, arg17, not SkuChat_CanChatGroupPerformExpressionExpansion(chatGroup))  -- If arg17 is true, don't convert to raid icons

			--Remove groups of many spaces
			arg1 = RemoveExtraSpaces(arg1) 

			local playerLink 
			local playerLinkDisplayText = coloredName 
			local relevantDefaultLanguage = self.defaultLanguage 

			if ( (type == "SAY") or (type == "YELL") ) then
				relevantDefaultLanguage = self.alternativeDefaultLanguage 
			end

			local usingDifferentLanguage = (arg3 ~= "") and (arg3 ~= relevantDefaultLanguage) 
			local usingEmote = (type == "EMOTE") or (type == "TEXT_EMOTE") 
			if ( usingDifferentLanguage or not usingEmote ) then
				playerLinkDisplayText = ("[%s]"):format(coloredName) 
			end

			local isCommunityType = type == "COMMUNITIES_CHANNEL" 
			local playerName, lineID, bnetIDAccount = arg2, arg11, arg13 
			if ( isCommunityType ) then
				local isBattleNetCommunity = bnetIDAccount ~= nil and bnetIDAccount ~= 0 
				local messageInfo, clubId, streamId, clubType = C_Club.GetInfoFromLastCommunityChatLine() 
				if (messageInfo ~= nil) then
					if ( isBattleNetCommunity ) then
						playerLink = SkuChat:GetBNPlayerCommunityLink(playerName, playerLinkDisplayText, bnetIDAccount, clubId, streamId, messageInfo.messageId.epoch, messageInfo.messageId.position) 
					else
						playerLink = SkuChat:GetPlayerCommunityLink(playerName, playerLinkDisplayText, clubId, streamId, messageInfo.messageId.epoch, messageInfo.messageId.position) 
					end
				else
					playerLink = playerLinkDisplayText 
				end
			else
				if ( type == "BN_WHISPER" or type == "BN_WHISPER_INFORM" ) then
					playerLink = SkuChat:GetBNPlayerLink(playerName, playerLinkDisplayText, bnetIDAccount, lineID, chatGroup, chatTarget) 
				else
					playerLink = SkuChat:GetPlayerLink(playerName, playerLinkDisplayText, lineID, chatGroup, chatTarget) 
				end
			end

			local message = arg1 
			if ( arg14 ) then	--isMobile
				message = SkuChat_GetMobileEmbeddedTexture(info.r, info.g, info.b)..message 
			end

			if ( usingDifferentLanguage ) then
				local languageHeader = "["..arg3.."] " 
				if ( showLink and (arg2 ~= "") ) then
					body = format(_G["CHAT_"..type.."_GET"]..languageHeader..message, pflag..playerLink) 
				else
					body = format(_G["CHAT_"..type.."_GET"]..languageHeader..message, pflag..arg2) 
				end
			else
				if ( not showLink or arg2 == "" ) then
					if ( type == "TEXT_EMOTE" ) then
						body = message 
					else
						body = format(_G["CHAT_"..type.."_GET"]..message, pflag..arg2, arg2) 
					end
				else
					if ( type == "EMOTE" ) then
						body = format(_G["CHAT_"..type.."_GET"]..message, pflag..playerLink) 
					elseif ( type == "TEXT_EMOTE") then
						body = string.gsub(message, arg2, pflag..playerLink, 1) 
					elseif (type == "GUILD_ITEM_LOOTED") then
						body = string.gsub(message, "$s", SkuChat:GetPlayerLink(arg2, playerLinkDisplayText)) 
					else
						body = format(_G["CHAT_"..type.."_GET"]..message, pflag..playerLink) 
					end
				end
			end

			-- Add Channel
			if (channelLength > 0) then
				body = "["..SkuChat_ResolvePrefixedChannelName(arg4).."] "..body
				local tMatched
				local tChannelList = {GetChannelList()}
				for q = 1, C_ChatInfo.GetNumActiveChannels() * 3, 3 do
					if arg8 == tChannelList[q] then
						tMessagetype = tChannelList[q + 1]
						tMatched = true
					end
				end
				-- Zone/server channels (General/Trade/Allgemein/Handel/...) are no
				-- longer returned by GetChannelList() on current clients, so the
				-- lookup above misses them and their per-channel audio setting never
				-- matched. Fall back to channelBaseName (arg9, "the channel name
				-- without the number in front" — see the CHANNEL branch above) for
				-- plain channels; the menu creates the settings entry under that same
				-- base name via EnumerateServerChannels(). Communities/customs keep
				-- their existing GetChannelList-based keying untouched.
				if not tMatched and type == "CHANNEL" and arg9 and arg9 ~= "" then
					tMessagetype = arg9
				end
			end

			--Add Timestamps
			if ( CHAT_TIMESTAMP_FORMAT ) then
				body = BetterDate(CHAT_TIMESTAMP_FORMAT, time())..body 
			end

			local accessID = ChatHistory_GetAccessID(chatGroup, chatTarget) 
			local typeID = ChatHistory_GetAccessID(infoType, chatTarget, arg12 or arg13) 
			self:AddMessage(tMessagetype, body, info.r, info.g, info.b, info.id, accessID, typeID, arg2) 
		end

		if ( type == "WHISPER" or type == "BN_WHISPER" ) then
			--BN_WHISPER FIXME
			--[[
			ChatEdit_SetLastTellTarget(arg2, type) 

			if ( self.tellTimer and (GetTime() > self.tellTimer) ) then
				PlaySound(SOUNDKIT.TELL_MESSAGE) 
			end
			self.tellTimer = GetTime() + CHAT_TELL_ALERT_TIME 
			--FCF_FlashTab(self) 
			FlashClientIcon() 
			]]
		end

		--[[
		if ( not self:IsShown() ) then
			if ( (self == DEFAULT_CHAT_FRAME and info.flashTabOnGeneral) or (self ~= DEFAULT_CHAT_FRAME and info.flashTab) ) then
				if ( not CHAT_OPTIONS.HIDE_FRAME_ALERTS or type == "WHISPER" or type == "BN_WHISPER" ) then	--BN_WHISPER FIXME
					if (not FCFManager_ShouldSuppressMessageFlash(self, chatGroup, chatTarget) ) then
						--FCF_StartAlertFlash(self) 
					end
				end
			end
		end
		]]
		return true 

	elseif ( event == "VOICE_CHAT_CHANNEL_TRANSCRIBING_CHANGED" ) then
		--[[
		local _, isNowTranscribing = ...
		if ( not self.isTranscribing and isNowTranscribing ) then
			SkuChat_DisplaySystemMessage(self, SPEECH_TO_TEXT_STARTED) 
		end
		self.isTranscribing = isNowTranscribing 
		]]
	end

end

--some blizzard helpers
function SkuChat_TimeBreakDown(time)
	local days = floor(time / (60 * 60 * 24)) 
	local hours = floor((time - (days * (60 * 60 * 24))) / (60 * 60)) 
	local minutes = floor((time - (days * (60 * 60 * 24)) - (hours * (60 * 60))) / 60) 
	local seconds = mod(time, 60) 
	return days, hours, minutes, seconds 
end

function SkuChat_DisplayTimePlayed(self, totalTime, levelTime)
	local info = {r = nil, g = nil, b = nil, id = nil}
	local d 
	local h 
	local m 
	local s 
	d, h, m, s = SkuChat_TimeBreakDown(totalTime) 
	local string = format(TIME_PLAYED_TOTAL, format(TIME_DAYHOURMINUTESECOND, d, h, m, s)) 
	self:AddMessage(tMessagetype, string, info.r, info.g, info.b, info.id) 

	d, h, m, s = SkuChat_TimeBreakDown(levelTime) 
	local string = format(TIME_PLAYED_LEVEL, format(TIME_DAYHOURMINUTESECOND, d, h, m, s)) 
	self:AddMessage(tMessagetype, string, info.r, info.g, info.b, info.id) 
end

function SkuChat_DisplayLevelUp(self, level, ...)
	-- Level up
	local info = {r = nil, g = nil, b = nil, id = nil}
	-- Blank arg is numNewPvpTalentSlots (always 0 in Classic).
	local arg2, arg3, arg4, _, arg5, arg6, arg7, arg8, arg9 = ... 
	local string = LEVEL_UP:format(level) 
	self:AddMessage(tMessagetype, string, info.r, info.g, info.b, info.id) 

	if ( arg3 > 0 ) then
		string = LEVEL_UP_HEALTH_MANA:format(arg2, arg3) 
	else
		string = LEVEL_UP_HEALTH:format(arg2) 
	end
	self:AddMessage(tMessagetype, string, info.r, info.g, info.b, info.id) 

	if ( arg4 > 0 ) then
		string = format(GetText("LEVEL_UP_CHAR_POINTS", nil, arg4), arg4) 
		self:AddMessage(tMessagetype, string, info.r, info.g, info.b, info.id) 
	end

	if ( arg5 > 0 ) then
		string = format(LEVEL_UP_STAT, SPELL_STAT1_NAME, arg5) 
		self:AddMessage(tMessagetype, string, info.r, info.g, info.b, info.id) 
	end

	if ( arg6 > 0 ) then
		string = format(LEVEL_UP_STAT, SPELL_STAT2_NAME, arg6) 
		self:AddMessage(tMessagetype, string, info.r, info.g, info.b, info.id) 
	end

	if ( arg7 > 0 ) then
		string = format(LEVEL_UP_STAT, SPELL_STAT3_NAME, arg7) 
		self:AddMessage(tMessagetype, string, info.r, info.g, info.b, info.id) 
	end

	if ( arg8 > 0 ) then
		string = format(LEVEL_UP_STAT, SPELL_STAT4_NAME, arg8) 
		self:AddMessage(tMessagetype, string, info.r, info.g, info.b, info.id) 
	end

	if ( arg9 > 0 ) then
		string = format(LEVEL_UP_STAT, SPELL_STAT5_NAME, arg9) 
		self:AddMessage(tMessagetype, string, info.r, info.g, info.b, info.id) 
	end
end

-- end of blizzards chatframe code
---------------------------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------------
-- start of sku code
--------------------------------------------------------------------------------------------------------------------------------------
-- Moved to SkuUtil (Sku 42 rework, W4 Phase A). Kept as a thin delegating shim
-- so any remaining/external "SkuChat:Unescape" callers keep working unchanged.
function SkuChat:Unescape(str, aChatSpecific)
	return SkuUtil:Unescape(str, aChatSpecific)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuChat:ShortenChannelName(aChannelName)
	if SkuSettings:Sub("SkuChat").chatSettings.shortenChannelNames ~= true then
		return aChannelName
	end

	local tDefaultNames = {
		["WorldDefense".."\]"] = "WD".."]",
		["GuildRecruitment".."\]"] = "GR".."]",
		["LookingForGroup".."\]"] = "LFG".."]",
		["Guild".."\]"] = "G".."]",
		["Party".."\]"] = "P".."]",
		["Raid".."\]"] = "R".."]",
		["\. ".."General".." \- .*"] = ". ".."GEN",
		["\. ".."Trade".." \- .*"] = ". ".."TRADE",
		["\. ".."LocalDefense".." \- .*"] = ". ".."LD",
	}	
	
	for i, v in pairs(tDefaultNames) do
		aChannelName = aChannelName:gsub(i, v)
	end

	return aChannelName
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuChat:GetBNPlayerCommunityLink(aPlayerName)
	return aPlayerName
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuChat:GetPlayerCommunityLink(aPlayerName)
	return aPlayerName
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuChat:GetBNPlayerLink(aPlayerName)
	return aPlayerName
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuChat:GetPlayerLink(aPlayerName)
	local tPlayer, tServer = SkuChat:GetOnlyPlayerName(aPlayerName)
	if tServer and tServer == GetNormalizedRealmName() then
		return tPlayer
	end

	return aPlayerName
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuChat:GetFullPlayerName(aName)
	if not string.find(aName, "-") then
		return aName.."-"..GetNormalizedRealmName() 
	else
		return aName
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuChat:GetOnlyPlayerName(aName)
	if not string.find(aName, "-") then
		return aName
	else
		return aName:match("(.+)-(.*)") 
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuChat:OnDisable()
	-- Real teardown so a disabled SkuChat genuinely goes quiet. The secure toggle
	-- frames (OnSkuChatToggle / OnSkuChatToggleSecureHandler) are deliberately
	-- left alive in _G; we only clear their override bindings. All query/helper
	-- methods (SetEditboxToCustom, GetTTSText, MenuBuilder, etc.) stay defined and
	-- callable while disabled.

	-- 1) Close the chat UI if it is currently open and release the in-chat
	-- navigation bindings (CloseChat itself InCombatLockdown-guards the
	-- SecureHandlerExecute and sets SkuChat.ChatOpen = false). Only call it when
	-- open so we do not play the close sound on an already-closed chat.
	if SkuChat.ChatOpen == true then
		SkuChat:CloseChat()
	end

	-- 2) Drop every AceEvent registration this addon armed (CHAT_MSG_WHISPER,
	-- CHAT_MSG_WHISPER_INFORM, CHAT_MSG_CHANNEL_NOTICE, COMBAT_LOG_EVENT,
	-- PLAYER_ENTERING_WORLD, PLAYER_LOGIN).
	SkuChat:UnregisterAllEvents()

	-- 3) Drop the dispatcher callbacks for the synthetic Sku chat streams.
	SkuDispatcher:UnregisterEventCallback("SKU_COMBATLOG", SkuChat_SkuMessageEventHandler)
	SkuDispatcher:UnregisterEventCallback("SKU_AUDIOLOG", SkuChat_SkuMessageEventHandler)

	-- 4) Clear the SKU_KEY_CHATOPEN override binding on the secure handler frame
	-- so the chat-open key no longer fires. Override bindings can only be changed
	-- out of combat; if we are in combat, leave them (re-enable would re-apply).
	local b = _G["OnSkuChatToggleSecureHandler"]
	if b and SkuState:IsInCombat() ~= true then
		ClearOverrideBindings(b)
	end

	-- Belt-and-braces: make sure the open flag is down.
	SkuChat.ChatOpen = false
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuChat:SetEditboxToSkuChat(aMsg)
	SkuChatEditboxHookFlag = true
	local channelNum, channelName = GetChannelName("SkuChat")
	ChatFrame1EditBox:SetAttribute("channelTarget", channelNum)
	ChatFrame1EditBox:SetAttribute("chatType", "CHANNEL")
	ChatFrame1EditBox:SetText(aMsg)
	ChatEdit_UpdateHeader(ChatFrame1EditBox)
	SkuChatEditboxHookFlag = false
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuChat:GetChannelAccessIdFromChannelName(aName)
	local tChannelList = {GetChannelList()}
	for q = 1, C_ChatInfo.GetNumActiveChannels() * 3, 3 do 
		if tChannelList[q + 1] == aName then
			return tChannelList[q]
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuChat:COMBAT_LOG_EVENT()
	if not CombatLog_OnEvent then return end
	if not Blizzard_CombatLog_CurrentSettings then return end
	local text, r, g, b, a = CombatLog_OnEvent(Blizzard_CombatLog_CurrentSettings, CombatLogGetCurrentEventInfo() );
	if ( text ) then
		SkuDispatcher:TriggerSkuEvent("SKU_COMBATLOG", "COMBATLOG", text)
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- W4 Rework B-step-2: AceEvent registrations used to live in OnInitialize (which
-- runs ONCE per session). To make SkuChat re-armable (runtime on/off), the event
-- registration moved into a re-armable helper that OnEnable calls on EVERY enable.
-- On first load OnEnable runs right after OnInitialize, so first-load behaviour is
-- byte-identical. OnDisable drops these again via UnregisterAllEvents.
function SkuChat:ArmEvents()
	SkuChat:RegisterEvent("PLAYER_ENTERING_WORLD")
	SkuChat:RegisterEvent("PLAYER_LOGIN")
	SkuChat:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")
	SkuChat:RegisterEvent("CHAT_MSG_WHISPER")
	SkuChat:RegisterEvent("CHAT_MSG_WHISPER_INFORM")
	SkuChat:RegisterEvent("COMBAT_LOG_EVENT")

	-- Dispatcher callbacks for the synthetic Sku chat streams (Combat/Audio log
	-- tabs). These are otherwise wired by tab init at PLAYER_ENTERING_WORLD;
	-- re-registering here makes a mid-session re-enable resume them without
	-- rebuilding tabs. RegisterEventCallback is idempotent (skips duplicates).
	SkuDispatcher:RegisterEventCallback("SKU_COMBATLOG", SkuChat_SkuMessageEventHandler)
	SkuDispatcher:RegisterEventCallback("SKU_AUDIOLOG", SkuChat_SkuMessageEventHandler)
end

---------------------------------------------------------------------------------------------------------------------------------------
-- W6-C #36: shared TTS-reading-frame navigation for the SHIFT-UP/DOWN and
-- CTRL-SHIFT-UP/DOWN chat keys. The four blocks were identical except the terminal
-- TTS method; the caller passes the current line datalink text + itemId. (SHIFT-DOWN
-- previously wrote the visibility test as `== false` rather than `not`; identical for
-- a boolean IsVisible().)
local function tSkuChatTtsFrameNav(aTextFull, aItemId, aMethod)
	SkuOptions.currentMenuPosition = SkuOptions.currentMenuPosition or {}
	SkuOptions.currentMenuPosition.textFull = aTextFull
	if SkuOptions.currentMenuPosition.textFull ~= "" then
		local tTextFull = SkuOptions:AddExtraTooltipData(SkuOptions.currentMenuPosition.textFull, aItemId)
		if not SkuOptions.TTS:IsVisible() then
			SkuOptions.TTS:Output(tTextFull, 1000)
		end
		SkuOptions.currentMenuPosition.links = {}
		SkuOptions.currentMenuPosition.linksSelected = 0
		if SkuOptions.TTS:IsAutoRead() == true then
			SkuOptions.TTS:ToggleAutoRead()
			SkuOptions.TTS.AutoReadEventFlag = nil
		end
		SkuOptions.TTS[aMethod](SkuOptions.TTS)
	end
end

function SkuChat:OnInitialize()
	local function CloseChatMenuHelper()
		_G["OnSkuChatToggle"].menuOpen = false
		SkuOptions.Menu = {}
	end

	-- OnSkuChatToggle to actually handle the chat key binds
	tSkuCurrentLineDatalinktTextFirstLine = ""
	tSkuCurrentLineDatalinktTextFull = ""
	tSkuCurrentLineDatalinktItemId = ""
	local a = _G["OnSkuChatToggle"] or CreateFrame("Button", "OnSkuChatToggle", UIParent, "SecureActionButtonTemplate")
	a.timeCounter = 0
	local ttime = 0
	a:SetScript("OnUpdate", function(self, atime)
		self.timeCounter = self.timeCounter + atime
		if self.timeCounter > 5 then
			if SkuSettings:Sub("SkuChat").tabs and SkuSettings:Sub("SkuChat").chatSettings.deleteWhisperTabsAfter > 1 then
				for x = 1, #SkuSettings:Sub("SkuChat").tabs do
					if SkuSettings:Sub("SkuChat").tabs[x] then
						if SkuSettings:Sub("SkuChat").tabs[x].privateMessages and #SkuSettings:Sub("SkuChat").tabs[x].privateMessages > 0 then
							if (SkuSettings:Sub("SkuChat").tabs[x].lastActivityAt or 0) + ((SkuChat.DeleteTabTimes[SkuSettings:Sub("SkuChat").chatSettings.deleteWhisperTabsAfter] * 60)) < time() then
								SkuChat:DeleteTab(x)
							end
						end
					end
				end
			end
			self.timeCounter = 0
		end

		ttime = ttime + atime
		if ttime > 0.1 then
			if SkuOptions.TTS:IsVisible() == true then
				if IsShiftKeyDown() == false and SkuOptions.TTS:IsAutoRead() ~= true then
					if SkuOptions.currentMenuPosition then
						if SkuOptions.currentMenuPosition.textFullInitial then
							SkuOptions.currentMenuPosition.textFull = SkuOptions.currentMenuPosition.textFullInitial
						end
						SkuOptions.currentMenuPosition.textFullInitial = nil
						SkuOptions.currentMenuPosition.links = {}
						SkuOptions.currentMenuPosition.linksSelected = 0
						SkuOptions.currentMenuPosition.currentLinkName = nil
						SkuOptions.currentMenuPosition.linksHistory = nil
					end
		
					SkuOptions.TTS:Output("", -1)
					SkuOptions.TTS:Hide()
				end
			end

			ttime = 0
		end
	end)

	a.menuOpen = false

	a.CloseChat = function(self)
		local tWasOpen = SkuChat.ChatOpen
		SkuChat.ChatOpen = false

		--close the line menu if open
		CloseChatMenuHelper()

		-- Only give the "chat closed" feedback (queue flush + close ping) when
		-- the chat actually was open. The menu calls CloseChat defensively on
		-- every open/close, so playing sound-off2 unconditionally leaked the
		-- chat-close ping into normal menu open/close.
		if tWasOpen then
			SkuOptions.Voice:StopOutputEmptyQueue(true, nil)
			SkuOptions.Voice:OutputString("sound-off2", true, true, 0.2)
		end

		--unbind chat keys
		if SkuState:IsInCombat() ~= true then
			if _G["OnSkuChatToggleSecureHandler"] then
				SecureHandlerExecute(_G["OnSkuChatToggleSecureHandler"], [=[
					if self:GetAttribute("ChatOpen") == true then
						self:ClearBinding(self:GetAttribute("SKU_KEY_CHAT_LINEPREV"))
						self:ClearBinding(self:GetAttribute("SKU_KEY_CHAT_LINENEXT"))
						self:ClearBinding(self:GetAttribute("SKU_KEY_CHAT_TABPREV"))
						self:ClearBinding(self:GetAttribute("SKU_KEY_CHAT_TABNEXT"))
						self:ClearBinding(self:GetAttribute("SKU_KEY_CHAT_LINEMENU"))
						self:ClearBinding(self:GetAttribute("SHIFT-DOWN"))
						self:ClearBinding(self:GetAttribute("SHIFT-UP"))
						self:ClearBinding(self:GetAttribute("CTRL-SHIFT-DOWN"))
						self:ClearBinding(self:GetAttribute("CTRL-SHIFT-UP"))
						self:ClearBinding(self:GetAttribute("ESCAPE"))
						self:SetAttribute("ChatOpen", false)
					end
				]=])
			end
		end
	end

	a.OpenChat = function(self)
		SkuOptions:CloseMenu()
		SkuChat.ChatOpen = true
		SkuOptions.Voice:StopOutputEmptyQueue()
		SkuOptions.Voice:OutputString("sound-on3_1", true, true, 0.2, true)
		if not SkuSettings:Sub("SkuChat").tabs[SkuChat.currentTab] then
			SkuChat.currentTab = 1
		end
		SkuSettings:Sub("SkuChat").tabs[SkuChat.currentTab].historyCurrentLine = 1
		SkuChat:ReadLine(SkuChat.currentTab, SkuSettings:Sub("SkuChat").tabs[SkuChat.currentTab].historyCurrentLine, true)
	end

	-- Helper: löst einen rohen Quest-Link-String ("quest:12345:60") auf
	-- in (firstLine, fullText, questID). Analog dazu, wie Items via
	-- SkuScanningTooltip:SetHyperlink in Tooltip-Text aufgelöst werden,
	-- nur dass für Quests die Tooltip-API auf TBC-Anniversary nicht
	-- zuverlässig funktioniert. Wir gehen daher direkt:
	--   1) eigenes Quest-Log via GetQuestLogTitle / GetQuestLogQuestText
	--   2) Sku-eigene Datenbank (SkuDB.questLookup) als Fallback
	local function tResolveQuestLink(aRaw)
		if not aRaw then return "", "", nil end
		local idStr, lvlStr = aRaw:match("quest:(%d+):(%-?%d+)")
		local questID = tonumber(idStr)
		local level = tonumber(lvlStr) or -1
		if not questID then return "", "", nil end

		local title
		local logIdx -- Quest-Log-Index, falls im Log
		-- 1) eigenes Log: finde Index zur Quest-ID
		if _G.GetNumQuestLogEntries and _G.GetQuestLogTitle then
			local tNum = _G.GetNumQuestLogEntries() or 0
			for i = 1, tNum do
				local t, lvl, _, isHeader, _, _, _, qid = _G.GetQuestLogTitle(i)
				if not isHeader and qid == questID then
					title = t
					if lvl then level = lvl end
					logIdx = i
					break
				end
			end
		end
		-- 2) Fallback-Titel via Sku-Lookup falls nicht im Log
		if (not title or title == "") and SkuDB and SkuDB.questLookup
			and SkuDB.questLookup[Sku.Loc] and SkuDB.questLookup[Sku.Loc][questID] then
			title = SkuDB.questLookup[Sku.Loc][questID][1]
		end
		title = title or ("Quest " .. questID)

		local first = (L["Quest"] or "Quest")
			.. (level and level > 0 and (L[" Stufe "] .. level) or "")
			.. ", " .. title

		-- Bevorzugt: SkuQuest:GetTTSText liefert exakt denselben Volltext,
		-- den der User beim Shift+Pfeil-runter auf einen Quest-Titel im
		-- Questlog hört (Beschreibung + Ziele + Status). Funktioniert
		-- nur, wenn die Quest im aktiven Log ist.
		local full
		if logIdx and SkuQuest and SkuQuest.GetTTSText then
			local ok, txt = pcall(function()
				return SkuQuest:GetTTSText(logIdx)
			end)
			if ok and txt and txt ~= "" then
				full = txt
			end
		end
		-- Fallback (Quest nicht im Log): kompakter Text aus SkuDB
		if not full or full == "" then
			local fullParts = { first }
			if SkuDB and SkuDB.questLookup and SkuDB.questLookup[Sku.Loc]
				and SkuDB.questLookup[Sku.Loc][questID]
				and SkuDB.questLookup[Sku.Loc][questID][3]
				and SkuDB.questLookup[Sku.Loc][questID][3][1] then
				fullParts[#fullParts + 1] = (L["Ziel"] or "Ziel") .. ": "
					.. SkuDB.questLookup[Sku.Loc][questID][3][1]
			end
			fullParts[#fullParts + 1] = "Quest-ID " .. questID
			full = table.concat(fullParts, "\r\n")
		end
		return first, full, questID
	end

	a:SetScript("OnClick", function(self, aKey)
		--handle chat navigation
		local tTextFirstLine, tTextFull = nil, "", ""

		if aKey ~= "SHIFT-UP" and aKey ~= "SHIFT-DOWN" and aKey ~= "CTRL-SHIFT-UP" and aKey ~= "CTRL-SHIFT-DOWN" then
			if SkuOptions.TTS:IsAutoRead() == true then
				SkuOptions.TTS:ToggleAutoRead()
				SkuOptions.Voice:StopOutputEmptyQueue(true, nil)
			end
			if SkuOptions.TTS:IsVisible() then
				SkuOptions.TTS:Hide()
			end
		end

		local tLineData = SkuSettings:Sub("SkuChat").tabs[SkuChat.currentTab].history[SkuSettings:Sub("SkuChat").tabs[SkuChat.currentTab].historyCurrentLine]
		
		if tLineData.itemLinks and #tLineData.itemLinks > 0 and self.menuOpen == false then
			if self.menuOpen == false then
				for w = 1, #tLineData.itemLinks do
					local ltSkuCurrentLineDatalinktTextFirstLine, ltSkuCurrentLineDatalinktTextFull = "", ""
					_G["SkuScanningTooltip"]:SetHyperlink(tLineData.itemLinks[w])

					if TooltipLines_helper(_G["SkuScanningTooltip"]:GetRegions()) ~= "asd" then
						if TooltipLines_helper(_G["SkuScanningTooltip"]:GetRegions()) ~= "" then
							local tText = SkuUtil:Unescape(TooltipLines_helper(_G["SkuScanningTooltip"]:GetRegions()))
							ltSkuCurrentLineDatalinktTextFirstLine, ltSkuCurrentLineDatalinktTextFull = SkuCore:ItemName_helper(tText)
						end
					end
					_G["SkuScanningTooltip"]:ClearLines()

					if ltSkuCurrentLineDatalinktTextFirstLine ~= "" then
						if w == 1 then
							tSkuCurrentLineDatalinktItemId = SkuGetItemIdFromItemLink(tLineData.itemLinks[w])
							tSkuCurrentLineDatalinktTextFirstLine, tSkuCurrentLineDatalinktTextFull = ltSkuCurrentLineDatalinktTextFirstLine, ltSkuCurrentLineDatalinktTextFull
							tSkuCurrentLineDatalinktTextFull = tSkuCurrentLineDatalinktTextFirstLine.."\r\n"..tSkuCurrentLineDatalinktTextFull

							local ttf = SkuCore.AuctionHouse:AuctionHouseGetAuctionPriceHistoryData(tSkuCurrentLineDatalinktItemId)
							if not ttf then
								ttf = {}
							end
							local tFull = tSkuCurrentLineDatalinktTextFull
							if type(ttf) ~= "table" then
								ttf = { (ttf or tSkuCurrentLineDatalinktTextFirstLine or ""), }
							end
							table.insert(ttf, 1, tFull)
							SkuCore:InsertComparisnSections(tSkuCurrentLineDatalinktItemId, ttf)
							tSkuCurrentLineDatalinktTextFull = ttf
						end
					end
				end
			end
		end

		-- Quest-Links aus dem Chat — analog zu itemLinks. Statt
		-- SkuScanningTooltip nutzen wir tResolveQuestLink (Quest-API
		-- bzw. SkuDB.questLookup), weil Tooltip:SetHyperlink für Quests
		-- auf TBC-Anniversary keinen brauchbaren Inhalt liefert.
		if tLineData.questLinks and #tLineData.questLinks > 0 and self.menuOpen == false then
			for w = 1, #tLineData.questLinks do
				local qFirst, qFull, qID = tResolveQuestLink(tLineData.questLinks[w])
				if qFirst and qFirst ~= "" and w == 1 then
					-- Wir landen hier nur dann, wenn die Zeile keinen
					-- Item-Link hatte (sonst hat oben bereits Item-Daten
					-- die Variablen befüllt). Falls beides existiert,
					-- gewinnt der Item-Link analog zur Vorlagenlogik.
					if not tSkuCurrentLineDatalinktTextFirstLine
						or tSkuCurrentLineDatalinktTextFirstLine == "" then
						tSkuCurrentLineDatalinktTextFirstLine = qFirst
						tSkuCurrentLineDatalinktTextFull = qFull
						tSkuCurrentLineDatalinktItemId = nil
					end
				end
			end
		end

		if self.menuOpen == false or (aKey == "SHIFT-UP" or aKey == "SHIFT-DOWN" or  aKey == "CTRL-SHIFT-UP" or aKey == "CTRL-SHIFT-DOWN") then
			if aKey == "CTRL-ENTER" then
				--build/open the line menu
				self.menuOpen = true
				SkuOptions.Menu = {}

				local tLineData = SkuSettings:Sub("SkuChat").tabs[SkuChat.currentTab].history[SkuSettings:Sub("SkuChat").tabs[SkuChat.currentTab].historyCurrentLine]

				--send
				local tAccessID
				if tLineData.messageTypeGroup == "CHANNEL" then
					_, tAccessID = ChatHistory_GetChatType(tLineData.accessID)
				end
				if not tAccessID then
					tAccessID = SkuChat:GetChannelAccessIdFromChannelName(tLineData.messageTypeGroup)
				end

				--[[
				--start route
				local _, _, _, tWpName = string.find(tLineData.body, "(.+)".."#"..L["Waypoint"]..":".."(.+)")
				if tWpName then
					local tWpObj = SkuNav:GetWaypointData2(tWpName)
					if tWpObj then
						local tNewMenuEntry = SkuOptions:InjectMenuItems(SkuOptions.Menu, {L["Start route to waypoint"]}, SkuGenericMenuItem)
						tNewMenuEntry.isSelect = true
						tNewMenuEntry.OnAction = function(self)
							--print("tWpName", tWpName)
							

							C_Timer.After(0.01, function() CloseChatMenuHelper() end)
						end
					end
				end
				]]

				--
				local tLineDataitemLinks = tLineData.itemLinks
				if tLineDataitemLinks and #tLineDataitemLinks > 0 then
					for w = 1, #tLineDataitemLinks do
						local ltSkuCurrentLineDatalinktTextFirstLine, ltSkuCurrentLineDatalinktTextFull = "", ""
						local ltSkuCurrentLineDatalinktItemId = ""
						_G["SkuScanningTooltip"]:SetHyperlink(tLineDataitemLinks[w])

						if TooltipLines_helper(_G["SkuScanningTooltip"]:GetRegions()) ~= "asd" then
							if TooltipLines_helper(_G["SkuScanningTooltip"]:GetRegions()) ~= "" then
								local tText = SkuUtil:Unescape(TooltipLines_helper(_G["SkuScanningTooltip"]:GetRegions()))
								ltSkuCurrentLineDatalinktTextFirstLine, ltSkuCurrentLineDatalinktTextFull = SkuCore:ItemName_helper(tText)
							end
						end
						_G["SkuScanningTooltip"]:ClearLines()
						if ltSkuCurrentLineDatalinktTextFirstLine ~= "" then
							local tNewMenuEntry = SkuOptions:InjectMenuItems(SkuOptions.Menu, {L["link"].." "..w.." "..ltSkuCurrentLineDatalinktTextFirstLine}, SkuGenericMenuItem)
							tNewMenuEntry.tSkuCurrentLineDatalinktTextFirstLine = ltSkuCurrentLineDatalinktTextFirstLine
							tNewMenuEntry.tSkuCurrentLineDatalinktItemId = SkuGetItemIdFromItemLink(tLineDataitemLinks[w])
							local ttf = SkuCore.AuctionHouse:AuctionHouseGetAuctionPriceHistoryData(tNewMenuEntry.tSkuCurrentLineDatalinktItemId)
							if not ttf then
								ttf = {}
							end
							local tFull = ltSkuCurrentLineDatalinktTextFull
							if type(ttf) ~= "table" then
								ttf = { (ttf or tSkuCurrentLineDatalinktTextFirstLine or ""), }
							end
							table.insert(ttf, 1, tFull)
							SkuCore:InsertComparisnSections(tNewMenuEntry.tSkuCurrentLineDatalinktItemId, ttf)
							tNewMenuEntry.tSkuCurrentLineDatalinktTextFull = ttf
							tNewMenuEntry.OnEnter = function(self, aValue, aName)
								tSkuCurrentLineDatalinktTextFirstLine, tSkuCurrentLineDatalinktTextFull = self.tSkuCurrentLineDatalinktTextFirstLine, self.tSkuCurrentLineDatalinktTextFull
								tSkuCurrentLineDatalinktItemId = self.tSkuCurrentLineDatalinktItemId
							end

							if w == 1 then
								tSkuCurrentLineDatalinktTextFirstLine, tSkuCurrentLineDatalinktTextFull = ltSkuCurrentLineDatalinktTextFirstLine, ttf
								tSkuCurrentLineDatalinktItemId = SkuGetItemIdFromItemLink(tLineDataitemLinks[w])
							end
						end
					end
				end

				-- Quest-Links als Menü-Einträge — analog zu Items.
				-- Kein Untermenü/Aufklappen — die Einträge sind Blätter
				-- mit textFirstLine/textFull, sodass beim Anwählen exakt
				-- derselbe TTS-Text vorgelesen wird, den der Nutzer auch
				-- im Questlog beim Shift+Pfeil-runter auf dem Quest-Titel
				-- hört (siehe tResolveQuestLink: nutzt SkuQuest:GetTTSText
				-- wenn die Quest im Log ist).
				local tLineDataquestLinks = tLineData.questLinks
				if tLineDataquestLinks and #tLineDataquestLinks > 0 then
					for w = 1, #tLineDataquestLinks do
						local qFirst, qFull, qID = tResolveQuestLink(tLineDataquestLinks[w])
						if qFirst and qFirst ~= "" then
							local tLabel = (L["link"] or "Link") .. " " .. ((#tLineData.itemLinks or 0) + w)
								.. " " .. qFirst
							local tNewMenuEntry = SkuOptions:InjectMenuItems(SkuOptions.Menu, {tLabel}, SkuGenericMenuItem)
							tNewMenuEntry.tSkuCurrentLineDatalinktTextFirstLine = qFirst
							tNewMenuEntry.tSkuCurrentLineDatalinktTextFull = qFull
							tNewMenuEntry.tSkuCurrentLineDatalinktItemId = nil
							tNewMenuEntry.OnEnter = function(self, aValue, aName)
								tSkuCurrentLineDatalinktTextFirstLine = self.tSkuCurrentLineDatalinktTextFirstLine
								tSkuCurrentLineDatalinktTextFull = self.tSkuCurrentLineDatalinktTextFull
								tSkuCurrentLineDatalinktItemId = nil
							end
							if w == 1 and (not tLineData.itemLinks or #tLineData.itemLinks == 0) then
								tSkuCurrentLineDatalinktTextFirstLine = qFirst
								tSkuCurrentLineDatalinktTextFull = qFull
								tSkuCurrentLineDatalinktItemId = nil
							end
						end
					end
				end


				--
				local tNewMenuEntry = SkuOptions:InjectMenuItems(SkuOptions.Menu, {L["send to channel"]}, SkuGenericMenuItem)
				tNewMenuEntry.OnEnter = function(self, aValue, aName)
					tSkuCurrentLineDatalinktTextFirstLine, tSkuCurrentLineDatalinktTextFull, tSkuCurrentLineDatalinktItemId = "", "", ""
				end
				tNewMenuEntry.isSelect = true
				tNewMenuEntry.OnAction = function(self)
					if tAccessID then
						SkuChat:SetEditboxToCustom("CHANNEL", tAccessID, "")
						C_Timer.After(0.01, function() CloseChatMenuHelper() end)
					elseif tLineData.messageTypeGroup then
						SkuChat:SetEditboxToCustom(tLineData.messageTypeGroup)
						C_Timer.After(0.01, function() CloseChatMenuHelper() end)
					end
				end

				local tNewMenuEntry = SkuOptions:InjectMenuItems(SkuOptions.Menu, {L["send item link to channel"]}, SkuGenericMenuItem)
				tNewMenuEntry.OnEnter = function(self, aValue, aName)
					tSkuCurrentLineDatalinktTextFirstLine, tSkuCurrentLineDatalinktTextFull, tSkuCurrentLineDatalinktItemId = "", "", ""
				end
				tNewMenuEntry.dynamic = true
				tNewMenuEntry.BuildChildren = function(self)
					local tBagSlotListSorted = {
						[1] = 0,
						[2] = 1,
						[3] = 2,
						[4] = 3,
						[5] = 4,
						[6] = -1,
						[7] = 5,
						[8] = 6,
						[9] = 7,
						[10] = 8,
						[11] = 9,
						[12] = 10,
						[13] = 11,
						[14] = -2,
						[15] = -3,
					}
					local allBagResults = {}
					for q = 1, #tBagSlotListSorted do
						local bagId = tBagSlotListSorted[q]
						local tNumSlots = GetContainerNumSlots(bagId)
						for slotId = 1, tNumSlots do
							local icon, itemCount, locked, quality, readable, lootable, itemLink, isFiltered, noValue, itemID, isBound = GetContainerItemInfo(bagId, slotId)
							if itemLink then
								local tNewMenuEntryItem = SkuOptions:InjectMenuItems(self, {SkuUtil:Unescape(itemLink).." ("..L["Bag"]..")"}, SkuGenericMenuItem)
								tNewMenuEntryItem.OnAction = function(self, a, b)
									if tAccessID then
										SkuChat:SetEditboxToCustom("CHANNEL", tAccessID, itemLink)
										C_Timer.After(0.01, function() CloseChatMenuHelper() end)
									elseif tLineData.messageTypeGroup then
										SkuChat:SetEditboxToCustom(tLineData.messageTypeGroup, nil, itemLink)
										C_Timer.After(0.01, function() CloseChatMenuHelper() end)
									end
								end					
		
							end
						end  
					end
					for slotId = 1, 40 do
						local itemLink = GetInventoryItemLink("player", slotId)
						if itemLink then
							local tNewMenuEntryItem = SkuOptions:InjectMenuItems(self, {SkuUtil:Unescape(itemLink).." ("..L["Equipped"]..")"}, SkuGenericMenuItem)
							tNewMenuEntryItem.OnAction = function(self, a, b)
								if tAccessID then
									SkuChat:SetEditboxToCustom("CHANNEL", tAccessID, itemLink)
									C_Timer.After(0.01, function() CloseChatMenuHelper() end)
								elseif tLineData.messageTypeGroup then
									SkuChat:SetEditboxToCustom(tLineData.messageTypeGroup, nil, itemLink)
									C_Timer.After(0.01, function() CloseChatMenuHelper() end)
								end
							end					
						end
					end  
				end

				--whisper
				if tLineData.arg2 then
					local tNewMenuEntry = SkuOptions:InjectMenuItems(SkuOptions.Menu, {L["whisper sender"]}, SkuGenericMenuItem)
					tNewMenuEntry.OnEnter = function(self, aValue, aName)
						tSkuCurrentLineDatalinktTextFirstLine, tSkuCurrentLineDatalinktTextFull, tSkuCurrentLineDatalinktItemId = "", "", ""
					end
						tNewMenuEntry.isSelect = true
					tNewMenuEntry.OnAction = function(self)
						if tLineData.messageTypeGroup ~= "BN_WHISPER" then
							SkuChat:SetEditboxToCustom("WHISPER", MaskBattleNetNames(tLineData.arg2), "")
						else
							SkuChat:SetEditboxToCustom(tLineData.messageTypeGroup, MaskBattleNetNames(tLineData.arg2), "")
						end
						C_Timer.After(0.01, function() CloseChatMenuHelper() end)
					end
				end
	
				--invite
				if tLineData.arg2 then
					local tNewMenuEntry = SkuOptions:InjectMenuItems(SkuOptions.Menu, {L["invite sender"]}, SkuGenericMenuItem)
					tNewMenuEntry.OnEnter = function(self, aValue, aName)
						tSkuCurrentLineDatalinktTextFirstLine, tSkuCurrentLineDatalinktTextFull, tSkuCurrentLineDatalinktItemId = "", "", ""
					end
						tNewMenuEntry.isSelect = true
					tNewMenuEntry.OnAction = function(self)
						if _G.C_PartyInfo and _G.C_PartyInfo.InviteUnit then
							C_PartyInfo.InviteUnit(MaskBattleNetNames(tLineData.arg2))
						elseif _G.InviteUnit then
							InviteUnit(MaskBattleNetNames(tLineData.arg2))
						end
						C_Timer.After(0.01, function() CloseChatMenuHelper() end)
					end
				end

				--spellout name/message






				--copy sender name
				if tLineData.arg2 then
					local tNewMenuEntry = SkuOptions:InjectMenuItems(SkuOptions.Menu, {L["copy sender name"]}, SkuGenericMenuItem)
					tNewMenuEntry.OnEnter = function(self, aValue, aName)
						tSkuCurrentLineDatalinktTextFirstLine, tSkuCurrentLineDatalinktTextFull, tSkuCurrentLineDatalinktItemId = "", "", ""
					end
						tNewMenuEntry.isSelect = true
					tNewMenuEntry.OnAction = function(self)
						PlaySound(88)
						SkuOptions.Voice:OutputStringBTtts(L["Copy text with control plus C and press escape"], true, true, 0.2, nil, nil, nil, 2)
						SkuOptions:EditBoxShow(SkuChat:GetOnlyPlayerName(MaskBattleNetNames(tLineData.arg2)), function(self)
							PlaySound(89)
						end)					
						C_Timer.After(0.01, function() CloseChatMenuHelper() end)
					end
				end

				--copy line
				local tNewMenuEntry = SkuOptions:InjectMenuItems(SkuOptions.Menu, {L["copy chat line"]}, SkuGenericMenuItem)
				tNewMenuEntry.OnEnter = function(self, aValue, aName)
					tSkuCurrentLineDatalinktTextFirstLine, tSkuCurrentLineDatalinktTextFull, tSkuCurrentLineDatalinktItemId = "", "", ""
				end
				tNewMenuEntry.isSelect = true
				tNewMenuEntry.OnAction = function(self)
					PlaySound(88)
					SkuOptions.Voice:OutputStringBTtts(L["Copy text with control plus C and press escape"], true, true, 0.2, nil, nil, nil, 2)
					SkuOptions:EditBoxShow(MaskBattleNetNames(tLineData.body), function(self)
						PlaySound(89)
					end)					
					C_Timer.After(0.01, function() CloseChatMenuHelper() end)
				end

				--copy all lines
				local tNewMenuEntry = SkuOptions:InjectMenuItems(SkuOptions.Menu, {L["copy all chat lines"]}, SkuGenericMenuItem)
				tNewMenuEntry.OnEnter = function(self, aValue, aName)
					tSkuCurrentLineDatalinktTextFirstLine, tSkuCurrentLineDatalinktTextFull, tSkuCurrentLineDatalinktItemId = "", "", ""
				end
				tNewMenuEntry.isSelect = true
				tNewMenuEntry.OnAction = function(self)
					PlaySound(88)
					SkuOptions.Voice:OutputStringBTtts(L["Copy text with control plus C and press escape"], true, true, 0.2, nil, nil, nil, 2)
					local tText = ""
					for line = 1, #SkuSettings:Sub("SkuChat").tabs[SkuChat.currentTab].history do
						tText = tText..SkuSettings:Sub("SkuChat").tabs[SkuChat.currentTab].history[line].body.."\r\n"
					end
					SkuOptions:EditBoxShow(tText, function(self)
						PlaySound(89)
					end)					
					C_Timer.After(0.01, function() CloseChatMenuHelper() end)
				end

				--target








				--add friend
				if tLineData.arg2 then
					local tNewMenuEntry = SkuOptions:InjectMenuItems(SkuOptions.Menu, {L["add sender to friend list"]}, SkuGenericMenuItem)
					tNewMenuEntry.OnEnter = function(self, aValue, aName)
						tSkuCurrentLineDatalinktTextFirstLine, tSkuCurrentLineDatalinktTextFull, tSkuCurrentLineDatalinktItemId = "", "", ""
					end
						tNewMenuEntry.isSelect = true
					tNewMenuEntry.OnAction = function(self)
						PlaySound(88)
						SkuOptions.Voice:OutputStringBTtts(L["Notiz eingeben und Enter drücken"], true, true, 0.2, nil, nil, nil, 2)
						SkuOptions:EditBoxShow("", function(self)
							if tLineData.arg2 and self:GetText() then
								C_FriendList.AddFriend(tLineData.arg2, self:GetText())
							end
							PlaySound(89)
						end)					
						C_Timer.After(0.01, function() CloseChatMenuHelper() end)
					end
				end			

				--ignore
				if tLineData.arg2 then
					local tNewMenuEntry = SkuOptions:InjectMenuItems(SkuOptions.Menu, {L["ignore sender"]}, SkuGenericMenuItem)
					tNewMenuEntry.OnEnter = function(self, aValue, aName)
						tSkuCurrentLineDatalinktTextFirstLine, tSkuCurrentLineDatalinktTextFull, tSkuCurrentLineDatalinktItemId = "", "", ""
					end
						tNewMenuEntry.isSelect = true
					tNewMenuEntry.OnAction = function(self)
						PlaySound(88)
						if tLineData.arg2 then
							C_FriendList.AddIgnore(tLineData.arg2)
						end
						C_Timer.After(0.01, function() CloseChatMenuHelper() end)
					end
				end	

				local tNewMenuEntry = SkuOptions:InjectMenuItems(SkuOptions.Menu, {L["Clear history"]}, SkuGenericMenuItem)
				tNewMenuEntry.OnEnter = function(self, aValue, aName)
					tSkuCurrentLineDatalinktTextFirstLine, tSkuCurrentLineDatalinktTextFull, tSkuCurrentLineDatalinktItemId = "", "", ""
				end
				tNewMenuEntry.isSelect = true
				tNewMenuEntry.OnAction = function(self)
					PlaySound(88)
					SkuSettings:Sub("SkuChat").tabs[SkuChat.currentTab].history = {}
					table.insert(SkuSettings:Sub("SkuChat").tabs[SkuChat.currentTab].history, 1, {
						body = L["Empty"], 
						messageTypeGroup = "SAY", 
						audio = false, 
						accessID = nil, 
						typeID = nil, 
						arg2 = nil, 
						time = time(),
					})					
				C_Timer.After(0.01, function() CloseChatMenuHelper() end)
				end

				local tNewMenuEntry = SkuOptions:InjectMenuItems(SkuOptions.Menu, {L["Delete tab"]}, SkuGenericMenuItem)
				tNewMenuEntry.OnEnter = function(self, aValue, aName)
					tSkuCurrentLineDatalinktTextFirstLine, tSkuCurrentLineDatalinktTextFull, tSkuCurrentLineDatalinktItemId = "", "", ""
				end
				tNewMenuEntry.isSelect = true
				tNewMenuEntry.OnAction = function(self)
					PlaySound(88)
					SkuChat:DeleteTab(SkuChat.currentTab)
					C_Timer.After(0.01, function() CloseChatMenuHelper() end)
				end

				SkuOptions.currentMenuPosition = SkuOptions.Menu[1]
				SkuOptions.Voice:OutputStringBTtts(SkuOptions.Menu[1].name, true, true, 0.3, nil, nil, nil, 2)

			--more chat/tab navigation







			elseif aKey ==  "SHIFT-UP" then
				tSkuChatTtsFrameNav(tSkuCurrentLineDatalinktTextFull, tSkuCurrentLineDatalinktItemId, "PreviousLine")
			
			elseif aKey ==  "SHIFT-DOWN" then
				tSkuChatTtsFrameNav(tSkuCurrentLineDatalinktTextFull, tSkuCurrentLineDatalinktItemId, "NextLine")
			
			elseif aKey ==  "CTRL-SHIFT-UP" then
				tSkuChatTtsFrameNav(tSkuCurrentLineDatalinktTextFull, tSkuCurrentLineDatalinktItemId, "PreviousSection")
			
			elseif aKey ==  "CTRL-SHIFT-DOWN" then
				tSkuChatTtsFrameNav(tSkuCurrentLineDatalinktTextFull, tSkuCurrentLineDatalinktItemId, "NextSection")
			
			elseif aKey == "UP" then
			--elseif aKey == SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_CHAT_LINEPREV"].key then
			local tHistoryCurrentLine = SkuSettings:Sub("SkuChat").tabs[SkuChat.currentTab].historyCurrentLine
				if tHistoryCurrentLine > 1 then
					SkuSettings:Sub("SkuChat").tabs[SkuChat.currentTab].historyCurrentLine = tHistoryCurrentLine - 1
				end
				SkuChat:ReadLine(SkuChat.currentTab, SkuSettings:Sub("SkuChat").tabs[SkuChat.currentTab].historyCurrentLine)
				tClearLinkReadoutIfNoLinks(self)

			elseif aKey == "DOWN" then
				local tHistoryCurrentLine = SkuSettings:Sub("SkuChat").tabs[SkuChat.currentTab].historyCurrentLine
				if tHistoryCurrentLine < #SkuSettings:Sub("SkuChat").tabs[SkuChat.currentTab].history then
					SkuSettings:Sub("SkuChat").tabs[SkuChat.currentTab].historyCurrentLine = tHistoryCurrentLine + 1
				end
				SkuChat:ReadLine(SkuChat.currentTab, SkuSettings:Sub("SkuChat").tabs[SkuChat.currentTab].historyCurrentLine)
				tClearLinkReadoutIfNoLinks(self)

			elseif aKey == "LEFT" then
				if SkuChat.currentTab > 1 then
					SkuChat.currentTab = SkuChat.currentTab - 1
				else
					SkuChat.currentTab = #SkuSettings:Sub("SkuChat").tabs
				end
				if SkuSettings:Sub("SkuChat").chatSettings.firstLineOnTabSwitch == true then
					SkuSettings:Sub("SkuChat").tabs[SkuChat.currentTab].historyCurrentLine = 1
				end
				SkuChat:ReadLine(SkuChat.currentTab, SkuSettings:Sub("SkuChat").tabs[SkuChat.currentTab].historyCurrentLine, true)
				tClearLinkReadoutIfNoLinks(self)

			elseif aKey == "RIGHT" then
				if SkuChat.currentTab < #SkuSettings:Sub("SkuChat").tabs then
					SkuChat.currentTab = SkuChat.currentTab + 1
				else
					SkuChat.currentTab = 1
				end
				if SkuSettings:Sub("SkuChat").chatSettings.firstLineOnTabSwitch == true then
					SkuSettings:Sub("SkuChat").tabs[SkuChat.currentTab].historyCurrentLine = 1
				end
				SkuChat:ReadLine(SkuChat.currentTab, SkuSettings:Sub("SkuChat").tabs[SkuChat.currentTab].historyCurrentLine, true)
				tClearLinkReadoutIfNoLinks(self)

			end

		--handle menu navigation			
		else
			--if user is leaving the line menu with SKU_KEY_CHAT_TABPREV
			if aKey == "LEFT" and self.menuOpen == true then
				CloseChatMenuHelper()
				SkuChat:ReadLine(SkuChat.currentTab, SkuSettings:Sub("SkuChat").tabs[SkuChat.currentTab].historyCurrentLine)
			end

			--more menu navigation
			if self.menuOpen == true then
				if aKey == "RIGHT" then
					SkuOptions.currentMenuPosition:OnSelect()
					SkuOptions:VocalizeCurrentMenuName(true)
				end
				if aKey == "UP" then
					SkuOptions.currentMenuPosition:OnPrev()
					SkuOptions:VocalizeCurrentMenuName(true)
				end
				if aKey == "DOWN" then
					SkuOptions.currentMenuPosition:OnNext()
					SkuOptions:VocalizeCurrentMenuName(true)
				end
				--menu entry selected
				if aKey == "CTRL-ENTER" then
					SkuOptions.currentMenuPosition:OnAction()
				end

			end
		end

	end)
end

---------------------------------------------------------------------------------------------------------------------------------------
--this is just a wrapper for external use
function SkuChat:CloseChat()
	if not _G["OnSkuChatToggle"] then
		return
	end
	_G["OnSkuChatToggle"]:CloseChat(_G["OnSkuChatToggle"])
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuChat:OnEnable()
	-- (Re-)arm all WoW/dispatcher event registrations. On first load this runs
	-- right after OnInitialize; on a mid-session re-enable it restores the
	-- registrations that OnDisable dropped.
	SkuChat:ArmEvents()

	-- W6-B #12: hand the audio engine (SkuVoice) a provider for the Blizzard-TTS
	-- params instead of letting it read our settings schema by string key. We
	-- return our live profile subtable (same values as before), so SkuChat can
	-- rename/restructure those keys freely behind this closure without touching
	-- SkuVoice.
	if SkuOptions.Voice and SkuOptions.Voice.SetChatTtsProvider then
		SkuOptions.Voice:SetChatTtsProvider(function() return SkuSettings:Sub("SkuChat") end)
	end

	--we need a secure handler to use setbindingclick/ClearBinding IC
	local b = _G["OnSkuChatToggleSecureHandler"] or CreateFrame("Button", "OnSkuChatToggleSecureHandler", UIParent, "SecureHandlerClickTemplate")
	b:SetFrameRef("OnSkuChatToggle", OnSkuChatToggle)
	b:SetAttribute("_onclick", [=[
		if self:GetAttribute("ChatOpen") ~= true then
			self:GetFrameRef("OnSkuChatToggle"):CallMethod("OpenChat")
			self:SetBindingClick(true, self:GetAttribute("SKU_KEY_CHAT_LINEPREV"), "OnSkuChatToggle", self:GetAttribute("SKU_KEY_CHAT_LINEPREV"))
			self:SetBindingClick(true, self:GetAttribute("SKU_KEY_CHAT_LINENEXT"), "OnSkuChatToggle", self:GetAttribute("SKU_KEY_CHAT_LINENEXT"))
			self:SetBindingClick(true, self:GetAttribute("SKU_KEY_CHAT_TABPREV"), "OnSkuChatToggle", self:GetAttribute("SKU_KEY_CHAT_TABPREV"))
			self:SetBindingClick(true, self:GetAttribute("SKU_KEY_CHAT_TABNEXT"), "OnSkuChatToggle", self:GetAttribute("SKU_KEY_CHAT_TABNEXT"))
			self:SetBindingClick(true, self:GetAttribute("SKU_KEY_CHAT_LINEMENU"), "OnSkuChatToggle", self:GetAttribute("SKU_KEY_CHAT_LINEMENU"))
			self:SetBindingClick(true, self:GetAttribute("SHIFT-DOWN"), "OnSkuChatToggle", self:GetAttribute("SHIFT-DOWN"))
			self:SetBindingClick(true, self:GetAttribute("SHIFT-UP"), "OnSkuChatToggle", self:GetAttribute("SHIFT-UP"))
			self:SetBindingClick(true, self:GetAttribute("CTRL-SHIFT-DOWN"), "OnSkuChatToggle", self:GetAttribute("CTRL-SHIFT-DOWN"))
			self:SetBindingClick(true, self:GetAttribute("CTRL-SHIFT-UP"), "OnSkuChatToggle", self:GetAttribute("CTRL-SHIFT-UP"))
			self:SetBindingClick(true, self:GetAttribute("ESCAPE"), "OnSkuChatToggleSecureHandler", self:GetAttribute("ESCAPE"))
			self:SetAttribute("ChatOpen", true)
		else
			self:GetFrameRef("OnSkuChatToggle"):CallMethod("CloseChat")
			if self:GetAttribute("ChatOpen") == true then
				self:ClearBinding(self:GetAttribute("SKU_KEY_CHAT_LINEPREV"))
				self:ClearBinding(self:GetAttribute("SKU_KEY_CHAT_LINENEXT"))
				self:ClearBinding(self:GetAttribute("SKU_KEY_CHAT_TABPREV"))
				self:ClearBinding(self:GetAttribute("SKU_KEY_CHAT_TABNEXT"))
				self:ClearBinding(self:GetAttribute("SKU_KEY_CHAT_LINEMENU"))
				self:ClearBinding(self:GetAttribute("SHIFT-DOWN"))
				self:ClearBinding(self:GetAttribute("SHIFT-UP"))
				self:ClearBinding(self:GetAttribute("CTRL-SHIFT-DOWN"))
				self:ClearBinding(self:GetAttribute("CTRL-SHIFT-UP"))
				self:ClearBinding(self:GetAttribute("ESCAPE"))
				self:SetAttribute("ChatOpen", false)
			end
		end
	]=])
	b:SetSize(1, 1)
	b:SetPoint("CENTER", -10, 10)
	b:Hide()

	-- attributes with button names for SetBindingClick. can only be updated ooc
	b:SetAttribute("SKU_KEY_CHAT_LINEPREV", "UP")
	b:SetAttribute("SKU_KEY_CHAT_LINENEXT", "DOWN")
	b:SetAttribute("SKU_KEY_CHAT_TABPREV", "LEFT")
	b:SetAttribute("SKU_KEY_CHAT_TABNEXT", "RIGHT")
	b:SetAttribute("SKU_KEY_CHAT_LINEMENU", "CTRL-ENTER")
	b:SetAttribute("SHIFT-DOWN", "SHIFT-DOWN")
	b:SetAttribute("SHIFT-UP", "SHIFT-UP")
	b:SetAttribute("CTRL-SHIFT-DOWN", "CTRL-SHIFT-DOWN")
	b:SetAttribute("CTRL-SHIFT-UP", "CTRL-SHIFT-UP")
	b:SetAttribute("ESCAPE", "ESCAPE")
	b:SetAttribute("ChatOpen", false)

	SetOverrideBindingClick(b, true, SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_CHATOPEN"].key, b:GetName(), SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_CHATOPEN"].key)
	if SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_CHATOPEN"].key2 and SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_CHATOPEN"].key2 ~= "" then SetOverrideBindingClick(b, true, SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_CHATOPEN"].key2, b:GetName(), SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_CHATOPEN"].key2) end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuChat:ReadLine(aTab, aLine, aReadTabName)
	if not SkuSettings:Sub("SkuChat").tabs[aTab] then
		return
	end
	if not SkuSettings:Sub("SkuChat").tabs[aTab].history[aLine] then
		return
	end
	
	local tLineText = SkuSettings:Sub("SkuChat").tabs[aTab].history[aLine].body

	if SkuSettings:Sub("SkuChat").chatSettings.addLineNumbers == true then
		tLineText =  aLine.." "..tLineText
	end

	if SkuSettings:Sub("SkuChat").chatSettings.timeStamp > 1 then
		if SkuSettings:Sub("SkuChat").chatSettings.timeStampAtLineEnd == true then
			tLineText =  tLineText..", "..BetterDate(SkuChat.timeStampFormats[SkuSettings:Sub("SkuChat").chatSettings.timeStamp], SkuSettings:Sub("SkuChat").tabs[aTab].history[aLine].time or time())
		else
			tLineText =  BetterDate(SkuChat.timeStampFormats[SkuSettings:Sub("SkuChat").chatSettings.timeStamp], SkuSettings:Sub("SkuChat").tabs[aTab].history[aLine].time or time())..", "..tLineText
		end
	end

	if aReadTabName then
		tLineText = SkuSettings:Sub("SkuChat").tabs[aTab].name..", "..(tLineText or "")
	end

	if tLineText then
		SkuOptions.Voice:OutputStringBTtts(tLineText, true, true, 0.3, nil, nil, nil, 2)
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuChat:NewWhisperTab(aType, ...)
	if SkuSettings:Sub("SkuChat").chatSettings.openWhispersInNewTab == true then
		local event, text, playerName, languageName, channelName, playerName2, specialFlags, zoneChannelID, channelIndex, channelBaseName, languageID, lineID, guid, bnSenderID, isMobile, isSubtitle, hideSenderInLetterbox, supressRaidIcons = ...

		--print("NewWhisperTab", aType, event, text, playerName, languageName, channelName, playerName2, specialFlags, zoneChannelID, channelIndex, channelBaseName, languageID, lineID, guid, bnSenderID, isMobile, isSubtitle, hideSenderInLetterbox, supressRaidIcons)

		playerName = SkuChat:GetFullPlayerName(playerName)
		playerName2 = SkuChat:GetFullPlayerName(playerName2)

		local tSender = playerName
		if aType == "INFORM" then
			tSender = playerName2
		end

		local tTabNumber 
		for z = 1, #SkuSettings:Sub("SkuChat").tabs do
			if SkuSettings:Sub("SkuChat").tabs[z].privateMessages then
				for x = 1, #SkuSettings:Sub("SkuChat").tabs[z].privateMessages do
					if SkuSettings:Sub("SkuChat").tabs[z].privateMessages[x] == tSender then 
						tTabNumber = z
						local tTab = SkuSettings:Sub("SkuChat").tabs[z]
						tTab.messageTypes["PLAYER_MESSAGES"][6] = play
						tTab.messageTypes["PLAYER_MESSAGES"][7] = play
						tTab.messageTypes["CREATURE_MESSAGES"][4] = play
						tTab.messageTypes["CREATURE_MESSAGES"][6] = play
					end
				end
			else
				local tTab = SkuSettings:Sub("SkuChat").tabs[z]
				tTab.messageTypes["PLAYER_MESSAGES"][6] = false
				tTab.messageTypes["PLAYER_MESSAGES"][7] = false
				tTab.messageTypes["CREATURE_MESSAGES"][4] = false
				tTab.messageTypes["CREATURE_MESSAGES"][6] = false			
			end
		end

		if not tTabNumber then
			local tNewTabName
			if aType == "WHISPER" then
				tNewTabName = playerName
			elseif aType == "INFORM" then
				tNewTabName = playerName2
			end

			tTabNumber = SkuChat:NewTab(tSender)
			SkuSettings:Sub("SkuChat").tabs[tTabNumber].privateMessages = {}
			table.insert(SkuSettings:Sub("SkuChat").tabs[tTabNumber].privateMessages, tSender)

			local tTab = SkuSettings:Sub("SkuChat").tabs[tTabNumber]
			for tCatName, tData in pairs(SkuChat.ChatFrameMessageTypes) do
				for x = 1, #tData do
					tTab.messageTypes[tCatName][x] = false
				end
			end
			tTab.messageTypes["PLAYER_MESSAGES"][6] = play
			tTab.messageTypes["PLAYER_MESSAGES"][7] = play
			tTab.messageTypes["CREATURE_MESSAGES"][4] = play
			tTab.messageTypes["CREATURE_MESSAGES"][6] = play

			SkuSettings:Sub("SkuChat").tabs[tTabNumber].channels = {}
			SkuChat:InitTab(tTabNumber)

			C_Timer.After(0.1, function() 
				--print("cu", SkuSettings:Sub("SkuChat").tabs[tTabNumber].history[1])
				if SkuSettings:Sub("SkuChat").tabs[tTabNumber].history[1] and SkuSettings:Sub("SkuChat").tabs[tTabNumber].history[1].body == L["Empty"] then
					--print("C_Timer.After", _G[SkuSettings:Sub("SkuChat").tabs[tTabNumber].frameName], event, text, playerName, languageName, channelName, playerName2, specialFlags, zoneChannelID, channelIndex, channelBaseName, languageID, lineID, guid, bnSenderID, isMobile, isSubtitle, hideSenderInLetterbox, supressRaidIcons)
					SkuChat_MessageEventHandler(_G[SkuSettings:Sub("SkuChat").tabs[tTabNumber].frameName], event, text, playerName, languageName, channelName, playerName2, specialFlags, zoneChannelID, channelIndex, channelBaseName, languageID, lineID, guid, bnSenderID, isMobile, isSubtitle, hideSenderInLetterbox, supressRaidIcons)
				end
			end)
		end

		return tTabNumber
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuChat:CHAT_MSG_WHISPER(...)
	SkuChat:NewWhisperTab("WHISPER", ...)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuChat:CHAT_MSG_WHISPER_INFORM(...)
	SkuChat:NewWhisperTab("INFORM", ...)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuChat:DEFAULT_CHAT_FRAME_AddMessage(...)
	-- Installed as a persistent hooksecurefunc (cannot be unhooked); guard the
	-- body so a disabled SkuChat does not mirror DEFAULT_CHAT_FRAME messages.
	if SkuChat.IsEnabled and not SkuChat:IsEnabled() then return end
	local a, b, c, d, e, f = ...
	if a == "" or a == " " then
		return
	end
	--SkuCore:Debug((a or "nil").." "..(b or "nil").." "..(c or "nil").." "..(d or "nil").." "..(e or "nil").." "..(f or "nil"))
	for i, v in pairs(SkuSettings:Sub("SkuChat").tabs) do

		if v.name ~= L["Combat Log"] and v.name ~= L["Audio Log"] then
			if _G[v.frameName] then
				if _G[v.frameName].AddMessage then
					if b == nil and c == nil and  d == nil and  e == nil and  f == nil then
						_G[v.frameName]:AddMessage("ADDON", a, 1, 1, 1, 0, 0, 0, "AddMessage")
					end
				end
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuChat:VARIABLES_LOADED(...)

end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuChat:PLAYER_LOGIN(...)
	SkuCore.outputSoundFiles["sound-newChatLine"] =L["aura;sound"].."#"..L["default new Chat Line sound"]
	SkuCore.outputSoundFiles["sound-silence0.1"] = L["aura;sound"].."#"..L["silent"]
	if SkuSettings:Sub("SkuChat").tabs then
		for x = 1, #SkuSettings:Sub("SkuChat").tabs do
			if SkuSettings:Sub("SkuChat").tabs[x].audioOnNewMessage == true then
				SkuSettings:Sub("SkuChat").tabs[x].audioOnNewMessage = "sound-newChatLine"
			elseif SkuSettings:Sub("SkuChat").tabs[x].audioOnNewMessage == false then
				SkuSettings:Sub("SkuChat").tabs[x].audioOnNewMessage = "sound-silence0.1"
			end
		end
	end

	hooksecurefunc(DEFAULT_CHAT_FRAME, "AddMessage", SkuChat.DEFAULT_CHAT_FRAME_AddMessage)

	ChatFrame1:HookScript("OnShow", function(self)
		C_Timer.After(5, function()
			SkuChat:JoinOrLeaveSkuChatChannel()
		end)
	end)

	ChatFrame1EditBox:HookScript("OnTextChanged", function(self, a, b, c)
		if SkuChatEditboxHookFlag == false then
			local tCurrentText = ChatFrame1EditBox:GetText() or ""
			tCurrentText = string.lower(tCurrentText)
			if tCurrentText == "/skuchat" then
				SkuChat:SetEditboxToSkuChat("")
			end
		end
	end)

	hooksecurefunc(ChatFrame1EditBox, "Show", SkuChat.ChatFrame1EditBoxOnShow)
	hooksecurefunc(ChatFrame1EditBox, "Hide", SkuChat.ChatFrame1EditBoxOnHide)

	-- [v43.2] Tastatur-Echo fuer Blizzards Chat-Eingabe. Bis hierher war sie das
	-- einzige Eingabefeld ohne Zeichen-Echo -- Sku hatte darauf nur den
	-- Oeffnen-/Schliessen-Ton. Beim SkuBeacon muss nichts registriert werden:
	-- "ChatFrame1EditBox" steht dort fest in der eingebauten Liste der
	-- Texteingaben. Ob ueberhaupt gesprochen wird, entscheidet weiterhin die
	-- allgemeine Einstellung "Tastatur-Echo ansagen"; die Einstellung hier
	-- entscheidet nur ueber die Pfeiltasten.
	if SkuOptions.AttachInputEcho then
		SkuOptions:AttachInputEcho(ChatFrame1EditBox, {
			arrowsMoveCursor = function()
				local tSettings = SkuSettings and SkuSettings:Sub("SkuChat")
				if not tSettings or not tSettings.chatSettings then return true end
				return tSettings.chatSettings.chatArrowsMoveCursor ~= false
			end,
			softStop = true,
			-- Pfeil hoch holt eine gesendete Zeile zurueck. Blizzards Verlauf
			-- merkt sich nur den TEXT -- wohin die Zeile ginge, sieht man ihr
			-- nicht an, und der Kanal ist derselbe wie vor dem Tastendruck, es
			-- gibt also auch keine Aenderung, die die normale Kanalansage
			-- ausloesen wuerde. Deshalb steht er hier vor der Zeile.
			wholeTextPrefix = function()
				return SkuChat:GetEditboxChannelLabel()
			end,
		})
	end

	-- Kanalwechsel ansagen. Es braucht ZWEI Haken:
	--  * Blizzards eigene Aufrufe laufen als Methode (self:UpdateHeader()) und
	--    landen deshalb nur auf dem Feld AM FRAME,
	--  * der globale ChatEdit_UpdateHeader ist in Blizzard_DeprecatedChatInfo
	--    dagegen nur ein ALIAS auf die Mixin-Funktion selbst
	--    (ChatEdit_UpdateHeader = ChatFrameEditBoxMixin.UpdateHeader). Er zeigt
	--    also am Frame-Feld VORBEI -- und genau diesen globalen Namen ruft Skus
	--    eigenes SetEditboxToCustom.
	-- Die Ansage entdoppelt sich selbst (sie feuert nur bei geaendertem Header),
	-- deshalb sind beide Haken zusammen unproblematisch.
	if ChatFrame1EditBox.UpdateHeader then
		hooksecurefunc(ChatFrame1EditBox, "UpdateHeader", function()
			SkuChat:AnnounceEditboxChannel(nil, "updateHeader:method")
		end)
	end
	if _G.ChatEdit_UpdateHeader then
		hooksecurefunc("ChatEdit_UpdateHeader", function()
			SkuChat:AnnounceEditboxChannel(nil, "updateHeader:global")
		end)
	end

	-- [v43.2] Der Merker fuer die Entdopplung haengt am FOKUS, nicht nur an der
	-- Show-Kante. Die Show-Kante liegt hinter dem Merkflag der Oeffnen-/
	-- Schliessen-Toene (ChatFrame1EditBoxIsShown); bleibt das Flag einmal
	-- stehen -- etwa weil die Box ohne :Hide() verschwindet --, dann meldet die
	-- Ansage danach fuer immer "unveraendert" und schweigt. Der Fokuswechsel
	-- ist die Kante, die nachweislich jedes Mal feuert: das Tastatur-Echo
	-- haengt daran und funktioniert.
	ChatFrame1EditBox:HookScript("OnEditFocusGained", function()
		SkuChat:ResetEditboxChannelMemo()
		C_Timer.After(0.05, function() SkuChat:AnnounceEditboxChannel(nil, "focusGained") end)
	end)
	ChatFrame1EditBox:HookScript("OnEditFocusLost", function()
		SkuChat:ResetEditboxChannelMemo()
	end)

	-- Unbekannte Slash-Befehle hoerbar machen (siehe AnnounceUnknownChatCommand).
	if _G.ChatFrameUtil and ChatFrameUtil.DisplayHelpTextSimple then
		hooksecurefunc(ChatFrameUtil, "DisplayHelpTextSimple", function()
			SkuChat:AnnounceUnknownChatCommand()
		end)
	else
		dprint("chatCommand", "ChatFrameUtil.DisplayHelpTextSimple fehlt, keine Ansage")
	end

	C_TTSSettings.SetSetting(Enum.TtsBoolSetting.PlaySoundSeparatingChatLineBreaks, SkuSettings:Sub("SkuChat").chatSettings.audioOnMessageEnd)
end

---------------------------------------------------------------------------------------------------------------------------------------
--hooks to play the chateditbox sounds
local ChatFrame1EditBoxIsShown = false

-- [v43.2] Kanalansage der Chat-Eingabe.
--
-- Blizzard schreibt den Zielkanal als FontString links in die Editbox
-- (ChatFrame1EditBoxHeader, gesetzt in ChatFrameEditBoxMixin:UpdateHeader). Der
-- Text ist bereits vollstaendig lokalisiert und deckt jeden Fall ab, den diese
-- Funktion kennt -- "Sagen:", "Gruppe:", "An Kai:", "2. Handel:", Emote,
-- BN-Fluestern, Instanz-Chat. Ihn auszulesen ist deshalb richtiger, als
-- chatType/channelTarget hier noch einmal selbst in einen Namen
-- zurueckzuuebersetzen: eine solche zweite Tabelle wuerde bei jedem dieser
-- Sonderfaelle auseinanderlaufen, und UpdateHeader schaltet einige davon sogar
-- im Lauf um (PARTY wird zu INSTANCE_CHAT, SMART_WHISPER zu BN_WHISPER).
local tLastAnnouncedChatHeader = nil

function SkuChat:GetEditboxChannelLabel()
	local tHeader = _G["ChatFrame1EditBoxHeader"]
	if not tHeader or not tHeader.GetText then
		return nil
	end
	local tText = tHeader:GetText()
	if type(tText) ~= "string" or tText == "" then
		return nil
	end
	-- Farbcodes raus und den Doppelpunkt am Ende weg: der Doppelpunkt trennt in
	-- Skus TTS-Ausgabe NICHTS (das tut nur das Semikolon), er wuerde die Ansage
	-- also nur mit dem naechsten Teil verkleben.
	tText = string.gsub(tText, "|c%x%x%x%x%x%x%x%x", "")
	tText = string.gsub(tText, "|r", "")
	tText = string.gsub(tText, "%s*:%s*$", "")
	tText = strtrim(tText)
	if tText == "" then
		return nil
	end
	return tText
end

-- Merker fuer die Entdopplung zuruecksetzen. Als Methode, weil PLAYER_LOGIN
-- WEITER OBEN in der Datei steht: eine Closure dort kann diesen local gar nicht
-- sehen (er existiert dort lexikalisch noch nicht) und wuerde stillschweigend
-- eine GLOBALE gleichen Namens schreiben.
function SkuChat:ResetEditboxChannelMemo()
	tLastAnnouncedChatHeader = nil
end

-- Die Kanalansage laeuft VERZOEGERT und in EINEM Slot -- genau wie das
-- Tastatur-Echo, und aus demselben Grund.
--
-- Jeder Kanalwechsel wird durch einen Tastendruck ausgeloest, und dessen
-- Zeichen-Echo geht mit overwrite in dieselbe Warteschlange. Sofort gesprochen
-- verliert die Ansage deshalb IMMER gegen das ausloesende Zeichen: Skus Pumpe
-- taktet nur alle 0.1 s, das Echo raeumt die Queue vorher leer. Im Log zweimal
-- exakt so belegt --
--     ansage Gilde -> queuereset -> SpeakText [ leerzeichen ]
--     ansage Sagen -> queuereset -> SpeakText [ / ]
-- -- das Leerzeichen aus "/g " bzw. der Schraegstrich beim Oeffnen kamen als
-- letzte und haben die Ansage aus der Queue geworfen, bevor sie je gesprochen
-- war. Kommt die Ansage dagegen NACH dem Zeichen, ueberschreibt sie es. Ein
-- Zeichen-Echo dafuer zu verlieren ist der richtige Tausch: dass sich der
-- Zielkanal geaendert hat, ist die wichtigere Information.
--
-- Ein Slot mit Generationszaehler: mehrere Ansagen kurz hintereinander (Blizzard
-- ruft UpdateHeader beim Oeffnen dreimal) sprechen nur EINMAL, mit dem zuletzt
-- gueltigen Kanal.
local tChannelPendingLabel = nil
local tChannelPendingGeneration = 0
local tChannelSpeakDelay = 0.3

local function tSpeakChannelSoon(aLabel)
	tChannelPendingLabel = aLabel
	tChannelPendingGeneration = tChannelPendingGeneration + 1
	local tGeneration = tChannelPendingGeneration
	C_Timer.After(tChannelSpeakDelay, function()
		if tGeneration ~= tChannelPendingGeneration then return end
		-- Zwischenzeitlich geschlossen (z. B. abgeschickt): dann waere die
		-- Ansage nur noch eine Ansage ins Leere.
		if not ChatFrame1EditBox or not ChatFrame1EditBox:IsShown() then
			dprintv("chatChannel", "spricht nicht, Editbox zu", tostring(tChannelPendingLabel))
			return
		end
		dprint("chatChannel", "spricht", tostring(tChannelPendingLabel))
		pcall(function()
			SkuOptions.Voice:OutputStringBTtts(tChannelPendingLabel, {overwrite = true, wait = false, length = 0.05, engine = 2, ignoreLinks = true})
		end)
	end)
end

-- Beim Oeffnen schweigt die Ansage NUR bei "Sagen".
--
-- Zwei Anlaeufe davor waren beide falsch herum gedacht:
--  * chatType == stickyType: bei einem nummerierten Kanal sind BEIDE schlicht
--    "CHANNEL", damit galt [4. SkuChat] als Standard -- und [2. Handel] haette
--    genauso gegolten, obwohl es ein ganz anderer Kanal ist.
--  * "wie beim letzten Oeffnen": technisch korrekt, praktisch das Gegenteil des
--    Gewuenschten. Blizzard oeffnet die Zeile auf dem zuletzt benutzten Kanal
--    (stickyType), also stand sie dauerhaft auf [4. SkuChat] -- und genau DAS
--    wurde dann nie wieder gesagt. Wer nichts hoert, tippt in einen Kanal, den
--    er nicht gewaehlt hat.
--
-- "Sagen" ist der harmlose Fall: es geht an die Umstehenden und ist das, was
-- ohne Zutun passiert. Jeder ANDERE Kanal -- Gilde, Gruppe, Fluestern, ein
-- nummerierter Kanal -- ist einer, in dem ein versehentliches Absenden zaehlt.
-- Der wird deshalb bei JEDEM Oeffnen gesagt, nicht nur beim ersten.

-- [v43.2] Unbekannter Slash-Befehl.
--
-- Ein vertippter Befehl ist der eine Fall, in dem gar nichts passiert und man
-- es nicht merkt: "/test" sieht beim Tippen aus wie eine Nachricht, wird aber
-- nie gesendet -- WoW sucht einen Befehl, findet keinen und schreibt nur die
-- allgemeine Hilfezeile (HELP_TEXT_SIMPLE) in den Chatrahmen. Ob die beim
-- Nutzer ankommt, haengt daran, welcher SkuChat-Reiter Systemmeldungen zeigt.
-- Genau diese Stille kostete hier eine Testrunde: die Nachricht "kam nicht an",
-- weil sie nie eine war.
--
-- ChatFrameUtil.DisplayHelpTextSimple ist Blizzards Behandlung genau dieses
-- Falls und laeuft VOR ClearChat -- der getippte Text steht also noch in der
-- Zeile und der Befehl laesst sich mitsagen. Der Schraegstrich wird von der
-- Sprachausgabe als "slash" gelesen, das ist hier genau richtig.
function SkuChat:AnnounceUnknownChatCommand()
    local tText = (ChatFrame1EditBox and ChatFrame1EditBox:GetText()) or ""
    local tCommand = string.match(tText, "^(/[^%s]+)") or ""
    local tMessage = L["Unbekannter Befehl"]
    if tCommand ~= "" then
        -- Semikolon: das ist Skus Trennzeichen in der Sprachausgabe.
        tMessage = tMessage .. "; " .. tCommand
    end
    dprint("chatCommand", "unbekannt", tCommand ~= "" and tCommand or tText)
    -- Verzoegert, weil unmittelbar danach die Chatzeile schliesst: der
    -- Fokusverlust laeuft in tEchoStop, und dessen Abbruch wuerde diese Ansage
    -- gleich wieder abschneiden (das Tastatur-Echo lief eben noch, also greift
    -- dort auch die "nur wenn kuerzlich"-Bedingung).
    C_Timer.After(0.25, function()
        pcall(function()
            SkuOptions.Voice:OutputStringBTtts(tMessage, {overwrite = true, wait = false, length = 0.05, engine = 2, ignoreLinks = true})
        end)
    end)
end

---@param aForce boolean|nil auch ansagen, wenn sich der Kanal nicht geaendert hat
---@param aWhy string|nil Ausloeser, nur fuers Log
function SkuChat:AnnounceEditboxChannel(aForce, aWhy)
	aWhy = aWhy or "?"
	if SkuChat.IsEnabled and not SkuChat:IsEnabled() then
		dprint("chatChannel", aWhy, "SkuChat aus")
		return
	end
	local tSettings = SkuSettings and SkuSettings:Sub("SkuChat")
	if not tSettings or not tSettings.chatSettings then
		dprint("chatChannel", aWhy, "keine Einstellungen")
		return
	end
	if tSettings.chatSettings.announceChatChannel == false then
		dprint("chatChannel", aWhy, "abgeschaltet")
		return
	end
	if not ChatFrame1EditBox or not ChatFrame1EditBox:IsShown() then
		dprintv("chatChannel", aWhy, "Editbox nicht sichtbar")
		return
	end
	local tLabel = SkuChat:GetEditboxChannelLabel()
	if not tLabel then
		dprint("chatChannel", aWhy, "kein Kopfzeilentext", "chatType",
			tostring(ChatFrame1EditBox:GetAttribute("chatType")))
		return
	end

	-- Leerer Merker = erste Ansage nach dem Fokuswechsel = das Oeffnen. Regel
	-- dafuer siehe oben bei tLastAnnouncedChatHeader: nur "Sagen" schweigt.
	-- Jeder spaetere WECHSEL laeuft ohnehin weiter unten durch, weil der Merker
	-- dann nicht mehr leer ist.
	if aForce ~= true and tLastAnnouncedChatHeader == nil then
		if ChatFrame1EditBox:GetAttribute("chatType") == "SAY" then
			tLastAnnouncedChatHeader = tLabel
			dprint("chatChannel", aWhy, "Sagen beim Oeffnen, nicht angesagt", tLabel)
			return
		end
		dprint("chatChannel", aWhy, "Oeffnen auf", tLabel)
	end

	-- Nur bei Aenderung ansagen: UpdateHeader laeuft auch bei jedem Tastendruck
	-- durch, der ein Schraegstrich-Befehl sein koennte.
	if aForce ~= true and tLabel == tLastAnnouncedChatHeader then
		dprintv("chatChannel", aWhy, "unveraendert", tLabel)
		return
	end
	dprint("chatChannel", aWhy, "ansage", tLabel, "vorher", tostring(tLastAnnouncedChatHeader))
	tLastAnnouncedChatHeader = tLabel
	tSpeakChannelSoon(tLabel)
end

function SkuChat:ChatFrame1EditBoxOnShow()
	if SkuChat.IsEnabled and not SkuChat:IsEnabled() then return end
	if ChatFrame1EditBoxIsShown == false  then
		ChatFrame1EditBoxIsShown = true
		PlaySoundFile("Interface\\AddOns\\Sku\\SkuChat\\assets\\audio\\chateditbox_open.mp3", "Talking Head")
		-- [v43.2] Merker UND Ansage haengen am FOKUS (unten in PLAYER_LOGIN). Die
		-- Show-Kante ist die unzuverlaessigere: sie feuert laut Log teils VOR
		-- dem Fokus und teils gar nicht (siehe "OHNE Kante" unten).
		dprint("chatChannel", "editbox show")
	else
		-- Kante verschluckt: das Flag stand schon auf true. Genau hier faellt
		-- sonst auch die Ansage aus, ohne dass sichtbar etwas schiefgeht.
		dprint("chatChannel", "editbox show OHNE Kante (Flag stand schon)")
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuChat:ChatFrame1EditBoxOnHide()
	if SkuChat.IsEnabled and not SkuChat:IsEnabled() then return end
	if ChatFrame1EditBoxIsShown == true  then
		ChatFrame1EditBoxIsShown = false
		PlaySoundFile("Interface\\AddOns\\Sku\\SkuChat\\assets\\audio\\chateditbox_close.mp3", "Talking Head")
		tLastAnnouncedChatHeader = nil
		dprint("chatChannel", "editbox hide")
	else
		dprint("chatChannel", "editbox hide OHNE Kante (Flag stand schon)")
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuChat:JoinOrLeaveSkuChatChannel()
	local id, name, instanceID, isCommunitiesChannel = GetChannelName("SkuChat")

	if SkuSettings:Sub("SkuChat").joinSkuChannel == true then
		if id == 0 then
			JoinPermanentChannel("SkuChat", nil, FCF_GetCurrentChatFrame():GetID())
			-- ChatFrameMixin:AddChannel on every client. The old non-TBC branch called
			-- a global ChatFrame_AddChannel that does not exist in the Anniversary
			-- interface code at all, so it was a nil call on Era. Confirmed in-game:
			-- ChatFrame_AddChannel -> nil, ChatFrame1.AddChannel -> function.
			-- (Latent: the `id == 0` gate above means it only fires for someone not
			-- yet in the SkuChat channel — i.e. every fresh Era install.)
			ChatFrame1:AddChannel("SkuChat")
		end
	else
		if id ~= 0 then
			LeaveChannelByName("SkuChat")
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuChat:CombatLogTabIndex()
	for x = 1, #SkuSettings:Sub("SkuChat").tabs do
		if SkuSettings:Sub("SkuChat").tabs[x].name == L["Combat Log"] then
			return x
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuChat:InitCombatLogTab()
	if SkuSettings:Sub("SkuChat").CombatLog.enabled == true then
		if not SkuChat:CombatLogTabIndex() then

			local tabIndex = SkuChat:NewTab(L["Combat Log"])
			for i, v in pairs(SkuSettings:Sub("SkuChat").tabs[tabIndex].messageTypes) do
				for u = 1, #v do
					v[u] = false
				end
			end
			for i, v in pairs(SkuSettings:Sub("SkuChat").tabs[tabIndex].channels) do
				v.status = false
			end

			SkuSettings:Sub("SkuChat").tabs[tabIndex].audioOnNewMessage = "sound-silence0.1"
			SkuSettings:Sub("SkuChat").tabs[tabIndex].messageTypes["SKU"][1] = true

			SkuChat:InitTab(tabIndex)
		end
	else
		if SkuChat:CombatLogTabIndex() then
			SkuChat:DeleteTab(SkuChat:CombatLogTabIndex())
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuChat:AudioLogTabIndex()
	for x = 1, #SkuSettings:Sub("SkuChat").tabs do
		if SkuSettings:Sub("SkuChat").tabs[x].name == L["Audio Log"] then
			return x
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuChat:InitAudioLogTab()
	if SkuSettings:Sub("SkuChat").AudioLog.enabled == true then
		if not SkuChat:AudioLogTabIndex() then
			local tabIndex = SkuChat:NewTab(L["Audio Log"])
			for i, v in pairs(SkuSettings:Sub("SkuChat").tabs[tabIndex].messageTypes) do
				for u = 1, #v do
					v[u] = false
				end
			end
			for i, v in pairs(SkuSettings:Sub("SkuChat").tabs[tabIndex].channels) do
				v.status = false
			end

			SkuSettings:Sub("SkuChat").tabs[tabIndex].audioOnNewMessage = "sound-silence0.1"
			SkuSettings:Sub("SkuChat").tabs[tabIndex].messageTypes["SKU"][2] = true

			SkuChat:InitTab(tabIndex)
		end
	else
		if SkuChat:AudioLogTabIndex() then
			SkuChat:DeleteTab(SkuChat:AudioLogTabIndex())
		end
	end			
end

---------------------------------------------------------------------------------------------------------------------------------------
local function CreateSkuDefaultFilters()
	SkuSettings:Sub("SkuChat", nil, "global")
	SkuSettings:Sub("SkuChat", nil, "global").CombatLogFilters = SkuSettings:Sub("SkuChat", nil, "global").CombatLogFilters or {
		[1] = {
			custom = false,
			name = "Everything",
			hasQuickButton = true,
			quickButtonName = "Everything",
			quickButtonDisplay = {
				solo = true,
				party = true,
				raid = true,
			},
			tooltip = "Everything",
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
		},
		[2] = {
			custom = false,
			name = "My actions",
			hasQuickButton = true,
			quickButtonName = "My actions",
			quickButtonDisplay = {
				solo = true,
				party = true,
				raid = true,
			},
			tooltip = "My actions",
			settings = CopyTable(COMBATLOG_DEFAULT_SETTINGS),
			colors = CopyTable(COMBATLOG_DEFAULT_COLORS),
			filters = {
				[1] = {
					eventList = {
						["ENVIRONMENTAL_DAMAGE"] = false,
						["SWING_DAMAGE"] = true,
						["SWING_MISSED"] = false,
						["RANGE_DAMAGE"] = true,
						["RANGE_MISSED"] = false,
						--["SPELL_CAST_START"] = true,
						--["SPELL_CAST_SUCCESS"] = true,
						--["SPELL_CAST_FAILED"] = true,
						["SPELL_MISSED"] = false,
						["SPELL_DAMAGE"] = true,
						["SPELL_HEAL"] = true,
						["SPELL_ENERGIZE"] = true,
						["SPELL_DRAIN"] = false,
						["SPELL_LEECH"] = false,
						["SPELL_INSTAKILL"] = false,
						["SPELL_INTERRUPT"] = false,
						["SPELL_EXTRA_ATTACKS"] = false,
						["SPELL_DURABILITY_DAMAGE"] = false,
						["SPELL_DURABILITY_DAMAGE_ALL"] = false,
						["SPELL_AURA_APPLIED"] = false,
						["SPELL_AURA_APPLIED_DOSE"] = false,
						["SPELL_AURA_REMOVED"] = false,
						["SPELL_AURA_REMOVED_DOSE"] = false,
						["SPELL_AURA_BROKEN"] = false,
					  ["SPELL_AURA_BROKEN_SPELL"] = false,
					  ["SPELL_AURA_REFRESH"] = false,
						["SPELL_DISPEL"] = false,
						["SPELL_STOLEN"] = false,
						["ENCHANT_APPLIED"] = false,
						["ENCHANT_REMOVED"] = false,
						["SPELL_PERIODIC_MISSED"] = false,
						["SPELL_PERIODIC_DAMAGE"] = true,
						["SPELL_PERIODIC_HEAL"] = true,
						["SPELL_PERIODIC_ENERGIZE"] = true,
						["SPELL_PERIODIC_DRAIN"] = false,
						["SPELL_PERIODIC_LEECH"] = false,
						["SPELL_DISPEL_FAILED"] = false,
						--["DAMAGE_SHIELD"] = true,
						--["DAMAGE_SHIELD_MISSED"] = true,
						["DAMAGE_SPLIT"] = true,
						["PARTY_KILL"] = true,
						["UNIT_DIED"] = false,
						["UNIT_DESTROYED"] = true,
						["UNIT_DISSIPATES"] = true,
					  ["UNIT_LOYALTY"] = false
					};
					sourceFlags = {
						[COMBATLOG_FILTER_MINE] = true
					};
					destFlags = nil;
				},
				[2] = {
					eventList = {
						--["ENVIRONMENTAL_DAMAGE"] = true,
						["SWING_DAMAGE"] = true,
						["SWING_MISSED"] = true,
						["RANGE_DAMAGE"] = true,
						["RANGE_MISSED"] = true,
						--["SPELL_CAST_START"] = true,
						--["SPELL_CAST_SUCCESS"] = true,
						--["SPELL_CAST_FAILED"] = true,
						["SPELL_MISSED"] = true,
						["SPELL_DAMAGE"] = true,
						["SPELL_HEAL"] = true,
						["SPELL_ENERGIZE"] = true,
						["SPELL_DRAIN"] = true,
						["SPELL_LEECH"] = true,
						["SPELL_INSTAKILL"] = true,
						["SPELL_INTERRUPT"] = true,
						["SPELL_EXTRA_ATTACKS"] = true,
						["SPELL_DURABILITY_DAMAGE"] = true,
						["SPELL_DURABILITY_DAMAGE_ALL"] = true,
						--["SPELL_AURA_APPLIED"] = true,
						--["SPELL_AURA_APPLIED_DOSE"] = true,
						--["SPELL_AURA_REMOVED"] = true,
						--["SPELL_AURA_REMOVED_DOSE"] = true,
						["SPELL_DISPEL"] = true,
						["SPELL_STOLEN"] = true,
						["ENCHANT_APPLIED"] = true,
						["ENCHANT_REMOVED"] = true,
						--["SPELL_PERIODIC_MISSED"] = true,
						--["SPELL_PERIODIC_DAMAGE"] = true,
						--["SPELL_PERIODIC_HEAL"] = true,
						--["SPELL_PERIODIC_ENERGIZE"] = true,
						--["SPELL_PERIODIC_DRAIN"] = true,
						--["SPELL_PERIODIC_LEECH"] = true,
						["SPELL_DISPEL_FAILED"] = true,
						--["DAMAGE_SHIELD"] = true,
						--["DAMAGE_SHIELD_MISSED"] = true,
						["DAMAGE_SPLIT"] = true,
						["PARTY_KILL"] = true,
						["UNIT_DIED"] = true,
						["UNIT_DESTROYED"] = true,
						["UNIT_DISSIPATES"] = true,
					  ["UNIT_LOYALTY"] = false
					};
					sourceFlags = nil;
					destFlags =  {
						[COMBATLOG_FILTER_MINE] = false,
						[COMBATLOG_FILTER_MY_PET] = false;
					};
				},				
			},
		},
		[3] = {
			custom = false,
			name = "What happend to me",
			hasQuickButton = true,
			quickButtonName = "What happend to me",
			quickButtonDisplay = {
				solo = true,
				party = true,
				raid = true,
			},
			tooltip = "What happend to me",
			settings = CopyTable(COMBATLOG_DEFAULT_SETTINGS),
			colors = CopyTable(COMBATLOG_DEFAULT_COLORS),
			filters = {
				[1] = {
					eventList = {
					      ["ENVIRONMENTAL_DAMAGE"] = true,
					      ["SWING_DAMAGE"] = true,
					      ["RANGE_DAMAGE"] = true,
					      ["SPELL_DAMAGE"] = true,
					      ["SPELL_HEAL"] = true,
					      ["SPELL_PERIODIC_DAMAGE"] = true,
					      ["SPELL_PERIODIC_HEAL"] = true,
					      ["DAMAGE_SPLIT"] = true,
					      ["UNIT_DIED"] = true,
					      ["UNIT_DESTROYED"] = true,
					      ["UNIT_DISSIPATES"] = true
					};
					sourceFlags = Blizzard_CombatLog_GenerateFullFlagList(false);
					destFlags = nil;
				};
				[2] = {
					eventList = Blizzard_CombatLog_GenerateFullEventList();
					sourceFlags = nil;
					destFlags =  {
						[COMBATLOG_FILTER_MINE] = true,
						[COMBATLOG_FILTER_MY_PET] = false;
					};
				};
			},
		},				
	}
end

---------------------------------------------------------------------------------------------------------------------------------------
local SkuChatEditboxHookFlag = false
function SkuChat:PLAYER_ENTERING_WORLD(...)
	local event, isInitialLogin, isReloadingUi = ...

	--init combat log stuff
	SkuSettings:Sub("SkuChat").CombatLog = SkuSettings:Sub("SkuChat").CombatLog or {
		enabled = false,
		currentFilter = 1,
	}

	-- we need to delay this to entering world because of global constants availablity
	CreateSkuDefaultFilters()

	if not SkuSettings:Sub("SkuChat", nil, "global").CombatLogFilters[SkuSettings:Sub("SkuChat").CombatLog.currentFilter] then
		SkuSettings:Sub("SkuChat").CombatLog.currentFilter = 1
	end

	Blizzard_CombatLog_CurrentSettings = SkuSettings:Sub("SkuChat", nil, "global").CombatLogFilters[SkuSettings:Sub("SkuChat").CombatLog.currentFilter]
	Blizzard_CombatLog_ApplyFilters(Blizzard_CombatLog_CurrentSettings)
	

	--init audio log stuff
	SkuSettings:Sub("SkuChat").AudioLog = SkuSettings:Sub("SkuChat").AudioLog or {
		enabled = false,
	}


	--remove aws polly dev voices on my system
	SkuChat.WowTtsVoices = {}
	for i, v in pairs(C_VoiceChat.GetTtsVoices()) do
		if not string.find(v.name, "Polly") then
			SkuChat.WowTtsVoices[i] = v.name
		end
	end
	SkuChat.options.args.WowTtsVoice.values = SkuChat.WowTtsVoices

	--create default tabs
	if not SkuSettings:Sub("SkuChat").tabs or #SkuSettings:Sub("SkuChat").tabs == 0 then
		SkuSettings:Sub("SkuChat").tabs = {}
		SkuChat:NewTab(L["Default"])
		SkuChat:NewTab(L["Communication"])
		SkuChat:NewTab(L["Other"])
		-- Dedicated whisper tab: NewTab/ResetTab pick the message types up from
		-- SkuChat.ChatFrameDefaultTabs[L["ChatTabWhisper"]] (whispers + Battle.net
		-- whispers audible, everything else muted). It gets its OWN new-message
		-- sound instead of the shared "sound-newChatLine" so an incoming whisper is
		-- recognisable by ear alone; changeable per tab under
		-- "Audio notification on chat message".
		local tWhisperTabIndex = SkuChat:NewTab(L["ChatTabWhisper"])
		if tWhisperTabIndex and SkuSettings:Sub("SkuChat").tabs[tWhisperTabIndex] then
			SkuSettings:Sub("SkuChat").tabs[tWhisperTabIndex].audioOnNewMessage = "sound-notification3"
		end
	end

	--init filters
	if not SkuSettings:Sub("SkuChat").chatSettings.filter then
		SkuSettings:Sub("SkuChat").chatSettings.filter = {}
	end
	if not SkuSettings:Sub("SkuChat").chatSettings.filter.terms then
		SkuSettings:Sub("SkuChat").chatSettings.filter.terms = {}
	end

	--update types for existing tabs; just to add new types with new releases
	for tCatName, tData in pairs(SkuChat.ChatFrameMessageTypes) do
		for i, tTabData in pairs(SkuSettings:Sub("SkuChat").tabs) do
			tTabData.messageTypes[tCatName] = tTabData.messageTypes[tCatName] or {}
			if #tTabData.messageTypes[tCatName] ~= #tData then
				for x = 1, #tData do
					tTabData.messageTypes[tCatName][x] = tData[x].default
				end
			end
		end
	end

	for x = #SkuSettings:Sub("SkuChat").tabs, 1, -1  do
		if _G[SkuSettings:Sub("SkuChat").tabs[x].frameName] then
			_G[SkuSettings:Sub("SkuChat").tabs[x].frameName]:UnregisterAllEvents() 
		end
		if SkuSettings:Sub("SkuChat").tabs[x].privateMessages then
			table.remove(SkuSettings:Sub("SkuChat").tabs, x)
		end
	end

	for x = 1, #SkuSettings:Sub("SkuChat").tabs do
		SkuChat:InitTab(x)
		SkuSettings:Sub("SkuChat").tabs[x].historyCurrentLine = 1
	end

	SkuChat.currentTab = 1

	--add new - because we want them at the last position
	SkuChat:InitAudioLogTab()
	SkuChat:InitCombatLogTab()	

	
	--delete history of all tabs if required
	if SkuSettings:Sub("SkuChat").chatSettings.deleteHistoryOnLogin == true  and isInitialLogin == true then
		for x = 1, #SkuSettings:Sub("SkuChat").tabs do
			SkuSettings:Sub("SkuChat").tabs[x].history = {}
			table.insert(SkuSettings:Sub("SkuChat").tabs[x].history, 1, {
				body = L["Empty"], 
				messageTypeGroup = "SAY", 
				audio = false, 
				accessID = nil, 
				typeID = nil, 
				arg2 = nil, 
				time = time(),
			})					
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuChat:SetEditboxToCustom(chatType, target, aMsg)
	SkuChatEditboxHookFlag = true
	if chatType == "CHANNEL" then
		local channelNum, channelName = GetChannelName(target)
		ChatFrame1EditBox:SetAttribute("channelTarget", channelNum)
		ChatFrame1EditBox:SetAttribute("chatType", "CHANNEL")
	elseif chatType == "WHISPER" then
		ChatFrame1EditBox:SetAttribute("tellTarget", target)
		ChatFrame1EditBox:SetAttribute("chatType", "WHISPER")
	elseif chatType == "BN_WHISPER" then
		ChatFrame1EditBox:SetAttribute("tellTarget", target)
		ChatFrame1EditBox:SetAttribute("chatType", "BN_WHISPER")
	else
		ChatFrame1EditBox:SetAttribute("chatType", chatType)
		ChatFrame1EditBox:SetAttribute("stickyType", chatType)
	end
	
	ChatEdit_UpdateHeader(ChatFrame1EditBox)
	ChatFrame1EditBox:Show()
	ChatFrame1EditBox:SetFocus() 
	if aMsg then
		ChatFrame1EditBox:SetText(aMsg)
	end

	SkuChatEditboxHookFlag = false
end

---------------------------------------------------------------------------------------------------------------------------------------
--event handler to add/remove channels from/to existing tabs on leave/join channels
function SkuChat:CHAT_MSG_CHANNEL_NOTICE(...)
	local tEvent, tAction, tPlayerName, tLangName, tChannelName, tPlayerName2, tSpecialFlags, tZoneChannelID, tChannelIndex, channelBaseName = ...
	local tInternalChannelName = channelBaseName

	if tZoneChannelID > 0 then
		local tShortNames = {
			[1] = "General",
			[2] = "Trade",
			[22] = "LocalDefense",
			[23] = "WorldDefense",
			[25] = "GuildRecruitment",
			[26] = "LookingForGroup",
		}
		tInternalChannelName = tShortNames[tZoneChannelID]
	end

	if tAction == "YOU_CHANGED" then
		for z = 1, #SkuSettings:Sub("SkuChat").tabs do
			local tExists
			for y = 1, #SkuSettings:Sub("SkuChat").tabs[1].channels do
				if tInternalChannelName and SkuSettings:Sub("SkuChat").tabs[1].channels[y] and SkuSettings:Sub("SkuChat").tabs[1].channels[y].name and string.lower(SkuSettings:Sub("SkuChat").tabs[1].channels[y].name) == string.lower(tInternalChannelName) then
					tExists = true
					break
				end
			end
			if not tExists then
				if z == 1 then
					local tStatus = true
					if string.lower(channelBaseName) == "skuchat" then
						tStatus = play
					end
					
					SkuSettings:Sub("SkuChat").tabs[1].channels[#SkuSettings:Sub("SkuChat").tabs[1].channels + 1] = {name = tInternalChannelName, status = tStatus}
				else
					SkuSettings:Sub("SkuChat").tabs[1].channels[#SkuSettings:Sub("SkuChat").tabs[1].channels + 1] = {name = tInternalChannelName, status = false}
				end
			end
		end
	elseif tAction == "YOU_LEFT" then
		-- Schutz: tInternalChannelName kann nil sein, wenn weder
		-- channelBaseName noch tShortNames[tZoneChannelID] greifen
		-- (z. B. beim Verlassen eines unbenannten/Server-internen
		-- Channels — kann beim Zonenwechsel auftreten, etwa beim
		-- Betreten/Verlassen des Schattenmondtals). Ohne Guard crasht
		-- string.lower(nil) und reißt den Sku-Menü-State (folgender
		-- Tooltip-/OnUpdate-Code läuft danach mit nil-currentMenuPosition).
		if not tInternalChannelName then return end
		C_Timer.After(0, function() --we need to delay this to the next frame, as we first need the message to be processed with the channel still active for the tab
			for x = 1, #SkuSettings:Sub("SkuChat").tabs do
				for y = 1, #SkuSettings:Sub("SkuChat").tabs[x].channels do
					if SkuSettings:Sub("SkuChat").tabs[x] ~= nil and SkuSettings:Sub("SkuChat").tabs[x].channels[y] ~= nil and SkuSettings:Sub("SkuChat").tabs[x].channels[y].name and string.lower(SkuSettings:Sub("SkuChat").tabs[x].channels[y].name) == string.lower(tInternalChannelName) then
						table.remove(SkuSettings:Sub("SkuChat").tabs[x].channels, y)
						break
					end
				end
			end
		end)
	end

	for x = 1, #SkuSettings:Sub("SkuChat").tabs do
		if SkuSettings:Sub("SkuChat").tabs[x].frameName and _G[SkuSettings:Sub("SkuChat").tabs[x].frameName] then
			_G[SkuSettings:Sub("SkuChat").tabs[x].frameName]:UnregisterAllEvents() 
		end
		SkuSettings:Sub("SkuChat").tabs[x].frameName = "SkuChatChatFrame"..x
		SkuChat:InitTab(x)	
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuChat:ResetTab(aIndex)
	--print("ResetTab", aIndex)
	--set default message groups
	if not SkuSettings:Sub("SkuChat").tabs[aIndex] then
		return
	end

	-- set default message types
	local tTab = SkuSettings:Sub("SkuChat").tabs[aIndex]
	for tCatName, tData in pairs(SkuChat.ChatFrameMessageTypes) do
		for x = 1, #tData do
			if SkuChat.ChatFrameDefaultTabs[tTab.name] and SkuChat.ChatFrameDefaultTabs[tTab.name][tCatName] then
				tTab.messageTypes[tCatName][x] = SkuChat.ChatFrameDefaultTabs[tTab.name][tCatName][x].default
			else
				tTab.messageTypes[tCatName][x] = tData[x].default
			end
		end
	end

	--set default channels
	if tTab.name == L["Default"] then
		tTab.channels = {
			[1] = {name = "General", status = true},
			[2] = {name = "Trade", status = true},
			[3] = {name = "LocalDefense", status = true},
			[4] = {name = "WorldDefense", status = true},
			[5] = {name = "GuildRecruitment", status = true},
			[6] = {name = "LookingForGroup", status = true},
			[7] = {name = "SkuChat", status = play},
		}
	else
		tTab.channels = {
			[1] = {name = "General", status = false},
			[2] = {name = "Trade", status = false},
			[3] = {name = "LocalDefense", status = false},
			[4] = {name = "WorldDefense", status = false},
			[5] = {name = "GuildRecruitment", status = false},
			[6] = {name = "LookingForGroup", status = false},
			[7] = {name = "SkuChat", status = false},
		}
	end

	--set custom channels
	local tChannelList = {GetChannelList()}
	for x = 1, C_ChatInfo.GetNumActiveChannels() * 3, 3 do 
		local tExists
		for y = 1, #tTab.channels do
			if tTab.channels[y].name == tChannelList[x + 1] then
				tExists = true
			end
		end
		if not tExists then
			if tTab.name == L["Default"] then
				tTab.channels[#tTab.channels + 1] = {name = tChannelList[x + 1], status = true}
			else
				tTab.channels[#tTab.channels + 1] = {name = tChannelList[x + 1], status = false}
			end
		end
	end

	tTab.privateMessages = nil
	tTab.excludePrivateMessages = nil

	
	tTab.history = tTab.history or {}
	table.insert(tTab.history, 1, {
		body = L["Empty"], 
		messageTypeGroup = "SAY", 
		audio = false, 
		accessID = nil, 
		typeID = nil, 
		arg2 = nil, 
		time = time(),
	})		
	

	return true
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuChat:DeleteTab(aIndex)
	if SkuSettings:Sub("SkuChat").tabs[aIndex] then
		local tIsCurrent = SkuChat.currentTab == aIndex

		local tFrame = _G[SkuSettings:Sub("SkuChat").tabs[aIndex].frameName]
		tFrame:UnregisterAllEvents() 
		table.remove(SkuSettings:Sub("SkuChat").tabs, aIndex)

		for x = 1, #SkuSettings:Sub("SkuChat").tabs do
			_G[SkuSettings:Sub("SkuChat").tabs[x].frameName]:UnregisterAllEvents() 
			SkuSettings:Sub("SkuChat").tabs[x].frameName = "SkuChatChatFrame"..x
			SkuChat:InitTab(x)
		end

		if SkuChat.currentTab >= aIndex then
			SkuChat.currentTab = SkuChat.currentTab - 1
		end

		if SkuChat.ChatOpen == true and tIsCurrent == true then
			SkuChat:ReadLine(SkuChat.currentTab, SkuSettings:Sub("SkuChat").tabs[SkuChat.currentTab].historyCurrentLine, true)
		end

		return true
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuChat:InitTab(tNewTabIndex)
	--print("InitTab")
	--build virtual chat frame that is registering chat events
	local a = _G[SkuSettings:Sub("SkuChat").tabs[tNewTabIndex].frameName] or CreateFrame("Button", SkuSettings:Sub("SkuChat").tabs[tNewTabIndex].frameName, UIParent, "SecureActionButtonTemplate")
	a.tab = SkuSettings:Sub("SkuChat").tabs[tNewTabIndex]
	a.name = SkuSettings:Sub("SkuChat").tabs[tNewTabIndex].name
	a:SetScript("OnEvent", function(self, aEvent, ...)
		SkuChat_OnEvent(self, aEvent, ...)
	end)

	--join private messages
	SkuChat_RemoveAllPrivateMessageTargets(a)
	if SkuSettings:Sub("SkuChat").tabs[tNewTabIndex].privateMessages then
		for i, v in pairs(SkuSettings:Sub("SkuChat").tabs[tNewTabIndex].privateMessages) do
			--a.privateMessageList = nil--a.privateMessageList or {}
			SkuChat_AddPrivateMessageTarget(a, v)
		end
	end

	--exclude private messages
	--SkuChat_ReceiveAllPrivateMessages(a)
	a.excludePrivateMessageList = nil
	if SkuSettings:Sub("SkuChat").tabs[tNewTabIndex].excludePrivateMessages then
		for i, v in pairs(SkuSettings:Sub("SkuChat").tabs[tNewTabIndex].excludePrivateMessages) do
			a.excludePrivateMessageList = a.excludePrivateMessageList or {}
			SkuChat_ExcludePrivateMessageTarget(a, v)
		end
	end

	--join channels
	a.channelList = {}
	a.zoneChannelList = {}
	SkuChat_RemoveAllChannels(a)
	for i, v in pairs(SkuSettings:Sub("SkuChat").tabs[tNewTabIndex].channels) do
		if v.status ~= false then
			if SkuChat_ContainsChannel(a, v.name) ~= true then
				if v and v.name then
					SkuChat_AddChannel(a, v.name)
				end
			end
		end
	end

	--register message types
	a.messageTypeList = {}
	SkuChat_RemoveAllMessageGroups(a)
	for tCName, tData in pairs(SkuSettings:Sub("SkuChat").tabs[tNewTabIndex].messageTypes) do
		for x = 1, #tData do
			if tData[x] ~= false or (tCName == "CREATURE_MESSAGES" and x == 4) then
				if SkuChatChatTypeGroup[SkuChat.ChatFrameMessageTypes[tCName][x].type] then
					SkuChat_AddMessageGroup(a, SkuChat.ChatFrameMessageTypes[tCName][x].type)
				else
					SkuChat_AddSingleMessageType(a, SkuChat.ChatFrameMessageTypes[tCName][x].type)
				end

			end
		end
	end

	--AddMessage handler
	function a:AddMessage(messageTypeGroup, body, r, g, b, id, accessID, typeID, arg2)
		
		if messageTypeGroup ~= "ADDON" then
			--print(messageTypeGroup, body, r, g, b, id, accessID, typeID, arg2)
		end
		
		local tLink = string.match(body, "|Hitem:(.+)|h%[")
		if tLink then
			tLink = "item:"..tLink
		end

		local tItemLinks = {}
		for i in string.gmatch(body, "|Hitem:([^Hitem]+)|h%[") do
			tItemLinks[#tItemLinks + 1] = "item:"..i
			dprint(string.gsub(i, "|", "!"))
		end

		-- Quest-Hyperlinks (|Hquest:ID:LEVEL|h[Titel]|h|r) — analog
		-- zu Items extrahieren, damit der User mit Shift+Pfeil-rauf/runter
		-- die Quest aus dem Chat öffnen / vorlesen lassen kann.
		-- Sku speichert die Roh-Strings ("quest:12345:60") in
		-- tLineData.questLinks und löst sie beim Lesen via Quest-API
		-- bzw. SkuDB.questLookup auf.
		local tQuestLinks = {}
		for i in string.gmatch(body, "|Hquest:([^|]+)|h%[") do
			tQuestLinks[#tQuestLinks + 1] = "quest:"..i
		end
		
		if not body then
			return
		end
		
		if body == "" or body == " " then
			return
		end



		--mask bnet names
		body = MaskBattleNetNames(body)

		--get output type
		local tAudio
		-- tVoice: optional per-category/per-channel Blizzard-TTS voice (1-based
		-- index into SkuChat.WowTtsVoices). nil => use the global voice. Only
		-- consulted for the `play` (Blizzard TTS) branch below.
		local tVoice
		for i, v in pairs(SkuChat.ChatFrameMessageTypes) do
			for w = 1, #v do
				if v[w].type == messageTypeGroup then
					tAudio = a.tab.messageTypes[i][w]
					if a.tab.messageTypeVoice and a.tab.messageTypeVoice[i] then
						tVoice = a.tab.messageTypeVoice[i][w]
					end
				end
			end
		end
		if not tAudio then
			for x = 1, #a.tab.channels do
				if a.tab.channels[x].name == messageTypeGroup then
					tAudio = a.tab.channels[x].status
					tVoice = a.tab.channels[x].voice
				end
			end
		end

		if string.find(body, "Debug:") then
			tAudio = false
		end

		--process
		if tAudio ~= false then
			--remove old if > max
			if #a.tab.history + 1 > a.tab.historyMax then 
				for x = a.tab.historyMax, #a.tab.history do
					table.remove(a.tab.history, #a.tab.history)
				end
			end

			--remove empty if this is the first line for the history
			if a.tab and a.tab.history and a.tab.history[1] then
				if a.tab.history[1].body and a.tab.history[1].body == L["Empty"] then
					a.tab.history = {}
				end
			end

			local tFlatBody = string.gsub(SkuUtil:Unescape(body), "|", "")
			tFlatBody = SkuChat:ShortenChannelName(tFlatBody)

			-- Multisell-Auktionen: der Server schickt pro erstelltem Stack eine
			-- eigene, identische Systemzeile "Auktion erstellt."
			-- (ERR_AUCTION_STARTED). Bei n Stacks sind das n gleiche Zeilen und
			-- damit Sprach-Spam. Die Auktions-Ansage von Sku nennt die Anzahl
			-- ohnehin selbst ("n Auktionen erstellt"), daher diese BLOSSE
			-- Bestätigung weder vorlesen noch den Neue-Nachricht-Ton spielen.
			-- Nur die EXAKTE Konstante wird geschluckt — jede Zeile mit
			-- Zusatzinfo (die nicht exakt der Konstante entspricht) läuft normal
			-- durch und wird vorgelesen, geht also nicht verloren.
			local tIsBareAuctionCreated = (messageTypeGroup == "SYSTEM")
				and (type(ERR_AUCTION_STARTED) == "string")
				and (body == ERR_AUCTION_STARTED)

			--audio output
			if tAudio == play and not tIsBareAuctionCreated then
				-- Blizzard TTS. tVoice (per-category/channel, 1-based index) rides
				-- along on the queued string and overrides the global voice for
				-- just this line; nil => global voice (unchanged legacy behaviour).
				SkuOptions.Voice:OutputStringBTtts(tFlatBody, {wait = true, length = 0.2, engine = 2, voice = tVoice})
			elseif tAudio == skuTts and not tIsBareAuctionCreated then
				-- Sku's own TTS (pre-recorded audio-file engine).
				SkuOptions.Voice:OutputString(tFlatBody, false, true, 0.2)
			end

			if a.tab.audioOnNewMessage and not tIsBareAuctionCreated then
				if SkuState:IsInCombat() == true then
				else
					if SkuSettings:Sub("SkuChat").tabs[tNewTabIndex].audioOnNewMessage ~= "sound-silence0.1" then
						SkuOptions.Voice:OutputString(SkuSettings:Sub("SkuChat").tabs[tNewTabIndex].audioOnNewMessage, false, true, 0.1)
					end
				end
			end

			--add to history
			table.insert(a.tab.history, 1, {
				body = tFlatBody,
				link = tLink,
				itemLinks = tItemLinks,
				questLinks = tQuestLinks,
				messageTypeGroup = messageTypeGroup,
				audio = tAudio,
				accessID = accessID,
				typeID = typeID,
				arg2 = arg2,
				time = time(),
			})

			--change the current line if the chat is open
			if SkuChat.ChatOpen == true then
				if a.tab.historyCurrentLine < #a.tab.history then
					if _G["OnSkuChatToggle"].menuOpen ~= true then
						a.tab.historyCurrentLine = a.tab.historyCurrentLine + 1
					end
				end
			end

			--update activity timestamp for auto deleting the tab
			a.tab.lastActivityAt = time()
		end
	end

	SkuChat:RegisterChatFrame(tNewTabIndex)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuChat:NewTab(aName)
	if #SkuSettings:Sub("SkuChat").tabs < SkuChat.maxTabs then
		local tNewTabIndex = #SkuSettings:Sub("SkuChat").tabs + 1

		SkuSettings:Sub("SkuChat").tabs[tNewTabIndex] = {
			name = aName or L["Default Tab"],
			frameName = "SkuChatChatFrame"..tNewTabIndex,
			enabled = true,
			messageTypes = {
				PLAYER_MESSAGES = {},
				CREATURE_MESSAGES = {},
				OTHER = {},
				PVP = {},
				SYSTEM = {},
				COMBAT = {},
				SKU = {},
			},
			channels = {},
			privateMessages = {},
			excludePrivateMessages = {},
			history = {},
			historyCurrentLine = 1,
			historyMax = SkuChat.defaultHistoryMax,
			audioOnNewMessage = "sound-newChatLine",--SkuSettings:Sub("SkuChat").chatSettings.audioOnNewMessage,
			createdAt = time(),
			lastActivityAt = time(),
		}

		SkuChat:ResetTab(tNewTabIndex)

		--re-initialise all tabs, just in case
		for x = 1, #SkuSettings:Sub("SkuChat").tabs do
			if _G[SkuSettings:Sub("SkuChat").tabs[x].frameName] then
				_G[SkuSettings:Sub("SkuChat").tabs[x].frameName]:UnregisterAllEvents() 
			end
			SkuSettings:Sub("SkuChat").tabs[x].frameName = "SkuChatChatFrame"..x
			SkuChat:InitTab(x)
		end

		return tNewTabIndex
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuChat:RegisterChatFrame(aFrameIndex)
	local tFrameList = {}

	for x = 1, #SkuSettings:Sub("SkuChat").tabs do
		table.insert(tFrameList, x)
	end
	if aFrameIndex then
		tFrameList = {}
		table.insert(tFrameList, aFrameIndex)
	end

	for _, tFrameIndex in pairs(tFrameList) do
		SkuChat_OnLoad(_G[SkuSettings:Sub("SkuChat").tabs[tFrameIndex].frameName])
		SkuChat_ConfigEventHandler(_G[SkuSettings:Sub("SkuChat").tabs[tFrameIndex].frameName], "UPDATE_CHAT_WINDOWS")
	end
end