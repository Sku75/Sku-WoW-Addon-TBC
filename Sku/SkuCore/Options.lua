local MODULE_NAME = "SkuCore"
local L = Sku.L

local tAdditionalTotemBarNameParts = {
	["MULTICASTACTIONBUTTON1"] = " ("..L["Set"].." 1) ",
	["MULTICASTACTIONBUTTON2"] = " ("..L["Set"].." 1) ",
	["MULTICASTACTIONBUTTON3"] = " ("..L["Set"].." 1) ",
	["MULTICASTACTIONBUTTON4"] = " ("..L["Set"].." 1) ",
	["MULTICASTACTIONBUTTON5"] = " ("..L["Set"].." 2) ",
	["MULTICASTACTIONBUTTON6"] = " ("..L["Set"].." 2) ",
	["MULTICASTACTIONBUTTON7"] = " ("..L["Set"].." 2) ",
	["MULTICASTACTIONBUTTON8"] = " ("..L["Set"].." 2) ",
	["MULTICASTACTIONBUTTON9"] = " ("..L["Set"].." 3) ",
	["MULTICASTACTIONBUTTON10"] = " ("..L["Set"].." 3) ",
	["MULTICASTACTIONBUTTON11"] = " ("..L["Set"].." 3) ",
	["MULTICASTACTIONBUTTON12"] = " ("..L["Set"].." 3) ",
	["MULTICASTSUMMONBUTTON1"] = " ("..L["Set"].." 1) ",
	["MULTICASTSUMMONBUTTON2"] = " ("..L["Set"].." 2) ",
	["MULTICASTSUMMONBUTTON3"] = " ("..L["Set"].." 3) ",
	["MultiCastActionButton1"] = " ("..L["Earth"]..") ",
	["MultiCastActionButton2"] = " ("..L["Fire"]..") ",
	["MultiCastActionButton3"] = " ("..L["Water"]..") ",
	["MultiCastActionButton4"] = " ("..L["Air"]..") ",
	["MultiCastActionButton5"] = " ("..L["Earth"]..") ",
	["MultiCastActionButton6"] = " ("..L["Fire"]..") ",
	["MultiCastActionButton7"] = " ("..L["Water"]..") ",
	["MultiCastActionButton8"] = " ("..L["Air"]..") ",
	["MultiCastActionButton9"] = " ("..L["Earth"]..") ",
	["MultiCastActionButton10"] = " ("..L["Fire"]..") ",
	["MultiCastActionButton11"] = " ("..L["Water"]..") ",
	["MultiCastActionButton12"] = " ("..L["Air"]..") ",
	
}

local tBlockedKeysParts = {
	"TAB",
	"BACKSPACE",
	"ENTER",
	--"ESCAPE",
	"BUTTON1",
	"BUTTON2",
	"BUTTON3",
	"BUTTON4",
	"BUTTON5",
	"DOWN",
	"UP",
	"LEFT",
	"RIGHT",
	"PAGEDOWN",
	"PAGEDUP",
}
local tBlockedKeysBinds = {
	--"I",
}

local tModifierKeys = {
	"",
	"CTRL-",
	"SHIFT-",
	"ALT-",
	"CTRL-SHIFT-",
	"ALT-CTRL-",
	"ALT-SHIFT-",
	"ALT-CTRL-SHIFT-",
}

local tStandardChars = {"a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "ä", "ü", "ö", "ß", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "Ä", "Ö", "Ü", ",", ".", "-", "#", "+", "ß", "´", "<"}
local tStandardNumbers = {"1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12",}
local function ArmBindCaptureKeys(f)
	for i, v in pairs(_G) do
		if string.find(i, "KEY_") == 1 then
			if not string.find(i, "ESC") then
				for x = 1, #tModifierKeys do
					SetOverrideBindingClick(f, true, tModifierKeys[x]..string.sub(i, 5), "SkuCoreBindControlFrame", tModifierKeys[x]..string.sub(i, 5))
				end
			end
		end
	end

	for x = 1, #tStandardChars do
		for y = 1, #tModifierKeys do
			SetOverrideBindingClick(f, true, tModifierKeys[y]..tStandardChars[x], "SkuCoreBindControlFrame", tModifierKeys[y]..tStandardChars[x])
		end
	end
	for x = 1, #tStandardNumbers do
		for y = 1, #tModifierKeys do
			SetOverrideBindingClick(f, true, tModifierKeys[y]..tStandardNumbers[x], "SkuCoreBindControlFrame", tModifierKeys[y]..tStandardNumbers[x])
		end
	end
end


local tActionBarData = {
	MultiBarLeft = {friendlyName = L["Left Multi Bar"], buttonName = "MultiBarLeftButton", command = "MULTIACTIONBAR4BUTTON", header = "BINDING_HEADER_MULTIACTIONBAR"},
	MultiBarRight = {friendlyName = L["Right Multi Bar"], buttonName = "MultiBarRightButton", command = "MULTIACTIONBAR3BUTTON", header = "BINDING_HEADER_MULTIACTIONBAR"},
	MultiBarBottomLeft = {friendlyName = L["Bottom Multi Bar Left"], buttonName = "MultiBarBottomLeftButton", command = "MULTIACTIONBAR1BUTTON", header = "BINDING_HEADER_MULTIACTIONBAR"},
	MultiBarBottomRight = {friendlyName = L["Bottom Multi Bar Right"], buttonName = "MultiBarBottomRightButton", command = "MULTIACTIONBAR2BUTTON", header = "BINDING_HEADER_MULTIACTIONBAR"},
	MainMenuBar = {friendlyName = L["Main Action Bar"], buttonName = "ActionButton", command = "ACTIONBUTTON", header = "BINDING_HEADER_ACTIONBAR"},
	PetBar = {friendlyName = L["Pet Action Bar"], buttonName = "PetActionButton", command = "BONUSACTIONBUTTON", header = "BINDING_HEADER_ACTIONBAR"},
	ShapeshiftBar = {friendlyName = L["Stance Action Bar"], buttonName = "", command = "SHAPESHIFTBUTTON", header = "BINDING_HEADER_ACTIONBAR"},
	OverrideActionBar = {friendlyName = L["Vehicle Action Bar"], buttonName = "OverrideActionBarButton", command = "SHAPESHIFTBUTTON", header = "BINDING_HEADER_ACTIONBAR"},
	MultiCastActionBar1 = {friendlyName = L["Totem Set"].." 1", buttonName = "MultiCastActionButton", command = "MULTICASTACTIONBUTTON", header = "BINDING_HEADER_MULTICASTFUNCTIONS", min = 1, max = 4, nameNumberMod = 0,},
	MultiCastActionBar2 = {friendlyName = L["Totem Set"].." 2", buttonName = "MultiCastActionButton", command = "MULTICASTACTIONBUTTON", header = "BINDING_HEADER_MULTICASTFUNCTIONS", min = 5, max = 8, nameNumberMod = 4,},
	MultiCastActionBar3 = {friendlyName = L["Totem Set"].." 3", buttonName = "MultiCastActionButton", command = "MULTICASTACTIONBUTTON", header = "BINDING_HEADER_MULTICASTFUNCTIONS", min = 9, max = 12, nameNumberMod = 8,},
	--StanceBarFrame = {friendlyName = L["Stance Action Bar"], buttonName = "StanceButton", command = "", header = ""},
}

local scanAccuracyValues = {
	[1] = 1,
	[2] = 2,
	[3] = 3,
	[4] = 4,
	[5] = 5,
}

---------------------------------------------------------------------------------------------------------------------------------------
SkuCore.options = {
	name = MODULE_NAME,
	type = "group",
	args = {
		scanBackgroundSound = {
			order = 1,
			name = L["scanning background sound"],
			desc = "",
			type = "select",
			values = SkuCore.BackgroundSoundFiles,
			forAudioMenu = false,   -- W7: surfaced under Einstellungen -> Scan
		},
		ressourceScanning={
			name = L["Ressource Scanning"],
			type = "group",
			order = 1,
			forAudioMenu = false,   -- W7: surfaced under Einstellungen -> Scan
			args= {
				miningNodes={
					order = 1,
					name = L["mining nodes"],
					type = "group",
					args= {},
				},
				herbs={
					name = L["Herbs"],
					type = "group",
					order = 2,
					args= {},
				},
				gasCollector={
					name = L["Gas"],
					type = "group",
					order = 3,
					args= {},
				},
				scanAccuracyS = {
					order = 4,
					name = L["scan accuracy"],
					desc = "",
					type = "select",
					values = scanAccuracyValues,
				},
				notifyOnRessources = {
					order = 5,
					name = L["notify On Ressources"],
					desc = "",
					type = "toggle",
				},
			},
		},
		readAllTooltips = {
			name = L["Read all tooltips"],
			desc = "",
			type = "toggle",
		},
		--[[
		autoFollow = {
			name = L["Auto follow"],
			desc = "",
			type = "toggle",
			set = function(info, val)
				SkuSettings:Sub("SkuCore").autoFollow = val
			end,
			get = function(info)
				return SkuSettings:Sub("SkuCore").autoFollow
			end
		},
		]]
		endFollowOnCast = {
			name = L["Folgen beim Zaubern temporär beenden"],
			desc = "",
			type = "toggle",
			set = function(info, val)
				SkuSettings:Sub("SkuCore").endFollowOnCast = val
			end,
			get = function(info)
				return SkuSettings:Sub("SkuCore").endFollowOnCast
			end
		},
		interactMove = {
			name = L["Bei Interagieren zum Ziel laufen"],
			desc = "",
			type = "toggle",
		},
		followCollision = {
			name = Sku.deEn("Kollisionswarnung beim Folgen", "Follow collision warning", "Avertissement de collision au suivi"),
			desc = "",
			type = "toggle",
		},
		turnToUnit = {
			name = L["Turn to unit"],
			order = 5,
			type = "group",
			forAudioMenu = false,   -- W7: surfaced under Einstellungen -> Scan
			args = {
				speed = {
					order = 1,
					name = L["Speed (higher is faster)"],
					desc = "",
					type = "range",
					min = 1,
					max = 10,
				},
				soundOnSuccess = {
					order = 2,
					name = L["Sound on success"],
					desc = "",
					type = "select",
					values = SkuCore.outputSoundFiles,
				},
				soundOnFail = {
					order = 3,
					name = L["Sound on fail"],
					desc = "",
					type = "select",
					values = SkuCore.outputSoundFiles,
				},
				targetSelection={
					name = L["Unit selection"],
					type = "group",
					order = 4,
					args= {
						key1 = {
							order = 1,
							name = L["Key bind"].." "..1,
							desc = "",
							type = "select",
							values = SkuCore.TurnToUnit.availableTargetsListNames,
						},
						key2 = {
							order = 2,
							name = L["Key bind"].." "..2,
							desc = "",
							type = "select",
							values = SkuCore.TurnToUnit.availableTargetsListNames,
						},
						key3 = {
							order = 3,
							name = L["Key bind"].." "..3,
							desc = "",
							type = "select",
							values = SkuCore.TurnToUnit.availableTargetsListNames,
						},
						key4 = {
							order = 4,
							name = L["Key bind"].." "..4,
							desc = "",
							type = "select",
							values = SkuCore.TurnToUnit.availableTargetsListNames,
						},
						key5 = {
							order = 5,
							name = L["Key bind"].." "..5,
							desc = "",
							type = "select",
							values = SkuCore.TurnToUnit.availableTargetsListNames,
						},
						key6 = {
							order = 6,
							name = L["Key bind"].." "..6,
							desc = "",
							type = "select",
							values = SkuCore.TurnToUnit.availableTargetsListNames,
						},

					},
				},

				enhancedSettings={
					name = L["Enhanced settings"],
					type = "group",
					order = 5,
					args= {
						delayOnPlate = {
							order = 1,
							name = L["Delay on found plate"],
							desc = "",
							type = "range",
							min = 1,
							max = 10,
						},
					},
				},
			},
		},		
		playNPCGreetings = {
			name = L["Play NPC greetings"],
			desc = "",
			type = "toggle",
			forAudioMenu = false,   -- W8: surfaced under Einstellungen -> Audio
		},
		doNotHideTooltip = {
			name = L["do not hide tooltip"],
			desc = "",
			type = "toggle",
			forAudioMenu = false,   -- W7: surfaced under Einstellungen -> Scan
		},
		classes={
			name = L["Classes"],
			type = "group",
			order = 2,
			forAudioMenu = false,   -- W7: Classes menu removed; pet-starving toggle lives in Monitor -> Tier -> Gesundheit (aq.lua)
			args= {
				hunter={
					name = L["Hunter"],
					type = "group",
					order = 1,
					args= {
						petHappyness = {
							order = 2,
							name = L["Notice on pet starving"],
							desc = "",
							type = "toggle",
						},
					},
				},
			},
		},
		itemSettings={
			name = L["item settings"],
			type = "group",
			order = 3,
			args= {
				ShowItemQality = {
					name = L["show item quality"],
					order = 1,
					desc = "",
					type = "toggle",
				},
				autoSellJunk = {
					name = L["Auto sell junk at vendors"],
					order = 2,
					desc = "",
					type = "toggle",
				},
				autoRepair = {
					name = L["Auto repair at vendors"],
					order = 3,
					desc = "",
					type = "toggle",
				},
	
			},
		},
		fallSettings={
			name = L["Fall detection settings"],
			type = "group",
			order = 10,
			forAudioMenu = false,   -- relocated to the Monitor menu (aq.lua MonitorMenuBuilder)
			args= {
				delay = {
					name = L["Delay before output trigger (milliseconds)"],
					order = 1,
					desc = "",
					type = "range",
					min = 0,
					max = 1000,
				},
				ignoreJumps = {
					name = L["Ignore jumps"],
					order = 2,
					desc = "",
					type = "toggle",
				},

				voiceOutput = {
					name = L["Voice output"],
					order = 3,
					desc = "",
					type = "toggle",
				},
				soundOutput = {
					name = L["Sound output"],
					order = 4,
					desc = "",
					type = "toggle",
				},
	
			},
		},

		UIErrors={
			name = L["Error feedback"],
			type = "group",
			order = 4,
			forAudioMenu = false,   -- relocated to the Monitor menu (aq.lua MonitorMenuBuilder)
			args= {
				ErrorSoundChannel={
					name = L["sound channel"],
					order = 1,
					desc = "",
					type = "select",
					values = SKU_CONSTANTS.SOUNDCHANNELS,
				},
				OutOfRangeMelee={
					name = L["out of range melee"],
					order = 2,
					desc = "",
					type = "select",
					values = SkuCore.Errors.Sounds,
				},
				OutOfRangeCast={
					name = L["out of range cast"],
					order = 2,
					desc = "",
					type = "select",
					values = SkuCore.Errors.Sounds,
				},
				Moving={
					name = L["Moving"],
					order = 3,
					desc = "",
					type = "select",
					values = SkuCore.Errors.Sounds,
				},
				NoLoS={
					name = L["No LoS"],
					order = 3,
					desc = "",
					type = "select",
					values = SkuCore.Errors.Sounds,
				},
				BadTarget={
					name = L["Bad Target"],
					order = 3,
					desc = "",
					type = "select",
					values = SkuCore.Errors.Sounds,
				},
				InCombat={
					name = L["In Combat"],
					order = 3,
					desc = "",
					type = "select",
					values = SkuCore.Errors.Sounds,
				},
				NoMana={
					name = L["No ressource"],
					order = 3,
					desc = "",
					type = "select",
					values = SkuCore.Errors.Sounds,
				},
				ObjectBusy={
					name = L["Object Busy"],
					order = 3,
					desc = "",
					type = "select",
					values = SkuCore.Errors.Sounds,
				},
				NotFacing={
					name = L["Not Facing"],
					order = 3,
					desc = "",
					type = "select",
					values = SkuCore.Errors.Sounds,
				},
				CrowdControlled={
					name = L["Crowd Controlled"],
					order = 3,
					desc = "",
					type = "select",
					values = SkuCore.Errors.Sounds,
				},
				Interrupted={
					name = L["Interrupted"],
					order = 3,
					desc = "",
					type = "select",
					values = SkuCore.Errors.Sounds,
				},
				Other={
					name = L["other"],
					order = 3,
					desc = "",
					type = "select",
					values = SkuCore.Errors.Sounds,
				},
				Cooldown={
					name = L["cooldown"],
					order = 3,
					desc = "",
					type = "select",
					values = SkuCore.Errors.Sounds,
				},				
				
			},
		},
	},
}

do
	for x = 1, #SkuCore.RessourceTypes.mining do
		SkuCore.options.args.ressourceScanning.args.miningNodes.args[x] = {
			order = x,
			name = SkuCore.RessourceTypes.mining[x][Sku.L["locale"]],
			desc = "",
			type = "toggle",
			set = function(info,val)
				SkuSettings:Sub("SkuCore").ressourceScanning.miningNodes[x] = val
			end,
			get = function(info)
				return SkuSettings:Sub("SkuCore").ressourceScanning.miningNodes[x]
			end
		}
	end
end

do
	for x = 1, #SkuCore.RessourceTypes.herbs do
		SkuCore.options.args.ressourceScanning.args.herbs.args[x] = {
			order = x,
			name = SkuCore.RessourceTypes.herbs[x][Sku.L["locale"]],
			desc = "",
			type = "toggle",
			set = function(info,val)
				SkuSettings:Sub("SkuCore").ressourceScanning.herbs[x] = val
			end,
			get = function(info)
				return SkuSettings:Sub("SkuCore").ressourceScanning.herbs[x]
			end
		}
	end
end

do
	for x = 1, #SkuCore.RessourceTypes.gasCollector do
		SkuCore.options.args.ressourceScanning.args.gasCollector.args[x] = {
			order = x,
			name = SkuCore.RessourceTypes.gasCollector[x][Sku.L["locale"]],
			desc = "",
			type = "toggle",
			set = function(info,val)
				SkuSettings:Sub("SkuCore").ressourceScanning.gasCollector[x] = val
			end,
			get = function(info)
				return SkuSettings:Sub("SkuCore").ressourceScanning.gasCollector[x]
			end
		}
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
SkuCore.defaults = {
	enable = true,
	readAllTooltips = false,
	--autoFollow = false,
	--endFollowOnCast = false,
	interactMove = true,
	followCollision = true,
	-- "Warnton wenn Folgen abbricht" (Barrierefreiheit, Sonstiges) is ON by default:
	-- losing autofollow without noticing is one of the classic ways to get lost.
	followBreakWarn = true,
	turnToUnit = {
		speed = 6,
		soundOnSuccess = "sound-waterdrop5",
		soundOnFail = "sound-waterdrop1",
		targetSelection = {
			key1 = 1,
			key2 = 13,
			key3 = 12,
			key4 = 11,
			key5 = 22,
			key6 = 22,
		},
		enhancedSettings = {
			delayOnPlate = 2,
		},
	},	
	playNPCGreetings = false,
	scanBackgroundSound = "tools-ratchet.mp3",
	doNotHideTooltip = false,
	ressourceScanning = {
		miningNodes = {},
		herbs = {},
		gasCollector = {},
		scanAccuracyS = 3,
		notifyOnRessources = false,
	},
	classes = {
		hunter = {
			petHappyness = true,
		},
	},
	itemSettings = {
		ShowItemQality = true,
		autoSellJunk = true,
		autoRepair = true,
	},
	fallSettings = {
		delay = 0,
		voiceOutput = false,
		soundOutput = true,
		ignoreJumps = true,
	},
	lfg = {
		roles = { tank = false, healer = false, damager = true },
		autoAccept = false,
		privateGroup = false,
		levelFilter = true,
	},
	UIErrors = {
		ErrorSoundChannel = "Talking Head",
		OutOfRangeMelee = "Interface\\AddOns\\Sku\\SkuCore\\assets\\audio\\error\\error_silent.mp3",
		OutOfRangeCast = "Interface\\AddOns\\Sku\\SkuCore\\assets\\audio\\error\\error_silent.mp3",
		Moving = "voice",
		NoLoS = "voice",
		BadTarget = "Interface\\AddOns\\Sku\\SkuCore\\assets\\audio\\error\\error_silent.mp3",
		InCombat = "voice",
		NoMana = "Interface\\AddOns\\Sku\\SkuCore\\assets\\audio\\error\\error_silent.mp3",
		ObjectBusy = "voice",
		NotFacing = "voice",
		CrowdControlled = "voice",
		Interrupted = "voice",
		Other = "voice",
		Cooldown  = "Interface\\AddOns\\Sku\\SkuCore\\assets\\audio\\error\\error_silent.mp3",
	},
}

do
	for x = 1, #SkuCore.RessourceTypes.mining do
		SkuCore.defaults.ressourceScanning.miningNodes[x] = true
	end
end
do
	for x = 1, #SkuCore.RessourceTypes.herbs do
		SkuCore.defaults.ressourceScanning.herbs[x] = true
	end
end
do
	for x = 1, #SkuCore.RessourceTypes.gasCollector do
		SkuCore.defaults.ressourceScanning.gasCollector[x] = true
	end
end

-- Settings schema for SkuCore's MAIN options menu (Sku 42 rework, W2 M-C1 /
-- W1 Phase C). Every key below is profile-scoped (these settings have always
-- lived under SkuSettings:Sub("SkuCore") with no scope override, i.e. the
-- profile scope, and the defaults mirror SkuCore.defaults above). Declared here
-- as the single source of truth (scope/type/default) for the schema-managed menu
-- generation: the matching nodes in SkuCore.options.args no longer carry get/set
-- and are resolved via SkuSettings:Get/Set("SkuCore", dottedKey).
--
-- NOT registered on purpose: the data-driven ressourceScanning.miningNodes /
-- .herbs / .gasCollector toggles (integer keys, count comes from
-- SkuCore.RessourceTypes at load) — their option nodes KEEP their own get/set
-- (see the do-loops in Options.lua) and are not schema-managed.
SkuSettings:Register("SkuCore", {
	["scanBackgroundSound"]                       = { scope = "profile", default = "tools-ratchet.mp3", type = "string" },
	["ressourceScanning.scanAccuracyS"]           = { scope = "profile", default = 3, type = "number" },
	["ressourceScanning.notifyOnRessources"]      = { scope = "profile", default = false, type = "boolean" },
	["readAllTooltips"]                           = { scope = "profile", default = false, type = "boolean" },
	["interactMove"]                              = { scope = "profile", default = true, type = "boolean" },
	-- Combat menu accessibility: open/read/navigate the Sku menu, bags, character sheet
	-- and quest log WHILE IN COMBAT (headless capture + relaxed self-deactivation).
	-- Default ON; toggle in the Kampf menu or via /skucombatmenu.
	["combatMenuOpen"]                            = { scope = "profile", default = true, type = "boolean" },
	["turnToUnit.speed"]                          = { scope = "profile", default = 6, type = "number" },
	["turnToUnit.soundOnSuccess"]                 = { scope = "profile", default = "sound-waterdrop5", type = "string" },
	["turnToUnit.soundOnFail"]                    = { scope = "profile", default = "sound-waterdrop1", type = "string" },
	["turnToUnit.targetSelection.key1"]           = { scope = "profile", default = 1, type = "number" },
	["turnToUnit.targetSelection.key2"]           = { scope = "profile", default = 13, type = "number" },
	["turnToUnit.targetSelection.key3"]           = { scope = "profile", default = 12, type = "number" },
	["turnToUnit.targetSelection.key4"]           = { scope = "profile", default = 11, type = "number" },
	["turnToUnit.targetSelection.key5"]           = { scope = "profile", default = 22, type = "number" },
	["turnToUnit.targetSelection.key6"]           = { scope = "profile", default = 22, type = "number" },
	["turnToUnit.enhancedSettings.delayOnPlate"]  = { scope = "profile", default = 2, type = "number" },
	["playNPCGreetings"]                          = { scope = "profile", default = false, type = "boolean" },
	["doNotHideTooltip"]                          = { scope = "profile", default = false, type = "boolean" },
	["followCollision"]                           = { scope = "profile", default = true, type = "boolean" },
	["followBreakWarn"]                           = { scope = "profile", default = true, type = "boolean" },
	["classes.hunter.petHappyness"]               = { scope = "profile", default = true, type = "boolean" },
	["itemSettings.ShowItemQality"]               = { scope = "profile", default = true, type = "boolean" },
	["itemSettings.autoSellJunk"]                 = { scope = "profile", default = true, type = "boolean" },
	["itemSettings.autoRepair"]                   = { scope = "profile", default = true, type = "boolean" },
	["fallSettings.delay"]                        = { scope = "profile", default = 0, type = "number" },
	["fallSettings.ignoreJumps"]                  = { scope = "profile", default = true, type = "boolean" },
	["fallSettings.voiceOutput"]                  = { scope = "profile", default = false, type = "boolean" },
	["fallSettings.soundOutput"]                  = { scope = "profile", default = true, type = "boolean" },
	["UIErrors.ErrorSoundChannel"]                = { scope = "profile", default = "Talking Head", type = "string" },
	["UIErrors.OutOfRangeMelee"]                  = { scope = "profile", default = "Interface\\AddOns\\Sku\\SkuCore\\assets\\audio\\error\\error_silent.mp3", type = "string" },
	["UIErrors.OutOfRangeCast"]                   = { scope = "profile", default = "Interface\\AddOns\\Sku\\SkuCore\\assets\\audio\\error\\error_silent.mp3", type = "string" },
	["UIErrors.Moving"]                           = { scope = "profile", default = "voice", type = "string" },
	["UIErrors.NoLoS"]                            = { scope = "profile", default = "voice", type = "string" },
	["UIErrors.BadTarget"]                        = { scope = "profile", default = "Interface\\AddOns\\Sku\\SkuCore\\assets\\audio\\error\\error_silent.mp3", type = "string" },
	["UIErrors.InCombat"]                         = { scope = "profile", default = "voice", type = "string" },
	["UIErrors.NoMana"]                           = { scope = "profile", default = "Interface\\AddOns\\Sku\\SkuCore\\assets\\audio\\error\\error_silent.mp3", type = "string" },
	["UIErrors.ObjectBusy"]                       = { scope = "profile", default = "voice", type = "string" },
	["UIErrors.NotFacing"]                        = { scope = "profile", default = "voice", type = "string" },
	["UIErrors.CrowdControlled"]                  = { scope = "profile", default = "voice", type = "string" },
	["UIErrors.Interrupted"]                      = { scope = "profile", default = "voice", type = "string" },
	["UIErrors.Other"]                            = { scope = "profile", default = "voice", type = "string" },
	["UIErrors.Cooldown"]                         = { scope = "profile", default = "Interface\\AddOns\\Sku\\SkuCore\\assets\\audio\\error\\error_silent.mp3", type = "string" },
})


---------------------------------------------------------------------------------------------------------------------------------------
-- W6-C #16b: shared primary/secondary rebind-capture (SkuCore command binds).
-- The two branches were identical except (a) SetBinding vs SetBinding2 and
-- (b) which friendly key is voiced. aSecondary selects both.
local function tRebindCaptureCommand(self, aSecondary)
		SkuOptions.bindingMode = true

		C_Timer.After(0.001, function()
			SkuOptions.Voice:OutputStringBTtts(L["Press new key or Escape to cancel"], true, true, 0.2, true, nil, nil, 2)

			local f = _G["SkuCoreBindControlFrame"] or CreateFrame("Button", "SkuCoreBindControlFrame", UIParent, "UIPanelButtonTemplate")
			f.menuTarget = self
			f.command = self.command
			f.category = self.category
			f.index = self.index
			f.prevKey = nil

			--f:RegisterForClicks("AnyUp", "AnyDown")
			f:SetSize(80, 22)
			f:SetText("SkuCoreBindControlFrame")
			f:SetPoint("LEFT", UIParent, "RIGHT", 1500, 0)
			f:SetPoint("CENTER")
			f:SetScript("OnClick", function(self, aKey, aB)
				dprint("CmdBind OnClick", "aKey=", aKey, "aB=", aB, "command=", self.command, "index=", self.index, "category=", self.category, "secondary=", aSecondary)
				if aKey ~= "ESCAPE" then
					if not self.command or not self.category or not self.menuTarget or not self.index then
						dprint("CmdBind abort: missing command/category/menuTarget/index", self.command, self.category, self.index)
						return
					end
					for z = 1, #tBlockedKeysParts do
						if string.find(aKey, tBlockedKeysParts[z]) or string.find(string.lower(aKey), string.lower(tBlockedKeysParts[z])) then 
							SkuOptions.Voice:OutputStringBTtts(L["Ungültig. Andere Taste drücken."], true, true, 0.2, true, nil, nil, 2)
							self.prevKey = nil
							return 
						end
					end

					for z = 1, #tBlockedKeysBinds do
						if aKey == tBlockedKeysBinds[z] or string.lower(aKey) == string.lower(tBlockedKeysBinds[z]) then 
							SkuOptions.Voice:OutputStringBTtts(L["Ungültig. Andere Taste drücken."], true, true, 0.2, true, nil, nil, 2)
							return
						end
					end

					local tCommand = SkuCore:CheckBound(aKey)
					local bindingConst = SkuOptions:SkuKeyBindsCheckBound(aKey)
					if tCommand or bindingConst then
						if not self.prevKey or self.prevKey ~= aKey then
							self.prevKey = aKey
							if bindingConst then
								SkuOptions.Voice:OutputStringBTtts(L["Warning! That key is already bound to"].." "..L[bindingConst]..L[". Press the key again to confirm new binding. The current bound action will be unbound!"], true, true, 0.2, true, nil, nil, 2)
							elseif tCommand then
								SkuOptions.Voice:OutputStringBTtts(L["Warning! That key is already bound to"].." ".._G["BINDING_NAME_"..tCommand]..L[". Press the key again to confirm new binding. The current bound action will be unbound!"], true, true, 0.2, true, nil, nil, 2)
							end
							return 
						end
					end

					if tCommand or bindingConst and self.prevKey == aKey then
						if bindingConst then
							SkuOptions:SkuKeyBindsDeleteConflictingKey(bindingConst, aKey)
						elseif tCommand then
							-- Nur die konfliktbehaftete Taste entbinden, nicht alle Tasten des Befehls
							SetBinding(aKey)
							SkuCore:SaveBindings()
						end
					end

					if aSecondary then SkuCore:SetBinding2(aKey, self.command) else SkuCore:SetBinding(aKey, self.command) end

					dprint("CmdBind after SetBinding", "command=", self.command, "aKey=", aKey,
						"GetBindingKey=", GetBindingKey(self.command), "bindingSet=", GetCurrentBindingSet())
					local tCommand, tCategory, tKey1, tKey2 = GetBinding(self.index, GetCurrentBindingSet())
					dprint("CmdBind readback", "idx=", self.index, "gotCommand=", tCommand, "tKey1=", tKey1, "tKey2=", tKey2, "matchesTarget=", tCommand == self.command)
					local aFriendlyKey1, tFriendlyKey2 = tKey1 or L["nichts"], tKey2 or L["nichts"]
					for kLocKey, vLocKey in pairs(SkuCore.Keys.LocNames) do
						aFriendlyKey1 = gsub(aFriendlyKey1, kLocKey, vLocKey)
						tFriendlyKey2 = gsub(tFriendlyKey2, kLocKey, vLocKey)
					end				
					if tCommand or bindingConst then
						_G["OnSkuOptionsMainOption1"]:GetScript("OnClick")(_G["OnSkuOptionsMainOption1"], "LEFT")
					else
						self.menuTarget.name = _G["BINDING_NAME_" .. tCommand]..L[" Taste 1: "]..(aFriendlyKey1)..L[" Taste 2: "]..(tFriendlyKey2)
						_G["OnSkuOptionsMainOption1"]:GetScript("OnClick")(_G["OnSkuOptionsMainOption1"], "RIGHT")
						_G["OnSkuOptionsMainOption1"]:GetScript("OnClick")(_G["OnSkuOptionsMainOption1"], "LEFT")
					end
					SkuOptions.Voice:OutputStringBTtts(L["New key"]..";"..(aSecondary and tFriendlyKey2 or aFriendlyKey1), true, true, 0.2, true, nil, nil, 2)
				elseif aKey == "ESCAPE" then
					SkuOptions.Voice:OutputStringBTtts(L["Binding canceled"], true, true, 0.2, true, nil, nil, 2)
				end
				ClearOverrideBindings(self)
				SkuOptions.bindingMode = nil
			end)
			SetOverrideBindingClick(f, true, "ESCAPE", "SkuCoreBindControlFrame", "ESCAPE")

			ArmBindCaptureKeys(f)
		end)											
end

-- W6-C #16b: shared primary/secondary rebind-capture (SkuKeyBinds const binds).
-- Branches were identical except SkuKeyBindsSetBinding vs ...SetBinding2 and which
-- friendly key is voiced (aSecondary selects both). The secondary path also picks
-- up the two gated dprint breadcrumbs that only the primary had — debug-only, no
-- user-visible change.
local function tRebindCaptureKeyBind(self, aSecondary)
						SkuOptions.bindingMode = true

						C_Timer.After(0.001, function()
							SkuOptions.Voice:OutputStringBTtts(L["Press new key or Escape to cancel"], true, true, 0.2, true, nil, nil, 2)

							local f = _G["SkuCoreBindControlFrame"] or CreateFrame("Button", "SkuCoreBindControlFrame", UIParent, "UIPanelButtonTemplate")
							f.menuTarget = self
							f.bindingConst = self.bindingConst
							f.prevKey = nil
		
							f:SetSize(80, 22)
							f:SetText("SkuCoreBindControlFrame")
							f:SetPoint("LEFT", UIParent, "RIGHT", 1500, 0)
							f:SetPoint("CENTER")
							f:SetScript("OnClick", function(self, aKey, aB)
								dprint("SkuCoreBindControlFrame OnClick", aKey, aB)
								if aKey ~= "ESCAPE" then
									if not self.bindingConst or not self.menuTarget then return end
									-- The in-combat menu keys (SKU_KEY_COMBATMENU_*) are ALLOWED to take
									-- otherwise-reserved keys (arrows / enter / backspace): they are bound
									-- ONLY during combat (override cleared at combat end), so reusing the
									-- menu-nav keys there is intended, and arrow-key movers need to relocate
									-- them onto (possibly modified) arrows. Skip the block list for those
									-- consts only; every other bind keeps the reserved-key protection.
									local tAllowReserved = string.find(self.bindingConst, "SKU_KEY_COMBATMENU_", 1, true) ~= nil
									if not tAllowReserved then
										for z = 1, #tBlockedKeysParts do
											if string.find(aKey, tBlockedKeysParts[z]) or string.find(string.lower(aKey), string.lower(tBlockedKeysParts[z])) then
												SkuOptions.Voice:OutputStringBTtts(L["Ungültig. Andere Taste drücken."], true, true, 0.2, true, nil, nil, 2)
												self.prevKey = nil
												return
											end
										end
										for z = 1, #tBlockedKeysBinds do
											if aKey == tBlockedKeysBinds[z] or string.lower(aKey) == string.lower(tBlockedKeysBinds[z]) then
												SkuOptions.Voice:OutputStringBTtts(L["Ungültig. Andere Taste drücken."], true, true, 0.2, true, nil, nil, 2)
												return
											end
										end
									end

									dprint(self.bindingConst, self.menuTarget, self.menuTarget.name, self.prevKey)

									local tCommand = SkuCore:CheckBound(aKey)
									local bindingConst = SkuOptions:SkuKeyBindsCheckBound(aKey)
									if tCommand or bindingConst then
										if not self.prevKey or self.prevKey ~= aKey then
											self.prevKey = aKey
											if bindingConst then
												SkuOptions.Voice:OutputStringBTtts(L["Warning! That key is already bound to"].." "..L[bindingConst]..L[". Press the key again to confirm new binding. The current bound action will be unbound!"], true, true, 0.2, true, nil, nil, 2)
											elseif tCommand then
												SkuOptions.Voice:OutputStringBTtts(L["Warning! That key is already bound to"].." ".._G["BINDING_NAME_"..tCommand]..L[". Press the key again to confirm new binding. The current bound action will be unbound!"], true, true, 0.2, true, nil, nil, 2)
											end
											return 
										end
									end

									if tCommand or bindingConst and self.prevKey == aKey then
										if bindingConst then
											SkuOptions:SkuKeyBindsDeleteConflictingKey(bindingConst, aKey)
										elseif tCommand then
											SetBinding(aKey)
											SkuCore:SaveBindings()
										end
									end

									if aSecondary then SkuOptions:SkuKeyBindsSetBinding2(self.bindingConst, aKey) else SkuOptions:SkuKeyBindsSetBinding(self.bindingConst, aKey) end

									local tKey1 = SkuOptions:SkuKeyBindsGetBinding(self.bindingConst)
									local tKey2 = SkuOptions:SkuKeyBindsGetBinding2(self.bindingConst)
									local tFriendlyKey1 = (tKey1 ~= "" and tKey1) or L["nichts"]
									local tFriendlyKey2 = (tKey2 ~= "" and tKey2) or L["nichts"]
									for kLocKey, vLocKey in pairs(SkuCore.Keys.LocNames) do
										tFriendlyKey1 = gsub(tFriendlyKey1, kLocKey, vLocKey)
										tFriendlyKey2 = gsub(tFriendlyKey2, kLocKey, vLocKey)
									end
									if tCommand or bindingConst then
										_G["OnSkuOptionsMainOption1"]:GetScript("OnClick")(_G["OnSkuOptionsMainOption1"], "LEFT")
									else
										self.menuTarget.name = L[self.bindingConst]..L[" Taste 1: "]..(tFriendlyKey1 or L["nichts"])..L[" Taste 2: "]..(tFriendlyKey2 or L["nichts"])
										_G["OnSkuOptionsMainOption1"]:GetScript("OnClick")(_G["OnSkuOptionsMainOption1"], "RIGHT")
										_G["OnSkuOptionsMainOption1"]:GetScript("OnClick")(_G["OnSkuOptionsMainOption1"], "LEFT")
									end
									SkuOptions.Voice:OutputStringBTtts(L["New key"]..";"..(aSecondary and tFriendlyKey2 or tFriendlyKey1), true, true, 0.2, true, nil, nil, 2)
								elseif aKey == "ESCAPE" then
									self.prevKey = nil
									SkuOptions.Voice:OutputStringBTtts(L["Binding canceled"], true, true, 0.2, true, nil, nil, 2)
								end
								ClearOverrideBindings(self)
								SkuOptions.bindingMode = nil
							end)
							SetOverrideBindingClick(f, true, "ESCAPE", "SkuCoreBindControlFrame", "ESCAPE")
		
							ArmBindCaptureKeys(f)
						end)											
end

local function KeyBindingKeyMenuEntryHelper(self, aValue, aName)
	if aName == L["Neu belegen"] then
		tRebindCaptureCommand(self, false)
	elseif aName == L["Sekundäre Taste neu belegen"] then
		tRebindCaptureCommand(self, true)
	elseif aName == L["Belegung löschen"] then
		if not self.command or not self.category or not self.index then return end
		SkuCore:DeleteBinding(self.command)
		local tCommand, tCategory, tKey1, tKey2 = GetBinding(self.index, GetCurrentBindingSet())
		local aFriendlyKey1, tFriendlyKey2
		self.name = _G["BINDING_NAME_" .. tCommand]..L[" Taste 1: "]..(aFriendlyKey1 or L["nichts"])..L[" Taste 2: "]..(tFriendlyKey2 or L["nichts"])
		_G["OnSkuOptionsMainOption1"]:GetScript("OnClick")(_G["OnSkuOptionsMainOption1"], "RIGHT")
		_G["OnSkuOptionsMainOption1"]:GetScript("OnClick")(_G["OnSkuOptionsMainOption1"], "LEFT")
		SkuOptions.Voice:OutputStringBTtts(L["Belegung gelöscht"], true, true, 0.2)
	elseif aName == L["Sekundäre Belegung löschen"] then
		if not self.command or not self.category or not self.index then return end
		SkuCore:DeleteBinding2(self.command)
		local tCommand, tCategory, tKey1, tKey2 = GetBinding(self.index, GetCurrentBindingSet())
		local aFriendlyKey1, tFriendlyKey2 = tKey1 or L["nichts"], tKey2 or L["nichts"]
		for kLocKey, vLocKey in pairs(SkuCore.Keys.LocNames) do
			aFriendlyKey1 = gsub(aFriendlyKey1, kLocKey, vLocKey)
			tFriendlyKey2 = gsub(tFriendlyKey2, kLocKey, vLocKey)
		end
		self.name = _G["BINDING_NAME_" .. tCommand]..L[" Taste 1: "]..(aFriendlyKey1 or L["nichts"])..L[" Taste 2: "]..(tFriendlyKey2 or L["nichts"])
		_G["OnSkuOptionsMainOption1"]:GetScript("OnClick")(_G["OnSkuOptionsMainOption1"], "RIGHT")
		_G["OnSkuOptionsMainOption1"]:GetScript("OnClick")(_G["OnSkuOptionsMainOption1"], "LEFT")
		SkuOptions.Voice:OutputStringBTtts(L["Sekundäre Belegung gelöscht"], true, true, 0.2)
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
local function ButtonContentNameHelper(aActionType, aId, aSubType, aActionBarName, aButtonId)
	--print("ButtonContentNameHelper", aActionType, aId, aSubType, aActionBarName, aButtonId)
	local rName = L["Empty"]

	if aActionType and aId then
		if aActionType == "spell" then
			local name, rank, icon, castTime, minRange, maxRange, spellID = GetSpellInfo(aId)
			rName = name
			if GetSpellSubtext(aId) and GetSpellSubtext(aId) ~= "" then
				rName = rName..";"..GetSpellSubtext(aId)
			end
		elseif aActionType == "item" then
			local itemName, itemLink, itemQuality, itemLevel, itemMinLevel, itemType, itemSubType, itemStackCount, itemEquipLoc, itemTexture, sellPrice, classID, subclassID, bindType, expacID, setID, isCraftingReagent = GetItemInfo(aId)
			rName = itemName
		elseif aActionType == "macro" then
			local name, icon, body, isLocal = GetMacroInfo(aId)
			if name then
				rName = L["Macro"]..";"..name
			else
				rName = L["Macro"]..";"..L["Unbekannt"]
			end
		elseif aActionType == "pet" then
			local name, texture, isToken, isActive, autoCastAllowed, autoCastEnabled, spellID = GetPetActionInfo(aId);
			if name then
				rName = _G[name] or name
			end
		elseif aActionType == "companion" then
			local name, rank, icon, castTime, minRange, maxRange, spellID = GetSpellInfo(aId)
			rName = name
			if GetSpellSubtext(aId) and GetSpellSubtext(aId) ~= "" then
				rName = rName..";"..GetSpellSubtext(aId)
			end
		elseif aActionType == "equipmentset" then
			--aId = string<setName>
			if C_EquipmentSet then
				for x = 0, C_EquipmentSet.GetNumEquipmentSets() do
					local name, iconFileID, setID, isEquipped, numItems, numEquipped, numInInventory, numLost, numIgnored = C_EquipmentSet.GetEquipmentSetInfo(x)
					if name and name == aId then
						rName = name
					end
				end
			end
		end
	end

	local tKeysString, key1, key2 = "", GetBindingKey(tActionBarData[aActionBarName].command..aButtonId)
	if key1 then
		tKeysString = ";"..L["Key"]..";"..GetBindingText(key1)
	end
	if key2 and tKeysString == "" then
		tKeysString = ";"..L["Key"]..";"..GetBindingText(key2)
	elseif key2 then
		tKeysString = tKeysString..";"..L["Key"]..";"..GetBindingText(key2)
	end
	if tKeysString == "" then
		tKeysString = ";"..L["Key;not;assigned"]
	end

	if rName == nil then
		rName = L["Empty"]
	end

	return rName..tKeysString
end

---------------------------------------------------------------------------------------------------------------------------------------
local function BindingHelper(aCurrentMenuEntry, aType, aButtonId, aParentEntry, aActionBarName, aBooktypeOrObjId)
	SkuOptions.Voice:OutputStringBTtts(L["Press new key or Escape to cancel"], true, true, 0.2)						
	local f = _G["SkuCoreBindControlFrame"] or CreateFrame("Button", "SkuCoreBindControlFrame", UIParent, "UIPanelButtonTemplate")
	f.menuTarget = aCurrentMenuEntry
	f:SetSize(80, 22)
	f:SetText("SkuCoreBindControlFrame")
	f:SetPoint("LEFT", UIParent, "RIGHT", 1500, 0)
	f:SetPoint("CENTER")
	f:SetScript("OnClick", function(self, aKey, aB)
		--dprint(aKey, aB)
		SkuOptions.bindingMode = nil

		for z = 1, #tBlockedKeysParts do
			if string.find(aKey, tBlockedKeysParts[z]) or string.find(string.lower(aKey), string.lower(tBlockedKeysParts[z])) then 
				SkuOptions.Voice:OutputStringBTtts(L["Ungültig. Andere Taste drücken."], true, true, 0.2, true, nil, nil, 2)
				return
			end
		end

		for z = 1, #tBlockedKeysBinds do
			if aKey == tBlockedKeysBinds[z] or string.lower(aKey) == string.lower(tBlockedKeysBinds[z]) then 
				SkuOptions.Voice:OutputStringBTtts(L["Ungültig. Andere Taste drücken."], true, true, 0.2, true, nil, nil, 2)
				return
			end
		end

		if aKey ~= "ESCAPE" then
			SetBinding(aKey)
			local key1, key2 = GetBindingKey(tActionBarData[aActionBarName].command..aButtonId)
			if key1 then SetBinding(key1) end
			if key2 then SetBinding(key2) end
			local ok = SetBinding(aKey , tActionBarData[aActionBarName].command..aButtonId)
			SaveBindings(GetCurrentBindingSet())

			if aType == "player" then
				local actionType, id, subType = GetActionInfo(self.menuTarget.buttonObj.action)
				self.menuTarget.name = L["Button"].." "..aButtonId..";"..ButtonContentNameHelper(actionType, id, subType, aActionBarName, aButtonId)
			elseif aType == "pet" then
				self.menuTarget.name = L["Button"].." "..aButtonId..";"..ButtonContentNameHelper("pet", aBooktypeOrObjId, subType, aActionBarName, aBooktypeOrObjId)
			end

			_G["OnSkuOptionsMainOption1"]:GetScript("OnClick")(_G["OnSkuOptionsMainOption1"], "RIGHT")
			_G["OnSkuOptionsMainOption1"]:GetScript("OnClick")(_G["OnSkuOptionsMainOption1"], "LEFT")
			SkuOptions.Voice:OutputStringBTtts(L["New key"]..";"..aKey, true, true, 0.2)						
		else
			SkuOptions.Voice:OutputStringBTtts(L["Binding canceled"], true, true, 0.2)						
		end
		ClearOverrideBindings(self)
	end)
	SetOverrideBindingClick(f, true, "ESCAPE", "SkuCoreBindControlFrame", "ESCAPE")

	ArmBindCaptureKeys(f)
end

---------------------------------------------------------------------------------------------------------------------------------------
local function MacrosMenuBuilder(aParentEntry)
	local tNewMenuSubEntry = SkuOptions:InjectMenuItems(aParentEntry, {L["Macros"]}, SkuGenericMenuItem)
	tNewMenuSubEntry.dynamic = true
	tNewMenuSubEntry.sorting = true
	tNewMenuSubEntry.OnEnter = function(self, aValue, aName)
		self.selectTarget.itemID = nil
	end
	tNewMenuSubEntry.BuildChildren = function(self)
		local tHasEntries = false
		local tGlobalOffset = 121
		local global, perChar = GetNumMacros()

		if global > 0 then
			for x = 1, global do
				local name, icon, body, isLocal = GetMacroInfo(x)
				if name then
					local tNewMenuSubSubEntry = SkuOptions:InjectMenuItems(self, {name}, SkuGenericMenuItem)
					tNewMenuSubSubEntry.OnEnter = function(self, aValue, aName)
						self.selectTarget.macroID = x
						SkuOptions.currentMenuPosition.textFirstLine, SkuOptions.currentMenuPosition.textFull = name, body
					end
					tHasEntries = true
				end
			end
		end
		if perChar > 0 then
			for x = tGlobalOffset, tGlobalOffset + perChar do
				local name, icon, body, isLocal = GetMacroInfo(x)
				if name then
					local tNewMenuSubSubEntry = SkuOptions:InjectMenuItems(self, {name}, SkuGenericMenuItem)
					tNewMenuSubSubEntry.OnEnter = function(self, aValue, aName)
						self.selectTarget.macroID = x
						SkuOptions.currentMenuPosition.textFirstLine, SkuOptions.currentMenuPosition.textFull = name, body
					end
					tHasEntries = true
				end
			end
		end

		if tHasEntries == false then
			SkuOptions:InjectMenuItems(self, {L["Menu empty"]}, SkuGenericMenuItem)
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
local function ItemsMenuBuilder(aParentEntry)
	local tNewMenuSubEntry = SkuOptions:InjectMenuItems(aParentEntry, {L["Items"]}, SkuGenericMenuItem)
	tNewMenuSubEntry.dynamic = true
	tNewMenuSubEntry.sorting = true
	tNewMenuSubEntry.OnEnter = function(self, aValue, aName)
		self.selectTarget.itemID = nil
	end
	tNewMenuSubEntry.BuildChildren = function(self)
		local tHasEntries = false
		for bag = BACKPACK_CONTAINER, NUM_BAG_SLOTS do
			for slot = 1, GetContainerNumSlots(bag) do
				local itemLink = GetContainerItemLink(bag, slot)
				local icon, itemCount, locked, quality, readable, lootable, itemLink, isFiltered, noValue, itemID = GetContainerItemInfo(bag, slot)
				if itemLink then
					local itemName = C_Item.GetItemNameByID(itemLink) or L["unknown"]
					local tNewMenuSubSubEntry = SkuOptions:InjectMenuItems(self, {bag.." "..slot..": "..itemName.." ("..itemCount..")"}, SkuGenericMenuItem)
					tNewMenuSubSubEntry.OnEnter = function(self, aValue, aName)
						self.selectTarget.itemID = itemID
						_G["SkuScanningTooltip"]:ClearLines()
						_G["SkuScanningTooltip"]:SetItemByID(itemID)
						if TooltipLines_helper(_G["SkuScanningTooltip"]:GetRegions()) ~= "asd" then
							if TooltipLines_helper(_G["SkuScanningTooltip"]:GetRegions()) ~= "" then
								local tText = SkuUtil:Unescape(TooltipLines_helper(_G["SkuScanningTooltip"]:GetRegions()))
								SkuOptions.currentMenuPosition.textFirstLine, SkuOptions.currentMenuPosition.textFull = SkuCore:ItemName_helper(tText)
							end
						end
					end
					tHasEntries = true
				end
			end
		end

		if tHasEntries == false then
			SkuOptions:InjectMenuItems(self, {L["Menu empty"]}, SkuGenericMenuItem)
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
local function SpellBookMenuBuilder(aParentEntry, aBooktype, aIsPet, aButtonsWithCurrentPetControlAction)
	aIsPet = aIsPet or false
	local tNewMenuSubEntry = SkuOptions:InjectMenuItems(aParentEntry, {L["Assign nothing"]}, SkuGenericMenuItem)

	local tNumSpellTabs = 1
	if aIsPet == false then
		tNumSpellTabs = GetNumSpellTabs()
	end

	for x = 1, tNumSpellTabs do
		local name, texture, offset, numEntries, isGuild, offspecID = GetSpellTabInfo(x)
		local tNumEntries, token = HasPetSpells()
		if aIsPet == true then
			numEntries = tNumEntries or 0
		end
		
		local tNewMenuSubEntry
		if aIsPet == true and token ~= nil then
			tNewMenuSubEntry = SkuOptions:InjectMenuItems(aParentEntry, {_G["PET_TYPE_"..token]}, SkuGenericMenuItem)
		else
			tNewMenuSubEntry = SkuOptions:InjectMenuItems(aParentEntry, {name}, SkuGenericMenuItem)
		end

		tNewMenuSubEntry.dynamic = true
		tNewMenuSubEntry.sorting = true
		tNewMenuSubEntry.OnEnter = function(self, aValue, aName)
			self.selectTarget.spellID = nil
		end
		tNewMenuSubEntry.BuildChildren = function(self)
			local tHasEntries = false
			if numEntries > 0 then
				for y = offset + 1, offset + numEntries do
					local spellName, spellSubName, spellID = GetSpellBookItemName(y, aBooktype) --BOOKTYPE_PET
					if spellName then
						local tIsPassive = IsPassiveSpell(spellID)
						local isKnown = IsSpellKnown(spellID, aIsPet)
						if name == L["Runes"] then
							isKnown = isKnown == false
						end

						if not tIsPassive and isKnown == true then
							local tNewMenuSubSubEntry = SkuOptions:InjectMenuItems(self, {spellName..";"..spellSubName}, SkuGenericMenuItem)
							tNewMenuSubSubEntry.OnEnter = function(self, aValue, aName)
								self.selectTarget.petDefaultControlId = nil
								self.selectTarget.spellID = spellID
								_G["SkuScanningTooltip"]:ClearLines()
								_G["SkuScanningTooltip"]:SetSpellByID(spellID)
								if TooltipLines_helper(_G["SkuScanningTooltip"]:GetRegions()) ~= "asd" then
									if TooltipLines_helper(_G["SkuScanningTooltip"]:GetRegions()) ~= "" then
										local tText = SkuUtil:Unescape(TooltipLines_helper(_G["SkuScanningTooltip"]:GetRegions()))
										SkuOptions.currentMenuPosition.textFirstLine, SkuOptions.currentMenuPosition.textFull = SkuCore:ItemName_helper(tText)
									end
								end
							end
							tHasEntries = true
						end
					end
				end
			end
			if aIsPet == true then
				for i, v in pairs(aButtonsWithCurrentPetControlAction) do
					local tNewMenuSubSubEntry = SkuOptions:InjectMenuItems(self, {_G[i]}, SkuGenericMenuItem)
					tNewMenuSubSubEntry.OnEnter = function(self, aValue, aName)
						self.selectTarget.spellID = nil
						self.selectTarget.petDefaultControlId = v
						_G["SkuScanningTooltip"]:ClearLines()
						_G["SkuScanningTooltip"]:SetPetAction(v)
						if TooltipLines_helper(_G["SkuScanningTooltip"]:GetRegions()) ~= "asd" then
							if TooltipLines_helper(_G["SkuScanningTooltip"]:GetRegions()) ~= "" then
								local tText = SkuUtil:Unescape(TooltipLines_helper(_G["SkuScanningTooltip"]:GetRegions()))
								SkuOptions.currentMenuPosition.textFirstLine, SkuOptions.currentMenuPosition.textFull = SkuCore:ItemName_helper(tText)
							end
						end						
					end
					tHasEntries = true

				end
			end

			if tHasEntries == false then
				local tNewMenuSubSubEntry = SkuOptions:InjectMenuItems(self, {L["Menu empty"]}, SkuGenericMenuItem)
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
local function ActionBarMenuBuilder(aParentEntry, aActionBarName, aBooktype)
	if not aParentEntry or not aActionBarName then return end

	local tFrom, tTo, tNameNumberMod = 1, 12, 0
	if tActionBarData[aActionBarName].min then
		tFrom = tActionBarData[aActionBarName].min
		tTo = tActionBarData[aActionBarName].max
	end
	if tActionBarData[aActionBarName].nameNumberMod then
		tNameNumberMod = tActionBarData[aActionBarName].nameNumberMod
	end

	for x = tFrom, tTo do
		local tButtonObj = _G[tActionBarData[aActionBarName].buttonName..x]
		if tButtonObj then
			local actionType, id, subType = GetActionInfo(tButtonObj.action)
			local tButtonName =""
			tButtonName = ButtonContentNameHelper(actionType, id, subType, aActionBarName, x)
			
			local tNewMenuEntry = SkuOptions:InjectMenuItems(aParentEntry, {L["Button"].." "..(x - tNameNumberMod)..(tAdditionalTotemBarNameParts[tActionBarData[aActionBarName].buttonName..x] or "")..";"..tButtonName}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.buttonObj = _G[tActionBarData[aActionBarName].buttonName..x]
			tNewMenuEntry.OnEnter = function(self, aValue, aName)
				self.spellID = nil
				self.itemID = nil
				self.macroID = nil
				self.companionID = nil
				self.equipmentSetID = nil
				if self.buttonObj.action then
					_G["SkuScanningTooltip"]:ClearLines()
					_G["SkuScanningTooltip"]:SetAction(self.buttonObj.action)
					if TooltipLines_helper(_G["SkuScanningTooltip"]:GetRegions()) ~= "asd" then
						if TooltipLines_helper(_G["SkuScanningTooltip"]:GetRegions()) ~= "" then
							local tText = SkuUtil:Unescape(TooltipLines_helper(_G["SkuScanningTooltip"]:GetRegions()))
							SkuOptions.currentMenuPosition.textFirstLine, SkuOptions.currentMenuPosition.textFull = SkuCore:ItemName_helper(tText)
						end
					end
				end
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				--dprint("OnAction", "aValue", aValue, "aName", aName)
				if aName == L["Assign nothing"] then
					PickupAction(self.buttonObj.action)
					ClearCursor()
				elseif self.spellID then
					ClearCursor()
					PickupAction(self.buttonObj.action)
					ClearCursor()
					if self.spellID then
						PickupSpell(self.spellID)
						if CursorHasSpell() then
							PlaceAction(self.buttonObj.action)
							ClearCursor()
						end
					end
				elseif self.itemID then
					ClearCursor()
					PickupItem(self.itemID)
					PlaceAction(self.buttonObj.action)
					ClearCursor()
				elseif self.macroID then
					ClearCursor()
					PickupMacro(self.macroID)
					PlaceAction(self.buttonObj.action)
					ClearCursor()
				elseif self.companionID then
					ClearCursor()
					PickupAction(self.buttonObj.action)
					ClearCursor()
					if self.companionSpellId then
						PickupSpell(self.companionSpellId)
						if CursorHasSpell() then
							PlaceAction(self.buttonObj.action)
							ClearCursor()
						end
					end
				elseif self.equipmentSetID then
					ClearCursor()
					PickupAction(self.buttonObj.action)
					ClearCursor()
					if self.equipmentSetID then
						C_EquipmentSet.PickupEquipmentSet(self.equipmentSetID) 
						PlaceAction(self.buttonObj.action)
						ClearCursor()
					end
				elseif aName == L["Bind key"] and aBooktype then
					SkuOptions.bindingMode = true
					SkuOptions.Voice:StopOutputEmptyQueue(true, nil)
					C_Timer.After(0.001, function()
						self.command = tActionBarData[aActionBarName].command..x --commandConst2
						self.category = tActionBarData[aActionBarName].header --categoryConst2
						self.index = SkuCore.Keys.SkuDefaultBindings[tActionBarData[aActionBarName].header][tActionBarData[aActionBarName].command..x].index --v1.index
						KeyBindingKeyMenuEntryHelper(self, aValue, L["Neu belegen"])
					end)
				end

				local actionType, id, subType = GetActionInfo(self.buttonObj.action)
				self.name = L["Button"].." "..x..";"..ButtonContentNameHelper(actionType, id, subType, aActionBarName, x)

				self.spellID = nil
				self.itemID = nil
				self.macroID = nil
			end
			tNewMenuEntry.BuildChildren = function(self)
				if aBooktype then
					SpellBookMenuBuilder(self, aBooktype)
				end
				ItemsMenuBuilder(self)
				
				
				MacrosMenuBuilder(self)
				local tNewMenuSubEntry = SkuOptions:InjectMenuItems(self, {L["Bind key"]}, SkuGenericMenuItem)
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
local function PetActionBarMenuBuilder(aParentEntry, aActionBarName, aBooktype)
	if not aParentEntry or not aActionBarName then return end

	local tButtonsWithCurrentPetControlAction = {
		PET_MODE_AGGRESSIVE = -1,
		PET_MODE_PASSIVE = -1,
		PET_MODE_DEFENSIVE = -1,
		PET_ACTION_ATTACK = -1,
		PET_ACTION_WAIT = -1,
		PET_ACTION_FOLLOW = -1,
	}

	for x = 1, NUM_PET_ACTION_SLOTS do
		local tButtonObj = _G[tActionBarData[aActionBarName].buttonName..x]
		if tButtonObj then
			local name = GetPetActionInfo(x)
			if name and tButtonsWithCurrentPetControlAction[name] then
				tButtonsWithCurrentPetControlAction[name] = x
			end
		end
	end

	for x = 1, NUM_PET_ACTION_SLOTS do
		local tButtonObj = _G[tActionBarData[aActionBarName].buttonName..x]
		if tButtonObj then
			local name, texture, isToken, isActive, autoCastAllowed, autoCastEnabled, spellID = GetPetActionInfo(x);
			local tButtonName = ButtonContentNameHelper("pet", x, subType, aActionBarName, x) --_G[name] or name or L["empty"] 
			local tNewMenuEntry = SkuOptions:InjectMenuItems(aParentEntry, {L["Button"].." "..x..";"..tButtonName}, SkuGenericMenuItem)
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.buttonObj = _G[tActionBarData[aActionBarName].buttonName..x]
			tNewMenuEntry.id = x
			tNewMenuEntry.OnEnter = function(self, aValue, aName)
				self.spellID = nil
				self.itemID = nil
				self.macroID = nil
				if self.buttonObj:GetID() and name then
					_G["SkuScanningTooltip"]:ClearLines()
					_G["SkuScanningTooltip"]:SetPetAction(x)
					if TooltipLines_helper(_G["SkuScanningTooltip"]:GetRegions()) ~= "asd" then
						if TooltipLines_helper(_G["SkuScanningTooltip"]:GetRegions()) ~= "" then
							local tText = SkuUtil:Unescape(TooltipLines_helper(_G["SkuScanningTooltip"]:GetRegions()))
							SkuOptions.currentMenuPosition.textFirstLine, SkuOptions.currentMenuPosition.textFull = SkuCore:ItemName_helper(tText)
						end
					end
				end
			end
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				dprint("OnAction", "aValue", aValue, "aName", aName, "petDefaultControlId", self.spellID)
				local tButtonObjId = self.buttonObj:GetID()
				if aName == L["Assign nothing"] then
					PickupPetAction(self.buttonObj:GetID())
					ClearCursor()
				elseif self.spellID and not self.petDefaultControlId then
					ClearCursor()
					if self.spellID then
						PickupPetSpell(self.spellID)
						PickupPetAction(self.buttonObj:GetID())
						ClearCursor()
					end					
				elseif self.petDefaultControlId then
					PickupPetAction(self.petDefaultControlId)
					PickupPetAction(self.buttonObj:GetID())
					ClearCursor()
				elseif aName == L["Bind key"] then
					SkuOptions.bindingMode = true
					SkuOptions.Voice:StopOutputEmptyQueue(true, nil)
					C_Timer.After(0.001, function()
						self.command = tActionBarData[aActionBarName].command..x --commandConst2
						self.category = tActionBarData[aActionBarName].header --categoryConst2
						self.index = SkuCore.Keys.SkuDefaultBindings[tActionBarData[aActionBarName].header][tActionBarData[aActionBarName].command..x].index --v1.index
						KeyBindingKeyMenuEntryHelper(self, aValue, L["Neu belegen"])
					end)
				end

				self.name = L["Button"].." "..x..";"..ButtonContentNameHelper("pet", self.id, subType, aActionBarName, self.id)
				self.spellID = nil
			end
			tNewMenuEntry.BuildChildren = function(self)
				SpellBookMenuBuilder(self, aBooktype, true, tButtonsWithCurrentPetControlAction)
				local tNewMenuSubEntry = SkuOptions:InjectMenuItems(self, {L["Bind key"]}, SkuGenericMenuItem)

				-- "Permanent"-Schalter (Autocast). Das Pet würfelt
				-- die Fähigkeit selbst, sofern Ressource (Mana / Fokus
				-- usw.) verfügbar ist. Die Sehenden setzen das per
				-- Rechtsklick auf das Icon — wir bieten hier eine
				-- tastatur-bediente Alternative.
				local lSlotID = x  -- Closure-Capture
				local lButtonName = tActionBarData[aActionBarName].buttonName .. x
				local lParentEntry = self
				local _, _, _, _, autoCastAllowed, autoCastEnabled = GetPetActionInfo(lSlotID)
				if autoCastAllowed then
					local tStateLabel = autoCastEnabled
						and L["aktiviert"] or L["deaktiviert"]
					local tPerm = SkuOptions:InjectMenuItems(self,
						{L["PETBAR_Autocast"] .. " (" .. tStateLabel .. ")"}, SkuGenericMenuItem)
					tPerm.dynamic = true
					tPerm.sorting = true
					tPerm.BuildChildren = function(self2)
						-- Aktiviert (macrotext: Rechtsklick auf PetActionButton)
						local tEnable = SkuOptions:InjectMenuItems(self2,
							{L["aktiviert"]}, SkuGenericMenuItem)
						tEnable.macrotext = "/click " .. lButtonName .. " RightButton"
						tEnable.secureMacro = true
						tEnable.OnAction = function()
							if SkuOptions and _G.C_Timer and _G.C_Timer.After then
								_G.C_Timer.After(0.05, function()
									SkuOptions.currentMenuPosition = lParentEntry
									if SkuOptions.VocalizeCurrentMenuName then
										pcall(function() SkuOptions:VocalizeCurrentMenuName() end)
									end
								end)
							end
						end

						-- Deaktiviert (gleicher macrotext — Toggle)
						local tDisable = SkuOptions:InjectMenuItems(self2,
							{L["deaktiviert"]}, SkuGenericMenuItem)
						tDisable.macrotext = "/click " .. lButtonName .. " RightButton"
						tDisable.secureMacro = true
						tDisable.OnAction = function()
							if SkuOptions and _G.C_Timer and _G.C_Timer.After then
								_G.C_Timer.After(0.05, function()
									SkuOptions.currentMenuPosition = lParentEntry
									if SkuOptions.VocalizeCurrentMenuName then
										pcall(function() SkuOptions:VocalizeCurrentMenuName() end)
									end
								end)
							end
						end
					end
				end
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
local function RangecheckMenuBuilder(aParent, aType)
	-- Refresh the availability snapshot straight from the live LibRangeCheck state
	-- right before we render, so the list is never stale/empty just because a
	-- CHECKERS_CHANGED callback was missed at load. Silent (no announce).
	if SkuCore.RangeCheck and SkuCore.RangeCheck.RangeCheckUpdateRanges then
		SkuCore.RangeCheck:RangeCheckUpdateRanges(false)
	end
	local tEntriesFound = false
	for i = 1, 100 do
		if SkuCore.RangeCheck.RangeCheckValues.Ranges[aType][i] then
			local tIsConfiguredWith = ";"..L["silent"]
			if SkuSettings:Sub("SkuCore", nil, "char").RangeChecks[aType][i] then
				if SkuSettings:Sub("SkuCore", nil, "char").RangeChecks[aType][i].sound == L["vocalized"] then
					tIsConfiguredWith = ";"..L["vocalized"]
				else
					tIsConfiguredWith = ";"..SkuCore.RangeCheckSounds[SkuSettings:Sub("SkuCore", nil, "char").RangeChecks[aType][i].sound]
				end
			end
			local tNewSubMenuEntry = SkuOptions:InjectMenuItems(aParent, {i..tIsConfiguredWith}, SkuGenericMenuItem)
			tEntriesFound = true
			tNewSubMenuEntry.dynamic = true
			tNewSubMenuEntry.isSelect = true
			tNewSubMenuEntry.OnAction = function(self, aValue, aName, aParentMenuName)
				local tRange = string.split(";", aParentMenuName)
				if aName == L["vocalized"] then
					SkuSettings:Sub("SkuCore", nil, "char").RangeChecks[aType][tonumber(tRange)] = {sound = L["vocalized"],}
				else
					for qi, qv in pairs(SkuCore.RangeCheckSounds) do
						if string.find(qv, aName) then
							SkuSettings:Sub("SkuCore", nil, "char").RangeChecks[aType][tonumber(tRange)] = {sound = qi,}
						end
					end
				end
				self.name = tRange..";"..aName
			end
			tNewSubMenuEntry.BuildChildren = function(self)
				local tNewSubSoundMenuEntry = SkuOptions:InjectMenuItems(self, {L["vocalized"]}, SkuGenericMenuItem)
				for x, v in pairs(SkuCore.RangeCheckSounds) do
					local tNewSubSoundMenuEntry = SkuOptions:InjectMenuItems(self, {v}, SkuGenericMenuItem)
					tNewSubSoundMenuEntry.dynamic = true
				end
			end
		end
	end
	if tEntriesFound == false then
		local tNewSubMenuEntry = SkuOptions:InjectMenuItems(aParent, {L["leer"]}, SkuGenericMenuItem)
	end

end
-- Exposed so the Monitor menu (SkuCore\aq.lua Aq:MonitorMenuBuilder) can reuse the
-- range-check builder: the "Entfernung" list was relocated from Kampf to Monitor.
SkuCore.RangecheckMenuBuilder = RangecheckMenuBuilder

local Sku_Mail_OpenAll_Listener
---------------------------------------------------------------------------------------------------------------------------------------
local function pairsByKeys (t, f)
	local a = {}
	for n in pairs(t) do table.insert(a, n) end
	table.sort(a, f)
	local i = 0      -- iterator variable
	local iter = function ()   -- iterator function
		i = i + 1
		if a[i] == nil then return nil
		else return a[i], t[a[i]]
		end
	end
	return iter
end


-- W7: top-level "Addons" menu — addon integrations that used to sit directly under
-- "Core". Each child reuses its existing builder (called with the entry as `self`,
-- as the old Core specs did). Module refs resolve at open time.
-- [8/15] Fernbedienung der Questie-Chatmitteilungen aus dem Addons-Menue.
-- Setzt die Werte direkt in Questie.db.profile (Questie persistiert selbst).
-- self ist der Menue-Eintrag (wie bei DamageMeterMenuBuilder).
function SkuCore:QuestieMenuBuilder()
	if not (_G.Questie and _G.Questie.db and _G.Questie.db.profile) then
		SkuOptions:InjectMenuItems(self, {L["Questie not installed"]}, SkuGenericMenuItem)
		return
	end
	local P = _G.Questie.db.profile

	-- Ein/Aus-Umschalter fuer ein boolsches Questie-Profilfeld.
	local function tBoolToggle(aLabel, aKey)
		local tNode = SkuOptions:InjectMenuItems(self, {aLabel}, SkuGenericMenuItem)
		tNode.dynamic = true
		tNode.isSelect = true
		tNode.GetCurrentValue = function(s, aValue, aName)
			if P[aKey] == true then return L["On"] else return L["Off"] end
		end
		tNode.OnAction = function(s, aValue, aName)
			if aName == L["Off"] then P[aKey] = false elseif aName == L["On"] then P[aKey] = true end
		end
		tNode.BuildChildren = function(s)
			SkuOptions:InjectMenuItems(s, {L["Off"]}, SkuGenericMenuItem)
			SkuOptions:InjectMenuItems(s, {L["On"]}, SkuGenericMenuItem)
		end
	end

	-- Master: Chatmitteilungen-Kanal (Aus / Gruppe / Schlachtzug / Beides)
	local cOff, cParty, cRaid, cBoth = L["Off"], L["Questie announce party"], L["Questie announce raid"], L["Questie announce both"]
	local tChan = SkuOptions:InjectMenuItems(self, {L["Questie chat announcements"]}, SkuGenericMenuItem)
	tChan.dynamic = true
	tChan.isSelect = true
	tChan.GetCurrentValue = function(s, aValue, aName)
		local v = P.questAnnounceChannel
		if v == "party" then return cParty elseif v == "raid" then return cRaid
		elseif v == "both" then return cBoth else return cOff end
	end
	tChan.OnAction = function(s, aValue, aName)
		if aName == cOff then P.questAnnounceChannel = "disabled"
		elseif aName == cParty then P.questAnnounceChannel = "party"
		elseif aName == cRaid then P.questAnnounceChannel = "raid"
		elseif aName == cBoth then P.questAnnounceChannel = "both" end
	end
	tChan.BuildChildren = function(s)
		SkuOptions:InjectMenuItems(s, {cOff}, SkuGenericMenuItem)
		SkuOptions:InjectMenuItems(s, {cParty}, SkuGenericMenuItem)
		SkuOptions:InjectMenuItems(s, {cRaid}, SkuGenericMenuItem)
		SkuOptions:InjectMenuItems(s, {cBoth}, SkuGenericMenuItem)
	end

	-- Einzel-Optionen (was im Chat geteilt wird)
	tBoolToggle(L["Announce quest accepted"], "questAnnounceAccepted")
	tBoolToggle(L["Announce quest abandoned"], "questAnnounceAbandoned")
	tBoolToggle(L["Announce quest progress"], "questAnnounceObjectives")
	tBoolToggle(L["Announce quest completed"], "questAnnounceCompleted")
	tBoolToggle(L["Announce quest items"], "questAnnounceItems")
end

function SkuCore:AddonsMenuBuilder(aParentEntry)
	local tSpecs = {}
	if SkuCore.AtlasLootIntegration and SkuCore.AtlasLootIntegration.alIntegrationMenuBuilder then
		tSpecs[#tSpecs+1] = { kind = "list", label = L["Atlas Loot"], sorting = true,
			build = SkuCore.AtlasLootIntegration.alIntegrationMenuBuilder }
	end
	if SkuCore.DamageMeter and SkuCore.DamageMeter.DamageMeterMenuBuilder then
		tSpecs[#tSpecs+1] = { kind = "list", label = L["Damage Meter"], sorting = true,
			build = SkuCore.DamageMeter.DamageMeterMenuBuilder }
	end
	if _G.Questie and _G.Questie.db then
		tSpecs[#tSpecs+1] = { kind = "list", label = "Questie", sorting = true,
			build = SkuCore.QuestieMenuBuilder }
	end
	-- Other addons' AceConfig settings (Questie, ECS, ...) rendered generically;
	-- logic in SkuCore/addonOptions.lua. The Escape menu's "AddOns" button routes
	-- here too (gameOptions.lua GameMenuBuilder).
	if SkuCore.AddonOptions and SkuCore.AddonOptions.AddonOptionsMenuBuilder then
		tSpecs[#tSpecs+1] = { kind = "list", label = Sku.deEn("AddOn-Einstellungen", "AddOn settings", "Réglages des extensions"), sorting = false,
			build = function(entry) SkuCore.AddonOptions:AddonOptionsMenuBuilder(entry) end }
	end
	SkuMenu:Build(aParentEntry, tSpecs)
end

-- Baut die "Brief verfassen"-Kindeintraege unter aLetterEntry auf und wird von
-- BEIDEN Verfassen-Pfaden benutzt: "Neuer Brief" (leer) und "Beantworten" (mit
-- vorbelegtem Empfaenger/Betreff). aLetterEntry haelt die Zwischenwerte
-- (TmpTo / TmpSubject / TmpBody / TmpMoneyCfg / TmpItemsLock) und ist zugleich der
-- Fokus-Rueckkehrpunkt nach dem Senden.
--
-- Eintraege:
--   Empfaenger / Betreff / Text -> NORMALE Eingabefelder (MailEditor): tippen,
--     mit ENTER bestaetigen. Der eingegebene Wert steht danach in der Beschriftung.
--   Gold anhaengen -> Gold/Silber/Kupfer-Muenzmenue (Geschwister), genau wie im
--     Auktionshaus: in eine Muenze gehen zeigt eine 0..max-Werteliste, ENTER auf
--     einem Wert setzt ihn und kehrt ins Muenzmenue zurueck (isSelect +
--     noStepUpAfterSelect); der Gesamtbetrag wird sofort per SetSendMailMoney an
--     den Brief gehaengt.
--   Gegenstaende anhaengen -> Taschen-Liste, ENTER haengt den Gegenstand an.
--   Senden -> prueft Empfaenger/Betreff und ruft SendMail.
function SkuCore.MailBuildComposeChildren(aLetterEntry)
	local tLetter = aLetterEntry

	-- 1. Empfaenger (normales Eingabefeld)
	local tToEntry = SkuOptions:InjectMenuItems(tLetter, {L["Recepient"]..(tLetter.TmpTo and (": "..tLetter.TmpTo) or "")}, SkuGenericMenuItem)
	tToEntry.OnAction = function(self)
		SkuCore.Mail:MailEditor("TmpTo", L["Recepient"])
	end

	-- 2. Betreff (normales Eingabefeld)
	local tSubjectEntry = SkuOptions:InjectMenuItems(tLetter, {L["Topic"]..(tLetter.TmpSubject and (": "..tLetter.TmpSubject) or "")}, SkuGenericMenuItem)
	tSubjectEntry.OnAction = function(self)
		SkuCore.Mail:MailEditor("TmpSubject", L["Topic"])
	end

	-- 3. Text (normales Eingabefeld)
	local tTextEntry = SkuOptions:InjectMenuItems(tLetter, {L["Text"]..(tLetter.TmpBody and (": "..tLetter.TmpBody) or "")}, SkuGenericMenuItem)
	tTextEntry.OnAction = function(self)
		SkuCore.Mail:MailEditor("TmpBody", L["Text"])
	end

	-- 4. Gegenstaende anhaengen
	local tItemsEntry = SkuOptions:InjectMenuItems(tLetter, {L["MAIL_AttachItems"]}, SkuGenericMenuItem)
	tItemsEntry.sorting = true
	tItemsEntry.dynamic = true
	local lItemsEntry = tItemsEntry
	tItemsEntry.BuildChildren = function(self)
		-- [Fix Nr24] Schluesselbund (Keyring) mit einbeziehen, damit ein nicht
		-- seelengebundener Silberdietrich per Post verschickt werden kann. Die
		-- bestehende IsItemSoulbound-Pruefung (unten) filtert seelengebundene
		-- Schluessel weiterhin aus.
		local tContainers = {}
		-- [Fix Nr24] Zuerst die Taschen (0..4), Schluesselbund ganz ans Ende, damit
		-- Schluessel-Items nicht auf Position 1 stehen.
		for b = BACKPACK_CONTAINER, NUM_BAG_SLOTS do tContainers[#tContainers+1] = b end
		if KEYRING_CONTAINER then tContainers[#tContainers+1] = KEYRING_CONTAINER end
		for _, bag in ipairs(tContainers) do
			for slot = 1, GetContainerNumSlots(bag) do
				local tLocked = tLetter.TmpItemsLock and tLetter.TmpItemsLock[bag.."-"..slot]
				if not tLocked then
					local itemLink = GetContainerItemLink(bag, slot)
					local icon, itemCount = GetContainerItemInfo(bag, slot)
					if itemLink and SkuCore:IsItemSoulbound(bag, slot) ~= true then
						local tItemEntry = SkuOptions:InjectMenuItems(self, {bag.." "..slot..": "..C_Item.GetItemNameByID(itemLink).." ("..itemCount..")"}, SkuGenericMenuItem)
						local lBag, lSlot = bag, slot
						tItemEntry.OnAction = function()
							-- [v42.08] Zuverlaessiges Anhaengen (Naxedim-Muster): einen freien
							-- Anhang-Slot suchen, das Item vom Cursor per ClickSendMailItemButton in
							-- GENAU diesen Slot legen und DANACH mit GetSendMailItem verifizieren.
							-- Der alte Pfad (SendMailAttachmentButton_OnDropAny) ist auf TBC
							-- Anniversary praktisch ein No-op: das Item blieb am Cursor haengen und
							-- der Slot wurde trotzdem (faelschlich) aus der Liste ausgeblendet.
							local tMax = ATTACHMENTS_MAX_SEND or 12
							local tFree
							for i = 1, tMax do
								if not GetSendMailItem(i) then tFree = i break end
							end
							if not tFree then
								pcall(function() SkuOptions.Voice:OutputStringBTtts(Sku.deEn("Alle Anhang-Plaetze belegt", "All attachment slots are full", "Tous les emplacements de pièce jointe sont pleins"), false, true, 0.2) end)
								return
							end
							ClearCursor()
							pcall(PickupContainerItem, lBag, lSlot)
							pcall(ClickSendMailItemButton, tFree)
							if GetSendMailItem(tFree) then
								-- Erfolg: den Slot erst JETZT aus der Liste ausblenden.
								if not tLetter.TmpItemsLock then tLetter.TmpItemsLock = {} end
								tLetter.TmpItemsLock[lBag.."-"..lSlot] = true
							else
								-- Fehlgeschlagen: Item NICHT am Cursor haengen lassen.
								ClearCursor()
							end
							local function tForce()
								if not SkuOptions then return end
								SkuOptions.currentMenuPosition = lItemsEntry
								if SkuOptions.ClearFilter then pcall(SkuOptions.ClearFilter, SkuOptions) end
							end
							if _G.C_Timer and _G.C_Timer.After then
								_G.C_Timer.After(0.02, tForce)
								_G.C_Timer.After(0.10, tForce)
								_G.C_Timer.After(0.30, function()
									tForce()
									if SkuOptions.VocalizeCurrentMenuName then
										pcall(function() SkuOptions:VocalizeCurrentMenuName() end)
									end
								end)
							end
						end
					end
				end
			end
		end
	end

	-- 4b. [v42.08] Angehaengte Gegenstaende sichten / einzeln zuruecknehmen. Sku bot
	-- bisher keine Moeglichkeit, bereits angehaengte Objekte zu pruefen oder wieder
	-- abzunehmen. ENTER auf einem Eintrag gibt das Objekt in die Taschen zurueck.
	local tAttachedEntry = SkuOptions:InjectMenuItems(tLetter, {Sku.deEn("Angehaengte Gegenstaende", "Attached items", "Objets joints")}, SkuGenericMenuItem)
	tAttachedEntry.dynamic = true
	tAttachedEntry.BuildChildren = function(self)
		local tMax = ATTACHMENTS_MAX_SEND or 12
		local tAny = false
		for i = 1, tMax do
			local tName, _, _, tCount = GetSendMailItem(i)
			if tName then
				tAny = true
				local tSlot = i
				local tCountSuffix = (tCount and tCount > 1) and (" ("..tCount..")") or ""
				local tItemEntry = SkuOptions:InjectMenuItems(self, {tName..tCountSuffix}, SkuGenericMenuItem)
				tItemEntry.OnAction = function()
					-- Anhang zuruecknehmen (rechte-Maustaste-Aequivalent): Objekt geht in
					-- die Taschen. Cursor vorher/nachher leeren, damit nichts haengen bleibt.
					ClearCursor()
					pcall(ClickSendMailItemButton, tSlot, true)
					ClearCursor()
					-- Angehaengte Objekte liegen physisch NICHT mehr in den Taschen; das
					-- zurueckgegebene erscheint dort wieder. Alle Ausblend-Marker loeschen,
					-- damit die Anhang-Liste (Abschnitt 4) frisch aus den Taschen neu baut.
					tLetter.TmpItemsLock = nil
					pcall(function() SkuOptions.Voice:OutputStringBTtts(Sku.deEn("Anhang entfernt", "Attachment removed", "Pièce jointe retirée"), false, true, 0.2) end)
					local function tForce()
						if not SkuOptions then return end
						SkuOptions.currentMenuPosition = tAttachedEntry
						if SkuOptions.ClearFilter then pcall(SkuOptions.ClearFilter, SkuOptions) end
					end
					if _G.C_Timer and _G.C_Timer.After then
						_G.C_Timer.After(0.02, tForce)
						_G.C_Timer.After(0.20, function()
							tForce()
							if SkuOptions.VocalizeCurrentMenuName then
								pcall(function() SkuOptions:VocalizeCurrentMenuName() end)
							end
						end)
					end
				end
			end
		end
		if not tAny then
			SkuOptions:InjectMenuItems(self, {Sku.deEn("Keine Anhaenge", "No attachments", "Aucune pièce jointe")}, SkuGenericMenuItem)
		end
	end

	-- 5. Gold anhaengen: Gold/Silber/Kupfer-Muenzmenue (wie Auktionshaus).
	local tGoldEntry = SkuOptions:InjectMenuItems(tLetter, {L["MAIL_AttachGold"]}, SkuGenericMenuItem)
	tGoldEntry.dynamic = true
	tGoldEntry.BuildChildren = function(self)
		local tCfg = tLetter.TmpMoneyCfg
		if not tCfg then
			tCfg = {gold = 0, silver = 0, copper = 0}
			tLetter.TmpMoneyCfg = tCfg
		end

		-- Gesamtbetrag (Kupfer) an den offenen Brief haengen.
		local function tApplyMoney()
			pcall(SetSendMailMoney, (tCfg.gold or 0) * 10000 + (tCfg.silver or 0) * 100 + (tCfg.copper or 0))
		end
		local function tParseNum(aValue, aName)
			local tNum = tonumber(aName)
			if not tNum and aValue and aValue.name then tNum = tonumber(aValue.name) end
			return tNum
		end

		-- Ein Muenz-Eintrag (Geschwister). isSelect + noStepUpAfterSelect: ENTER auf
		-- einem Wert setzt ihn und bleibt im Muenzmenue. GetCurrentValue positioniert
		-- den Cursor auf den aktuellen Wert.
		local function tAddCoin(aKey, aLabel, aMax)
			local tInputLabel = Sku.deEn("Betrag eingeben", "Enter amount", "Saisir le montant")
			local tNode = SkuOptions:InjectMenuItems(self, {aLabel..": "..(tCfg[aKey] or 0)}, SkuGenericMenuItem)
			tNode.dynamic = true
			tNode.sorting = true
			tNode.isSelect = true
			tNode.noStepUpAfterSelect = true
			tNode.GetCurrentValue = function(s) return tostring(tCfg[aKey] or 0) end
			tNode.OnAction = function(s, aValue, aName)
				-- [v42.08] Erster Listeneintrag = Freitext-Eingabe: erlaubt Betraege ueber
				-- die Listengrenze hinaus (z. B. mehr als 999 Gold). Die vertraute
				-- 0..N-Werteliste bleibt daneben erhalten -- beide Wege aktiv.
				if aName == tInputLabel then
					PlaySound(88)
					pcall(function() SkuOptions.Voice:OutputStringBTtts(L["Enter text and press ENTER key"], false, true, 0.2) end)
					SkuOptions:EditBoxShow(tostring(tCfg[aKey] or 0), function()
						PlaySound(89)
						local tNum = math.floor(tonumber(SkuOptionsEditBoxEditBox:GetText() or "") or 0)
						if tNum < 0 then tNum = 0 end
						tCfg[aKey] = tNum
						s.name = aLabel..": "..tNum
						tApplyMoney()
						if SkuOptions then SkuOptions.currentMenuPosition = s end
						pcall(function() SkuOptions.Voice:OutputStringBTtts(tNum.." "..aLabel, true, true, 0.2, nil, nil, nil, 2) end)
					end)
					return
				end
				tCfg[aKey] = tParseNum(aValue, aName) or 0
				s.name = aLabel..": "..tCfg[aKey]
				tApplyMoney()
				pcall(function() SkuOptions.Voice:OutputStringBTtts(tCfg[aKey].." "..aLabel, true, true, 0.2, nil, nil, nil, 2) end)
			end
			tNode.BuildChildren = function(s)
				SkuOptions:InjectMenuItems(s, {tInputLabel}, SkuGenericMenuItem)
				for x = 0, aMax do
					SkuOptions:InjectMenuItems(s, {tostring(x)}, SkuGenericMenuItem)
				end
			end
		end
		tAddCoin("gold", L["Gold"], 999)
		tAddCoin("silver", L["Silver"], 99)
		tAddCoin("copper", L["Copper"], 99)
	end

	-- 6. Senden
	local tSendEntry = SkuOptions:InjectMenuItems(tLetter, {L["Send"]}, SkuGenericMenuItem)
	tSendEntry.OnAction = function(self)
		if not tLetter.TmpTo then
			SkuOptions.Voice:OutputStringBTtts(L["No Recipient"], false, true, 0.2)
			return
		end
		if not tLetter.TmpSubject then
			SkuOptions.Voice:OutputStringBTtts(L["No topic"], false, true, 0.2)
			return
		end
		-- [v42.08] Den aktiven Entwurf fuer die Ergebnis-Handler merken (mail.lua):
		-- MAIL_SEND_SUCCESS leert die Zwischenwerte und sagt "Gesendet" an;
		-- MAIL_FAILED (z. B. Empfaenger unbekannt, Postfach voll) meldet den
		-- Fehlschlag und LAESST den Entwurf stehen -- so muss der Nutzer nach einem
		-- Tippfehler nur den Namen korrigieren und erneut senden. Frueher wurde der
		-- Entwurf optimistisch direkt nach SendMail geleert und war bei jedem
		-- Fehlschlag verloren; ausserdem blieb ein Fehlschlag voellig stumm.
		SkuCore.Mail.gPendingCompose = tLetter
		SendMail(tLetter.TmpTo, tLetter.TmpSubject, tLetter.TmpBody or " ")
	end
end

-- W7: Mail menu lifted to file scope so it can be a Local window contributor
-- (opened via the contextual "Local" menu when the mailbox is shown) instead
-- of a permanent Core "Mail" child. Body is the unchanged inline build closure.
function SkuCore.MailMenuBuilder(self)
		-- Neuer Brief: leerer Verfassen-Baum (Empfaenger/Betreff/Text/Gold/Items/Senden).
		local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["New letter"]}, SkuGenericMenuItem)
		tNewMenuEntry.dynamic = true
		tNewMenuEntry.BuildChildren = function(self)
			SkuCore.MailBuildComposeChildren(self)
		end

		local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Open all"]}, SkuGenericMenuItem)
		--tNewMenuEntry.ttsEngine = 2
		tNewMenuEntry.OnAction = function(self, aValue, aName)
			local numItems, totalItems = GetInboxNumItems()
			if totalItems > 0 then
				if not Sku_Mail_OpenAll_Listener then
					Sku_Mail_OpenAll_Listener = CreateFrame("FRAME", "Sku_Mail_OpenAll_Listener")
				end

				-- since these functions refer to each other, they need to be declared ahead of time
				local openAllLoop, continueLoopAfterNMailSuccesses

				openAllLoop = function(index)
					if index <= select(2, GetInboxNumItems()) then
						local inboxItemInfo = { GetInboxHeaderInfo(index) }
						-- if mail from auction house, inbox item is auto deleted after taking money/items, so 1 additional success to listen for
						local auctionHouseAddend = string.find(string.lower(inboxItemInfo[3]), string.lower(L["Auction house"])) and 1 or 0
						-- take money if exist
						if (inboxItemInfo[5] or 0) > 0 then
							continueLoopAfterNMailSuccesses(1 + auctionHouseAddend, index)
							TakeInboxMoney(index)
							return
						end
						-- take items if exist
						local numToTake = inboxItemInfo[8] or 0
						if numToTake > 0 then
							continueLoopAfterNMailSuccesses(numToTake + auctionHouseAddend, index)
							AutoLootMailItem(index)
							return
						end
						-- no money or items so delete it
						continueLoopAfterNMailSuccesses(1, index)
						DeleteInboxItem(index)
					else -- done opening
						-- delay otherwise might be cut off
						C_Timer.After(0.5, function()
							SkuOptions.Voice:OutputStringBTtts(L["All opened"], false, true, 0.2)
						end)
					end
				end

				---Sets up listening for whether the next mail command succeeds or fails
				continueLoopAfterNMailSuccesses = function(n, index)
					local function deactivateListener()
						Sku_Mail_OpenAll_Listener:UnregisterAllEvents()
						Sku_Mail_OpenAll_Listener:SetScript("OnEvent", nil)
					end

					local function handler(self, event)
						if event == "MAIL_CLOSED" then
							-- player closed mailbox during open all, break loop
							deactivateListener()
						elseif event == "MAIL_SUCCESS" then
							-- one of an item was received, money was received, or inbox item deleted
							n = n - 1
							if n == 0 then
								-- mail command completed successfully, go to start of loop
								deactivateListener()
								openAllLoop(index)
							end
						elseif event == "MAIL_FAILED" then
							-- failed to perform the mail command, most likely failed to take item because bags are full
							-- skip this mail item and try next one
							deactivateListener()
							openAllLoop(index + 1)
						end
					end

					Sku_Mail_OpenAll_Listener:SetScript("OnEvent", handler)
					for _, e in pairs({ "MAIL_CLOSED", "MAIL_SUCCESS", "MAIL_FAILED" }) do
						Sku_Mail_OpenAll_Listener:RegisterEvent(e)
					end
				end

				openAllLoop(1)

			end
		end

		local numItems, totalItems = GetInboxNumItems()
		for x = 1, totalItems do
			local packageIcon, stationeryIcon, sender, subject, money, CODAmount, daysLeft, hasItem, wasRead, wasReturned, textCreated, canReply, isGM = GetInboxHeaderInfo(x)
			if sender then
				local tSubject = ""
				if CODAmount > 0 then
					tSubject = x.." "..sender.." - "..L["Caution: Cash on delivery"].."! - "..(subject or L["No topic"])
				else
					tSubject = x.." "..sender.." - "..(subject or L["No topic"])
				end
				local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {tSubject}, SkuGenericMenuItem)
				tNewMenuEntry.dynamic = true
				tNewMenuEntry.isSelect = true
				-- [41.02.08] Nach Anhang-Entnahme (auch nach Loeschen) Cursor auf dem
				-- Brief halten, statt zur Inbox hochzuspringen. MAIL_INBOX_UPDATE ->
				-- OnUpdate baut die Inbox neu und bleibt auf dem Brief; per Rechts-Taste
				-- wieder in die aktualisierten Anhaenge. Beim Loeschen faellt OnUpdate
				-- sauber auf einen Nachbar-Brief zurueck. RUECKBAU: diese Zeile entfernen.
				tNewMenuEntry.noStepUpAfterSelect = true
				tNewMenuEntry.OnAction = function(self, aValue, aName)
					--dprint("onaction mailitem", self, aValue, aName)
					--dprint(aName, self.TmpMailItemIndex, self.TmpMailItemIndexAttachmentIndex)
					if aName == L["Reply"] then
						--dprint(self.name, "beantworten")

					elseif aName == L["Take gold"] then
						if self.TmpMailItemIndex then
							TakeInboxMoney(self.TmpMailItemIndex)
						end
					elseif aName == L["Take all"] then
						if self.TmpMailItemIndex then
							AutoLootMailItem(self.TmpMailItemIndex)
						end

					elseif aName == L["Delete"] then
						if self.TmpMailItemIndex then
							DeleteInboxItem(self.TmpMailItemIndex)
						end
					elseif aName ~= "" then
						if self.TmpMailItemIndex and self.TmpMailItemIndexAttachmentIndex then
							local itemLink = GetInboxItemLink(self.TmpMailItemIndex, self.TmpMailItemIndexAttachmentIndex)
							TakeInboxItem(self.TmpMailItemIndex, self.TmpMailItemIndexAttachmentIndex)
						end
					end
				end
				tNewMenuEntry.OnEnter = function(self, aValue, aName)
					self.TmpMailItemIndex = x
					self.TmpMailItemIndexAttachmentIndex = nil
					local bodyText, stationaryMiddle, stationaryEdge, isTakeable, isInvoice = GetInboxText(x)
					local tSubject = ""
					local tGoldDir = ""
					if CODAmount > 0 then
						tSubject = L["Caution: Cash on delivery"].."! - "..(subject or L["No topic"])
						tGoldDir = L["CASH ON DELIVERY"].."! "
						money = CODAmount
					else
						tGoldDir = L["Attached"]..": "
						tSubject = (subject or L["No topic"])
					end

					local tGold, tSilver, tCopper = 0, 0, 0
					if money then
						tCopper = money
						tGold = math.floor(tCopper / 10000)
						tSilver = math.floor((tCopper - (tGold * 10000)) / 100)
						tCopper = tCopper - (tGold * 10000) - (tSilver * 100)
					end

					SkuOptions.currentMenuPosition.textFull = L["Sender"]..": "..sender.."\r\n"..L["Topic"]..": "..tSubject.."\r\n"..tGoldDir..tGold.." "..L["Gold"].." "..tSilver.." "..L["Silver"].." "..tCopper.." "..L["Copper"].."\r\n"..L["Attached"]..": "..(hasItem or "0").." "..L["Items"].."\r\n"..L["Text"]..": "..(bodyText or L["Empty"])
				end

				tNewMenuEntry.BuildChildren = function(self)
					local tNewMenuParentEntrySub = SkuOptions:InjectMenuItems(self, {L["Reply"]}, SkuGenericMenuItem)
					tNewMenuParentEntrySub.dynamic = true
					-- Empfaenger/Betreff aus dem Original vorbelegen; alle Felder bleiben
					-- editierbar. Verfassen-Baum kommt aus dem gemeinsamen Builder (gleiche
					-- normalen Eingabefelder + Gold/Silber/Kupfer-Muenzmenue wie "Neuer Brief").
					tNewMenuParentEntrySub.TmpTo = sender
					tNewMenuParentEntrySub.TmpSubject = subject
					tNewMenuParentEntrySub.BuildChildren = function(self)
						SkuCore.MailBuildComposeChildren(self)
					end

					if hasItem or (money and money > 0) then
						local tNewMenuParentEntrySub = SkuOptions:InjectMenuItems(self, {L["Attachments"]}, SkuGenericMenuItem)
						tNewMenuParentEntrySub.dynamic = true
						--tNewMenuParentEntrySub.ttsEngine = 2
						tNewMenuParentEntrySub.BuildChildren = function(self)
							if (money and money > 0 and CODAmount == 0) then
								local tNewMenuParentEntrySubSub = SkuOptions:InjectMenuItems(self, {L["Take gold"]}, SkuGenericMenuItem)
								--tNewMenuParentEntrySubSub.dynamic = true
								--tNewMenuParentEntrySubSub.ttsEngine = 2
							end

							if hasItem then
								local tNewMenuParentEntrySubSub = SkuOptions:InjectMenuItems(self, {L["Take all"]}, SkuGenericMenuItem)
								--tNewMenuParentEntrySubSub.dynamic = true
								--tNewMenuParentEntrySubSub.ttsEngine = 2
								for y = 1, ATTACHMENTS_MAX_RECEIVE do
									local itemLink = GetInboxItemLink(x, y)
									--itemLink = itemLink or L["Empty"]
									if itemLink then
										local name = GetInboxItem(x, y)
										name = name or L["Empty"]
										local tNewMenuParentEntrySubSub = SkuOptions:InjectMenuItems(self, {y.." "..name}, SkuGenericMenuItem)
										--tNewMenuParentEntrySubSub.dynamic = true
										--tNewMenuParentEntrySubSub.ttsEngine = 2
										tNewMenuParentEntrySubSub.OnEnter = function(self, aValue, aName)
											if itemLink ~= L["Empty"] then
												local name, itemID, texture, count, quality, canUse  = GetInboxItem(x, y)
												if itemID then
													_G["SkuScanningTooltip"]:ClearLines()
													_G["SkuScanningTooltip"]:SetItemByID(itemID)
													if TooltipLines_helper(_G["SkuScanningTooltip"]:GetRegions()) ~= "asd" then
														if TooltipLines_helper(_G["SkuScanningTooltip"]:GetRegions()) ~= "" then
															local tText = SkuUtil:Unescape(TooltipLines_helper(_G["SkuScanningTooltip"]:GetRegions()))
															SkuOptions.currentMenuPosition.textFirstLine, SkuOptions.currentMenuPosition.textFull = SkuCore:ItemName_helper(tText)
														end
													end
												end
												self.selectTarget.TmpMailItemIndexAttachmentIndex = y
											end
										end
									end
								end
							end
						end
					end

					local tNewMenuParentEntrySub = SkuOptions:InjectMenuItems(self, {L["Delete"]}, SkuGenericMenuItem)
					--tNewMenuParentEntrySub.dynamic = true
					--tNewMenuParentEntrySub.ttsEngine = 2
				end
			end
		end
end

-- Builds the action bars list (one entry per active bar; each descends into
-- ActionBarMenuBuilder). Extracted verbatim from the old Einstellungen>Sonstiges
-- "Action bars" node so it is NO LONGER browsable in the settings tree -- it is now
-- reached ONLY as the hidden "Aktionsleisten" root entry that Shift-F11 splices in
-- (SkuCore:UpdateActionBarsRootEntry / SkuCore:ActionBarsShowHandler), mirroring how
-- the Escape "Spielmenue" and the Auktionshaus stay in the tree but off the browsable
-- root. Defined at file scope (not inside MenuBuilder) so it exists at login, before
-- Einstellungen is ever opened. `self` is the menu parent (called via
-- node:BuildChildren -> SkuCore.ActionBarsMenuBuilder(self)).
function SkuCore.ActionBarsMenuBuilder(self)
	local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {tActionBarData["MainMenuBar"].friendlyName}, SkuGenericMenuItem)
	tNewMenuEntry.dynamic = true
	tNewMenuEntry.sorting = true
	tNewMenuEntry.BuildChildren = function(self)
		ActionBarMenuBuilder(self, "MainMenuBar", BOOKTYPE_SPELL)
	end
	local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {tActionBarData["MultiBarBottomLeft"].friendlyName}, SkuGenericMenuItem)
	tNewMenuEntry.dynamic = true
	tNewMenuEntry.sorting = true
	tNewMenuEntry.BuildChildren = function(self)
		ActionBarMenuBuilder(self, "MultiBarBottomLeft", BOOKTYPE_SPELL)
	end
	local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {tActionBarData["MultiBarBottomRight"].friendlyName}, SkuGenericMenuItem)
	tNewMenuEntry.dynamic = true
	tNewMenuEntry.sorting = true
	tNewMenuEntry.BuildChildren = function(self)
		ActionBarMenuBuilder(self, "MultiBarBottomRight", BOOKTYPE_SPELL)
	end
	local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {tActionBarData["MultiBarRight"].friendlyName}, SkuGenericMenuItem)
	tNewMenuEntry.dynamic = true
	tNewMenuEntry.sorting = true
	tNewMenuEntry.BuildChildren = function(self)
		ActionBarMenuBuilder(self, "MultiBarRight", BOOKTYPE_SPELL)
	end
	local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {tActionBarData["MultiBarLeft"].friendlyName}, SkuGenericMenuItem)
	tNewMenuEntry.dynamic = true
	tNewMenuEntry.sorting = true
	tNewMenuEntry.BuildChildren = function(self)
		ActionBarMenuBuilder(self, "MultiBarLeft", BOOKTYPE_SPELL)
	end

	-- Pet action bar: the previous check relied on PetActionBarFrame:IsShown(),
	-- which is false while the frame is hidden by layout rules (e.g. on the
	-- Anniversary client right after login or while the menu is being built
	-- before the pet frame becomes visible). Use a broader set of pet-presence
	-- probes so the entry reappears for Hunters, Warlocks, etc. whenever the
	-- character actually has a pet with an action bar.
	local tHasPet = false
	if _G.UnitExists and _G.UnitExists("pet") then tHasPet = true end
	if not tHasPet and _G.HasPetUI then
		local ok, v = pcall(_G.HasPetUI); if ok and v then tHasPet = true end
	end
	if not tHasPet and _G.HasPetSpells then
		local ok, v = pcall(_G.HasPetSpells); if ok and v then tHasPet = true end
	end
	if not tHasPet and _G.PetHasActionBar then
		local ok, v = pcall(_G.PetHasActionBar); if ok and v then tHasPet = true end
	end
	if not tHasPet and _G["PetActionBarFrame"] and _G["PetActionBarFrame"]:IsShown() == true then
		tHasPet = true
	end
	if tHasPet then
		local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {tActionBarData["PetBar"].friendlyName}, SkuGenericMenuItem)
		tNewMenuEntry.dynamic = true
		tNewMenuEntry.sorting = true
		tNewMenuEntry.BuildChildren = function(self)
			PetActionBarMenuBuilder(self, "PetBar", BOOKTYPE_PET)
		end
	end
	if _G["OverrideActionBar"] and _G["OverrideActionBar"]:IsShown() == true then
		local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {tActionBarData["OverrideActionBar"].friendlyName}, SkuGenericMenuItem)
		tNewMenuEntry.dynamic = true
		tNewMenuEntry.sorting = true
		tNewMenuEntry.BuildChildren = function(self)
			ActionBarMenuBuilder(self, "OverrideActionBar", nil)
		end
	end
	if _G["MultiCastActionBarFrame"] and _G["MultiCastActionBarFrame"]:IsShown() == true then
		local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {tActionBarData["MultiCastActionBar1"].friendlyName}, SkuGenericMenuItem)
		tNewMenuEntry.dynamic = true
		tNewMenuEntry.sorting = true
		tNewMenuEntry.BuildChildren = function(self)
			ActionBarMenuBuilder(self, "MultiCastActionBar1", BOOKTYPE_SPELL)
		end

		local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {tActionBarData["MultiCastActionBar2"].friendlyName}, SkuGenericMenuItem)
		tNewMenuEntry.dynamic = true
		tNewMenuEntry.sorting = true
		tNewMenuEntry.BuildChildren = function(self)
			ActionBarMenuBuilder(self, "MultiCastActionBar2", BOOKTYPE_SPELL)
		end

		local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {tActionBarData["MultiCastActionBar3"].friendlyName}, SkuGenericMenuItem)
		tNewMenuEntry.dynamic = true
		tNewMenuEntry.sorting = true
		tNewMenuEntry.BuildChildren = function(self)
			ActionBarMenuBuilder(self, "MultiCastActionBar3", BOOKTYPE_SPELL)
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Settings search ("Einstellungen durchsuchen"). A text-input leaf placed FIRST in
-- the Einstellungen menu. ENTER opens a text box (SkuOptions:EditBoxShow, same as
-- the mail composer); on confirm we walk a SCRATCH copy of the whole Einstellungen
-- tree, collect every entry whose name contains the typed text, and render the
-- matches as this entry's children -- a flat, breadcrumb-labelled result list. ENTER
-- (or RIGHT) on a result JUMPS the live menu to that setting and opens it (its
-- on/off / value submenu), exactly like navigating there by hand. RIGHT on the
-- search field itself re-browses the last result list without re-typing.
--
-- The walk uses a scratch tree (SkuCore:MenuBuilder on a throwaway root) so the live
-- menu the user is sitting in is never mutated; each dynamic BuildChildren runs under
-- pcall and is bounded by depth/visit caps. isSelect value-leaves (On/Off, enum
-- values, range numbers) are collected but not descended into -- they are the search
-- targets, not containers.
---------------------------------------------------------------------------------------------------------------------------------------
local SETTINGS_SEARCH_MAXDEPTH = 10
local SETTINGS_SEARCH_MAXVISIT = 6000

local function SettingsSearchMatch(aName, aQueryLower)
	if type(aName) ~= "string" then return false end
	return string.find(string.lower(aName), aQueryLower, 1, true) ~= nil
end

-- DFS the scratch tree, collecting {name=breadcrumb, path={names}} for every entry
-- whose name matches. `path` is the list of node names from a top-level category
-- down to the match (inclusive), used later to re-descend the LIVE tree.
function SkuCore:SettingsSearchCollect(aQuery)
	local tResults = {}
	if not aQuery or aQuery == "" then return tResults end
	local tQueryLower = string.lower(aQuery)

	-- throwaway root; MenuBuilder injects the search field + all categories into it
	local tScratchRoot = { name = "__settingsSearchScratch", children = {} }
	local tOk = pcall(function() SkuCore:MenuBuilder(tScratchRoot) end)
	if not tOk then return tResults end

	local tVisited = 0

	local function tWalk(aNode, aPath, aDepth)
		if tVisited >= SETTINGS_SEARCH_MAXVISIT then return end

		-- build this level's children on demand (dynamic containers start empty)
		local tChildren = aNode.children
		if (type(tChildren) ~= "table" or #tChildren == 0) and type(aNode.BuildChildren) == "function" then
			aNode.children = {}
			pcall(function() aNode:BuildChildren(aNode) end)
			tChildren = aNode.children
		end
		if type(tChildren) ~= "table" then return end

		for x = 1, #tChildren do
			if tVisited >= SETTINGS_SEARCH_MAXVISIT then break end
			local tChild = tChildren[x]
			-- never index the search field itself
			if type(tChild) == "table" and not tChild.isSettingsSearch and type(tChild.name) == "string" then
				tVisited = tVisited + 1

				local tChildPath = {}
				for i = 1, #aPath do tChildPath[i] = aPath[i] end
				tChildPath[#tChildPath + 1] = tChild.name

				if SettingsSearchMatch(tChild.name, tQueryLower) then
					tResults[#tResults + 1] = { name = table.concat(tChildPath, " > "), path = tChildPath }
				end

				-- recurse into containers only; isSelect nodes are value pickers
				-- (On/Off, enum, range) whose children are the values, not settings.
				if aDepth < SETTINGS_SEARCH_MAXDEPTH and tChild.isSelect ~= true then
					tWalk(tChild, tChildPath, aDepth + 1)
				end
			end
		end
	end

	-- Some settings BuildChildren closures read/adjust the global cursor; the walk
	-- runs them on a scratch tree, so snapshot and restore the live cursor around it.
	local tSavedCursor = SkuOptions.currentMenuPosition
	tWalk(tScratchRoot, {}, 0)
	SkuOptions.currentMenuPosition = tSavedCursor
	dprint("SettingsSearchCollect", aQuery, "visited", tVisited, "matches", #tResults)
	return tResults
end

-- Re-descend the LIVE Einstellungen tree to aPath and open the target, mirroring
-- SkuOptions:SlashFunc's path walk (build children per level, OnSelect to descend).
-- Leaves the cursor on the opened target; the key handler vocalizes afterwards.
function SkuCore:SettingsSearchGoTo(aNavRoot, aPath)
	if type(aNavRoot) ~= "table" or type(aPath) ~= "table" then return end

	if type(aNavRoot.children) ~= "table" or #aNavRoot.children == 0 then
		if type(aNavRoot.BuildChildren) == "function" then
			pcall(function() aNavRoot:BuildChildren(aNavRoot) end)
		end
	end

	local tMenu = aNavRoot.children
	local tFound = nil
	for x = 1, #aPath do
		if type(tMenu) ~= "table" then tMenu = nil break end
		local tMatched = nil
		for y = 1, #tMenu do
			if aPath[x] == tMenu[y].name then
				tMatched = tMenu[y]
				pcall(function() tMatched:OnSelect(true) end)
				tMenu = tMatched.children
				break
			end
		end
		if not tMatched then tFound = nil break end
		tFound = tMatched
	end

	if tFound then
		SkuOptions.currentMenuPosition = tFound
		pcall(function() tFound:OnSelect() end)
	else
		SkuOptions.Voice:OutputStringBTtts(L["No results"], true, true, 0.2, nil, nil, nil, 2)
	end
end

-- Build the match list as children of the search field from its stored query.
-- No matches -> children left empty (caller announces "No results").
function SkuCore:SettingsSearchBuildResults(aSearchEntry)
	aSearchEntry.children = {}
	local tQuery = aSearchEntry.searchQuery
	if not tQuery or tQuery == "" then return end

	local tResults = SkuCore:SettingsSearchCollect(tQuery)
	for x = 1, #tResults do
		local tRes = SkuOptions:InjectMenuItems(aSearchEntry, {tResults[x].name}, SkuGenericMenuItem)
		tRes.searchNavRoot = aSearchEntry.searchNavRoot
		tRes.searchPath = tResults[x].path
		-- ENTER/RIGHT on a result jumps the live menu to the setting and opens it.
		-- (When sorting filters the list, ApplyFilter clones the first result into a
		-- "Filter;<string>" header that inherits this OnSelect; overriding OnSelect
		-- bypasses the stock header guard, so re-apply it here.)
		tRes.OnSelect = function(self, aEnterFlag)
			if self.name and string.find(self.name, L["Filter"]..";") then return end
			SkuCore:SettingsSearchGoTo(self.searchNavRoot, self.searchPath)
		end
	end
end

-- ENTER on the search field: open the text box; on confirm rebuild + descend.
function SkuCore:SettingsSearchPrompt(aSearchEntry)
	PlaySound(88)
	SkuOptions.Voice:OutputStringBTtts(L["Enter text and press ENTER key"], false, true, 0.2)

	SkuOptions:EditBoxShow(aSearchEntry.searchQuery or "", function(self)
		PlaySound(89)
		local tText = strtrim(SkuOptionsEditBoxEditBox:GetText() or "")
		aSearchEntry.searchQuery = (tText ~= "") and tText or nil

		SkuCore:SettingsSearchBuildResults(aSearchEntry)

		-- Descend into the results (or stay put and announce none). Re-pinned on a
		-- short timer because the ENTER that opened the box may still be settling
		-- the menu cursor (same async-editbox gotcha as the mail composer).
		local function tShow()
			if aSearchEntry.children and #aSearchEntry.children > 0 then
				SkuOptions.currentMenuPosition = aSearchEntry.children[1]
				pcall(function() SkuOptions.currentMenuPosition:OnEnter() end)
				SkuOptions:VocalizeCurrentMenuName()
			else
				SkuOptions.currentMenuPosition = aSearchEntry
				pcall(function() aSearchEntry:OnEnter() end)
				SkuOptions.Voice:OutputStringBTtts(L["No results"], true, true, 0.3, nil, nil, nil, 2)
			end
		end
		tShow()
		if C_Timer and C_Timer.After then
			C_Timer.After(0.05, tShow)
		end
	end)
end

-- W7: this is now the "Einstellungen" (Settings) builder, not the old "Core" grab-bag.
-- It collects three groups of leftover Core specs (Kampf / Tastenbelegungen /
-- Sonstiges) plus the aggregated settings sub-menus (Allgemein, Spieleinstellungen,
-- Module). The leftover specs are retargeted into per-group arrays below by editing
-- only their assignment heads; their build closures are unchanged.
function SkuCore:MenuBuilder(aParentEntry)
	--dprint("SkuCore:MenuBuilder", aParentEntry)
	-- tKampf dropped: the Kampf submenu is gone (contents relocated to Monitor,
	-- Schnellmenue and Allgemein).
	local tKeybinds, tSonstiges, tScan = {}, {}, {}

	-- Mail: now a Local window contributor (SkuCore.MailMenuBuilder) -- W7

	-- Action bars: no longer a browsable Sonstiges node -- moved to the hidden,
	-- Shift-F11-only "Aktionsleisten" root entry (SkuCore.ActionBarsMenuBuilder,
	-- spliced by SkuCore:UpdateActionBarsRootEntry).

	-- "Entfernung" (Reichweiten-Checks) relocated from Kampf to the Monitor menu
	-- (SkuCore\aq.lua Aq:MonitorMenuBuilder); same RangecheckMenuBuilder logic.

	tKeybinds[#tKeybinds+1] = { kind = "list", label = L["Spiel Tastenbelegung"],
		build = function(self)
		local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Alles zurücksetzen"]}, SkuGenericMenuItem)
		tNewMenuEntry.BuildChildren = function(self)
			local tNewMenuEntry1 = SkuOptions:InjectMenuItems(self, {L["Wirklich zurücksetzen? (keine weitere Warnung)"]}, SkuGenericMenuItem)
			tNewMenuEntry1.OnAction = function(self, aValue, aName)
				SkuCore:ResetBindings()
				SkuOptions.Voice:OutputStringBTtts(L["Alle Tasten Belegungen wurden auf die Standardeinstellungen zurückgesetzt."], true, true, 0.2)						
			end
			local tNewMenuEntry1 = SkuOptions:InjectMenuItems(self, {L["Oh nein hilfe! Ich bin ein Trottel und will doch nicht zurücksetzen"]}, SkuGenericMenuItem)
		end

		-- Game keybindings: the old "Taste zuweisen" wrapper is folded away (2026-07-03).
		-- The per-category sub-menus (Bewegung, Aktionsleiste, ...) are already a useful
		-- grouping, so they now sit directly under "Spiel Tastenbelegung" -- one pure
		-- navigation level removed. Each category is still its own dynamic sub-menu, so
		-- key displays stay live. Built straight into the list `self` below.
			local tBindings = {}

			local aBindingSet = GetCurrentBindingSet()
			local tNumKeyBindings = GetNumBindings()
			local tCurrentCategory = ""
		
			for x = 1, tNumKeyBindings do
				local tCommand, tCategory, tKey1, tKey2 = GetBinding(x, aBindingSet)
				if tCategory ~= tCurrentCategory then
					tCurrentCategory = tCategory
					if not tCurrentCategory then 
						tCurrentCategory = "ADDONS" 
					end
					tBindings[tCurrentCategory] = {}
				end
				tBindings[tCurrentCategory][tCommand] = {key1 = tKey1, key2 = tKey2, index = x}
			end			

			SkuSettings:Sub("SkuCore").tBindings = tBindings

			for categoryConst, v in pairsByKeys(tBindings) do
			--for categoryConst, v in pairs(tBindings) do
				local tNewMenuEntryCat 
				if _G[categoryConst] then
					tNewMenuEntryCat = SkuOptions:InjectMenuItems(self, {_G[categoryConst]}, SkuGenericMenuItem)
				else
					tNewMenuEntryCat = SkuOptions:InjectMenuItems(self, {categoryConst}, SkuGenericMenuItem)
				end
				tNewMenuEntryCat.dynamic = true
				tNewMenuEntryCat.sorting = true

				tNewMenuEntryCat.BuildChildren = function(self)
					--dprint("categoryConst BuildChildren")
					local tBindings = {}

					local aBindingSet = GetCurrentBindingSet()
					local tNumKeyBindings = GetNumBindings()
					local tCurrentCategory = ""
				
					for x = 1, tNumKeyBindings do
						local tCommand, tCategory, tKey1, tKey2 = GetBinding(x, aBindingSet)
						if tCategory ~= tCurrentCategory then
							tCurrentCategory = tCategory
							if not tCurrentCategory then 
								tCurrentCategory = "ADDONS" 
							end	
							tBindings[tCurrentCategory] = tBindings[tCurrentCategory] or {}
						end
						tBindings[tCurrentCategory][tCommand] = {key1 = tKey1, key2 = tKey2, index = x}
					end	

					--for categoryConst2, v in pairs(tBindings) do
					for categoryConst2, v in pairsByKeys(tBindings) do
						--for commandConst2, v1 in pairs(v) do
						for commandConst2, v1 in pairsByKeys(v) do
							if categoryConst2 == categoryConst then
								if _G["BINDING_NAME_" .. commandConst2] then
									--local tLocKey = gsub(v1.key1, "CTRL", "STRG")
									local tFriendlyKey1, tFriendlyKey2 = v1.key1 or L["nichts"], v1.key2 or L["nichts"]
									for kLocKey, vLocKey in pairs(SkuCore.Keys.LocNames) do
										tFriendlyKey1 = gsub(tFriendlyKey1, kLocKey, vLocKey)
										tFriendlyKey2 = gsub(tFriendlyKey2, kLocKey, vLocKey)
									end
									if tFriendlyKey1 == "-" then
										tFriendlyKey1 = L["Minus"]
									else
										tFriendlyKey1 = gsub(tFriendlyKey1, "%-%-", "-"..L["Minus"])
									end
									if tFriendlyKey2 == "-" then
										tFriendlyKey2 = L["Minus"]
									else
										tFriendlyKey2 = gsub(tFriendlyKey2, "%-%-", "-"..L["Minus"])
									end

									local tNewMenuEntryKey = SkuOptions:InjectMenuItems(self, {_G["BINDING_NAME_" .. commandConst2]..(tAdditionalTotemBarNameParts[commandConst2] or "")..L[" Taste 1: "]..(tFriendlyKey1 or L["nichts"])..L[" Taste 2: "]..(tFriendlyKey2 or L["nichts"])}, SkuGenericMenuItem)
									tNewMenuEntryKey.isSelect = true
									tNewMenuEntryKey.dynamic = true
									tNewMenuEntryKey.OnAction = function(self, aValue, aName)
										KeyBindingKeyMenuEntryHelper(self, aValue, aName)
									end

									tNewMenuEntryKey.command = commandConst2
									tNewMenuEntryKey.category = categoryConst2
									tNewMenuEntryKey.index = v1.index

									tNewMenuEntryKey.BuildChildren = function(self)
										local tNewMenuEntryKeyAction = SkuOptions:InjectMenuItems(self, {L["Neu belegen"]}, SkuGenericMenuItem)
										local tNewMenuEntryKeyAction = SkuOptions:InjectMenuItems(self, {L["Sekundäre Taste neu belegen"]}, SkuGenericMenuItem)
										local tNewMenuEntryKeyAction = SkuOptions:InjectMenuItems(self, {L["Belegung löschen"]}, SkuGenericMenuItem)
										local tNewMenuEntryKeyAction = SkuOptions:InjectMenuItems(self, {L["Sekundäre Belegung löschen"]}, SkuGenericMenuItem)
									end										
								end
							end
						end
					end
				end
			end
	end }

	tKeybinds[#tKeybinds+1] = { kind = "list", label = L["Sku Tastenbelegung"],
		build = function(self)
		local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Alles zurücksetzen"]}, SkuGenericMenuItem)
		tNewMenuEntry.BuildChildren = function(self)
			local tNewMenuEntry1 = SkuOptions:InjectMenuItems(self, {L["Wirklich zurücksetzen? (keine weitere Warnung)"]}, SkuGenericMenuItem)
			tNewMenuEntry1.OnAction = function(self, aValue, aName)
				SkuOptions:SkuKeyBindsResetBindings()
				SkuOptions.Voice:OutputStringBTtts(L["Alle Tasten Belegungen wurden auf die Standardeinstellungen zurückgesetzt."], true, true, 0.2)						
			end
			local tNewMenuEntry1 = SkuOptions:InjectMenuItems(self, {L["Oh nein hilfe! Ich bin ein Trottel und will doch nicht zurücksetzen"]}, SkuGenericMenuItem)
		end

		-- Helper: render one key-binding entry under aParent (name shows current keys;
		-- descend to rebind/clear primary+secondary). Extracted from the old flat
		-- "Taste zuweisen" loop so entries can live at the top level of "Sku
		-- Tastenbelegung" OR inside one of the group sub-menus built further below.
		local function AddKeyBindEntry(aParent, tBindingConst)
				local v = SkuOptions.db.profile["SkuOptions"].SkuKeyBinds[tBindingConst]
				if not v then return end
				local tFriendlyKey1
				if v.key == "" then
					tFriendlyKey1 = L["nichts"]
				else
					tFriendlyKey1 = v.key or L["nichts"]
				end
				local tFriendlyKey2
				if not v.key2 or v.key2 == "" then
					tFriendlyKey2 = L["nichts"]
				else
					tFriendlyKey2 = v.key2 or L["nichts"]
				end
				for kLocKey, vLocKey in pairs(SkuCore.Keys.LocNames) do
					tFriendlyKey1 = gsub(tFriendlyKey1, kLocKey, vLocKey)
					tFriendlyKey2 = gsub(tFriendlyKey2, kLocKey, vLocKey)
				end
				if tFriendlyKey1 == "-" then
					tFriendlyKey1 = L["Minus"]
				else
					tFriendlyKey1 = gsub(tFriendlyKey1, "%-%-", "-"..L["Minus"])
				end
				if tFriendlyKey2 == "-" then
					tFriendlyKey2 = L["Minus"]
				else
					tFriendlyKey2 = gsub(tFriendlyKey2, "%-%-", "-"..L["Minus"])
				end

				local tNewMenuEntryKey = SkuOptions:InjectMenuItems(aParent, {L[tBindingConst]..L[" Taste 1: "]..(tFriendlyKey1 or L["nichts"])..L[" Taste 2: "]..(tFriendlyKey2 or L["nichts"])}, SkuGenericMenuItem)
				tNewMenuEntryKey.isSelect = true
				tNewMenuEntryKey.dynamic = true
				tNewMenuEntryKey.OnAction = function(self, aValue, aName)
					dprint("Taste zuweisen OnAction", aValue, aName, self.name)
					if aName == L["fixed"] then
						return
					end
					if aName == L["Neu belegen"] then
						tRebindCaptureKeyBind(self, false)
					elseif aName == L["Sekundäre Taste neu belegen"] then
						tRebindCaptureKeyBind(self, true)
					elseif aName == L["Belegung löschen"] then
						if not self.bindingConst then return end
						SkuOptions:SkuKeyBindsDeleteBinding(self.bindingConst)
						local tKey1 = SkuOptions:SkuKeyBindsGetBinding(self.bindingConst)
						local tKey2 = SkuOptions:SkuKeyBindsGetBinding2(self.bindingConst)
						local tFriendlyKey1 = (tKey1 ~= "" and tKey1) or L["nichts"]
						local tFriendlyKey2 = (tKey2 ~= "" and tKey2) or L["nichts"]
						self.name = L[self.bindingConst]..L[" Taste 1: "]..(tFriendlyKey1 or L["nichts"])..L[" Taste 2: "]..(tFriendlyKey2 or L["nichts"])
						_G["OnSkuOptionsMainOption1"]:GetScript("OnClick")(_G["OnSkuOptionsMainOption1"], "RIGHT")
						_G["OnSkuOptionsMainOption1"]:GetScript("OnClick")(_G["OnSkuOptionsMainOption1"], "LEFT")
						SkuOptions.Voice:OutputStringBTtts(L["Belegung gelöscht"], true, true, 0.2)
					elseif aName == L["Sekundäre Belegung löschen"] then
						if not self.bindingConst then return end
						SkuOptions:SkuKeyBindsDeleteBinding2(self.bindingConst)
						local tKey1 = SkuOptions:SkuKeyBindsGetBinding(self.bindingConst)
						local tKey2 = SkuOptions:SkuKeyBindsGetBinding2(self.bindingConst)
						local tFriendlyKey1 = (tKey1 ~= "" and tKey1) or L["nichts"]
						local tFriendlyKey2 = (tKey2 ~= "" and tKey2) or L["nichts"]
						self.name = L[self.bindingConst]..L[" Taste 1: "]..(tFriendlyKey1 or L["nichts"])..L[" Taste 2: "]..(tFriendlyKey2 or L["nichts"])
						_G["OnSkuOptionsMainOption1"]:GetScript("OnClick")(_G["OnSkuOptionsMainOption1"], "RIGHT")
						_G["OnSkuOptionsMainOption1"]:GetScript("OnClick")(_G["OnSkuOptionsMainOption1"], "LEFT")
						SkuOptions.Voice:OutputStringBTtts(L["Sekundäre Belegung gelöscht"], true, true, 0.2)
					end
				end
				tNewMenuEntryKey.bindingConst = tBindingConst

				tNewMenuEntryKey.BuildChildren = function(self)
					local tNewMenuEntryKeyAction = SkuOptions:InjectMenuItems(self, {L["Neu belegen"]}, SkuGenericMenuItem)
					local tNewMenuEntryKeyAction = SkuOptions:InjectMenuItems(self, {L["Sekundäre Taste neu belegen"]}, SkuGenericMenuItem)
					local tNewMenuEntryKeyAction = SkuOptions:InjectMenuItems(self, {L["Belegung löschen"]}, SkuGenericMenuItem)
					local tNewMenuEntryKeyAction = SkuOptions:InjectMenuItems(self, {L["Sekundäre Belegung löschen"]}, SkuGenericMenuItem)
				end
		end

		-- Regrouped 2026-07-03: the old "Taste zuweisen" wrapper is gone -- its key
		-- entries now sit directly under "Sku Tastenbelegung". Numbered series (Scan,
		-- audio quick-access, quick waypoints, focus, target markers, turn-to-unit) and
		-- large thematic clusters (combat menu, targeting, navigation, monitor, rolling)
		-- each get their own sub-menu; everything else stays loose at this level.
		--drop outdated bindings once (was inside the old flat BuildChildren)
		for i, v in pairs(SkuOptions.db.profile["SkuOptions"].SkuKeyBinds) do
			if not SkuOptions.skuDefaultKeyBindings[i] then
				SkuOptions.db.profile["SkuOptions"].SkuKeyBinds[i] = nil
			end
		end

		local tKeyBindGroups = {
			{ label = L["Scan Tasten"], members = {
				"SKU_KEY_SCANCONTINUE", "SKU_KEY_SCAN1", "SKU_KEY_SCAN2", "SKU_KEY_SCAN3", "SKU_KEY_SCAN4",
				"SKU_KEY_SCAN5", "SKU_KEY_SCAN6", "SKU_KEY_SCAN7", "SKU_KEY_SCAN8",
				"SKU_KEY_MMSCANWIDE", "SKU_KEY_MMSCANNARROW", "SKU_KEY_NOTIFYONRESOURCES", }, },
			{ label = L["Audio Menü Schnellzugriff"], members = {
				"SKU_KEY_MENUQUICK1", "SKU_KEY_MENUQUICK1SET", "SKU_KEY_MENUQUICK2", "SKU_KEY_MENUQUICK2SET",
				"SKU_KEY_MENUQUICK3", "SKU_KEY_MENUQUICK3SET", "SKU_KEY_MENUQUICK4", "SKU_KEY_MENUQUICK4SET",
				"SKU_KEY_MENUQUICK5", "SKU_KEY_MENUQUICK5SET", "SKU_KEY_MENUQUICK6", "SKU_KEY_MENUQUICK6SET",
				"SKU_KEY_MENUQUICK7", "SKU_KEY_MENUQUICK7SET", "SKU_KEY_MENUQUICK8", "SKU_KEY_MENUQUICK8SET",
				"SKU_KEY_MENUQUICK9", "SKU_KEY_MENUQUICK9SET", "SKU_KEY_MENUQUICK10", "SKU_KEY_MENUQUICK10SET", }, },
			{ label = L["Schnellwegpunkte"], members = {
				"SKU_KEY_QUICKWP1", "SKU_KEY_QUICKWP1SET", "SKU_KEY_QUICKWP2", "SKU_KEY_QUICKWP2SET",
				"SKU_KEY_QUICKWP3", "SKU_KEY_QUICKWP3SET", "SKU_KEY_QUICKWP4", "SKU_KEY_QUICKWP4SET", }, },
			{ label = L["Fokus Tasten"], members = {
				"SKU_KEY_FOCUSGET1", "SKU_KEY_FOCUSSET1", "SKU_KEY_FOCUSGET2", "SKU_KEY_FOCUSSET2",
				"SKU_KEY_FOCUSGET3", "SKU_KEY_FOCUSSET3", "SKU_KEY_FOCUSGET4", "SKU_KEY_FOCUSSET4",
				"SKU_KEY_FOCUSGET5", "SKU_KEY_FOCUSSET5", "SKU_KEY_FOCUSGET6", "SKU_KEY_FOCUSSET6",
				"SKU_KEY_FOCUSGET7", "SKU_KEY_FOCUSSET7", "SKU_KEY_FOCUSGET8", "SKU_KEY_FOCUSSET8", }, },
			{ label = L["Ziel Markierungen"], members = {
				"SKU_KEY_SKUMARKERSET1WHITE", "SKU_KEY_SKUMARKERSET2RED", "SKU_KEY_SKUMARKERSET3BLUE",
				"SKU_KEY_SKUMARKERSET4GREEN", "SKU_KEY_SKUMARKERSET5PURPLE", "SKU_KEY_SKUMARKERSET6YELLOW",
				"SKU_KEY_SKUMARKERSET7ORANGE", "SKU_KEY_SKUMARKERSET8GREY", "SKU_KEY_SKUMARKERCLEARALL", }, },
			{ label = L["Zu Einheit und Drehen"], members = {
				"SKU_KEY_TURNTOUNIT1", "SKU_KEY_TURNTOUNIT2", "SKU_KEY_TURNTOUNIT3", "SKU_KEY_TURNTOUNIT4",
				"SKU_KEY_TURNTOUNIT5", "SKU_KEY_TURNTOUNIT6", "SKU_KEY_TURNTOUNITTURN180", "SKU_KEY_TURNTOBEACON", }, },
			{ label = L["Kampfmenü Steuerung"], members = {
				"SKU_KEY_COMBATMENU_UP", "SKU_KEY_COMBATMENU_DOWN", "SKU_KEY_COMBATMENU_LEFT", "SKU_KEY_COMBATMENU_RIGHT",
				-- SKU_KEY_COMBATMENU_USE is retired: it defaulted to ENTER and bound the
				-- LEFT click key to the secure use button, colliding with
				-- SKU_KEY_MENURIGHTCLICK ("Menü Klick Tasten" below). Both click keys are
				-- configured there now and apply in and out of combat alike.
				"SKU_KEY_COMBATMENU_HOME", "SKU_KEY_COMBATMENU_END", "SKU_KEY_COMBATMENU_BACK",
				"SKU_KEY_COMBATMENU_CLOSE", }, },
			{ label = L["Menü Klick Tasten"], members = {
				"SKU_KEY_MENULEFTCLICK", "SKU_KEY_MENURIGHTCLICK", }, },
			{ label = L["Ziel und Soft Targeting"], members = {
				"SKU_KEY_TARGETDISTANCE", "SKU_KEY_TARGETHEALTH", "SKU_KEY_OUTPUTHARDTARGET", "SKU_KEY_OUTPUTSOFTTARGET",
				"SKU_KEY_ENABLESOFTTARGETINGENEMY", "SKU_KEY_ENABLESOFTTARGETINGFRIENDLY", "SKU_KEY_ENABLESOFTTARGETINGINTERACT", }, },
			{ label = L["Navigation und Wegpunkte"], members = {
				"SKU_KEY_SELECTNEXTBASEWAYPOINT", "SKU_KEY_MOVETONEXTWP", "SKU_KEY_MOVETOPREVWP", "SKU_KEY_ADDLARGEWP",
				"SKU_KEY_ADDSMALLWP", "SKU_KEY_STARTRRFOLLOW", "SKU_KEY_STOPROUTEORWAYPOINT", "SKU_KEY_TOGGLEREACHRANGE",
				"SKU_KEY_TOGGLEMMSIZE", "SKU_KEY_TAXICANCEL", }, },
			{ label = L["Monitor und Kampf"], members = {
				"SKU_KEY_ENABLEPARTYRAIDHEALTHMONITOR", "SKU_KEY_DOMONITORPARTYHEALTH2CONTI", "SKU_KEY_GROUPMEMBERSRANGECHECK",
				"SKU_KEY_COMBATMONSETFOLLOWTARGET", "SKU_KEY_COMBATMONOUTPUTNUMBERINCOMBAT", "SKU_KEY_NEXTCOMBATENEMY", }, },
			{ label = L["Würfeln"], members = {
				"SKU_KEY_ROLLNEED", "SKU_KEY_ROLLGREED", "SKU_KEY_ROLLPASS", "SKU_KEY_ROLLINFO",
				"SKU_KEY_QUESTSHARE", }, },
		}

		local tGrouped = {}
		for _, tGroup in ipairs(tKeyBindGroups) do
			for _, tConst in ipairs(tGroup.members) do
				tGrouped[tConst] = true
			end
		end

		--one dynamic, type-ahead sub-menu per group (mirrors the old flat list's flags)
		for _, tGroup in ipairs(tKeyBindGroups) do
			local tGroupMembers = tGroup.members
			local tGroupEntry = SkuOptions:InjectMenuItems(self, {tGroup.label}, SkuGenericMenuItem)
			tGroupEntry.dynamic = true
			tGroupEntry.sorting = true
			tGroupEntry.BuildChildren = function(self)
				for _, tConst in ipairs(tGroupMembers) do
					AddKeyBindEntry(self, tConst)
				end
			end
		end

		--loose entries: everything not in a group, alphabetically by localized name
		local tLooseSorted = {}
		for k, v in SkuSpairs(SkuOptions.db.profile["SkuOptions"].SkuKeyBinds, function(t,a,b)
			return L[b] > L[a] end) do
			if not tGrouped[k] then
				tLooseSorted[#tLooseSorted+1] = k
			end
		end
		for _, tBindingConst in ipairs(tLooseSorted) do
			AddKeyBindEntry(self, tBindingConst)
		end
	end }

	tScan[#tScan+1] = { kind = "list", label = L["Scan settings"],
		build = function(self)
		for x = 1, 8 do
			local tText = SkuCore.ScanTypes[SkuSettings:Sub("SkuCore", nil, "char").scanConfigs[x].type].name
			for iDb, vDb in pairs(SkuSettings:Sub("SkuCore", nil, "char").scanConfigs[x].objects) do
				tText = tText..", "..L[SkuCore.ScanObjects[vDb]]
			end

			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["SKU_KEY_SCAN"..x].." "..tText}, SkuGenericMenuItem)
			tNewMenuEntry.isSelect = true
			tNewMenuEntry.dynamic = true
			tNewMenuEntry.scanNumber = nil
			tNewMenuEntry.tAction = nil
			tNewMenuEntry.OnAction = function(self, aValue, aName)
				--print(L["SKU_KEY_SCAN"..x].." OnAction", aValue, aName, self.name, self.tAction)
				if aName == L["Empty"] then
					return
				end
				if self.tAction == "type" then
					for i, v in pairs(SkuCore.ScanTypes) do
						if v.name == aName then
							SkuSettings:Sub("SkuCore", nil, "char").scanConfigs[x].type = i
							self:OnUpdate(self)
							return
						end
					end
				elseif self.tAction == "add" then
					for i, v in pairs(SkuCore.ScanObjects) do
						if aName == L[v] then
							local tFound = false
							for iDb, vDb in pairs(SkuSettings:Sub("SkuCore", nil, "char").scanConfigs[x].objects) do
								if i == vDb then
									tFound = true
								end
							end
							if tFound == false then
								table.insert(SkuSettings:Sub("SkuCore", nil, "char").scanConfigs[x].objects, i)
								self:OnUpdate(self)
								return
							end
						end
					end

				elseif self.tAction == "remove" then
					for i, v in pairs(SkuCore.ScanObjects) do
						if aName == L[v] then
							for iDb, vDb in pairs(SkuSettings:Sub("SkuCore", nil, "char").scanConfigs[x].objects) do
								if i == vDb then
									table.remove(SkuSettings:Sub("SkuCore", nil, "char").scanConfigs[x].objects, iDb)
									self:OnUpdate(self)
									return
								end
							end
						end
					end

				end
			end
			tNewMenuEntry.OnEnter = function(self, aValue, aName)
				self.tAction = nil
			end

			tNewMenuEntry.BuildChildren = function(self)
				local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["type"]}, SkuGenericMenuItem)
				tNewMenuEntry.dynamic = true
				tNewMenuEntry.BuildChildren = function(self)
					for y = 1, #SkuCore.ScanTypes  do
						local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {SkuCore.ScanTypes[y].name}, SkuGenericMenuItem)
						tNewMenuEntry.OnEnter = function(self, aValue, aName)
							SkuOptions.currentMenuPosition.textFirstLine, SkuOptions.currentMenuPosition.textFull = SkuCore.ScanTypes[y].name, SkuCore.ScanTypes[y].desc
							self.selectTarget.tAction = "type"
							self.selectTarget.scanNumber = y
						end
					end
				end

				local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["add object"]}, SkuGenericMenuItem)
				tNewMenuEntry.dynamic = true
				tNewMenuEntry.BuildChildren = function(self)
					local tEmpty = true
					for i, v in pairs(SkuCore.ScanObjects) do
						local tFound = false
						for iDb, vDb in pairs(SkuSettings:Sub("SkuCore", nil, "char").scanConfigs[x].objects) do
							if i == vDb then
								tFound = true
							end
						end
						if tFound == false then
							tEmpty = false
							local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L[v]}, SkuGenericMenuItem)
							tNewMenuEntry.OnEnter = function(self, aValue, aName)
								SkuOptions.currentMenuPosition.textFirstLine, SkuOptions.currentMenuPosition.textFull = "", ""
								self.selectTarget.tAction = "add"
							end
						end
					end
					if tEmpty == true then
						local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Empty"]}, SkuGenericMenuItem)
					end
				end
				local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["remove object"]}, SkuGenericMenuItem)
				tNewMenuEntry.dynamic = true
				tNewMenuEntry.BuildChildren = function(self)
					local tEmpty = true
					for i, v in pairs(SkuCore.ScanObjects) do
						local tFound = false
						for iDb, vDb in pairs(SkuSettings:Sub("SkuCore", nil, "char").scanConfigs[x].objects) do
							if i == vDb then
								tFound = true
							end
						end
						if tFound == true then
							tEmpty = false
							local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L[v]}, SkuGenericMenuItem)
							tNewMenuEntry.OnEnter = function(self, aValue, aName)
								SkuOptions.currentMenuPosition.textFirstLine, SkuOptions.currentMenuPosition.textFull = "", ""
								self.selectTarget.tAction = "remove"
							end
						end
					end
					if tEmpty == true then
						local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Empty"]}, SkuGenericMenuItem)
					end

				end
			end
		end

	end }


	-- Auktionshaus: now a Local window contributor (AuctionHouseMenuBuilder) -- W7
	-- Monitor: promoted to a top-level entry (SkuMenu "Monitor") -- W7

	-- DIAL-TARGETING (41.02.06e): relocated to the Schnellmenue root entry
	-- (SkuZOptions\Core.lua, [42.14]; formerly the "Werkzeuge" menu). Entfernbar: Block
	-- dort löschen + DialTargeting.lua + TOC + Core.lua Init

	-- Social: now a Local window contributor (FriendsMenuBuilder) -- W7
	-- Damage Meter + Atlas Loot: moved into the top-level "Addons" menu
	-- (SkuCore:AddonsMenuBuilder) -- W7
	-- Macros: promoted to a top-level entry (SkuMenu "Macros") -- W7


	--[[
	if Sku.IsEraSoD == true then
		local tNewMenuParentEntry =  SkuOptions:InjectMenuItems(aParentEntry, {L["Runes"]}, SkuGenericMenuItem)
		tNewMenuParentEntry.dynamic = true
		tNewMenuParentEntry.sorting = true
		tNewMenuParentEntry.BuildChildren = SkuCore.EngravingFrameMenuBuilder
	end
	]]


	-- W7: the SkuCore options no longer get their own "Optionen" wrapper under
	-- Sonstiges — they are rendered directly into Sonstiges in the build below.

	-- W8: SkuQuest's settings moved again, out of Sonstiges to a top-level
	-- Einstellungen entry (the "Quest" spec in tSpecs below); same args/db.

	-- W7: SkuMob's settings ("Ziel Optionen") were under Kampf; now relocated to the
	-- Monitor menu (SkuCore\aq.lua Aq:MonitorMenuBuilder). Same args/db -> saved values preserved.

	-- W7: top-level Einstellungen layout. Allgemein reuses the old "Optionen" menu
	-- (SkuOptions:MenuBuilder); Spieleinstellungen reuses the Game Options builder;
	-- Module reuses the per-feature on/off list (the old "Funktionen an/aus"). Kampf /
	-- Tastenbelegungen / Sonstiges are the regrouped Core leftovers from above.
	local function tDeEn(de, en) return function() return (GetLocale and GetLocale() == "deDE") and de or en end end

	-- W7: relocated AceConfig entries are rendered via IterateOptionsArgs with
	-- aIncludeHidden=true and their ORIGINAL keyPrefix, so their saved values are
	-- preserved (they only moved menu category, not storage). Each source entry is
	-- flagged forAudioMenu=false so it does NOT also appear in its old place.
	local tSub = SkuSettings:Sub("SkuCore")
	local tSpecs = {
		{ kind = "submenu", label = tDeEn("Allgemein", "General"),
			build = function(self)
				SkuOptions:MenuBuilder(self)
				-- [42.14] "Sku Menue im Kampf": the Kampf submenu held nothing else, so
				-- the toggle moved up into Allgemein and Kampf is gone. Same builder and
				-- same combatMenuOpen setting -> saved value intact.
				if SkuCore.aqCombat and SkuCore.aqCombat.CombatMenuOpenMenuBuilder then
					SkuCore.aqCombat.CombatMenuOpenMenuBuilder(self)
				end
			end },
		{ kind = "submenu", label = tDeEn("Spieleinstellungen", "Game options"),
			build = function(self) if SkuCore.GameOptions and SkuCore.GameOptions.GameOptionsMenuBuilder then SkuCore.GameOptions:GameOptionsMenuBuilder(self) end end },
		-- W8: Audio bundles the sound-related SkuOptions nodes relocated out of
		-- Allgemein (forAudioMenu=false there; ORIGINAL nodes + keyPrefix "" via
		-- aIncludeHidden=true, so saved values and behavior are unchanged).
		{ kind = "submenu", label = "Audio",
			build = function(self)
				local a = SkuOptions.options and SkuOptions.options.args
				if a then
					-- backgroundSound (Hintergrund Audio) selection removed: feature no
					-- longer offered in the Audio menu.
					-- Existing (more important) entry first: the Audio-Kanaele group.
					SkuOptions:IterateOptionsArgs({
						soundChannels = a.soundChannels,
					}, self, SkuSettings:Sub("SkuOptions"), "SkuOptions", "", true)
				end
				-- W8: "NPC Begrüßungen abspielen" (SkuCore node), relocated from
				-- Sonstiges; same db/keyPrefix -> saved value intact.
				if SkuCore.options and SkuCore.options.args and SkuCore.options.args.playNPCGreetings then
					SkuOptions:IterateOptionsArgs({ playNPCGreetings = SkuCore.options.args.playNPCGreetings }, self, tSub, "SkuCore", "", true)
				end
				-- Soundeinstellungen flattened: instead of an extra "Sound Settings" submenu,
				-- its toggles render DIRECTLY into the Audio menu, placed BELOW the existing
				-- (more important) entries above. Same db/keyPrefix (soundSettings.<key> under
				-- SkuOptions) -> saved values preserved.
				if a and a.soundSettings and a.soundSettings.args then
					SkuOptions:IterateOptionsArgs(a.soundSettings.args, self, SkuSettings:Sub("SkuOptions").soundSettings, "SkuOptions", "soundSettings.", true)
				end
			end },
		-- W8: Kamera, relocated from the Barrierefreiheit root menu (7.3); the
		-- builder moved 1:1 to file scope in SkuZOptions/Core.lua.
		{ kind = "submenu", label = function() return Sku.L["CAM_MenuTitle"] end,
			build = function(self)
				if SkuOptions.CameraMenuBuilder then SkuOptions.CameraMenuBuilder(self) end
			end },
		-- W8: Visuelle Hilfen, relocated from the Barrierefreiheit root menu.
		{ kind = "submenu", label = function() return Sku.L["Visuelle Hilfen"] end,
			build = function(self)
				if SkuCore.VisualAids and SkuCore.VisualAids.VisualAidsBuildMenu then
					pcall(function() SkuCore.VisualAids:VisualAidsBuildMenu(self) end)
				end
			end },
		-- [42.14] "Kampf" (Combat) is gone again: its contents stay relocated
		-- (Entfernung and Ziel Optionen in the Monitor menu, Dial/Soft Targeting in the
		-- Schnellmenue) and its last entry, the "Sku Menü im Kampf" toggle, moved up
		-- into Allgemein above.
		{ kind = "submenu", label = tDeEn("Scan", "Scan"),
			build = function(self)
				-- Scan-related settings relocated from the SkuCore "Options" group.
				local tScanArgs = {
					scanBackgroundSound = SkuCore.options.args.scanBackgroundSound,
					ressourceScanning   = SkuCore.options.args.ressourceScanning,
					doNotHideTooltip    = SkuCore.options.args.doNotHideTooltip,
					turnToUnit          = SkuCore.options.args.turnToUnit,
				}
				SkuOptions:IterateOptionsArgs(tScanArgs, self, tSub, "SkuCore", "", true)
				SkuMenu:Build(self, tScan)
			end },
		-- W8: Quest (SkuQuest settings), promoted from Sonstiges to an own
		-- top-level Einstellungen entry; same args/db -> saved values preserved.
		{ kind = "submenu", label = "Quest", sorting = true,
			build = function(self)
				if SkuQuest and SkuQuest.options and SkuQuest.options.args then
					SkuOptions:IterateOptionsArgs(SkuQuest.options.args, self, SkuSettings:Sub("SkuQuest"), "SkuQuest")
				end
			end },
		-- Navigation settings, relocated here from the Nav menu's "Optionen". Only
		-- the NON-beacon nav settings render here; the beacon settings (volume, click
		-- on beacon, sound sets) live under Monitor -> Beacon. Same args/db (SkuNav)
		-- via IterateOptionsArgs -> saved values are unchanged.
		{ kind = "submenu", label = L["SkuNavMenuEntry"], sorting = true,
			build = function(self)
				if SkuNav and SkuNav.options and SkuNav.options.args then
					local a = SkuNav.options.args
					SkuOptions:IterateOptionsArgs({
						vocalizeFullDirectionDistance      = a.vocalizeFullDirectionDistance,
						vocalizeZoneNames                  = a.vocalizeZoneNames,
						nearbyWpRange                      = a.nearbyWpRange,
						standardWpReachedRange             = a.standardWpReachedRange,
						autoGlobalDirection                = a.autoGlobalDirection,
						showGlobalDirectionInWaypointLists = a.showGlobalDirectionInWaypointLists,
						trackVisited                       = a.trackVisited,
						timeForVisitedToExpire             = a.timeForVisitedToExpire,
						showGatherWaypoints                = a.showGatherWaypoints,
						showRoutesOnMinimap                = a.showRoutesOnMinimap,
						showSkuMM                          = a.showSkuMM,
						tomtomWp                           = a.tomtomWp,
						autoNextWaypoint                   = a.autoNextWaypoint,
						outputDistance                     = a.outputDistance,
						routesMaxDistance                  = a.routesMaxDistance,
					}, self, SkuSettings:Sub("SkuNav"), "SkuNav")
				end
			end },
		{ kind = "submenu", label = tDeEn("Tastenbelegungen", "Key bindings"), children = tKeybinds },
		{ kind = "submenu", label = tDeEn("Module", "Modules"),
			build = function(self) if SkuCore.FeaturesMenuBuilder then SkuCore:FeaturesMenuBuilder(self) end end },
		{ kind = "submenu", label = tDeEn("Sprachausgabe", "Speech output"),
			build = function(self)
				-- The non-chat-settings SkuChat options, moved out of the chat menu's
				-- "Optionen" (keyPrefix "" preserved -> saved values intact).
				-- joinSkuChannel deliberately NOT here: it is a chat-channel setting,
				-- and this menu shares its label with the Audio -> Sprachausgabe
				-- shortcut (which shows only the TTS sliders), so it was effectively
				-- unfindable. Back under SkuChat -> Optionen; same keyPrefix "" there,
				-- so the saved value carries over untouched.
				if SkuChat and SkuChat.options and SkuChat.options.args then
					local a = SkuChat.options.args
					local tArgs = {
						WowTtsVoice           = a.WowTtsVoice,
						WowTtsSpeed           = a.WowTtsSpeed,
						WowTtsVolume          = a.WowTtsVolume,
						neverResetQueues      = a.neverResetQueues,
						allChatViaBlizzardTts = a.allChatViaBlizzardTts,
						doNotReadoutEmojis    = a.doNotReadoutEmojis,
					}
					SkuOptions:IterateOptionsArgs(tArgs, self, SkuSettings:Sub("SkuChat"), "SkuChat", "")
				end
				-- W7: "Audio Dauer Pause" (TTSSepPause), moved here from Allgemein
				-- (keyPrefix "" preserved -> saved value intact).
				if SkuOptions.options and SkuOptions.options.args and SkuOptions.options.args.TTSSepPause then
					SkuOptions:IterateOptionsArgs({ TTSSepPause = SkuOptions.options.args.TTSSepPause }, self, SkuSettings:Sub("SkuOptions"), "SkuOptions", "", true)
				end
				-- W8: "Fehlende Audio Wörter kopieren", relocated from Allgemein;
				-- deliberately appended LAST.
				if SkuOptions.MissingAudioWordsMenuEntry then
					SkuOptions:MissingAudioWordsMenuEntry(self)
				end
			end },
		{ kind = "submenu", label = tDeEn("Sonstiges", "Other"),
			build = function(self)
				SkuMenu:Build(self, tSonstiges)
				-- W7: the SkuCore options rendered DIRECTLY into Sonstiges (no "Optionen"
				-- wrapper); forAudioMenu=false entries stay hidden (they live in Scan etc.).
				SkuOptions:IterateOptionsArgs(SkuCore.options.args, self, tSub, "SkuCore")
				-- "Notice on pet starving" no longer renders here: relocated to the
				-- Monitor -> Tier -> Gesundheit menu (aq.lua MonitorMenuBuilder), same
				-- classes.hunter.petHappyness setting.
			end },
	}

	-- Settings search: the FIRST entry in Einstellungen. ENTER opens a text box to
	-- type a query; RIGHT re-opens the last result list. Injected before SkuMenu:Build
	-- so it lands ahead of the categories (which get appended after it). See the
	-- SkuCore:SettingsSearch* helpers above. On the scratch tree used by the search
	-- walk this same entry is added and skipped via its isSettingsSearch flag.
	local tSearchLabel = Sku.deEn("Einstellungen durchsuchen", "Search settings", "Rechercher dans les réglages")
	local tSearchEntry = SkuOptions:InjectMenuItems(aParentEntry, {tSearchLabel}, SkuGenericMenuItem)
	tSearchEntry.isSettingsSearch = true
	tSearchEntry.searchNavRoot = aParentEntry
	-- sorting=true makes the RESULT list (this entry's children) filterable: typing
	-- 2+ letters narrows it via ApplyFilter, like other sorting lists (bags etc.).
	tSearchEntry.sorting = true
	tSearchEntry.OnSelect = function(self, aEnterFlag)
		if aEnterFlag == true then
			SkuCore:SettingsSearchPrompt(self)
		elseif self.children and #self.children > 0 then
			SkuOptions.currentMenuPosition = self.children[1]
			pcall(function() SkuOptions.currentMenuPosition:OnEnter() end)
		end
	end

	SkuMenu:Build(aParentEntry, tSpecs)
end





