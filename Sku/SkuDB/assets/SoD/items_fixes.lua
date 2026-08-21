
    local itemKeys = {
        ['name'] = 1, -- string
        ['npcDrops'] = 2, -- table or nil, NPC IDs
        ['objectDrops'] = 3, -- table or nil, object IDs
        ['itemDrops'] = 4, -- table or nil, item IDs
        ['startQuest'] = 5, -- int or nil, ID of the quest started by this item
        ['questRewards'] = 6, -- table or nil, quest IDs
        ['flags'] = 7, -- int or nil, see: https://github.com/cmangos/issues/wiki/Item_template#flags
        ['foodType'] = 8, -- int or nil, see https://github.com/cmangos/issues/wiki/Item_template#foodtype
        ['itemLevel'] = 9, -- int, the level of this item
        ['requiredLevel'] = 10, -- int, the level required to equip/use this item
        ['ammoType'] = 11, -- int,
        ['class'] = 12, -- int,
        ['subClass'] = 13, -- int,
        ['vendors'] = 14, -- table or nil, NPC IDs
        ['relatedQuests'] = 15, -- table or nil, IDs of quests that are related to this item
    }

    local SkuItemFixes = {

    }

function SkuDB:SoDFixItemDB(aTargetTable)
    SkuDB:FixItemDB(aTargetTable)
    for i, v in pairs(SkuItemFixes) do
        local tNew = false
        for k, val in pairs(v) do
            if aTargetTable.itemDataTBC[i] then
                aTargetTable.itemDataTBC[i][k] = val
            else
                aTargetTable.itemDataTBC[i] = v
                tNew = true
            end
        end
        if tNew == true then
            aTargetTable.itemLookup["deDE"][i] = aTargetTable.itemDataTBC[i][itemKeys.name]
            aTargetTable.itemLookup["enUS"][i] = aTargetTable.itemDataTBC[i][itemKeys.name]
        end

    end
end