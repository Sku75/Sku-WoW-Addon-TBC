local MODULE_NAME, MODULE_PART = "SkuCore", "DialogKey"
local L = Sku.L
local _G = _G

SkuCore = SkuCore or LibStub("AceAddon-3.0"):NewAddon("SkuCore", "AceConsole-3.0", "AceEvent-3.0")

-- W4 Phase D: DialogKey is a real AceAddon SUBMODULE of SkuCore, so the
-- space/number dialog-key handler can be turned on/off independently at runtime:
--   * OnEnable  arms the feature (creates the hidden OnKeyDown driver frame).
--   * OnDisable disarms it (hides/disables the frame), so a disabled feature
--     genuinely does nothing.
-- AceAddon auto-enables modules when SkuCore enables (≈ PLAYER_LOGIN), replacing
-- the old explicit SkuCore:DialogKeyLogin() call in the isInitialLogin block
-- (which only ran on the initial login, so the dialog key did not re-arm after a
-- /reload — OnEnable fixes that by arming on every load).
local DialogKey = SkuCore:NewModule(MODULE_PART)
SkuCore.DialogKey = DialogKey   -- keep the published handle

-- Make this feature user-toggleable (Features menu + persisted on/off). One line;
-- the framework (SkuCore/ModuleManager.lua) handles the rest.
SkuCore:RegisterToggleableModule(MODULE_PART, function()
	return (GetLocale and GetLocale() == "deDE") and "Dialogtaste" or "Dialog key"
end)

-- Feature-private state: the hidden OnKeyDown driver frame, reused across
-- enable/disable cycles.
local DialogkeyControlFrame

---------------------------------------------------------------------------------------------------------------------------------------
local function DialogkeyCreateControlFrame()
	-- Idempotent: create the driver frame once, reuse it across enable/disable.
	if DialogkeyControlFrame then
		return DialogkeyControlFrame
	end
	local tFrame = CreateFrame("Frame", "SkuCoreDialogkeyControl", UIParent)
   tFrame:EnableKeyboard(true)
   tFrame:SetPropagateKeyboardInput(true)
   tFrame:SetScript("OnKeyDown", function(self, a, b)
      -- Disabled feature is a safe no-op.
      if not DialogKey:IsEnabled() then
         return
      end
      if SkuCore.inCombat == true then
         return
      end

      if a == "SPACE" then
         if QuestFrameAcceptButton and QuestFrameAcceptButton:IsShown() and QuestFrameAcceptButton:IsVisible() then
            if QuestFrameAcceptButton:IsEnabled() then
               QuestFrameAcceptButton:Click()
            else
               PlaySound(847)
            end
         end
         if QuestFrameCompleteButton and QuestFrameCompleteButton:IsShown() and QuestFrameCompleteButton:IsVisible() then
            if QuestFrameCompleteButton:IsEnabled() then
               QuestFrameCompleteButton:Click()
            else
               PlaySound(847)
            end
         end
         if QuestFrameCompleteQuestButton and QuestFrameCompleteQuestButton:IsShown() and QuestFrameCompleteQuestButton:IsVisible() then
            if QuestFrameCompleteQuestButton:IsEnabled() then
               QuestFrameCompleteQuestButton:Click()
            else
               PlaySound(847)
            end
         end

         local tActiveQuests = {}
         local tAvailableQuests = {}
         local tGossipOptions = {}
         local tHasActiveQuests = false
         local tHasAvailableQuests = false
         local tHasGossipOptions = false
         if GossipFrame and GossipFrame.GreetingPanel and GossipFrame.GreetingPanel.ScrollBox and GossipFrame.GreetingPanel.ScrollBox:IsShown() and GossipFrame.GreetingPanel.ScrollBox:IsVisible() then
            local tChild = GossipFrame.GreetingPanel.ScrollBox:GetChildren()
            local tButtons = {tChild:GetChildren()}
            for i, v in pairs(tButtons) do
               if v.GetElementData then
                  local tData = v:GetElementData()
                  if tData.buttonType == 3 then
                     tGossipOptions[tData.index] = tData.gossipOptionID or tData.titleOptionButton
                     tHasGossipOptions = true
                  elseif tData.buttonType == 4 then
                     local tQuestName = SkuUtil:Unescape(tData.activeQuestButton:GetText())
                     if tQuestName then
                        local _, tResult = SkuQuest:CheckQuestProgress(true, tQuestName)
                        if tResult == true then
                           tActiveQuests[tData.index] = tData.activeQuestButton
                           tHasActiveQuests = true
                        end
                     end
                  elseif tData.buttonType == 5 then
                     tAvailableQuests[tData.index] = tData.availableQuestButton
                     tHasAvailableQuests = true
                  end
               end
            end
         end

         if _G["QuestFrameGreetingPanel"] and _G["QuestFrameGreetingPanel"]:IsVisible() == true then
            for x = 1, 10 do
               if _G["QuestTitleButton"..x] and _G["QuestTitleButton"..x]:IsVisible() == true then
                  local tButton = _G["QuestTitleButton"..x]
                  if tButton:GetText() and tButton:GetText() ~= "" then
                     if tButton.isActive == 1 then
                        local tQuestName = SkuUtil:Unescape(tButton:GetText())
                        local _, tResult = SkuQuest:CheckQuestProgress(true, tQuestName)
                        if tResult == true then
                           tActiveQuests[x] = tButton
                           tHasActiveQuests = true
                        end
                     elseif tButton.isActive == 0 then
                        tAvailableQuests[x] = tButton
                        tHasAvailableQuests = true
                     end
                  end
               end
            end
         end

         if tHasActiveQuests == true then
            for x = 1, 20 do
               if tActiveQuests[x] then
                  tActiveQuests[x]:Click()
                  break
               end
            end
         elseif tHasAvailableQuests == true then
            for x = 1, 20 do
               if tAvailableQuests[x] then
                  tAvailableQuests[x]:Click()
                  break
               end
            end
         elseif tHasGossipOptions == true then
            for x = 1, 20 do
               if tGossipOptions[x] then
                  tGossipOptions[x]:Click()
                  break
               end
            end
         end

      end
      for x = 1, 9 do
         if a == tostring(x) then
            if _G["QuestInfoRewardsFrameQuestInfoItem"..x] and _G["QuestInfoRewardsFrameQuestInfoItem"..x]:IsShown() and _G["QuestInfoRewardsFrameQuestInfoItem"..x]:IsVisible() then
               if _G["QuestInfoRewardsFrameQuestInfoItem"..x]:IsEnabled() then
                  _G["QuestInfoRewardsFrameQuestInfoItem"..x]:Click()
               else
                  PlaySound(847)
               end
            end
         end
      end
   end)
   tFrame:Hide()
   tFrame:Show()
   DialogkeyControlFrame = tFrame
   return tFrame
end

---------------------------------------------------------------------------------------------------------------------------------------
function DialogKey:DialogKeyLogin()
	DialogkeyCreateControlFrame()
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Arm the feature. Called automatically by AceAddon when the module is enabled
-- (at SkuCore enable, and again whenever the user toggles it back on).
function DialogKey:OnEnable()
	DialogkeyCreateControlFrame()
	if DialogkeyControlFrame then
		DialogkeyControlFrame:EnableKeyboard(true)
		DialogkeyControlFrame:Show()
	end
end

-- Disarm the feature: hide and disable the driver frame so a disabled DialogKey
-- swallows nothing and clicks nothing.
function DialogKey:OnDisable()
	if DialogkeyControlFrame then
		DialogkeyControlFrame:EnableKeyboard(false)
		DialogkeyControlFrame:Hide()
	end
end
