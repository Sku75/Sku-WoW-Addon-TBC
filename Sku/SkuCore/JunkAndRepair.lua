local MODULE_NAME, MODULE_PART = "SkuCore", "JunkAndRepair"
local L = Sku.L
local _G = _G

SkuCore = SkuCore or LibStub("AceAddon-3.0"):NewAddon("SkuCore", "AceConsole-3.0", "AceEvent-3.0")

-- W4 Phase D: JunkAndRepair is a real AceAddon SUBMODULE of SkuCore. This is the
-- first feature promoted from a bare SkuCore method to a module with its own
-- lifecycle, so it can be turned on/off independently at runtime:
--   * OnEnable  arms the merchant frame (registers MERCHANT_SHOW/MERCHANT_CLOSED).
--   * OnDisable disarms it (stops any active sell + unregisters), so a disabled
--     feature genuinely does nothing.
-- AceAddon auto-enables modules when SkuCore enables (≈ PLAYER_LOGIN), replacing
-- the old explicit SkuCore.JunkAndRepair:Initialize() call in PLAYER_ENTERING_WORLD
-- (which only ran on the initial login, so junk-sell/repair did not re-arm after a
-- /reload — OnEnable fixes that by arming on every load).
-- Settings stay under the "SkuCore" SkuSettings namespace (shared with the
-- SkuZOptions junk-list menu), so there is no SavedVariables migration.
local JunkAndRepair = SkuCore:NewModule(MODULE_PART)
SkuCore.JunkAndRepair = JunkAndRepair   -- keep the published handle

-- Make this feature user-toggleable (Features menu + persisted on/off). One line;
-- the framework (SkuCore/ModuleManager.lua) handles the rest.
SkuCore:RegisterToggleableModule(MODULE_PART, function()
	return (GetLocale and GetLocale() == "deDE") and "Schrott verkaufen & reparieren" or "Sell junk & repair"
end)

-- Feature-private state (module upvalues, shared by OnEnable/OnDisable and the
-- merchant event handler; previously locals inside Initialize).
local SellJunkFrame
local IterationCount = 500
local totalPrice = 0
local SellJunkTicker, mBagID, mBagSlot

-- Function to stop selling
local function StopSelling()
   if SellJunkTicker then SellJunkTicker:Cancel() end
   if SellJunkFrame then
      SellJunkFrame:UnregisterEvent("ITEM_LOCKED")
      SellJunkFrame:UnregisterEvent("ITEM_UNLOCKED")
   end
   -- Auto-sell changed the bags without a Sku menu action, so nothing else
   -- refreshes an open bag list — it would keep showing the already-sold junk.
   -- Once selling has settled, silently re-sync the list and re-pin the cursor
   -- by identity (no announce; the user hears fresh data on next navigation).
   if _G.C_Timer and _G.C_Timer.After then
      _G.C_Timer.After(0.3, function()
         if _G.SkuBagIdleRefresh then pcall(_G.SkuBagIdleRefresh) end
      end)
   end
end

-- Vendor function
local function SellJunkFunc()
   SkuSettings:Sub("SkuCore", nil, "char").SellJunkCustomItemIds = SkuSettings:Sub("SkuCore", nil, "char").SellJunkCustomItemIds or {}
   -- Variables
   local SoldCount, Rarity, ItemPrice = 0, 0, 0
   local CurrentItemLink, void

   local tSouldSomething = false
   -- Traverse bags and sell grey items
   for BagID = 0, 4 do
      for BagSlot = 1, GetContainerNumSlots(BagID) do
         CurrentItemLink = GetContainerItemLink(BagID, BagSlot)
         if CurrentItemLink then
            void, void, Rarity, void, void, void, void, void, void, void, ItemPrice = GetItemInfo(CurrentItemLink)
            local icon, itemCount, locked, quality, readable, lootable, itemLink, isFiltered, noValue, itemID = GetContainerItemInfo(BagID, BagSlot)
            if itemID and (Rarity == 0 or SkuSettings:Sub("SkuCore", nil, "char").SellJunkCustomItemIds[itemID]) and ItemPrice ~= 0 then
               SoldCount = SoldCount + 1
               if MerchantFrame:IsShown() then
                  -- If merchant frame is open, vendor the item
                  UseContainerItem(BagID, BagSlot)
                  tSouldSomething = true
                  -- Perform actions on first iteration
                  if SellJunkTicker._remainingIterations == IterationCount then
                     -- Calculate total price
                     totalPrice = totalPrice + (ItemPrice * itemCount)
                     -- Store first sold bag slot for analysis
                     if SoldCount == 1 then
                        mBagID, mBagSlot = BagID, BagSlot
                     end
                  end
               else
                  -- If merchant frame is not open, stop selling
                  StopSelling()
                  return
               end
            end
         end
      end
   end

   -- Stop selling if no items were sold for this iteration or iteration limit was reached
   if SoldCount == 0 or SellJunkTicker and SellJunkTicker._remainingIterations == 1 then
      StopSelling()
      if totalPrice > 0 then
         dprint("Sold junk for" .. " " .. GetCoinText(totalPrice) .. ".")
      end
   end

end

-- Merchant event handler (frame OnEvent)
local function OnMerchantEvent(self, event)
   if event == "MERCHANT_SHOW" then
      -- repair
      if CanMerchantRepair() then -- If merchant is capable of repair
         local RepairCost, CanRepair = GetRepairAllCost()
         if CanRepair then -- If merchant is offering repair
            if SkuSettings:Sub("SkuCore").itemSettings.autoRepair == true then
               if RepairCost > GetMoney() then
                  SkuOptions.Voice:OutputString(L["Nicht genug Gold zum Reparieren"], false, true, 1, true)
               else
                  RepairAllItems()
                  SkuOptions.Voice:OutputString(L["Alles repariert"], false, true, 1, true)
               end
            end
         end
      end

      if SkuSettings:Sub("SkuCore").itemSettings.autoSellJunk == true then
         -- Reset variables
         totalPrice, mBagID, mBagSlot = 0, -1, -1
         -- Cancel existing ticker if present
         if SellJunkTicker then SellJunkTicker:Cancel() end
         -- Sell grey items using ticker (ends when all grey items are sold or iteration count reached)
         SkuOptions.Voice:OutputString(L["Schrott verkauft"], false, true, 1, true)
         SellJunkTicker = C_Timer.NewTicker(0.2, SellJunkFunc, IterationCount)
         SellJunkFrame:RegisterEvent("ITEM_LOCKED")
         SellJunkFrame:RegisterEvent("ITEM_UNLOCKED")
      end
   elseif event == "ITEM_LOCKED" then
      if SkuSettings:Sub("SkuCore").itemSettings.autoSellJunk == true then
         SellJunkFrame:UnregisterEvent("ITEM_LOCKED")
      end
   elseif event == "ITEM_UNLOCKED" then
      if SkuSettings:Sub("SkuCore").itemSettings.autoSellJunk == true then
         SellJunkFrame:UnregisterEvent("ITEM_UNLOCKED")
         -- Check whether vendor refuses to buy items
         if mBagID and mBagSlot and mBagID ~= -1 and mBagSlot ~= -1 then
            local texture, count, locked = GetContainerItemInfo(mBagID, mBagSlot)
            if count and not locked then
               -- Item has been unlocked but still not sold so stop selling
               StopSelling()
            end
         end
      end
   elseif event == "MERCHANT_CLOSED" then
      -- If merchant frame is closed, stop selling
      StopSelling()
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Arm the feature. Called automatically by AceAddon when the module is enabled
-- (at SkuCore enable, and again whenever the user toggles it back on).
function JunkAndRepair:OnEnable()
   if not SkuSettings:Sub("SkuCore", nil, "char").AuctionCurrentFilter then
      SkuSettings:Sub("SkuCore", nil, "char").SellJunkCustomItemIds = {}
   end

   -- Create the hidden driver frame once; reuse it across enable/disable cycles.
   if not SellJunkFrame then
      SellJunkFrame = CreateFrame("Frame", "SkuSellJunkFrame", _G["UIParent"])
      SellJunkFrame:SetSize(1, 1)
      SellJunkFrame:SetPoint("TOPLEFT", _G["UIParent"], "TOPLEFT", 0, 0)
      SellJunkFrame:Show()
      SellJunkFrame:SetScript("OnEvent", OnMerchantEvent)
   end

   SellJunkFrame:RegisterEvent("MERCHANT_SHOW")
   SellJunkFrame:RegisterEvent("MERCHANT_CLOSED")
end

-- Disarm the feature: stop any in-progress sell and unregister merchant events so
-- a disabled JunkAndRepair does nothing at a vendor.
function JunkAndRepair:OnDisable()
   StopSelling()
   if SellJunkFrame then
      SellJunkFrame:UnregisterEvent("MERCHANT_SHOW")
      SellJunkFrame:UnregisterEvent("MERCHANT_CLOSED")
   end
end
