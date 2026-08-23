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
-- [v42.13] Nil-tolerant friendlyName lookup. SkuAuras.values is populated by the
-- BACKGROUND list build (SkuAuras:StartAttributeValueListsBuild), so a menu
-- opened in the first seconds of a session - or one referencing a key the
-- current data set no longer knows - must degrade to the raw key instead of
-- erroring out of the menu with "attempt to index field '?'".
-- [v43.0] The raw-key fallback goes through RemoveTags: values carry a tag
-- ("spellgroup:Frostbolt", "item:1234"), and on a friendlyName miss the old
-- fallback read the tag out loud to the user.
--
-- The type guard is load-bearing: SkuAuras:RemoveTags maps the STRINGS "true"
-- and "false" to the booleans, and the binary attributes' values are exactly
-- those two keys. A menu opened before the value lists finish building reaches
-- the fallback for them, and returning a boolean into a string concatenation is
-- how the aura menu would error out instead of merely reading a raw key.
local slower = string.lower

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
-- [v43.0] "I know the id but not the name". The typed id is RESOLVED to its
-- group and the GROUP value is stored, not the id: the list attributes match
-- against live lists keyed by group name, so a bare "spell:<id>" could never
-- match one of them, and spellName compares names and could not match an id
-- either. spellId is the one attribute where an id IS the value - and there it
-- is stored exactly as typed.
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
		return SkuAuras.values and SkuAuras.values[tValue] and tValue or nil
	end
	local tGroup = SkuAuras:SpellGroupName(aSpellId, nil)
	if not tGroup then
		return nil
	end
	local tValue = SkuAuras.SPELL_GROUP_TAG..tGroup
	return SkuAuras.values and SkuAuras.values[tValue] and tValue or nil
end

-- [v43.1] Type a spell NAME instead of hunting for it in a list of several
-- thousand entries - a numeric input still goes down the id lane above. The
-- result is always the value KEY the attribute actually stores, so a typed name
-- and a picked list entry produce byte-identical auras.
--
-- Resolution order, first hit wins:
--   1. the enUS group key exactly as typed (that IS the plain name on an enUS
--      client, and the identity everything is stored under),
--   2. the localized-name -> group map built by the value-list build,
--   3. a case-insensitive sweep of the attribute's OWN value list, matching
--      either the spoken name or the tag-stripped key. This is what catches a
--      name the map disambiguated with an English suffix.
local function tResolveSpellText(aAttributeName, aText)
	local tText = strtrim(tostring(aText or ""))
	if tText == "" then
		return nil
	end
	local tNumber = tonumber(tText)
	if tNumber then
		return tSpellIdValueFor(aAttributeName, tNumber)
	end
	if not tIdInputAttributes[aAttributeName] then
		return nil
	end
	local tTag = SkuAuras.SPELL_GROUP_TAG
	if SkuAuras.values and SkuAuras.values[tTag..tText] then
		return tTag..tText
	end
	local tMapped = SkuAuras.spellGroupByLocName and SkuAuras.spellGroupByLocName[tText]
	if type(tMapped) == "string" and SkuAuras.values and SkuAuras.values[tTag..tMapped] then
		return tTag..tMapped
	end
	local tLower = slower(tText)
	local tAttribute = SkuAuras.attributes[aAttributeName]
	local tValues = tAttribute and tAttribute.values
	if type(tValues) == "table" then
		for _, tValue in pairs(tValues) do
			local tEntry = SkuAuras.values and SkuAuras.values[tValue]
			local tPlain = tEntry and (tEntry.speakName or tEntry.friendlyName)
			if type(tPlain) == "string" and slower(tPlain) == tLower then
				return tValue
			end
			local tBare = tStripTagsForDisplay(tValue)
			if type(tBare) == "string" and slower(tBare) == tLower then
				return tValue
			end
		end
	end
	return nil
end

---------------------------------------------------------------------------------------------------------------------------------------
-- [v43.1] THE AURA BUILDER - draft model
--
-- Until v43.0 a new aura WAS the menu path the user had walked: the type node
-- collected the aura by walking `collectValuesFrom` back up the .parent chain,
-- every level re-pointed BuildChildren at the next builder in the chain, and
-- ENTER anywhere along the path committed whatever had been assembled so far.
-- One three-condition aura with two outputs was fourteen levels deep, nothing
-- could be reviewed or removed while building, and multi-value (OR) conditions
-- - which the storage format and the evaluator have always supported - were not
-- reachable from the menu at all.
--
-- Now the aura under construction lives in ONE table and the menu is only a
-- VIEW of it. Order-independence, review, removal and multi-select all fall out
-- of that one change, and the same workbench serves both "create" and "edit".
--
-- A condition row is
--     {att = <attribute key>, op = <operator key>, values = {v1, v2, ...}}
-- Several values in one row are OR-ed, which is exactly how the evaluator reads
-- several {op, value} pairs stored under one attribute (Core.lua, the
-- `#tAttributeValue > 1` branch).
--
-- The draft's type is always "if". "Wenn nicht" is gone from the builder - it
-- was expressible through the negating operators, unused in every shipped set
-- and in the live data, and its firing path skips the output-feeding
-- assignments after the loop's break. The evaluator still READS a legacy
-- ifNot aura; see the note there.
local AURA_DRAFT_ID = "auraDraftWorkbench"
local AURA_COND_ID = "auraDraftConditions"

SkuAuras.draft = nil

local function tConditionsFromAttributes(aAttributes)
	local tConditions = {}
	if type(aAttributes) ~= "table" then
		return tConditions
	end
	for tAtt, tEntries in pairs(aAttributes) do
		-- A stored group may legally mix operators. Group by operator so a row
		-- always means "this attribute, this operator, these OR-ed values"; the
		-- rows merge back into one stored group on save, so this round-trips.
		local tByOp, tOpOrder = {}, {}
		if type(tEntries) == "table" then
			for _, tEntry in pairs(tEntries) do
				if type(tEntry) == "table" and tEntry[1] then
					local tOp = tEntry[1]
					if not tByOp[tOp] then
						tByOp[tOp] = {}
						tOpOrder[#tOpOrder + 1] = tOp
					end
					tByOp[tOp][#tByOp[tOp] + 1] = tEntry[2]
				end
			end
		end
		for _, tOp in ipairs(tOpOrder) do
			tConditions[#tConditions + 1] = {att = tAtt, op = tOp, values = tByOp[tOp]}
		end
	end
	-- pairs() order is hash order; the menu needs a stable one.
	table.sort(tConditions, function(a, b)
		return slower(tFriendlyName(SkuAuras.attributes, a.att)) < slower(tFriendlyName(SkuAuras.attributes, b.att))
	end)
	return tConditions
end

local function tAttributesFromConditions(aConditions)
	local tAttributes = {}
	for _, tCond in ipairs(aConditions) do
		if tCond.att and tCond.op and type(tCond.values) == "table" and #tCond.values > 0 then
			local tGroup = tAttributes[tCond.att]
			if not tGroup then
				tGroup = {}
				tAttributes[tCond.att] = tGroup
			end
			for _, tValue in ipairs(tCond.values) do
				tGroup[#tGroup + 1] = {tCond.op, tValue}
			end
		end
	end
	return tAttributes
end

-- aAuraName = nil -> empty draft for a NEW aura; a name -> load that aura for
-- editing (and remember which one, so saving replaces it instead of adding).
function SkuAuras:DraftNew(aAuraName)
	local tData = aAuraName and SkuSettings:Sub("SkuAuras", nil, "char").Auras[aAuraName] or nil
	SkuAuras.draft = {
		type = (tData and tData.type) or "if",
		conditions = (tData and tConditionsFromAttributes(tData.attributes)) or {},
		actions = (tData and TableCopy(tData.actions or {}, true)) or {"notifyAudioSingle"},
		outputs = (tData and TableCopy(tData.outputs or {}, true)) or {},
		name = (tData and tData.customName == true) and aAuraName or nil,
		enabled = (tData and tData.enabled) ~= false,
		editing = (tData and aAuraName) or nil,
	}
	return SkuAuras.draft
end

local function tDraft()
	if not SkuAuras.draft then
		SkuAuras:DraftNew(nil)
	end
	return SkuAuras.draft
end

local function tIndexOfValue(aList, aValue)
	if type(aList) ~= "table" then
		return nil
	end
	for x = 1, #aList do
		if aList[x] == aValue then
			return x
		end
	end
	return nil
end

local function tDraftIndexOfCondition(aCond)
	local tD = tDraft()
	for x = 1, #tD.conditions do
		if tD.conditions[x] == aCond then
			return x
		end
	end
	return nil
end

-- A condition belongs to the draft exactly while it has at least one value.
-- That is what lets the user walk attribute -> operator -> values and simply
-- arrow back out: nothing was added if nothing was toggled on.
local function tDraftSyncCondition(aCond)
	local tD = tDraft()
	local tIndex = tDraftIndexOfCondition(aCond)
	if #aCond.values > 0 then
		if not tIndex then
			tD.conditions[#tD.conditions + 1] = aCond
		end
	elseif tIndex then
		table.remove(tD.conditions, tIndex)
	end
end

local function tToggleLabel(aName, aOn)
	-- Name first, state after: the list is scanned by name (and type-ahead keys
	-- off the first letter), the state is what the user needs to hear right
	-- after pressing ENTER on one entry.
	return aName..";"..(aOn and L["ein"] or L["aus"])
end

-- [v43.1] The joining word is the ONLY thing that tells the user which reading a
-- multi-value condition gets, so it has to match the evaluator exactly (see the
-- De Morgan note in SkuAuras/Core.lua): "oder" for an affirmative operator,
-- "und" for a negating one. Getting this wrong is worse than not showing it -
-- the user would hear a promise the evaluation does not keep.
local function tValueJoinWord(aOperator)
	if SkuAuras.negatingOperators and SkuAuras.negatingOperators[aOperator] == true then
		return L["und;"]
	end
	return L["oder;"]
end

local function tConditionText(aCond)
	local tText = tFriendlyName(SkuAuras.attributes, aCond.att)..";"..tFriendlyName(SkuAuras.Operators, aCond.op)..";"
	if #aCond.values == 0 then
		return tText..L["nicht festgelegt"]
	end
	local tJoin = tValueJoinWord(aCond.op)
	for x = 1, #aCond.values do
		if x > 1 then
			tText = tText..tJoin
		end
		tText = tText..tValueName(aCond.values[x])..";"
	end
	return tText
end

local function tActionText()
	local tD = tDraft()
	local tName = tD.actions[1] and tFriendlyName(SkuAuras.actions, tD.actions[1]) or L["nicht festgelegt"]
	return L["Ausgabe Typ"]..";"..tName
end

local function tConditionsLabel()
	return L["Bedingungen"].." ("..#tDraft().conditions..")"
end

local function tOutputsLabel()
	return L["Ausgabe"].." ("..#tDraft().outputs..")"
end

local function tNameLabel()
	return L["Name"]..";"..(tDraft().name or L["automatisch"])
end

local function tOutputText(aStoredOutput)
	return tFriendlyName(SkuAuras.outputs, string.gsub(tostring(aStoredOutput), "output:", ""))
end

-- The whole draft as tooltip sections, for the reading frame.
local function tDraftSummary()
	local tD = tDraft()
	local tSections = {}

	local tText = L["Bedingungen"]..":\r\n"
	if #tD.conditions == 0 then
		tText = tText..L["nicht festgelegt"].."\r\n"
	else
		for x = 1, #tD.conditions do
			tText = tText..x..": "..tConditionText(tD.conditions[x]).."\r\n"
		end
	end
	tSections[#tSections + 1] = tText

	tSections[#tSections + 1] = tActionText()

	tText = L["Ausgabe"]..":\r\n"
	if #tD.outputs == 0 then
		tText = tText..L["nicht festgelegt"].."\r\n"
	else
		for x = 1, #tD.outputs do
			tText = tText..x..": "..tOutputText(tD.outputs[x]).."\r\n"
		end
	end
	tSections[#tSections + 1] = tText

	tSections[#tSections + 1] = tNameLabel()
	return tSections
end

-- [v43.1] The old chained builder rewrote the reading frame at EVERY step, so
-- wherever the user stood they could read back the aura as it was so far. That
-- is the one thing the path-as-aura design got right, and it has to survive:
-- the draft summary goes on EVERY node of the builder, not just on the two that
-- happen to be about the whole thing.
--
-- aOwnText is what THIS entry is (an attribute's tooltip, an action's tooltip),
-- placed as the first section - the same shape the old
-- SkuAuras:BuildAuraTooltip produced: what you are standing on, then the aura.
local function tSetDraftTooltip(aNode, aOwnText)
	if not aNode then
		return
	end
	local tSections = tDraftSummary()
	if type(aOwnText) == "string" and aOwnText ~= "" then
		table.insert(tSections, 1, aOwnText)
	end
	aNode.textFull = tSections
end

---------------------------------------------------------------------------------------------------------------------------------------
-- The reading-frame text for a STORED aura (the "Auren verwalten" list). The
-- old SkuAuras:BuildAuraTooltip assembled this by walking the menu PATH the
-- user had walked, which is why it only ever worked while an aura was being
-- built along that path. A stored aura carries the data, so it is read straight
-- out of it and through the same formatting as the draft summary above.
function SkuAuras:BuildStoredAuraTooltip(aNode, aAuraName)
	local tData = aAuraName and SkuSettings:Sub("SkuAuras", nil, "char").Auras[aAuraName]
	if not tData then
		return
	end

	local tSections = {}
	local tConditions = tConditionsFromAttributes(tData.attributes)

	local tText = L["Bedingungen"]..":\r\n"
	if #tConditions == 0 then
		tText = tText..L["nicht festgelegt"].."\r\n"
	else
		for x = 1, #tConditions do
			tText = tText..x..": "..tConditionText(tConditions[x]).."\r\n"
		end
	end
	tSections[#tSections + 1] = tText

	local tAction = tData.actions and tData.actions[1]
	tSections[#tSections + 1] = L["Ausgabe Typ"]..": "..(tAction and tFriendlyName(SkuAuras.actions, tAction) or L["nicht festgelegt"])

	tText = L["Ausgabe"]..":\r\n"
	if not tData.outputs or #tData.outputs == 0 then
		tText = tText..L["nicht festgelegt"].."\r\n"
	else
		for x = 1, #tData.outputs do
			tText = tText..x..": "..tOutputText(tData.outputs[x]).."\r\n"
		end
	end
	tSections[#tSections + 1] = tText

	if aNode then
		aNode.textFull = tSections
	end
	return tSections
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Re-anchor the cursor on a level after an action that changed it. The generic
-- ENTER path parks the cursor before any C_Timer callback can run, so the
-- re-pin has to be deferred - the same shape UpdateAura and "Duplizieren" have
-- always used.
-- aAnnounce is spoken from INSIDE the deferred callback, with a queue reset, and
-- the level name is appended behind it. That ordering matters: the key handler
-- vocalizes the node the user just pressed synchronously, long before this
-- callback runs, so an announcement made in OnAction would end up sandwiched
-- between "Löschen" and the level name. Resetting here drops that leftover, and
-- what the user hears is "gelöscht, Bedingungen (1)".
local function tRepinLevel(aLevel, aNewName, aAnnounce)
	if not aLevel then
		if aAnnounce then
			SkuOptions.Voice:OutputStringBTtts(aAnnounce, true, true, 0.2, true)
		end
		return
	end
	C_Timer.After(0.01, function()
		if aNewName then
			aLevel.name = aNewName
		end
		SkuOptions:RebuildNodeChildren(aLevel)
		SkuOptions.currentMenuPosition = aLevel
		if aAnnounce then
			SkuOptions.Voice:OutputStringBTtts(aAnnounce, true, true, 0.2, true)
			SkuOptions:VocalizeCurrentMenuName(false)
		else
			SkuOptions:VocalizeCurrentMenuName()
		end
		if aLevel.OnEnter then
			aLevel:OnEnter()
		end
	end)
end

---------------------------------------------------------------------------------------------------------------------------------------
-- aCtx lets a caller that is NOT the draft reuse this: `onChange` replaces
-- the draft attach/detach, `ownerLabel` and `tooltip` replace the draft's
-- label refreshes. Defaults keep the draft behaviour, so the custom builder
-- passes nothing.
local function tCtxOnChange(aCtx, aCond)
	if aCtx and aCtx.onChange then
		aCtx.onChange(aCond)
	else
		tDraftSyncCondition(aCond)
	end
end

local function tPromptForSpellValue(aNode, aCond, aCtx)
	SkuOptions.Voice:OutputStringBTtts(L["Zaubername oder ID eingeben und Enter, oder Escape zum Abbrechen"], false, true, 0.2)
	SkuOptions:EditBoxShow("", function()
		local tText = strtrim(SkuOptionsEditBoxEditBox:GetText() or "")
		local tValue = tResolveSpellText(aCond.att, tText)
		if not tValue then
			SkuOptions.Voice:OutputStringBTtts(L["Unbekannter Zauber"], false, true, 0.2)
			return
		end
		if not tIndexOfValue(aCond.values, tValue) then
			aCond.values[#aCond.values + 1] = tValue
			tCtxOnChange(aCtx, aCond)
		end
		-- The framework parked the cursor when OnAction returned, long before
		-- this callback runs. Put it back where the user was standing.
		SkuOptions.currentMenuPosition = aNode
		local tCondLevel = aNode.FindAncestorById and aNode:FindAncestorById(AURA_COND_ID)
		if tCondLevel then
			tCondLevel.name = tConditionsLabel()
		end
		-- A recipe form has no condition level above it; its owning entry is the
		-- LEVEL this list was built into, and its label has to follow a typed-in
		-- value the same way it follows a toggled one.
		if aCtx and aCtx.ownerLabel and aNode.parent then
			aNode.parent.name = aCtx.ownerLabel(aCond)
		end
		SkuOptions.Voice:OutputStringBTtts(L["Wert gesetzt: "]..tValueName(tValue), false, true, 0.2)
	end)
end

-- The value list of ONE condition, as toggles: ENTER flips an entry on or off
-- and leaves the cursor on it (actionInPlace, see SkuZOptions/templates.lua),
-- so several OR-ed values are picked in one visit instead of one value per
-- walk down the whole menu.
-- aOwnerNode: the condition ROW this list belongs to, when there is one (the
-- edit path). Its label shows the condition, so it has to follow every toggle;
-- the ADD chain has no row yet and passes nil.
-- The value list of an attribute, in the order it should be READ: numerically
-- for the numeric types (otherwise it reads 1, 10, 100, 11, 12, ...) and by
-- localized name otherwise. Shared by the multi-select condition list and the
-- single-pick list of a base-aura form, so the same attribute always offers the
-- same entries in the same order wherever it turns up.
local function tSortedAttributeValues(aAttribute)
	local tSorted = {}
	if not aAttribute then
		return tSorted
	end
	if aAttribute.updateValues then
		aAttribute:updateValues()
	end
	for _, v in SkuSpairs(aAttribute.values or {},
		function(t, a, b)
			if aAttribute.type == "ORDINAL" or aAttribute.type == "THRESHOLD" then
				return (tonumber(t[a]) or 0) < (tonumber(t[b]) or 0)
			end
			return slower(tValueName(t[b])) > slower(tValueName(t[a]))
		end)
	do
		tSorted[#tSorted + 1] = v
	end
	return tSorted
end

local function tBuildValueToggleList(aLevel, aCond, aOwnerNode, aCtx)
	aLevel.auraCond = aCond
	aLevel.sorting = true

	local tAttribute = SkuAuras.attributes[aCond.att]
	if not tAttribute then
		SkuOptions:InjectMenuItems(aLevel, {L["leer"]}, SkuGenericMenuItem)
		return
	end
	-- index 0: type the name or the id rather than hunt through thousands of
	-- entries. Injected before the loop, and the menu keeps INSERTION order.
	if tIdInputAttributes[aCond.att] then
		local tInput = SkuOptions:InjectMenuItems(aLevel, {L["Zauber eingeben"]}, SkuGenericMenuItem)
		tInput.vocalizeAsIs = true
		tInput.sorting = true
		tInput.elementType = "value"
		tInput.actionInPlace = true
		tInput.OnEnter = function(self)
			if aCtx and aCtx.tooltip then
				aCtx.tooltip(self)
			else
				tSetDraftTooltip(self)
			end
		end
		tInput.OnAction = function(self)
			tPromptForSpellValue(self, aCond, aCtx)
		end
	end

	local tSorted = tSortedAttributeValues(tAttribute)

	for x = 1, #tSorted do
		local tValue = tSorted[x]
		local tNode = SkuOptions:InjectMenuItems(aLevel, {tToggleLabel(tValueName(tValue), tIndexOfValue(aCond.values, tValue) ~= nil)}, SkuGenericMenuItem)
		tNode.internalName = tValue
		tNode.sorting = true
		tNode.vocalizeAsIs = true
		tNode.elementType = "value"
		tNode.actionInPlace = true
		tNode.OnEnter = function(self)
			if aCtx and aCtx.tooltip then
				aCtx.tooltip(self)
			else
				tSetDraftTooltip(self, tConditionText(aCond))
			end
		end
		tNode.OnAction = function(self)
			local tIndex = tIndexOfValue(aCond.values, self.internalName)
			if tIndex then
				table.remove(aCond.values, tIndex)
			else
				aCond.values[#aCond.values + 1] = self.internalName
			end
			tCtxOnChange(aCtx, aCond)
			self.name = tToggleLabel(tValueName(self.internalName), tIndex == nil)
			-- Keep the labels ABOVE this list current: arrowing left must not
			-- read back the condition, or the condition count, as it was before
			-- the toggle. Neither level is rebuilt by simply stepping out of it.
			if aOwnerNode then
				if aCtx and aCtx.ownerLabel then
					aOwnerNode.name = aCtx.ownerLabel(aCond)
				else
					aOwnerNode.name = tConditionText(aCond)
				end
			end
			local tCondLevel = self:FindAncestorById(AURA_COND_ID)
			if tCondLevel then
				tCondLevel.name = tConditionsLabel()
			end
		end
	end
end

-- Plain operator entries for a select level ("Operator ändern").
local function tBuildOperatorEntries(aLevel, aAttName)
	aLevel.sorting = true
	local tAttribute = SkuAuras.attributes[aAttName]
	-- An attribute with no declared type falls back to CATEGORY, exactly as the
	-- old chained builder did; the nil guard is for a type that has no operator
	-- subset at all, which would otherwise take the whole menu down.
	local tOperators = SkuAuras.operatorsForAttributeType[(tAttribute and tAttribute.type) or "CATEGORY"]
		or SkuAuras.operatorsForAttributeType.CATEGORY
	local tSorted = TableSortByIndex(tOperators)
	for x = 1, #tSorted do
		local tOp = tSorted[x]
		if tOp ~= "then" then
			local tNode = SkuOptions:InjectMenuItems(aLevel, {tFriendlyName(SkuAuras.Operators, tOp)}, SkuGenericMenuItem)
			tNode.internalName = tOp
			tNode.sorting = true
			tNode.vocalizeAsIs = true
			tNode.elementType = "operator"
			tNode.OnEnter = function(self)
				tSetDraftTooltip(self, tFriendlyName(SkuAuras.Operators, self.internalName))
			end
		end
	end
end

-- Operator entries for the ADD chain: each one descends into the value list of
-- the condition it is about to create.
local function tBuildNewConditionOperators(aLevel, aAttName)
	aLevel.sorting = true
	local tAttribute = SkuAuras.attributes[aAttName]
	-- An attribute with no declared type falls back to CATEGORY, exactly as the
	-- old chained builder did; the nil guard is for a type that has no operator
	-- subset at all, which would otherwise take the whole menu down.
	local tOperators = SkuAuras.operatorsForAttributeType[(tAttribute and tAttribute.type) or "CATEGORY"]
		or SkuAuras.operatorsForAttributeType.CATEGORY
	local tSorted = TableSortByIndex(tOperators)
	for x = 1, #tSorted do
		local tOp = tSorted[x]
		if tOp ~= "then" then
			local tNode = SkuOptions:InjectMenuItems(aLevel, {tFriendlyName(SkuAuras.Operators, tOp)}, SkuGenericMenuItem)
			tNode.internalName = tOp
			tNode.dynamic = true
			tNode.sorting = true
			tNode.vocalizeAsIs = true
			tNode.elementType = "operator"
			tNode.OnEnter = function(self)
				tSetDraftTooltip(self, tFriendlyName(SkuAuras.Operators, self.internalName))
			end
			tNode.BuildChildren = function(self)
				-- Created here, attached to the draft by the first toggle
				-- (tDraftSyncCondition). Backing out without toggling anything
				-- therefore leaves no empty condition behind.
				if not self.auraCond then
					self.auraCond = {att = aAttName, op = self.internalName, values = {}}
				end
				tBuildValueToggleList(self, self.auraCond)
			end
		end
	end
end

-- One row per attribute. Two rows on the SAME attribute would be merged into
-- one stored group on save, and the evaluator ORs a group - so "duration
-- bigger 3" plus "duration smaller 10" would silently become "bigger 3 OR
-- smaller 10", i.e. always true. The old chained builder enforced the same rule
-- through usedAttributes.
local function tAttributeAllowed(aAttName)
	if aAttName == "action" then
		-- the pseudo-attribute the old chain used to reach the action step; the
		-- action has its own section now.
		return false
	end
	local tD = tDraft()
	for _, tCond in ipairs(tD.conditions) do
		if tCond.att == aAttName then
			return false
		end
	end
	local tRef = string.match(aAttName, "^skuAura(.+)$")
	if tRef then
		-- Aura-references are one level deep only; that is what keeps the nested
		-- EvaluateAllAuras call in the skuAura attribute from recursing.
		if tD.editing and tRef == SkuAuras:GetBaseAuraName(tD.editing) then
			return false
		end
		if SkuAuras:AuraHasOtherAuras(tRef) == true then
			return false
		end
		if tD.editing and SkuAuras:AuraUsedInOtherAuras(tD.editing) ~= nil then
			return false
		end
	end
	return true
end

local function tBuildAttributeList(aLevel)
	aLevel.sorting = true
	local tSorted = TableSortByIndex(SkuAuras.attributes)
	local tAny = false
	for x = 1, #tSorted do
		local tAttName = tSorted[x]
		if tAttributeAllowed(tAttName) then
			tAny = true
			local tNode = SkuOptions:InjectMenuItems(aLevel, {tFriendlyName(SkuAuras.attributes, tAttName)}, SkuGenericMenuItem)
			tNode.internalName = tAttName
			tNode.dynamic = true
			tNode.sorting = true
			tNode.vocalizeAsIs = true
			tNode.elementType = "attribute"
			tNode.OnEnter = function(self)
				local tEntry = SkuAuras.attributes[self.internalName]
				tSetDraftTooltip(self, tEntry and tEntry.tooltip)
			end
			tNode.BuildChildren = function(self)
				tBuildNewConditionOperators(self, self.internalName)
			end
		end
	end
	if tAny ~= true then
		SkuOptions:InjectMenuItems(aLevel, {L["leer"]}, SkuGenericMenuItem)
	end
end

local function tBuildConditionsLevel(aLevel)
	local tD = tDraft()

	for x = 1, #tD.conditions do
		local tCond = tD.conditions[x]
		local tRow = SkuOptions:InjectMenuItems(aLevel, {tConditionText(tCond)}, SkuGenericMenuItem)
		tRow.dynamic = true
		tRow.vocalizeAsIs = true
		tRow.elementType = "attribute"
		tRow.OnEnter = function(self)
			tSetDraftTooltip(self)
		end
		tRow.BuildChildren = function(self)
			local tValuesEntry = SkuOptions:InjectMenuItems(self, {L["Werte ändern"]}, SkuGenericMenuItem)
			tValuesEntry.dynamic = true
			tValuesEntry.OnEnter = function(self)
				tSetDraftTooltip(self, tConditionText(tCond))
			end
			tValuesEntry.BuildChildren = function(self)
				tBuildValueToggleList(self, tCond, self.parent)
			end

			local tOperatorEntry = SkuOptions:InjectMenuItems(self, {L["Operator ändern"]}, SkuGenericMenuItem)
			tOperatorEntry.dynamic = true
			tOperatorEntry.isSelect = true
			tOperatorEntry.sorting = true
			tOperatorEntry.OnEnter = function(self)
				tSetDraftTooltip(self, tConditionText(tCond))
			end
			tOperatorEntry.GetCurrentValue = function(self)
				return tFriendlyName(SkuAuras.Operators, tCond.op)
			end
			tOperatorEntry.OnAction = function(self, aNode)
				if type(aNode) ~= "table" or not aNode.internalName then
					return
				end
				tCond.op = aNode.internalName
				if self.parent then
					self.parent.name = tConditionText(tCond)
				end
				SkuOptions.Voice:OutputStringBTtts(tFriendlyName(SkuAuras.Operators, tCond.op), false, true, 0.1, true)
			end
			tOperatorEntry.BuildChildren = function(self)
				tBuildOperatorEntries(self, tCond.att)
			end

			local tDeleteEntry = SkuOptions:InjectMenuItems(self, {L["Löschen"]}, SkuGenericMenuItem)
			tDeleteEntry.actionInPlace = true
			tDeleteEntry.OnEnter = function(self)
				tSetDraftTooltip(self, tConditionText(tCond))
			end
			tDeleteEntry.OnAction = function(self)
				local tIndex = tDraftIndexOfCondition(tCond)
				if tIndex then
					table.remove(tDraft().conditions, tIndex)
				end
				tRepinLevel(self:FindAncestorById(AURA_COND_ID), tConditionsLabel(), L["gelöscht"])
			end
		end
	end

	-- [v43.1] The attribute list sits DIRECTLY in this level, behind the existing
	-- condition rows - there is no "Bedingung hinzufügen" step to walk through
	-- first. The step carried no information: it had exactly one thing behind it,
	-- so it was a keypress that only ever said "yes, really". The two kinds of
	-- entry are told apart by what they SAY: a row reads
	-- "attribut;operator;wert", an attribute reads its name alone.
	tBuildAttributeList(aLevel)
end

local function tBuildOutputsLevel(aLevel)
	aLevel.sorting = true
	local tSorted = TableSortByIndex(SkuAuras.outputs)
	for x = 1, #tSorted do
		local tKey = tSorted[x]
		local tStored = "output:"..tKey
		local tFriendly = SkuAuras.outputs[tKey].friendlyName
		local tNode = SkuOptions:InjectMenuItems(aLevel, {tToggleLabel(tFriendly, tIndexOfValue(tDraft().outputs, tStored) ~= nil)}, SkuGenericMenuItem)
		tNode.internalName = tStored
		-- Lets the generic OnEnter audition the beep even though the node name
		-- now carries a state suffix (SkuZOptions/templates.lua).
		tNode.auraOutputKey = tKey
		tNode.sorting = true
		tNode.vocalizeAsIs = true
		tNode.elementType = "output"
		tNode.actionInPlace = true
		-- The GENERIC OnEnter is what auditions the beep, so it has to run;
		-- overriding it outright would silence the preview.
		tNode.OnEnter = function(self, aValue, aName)
			SkuGenericMenuItem.OnEnter(self, aValue, aName)
			tSetDraftTooltip(self)
		end
		tNode.OnAction = function(self)
			local tOutputs = tDraft().outputs
			local tIndex = tIndexOfValue(tOutputs, self.internalName)
			if tIndex then
				table.remove(tOutputs, tIndex)
			else
				tOutputs[#tOutputs + 1] = self.internalName
			end
			self.name = tToggleLabel(tFriendly, tIndex == nil)
			if self.parent then
				self.parent.name = tOutputsLabel()
			end
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Write the draft to the aura store. Creating and editing differ only in
-- whether an old key has to go.
function SkuAuras:DraftCommit(aNode)
	local tD = tDraft()
	local tAttributes = tAttributesFromConditions(tD.conditions)

	if next(tAttributes) == nil then
		SkuOptions.Voice:OutputStringBTtts(L["Keine Bedingung festgelegt"], false, true, 0.2, true)
		return
	end
	if #tD.outputs == 0 then
		SkuOptions.Voice:OutputStringBTtts(L["Keine Ausgabe festgelegt"], false, true, 0.2, true)
		return
	end
	if not tD.actions[1] then
		tD.actions = {"notifyAudioSingle"}
	end

	local tCustomName = tD.name ~= nil
	local tAuraName = tD.name or SkuAuras:BuildAuraName(tD.type, tAttributes, tD.actions, tD.outputs)

	local tStore = SkuSettings:Sub("SkuAuras", nil, "char").Auras
	if tStore[tAuraName] and tAuraName ~= tD.editing then
		SkuOptions.Voice:OutputStringBTtts(L["name already exists"], false, true, 0.2, true)
		return
	end

	if tD.editing and tD.editing ~= tAuraName then
		tStore[tD.editing] = nil
	end

	tStore[tAuraName] = {
		type = tD.type,
		enabled = tD.enabled ~= false,
		attributes = tAttributes,
		actions = TableCopy(tD.actions, true),
		outputs = TableCopy(tD.outputs, true),
		customName = tCustomName or nil,
	}

	if tD.editing and tD.editing ~= tAuraName then
		SkuAuras:UpdateAttributesWithUpdatedAuraName(tD.editing, tAuraName)
	end
	SkuAuras:UpdateAttributesListWithCurrentAuras()

	SkuAuras.draft = nil
	-- The edit level remembers WHICH aura it is editing (auraName); a rename
	-- would otherwise leave it pointing at a key that no longer exists, and the
	-- rebuild below would open an empty draft instead of the aura just saved.
	local tLevel = aNode and aNode.parent
	if tLevel and tLevel.auraName then
		tLevel.auraName = tAuraName
	end
	tRepinLevel(tLevel, nil, tD.editing and L["Aura gespeichert"] or L["Aura erstellt"])
end

---------------------------------------------------------------------------------------------------------------------------------------
-- The workbench. Every section is enterable in any order, any number of times,
-- and each section's own entry NAME carries its state - so arrowing across the
-- level reads the whole draft back without entering anything. Only "Aura
-- erstellen" and "Verwerfen" change the stored auras.
function SkuAuras:BuildDraftWorkbench(aLevel)
	local tD = tDraft()

	local tConditionsEntry = SkuOptions:InjectMenuItems(aLevel, {tConditionsLabel()}, SkuGenericMenuItem)
	tConditionsEntry.dynamic = true
	tConditionsEntry.id = AURA_COND_ID
	tConditionsEntry.vocalizeAsIs = true
	tConditionsEntry.OnEnter = function(self)
		tSetDraftTooltip(self)
	end
	tConditionsEntry.BuildChildren = function(self)
		tBuildConditionsLevel(self)
	end

	local tActionEntry = SkuOptions:InjectMenuItems(aLevel, {tActionText()}, SkuGenericMenuItem)
	tActionEntry.dynamic = true
	tActionEntry.isSelect = true
	tActionEntry.sorting = true
	tActionEntry.vocalizeAsIs = true
	tActionEntry.OnEnter = function(self)
		tSetDraftTooltip(self)
	end
	tActionEntry.GetCurrentValue = function(self)
		local tCurrent = tDraft().actions[1]
		return tCurrent and tFriendlyName(SkuAuras.actions, tCurrent) or nil
	end
	tActionEntry.OnAction = function(self, aNode)
		if type(aNode) ~= "table" or not aNode.internalName then
			return
		end
		tDraft().actions = {aNode.internalName}
		self.name = tActionText()
	end
	tActionEntry.BuildChildren = function(self)
		local tSorted = TableSortByIndex(SkuAuras.actions)
		for x = 1, #tSorted do
			local tKey = tSorted[x]
			local tNode = SkuOptions:InjectMenuItems(self, {tFriendlyName(SkuAuras.actions, tKey)}, SkuGenericMenuItem)
			tNode.internalName = tKey
			tNode.sorting = true
			tNode.vocalizeAsIs = true
			tNode.elementType = "action"
			tNode.OnEnter = function(self)
				local tEntry = SkuAuras.actions[self.internalName]
				tSetDraftTooltip(self, tEntry and tEntry.tooltip)
			end
		end
	end

	local tOutputsEntry = SkuOptions:InjectMenuItems(aLevel, {tOutputsLabel()}, SkuGenericMenuItem)
	tOutputsEntry.dynamic = true
	tOutputsEntry.vocalizeAsIs = true
	tOutputsEntry.OnEnter = function(self)
		tSetDraftTooltip(self)
	end
	tOutputsEntry.BuildChildren = function(self)
		tBuildOutputsLevel(self)
	end

	local tNameEntry = SkuOptions:InjectMenuItems(aLevel, {tNameLabel()}, SkuGenericMenuItem)
	tNameEntry.vocalizeAsIs = true
	tNameEntry.actionInPlace = true
	tNameEntry.OnEnter = function(self)
		tSetDraftTooltip(self)
	end
	tNameEntry.OnAction = function(self)
		local tSelf = self
		SkuOptions.Voice:OutputStringBTtts(L["Namen eingeben und Enter, leer für automatisch"], false, true, 0.2)
		SkuOptions:EditBoxShow(tDraft().name or "", function()
			local tText = strtrim(SkuOptionsEditBoxEditBox:GetText() or "")
			tDraft().name = (tText ~= "" and tText) or nil
			tSelf.name = tNameLabel()
			SkuOptions.currentMenuPosition = tSelf
			SkuOptions.Voice:OutputStringBTtts(tSelf.name, false, true, 0.2)
		end)
	end

	local tSaveEntry = SkuOptions:InjectMenuItems(aLevel, {tD.editing and L["Aura speichern"] or L["Aura erstellen"]}, SkuGenericMenuItem)
	tSaveEntry.vocalizeAsIs = true
	tSaveEntry.actionInPlace = true
	tSaveEntry.OnEnter = function(self)
		tSetDraftTooltip(self)
	end
	tSaveEntry.OnAction = function(self)
		SkuAuras:DraftCommit(self)
	end

	local tDiscardEntry = SkuOptions:InjectMenuItems(aLevel, {L["Verwerfen"]}, SkuGenericMenuItem)
	tDiscardEntry.actionInPlace = true
	tDiscardEntry.OnEnter = function(self)
		tSetDraftTooltip(self)
	end
	tDiscardEntry.OnAction = function(self)
		local tEditing = tDraft().editing
		SkuAuras:DraftNew(tEditing)
		tRepinLevel(self.parent, nil, L["Entwurf verworfen"])
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- [v43.1] BASE AURAS
--
-- The recipes that cover what nearly everybody wants: a fixed condition
-- skeleton plus ONE attribute the user fills in. The sound and the aura name
-- have working defaults, so the whole thing is "pick a spell, press create".
--
-- The names say what the aura DOES, in the order the user thinks about it
-- ("dein Debuff auf Ziel läuft aus"), not how it is wired ("source self, event
-- aura removed, dest target").
--
-- The two "auf Ziel" recipes build the SAME conditions and differ only in the
-- name they give the aura. That is deliberate. They used to carry an
-- `auraType is BUFF/DEBUFF` condition to tell them apart, and it had to go: the
-- spell name already decides whether the aura is a buff or a debuff, so the
-- condition could only ever be redundant - or, if the user picked the recipe
-- whose label did not match their spell, fatal, and silently so. A condition
-- that is redundant when right and invisible when wrong does not earn its place
-- (same rule as the duration "gleich"). The two labels stay because they are
-- how the user finds the recipe, and because the aura NAME they generate is
-- what gets read back later. The attribute itself is untouched and still
-- available by hand, where it IS the only way to say something: an aura with no
-- spell name at all, e.g. "any debuff was applied to me".
--
-- A recipe is DATA, not a build function:
--   fixed     - the conditions the recipe pins down itself
--   attribute - the one the user fills in
--   operator  - how that attribute is compared
-- so the filled attribute is an ordinary condition group and the form can hand
-- it straight to the SAME value list the custom builder uses. That is what lets
-- a recipe take SEVERAL spells ("Mondfeuer oder Insektenschwarm") for free.
local tBaseAuraRecipes = {
	{
		id = "targetDebuffExpires",
		label = L["Dein Debuff auf Ziel läuft aus"],
		attribute = "spellName",
		operator = "is",
		defaultSound = "sound-glass1",
		fixedOutputs = {},
		fixed = {
			sourceUnitId = {{"contains", "player"}},
			event = {{"is", "SPELL_AURA_REMOVED"}},
			destUnitId = {{"contains", "target"}},
		},
	},
	{
		id = "targetBuffExpires",
		label = L["Dein Buff auf Ziel läuft aus"],
		attribute = "spellName",
		operator = "is",
		defaultSound = "sound-glass2",
		fixedOutputs = {},
		fixed = {
			sourceUnitId = {{"contains", "player"}},
			event = {{"is", "SPELL_AURA_REMOVED"}},
			destUnitId = {{"contains", "target"}},
		},
	},
	{
		id = "ownCooldownReady",
		label = L["Eigener Cooldown wieder bereit"],
		attribute = "spellName",
		operator = "is",
		defaultSound = "sound-glass5",
		fixedOutputs = {},
		fixed = {
			sourceUnitId = {{"contains", "player"}},
			event = {{"is", "SPELL_COOLDOWN_END"}},
		},
	},
	{
		-- Modelled on the user's own "SEELENSTÄRKE" aura (source self, aura
		-- removed, spellName Power Word: Fortitude, outputs sound + spell name +
		-- dest unit), with the group condition it was missing: without
		-- "destUnitId contains party" the same aura also fires for a buff falling
		-- off a stranger you happened to have buffed.
		-- `party` includes the player (see the destUnitId evaluate) - you want to
		-- hear your own Fortitude drop too.
		-- The two data outputs are FIXED rather than optional: "which buff, on
		-- whom" is the entire point of this one, and a beep alone would not say
		-- either. `sourceUnitId contains player` is why the label says "Dein".
		id = "groupBuffExpired",
		label = L["Dein Buff auf Gruppenmitglied ausgelaufen"],
		attribute = "spellName",
		operator = "is",
		defaultSound = "sound-error_dang",
		fixedOutputs = {"output:spellName", "output:destUnitId"},
		fixed = {
			sourceUnitId = {{"contains", "player"}},
			event = {{"is", "SPELL_AURA_REMOVED"}},
			destUnitId = {{"contains", "party"}},
		},
	},
	{
		id = "debuffOnTargetChange",
		label = L["Debuff bei Zielwechsel ausgeben"],
		attribute = "debuffListTarget",
		operator = "contains",
		defaultSound = "sound-notification12",
		fixedOutputs = {},
		fixed = {
			listsOwnOnly = {{"is", "true"}},
			event = {{"is", "UNIT_TARGETCHANGE"}},
		},
	},
}

SkuAuras.baseForm = nil

-- The form's filled-in attribute is a condition row of exactly the shape the
-- custom builder uses, which is what lets the two share the value list.
local function tBaseForm(aRecipe)
	local tF = SkuAuras.baseForm
	if not tF or tF.recipe ~= aRecipe.id then
		tF = {
			recipe = aRecipe.id,
			cond = {att = aRecipe.attribute, op = aRecipe.operator, values = {}},
			sound = aRecipe.defaultSound,
			name = nil,
		}
		SkuAuras.baseForm = tF
	end
	return tF
end

local function tBaseValuesText(aRecipe)
	local tF = tBaseForm(aRecipe)
	if #tF.cond.values == 0 then
		return L["nicht festgelegt"]
	end
	local tJoin = tValueJoinWord(tF.cond.op)
	local tText = ""
	for x = 1, #tF.cond.values do
		if x > 1 then
			tText = tText..tJoin
		end
		tText = tText..tValueName(tF.cond.values[x])..";"
	end
	return tText
end

local function tBaseSpellLabel(aRecipe)
	return L["Zauber"]..";"..tBaseValuesText(aRecipe)
end

-- The sound outputs' friendlyName is "<tag>#<name>" - the tag is what the
-- generic OnEnter keys the audition off, and it belongs on the list ENTRIES,
-- not in a settings label that merely reports which sound is chosen.
local function tSoundDisplayName(aKey)
	local tName = tFriendlyName(SkuAuras.outputs, aKey)
	local tPos = string.find(tName, "#", 1, true)
	if tPos then
		return string.sub(tName, tPos + 1)
	end
	return tName
end

local function tBaseSoundLabel(aRecipe)
	local tF = tBaseForm(aRecipe)
	if not tF.sound then
		return L["Ton"]..";"..L["kein Ton"]
	end
	return L["Ton"]..";"..tSoundDisplayName(tF.sound)
end

local function tBaseNameLabel(aRecipe)
	local tF = tBaseForm(aRecipe)
	return L["Name"]..";"..(tF.name or L["automatisch"])
end

-- The attributes this recipe would store right now: its own fixed conditions
-- plus the group the user filled in.
local function tBaseAttributes(aRecipe)
	local tF = tBaseForm(aRecipe)
	local tAttributes = TableCopy(aRecipe.fixed, true)
	local tGroup = {}
	for x = 1, #tF.cond.values do
		tGroup[#tGroup + 1] = {tF.cond.op, tF.cond.values[x]}
	end
	if #tGroup == 0 then
		tGroup[1] = {tF.cond.op, L["nicht festgelegt"]}
	end
	tAttributes[aRecipe.attribute] = tGroup
	return tAttributes
end

-- [v43.1] The same read-back the workbench gives, for a recipe form: what this
-- aura WILL be, rendered from the recipe's own skeleton through the very same
-- formatting as a hand-built condition. A recipe is not a black box just
-- because it fills itself in - the user has to be able to hear what they are
-- about to create.
--
-- With nothing picked yet the spell slot renders as L["nicht festgelegt"]: that
-- key is not in SkuAuras.values, so tValueName falls through to the raw string
-- and reads exactly as it says.
local function tBaseFormSummary(aRecipe)
	local tF = tBaseForm(aRecipe)
	local tSections = {aRecipe.label}

	local tConditions = tConditionsFromAttributes(tBaseAttributes(aRecipe))
	local tText = L["Bedingungen"]..":\r\n"
	for x = 1, #tConditions do
		tText = tText..x..": "..tConditionText(tConditions[x]).."\r\n"
	end
	tSections[#tSections + 1] = tText

	tText = L["Ausgabe"]..":\r\n"
	local tCount = 0
	if tF.sound then
		tCount = tCount + 1
		tText = tText..tCount..": "..tOutputText("output:"..tF.sound).."\r\n"
	end
	for _, tOutput in ipairs(aRecipe.fixedOutputs) do
		tCount = tCount + 1
		tText = tText..tCount..": "..tOutputText(tOutput).."\r\n"
	end
	if tCount == 0 then
		tText = tText..L["nicht festgelegt"].."\r\n"
	end
	tSections[#tSections + 1] = tText

	tSections[#tSections + 1] = tBaseNameLabel(aRecipe)
	return tSections
end

local function tSetBaseTooltip(aNode, aRecipe)
	if aNode then
		aNode.textFull = tBaseFormSummary(aRecipe)
	end
end

local function tBaseFormCommit(aNode, aRecipe)
	local tF = tBaseForm(aRecipe)
	if #tF.cond.values == 0 then
		SkuOptions.Voice:OutputStringBTtts(L["Kein Zauber festgelegt"], false, true, 0.2, true)
		return
	end

	local tOutputs = {}
	if tF.sound then
		tOutputs[#tOutputs + 1] = "output:"..tF.sound
	end
	for _, tOutput in ipairs(aRecipe.fixedOutputs) do
		tOutputs[#tOutputs + 1] = tOutput
	end
	if #tOutputs == 0 then
		SkuOptions.Voice:OutputStringBTtts(L["Keine Ausgabe festgelegt"], false, true, 0.2, true)
		return
	end

	-- Base auras always get a custom name: it is the readable one, and a custom
	-- name is also what makes an aura referenceable from another aura.
	local tAuraName = tF.name or (aRecipe.label..";"..tBaseValuesText(aRecipe))
	local tStore = SkuSettings:Sub("SkuAuras", nil, "char").Auras
	if tStore[tAuraName] then
		SkuOptions.Voice:OutputStringBTtts(L["name already exists"], false, true, 0.2, true)
		return
	end

	tStore[tAuraName] = {
		type = "if",
		enabled = true,
		attributes = tBaseAttributes(aRecipe),
		actions = {"notifyAudioSingle"},
		outputs = tOutputs,
		customName = true,
	}
	SkuAuras:UpdateAttributesListWithCurrentAuras()
	SkuAuras.baseForm = nil
	tRepinLevel(aNode and aNode.parent, nil, L["Aura erstellt"])
end

local function tBuildBaseRecipeForm(aLevel, aRecipe)
	tBaseForm(aRecipe)

	-- [v43.1] The spell entry is a plain container over THE value list the
	-- custom builder uses - same entries, same order, same multi-select, same
	-- "Zauber eingeben" at index 0. It used to have a list of its own that
	-- allowed one pick and threw the user back out, which meant the easy path
	-- behaved differently from the real one for no reason. Several values are
	-- allowed here too: "Mondfeuer oder Insektenschwarm" is one aura.
	local tSpellEntry = SkuOptions:InjectMenuItems(aLevel, {tBaseSpellLabel(aRecipe)}, SkuGenericMenuItem)
	tSpellEntry.vocalizeAsIs = true
	tSpellEntry.dynamic = true
	tSpellEntry.OnEnter = function(self)
		tSetBaseTooltip(self, aRecipe)
	end
	tSpellEntry.BuildChildren = function(self)
		-- The context is what keeps the shared list out of the custom builder's
		-- draft: this condition belongs to a recipe form, so it must not be
		-- attached to SkuAuras.draft.conditions, and the labels it refreshes are
		-- the recipe's, not the draft's.
		tBuildValueToggleList(self, tBaseForm(aRecipe).cond, self, {
			onChange = function() end,
			ownerLabel = function() return tBaseSpellLabel(aRecipe) end,
			tooltip = function(aNode) tSetBaseTooltip(aNode, aRecipe) end,
		})
	end

	local tSoundEntry = SkuOptions:InjectMenuItems(aLevel, {tBaseSoundLabel(aRecipe)}, SkuGenericMenuItem)
	tSoundEntry.dynamic = true
	tSoundEntry.isSelect = true
	tSoundEntry.sorting = true
	tSoundEntry.vocalizeAsIs = true
	tSoundEntry.OnEnter = function(self)
		tSetBaseTooltip(self, aRecipe)
	end
	tSoundEntry.GetCurrentValue = function(self)
		local tF = tBaseForm(aRecipe)
		if not tF.sound then
			return L["kein Ton"]
		end
		return tFriendlyName(SkuAuras.outputs, tF.sound)
	end
	tSoundEntry.OnAction = function(self, aNode)
		if type(aNode) ~= "table" then
			return
		end
		local tF = tBaseForm(aRecipe)
		tF.sound = aNode.auraOutputKey
		self.name = tBaseSoundLabel(aRecipe)
	end
	tSoundEntry.BuildChildren = function(self)
		local tNoSound = SkuOptions:InjectMenuItems(self, {L["kein Ton"]}, SkuGenericMenuItem)
		tNoSound.sorting = true
		tNoSound.vocalizeAsIs = true
		local tSorted = TableSortByIndex(SkuAuras.outputs)
		for x = 1, #tSorted do
			local tKey = tSorted[x]
			if SkuAuras.outputs[tKey].outputString then
				local tNode = SkuOptions:InjectMenuItems(self, {SkuAuras.outputs[tKey].friendlyName}, SkuGenericMenuItem)
				tNode.auraOutputKey = tKey
				tNode.internalName = tKey
				tNode.sorting = true
				tNode.vocalizeAsIs = true
				-- the GENERIC OnEnter auditions the beep, so it has to run
				tNode.OnEnter = function(self, aValue, aName)
					SkuGenericMenuItem.OnEnter(self, aValue, aName)
					tSetBaseTooltip(self, aRecipe)
				end
			end
		end
	end

	local tNameEntry = SkuOptions:InjectMenuItems(aLevel, {tBaseNameLabel(aRecipe)}, SkuGenericMenuItem)
	tNameEntry.vocalizeAsIs = true
	tNameEntry.actionInPlace = true
	tNameEntry.OnEnter = function(self)
		tSetBaseTooltip(self, aRecipe)
	end
	tNameEntry.OnAction = function(self)
		local tSelf = self
		SkuOptions.Voice:OutputStringBTtts(L["Namen eingeben und Enter, leer für automatisch"], false, true, 0.2)
		SkuOptions:EditBoxShow(tBaseForm(aRecipe).name or "", function()
			local tText = strtrim(SkuOptionsEditBoxEditBox:GetText() or "")
			tBaseForm(aRecipe).name = (tText ~= "" and tText) or nil
			tSelf.name = tBaseNameLabel(aRecipe)
			SkuOptions.currentMenuPosition = tSelf
			SkuOptions.Voice:OutputStringBTtts(tSelf.name, false, true, 0.2)
		end)
	end

	local tCreateEntry = SkuOptions:InjectMenuItems(aLevel, {L["Aura erstellen"]}, SkuGenericMenuItem)
	tCreateEntry.vocalizeAsIs = true
	tCreateEntry.actionInPlace = true
	tCreateEntry.OnEnter = function(self)
		tSetBaseTooltip(self, aRecipe)
	end
	tCreateEntry.OnAction = function(self)
		tBaseFormCommit(self, aRecipe)
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- "Neue Aura" -> Basis-Auren / Eigene Aura erstellen
function SkuAuras:BuildNewAuraMenu(aLevel)
	local tBaseEntry = SkuOptions:InjectMenuItems(aLevel, {L["Basis-Auren"]}, SkuGenericMenuItem)
	tBaseEntry.dynamic = true
	tBaseEntry.BuildChildren = function(self)
		for x = 1, #tBaseAuraRecipes do
			local tRecipe = tBaseAuraRecipes[x]
			local tNode = SkuOptions:InjectMenuItems(self, {tRecipe.label}, SkuGenericMenuItem)
			tNode.dynamic = true
			tNode.vocalizeAsIs = true
			tNode.OnEnter = function(self)
				tSetBaseTooltip(self, tRecipe)
			end
			tNode.BuildChildren = function(self)
				tBuildBaseRecipeForm(self, tRecipe)
			end
		end
	end

	local tCustomEntry = SkuOptions:InjectMenuItems(aLevel, {L["Eigene Aura erstellen"]}, SkuGenericMenuItem)
	tCustomEntry.dynamic = true
	tCustomEntry.id = AURA_DRAFT_ID
	tCustomEntry.BuildChildren = function(self)
		-- Entering the CREATE workbench while an EDIT draft is open starts a
		-- fresh one; an unfinished create draft is kept, so arrowing out and
		-- back in does not lose work.
		if SkuAuras.draft and SkuAuras.draft.editing then
			SkuAuras.draft = nil
		end
		SkuAuras:BuildDraftWorkbench(self)
	end
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
			-- [v43.1] "oder" or "und" between the values of one condition, from the
			-- group's operator - the aura NAME has to state the same reading the
			-- evaluator applies (see tValueJoinWord above).
			local tJoin = tValueJoinWord(tAttributeValue[1][1])
			for tInd, tLocalValue in pairs(tAttributeValue) do
				local tFname = tLocalValue[2]
				if SkuAuras.values[tLocalValue[2]] then
					tFname = SkuAuras.values[tLocalValue[2]].friendlyName
				end
				tFname = SkuAuras:RemoveTags(tFname)

				if tCount > 0 then
					tAuraName = tAuraName..tJoin..tFn(SkuAuras.attributes, tAttributeName)..";"..tFn(SkuAuras.Operators, tLocalValue[1])..";"..tFname..";"
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
function SkuAuras:BuildManageSubMenu(aParentEntry, aNewEntry)
	local tTypeItem = SkuOptions:InjectMenuItems(aParentEntry, aNewEntry, SkuGenericMenuItem)
	tTypeItem.dynamic = true
	tTypeItem.internalName = "action"
	tTypeItem.OnEnter = function(self)
		self.selectTarget.targetAuraName = self.name
		SkuAuras:BuildStoredAuraTooltip(self, self.name)
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
		-- [v43.1] Editing IS the workbench: same builder, same draft table, the
		-- only difference is that the save writes back under the old name
		-- instead of creating. The old per-keystroke path went with it - every
		-- ENTER in the old "Bedingungen"/"Ausgaben" sub-chains called
		-- SkuAuras:UpdateAura, which deleted and re-added the whole aura,
		-- re-derived its name and navigated away.
		local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Bearbeiten"]}, SkuGenericMenuItem)
		tNewMenuEntry.dynamic = true
		tNewMenuEntry.id = AURA_DRAFT_ID
		tNewMenuEntry.auraName = self.name
		tNewMenuEntry.OnEnter = function(self)
			if self.selectTarget then
				self.selectTarget.targetAuraName = self.parent.name
			end
		end
		tNewMenuEntry.BuildChildren = function(self)
			if not SkuAuras.draft or SkuAuras.draft.editing ~= self.auraName then
				SkuAuras:DraftNew(self.auraName)
			end
			SkuAuras:BuildDraftWorkbench(self)
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
			SkuAuras:BuildNewAuraMenu(self)
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