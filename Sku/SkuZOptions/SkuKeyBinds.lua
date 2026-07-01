---------------------------------------------------------------------------------------------------------------------------------------
local MODULE_NAME, MODULE_PART = "SkuOptions", "SkuKeyBinds"  
local L = Sku.L

SkuOptions = SkuOptions or LibStub("AceAddon-3.0"):NewAddon("SkuOptions", "AceConsole-3.0", "AceEvent-3.0")

SkuOptions.skuDefaultKeyBindings = {
   ["SKU_KEY_SELECTNEXTBASEWAYPOINT"] = {key = "", object = "SkuNav", func = "CreateSkuNavMain",},

   ["SKU_KEY_TARGETDISTANCE"] = {key = "", object = "SkuCoreControlOption1", script = "OnHide",},
   ["SKU_KEY_PANICMODE"] = {key = "CTRL-SHIFT-Y", object = "SkuCoreControlOption1", script = "OnHide",},
   ["SKU_KEY_MOUSEFINDER"] = {key = "", object = "SkuCoreControlOption1", script = "OnHide",},
   ["SKU_KEY_MMSCANWIDE"] = {key = "CTRL-SHIFT-F", object = "SkuCoreControlOption1", script = "OnHide",},
   ["SKU_KEY_MMSCANNARROW"] = {key = "CTRL-SHIFT-R", object = "SkuCoreControlOption1", script = "OnHide",},
   ["SKU_KEY_STARTRRFOLLOW"] = {key = "CTRL-SHIFT-Z", object = "SkuNav", func = "CreateSkuNavMain",},
   --["SKU_KEY_SKUMMOPEN"] = {key = "ALT-K", object = "SkuNav", func = "CreateSkuNavMain",},
   --["SKU_KEY_SKURTMMDISPLAY"] = {key = "ALT-L", object = "SkuNav", func = "CreateSkuNavMain",},
   ["SKU_KEY_MOVETONEXTWP"] = {key = "CTRL-SHIFT-W", object = "SkuNav", func = "CreateSkuNavMain",},
   ["SKU_KEY_MOVETOPREVWP"] = {key = "CTRL-SHIFT-S", object = "SkuNav", func = "CreateSkuNavMain",},
   ["SKU_KEY_ADDLARGEWP"] = {key = "ALT-O", object = "SkuNav", func = "CreateSkuNavMain",},
   ["SKU_KEY_ADDSMALLWP"] = {key = "ALT-P", object = "SkuNav", func = "CreateSkuNavMain",},
   ["SKU_KEY_TOGGLEMMSIZE"] = {key = "SHIFT-M", object = "SkuNav", func = "CreateSkuNavMain",},
   ["SKU_KEY_QUICKWP1"] = {key = "SHIFT-F5", object = "SkuNav", func = "CreateSkuNavMain",},
   ["SKU_KEY_QUICKWP1SET"] = {key = "CTRL-SHIFT-F5", object = "SkuNav", func = "CreateSkuNavMain",},
   ["SKU_KEY_QUICKWP2"] = {key = "SHIFT-F6", object = "SkuNav", func = "CreateSkuNavMain",},
   ["SKU_KEY_QUICKWP2SET"] = {key = "CTRL-SHIFT-F6", object = "SkuNav", func = "CreateSkuNavMain",},
   ["SKU_KEY_QUICKWP3"] = {key = "SHIFT-F7", object = "SkuNav", func = "CreateSkuNavMain",},
   ["SKU_KEY_QUICKWP3SET"] = {key = "CTRL-SHIFT-F7", object = "SkuNav", func = "CreateSkuNavMain",},
   ["SKU_KEY_QUICKWP4"] = {key = "SHIFT-F8", object = "SkuNav", func = "CreateSkuNavMain",},
   ["SKU_KEY_QUICKWP4SET"] = {key = "CTRL-SHIFT-F8", object = "SkuNav", func = "CreateSkuNavMain",},
   ["SKU_KEY_DEBUGMODE"] = {key = "CTRL-SHIFT-F3", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_QUESTSHARE"] = {key = "CTRL-SHIFT-T", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_OPENMENU"] = {key = "SHIFT-F1", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_MENUQUICK1"] = {key = "SHIFT-F9", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_MENUQUICK2"] = {key = "SHIFT-F10", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_MENUQUICK3"] = {key = "SHIFT-F11", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_MENUQUICK4"] = {key = "SHIFT-F12", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_MENUQUICK1SET"] = {key = "CTRL-SHIFT-F9", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_MENUQUICK2SET"] = {key = "CTRL-SHIFT-F10", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_MENUQUICK3SET"] = {key = "CTRL-SHIFT-F11", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_MENUQUICK4SET"] = {key = "CTRL-SHIFT-F12", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_ROLLNEED"] = {key = "CTRL-SHIFT-B", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_ROLLGREED"] = {key = "CTRL-SHIFT-G", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_ROLLPASS"] = {key = "CTRL-SHIFT-X", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_ROLLINFO"] = {key = "CTRL-SHIFT-C", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_STOPTTSOUTPUT"] = {key = "CTRL-V", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_QUESTABANDON"] = {key = "CTRL-SHIFT-D", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_CHATOPEN"] = {key = "SHIFT-F2", object = "SkuChat", func = "OnEnable",},
   ["SKU_KEY_TOGGLEREACHRANGE"] = {key = "CTRL-SHIFT-Q", object = "SkuNav", func = "CreateSkuNavMain",},

   ["SKU_KEY_SCANCONTINUE"] = {key = "SHIFT-L", object = "SkuCoreControlOption1", script = "OnHide",},
   ["SKU_KEY_SCAN1"] = {key = "", object = "SkuCoreControlOption1", script = "OnHide",},
   ["SKU_KEY_SCAN2"] = {key = "", object = "SkuCoreControlOption1", script = "OnHide",},
   ["SKU_KEY_SCAN3"] = {key = "", object = "SkuCoreControlOption1", script = "OnHide",},
   ["SKU_KEY_SCAN4"] = {key = "", object = "SkuCoreControlOption1", script = "OnHide",},
   ["SKU_KEY_SCAN5"] = {key = "CTRL-SHIFT-U", object = "SkuCoreControlOption1", script = "OnHide",},
   ["SKU_KEY_SCAN6"] = {key = "CTRL-SHIFT-O", object = "SkuCoreControlOption1", script = "OnHide",},
   ["SKU_KEY_SCAN7"] = {key = "CTRL-SHIFT-P", object = "SkuCoreControlOption1", script = "OnHide",},
   ["SKU_KEY_SCAN8"] = {key = "CTRL-SHIFT-I", object = "SkuCoreControlOption1", script = "OnHide",},

   ["SKU_KEY_TURNTOBEACON"] = {key = "I", object = "SkuNav", func = "CreateSkuNavMain",},

   ["SKU_KEY_OPENDUNGEONBROWSER"] = {key = "", object = "SkuOptions", func = "CreateMainFrame",},

   ["SKU_KEY_OPENATLASLOOT"] = {key = "CTRL-SHIFT-L", object = "SkuCore", func = "AtlasLootApplyKeyBinding",},

   -- Combat bag access (SkuCore/combatBags.lua): navigate occupied bag slots and
   -- left/right-click them WHILE IN COMBAT. Default empty -> assign in the keybind menu.
   ["SKU_KEY_COMBATBAGPREV"] = {key = "", object = "SkuCore", func = "CombatBagsApplyKeyBinding",},
   ["SKU_KEY_COMBATBAGNEXT"] = {key = "", object = "SkuCore", func = "CombatBagsApplyKeyBinding",},
   ["SKU_KEY_COMBATBAGUSE"] = {key = "", object = "SkuCore", func = "CombatBagsApplyKeyBinding",},
   ["SKU_KEY_COMBATBAGPICKUP"] = {key = "", object = "SkuCore", func = "CombatBagsApplyKeyBinding",},
   ["SKU_KEY_COMBATBAGARROWS"] = {key = "", object = "SkuCore", func = "CombatBagsApplyKeyBinding",},

   -- Combat trading (SkuCore/combatTrade.lua): finish a trade while in combat.
   ["SKU_KEY_COMBATTRADEACCEPT"] = {key = "", object = "SkuCore", func = "CombatTradeApplyKeyBinding",},
   ["SKU_KEY_COMBATTRADECANCEL"] = {key = "", object = "SkuCore", func = "CombatTradeApplyKeyBinding",},
   ["SKU_KEY_COMBATTRADEADD"] = {key = "", object = "SkuCore", func = "CombatTradeApplyKeyBinding",},

   ["SKU_KEY_STOPROUTEORWAYPOINT"] = {key = "", object = "SkuNav", func = "CreateSkuNavMain",},

   ["SKU_KEY_MENUQUICK5"] = {key = "", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_MENUQUICK5SET"] = {key = "", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_MENUQUICK6"] = {key = "", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_MENUQUICK6SET"] = {key = "", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_MENUQUICK7"] = {key = "", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_MENUQUICK7SET"] = {key = "", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_MENUQUICK8"] = {key = "", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_MENUQUICK8SET"] = {key = "", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_MENUQUICK9"] = {key = "", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_MENUQUICK9SET"] = {key = "", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_MENUQUICK10"] = {key = "", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_MENUQUICK10SET"] = {key = "", object = "SkuOptions", func = "CreateMainFrame",},
   
   ["SKU_KEY_NOTIFYONRESOURCES"] = {key = "", object = "SkuCoreControlOption1", func = "OnHide",},

   ["SKU_KEY_DOMONITORPARTYHEALTH2CONTI"] = {key = "", object = "SkuCoreControlOption1", func = "OnHide",},

   ["SKU_KEY_ENABLESOFTTARGETINGENEMY"] = {key = "SHIFT-I", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_ENABLESOFTTARGETINGFRIENDLY"] = {key = "SHIFT-P", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_ENABLESOFTTARGETINGINTERACT"] = {key = "SHIFT-O", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_OUTPUTHARDTARGET"] = {key = "", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_OUTPUTSOFTTARGET"] = {key = "", object = "SkuOptions", func = "CreateMainFrame",},





   ["SKU_KEY_ENABLEPARTYRAIDHEALTHMONITOR"] = {key = "", object = "SkuOptions", func = "CreateMainFrame",},

   ["SKU_KEY_GROUPMEMBERSRANGECHECK"] = {key = "", object = "SkuOptions", func = "CreateMainFrame",},

   ["SKU_KEY_SKUMARKERSET1WHITE"] = {key = "", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_SKUMARKERSET2RED"] = {key = "", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_SKUMARKERSET3BLUE"] = {key = "", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_SKUMARKERSET4GREEN"] = {key = "", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_SKUMARKERSET5PURPLE"] = {key = "", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_SKUMARKERSET6YELLOW"] = {key = "", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_SKUMARKERSET7ORANGE"] = {key = "", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_SKUMARKERSET8GREY"] = {key = "", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_SKUMARKERCLEARALL"] = {key = "", object = "SkuOptions", func = "CreateMainFrame",},
   
   ["SKU_KEY_TURNTOUNIT1"] = {key = "", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_TURNTOUNIT2"] = {key = "", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_TURNTOUNIT3"] = {key = "", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_TURNTOUNIT4"] = {key = "", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_TURNTOUNIT5"] = {key = "", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_TURNTOUNIT6"] = {key = "", object = "SkuOptions", func = "CreateMainFrame",},

   ["SKU_KEY_TURNTOUNITTURN180"] = {key = "", object = "SkuOptions", func = "CreateMainFrame",},

   ["SKU_KEY_COMBATMONSETFOLLOWTARGET"] = {key = "", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_COMBATMONOUTPUTNUMBERINCOMBAT"] = {key = "", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_NEXTCOMBATENEMY"] = {key = "", object = "SkuCore", func = "UpdateNextCombatEnemyBinding",},

   ["SKU_KEY_TARGETHEALTH"] = {key = "", object = "SkuCoreControlOption1", script = "OnHide",},

   --["SKU_KEY_CHAT_LINEPREV"] = {key = "UP", object = "SkuChat", func = "OnEnable",},
   --["SKU_KEY_CHAT_LINENEXT"] = {key = "DOWN", object = "SkuChat", func = "OnEnable",},
   --["SKU_KEY_CHAT_TABPREV"] = {key = "LEFT", object = "SkuChat", func = "OnEnable",},
   --["SKU_KEY_CHAT_TABNEXT"] = {key = "RIGHT", object = "SkuChat", func = "OnEnable",},
   --["SKU_KEY_CHAT_LINEMENU"] = {key = "CTRL-ENTER", object = "SkuChat", func = "OnEnable",},
   
}
for x = 1, 8 do
   SkuOptions.skuDefaultKeyBindings["SKU_KEY_FOCUSGET"..x] = {key = "", object = "SkuCoreSkuFocusControl", script = "OnHide",}
   SkuOptions.skuDefaultKeyBindings["SKU_KEY_FOCUSSET"..x] = {key = "", object = "SkuCoreSkuFocusControl", script = "OnHide",}
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:SkuKeyBindsResetBindings()
   SkuSettings:Sub("SkuOptions").SkuKeyBinds = {}
   SkuOptions:SkuKeyBindsUpdate()
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:SkuKeyBindsGetBinding(aBindingConst)
   return SkuSettings:Sub("SkuOptions").SkuKeyBinds[aBindingConst].key
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:SkuKeyBindsGetBinding2(aBindingConst)
   local tEntry = SkuSettings:Sub("SkuOptions").SkuKeyBinds[aBindingConst]
   return tEntry and tEntry.key2 or ""
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:SkuKeyBindsSetBinding(aBindingConst, aNewKey)
   if not SkuSettings:Sub("SkuOptions").SkuKeyBinds[aBindingConst] then
      return
   end
   SkuSettings:Sub("SkuOptions").SkuKeyBinds[aBindingConst].key = aNewKey
   SkuOptions:SkuKeyBindsUpdate()
   return true
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:SkuKeyBindsSetBinding2(aBindingConst, aNewKey)
   if not SkuSettings:Sub("SkuOptions").SkuKeyBinds[aBindingConst] then
      return
   end
   SkuSettings:Sub("SkuOptions").SkuKeyBinds[aBindingConst].key2 = aNewKey
   SkuOptions:SkuKeyBindsUpdate()
   return true
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:SkuKeyBindsDeleteBinding(aBindingConst)
   dprint("SkuKeyBindsDeleteBinding", aBindingConst)
   if not SkuSettings:Sub("SkuOptions").SkuKeyBinds[aBindingConst] then
      return
   end
   SkuSettings:Sub("SkuOptions").SkuKeyBinds[aBindingConst].key = ""
   SkuOptions:SkuKeyBindsUpdate()
   return true
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:SkuKeyBindsDeleteBinding2(aBindingConst)
   dprint("SkuKeyBindsDeleteBinding2", aBindingConst)
   if not SkuSettings:Sub("SkuOptions").SkuKeyBinds[aBindingConst] then
      return
   end
   SkuSettings:Sub("SkuOptions").SkuKeyBinds[aBindingConst].key2 = ""
   SkuOptions:SkuKeyBindsUpdate()
   return true
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Loescht nur die Taste die den Konflikt verursacht (.key oder .key2).
-- Wenn aConflictKey angegeben ist, wird geprueft ob sie in .key oder .key2
-- liegt und nur das passende Feld geleert. Ohne aConflictKey: .key leeren (Rueckwaertskompatibel).
function SkuOptions:SkuKeyBindsDeleteConflictingKey(aBindingConst, aConflictKey)
   if not SkuSettings:Sub("SkuOptions").SkuKeyBinds[aBindingConst] then
      return
   end
   local tEntry = SkuSettings:Sub("SkuOptions").SkuKeyBinds[aBindingConst]
   if aConflictKey then
      if tEntry.key2 and tEntry.key2 == aConflictKey then
         tEntry.key2 = ""
      elseif tEntry.key == aConflictKey then
         tEntry.key = ""
      end
   else
      tEntry.key = ""
   end
   SkuOptions:SkuKeyBindsUpdate()
   return true
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:SkuKeyBindsCheckBound(aKey)
   for i, v in pairs(SkuOptions.skuDefaultKeyBindings) do
      if SkuSettings:Sub("SkuOptions").SkuKeyBinds[i] then
         if SkuSettings:Sub("SkuOptions").SkuKeyBinds[i].key == aKey then
            return i
         end
         if SkuSettings:Sub("SkuOptions").SkuKeyBinds[i].key2 and SkuSettings:Sub("SkuOptions").SkuKeyBinds[i].key2 == aKey then
            return i
         end
      end
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:SkuKeyBindsMatchKey(aKey, aBindingConst)
   local tEntry = SkuSettings:Sub("SkuOptions").SkuKeyBinds[aBindingConst]
   if not tEntry then return false end
   if aKey == tEntry.key then return true end
   if tEntry.key2 and tEntry.key2 ~= "" and aKey == tEntry.key2 then return true end
   return false
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:SkuKeyBindsUpdate(aInitializeFlag)
   SkuSettings:Sub("SkuOptions")

   --default settings if no data
   if not SkuSettings:Sub("SkuOptions").SkuKeyBinds then
      SkuSettings:Sub("SkuOptions").SkuKeyBinds = {}
   end
   for i, v in pairs(SkuOptions.skuDefaultKeyBindings) do
      if not SkuSettings:Sub("SkuOptions").SkuKeyBinds[i] then
         SkuSettings:Sub("SkuOptions").SkuKeyBinds[i] = {key = v.key or "", key2 = v.key2 or ""}
         dprint("set default", i, v)
      end
      -- Migration: key2 hinzufuegen fuer bestehende Profile ohne key2
      if SkuSettings:Sub("SkuOptions").SkuKeyBinds[i].key2 == nil then
         SkuSettings:Sub("SkuOptions").SkuKeyBinds[i].key2 = ""
      end
   end

   --update all override bindings
   if not aInitializeFlag then
      local tDone = {}   
      for i, v in pairs(SkuOptions.skuDefaultKeyBindings) do
         if not tDone[v.object..(v.func or v.script)] then
            tDone[v.object..(v.func or v.script)] = true
            if _G[v.object] then
               if v.func then
                  if _G[v.object][v.func] then
                     dprint("calling ", v.object, v.func, _G[v.object][v.func])
                     _G[v.object][v.func](_G[v.object])
                  else
                     dprint("nil func", v.func)
                  end
               elseif v.script then
                  if _G[v.object]:GetScript(v.script) then
                     dprint("calling ", v.object, v.script, _G[v.object]:GetScript(v.script))
                     _G[v.object]:GetScript(v.script)(_G[v.object])
                  else
                     dprint("nil func", v.func)
                  end
               end
            else
               dprint("  ", "nil object", v.object)
            end
         end
      end
   end
end