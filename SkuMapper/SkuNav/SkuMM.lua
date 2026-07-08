--/script SkuOptions.db.profile["SkuNav"].showAdvancedControls = 2

---@diagnostic disable: undefined-field, undefined-doc-name
---------------------------------------------------------------------------------------------------------------------------------------
local MODULE_NAME = "SkuNav"
local L = Sku.L
local _G = _G

SkuNav = SkuNav or LibStub("AceAddon-3.0"):NewAddon("SkuNav", "AceConsole-3.0", "AceEvent-3.0")

local SkuLineRepo
local SkuWaypointLineRepoMM
SkuWaypointWidgetRepo = nil
SkuWaypointWidgetRepoMM = nil
SkuWaypointWidgetCurrent = nil

tSkuNavMMDrawCache = {}

local tSkuNavMMContent = {}
local tSkuNavMMZoom = 1
local tSkuNavMMPosX = 0
local tSkuNavMMPosY = 0
local tTileSize = 533.33
local tYardsPerTile = 533.33

SkuNavRecordingPoly = 0
SkuNavRecordingPolySub = 0
SkuNavRecordingPolyFor = 0

local slower = string.lower
local sfind = string.find
local ssplit = string.split

local minimap_size = {
	indoor = {
		 [0] = 300, -- scale
		 [1] = 240, -- 1.25
		 [2] = 180, -- 5/3
		 [3] = 120, -- 2.5
		 [4] = 80,  -- 3.75
		 [5] = 50,  -- 6
	},
	outdoor = {
		 [0] = 466 + 2/3, -- scale
		 [1] = 400,       -- 7/6
		 [2] = 333 + 1/3, -- 1.4
		 [3] = 266 + 2/6, -- 1.75
		 [4] = 200,       -- 7/3
		 [5] = 133 + 1/3, -- 3.5
	},
}

-----------------------------------------------------------------------------------------------------------------------
local function MinimapPointToWorldPoint(aMinimapmY, aMinimapX)
	local indoors = GetCVar("minimapZoom")+0 == Minimap:GetZoom() and "outdoor" or "indoor"
	local mapRadius = minimap_size[indoors][Minimap:GetZoom()] / 2
	local diffX, diffY = -aMinimapX / (Minimap:GetWidth() / 2), aMinimapmY / (Minimap:GetHeight() / 2)
	local distx, disty = diffX * mapRadius, diffY * mapRadius
	local fPlayerPosX, fPlayerPosY = UnitPosition("player")
	return -(distx - fPlayerPosX), -(disty - fPlayerPosY)
end

-----------------------------------------------------------------------------------------------------------------------
local function WorldPointToMinimapPoint(aWorldX, aWorldY)
	local indoors = GetCVar("minimapZoom")+0 == Minimap:GetZoom() and "outdoor" or "indoor"
	local mapRadius = minimap_size[indoors][Minimap:GetZoom()] / 2
	local fPlayerPosX, fPlayerPosY = UnitPosition("player")
	local xDist, yDist = fPlayerPosX - aWorldX, fPlayerPosY - aWorldY
	local diffX = xDist / mapRadius
	local diffY = yDist / mapRadius
	return diffY * (Minimap:GetHeight() / 2), -(diffX * (Minimap:GetWidth() / 2))
end

------------------------------------------------------------------------------------------------------------------------
function SkuNavMMGetCursorPositionContent2()
	local x, y = GetCursorPosition()
	local txPos = ((x / UIParent:GetScale()) - ( _G["SkuNavMMMainFrameScrollFrameContent"]:GetLeft()   * _G["SkuNavMMMainFrame"]:GetScale() ) - ((_G["SkuNavMMMainFrameScrollFrameContent"]:GetWidth()  / 2) * _G["SkuNavMMMainFrame"]:GetScale()) ) * (1 / _G["SkuNavMMMainFrame"]:GetScale())
	local tyPos = ((y / UIParent:GetScale()) - ( _G["SkuNavMMMainFrameScrollFrameContent"]:GetBottom() * _G["SkuNavMMMainFrame"]:GetScale() ) - ((_G["SkuNavMMMainFrameScrollFrameContent"]:GetHeight() / 2) * _G["SkuNavMMMainFrame"]:GetScale()) ) * (1 / _G["SkuNavMMMainFrame"]:GetScale())
	return txPos, tyPos
end

------------------------------------------------------------------------------------------------------------------------
function SkuNavMMContentToWorld(aPosX, aPosY)
	local tModTileSize = tYardsPerTile * tSkuNavMMZoom
	local tTilesX, tTilesY = (aPosX - (tSkuNavMMPosX * tSkuNavMMZoom)) / tModTileSize - 1, (aPosY - (tSkuNavMMPosY * tSkuNavMMZoom)) / tModTileSize - 2
	return -(tTilesX * tYardsPerTile), tTilesY * tYardsPerTile
end

------------------------------------------------------------------------------------------------------------------------
function SkuNavMMWorldToContent(aPosY, aPosX)
	aPosX, aPosY = (aPosX - tYardsPerTile) * tSkuNavMMZoom, (aPosY + tYardsPerTile + tYardsPerTile) * tSkuNavMMZoom
	aPosX, aPosY = (aPosX + (tSkuNavMMPosX * tSkuNavMMZoom)) - ((tSkuNavMMPosX * tSkuNavMMZoom) * 2), aPosY + (tSkuNavMMPosY * tSkuNavMMZoom)
	return -(aPosX), aPosY
end


------------------------------------------------------------------------------------------------------------------------
function SkuNav:SkuMM_PLAYER_LOGIN()
	--[[
	if SkuOptions.db.profile[MODULE_NAME].SkuNavMMMainIsCollapsedOnLogout == true then
		C_Timer.After(20, function()
			--_G["SkuNavMMMainFrame"]:SetWidth(_G["SkuNavMMMainFrame"]:GetWidth() - 300)
		end)
	end	
]]
end

------------------------------------------------------------------------------------------------------------------------
function SkuNav:SkuMM_PLAYER_LOGOUT()
	--[[
	SkuOptions.db.profile[MODULE_NAME].SkuNavMMMainIsCollapsedOnLogout = SkuOptions.db.profile[MODULE_NAME].SkuNavMMMainIsCollapsed
]]
end

------------------------------------------------------------------------------------------------------------------------
function SkuNav:DrawTerrainData(aFrame)
	--SkuNav:ClearLines(aFrame)
	if SkuOptions.db.profile[MODULE_NAME].showRoutesOnMinimap ~= true or not SkuCoreDB.TerrainData then
		return
	end
	local tExtMap = SkuNav:GetBestMapForUnit("player")

	if not SkuCoreDB.TerrainData[tExtMap] then
		return
	end

	local fPlayerPosX, fPlayerPosY = UnitPosition("player")
	local fPlayerInstanceId = select(8, GetInstanceInfo())


	local tRouteColor = {r = 1, g = 1, b = 1, a = 1}
	for ix, vx in pairs(SkuCoreDB.TerrainData[tExtMap]) do
		for iy, vy in pairs(vx) do
			if vy == true then
				local indoors = GetCVar("minimapZoom")+0 == Minimap:GetZoom() and "outdoor" or "indoor"
				local zoom = Minimap:GetZoom()
				local mapRadius = minimap_size[indoors][zoom]

				local x, y = -(fPlayerPosX - ix), (fPlayerPosY - iy) 
				x, y = x * ((mapRadius)/(minimap_size[indoors][5])), y  * ((mapRadius)/(minimap_size[indoors][5]))

				DrawLine(y, x, y + 1, x + 1, 0.8, tRouteColor.r, tRouteColor.g, tRouteColor.b, tRouteColor.a, aFrame)
			end

		end
	end
end

------------------------------------------------------------------------------------------------------------------------
local function ClearWaypoints()
	SkuLineRepo:ReleaseAll()
	SkuWaypointWidgetRepo:ReleaseAll()
end
local function DrawWaypointWidget(sx, sy, ex, ey, lineW, lineAlpha, r, g, b, aframe, aText, aWpColorR, aWpColorG, aWpColorB)
	local l = SkuWaypointWidgetRepo:Acquire()
	l:SetColorTexture(aWpColorR, aWpColorG, aWpColorB)
	l:SetSize(2, 2)
	l:SetDrawLayer("OVERLAY", 1)
	l.aText = aText
	l.MMx = sx
	l.MMy = sy
	--l:SetParent(aframe)
	l:SetPoint("CENTER", aframe, "CENTER", sx, sy)
	l:Show()
	return l
end
local function DrawLine(sx, sy, ex, ey, lineW, lineAlpha, r, g, b, aframe, aForceAnchor)
	local frame = SkuLineRepo:Acquire()
	if not frame.line or aForceAnchor then
		frame:SetPoint("CENTER", aframe, "CENTER")
		frame:SetWidth(1)
		frame:SetHeight(1)
		frame:SetFrameStrata("TOOLTIP")
	end
	frame:Show()
	if not frame.line then
		frame.line = frame:CreateLine()
	end
	frame.line:SetThickness(lineW)
	frame.line:SetColorTexture(r, g, b, lineAlpha)
	frame.line:SetStartPoint("CENTER", sx, sy)
	frame.line:SetEndPoint("CENTER", ex, ey)
	--	frame.line:Show()
	return frame.line
end

-----------------------------------------------------------------------------------------------------------------------
-- game mm
local function DrawWaypoints(aFrame)
	if SkuOptions.db.profile[MODULE_NAME].showRoutesOnMinimap ~= true then
		return
	end
	local fPlayerPosX, fPlayerPosY = UnitPosition("player")
	if not fPlayerPosX or not fPlayerPosY then
		return
	end
	local tRouteColor = {r = 1, g = 1, b = 1, a = 1}
	local tAreaId = SkuNav:GetCurrentAreaId()
	local indoors = GetCVar("minimapZoom")+0 == Minimap:GetZoom() and "outdoor" or "indoor"
	local zoom = Minimap:GetZoom()
	--local mapRadius = minimap_size[indoors][zoom]
	local tPlayerContintentId = select(3, SkuNav:GetAreaData(SkuNav:GetCurrentAreaId()))

	local tForce
	if tOldMMZoom ~= zoom then
		tForce = true
	end
	tOldMMZoom = zoom
	if tOldMMScale ~= MinimapCluster:GetScale() then
		tForce = true
	end
	tOldMMScale = MinimapCluster:GetScale()

	local tWpFrames =  {}
	local tWpObjects =  {}
	--lastXY, lastYY = UnitPosition("player")

	local mapRadius = minimap_size[indoors][zoom] / 2
	local minimapWidth = Minimap:GetWidth() / 2
	local minimapHeight = Minimap:GetHeight() / 2

	for i, v in SkuNav:ListWaypoints2(false, nil, tAreaId, tPlayerContintentId, nil) do
		tWP = SkuNav:GetWaypointData2(v)
		if tWP then
			if tWP.worldX and tWP.worldY then
				tWP.comments = tWP.comments or {["deDE"] = {},["enUS"] = {},}
				local tFinalX, tFinalY = WorldPointToMinimapPoint(tWP.worldX, tWP.worldY)
				if tWP.typeId == 1 or tWP.typeId == 4 then
					--red
					tWpFrames[v] = DrawWaypointWidget(tFinalX, tFinalY, 1,  1, 4, tRouteColor.r, tRouteColor.g, tRouteColor.b, tRouteColor.a, aFrame, v, 1, 0, 0, 1, tWP.comments[Sku.Loc])
					tWpFrames[v].hasLine = false
				elseif tWP.typeId == 2 then
					if tWP.spawnNr > 3 then
						tWpFrames[v] = DrawWaypointWidget(tFinalX, tFinalY, 1,  1, 4, tRouteColor.r, tRouteColor.g, tRouteColor.b, tRouteColor.a, aFrame, v, 0.3, 0.7, 0.7, 1, tWP.comments[Sku.Loc])
						tWpFrames[v].hasLine = false
					else
						tWpFrames[v] = DrawWaypointWidget(tFinalX, tFinalY, 1,  1, 4, tRouteColor.r, tRouteColor.g, tRouteColor.b, tRouteColor.a, aFrame, v, 1, 0.3, 0.7, 1, tWP.comments[Sku.Loc])
						tWpFrames[v].hasLine = false
					end
				elseif tWP.typeId == 3 then
					--green
					if tWP.spawnNr > 3 then
						tWpFrames[v] = DrawWaypointWidget(tFinalX, tFinalY,  1,   1, 4, tRouteColor.r, tRouteColor.g, tRouteColor.b, tRouteColor.a, aFrame, v, 0, 0.7, 0, 1, tWP.comments[Sku.Loc])
						tWpFrames[v].hasLine = false
					else
						tWpFrames[v] = DrawWaypointWidget(tFinalX, tFinalY,  1,   1, 4, tRouteColor.r, tRouteColor.g, tRouteColor.b, tRouteColor.a, aFrame, v, 0.35, 0.7, 0, 1, tWP.comments[Sku.Loc])
						tWpFrames[v].hasLine = false
					end
				else
					--white
					tWpFrames[v] = DrawWaypointWidget(tFinalX, tFinalY,  1,   1, 4, tRouteColor.r, tRouteColor.g, tRouteColor.b, tRouteColor.a, aFrame, v, 1, 1, 1, 1, tWP.comments[Sku.Loc])
					tWpFrames[v].hasLine = false
				end

				tWpFrames[v]:SetSize(3, 3)

				if (SkuNavMMShowCustomWo == true or SkuNavMMShowDefaultWo == true) == false then
					if tWP.links.byName then
						for tName, tDistance in pairs(tWP.links.byName) do
							if tWpFrames[tName] then
								local _, relativeTo, _, xOfs, yOfs = tWpFrames[v]:GetPoint(1)
								local _, PrevrelativeTo, _, PrevxOfs, PrevyOfs = tWpFrames[tName]:GetPoint(1)
								DrawLine(xOfs, yOfs, PrevxOfs, PrevyOfs, 1, tRouteColor.a, tRouteColor.r, tRouteColor.g, tRouteColor.b, aFrame, tForce) 
							end
						end
					end
				end
			end
		end
	end
end

------------------------------------------------------------------------------------------------------------------------
function SkuNav:DrawAll(aFrame)
	if not SkuWaypointWidgetRepo then
		SkuWaypointWidgetRepo = CreateTexturePool(aFrame, "OVERLAY")
	end
	if not SkuLineRepo then
		SkuLineRepo = CreateFramePool("Frame", aFrame)
	end

	if SkuDrawFlag == true then
		ClearWaypoints()
		--SkuNav:DrawTerrainData(aFrame)
		DrawWaypoints(aFrame)
	end
end

------------------------------------------------------------------------------------------------------------------------
-- new mm
------------------------------------------------------------------------------------------------------------------------
local function RotateTexture(TA, TB, TC, TD, TE, TF, x, y, size, obj)
	local ULx = ( TB*TF - TC*TE )             / (TA*TE - TB*TD) / size;
  local ULy = ( -(TA*TF) + TC*TD )          / (TA*TE - TB*TD)  / size;
  local LLx = ( -TB + TB*TF - TC*TE )       / size / (TA*TE - TB*TD);
  local LLy = ( TA - TA*TF + TC*TD )        / (TA*TE - TB*TD) / size;
  local URx = ( TE + TB*TF - TC*TE )        / size / (TA*TE - TB*TD);
  local URy = ( -TD - TA*TF + TC*TD )       / (TA*TE - TB*TD) / size;
  local LRx = ( TE - TB + TB*TF - TC*TE )   / size / (TA*TE - TB*TD);
  local LRy = ( -TD + TA -(TA*TF) + TC*TD ) / (TA*TE - TB*TD) / size;
  obj:SetTexCoord(ULx + x, ULy + y, LLx  + x, LLy  + y , URx + x , URy  + y, LRx + x , LRy + y );
end

local PreCalc = {["sin"] = {}, ["cos"] = {}} 
do 
	for x = -720, 720 do 
		PreCalc.sin[x] = sin(x) 
		PreCalc.cos[x] = cos(x) 
	end 
end

local oldtSkuNavMMZoom
function SkuNavDrawLine(sx, sy, ex, ey, lineW, lineAlpha, r, g, b, prt, lineframe, pA, pB) 
	if not sx or not sy or not ex or not ey then return nil end

	if lineframe == nil then
		lineframe = SkuWaypointLineRepoMM:Acquire()
		lineframe:Show()
	else
	end


	if sx == ex and sy == ey then 
		return nil 
	end
	local dx, dy = ex - sx, ey - sy
	local w, h = abs(dx), abs(dy)
	local d

	if w>h then 
		d = w
	else 
		d = h 
	end

	local tx = (sx + ex - d) / 2.0
	local ty = (sy + ey - d) / 2.0
	local a = atan2(dy, dx)
	local s = lineW * 16 / d	
	local ca = PreCalc.cos[floor(a)] / s 
	local sa = PreCalc.sin[floor(a)] / s

	lineframe:SetPoint("BOTTOMLEFT", pA ,"CENTER", tx, ty)
	lineframe:SetPoint("TOPRIGHT", pB, "CENTER", tx + d, ty + d)
	local C1, C2 = (1 + sa - ca) / 2.0, (1 - sa - ca) / 2.0
	lineframe:SetTexCoord(C1, C2, -sa+C1, ca+C2, ca+C1, sa+C2, ca-sa+C1, ca+sa+C2)
	lineframe:SetVertexColor(r, g, b, lineAlpha)

	if tSkuNavMMZoom < 1.75 then
		if lineframe:GetTexture() ~= "Interface\\AddOns\\SkuMapper\\SkuNav\\assets\\line64" then lineframe:SetTexture("Interface\\AddOns\\SkuMapper\\SkuNav\\assets\\line64") end
	else
		if lineframe:GetTexture() ~= "Interface\\AddOns\\SkuMapper\\SkuNav\\assets\\line" then lineframe:SetTexture("Interface\\AddOns\\SkuMapper\\SkuNav\\assets\\line") end
	end
	--lineframe.aText = "line"

	return lineframe
end

------------------------------------------------------------------------------------------------------------------------

local tContinentIdToFolderName = {
	[0] = "azeroth",
	[1] = "kalimdor",
	[369] = "",
	[530] = "expansion01",
	[571] = "northrend",
	[609] = "azeroth",
	[646] = "deephome",
	[730] = "maelstromzone",
	[967] = "maelstromzone",
	[648] = "lostisles",
	[728] = "thebattleforgilneas",
	[654] = "gilneas2",
	[2755] = "tolbarad",
	[861] = "firelandsdailies",
}
local currentContinentId
local function SkuNavMMUpdateContent()
	local _, _, tPlayerContinentID  = SkuNav:GetAreaData(SkuNav:GetCurrentAreaId())
	if currentContinentId ~= tPlayerContinentID then
		currentContinentId = tPlayerContinentID
		local folderName = tContinentIdToFolderName[currentContinentId]
		
		if folderName then
			for tx = 1, 63, 1 do
				local tPrevFrame
				for ty = 1, 63, 1 do
					_G["SkuMapTile_"..tx.."_"..ty].mapTile:SetTexture("Interface\\AddOns\\SkuMapper\\SkuNav\\assets\\MinimapData\\"..folderName.."\\map"..(tx - 1).."_"..(64 - (ty - 1))..".blp")
				end
			end
		end
	end

	local tContentFrame = _G["SkuNavMMMainFrameScrollFrameMapMain"]
	for x = 1, #tSkuNavMMContent do
		if tSkuNavMMContent[x].obj.tRender == true then
			local mX, mY = 0, 0
			local tX = tSkuNavMMContent[x].x + tSkuNavMMPosX - (mX * tSkuNavMMZoom)
			local tY = tSkuNavMMContent[x].y + tSkuNavMMPosY - (mY * tSkuNavMMZoom)
			tX = tX * tSkuNavMMZoom
			tY = tY * tSkuNavMMZoom
			tX = tX + (mX * tSkuNavMMZoom)
			tY = tY + (mY * tSkuNavMMZoom)
			tSkuNavMMContent[x].obj:SetPoint("CENTER", tContentFrame, "CENTER", tX, tY)
		end
		tSkuNavMMContent[x].obj:SetSize(tSkuNavMMContent[x].w * tSkuNavMMZoom, tSkuNavMMContent[x].h * tSkuNavMMZoom)
	end
	if UnitPosition("player") then
		_G["playerArrow"]:SetPoint("CENTER", _G["SkuNavMMMainFrameScrollFrameMapMainDraw1"], "CENTER", SkuNavMMWorldToContent(UnitPosition("player")))
	end

	--[[
	for tx = 1, 63, 1 do
		for ty = 1, 63, 1 do
			_G["SkuMapTile_"..tx.."_"..ty].tileindext:SetTextHeight(18 * tSkuNavMMZoom)	
			if tSkuNavMMZoom < 0.04 then
				_G["SkuMapTile_"..tx.."_"..ty].borderTex:SetTexture("Interface\\AddOns\\SkuMapper\\SkuNav\\assets\\tile_border64.tga")
			elseif tSkuNavMMZoom < 0.07 then
				_G["SkuMapTile_"..tx.."_"..ty].borderTex:SetTexture("Interface\\AddOns\\SkuMapper\\SkuNav\\assets\\tile_border128.tga")
			elseif tSkuNavMMZoom < 0.3 then
				_G["SkuMapTile_"..tx.."_"..ty].borderTex:SetTexture("Interface\\AddOns\\SkuMapper\\SkuNav\\assets\\tile_border256.tga")
			elseif tSkuNavMMZoom < 0.5 then
				_G["SkuMapTile_"..tx.."_"..ty].borderTex:SetTexture("Interface\\AddOns\\SkuMapper\\SkuNav\\assets\\tile_border512.tga")
			else
				_G["SkuMapTile_"..tx.."_"..ty].borderTex:SetTexture("Interface\\AddOns\\SkuMapper\\SkuNav\\assets\\tile_border1024.tga")
			end
		end
	end
	]]
end

------------------------------------------------------------------------------------------------------------------------
local function ClearWaypointsMM()
	--print("ClearWaypointsMM")
	--SkuWaypointWidgetRepoMM:ReleaseAll()
	--SkuWaypointLineRepoMM:ReleaseAll()
end
------------------------------------------------------------------------------------------------------------------------
function ClearLineMM(aPoolObject)
	if aPoolObject then
		aPoolObject:Hide()
		SkuWaypointLineRepoMM:Release(aPoolObject)
	end
end
------------------------------------------------------------------------------------------------------------------------
 function ClearWaypointMM(aPoolObjects)
	if aPoolObjects.waypoint then
		if aPoolObjects.lines then
			for i1, v1 in pairs(aPoolObjects.lines) do
				ClearLineMM(v1)
			end
			aPoolObjects.lines = {}
		end
		aPoolObjects.waypoint:Hide()
		SkuWaypointWidgetRepoMM:Release(aPoolObjects.waypoint)
		aPoolObjects.waypoint = nil
	end
end
------------------------------------------------------------------------------------------------------------------------
local function ClearAllWaypointsMM()
	for i, v in pairs(tSkuNavMMDrawCache) do
		if v.poolObjects then
			if v.poolObjects.waypoint then
				ClearWaypointMM(v.poolObjects)
				if v.poolObjects.lines then
					for i1, v1 in pairs(v.poolObjects.lines) do
						ClearLineMM(v1)
					end
					v.poolObjects.lines = {}
				end
			end
		elseif v.lines  then
			for i1, v1 in pairs(v.lines) do
				ClearLineMM(v1)
			end
			v.lines = {}
		end
	end
	tSkuNavMMDrawCache = {}
end



function SkuNavDrawWaypointWidgetMM(sx, sy, ex, ey, lineW, lineAlpha, r, g, b, aframe, aText, aWpColorR, aWpColorG, aWpColorB, aWpColorA, aComments, aPoolObject)
	aWpColorA = aWpColorA or 1
	local l = aPoolObject
	if not l then
		l = SkuWaypointWidgetRepoMM:Acquire()
		l:SetParent(_G["SkuNavMMMainFrameScrollFrameMapMainDraw1"])
		l:SetDrawLayer("ARTWORK", 1)
		l:Show()
	end
	l:SetColorTexture(aWpColorR, aWpColorG, aWpColorB, aWpColorA)
	l:SetSize(lineW * (tSkuNavMMZoom) - tSkuNavMMZoom * 2 + (2 - tSkuNavMMZoom), lineW * (tSkuNavMMZoom) - tSkuNavMMZoom * 2 + (2 - tSkuNavMMZoom))
	l.aText = aText
	l.aComments = aComments
	if l.MMx ~= sx or l.MMy ~= sy then
		l:SetPoint("CENTER", aframe, "CENTER", sx, sy)
	end
	l.MMx = sx
	l.MMy = sy

	return l
end
-----------------------------------------------------------------------------------------------------------------------
local function DrawPolyZonesMM(aFrame)
	tSkuNavMMDrawCache.polyPoolObjects = tSkuNavMMDrawCache.polyPoolObjects or {lines = {}}
	local tPlayerContintentId = select(3, SkuNav:GetAreaData(SkuNav:GetCurrentAreaId()))
	for x = 1, #SkuDB.Polygons.data do
		if SkuDB.Polygons.data[x].continentId == tPlayerContintentId then		
			if #SkuDB.Polygons.data[x].nodes > 2 then
				local tRouteColor = {r = 1, g = 1, b = 1, a = 1}
				for line = 2, #SkuDB.Polygons.data[x].nodes do
					if tSkuNavMMDrawCache[x.."-"..line] == nil then
						tSkuNavMMDrawCache[x.."-"..line] = {}
					end
					if tSkuNavMMDrawCache[x.."-"..line].poolObjects == nil then
				
						tSkuNavMMDrawCache[x.."-"..line].poolObjects = {waypoint = nil, lines = {}}
					end
		

					local tRouteColor = SkuDB.Polygons.eTypes[SkuDB.Polygons.data[x].type][2][SkuDB.Polygons.data[x].subtype][2]
					local x1, y1 = SkuNavMMWorldToContent(SkuDB.Polygons.data[x].nodes[line].x, SkuDB.Polygons.data[x].nodes[line].y)

					
					local tP1Obj = SkuNavDrawWaypointWidgetMM(x1, y1, 1,  1, 3, tRouteColor.r, tRouteColor.g, tRouteColor.b, tRouteColor.a, aFrame, v, tRouteColor.r, tRouteColor.g, tRouteColor.b, 0, nil, tSkuNavMMDrawCache[x.."-"..line].poolObjects.waypoint)
					if tP1Obj ~= nil then
						tSkuNavMMDrawCache[x.."-"..line].poolObjects.waypoint = tP1Obj
					end					
					local point, relativeTo, relativePoint, xOfs, yOfs = tP1Obj:GetPoint(1)

					local x2, y2 = SkuNavMMWorldToContent(SkuDB.Polygons.data[x].nodes[line-1].x, SkuDB.Polygons.data[x].nodes[line-1].y)
					local tP2Obj = SkuNavDrawWaypointWidgetMM(x2, y2, 1,  1, 3, tRouteColor.r, tRouteColor.g, tRouteColor.b, tRouteColor.a, aFrame, v, tRouteColor.r, tRouteColor.g, tRouteColor.b, 0, nil, tSkuNavMMDrawCache[x.."-"..line].poolObjects.waypoint)
					if tP2Obj ~= nil then
						tSkuNavMMDrawCache[x.."-"..line].poolObjects.waypoint = tP2Obj
					end					
					local Prevpoint, PrevrelativeTo, PrevrelativePoint, PrevxOfs, PrevyOfs = tP2Obj:GetPoint(1)

					local tDrawn = false

					if PrevrelativeTo then
						--SkuNavDrawLine(xOfs, yOfs, PrevxOfs, PrevyOfs, 3, tRouteColor.a, tRouteColor.r, tRouteColor.g, tRouteColor.b, aFrame, nil, relativeTo, PrevrelativeTo) 
						local tPObject = tSkuNavMMDrawCache.polyPoolObjects.lines[x.."-"..line]
						tPObject = SkuNavDrawLine(xOfs, yOfs, PrevxOfs, PrevyOfs, 3, tRouteColor.a, tRouteColor.r, tRouteColor.g, tRouteColor.b, aFrame, tPObject, relativeTo, PrevrelativeTo) 
						tSkuNavMMDrawCache.polyPoolObjects.lines[x.."-"..line] = tPObject
						tDrawn = true
					end
					
					if line == #SkuDB.Polygons.data[x].nodes then
						local x2, y2 = SkuNavMMWorldToContent(SkuDB.Polygons.data[x].nodes[1].x, SkuDB.Polygons.data[x].nodes[1].y)
						local tP2Obj = SkuNavDrawWaypointWidgetMM(x2, y2, 1,  1, 3, tRouteColor.r, tRouteColor.g, tRouteColor.b, tRouteColor.a, aFrame, v, tRouteColor.r, tRouteColor.g, tRouteColor.b, 0, nil, tSkuNavMMDrawCache[x.."-"..line].poolObjects.waypoint)
						if tP2Obj ~= nil then
							tSkuNavMMDrawCache[x.."-"..line].poolObjects.waypoint = tP2Obj
						end							
						local Prevpoint, PrevrelativeTo, PrevrelativePoint, PrevxOfs, PrevyOfs = tP2Obj:GetPoint(1)
						if PrevrelativeTo then
							--SkuNavDrawLine(xOfs, yOfs, PrevxOfs, PrevyOfs, 3, tRouteColor.a, tRouteColor.r, tRouteColor.g, tRouteColor.b, aFrame, nil, relativeTo, PrevrelativeTo) 
							local tPObject = tSkuNavMMDrawCache.polyPoolObjects.lines[x.."-"..line.."e"]
							tPObject = SkuNavDrawLine(xOfs, yOfs, PrevxOfs, PrevyOfs, 3, tRouteColor.a, tRouteColor.r, tRouteColor.g, tRouteColor.b, aFrame, tPObject, relativeTo, PrevrelativeTo) 
							tSkuNavMMDrawCache.polyPoolObjects.lines[x.."-"..line.."e"] = tPObject
							tDrawn = true
						end
					end

					if tDrawn == false then
						--don't draw line
						if tSkuNavMMDrawCache.polyPoolObjects.lines[x.."-"..line] then
							ClearLineMM(tSkuNavMMDrawCache.polyPoolObjects.lines[x.."-"..line])
							tSkuNavMMDrawCache.polyPoolObjects.lines[x.."-"..line] = nil
						end
						if tSkuNavMMDrawCache.polyPoolObjects.lines[x.."-"..line.."e"] then
							ClearLineMM(tSkuNavMMDrawCache.polyPoolObjects.lines[x.."-"..line.."e"])
							tSkuNavMMDrawCache.polyPoolObjects.lines[x.."-"..line.."e"] = nil
						end

					end
				end
			end
		end
	end
end
-----------------------------------------------------------------------------------------------------------------------
local SkuNavMMShowCustomWo = false
local SkuNavMMShowDefaultWo = false
local tWpFrames = {}
local tCutOffFactor = 0.6
local lastAreaId, lastContinentId = nil, nil
local tCountDrawnWPs = 0
local tCountDrawnLs = 0
local tCountClearedWPs = 0
local tCountClearedWPs1 = 0
local tCountClearedLs = 0
-- sku mm
function SkuNavDrawWaypointsMM(aFrame)
	local beginTime = debugprofilestop()

	tCountDrawnWPs = 0
	tCountDrawnLs = 0
	tCountClearedWPs = 0
	tCountClearedWPs1 = 0
	tCountClearedLs = 0

	if SkuOptions.db.profile[MODULE_NAME].showRoutesOnMinimap ~= true then
		--return
	end
	local fPlayerPosX, fPlayerPosY = UnitPosition("player")
	if not fPlayerPosX or not fPlayerPosY then
		return
	end
	local tRouteColor = {r = 1, g = 1, b = 1, a = 1}
	local tAreaId = SkuNav:GetCurrentAreaId()
	local tPlayerContintentId = select(3, SkuNav:GetAreaData(SkuNav:GetCurrentAreaId()))

	if not tPlayerContintentId then
		return
	end
	if not tAreaId then
		return
	end

	tWpFrames = {}

	local tSelectedZone = _G["SkuNavMMMainFrameZoneSelect"].value
	if tSelectedZone then
		if tSelectedZone == -2 then
			tAreaId = nil
		elseif tSelectedZone ~= -2 and tSelectedZone ~= -1 then
			tAreaId = tSelectedZone 
		end
	end

	--wp draw
	local tWP = nil


	if not tAreaId and not tPlayerContintentId then
		print("fail: tAreaId, tPlayerContintentId nil")
		return
	end

	if tAreaId ~= lastAreaId or lastContinentId ~= tPlayerContintentId then
		ClearAllWaypointsMM()
	end

	lastAreaId = tAreaId
	lastContinentId = tPlayerContintentId

	for i, v in SkuNav:ListWaypoints2(false, nil, tAreaId, tPlayerContintentId, nil) do
		tWP = SkuNav:GetWaypointData2(v)
		if tWP then
			local tTooltipText = v
			if tSkuNavMMDrawCache[WaypointCacheLookupAll[v]] == nil then
				tSkuNavMMDrawCache[WaypointCacheLookupAll[v]] = {}
			end
			if tSkuNavMMDrawCache[WaypointCacheLookupAll[v]].poolObjects == nil then
				
				tSkuNavMMDrawCache[WaypointCacheLookupAll[v]].poolObjects = {waypoint = nil, lines = {}}
			end
			tWP.comments = tWP.comments or {["deDE"] = {},["enUS"] = {},}
			local tShow = false
			if _G["SkuNavMMMainFrameShowFilter"].selected == true then
				if SkuQuest.QuestWpCache[v] or tWP.typeId == 1 then
					tShow = true
				end
			else
				tShow = true
			end

			if _G["SkuNavMMMainFrameShowUniqueOnly"].selected == true and tShow == true then
				if tWP.dbIndex then
					local spawnkey
					local datatable
					if tWP.typeId == 2 then
						spawnkey =  SkuDB.NpcData.Keys.spawns
						datatable = SkuDB.NpcData.Data
					elseif tWP.typeId == 3 then
						spawnkey =  SkuDB.objectKeys.spawns
						datatable = SkuDB.objectDataTBC
					end
					if spawnkey and datatable then
						
						if datatable[tWP.dbIndex] and datatable[tWP.dbIndex][spawnkey] and datatable[tWP.dbIndex][spawnkey][tAreaId] then
							if #datatable[tWP.dbIndex][spawnkey][tAreaId] > 1 then
								tShow = false
							end
						end
					end
				end
			end


			if tWP.links.byName then
				if (SkuNavMMShowCustomWo == true or SkuNavMMShowDefaultWo == true) == false then
					if tWP.links.byName then
						for tName, tDistance in pairs(tWP.links.byName) do
							tShow = true
							break
						end
					end
				end
			end


			if tShow == true then
				if tWP.worldX and tWP.worldY then
					local tFinalX, tFinalY = SkuNavMMWorldToContent(tWP.worldX, tWP.worldY)
					if 
						(tFinalX > -(tTileSize * tCutOffFactor) and tFinalX < (tTileSize * tCutOffFactor))
							and
						(tFinalY > -(tTileSize * tCutOffFactor) and tFinalY < (tTileSize * tCutOffFactor))
					then

						--needs to be drawn

						if tCountDrawnWPs + tCountDrawnLs < 15000 or tSelectedZone ~= -2 then

							tCountDrawnWPs = tCountDrawnWPs + 1

							local tSize = 4
							
							if WaypointCache[WaypointCacheLookupAll[v]].tackStep ~= nil then
								tRouteColor = {r = 0.33, g = 0.33, b = 1, a = 1}
							else
								tRouteColor = {r = 1, g = 1, b = 1, a = 1}
							end
		


							local tFilter
							if SkuOptions.db.profile["SkuNav"].waypointFilterString ~= "" then
								if string.find(slower(tWP.name), slower(SkuOptions.db.profile["SkuNav"].waypointFilterString)) then
									tFilter = true
								end
							end

							if tFilter then
								tWpFrames[v] = SkuNavDrawWaypointWidgetMM(tFinalX, tFinalY, 1,  1, tSize, tRouteColor.r, tRouteColor.g, tRouteColor.b, tRouteColor.a, aFrame, tTooltipText, 1, 1, 1, 1, tWP.comments[Sku.Loc], tSkuNavMMDrawCache[WaypointCacheLookupAll[v]].poolObjects.waypoint)
								tWpFrames[v].hasLine = false
							else
								if tWP.typeId == 1 or tWP.typeId == 4 then
										--red
									tWpFrames[v] = SkuNavDrawWaypointWidgetMM(tFinalX, tFinalY, 1,  1, tSize, tRouteColor.r, tRouteColor.g, tRouteColor.b, tRouteColor.a, aFrame, tTooltipText, 1, 0, 0, 1, tWP.comments[Sku.Loc], tSkuNavMMDrawCache[WaypointCacheLookupAll[v]].poolObjects.waypoint)
									tWpFrames[v].hasLine = false
								elseif tWP.typeId == 2 then
									if tWP.spawnNr > 3 then
										tWpFrames[v] = SkuNavDrawWaypointWidgetMM(tFinalX, tFinalY, 1,  1, tSize, tRouteColor.r, tRouteColor.g, tRouteColor.b, tRouteColor.a, aFrame, tTooltipText, 0.3, 0.7, 0.7, 1, tWP.comments[Sku.Loc], tSkuNavMMDrawCache[WaypointCacheLookupAll[v]].poolObjects.waypoint)
										tWpFrames[v].hasLine = false
									else
										tWpFrames[v] = SkuNavDrawWaypointWidgetMM(tFinalX, tFinalY, 1,  1, tSize, tRouteColor.r, tRouteColor.g, tRouteColor.b, tRouteColor.a, aFrame, tTooltipText, 1, 0.3, 0.7, 1, tWP.comments[Sku.Loc], tSkuNavMMDrawCache[WaypointCacheLookupAll[v]].poolObjects.waypoint)
										tWpFrames[v].hasLine = false
									end
								elseif tWP.typeId == 3 then
									--green
									if tWP.spawnNr > 3 then
										tWpFrames[v] = SkuNavDrawWaypointWidgetMM(tFinalX, tFinalY,  1,   1, tSize, tRouteColor.r, tRouteColor.g, tRouteColor.b, tRouteColor.a, aFrame, tTooltipText, 0, 0.7, 0, 1, tWP.comments[Sku.Loc], tSkuNavMMDrawCache[WaypointCacheLookupAll[v]].poolObjects.waypoint)
										tWpFrames[v].hasLine = false
									else
										tWpFrames[v] = SkuNavDrawWaypointWidgetMM(tFinalX, tFinalY,  1,   1, tSize, tRouteColor.r, tRouteColor.g, tRouteColor.b, tRouteColor.a, aFrame, tTooltipText, 0.8, 0.8, 0, 1, tWP.comments[Sku.Loc], tSkuNavMMDrawCache[WaypointCacheLookupAll[v]].poolObjects.waypoint)
										tWpFrames[v].hasLine = false
									end
								else
									--white
									tWpFrames[v] = SkuNavDrawWaypointWidgetMM(tFinalX, tFinalY,  1,   1, tSize, tRouteColor.r, tRouteColor.g, tRouteColor.b, tRouteColor.a, aFrame, tTooltipText, 1, 1, 1, 1, tWP.comments[Sku.Loc], tSkuNavMMDrawCache[WaypointCacheLookupAll[v]].poolObjects.waypoint)
									tWpFrames[v].hasLine = false
								end
							end


							if tWpFrames[v] ~= nil then
								tSkuNavMMDrawCache[WaypointCacheLookupAll[v]].poolObjects.waypoint = tWpFrames[v]
							end

							local tFinalSize = tSize
							if tSkuNavMMZoom <= 1 then
								tFinalSize = tSize * (tSkuNavMMZoom)
								if tFinalSize < 2 then
									tFinalSize = 2
								end
							else
								tFinalSize = 4 + (tSkuNavMMZoom / 12)
								if tFinalSize > 16 then
									tFinalSize = 16
								end
							end

							if tFilter then
								tFinalSize = tFinalSize + 3
							end

							tWpFrames[v]:SetSize(tFinalSize, tFinalSize)--4 * (tSkuNavMMZoom) - tSkuNavMMZoom * 2 + (3 - tSkuNavMMZoom), tSize * (tSkuNavMMZoom) - tSkuNavMMZoom * 2 + (3 - tSkuNavMMZoom))

						end
					else
						--don't draw wp
						if tSkuNavMMDrawCache[WaypointCacheLookupAll[v]].poolObjects.waypoint then
							tCountClearedWPs = tCountClearedWPs + 1
							ClearWaypointMM(tSkuNavMMDrawCache[WaypointCacheLookupAll[v]].poolObjects)
							tSkuNavMMDrawCache[WaypointCacheLookupAll[v]].poolObjects.waypoint = nil
						end


					end
				end
			else
				--don't draw wp
				if tSkuNavMMDrawCache[WaypointCacheLookupAll[v]].poolObjects.waypoint then
					tCountClearedWPs1 = tCountClearedWPs1 + 1
					ClearWaypointMM(tSkuNavMMDrawCache[WaypointCacheLookupAll[v]].poolObjects)
					tSkuNavMMDrawCache[WaypointCacheLookupAll[v]].poolObjects.waypoint = nil
				end				
			end
		else
			print("no wp data")
		end
	end

	for name, widget in pairs(tWpFrames) do
		tWP = SkuNav:GetWaypointData2(name)
		if tWP then

			if (SkuNavMMShowCustomWo == true or SkuNavMMShowDefaultWo == true) == false then
				if tWP.links.byName then
					for tName, tDistance in pairs(tWP.links.byName) do
						if tWpFrames[tName] then

							local tTrack
							if 
								WaypointCacheLookupAll[tWP.name] and
								WaypointCacheLookupAll[tName] and
								WaypointCache[WaypointCacheLookupAll[tName]] and
								WaypointCache[WaypointCacheLookupAll[tWP.name]] and
								WaypointCache[WaypointCacheLookupAll[tWP.name]].tackStep ~= nil and
								WaypointCache[WaypointCacheLookupAll[tName]].tackStep ~= nil 
							then
								tTrack = true
							end

							tCountDrawnWPs = tCountDrawnWPs + 1
							local _, relativeTo, _, xOfs, yOfs = tWpFrames[name]:GetPoint(1)
							local _, PrevrelativeTo, _, PrevxOfs, PrevyOfs = tWpFrames[tName]:GetPoint(1)
							local tPObject = tSkuNavMMDrawCache[WaypointCacheLookupAll[name]].poolObjects.lines[WaypointCacheLookupAll[tName]]
							if tTrack then
								tPObject = SkuNavDrawLine(xOfs, yOfs, PrevxOfs, PrevyOfs, 3, tRouteColor.a, 0.33, 0.33, 1, aFrame, tPObject, relativeTo, PrevrelativeTo) 
								tCountDrawnLs = tCountDrawnLs + 1
							else
								tPObject = SkuNavDrawLine(xOfs, yOfs, PrevxOfs, PrevyOfs, 3, tRouteColor.a, 1, 1, 1, aFrame, tPObject, 		relativeTo, PrevrelativeTo) 
								tCountDrawnLs = tCountDrawnLs + 1
							end

							tSkuNavMMDrawCache[WaypointCacheLookupAll[name]].poolObjects.lines[WaypointCacheLookupAll[tName]] = tPObject

						else
							--don't draw line
							if tSkuNavMMDrawCache[WaypointCacheLookupAll[name]].poolObjects.lines[WaypointCacheLookupAll[tName]] then
								tCountClearedLs = tCountClearedLs + 1
								ClearLineMM(tSkuNavMMDrawCache[WaypointCacheLookupAll[name]].poolObjects.lines[WaypointCacheLookupAll[tName]])
								tSkuNavMMDrawCache[WaypointCacheLookupAll[name]].poolObjects.lines[WaypointCacheLookupAll[tName]] = nil
							end
						end
					end
				end
			end
		end

	end

	SkuNavMmDrawTimer = tCountDrawnWPs / 5000
	if SkuNavMmDrawTimer < 0.25 then SkuNavMmDrawTimer = 0.25	 end

	--if SkuNavMmDrawTimer > 1 then SkuNavMmDrawTimer = 1 end

end


function SkuNav:CreateButtonFrameTemplate(aName, aParent, aText, aWidth, aHeight, aPoint, aRelativeTo, aAnchor, aOffX, aOffY)
	local tWidget = CreateFrame("Frame",aName, aParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	tWidget:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background", edgeFile="", tile = false, tileSize = 0, edgeSize = 0, insets = { left = 2, right = 2, top = 2, bottom = 2 }})
	tWidget:SetBackdropColor(0.3, 0.3, 0.3, 1)
	tWidget:SetWidth(aWidth)  
	tWidget:SetHeight(aHeight) 
	tWidget:SetPoint(aPoint, aRelativeTo,aAnchor, aOffX, aOffY)
	tWidget:SetMouseClickEnabled(true)
	tWidget.selectedDefault = false
	tWidget.selected = false
	tWidget:SetScript("OnEnter", function(self) 
		self:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background", edgeFile="", tile = false, tileSize = 0, edgeSize = 0, insets = { left = 1, right = 1, top = 1, bottom = 1 }})
		self:SetBackdropColor(0.5, 0.5, 0.5, 1)
	end)
	tWidget:SetScript("OnLeave", function(self) 
		self:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background", edgeFile="", tile = false, tileSize = 0, edgeSize = 0, insets = { left = 2, right = 2, top = 2, bottom = 2 }})
		self:SetBackdropColor(0.3, 0.3, 0.3, 1)
		if self.selected == true then
			self:SetBackdropColor(0.5, 0.5, 0.5, 1)
		end
	end)
	tWidget:SetScript("OnShow", function(self) 
		self:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background", edgeFile="", tile = false, tileSize = 0, edgeSize = 0, insets = { left = 2, right = 2, top = 2, bottom = 2 }})
		self:SetBackdropColor(0.3, 0.3, 0.3, 1)
		if self.selected == true then
			self:SetBackdropColor(0.5, 0.5, 0.5, 1)
		end
	end)
	tWidget:SetScript("OnMouseUp", function(self, button) 
		self:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background", edgeFile="", tile = false, tileSize = 0, edgeSize = 0, insets = { left = 2, right = 2, top = 2, bottom = 2 }})
		self:SetBackdropColor(0.3, 0.3, 0.3, 1)
		if self.selected == true then
			self:SetBackdropColor(0.5, 0.5, 0.5, 1)
		end
	end)
	fs = tWidget:CreateFontString(aName.."Text", "OVERLAY", "GameTooltipText")
	fs:SetTextHeight(12)
	fs:SetPoint("TOPLEFT", tWidget, "TOPLEFT", 3, 0)
	fs:SetPoint("BOTTOMRIGHT", tWidget, "BOTTOMRIGHT", -3, 0)
	fs:Show()
	tWidget.Text = fs
	tWidget.SetText = function(self, aText)
		self.Text:SetText(aText)
	end
	tWidget:SetText(aText)
	tWidget:Show()
	return tWidget
end

local function StartPolyRecording(aType, aSubtype)
	if SkuNavRecordingPoly == 0 then
		SkuNavRecordingPoly = aType
		SkuNavRecordingPolySub = aSubtype
		local _, _, tPlayerContinentID  = SkuNav:GetAreaData(SkuNav:GetCurrentAreaId())
		SkuDB.Polygons.data[#SkuDB.Polygons.data + 1] = {
			continentId = tPlayerContinentID,
			nodes = {},
			type = SkuNavRecordingPoly,
			subtype = SkuNavRecordingPolySub,
		}
		SkuNavRecordingPolyFor = #SkuDB.Polygons.data
		print("recording started", SkuDB.Polygons.eTypes[SkuNavRecordingPoly][2][SkuNavRecordingPolySub][1], "ds:", SkuNavRecordingPolyFor)
	else
		print("recording in process: ", SkuDB.Polygons.eTypes[SkuNavRecordingPoly][2][SkuNavRecordingPolySub][1])
	end
end

function SkuNav:SkuNavMMOpen()
	SkuOptions.db.profile[MODULE_NAME].SkuNavMMMainIsCollapsed = SkuOptions.db.profile[MODULE_NAME].SkuNavMMMainIsCollapsed or true
	SkuOptions.db.profile[MODULE_NAME].SkuNavMMMainWidth = SkuOptions.db.profile[MODULE_NAME].SkuNavMMMainWidth or 300
	SkuOptions.db.profile[MODULE_NAME].SkuNavMMMainHeight = SkuOptions.db.profile[MODULE_NAME].SkuNavMMMainHeight or 300
	SkuOptions.db.profile[MODULE_NAME].SkuNavMMMainPosX = SkuOptions.db.profile[MODULE_NAME].SkuNavMMMainPosX or UIParent:GetWidth() / 2
	SkuOptions.db.profile[MODULE_NAME].SkuNavMMMainPosY = SkuOptions.db.profile[MODULE_NAME].SkuNavMMMainPosY or UIParent:GetHeight() / 2
	if not SkuOptions.db.profile[MODULE_NAME].SkuNavMMOptionsPosX then
		SkuOptions.db.profile[MODULE_NAME].SkuNavMMOptionsPosX = SkuOptions.db.profile[MODULE_NAME].SkuNavMMMainPosX - 300
		SkuOptions.db.profile[MODULE_NAME].SkuNavMMOptionsPosY = SkuOptions.db.profile[MODULE_NAME].SkuNavMMMainPosY
	end

	if SkuOptions.db.profile[MODULE_NAME].showSkuMM == true then
		SkuNavMMShowCustomWo = false
		SkuNavMMShowDefaultWo = false

		if not _G["SkuNavMMMainFrame"] then
			local MainFrameObj = CreateFrame("Frame", "SkuNavMMMainFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
			--MainFrameObj:SetFrameStrata("HIGH")
			MainFrameObj.ScrollValue = 0
			MainFrameObj:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
			MainFrameObj:SetHeight(500) --275
			MainFrameObj:SetWidth(800)
			MainFrameObj:EnableMouse(true)
			MainFrameObj:SetScript("OnDragStart", function(self) self:StartMoving() end)
			MainFrameObj:SetScript("OnDragStop", function(self)
				self:StopMovingOrSizing()
				SkuOptions.db.profile[MODULE_NAME].SkuNavMMMainPosX = _G["SkuNavMMMainFrame"]:GetLeft()
				SkuOptions.db.profile[MODULE_NAME].SkuNavMMMainPosY = _G["SkuNavMMMainFrame"]:GetBottom()
				_G["SkuNavMMMainFrame"]:ClearAllPoints()
				_G["SkuNavMMMainFrame"]:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", SkuOptions.db.profile[MODULE_NAME].SkuNavMMMainPosX, SkuOptions.db.profile[MODULE_NAME].SkuNavMMMainPosY)
			end)
			MainFrameObj:SetScript("OnShow", function(self)
				local children = {_G["SkuNavMMMainFrameOptionsParent"]:GetChildren()}
				for i, child in ipairs(children) do
					child.selected = child.selectedDefault
				end
				SkuQuest.QuestWpCache = {}
				if not SkuQuest.QuestZoneCache then
					SkuQuest:BuildQuestZoneCache()
				end
				local tPlayerAreaId = SkuNav:GetCurrentAreaId()
				for i, _ in pairs(SkuDB.questDataTBC) do
					if SkuQuest.QuestZoneCache[i][tPlayerAreaId] then
						SkuQuest:GetAllQuestWps(i, _G["SkuNavMMMainFrameShowQuestStartWps"].selected, _G["SkuNavMMMainFrameShowQuestObjectiveWps"].selected, _G["SkuNavMMMainFrameShowQuestFinishWps"].selected, _G["SkuNavMMMainFrameShowLimitWps"].selected)
					end
				end					
			end)			
			MainFrameObj:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background", edgeFile="", tile = false, tileSize = 0, edgeSize = 0, insets = { left = 0, right = 0, top = 0, bottom = 0 }})
			MainFrameObj:SetBackdropColor(1, 1, 1, 1)
			MainFrameObj:SetMovable(true)
			MainFrameObj:SetClampedToScreen(true)
			MainFrameObj:RegisterForDrag("LeftButton")
			MainFrameObj:Show()

			--pos fs
			local MainFramePosFsFrame = CreateFrame("Frame", "SkuNavMMMainFramePosFs", MainFrameObj, BackdropTemplateMixin and "BackdropTemplate" or nil)
			MainFramePosFsFrame:SetPoint("TOPRIGHT", MainFrameObj, "TOPRIGHT", 0, 0)
			--MainFramePosFsFrame:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background", edgeFile="", tile = false, tileSize = 0, edgeSize = 0, insets = { left = 0, right = 0, top = 0, bottom = 0 }})
			--MainFramePosFsFrame:SetBackdropColor(1, 1, 1, 1)
			MainFramePosFsFrame:SetFrameStrata("TOOLTIP")
			MainFramePosFsFrame:SetHeight(1)
			MainFramePosFsFrame:SetWidth(1)
			MainFramePosFsFrame:Show()
			fs = MainFramePosFsFrame:CreateFontString("MousePosText")--, "HIGHLIGHT", "GameTooltipText")
			fs:SetTextHeight(12)
			fs:SetFontObject("ChatFontSmall")
			fs:SetPoint("TOPRIGHT", MainFramePosFsFrame, "TOPRIGHT", -5, -5)
			fs:SetText("")
			fs:Show()
			fs = MainFramePosFsFrame:CreateFontString("PlayerPosText")--, "HIGHLIGHT", "GameTooltipText")
			fs:SetTextHeight(12)
			fs:SetFontObject("ChatFontSmall")
			fs:SetPoint("TOPRIGHT", _G["MousePosText"], "TOPRIGHT", 0, -4)
			fs:SetText("PlayerPosText")
			fs:Show()			

			-- Resizable
			MainFrameObj:SetResizable(true)
			local tW, tH = _G["UIParent"]:GetSize()
			if MainFrameObj.SetResizeBounds then
				MainFrameObj:SetResizeBounds(300, 300, tW - 100, tH - 100)
			elseif MainFrameObj.SetMinResize then
				MainFrameObj:SetMinResize(300, 300)
				MainFrameObj:SetMaxResize(tW - 100, tH - 100)
			end			
			local rb = CreateFrame("Button", "SkuNavMMMainFrameResizeButton", _G["SkuNavMMMainFrame"])
			rb:SetPoint("BOTTOMRIGHT", 0, 0)
			rb:SetSize(16, 16)
			rb:SetNormalTexture("Interface\\AddOns\\SkuMapper\\SkuNav\\assets\\resize.tga")
			rb:SetHighlightTexture("Interface\\AddOns\\SkuMapper\\SkuNav\\assets\\resize_hightlighted.tga")
			rb:SetPushedTexture("Interface\\AddOns\\SkuMapper\\SkuNav\\assets\\resize_hightlighted.tga")
			local tRbIsDrag = false
			rb:SetScript("OnUpdate", function(self, button)
				if SkuOptions.db.profile[MODULE_NAME].showSkuMM == true then
					if tRbIsDrag == true then
						self:GetHighlightTexture():Show()
						if self:GetParent():GetWidth() < 300  then self:GetParent():SetWidth(300  ) end
						if self:GetParent():GetHeight() < 300 then self:GetParent():SetHeight(300) end
						_G["SkuNavMMMainFrameScrollFrame"]:SetWidth(self:GetParent():GetWidth()  - 10)
						_G["SkuNavMMMainFrameScrollFrame"]:SetHeight(self:GetParent():GetHeight() - 10)
						_G["SkuNavMMMainFrameScrollFrame1"]:SetWidth(self:GetParent():GetWidth()  - 10)
						_G["SkuNavMMMainFrameScrollFrame1"]:SetHeight(self:GetParent():GetHeight() - 10)

						_G["SkuNavMMMainFrameScrollFrameContent"]:SetWidth(self:GetParent():GetWidth()  - 10)
						_G["SkuNavMMMainFrameScrollFrameContent"]:SetHeight(self:GetParent():GetHeight() - 10)
						_G["SkuNavMMMainFrameScrollFrameContent1"]:SetWidth(self:GetParent():GetWidth()  - 10)
						_G["SkuNavMMMainFrameScrollFrameContent1"]:SetHeight(self:GetParent():GetHeight() - 10)

						SkuOptions.db.profile[MODULE_NAME].SkuNavMMMainPosX = _G["SkuNavMMMainFrame"]:GetLeft()
						SkuOptions.db.profile[MODULE_NAME].SkuNavMMMainPosY = _G["SkuNavMMMainFrame"]:GetBottom()
					end
				end
			end)
			rb:SetScript("OnMouseDown", function(self, button)
				if button == "LeftButton" then
					if SkuOptions.db.profile["SkuNav"].showAdvancedControls > 1 then
						_G["SkuNavMMMainEditBoxEditBox"]:ClearFocus()
					end
					self:GetParent():StartSizing("BOTTOMRIGHT")
					self:GetHighlightTexture():Hide() -- more noticeable
					tRbIsDrag = true
				end
			end)
			rb:SetScript("OnMouseUp", function(self, button)
				self:GetParent():StopMovingOrSizing()
				self:GetHighlightTexture():Show()
				_G["SkuNavMMMainFrameScrollFrame"]:SetWidth(self:GetParent():GetWidth()  - 10)
				_G["SkuNavMMMainFrameScrollFrame"]:SetHeight(self:GetParent():GetHeight() - 10)
				_G["SkuNavMMMainFrameScrollFrame1"]:SetWidth(self:GetParent():GetWidth()  - 10)
				_G["SkuNavMMMainFrameScrollFrame1"]:SetHeight(self:GetParent():GetHeight() - 10)

				_G["SkuNavMMMainFrameScrollFrameContent"]:SetWidth(self:GetParent():GetWidth()  - 10)
				_G["SkuNavMMMainFrameScrollFrameContent"]:SetHeight(self:GetParent():GetHeight() - 10)
				_G["SkuNavMMMainFrameScrollFrameContent1"]:SetWidth(self:GetParent():GetWidth()  - 10)
				_G["SkuNavMMMainFrameScrollFrameContent1"]:SetHeight(self:GetParent():GetHeight() - 10)
		
				SkuOptions.db.profile[MODULE_NAME].SkuNavMMMainWidth = self:GetParent():GetWidth()
				SkuOptions.db.profile[MODULE_NAME].SkuNavMMMainHeight = self:GetParent():GetHeight()

				SkuOptions.db.profile[MODULE_NAME].SkuNavMMMainPosX = _G["SkuNavMMMainFrame"]:GetLeft()
				SkuOptions.db.profile[MODULE_NAME].SkuNavMMMainPosY = _G["SkuNavMMMainFrame"]:GetBottom()

				_G["SkuNavMMMainFrame"]:ClearAllPoints()
				_G["SkuNavMMMainFrame"]:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", SkuOptions.db.profile[MODULE_NAME].SkuNavMMMainPosX, SkuOptions.db.profile[MODULE_NAME].SkuNavMMMainPosY)

				tRbIsDrag = false
			end)

			--collapse
			local rb = CreateFrame("Button", "SkuNavMMMainCollapseButton", _G["SkuNavMMMainFrame"])
			rb:SetPoint("LEFT")
			rb:SetSize(16, 16)
			rb:SetNormalTexture("Interface\\AddOns\\SkuMapper\\SkuNav\\assets\\expand1.tga")
			rb:SetHighlightTexture("Interface\\AddOns\\SkuMapper\\SkuNav\\assets\\expand_hightlighted1.tga")
			rb:SetPushedTexture("Interface\\AddOns\\SkuMapper\\SkuNav\\assets\\expand_hightlighted1.tga")
			rb:SetScript("OnMouseUp", function(self, button)
				self:GetHighlightTexture():Show()
				if _G["SkuNavMMMainFrameOptionsParent"]:IsShown() then
					_G["SkuNavMMMainFrameOptionsParent"]:SetWidth(0)
					_G["SkuNavMMMainFrameOptionsParent"]:Hide()
					--_G["SkuNavMMMainFrame"]:ClearAllPoints()
					--_G["SkuNavMMMainFrame"]:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", (_G["SkuNavMMMainFrame"]:GetLeft() + 300 ), (_G["SkuNavMMMainFrame"]:GetBottom()))
					--_G["SkuNavMMMainFrame"]:SetWidth(_G["SkuNavMMMainFrame"]:GetWidth() - 300)

					--_G["SkuNavMMMainFrameScrollFrame"]:SetPoint("TOPLEFT", _G["SkuNavMMMainFrame"], "TOPLEFT", _G["SkuNavMMMainFrameOptionsParent"]:GetWidth() + 5, -5)
					--_G["SkuNavMMMainFrameScrollFrame1"]:SetPoint("TOPLEFT", _G["SkuNavMMMainFrame"], "TOPLEFT", _G["SkuNavMMMainFrameOptionsParent"]:GetWidth() + 5, -5)
					SkuOptions.db.profile[MODULE_NAME].SkuNavMMMainIsCollapsed = true
		
				else
					_G["SkuNavMMMainFrameOptionsParent"]:Show()
					_G["SkuNavMMMainFrameOptionsParent"]:SetWidth(300)
					--_G["SkuNavMMMainFrame"]:ClearAllPoints()
					--_G["SkuNavMMMainFrame"]:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", (_G["SkuNavMMMainFrame"]:GetLeft() - 300 ), (_G["SkuNavMMMainFrame"]:GetBottom()))
					--_G["SkuNavMMMainFrame"]:SetWidth(_G["SkuNavMMMainFrame"]:GetWidth() + 300)
					--_G["SkuNavMMMainFrameScrollFrame"]:SetPoint("TOPLEFT", _G["SkuNavMMMainFrame"], "TOPLEFT", _G["SkuNavMMMainFrameOptionsParent"]:GetWidth() + 5, -5)
					--_G["SkuNavMMMainFrameScrollFrame1"]:SetPoint("TOPLEFT", _G["SkuNavMMMainFrame"], "TOPLEFT", _G["SkuNavMMMainFrameOptionsParent"]:GetWidth() + 5, -5)
					SkuOptions.db.profile[MODULE_NAME].SkuNavMMMainIsCollapsed = false
				end
			end)

			----------------------------menu
			--buttons
			SkuMapperFocusOnPlayer = true

			local tMain = _G["SkuNavMMMainFrame"]
			--map texture parent frame
			local f1 = CreateFrame("Frame", "SkuNavMMMainFrameOptionsParent", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
			f1:SetBackdrop({bgFile="Interface\\AddOns\\SkuMapper\\SkuNav\\assets\\white.tga", edgeFile="", tile = false, tileSize = 0, edgeSize = 32, insets = { left = -1, right = 3, top = 0, bottom = -3 }})
			f1:SetBackdropColor(0.5, 0.5, 0.5, 1)
			f1:SetWidth(300)  
			f1:SetHeight(300) 
			f1:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", SkuOptions.db.profile[MODULE_NAME].SkuNavMMOptionsPosX, (SkuOptions.db.profile[MODULE_NAME].SkuNavMMOptionsPosY))
			f1:EnableMouse(true)
			f1:SetScript("OnDragStart", function(self) self:StartMoving() end)
			f1:SetScript("OnDragStop", function(self)
				self:StopMovingOrSizing()
				SkuOptions.db.profile[MODULE_NAME].SkuNavMMOptionsPosX = _G["SkuNavMMMainFrameOptionsParent"]:GetLeft()
				SkuOptions.db.profile[MODULE_NAME].SkuNavMMOptionsPosY = _G["SkuNavMMMainFrameOptionsParent"]:GetBottom()
				_G["SkuNavMMMainFrameOptionsParent"]:ClearAllPoints()
				_G["SkuNavMMMainFrameOptionsParent"]:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", SkuOptions.db.profile[MODULE_NAME].SkuNavMMOptionsPosX, SkuOptions.db.profile[MODULE_NAME].SkuNavMMOptionsPosY)
			end)
			f1:SetScript("OnShow", function(self)
			end)			
			f1:SetMovable(true)
			f1:SetClampedToScreen(true)
			f1:RegisterForDrag("LeftButton")
			f1:Show()

			if SkuOptions.db.profile["SkuNav"].showAdvancedControls > 1 then
				f1:SetHeight(380) 
			end
			if SkuOptions.db.profile["SkuNav"].showAdvancedControls > 2 then
				f1:SetHeight(550) 
			end

			local tOptionsParent = _G["SkuNavMMMainFrameOptionsParent"]
			local tButtonObj = SkuNav:CreateButtonFrameTemplate("SkuNavMMMainFrameFollow", tOptionsParent, "Follow", 100, 20, "TOPLEFT", tOptionsParent, "TOPLEFT", 3, -3)
			tButtonObj:SetScript("OnMouseUp", function(self, button)
				SkuMapperFocusOnPlayer = true
			end)


			local tButtonObj = SkuNav:CreateButtonFrameTemplate("SkuNavMMMainFrameShowFilter", tOptionsParent, "Filter", 95, 20, "TOPLEFT", _G["SkuNavMMMainFrameFollow"], "TOPLEFT", 100, 0)
			tButtonObj:SetScript("OnMouseUp", function(self, button)
				self.selected  = self.selected  ~= true
				SkuQuest.QuestWpCache = {}
				local tPlayerAreaId = SkuNav:GetCurrentAreaId()
				for i, _ in pairs(SkuDB.questDataTBC) do
					if SkuQuest.QuestZoneCache[i][tPlayerAreaId] then
						SkuQuest:GetAllQuestWps(i, _G["SkuNavMMMainFrameShowQuestStartWps"].selected, _G["SkuNavMMMainFrameShowQuestObjectiveWps"].selected, _G["SkuNavMMMainFrameShowQuestFinishWps"].selected, _G["SkuNavMMMainFrameShowLimitWps"].selected)
					end
				end
			end)
			_G["SkuNavMMMainFrameShowFilter"].selectedDefault = false

			local tButtonObj = SkuNav:CreateButtonFrameTemplate("SkuNavMMMainFrameShowUniqueOnly", tOptionsParent, "Unique only", 100, 20, "TOPLEFT", _G["SkuNavMMMainFrameFollow"], "TOPLEFT", 0, -20)
			tButtonObj:SetScript("OnMouseUp", function(self, button)
				self.selected  = self.selected  ~= true
			end)
			_G["SkuNavMMMainFrameShowUniqueOnly"].selectedDefault = false


			local tButtonObj = SkuNav:CreateButtonFrameTemplate("SkuNavMMMainFrameShowQuestStartWps", tOptionsParent, "Starts", 95, 20, "TOPLEFT", _G["SkuNavMMMainFrameFollow"], "TOPLEFT", 100, -20)
			tButtonObj:SetScript("OnMouseUp", function(self, button)
				self.selected  = self.selected  ~= true
				SkuQuest.QuestWpCache = {}
				local tPlayerAreaId = SkuNav:GetCurrentAreaId()
				for i, _ in pairs(SkuDB.questDataTBC) do
					if SkuQuest.QuestZoneCache[i][tPlayerAreaId] then
						SkuQuest:GetAllQuestWps(i, _G["SkuNavMMMainFrameShowQuestStartWps"].selected, _G["SkuNavMMMainFrameShowQuestObjectiveWps"].selected, _G["SkuNavMMMainFrameShowQuestFinishWps"].selected, _G["SkuNavMMMainFrameShowLimitWps"].selected)
					end
				end
			end)
			_G["SkuNavMMMainFrameShowQuestStartWps"].selectedDefault = true

			local tButtonObj = SkuNav:CreateButtonFrameTemplate("SkuNavMMMainFrameShowQuestObjectiveWps", tOptionsParent, "Objectives", 95, 20, "TOPLEFT", _G["SkuNavMMMainFrameShowQuestStartWps"], "TOPLEFT", 95, 0)
			tButtonObj:SetScript("OnMouseUp", function(self, button)
				self.selected  = self.selected  ~= true
				SkuQuest.QuestWpCache = {}
				local tPlayerAreaId = SkuNav:GetCurrentAreaId()
				for i, _ in pairs(SkuDB.questDataTBC) do
					if SkuQuest.QuestZoneCache[i][tPlayerAreaId] then
						SkuQuest:GetAllQuestWps(i, _G["SkuNavMMMainFrameShowQuestStartWps"].selected, _G["SkuNavMMMainFrameShowQuestObjectiveWps"].selected, _G["SkuNavMMMainFrameShowQuestFinishWps"].selected, _G["SkuNavMMMainFrameShowLimitWps"].selected)
					end
				end				
			end)
			_G["SkuNavMMMainFrameShowQuestObjectiveWps"].selectedDefault = true

			local tButtonObj = SkuNav:CreateButtonFrameTemplate("SkuNavMMMainFrameShowQuestFinishWps", tOptionsParent, "Finish", 95, 20, "TOPLEFT", _G["SkuNavMMMainFrameShowQuestStartWps"], "TOPLEFT", 0, -20)
			tButtonObj:SetScript("OnMouseUp", function(self, button)
				self.selected  = self.selected  ~= true
				SkuQuest.QuestWpCache = {}
				local tPlayerAreaId = SkuNav:GetCurrentAreaId()
				for i, _ in pairs(SkuDB.questDataTBC) do
					if SkuQuest.QuestZoneCache[i][tPlayerAreaId] then
						SkuQuest:GetAllQuestWps(i, _G["SkuNavMMMainFrameShowQuestStartWps"].selected, _G["SkuNavMMMainFrameShowQuestObjectiveWps"].selected, _G["SkuNavMMMainFrameShowQuestFinishWps"].selected, _G["SkuNavMMMainFrameShowLimitWps"].selected)
					end
				end				
			end)
			_G["SkuNavMMMainFrameShowQuestFinishWps"].selectedDefault = true

			local tButtonObj = SkuNav:CreateButtonFrameTemplate("SkuNavMMMainFrameShowLimitWps", tOptionsParent, "Limit", 95, 20, "TOPLEFT", _G["SkuNavMMMainFrameShowQuestFinishWps"], "TOPLEFT", 95, 0)
			tButtonObj:SetScript("OnMouseUp", function(self, button)
				self.selected  = self.selected  ~= true
				SkuQuest.QuestWpCache = {}
				local tPlayerAreaId = SkuNav:GetCurrentAreaId()
				for i, _ in pairs(SkuDB.questDataTBC) do
					if SkuQuest.QuestZoneCache[i][tPlayerAreaId] then
						SkuQuest:GetAllQuestWps(i, _G["SkuNavMMMainFrameShowQuestStartWps"].selected, _G["SkuNavMMMainFrameShowQuestObjectiveWps"].selected, _G["SkuNavMMMainFrameShowQuestFinishWps"].selected, _G["SkuNavMMMainFrameShowLimitWps"].selected)
					end
				end				
			end)
			_G["SkuNavMMMainFrameShowLimitWps"].selectedDefault = false

			local tDropdownFrame = SkuNav:CreateButtonFrameTemplate("SkuNavMMMainFrameZoneSelect", tOptionsParent, "Zone", 95, 20, "TOPLEFT", _G["SkuNavMMMainFrameFollow"], "TOPLEFT", 195, 0)
			local tex = tDropdownFrame:CreateTexture(nil, "OVERLAY")
			tex:SetTexture("Interface\\AddOns\\SkuMapper\\SkuNav\\assets\\ui_dropdown.tga")
			tex:SetSize(20, 20)
			tex:SetPoint("TOPRIGHT", tDropdownFrame, "TOPRIGHT", 0, 0)


			tDropdownFrame.MenuButtonsObjects = {}
			tDropdownFrame.value = -1
			tDropdownFrame:SetText("Current Zone") 
			tDropdownFrame:SetScript("OnEnter", function(self)
				GameTooltip:ClearLines()
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:AddLine(self.Text:GetText(), 1, 1, 1)
				GameTooltip:AddLine("zone id: "..(self.value or ""), 1, 1, 1)
				GameTooltip:Show()
			end)
			tDropdownFrame:SetScript("OnLeave", function(self)
				GameTooltip:Hide()
			end)
			tDropdownFrame.maxVisibleItems = 11
			tDropdownFrame.maxCurrentItems = 0
			tDropdownFrame.firstVisibleItem = 1
			tDropdownFrame.UpdateList = function(self, a, b)
				local tPlayerContintentId = select(3, SkuNav:GetAreaData(SkuNav:GetCurrentAreaId()))
				local tMenuItems = {}
				for i, v in pairs(SkuDB.InternalAreaTable) do
					if v.ContinentID == tPlayerContintentId and v.ParentAreaID == 0 then
						tMenuItems[#tMenuItems + 1] = {zoneId = i, buttonText = v.AreaName_lang[Sku.Loc],}
					end
				end
				tMenuItems[#tMenuItems + 1] = {zoneId = -1, buttonText = "Current Zone",}
				tMenuItems[#tMenuItems + 1] = {zoneId = -2, buttonText = "Current Contintent",}
				
				self.maxCurrentItems = #tMenuItems
				for x = 1, self.maxVisibleItems do
					if self.MenuButtonsObjects[x] then
						self.MenuButtonsObjects[x]:SetText(tMenuItems[x + self.firstVisibleItem - 1].buttonText)
						self.MenuButtonsObjects[x].value = tMenuItems[x + self.firstVisibleItem - 1].zoneId
					end
				end
			end

			tDropdownFrame:SetScript("OnMouseUp", function(self, button)
				self.selected  = self.selected  ~= true
				local tPlayerContintentId = select(3, SkuNav:GetAreaData(SkuNav:GetCurrentAreaId()))
				local tMenuItems = {}
				local tMenuItemsMaxLen = 0
				for i, v in pairs(SkuDB.InternalAreaTable) do
					if v.ContinentID == tPlayerContintentId and v.ParentAreaID == 0 then
						tMenuItems[#tMenuItems + 1] = {zoneId = i, buttonText = v.AreaName_lang[Sku.Loc],}
						if string.len(tMenuItems[#tMenuItems].buttonText) > tMenuItemsMaxLen then
							tMenuItemsMaxLen = string.len(tMenuItems[#tMenuItems].buttonText)
						end
					end
				end
				tMenuItems[#tMenuItems + 1] = {zoneId = -1, buttonText = "Current Zone",}
				if string.len(tMenuItems[#tMenuItems].buttonText) > tMenuItemsMaxLen then
					tMenuItemsMaxLen = string.len(tMenuItems[#tMenuItems].buttonText)
				end
				tMenuItems[#tMenuItems + 1] = {zoneId = -2, buttonText = "Current Contintent",}
				if string.len(tMenuItems[#tMenuItems].buttonText) > tMenuItemsMaxLen then
					tMenuItemsMaxLen = string.len(tMenuItems[#tMenuItems].buttonText)
				end
				
				--for x = 1, #tMenuItems do
				self.maxCurrentItems = #tMenuItems
				for x = 1, self.maxVisibleItems do
					if tMenuItems[x + _G["SkuNavMMMainFrameZoneSelect"].firstVisibleItem - 1] then
						self.MenuButtonsObjects[x] = _G["SkuNavMMMainFrameZoneSelectEntry"..x] or SkuNav:CreateButtonFrameTemplate("SkuNavMMMainFrameZoneSelectEntry"..x, self, "button"..x, 95, 20, "TOPLEFT", self, "TOPLEFT", 25, -(x * 16))
						self.MenuButtonsObjects[x]:SetScript("OnMouseDown", function(self, button)
							local tSelectedZone = _G["SkuNavMMMainFrameZoneSelect"].value
							if tSelectedZone then
								if tSelectedZone == -2 then
									if tSkuNavMMZoom < 0.5 then
										tSkuNavMMZoom = 0.5
									end
								end
							end
							SkuNavMMUpdateContent()

							ClearAllWaypointsMM()
							--_G["SkuNavMMMainFrameScrollFrameContent"]:GetScript("OnMouseWheel")(_G["SkuNavMMMainFrameScrollFrameContent"]:GetScript("OnMouseWheel"), 1)

							self:GetParent().value = self.value
							self:GetParent():SetText(tMenuItems[x + _G["SkuNavMMMainFrameZoneSelect"].firstVisibleItem - 1].buttonText) 
							for z = 1, #self:GetParent().MenuButtonsObjects do
								self:GetParent().MenuButtonsObjects[z]:Hide()
							end
						end)
						self.MenuButtonsObjects[x]:SetFrameStrata("FULLSCREEN_DIALOG")						
						self.MenuButtonsObjects[x]:SetWidth(tMenuItemsMaxLen * 8)						
						self.MenuButtonsObjects[x]:SetText(tMenuItems[x + _G["SkuNavMMMainFrameZoneSelect"].firstVisibleItem - 1].buttonText)
						self.MenuButtonsObjects[x].value = tMenuItems[x + _G["SkuNavMMMainFrameZoneSelect"].firstVisibleItem - 1].zoneId
						if self.selected == true then
							self.MenuButtonsObjects[x]:Show()
						else
							self.MenuButtonsObjects[x]:Hide()
						end
					end
				end
				for x = self.maxVisibleItems + 1, #self.MenuButtonsObjects do
					self.MenuButtonsObjects[x]:Hide()
				end
				if self.MenuButtonsObjects[self.maxVisibleItems] then
					self.ItemsBackdropFrame = self.ItemsBackdropFrame or CreateFrame("Frame",nil, tOptionsParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
					self.ItemsBackdropFrame:SetFrameStrata("TOOLTIP")						
					self.ItemsBackdropFrame:SetWidth(tMenuItemsMaxLen * 8 + 10)
					--self.ItemsBackdropFrame:SetHeight(500)--20 * #tMenuItems + 10)
					self.ItemsBackdropFrame:SetHeight(20 * self.maxVisibleItems + 10)
					self.ItemsBackdropFrame:SetPoint("TOPLEFT", self.MenuButtonsObjects[1], "TOPLEFT", 0, 0)
					--self.ItemsBackdropFrame:SetPoint("BOTTOMRIGHT", self.MenuButtonsObjects[#tMenuItems], "BOTTOMRIGHT", 0, 0)
					self.ItemsBackdropFrame:SetPoint("BOTTOMRIGHT", self.MenuButtonsObjects[self.maxVisibleItems], "BOTTOMRIGHT", 0, 0)
					self.ItemsBackdropFrame:EnableMouse(false)
				
					self.ItemsBackdropFrame:SetScript("OnMouseWheel", function(self, aDelta)
						if aDelta > 0 then
							if _G["SkuNavMMMainFrameZoneSelect"].firstVisibleItem > 1 then
								_G["SkuNavMMMainFrameZoneSelect"].firstVisibleItem = _G["SkuNavMMMainFrameZoneSelect"].firstVisibleItem - 1
							end
						else
							if _G["SkuNavMMMainFrameZoneSelect"].firstVisibleItem < _G["SkuNavMMMainFrameZoneSelect"].maxCurrentItems - _G["SkuNavMMMainFrameZoneSelect"].maxVisibleItems + 1 then
								_G["SkuNavMMMainFrameZoneSelect"].firstVisibleItem = _G["SkuNavMMMainFrameZoneSelect"].firstVisibleItem + 1
							end
						end
						_G["SkuNavMMMainFrameZoneSelect"]:UpdateList()
					end)
					self.ItemsBackdropFrame:SetScript("OnLeave", function(self)
						if self:IsVisible() == true then
							_G["SkuNavMMMainFrameZoneSelect"]:GetScript("OnMouseUp")(_G["SkuNavMMMainFrameZoneSelect"], "LeftButton")
						end
					end)
					self.ItemsBackdropFrame:SetMouseClickEnabled(false)
						if self.selected == true then
						self.ItemsBackdropFrame:Show()
					else
						self.ItemsBackdropFrame:Hide()
					end
				end
			end)
			_G["SkuNavMMMainFrameZoneSelect"].selectedDefault = false


			--init
			_G["SkuNavMMMainFrameShowFilter"].selected = _G["SkuNavMMMainFrameShowFilter"].selectedDefault
			_G["SkuNavMMMainFrameShowQuestStartWps"].selected = _G["SkuNavMMMainFrameShowQuestStartWps"].selectedDefault
			_G["SkuNavMMMainFrameShowQuestObjectiveWps"].selected = _G["SkuNavMMMainFrameShowQuestObjectiveWps"].selectedDefault
			_G["SkuNavMMMainFrameShowQuestFinishWps"].selected = _G["SkuNavMMMainFrameShowQuestFinishWps"].selectedDefault
			_G["SkuNavMMMainFrameShowLimitWps"].selected = _G["SkuNavMMMainFrameShowLimitWps"].selectedDefault
			if not SkuQuest.QuestZoneCache then
				SkuQuest:BuildQuestZoneCache()
			end
			SkuQuest.QuestWpCache = {}
			local tPlayerAreaId = SkuNav:GetCurrentAreaId()
			for i, _ in pairs(SkuDB.questDataTBC) do
				if SkuQuest.QuestZoneCache[i][tPlayerAreaId] then
					SkuQuest:GetAllQuestWps(i, _G["SkuNavMMMainFrameShowQuestStartWps"].selected, _G["SkuNavMMMainFrameShowQuestObjectiveWps"].selected, _G["SkuNavMMMainFrameShowQuestFinishWps"].selected, _G["SkuNavMMMainFrameShowLimitWps"].selected)
				end
			end			



			-- filter EditBox
			local f = CreateFrame("Frame", "SkuNavMMMainFrameFilterEditBox", tOptionsParent, BackdropTemplateMixin and "BackdropTemplate" or nil)--, "DialogBoxFrame")
			f:SetPoint("TOPLEFT", _G["SkuNavMMMainFrameFollow"], "TOPLEFT", 2, -60)
			f:SetSize(286, 17)
			f:SetBackdrop({bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeSize = 2, insets = { left = 0, right = 0, top = 0, bottom = 0 },})
			f:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
			f:SetBackdropColor(0.5, 0.5, 0.5, 1)
			f:Show()
			local fs = SkuNavMMMainFrameFilterEditBox:CreateFontString("SkuNavMMMainFrameFilterEditBoxLabel")--, "HIGHLIGHT", "GameTooltipText")
			fs:SetTextHeight(12)
			fs:SetFontObject("ChatFontSmall")
			fs:SetPoint("TOPLEFT", SkuNavMMMainFrameFilterEditBox, "TOPLEFT", 0, 12)
			fs:SetText(L["Filter"])
			fs:Show()			
			local eb = CreateFrame("EditBox", "SkuNavMMMainFrameFilterEditBoxEditBox", _G["SkuNavMMMainFrameFilterEditBox"])
			eb:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
			eb:SetSize(f:GetSize())
			eb:SetMultiLine(false)
			eb:SetAutoFocus(false)
			eb:SetFontObject("ChatFontSmall")
			eb:SetScript("OnEscapePressed", function(self) 
				SkuOptions.db.profile["SkuNav"].waypointFilterString = self:GetText()
				SkuOptions.db.profile["SkuNav"].waypointFilterString = string.gsub(SkuOptions.db.profile["SkuNav"].waypointFilterString, "%-", "%%%-")

				self:ClearFocus()
				PlaySound(89)
			end)
			eb:SetScript("OnEnterPressed", function(self) 
				SkuOptions.db.profile["SkuNav"].waypointFilterString = self:GetText()
				SkuOptions.db.profile["SkuNav"].waypointFilterString = string.gsub(SkuOptions.db.profile["SkuNav"].waypointFilterString, "%-", "%%%-")


				self:ClearFocus()
				PlaySound(89)
			end)


			-- suffix EditBoxes
			
			---------------- AutoEn
			local tEnSuffixY = -33
			local tDeSuffixY = -33
			if SkuOptions.db.profile["SkuNav"].showAdvancedControls > 1 then
				tDeSuffixY = -105
			elseif Sku.Loc == "enUS" then
				tDeSuffixY = -33
			end

			local tName = "SkuNavMMMainFrameSuffixAutoenUSEditBox"
			local f = CreateFrame("Frame", tName, tOptionsParent, BackdropTemplateMixin and "BackdropTemplate" or nil)--, "DialogBoxFrame")
			f:SetPoint("TOPLEFT", _G["SkuNavMMMainFrameFilterEditBox"], "TOPLEFT", 0, -35)
			f:SetSize(286, 17)
			f:SetBackdrop({bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "", edgeSize = 2, insets = { left = 0, right = 0, top = 0, bottom = 0 },})
			f:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
			f:SetBackdropColor(0.5, 0.5, 0.5, 1)
			f:Show()
			local fs = _G[tName]:CreateFontString(tName.."Label")--, "HIGHLIGHT", "GameTooltipText")
			fs:SetTextHeight(12)
			fs:SetFontObject("ChatFontSmall")
			fs:SetPoint("TOPLEFT", _G[tName], "TOPLEFT", 0, 12)
			fs:SetText("EN name for new auto waypoints (+ number)")
			fs:Show()			
			local eb = CreateFrame("EditBox", tName.."EditBox", _G[tName])
			eb:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
			eb:SetSize(f:GetSize())
			eb:SetMultiLine(false)
			eb:SetAutoFocus(false)
			eb:SetFontObject("ChatFontSmall")
			eb:SetScript("OnEscapePressed", function(self) 
				SkuNav:UpdateAutoPrefixes()
				self:ClearFocus()
				PlaySound(89)
			end)
			eb:SetScript("OnEnterPressed", function(self) 
				SkuNav:UpdateAutoPrefixes()
				self:ClearFocus()
				PlaySound(89)
			end)
			eb:Disable()
			-- CustomEn
			local tName = "SkuNavMMMainFrameSuffixCustomenUSEditBox"
			local f = CreateFrame("Frame", tName, tOptionsParent, BackdropTemplateMixin and "BackdropTemplate" or nil)--, "DialogBoxFrame")
			f:SetPoint("TOPLEFT", _G["SkuNavMMMainFrameSuffixAutoenUSEditBox"], "TOPLEFT", 0, -33)
			f:SetSize(236, 20)
			f:SetBackdrop({bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeSize = 2, insets = { left = 0, right = 0, top = 0, bottom = 0 },})
			f:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
			f:SetBackdropColor(0.5, 0.5, 0.5, 1)
			f:Show()
			local fs = _G[tName]:CreateFontString(tName.."Label")--, "HIGHLIGHT", "GameTooltipText")
			fs:SetTextHeight(12)
			fs:SetFontObject("ChatFontSmall")
			fs:SetPoint("TOPLEFT", _G[tName], "TOPLEFT", 0, 12)
			fs:SetText("EN custom prefix")
			fs:Show()			
			local eb = CreateFrame("EditBox", tName.."EditBox", _G[tName])
			eb:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
			eb:SetSize(f:GetSize())
			eb:SetMultiLine(false)
			eb:SetAutoFocus(false)
			eb:SetFontObject("ChatFontSmall")
			local function tSkuNavMMMainFrameSuffixCustomenUSEditBoxUpdateHelper(self)
				if SkuOptions.db.profile["SkuNav"].showAdvancedControls < 2 then
					_G["SkuNavMMMainFrameSuffixCustomdeDEEditBoxEditBox"]:SetText(self:GetText())
				end
				SkuNav:UpdateAutoPrefixes()
				self:ClearFocus()
				PlaySound(89)
			end
			eb:SetScript("OnEditFocusLost", function(self) 
				tSkuNavMMMainFrameSuffixCustomenUSEditBoxUpdateHelper(self)
			end)
			eb:SetScript("OnEscapePressed", function(self) 
				tSkuNavMMMainFrameSuffixCustomenUSEditBoxUpdateHelper(self)
			end)
			eb:SetScript("OnEnterPressed", function(self) 
				tSkuNavMMMainFrameSuffixCustomenUSEditBoxUpdateHelper(self)
			end)

			local tButtonObj = SkuNav:CreateButtonFrameTemplate("SkuNavMMMainFrameSuffixCustomenUSClear", tOptionsParent, "Clear", 50, 24, "TOPLEFT", _G["SkuNavMMMainFrameSuffixCustomenUSEditBox"], "TOPRIGHT", 1, 2)
			tButtonObj:SetScript("OnMouseUp", function(self, button)
				_G["SkuNavMMMainFrameSuffixCustomenUSEditBoxEditBox"]:SetText("")
				if SkuOptions.db.profile["SkuNav"].showAdvancedControls < 2 then
					_G["SkuNavMMMainFrameSuffixCustomdeDEEditBoxEditBox"]:SetText("")
				end
				SkuNav:UpdateAutoPrefixes()
				PlaySound(89)
			end)



			------------------- AutoDE
			local tName = "SkuNavMMMainFrameSuffixAutodeDEEditBox"
			local f = CreateFrame("Frame", tName, tOptionsParent, BackdropTemplateMixin and "BackdropTemplate" or nil)--, "DialogBoxFrame")
			f:SetPoint("TOPLEFT", _G["SkuNavMMMainFrameFilterEditBox"], "TOPLEFT", 0, tDeSuffixY)
			f:SetSize(286, 17)
			f:SetBackdrop({bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "", edgeSize = 2, insets = { left = 0, right = 0, top = 0, bottom = 0 },})
			f:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
			f:SetBackdropColor(0.5, 0.5, 0.5, 1)
			f:Show()
			local fs = _G[tName]:CreateFontString(tName.."Label")--, "HIGHLIGHT", "GameTooltipText")
			fs:SetTextHeight(12)
			fs:SetFontObject("ChatFontSmall")
			fs:SetPoint("TOPLEFT", _G[tName], "TOPLEFT", 0, 12)
			fs:SetText("DE name for new auto waypoints (+ number)")
			fs:Show()			
			local eb = CreateFrame("EditBox", tName.."EditBox", _G[tName])
			eb:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
			eb:SetSize(f:GetSize())
			eb:SetMultiLine(false)
			eb:SetAutoFocus(false)
			eb:SetFontObject("ChatFontSmall")
			eb:SetScript("OnEscapePressed", function(self) 
				SkuNav:UpdateAutoPrefixes()
				self:ClearFocus()
				PlaySound(89)
			end)
			eb:SetScript("OnEnterPressed", function(self) 
				SkuNav:UpdateAutoPrefixes()
				self:ClearFocus()
				PlaySound(89)
			end)
			-- CustomDE
			local tName = "SkuNavMMMainFrameSuffixCustomdeDEEditBox"
			local f = CreateFrame("Frame", tName, tOptionsParent, BackdropTemplateMixin and "BackdropTemplate" or nil)--, "DialogBoxFrame")
			f:SetPoint("TOPLEFT", _G["SkuNavMMMainFrameSuffixAutodeDEEditBox"], "TOPLEFT", 0, -33)
			f:SetSize(236, 20)
			f:SetBackdrop({bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeSize = 2, insets = { left = 0, right = 0, top = 0, bottom = 0 },})
			f:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
			f:SetBackdropColor(0.5, 0.5, 0.5, 1)
			f:Show()
			local fs = _G[tName]:CreateFontString(tName.."Label")--, "HIGHLIGHT", "GameTooltipText")
			fs:SetTextHeight(12)
			fs:SetFontObject("ChatFontSmall")
			fs:SetPoint("TOPLEFT", _G[tName], "TOPLEFT", 0, 12)
			fs:SetText("DE custom prefix")
			fs:Show()			
			local eb = CreateFrame("EditBox", tName.."EditBox", _G[tName])
			eb:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
			eb:SetSize(f:GetSize())
			eb:SetMultiLine(false)
			eb:SetAutoFocus(false)
			eb:SetFontObject("ChatFontSmall")
			local function tSkuNavMMMainFrameSuffixCustomenUSEditBoxEditBoxUpdateHelper(self)
				if SkuOptions.db.profile["SkuNav"].showAdvancedControls < 2 then
					_G["SkuNavMMMainFrameSuffixCustomenUSEditBoxEditBox"]:SetText(self:GetText())
				end
				SkuNav:UpdateAutoPrefixes()
				self:ClearFocus()
				PlaySound(89)
			end
			eb:SetScript("OnEditFocusLost", function(self) 
				tSkuNavMMMainFrameSuffixCustomenUSEditBoxEditBoxUpdateHelper(self)
			end)
			eb:SetScript("OnEscapePressed", function(self) 
				tSkuNavMMMainFrameSuffixCustomenUSEditBoxEditBoxUpdateHelper(self)
			end)
			eb:SetScript("OnEnterPressed", function(self) 
				tSkuNavMMMainFrameSuffixCustomenUSEditBoxEditBoxUpdateHelper(self)
			end)


			local tButtonObj = SkuNav:CreateButtonFrameTemplate("SkuNavMMMainFrameSuffixCustomdeDEClear", tOptionsParent, "Clear", 50, 24, "TOPLEFT", _G["SkuNavMMMainFrameSuffixCustomdeDEEditBox"], "TOPRIGHT", 1, 2)
			tButtonObj:SetScript("OnMouseUp", function(self, button)
				if SkuOptions.db.profile["SkuNav"].showAdvancedControls < 2 then
					_G["SkuNavMMMainFrameSuffixCustomenUSEditBoxEditBox"]:SetText("")
				end
				_G["SkuNavMMMainFrameSuffixCustomdeDEEditBoxEditBox"]:SetText("")
				SkuNav:UpdateAutoPrefixes()
				PlaySound(89)
			end)


			--auto update controls

				------
				--mode button
				local tButtonObj = SkuNav:CreateButtonFrameTemplate("SkuNavMMMainFrameEditMode2", tOptionsParent, (SkuNav.tWpEditMode == 1 and "Selection mode: mouse over" or "Mode: start / end"), 185, 20, "TOPLEFT", _G["SkuNavMMMainFrameSuffixCustomdeDEEditBox"], "BOTTOMLEFT", -1, -17)
				local tex = tButtonObj:CreateTexture(nil, "OVERLAY")
				tex:SetTexture("Interface\\AddOns\\SkuMapper\\SkuNav\\assets\\ui_toggle.tga")
				tex:SetSize(20, 20)
				tex:SetPoint("TOPRIGHT", tButtonObj, "TOPRIGHT", 0, 0)
				tButtonObj:SetScript("OnMouseUp", function(self, button)
					if SkuNav.tWpEditMode ~= 2 then
						SkuNav.tWpEditMode = 2
						self:SetText("Selection mode: start / end")
					else
						SkuNav.tWpEditMode = 1
						self:SetText("Selection mode: mouse over")
					end
					if SkuNav.tWpEditMode == 1 then
						_G["SkuNavMMMainFrameMouseSize"]:Show()
						_G["SkuNavMMMainFrameTrackSize"]:Hide()
					else
						_G["SkuNavMMMainFrameMouseSize"]:Hide()
						_G["SkuNavMMMainFrameTrackSize"]:Show()
					end

					PlaySound(89)
				end)
	
				local fs = _G["SkuNavMMMainFrameEditMode2"]:CreateFontString("SkuNavMMMainFrameEditMode2Label")--, "HIGHLIGHT", "GameTooltipText")
				fs:SetTextHeight(12)
				fs:SetFontObject("ChatFontSmall")
				fs:SetPoint("TOPLEFT", _G["SkuNavMMMainFrameEditMode2"], "TOPLEFT", 1, 12)
				fs:SetText("Selecting existing waypoints for manipulation")
				fs:Show()			
	

				--SkuNav.tCoverSize
				local tButtonObj = SkuNav:CreateButtonFrameTemplate("SkuNavMMMainFrameMouseSize", tOptionsParent, "Cursor size: "..SkuNav.tCoverSize, 104, 20, "TOPLEFT", _G["SkuNavMMMainFrameEditMode2"], "TOPRIGHT", 0, 0)
				local tex = tButtonObj:CreateTexture(nil, "OVERLAY")
				tex:SetTexture("Interface\\AddOns\\SkuMapper\\SkuNav\\assets\\ui_updown.tga")
				tex:SetSize(20, 20)
				tex:SetPoint("TOPRIGHT", tButtonObj, "TOPRIGHT", 0, 0)
				tButtonObj:SetScript("OnMouseDown", function(self, button)
					if button == "LeftButton" then
						SkuNav.tCoverSize = SkuNav.tCoverSize + 1
					else
						SkuNav.tCoverSize = SkuNav.tCoverSize - 1
					end
					if SkuNav.tCoverSize < 3 then
						SkuNav.tCoverSize = 0
					end
					if SkuNav.tCoverSize > 100 then
						SkuNav.tCoverSize = 100
					end
					self:SetText("Cursor size: "..SkuNav.tCoverSize)
				end)
				tButtonObj:SetScript("OnMouseWheel", function(self, delta)
					SkuNav.tCoverSize = SkuNav.tCoverSize + delta
					if SkuNav.tCoverSize < 3 then
						SkuNav.tCoverSize = 0
					end
					if SkuNav.tCoverSize > 100 then
						SkuNav.tCoverSize = 100
					end
					self:SetText("Cursor size: "..SkuNav.tCoverSize)

					PlaySound(89)
				end)
				--SkuNav.TrackSize
				local tButtonObj = SkuNav:CreateButtonFrameTemplate("SkuNavMMMainFrameTrackSize", tOptionsParent, "Steps: "..SkuNav.TrackSize, 104, 20, "TOPLEFT", _G["SkuNavMMMainFrameEditMode2"], "TOPRIGHT", 0, 0)
				local tex = tButtonObj:CreateTexture(nil, "OVERLAY")
				tex:SetTexture("Interface\\AddOns\\SkuMapper\\SkuNav\\assets\\ui_updown.tga")
				tex:SetSize(20, 20)
				tex:SetPoint("TOPRIGHT", tButtonObj, "TOPRIGHT", 0, 0)
				tButtonObj:SetScript("OnMouseDown", function(self, button)
					if button == "LeftButton" then
						SkuNav.TrackSize = SkuNav.TrackSize + 1
					else
						SkuNav.TrackSize = SkuNav.TrackSize - 1
					end
					if SkuNav.TrackSize < 1 then
						SkuNav.TrackSize = 1
					end
					if SkuNav.TrackSize > 100 then
						SkuNav.TrackSize = 100
					end
					self:SetText("Steps: "..SkuNav.TrackSize)
					C_Timer.After(0.2, function()
						SkuNav:RebuildTracks()
					end)

				end)				
				tButtonObj:SetScript("OnMouseWheel", function(self, delta)
					if IsAltKeyDown() == true then
						delta = delta * 10
					end
					SkuNav.TrackSize = SkuNav.TrackSize + delta
					
					if SkuNav.TrackSize < 1 then
						SkuNav.TrackSize = 1
					end
					if SkuNav.TrackSize > 100 then
						SkuNav.TrackSize = 100
					end
					self:SetText("Steps: "..SkuNav.TrackSize)
					C_Timer.After(0.2, function()
						SkuNav:RebuildTracks()
						PlaySound(89)
					end)
				end)

				if SkuNav.tWpEditMode == 1 then
					_G["SkuNavMMMainFrameMouseSize"]:Show()
					_G["SkuNavMMMainFrameTrackSize"]:Hide()
				else
					_G["SkuNavMMMainFrameMouseSize"]:Hide()
					_G["SkuNavMMMainFrameTrackSize"]:Show()
				end

				local tButtonObj = SkuNav:CreateButtonFrameTemplate("SkuNavMMMainFrameClearSE", tOptionsParent, "Clear selected waypoints", 289, 20, "TOPLEFT", _G["SkuNavMMMainFrameEditMode2"], "BOTTOMLEFT", 0, 0)
				tButtonObj:SetScript("OnMouseUp", function(self, button)
					local tcontintentId = select(3, SkuNav:GetAreaData(SkuNav:GetCurrentAreaId()))

					local tOldTracksa = SkuTableCopy(SkuNav.Tracks, true)
					local tOldTracksb = {}
					for x = 1, #WaypointCache do
						if WaypointCache[x] and WaypointCache[x].tackStep and WaypointCache[x].tackStep == 99999 then
							tOldTracksb[x] = true
						end
					end
					SkuNav:History_Generic("Clear selection", function(self, aOldTracksa, aOldTracksb)
						for x = 1, #WaypointCache do
							if aOldTracksb[x] == true then
								WaypointCache[x].tackStep = 99999
							else
								WaypointCache[x].tackStep = nil
							end
						end
						SkuNav.Tracks = SkuTableCopy(aOldTracksa, true)
						SkuNav:RebuildTracks()						
					end,
					tOldTracksa, tOldTracksb
					)		


					SkuNav.Tracks = {
						startid = nil,
						endids = {},
					}
					for x = 1, #WaypointCache do
						if WaypointCacheLookupPerContintent[tcontintentId][x] then
							WaypointCache[x].tackStart = nil
							WaypointCache[x].tackStep = nil
							WaypointCache[x].tackend = nil
						end
					end					
					SkuNav:RebuildTracks()
	
					PlaySound(89)
				end)
	

			local tButtonObj = SkuNav:CreateButtonFrameTemplate("SkuNavMMMainFrameUpdateTracked", tOptionsParent, "Add custom prefix to all selected auto", 289, 20, "TOPLEFT", _G["SkuNavMMMainFrameClearSE"], "BOTTOMLEFT", 0, -17)
			tButtonObj:SetScript("OnMouseUp", function(self, button)
				SkuNav:UpdateTracksNames()
				PlaySound(89)
			end)

			local fs = _G["SkuNavMMMainFrameUpdateTracked"]:CreateFontString("SkuNavMMMainFrameUpdateTrackedLabel")--, "HIGHLIGHT", "GameTooltipText")
			fs:SetTextHeight(12)
			fs:SetFontObject("ChatFontSmall")
			fs:SetPoint("TOPLEFT", _G["SkuNavMMMainFrameUpdateTracked"], "TOPLEFT", 1, 12)
			fs:SetText("Manipulate only selected 'auto' waypoints (custom)")
			fs:Show()	


			--SkuNav.TrackedLevel
			local tButtonObj = SkuNav:CreateButtonFrameTemplate("SkuNavMMMainFrameTrackLevel", tOptionsParent, "New Layer: "..SkuNav.TrackedLevels[SkuNav.TrackedLevel], 144, 20, "TOPLEFT", _G["SkuNavMMMainFrameUpdateTracked"], "BOTTOMLEFT", 0, -17)
			local tex = tButtonObj:CreateTexture(nil, "OVERLAY")
			tex:SetTexture("Interface\\AddOns\\SkuMapper\\SkuNav\\assets\\ui_updown.tga")
			tex:SetSize(20, 20)
			tex:SetPoint("TOPRIGHT", tButtonObj, "TOPRIGHT", 0, 0)
			tButtonObj:SetScript("OnMouseDown", function(self, button)
				if button == "LeftButton" then
					SkuNav.TrackedLevel = SkuNav.TrackedLevel + 1
				else
					SkuNav.TrackedLevel = SkuNav.TrackedLevel - 1
				end
				if SkuNav.TrackedLevel < -10 then
					SkuNav.TrackedLevel = -10
				end
				if SkuNav.TrackedLevel > 10 then
					SkuNav.TrackedLevel = 10
				end
				self:SetText("New Layer: "..SkuNav.TrackedLevels[SkuNav.TrackedLevel])
				self.Text:SetTextColor(1, 1, 1, 1)
				if SkuNav.TrackedLevel < -1 then
					self.Text:SetTextColor(1, 0.33, 0.33, 1)
				elseif SkuNav.TrackedLevel > -1 then
					self.Text:SetTextColor(0, 1, 0, 1)
				end

				C_Timer.After(0.2, function()
					SkuNav:RebuildTracks()
				end)
			end)						
			tButtonObj:SetScript("OnMouseWheel", function(self, delta)
				if IsAltKeyDown() == true then
					delta = delta * 10
				end
				SkuNav.TrackedLevel = SkuNav.TrackedLevel + delta
				
				if SkuNav.TrackedLevel < -10 then
					SkuNav.TrackedLevel = -10
				end
				if SkuNav.TrackedLevel > 10 then
					SkuNav.TrackedLevel = 10
				end
				self:SetText("New Layer: "..SkuNav.TrackedLevels[SkuNav.TrackedLevel])
				self.Text:SetTextColor(1, 1, 1, 1)
				if SkuNav.TrackedLevel < -1 then
					self.Text:SetTextColor(1, 0.33, 0.33, 1)
				elseif SkuNav.TrackedLevel > -1 then
					self.Text:SetTextColor(0, 1, 0, 1)
				end

				C_Timer.After(0.2, function()
					SkuNav:RebuildTracks()
					PlaySound(89)
				end)
			end)

			local fs = _G["SkuNavMMMainFrameTrackLevel"]:CreateFontString("SkuNavMMMainFrameTrackLevelLabel")--, "HIGHLIGHT", "GameTooltipText")
			fs:SetTextHeight(12)
			fs:SetFontObject("ChatFontSmall")
			fs:SetPoint("TOPLEFT", _G["SkuNavMMMainFrameTrackLevel"], "TOPLEFT", 1, 12)
			fs:SetText("Manipulate all selected waypoints (custom, creature, object)")
			fs:Show()	


			local tButtonObj = SkuNav:CreateButtonFrameTemplate("SkuNavMMMainFrameUpdateNonAuto", tOptionsParent, "Assign new layer to all selected waypoints", 289, 20, "TOPLEFT", _G["SkuNavMMMainFrameTrackLevel"], "BOTTOMLEFT", 0, 0)
			tButtonObj:SetScript("OnMouseUp", function(self, button)
				SkuNav:UpdateTracksNonAutoLevel()
				PlaySound(89)
			end)



			--poly
			local tButtonObj = SkuNav:CreateButtonFrameTemplate("SkuNavMMMainFrameWorldStart", tOptionsParent, "World Start", 100, 20, "TOPLEFT", _G["SkuNavMMMainFrameUpdateNonAuto"], "BOTTOMLEFT", 0, -10)
			tButtonObj:SetScript("OnMouseUp", function(self, button)
				StartPolyRecording(1, 1)
			end)
			local tButtonObj = SkuNav:CreateButtonFrameTemplate("SkuNavMMMainFrameFlyStart", tOptionsParent, "Fly Start", 100, 20, "TOPLEFT", _G["SkuNavMMMainFrameWorldStart"], "TOPLEFT", 0, -20)
			tButtonObj:SetScript("OnMouseUp", function(self, button)
				StartPolyRecording(2, 1)
			end)
			local tButtonObj = SkuNav:CreateButtonFrameTemplate("SkuNavMMMainFrameFactionAStart", tOptionsParent, "Alli Start", 100, 20, "TOPLEFT", _G["SkuNavMMMainFrameFlyStart"], "TOPLEFT", 0, -20)
			tButtonObj:SetScript("OnMouseUp", function(self, button)
				StartPolyRecording(3, 1)
			end)
			local tButtonObj = SkuNav:CreateButtonFrameTemplate("SkuNavMMMainFrameFactionHStart", tOptionsParent, "Horde Start", 100, 20, "TOPLEFT", _G["SkuNavMMMainFrameFactionAStart"], "TOPLEFT", 0, -20)
			tButtonObj:SetScript("OnMouseUp", function(self, button)
				StartPolyRecording(3, 2)
			end)
			local tButtonObj = SkuNav:CreateButtonFrameTemplate("SkuNavMMMainFrameFactionAldorStart", tOptionsParent, "Aldor Start", 100, 20, "TOPLEFT", _G["SkuNavMMMainFrameFactionHStart"], "TOPLEFT", 0, -20)
			tButtonObj:SetScript("OnMouseUp", function(self, button)
				StartPolyRecording(3, 3)
			end)
			local tButtonObj = SkuNav:CreateButtonFrameTemplate("SkuNavMMMainFrameFactionScryerStart", tOptionsParent, "Scryer Start", 100, 20, "TOPLEFT", _G["SkuNavMMMainFrameFactionAldorStart"], "TOPLEFT", 0, -20)
			tButtonObj:SetScript("OnMouseUp", function(self, button)
				StartPolyRecording(3, 4)
			end)
			local tButtonObj = SkuNav:CreateButtonFrameTemplate("SkuNavMMMainFrameOthertart", tOptionsParent, "Other Start", 100, 20, "TOPLEFT", _G["SkuNavMMMainFrameFactionScryerStart"], "TOPLEFT", 0, -20)
			tButtonObj:SetScript("OnMouseUp", function(self, button)
				StartPolyRecording(4, 1)
			end)
			local tButtonObj = SkuNav:CreateButtonFrameTemplate("SkuNavMMMainFrameEnd", tOptionsParent, "End", 100, 20, "TOPLEFT", _G["SkuNavMMMainFrameOthertart"], "TOPLEFT", 0, -20)
			tButtonObj:SetScript("OnMouseUp", function(self, button)
				if SkuNavRecordingPoly > 0 then
					if #SkuDB.Polygons.data[SkuNavRecordingPolyFor].nodes > 0 then
						print("recording completed > saved", SkuDB.Polygons.eTypes[SkuNavRecordingPoly][2][SkuNavRecordingPolySub][1], "ds:", SkuNavRecordingPolyFor)
					else
						print("recording completed, but no nodes > wasted", SkuDB.Polygons.eTypes[SkuNavRecordingPoly][2][SkuNavRecordingPolySub][1], "ds:", SkuNavRecordingPolyFor)
					end
					SkuNavRecordingPoly = 0
					SkuNavRecordingPolySub = 0
					SkuNavRecordingPolyFor = nil
				else
					print("no recording in process: ")--, SkuDB.Polygons.eTypes[SkuNavRecordingPoly][2][SkuNavRecordingPolySub][1])
				end
			end)

			local tButtonObj = SkuNav:CreateButtonFrameTemplate("SkuNavMMMainFrameWrite", tOptionsParent, "Write", 95, 20, "TOPLEFT", _G["SkuNavMMMainFrameWorldStart"], "TOPRIGHT", 0, 0)
			tButtonObj:SetScript("OnMouseUp", function(self, button)
				local tStr = tostring(SkuDB.Polygons.data)
				_G["SkuNavMMMainEditBoxEditBox"]:SetText(tStr)
			end)
			local tButtonObj = SkuNav:CreateButtonFrameTemplate("SkuNavMMMainFrameRead", tOptionsParent, "Read", 95, 20, "TOPLEFT", _G["SkuNavMMMainFrameWrite"], "TOPLEFT", 95, 0)
			tButtonObj:SetScript("OnMouseUp", function(self, button)
				local tStr = tostring(SkuDB.Polygons.data)
				local f = assert(loadstring("return {".._G["SkuNavMMMainEditBoxEditBox"]:GetText().."}"), "invalid")
				SkuDB.Polygons.data = f()
				setmetatable(SkuDB.Polygons.data, SkuPrintMT)
				_G["SkuNavMMMainEditBoxEditBox"]:ClearFocus()
			end)

			-- EditBox
			local f = CreateFrame("Frame", "SkuNavMMMainFrameEditBox", tOptionsParent, BackdropTemplateMixin and "BackdropTemplate" or nil)--, "DialogBoxFrame")
			f:SetPoint("TOPLEFT", _G["SkuNavMMMainFrameWrite"], "TOPLEFT", 2, -20)
			f:SetSize(170,140)
			--f:SetBackdrop({bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",edgeFile = "", Size = 0, insets = { left = 0, right = 0, top = 0, bottom = 0 },})
			--f:SetBackdropBorderColor(0, .44, .87, 0.5) -- darkblue
			f:SetBackdrop({bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeSize = 2, insets = { left = 0, right = 0, top = 0, bottom = 0 },})
			f:SetBackdropBorderColor(0.25, 0.25, 0.25, 1)
			f:SetBackdropColor(0.5, 0.5, 0.5, 1)
			f:Show()

			local sf = CreateFrame("ScrollFrame", "SkuNavMMMainEditBoxScrollFrame", _G["SkuNavMMMainFrameEditBox"], "UIPanelScrollFrameTemplate")
			sf:SetPoint("TOPLEFT", _G["SkuNavMMMainFrameEditBox"], "TOPLEFT", 0, 0)
			sf:SetSize(f:GetSize())
			sf:SetWidth(f:GetWidth() - 5)

			local eb = CreateFrame("EditBox", "SkuNavMMMainEditBoxEditBox", _G["SkuNavMMMainEditBoxScrollFrame"])
			eb:SetSize(f:GetSize())
			eb:SetMultiLine(true)
			eb:SetAutoFocus(false)
			eb:SetFontObject("ChatFontSmall")
			eb:SetScript("OnEscapePressed", function(self) 
				_G["SkuNavMMMainEditBoxEditBox"]:ClearFocus()
				PlaySound(89)
			end)
			eb:SetScript("OnTextSet", function(self)
				_G["SkuNavMMMainEditBoxEditBox"]:ClearFocus()
			end)
			sf:SetScrollChild(eb)

			-------
			if SkuOptions.db.profile["SkuNav"].showAdvancedControls > 0 then
				_G["SkuNavMMMainFrameSuffixAutodeDEEditBox"]:Show()
				_G["SkuNavMMMainFrameSuffixCustomdeDEEditBox"]:Show()
				_G["SkuNavMMMainFrameSuffixCustomdeDEClear"]:Show()
				_G["SkuNavMMMainFrameSuffixAutoenUSEditBox"]:Show()
				_G["SkuNavMMMainFrameSuffixCustomenUSEditBox"]:Show()
			elseif Sku.Loc == "enUS" then
				_G["SkuNavMMMainFrameSuffixAutodeDEEditBox"]:Hide()
				_G["SkuNavMMMainFrameSuffixCustomdeDEEditBox"]:Hide()
				_G["SkuNavMMMainFrameSuffixCustomdeDEClear"]:Hide()
				_G["SkuNavMMMainFrameSuffixAutoenUSEditBox"]:Show()
				_G["SkuNavMMMainFrameSuffixCustomenUSEditBox"]:Show()
			elseif Sku.Loc == "deDE" then
				_G["SkuNavMMMainFrameSuffixAutodeDEEditBox"]:Show()
				_G["SkuNavMMMainFrameSuffixCustomdeDEEditBox"]:Show()
				_G["SkuNavMMMainFrameSuffixCustomdeDEClear"]:Show()
				_G["SkuNavMMMainFrameSuffixAutoenUSEditBox"]:Hide()
				_G["SkuNavMMMainFrameSuffixCustomenUSEditBox"]:Hide()
			end
			if Sku.Loc == "deDE" and SkuOptions.db.profile["SkuNav"].showAdvancedControls < 2 then
				_G["SkuNavMMMainFrameSuffixAutoenUSEditBox"]:Hide()
				_G["SkuNavMMMainFrameSuffixCustomenUSEditBox"]:Hide()
				_G["SkuNavMMMainFrameSuffixCustomenUSClear"]:Hide()
				_G["SkuNavMMMainFrameSuffixAutoenUSEditBoxLabel"]:Hide()
				_G["SkuNavMMMainFrameSuffixCustomenUSEditBoxLabel"]:Hide()
			end
			if Sku.Loc == "enUS" and SkuOptions.db.profile["SkuNav"].showAdvancedControls < 2 then
				_G["SkuNavMMMainFrameSuffixAutodeDEEditBox"]:Hide()
				_G["SkuNavMMMainFrameSuffixCustomdeDEEditBox"]:Hide()
				_G["SkuNavMMMainFrameSuffixCustomdeDEClear"]:Hide()
				_G["SkuNavMMMainFrameSuffixAutodeDEEditBoxLabel"]:Hide()
				_G["SkuNavMMMainFrameSuffixCustomdeDEEditBoxLabel"]:Hide()
			end


				

			----------------------------map
			--map frame main container
			local scrollFrameObj = CreateFrame("ScrollFrame", "SkuNavMMMainFrameScrollFrame", _G["SkuNavMMMainFrame"], BackdropTemplateMixin and "BackdropTemplate" or nil)
			scrollFrameObj:SetFrameStrata("HIGH")
			scrollFrameObj.ScrollValue = 0
			scrollFrameObj:SetPoint("TOPLEFT", _G["SkuNavMMMainFrame"], "TOPLEFT", _G["SkuNavMMMainFrameOptionsParent"]:GetWidth() + 5, -5)
			scrollFrameObj:SetHeight(490)
			scrollFrameObj:SetWidth(490)

			-- scrollframe container object
			local contentObj = CreateFrame("Frame", "SkuNavMMMainFrameScrollFrameContent", scrollFrameObj)
			scrollFrameObj.Content = contentObj
			contentObj:SetHeight(490)
			contentObj:SetWidth(490)
			contentObj:SetPoint("TOPLEFT", scrollFrameObj, "TOPLEFT")
			contentObj:SetPoint("BOTTOMRIGHT", scrollFrameObj, "BOTTOMRIGHT")
			scrollFrameObj:SetScrollChild(contentObj)
			contentObj:Show()
			local SkuNavMMMainFrameScrollFrameContenttTime = 0
			local SkuNavMMMainFrameScrollFrameContentDraging = false
			contentObj:SetScript("OnUpdate", function(self, time)
				SkuNavMMMainFrameScrollFrameContenttTime = SkuNavMMMainFrameScrollFrameContenttTime + time
				if SkuNavMMMainFrameScrollFrameContenttTime > 0.1 then
					if SkuNavMMMainFrameScrollFrameContentDraging == true then
						local tEndX, tEndY = SkuNavMMGetCursorPositionContent2()
						tSkuNavMMPosX = tSkuNavMMPosX + ((tEndX - self.tStartMoveX) / tSkuNavMMZoom)
						tSkuNavMMPosY = tSkuNavMMPosY + ((tEndY - self.tStartMoveY) / tSkuNavMMZoom)
						SkuNavMMUpdateContent()
						self.tStartMoveX, self.tStartMoveY = SkuNavMMGetCursorPositionContent2()
					end
					SkuNavMMUpdateContent()			

					-- update coords fs
					if _G["MousePosText"] then
						--[[
						local tWy, tWx = SkuNavMMContentToWorld(SkuNavMMGetCursorPositionContent2())
						--print(tWy, tWx)
						local vec = CreateVector2D(tWx, tWy)
						local _, _, tPlayerContinentID  = SkuNav:GetAreaData(SkuNav:GetCurrentAreaId())
						local mapID = C_Map.GetBestMapForUnit("player");
						local tAreaId = SkuNav:GetCurrentAreaId()
						local tZoneName, tAreaName_lang, tContinentID, tParentAreaID, tFaction, tFlags = SkuNav:GetAreaData(tAreaId)
						local uiMapID, mapPosition = C_Map.GetMapPosFromWorldPos(tParentAreaID, vec)
						local tmapx, tmapy = mapPosition:GetXY()
						--print(tmapx, tmapy)
						local tZx, tZy = format("%.1f", tmapx * 100), format("%.1f", tmapy * 100)
						_G["MousePosText"]:SetText(tZx.." "..tZy)
]]
						--[[
						if WorldMapFrame then
							-- get cursor position
							local curX, curY = GetCursorPosition();

							local scale = WorldMapFrame:GetCanvas():GetEffectiveScale();
							curX = curX / scale;
							curY = curY / scale;
							print("c", curX, curY)

							local width = WorldMapFrame:GetCanvas():GetWidth();
							local height = WorldMapFrame:GetCanvas():GetHeight();
							local left = WorldMapFrame:GetCanvas():GetLeft();
							local top = WorldMapFrame:GetCanvas():GetTop();

							curX = (curX - left) / width * 100;
							curY = (top - curY) / height * 100;
							print("m", curX, curY)
							--local precision = "%.".. Questie.db.global.mapCoordinatePrecision .."f";

							--local worldmapCoordsText = "Cursor: "..format(precision.. " X, ".. precision .." Y  ", curX, curY);

							--worldmapCoordsText = worldmapCoordsText.."|  Player: "..format(precision.. " X , ".. precision .." Y", posX, posY);
							-- Add text to world map
							--GetMapTitleText():SetText(worldmapCoordsText)
						end
						]]

						local mapID = C_Map.GetBestMapForUnit("player");
						if mapID then
							local position = C_Map.GetPlayerMapPosition(mapID, "player");
							local posX = position.x * 100;
							local posY = position.y * 100;
							local tZx, tZy = format("%.1f", posX), format("%.1f", posY)
							_G["PlayerPosText"]:SetText(
							"Pos "..tZx.." "..tZy..
							--"\r\nZoom: "..tSkuNavMMZoom..
							"\r\nDrawn "..tCountDrawnWPs.."/"..tCountDrawnLs..
							"\r\nClear "..tCountClearedWPs.."/"..tCountClearedLs
							--"\r\nCleared Links: "..tCountClearedLs
						)


						end
					end
										
					SkuNavMMMainFrameScrollFrameContenttTime = 0
				end
				--[[
				local x, y = UnitPosition("player")
				--dprint("player", x, y)
				local tEndX, tEndY = SkuNavMMGetCursorPositionContent2()
				--dprint("cursor", tEndX, tEndY)
				local twy, twx = SkuNavMMContentToWorld(tEndX, tEndY)
				--dprint("world", twx, twy)
				local tmx, tmy = SkuNavMMWorldToContent(twx, twy)
				--dprint("map", tmx, tmy)
				]]
			end)
			contentObj:SetScript("OnMouseWheel", function(self, dir)
				tSkuNavMMZoom = tSkuNavMMZoom + ((dir / 10) * tSkuNavMMZoom)
				local tSelectedZone = _G["SkuNavMMMainFrameZoneSelect"].value
				if tSelectedZone then
					if tSelectedZone == -2 then
						if tSkuNavMMZoom < 0.5 then
							tSkuNavMMZoom = 0.5
						end
					else
						if tSkuNavMMZoom < 0.01 then
							tSkuNavMMZoom = 0.01
						end
					end
				end
					
				if tSkuNavMMZoom > 150 then
					tSkuNavMMZoom = 150
				end

				SkuNavMMUpdateContent()
			end)
			contentObj:SetScript("OnMouseDown", function(self, button)
				--dprint(button)
				if button == "LeftButton" then
					self.tStartMoveX, self.tStartMoveY = SkuNavMMGetCursorPositionContent2()
					SkuNavMMMainFrameScrollFrameContentDraging = true
					SkuMapperFocusOnPlayer = false
				end
				if button == "RightButton" then

				end
			end)
			contentObj:SetScript("OnMouseUp", function(self, button)
				--dprint(button)
				if button == "LeftButton" then
					local tEndX, tEndY = SkuNavMMGetCursorPositionContent2()
					tSkuNavMMPosX = tSkuNavMMPosX + ((tEndX - self.tStartMoveX) / tSkuNavMMZoom)
					tSkuNavMMPosY = tSkuNavMMPosY + ((tEndY - self.tStartMoveY) / tSkuNavMMZoom)
					SkuNavMMUpdateContent()
					self.tStartMoveX = nil
					self.tStartMoveY = nil
					SkuNavMMMainFrameScrollFrameContentDraging = false
				end
				if button == "RightButton" then

				end
			end)

			--map texture parent frame
			local f1 = CreateFrame("Frame", "SkuNavMMMainFrameScrollFrameMapMain", _G["SkuNavMMMainFrameScrollFrameContent"], BackdropTemplateMixin and "BackdropTemplate" or nil)
			f1:SetWidth(490)  
			f1:SetHeight(490) 
			f1:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background", edgeFile="", tile = false, tileSize = 0, edgeSize = 32, insets = { left = 5, right = 5, top = 5, bottom = 5 }})
			f1:SetBackdropColor(1, 1, 1, 1)
			f1:SetPoint("CENTER", _G["SkuNavMMMainFrameScrollFrameContent"], "CENTER", 0, 0)
			f1:EnableMouse(false)
			f1:Show()

			--tiles
			for tx = 1, 63, 1 do
				local tPrevFrame
				for ty = 1, 63, 1 do
					local f1 = CreateFrame("Frame", "SkuMapTile_"..tx.."_"..ty, _G["SkuNavMMMainFrameScrollFrameMapMain"])
					f1:SetWidth(tTileSize)
					f1:SetHeight(tTileSize)
					if ty == 1 then
						f1:SetPoint("CENTER", _G["SkuNavMMMainFrameScrollFrameMapMain"], "CENTER", tTileSize * (tx - 32) +  (tTileSize/2), tTileSize * (ty - 32) +  (tTileSize/2))
						f1.tRender = true
					else
						f1:SetPoint("BOTTOM", tPrevFrame, "TOP", 0, 0)
					end
					tPrevFrame = f1
					local tex = f1:CreateTexture(nil, "BACKGROUND")
					tex:SetTexture("Interface\\AddOns\\SkuMapper\\SkuNav\\assets\\MinimapData\\expansion01\\map"..(tx - 1).."_"..(64 - (ty - 1))..".blp")
					tex:SetAllPoints()
					f1.mapTile = tex
					--[[
					local tex = f1:CreateTexture(nil, "BORDER")
					tex:SetTexture("Interface\\AddOns\\SkuMapper\\SkuNav\\assets\\tile_border1024.tga")
					tex:SetAllPoints()
					f1.borderTex = tex
					--tex:SetColorTexture(1, 1, 1, 1)
					fs = f1:CreateFontString(f1, "OVERLAY", "GameTooltipText")
					f1.tileindext = fs
					fs:SetTextHeight(14 / tSkuNavMMZoom)
					fs:SetText((tx - 1).."_"..(64 - (ty - 1)))
					fs:SetPoint("TOPLEFT", 15, -15)
					]]
					f1:Show()
					local _, _, _, x, y = f1:GetPoint(1)
					tSkuNavMMContent[#tSkuNavMMContent + 1] = {
						obj = f1,
						x = x,
						y = y,
						w = f1:GetWidth(),
						h = f1:GetHeight(),
					}
				end
			end

			local f1 = CreateFrame("Frame","SkuNavMMMainFrameScrollFrameMapMainDraw", _G["SkuNavMMMainFrameScrollFrameMapMain"], BackdropTemplateMixin and "BackdropTemplate" or nil)
			--f1:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background", edgeFile="", tile = false, tileSize = 0, edgeSize = 32, insets = { left = 5, right = 5, top = 5, bottom = 5 }})
			--f1:SetBackdropColor(0, 0, 1, 1)
			f1:SetWidth(490)  
			f1:SetHeight(490) 
			f1:SetPoint("CENTER", _G["SkuNavMMMainFrameScrollFrameMapMain"], "CENTER", 0, 0)
			f1:SetFrameStrata("HIGH")
			f1:Show()

			----------------------------rts/wps
			--map frame main container
			local scrollFrameObj = CreateFrame("ScrollFrame", "SkuNavMMMainFrameScrollFrame1", _G["SkuNavMMMainFrame"], BackdropTemplateMixin and "BackdropTemplate" or nil)
			scrollFrameObj:SetFrameStrata("FULLSCREEN_DIALOG")
			scrollFrameObj.ScrollValue = 0
			--scrollFrameObj:SetPoint("RIGHT", _G["SkuNavMMMainFrame"], "RIGHT", -5, 0)
			scrollFrameObj:SetPoint("TOPLEFT", _G["SkuNavMMMainFrame"], "TOPLEFT", _G["SkuNavMMMainFrameOptionsParent"]:GetWidth() + 5, -5)
			scrollFrameObj:SetHeight(490)
			scrollFrameObj:SetWidth(490)

			-- scrollframe container object
			local contentObj = CreateFrame("Frame", "SkuNavMMMainFrameScrollFrameContent1", scrollFrameObj)
			scrollFrameObj.Content = contentObj
			contentObj:SetHeight(490)
			contentObj:SetWidth(490)
			contentObj:SetPoint("TOPLEFT", scrollFrameObj, "TOPLEFT")
			contentObj:SetPoint("BOTTOMRIGHT", scrollFrameObj, "BOTTOMRIGHT")
			scrollFrameObj:SetScrollChild(contentObj)
			contentObj:Show()
			local SkuNavMMMainFrameScrollFrameContenttTime1 = 0
			contentObj:SetScript("OnUpdate", function(self, time)
				if SkuOptions.db.profile[MODULE_NAME].showSkuMM == true then
					SkuNavMMMainFrameScrollFrameContenttTime1 = SkuNavMMMainFrameScrollFrameContenttTime1 + time
					if SkuNavMMMainFrameScrollFrameContentDraging == true then
						--ClearWaypointsMM()
						SkuNavDrawWaypointsMM(_G["SkuNavMMMainFrameScrollFrameContent1"])
						DrawPolyZonesMM(_G["SkuNavMMMainFrameScrollFrameContent1"])
					else
						if SkuNavMMMainFrameScrollFrameContenttTime1 > (SkuNavMmDrawTimer or 0.1) then
							if SkuMapperFocusOnPlayer == true then
								local tPx, tPy = UnitPosition("player")
								if tPx then
									tSkuNavMMPosX = tPy - tYardsPerTile
									tSkuNavMMPosY = -tPx - (tYardsPerTile * 2)
								end
							end
							--ClearWaypointsMM()
							SkuNavDrawWaypointsMM(_G["SkuNavMMMainFrameScrollFrameContent1"])
							DrawPolyZonesMM(_G["SkuNavMMMainFrameScrollFrameContent1"])


							SkuNavMMMainFrameScrollFrameContenttTime1 = 0
						end
					end
					local facing = GetPlayerFacing()
					if facing then
						RotateTexture(math.cos(-facing), -math.sin(-facing),0.5,math.sin(-facing), math.cos(-facing),0.5, 0.5, 0.5, 1, _G["playerArrow"])
					end					
				end
			end)

			--map texture parent frame
			local f1 = CreateFrame("Frame", "SkuNavMMMainFrameScrollFrameMapMain1", _G["SkuNavMMMainFrameScrollFrameContent1"], BackdropTemplateMixin and "BackdropTemplate" or nil)
			f1:SetWidth(490)  
			f1:SetHeight(490) 
			f1:SetPoint("CENTER", _G["SkuNavMMMainFrameScrollFrameContent1"], "CENTER", 0, 0)
			f1:EnableMouse(false)
			f1:Show()

			local f1 = CreateFrame("Frame","SkuNavMMMainFrameScrollFrameMapMainDraw1", _G["SkuNavMMMainFrameScrollFrameMapMain1"], BackdropTemplateMixin and "BackdropTemplate" or nil)
			f1:SetWidth(490)  
			f1:SetHeight(490) 
			f1:SetPoint("CENTER", _G["SkuNavMMMainFrameScrollFrameMapMain1"], "CENTER", 0, 0)
			f1:SetFrameStrata("TOOLTIP")
			f1:Show()

			local tex = f1:CreateTexture("playerArrow", "BACKGROUND")
			tex:SetTexture("Interface\\AddOns\\SkuMapper\\SkuNav\\assets\\player_arrow.tga")
			tex:SetSize(30,30)
			tex:SetPoint("CENTER", _G["SkuNavMMMainFrameScrollFrameMapMainDraw1"], "CENTER", 0, 0)--_G["playerArrow"]
		end

		local tObjs = {
			"SkuNavMMMainFrameEditBox",
			"SkuNavMMMainFrameWorldStart",
			"SkuNavMMMainFrameFlyStart",
			"SkuNavMMMainFrameFactionAStart",
			"SkuNavMMMainFrameFactionHStart",
			"SkuNavMMMainFrameFactionAldorStart",
			"SkuNavMMMainFrameFactionScryerStart",
			"SkuNavMMMainFrameOthertart",
			"SkuNavMMMainFrameEnd",
			"SkuNavMMMainFrameWrite",
			"SkuNavMMMainFrameRead",
		}
		for _, v in pairs(tObjs) do
			if _G[v] then
				if SkuOptions.db.profile["SkuNav"].showAdvancedControls < 3 then
					_G[v]:Hide()
				else
					_G[v]:Show()
				end
			end
		end

		if not _G["SkuNavMMMainFrame"]:IsShown() then
			_G["SkuNavMMMainFrame"]:Show()
			_G["SkuNavMMMainFrameOptionsParent"]:Show()
		end

		if not SkuWaypointWidgetRepoMM then
			SkuWaypointWidgetRepoMM = CreateTexturePool(_G["SkuNavMMMainFrameScrollFrameMapMainDraw1"], "ARTWORK")
		end
		if not SkuWaypointLineRepoMM then
			SkuWaypointLineRepoMM = CreateTexturePool(_G["SkuNavMMMainFrameScrollFrameMapMainDraw1"], "ARTWORK")
		end

		--restore mm visual from saved vars
		if SkuOptions.db.profile[MODULE_NAME].SkuNavMMMainIsCollapsed == true then
			_G["SkuNavMMMainFrameOptionsParent"]:SetWidth(0)
			_G["SkuNavMMMainFrameOptionsParent"]:Hide()
			_G["SkuNavMMMainFrameScrollFrame"]:SetPoint("TOPLEFT", _G["SkuNavMMMainFrame"], "TOPLEFT", _G["SkuNavMMMainFrameOptionsParent"]:GetWidth() + 5, -5)
			_G["SkuNavMMMainFrameScrollFrame1"]:SetPoint("TOPLEFT", _G["SkuNavMMMainFrame"], "TOPLEFT", _G["SkuNavMMMainFrameOptionsParent"]:GetWidth() + 5, -5)

		else
			_G["SkuNavMMMainFrameOptionsParent"]:SetWidth(300)
			_G["SkuNavMMMainFrameOptionsParent"]:Show()
			_G["SkuNavMMMainFrameScrollFrame"]:SetPoint("TOPLEFT", _G["SkuNavMMMainFrame"], "TOPLEFT", _G["SkuNavMMMainFrameOptionsParent"]:GetWidth() + 5, -5)
			_G["SkuNavMMMainFrameScrollFrame1"]:SetPoint("TOPLEFT", _G["SkuNavMMMainFrame"], "TOPLEFT", _G["SkuNavMMMainFrameOptionsParent"]:GetWidth() + 5, -5)
		end

		_G["SkuNavMMMainFrame"]:ClearAllPoints()
		_G["SkuNavMMMainFrame"]:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", SkuOptions.db.profile[MODULE_NAME].SkuNavMMMainPosX - _G["SkuNavMMMainFrameOptionsParent"]:GetWidth(), SkuOptions.db.profile[MODULE_NAME].SkuNavMMMainPosY)
		_G["SkuNavMMMainFrame"]:SetWidth(SkuOptions.db.profile[MODULE_NAME].SkuNavMMMainWidth )--+ _G["SkuNavMMMainFrameOptionsParent"]:GetWidth())
		_G["SkuNavMMMainFrame"]:SetHeight(SkuOptions.db.profile[MODULE_NAME].SkuNavMMMainHeight)

		_G["SkuNavMMMainFrameScrollFrame"]:SetWidth(_G["SkuNavMMMainFrame"]:GetWidth() - _G["SkuNavMMMainFrameOptionsParent"]:GetWidth() - 10)
		_G["SkuNavMMMainFrameScrollFrame"]:SetHeight(_G["SkuNavMMMainFrame"]:GetHeight() - 10)
		_G["SkuNavMMMainFrameScrollFrame1"]:SetWidth(_G["SkuNavMMMainFrame"]:GetWidth() - _G["SkuNavMMMainFrameOptionsParent"]:GetWidth() - 10)
		_G["SkuNavMMMainFrameScrollFrame1"]:SetHeight(_G["SkuNavMMMainFrame"]:GetHeight() - 10)

		_G["SkuNavMMMainFrameScrollFrameContent"]:SetWidth(_G["SkuNavMMMainFrame"]:GetWidth() - _G["SkuNavMMMainFrameOptionsParent"]:GetWidth() - 10)
		_G["SkuNavMMMainFrameScrollFrameContent"]:SetHeight(_G["SkuNavMMMainFrame"]:GetHeight() - 10)
		_G["SkuNavMMMainFrameScrollFrameContent1"]:SetWidth(_G["SkuNavMMMainFrame"]:GetWidth() - _G["SkuNavMMMainFrameOptionsParent"]:GetWidth() - 10)
		_G["SkuNavMMMainFrameScrollFrameContent1"]:SetHeight(_G["SkuNavMMMainFrame"]:GetHeight() - 10)

		SkuNav:UpdateAutoPrefixes()
	else
		if _G["SkuNavMMMainFrame"] then
			_G["SkuNavMMMainFrame"]:Hide()
			_G["SkuNavMMMainFrameOptionsParent"]:Hide()
		end
	end
end