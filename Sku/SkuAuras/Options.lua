local MODULE_NAME = "SkuAuras"
local L = Sku.L

SkuAuras.options = {
	name = MODULE_NAME,
	type = "group",
	args = {
	},
}

---------------------------------------------------------------------------------------------------------------------------------------
SkuAuras.defaults = {
	enable = true,
}

---------------------------------------------------------------------------------------------------------------------------------------
-- Widget-safe deep copy, consolidated to SkuUtil (W6-B #3).
local TableCopy = SkuUtil.TableCopy

------------------------------------------------------------------------------------------------------------------
local function NoIndexTableGetn(aTable)
	local tCount = 0
	for _, _ in pairs(aTable) do
		tCount = tCount + 1
	end
	return tCount
end

------------------------------------------------------------------------------------------------------------------
local function RemoveTagFromValue(aValue)
   if not aValue then
      return
   end
   -- [v43.0] group tag first, same rule as SkuAuras:RemoveTags in data.lua
   local tCleanValue = string.gsub(aValue, "spellgroup:", "")
   tCleanValue = string.gsub(tCleanValue, "item:", "")
   tCleanValue = string.gsub(tCleanValue, "spell:", "")
   tCleanValue = string.gsub(tCleanValue, "output:", "")
   return tCleanValue
end

---------------------------------------------------------------------------------------------------------------------------------------
local function TableSortByIndex(aTable)
	local tSortedList = {}
	for k, v in SkuSpairs(aTable, 
		function(t, a, b) 
			return string.lower(t[b].friendlyName) > string.lower(t[a].friendlyName)
		end) 
	do
		tSortedList[#tSortedList+1] = k
	end
	return tSortedList
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuAuras:BuildAuraTooltip(aCurrentMenuItem, aAuraName)
	--print("SkuAuras:BuildAuraTooltip(", aCurrentMenuItem, aAuraName)	
	local tMenuItem = aCurrentMenuItem
	local tSections = {}

	local tType = ""
	local tConditions = {}
	local tAction = ""
	local tOutputs = {}
	local tCurrent = {elementType = tMenuItem.elementType, name = tMenuItem.name, internalName = tMenuItem.internalName}

	local tItemsRev = {}

	while tMenuItem.internalName do
		table.insert(tItemsRev, 1, {internalName = tMenuItem.internalName, elementType = tMenuItem.elementType, name = tMenuItem.name})
		tMenuItem = tMenuItem.parent
	end

	local x = 1
	while tItemsRev[x] do
		if tItemsRev[x].elementType == "type" then
			tType = tItemsRev[x].name
			x = x + 1
		elseif tItemsRev[x].elementType == "attribute" and tItemsRev[x].internalName ~= "action" then
			local tCondNo = #tConditions + 1
			tConditions[tCondNo] = {attribute = tItemsRev[x].name}
			x = x + 1
			if not tItemsRev[x] then break end
			tConditions[tCondNo].operator = tItemsRev[x].name
			x = x + 1
			if not tItemsRev[x] then break end
			tConditions[tCondNo].value = tItemsRev[x].name
			x = x + 1
		elseif tItemsRev[x].elementType == "attribute" and tItemsRev[x].internalName == "action" then
			x = x + 2
			if not tItemsRev[x] then tAction = L["nicht festgelegt"] break end
			tAction = tItemsRev[x].name
			x = x + 1
		elseif tItemsRev[x].elementType == "output" then
			tOutputs[#tOutputs + 1] = tItemsRev[x].name
			x = x + 1
		else
			x = x + 1
		end
	end

	if #tOutputs == 0 then
		tOutputs[#tOutputs + 1] = L["nicht festgelegt"]
	end
	if #tConditions == 0 then
		tConditions[#tConditions + 1] = {attribute = L["nicht festgelegt"]}
	end
	if tType == "" then
		tType = L["nicht festgelegt"]
	end
	if tAction == "" then
		tAction = L["nicht festgelegt"]
	end

	if tCurrent.elementType then
		local tText = L["Aktuelles Element: "]..SkuAuras.itemTypes[tCurrent.elementType].friendlyName..L["\r\nAuswählter Wert: "]..tCurrent.name.." "
		if tCurrent.elementType == "type" then
			if SkuAuras.Types[tCurrent.internalName].tooltip then
				tText = tText.."("..SkuAuras.Types[tCurrent.internalName].tooltip..")"
			end
		elseif tCurrent.elementType == "attribute" then
			--print("tCurrent.internalName", tCurrent.internalName)			
			if SkuAuras.attributes[tCurrent.internalName].tooltip then
				tText = tText.."("..SkuAuras.attributes[tCurrent.internalName].tooltip..")"
			end
		elseif tCurrent.elementType == "operator" then
			if SkuAuras.Operators[tCurrent.internalName].tooltip then
				tText = tText.."("..SkuAuras.Operators[tCurrent.internalName].tooltip..")"
			end
		elseif tCurrent.elementType == "value" then
			if SkuAuras.values[tCurrent.internalName] then
				if SkuAuras.values[tCurrent.internalName].tooltip then
					tText = tText.."("..SkuAuras.values[tCurrent.internalName].tooltip..")"
				end
			end
		elseif tCurrent.elementType == "action" then
			if SkuAuras.actions[tCurrent.internalName].tooltip then
				tText = tText.."("..SkuAuras.actions[tCurrent.internalName].tooltip..")"
			end
		elseif tCurrent.elementType == "output" then
			if SkuAuras.outputs[RemoveTagFromValue(tCurrent.internalName)].tooltip then
				tText = tText.."("..SkuAuras.outputs[RemoveTagFromValue(tCurrent.internalName)].tooltip..")"
			end
		end
		table.insert(tSections, tText)
	end


	if aAuraName and SkuSettings:Sub("SkuAuras", nil, "char").Auras[aAuraName] then
		if SkuSettings:Sub("SkuAuras", nil, "char").Auras[aAuraName].type then
			tType = SkuAuras.Types[SkuSettings:Sub("SkuAuras", nil, "char").Auras[aAuraName].type].friendlyName
		end
		tConditions = {}
		for tName, tData in pairs(SkuSettings:Sub("SkuAuras", nil, "char").Auras[aAuraName].attributes) do
			if SkuAuras.attributes[tName] then
				for tDataIndex, tDataData in pairs(tData) do
					local tFname = tDataData[2]
					if  SkuAuras.values[tDataData[2]] then
						tFname = SkuAuras.values[tDataData[2]].friendlyName
					end
					tFname = SkuAuras:RemoveTags(tFname)					
					tConditions[#tConditions + 1] = {attribute = SkuAuras.attributes[tName].friendlyName, operator = SkuAuras.Operators[tDataData[1]].friendlyName, value = tFname}
				end
			end
		end
		tAction = SkuAuras.actions[SkuSettings:Sub("SkuAuras", nil, "char").Auras[aAuraName].actions[1]].friendlyName
		tOutputs = {}
		for tIndex, tData in pairs(SkuSettings:Sub("SkuAuras", nil, "char").Auras[aAuraName].outputs) do
			local tString = string.gsub(SkuAuras.outputs[RemoveTagFromValue(tData)].friendlyName, L["sound"].."#", ";")
			tOutputs[#tOutputs + 1] = tString
		end
		table.insert(tSections, L["Aura Elemente\r\n"])
	else
		table.insert(tSections, L["Bisherige Aura Elemente\r\n"])
	end

	table.insert(tSections, L["Aura Typ: "]..(tType or ""))
	
	local tString = L["Aura Bedingungen:\r\n"]
	for x = 1, #tConditions do
		tString = tString..x..": "..tConditions[x].attribute.." "..(tConditions[x].operator or "").." "..(tConditions[x].value or "").."\r\n"
	end
	table.insert(tSections, tString)

	table.insert(tSections, L["Aura Aktion: "]..(tAction or ""))

	tString = L["Aura Ausgaben:\r\n"]
	for x = 1, #tOutputs do
		tString = tString..x..": "..(tOutputs[x] or "").."\r\n"
	end
	table.insert(tSections, tString)

	SkuOptions.currentMenuPosition.textFull = tSections
end

---------------------------------------------------------------------------------------------------------------------------------------
local function RebuildUsedOutputsHelper(aCurrentMenuItem)
	local tUsed = {}
	local tCurrentItem = aCurrentMenuItem.parent

	tUsed[RemoveTagFromValue(aCurrentMenuItem.internalName)] = true

	while tCurrentItem.parent.parent.internalName ~= "action" do
		tUsed[RemoveTagFromValue(tCurrentItem.internalName)] = true
		tCurrentItem = tCurrentItem.parent
	end

	tUsed[RemoveTagFromValue(tCurrentItem.parent.internalName)] = true

	return tUsed
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuAuras:NewAuraAttributeBuilder(self)
	local tSelectTarget = nil
	if self.isSelect then
		tSelectTarget = self
	elseif self.parent.selectTarget then
		tSelectTarget = self.parent.selectTarget
	elseif self.parent.isSelect then
		tSelectTarget = self.parent
	end
	
	local tBuildChildrenFunc = function(self)
		if not tSelectTarget then
			local tAttributeEntry = SkuOptions:InjectMenuItems(self, {"empty no tSelectTarget"}, SkuGenericMenuItem)
			return
		end

		if self.parent.parent.internalName == "action" and not tSelectTarget.newOrChanged then
			local tSortedList = TableSortByIndex(SkuAuras.outputs)
			for x = 1, #tSortedList do
				local i, v = tSortedList[x], SkuAuras.outputs[tSortedList[x]]
				if not tSelectTarget.usedOutputs[i] then
					tItemCount = true
					local tAttributeEntry = SkuOptions:InjectMenuItems(self, {v.friendlyName}, SkuGenericMenuItem)
					tAttributeEntry.internalName = "output:"..i
					tAttributeEntry.dynamic = true
					tAttributeEntry.sorting = true
					tAttributeEntry.actionOnEnter = true
					tAttributeEntry.elementType = "output"
					tAttributeEntry.OnEnter = function(self, aValue, aName)
						tSelectTarget.collectValuesFrom = self
						tSelectTarget.usedOutputs = RebuildUsedOutputsHelper(self)
						self.BuildChildren = SkuAuras:NewAuraOutputBuilder(self)		
						SkuAuras:BuildAuraTooltip(self)
						SkuGenericMenuItem.OnEnter(self, aValue, aName)
					end
					tAttributeEntry.BuildChildren = function(self)
						--dprint("build content of", self.name)
						--dprint("self.internalName", self.internalName)
					end
				end
			end
		
		else
			local tItemCount
			if SkuAuras.Types[tSelectTarget.internalName] then
				local tSortedList = TableSortByIndex(SkuAuras.attributes)
				for x = 1, #tSortedList do
					local i, v = tSortedList[x], tSortedList[x]
					
					local tIsInvalid
					if string.find(i , "skuAura") ~= nil and (self.parent and self.parent.parent and self.parent.parent.parent and self.parent.parent.parent.name) ~= nil and SkuAuras:AuraUsedInOtherAuras(self.parent.parent.parent.name) ~= nil then
						tIsInvalid = true
					else
						if SkuAuras.attributes["skuAura"..i] ~= nil then
							tIsInvalid = true
						else
							if not (self.parent and self.parent.parent and self.parent.parent.parent and self.parent.parent.parent.name) or i ~= "skuAura"..self.parent.parent.parent.name then
								if SkuAuras:AuraHasOtherAuras(string.gsub(i, "skuAura", "")) ~= true then
								else
									tIsInvalid = true
								end
							else
								tIsInvalid = true
							end
						end
					end

					if tIsInvalid ~= true then
						tItemCount = true

						local tAttributeEntry = SkuOptions:InjectMenuItems(self, {SkuAuras.attributes[v].friendlyName}, SkuGenericMenuItem)
						tAttributeEntry.internalName = v
						tAttributeEntry.dynamic = true
						tAttributeEntry.sorting = true
						tAttributeEntry.vocalizeAsIs = true
						tAttributeEntry.elementType = "attribute"
						tAttributeEntry.OnEnter = function(self, aValue, aName)
							self.BuildChildren = SkuAuras:NewAuraOperatorBuilder(self)		
							SkuAuras:BuildAuraTooltip(self)
						end
						tAttributeEntry.BuildChildren = function(self)
							--dprint("build content of", self.name)
							--dprint("self.internalName", self.internalName)
						end
					end
				end

				if not tItemCount then
					self.dynamic = false
				end
			else
				local tAttributeEntry = SkuOptions:InjectMenuItems(self, {"this should not happen - empty not SkuAuras.Types[tSelectTarget.name.internalName]"}, SkuGenericMenuItem)
			end
		end
	end

	return tBuildChildrenFunc
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuAuras:NewAuraOutputBuilder(self)
	local tSelectTarget = nil
	if self.isSelect then
		tSelectTarget = self
	elseif self.parent.selectTarget then
		tSelectTarget = self.parent.selectTarget
	elseif self.parent.isSelect then
		tSelectTarget = self.parent
	end

	local tBuildChildrenFunc = function(self)
		if not tSelectTarget then
			local tAttributeEntry = SkuOptions:InjectMenuItems(self, {"this should not happen - empty no tSelectTarget"}, SkuGenericMenuItem)
			return
		end

		tItemCount = 0

		local tSortedList = TableSortByIndex(SkuAuras.outputs)
		for x = 1, #tSortedList do
			local i, v = tSortedList[x], SkuAuras.outputs[tSortedList[x]]
			if not tSelectTarget.usedOutputs[i] then
				tItemCount = tItemCount + 1
				local tAttributeEntry = SkuOptions:InjectMenuItems(self, {v.friendlyName}, SkuGenericMenuItem)
				tAttributeEntry.internalName = "output:"..i
				tAttributeEntry.dynamic = true
				tAttributeEntry.sorting = true
				tAttributeEntry.actionOnEnter = true
				tAttributeEntry.vocalizeAsIs = true
				tAttributeEntry.elementType = "output"
				tAttributeEntry.OnEnter = function(self, aValue, aName)
					tSelectTarget.collectValuesFrom = self
					tSelectTarget.usedOutputs = RebuildUsedOutputsHelper(self)
					if tItemCount > 0 then
						self.BuildChildren = SkuAuras:NewAuraOutputBuilder(self)		
					end
					if tItemCount == 1 then
						self.dynamic = false
					end
					SkuAuras:BuildAuraTooltip(self)
					SkuGenericMenuItem.OnEnter(self, aValue, aName)
				end
				tAttributeEntry.BuildChildren = function(self)
					--dprint("build content of", self.name)
					--dprint("self.internalName", self.internalName)
				end
			end
		end
	end

	return tBuildChildrenFunc
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuAuras:NewAuraOperatorBuilder(self)
	local tSelectTarget = nil
	if self.isSelect then
		tSelectTarget = self
	elseif self.parent.selectTarget then
		tSelectTarget = self.parent.selectTarget
	elseif self.parent.isSelect then
		tSelectTarget = self.parent
	end
	
	local tBuildChildrenFunc = function(self)
		if not tSelectTarget then
			local tAttributeEntry = SkuOptions:InjectMenuItems(self, {"empty"}, SkuGenericMenuItem)
			return
		end

		if SkuAuras.attributes[self.internalName] and SkuAuras.attributes[self.internalName].updateValues then
			SkuAuras.attributes[self.internalName]:updateValues()
		end

		if self.internalName == "action" then
			local tAttributeEntry = SkuOptions:InjectMenuItems(self, {L["then"]}, SkuGenericMenuItem)
			tAttributeEntry.internalName = "then"
			tAttributeEntry.dynamic = true
			tAttributeEntry.sorting = true
			tAttributeEntry.elementType = "then"
			tAttributeEntry.OnEnter = function(self, aValue, aName)
				self.BuildChildren = SkuAuras:NewAuraValueBuilder(self)
				SkuAuras:BuildAuraTooltip(self)
			end
			tAttributeEntry.BuildChildren = function(self)
				--dprint("build content of", self.name)
			end
		else
			local attrType = SkuAuras.attributes[self.internalName].type or "CATEGORY"
			local operators = SkuAuras.operatorsForAttributeType[attrType]
			local tSortedList = TableSortByIndex(operators)
			for x = 1, #tSortedList do
				local i, v = tSortedList[x], SkuAuras.Operators[tSortedList[x]]
				if i ~= "then" then
					local tAttributeEntry = SkuOptions:InjectMenuItems(self, {v.friendlyName}, SkuGenericMenuItem)
					tAttributeEntry.internalName = i
					tAttributeEntry.dynamic = true
					tAttributeEntry.sorting = true
					tAttributeEntry.vocalizeAsIs = true
					tAttributeEntry.elementType = "operator"
					tAttributeEntry.OnEnter = function(self, aValue, aName)
						self.BuildChildren = SkuAuras:NewAuraValueBuilder(self)
						SkuAuras:BuildAuraTooltip(self)
					end
					tAttributeEntry.BuildChildren = function(self)
						--dprint("build content of", self.name)
					end
				end
			end
		end
	end

	return tBuildChildrenFunc
end

---------------------------------------------------------------------------------------------------------------------------------------
local slower = string.lower
-- [v42.13] Nil-tolerant friendlyName lookup, same idea as the tFn helper in
-- BuildAuraName. SkuAuras.values is populated by the BACKGROUND list build
-- (SkuAuras:StartAttributeValueListsBuild), so a menu opened in the first
-- seconds of a session - or one referencing a key the current data set no longer
-- knows - must degrade to the raw key instead of erroring out of the menu with
-- "attempt to index field '?'".
-- [v43.0] The raw-key fallback goes through RemoveTags now. Values carry a tag
-- ("spellgroup:Frostbolt", "item:1234"), and on a friendlyName miss - a stale
-- key, or a menu opened while the background list build is still running - the
-- old fallback read the tag out loud to the user. Note the degraded path now
-- speaks the ENGLISH group name rather than a localized one; that is the
-- unresolvable case either way, and "Frostbolt" beats "spellgroup:Frostbolt".
--
-- The type guard is load-bearing: SkuAuras:RemoveTags maps the STRINGS "true"
-- and "false" to the booleans, and the binary attributes' values are exactly
-- those two keys. A menu opened before the value lists finish building reaches
-- the fallback for them, and returning a boolean into a string concatenation is
-- how the aura menu would error out instead of merely reading a raw key.
local function tStripTagsForDisplay(aKey)
	local tKey = tostring(aKey)
	local tClean = SkuAuras:RemoveTags(tKey)
	if type(tClean) ~= "string" then
		return tKey
	end
	return tClean
end
local function tFriendlyName(aTbl, aKey)
	local e = aTbl and aTbl[aKey]
	return (e and e.friendlyName) or tStripTagsForDisplay(aKey)
end
local function tValueName(aKey)
	return tFriendlyName(SkuAuras.values, aKey)
end

---------------------------------------------------------------------------------------------------------------------------------------
-- [v43.0] "I know the id but not the name": an input node at index 0 of every
-- spell value list. Injecting it before the loop genuinely puts it first - the
-- menu keeps INSERTION order, and the `sorting` flag selects type-ahead vs
-- filter rather than sorting anything.
--
-- The typed id is RESOLVED to its group and the GROUP value is stored, not the
-- id. The list attributes match against live lists keyed by group name, so a
-- bare "spell:<id>" could never match one of them, and spellName compares names
-- and could not match an id either. spellId is the one attribute where an id is
-- the value - and there it is stored exactly as typed.
local tIdInputAttributes = {
	spellId = "id",
	spellName = "group", spellNameOnCd = "group", spellNameUsable = "group",
	buffListTarget = "group", debuffListTarget = "group",
	buffListPlayer = "group", debuffListPlayer = "group",
}

local function tSpellIdValueFor(aAttributeName, aSpellId)
	local tMode = tIdInputAttributes[aAttributeName]
	if not tMode then
		return nil
	end
	if tMode == "id" then
		local tValue = "spell:"..tostring(aSpellId)
		return SkuAuras.values[tValue] and tValue or nil
	end
	local tGroup = SkuAuras:SpellGroupName(aSpellId, nil)
	if not tGroup then
		return nil
	end
	local tValue = SkuAuras.SPELL_GROUP_TAG..tGroup
	return SkuAuras.values[tValue] and tValue or nil
end

-- ENTER inside a select level always dispatches to the LEVEL'S SELECT TARGET
-- (SkuZOptions/templates.lua OnPostSelect), never to the focused node's own
-- OnAction, so this node cannot own its ENTER. The target's OnAction is wrapped
-- once per target instead and recognises the node by its auraIdInput marker.
local function tPromptForSpellId(aNode, aSelectTarget)
	local tAttributeName = aNode.parent and aNode.parent.parent and aNode.parent.parent.internalName
	SkuOptions.Voice:OutputStringBTtts(L["Zauber-ID eingeben und Enter, oder Escape zum Abbrechen"], false, true, 0.2)
	SkuOptions:EditBoxShow("", function(self)
		local tText = strtrim(SkuOptionsEditBoxEditBox:GetText() or "")
		local tSpellId = tonumber(tText)
		local tValue = tSpellId and tSpellIdValueFor(tAttributeName, tSpellId)
		if not tValue then
			SkuOptions.Voice:OutputStringBTtts(L["Unbekannte Zauber-ID"], false, true, 0.2)
			return
		end
		aNode.internalName = tValue
		aNode.name = tValueName(tValue)
		aNode.auraIdInput = nil
		aSelectTarget.collectValuesFrom = aNode
		if aSelectTarget.usedAttributes and tAttributeName then
			aSelectTarget.usedAttributes[tAttributeName] = true
		end
		if not aSelectTarget.single then
			aNode.BuildChildren = SkuAuras:NewAuraAttributeBuilder(aNode)
		end
		-- The framework parked the cursor on the select target when OnAction
		-- returned (synchronously, long before this callback runs). Put it back
		-- on the node the user just filled in, so the next ENTER commits it.
		SkuOptions.currentMenuPosition = aNode
		SkuOptions.Voice:OutputStringBTtts(L["Wert gesetzt: "]..tostring(aNode.name), false, true, 0.2)
	end)
end

local function tInjectValueIdInput(aLevel, aSelectTarget)
	local tAttributeName = aLevel.parent and aLevel.parent.internalName
	if not (tAttributeName and tIdInputAttributes[tAttributeName]) then
		return
	end
	local tNode = SkuOptions:InjectMenuItems(aLevel, {L["Zauber-ID eingeben"]}, SkuGenericMenuItem)
	tNode.internalName = ""
	tNode.auraIdInput = true
	tNode.elementType = "value"
	tNode.vocalizeAsIs = true
	tNode.sorting = true
	if not aSelectTarget.single then
		tNode.dynamic = true
		tNode.BuildChildren = function(self)
		end
	end
	tNode.OnEnter = function(self, aValue, aName)
		-- Claim the value slot only once an id has actually been typed: while
		-- this is still the prompt its internalName is empty, and the aura
		-- builder walks internalNames upward to assemble the condition.
		if self.auraIdInput ~= true then
			aSelectTarget.collectValuesFrom = self
			aSelectTarget.usedAttributes[self.parent.parent.internalName] = true
			if not aSelectTarget.single then
				self.BuildChildren = SkuAuras:NewAuraAttributeBuilder(self)
			end
		end
		SkuAuras:BuildAuraTooltip(self)
	end
	return tNode
end

function SkuAuras:NewAuraValueBuilder(self)
	local tSelectTarget = nil
	if self.isSelect then
		tSelectTarget = self
	elseif self.parent.parent.selectTarget then
		tSelectTarget = self.parent.parent.selectTarget
	elseif self.parent.parent.isSelect then
		tSelectTarget = self.parent.parent
	end
	
	tSelectTarget.usedOutputs = {}

	-- [v43.0] One wrapper per select target, for the ID-input node's ENTER.
	if tSelectTarget and tSelectTarget.tAuraIdInputHooked ~= true then
		tSelectTarget.tAuraIdInputHooked = true
		local tOriginalOnAction = tSelectTarget.OnAction
		tSelectTarget.OnAction = function(aSelf, aNode, aName, ...)
			if type(aNode) == "table" and aNode.auraIdInput == true then
				tPromptForSpellId(aNode, tSelectTarget)
				return
			end
			if tOriginalOnAction then
				return tOriginalOnAction(aSelf, aNode, aName, ...)
			end
		end
	end

	local tBuildChildrenFunc = function(self)
		if not tSelectTarget then
			local tAttributeValueEntry = SkuOptions:InjectMenuItems(self, {L["empty"]}, SkuGenericMenuItem)
			return
		end

		if SkuAuras.Types[tSelectTarget.internalName] then
			-- [v43.0] index 0: type an id instead of hunting for the name
			tInjectValueIdInput(self, tSelectTarget)
			local tSortedList = {}
			for k, v in SkuSpairs(SkuAuras.attributes[self.parent.internalName].values,
				function(t, a, b)
					-- ORDINAL-Werte (Gesundheit %, Dauer, Combopunkte) numerisch sortieren
					if SkuAuras.attributes[self.parent.internalName] and SkuAuras.attributes[self.parent.internalName].type == "ORDINAL" then
						return (tonumber(t[a]) or 0) < (tonumber(t[b]) or 0)
					end
					if SkuAuras.actions[SkuAuras.attributes[self.parent.internalName].values[b]] then
						return slower(SkuAuras.actions[SkuAuras.attributes[self.parent.internalName].values[b]].friendlyName) > slower(SkuAuras.actions[SkuAuras.attributes[self.parent.internalName].values[a]].friendlyName)
					else
						return slower(tValueName(SkuAuras.attributes[self.parent.internalName].values[b])) > slower(tValueName(SkuAuras.attributes[self.parent.internalName].values[a]))
					end
				end)
			do
				tSortedList[#tSortedList+1] = v
			end

			--for i, v in pairs(SkuAuras.attributes[self.parent.internalName].values) do
			for x = 1, #tSortedList do
				local i, v = tSortedList[x], tSortedList[x]
				local tAttributeValueEntryName = ""
				if self.internalName == "then" then
					tAttributeValueEntryName = SkuAuras.actions[v].friendlyName
				else
					tAttributeValueEntryName = tValueName(v)
				end
				local tAttributeValueEntry = SkuOptions:InjectMenuItems(self, {tAttributeValueEntryName}, SkuGenericMenuItem)
				tAttributeValueEntry.internalName = v
				if not tSelectTarget.single then
					tAttributeValueEntry.dynamic = true
				end
				tAttributeValueEntry.sorting = true
				--tAttributeValueEntry.actionOnEnter = true
				tAttributeValueEntry.vocalizeAsIs = true
				tAttributeValueEntry.elementType = "value"
				tAttributeValueEntry.OnEnter = function(self, aValue, aName)
					tSelectTarget.collectValuesFrom = self
					tSelectTarget.usedAttributes[self.parent.parent.internalName] = true
					if not tSelectTarget.single then
						self.BuildChildren = SkuAuras:NewAuraAttributeBuilder(self)
					end
					SkuAuras:BuildAuraTooltip(self)
				end
				if not tSelectTarget.single then
					tAttributeValueEntry.BuildChildren = function(self)
						--dprint("build content of", self.name)
					end
				end
			end
		else
			local tAttributeValueEntry = SkuOptions:InjectMenuItems(self, {L["empty"]}, SkuGenericMenuItem)
		end
	end

	return tBuildChildrenFunc
end


---------------------------------------------------------------------------------------------------------------------------------------
function SkuAuras:BuildAuraName(aNewType, aNewAttributes, aNewActions, aNewOutputs)
	--print("BuildAuraName(", aNewType, aNewAttributes, aNewActions, aNewOutputs)
	-- Nil-sicherer Lookup: liefert friendlyName, oder bei unbekanntem/stale
	-- Schluessel den Rohschluessel als Text - so kann der Namensaufbau nicht
	-- mehr abstuerzen ("attempt to index field '?'"), wenn eine gespeicherte
	-- Aura eine nicht mehr aufloesbare Aktion/Wert/Output referenziert.
	-- [v43.0] Same tag-stripping fallback as tFriendlyName above: without it an
	-- unresolvable value would put "spellgroup:Frostbolt" verbatim into the
	-- aura's NAME, and the name is the table key it is stored under.
	local function tFn(aTbl, aKey)
		local e = aTbl and aTbl[aKey]
		return (e and e.friendlyName) or tStripTagsForDisplay(aKey)
	end
	local tAuraName = tFn(SkuAuras.Types, aNewType)..";"
	local tOuterCount = 0
	for tAttributeName, tAttributeValue in pairs(aNewAttributes) do
		if tOuterCount > 0 then
			tAuraName = tAuraName..L["und;"]
		end
		if #tAttributeValue > 1 then
			local tCount = 0
			for tInd, tLocalValue in pairs(tAttributeValue) do
				local tFname = tLocalValue[2]
				if SkuAuras.values[tLocalValue[2]] then
					tFname = SkuAuras.values[tLocalValue[2]].friendlyName
				end
				tFname = SkuAuras:RemoveTags(tFname)

				if tCount > 0 then
					tAuraName = tAuraName..L["oder;"]..tFn(SkuAuras.attributes, tAttributeName)..";"..tFn(SkuAuras.Operators, tLocalValue[1])..";"..tFname..";"
				else
					tAuraName = tAuraName..tFn(SkuAuras.attributes, tAttributeName)..";"..tFn(SkuAuras.Operators, tLocalValue[1])..";"..tFname..";"
				end
				tCount = tCount + 1
			end
		else
			tAuraName = tAuraName..tFn(SkuAuras.attributes, tAttributeName)..";"..tFn(SkuAuras.Operators, tAttributeValue[1][1])..";"..tFn(SkuAuras.values, tAttributeValue[1][2])..";"
		end
		tOuterCount = tOuterCount + 1
	end

	tAuraName = tAuraName..L["dann;"]..tFn(SkuAuras.actions, aNewActions[1])..";"

	for tOutputIndex, tOutputName in pairs(aNewOutputs) do
		tAuraName = tAuraName..L[";und;"]..tFn(SkuAuras.outputs, string.gsub(tOutputName, "output:", ""))..";"
		tAuraName = string.gsub(tAuraName, "aura;sound#", L["sound;"])
	end

	return tAuraName
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuAuras:UpdateAura(aAuraNameToUpdate, aNewType, aEnabled, aNewAttributes, aNewActions, aNewOutputs)
	--print("UpdateAura", aAuraNameToUpdate)
	--build the new name
	local tAuraName = SkuAuras:BuildAuraName(aNewType, aNewAttributes, aNewActions, aNewOutputs)
	if SkuSettings:Sub("SkuAuras", nil, "char").Auras[aAuraNameToUpdate].customName == true then
		tAuraName = aAuraNameToUpdate
	end

	--update aura
	local tBackTo = SkuOptions.currentMenuPosition.selectTarget.backTo
	C_Timer.After(0.01, function()
		--remove old aura
		local tIsCustomName = SkuSettings:Sub("SkuAuras", nil, "char").Auras[aAuraNameToUpdate].customName
		SkuSettings:Sub("SkuAuras", nil, "char").Auras[aAuraNameToUpdate] = nil

		--add new aura
		SkuSettings:Sub("SkuAuras", nil, "char").Auras[tAuraName] = {
			type = aNewType,
			enabled = aEnabled,
			attributes = aNewAttributes,
			actions = aNewActions,
			outputs = aNewOutputs,
			customName = tIsCustomName,
		}

		SkuOptions.Voice:OutputStringBTtts(L["Aktualisiert"], true, true, 0.3, true)		

		C_Timer.After(0.01, function()
			SkuOptions:SlashFunc(Sku.MENU_ROOT..",SkuAuras,aurenVerwalten,"..SkuOptions.currentMenuPosition.parent.parent.parent.name..","..tAuraName)
			SkuOptions.currentMenuPosition:OnBack(SkuOptions.currentMenuPosition)
			SkuOptions:VocalizeCurrentMenuName()
		end)
	end)

end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuAuras:BuildManageSubMenu(aParentEntry, aNewEntry)
	local tTypeItem = SkuOptions:InjectMenuItems(aParentEntry, aNewEntry, SkuGenericMenuItem)
	tTypeItem.dynamic = true
	tTypeItem.internalName = "action"
	tTypeItem.OnEnter = function(self)
		self.selectTarget.targetAuraName = self.name
		SkuAuras:BuildAuraTooltip(self, self.name)
	end
	tTypeItem.BuildChildren = function(self)
		local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Umbenennen"]}, SkuGenericMenuItem)
		tNewMenuEntry.OnEnter = function(self)
			self.selectTarget.targetAuraName = self.parent.name
		end
		if SkuSettings:Sub("SkuAuras", nil, "char").Auras[self.selectTarget.targetAuraName] and SkuSettings:Sub("SkuAuras", nil, "char").Auras[self.selectTarget.targetAuraName].customName then
			if SkuAuras:AuraUsedInOtherAuras(self.selectTarget.targetAuraName) ~= true then
				local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Set name to auto generated"]}, SkuGenericMenuItem)
				tNewMenuEntry.OnEnter = function(self)
					self.selectTarget.targetAuraName = self.parent.name
				end
			end
		end

		if SkuAuras:AuraUsedInOtherAuras(self.selectTarget.targetAuraName) ~= true then
			if self.parent.name == L["Aktivierte"] then
				local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Deaktivieren"]}, SkuGenericMenuItem)
				tNewMenuEntry.OnEnter = function(self)
					self.selectTarget.targetAuraName = self.parent.name
				end
			else
				local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Aktivieren"]}, SkuGenericMenuItem)
				tNewMenuEntry.OnEnter = function(self)
					self.selectTarget.targetAuraName = self.parent.name
				end			
			end
		end
		local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Bearbeiten"]}, SkuGenericMenuItem)
		tNewMenuEntry.OnEnter = function(self)
			self.selectTarget.targetAuraName = self.parent.name
		end		
		tNewMenuEntry.dynamic = true
		tNewMenuEntry.internalName = "action"
		tNewMenuEntry.BuildChildren = function(self)
			local tNewMenuEntryCond = SkuOptions:InjectMenuItems(self, {L["Bedingungen"]}, SkuGenericMenuItem)
			tNewMenuEntryCond.dynamic = true
			tNewMenuEntryCond.isSelect = true
			tNewMenuEntryCond.auraName = self.parent.name
			tNewMenuEntryCond.backTo = self.parent.parent
			tNewMenuEntryCond.usedAttributes = {}
			tNewMenuEntryCond.single = true
			tNewMenuEntryCond.internalName = SkuSettings:Sub("SkuAuras", nil, "char").Auras[self.parent.name].type
			tNewMenuEntryCond.OnAction = function(self, aValue, aName)
				local tType = SkuSettings:Sub("SkuAuras", nil, "char").Auras[self.auraName].type
				local tEnabled = SkuSettings:Sub("SkuAuras", nil, "char").Auras[self.auraName].enabled
				local tAttributes = SkuSettings:Sub("SkuAuras", nil, "char").Auras[self.auraName].attributes
				local tActions = SkuSettings:Sub("SkuAuras", nil, "char").Auras[self.auraName].actions
				local tOutputs = SkuSettings:Sub("SkuAuras", nil, "char").Auras[self.auraName].outputs

				local function tAddConditionHelper(aParent)
					if not tAttributes[aParent.collectValuesFrom.parent.parent.internalName] then
						tAttributes[aParent.collectValuesFrom.parent.parent.internalName] = {}
					end
					table.insert(tAttributes[aParent.collectValuesFrom.parent.parent.internalName], {
						[1] = aParent.collectValuesFrom.parent.internalName,
						[2] = aParent.collectValuesFrom.internalName,
					})
				end
				
				local function tDeleteConditionHelper(aParent)
					local tDeleteAttribute
					for i, v in pairs(tAttributes) do
						if i == aParent.selectedCond[1] then
							local tFoundX
							if #v > 1 then
								for x = 1, #v do
									if v[x][1] == aParent.selectedCond[2] and v[x][2] == aParent.selectedCond[3] then
										tFoundX = x
									end
								end
								if tFoundX then
									table.remove(v, tFoundX)
								end
							else
								if v[1][1] == aParent.selectedCond[2] and v[1][2] == aParent.selectedCond[3] then
									table.remove(v, tFoundX)
								end
							end
							if #v == 0 then
								tDeleteAttribute = i
							end
						end
					end
					if tDeleteAttribute then
						tAttributes[tDeleteAttribute] = nil
					end
				end

				if aName == L["Löschen"] then
					tDeleteConditionHelper(self)

				elseif self.newOrChanged == "new" then
					tAddConditionHelper(self)

				elseif self.newOrChanged == "changed" then
					tDeleteConditionHelper(self)
					tAddConditionHelper(self)
				end

				SkuAuras:UpdateAura(self.auraName, tType, tEnabled, tAttributes, tActions, tOutputs)
			end

			tNewMenuEntryCond.BuildChildren = function(self)
				local tNewMenuEntryCondVal = SkuOptions:InjectMenuItems(self, {L["Bedingung hinzufügen"]}, SkuGenericMenuItem)
				tNewMenuEntryCondVal.dynamic = true
				tNewMenuEntryCondVal.OnEnter = function(self, aValue, aName)
					self.selectTarget.newOrChanged = "new"
				end
				tNewMenuEntryCondVal.BuildChildren = SkuAuras:NewAuraAttributeBuilder(tNewMenuEntryCondVal)
				for i, v in pairs(SkuSettings:Sub("SkuAuras", nil, "char").Auras[self.parent.parent.name].attributes) do
					for x = 1, #v do
						-- [v42.13] nil-tolerant (see tFriendlyName): a stale key, or one
						-- whose value list is still building, must not error the menu.
						local tNewMenuEntryCondValCon = SkuOptions:InjectMenuItems(self, {tFriendlyName(SkuAuras.attributes, i)..";"..tFriendlyName(SkuAuras.Operators, v[x][1])..";"..tValueName(v[x][2])}, SkuGenericMenuItem)
						tNewMenuEntryCondValCon.dynamic = true
						tNewMenuEntryCondValCon.OnEnter = function(self, aValue, aName)
							self.selectTarget.selectedCond = {[1] = i, [2] = v[x][1], [3] = v[x][2]}
						end
						tNewMenuEntryCondValCon.BuildChildren = function(self)
							local tNewMenuEntryCondValOptions = SkuOptions:InjectMenuItems(self, {L["Ändern"]}, SkuGenericMenuItem)
							tNewMenuEntryCondValOptions.dynamic = true
							tNewMenuEntryCondValOptions.OnEnter = function(self, aValue, aName)
								self.selectTarget.newOrChanged = "changed"
							end
							tNewMenuEntryCondValOptions.BuildChildren = SkuAuras:NewAuraAttributeBuilder(tNewMenuEntryCondValOptions)

							if NoIndexTableGetn(SkuSettings:Sub("SkuAuras", nil, "char").Auras[self.parent.parent.parent.name].attributes) > 1 then
								local tNewMenuEntryCondValOptions = SkuOptions:InjectMenuItems(self, {L["Löschen"]}, SkuGenericMenuItem)
								tNewMenuEntryCondValOptions.actionOnEnter = true
							end
						end
					end
				end
			end

			local tNewMenuEntryOutp = SkuOptions:InjectMenuItems(self, {L["Ausgaben"]}, SkuGenericMenuItem)
			tNewMenuEntryOutp.sorting = true
			tNewMenuEntryOutp.dynamic = true
			tNewMenuEntryOutp.isSelect = true
			tNewMenuEntryOutp.auraName = self.parent.name
			tNewMenuEntryOutp.usedOutputs = {}
			tNewMenuEntryOutp.backTo = self.parent.parent
			tNewMenuEntryOutp.single = true
			tNewMenuEntryOutp.internalName = "action"
			tNewMenuEntryOutp.OnAction = function(self, aValue, aName)
				--dprint("---- OnAction Ausgaben ", aValue, aName)
				--dprint("     self.auraName", self.auraName)
				--dprint("     self.collectValuesFrom.name", self.collectValuesFrom.name)

				local tType = SkuSettings:Sub("SkuAuras", nil, "char").Auras[self.auraName].type
				local tEnabled = SkuSettings:Sub("SkuAuras", nil, "char").Auras[self.auraName].enabled
				local tAttributes = SkuSettings:Sub("SkuAuras", nil, "char").Auras[self.auraName].attributes
				local tActions = SkuSettings:Sub("SkuAuras", nil, "char").Auras[self.auraName].actions
				local tOutputs = SkuSettings:Sub("SkuAuras", nil, "char").Auras[self.auraName].outputs

				local tTmpOutputs = {}
				local tCurrent = self.collectValuesFrom
				while tCurrent.name ~= L["Ausgaben"] do
					tTmpOutputs[#tTmpOutputs + 1] = tCurrent.internalName
					tCurrent = tCurrent.parent
				end
				
				local tNewOutputs = {}
				for x = #tTmpOutputs, 1, -1 do
					tNewOutputs[#tNewOutputs + 1] = tTmpOutputs[x]
				end

				SkuAuras:UpdateAura(self.auraName, tType, tEnabled, tAttributes, tActions, tNewOutputs)
			end
			tNewMenuEntryOutp.BuildChildren = SkuAuras:NewAuraAttributeBuilder(tNewMenuEntryOutp)
		end
		local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Duplizieren"]}, SkuGenericMenuItem)
		tNewMenuEntry.dynamic = true
		tNewMenuEntry.isSelect = true
		tNewMenuEntry.OnAction = function(self, aValue, aName)
			--dprint("OnAction Duplizieren")
			local tCopyCounter = 1
			local tTestNewName = L["Kopie;"]..tCopyCounter..";"..self.parent.name
			while SkuSettings:Sub("SkuAuras", nil, "char").Auras[tTestNewName] do
				tCopyCounter = tCopyCounter + 1
				tTestNewName = L["Kopie;"]..tCopyCounter..";"..self.parent.name
			end
			SkuSettings:Sub("SkuAuras", nil, "char").Auras[tTestNewName] = TableCopy(SkuSettings:Sub("SkuAuras", nil, "char").Auras[self.parent.name], true)
			SkuOptions.Voice:OutputStringBTtts(L["Dupliziert"], true, true, 0.3, true)		

			C_Timer.After(0.01, function()
				SkuOptions:SlashFunc(Sku.MENU_ROOT..",SkuAuras,aurenVerwalten,"..self.parent.parent.name..","..tTestNewName)
				SkuOptions.currentMenuPosition:OnBack(SkuOptions.currentMenuPosition)
				SkuOptions:VocalizeCurrentMenuName()
			end)
		end
		tNewMenuEntry.BuildChildren = function(self)
			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Wirklich duplizieren?"]}, SkuGenericMenuItem)
		end

		if SkuAuras:AuraUsedInOtherAuras(self.selectTarget.targetAuraName) ~= true then
			local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Löschen"]}, SkuGenericMenuItem)
		end
		local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Exportieren"]}, SkuGenericMenuItem)
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuAuras:ExportAuraData(aAuraNamesTable)
	if not aAuraNamesTable then
		return
	end

	local tExportDataTable = {
		version = (GetAddOnMetadata and GetAddOnMetadata("Sku", "Version"))
			or (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("Sku", "Version"))
			or "unknown",
		auraData = {},
	}

	for i, v in pairs(aAuraNamesTable) do
		if SkuSettings:Sub("SkuAuras", nil, "char").Auras[v] then
			tExportDataTable.auraData[v] = SkuSettings:Sub("SkuAuras", nil, "char").Auras[v]
		end
	end

	PlaySound(88)
	print(L["Aura exportiert"])
	SkuOptions.Voice:OutputStringBTtts(L["Jetzt Export Daten mit Steuerung plus C kopieren und Escape drücken"], false, true, 0.3)		
	SkuOptions:EditBoxShow(SkuOptions:Serialize(tExportDataTable.version, tExportDataTable.auraData), function(self) PlaySound(89) end)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuAuras:ImportAuraData()
	PlaySound(88)
	SkuOptions.Voice:OutputStringBTtts(L["Paste data to import now"], false, true, 0.2)

	SkuOptions:EditBoxPasteShow("", function(self)
		PlaySound(89)
		local tSerializedData = strtrim(table.concat(_G["SkuOptionsEditBoxPaste"].SkuOptionsTextBuffer))

		if tSerializedData ~= "" then
			local tSuccess, version, auraName, auraData = SkuOptions:Deserialize(tSerializedData)
			if type(auraName) == "string" then
				if auraName and auraData and version then
					if version < 22.8 then
						SkuOptions.Voice:OutputStringBTtts(L["Aura version zu alt"], false, true, 0.3)		
						return
					end
					auraData.enabled = true
					-- [v43.0] Same-locale values move to group identity, and the
					-- NAME is re-derived so an imported aura is named in THIS
					-- client's language (it is derived data; only customName auras
					-- keep theirs, and those are the ones other auras reference).
					SkuAuras:ConvertAuraValuesToGroups(auraData)
					auraName = SkuAuras:RelocalizedAuraName(auraName, auraData)
					SkuSettings:Sub("SkuAuras", nil, "char").Auras[auraName] = auraData
					print(L["Aura importiert:"])
					print(auraName)
					SkuOptions.Voice:OutputStringBTtts(L["Aura importiert"], false, true, 0.3)		
				else
					SkuOptions.Voice:OutputStringBTtts(L["Aura daten defekt"], false, true, 0.3)		
					return
				end

			elseif type(auraName) == "table" then
				auraData = auraName
				for i, v in pairs(auraData) do
					print(i)
					v.enabled = true
					-- [v43.0] see the single-aura branch above
					SkuAuras:ConvertAuraValuesToGroups(v)
					SkuSettings:Sub("SkuAuras", nil, "char").Auras[SkuAuras:RelocalizedAuraName(i, v)] = v
				end
				SkuOptions.Voice:OutputStringBTtts(L["Aura importiert"], false, true, 0.3)		
			end
		end
	end)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuAuras:MenuBuilder(aParentEntry)
	-- Flattened: the top-level "Auren" entry holds the aura list DIRECTLY. The
	-- old intermediate "Auren" list level and its empty "Optionen" sibling
	-- (SkuAuras.options.args is {}) are gone, so ONE right-arrow from the root
	-- entry lands on "Neue aura". SlashFunc anchor paths dropped the aurenList
	-- segment accordingly. The entries below stay hand-built/verbatim.
	aParentEntry.sorting = true
	local tBuildList = function(self)
		-- [41.05] Sets anlegen/teilen (Stufe 1+2), isoliert in SkuAuras\sharing.lua
		-- [41.06] Sets-Menue an Position 3 verschoben (siehe weiter unten, vor Aura importieren)
		local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Neue aura"]}, SkuGenericMenuItem)
		tNewMenuEntry.dynamic = true
		tNewMenuEntry.BuildChildren = function(self)
			for i, v in pairs(SkuAuras.Types) do
				local tTypeItem = SkuOptions:InjectMenuItems(self, {v.friendlyName}, SkuGenericMenuItem)
				tTypeItem.internalName = i
				tTypeItem.dynamic = true
				tTypeItem.sorting = true
				tTypeItem.isSelect = true
				tTypeItem.collectValuesFrom = self
				tTypeItem.usedAttributes = {}
				tTypeItem.elementType = "type"
				tTypeItem.OnAction = function(self, aValue, aName)
					local tMenuItem = self.collectValuesFrom
					local tFinalAttributes = {}
					while tMenuItem.internalName ~= self.internalName do
						if string.find(tMenuItem.internalName, "output:") then
							table.insert(tFinalAttributes, 1, {tMenuItem.internalName,})
							tMenuItem = tMenuItem.parent
						else
							table.insert(tFinalAttributes, 1, {tMenuItem.parent.parent.internalName, tMenuItem.internalName, tMenuItem.parent.internalName, })
							tMenuItem = tMenuItem.parent.parent.parent
						end
					end

					if SkuAuras:CreateAura(self.internalName, tFinalAttributes) == true then
						SkuOptions.Voice:OutputStringBTtts(L["Aura erstellt"], false, true, 0.1, true)

						SkuAuras:UpdateAttributesListWithCurrentAuras()
					else
						SkuOptions.Voice:OutputStringBTtts(L["Aura nicht erstellt"], false, true, 0.1, true)
					end
										
				end
				tTypeItem.OnEnter = function(self, aValue, aName)
					self.collectValuesFrom = self
					self.usedAttributes = {}
					self.BuildChildren = SkuAuras:NewAuraAttributeBuilder(self)
					SkuAuras:BuildAuraTooltip(self)
				end
				tTypeItem.BuildChildren = function(self)
					--dprint("generic build content of", self.name, "this should not happen")
				end
			end		
		end
		local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Auren verwalten"]}, SkuGenericMenuItem)
		tNewMenuEntry.dynamic = true
		tNewMenuEntry.isSelect = true
		tNewMenuEntry.sorting = true
		tNewMenuEntry.id = "aurenVerwalten"  -- stable nav anchor (W6-B #14)
		tNewMenuEntry.OnAction = function(self, aValue, aName)
			--print("OnAction Auren verwalten", aValue, aName, self.targetAuraName)
			if not self.targetAuraName then return end
			if not SkuSettings:Sub("SkuAuras", nil, "char").Auras[self.targetAuraName] then return end
			if aName == L["Deaktivieren"] or aName == L["Aktivieren"] then
				if SkuSettings:Sub("SkuAuras", nil, "char").Auras[self.targetAuraName].enabled == true then
					SkuSettings:Sub("SkuAuras", nil, "char").Auras[self.targetAuraName].enabled = false
					SkuOptions.Voice:OutputStringBTtts(L["deaktiviert"], false, true, 0.1, true)
				else
					SkuSettings:Sub("SkuAuras", nil, "char").Auras[self.targetAuraName].enabled = true
					SkuOptions.Voice:OutputStringBTtts(L["aktiviert"], false, true, 0.1, true)
				end			
			elseif aName == L["Löschen"] then
				SkuSettings:Sub("SkuAuras", nil, "char").Auras[self.targetAuraName] = nil
				SkuOptions.Voice:OutputStringBTtts(L["gelöscht"], false, true, 0.1, true)
			elseif aName == L["Exportieren"] then				
				SkuAuras:ExportAuraData({self.targetAuraName})

			elseif aName == L["Set name to auto generated"] then		
				local tData = SkuSettings:Sub("SkuAuras", nil, "char").Auras[self.targetAuraName]
				local tAutoName = SkuAuras:BuildAuraName(tData.type, tData.attributes, tData.actions, tData.outputs)
				if tAutoName ~= self.targetAuraName then
					SkuSettings:Sub("SkuAuras", nil, "char").Auras[tAutoName] = TableCopy(SkuSettings:Sub("SkuAuras", nil, "char").Auras[self.targetAuraName], true)
					SkuSettings:Sub("SkuAuras", nil, "char").Auras[tAutoName].customName = nil
					SkuSettings:Sub("SkuAuras", nil, "char").Auras[self.targetAuraName] = nil










					SkuAuras:UpdateAttributesWithUpdatedAuraName(tAutoName, tAutoName)














				end

			elseif aName == L["Umbenennen"] then				
				local tCurrentName = self.targetAuraName
				SkuOptions:EditBoxShow(
					"",
					function(self)
						local tNewName = SkuOptionsEditBoxEditBox:GetText()
						if tNewName and tNewName ~= "" then
							if SkuSettings:Sub("SkuAuras", nil, "char").Auras[tNewName] then
								SkuOptions.Voice:OutputStringBTtts(L["name already exists"], false, false, 0.2, true, nil, nil, 2)
								SkuOptions.Voice:OutputStringBTtts(L["Auren verwalten"], false, false, 0.2, true, nil, nil, 2)
								PlaySound(88)
								return
							end

							SkuSettings:Sub("SkuAuras", nil, "char").Auras[tNewName] = TableCopy(SkuSettings:Sub("SkuAuras", nil, "char").Auras[tCurrentName], true)
							SkuSettings:Sub("SkuAuras", nil, "char").Auras[tNewName].customName = true
							SkuSettings:Sub("SkuAuras", nil, "char").Auras[tCurrentName] = nil








							SkuAuras:UpdateAttributesWithUpdatedAuraName(tCurrentName, tNewName)











							PlaySound(88)
							C_Timer.After(0.01, function()
								SkuOptions.Voice:OutputStringBTtts(L["Renamed"], false, false, 0.2, true, nil, nil, 2)
								SkuOptions.Voice:OutputStringBTtts(L["Auren verwalten"], false, false, 0.2, true, nil, nil, 2)
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

			SkuAuras:UpdateAttributesListWithCurrentAuras()
		end
		tNewMenuEntry.BuildChildren = function(self)
			local tTypeItem = SkuOptions:InjectMenuItems(self, {L["Aktivierte"]}, SkuGenericMenuItem)
			tTypeItem.dynamic = true
			tTypeItem.sorting = true
			tTypeItem.BuildChildren = function(self)
				local tHasEntries = false
				for i, v in pairs(SkuSettings:Sub("SkuAuras", nil, "char").Auras) do 
					if v.enabled == true then
						tHasEntries = true
						SkuAuras:BuildManageSubMenu(self, {i})
					end
				end
				if tHasEntries == false then
					local tEmpty = SkuOptions:InjectMenuItems(self, {L["leer"]}, SkuGenericMenuItem)
				end
			end
			local tTypeItem = SkuOptions:InjectMenuItems(self, {L["Deaktivierte"]}, SkuGenericMenuItem)
			tTypeItem.dynamic = true
			tTypeItem.sorting = true
			tTypeItem.BuildChildren = function(self)
				local tHasEntries = false
				for i, v in pairs(SkuSettings:Sub("SkuAuras", nil, "char").Auras) do 
					if v.enabled ~= true then
						tHasEntries = true
						SkuAuras:BuildManageSubMenu(self, {i})
					end
				end
				if tHasEntries == false then
					local tEmpty = SkuOptions:InjectMenuItems(self, {L["leer"]}, SkuGenericMenuItem)
				end
			end
			local tTypeItem = SkuOptions:InjectMenuItems(self, {L["Alle"]}, SkuGenericMenuItem)
			tTypeItem.dynamic = true
			tTypeItem.sorting = true
			tTypeItem.BuildChildren = function(self)
				local tHasEntries = false
				for i, v in pairs(SkuSettings:Sub("SkuAuras", nil, "char").Auras) do 
					tHasEntries = true
					SkuAuras:BuildManageSubMenu(self, {i})
				end
				if tHasEntries == false then
					local tEmpty = SkuOptions:InjectMenuItems(self, {L["leer"]}, SkuGenericMenuItem)
				end
			end
		end

		-- [41.06] Sets anlegen/teilen an Position 3 (nach Neue aura + Auren verwalten)
			if SkuAuras.BuildSetsMenu then pcall(function() SkuAuras:BuildSetsMenu(self) end) end

			local tdel = SkuOptions:InjectMenuItems(self, {L["Aura importieren"]}, SkuGenericMenuItem)
		tdel.dynamic = false
		tdel.isSelect = true
		tdel.OnAction = function(self, aValue, aName)
			SkuAuras:ImportAuraData()
			SkuAuras:UpdateAttributesListWithCurrentAuras()
		end		

		local tdel = SkuOptions:InjectMenuItems(self, {L["Alle Auren löschen"]}, SkuGenericMenuItem)
		tdel.dynamic = false
		tdel.isSelect = true
		tdel.OnAction = function(self, aValue, aName)
			SkuSettings:Sub("SkuAuras", nil, "char").Auras = {}
			SkuOptions.Voice:OutputStringBTtts(L["Alle auren gelöscht"], true, true, 0.1, true)
			SkuAuras:UpdateAttributesListWithCurrentAuras()
		end

		local tdel = SkuOptions:InjectMenuItems(self, {L["Alle Auren exportieren"]}, SkuGenericMenuItem)
		tdel.dynamic = false
		tdel.isSelect = true
		tdel.OnAction = function(self, aValue, aName)
			local aAuraNamesTable = {}
			for i, v in pairs(SkuSettings:Sub("SkuAuras", nil, "char").Auras) do 
				table.insert(aAuraNamesTable, i)
			end 
			SkuAuras:ExportAuraData(aAuraNamesTable)
		end


		-- [Fix Nr22] Alte Set-Verwaltung (SkuAuras.AuraSets mit 3 Test-Sets) stillgelegt.
		-- Ersetzt durch die neue Set-Verwaltung ("Set Verwaltung", frueher "Sets (teilen)").
		if false then
		local tTypeItem = SkuOptions:InjectMenuItems(self, {L["Aura Sets verwalten"]}, SkuGenericMenuItem)
		tTypeItem.dynamic = true
		tTypeItem.isSelect = true
		tTypeItem.OnAction = function(self, aValue, aName)
			--dprint("OnAction Sets verwalten", self, aValue, aName)
			--dprint(self.selectedSetInternalName)
			if aName == L["Übernehmen überschreiben"] then
				SkuSettings:Sub("SkuAuras", nil, "char").Auras = {}
				tSetData = SkuAuras.AuraSets[self.selectedSetInternalName]
				for tAuraName, tAuraData in pairs(tSetData.auras) do
					SkuSettings:Sub("SkuAuras", nil, "char").Auras[tAuraData.friendlyNameShort] = tAuraData
				end
				SkuOptions.Voice:OutputStringBTtts(L["Set angewendet"], false, true, 0.3, true)	
				SkuAuras:UpdateAttributesListWithCurrentAuras()
			elseif aName == L["Übernehmen hinzufügen"] then
				tSetData = SkuAuras.AuraSets[self.selectedSetInternalName]
				for tAuraName, tAuraData in pairs(tSetData.auras) do
					SkuSettings:Sub("SkuAuras", nil, "char").Auras[tAuraData.friendlyNameShort] = tAuraData
				end
				SkuOptions.Voice:OutputStringBTtts(L["Set hinzugefügt"], false, true, 0.3, true)	
				SkuAuras:UpdateAttributesListWithCurrentAuras()
			elseif aName == L["Bearbeiten"] then
				SkuOptions.Voice:OutputStringBTtts(L["noch nicht implementiert"], false, true, 0.1, true)

			elseif aName == L["Exportieren"] then
				SkuOptions.Voice:OutputStringBTtts(L["noch nicht implementiert"], false, true, 0.1, true)

			elseif aName == L["Löschen"] then
				SkuAuras.AuraSets[self.selectedSetInternalName] = nil

			end
		end
		tTypeItem.BuildChildren = function(self)
			local tHasEntries = false
			for tIntName, tData in pairs(SkuAuras.AuraSets) do 
				--dprint(tIntName, tData, tData.friendlyName)
				tHasEntries = true
				local tSet = SkuOptions:InjectMenuItems(self, {tData.friendlyName}, SkuGenericMenuItem)
				tSet.dynamic = true
				tSet.internalName = tIntName
				tSet.OnEnter = function(self, aValue, aName)
					--dprint(self, aValue, aName)
					self.parent.selectedSetInternalName = self.internalName
					self.textFull = SkuAuras.AuraSets[self.internalName].tooltip
				end
				tSet.BuildChildren = function(self)
					local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Übernehmen überschreiben"]}, SkuGenericMenuItem)
					local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Übernehmen hinzufügen"]}, SkuGenericMenuItem)
					--local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Bearbeiten"]}, SkuGenericMenuItem)
					local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Exportieren"]}, SkuGenericMenuItem)
					local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Löschen"]}, SkuGenericMenuItem)
				end
			end
			if tHasEntries == false then
				local tEmpty = SkuOptions:InjectMenuItems(self, {L["leer"]}, SkuGenericMenuItem)
			end
		end
		end -- [Fix Nr22] Ende des stillgelegten alten Set-Verwaltung-Blocks
		-- [Fix Nr19] Menuepunkt "Aura Set importieren" entfernt (war nur Platzhalter
		-- "noch nicht implementiert"). Die neue Set-Verwaltung liegt unter "Set Verwaltung".
	end
	tBuildList(aParentEntry)
end