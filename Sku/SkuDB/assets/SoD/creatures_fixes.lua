local npcKeys = {
    ['name'] = 1, -- string
    ['minLevelHealth'] = 2, -- int
    ['maxLevelHealth'] = 3, -- int
    ['minLevel'] = 4, -- int
    ['maxLevel'] = 5, -- int
    ['rank'] = 6, -- int, see https://github.com/cmangos/issues/wiki/creature_template#rank
    ['spawns'] = 7, -- table {[zoneID(int)] = {coordPair(floatVector2D),...},...}
    ['waypoints'] = 8, -- table {[zoneID(int)] = {coordPair(floatVector2D),...},...}
    ['zoneID'] = 9, -- guess as to where this NPC is most common
    ['questStarts'] = 10, -- table {questID(int),...}
    ['questEnds'] = 11, -- table {questID(int),...}
    ['factionID'] = 12, -- int, see https://github.com/cmangos/issues/wiki/FactionTemplate.dbc
    ['friendlyToFaction'] = 13, -- string, Contains "A" and/or "H" depending on NPC being friendly towards those factions. nil if hostile to both.
    ['subName'] = 14, -- string, The title or function of the NPC, e.g. "Weapon Vendor"
    ['npcFlags'] = 15, -- int, Bitmask containing various flags about the NPCs function (Vendor, Trainer, Flight Master, etc.).
                        -- For flag values see https://github.com/cmangos/mangos-classic/blob/172c005b0a69e342e908f4589b24a6f18246c95e/src/game/Entities/Unit.h#L536
}
local zoneIDs = SkuDB.zoneIDs
local npcFlags = {
    NONE = 0,
    GOSSIP = 1,
    QUEST_GIVER = 2,
    TRAINER = 16,
    VENDOR = 128,
    REPAIR = 4096,
    FLIGHT_MASTER = 8192,
    SPIRIT_HEALER = 16384,
    SPIRIT_GUIDE = 32768,
    INNKEEPER = 65536,
    BANKER = 131072,
    PETITIONER = 262144,
    TABARD_DESIGNER = 524288,
    BATTLEMASTER = 1048576,
    AUCTIONEER = 2097152,
    STABLEMASTER = 4194304,
}

local SkuCreaturesFixes = {

}

    
function SkuDB:SoDFixCreaturesDB(aTargetTable)
  for i, v in pairs(SkuCreaturesFixes) do
    for k, val in pairs(v) do
      if aTargetTable.NpcData.Data[i] then
        aTargetTable.NpcData.Data[i][k] = val
      else
        aTargetTable.NpcData.Data[i] = v
      end
    end
  end
end