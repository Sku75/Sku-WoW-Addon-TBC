local MODULE_NAME = "SkuAdventureGuide"
local L = Sku.L
local slower = string.lower

-- W6-B #6: migrated onto the W1/W2 settings pattern (the last module that had
-- skipped it). Leaf nodes carry no inline get/set — the SkuSettings:Register
-- schema below is the source of truth, and MenuBuilder passes the module name so
-- IterateOptionsArgs auto-manages get/set through SkuSettings (skuManaged).
SkuAdventureGuide.options = {
	name = MODULE_NAME,
	type = "group",
	args = {
		formatEnumsInArticles = {
			order = 1,
			name = L["Bullet lists as numbers"],
			desc = "",
			type = "toggle",
		},
		history = {
			order = 2,
			name = L["Link History"],
			type = "group",
			args = {
				soundOnNewLinkInHistory = {
					order = 1,
					name = L["Sound on new link in history"],
					desc = "",
					type = "select",
					values = SkuAdventureGuide.HistoryNotifySounds,
				},
				ignoreSeenLinks = {
					order = 2,
					name = L["Do not add seen links in history"],
					desc = "",
					type = "toggle",
				},
			},
		},
		links = {
			order = 3,
			name = L["Links"],
			type = "group",
			args = {
				enableLinksInTooltips = {
					order = 1,
					name = L["List links in tooltips"],
					desc = "",
					type = "toggle",
				},
				tooltipLinksIndicator = {
					order = 2,
					name = L["Link indicator in tooltips"],
					desc = "",
					type = "select",
					values = SkuAdventureGuide.tooltipLinksIndicatorValues,
				},
				--[[
				globalLinkListOnly = {
					order = 2,
					name = L["Only global link list in last line"],
					desc = "",
					type = "toggle",
					set = function(info, val)
						SkuOptions.db.profile[MODULE_NAME].links.globalLinkListOnly = val
					end,
					get = function(info)
						return SkuOptions.db.profile[MODULE_NAME].links.globalLinkListOnly
					end,
				},
				]]
			},
		},
	},
}

---------------------------------------------------------------------------------------------------------------------------------------
SkuAdventureGuide.defaults = {
	formatEnumsInArticles = true,
	history = {
		soundOnNewLinkInHistory = "sound-notification15",
		ignoreSeenLinks = true,
	},
	links = {
		enableLinksInTooltips = true,
		tooltipLinksIndicator = "word",
		--globalLinkListOnly = false,
	},
}

-- Flat schema (dotted keys mirror the nested args) — the authoritative
-- scope/default/type for each key. All profile scope (the seenLinksHistory
-- runtime store is global and not a menu setting, so it is not registered here).
SkuSettings:Register(MODULE_NAME, {
	["formatEnumsInArticles"]            = { scope = "profile", type = "boolean", default = true },
	["history.soundOnNewLinkInHistory"]  = { scope = "profile", type = "string",  default = "sound-notification15" },
	["history.ignoreSeenLinks"]          = { scope = "profile", type = "boolean", default = true },
	["links.enableLinksInTooltips"]      = { scope = "profile", type = "boolean", default = true },
	["links.tooltipLinksIndicator"]      = { scope = "profile", type = "string",  default = "word" },
})

--------------------------------------------------------------------------------------------------------------------------------------
function SkuAdventureGuide:MenuBuilder(aParentEntry)
	--dprint("SkuAdventureGuide:MenuBuilderTest", aParentEntry)
	local tNewMenuParentEntryWiki =  SkuOptions:InjectMenuItems(aParentEntry, {L["Wiki"]}, SkuGenericMenuItem)
	tNewMenuParentEntryWiki.dynamic = true
	tNewMenuParentEntryWiki.BuildChildren = function(self)
		local tNewMenuParentEntry =  SkuOptions:InjectMenuItems(tNewMenuParentEntryWiki, {L["Link History"]}, SkuGenericMenuItem)
		tNewMenuParentEntry.dynamic = true
		tNewMenuParentEntry.sorting = true
		tNewMenuParentEntry.BuildChildren = function(self)
			if #SkuAdventureGuide.linkHistory > 0 then
				for x = #SkuAdventureGuide.linkHistory, 1, -1 do
					local tDataLink = SkuDB.Wiki[Sku.Loc].lookup[slower(SkuAdventureGuide.linkHistory[x])]
					if tDataLink then
						if string.len(SkuDB.Wiki[Sku.Loc].data[tDataLink].content) > 0 and SkuDB.Wiki[Sku.Loc].data[tDataLink].content ~= "\r\n" then
							--check if that link actually is redirect and has a valid final target in that case
							local tFinalLink = SkuOptions:GetLinkFinalRedirectTarget(tDataLink)
							if tFinalLink then
								local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {tDataLink}, SkuGenericMenuItem)
								--tNewMenuEntry.dynamic = true
								tNewMenuEntry.sorting = true
								tNewMenuEntry.OnEnter = function(self, aValue, aName)
									SkuOptions.currentMenuPosition.linksHistory = {}
									if tFinalLink ~= tDataLink then
										SkuOptions.currentMenuPosition.textFull = SkuOptions:FormatAndBuildSectionTable(SkuDB.Wiki[Sku.Loc].data[tFinalLink].content, tFinalLink, tDataLink)
									else
										SkuOptions.currentMenuPosition.textFull = SkuOptions:FormatAndBuildSectionTable(SkuDB.Wiki[Sku.Loc].data[tFinalLink].content, tFinalLink)
									end
								end
							end
						end
					end
				end
			else
				local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Empty"]}, SkuGenericMenuItem)
			end
		end

		local tNewMenuParentEntry =  SkuOptions:InjectMenuItems(tNewMenuParentEntryWiki, {L["All entries"]}, SkuGenericMenuItem)
		tNewMenuParentEntry.dynamic = true
		tNewMenuParentEntry.sorting = true
		tNewMenuParentEntry.BuildChildren = function(self)
			for i, v in pairs(SkuDB.Wiki[Sku.Loc].data) do
				if string.len(v.content) > 0 and v.content ~= "\r\n" then
					local tFinalLink = SkuOptions:GetLinkFinalRedirectTarget(i)
					if tFinalLink then
						local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {i}, SkuGenericMenuItem)
						--tNewMenuEntry.dynamic = true
						tNewMenuEntry.sorting = true
						tNewMenuEntry.OnEnter = function(self, aValue, aName)
							SkuOptions.currentMenuPosition.linksHistory = {}
							if tFinalLink ~= i then
								SkuOptions.currentMenuPosition.textFull = SkuOptions:FormatAndBuildSectionTable(SkuDB.Wiki[Sku.Loc].data[tFinalLink].content, tFinalLink, i)
							else
								SkuOptions.currentMenuPosition.textFull = SkuOptions:FormatAndBuildSectionTable(SkuDB.Wiki[Sku.Loc].data[tFinalLink].content, tFinalLink)
							end
						end
					end
				end
			end
		end
	end

	local tNewMenuEntry =  SkuOptions:InjectMenuItems(aParentEntry, {L["Options"]}, SkuGenericMenuItem)
	tNewMenuEntry.sorting = true
	SkuOptions:IterateOptionsArgs(SkuAdventureGuide.options.args, tNewMenuEntry, SkuSettings:Sub(MODULE_NAME), MODULE_NAME)
end
