import sys
P = r"C:/Users/fabia/Dev/Sku-TBC-42/Sku/SkuMob/Options.lua"
lines = open(P, encoding="utf-8-sig").read().split("\n")

# sanity: line 8 is the table head, line 94 the closing brace
assert lines[7].strip() == "SkuMob.options = {", lines[7]
assert lines[93].strip() == "}", lines[93]

new = '''SkuMob.options = {
\tname = MODULE_NAME,
\ttype = "group",
\t-- W2-MC1: per-key storage get/set removed — these nodes are schema-managed.
\t-- The menu reads/writes via SkuSettings:Get/Set("SkuMob", key); scope/type/
\t-- default come from the SkuSettings:Register schema below. Re-add get/set on a
\t-- node ONLY if it needs a side effect (it then uses the inline handler again).
\targs = {
\t\tvocalizeRaidTargetOnly = {
\t\t\tname = L["Only raid icon for targets with icon"],
\t\t\tdesc = "",
\t\t\ttype = "toggle",
\t\t},
\t\tdontVocalizePlayerReactionAndLevelInCombat  = {
\t\t\tname = L["Don't vocalize reaction and level for players in combat"],
\t\t\torder = 2,
\t\t\tdesc = "",
\t\t\ttype = "toggle",
\t\t},
\t\tvocalizePlayerNamePlaceholders  = {
\t\t\tname = L["Announce friendly and hostile players"],
\t\t\tdesc = "",
\t\t\ttype = "toggle",
\t\t},
\t\tvocalizePlayerNamePlaceholdersSkuTts = {
\t\t\tname = L["Announce player controled units with generic descriptions"],
\t\t\tdesc = "",
\t\t\ttype = "toggle",
\t\t},
\t\trepeatRaidTargetMarkers = {
\t\t\tname = L["Repeat raid target markers on units"],
\t\t\tdesc = "",
\t\t\ttype = "toggle",
\t\t},
\t\tautoSetSkuRaidTargetsToInCombatCreatures = {
\t\t\tname = L["Auto set private Sku raid targets on in combat targets without a raid target"],
\t\t\torder = 6,
\t\t\tdesc = "",
\t\t\ttype = "toggle",
\t\t},
\t\tInCombatSound={
\t\t\tname = L["Sound if target is in combat"],
\t\t\torder = 7,
\t\t\tdesc = "",
\t\t\ttype = "select",
\t\t\tvalues = SkuMob.InCombatSounds,
\t\t},
\t}
}'''.split("\n")

out = lines[:7] + new + lines[94:]
open(P, "w", encoding="utf-8-sig", newline="").write("\n".join(out))
print("OK SkuMob options rewritten (%d -> %d lines)" % (len(lines), len(out)))
