local MODULE_NAME = "SkuAuras"
local _G = _G
local L = Sku.L

local tonumber = tonumber
local sgsub = string.gsub
local supper = string.upper
local sfind = string.find
local ssplit = string.split

------------------------------------------------------------------------------------------------------------------
local function KeyValuesHelper()
   local tKeys = {
      "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "Ä", "Ö", "Ü", 
      "1", "2", "3", "4", "5", "6", "7", "8", "9", "0",
      "BACKSPACE", "BACKSPACE_MAC", "DELETE", "DELETE_MAC", "DOWN", "END", "ENTER", "ENTER_MAC", "ESCAPE", "HOME", 
      "INSERT", "INSERT_MAC", "LEFT", "NUMLOCK", "NUMLOCK_MAC", "NUMPAD0", "NUMPAD1", "NUMPAD2", "NUMPAD3", "NUMPAD4", 
      "NUMPAD5", "NUMPAD6", "NUMPAD7", "NUMPAD8", "NUMPAD9", "NUMPADDECIMAL", "NUMPADDIVIDE", "NUMPADMINUS", "NUMPADMULTIPLY", 
      "NUMPADPLUS", "PAGEDOWN", "PAGEUP", "PAUSE", "PAUSE_MAC", "PRINTSCREEN", "PRINTSCREEN_MAC", "RIGHT", "SCROLLLOCK", 
      "SCROLLLOCK_MAC", "SPACE", "TAB", "TILDE", "'", "%+", "´", ",", "#",
      "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12",
   }

   local tModifiers = {"CTRL-", "SHIFT-", "ALT-", "CTRL-SHIFT-", "CTRL-ALT-", "SHIFT-ALT-", }
   local tResultTable = {}

   for x = 1, #tKeys do
      if SkuCore.Keys.LocNames[supper(tKeys[x])] then
         tResultTable[tKeys[x]] = SkuCore.Keys.LocNames[supper(tKeys[x])]
      else
         tResultTable[tKeys[x]] = tKeys[x]
      end
   end

   for y = 1, #tModifiers do
      local tLocModifier = sgsub(tModifiers[y], "CTRL", SkuCore.Keys.LocNames["CTRL"])
      for x = 1, #tKeys do
         if SkuCore.Keys.LocNames[supper(tKeys[x])] then
            tResultTable[tModifiers[y]..tKeys[x]] = tLocModifier..SkuCore.Keys.LocNames[supper(tKeys[x])]
         else
            tResultTable[tModifiers[y]..tKeys[x]] = tLocModifier..tKeys[x]
         end
      end
   end
   return tResultTable
end

------------------------------------------------------------------------------------------------------------------
function SkuAuras:RemoveTags(aValue)
   if type(aValue) ~= "string" then
      return aValue
   end
   -- [v43.0] "spellgroup:" is stripped FIRST. It does not contain the literal
   -- "spell:" so the order is not load-bearing, but a stored group value that
   -- reached a friendlyName miss would otherwise be read out to the user
   -- verbatim as "spellgroup:Frostbolt".
   local tCleanValue = sgsub(aValue, "spellgroup:", "")
   tCleanValue = sgsub(tCleanValue, "item:", "")
   tCleanValue = sgsub(tCleanValue, "spell:", "")
   tCleanValue = sgsub(tCleanValue, "output:", "")
   if tCleanValue == "true" then
      return true
   elseif tCleanValue == "false" then
      return false
   else
      return tCleanValue
   end
end

------------------------------------------------------------------------------------------------------------------
-- [v43.0] Match a stored condition value against the SEVERAL forms the live
-- data can carry for the same thing: the enUS group identity and the localized
-- name (the fallback lane, for an id SpellDataTBC does not know or a saved
-- value the migration could not resolve).
--
-- Plain OR would be wrong for the negating operators: "spell name is not X"
-- would come out true the moment EITHER form differs from X, i.e. always. A
-- negating operator therefore has to hold for EVERY form present, an
-- affirmative one for any.
--
-- The SET attributes need none of this - their live lists carry both forms as
-- keys, so contains/containsNot answer correctly by construction. Only the
-- scalar (CATEGORY) lane comes through here.
-- [v43.1] Promoted to a field: the evaluate loop in Core.lua and the two places
-- that NAME a condition (SkuAuras:BuildAuraName, the builder's condition rows)
-- all need the same answer to "is this operator a negation?", and three copies
-- of a two-entry list is how they drift apart.
SkuAuras.negatingOperators = {isNot = true, containsNot = true,}
local tNegatingOperators = SkuAuras.negatingOperators
local function MatchAnyForm(aOperator, aValue, aFormA, aFormB)
   local tOp = SkuAuras.Operators[aOperator]
   if not tOp then
      return false
   end
   local tNegating = tNegatingOperators[aOperator]
   local tSeen = false
   for x = 1, 2 do
      local tLive = (x == 1) and aFormA or aFormB
      -- `false` is the lazy-field cache marker for "no value" (see
      -- tLazyEvaluateFields in Core.lua), not a form to compare against.
      if tLive ~= nil and tLive ~= false then
         tSeen = true
         local tResult = tOp.func(tLive, aValue) == true
         if tNegating == true then
            if tResult ~= true then
               return false
            end
         elseif tResult == true then
            return true
         end
      end
   end
   if tSeen ~= true then
      return false
   end
   return tNegating == true
end

------------------------------------------------------------------------------------------------------------------
SkuAuras.itemTypes = {
   ["type"] = {
      friendlyName = L["Aura Typ"],
   },
   ["attribute"] = {
      friendlyName = L["Attribut für Bedingung"],
   },
   ["operator"] = {
      friendlyName = L["Operator für Bedingung"],
   },
   ["value"] = {
      friendlyName = L["Wert für Bedingung"],
   },
   ["then"] = {
      friendlyName = L["Beginn des Dann Teils der Aura"],
   },
   ["action"] = {
      friendlyName = L["Aktion für Aura"],
   },
   ["output"] = {
      friendlyName = L["Ausgabe von Aura"],
   },
}
------------------------------------------------------------------------------------------------------------------
SkuAuras.actions = {
   nothing = {
      tooltip = L["No action"],
      friendlyName = L["No action"],
      func = function(tAuraName, tEvaluateData)
      	--print("    SkuAuras.actions nothing")
      end,
      single = false,
   },

   notifyAudio = {
      tooltip = L["Die Ausgaben werden als Audio ausgegeben"],
      friendlyName = L["audio ausgabe"],
      func = function(tAuraName, tEvaluateData)
      	----dprint("    ","action func audio benachrichtigung DING")
      end,
      single = false,
      -- [v43.0] All aura AUDIO actions are instant now: the flag travels
      -- evaluate-loop -> output funct 4th arg -> OutputString's aInstant, which
      -- FRONT-inserts the words right behind whatever is playing instead of
      -- appending behind the whole pending queue. This is the word counterpart
      -- of the beeps' auraSound fast path: a word can never legally OVERLAY
      -- running speech (that is mush), so its floor is the playing clip's
      -- pacing point — but it no longer waits out unrelated queued speech.
      -- Word-to-word pacing, aFirst/overwrite interrupt logic and multi-word
      -- ordering are untouched (see the same-frame cursor in SkuVoice).
      instant = true,
   },
   notifyChat = {
      tooltip = L["Die Ausgaben werden als Text im Chat ausgegeben"],
      friendlyName = L["chat ausgabe"],
      func = function(tAuraName, tEvaluateData)
      	----dprint("    ","action func chat benachrichtigung")
      end,
      single = false,
   },
   notifyAudioSingle = {
      tooltip = L["Die Ausgaben werden als Audio ausgegeben. Die Aura wird jedoch nur einmal ausgelöst. Die nächste Auslösung der Aura erfolgt erst dann, wenn die Aura mindestens einmal nicht zugetroffen hat."],
      friendlyName = L["audio ausgabe einmal"],
      func = function(tAuraName, tEvaluateData)
      	----dprint("    ","action func audio benachrichtigung single")
      end,
      single = true,
      instant = true,
   },
   notifyAudioAndChatSingle = {
      tooltip = L["Die Ausgaben werden als Audio und chat ausgegeben"],
      friendlyName = L["audio und chat ausgabe"],
      func = function(tAuraName, tEvaluateData)
      	----dprint("    ","action func audio benachrichtigung DING")
      end,
      single = true,
      instant = true,
   },
   --[[
   notifyAudioSingleInstant = {
      tooltip = L["Die Ausgaben werden als Audio ausgegeben und dabei vor allen anderen Ausgaben platziert. Die Aura wird jedoch nur einmal ausgelöst. Die nächste Auslösung der Aura erfolgt erst dann, wenn die Aura mindestens einmal nicht zugetroffen hat."],
      friendlyName = L["audio ausgabe einmal sofort",
      func = function(tAuraName, tEvaluateData)
      	--dprint("    ","action func audio benachrichtigung SingleInstant")
      end,
      single = true,
      instant = true,
   },
   ]]
   notifyChatSingle = {
      tooltip = L["Die Ausgaben werden als Text im Chat ausgegeben. Die Aura wird jedoch nur einmal ausgelöst. Die nächste Auslösung der Aura erfolgt erst dann, wenn die Aura mindestens einmal nicht zugetroffen hat."],
      friendlyName = L["chat ausgabe einmal"],
      func = function(tAuraName, tEvaluateData)
      	--dprint("    ","action func chat benachrichtigung single")
      end,
      single = true,
   },
}

local function tNothingOutputFunction(tAuraName, tEvaluateData, aFirst, aInstant)
   --print("    SkuAuras.outputs nothing nothing","SkuAuras.outputs.event", tEvaluateData.event, aFirst, aInstant)
   return
end

-- [v43.0] The sourceUnitId/destUnitId outputs used to hand the RAW unit token
-- ("party3", "party2target") to the audio voice as ONE word. The audio packs
-- happen to ship single files "party0/1/2/4" -- but NOT "party3" and no
-- "partyNtarget" at all -- so some slots spoke and the others degraded to the
-- missing-word beep (db.realm.missingAudio counted 129 beeps for "party3"
-- alone). Split the party tokens into words the packs reliably ship ("party" +
-- digit + "ziel"), so every slot speaks the same short way; other tokens fall
-- back to their localized friendlyName from the value lists, then to the raw
-- token.
local function tUnitIdToSpokenName(aUnitId)
   if not aUnitId then
      return aUnitId
   end
   local tNr = string.match(aUnitId, "^party(%d)$")
   if tNr then
      return "party "..tNr
   end
   tNr = string.match(aUnitId, "^party(%d)target$")
   if tNr then
      return Sku.deEn("ziel", "target", "cible").." party "..tNr
   end
   local tEntry = (SkuAuras.values and SkuAuras.values[aUnitId]) or SkuAuras.valuesDefault[aUnitId]
   if tEntry and tEntry.friendlyName then
      return tEntry.friendlyName
   end
   return aUnitId
end

------------------------------------------------------------------------------------------------------------------
--local tPrevAuraPlaySoundFileHandle
SkuAuras.outputs = {
   nothing = {
      tooltip = L["No output"],
      friendlyName = L["nothing"],
      functs = {
         ["nothing"] = tNothingOutputFunction,
         ["notifyAudio"] = tNothingOutputFunction,
         ["notifyChat"] = tNothingOutputFunction,
      },
   },
   event = {
      tooltip = L["Der Name des auslösenden Ereignisses der Aura"],
      friendlyName = L["ereignis"],
      functs = {
         ["nothing"] = tNothingOutputFunction,
         ["notifyAudio"] = function(tAuraName, tEvaluateData, aFirst, aInstant)
            --dprint("    ","SkuAuras.outputs.event", tEvaluateData.event, aFirst, aInstant)
            if not tEvaluateData.event then return end
            if not SkuAuras.values[tEvaluateData.event] then return end
            if SkuAuras.values[tEvaluateData.event].friendlyNameShort then
               SkuOptions.Voice:OutputString(SkuAuras.values[tEvaluateData.event].friendlyNameShort, aFirst, true, 0.1, true, nil, nil, nil, nil, nil, aInstant)
            else
               SkuOptions.Voice:OutputString(SkuAuras.values[tEvaluateData.event].friendlyName, aFirst, true, 0.1, true, nil, nil, nil, nil, nil, aInstant)
            end
         end,
         ["notifyChat"] = function(tAuraName, tEvaluateData)
            if not tEvaluateData.event then return end
            if not SkuAuras.values[tEvaluateData.event] then return end
            if SkuAuras.values[tEvaluateData.event].friendlyNameShort then
               print(SkuAuras.values[tEvaluateData.event].friendlyNameShort)
            else
               print(SkuAuras.values[tEvaluateData.event].friendlyName)
            end
         end,
      },
   },
   sourceUnitId = {
      tooltip = L["Die Einheiten ID der Quelle für das ausgelöste Ereignis"],
      friendlyName = L["quell einheit"],
      functs = {
         ["nothing"] = tNothingOutputFunction,
         ["notifyAudio"] = function(tAuraName, tEvaluateData, aFirst, aInstant)
            if tEvaluateData.sourceUnitId then
               --dprint("    ","tEvaluateData.sourceUnitId", tEvaluateData.sourceUnitId)
               SkuOptions.Voice:OutputString(tUnitIdToSpokenName(tEvaluateData.sourceUnitId[1]), aFirst, true, 0.1, true, nil, nil, nil, nil, nil, aInstant)
            end
         end,
         ["notifyChat"] = function(tAuraName, tEvaluateData)
            if tEvaluateData.sourceUnitId then
               print(tUnitIdToSpokenName(tEvaluateData.sourceUnitId[1]))
            end
         end,
      },
   },   
   destUnitId = {
      tooltip = L["Die Einheiten ID des Ziels für das ausgelöste Ereignis"],
      friendlyName = L["ziel einheit"],
      functs = {
         ["nothing"] = tNothingOutputFunction,
         ["notifyAudio"] = function(tAuraName, tEvaluateData, aFirst, aInstant)
            --dprint("    ","tEvaluateData.destUnitId", tEvaluateData.destUnitId)
            if tEvaluateData.destUnitId then
               SkuOptions.Voice:OutputString(tUnitIdToSpokenName(tEvaluateData.destUnitId[1]), aFirst, true, 0.1, true, nil, nil, nil, nil, nil, aInstant)
            end
         end,
         ["notifyChat"] = function(tAuraName, tEvaluateData)
            if tEvaluateData.destUnitId then
               print(tUnitIdToSpokenName(tEvaluateData.destUnitId[1]))
            end
         end,
      },
   },
   unitHealthPlayer = {
      tooltip = L["Dein Gesundheit in Prozent"],
      friendlyName = L["eigene Gesundheit"],
      functs = {
         ["nothing"] = tNothingOutputFunction,
         ["notifyAudio"] = function(tAuraName, tEvaluateData, aFirst, aInstant)
            if tEvaluateData.unitHealthPlayer then
               SkuOptions.Voice:OutputString(tEvaluateData.unitHealthPlayer, aFirst, true, 0.1, true, nil, nil, nil, nil, nil, aInstant)
            end
         end,
         ["notifyChat"] = function(tAuraName, tEvaluateData)
            if tEvaluateData.unitHealthPlayer then
               print(tEvaluateData.unitHealthPlayer)
            end
         end,
      },
   },      
   auraAmount = {
      tooltip = L["Die Stapel Anzahl der Aura"],
      friendlyName = L["aura stapel"],
      functs = {
         ["nothing"] = tNothingOutputFunction,
         ["notifyAudio"] = function(tAuraName, tEvaluateData, aFirst, aInstant)
            if tEvaluateData.auraAmount then
               SkuOptions.Voice:OutputString(tEvaluateData.auraAmount, aFirst, true, 0.1, true, nil, nil, nil, nil, nil, aInstant)
            end
         end,
         ["notifyChat"] = function(tAuraName, tEvaluateData)
            if tEvaluateData.auraAmount then
               print(tEvaluateData.auraAmount)
            end
         end,
      },
   },
   --[[
   class = {
      tooltip = L["Die Klasse der Einheit für das ausgelöste Ereignis",
      friendlyName = L["klasse",
      functs = {
         ["nothing"] = tNothingOutputFunction,
         ["notifyAudio"] = function(tAuraName, tEvaluateData, aFirst, aInstant)
            if tEvaluateData.class then
               SkuOptions.Voice:OutputString(tEvaluateData.class, aFirst, true, 0.1, true, nil, nil, nil, nil, nil, aInstant)
            end
         end,
         ["notifyChat"] = function(tAuraName, tEvaluateData)
            if tEvaluateData.class then
               print(tEvaluateData.class)
            end
         end,
      },
   },
   ]]
   unitPowerPlayer = {
      tooltip = L["Deine Ressourcen Menge (Mana, Wut, Energie) für das ausgelöste Ereignis"],
      friendlyName = L["eigene Ressource"],
      functs = {
         ["nothing"] = tNothingOutputFunction,
         ["notifyAudio"] = function(tAuraName, tEvaluateData, aFirst, aInstant)
            if tEvaluateData.unitPowerPlayer then
               SkuOptions.Voice:OutputString(tEvaluateData.unitPowerPlayer, aFirst, true, 0.1, true, nil, nil, nil, nil, nil, aInstant)
            end
         end,
         ["notifyChat"] = function(tAuraName, tEvaluateData)
            if tEvaluateData.unitPowerPlayer then
               print(tEvaluateData.unitPowerPlayer)
            end
         end,
      },
   },
   unitManaPlayer = {
      tooltip = L["AURA_PowerManaOutTip"],
      friendlyName = L["AURA_PowerMana"],
      functs = {
         ["nothing"] = tNothingOutputFunction,
         ["notifyAudio"] = function(tAuraName, tEvaluateData, aFirst, aInstant)
            if tEvaluateData.unitManaPlayer then
               SkuOptions.Voice:OutputString(tEvaluateData.unitManaPlayer, aFirst, true, 0.1, true, nil, nil, nil, nil, nil, aInstant)
            end
         end,
         ["notifyChat"] = function(tAuraName, tEvaluateData)
            if tEvaluateData.unitManaPlayer then
               print(tEvaluateData.unitManaPlayer)
            end
         end,
      },
   },
   unitRagePlayer = {
      tooltip = L["AURA_PowerRageOutTip"],
      friendlyName = L["AURA_PowerRage"],
      functs = {
         ["nothing"] = tNothingOutputFunction,
         ["notifyAudio"] = function(tAuraName, tEvaluateData, aFirst, aInstant)
            if tEvaluateData.unitRagePlayer then
               SkuOptions.Voice:OutputString(tEvaluateData.unitRagePlayer, aFirst, true, 0.1, true, nil, nil, nil, nil, nil, aInstant)
            end
         end,
         ["notifyChat"] = function(tAuraName, tEvaluateData)
            if tEvaluateData.unitRagePlayer then
               print(tEvaluateData.unitRagePlayer)
            end
         end,
      },
   },
   unitEnergyPlayer = {
      tooltip = L["AURA_PowerEnergyOutTip"],
      friendlyName = L["AURA_PowerEnergy"],
      functs = {
         ["nothing"] = tNothingOutputFunction,
         ["notifyAudio"] = function(tAuraName, tEvaluateData, aFirst, aInstant)
            if tEvaluateData.unitEnergyPlayer then
               SkuOptions.Voice:OutputString(tEvaluateData.unitEnergyPlayer, aFirst, true, 0.1, true, nil, nil, nil, nil, nil, aInstant)
            end
         end,
         ["notifyChat"] = function(tAuraName, tEvaluateData)
            if tEvaluateData.unitEnergyPlayer then
               print(tEvaluateData.unitEnergyPlayer)
            end
         end,
      },
   },
   unitRunicPowerPlayer = {
      tooltip = L["AURA_PowerRunicOutTip"],
      friendlyName = L["AURA_PowerRunic"],
      functs = {
         ["nothing"] = tNothingOutputFunction,
         ["notifyAudio"] = function(tAuraName, tEvaluateData, aFirst, aInstant)
            if tEvaluateData.unitRunicPowerPlayer then
               SkuOptions.Voice:OutputString(tEvaluateData.unitRunicPowerPlayer, aFirst, true, 0.1, true, nil, nil, nil, nil, nil, aInstant)
            end
         end,
         ["notifyChat"] = function(tAuraName, tEvaluateData)
            if tEvaluateData.unitRunicPowerPlayer then
               print(tEvaluateData.unitRunicPowerPlayer)
            end
         end,
      },
   },
   unitComboPlayer = {
      tooltip = L["Deine combopunkte auf dein aktuelles ziel"],
      friendlyName = L["Eigene combopunkte"],
      functs = {
         ["nothing"] = tNothingOutputFunction,
         ["notifyAudio"] = function(tAuraName, tEvaluateData, aFirst, aInstant)
            if tEvaluateData.unitComboPlayer then
               SkuOptions.Voice:OutputString(tEvaluateData.unitComboPlayer, aFirst, true, 0.1, true, nil, nil, nil, nil, nil, aInstant)
            end
         end,
         ["notifyChat"] = function(tAuraName, tEvaluateData)
            if tEvaluateData.unitComboPlayer then
               print(tEvaluateData.unitComboPlayer)
            end
         end,
      },
   },

   unitHealthPlayer = {
      tooltip = L["Deine Gesundheits Menge für das ausgelöste Ereignis"],
      friendlyName = L["eigene gesundheit"],
      functs = {
         ["nothing"] = tNothingOutputFunction,
         ["notifyAudio"] = function(tAuraName, tEvaluateData, aFirst, aInstant)
            if tEvaluateData.unitHealthPlayer then
               SkuOptions.Voice:OutputString(tEvaluateData.unitHealthPlayer, aFirst, true, 0.1, true, nil, nil, nil, nil, nil, aInstant)
            end
         end,
         ["notifyChat"] = function(tAuraName, tEvaluateData)
            if tEvaluateData.unitHealthPlayer then
               print(tEvaluateData.unitHealthPlayer)
            end
         end,
      },
   },
   unitHealthTarget = {
      tooltip = L["Your target's health percentage"],
      friendlyName = L["Your target's health"],
      functs = {
         ["nothing"] = tNothingOutputFunction,
         ["notifyAudio"] = function(tAuraName, tEvaluateData, aFirst, aInstant)
            if tEvaluateData.unitHealthTarget then
               SkuOptions.Voice:OutputString(tEvaluateData.unitHealthTarget, aFirst, true, 0.1, true, nil, nil, nil, nil, nil, aInstant)
            end
         end,
         ["notifyChat"] = function(tAuraName, tEvaluateData)
            if tEvaluateData.unitHealthTarget then
               print(tEvaluateData.unitHealthTarget)
            end
         end,
      },
   },
   unitPowerTarget = {
      tooltip = L["Percentage of your target's primary resource, for example mana or rage"],
      friendlyName = L["Your target's resource"],
      functs = {
         ["nothing"] = tNothingOutputFunction,
         ["notifyAudio"] = function(tAuraName, tEvaluateData, aFirst, aInstant)
            if tEvaluateData.unitPowerTarget then
               SkuOptions.Voice:OutputString(tEvaluateData.unitPowerTarget, aFirst, true, 0.1, true, nil, nil, nil, nil, nil, aInstant)
            end
         end,
         ["notifyChat"] = function(tAuraName, tEvaluateData)
            if tEvaluateData.unitPowerTarget then
               print(tEvaluateData.unitPowerTarget)
            end
         end,
      },
   },
   unitHealthOrPowerUpdate = {
      tooltip = L["The updated health or resource percentage from a health update or resource update event"],
      friendlyName = L["Health/Resource update"],
      functs = {
         ["nothing"] = tNothingOutputFunction,
         ["notifyAudio"] = function(tAuraName, tEvaluateData, aFirst, aInstant)
            if tEvaluateData.unitHealthOrPowerUpdate then
               SkuOptions.Voice:OutputString(tEvaluateData.unitHealthOrPowerUpdate, aFirst, true, 0.1, true, nil, nil, nil, nil, nil, aInstant)
            end
         end,
         ["notifyChat"] = function(tAuraName, tEvaluateData)
            if tEvaluateData.unitHealthOrPowerUpdate then
               print(tEvaluateData.unitHealthOrPowerUpdate)
            end
         end,
      },
   },
   damageAmount = {
      tooltip = L["The amount of damage from a spell, melee, or ranged attack"],
      friendlyName = L["Damage amount"],
      functs = {
         ["nothing"] = tNothingOutputFunction,
         ["notifyAudio"] = function(tAuraName, tEvaluateData, aFirst, aInstant)
            if tEvaluateData.damageAmount then
               SkuOptions.Voice:OutputString(tEvaluateData.damageAmount, aFirst, true, 0.1, true, nil, nil, nil, nil, nil, aInstant)
            end
         end,
         ["notifyChat"] = function(tAuraName, tEvaluateData)
            if tEvaluateData.damageAmount then
               print(tEvaluateData.damageAmount)
            end
         end,
      },
   },
   healAmount = {
      tooltip = L["The amount of healing"],
      friendlyName = L["Healing amount"],
      functs = {
         ["nothing"] = tNothingOutputFunction,
         ["notifyAudio"] = function(tAuraName, tEvaluateData, aFirst, aInstant)
            if tEvaluateData.healAmount then
               SkuOptions.Voice:OutputString(tEvaluateData.healAmount, aFirst, true, 0.1, true, nil, nil, nil, nil, nil, aInstant)
            end
         end,
         ["notifyChat"] = function(tAuraName, tEvaluateData)
            if tEvaluateData.healAmount then
               print(tEvaluateData.healAmount)
            end
         end,
      },
   },
   overhealingAmount = {
      tooltip = L["The amount of overhealing"],
      friendlyName = L["Overhealing amount"],
      functs = {
         ["nothing"] = tNothingOutputFunction,
         ["notifyAudio"] = function(tAuraName, tEvaluateData, aFirst, aInstant)
            if tEvaluateData.overhealingAmount then
               SkuOptions.Voice:OutputString(tEvaluateData.overhealingAmount, aFirst, true, 0.1, true, nil, nil, nil, nil, nil, aInstant)
            end
         end,
         ["notifyChat"] = function(tAuraName, tEvaluateData)
            if tEvaluateData.overhealingAmount then
               print(tEvaluateData.overhealingAmount)
            end
         end,
      },
   },
   overhealingPercentage = {
      tooltip = L["How much of the healing amount was overhealing"],
      friendlyName = L["Overhealing percentage"],
      functs = {
         ["nothing"] = tNothingOutputFunction,
         ["notifyAudio"] = function(tAuraName, tEvaluateData, aFirst, aInstant)
            if tEvaluateData.overhealingPercentage then
               SkuOptions.Voice:OutputString(tEvaluateData.overhealingPercentage, aFirst, true, 0.1, true, nil, nil, nil, nil, nil, aInstant)
            end
         end,
         ["notifyChat"] = function(tAuraName, tEvaluateData)
            if tEvaluateData.overhealingPercentage then
               print(tEvaluateData.overhealingPercentage)
            end
         end,
      },
   },
   spellName = {
      tooltip = L["Der Name des Zaubers, der die Aura ausgelöst hat"],
      friendlyName = L["zauber name"],
      functs = {
         ["nothing"] = tNothingOutputFunction,
         ["notifyAudio"] = function(tAuraName, tEvaluateData, aFirst, aInstant)
            if tEvaluateData.spellName then
               SkuOptions.Voice:OutputString(tEvaluateData.spellName, aFirst, true, 0.1, true, nil, nil, nil, nil, nil, aInstant)
            end
         end,
         ["notifyChat"] = function(tAuraName, tEvaluateData)
            if tEvaluateData.spellName then
               print(tEvaluateData.spellName)
            end
         end,
      },
   },
   -- [41.03 Fix] Ausgaben fuer den NAMEN der in DIESER Aura gewaehlten Waffenverzauberung
   -- (analog zu buffListTarget). Lesen tEvaluateData.weaponEnchant<Hand>Selected, das im
   -- Auswerte-Loop (Core.lua) mit dem in der Bedingung gewaehlten VZ-Namen gefuellt wird.
   -- So sagt z. B. "enthaelt nicht Flammenzunge" beim Ausloesen "Waffe der Flammenzunge
   -- (Passiv)" an - NICHT die VZ, die sie ueberschrieben hat. Die generische "zauber name"-
   -- Ausgabe liest dagegen den Zauber des ausloesenden Ereignisses (fuer VZ-Auren wirr).
   weaponEnchantMainHandName = {
      tooltip = L["AURA_OutWeMHTip"],
      friendlyName = L["AURA_OutWeMH"],
      functs = {
         ["nothing"] = tNothingOutputFunction,
         ["notifyAudio"] = function(tAuraName, tEvaluateData, aFirst, aInstant)
            if tEvaluateData.weaponEnchantMainHandSelected then
               SkuOptions.Voice:OutputString(tEvaluateData.weaponEnchantMainHandSelected, aFirst, true, 0.1, true, nil, nil, nil, nil, nil, aInstant)
            end
         end,
         ["notifyChat"] = function(tAuraName, tEvaluateData)
            if tEvaluateData.weaponEnchantMainHandSelected then
               print(tEvaluateData.weaponEnchantMainHandSelected)
            end
         end,
      },
   },
   weaponEnchantOffHandName = {
      tooltip = L["AURA_OutWeOHTip"],
      friendlyName = L["AURA_OutWeOH"],
      functs = {
         ["nothing"] = tNothingOutputFunction,
         ["notifyAudio"] = function(tAuraName, tEvaluateData, aFirst, aInstant)
            if tEvaluateData.weaponEnchantOffHandSelected then
               SkuOptions.Voice:OutputString(tEvaluateData.weaponEnchantOffHandSelected, aFirst, true, 0.1, true, nil, nil, nil, nil, nil, aInstant)
            end
         end,
         ["notifyChat"] = function(tAuraName, tEvaluateData)
            if tEvaluateData.weaponEnchantOffHandSelected then
               print(tEvaluateData.weaponEnchantOffHandSelected)
            end
         end,
      },
   },
   itemName = {
      tooltip = L["Der Name des Gegenstands, der die Aura ausgelöst hat"],
      friendlyName = L["gegenstand name"],
      functs = {
         ["nothing"] = tNothingOutputFunction,
         ["notifyAudio"] = function(tAuraName, tEvaluateData, aFirst, aInstant)
            if tEvaluateData.itemName then
               SkuOptions.Voice:OutputString(tEvaluateData.itemName, aFirst, true, 0.1, true, nil, nil, nil, nil, nil, aInstant)
            end
         end,
         ["notifyChat"] = function(tAuraName, tEvaluateData)
            if tEvaluateData.itemName then
               print(tEvaluateData.itemName)
            end
         end,
      },
   },
   itemCount = {
      tooltip = L["Die Anzahl in deiner Tasche des Gegenstands, der die Aura ausgelöst hat"],
      friendlyName = L["gegenstand anzahl"],
      functs = {
         ["nothing"] = tNothingOutputFunction,
         ["notifyAudio"] = function(tAuraName, tEvaluateData, aFirst, aInstant)
            if tEvaluateData.itemCount then
               SkuOptions.Voice:OutputString(tEvaluateData.itemCount, aFirst, true, 0.1, true, nil, nil, nil, nil, nil, aInstant)
            end
         end,
         ["notifyChat"] = function(tAuraName, tEvaluateData)
            if tEvaluateData.itemCount then
               print(tEvaluateData.itemCount)
            end
         end,
      },
   },
   buffListTarget = {
      tooltip = L["Aura, die in der Buff liste des Ziels gesucht oder ausgeschlossen wurde"],
      friendlyName = L["wert buff liste ziel"],
      functs = {
         ["nothing"] = tNothingOutputFunction,
         ["notifyAudio"] = function(tAuraName, tEvaluateData, aFirst, aInstant)
            if tEvaluateData.buffListTarget then
               SkuOptions.Voice:OutputString(tEvaluateData.buffListTarget, aFirst, true, 0.1, true, nil, nil, nil, nil, nil, aInstant)
            end
         end,
         ["notifyChat"] = function(tAuraName, tEvaluateData)
            if tEvaluateData.buffListTarget then
               print(tEvaluateData.buffListTarget)
            end
         end,
      },
   },
   debuffListTarget = {
      tooltip = L["Aura, die in der Debuff liste des Ziels gesucht oder ausgeschlossen wurde"],
      friendlyName = L["wert debuff liste ziel"],
      functs = {
         ["nothing"] = tNothingOutputFunction,
         ["notifyAudio"] = function(tAuraName, tEvaluateData, aFirst, aInstant)
            if tEvaluateData.debuffListTarget then
               SkuOptions.Voice:OutputString(tEvaluateData.debuffListTarget, aFirst, true, 0.1, true, nil, nil, nil, nil, nil, aInstant)
            end
         end,
         ["notifyChat"] = function(tAuraName, tEvaluateData)
            if tEvaluateData.debuffListTarget then
               print(tEvaluateData.debuffListTarget)
            end
         end,
      },
   },
}

SkuAuras.outputSoundFiles = SkuCore.outputSoundFiles

for tOutputString, tFriendlyName in pairs(SkuAuras.outputSoundFiles) do
   SkuAuras.outputs[tOutputString] = {
      tooltip = tFriendlyName,
      outputString = tOutputString,
      friendlyName = tFriendlyName,
      functs = {
         ["nothing"] = tNothingOutputFunction,
         ["notifyAudio"] = function(tAuraName, tEvaluateData, aFirst, aOutputName, aDelay)
            --if aFirst == true then
               --[[
               if tPrevAuraPlaySoundFileHandle then
                  StopSound(tPrevAuraPlaySoundFileHandle)
               end
               ]]
               --SkuOptions.Voice:OutputString("sound-silence0.1", true, false, 0.3, true)
            --end
            -- [v43.0] 16th arg = aAuraSound: let the pump start this beep without
            -- waiting out the TTSSepPause hold of whatever is playing in front of it
            -- (it still yields to another aura sound that is already playing, so two
            -- aura sounds never overlap). Positional rather than the table form on
            -- purpose: no table allocated on the aura firing path.
            -- This is the ONLY output family that may set it -- the word/text outputs
            -- above must keep the hold or a multi-word output would slur.
            SkuOptions.Voice:OutputString(tOutputString, aFirst, true, 0.3, true, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, true)
         end,
         ["notifyChat"] = function(tAuraName, tEvaluateData)
            print(tFriendlyName)
         end,
      },
   }
end

------------------------------------------------------------------------------------------------------------------
SkuAuras.valuesDefault = {
   --auraAmount;itemCount
      ["0"] = {friendlyName = "0"},
      ["1"] = {friendlyName = "1"},
      ["2"] = {friendlyName = "2"},
      ["3"] = {friendlyName = "3"},
      ["4"] = {friendlyName = "4"},
      ["5"] = {friendlyName = "5"},
      ["6"] = {friendlyName = "6"},
      ["7"] = {friendlyName = "7"},
      ["8"] = {friendlyName = "8"},
      ["9"] = {friendlyName = "9"},
      ["10"] = {friendlyName = "10"},
      ["11"] = {friendlyName = "11"},
      ["12"] = {friendlyName = "12"},
      ["13"] = {friendlyName = "13"},
      ["14"] = {friendlyName = "14"},
      ["15"] = {friendlyName = "15"},
      ["16"] = {friendlyName = "16"},
      ["17"] = {friendlyName = "17"},
      ["18"] = {friendlyName = "18"},
      ["19"] = {friendlyName = "19"},
      ["20"] = {friendlyName = "20"},
      ["21"] = {friendlyName = "21"},
      ["22"] = {friendlyName = "22"},
      ["23"] = {friendlyName = "23"},
      ["24"] = {friendlyName = "24"},
      ["25"] = {friendlyName = "25"},
      ["26"] = {friendlyName = "26"},
      ["27"] = {friendlyName = "27"},
      ["28"] = {friendlyName = "28"},
      ["29"] = {friendlyName = "29"},
      ["30"] = {friendlyName = "30"},
      ["31"] = {friendlyName = "31"},
      ["32"] = {friendlyName = "32"},
      ["33"] = {friendlyName = "33"},
      ["34"] = {friendlyName = "34"},
      ["35"] = {friendlyName = "35"},
      ["36"] = {friendlyName = "36"},
      ["37"] = {friendlyName = "37"},
      ["38"] = {friendlyName = "38"},
      ["39"] = {friendlyName = "39"},
      ["40"] = {friendlyName = "40"},
      ["41"] = {friendlyName = "41"},
      ["42"] = {friendlyName = "42"},
      ["43"] = {friendlyName = "43"},
      ["44"] = {friendlyName = "44"},
      ["45"] = {friendlyName = "45"},
      ["46"] = {friendlyName = "46"},
      ["47"] = {friendlyName = "47"},
      ["48"] = {friendlyName = "48"},
      ["49"] = {friendlyName = "49"},
      ["50"] = {friendlyName = "50"},
      ["51"] = {friendlyName = "51"},
      ["52"] = {friendlyName = "52"},
      ["53"] = {friendlyName = "53"},
      ["54"] = {friendlyName = "54"},
      ["55"] = {friendlyName = "55"},
      ["56"] = {friendlyName = "56"},
      ["57"] = {friendlyName = "57"},
      ["58"] = {friendlyName = "58"},
      ["59"] = {friendlyName = "59"},
      ["60"] = {friendlyName = "60"},
      ["61"] = {friendlyName = "61"},
      ["62"] = {friendlyName = "62"},
      ["63"] = {friendlyName = "63"},
      ["64"] = {friendlyName = "64"},
      ["65"] = {friendlyName = "65"},
      ["66"] = {friendlyName = "66"},
      ["67"] = {friendlyName = "67"},
      ["68"] = {friendlyName = "68"},
      ["69"] = {friendlyName = "69"},
      ["70"] = {friendlyName = "70"},
      ["71"] = {friendlyName = "71"},
      ["72"] = {friendlyName = "72"},
      ["73"] = {friendlyName = "73"},
      ["74"] = {friendlyName = "74"},
      ["75"] = {friendlyName = "75"},
      ["76"] = {friendlyName = "76"},
      ["77"] = {friendlyName = "77"},
      ["78"] = {friendlyName = "78"},
      ["79"] = {friendlyName = "79"},
      ["80"] = {friendlyName = "80"},
      ["81"] = {friendlyName = "81"},
      ["82"] = {friendlyName = "82"},
      ["83"] = {friendlyName = "83"},
      ["84"] = {friendlyName = "84"},
      ["85"] = {friendlyName = "85"},
      ["86"] = {friendlyName = "86"},
      ["87"] = {friendlyName = "87"},
      ["88"] = {friendlyName = "88"},
      ["89"] = {friendlyName = "89"},
      ["90"] = {friendlyName = "90"},
      ["91"] = {friendlyName = "91"},
      ["92"] = {friendlyName = "92"},
      ["93"] = {friendlyName = "93"},
      ["94"] = {friendlyName = "94"},
      ["95"] = {friendlyName = "95"},
      ["96"] = {friendlyName = "96"},
      ["97"] = {friendlyName = "97"},
      ["98"] = {friendlyName = "98"},
      ["99"] = {friendlyName = "99"},
      ["100"] = {friendlyName = "100"},
      ["110"] = {friendlyName = "110"},
      ["120"] = {friendlyName = "120"},
      ["130"] = {friendlyName = "130"},
      ["140"] = {friendlyName = "140"},
      ["150"] = {friendlyName = "150"},
      ["200"] = {friendlyName = "200"},
      ["300"] = {friendlyName = "300"},
      ["400"] = {friendlyName = "400"},
      ["500"] = {friendlyName = "500"},

   
      ["true"] = {
         tooltip = L["triff zu"],
         friendlyName = L["wahr"],
      },
      ["false"] = {
         tooltip = L["Trifft nicht zu"],
         friendlyName = L["falsch"],
      },

   --missType
      ["ABSORB"] = {
         tooltip = L["Absorbiert"],
         friendlyName = L["Absorbiert"],
      },
      ["BLOCK"] = {
         tooltip = L["Geblockt"],
         friendlyName = L["Geblockt"],
      },
      ["DEFLECT"] = {
         tooltip = L["Umgelenkt"],
         friendlyName = L["Umgelenkt"],
      },
      ["DODGE"] = {
         tooltip = L["Ausgewichen"],
         friendlyName = L["Ausgewichen"],
      },
      ["EVADE"] = {
         tooltip = L["Vermieden"],
         friendlyName = L["Vermieden"],
      },
      ["IMMUNE"] = {
         tooltip = L["Immun"],
         friendlyName = L["Immun"],
      },
      ["MISS"] = {
         tooltip = L["Verfehlt"],
         friendlyName = L["Verfehlt"],
      },
      ["PARRY"] = {
         tooltip = L["Pariert"],
         friendlyName = L["Pariert"],
      },
      ["REFLECT"] = {
         tooltip = L["Reflektiert"],
         friendlyName = L["Reflektiert"],
      },
      ["RESIST"] = {
         tooltip = L["Widerstanden"],
         friendlyName = L["Widerstanden"],
      },
   --auraType
      ["BUFF"] = {
         tooltip = L["Reagiert, wenn der Aura-Typ ein Buff ist"],
         friendlyName = L["buff"],
      },
      ["DEBUFF"] = {
         tooltip = L["Reagiert, wenn der Aura-Typ ein Debuff ist"],
         friendlyName = L["debuff"],
      },
   --destUnitId
      ["target"] = {
         tooltip = L["dein aktuelles Ziel. Beispiel: Ein Debuff, der auf deinem aktuelle Ziel ausgelaufen ist"],
         friendlyName = L["dein ziel"],
      },
      ["player"] = {
         tooltip = L["du selbst. Beispiel: Ein Buff, der auf dich gezaubert wurde"],
         friendlyName = L["selbst"],
      },
      ["pet"] = {
         tooltip = L["The player character's active pet"],
         friendlyName = L["Your pet"],
      },
      ["focus"] = {
         tooltip = L["dein fokus. Beispiel: Ein Buff, der auf deinen focus gezaubert wurde"],
         friendlyName = L["fokus"],
      },
      ["partyWoPlayer"] = {
         tooltip = L["ein beliebiges Gruppenmitglied. Beispiel: Ein Buff, der auf einem Gruppenmitglied ausgelaufen ist"],
         friendlyName = L["gruppenmitglieder ohne dich"],
      },
      ["party"] = {
         tooltip = L["ein beliebiges Gruppenmitglied. Beispiel: Ein Buff, der auf einem Gruppenmitglied ausgelaufen ist"],
         friendlyName = L["gruppenmitglieder"],
      },
      ["party0"] = {
         tooltip = L["Gruppenmitglied 0 (du)."],
         friendlyName = L["gruppenmitglied 0"],
      },      
      ["party1"] = {
         tooltip = L["Gruppenmitglied 1."],
         friendlyName = L["gruppenmitglied 1"],
      },      
      ["party2"] = {
         tooltip = L["Gruppenmitglied 2."],
         friendlyName = L["gruppenmitglied 2"],
      },      
      ["party3"] = {
         tooltip = L["Gruppenmitglied 3."],
         friendlyName = L["gruppenmitglied 3"],
      },      
      ["party4"] = {
         tooltip = L["Gruppenmitglied 4."],
         friendlyName = L["gruppenmitglied 4"],
      },      
      ["all"] = {
         tooltip = L["eine beliebige Einheit. Beispiel: Irgendein Mob stirbt"],
         friendlyName = L["alle"],
      },


      ["targettarget"] = {
         tooltip = L["ziel deines Ziels"],
         friendlyName = L["ziel deines ziels"],
      },
      ["focustarget"] = {
         tooltip = L["ziel deines deines fokus"],
         friendlyName = L["ziel deines fokus"],
      },
      ["party0target"] = {
         tooltip = L["ziel von Gruppenmitglied 0 (du)."],
         friendlyName = L["ziel von gruppenmitglied 0"],
      },      
      ["party1target"] = {
         tooltip = L["ziel von Gruppenmitglied 1."],
         friendlyName = L["ziel von gruppenmitglied 1"],
      },      
      ["party2target"] = {
         tooltip = L["ziel von Gruppenmitglied 2."],
         friendlyName = L["ziel von gruppenmitglied 2"],
      },      
      ["party3target"] = {
         tooltip = L["ziel von Gruppenmitglied 3."],
         friendlyName = L["ziel von gruppenmitglied 3"],
      },      
      ["party4target"] = {
         tooltip = L["ziel von Gruppenmitglied 4."],
         friendlyName = L["ziel von gruppenmitglied 4"],
      },      
   --class
      ["Warrior"] = {
         tooltip = L["Reagiert, wenn die Zieleinheit die Klasse Krieger hat"],
         friendlyName = L["krieger"],
      },
      ["Paladin"] = {
         tooltip = L["Reagiert, wenn die Zieleinheit die Klasse Paladin hat"],
         friendlyName = L["paladin"],
      },
      ["Hunter"] = {
         tooltip = L["Reagiert, wenn die Zieleinheit die Klasse Jäger hat"],
         friendlyName = L["jäger"],
      },
      ["Rogue"] = {
         tooltip = L["Reagiert, wenn die Zieleinheit die Klasse Schurke hat"],
         friendlyName = L["schurke"],
      },
      ["Priest"] = {
         tooltip = L["Reagiert, wenn die Zieleinheit die Klasse Priester hat"],
         friendlyName = L["priester"],
      },
      ["Death Knight"] = {
         tooltip = L["Reagiert, wenn die Zieleinheit die Klasse Todesritter hat"],
         friendlyName = L["todesritter"],
      },
      ["Shaman"] = {
         tooltip = L["Reagiert, wenn die Zieleinheit die Klasse Schamane hat"],
         friendlyName = L["schamane"],
      },
      ["Mage"] = {
         tooltip = L["Reagiert, wenn die Zieleinheit die Klasse Magier hat"],
         friendlyName = L["magier"],
      },
      ["Warlock"] = {
         tooltip = L["Reagiert, wenn die Zieleinheit die Klasse Hexer hat"],
         friendlyName = L["hexer"],
      },
      --["Monk"] = {
         --tooltip = L["Reagiert, wenn die Zieleinheit die Klasse Mönch hat"],
         --friendlyName = L["mönch"],
      --},
      ["Druid"] = {
         tooltip = L["Reagiert, wenn die Zieleinheit die Klasse Druide hat"],
         friendlyName = L["druide"],
      },
      ["Demon Hunter"] = {
         tooltip = L["Reagiert, wenn die Zieleinheit die Klasse Dämonenjäger hat"],
         friendlyName = L["dämonenjäger"],
      },
   --event
      ["UNIT_TARGETCHANGE"] = {
         tooltip = L["Eine Einheit hat das Ziel gewechselt. Quell Einheit ID ist die Einheit, die das Ziel gewechselt hat. Ziel Einheit ID ist das neue Ziel von Quell einheit."],
         friendlyName = L["Ziel änderung"],
         friendlyNameShort = L["ziel änderung"],
      },
      ["UNIT_POWER"] = {
         tooltip = L["Ressource hat sich verändert (Mana, Energie, Wut etc."],
         friendlyName = L["Ressourcen änderung"],
         friendlyNameShort = L["ressource"],
      },
      ["UNIT_HEALTH"] = {
         tooltip = L["Gesundheit hat sich verändert"],
         friendlyName = L["Gesundheit änderung"],
         friendlyNameShort = L["gesundheit"],
      },
      ["SPELL_AURA_APPLIED;SPELL_AURA_REFRESH;SPELL_AURA_APPLIED_DOSE"] = {
         tooltip = L["Buff oder Debuff erhalten oder erneuert"],
         friendlyName = L["aura erhalten"],
         friendlyNameShort = L["erhalten"],
      },
      ["SPELL_AURA_REMOVED"] = {
         tooltip = L["Buff oder Debuff verloren"],
         friendlyName = L["aura verloren"],
         friendlyNameShort = L["verloren"],
      },
      ["SPELL_CAST_START"] = {
         tooltip = L["Ein Zauber wurde begonnen"],
         friendlyName = L["zauber start"],
      },
      ["SPELL_CAST_SUCCESS"] = {
         tooltip = L["Ein Zauber wurde erfolgreich gezaubert"],
         friendlyName = L["zauber erfolgreich"],
      },
      ["SPELL_COOLDOWN_START"] = {
         tooltip = L["Der Cooldown eines Zaubers hat begonnen"],
         friendlyName = L["zauber cooldown start"],  
         friendlyNameShort = L["cooldown"],
      },
      ["SPELL_COOLDOWN_END"] = {
         tooltip = L["Der Cooldown eines Zaubers ist beendet"],
         friendlyName = L["zauber cooldown ende"], 
         friendlyNameShort = L["bereit"],
      },
      ["ITEM_COOLDOWN_START"] = {
         tooltip = L["Der Cooldown eines Gegenstands hat begonnen"],
         friendlyName = L["gegenstand cooldown start"], 
         friendlyNameShort = L["cooldown"],
      },
      ["ITEM_COOLDOWN_END"] = {
         tooltip = L["Der Cooldown eines Gegenstands ist beendet"],
         friendlyName = L["gegenstand cooldown ende"],
         friendlyNameShort = L["bereit"],
      },
      ["WEAPON_ENCHANT_REMOVED"] = {
         tooltip = L["AURA_WeaponEnchantRemovedTip"],
         friendlyName = L["AURA_WeaponEnchantRemoved"],
         friendlyNameShort = L["AURA_WeaponEnchantRemovedShort"],
      },
      ["SWING_DAMAGE"] = {
         tooltip = L["Ein Nahkampfangriff hat Schaden verursacht"],
         friendlyName = L["nahkampf schaden"],
      },
      ["SWING_MISSED"] = {
         tooltip = L["Ein Nahkampfangriff hat verfehlt"],
         friendlyName = L["nahkampf verfehlt"],
      },
      ["SWING_EXTRA_ATTACKS"] = {
         tooltip = L["Ein Nahkampfangriff hat einen Extrangriff gewährt"],
         friendlyName = L["nahkampf zusatz angriff"],
      },
      ["SWING_ENERGIZE"] = {
         tooltip = L["Ein Nahkampfangriff hat eine Ressource (Wut, Energie, Kombopunkt) gewährt"],
         friendlyName = L["nahkampf ressource"],
      },
      ["RANGE_DAMAGE"] = {
         tooltip = L["Ein Fernkampfangriff hat Schaden verursacht"],
         friendlyName = L["fernkampf schaden"],
      },
      ["RANGE_MISSED"] = {
         tooltip = L["Ein Fernkampfangriff hat verfehlt"],
         friendlyName = L["fernkampf verfehlt"],
      },
      ["RANGE_EXTRA_ATTACKS"] = {
         tooltip = L["Ein Fernkampfangriff hat einen Extraangriff ausgelöst"],
         friendlyName = L["fernkampf zusatz angriff"],
      },
      --[[
      ["RANGE_ENERGIZE"] = {
         tooltip = L[""],
         friendlyName = L["fernkampf ressource"],
      },]]
      ["SPELL_PERIODIC_DAMAGE"] = {
         tooltip = L["A dot spell tick has caused damage"],
         friendlyName = L["dot tick"],
      },
      ["SPELL_PERIODIC_HEAL"] = {
         tooltip = L["A hot spell tick has caused damage"],
         friendlyName = L["hot tick"],
      },
      ["SPELL_DAMAGE"] = {
         tooltip = L["Ein Zauber hat Schaden verursacht"],
         friendlyName = L["zauber schaden"],
      },
      ["SPELL_MISSED"] = {
         tooltip = L["Ein Zauber hat Schaden verfehlt"],
         friendlyName = L["zauber verfehlt"],
      },
      ["SPELL_HEAL"] = {
         tooltip = L["Ein Zauber hat Heilung verursacht"],
         friendlyName = L["zauber heilung"],
      },
      ["SPELL_ENERGIZE"] = {
         tooltip = L["Ein Zauber hat eine Ressource (Mana) gewährt"],
         friendlyName = L["zauber ressource"],
      },
      ["SPELL_INTERRUPT"] = {
         tooltip = L["Ein Zauber wurde unterbrochen"],
         friendlyName = L["zauber unterbrochen"],
      },
      ["SPELL_EXTRA_ATTACKS"] = {
         tooltip = L["Ein Zauber hat einen Extraangriff gewährt"],
         friendlyName = L["zauber zusatz angriff"],
      },
      ["SPELL_CAST_FAILED"] = {
         tooltip = L["Ein Zauber ist fehlgeschlagen"],
         friendlyName = L["zauber fehlgeschlagen"],
      },
      ["SPELL_CREATE"] = {
         tooltip = L["Etwas wurde durch einen Zauber hergestellt (z. B. Berufe-Skill)"],
         friendlyName = L["zauber erstellen"], 
         friendlyNameShort = L["erstellen"],
      },
      ["SPELL_SUMMON"] = {
         tooltip = L["Etwas wurde duch einen Zauber beschworen (z. B. Leerwandler beim Hexer"],
         friendlyName = L["zauber beschwören"], 
         friendlyNameShort = L["beschwören"],
      },
      ["SPELL_RESURRECT"] = {
         tooltip = L["Ein Zauber hat etwas wiederbelebt"],
         friendlyName = L["zauber wiederbeleben"],  
         friendlyNameShort = L["wiederbeleben"],
      },
      ["UNIT_DIED"] = {
         tooltip = L["Eine Einheit (Spieler, NPC, Mob etc.) ist gestorben"],
         friendlyName = L["einheit tot"], 
         friendlyNameShort = L["tot"],
      },
      ["UNIT_DESTROYED"] = {
         tooltip = L["Etwas wurde zerstört (z. B. ein Totem)"],
         friendlyName = L["einheit zerstört"], 
         friendlyNameShort = L["zerstört"],
      },
      ["ITEM_USE"] = {
         tooltip = L["Ein Gegenstand wurde verwendet"],
         friendlyName = L["gegenstand verwenden"], 
         friendlyNameShort = L["verwenden"],
      },
      ["KEY_PRESS"] = {
         tooltip = L["Eine Taste wurde gedrückt"],
         friendlyName = L["Taste gedrückt"], 
         friendlyNameShort = L["Taste"],
      },
   --spellId
      --build from skudb on PLAYER_ENTERING_WORLD
   --itemId
      --build from skudb on PLAYER_ENTERING_WORLD
      ["itemCount"] = {
         tooltip = L["Die Anzahl der verbleibenden Gegenstände in deinen Taschen, vom Typ des Gegenstands, der das Ereignis ausgelöst hat"],
         friendlyName = L["gegenstand anzahl"], 
         friendlyNameShort = L["anzahl"],
      },
}
--add keys for pressedKey
local tKeys = KeyValuesHelper()
for i, v in pairs (tKeys) do
   SkuAuras.valuesDefault[i] = {friendlyName = v}
end

SkuAuras.values = {
}

local zeroToOneHundred = {
   "0",
   "1",
   "2",
   "3",
   "4",
   "5",
   "6",
   "7",
   "8",
   "9",
   "10",
   "11",
   "12",
   "13",
   "14",
   "15",
   "16",
   "17",
   "18",
   "19",
   "20",
   "21",
   "22",
   "23",
   "24",
   "25",
   "26",
   "27",
   "28",
   "29",
   "30",
   "31",
   "32",
   "33",
   "34",
   "35",
   "36",
   "37",
   "38",
   "39",
   "40",
   "41",
   "42",
   "43",
   "44",
   "45",
   "46",
   "47",
   "48",
   "49",
   "50",
   "51",
   "52",
   "53",
   "54",
   "55",
   "56",
   "57",
   "58",
   "59",
   "60",
   "61",
   "62",
   "63",
   "64",
   "65",
   "66",
   "67",
   "68",
   "69",
   "70",
   "71",
   "72",
   "73",
   "74",
   "75",
   "76",
   "77",
   "78",
   "79",
   "80",
   "81",
   "82",
   "83",
   "84",
   "85",
   "86",
   "87",
   "88",
   "89",
   "90",
   "91",
   "92",
   "93",
   "94",
   "95",
   "96",
   "97",
   "98",
   "99",
   "100",
           
}

local unitIDValues = {
   "target",
   "player",
   "pet",
   "party",
   "partyWoPlayer",
   "all",
   "focus",
   "party0",
   "party1",
   "party2",
   "party3",
   "party4",
   "targettarget",
   "focustarget",
   "party0target",
   "party1target",
   "party2target",
   "party3target",
   "party4target",
}

------------------------------------------------------------------------------------------------------------------
SkuAuras.attributes = {
   action = {
      tooltip = L["Du legst als nächstes die Aktion fest, die bei der Auslösung der Aura passieren soll"],
      friendlyName = L["aktion"],
      evaluate = function()
      	--dprint("    ","SkuAuras.attributes.action.evaluate")
      end,
      values = {
         "nothing",
         "notifyAudio",
         "notifyAudioSingle",
         --"notifyAudioSingleInstant",
         "notifyChat",
         "notifyChatSingle",
         "notifyAudioAndChatSingle",
      },
   },
   destUnitId = {
      tooltip = L["Die Ziel-Einheit, bei der die Aura ausgelöst werden soll"],
      friendlyName = L["ziel (L)"],
      type = "SET",
      evaluate = function(self, aEventData, aOperator, aValue)
      	--dprint("    ","SkuAuras.attributes.destUnitId.evaluate", aEventData.destUnitId)
         if aOperator == "is" then
            aOperator = "contains"
         elseif aOperator == "isNot" then
            aOperator = "containsNot"
         end
   
         if aEventData.destUnitId then

            if aValue == "all" then
               return true
            end
            local tEvaluation = false

            if aOperator == "containsNot" or aOperator == "contains" then
               
               if aValue == "party" then
                  tEvaluation = SkuAuras.Operators[aOperator].func(aEventData.destUnitId, {"player", "party0", "party1", "party2", "party3", "party4"})
               elseif aValue == "partyWoPlayer" then
                  tEvaluation = SkuAuras.Operators[aOperator].func(aEventData.destUnitId, {"party1", "party2", "party3", "party4"})
               else
                  tEvaluation = SkuAuras.Operators[aOperator].func(aEventData.destUnitId, aValue)
               end
            else
               for x = 1, #aEventData.destUnitId do
                  if aValue == "all" then
                     return true
                  elseif aValue == "party" or aValue == "partyWoPlayer" then
                     if aValue == "party" then
                        if SkuAuras.Operators[aOperator].func(aEventData.destUnitId[x], "player") == true then
                           tEvaluation = true
                        end
                     end
                     local tStart = 0
                     if aValue == "partyWoPlayer" then
                        tStart = 1
                     end
                     for x = tStart, 4 do 
                        if SkuAuras.Operators[aOperator].func(aEventData.destUnitId[x], "party"..x) == true then
                           tEvaluation = true
                        end
                     end
                     for x = 1, MAX_RAID_MEMBERS do 
                        if SkuAuras.Operators[aOperator].func(aEventData.destUnitId[x], "raid"..x) == true then
                           tEvaluation = true
                        end
                     end
                  else
                     tEvaluation = SkuAuras.Operators[aOperator].func(aEventData.destUnitId[x], aValue)
                  end
               end
            end
            if tEvaluation == true then
               return true
            end
         end
      end,
      values = unitIDValues,
   },
   targetTargetUnitId = {
      tooltip = L["Die Einheit des Ziels deines Ziels"],
      friendlyName = L["ziel deines ziels (L)"],
      type = "SET",
      evaluate = function(self, aEventData, aOperator, aValue)
      	--dprint("    ","SkuAuras.attributes.targetTargetUnitId.evaluate", aEventData.targetTargetUnitId)
         if aOperator == "is" then
            aOperator = "contains"
         elseif aOperator == "isNot" then
            aOperator = "containsNot"
         end

         if aEventData.targetTargetUnitId then
            if aValue == "all" then
               return true
            end
            local tEvaluation = false

            if aOperator == "containsNot" or aOperator == "contains" then
               
               if aValue == "party" then
                  tEvaluation = SkuAuras.Operators[aOperator].func(aEventData.targetTargetUnitId, {"player", "party0", "party1", "party2", "party3", "party4"})
               elseif aValue == "partyWoPlayer" then
                  tEvaluation = SkuAuras.Operators[aOperator].func(aEventData.targetTargetUnitId, {"party1", "party2", "party3", "party4"})
               else
                  tEvaluation = SkuAuras.Operators[aOperator].func(aEventData.targetTargetUnitId, aValue)
               end
            else            
               for x = 1, #aEventData.targetTargetUnitId do
                  if aValue == "all" then
                     return true
                  elseif aValue == "party" then
                     if aValue == "party" then
                        if SkuAuras.Operators[aOperator].func(aEventData.targetTargetUnitId[x], "player") == true then
                           tEvaluation = true
                        end
                     end
                     local tStart = 0
                     if aValue == "partyWoPlayer" then
                        tStart = 1
                     end
                     for x = tStart, 4 do 
                        if SkuAuras.Operators[aOperator].func(aEventData.targetTargetUnitId[x], "party"..x) == true then
                           tEvaluation = true
                        end
                     end
                     for x = 1, MAX_RAID_MEMBERS do 
                        if SkuAuras.Operators[aOperator].func(aEventData.targetTargetUnitId[x], "raid"..x) == true then
                           tEvaluation = true
                        end
                     end
                  else
                     tEvaluation = SkuAuras.Operators[aOperator].func(aEventData.targetTargetUnitId[x], aValue)
                  end
               end
            end
            if tEvaluation == true then
               return true
            end
         end
      end,
      values = unitIDValues,
   },   
   pressedKey = {
      tooltip = L["Welche Taste das Ereignis ausgelöst hat"],
      friendlyName = L["Taste"],
      type = "CATEGORY",
      evaluate = function(self, aEventData, aOperator, aValue)
         if aEventData.pressedKey then
            --dprint("    ","SkuAuras.attributes.pressedKey.evaluate", supper(aEventData.pressedKey), aOperator, supper(aValue))
            return SkuAuras.Operators[aOperator].func(supper(aEventData.pressedKey), supper(aValue))
         end
      end,
      values = {}, --values are added below the attributes table
   },
   tInCombat = {
      tooltip = L["Ob das Event im Kampf auftritt"],
      friendlyName = L["Im Kampf"],
      type = "BINARY",
      evaluate = function(self, aEventData, aOperator, aValue)
         --dprint("    ","SkuAuras.attributes.tInCombat.evaluate", aEventData.tInCombat, aOperator, true)
         return SkuAuras.Operators[aOperator].func(aEventData.tInCombat, aValue == "true")
      end,
      values = {
         "true",
         "false",
      },
   },
   -- [v43.0] MODIFIER, not a condition: with value "true", THIS aura's four
   -- buff/debuff list conditions and their duration conditions see only auras
   -- the player cast (EvaluateAllAuras swaps in the caster == "player" subsets
   -- and getFixedDuration reads the own exp map). Evaluate always passes so
   -- the flag never blocks the aura; the stored value carries the meaning.
   -- Solves: a debuff-list aura reacting to OTHER players' copies of the same
   -- debuff (e.g. two priests' Schattenwort: Schmerz on one target).
   listsOwnOnly = {
      tooltip = L["Ob die Listen Bedingungen nur selbst gewirkte Auren sehen"],
      friendlyName = L["Listen nur selbst gewirkte"],
      type = "BINARY",
      evaluate = function(self, aEventData, aOperator, aValue)
         return true
      end,
      values = {
         "true",
         "false",
      },
   },
   critical = {
      tooltip = L["Whether the damage or heal was critical"],
      friendlyName = L["Critical"],
      type = "BINARY",
      evaluate = function(self, aEventData, aOperator, aValue)
         return SkuAuras.Operators[aOperator].func(aEventData.critical, aValue == "true")
      end,
      values = {
         "true",
         "false",
      },
   },
   tSourceUnitIDCannAttack = {
      tooltip = L["Ob die Quell-Einheit, für die Aura ausgelöst wird, angreifbar ist"],
      friendlyName = L["Quell Einheit angreifbar"],
      type = "BINARY",
      evaluate = function(self, aEventData, aOperator, aValue)
         --dprint("    ","SkuAuras.attributes.tSourceUnitIDCannAttack.evaluate", aEventData.tSourceUnitIDCannAttack, aOperator, true)
         return SkuAuras.Operators[aOperator].func(aEventData.tSourceUnitIDCannAttack, aValue == "true")
      end,
      values = {
         "true",
         "false",
      },
   },
   tDestinationUnitIDCannAttack = {
      tooltip = L["Ob die Ziel-Einheit, für die Aura ausgelöst wird, angreifbar ist"],
      friendlyName = L["Ziel Einheit angreifbar"],
      type = "BINARY",
      evaluate = function(self, aEventData, aOperator, aValue)
         --dprint("    ","SkuAuras.attributes.tDestinationUnitIDCannAttack.evaluate", aEventData.tDestinationUnitIDCannAttack, aOperator, true)
         return SkuAuras.Operators[aOperator].func(aEventData.tDestinationUnitIDCannAttack, aValue == "true")
      end,
      values = {
         "true",
         "false",
      },
   },
   targetCannAttack = {
      tooltip = L["Whether you can attack your target"],
      friendlyName = L["Your target is attackable"],
      type = "BINARY",
      evaluate = function(self, aEventData, aOperator, aValue)
         return SkuAuras.Operators[aOperator].func(aEventData.targetCanAttack, aValue == "true")
      end,
      values = {
         "true",
         "false",
      },
   },
   sourceUnitId = {
      tooltip = L["Die Quell Einheit, bei der die Aura ausgelöst werden soll"],
      friendlyName = L["Quelle (L)"],
      type = "SET",
      evaluate = function(self, aEventData, aOperator, aValue)
      	--print("","SkuAuras.attributes.sourceUnitId.evaluate", aEventData.sourceUnitId, aOperator, aValue)
         if aOperator == "is" then
            aOperator = "contains"
         elseif aOperator == "isNot" then
            aOperator = "containsNot"
         end

         if aValue == "all" then
            return true
         end
         if aEventData.sourceUnitId then
            if type(aEventData.sourceUnitId) ~= "table" then
               aEventData.sourceUnitId = {aEventData.sourceUnitId}
            end

            if aValue == "all" then
               return true
            end
            local tEvaluation = false

            if aOperator == "containsNot" or aOperator == "contains" then
               if aValue == "party" then
                  tEvaluation = SkuAuras.Operators[aOperator].func(aEventData.sourceUnitId, {"player", "party0", "party1", "party2", "party3", "party4"})

               elseif aValue == "partyWoPlayer" then
                  tEvaluation = SkuAuras.Operators[aOperator].func(aEventData.sourceUnitId, {"party1", "party2", "party3", "party4"})
               else
                  tEvaluation = SkuAuras.Operators[aOperator].func(aEventData.sourceUnitId, aValue)
               end
            else
               for x = 1, #aEventData.sourceUnitId do
                  if aValue == "party" then
                     if aValue == "party" then
                        if SkuAuras.Operators[aOperator].func(aEventData.sourceUnitId[x], "player") == true then
                           tEvaluation = true
                        end
                     end
                     local tStart = 0
                     if aValue == "partyWoPlayer" then
                        tStart = 1
                     end
                     for x = tStart, 4 do 
                        if SkuAuras.Operators[aOperator].func(aEventData.sourceUnitId[x], "party"..x) == true then
                           tEvaluation = true
                        end
                     end
                     for x = 1, MAX_RAID_MEMBERS do 
                        if SkuAuras.Operators[aOperator].func(aEventData.sourceUnitId[x], "raid"..x) == true then
                           tEvaluation = true
                        end
                     end
                  else
                     tEvaluation = SkuAuras.Operators[aOperator].func(aEventData.sourceUnitId[x], aValue)
                  end
               end
            end

            if tEvaluation == true then
               return true
            end
         end
      end,
      values = unitIDValues,
   },
   event = {
      tooltip = L["Das Ereignis, das die Aura auslösen soll"],
      friendlyName = L["ereignis"],
      type = "CATEGORY",
      evaluate = function(self, aEventData, aOperator, aValue)
      	--print("    ","SkuAuras.attributes.event.evaluate")
         if aEventData.event then
            local tEvaluation
            if sfind(aValue, ";") then
               local tEvents = {ssplit(";", aValue)}
               for i, v in pairs(tEvents) do
                  local tSingleEvaluation = SkuAuras.Operators[aOperator].func(aEventData.event, v)
                  if tSingleEvaluation == true then
                     tEvaluation = true
                  end
               end
            else
               tEvaluation = SkuAuras.Operators[aOperator].func(aEventData.event, aValue)
            end
            if tEvaluation == true then
               return true
            end
         end
      end,
      values = {
         "UNIT_TARGETCHANGE",
         "UNIT_POWER",
         "UNIT_HEALTH",
         "SPELL_AURA_APPLIED;SPELL_AURA_REFRESH;SPELL_AURA_APPLIED_DOSE",
         "SPELL_AURA_REMOVED",
         "SPELL_CAST_START",
         "SPELL_CAST_SUCCESS",
         "SPELL_COOLDOWN_START",
         "SPELL_COOLDOWN_END",
         "ITEM_COOLDOWN_START",
         "ITEM_COOLDOWN_END",
         "WEAPON_ENCHANT_REMOVED",
         "SWING_DAMAGE",
         "SWING_MISSED",
         "SWING_EXTRA_ATTACKS",
         "SWING_ENERGIZE",
         "RANGE_DAMAGE",
         "RANGE_MISSED",
         "RANGE_EXTRA_ATTACKS",
         --"RANGE_ENERGIZE",
         "SPELL_PERIODIC_DAMAGE",
         "SPELL_PERIODIC_HEAL",
         "SPELL_DAMAGE",
         "SPELL_MISSED",
         "SPELL_HEAL",
         "SPELL_ENERGIZE",
         "SPELL_INTERRUPT",
         "SPELL_EXTRA_ATTACKS",
         "SPELL_CAST_FAILED",
         "SPELL_CREATE",
         "SPELL_SUMMON",
         "SPELL_RESURRECT",
         "UNIT_DIED",
         "UNIT_DESTROYED",
         "ITEM_USE",
         "KEY_PRESS",
      },
   },
   missType = {
      tooltip = L["Der Typ des Verfehlen Ereignisses"],
      friendlyName = L["Verfehlen Typ"],
      type = "CATEGORY",
      evaluate = function(self, aEventData, aOperator, aValue)
      	--dprint("    ","SkuAuras.attributes.missType.evaluate")
         if aEventData.missType then
            return SkuAuras.Operators[aOperator].func(aEventData.missType, aValue)
         end
      end,
      values = {
         "ABSORB",
         "BLOCK",
         "DEFLECT",
         "DODGE",
         "EVADE",
         "IMMUNE",
         "MISS",
         "PARRY",
         "REFLECT",
         "RESIST",
      },
   },
   targetUnitDistance = {
      tooltip = L["Distance to your current target"],
      friendlyName = L["target distance"],
      type = "ORDINAL",
      evaluate = function(self, aEventData, aOperator, aValue)
      	dprint("    ","SkuAuras.attributes.targetUnitDistance.evaluate", aEventData.targetUnitDistance)
         if aEventData.targetUnitDistance then
            local tEvaluation = SkuAuras.Operators[aOperator].func(tonumber(aEventData.targetUnitDistance), tonumber(aValue))
            if tEvaluation == true then
               return true
            end
         end
      end,
      values = zeroToOneHundred,
   },   
   unitPowerPlayer = {
      tooltip = L["AURA_PowerActiveTip"],
      friendlyName = L["AURA_PowerActive"],
      type = "ORDINAL",
      evaluate = function(self, aEventData, aOperator, aValue)
      	--dprint("    ","SkuAuras.attributes.unitPowerPlayer.evaluate")
         if aEventData.unitPowerPlayer then
            local tEvaluation = SkuAuras.Operators[aOperator].func(tonumber(aEventData.unitPowerPlayer), tonumber(aValue))
            if tEvaluation == true then
               return true
            end
         end
      end,
      values = zeroToOneHundred,
   },
   -- [v43.1] The SPECIFIC power pools, beside unitPowerPlayer's "whatever bar
   -- the game is showing". Same split the resource monitor has had all along
   -- (SkuCore/aq.lua, tPowerTypes: ACTIVE / MANA / RAGE / ENERGY / RUNIC_POWER),
   -- so a druid can say "mana under 20" and have it mean mana in cat form too,
   -- where unitPowerPlayer reads energy.
   --
   -- The reading is nil, and the condition therefore false, for a pool the
   -- character does not have - UnitPowerMax comes back 0 for a warrior's mana -
   -- which is what keeps "Eigenes Mana kleiner 20" from firing on every warrior
   -- event. The fields are LAZY (Core.lua, tLazyEvaluateFields): four more
   -- UnitPower pairs on every combat-log event would be paid by every user,
   -- and only an aura that asks needs them.
   unitManaPlayer = {
      tooltip = L["AURA_PowerManaTip"],
      friendlyName = L["AURA_PowerMana"],
      type = "ORDINAL",
      evaluate = function(self, aEventData, aOperator, aValue)
         if aEventData.unitManaPlayer then
            return SkuAuras.Operators[aOperator].func(tonumber(aEventData.unitManaPlayer), tonumber(aValue)) == true
         end
      end,
      values = zeroToOneHundred,
   },
   unitRagePlayer = {
      tooltip = L["AURA_PowerRageTip"],
      friendlyName = L["AURA_PowerRage"],
      type = "ORDINAL",
      evaluate = function(self, aEventData, aOperator, aValue)
         if aEventData.unitRagePlayer then
            return SkuAuras.Operators[aOperator].func(tonumber(aEventData.unitRagePlayer), tonumber(aValue)) == true
         end
      end,
      values = zeroToOneHundred,
   },
   unitEnergyPlayer = {
      tooltip = L["AURA_PowerEnergyTip"],
      friendlyName = L["AURA_PowerEnergy"],
      type = "ORDINAL",
      evaluate = function(self, aEventData, aOperator, aValue)
         if aEventData.unitEnergyPlayer then
            return SkuAuras.Operators[aOperator].func(tonumber(aEventData.unitEnergyPlayer), tonumber(aValue)) == true
         end
      end,
      values = zeroToOneHundred,
   },
   unitRunicPowerPlayer = {
      tooltip = L["AURA_PowerRunicTip"],
      friendlyName = L["AURA_PowerRunic"],
      type = "ORDINAL",
      evaluate = function(self, aEventData, aOperator, aValue)
         if aEventData.unitRunicPowerPlayer then
            return SkuAuras.Operators[aOperator].func(tonumber(aEventData.unitRunicPowerPlayer), tonumber(aValue)) == true
         end
      end,
      values = zeroToOneHundred,
   },
   unitComboPlayer = {
      tooltip = L["Dein combopunkte auf das aktuelle ziel, die die Aura auslösen sollen"],
      friendlyName = L["Eigene combopunkte"],
      type = "ORDINAL",
      evaluate = function(self, aEventData, aOperator, aValue)
      	dprint("    ","SkuAuras.attributes.unitComboPlayer.evaluate", aEventData.unitComboPlayer)
         if aEventData.unitComboPlayer then
            local tEvaluation = SkuAuras.Operators[aOperator].func(tonumber(aEventData.unitComboPlayer), tonumber(aValue))
            if tEvaluation == true then
               return true
            end
         end
      end,
      values = {
         "0",
         "1",
         "2",
         "3",
         "4",
         "5",
      },
   },   
   unitHealthPlayer = {
      tooltip = L["Dein gesundheits Level in Prozent, das die Aura auslösen soll"],
      friendlyName = L["Eigene Gesundheit"],
      type = "ORDINAL",
      evaluate = function(self, aEventData, aOperator, aValue)
      	--dprint("    ","SkuAuras.attributes.unitHealthPlayer.evaluate")
         if aEventData.unitHealthPlayer then
            local tEvaluation = SkuAuras.Operators[aOperator].func(tonumber(aEventData.unitHealthPlayer), tonumber(aValue))
            if tEvaluation == true then
               return true
            end
         end
      end,
      values = zeroToOneHundred,      
   },
   unitHealthTarget = {
      tooltip = L["Your target's health percentage"],
      friendlyName = L["Your target's health"],
      type = "ORDINAL",
      evaluate = function(self, aEventData, aOperator, aValue)
         return aEventData.unitHealthTarget and SkuAuras.Operators[aOperator].func(aEventData.unitHealthTarget, tonumber(aValue))
      end,
      values = zeroToOneHundred,
   },
   unitPowerTarget = {
      tooltip = L["Percentage of your target's primary resource, for example mana or rage"],
      friendlyName = L["Your target's resource"],
      type = "ORDINAL",
      evaluate = function(self, aEventData, aOperator, aValue)
         return aEventData.unitPowerTarget and SkuAuras.Operators[aOperator].func(aEventData.unitPowerTarget, tonumber(aValue))
      end,
      values = zeroToOneHundred,
   },
   unitHealthOrPowerUpdate = {
      tooltip = L["The updated health or resource percentage from a health update or resource update event"],
      friendlyName = L["Health/Resource update"],
      type = "ORDINAL",
      evaluate = function(self, aEventData, aOperator, aValue)
         return aEventData.unitHealthOrPowerUpdate and SkuAuras.Operators[aOperator].func(aEventData.unitHealthOrPowerUpdate, tonumber(aValue))
      end,
      values = zeroToOneHundred,
   },
   overhealingPercentage = {
      tooltip = L["How much of the healing amount was overhealing"],
      friendlyName = L["Overhealing percentage"],
      type = "ORDINAL",
      evaluate = function(self, aEventData, aOperator, aValue)
         return aEventData.overhealingPercentage and SkuAuras.Operators[aOperator].func(aEventData.overhealingPercentage, tonumber(aValue))
      end,
      values = zeroToOneHundred,
   },
   spellId = {
      tooltip = L["Die Zauber-ID, die die Aura auslösen soll"],
      friendlyName = L["zauber nr"],
      type = "CATEGORY",
      evaluate = function(self, aEventData, aOperator, aValue)
      	--print("SkuAuras.attributes.spellId.evaluate aEventData", aEventData, "aOperator", aOperator, "aValue", aValue)
         if aEventData.spellId then
            local tEvaluation = SkuAuras.Operators[aOperator].func(tonumber(aEventData.spellId), tonumber(SkuAuras:RemoveTags(aValue)))
            if tEvaluation == true then
               return true
            end
         end
      end,
      values = {
      },      
   },
   spellNameOnCd = {
      tooltip = L["Ob ein Zauber gerade auf CD ist"],
      friendlyName = L["zauber auf cd (L)"],
      type = "SET",
      evaluate = function(self, aEventData, aOperator, aValue)
      	--dprint("    ","SkuAuras.attributes.spellNameOnCd.evaluate", aEventData, aOperator, aValue)
         if aOperator == "is" then
            aOperator = "contains"
         elseif aOperator == "isNot" then
            aOperator = "containsNot"
         end

         if aEventData.spellNameOnCd then
            local tEvaluation = SkuAuras.Operators[aOperator].func(aEventData.spellNameOnCd, SkuAuras:RemoveTags(aValue))
            if tEvaluation == true then
               return true
            end
         end
      end,
      values = {
      },      
   },
--[[
   spellNameNotOnCd = {
      tooltip = L["Ob ein Zauber gerade nicht auf CD ist"],
      friendlyName = L["zauber nicht auf cd (L)"],
      evaluate = function(self, aEventData, aOperator, aValue)
      	--dprint("    ","SkuAuras.attributes.spellNameNotOnCd.evaluate", aValue)
         if aEventData.spellsNamesOnCd then
            --dprint("aEventData.spellsNamesOnCd")
            setmetatable(aEventData.spellsNamesOnCd, SkuPrintMTWo)
            --dprint(aEventData.spellsNamesOnCd)
      
            local tEvaluation = SkuAuras.Operators[aOperator].func(aEventData.spellsNamesOnCd[aValue], aValue)
            if tEvaluation == false then
               return true
            end
         end
      end,
      values = {
      },      
   },
]]
   spellName = {
      tooltip = L["Der Zauber-name, der die Aura auslösen soll"],
      friendlyName = L["zauber name"],
      type = "CATEGORY",
      evaluate = function(self, aEventData, aOperator, aValue)
      	--dprint("    ","SkuAuras.attributes.spellName.evaluate")
         -- [v43.0] Group lane (aEventData.spellGroup, the event spell's enUS
         -- name) with the localized live name as the fallback lane. Unlike the
         -- buff lists this is a scalar, so it cannot carry both forms as keys
         -- and needs the negation-aware combiner.
         if aEventData.spellName then
            if MatchAnyForm(aOperator, aValue, aEventData.spellGroup, aEventData.spellName) == true then
               return true
            end
         end
      end,
      values = {
      },      
   },
   buffListTarget = {
      tooltip = L["Die Liste der Buffs des Ziels"],
      friendlyName = L["Buff Liste Ziel (L)"],
      type = "SET",
      evaluate = function(self, aEventData, aOperator, aValue)
      	--dprint("    ","SkuAuras.attributes.buffListTarget.evaluate", aEventData, aOperator, aValue)
         if aEventData.buffListTarget then
            local tEvaluation = SkuAuras.Operators[aOperator].func(aEventData.buffListTarget, SkuAuras:RemoveTags(aValue))
            if tEvaluation == true then
               return true
            end
         end
         return false
      end,
      values = {
      },      
   },
   debuffListTarget = {
      tooltip = L["Die Liste der Debuffs  des Ziels"],
      friendlyName = L["Debuff Liste Ziel (L)"],
      type = "SET",
      evaluate = function(self, aEventData, aOperator, aValue)
      	--dprint("    ","SkuAuras.attributes.debuffListTarget.evaluate", aEventData.debuffListTarget)
         if aEventData.debuffListTarget then
            local tEvaluation = SkuAuras.Operators[aOperator].func(aEventData.debuffListTarget, SkuAuras:RemoveTags(aValue))
            if tEvaluation == true then
               return true
            end
         end
         return false
      end,
      values = {
      },      
   },
   buffListPlayer = {
      tooltip = L["Your list of buffs"],
      friendlyName = L["Your buff list (L)"],
      type = "SET",
      evaluate = function(self, aEventData, aOperator, aValue)
         return aEventData.buffListPlayer ~= nil and SkuAuras.Operators[aOperator].func(aEventData.buffListPlayer, SkuAuras:RemoveTags(aValue)) == true
      end,
      values = {},      
   },
   debuffListPlayer = {
      tooltip = L["Your list of dbuffs"],
      friendlyName = L["Your debuff list (L)"],
      type = "SET",
      evaluate = function(self, aEventData, aOperator, aValue)
         return aEventData.debuffListPlayer ~= nil and SkuAuras.Operators[aOperator].func(aEventData.debuffListPlayer, SkuAuras:RemoveTags(aValue)) == true
      end,
      values = {},      
   },








   
   buffListTargetDuration = {
      tooltip = L["The remaining duration of the buff from the buff list target (L) condition"],
      friendlyName = L["buff list target remaining duration"],
      type = "THRESHOLD",
      evaluate = function(self, aEventData, aOperator, aValue)
         if aEventData.buffListTargetDuration then
            local tEvaluation = SkuAuras.Operators[aOperator].func(tonumber(aEventData.buffListTargetDuration), tonumber(aValue))
            if tEvaluation == true then
               return true
            end
         end
      end,
      values = zeroToOneHundred,      
   },
   debuffListTargetDuration = {
      tooltip = L["The remaining duration of the debuff from the debuff list target (L) condition"],
      friendlyName = L["Debuff list target remaining duration"],
      type = "THRESHOLD",
      evaluate = function(self, aEventData, aOperator, aValue)
         if aEventData.debuffListTargetDuration then
            local tEvaluation = SkuAuras.Operators[aOperator].func(tonumber(aEventData.debuffListTargetDuration), tonumber(aValue))
            if tEvaluation == true then
               return true
            end
         end
      end,
      values = zeroToOneHundred,      
   },   
   buffListPlayerDuration = {
      tooltip = L["The remaining duration of the buff from the your buff list (L) condition"],
      friendlyName = L["Your buff list remaining duration"],
      type = "THRESHOLD",
      evaluate = function(self, aEventData, aOperator, aValue)
         if aEventData.buffListPlayerDuration then
            local tEvaluation = SkuAuras.Operators[aOperator].func(tonumber(aEventData.buffListPlayerDuration), tonumber(aValue))
            if tEvaluation == true then
               return true
            end
         end
      end,
      values = zeroToOneHundred,      
   },   
   debuffListPlayerDuration = {
      tooltip = L["The remaining duration of the debuff from the your debuff list (L) condition"],
      friendlyName = L["Your debuff list remaining duration"],
      type = "THRESHOLD",
      evaluate = function(self, aEventData, aOperator, aValue)
         if aEventData.debuffListPlayerDuration then
            local tEvaluation = SkuAuras.Operators[aOperator].func(tonumber(aEventData.debuffListPlayerDuration), tonumber(aValue))
            if tEvaluation == true then
               return true
            end
         end
      end,
      values = zeroToOneHundred,      
   },

   -- [41.03] Waffenbuff-Auren (additiv, eigene Kategorie). Spiegelt buffListPlayer
   -- (SET) und buffListPlayerDuration (ORDINAL). Befuellung in Core.lua EvaluateAllAuras.
   -- RUECKBAU: diese 4 Attribute entfernen.
   weaponEnchantMainHand = {
      tooltip = L["AURA_WeMHTip"],
      friendlyName = L["AURA_WeMH"],
      type = "SET",
      evaluate = function(self, aEventData, aOperator, aValue)
         return aEventData.weaponEnchantMainHand ~= nil and SkuAuras.Operators[aOperator].func(aEventData.weaponEnchantMainHand, SkuAuras:RemoveTags(aValue)) == true
      end,
      values = {},
   },
   weaponEnchantOffHand = {
      tooltip = L["AURA_WeOHTip"],
      friendlyName = L["AURA_WeOH"],
      type = "SET",
      evaluate = function(self, aEventData, aOperator, aValue)
         return aEventData.weaponEnchantOffHand ~= nil and SkuAuras.Operators[aOperator].func(aEventData.weaponEnchantOffHand, SkuAuras:RemoveTags(aValue)) == true
      end,
      values = {},
   },
   weaponEnchantMainHandDuration = {
      tooltip = L["AURA_WeMHDurTip"],
      friendlyName = L["AURA_WeMHDur"],
      type = "THRESHOLD",
      evaluate = function(self, aEventData, aOperator, aValue)
         if aEventData.weaponEnchantMainHandDuration then
            local tEvaluation = SkuAuras.Operators[aOperator].func(tonumber(aEventData.weaponEnchantMainHandDuration), tonumber(aValue))
            if tEvaluation == true then
               return true
            end
         end
      end,
      values = zeroToOneHundred,
   },
   weaponEnchantOffHandDuration = {
      tooltip = L["AURA_WeOHDurTip"],
      friendlyName = L["AURA_WeOHDur"],
      type = "THRESHOLD",
      evaluate = function(self, aEventData, aOperator, aValue)
         if aEventData.weaponEnchantOffHandDuration then
            local tEvaluation = SkuAuras.Operators[aOperator].func(tonumber(aEventData.weaponEnchantOffHandDuration), tonumber(aValue))
            if tEvaluation == true then
               return true
            end
         end
      end,
      values = zeroToOneHundred,
   },

   itemName = {
      tooltip = L["Der Gegenstandsname, der die Aura auslösen soll"],
      friendlyName = L["gegenstand name"],
      type = "CATEGORY",
      evaluate = function(self, aEventData, aOperator, aValue)
      	--dprint("    ","SkuAuras.attributes.itemName.evaluate")
         if aEventData.itemName then
            local tEvaluation = SkuAuras.Operators[aOperator].func(aEventData.itemName, aValue)
            if tEvaluation == true then
               return true
            end
         end
      end,
      values = {
      },      
   },
   itemId = {
      tooltip = L["Die Gegenstands-ID, die die Aura auslösen soll"],
      friendlyName = L["gegenstand nr"],
      type = "CATEGORY",
      evaluate = function(self, aEventData, aOperator, aValue)
      	--dprint("    ","SkuAuras.attributes.itemId.evaluate")
         if aEventData.itemId then
            local tEvaluation = SkuAuras.Operators[aOperator].func(tonumber(aEventData.itemId), tonumber(aValue))
            if tEvaluation == true then
               return true
            end
         end
      end,
      values = {
      },      
   },
   itemCount = {
      tooltip = L["Die verbleibende Menge eines Gegenstands in deinen Taschen, bei der die auslösen soll"],
      friendlyName = L["gegenstand anzahl"],
      type = "ORDINAL",
      evaluate = function(self, aEventData, aOperator, aValue)
      	--dprint("    ","SkuAuras.attributes.itemCount.evaluate")
         if aEventData.itemCount then
            local tEvaluation = SkuAuras.Operators[aOperator].func(tonumber(aEventData.itemCount), tonumber(aValue))
            if tEvaluation == true then
               return true
            end
         end
      end,
      values = zeroToOneHundred,      
   },
   auraType = {
      tooltip = L["Der Aura-Typ (Buff oder Debuff), der die Aura auslösen soll"],
      friendlyName = L["buff/debuff"],
      type = "BINARY",
      evaluate = function(self, aEventData, aOperator, aValue)
      	--dprint("    ","SkuAuras.attributes.auraType.evaluate")
         if aEventData.auraType then
            local tEvaluation = SkuAuras.Operators[aOperator].func(aEventData.auraType, aValue)
            if tEvaluation == true then
               return true
            end
         end
      end,
      values = {
         "BUFF",
         "DEBUFF",
      },      
   },
   auraAmount = {
      tooltip = L["Die Anzahl der Stacks einer Aura (Buff oder Debuff), bei der die Aura auslösen soll"],
      friendlyName = L["aura stacks"],
      type = "ORDINAL",
      evaluate = function(self, aEventData, aOperator, aValue)
      	--dprint("    ","SkuAuras.attributes.auraAmount.evaluate")
         if aEventData.auraAmount then
            local tEvaluation = SkuAuras.Operators[aOperator].func(tonumber(aEventData.auraAmount), tonumber(aValue))
            if tEvaluation == true then
               return true
            end
         end
      end,
      values = zeroToOneHundred,      
   },
   class = {
      tooltip = L["Der Klasse, die die Aura auslösen soll"],
      friendlyName = L["klasse"],
      type = "CATEGORY",
      evaluate = function()
      	--dprint("    ","SkuAuras.attributes.class.evaluate")












      end,
      values = {
         "Warrior",
         "Paladin",
         "Hunter",
         "Rogue",
         "Priest",
         "Death Knight",
         "Shaman",
         "Mage",
         "Warlock",
         --"Monk",
         "Druid",
         "Demon Hunter",
      },      
   },
   spellNameUsable = {
      tooltip = L["If a spell is usable (range, cooldown, stance, etc.)"],--L["Der Zauber-name, der die Aura auslösen soll"],
      friendlyName = L["Spell usable"], --L["zauber name"],
      type = "SET",
      evaluate = function(self, aEventData, aOperator, aValue)
      	--dprint("    ","SkuAuras.attributes.spellNameOnCd.evaluate", aEventData, aOperator, aValue)
         if aOperator == "is" then
            aOperator = "contains"
         elseif aOperator == "isNot" then
            aOperator = "containsNot"
         end

         if aEventData.spellNameUsable then
            local tEvaluation = SkuAuras.Operators[aOperator].func(aEventData.spellNameUsable, SkuAuras:RemoveTags(aValue))
            if tEvaluation == true then
               return true
            end
         end
      end,
      values = {
      },      
      updateValues = function(self)
         -- [v43.0] Group identity, deduped, built into a local and published in
         -- one assignment (the value-list lesson: an abort mid-fill used to leave
         -- a permanently half-populated list). Also nil-tolerant on the locale
         -- sub-table - the unguarded index this used to do is the exact shape
         -- that threw on a French client.
         local tValues, tSeen = {}, {}
         local tNameKey = SkuDB.spellKeys["name_lang"]
         for spellId, spellData in pairs(SkuDB.SpellDataTBC) do
            if C_ActionBar.FindSpellActionButtons(spellId) then
               local tLocData = spellData and (spellData[Sku.Loc] or spellData.enUS or spellData.deDE)
               local spellName = tLocData and tLocData[tNameKey]
               if spellName then
                  local tEnData = spellData.enUS
                  local tGroupValue = SkuAuras.SPELL_GROUP_TAG..tostring((tEnData and tEnData[tNameKey]) or spellName)
                  if not tSeen[tGroupValue] then
                     tSeen[tGroupValue] = true
                     tValues[#tValues + 1] = tGroupValue
                  end
                  if not SkuAuras.values[tGroupValue] then
                     SkuAuras.values[tGroupValue] = {friendlyName = spellName,}
                  end
                  if not SkuAuras.values["spell:"..tostring(spellId)] then
                     SkuAuras.values["spell:"..tostring(spellId)] = {friendlyName = spellId.." ("..spellName..")",}
                  end
               end
            end
         end
         SkuAuras.attributes.spellNameUsable.values = tValues
      end,
   },

}
local tKeys = KeyValuesHelper()
for i, v in pairs (tKeys) do
   table.insert(SkuAuras.attributes.pressedKey.values , i)
end

------------------------------------------------------------------------------------------------------------------
SkuAuras.Operators = {
   ["then"] = {
      tooltip = L[""],
      friendlyName = L["dann"],
      func = function(a) 
      	--dprint("    ","action", a)
         return
      end,
   },
   ["is"] = {
      tooltip = L["Gewähltes Attribut entspricht dem gewählten Wert"],
      friendlyName = L["gleich"],
      func = function(aValueA, aValueB) 
         if aValueA == nil or aValueB == nil then return false end
         if type(aValueA) == "table" then 
            for tName, tValue in pairs(aValueA) do
               if type(aValueB) == "table" then
                  for tNameB, tValueB in pairs(aValueB) do
                     local tResult = SkuAuras:RemoveTags(tValue) == SkuAuras:RemoveTags(tValueB)
                     if tResult == true then
                        return true
                     end
                  end
               else
                  local tResult = SkuAuras:RemoveTags(tValue) == SkuAuras:RemoveTags(aValueB)
                  if tResult == true then
                     return true
                  end
               end
            end
         else
            --print("aValueA", "-"..tostring(SkuAuras:RemoveTags(aValueA)).."-", "aValueB", "-"..tostring(SkuAuras:RemoveTags(aValueB)).."-", SkuAuras:RemoveTags(aValueA) == SkuAuras:RemoveTags(aValueB), tostring(aValueA) == tostring(aValueB))
            if SkuAuras:RemoveTags(aValueA) == SkuAuras:RemoveTags(aValueB) then 
               return true 
            end
         end
         return false
      end,
   },
   ["isNot"] = {
      tooltip = L["Gewähltes Attribut entspricht nicht dem gewählten Wert"],
      friendlyName = L["ungleich"],
      func = function(aValueA, aValueB) 
         if aValueA == nil or aValueB == nil then return false end
         if type(aValueA) == "table" then 
            for tName, tValue in pairs(aValueA) do
               if type(aValueB) == "table" then
                  for tNameB, tValueB in pairs(aValueB) do
                     local tResult = SkuAuras:RemoveTags(tValue) == SkuAuras:RemoveTags(tValueB)
                     if tResult == true then
                        return true
                     end
                  end
               else
                  local tResult = SkuAuras:RemoveTags(tValue) == SkuAuras:RemoveTags(aValueB)
                  if tResult == true then
                     return true
                  end
               end
            end
         else

            if SkuAuras:RemoveTags(aValueA) ~= SkuAuras:RemoveTags(aValueB) then 
               return true 
            end
         end
         return false
      end,
   },
   ["contains"] = {
      tooltip = L["Gewähltes Attribut enthält den gewählten Wert"],
      friendlyName = L["enthält"],
      func = function(aValueA, aValueB) 
         if not aValueA or not aValueB then return false end
         if type(aValueB) ~= "table" then 
            aValueB = {aValueB}
         end
         if type(aValueA) == "table" then 
            for tName, tValue in pairs(aValueA) do
               for tNameB, tValueB in pairs(aValueB) do
                  local tResult = SkuAuras:RemoveTags(tValue) == SkuAuras:RemoveTags(tValueB)
                  if tResult == true then
                     return true
                  end
               end
            end
         else
            for tNameB, tValueB in pairs(aValueB) do
               if SkuAuras:RemoveTags(aValueA) == SkuAuras:RemoveTags(tValueB) then 
                  return true 
               end
            end
         end
      end,
   },   
   ["containsNot"] = {
      tooltip = L["Gewähltes Attribut enthält nicht den gewählten Wert"],
      friendlyName = L["enthält nicht"],
      func = function(aValueA, aValueB) 
         if not aValueA or not aValueB then return false end
         if type(aValueB) ~= "table" then 
            aValueB = {aValueB}
         end

         if type(aValueA) == "table" then 
            local tFound = false
            for tName, tValue in pairs(aValueA) do
               for tNameB, tValueB in pairs(aValueB) do
                  local tResult = SkuAuras:RemoveTags(tValue) == SkuAuras:RemoveTags(tValueB)
                  if tResult == true then
                     tFound = true
                  end
               end
            end
            if tFound == false then
               return true
            else
               return false
            end
         else
            local tFound = false
            for tNameB, tValueB in pairs(aValueB) do
               if SkuAuras:RemoveTags(aValueA) == SkuAuras:RemoveTags(tValueB) then 
                  tFound = true
               end
            end
            if tFound == false then
               return true
            else
               return false
            end            
         end
      end,
   },   
   ["bigger"] = {
      tooltip = L["Gewähltes Attribut ist größer als der gewählte Wert"],
      friendlyName = L["größer"],
      func = function(aValueA, aValueB) 
         if not aValueA or not aValueB then return false end
         if type(aValueA) == "table" then return false end
         if tonumber(SkuAuras:RemoveTags(aValueA)) > tonumber(SkuAuras:RemoveTags(aValueB)) then 
            return true 
         end
         return false
      end,
   },
   ["smaller"] = {
      tooltip = L["Gewähltes Attribut ist kleiner als der gewählte Wert"],
      friendlyName = L["kleiner"],
      func = function(aValueA, aValueB) 
         if not aValueA or not aValueB then return false end
         if type(aValueA) == "table" then return false end
         if tonumber(SkuAuras:RemoveTags(aValueA)) < tonumber(SkuAuras:RemoveTags(aValueB)) then 
            return true 
         end
         return false
      end,
   },
}

---Returns a subset of the operators table, with only given operators
local function operatorsSubset(...)
   local subset = {}
   for i, op in pairs({ ... }) do
      subset[op] = SkuAuras.Operators[op]
   end
   return subset
end

------------------------------------------------------------------------------------------------------------------
---The type of an attribute defines what operators it supports.
SkuAuras.operatorsForAttributeType = {
   ---Attributes that can only be checked for equality (e.g. spell name, class)
   CATEGORY = operatorsSubset("is", "isNot"),
   -- Attributes with only 2 possible values (e.g. in combat)
   BINARY = operatorsSubset("is"),
   ---Attributes that can also be compared to be bigger/smaller (e.g. health, resource)
   ORDINAL = operatorsSubset("is", "isNot", "bigger", "smaller"),
   ---Supports checking if contains a given element (e.g. source, buff list)
   SET = operatorsSubset("contains", "containsNot"),
   -- [v43.1] A CONTINUOUSLY falling numeric reading: the remaining duration of a
   -- buff, a debuff or a weapon enchant. Same comparisons as ORDINAL minus the
   -- two that are useless on it:
   --   "gleich 8"    - the reading is a float that is sampled on events, so it
   --                   is essentially never exactly 8; the condition would
   --                   simply never fire, and a condition that cannot fire is
   --                   worse than a missing one because it looks right.
   --   "ungleich 8"  - the same fact inverted: always true, so it is not a
   --                   condition at all.
   -- Only a THRESHOLD ("weniger als 5 Sekunden übrig") says anything about a
   -- value that is falling past you. Stored auras are untouched: the operators
   -- still exist and still evaluate, they are only gone from the builder.
   THRESHOLD = operatorsSubset("bigger", "smaller"),
}

------------------------------------------------------------------------------------------------------------------
-- [v43.1] Only the NAME lookup is left of this table. The aura builder no
-- longer offers a type choice: every aura it creates is "if", and the type step
-- is gone from the flow.
--
-- "ifNot" stays here, and its branch stays in the evaluator, so a legacy or
-- imported aura keeps working - but nothing can create a new one. Why it went:
--   * it was expressible as "if" throughout. One condition is the negating
--     operator (CATEGORY isNot, SET containsNot, BINARY has two values, ORDINAL
--     isNot/bigger/smaller); several conditions compose through the BINARY
--     skuAura<Name> attribute ("if skuAuraX is false").
--   * measured 2026-08-23: 0 of the 22 auras in the live account and 0 of the
--     19 shipped default-set auras were ifNot; not one negating operator was in
--     use anywhere either.
--   * it was already degraded. The evaluation loop BREAKS on the first false
--     condition, and for ifNot that break IS the fire path - so the five
--     output-feeding assignments after it never run for any attribute past the
--     break, and an ifNot aura that announces a buff name can announce nothing.
--     tAuraWatchesEvent (Core.lua) also reasons affirmatively by construction.
SkuAuras.Types = {
   ["if"] = {
      tooltip = L["Wenn die Bedingungen dieser Aura zutreffen"],
      friendlyName = L["Wenn"],
   },
   ["ifNot"] = {
      tooltip = L["Wenn die Bedingungen dieser Aura nicht zutreffen"],
      friendlyName = L["Wenn nicht"],
   },
}