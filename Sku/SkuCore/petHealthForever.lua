---------------------------------------------------------------------------------------------------------------------------------------
-- Pet health by key on WoW Forever.
-- On Forever UnitHealthPercent("pet") returns a secret number: Sku cannot read, compare or calculate with it. It can,
-- however, hand it to the speech output, which accepts secret text (C_VoiceChat.SpeakText, documented as
-- SecretArguments = "AllowedWhenTainted"). SkuVoice:SpeakSecretText does that without ever looking at the text.
-- The key is SKU_KEY_PETHEALTH (no default key, set in the key menu); it is dispatched in SkuZOptions/Core.lua like
-- SKU_KEY_TARGETHEALTH and also works in combat.
---------------------------------------------------------------------------------------------------------------------------------------
if not Sku.isForever then return end

local L = Sku.L

function SkuCore:SpeakPetHealth()
	if not UnitExists("pet") then
		SkuOptions.Voice:OutputStringBTtts(L["No pet"], true, true, 0.2)
		return
	end
	SkuOptions.Voice:SpeakSecretText(L["Pet health: %d percent"], UnitHealthPercent("pet", true, CurveConstants.ScaleTo100))
end
