--[[----------------------------------------------------------------------------
  Sku Pixel Bridge (PROTOTYPE)  --  "Morse with pixels"

  Goal: get the text Sku speaks OUT of the sandboxed WoW client to an external
  companion program that can hand it to a real screen reader (NVDA/JAWS) using
  the user's own voice/settings. WoW addons cannot load DLLs, open sockets, or
  write files in real time -- the only real-time channel out of the sandbox is
  the SCREEN. So we encode each spoken line as a row of solid-colour cells and
  an external screen-capture reader (sku_pixel_reader.ahk) decodes them.

  This is NOT OCR: there are no glyphs to recognise. Each cell is a flat colour
  whose R/G channels carry one byte (two 4-bit nibbles). Reading a cell is exact
  arithmetic, not shape guessing.

  Prior art that shaped this: the maintainer's AutoHotkey "WoW Login Tool" reads
  WoW's login UI with PixelGetColor and matches colours with +/-2 tolerance at
  default gamma. We space our 16 levels 17 apart, so +/-8 drift is absorbed.

  Toggle in game:  /skupixel on | off | test | calib
  Default: OFF, resets to OFF every load (prototype).
------------------------------------------------------------------------------]]

SkuPixelBridge = SkuPixelBridge or {}
local PB = SkuPixelBridge

------------------------------------------------------------------- layout config
PB.CELL_PX      = 16   -- physical pixel size of each square cell
PB.MAX_BYTES    = 64   -- max UTF-8 payload bytes per frame (longer = truncated)
PB.X_OFFSET_PX  = 160  -- shift the whole row right off the bottom-left corner:
                       -- WoW draws a solid element there (covers the marker).
                       -- The data cells proved x>=48 along the bottom is clear.
-- Cell layout (index -> meaning), single row along the BOTTOM edge, shifted
-- right by X_OFFSET_PX. The marker is TWO magenta cells so the reader can (a)
-- find it by scanning for a >=~24px magenta run (rejects stray magenta scene
-- pixels) and (b) measure the on-screen cell width from the block:
--   0,1          MARKER   two pure-magenta cells (255,0,255)
--   2            SEQ      R = seq*17 (0..15)  -> changes => new message
--   3            LEN      one byte (R hi / G lo nibble)
--   4 .. 4+LEN-1 PAYLOAD  UTF-8 bytes, one per cell
--   4+LEN        CHECKSUM sum(payload) mod 256, one byte
PB.enabled  = false
PB.seq      = 0
PB.cells    = nil      -- array of Texture objects
PB.frame    = nil
PB.lastText = nil

------------------------------------------------------------------- helpers
-- one byte -> two nibble colour channels (0,17,34,...255); blue stays 0 so the
-- magenta marker (blue=255) is never confused with a data cell.
local function ByteToRGB(b)
	local hi = math.floor(b / 16)      -- 0..15
	local lo = b % 16                  -- 0..15
	return (hi * 17) / 255, (lo * 17) / 255, 0
end

-- clip a UTF-8 string to at most n bytes without splitting a multibyte char
local function ClipUtf8(s, n)
	if #s <= n then return s end
	local i = n
	-- back up while we're on a UTF-8 continuation byte (0x80..0xBF)
	while i > 0 do
		local c = string.byte(s, i)
		if c < 0x80 or c >= 0xC0 then break end
		i = i - 1
	end
	-- if the char that starts at i would run past n, drop it too
	local c = string.byte(s, i)
	if c and c >= 0xC0 then
		local len = (c >= 0xF0 and 4) or (c >= 0xE0 and 3) or (c >= 0xC0 and 2) or 1
		if i + len - 1 > n then i = i - 1 end
	end
	return string.sub(s, 1, i)
end

------------------------------------------------------------------- geometry
-- One cell = CELL_PX *physical render pixels*, expressed in UI units. Uses the
-- same maths as WeakAuras' AlignToPixel: physicalPx = uiUnits * physW / virtW,
-- so uiUnits-per-cell = CELL_PX * virtW / physW. GetEffectiveScale alone is
-- wrong on HiDPI (physical != virtual). Width and height scale separately.
function PB:CellUiSize()
	local physW, physH = GetPhysicalScreenSize()
	local virtW, virtH = GetScreenWidth(), GetScreenHeight()
	local vW = self.CELL_PX * virtW / physW
	local vH = self.CELL_PX * virtH / physH
	return vW, vH
end

function PB:GeometryString()
	local physW, physH = GetPhysicalScreenSize()
	local vW, vH = self:CellUiSize()
	return string.format("phys=%dx%d  virt=%.0fx%.0f  cell=%dpx -> uiW=%.2f uiH=%.2f",
		physW, physH, GetScreenWidth(), GetScreenHeight(), self.CELL_PX, vW, vH)
end

------------------------------------------------------------------- frame build
function PB:Build()
	if self.frame then return end
	local vW, vH = self:CellUiSize()
	local offUI = self.X_OFFSET_PX * (GetScreenWidth() / select(1, GetPhysicalScreenSize()))
	local total = 4 + self.MAX_BYTES + 1

	local f = CreateFrame("Frame", "SkuPixelBridgeFrame", UIParent)
	f:SetFrameStrata("TOOLTIP")
	f:SetFrameLevel(2000)
	f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", offUI, 0)
	f:SetSize(total * vW, vH)

	self.cells = {}
	for i = 0, total - 1 do
		local t = f:CreateTexture(nil, "OVERLAY")
		t:SetSize(vW, vH)
		t:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", offUI + i * vW, 0)
		t:SetColorTexture(0, 0, 0, 1)
		self.cells[i] = t
	end
	self.frame = f
	-- rebuild geometry if the display scale/size changes (keeps cells == CELL_PX)
	f:RegisterEvent("DISPLAY_SIZE_CHANGED")
	f:RegisterEvent("UI_SCALE_CHANGED")
	f:SetScript("OnEvent", function() self:Rescale() end)
end

function PB:Rescale()
	if not self.frame then return end
	local vW, vH = self:CellUiSize()
	local offUI = self.X_OFFSET_PX * (GetScreenWidth() / select(1, GetPhysicalScreenSize()))
	local total = #self.cells + 1
	self.frame:SetSize(total * vW, vH)
	for i = 0, #self.cells do
		local t = self.cells[i]
		t:SetSize(vW, vH)
		t:ClearAllPoints()
		t:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", offUI + i * vW, 0)
	end
end

------------------------------------------------------------------- encode a line
local function SetCellByte(t, b)
	local r, g, bl = ByteToRGB(b)
	t:SetColorTexture(r, g, bl, 1)
end

function PB:Send(text)
	if not self.enabled or not self.frame then return end
	if type(text) ~= "string" or text == "" then return end
	if text:sub(1, 6) == "sound-" then return end   -- audio-token, not readable text
	if text == self.lastText then return end
	self.lastText = text

	local payload = ClipUtf8(text, self.MAX_BYTES)
	local len = #payload
	local sum = 0
	for i = 1, len do sum = (sum + string.byte(payload, i)) % 256 end

	self.seq = (self.seq + 1) % 16

	-- marker (2x magenta), seq (R=seq*17), len, payload, checksum
	self.cells[0]:SetColorTexture(1, 0, 1, 1)
	self.cells[1]:SetColorTexture(1, 0, 1, 1)
	self.cells[2]:SetColorTexture((self.seq * 17) / 255, 0, 0, 1)
	SetCellByte(self.cells[3], len)
	for i = 1, len do
		SetCellByte(self.cells[3 + i], string.byte(payload, i))
	end
	SetCellByte(self.cells[4 + len], sum)
	-- blank the tail so a shorter message can't leave stale bytes (cosmetic;
	-- the reader stops at 4+len+1 anyway)
	for i = 4 + len + 1, #self.cells do
		self.cells[i]:SetColorTexture(0, 0, 0, 1)
	end
end

------------------------------------------------------------------- hook Sku voice
function PB:InstallHook()
	if self.hooked or not (SkuOptions and SkuOptions.Voice) then return end
	hooksecurefunc(SkuOptions.Voice, "OutputStringBTtts", function(_, aString)
		if type(aString) == "string" then PB:Send(aString) end
	end)
	hooksecurefunc(SkuOptions.Voice, "OutputString", function(_, aString)
		if type(aString) == "string" then PB:Send(aString) end
	end)
	self.hooked = true
end

------------------------------------------------------------------- enable/disable
function PB:Enable()
	self:Build()
	self:InstallHook()
	self.enabled = true
	self.frame:Show()
end

function PB:Disable()
	self.enabled = false
	if self.frame then self.frame:Hide() end
end

------------------------------------------------------------------- calibration ramp
-- fills cells 2.. with byte values 0,17,34,... so the companion can measure the
-- exact on-screen value of each of the 16 levels (accounts for gamma once).
function PB:Calib()
	self:Build()
	self.enabled = true
	self.frame:Show()
	self.cells[0]:SetColorTexture(1, 0, 1, 1)
	self.cells[1]:SetColorTexture(1, 0, 1, 1)
	self.cells[2]:SetColorTexture(0, 0, 0, 1)
	for lvl = 0, 15 do
		local t = self.cells[3 + lvl]
		if t then t:SetColorTexture((lvl * 17) / 255, (lvl * 17) / 255, 0, 1) end
	end
	self.lastText = "\1calib"
end

------------------------------------------------------------------- slash command
SLASH_SKUPIXEL1 = "/skupixel"
SlashCmdList["SKUPIXEL"] = function(msg)
	msg = (msg or ""):lower():gsub("%s+", "")
	if msg == "off" then
		PB:Disable(); print("Sku pixel bridge: OFF")
	elseif msg == "test" then
		PB:Enable(); PB.lastText = nil; PB:Send("Sku pixel bridge test one two three")
		print("Sku pixel bridge: TEST sent. "..PB:GeometryString())
	elseif msg == "calib" then
		PB:Calib(); print("Sku pixel bridge: CALIB ramp shown. "..PB:GeometryString())
	elseif msg == "geo" then
		PB:Enable(); print("Sku pixel bridge: "..PB:GeometryString())
	else
		PB:Enable(); print("Sku pixel bridge: ON. "..PB:GeometryString())
	end
end
