---------------------------------------------------------------------------------------------------------------------------------------
-- Pet health by key (SKU_KEY_PETHEALTH, no default key, set in the key menu; dispatched in SkuZOptions/Core.lua like
-- SKU_KEY_TARGETHEALTH, so it also works in combat). Spoken as "Pet <percent>", rounded up like Blizzard's combat audio
-- alerts (CombatAudioAlertManagerMixin:GetUnitHealthPercent: math.ceil): a living pet is never "0".
-- On WoW Forever the pet's health is a secret value: Sku cannot read, compare or calculate with it, only hand it to the
-- speech output (SkuVoice:SpeakSecretText). The rounding then comes from a curve, the only arithmetic allowed on a secret.
---------------------------------------------------------------------------------------------------------------------------------------
local L = Sku.L

-- [0, 1] -> [0.999, 100.999]; "%d" cuts the fraction, so this is math.ceil of the percentage (a dead pet stays 0, 0.4 % becomes 1).
local tCeilTo100

function SkuCore:SpeakPetHealth()
	if not UnitExists("pet") then
		SkuOptions.Voice:OutputStringBTtts(L["No pet"], true, true, 0.2)
		return
	end
	local tMax = UnitHealthMax("pet")
	local tHealth = UnitHealth("pet")
	-- Either value can be secret on its own: the max can be readable while the current health is not.
	if Sku.IsSecret(tMax) or Sku.IsSecret(tHealth) then
		if not tCeilTo100 then
			tCeilTo100 = C_CurveUtil.CreateCurve()
			tCeilTo100:SetType(Enum.LuaCurveType.Linear)
			tCeilTo100:AddPoint(0.0, 0.999)
			tCeilTo100:AddPoint(1.0, 100.999)
		end
		SkuOptions.Voice:SpeakSecretText(L["Pet %d"], UnitHealthPercent("pet", true, tCeilTo100))
		return
	end
	local tPercent = tMax > 0 and math.ceil(tHealth / tMax * 100) or 0
	SkuOptions.Voice:OutputStringBTtts(string.format(L["Pet %d"], tPercent), true, true, 0.2)
end
