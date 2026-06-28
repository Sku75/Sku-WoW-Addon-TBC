"""Upgrade the W2-MC1 engine to thread a dotted key prefix so NESTED option
groups are schema-managed by their full storage path (module.group.leaf)."""
import sys
P = r"C:/Users/fabia/Dev/Sku-TBC-42/Sku/SkuZOptions/Core.lua"
s = open(P, encoding="utf-8-sig").read()

def repl(old, new, n_expected):
    c = s.count(old)
    assert c == n_expected, "expected %d got %d for: %r" % (n_expected, c, old[:60])
    return s.replace(old, new)

# 1) signature: add aKeyPrefix
s = repl(
 "function SkuOptions:IterateOptionsArgs(aArgTable, aParentMenu, tProfileParentPath, aModule)",
 "function SkuOptions:IterateOptionsArgs(aArgTable, aParentMenu, tProfileParentPath, aModule, aKeyPrefix)",
 1)

# 2) recursion into a group: extend the key prefix with this group's key
s = repl(
 "\t\t\tSkuOptions:IterateOptionsArgs(v.args, tParentMenu, tProfileParentPath[i], aModule)",
 "\t\t\tSkuOptions:IterateOptionsArgs(v.args, tParentMenu, tProfileParentPath[i], aModule, (aKeyPrefix or \"\") .. tostring(i) .. \".\")",
 1)

# 3) record the full dotted storage key on every leaf (toggle/select/range share the flag block)
s = repl(
 "\t\t\t\ttNewMenuEntry.skuModule = aModule\n"
 "\t\t\t\ttNewMenuEntry.skuManaged = (v.get == nil and v.set == nil and aModule ~= nil)",
 "\t\t\t\ttNewMenuEntry.skuModule = aModule\n"
 "\t\t\t\ttNewMenuEntry.skuKey = (aKeyPrefix or \"\") .. tostring(i)\n"
 "\t\t\t\ttNewMenuEntry.skuManaged = (v.get == nil and v.set == nil and aModule ~= nil)",
 3)

# 4) managed storage now keys off the full dotted skuKey, not the leaf-only profileIndex
s = repl("SkuSettings:Get(self.skuModule, self.profileIndex)",
         "SkuSettings:Get(self.skuModule, self.skuKey)", 3)
s = repl("SkuSettings:Set(self.skuModule, self.profileIndex,",
         "SkuSettings:Set(self.skuModule, self.skuKey,", 3)

open(P, "w", encoding="utf-8-sig", newline="").write(s)
print("OK dotted-key engine upgrade applied")
