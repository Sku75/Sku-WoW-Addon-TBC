local MODULE_NAME = "SkuOptions"
local L = Sku.L


SkuCore.SoftTargetingArcValues = {
	[0] = L["Only directly in front"],
	[1] = L["15 degrees in front"],
	[2] = L["180 degrees in front"],
}
SkuCore.SofttargetingForceValues  = {
	[0] = L["Off"],
	[1] = L["Enemies"],
	[2] = L["Friends"],
}
SkuCore.SofttargetingMatchLockedValues  = {
	[0] = L["Always"],
	[1] = L["If no hard target locked"],
	[2] = L["No attackable hard target locked"],
	--[2] = L["Targets you attack"],
}
SkuCore.SofttargetingInteractNameForValues  = {
	[1] = L["Nothing"],
	[2] = L["Objects"],
	[3] = L["Objects and lootable/skinnable"],
	[4] = L["Objects and lootable/skinnable and units"],
}
do
	SkuCore.SofttargetingSoundsValue = {}
	SkuCore.SofttargetingSoundsValue[" "] = L["silent"]
	for i, v in pairs (SkuAuras.outputSoundFiles) do
		SkuCore.SofttargetingSoundsValue[i] = v
	end
end

--------------------------------------------------------------------------------------------------------------------------------------
-- The game sound CVars belong to the GAME, not to Sku: the client persists them
-- in Config.wtf on its own. Sku reads and writes them and keeps NO copy of its
-- own. The copy it used to keep was profile-scoped while the CVars are not, and
-- it was pushed back over the game's values at every login -- so a volume set on
-- one character came back at the old value on the next one whose AceDB profile
-- pointer resolved elsewhere.
local function tGetSoundCVarPercent(aCVar)
	local tValue = tonumber(C_CVar.GetCVar(aCVar))
	if not tValue then
		return 100
	end
	-- round, do not floor: tonumber("0.35") * 100 is 34.999... and would read back one step low
	return math.floor((tValue * 100) + 0.5)
end

local function tSetSoundCVarPercent(aCVar, aValue)
	C_CVar.SetCVar(aCVar, (tonumber(aValue) or 0) / 100)
end

local function tGetSoundCVarBool(aCVar)
	return C_CVar.GetCVar(aCVar) == "1"
end

--------------------------------------------------------------------------------------------------------------------------------------
SkuOptions.options = {
	name = MODULE_NAME,
	handler = SkuOptions,
	type = "group",
	args = {
		vocalizeMenuNumbers = {
			order = 1,
			name = L["Menünummern ansagen"],
			desc = "",
			type = "toggle",
		},
		vocalizeSubmenus = {
			order = 2,
			name = L["Untermenüs ansagen"] ,
			desc = "",
			type = "toggle",
		},
		TTSSepPause = {
			order = 3,
			name = L["Audio Dauer Pause"] ,
			desc = "",
			type = "range",
			forAudioMenu = false,   -- W7: surfaced under Einstellungen -> Sprachausgabe
		},
		backgroundSound = {
			order = 4,
			name = L["Hintergrund Audio"] ,
			desc = "",
			type = "select",
			values = SkuCore.BackgroundSoundFiles,
			forAudioMenu = false,   -- W8: surfaced under Einstellungen -> Audio
		},
		localActive = {
			order = 5,
			name = L["Lokal aktiv"] ,
			desc = "",
			type = "toggle",
		},
		--[[
		useBlizzTtsInMenu = {
			order = 6,
			name = L["Use Blizzard TTS for audio menu"],
			desc = "",
			type = "toggle",
			set = function(info,val)
				SkuSettings:Sub("SkuOptions").useBlizzTtsInMenu = val
			end,
			get = function(info)
				return SkuSettings:Sub("SkuOptions").useBlizzTtsInMenu
			end
		},
		]]
		soundChannels={
			name = L["Audio-Kanäle"],
			type = "group",
			order = 6,
			forAudioMenu = false,   -- W8: surfaced under Einstellungen -> Audio
			args= {
					MasterVolume = {
						order = 2,
						name = L["Gesamt Lautstärke"] ,
						desc = "",
						type = "range",
						set = function(info,val)
							tSetSoundCVarPercent("Sound_MasterVolume", val)
						end,
						get = function(info)
							return tGetSoundCVarPercent("Sound_MasterVolume")
						end
					},
					SFXVolume = {
						order = 3,
						name = L["Soundeffekte Lautstärke"] ,
						desc = "",
						type = "range",
						set = function(info,val)
							tSetSoundCVarPercent("Sound_SFXVolume", val)
						end,
						get = function(info)
							return tGetSoundCVarPercent("Sound_SFXVolume")
						end
					},
					MusicVolume = {
						order = 5,
						name = L["Musik Lautstärke"] ,
						desc = "",
						type = "range",
						set = function(info,val)
							tSetSoundCVarPercent("Sound_MusicVolume", val)
						end,
						get = function(info)
							return tGetSoundCVarPercent("Sound_MusicVolume")
						end
					},
					AmbienceVolume = {
						order = 6,
						name = L["Umgebung Lautstärke"] ,
						desc = "",
						type = "range",
						set = function(info,val)
							tSetSoundCVarPercent("Sound_AmbienceVolume", val)
						end,
						get = function(info)
							return tGetSoundCVarPercent("Sound_AmbienceVolume")
						end
					},
					DialogVolume = {
						order = 7	,
						name = L["Dialog Lautstärke"] ,
						desc = "",
						type = "range",
						set = function(info,val)
							tSetSoundCVarPercent("Sound_DialogVolume", val)
						end,
						get = function(info)
							return tGetSoundCVarPercent("Sound_DialogVolume")
						end
					},
					SkuChannel = {
						order = 8,
						name = L["Sku Kanal"] ,
						desc = "",
						type = "select",
						values = SKU_CONSTANTS.SOUNDCHANNELS,
					},
				},
			},
		soundSettings={
			name = L["Sound Settings"],
			type = "group",
			order = 7,
			forAudioMenu = false,   -- W8: surfaced under Einstellungen -> Audio
			args= {
				Sound_EnableReverb = {
					order = 1,
					name = L["Reverb"],
					desc = "",
					type = "toggle",
					OnAction = function(self, info, val)
						if val == true then
							C_CVar.SetCVar("Sound_EnableReverb", 1)
						else
							C_CVar.SetCVar("Sound_EnableReverb", 0)
						end
					end,
					set = function(info,val)
						if val == true then
							C_CVar.SetCVar("Sound_EnableReverb", 1)
						else
							C_CVar.SetCVar("Sound_EnableReverb", 0)
						end
					end,
					get = function(info)
						return tGetSoundCVarBool("Sound_EnableReverb")
					end
				},
				Sound_EnablePositionalLowPassFilter = {
					order = 2,
					name = L["Positional Low Pass Filter"],
					desc = "",
					type = "toggle",
					OnAction = function(self, info, val)
						if val == true then
							C_CVar.SetCVar("Sound_EnablePositionalLowPassFilter", 1)
						else
							C_CVar.SetCVar("Sound_EnablePositionalLowPassFilter", 0)
						end
					end,
					set = function(info,val)
						if val == true then
							C_CVar.SetCVar("Sound_EnablePositionalLowPassFilter", 1)
						else
							C_CVar.SetCVar("Sound_EnablePositionalLowPassFilter", 0)
						end
					end,
					get = function(info)
						return tGetSoundCVarBool("Sound_EnablePositionalLowPassFilter")
					end
				},
				Sound_EnableDSPEffects = {
					order = 3,
					name = L["DSP Effects"],
					desc = "",
					type = "toggle",
					OnAction = function(self, info, val)
						if val == true then
							C_CVar.SetCVar("Sound_EnableDSPEffects", 1)
						else
							C_CVar.SetCVar("Sound_EnableDSPEffects", 0)
						end
					end,
					set = function(info,val)
						if val == true then
							C_CVar.SetCVar("Sound_EnableDSPEffects", 1)
						else
							C_CVar.SetCVar("Sound_EnableDSPEffects", 0)
						end
					end,
					get = function(info)
						return tGetSoundCVarBool("Sound_EnableDSPEffects")
					end
				},
				Sound_EnableSoundWhenGameIsInBG = {
					order = 4,
					name = L["Sound When Game Is In Background"],
					desc = "",
					type = "toggle",
					OnAction = function(self, info, val)
						if val == true then
							C_CVar.SetCVar("Sound_EnableSoundWhenGameIsInBG", 1)
						else
							C_CVar.SetCVar("Sound_EnableSoundWhenGameIsInBG", 0)
						end
					end,
					set = function(info,val)
						if val == true then
							C_CVar.SetCVar("Sound_EnableSoundWhenGameIsInBG", 1)
						else
							C_CVar.SetCVar("Sound_EnableSoundWhenGameIsInBG", 0)
						end
					end,
					get = function(info)
						return tGetSoundCVarBool("Sound_EnableSoundWhenGameIsInBG")
					end
				},
				Sound_ZoneMusicNoDelay = {
					order = 5,
					name = L["Zone Music No Delay"],
					desc = "",
					type = "toggle",
					OnAction = function(self, info, val)
						if val == true then
							C_CVar.SetCVar("Sound_ZoneMusicNoDelay", 1)
						else
							C_CVar.SetCVar("Sound_ZoneMusicNoDelay", 0)
						end
					end,
					set = function(info,val)
						if val == true then
							C_CVar.SetCVar("Sound_ZoneMusicNoDelay", 1)
						else
							C_CVar.SetCVar("Sound_ZoneMusicNoDelay", 0)
						end
					end,
					get = function(info)
						return tGetSoundCVarBool("Sound_ZoneMusicNoDelay")
					end
				},
			},
		},

						
		debugOptions={
			name = L["Debug Optionen"],
			type = "group",
			order = 8,
			args= {
				soundOnError = {
					order = 2,
					name = L["Sound bei Fehler"] ,
					desc = "",
					type = "toggle",
				},
			},
		},
	
		allModules={
			name = L["Schnellwahl"],
			type = "group",
			order = 9,
			-- Hidden: slots 1-4 are now dedicated hardwired keys (Shift-F9/F10/F11/F12),
			-- so these path-input fields no longer do anything. Kept in the schema so
			-- saved values migrate cleanly; just not shown in the menu.
			forAudioMenu = false,
			args={
					MenuQuickSelect1 = {
						order = 1,
						name = L["Schnellwahl 1"] ,
						desc = "",
						type = "input",
					},
					MenuQuickSelect2 = {
						order = 2,
						name = L["Schnellwahl 2"] ,
						desc = "",
						type = "input",
					},
					MenuQuickSelect3 = {
						order = 3,
						name = L["Schnellwahl 3"] ,
						desc = "",
						type = "input",
					},
					MenuQuickSelect4 = {
						order = 4,
						name = L["Schnellwahl 4"] ,
						desc = "",
						type = "input",
					},
				},
			},
			softTargeting={
				name = L["Soft targeting"],
				type = "group",
				order = 10,
				forAudioMenu = false,   -- surfaced under the top-level "Werkzeuge" (Tools) menu
				args= {
					enemy={
						name = L["Enemies"],
						type = "group",
						order = 1,
						args= {
							enabled = {
								order = 1,
								name = L["Enabled"] ,
								desc = "",
								type = "toggle",
								OnAction = function(self, info, val)
									SkuOptions:UpdateSoftTargetingSettings("all")
								end,
							},
							arc = {
								order = 2,
								name = L["Arc"] ,
								desc = "",
								type = "select",
								OnAction = function(self, info, val)
									SkuOptions:UpdateSoftTargetingSettings("all")
								end,
								values = SkuCore.SoftTargetingArcValues,
							},							
							range = {
								order = 3,
								name = L["Range"] ,
								desc = "",
								type = "range",
								OnAction = function(self, info, val)
									SkuOptions:UpdateSoftTargetingSettings("all")
								end,
								min = 1,
								max = 60,
							},		
							forPlayers = {
								order = 4,
								name = L["Include players"] ,
								desc = "",
								type = "toggle",
								OnAction = function(self, info, val)
									SkuOptions:UpdateSoftTargetingSettings("all")
								end,
							},
							forPets = {
								order = 5,
								name = L["Include pets"] ,
								desc = "",
								type = "toggle",
								OnAction = function(self, info, val)
									SkuOptions:UpdateSoftTargetingSettings("all")
								end,
							},							
							forPassive = {
								order = 5,
								name = L["Include passive units"] ,
								desc = "",
								type = "toggle",
								OnAction = function(self, info, val)
									SkuOptions:UpdateSoftTargetingSettings("all")
								end,
							},
							sound = {
								order = 6,
								name = L["sound on enemy soft target"] ,
								desc = "",
								type = "select",
								OnAction = function(self, info, val)
									SkuOptions:UpdateSoftTargetingSettings("all")
								end,
								values = SkuCore.SofttargetingSoundsValue,
							},									
							soundNoTarget = {
								order = 6.5,
								name = L["Sound on empty enemy soft target"],
								desc = "",
								type = "select",
								OnAction = function(self, info, val)
									SkuOptions:UpdateSoftTargetingSettings("all")
								end,
								values = SkuCore.SofttargetingSoundsValue,
							},									

							outputName = {
								order = 7,
								name = L["Output unit name"] ,
								desc = "",
								type = "toggle",
								OnAction = function(self, info, val)
									SkuOptions:UpdateSoftTargetingSettings("all")
								end,
							},
							muteInCombat = {
								order = 8,
								name = L["Mute in Combat"],
								desc = "",
								type = "toggle",
								OnAction = function(self, info, val)
									SkuOptions:UpdateSoftTargetingSettings("all")
								end,
							},
						},
					},
					friend={
						name = L["Friends"],
						type = "group",
						order = 2,
						args= {
							enabled = {
								order = 1,
								name = L["Enabled"] ,
								desc = "",
								type = "toggle",
								OnAction = function(self, info, val)
									SkuOptions:UpdateSoftTargetingSettings("all")
								end,
							},
							arc = {
								order = 2,
								name = L["Arc"] ,
								desc = "",
								type = "select",
								OnAction = function(self, info, val)
									SkuOptions:UpdateSoftTargetingSettings("all")
								end,
								values = SkuCore.SoftTargetingArcValues,
							},							
							range = {
								order = 3,
								name = L["Range"] ,
								desc = "",
								type = "range",
								OnAction = function(self, info, val)
									SkuOptions:UpdateSoftTargetingSettings("all")
								end,
								min = 1,
								max = 60,
							},		
							forPlayers = {
								order = 4,
								name = L["Include players"] ,
								desc = "",
								type = "toggle",
								OnAction = function(self, info, val)
									SkuOptions:UpdateSoftTargetingSettings("all")
								end,
							},
							forPets = {
								order = 5,
								name = L["Include pets"] ,
								desc = "",
								type = "toggle",
								OnAction = function(self, info, val)
									SkuOptions:UpdateSoftTargetingSettings("all")
								end,
							},
							sound = {
								order = 6,
								name = L["sound on friendly soft target"],
								desc = "",
								type = "select",
								OnAction = function(self, info, val)
									SkuOptions:UpdateSoftTargetingSettings("all")
								end,
								values = SkuCore.SofttargetingSoundsValue,
							},			
							soundNoTarget = {
								order = 6.5,
								name = L["Sound on empty friendly soft target"],
								desc = "",
								type = "select",
								OnAction = function(self, info, val)
									SkuOptions:UpdateSoftTargetingSettings("all")
								end,
								values = SkuCore.SofttargetingSoundsValue,
							},									

							outputName = {
								order = 7,
								name = L["Output unit name"] ,
								desc = "",
								type = "toggle",
								OnAction = function(self, info, val)
									SkuOptions:UpdateSoftTargetingSettings("all")
								end,
							},													
						},
					},
					interact={
						name = L["Interact"],
						type = "group",
						order = 3,
						args= {
							enabled = {
								order = 1,
								name = L["Enabled"] ,
								desc = "",
								type = "toggle",
								OnAction = function(self, info, val)
									SkuOptions:UpdateSoftTargetingSettings("all")
								end,
							},
							arc = {
								order = 2,
								name = L["Arc"] ,
								desc = "",
								type = "select",
								OnAction = function(self, info, val)
									SkuOptions:UpdateSoftTargetingSettings("all")
								end,
								values = SkuCore.SoftTargetingArcValues,
							},							
							range = {
								order = 3,
								name = L["Range"] ,
								desc = "",
								type = "range",
								OnAction = function(self, info, val)
									SkuOptions:UpdateSoftTargetingSettings("all")
								end,
								min = 1,
								max = 15,
							},		
							soundfor = {
								order = 4,
								name = L["Output sound for"],
								desc = "",
								type = "select",
								OnAction = function(self, info, val)
									SkuOptions:UpdateSoftTargetingSettings("all")
								end,
								values = SkuCore.SofttargetingInteractNameForValues,
							},				
							sound = {
								order = 5,
								name = L["sound on interact soft target"] ,
								desc = "",
								type = "select",
								OnAction = function(self, info, val)
									SkuOptions:UpdateSoftTargetingSettings("all")
								end,
								values = SkuCore.SofttargetingSoundsValue,
							},			
							soundNoTarget = {
								order = 5.5,
								name = L["Sound on empty interact soft target"],
								desc = "",
								type = "select",
								OnAction = function(self, info, val)
									SkuOptions:UpdateSoftTargetingSettings("all")
								end,
								values = SkuCore.SofttargetingSoundsValue,
							},																								
							unitNameFor = {
								order = 6,
								name = L["Output name for"] ,
								desc = "",
								type = "select",
								OnAction = function(self, info, val)
									SkuOptions:UpdateSoftTargetingSettings("all")
								end,
								values = SkuCore.SofttargetingInteractNameForValues,
							},							

							outputBTTS = {
								order = 8,
								name = L["Name output via Blizzard TTS"] ,
								desc = "",
								type = "toggle",
								OnAction = function(self, info, val)
									SkuOptions:UpdateSoftTargetingSettings("all")
								end,
							},									
						},
					},
					force = {
						order = 5,
						name = L["Auto set hard target to soft target for"] ,
						desc = "",
						type = "select",
						OnAction = function(self, info, val)
							SkuOptions:UpdateSoftTargetingSettings("all")
						end,
						values = SkuCore.SofttargetingForceValues,
					},							
					matchLocked = {
						order = 6,
						name = L["Do interact soft targeting if"],
						desc = "",
						type = "select",
						OnAction = function(self, info, val)
							SkuOptions:UpdateSoftTargetingSettings("all")
						end,
						values = SkuCore.SofttargetingMatchLockedValues,
					},		
					enableDisableOutputInChat = {
						order = 7,
						name = L["Chat notification on enabling/disabling soft targeting categories"] ,
						desc = "",
						type = "toggle",
						OnAction = function(self, info, val)
							SkuOptions:UpdateSoftTargetingSettings("all")
						end,
					},									

				}
			},			
		},

}
---------------------------------------------------------------------------------------------------------------------------------------
SkuOptions.defaults = {
	vocalizeMenuNumbers = true,
	vocalizeSubmenus = true,
	TTSSepPause = 85,
	backgroundSound = "silence.mp3",
	localActive = true,
	visualAudioMenu = false,
	--useBlizzTtsInMenu = false,
	allModules  = {
		-- Slots 1-4 are now dedicated hardwired keys (handled directly in
		-- SkuZOptions OnClick), NOT audio-menu-path walks: Shift-F9 = nearby
		-- waypoints, Shift-F10 = nearby route destinations, Shift-F11 = action bars,
		-- Shift-F12 = cancel navigation. Their stored paths are no longer read on
		-- press, so the old fragile localized defaults are cleared. Slots 5-10 stay
		-- available as generic user-set menu bookmarks.
		MenuQuickSelect1 = "",
		MenuQuickSelect2 = "",
		MenuQuickSelect3 = "",
		MenuQuickSelect4 = "",
		},
	soundChannels  = {
		SkuChannel = "Talking Head",
		},
		softTargeting = {
			enemy = {
				enabled = false,
				arc = 1,
				range = 60,
				forPassive = true,
				forPlayers = false,
				forPets = false,
				sound = "sound-notification26",
				soundNoTarget = " ",
				outputName = true,
				muteInCombat = false,
			},
			friend = {
				enabled = false,
				arc = 1,
				range = 60,
				forPlayers = false,
				forPets = false,
				sound = "sound-notification27",
				soundNoTarget = " ",
				outputName = true,
			},
			interact = {
				enabled = false,
				arc = 2,
				range = 15,
				soundfor = 4,
				unitNameFor = 4,
				sound = "sound-notification25",
				soundNoTarget = " ",
				outputBTTS = true,
			},
			force = 0, --0 1 2 target wird softtarget 		Auto-set target to match soft target. 1 = for enemies, 2 = for friends
			matchLocked = 2, --0 1 softtarget immer locked wenn target 2?	Match appropriate soft target to locked target. 1 = hard locked target only, 2 = for targets you attack
			enableDisableOutputInChat = true,
		},				
	debugOptions = {
		soundOnError = false,
		},
	}

---------------------------------------------------------------------------------------------------------------------------------------
-- Settings schema for SkuOptions (Sku 42 rework, W1 Phase C / W2 MC1). All
-- keys profile scope (the menu renders via SkuSettings:Sub("SkuOptions")).
-- Pure-storage leaves are schema-managed (get/set stripped above); leaves
-- whose set/get carried a side effect (C_CVar sound channel/settings writes)
-- keep their inline handlers and are listed here only for the schema.
SkuSettings:Register("SkuOptions", {
	["vocalizeMenuNumbers"] = { scope = "profile", default = true, type = "boolean" },
	["vocalizeSubmenus"] = { scope = "profile", default = true, type = "boolean" },
	["TTSSepPause"] = { scope = "profile", default = 85, type = "number" },
	["backgroundSound"] = { scope = "profile", default = "silence.mp3", type = "string" },
	["localActive"] = { scope = "profile", default = true, type = "boolean" },
	["soundChannels.SkuChannel"] = { scope = "profile", default = "Talking Head", type = "string" },
	["debugOptions.soundOnError"] = { scope = "profile", default = false, type = "boolean" },
	["allModules.MenuQuickSelect1"] = { scope = "profile", default = "", type = "string" },
	["allModules.MenuQuickSelect2"] = { scope = "profile", default = "", type = "string" },
	["allModules.MenuQuickSelect3"] = { scope = "profile", default = "", type = "string" },
	["allModules.MenuQuickSelect4"] = { scope = "profile", default = "", type = "string" },
	["softTargeting.enemy.enabled"] = { scope = "profile", default = false, type = "boolean" },
	["softTargeting.enemy.arc"] = { scope = "profile", default = 1, type = "number" },
	["softTargeting.enemy.range"] = { scope = "profile", default = 60, type = "number" },
	["softTargeting.enemy.forPlayers"] = { scope = "profile", default = false, type = "boolean" },
	["softTargeting.enemy.forPets"] = { scope = "profile", default = false, type = "boolean" },
	["softTargeting.enemy.forPassive"] = { scope = "profile", default = true, type = "boolean" },
	["softTargeting.enemy.sound"] = { scope = "profile", default = "sound-notification26", type = "string" },
	["softTargeting.enemy.soundNoTarget"] = { scope = "profile", default = " ", type = "string" },
	["softTargeting.enemy.outputName"] = { scope = "profile", default = true, type = "boolean" },
	["softTargeting.enemy.muteInCombat"] = { scope = "profile", default = false, type = "boolean" },
	["softTargeting.friend.enabled"] = { scope = "profile", default = false, type = "boolean" },
	["softTargeting.friend.arc"] = { scope = "profile", default = 1, type = "number" },
	["softTargeting.friend.range"] = { scope = "profile", default = 60, type = "number" },
	["softTargeting.friend.forPlayers"] = { scope = "profile", default = false, type = "boolean" },
	["softTargeting.friend.forPets"] = { scope = "profile", default = false, type = "boolean" },
	["softTargeting.friend.sound"] = { scope = "profile", default = "sound-notification27", type = "string" },
	["softTargeting.friend.soundNoTarget"] = { scope = "profile", default = " ", type = "string" },
	["softTargeting.friend.outputName"] = { scope = "profile", default = true, type = "boolean" },
	["softTargeting.interact.enabled"] = { scope = "profile", default = false, type = "boolean" },
	["softTargeting.interact.arc"] = { scope = "profile", default = 2, type = "number" },
	["softTargeting.interact.range"] = { scope = "profile", default = 15, type = "number" },
	["softTargeting.interact.soundfor"] = { scope = "profile", default = 4, type = "number" },
	["softTargeting.interact.unitNameFor"] = { scope = "profile", default = 4, type = "number" },
	["softTargeting.interact.sound"] = { scope = "profile", default = "sound-notification25", type = "string" },
	["softTargeting.interact.soundNoTarget"] = { scope = "profile", default = " ", type = "string" },
	["softTargeting.interact.outputBTTS"] = { scope = "profile", default = true, type = "boolean" },
	["softTargeting.force"] = { scope = "profile", default = 0, type = "number" },
	["softTargeting.matchLocked"] = { scope = "profile", default = 2, type = "number" },
	["softTargeting.enableDisableOutputInChat"] = { scope = "profile", default = true, type = "boolean" },
})

--------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:MenuBuilder(aParentEntry)
	-- W7: render directly into the parent (Einstellungen -> Allgemein) instead of an
	-- extra "Optionen" wrapper node. tNewMenuEntry is aliased so the rest of this
	-- builder (Overview pages, Profil, ...) keeps attaching to the same parent.
	local tNewMenuEntry = aParentEntry
	tNewMenuEntry.sorting = true
	SkuOptions:IterateOptionsArgs(SkuOptions.options.args, tNewMenuEntry, SkuSettings:Sub("SkuOptions"), "SkuOptions")


	local tNewMenuParentEntry =  SkuOptions:InjectMenuItems(tNewMenuEntry, {L["Overview pages"]}, SkuGenericMenuItem)
	tNewMenuParentEntry.dynamic = true
	tNewMenuParentEntry.BuildChildren = function(self)
		for q = 1, 2 do
			local tNewMenuParentEntry =  SkuOptions:InjectMenuItems(self, {L["Overview page "]..q}, SkuGenericMenuItem)
			tNewMenuParentEntry.dynamic = true
			tNewMenuParentEntry.isSelect = true
			tNewMenuParentEntry.pageId = nil
			tNewMenuParentEntry.tEntry = nil
			tNewMenuParentEntry.OnAction = function(self, aValue, aName)
				local tlName, tPos = string.split(";", self.tEntry)
				for i, v in pairs(SkuSettings:Sub("SkuOptions").overviewPages[self.pageId].overviewSections) do
					if v.locName == tlName then
						if aName == L["Up"] then
							for i1, v1 in pairs(SkuSettings:Sub("SkuOptions").overviewPages[self.pageId].overviewSections) do
								if v1.pos == (tonumber(tPos) - 1) then
									v1.pos = tonumber(tPos)
									SkuSettings:Sub("SkuOptions").overviewPages[self.pageId].overviewSections[i].pos = tonumber(tPos) - 1
									break
								end
							end
						elseif aName == L["Down"] then
							for i1, v1 in pairs(SkuSettings:Sub("SkuOptions").overviewPages[self.pageId].overviewSections) do
								if v1.pos == (tonumber(tPos) + 1) then
									v1.pos = tonumber(tPos)
									SkuSettings:Sub("SkuOptions").overviewPages[self.pageId].overviewSections[i].pos = tonumber(tPos) + 1
									break
								end
							end
						elseif aName == L["Show"] then
							local tMax = 0
							for i1, v1 in pairs(SkuSettings:Sub("SkuOptions").overviewPages[self.pageId].overviewSections) do
								if tonumber(v1.pos) > tMax and tonumber(v1.pos) ~= 999 then
									tMax = v1.pos
								end
							end
							v.pos = tMax + 1
						elseif aName == L["Hide"] then
							local tFrom = tonumber(v.pos)
							for i1, v1 in pairs(SkuSettings:Sub("SkuOptions").overviewPages[self.pageId].overviewSections) do
								if v1.pos >= tFrom and v1.pos ~= 999 then
									v1.pos = v1.pos - 1
								end
							end
							v.pos = 999
						end

						return
					end
				end
			end
			tNewMenuParentEntry.BuildChildren = function(self)
				local tSorted = {}
				for k, v in SkuSpairs(SkuSettings:Sub("SkuOptions").overviewPages[q].overviewSections, function(t,a,b) return t[b].pos > t[a].pos end) do
					table.insert(tSorted, k)
				end
				local tNumberItems = #tSorted
				for x = 1, #tSorted do
					local tPos = SkuSettings:Sub("SkuOptions").overviewPages[q].overviewSections[tSorted[x]].pos
					local tPosName = tPos
					if tPosName == 999 then
						tPosName = L["hidden"]
						tNumberItems = tNumberItems - 1
					end
					local tNewMenuSubEntry = SkuOptions:InjectMenuItems(self, {SkuSettings:Sub("SkuOptions").overviewPages[q].overviewSections[tSorted[x]].locName..";"..tPosName}, SkuGenericMenuItem)
					tNewMenuSubEntry.dynamic = true
					tNewMenuSubEntry.OnEnter = function(self, aValue, aName)
						self.selectTarget.pageId = q
						self.selectTarget.tEntry = SkuSettings:Sub("SkuOptions").overviewPages[q].overviewSections[tSorted[x]].locName..";"..tPosName
					end

					tNewMenuSubEntry.BuildChildren = function(self)
						if tPos > 1 and tPos < 999 then
							SkuOptions:InjectMenuItems(self, {L["Up"]}, SkuGenericMenuItem)
						end
						if tPos < tNumberItems then
							SkuOptions:InjectMenuItems(self, {L["Down"]}, SkuGenericMenuItem)
						end
						if tPos == 999 then
							SkuOptions:InjectMenuItems(self, {L["Show"]}, SkuGenericMenuItem)
						else
							SkuOptions:InjectMenuItems(self, {L["Hide"]}, SkuGenericMenuItem)
						end

					end
				end
			end
		end
	end

	local tNewMenuParentEntry =  SkuOptions:InjectMenuItems(tNewMenuEntry, {L["Profil"]}, SkuGenericMenuItem)
	local tNewMenuSubEntry =SkuOptions:InjectMenuItems(tNewMenuParentEntry, {L["Auswählen"]}, SkuGenericMenuItem)
	tNewMenuSubEntry.dynamic = true
	tNewMenuSubEntry.isSelect = true
	tNewMenuSubEntry.OnAction = function(self, aValue, aName)
		SkuOptions.db:SetProfile(aName)
	end
	tNewMenuSubEntry.BuildChildren = function(self)
		local tList = SkuOptions.db:GetProfiles()
		local tNewMenuEntry = SkuOptions:InjectMenuItems(self, tList, SkuGenericMenuItem)
	end
	tNewMenuSubEntry.GetCurrentValue = function(self, aValue, aName)
		return SkuOptions.db:GetCurrentProfile()
	end

	local tNewMenuSubEntry =SkuOptions:InjectMenuItems(tNewMenuParentEntry, {L["New"]}, SkuGenericMenuItem)
	tNewMenuSubEntry.dynamic = false
	tNewMenuSubEntry.isSelect = true
	tNewMenuSubEntry.OnAction = function(self, aValue, aName)
		SkuOptions:EditBoxShow(
			"",
			function(self)
				local tText = SkuOptionsEditBoxEditBox:GetText()
				if tText and tText ~= "" then
					for i, v in pairs(SkuOptions.db:GetProfiles()) do
						if v == tText then
							C_Timer.After(0.1, function()
								SkuOptions.Voice:OutputStringBTtts(L["name already taken"], true, true, 1, true)
							end)
							return
						end
					end
					SkuOptions.db:SetProfile(tText)
				end
			end,
			nil
		)
		C_Timer.After(0.1, function()
			SkuOptions.Voice:OutputStringBTtts(L["enter profile name now"], true, true, 1, true)
		end)
	end

	local tNewMenuSubEntry =SkuOptions:InjectMenuItems(tNewMenuParentEntry, {L["Kopieren von"]}, SkuGenericMenuItem)
	tNewMenuSubEntry.dynamic = true
	tNewMenuSubEntry.isSelect = true
	tNewMenuSubEntry.OnAction = function(self, aValue, aName)
		SkuOptions.db:CopyProfile(aName, true)
	end
	tNewMenuSubEntry.BuildChildren = function(self)
		local tList = SkuOptions.db:GetProfiles()
		local tNewMenuEntry = SkuOptions:InjectMenuItems(self, tList, SkuGenericMenuItem)
	end
	tNewMenuSubEntry.GetCurrentValue = function(self, aValue, aName)
		return SkuOptions.db:GetCurrentProfile()
	end

	local tNewMenuSubEntry =SkuOptions:InjectMenuItems(tNewMenuParentEntry, {L["Löschen"]}, SkuGenericMenuItem)
	tNewMenuSubEntry.dynamic = true
	tNewMenuSubEntry.isSelect = true
	tNewMenuSubEntry.OnAction = function(self, aValue, aName)
		SkuOptions.db:DeleteProfile(aName)
	end
	tNewMenuSubEntry.BuildChildren = function(self)
		local tList = SkuOptions.db:GetProfiles()
		local tClean = {}
		for i, v in pairs(tList) do
			if v ~= SkuOptions.db:GetCurrentProfile() then
				table.insert(tClean, v)
			end
		end
		local tNewMenuEntry = SkuOptions:InjectMenuItems(self, tClean, SkuGenericMenuItem)
	end
	
	local tNewMenuSubEntry =SkuOptions:InjectMenuItems(tNewMenuParentEntry, {L["Zurücksetzen"]}, SkuGenericMenuItem)
	tNewMenuSubEntry.dynamic = true
	tNewMenuSubEntry.OnAction = function(self, aValue, aName)
		SkuOptions.db:ResetProfile()
		SkuOptions.db.char["SkuCore"] = {}
		SkuOptions.db.char["SkuCore"].RangeChecks = {
			Friendly = {},
			Hostile = {},
			Misc = {},
		}
		SkuOptions:OnProfileReset()
	end

	-- W8: "Fehlende Audio Wörter kopieren" ist kein Allgemein-Eintrag mehr —
	-- SkuCore:MenuBuilder haengt ihn als LETZTEN Eintrag von Einstellungen ->
	-- Sprachausgabe an (SkuOptions:MissingAudioWordsMenuEntry unten).
end

---------------------------------------------------------------------------------------------------------------------------------------
-- "Fehlende Audio Wörter kopieren": Woerter ohne Audio-Datei in einer EditBox
-- zum Kopieren anzeigen (und die gesammelte Liste danach leeren).
function SkuOptions:MissingAudioWordsMenuEntry(aParentEntry)
	local tNewMenuSubEntry =SkuOptions:InjectMenuItems(aParentEntry, {L["Fehlende Audio Wörter kopieren"]}, SkuGenericMenuItem)
	tNewMenuSubEntry.dynamic = true
	tNewMenuSubEntry.OnAction = function(self, aValue, aName)
		if SkuOptions.db.realm then
			if SkuOptions.db.realm.missingAudio then
				local tText = ""
				if SkuOptions.db.realm.missingAudio then
					for i, v in pairs(SkuOptions.db.realm.missingAudio) do
						tText = tText..i.."\r\n"
					end
				end
				PlaySound(88)
				SkuOptions.Voice:OutputString(L["Jetzt wort liste mit Steuerung plus C kopieren und Escape drücken"], true, true, 0.2)
				SkuOptions:EditBoxShow(tText, function(self) PlaySound(89) end)
				SkuOptions.db.realm.missingAudio = {}
			end
		end
	end
end
