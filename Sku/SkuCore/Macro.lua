local MODULE_NAME, MODULE_PART = "SkuCore", "Macro"
SkuCore = SkuCore or LibStub("AceAddon-3.0"):NewAddon("SkuCore", "AceConsole-3.0", "AceEvent-3.0")
local L = Sku.L

-- W4 Phase D: Macro is a real AceAddon SUBMODULE of SkuCore so it can be turned
-- on/off at runtime via the Features menu. This feature is a pure menu-builder
-- (SkuCore:MacroMenuBuilder, referenced by Options.lua) with no events, hooks, or
-- timers to arm, so OnEnable/OnDisable are intentional no-ops — toggling it off
-- simply removes it from the Features list / leaves its menu inert. The menu
-- methods stay exactly where they are so external callers keep working.
local Macro = SkuCore:NewModule(MODULE_PART)
SkuCore.Macro = Macro   -- keep the published handle

-- Make this feature user-toggleable (Features menu + persisted on/off). One line;
-- the framework (SkuCore/ModuleManager.lua) handles the rest.
SkuCore:RegisterToggleableModule(MODULE_PART, function()
    return (GetLocale and GetLocale() == "deDE") and "Makros" or "Macros"
end)

-- No lifecycle to arm/disarm: this is a pure menu-builder feature.
function Macro:OnEnable()
end

function Macro:OnDisable()
end
---------------------------------------------------------------------------------------------------------------------------------------
function MacroMenuBuilderNew(aParent)
    CreateTextBox(aParent, L["MacroName"], L["EnterMacroName"], function(value)
        aParent["Name"] = value
        C_Timer.After(0.1, function()
            SkuOptions.currentMenuPosition:OnSelect()
            SkuOptions.currentMenuPosition:OnUpdate()
        end)
    end)

    local tScopeMenuEntry = SkuOptions:InjectMenuItems(aParent, { L["MacroScope"] }, SkuGenericMenuItem)
    tScopeMenuEntry.dynamic = true
    tScopeMenuEntry.BuildChildren = function(self)
        local tGlobalMenuEntry = SkuOptions:InjectMenuItems(self, { L["MacroScopeGlobal"] }, SkuGenericMenuItem)
        tGlobalMenuEntry.OnAction = function(self)
            aParent["MacroScope"] = nil
        end
        local tCharMenuEntry = SkuOptions:InjectMenuItems(self, { L["MacroScopeChar"] }, SkuGenericMenuItem)
        tCharMenuEntry.OnAction = function(self)
            aParent["MacroScope"] = 1
        end
    end

    CreateTextBox(aParent, L["MacroBody"], L["EnterMacroBody"], function(value)
        aParent["MacroBody"] = value
        C_Timer.After(0.1, function()
            SkuOptions.currentMenuPosition:OnSelect()
            SkuOptions.currentMenuPosition:OnUpdate()
        end)
    end, true)

    local tCreateMenuEntry = SkuOptions:InjectMenuItems(aParent, { L["CreateMacro"] }, SkuGenericMenuItem)
    tCreateMenuEntry.OnAction = function(self)
        if aParent["Name"] == nil or aParent["Name"] == '' then
            SkuOptions.Voice:OutputStringBTtts(L["MissingMacroName"], false, true, 0.2)
            return
        end
        if aParent["MacroBody"] == nil or aParent["MacroBody"] == '' then
            SkuOptions.Voice:OutputStringBTtts(L["MissingMacroBody"], false, true, 0.2)
            return
        end
        CreateMacro(aParent["Name"], "INV_MISC_QUESTIONMARK", aParent["MacroBody"], aParent["MacroScope"])
        
        aParent["Name"] = nil
        aParent["MacroBody"] = nil
        aParent["MacroScope"] = nil
        C_Timer.After(2.5, function()
            SkuOptions.Voice:OutputStringBTtts(L["MacroCreated"], true, true, 0.2)
        end)
    end
end

---------------------------------------------------------------------------------------------------------------------------------------
function Macro:MacroMenuBuilder()
    local aParent = self
    local tNewMenuEntry = SkuOptions:InjectMenuItems(aParent, { L["NewMacro"] }, SkuGenericMenuItem)
    tNewMenuEntry.dynamic = true
    tNewMenuEntry.BuildChildren = MacroMenuBuilderNew
    local tGlobalMenuEntry = SkuOptions:InjectMenuItems(aParent, { L["MacroScopeGlobal"] }, SkuGenericMenuItem)
    tGlobalMenuEntry.dynamic = true
    tGlobalMenuEntry.BuildChildren = MacroMenuBuilderGlobalList
    local tCharMenuEntry = SkuOptions:InjectMenuItems(aParent, { L["MacroScopeChar"] }, SkuGenericMenuItem)
    tCharMenuEntry.dynamic = true
    tCharMenuEntry.BuildChildren = MacroMenuBuilderCharList
end

function MacroMenuBuilderGlobalList(aParent)
    MacroMenuBuilderList(aParent, true)
end

function MacroMenuBuilderCharList(aParent)
    MacroMenuBuilderList(aParent, false)
end

function MacroMenuBuilderList(aParent, isGlobal)
    local firstCharNumber = 121
    local numGlobal, numChar = GetNumMacros()
    local from, to
    if isGlobal then
        from = 1
        to = numGlobal
    else
        from = firstCharNumber
        to = numChar + (firstCharNumber - 1)
    end

    for i = from, to do
        local name, iconTexture, body, isLocal = GetMacroInfo(i)
        local tListEntry = SkuOptions:InjectMenuItems(aParent, { name }, SkuGenericMenuItem)
        tListEntry.dynamic = true
        tListEntry["Id"] = i          -- capital Id: the WoW macro index (unrelated to nav)
        tListEntry.id = "macroEntry"  -- lowercase id: stable nav anchor (W6-B #14)
        tListEntry.BuildChildren = MacroMenuBuilderEntryButtons
    end
end

function MacroMenuBuilderEntryButtons(aParent)
    local tDeleteEntry = SkuOptions:InjectMenuItems(aParent, { L["Delete"] }, SkuGenericMenuItem)
    tDeleteEntry.dynamic = true
    tDeleteEntry.BuildChildren = function(menuEntry) 
        SkuOptions:ConfirmationDialog(menuEntry, function(self)
            DeleteMacro(aParent["Id"])
            C_Timer.After(0.1, function()
                -- Re-pin to the macro entry via its stable id instead of a fixed
                -- .parent.parent.parent hop (W6-B #14). Same target, depth-robust.
                local tAnchor = SkuOptions.currentMenuPosition:FindAncestorById("macroEntry")
                if tAnchor then tAnchor:OnSelect() end
                SkuOptions.currentMenuPosition:OnUpdate()
            end)
        end)
    end
    CreateTextBox(aParent, L["Rename"], L["Enter name and press ENTER key"], function(value) 
        EditMacro(aParent["Id"],value,nil,1)
        aParent.Name = value
        C_Timer.After(0.1, function()
            SkuOptions.currentMenuPosition:OnUpdate()
        end)
    end)
end

function CreateTextBox(aParent, name, message, setterFunction, aMultilineFlag)
    local tNewTextMenuEntry = SkuOptions:InjectMenuItems(aParent, { name }, SkuGenericMenuItem)

    tNewTextMenuEntry.OnAction = function(self)
        PlaySound(88)
        SkuOptions.Voice:OutputStringBTtts(message, false, true, 0.2)
        SkuOptions:EditBoxShow("", function(self)
            local tText = SkuOptionsEditBoxEditBox:GetText()
            setterFunction(tText)
        end, aMultilineFlag)
    end
end