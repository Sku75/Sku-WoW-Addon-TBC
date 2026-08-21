local objectKeys = {
    ['name'] = 1, -- string
    ['questStarts'] = 2, -- table {questID(int),...}
    ['questEnds'] = 3, -- table {questID(int),...}
    ['spawns'] = 4, -- table {[zoneID(int)] = {coordPair(floatVector2D),...},...}
    ['zoneID'] = 5, -- guess as to where this object is most common
    ['factionID'] = 6, -- faction restriction mask (same as spawndb factionid)
}
local zoneIDs = SkuDB.zoneIDs

local SkuObjectsFixes = {

}
function SkuDB:SoDFixObjectsDB(aTargetTable)
    SkuDB:FixObjectsDB(aTargetTable)
    for i, v in pairs(SkuObjectsFixes) do
        local tNew = false
        for k, val in pairs(v) do
            if aTargetTable.objectDataTBC[i] then
                aTargetTable.objectDataTBC[i][k] = val
            else
                aTargetTable.objectDataTBC[i] = v
                tNew = true
            end
        end
        if tNew == true then
            aTargetTable.objectLookup["deDE"][i] = aTargetTable.objectDataTBC[i][objectKeys.name]
            aTargetTable.objectLookup["enUS"][i] = aTargetTable.objectDataTBC[i][objectKeys.name]
        end

    end
end