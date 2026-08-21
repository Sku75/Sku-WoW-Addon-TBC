local questKeys = SkuDB.questKeys
local raceIDs = SkuDB.raceKeys
local classIDs = SkuDB.classKeys
local zoneIDs = SkuDB.zoneIDs
local sortKeys = {
    SEASONAL = -22,
    HERBALISM = -24,
    BATTLEGROUND = -25,
    WARLOCK = -61,
    WARRIOR = -81,
    SHAMAN = -82,
    FISHING = -101,
    BLACKSMITHING = -121,
    PALADIN = -141,
    MAGE = -161,
    ROGUE = -162,
    ALCHEMY = -181,
    LEATHERWORKING = -182,
    ENGINEERING = -201,
    HUNTER = -261,
    PRIEST = -262,
    DRUID = -263,
    TAILORING = -264,
    SPECIAL = -284,
    COOKING = -304,
    FIRST_AID = -324,
    DARKMOON_FAIRE = -364,
    LUNAR_FESTIVAL = -366,
    REPUTATION = -367,
    MIDSUMMER = -369,
    BREWFEST = -370,
}

local ICON_TYPE_COMPLETE = ""
local ICON_TYPE_EVENT = ""
local ICON_TYPE_GLOW = ""
local ICON_TYPE_LOOT = ""
local ICON_TYPE_OBJECT = ""
local ICON_TYPE_SLAY = ""
local ICON_TYPE_AVAILABLE = ""
local ICON_TYPE_AVAILABLE_GRAY = ""
local ICON_TYPE_REPEATABLE = ""

local SkuQuestFixes = {

}

local SkuQuestFixesHorde = {
}

local SkuQuestFixesAlliance = {
}

------------------------------------------------------------------------------------------------------------------------------------------------------------
local SkuQuestFixesSKU = {

}

------------------------------------------------------------------------------------------------------------------------------------------------------------
function SkuDB:SoDFixQuestDB(aTargetTable)
    SkuDB:FixQuestDB(aTargetTable)
    for i, v in pairs(SkuQuestFixes) do
        local tNew = false
        for k, val in pairs(v) do
            if aTargetTable.questDataTBC[i] then
                aTargetTable.questDataTBC[i][k] = val
            else
                aTargetTable.questDataTBC[i] = v    
                tNew = true
            end
        end
        if tNew == true then
            aTargetTable.questLookup["deDE"][i] = {aTargetTable.questDataTBC[i][questKeys.name], nil, aTargetTable.questDataTBC[i][questKeys.objectivesText],}
            aTargetTable.questLookup["enUS"][i] = {aTargetTable.questDataTBC[i][questKeys.name], nil, aTargetTable.questDataTBC[i][questKeys.objectivesText],}
        end
    end
    --[[
    for i, v in pairs(SkuQuestFixesHorde) do
        local tNew = false
        for k, val in pairs(v) do
            if aTargetTable.questDataTBC[i] then
                aTargetTable.questDataTBC[i][k] = val
            else
                aTargetTable.questDataTBC[i] = v         
                tNew = true
            end
        end
        if tNew == true then
            aTargetTable.questLookup["deDE"][i] = {aTargetTable.questDataTBC[i][questKeys.name], nil, aTargetTable.questDataTBC[i][questKeys.objectivesText],}
            aTargetTable.questLookup["enUS"][i] = {aTargetTable.questDataTBC[i][questKeys.name], nil, aTargetTable.questDataTBC[i][questKeys.objectivesText],}
        end
    end
    for i, v in pairs(SkuQuestFixesAlliance) do
        local tNew = false
        for k, val in pairs(v) do
            if aTargetTable.questDataTBC[i] then
                aTargetTable.questDataTBC[i][k] = val
            else
                aTargetTable.questDataTBC[i] = v         
                tNew = true
            end
        end
        if tNew == true then
            aTargetTable.questLookup["deDE"][i] = {aTargetTable.questDataTBC[i][questKeys.name], nil, aTargetTable.questDataTBC[i][questKeys.objectivesText],}
            aTargetTable.questLookup["enUS"][i] = {aTargetTable.questDataTBC[i][questKeys.name], nil, aTargetTable.questDataTBC[i][questKeys.objectivesText],}
        end        
    end
    ]]
    for i, v in pairs(SkuQuestFixesSKU) do
        local tNew = false
        for k, val in pairs(v) do
            if aTargetTable.questDataTBC[i] then
                aTargetTable.questDataTBC[i][k] = val
            else
                aTargetTable.questDataTBC[i] = v         
                tNew = true
            end
        end
        if tNew == true then
            aTargetTable.questLookup["deDE"][i] = {aTargetTable.questDataTBC[i][questKeys.name], nil, aTargetTable.questDataTBC[i][questKeys.objectivesText],}
            aTargetTable.questLookup["enUS"][i] = {aTargetTable.questDataTBC[i][questKeys.name], nil, aTargetTable.questDataTBC[i][questKeys.objectivesText],}
        end        
    end
end