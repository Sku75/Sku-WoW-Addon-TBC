-- Uninterruptible enemy casts — data source for the "Nur unterbrechbare
-- Zauber ansagen" filter in SkuCore/aqCombat.lua.
--
-- The notInterruptible return of UnitCastingInfo/UnitChannelInfo is NEVER
-- populated on pre-Wrath clients (verified empirically on Anniversary 2.5.6,
-- 2026-07-26: nil on every cast while the 9th return delivered the correct
-- spellId; Blizzard's own CastingBarFrame force-falses the flag for <=BC).
-- A manual list is therefore the only data source on this client.
--
-- Entries derived from the ClassicCastbars addon
-- (https://github.com/wardz/ClassicCastbars, core/ClassicSpellData.lua,
-- MIT License, Copyright (C) Wardz) — Era-only entries dropped, TBC-gated
-- entries resolved for this client. To re-sync, diff against that file
-- upstream; it is small and changes rarely. NOTE upstream covers only
-- old-world (vanilla) content — there are no TBC dungeon/raid NPC entries
-- anywhere in the community yet. Add TBC findings to the SkuTbcAdditions
-- tables below (kept separate so upstream re-syncs stay a clean diff).
--
-- Key formats (identical to upstream):
--   spells:    [spellID] = true  OR  [localizedSpellName] = true
--              (name keys via GetSpellInfo for multi-rank/duplicate spells)
--   npcSpells: [npcID .. localizedSpellName] = true  (npcID as STRING)

local GetSpellInfo = _G.GetSpellInfo

SkuDB.uninterruptibleCasts = {}

SkuDB.uninterruptibleCasts.spells = {
	[34120] = true, -- Steady Shot (TBC)
	[19821] = true, -- Arcane Bomb
	[4068] = true, -- Iron Grenade
	[19769] = true, -- Thorium Grenade
	[13808] = true, -- M73 Frag Grenade
	[4069] = true, -- Big Iron Bomb
	[12543] = true, -- Hi-Explosive Bomb
	[4064] = true, -- Rough Copper Bomb
	[12421] = true, -- Mithril Frag Bomb
	[19784] = true, -- Dark Iron Bomb
	[4067] = true, -- Big Bronze Bomb
	[4066] = true, -- Small Bronze Bomb
	[4065] = true, -- Large Copper Bomb
	[4061] = true, -- Coarse Dynamite
	[4054] = true, -- Rough Dynamite
	[8331] = true, -- EZ-Thro Dynamite
	[23000] = true, -- EZ-Thro Dynamite II
	[4062] = true, -- Heavy Dynamite
	[23063] = true, -- Dense Dynamite
	[12419] = true, -- Solid Dynamite
	[13278] = true, -- Gnomish Death Ray
	[23041] = true, -- Call Anathema
	[20589] = true, -- Escape Artist
	[20549] = true, -- War Stomp
	[1510] = true, -- Volley
	[20904] = true, -- Aimed Shot
	[11605] = true, -- Slam
	[1804] = true, -- Pick Lock
	[1842] = true, -- Disarm Trap
	[2641] = true, -- Dismiss Pet
	[11202] = true, -- Crippling Poison
	[3421] = true, -- Crippling Poison II
	[2835] = true, -- Deadly Poison
	[2837] = true, -- Deadly Poison II
	[11355] = true, -- Deadly Poison III
	[11356] = true, -- Deadly Poison IV
	[25347] = true, -- Deadly Poison V
	[8681] = true, -- Instant Poison
	[8686] = true, -- Instant Poison II
	[8688] = true, -- Instant Poison III
	[11338] = true, -- Instant Poison IV
	[11339] = true, -- Instant Poison V
	[11343] = true, -- Instant Poison VI
	[5761] = true, -- Mind-numbing Poison
	[8693] = true, -- Mind-numbing Poison II
	[11399] = true, -- Mind-numbing Poison III
	[13220] = true, -- Wound Poison
	[13228] = true, -- Wound Poison II
	[13229] = true, -- Wound Poison III
	[13230] = true, -- Wound Poison IV
	[22999] = true, -- Defibrillate
	[746] = true, -- First Aid
	[20577] = true, -- Cannibalize
	[16075] = true, -- Throw Axe
	[6925] = true, -- Gift of the Xavian
	[4979] = true, -- Quick Flame Ward
	[4980] = true, -- Quick Frost Ward
	[8800] = true, -- Dynamite
	[7978] = true, -- Throw Dynamite
	[5106] = true, -- Crystal Flash
	[7279] = true, -- Black Sludge
	[13692] = true, -- Dire Growl
	[9612] = true, -- Ink Spray
	[22661] = true, -- Enervate
	[22421] = true, -- Massive Geyser
	[22662] = true, -- Wither
	[1050] = true, -- Sacrifice 1 (Non-English)
	[22651] = true, -- Sacrifice 2 (English)
	[22478] = true, -- Intense Pain
	[24189] = true, -- Force Punch
	[24314] = true, -- Threatening Gaze
	[24024] = true, -- Unstable Concoction
	[21188] = true, -- Stun Bomb Attack
	[22372] = true, -- Demon Portal
	[26102] = true, -- Sand Blast
	[25748] = true, -- Poison Stinger
	[21097] = true, -- Manastorm
	[785] = true, -- True Fulfillment
	[28615] = true, -- Spike Volley
	[28614] = true, -- Pointy Spike
	[28089] = true, -- Polarity Shift
	[28785] = true, -- Locust Swarm
	[18159] = true, -- Curse of the Fallen Magram
	[23511] = true, -- Demoralizing Shout
	[17238] = true, -- Drain Life
	[17243] = true, -- Drain Mana
	[17503] = true, -- Frostbolt
	[16869] = true, -- Ice Tomb
	[16788] = true, -- Fireball
	[16419] = true, -- Flamestrike
	[16390] = true, -- Flame Breath
	[13899] = true, -- Fire Storm
	[15668] = true, -- Fiery Burst
	[17235] = true, -- Raise Undead Scarab
	[4962] = true, -- Encasing Webs
	[16418] = true, -- Crypt Scarabs
	[18327] = true, -- Silence
	[7121] = true, -- Anti-Magic Shield

	-- Spells with duplicate versions/ranks, matched by localized name
	[GetSpellInfo(10436)] = true, -- Attack (Totems)
	[GetSpellInfo(8858)] = true, -- Bomb
	[GetSpellInfo(9483)] = true, -- Boulder
	[GetSpellInfo(14146)] = true, -- Clone
	[GetSpellInfo(16594)] = true, -- Crypt Scarabs
	[GetSpellInfo(8995)] = true, -- Shoot
	[GetSpellInfo(2764)] = true, -- Throw
	[GetSpellInfo(1510)] = true, -- Volley
	[GetSpellInfo(18431)] = true, -- Bellowing Roar
	[GetSpellInfo(18500)] = true, -- Wing Buffet
	[GetSpellInfo(22539)] = true, -- Shadow Flame
	[GetSpellInfo(16868)] = true, -- Banshee Wail
	[GetSpellInfo(22479)] = true, -- Frost Breath
	[GetSpellInfo(26103)] = true, -- Sweep
	[GetSpellInfo(30732)] = true, -- Worm Sweep
	[GetSpellInfo(15847)] = true, -- Tail Sweep
	[GetSpellInfo(7588)] = true, -- Void Bolt
	[GetSpellInfo(26381)] = true, -- Burrow
	[GetSpellInfo(27794)] = true, -- Cleave
	[GetSpellInfo(28995)] = true, -- Stoneskin
	[GetSpellInfo(28783)] = true, -- Impale
	[GetSpellInfo(7951)] = true, -- Toxic Spit
	[GetSpellInfo(7054)] = true, -- Forsaken Skills
	[GetSpellInfo(29121)] = true, -- Shoot Bow (TBC)
	[GetSpellInfo(33808)] = true, -- Shoot Gun (TBC)
}

SkuDB.uninterruptibleCasts.npcSpells = {
	["12264" .. GetSpellInfo(1449)] = true, -- Shazzrah Arcane Explosion
	["11983" .. GetSpellInfo(18500)] = true, -- Firemaw Wing Buffet
	["12265" .. GetSpellInfo(133)] = true, -- Lava Spawn Fireball
	["10438" .. GetSpellInfo(116)] = true, -- Maleki the Pallid Frostbolt
	["12465" .. GetSpellInfo(22425)] = true, -- Death Talon Wyrmkin Fireball Volley
	["14020" .. GetSpellInfo(23310)] = true, -- Chromaggus Time Lapse
	["14020" .. GetSpellInfo(23316)] = true, -- Chromaggus Ignite Flesh
	["14020" .. GetSpellInfo(23309)] = true, -- Chromaggus Incinerate
	["14020" .. GetSpellInfo(23187)] = true, -- Chromaggus Frost Burn
	["14020" .. GetSpellInfo(23314)] = true, -- Chromaggus Corrosive Acid
	["12468" .. GetSpellInfo(2120)] = true, -- Death Talon Hatcher Flamestrike
	["13020" .. GetSpellInfo(9573)] = true, -- Vaelastrasz the Corrupt Flame Breath
	["12435" .. GetSpellInfo(22425)] = true, -- Razorgore the Untamed Fireball Volley
	["12118" .. GetSpellInfo(20604)] = true, -- Lucifron Dominate Mind
	["10184" .. GetSpellInfo(9573)] = true, -- Onyxia Flame Breath
	["10184" .. GetSpellInfo(133)] = true, -- Onyxia Fireball
	["11492" .. GetSpellInfo(9616)] = true, -- Alzzin the Wildshaper Wild Regeneration
	["11359" .. GetSpellInfo(16430)] = true, -- Soulflayer Soul Tap
	["11372" .. GetSpellInfo(24011)] = true, -- Razzashi Adder Venom Spit
	["14834" .. GetSpellInfo(24322)] = true, -- Hakkar Blood Siphon
	["12259" .. GetSpellInfo(686)] = true, -- Gehennas Shadow Bolt
	["14507" .. GetSpellInfo(14914)] = true, -- High Priest Venoxis Holy Fire
	["12119" .. GetSpellInfo(20604)] = true, -- Flamewaker Protector Dominate Mind
	["12557" .. GetSpellInfo(14515)] = true, -- Grethok the Controller Dominate Mind
	["15276" .. GetSpellInfo(26006)] = true, -- Emperor Vek'lor Shadow Bolt
	["12397" .. GetSpellInfo(15245)] = true, -- Lord Kazzak Shadow Bolt Volley
	["14887" .. GetSpellInfo(16247)] = true, -- Ysondre Curse of Thorns
	["15246" .. GetSpellInfo(11981)] = true, -- Qiraji Mindslayer Mana Burn
	["15246" .. GetSpellInfo(17194)] = true, -- Qiraji Mindslayer Mind Blast
	["15246" .. GetSpellInfo(22919)] = true, -- Qiraji Mindslayer Mind Flay
	["15311" .. GetSpellInfo(26069)] = true, -- Anubisath Warder Silence
	["15311" .. GetSpellInfo(11922)] = true, -- Anubisath Warder Entangling Roots
	["15311" .. GetSpellInfo(12542)] = true, -- Anubisath Warder Fear
	["15311" .. GetSpellInfo(26072)] = true, -- Anubisath Warder Dust Cloud
	["15335" .. GetSpellInfo(21067)] = true, -- Flesh Hunter Poison Bolt
	["15247" .. GetSpellInfo(11981)] = true, -- Qiraji Brainwasher Mana Burn
	["15247" .. GetSpellInfo(16568)] = true, -- Qiraji Brainwasher Mind Flay
	["11729" .. GetSpellInfo(19452)] = true, -- Hive'Zora Hive Sister Toxic Spit
	["16146" .. GetSpellInfo(17473)] = true, -- Death Knight Raise Dead
	["16368" .. GetSpellInfo(9081)] = true, -- Necropolis Acolyte Shadow Bolt Volley
	["16022" .. GetSpellInfo(16568)] = true, -- Surgical Assistant Mind Flay
	["8519" .. GetSpellInfo(16554)] = true, -- Blighted Surge Toxic Bolt
	["4543" .. GetSpellInfo(9613)] = true, -- Bloodmage Thalnos Shadow Bolt
	["4543" .. GetSpellInfo(8814)] = true, -- Bloodmage Thalnos Flame Spike
	["3977" .. GetSpellInfo(9481)] = true, -- High Inquisitor Whitemane Holy Smite
	["3977" .. GetSpellInfo(12039)] = true, -- High Inquisitor Whitemane Heal
	["3977" .. GetSpellInfo(9232)] = true, -- High Inquisitor Whitemane Scarlet Resurrection
	["7358" .. GetSpellInfo(15530)] = true, -- Amnennar the Coldbringer Frostbolt
	["11487" .. GetSpellInfo(7645)] = true, -- Magister Kalendris Dominate Mind
	["11487" .. GetSpellInfo(15407)] = true, -- Magister Kalendris Mind Flay
	["1853" .. GetSpellInfo(18702)] = true, -- Darkmaster Gandling Curse of the Darkmaster
	["1853" .. GetSpellInfo(5143)] = true, -- Darkmaster Gandling Arcane Missiles
	["10502" .. GetSpellInfo(14515)] = true, -- Lady Illucia Barov Dominate Mind
	["10502" .. GetSpellInfo(12528)] = true, -- Lady Illucia Barov Silence
	["10502" .. GetSpellInfo(12542)] = true, -- Lady Illucia Barov Fear
	["10440" .. GetSpellInfo(17393)] = true, -- Baron Rivendare Shadow Bolt
	["9029" .. GetSpellInfo(15245)] = true, -- Eviscerator Shadow Bolt Volley
	["8983" .. GetSpellInfo(15305)] = true, -- Golem Lord Argelmach Chain Lightning
	["15589" .. GetSpellInfo(26134)] = true, -- Eye of C'thun Eye Beam
	["15727" .. GetSpellInfo(26134)] = true, -- C'thun Eye Beam
}

-- TBC content additions (NOT from upstream — collected by the Sku project).
-- Merge target for anything learned in Anniversary TBC dungeons/raids.
local SkuTbcAdditionsSpells = {
}
local SkuTbcAdditionsNpcSpells = {
}

for k, v in pairs(SkuTbcAdditionsSpells) do
	SkuDB.uninterruptibleCasts.spells[k] = v
end
for k, v in pairs(SkuTbcAdditionsNpcSpells) do
	SkuDB.uninterruptibleCasts.npcSpells[k] = v
end
