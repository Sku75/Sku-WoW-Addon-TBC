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
   -- Request an early landing on a flightmaster taxi flight (SkuCore/taxi.lua).
   ["SKU_KEY_TAXICANCEL"] = {key = "CTRL-SHIFT-E", object = "SkuCoreControlOption1", script = "OnHide",},
   ["SKU_KEY_STARTRRFOLLOW"] = {key = "CTRL-SHIFT-Z", object = "SkuNav", func = "CreateSkuNavMain",},
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
   -- Quick-access slots 1-4 ship UNBOUND like slots 5-10. They used to default to
   -- Shift-F9..F12, but v42 intercepted exactly those four keys for four FIXED
   -- actions before the generic quick-select loop could see them: the slots were
   -- dead (their SET keys still stored a path that nothing could ever recall) and
   -- the fixed actions were only rebindable under a label that said "audio menu
   -- quick access N". Each fixed action now owns a proper const of its own
   -- (SKU_KEY_NAVWAYPOINTSQUICK / -NAVROUTEDESTINATIONSQUICK / -ACTIONBARSOPEN /
   -- -STOPROUTEORWAYPOINT below) and keeps the Shift-F9..F12 defaults, so nothing
   -- moves for the user; the ten quick-select slots are all user-assigned again.
   -- tMigrateQuickKeys() in SkuKeyBindsUpdate carries existing profiles over.
   ["SKU_KEY_MENUQUICK1"] = {key = "", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_MENUQUICK2"] = {key = "", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_MENUQUICK3"] = {key = "", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_MENUQUICK4"] = {key = "", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_MENUQUICK1SET"] = {key = "", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_MENUQUICK2SET"] = {key = "", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_MENUQUICK3SET"] = {key = "", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_MENUQUICK4SET"] = {key = "", object = "SkuOptions", func = "CreateMainFrame",},

   -- The four ex-MENUQUICK1..4 actions, each under its own name. All four are
   -- dispatched from SkuOptions' OnSkuOptionsMain OnClick and bound there
   -- (CreateMainFrame) -- the same frame that handled them as MENUQUICK keys.
   -- Handing the three nav-ish ones to SkuNav's OnSkuNavMain instead looked
   -- tidier (module ownership) but changed behaviour: Shift-F9 stopped opening
   -- the waypoint list. One frame, one owner per key, dispatch order preserved.
   ["SKU_KEY_NAVWAYPOINTSQUICK"] = {key = "SHIFT-F9", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_NAVROUTEDESTINATIONSQUICK"] = {key = "SHIFT-F10", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_ACTIONBARSOPEN"] = {key = "SHIFT-F11", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_ROLLNEED"] = {key = "CTRL-SHIFT-B", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_ROLLGREED"] = {key = "CTRL-SHIFT-G", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_ROLLPASS"] = {key = "CTRL-SHIFT-X", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_ROLLINFO"] = {key = "CTRL-SHIFT-C", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_STOPTTSOUTPUT"] = {key = "CTRL-V", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_QUESTABANDON"] = {key = "CTRL-SHIFT-D", object = "SkuOptions", func = "CreateMainFrame",},

   -- Menu activate/left-click and right-click keys (the old "Linksklick"/"Rechtsklick"
   -- child entries were removed; these keys act directly on the focused menu item).
   -- The physical key always clicks the secure menu button with a FIXED virtual button
   -- name ("ENTER" / "RCLICK"), so rebinding never changes the dispatcher logic.
   -- Applied while the menu is open (secure buttons' OnShow re-arms on rebind).
   -- transientOverride: the key is armed ONLY while the menu is open (the secure
   -- button's OnShow/OnHide own it), so it does not really collide with a game
   -- binding on the same key -- see SkuOptions:SkuKeyBindsIsTransientOverride.
   ["SKU_KEY_MENULEFTCLICK"] = {key = "ENTER", object = "SecureOnSkuOptionsMainOption1", script = "OnShow", transientOverride = true,},
   ["SKU_KEY_MENURIGHTCLICK"] = {key = "CTRL-ENTER", object = "SecureOnSkuOptionsMainOption2", script = "OnShow", transientOverride = true,},
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

   -- "Zum aktuellen Beacon drehen": I stays the primary key, T is added as the second
   -- binding (t = turn/drehen) so both work out of the box. SkuNav's binder below
   -- applies key AND key2.
   ["SKU_KEY_TURNTOBEACON"] = {key = "I", key2 = "T", object = "SkuNav", func = "CreateSkuNavMain",},

   ["SKU_KEY_OPENDUNGEONBROWSER"] = {key = "", object = "SkuOptions", func = "CreateMainFrame",},

   ["SKU_KEY_OPENATLASLOOT"] = {key = "CTRL-SHIFT-L", object = "SkuCore", func = "AtlasLootApplyKeyBinding",},

   -- (Combat bag access + combat trading keybinds removed 2026-07-01 -- their probe-era
   -- modules SkuCore/combatBags.lua + combatTrade.lua were archived. The Path A combat
   -- item-use rework will register its own keys. See [[sku42-combat-item-use-design]].)
   -- Trade-accept: permanent, rebindable secure /click TradeFrameTradeButton (works in and out
   -- of combat, no-op with no trade open). See SkuCore:UpdateTradeAcceptBinding.
   ["SKU_KEY_TRADEACCEPT"] = {key = "CTRL-T", object = "SkuCore", func = "UpdateTradeAcceptBinding",},

   -- In-combat menu navigation keys (Path A combat item-use). Unlike most binds these are NOT
   -- applied out of combat -- SkuCore:CombatMenuKeysBindNow reads them from this store and binds
   -- them as secure override clicks only at combat start (cleared at combat end), so out of
   -- combat the arrows/enter stay the game's normal keys. The dispatch object/func here is just
   -- the harmless CreateMainFrame placeholder (the real apply happens at the next combat start).
   -- Defaults mirror the hardcoded out-of-combat menu nav keys. The physical key the user
   -- assigns is mapped to a fixed logical action inside CombatMenuKeysBindNow, so rebinding the
   -- key never changes what the snippet/menu handler does. See [[sku42-combat-item-use-design]].
   -- NOTE: bag (B) and character (C) do NOT get their own bind here -- their in-combat SYNC/CSYNC
   -- follows whatever key already opens bags/character (GetBindingKey in CombatMenuKeysBindNow),
   -- so moving that binding moves the combat action with it.
   -- transientOverride: bound as secure override clicks only for the duration of a
   -- fight, so they shadow the game's key there and give it back afterwards --
   -- same coexistence as the menu click keys above.
   ["SKU_KEY_COMBATMENU_UP"] = {key = "UP", object = "SkuOptions", func = "CreateMainFrame", transientOverride = true,},
   ["SKU_KEY_COMBATMENU_DOWN"] = {key = "DOWN", object = "SkuOptions", func = "CreateMainFrame", transientOverride = true,},
   ["SKU_KEY_COMBATMENU_LEFT"] = {key = "LEFT", object = "SkuOptions", func = "CreateMainFrame", transientOverride = true,},
   ["SKU_KEY_COMBATMENU_RIGHT"] = {key = "RIGHT", object = "SkuOptions", func = "CreateMainFrame", transientOverride = true,},
   ["SKU_KEY_COMBATMENU_HOME"] = {key = "HOME", object = "SkuOptions", func = "CreateMainFrame", transientOverride = true,},
   ["SKU_KEY_COMBATMENU_END"] = {key = "END", object = "SkuOptions", func = "CreateMainFrame", transientOverride = true,},
   ["SKU_KEY_COMBATMENU_BACK"] = {key = "BACKSPACE", object = "SkuOptions", func = "CreateMainFrame", transientOverride = true,},
   ["SKU_KEY_COMBATMENU_CLOSE"] = {key = "ESCAPE", object = "SkuOptions", func = "CreateMainFrame", transientOverride = true,},
   -- SKU_KEY_COMBATMENU_USE (was ENTER) is RETIRED. It bound the left-click key to the
   -- secure in-combat use button, so ENTER and SKU_KEY_MENURIGHTCLICK (CTRL-ENTER) both
   -- fired the same armed action and the left/right split collapsed in combat. The two
   -- menu click keys now cover combat as well (SkuCore/combatMenuKeys.lua). A stale entry
   -- in an existing profile is inert: every binder iterates skuDefaultKeyBindings.

   -- The ONE cancel-navigation key (default Shift-F12, the key users already press).
   -- Until v43.0 two paths did nearly the same teardown: this const (correctly named,
   -- in the Navigation keybind group, but shipped unbound and announcing the same
   -- "following stopped" line the automatic stop uses) and the hardcoded Shift-F12
   -- MENUQUICK4 branch (guarded + its own "Navigation abgebrochen" line, but named
   -- after a quick-access slot). Merged into this const with the guarded behaviour --
   -- see the branch at the top of OnSkuOptionsMain's OnClick (SkuZOptions/Core.lua).
   ["SKU_KEY_STOPROUTEORWAYPOINT"] = {key = "SHIFT-F12", object = "SkuOptions", func = "CreateMainFrame",},

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
   
   ["SKU_KEY_NOTIFYONRESOURCES"] = {key = "", object = "SkuCoreControlOption1", script = "OnHide",},

   ["SKU_KEY_DOMONITORPARTYHEALTH2CONTI"] = {key = "", object = "SkuCoreControlOption1", script = "OnHide",},

   ["SKU_KEY_ENABLESOFTTARGETINGENEMY"] = {key = "SHIFT-I", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_ENABLESOFTTARGETINGFRIENDLY"] = {key = "SHIFT-P", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_ENABLESOFTTARGETINGINTERACT"] = {key = "SHIFT-O", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_OUTPUTHARDTARGET"] = {key = "", object = "SkuOptions", func = "CreateMainFrame",},
   ["SKU_KEY_OUTPUTSOFTTARGET"] = {key = "", object = "SkuOptions", func = "CreateMainFrame",},
   -- [v43.2] Speak the CURRENT unit's FULL tooltip on demand. Sits with the two
   -- OUTPUT*TARGET keys above because it is the same kind of action -- describe
   -- what I am on, now -- just at the verbose end. CTRL-SHIFT-V is free (CTRL-V
   -- alone is SKU_KEY_STOPTTSOUTPUT; the two do not collide, and /skucheck keys
   -- reports it if a profile ever binds over it).
   ["SKU_KEY_OUTPUTTARGETTOOLTIP"] = {key = "CTRL-SHIFT-V", object = "SkuOptions", func = "CreateMainFrame",},





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
   -- STRG-H als Vorgabe, passend zum ALT-H des Questziels: beide Tasten sind
   -- frei und gehoeren sachlich zusammen ("nimm etwas ins Ziel").
   ["SKU_KEY_NEXTCOMBATENEMY"] = {key = "CTRL-H", object = "SkuCore", func = "UpdateNextCombatEnemyBinding",},

   -- Naechstes Questziel: eigener sicherer Button in SkuQuest/QuestTarget.lua,
   -- deshalb dieselbe Objekt/Funktion-Zustellung wie beim naechsten Gegner.
   -- ALT-H als Vorgabe: frei (kein anderer Sku-Const und keine Standardbelegung
   -- des Spiels liegt darauf), und ohne Vorgabe entdeckt die Funktion niemand.
   ["SKU_KEY_QUESTTARGET"] = {key = "ALT-H", object = "SkuQuest", func = "UpdateQuestTargetBinding",},

   ["SKU_KEY_TARGETHEALTH"] = {key = "", object = "SkuCoreControlOption1", script = "OnHide",},

   
}
-- Default keys for the first five Sku focus slots (numeric keypad). The bare key
-- CALLS the focus (FOCUSGET), CTRL + the same key SETS/captures it (FOCUSSET), so a
-- new player has a usable focus block without configuring anything. Slots 6-8 stay
-- unbound on purpose. Note skuFocus.lua only applies .key for these, so no key2 here.
local tFocusDefaultKeys = {
   [1] = "NUMPADPLUS",
   [2] = "NUMPAD6",
   [3] = "NUMPAD9",
   [4] = "NUMPADMINUS",
   [5] = "NUMPADMULTIPLY",
}
for x = 1, 8 do
   local tKey = tFocusDefaultKeys[x]
   SkuOptions.skuDefaultKeyBindings["SKU_KEY_FOCUSGET"..x] = {key = tKey or "", object = "SkuCoreSkuFocusControl", script = "OnHide",}
   SkuOptions.skuDefaultKeyBindings["SKU_KEY_FOCUSSET"..x] = {key = tKey and ("CTRL-"..tKey) or "", object = "SkuCoreSkuFocusControl", script = "OnHide",}
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
local function tSetKeyBindField(aBindingConst, aField, aValue)
   if not SkuSettings:Sub("SkuOptions").SkuKeyBinds[aBindingConst] then
      return
   end
   SkuSettings:Sub("SkuOptions").SkuKeyBinds[aBindingConst][aField] = aValue
   SkuOptions:SkuKeyBindsUpdate()
   return true
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:SkuKeyBindsSetBinding(aBindingConst, aNewKey) return tSetKeyBindField(aBindingConst, "key", aNewKey) end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:SkuKeyBindsSetBinding2(aBindingConst, aNewKey) return tSetKeyBindField(aBindingConst, "key2", aNewKey) end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:SkuKeyBindsDeleteBinding(aBindingConst)
   dprint("SkuKeyBindsDeleteBinding", aBindingConst)
   return tSetKeyBindField(aBindingConst, "key", "")
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:SkuKeyBindsDeleteBinding2(aBindingConst)
   dprint("SkuKeyBindsDeleteBinding2", aBindingConst)
   return tSetKeyBindField(aBindingConst, "key2", "")
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
   local tBinds = SkuSettings:Sub("SkuOptions").SkuKeyBinds
   for i, v in pairs(SkuOptions.skuDefaultKeyBindings) do
      local tEntry = tBinds[i]
      if tEntry then
         if tEntry.key == aKey then
            return i
         end
         if tEntry.key2 and tEntry.key2 == aKey then
            return i
         end
      end
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- True for bindings whose key is applied only as a TEMPORARY override binding,
-- i.e. SetOverrideBindingClick on a frame that owns the key for a limited time:
-- the menu click keys (armed by the secure button's OnShow, cleared by OnHide,
-- so only while the menu is open) and the in-combat menu keys (armed at combat
-- start, cleared at combat end). Such a key does NOT really collide with a GAME
-- binding on the same key: the override wins while it is armed, the game command
-- fires the rest of the time. That is exactly how ENTER served the menu's
-- activate key AND OPENCHAT side by side for years.
-- The rebind capture must therefore not unbind the game command for these
-- consts. Conflicts against OTHER Sku consts stay real and keep the normal
-- warn-and-unbind: two of them are armed at the same time and the last
-- SetOverrideBindingClick simply wins.
function SkuOptions:SkuKeyBindsIsTransientOverride(aBindingConst)
   local tEntry = aBindingConst and SkuOptions.skuDefaultKeyBindings[aBindingConst]
   return (tEntry and tEntry.transientOverride) == true
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Returns the list of physical keys for a binding ({key, key2}, empty strings
-- skipped). aFallbackKey (optional) is returned as sole entry when the binding
-- has no keys at all -- used for SKU_KEY_MENULEFTCLICK so the menu can never
-- end up without an activate key.
-- A key WITH a modifier is fine here: the menu's click payloads carry a
-- modifier-proof variant (plainMacrotext, see SkuZOptions/Core.lua) for every
-- native button whose OnClick would otherwise take its OnModifiedClick branch.
function SkuOptions:SkuKeyBindsGetKeys(aBindingConst, aFallbackKey)
   local rKeys = {}
   local tStore = SkuSettings and SkuSettings:Sub("SkuOptions").SkuKeyBinds
   local tEntry = tStore and tStore[aBindingConst]
   if tEntry then
      if tEntry.key and tEntry.key ~= "" then table.insert(rKeys, tEntry.key) end
      if tEntry.key2 and tEntry.key2 ~= "" then table.insert(rKeys, tEntry.key2) end
   end
   if #rKeys == 0 and aFallbackKey then table.insert(rKeys, aFallbackKey) end
   return rKeys
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
-- [v43.0] Run-once carry-over: the four fixed actions v42 had wired onto the
-- MENUQUICK1..4 keys now own consts of their own. Whatever key a profile has on
-- MENUQUICK1..4 today IS the key that performs the fixed action today, so move it
-- verbatim onto the new const and free the quick-access slot -- an unbound slot
-- stays unbound, so a user who deliberately cleared it does not get a key back.
-- Sentinel: a pre-change profile has no SKU_KEY_NAVWAYPOINTSQUICK entry (the
-- defaults loop below creates it, so this runs exactly once). Must therefore run
-- BEFORE that loop.
-- SKU_KEY_STOPROUTEORWAYPOINT is the one target that already existed: never
-- overwrite a key the user set on it, only fill its free slots.
local function tMigrateQuickKeys(aStore)
   if aStore["SKU_KEY_NAVWAYPOINTSQUICK"] ~= nil then
      return
   end
   local tPairs = {
      {"SKU_KEY_MENUQUICK1", "SKU_KEY_NAVWAYPOINTSQUICK"},
      {"SKU_KEY_MENUQUICK2", "SKU_KEY_NAVROUTEDESTINATIONSQUICK"},
      {"SKU_KEY_MENUQUICK3", "SKU_KEY_ACTIONBARSOPEN"},
      {"SKU_KEY_MENUQUICK4", "SKU_KEY_STOPROUTEORWAYPOINT"},
   }
   for x = 1, #tPairs do
      local tOld, tNew = tPairs[x][1], tPairs[x][2]
      local tOldEntry = aStore[tOld]
      if tOldEntry then
         local tNewEntry = aStore[tNew]
         if not tNewEntry then
            aStore[tNew] = {key = tOldEntry.key or "", key2 = tOldEntry.key2 or ""}
         else
            for _, tKey in ipairs({tOldEntry.key or "", tOldEntry.key2 or ""}) do
               if tKey ~= "" and tNewEntry.key ~= tKey and tNewEntry.key2 ~= tKey then
                  if (tNewEntry.key or "") == "" then
                     tNewEntry.key = tKey
                  elseif (tNewEntry.key2 or "") == "" then
                     tNewEntry.key2 = tKey
                  end
               end
            end
         end
         dprint("keybind migration", tOld, "->", tNew, aStore[tNew].key, aStore[tNew].key2)
         tOldEntry.key, tOldEntry.key2 = "", ""
      end
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuOptions:SkuKeyBindsUpdate(aInitializeFlag)
   SkuSettings:Sub("SkuOptions")

   --default settings if no data
   if not SkuSettings:Sub("SkuOptions").SkuKeyBinds then
      SkuSettings:Sub("SkuOptions").SkuKeyBinds = {}
   end
   tMigrateQuickKeys(SkuSettings:Sub("SkuOptions").SkuKeyBinds)
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