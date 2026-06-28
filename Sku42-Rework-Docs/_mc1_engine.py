"""W2-MC1 engine patch: schema-managed get/set fallback in IterateOptionsArgs.
Idempotent-ish: asserts each replacement hits exactly once."""
import io, sys

P = r"C:/Users/fabia/Dev/Sku-TBC-42/Sku/SkuZOptions/Core.lua"
s = open(P, encoding="utf-8-sig").read()

reps = []

# --- TOGGLE: write logic + flags
reps.append((
"\t\t\t\ttNewMenuEntry.isSelect = true\n"
"\t\t\t\ttNewMenuEntry.OnAction = function(self, aValue, aName)\n"
"\t\t\t\t\tif aName == L[\"On\"] then\n"
"\t\t\t\t\t\tself.profilePath[self.profileIndex] = true\n"
"\t\t\t\t\telseif aName == L[\"Off\"] then\n"
"\t\t\t\t\t\tself.profilePath[self.profileIndex] = false\n"
"\t\t\t\t\tend",
"\t\t\t\ttNewMenuEntry.isSelect = true\n"
"\t\t\t\ttNewMenuEntry.skuModule = aModule\n"
"\t\t\t\ttNewMenuEntry.skuManaged = (v.get == nil and v.set == nil and aModule ~= nil)\n"
"\t\t\t\ttNewMenuEntry.OnAction = function(self, aValue, aName)\n"
"\t\t\t\t\tlocal tNewToggleValue\n"
"\t\t\t\t\tif aName == L[\"On\"] then\n"
"\t\t\t\t\t\ttNewToggleValue = true\n"
"\t\t\t\t\telseif aName == L[\"Off\"] then\n"
"\t\t\t\t\t\ttNewToggleValue = false\n"
"\t\t\t\t\tend\n"
"\t\t\t\t\tif tNewToggleValue ~= nil then\n"
"\t\t\t\t\t\tif self.skuManaged then\n"
"\t\t\t\t\t\t\tSkuSettings:Set(self.skuModule, self.profileIndex, tNewToggleValue)\n"
"\t\t\t\t\t\telse\n"
"\t\t\t\t\t\t\tself.profilePath[self.profileIndex] = tNewToggleValue\n"
"\t\t\t\t\t\tend\n"
"\t\t\t\t\tend",
))

# --- TOGGLE: GetCurrentValue read
reps.append((
"\t\t\t\ttNewMenuEntry.GetCurrentValue = function(self, aValue, aName)\n"
"\t\t\t\t\tlocal tValue = L[\"On\"]\n"
"\t\t\t\t\t--if self.profilePath[self.profileIndex] == true then\n"
"\t\t\t\t\tif self.optionsPath[self.profileIndex]:get() == true then\n"
"\t\t\t\t\t\ttValue = L[\"On\"]\n"
"\t\t\t\t\telse\n"
"\t\t\t\t\t\ttValue = L[\"Off\"]\n"
"\t\t\t\t\tend\n"
"\t\t\t\t\treturn tValue\n"
"\t\t\t\tend",
"\t\t\t\ttNewMenuEntry.GetCurrentValue = function(self, aValue, aName)\n"
"\t\t\t\t\tlocal tStored\n"
"\t\t\t\t\tif self.skuManaged then\n"
"\t\t\t\t\t\ttStored = SkuSettings:Get(self.skuModule, self.profileIndex)\n"
"\t\t\t\t\telse\n"
"\t\t\t\t\t\ttStored = self.optionsPath[self.profileIndex]:get()\n"
"\t\t\t\t\tend\n"
"\t\t\t\t\tif tStored == true then\n"
"\t\t\t\t\t\treturn L[\"On\"]\n"
"\t\t\t\t\telse\n"
"\t\t\t\t\t\treturn L[\"Off\"]\n"
"\t\t\t\t\tend\n"
"\t\t\t\tend",
))

# --- SELECT: flags + write inside values loop
reps.append((
"\t\t\t\ttNewMenuEntry.OnAction = function(self, aValue, aName)\n"
"\t\t\t\t\tfor ia, va in pairs(v.values) do\n"
"\t\t\t\t\t\tif va == aName or va == L[\"sound\"]..\"#\"..aName or va == L[\"aura;sound\"]..\"#\"..aName then\n"
"\t\t\t\t\t\t\tself.profilePath[self.profileIndex] = ia\n"
"\t\t\t\t\t\tend\n"
"\t\t\t\t\tend",
"\t\t\t\ttNewMenuEntry.skuModule = aModule\n"
"\t\t\t\ttNewMenuEntry.skuManaged = (v.get == nil and v.set == nil and aModule ~= nil)\n"
"\t\t\t\ttNewMenuEntry.OnAction = function(self, aValue, aName)\n"
"\t\t\t\t\tfor ia, va in pairs(v.values) do\n"
"\t\t\t\t\t\tif va == aName or va == L[\"sound\"]..\"#\"..aName or va == L[\"aura;sound\"]..\"#\"..aName then\n"
"\t\t\t\t\t\t\tif self.skuManaged then\n"
"\t\t\t\t\t\t\t\tSkuSettings:Set(self.skuModule, self.profileIndex, ia)\n"
"\t\t\t\t\t\t\telse\n"
"\t\t\t\t\t\t\t\tself.profilePath[self.profileIndex] = ia\n"
"\t\t\t\t\t\t\tend\n"
"\t\t\t\t\t\tend\n"
"\t\t\t\t\tend",
))

# --- SELECT: GetCurrentValue read
reps.append((
"\t\t\t\ttNewMenuEntry.GetCurrentValue = function(self, aValue, aName)\n"
"\t\t\t\t\tlocal tValue = \"\"\n"
"\t\t\t\t\tfor ia, va in pairs(v.values) do\n"
"\t\t\t\t\t\t--if ia == self.profilePath[self.profileIndex] then\n"
"\t\t\t\t\t\tif ia == self.optionsPath[self.profileIndex]:get() then\n"
"\t\t\t\t\t\t\ttValue = va\n"
"\t\t\t\t\t\tend\n"
"\t\t\t\t\tend\n"
"\t\t\t\t\treturn tValue\n"
"\t\t\t\tend",
"\t\t\t\ttNewMenuEntry.GetCurrentValue = function(self, aValue, aName)\n"
"\t\t\t\t\tlocal tValue = \"\"\n"
"\t\t\t\t\tlocal tStored\n"
"\t\t\t\t\tif self.skuManaged then\n"
"\t\t\t\t\t\ttStored = SkuSettings:Get(self.skuModule, self.profileIndex)\n"
"\t\t\t\t\telse\n"
"\t\t\t\t\t\ttStored = self.optionsPath[self.profileIndex]:get()\n"
"\t\t\t\t\tend\n"
"\t\t\t\t\tfor ia, va in pairs(v.values) do\n"
"\t\t\t\t\t\tif ia == tStored then\n"
"\t\t\t\t\t\t\ttValue = va\n"
"\t\t\t\t\t\tend\n"
"\t\t\t\t\tend\n"
"\t\t\t\t\treturn tValue\n"
"\t\t\t\tend",
))

# --- RANGE: flags + write
reps.append((
"\t\t\t\ttNewMenuEntry.rangeMax = v.max or 100\n"
"\t\t\t\ttNewMenuEntry.OnAction = function(self, aValue, aName)\n"
"\t\t\t\t\t--self.profilePath[self.profileIndex] = tonumber(aName)\n"
"\t\t\t\t\tself.optionsPath[self.profileIndex]:set(tonumber(aName))",
"\t\t\t\ttNewMenuEntry.rangeMax = v.max or 100\n"
"\t\t\t\ttNewMenuEntry.skuModule = aModule\n"
"\t\t\t\ttNewMenuEntry.skuManaged = (v.get == nil and v.set == nil and aModule ~= nil)\n"
"\t\t\t\ttNewMenuEntry.OnAction = function(self, aValue, aName)\n"
"\t\t\t\t\t--self.profilePath[self.profileIndex] = tonumber(aName)\n"
"\t\t\t\t\tif self.skuManaged then\n"
"\t\t\t\t\t\tSkuSettings:Set(self.skuModule, self.profileIndex, tonumber(aName))\n"
"\t\t\t\t\telse\n"
"\t\t\t\t\t\tself.optionsPath[self.profileIndex]:set(tonumber(aName))\n"
"\t\t\t\t\tend",
))

# --- RANGE: GetCurrentValue read
reps.append((
"\t\t\t\ttNewMenuEntry.GetCurrentValue = function(self, aValue, aName)\n"
"\t\t\t\t\treturn self.optionsPath[self.profileIndex]:get()\n"
"\t\t\t\t\t--return self.profilePath[self.profileIndex]\n"
"\t\t\t\tend",
"\t\t\t\ttNewMenuEntry.GetCurrentValue = function(self, aValue, aName)\n"
"\t\t\t\t\tif self.skuManaged then\n"
"\t\t\t\t\t\treturn SkuSettings:Get(self.skuModule, self.profileIndex)\n"
"\t\t\t\t\tend\n"
"\t\t\t\t\treturn self.optionsPath[self.profileIndex]:get()\n"
"\t\t\t\t\t--return self.profilePath[self.profileIndex]\n"
"\t\t\t\tend",
))

for idx, (old, new) in enumerate(reps):
    c = s.count(old)
    if c != 1:
        print("FAIL rep #%d matched %d times" % (idx, c)); sys.exit(1)
    s = s.replace(old, new)

open(P, "w", encoding="utf-8-sig", newline="").write(s)
print("OK all %d replacements applied" % len(reps))
