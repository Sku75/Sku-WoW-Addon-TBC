local MODULE_NAME = "SkuNav"
local _G = _G
local L = Sku.L

SkuNav.History = {}
SkuNav.History.actions = {}

--[[
--move wp?
				local tDragY, tDragX = SkuNavMMContentToWorld(SkuNavMMGetCursorPositionContent2())
				if tDragX and tDragY then
					SkuNav:SetWaypoint(tCurrentDragWpName, {
						worldX = tDragX,
						worldY = tDragY,
					})
]]

local tIsHistoryAction = false

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:History_Generic(tActionText, aFunc, aArg1, aArg2, aArg3, aArg4, aArg5, aArg6, aArg7, aArg8, aArg9, aArg10, aArg11)
   if tIsHistoryAction == true then
      return
   end   

   table.insert(SkuNav.History.actions, 1, {
      actionText = tActionText,
      func = aFunc,
      args = {
         [1] = aArg1,
         [2] = aArg2,
         [3] = aArg3,
         [4] = aArg4,
         [5] = aArg5,
         [6] = aArg6,
         [7] = aArg7,
         [8] = aArg8,
         [9] = aArg9,
         [10] = aArg10,
         [11] = aArg11,
      }
   })

   if #SkuNav.History.actions > 100 then
      table.remove(SkuNav.History.actions, #SkuNav.History.actions)
   end

end


---------------------------------------------------------------------------------------------------------------------------------------
local function History_CreateWpLink_Hook(self, aWpName, aWpBName)
   if tIsHistoryAction == true then
      return
   end

   table.insert(SkuNav.History.actions, 1, {
      actionText = "Create waypoint link",
      func = SkuNav.DeleteWpLink,
      args = {
         [1] = aWpName,
         [2] = aWpBName,
      }
   })

   if #SkuNav.History.actions > 100 then
      table.remove(SkuNav.History.actions, #SkuNav.History.actions)
   end

end

---------------------------------------------------------------------------------------------------------------------------------------
local function History_DeleteWpLink_Hook(self, aWpName, aWpBName)
   if tIsHistoryAction == true then
      return
   end

   table.insert(SkuNav.History.actions, 1, {
      actionText = "Delete waypoint link",
      func = SkuNav.CreateWpLink,
      args = {
         [1] = aWpName,
         [2] = aWpBName,
      }
   })

   if #SkuNav.History.actions > 100 then
      table.remove(SkuNav.History.actions, #SkuNav.History.actions)
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:History_OnInitialize()
   hooksecurefunc(SkuNav, "CreateWpLink", History_CreateWpLink_Hook)
   hooksecurefunc(SkuNav, "DeleteWpLink", History_DeleteWpLink_Hook)
   SkuNav.ActionsHistory = {}
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuNav:History_Undo()
   tIsHistoryAction = true

   if SkuNav.History.actions[1] then
      print("Undoing "..SkuNav.History.actions[1].actionText)
      SkuNav.History.actions[1].func(self, SkuNav.History.actions[1].args[1], SkuNav.History.actions[1].args[2], SkuNav.History.actions[1].args[3], SkuNav.History.actions[1].args[4], SkuNav.History.actions[1].args[5], SkuNav.History.actions[1].args[6], SkuNav.History.actions[1].args[7], SkuNav.History.actions[1].args[8], SkuNav.History.actions[1].args[9], SkuNav.History.actions[1].args[10], SkuNav.History.actions[1].args[11])
      table.remove(SkuNav.History.actions, 1)
   end

   tIsHistoryAction = false
end
