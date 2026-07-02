--[[--------------------------------------------------------------------------
SkuCombatTest  --  in-combat secure-action probe (standalone, dependency-free)

Purpose: verify, in the live client, two things we cannot settle from source:
  1) Bag use in combat via slot-positional secure macros ( /use <bag> <slot> ).
     One pre-built SecureActionButton per bag slot; the macro targets the SLOT
     POSITION, so it uses whatever item sits there, no re-pointing needed in
     combat. We expect: usable items (potion/healthstone/food/bandage) fire in
     combat; equippable items get refused (same wall sighted players hit).
  2) Trade in combat: whether InitiateTrade / loading items / AcceptTrade are
     blocked by combat or hardware-gated, and whether a secure
     /click TradeFrameTradeButton drives the accept.

Everything is logged to chat AND to SkuCombatTestDB.log (read back out of game).
No protected setup happens in combat (buttons + bindings are built out of
combat); only the keypress that triggers them happens in combat.

Slash:  /sct help
----------------------------------------------------------------------------]]

local ADDON = "SkuCombatTest"

--===========================================================================
-- logging
--===========================================================================
local seq = 0
local lastUIError, lastUIErrorTime = nil, 0
local function clog(msg)
	SkuCombatTestDB = SkuCombatTestDB or {}
	SkuCombatTestDB.log = SkuCombatTestDB.log or {}
	seq = seq + 1
	local t = date("%H:%M:%S")
	table.insert(SkuCombatTestDB.log, {seq = seq, t = t, msg = msg})
	while #SkuCombatTestDB.log > 500 do table.remove(SkuCombatTestDB.log, 1) end
	-- ring buffer only: NO chat print (chat spam is read aloud by the screen reader
	-- and masks the real TTS behaviour). Review with /sct log or out-of-game.
end

local function inCombat()
	return InCombatLockdown and InCombatLockdown() and true or false
end

-- remember armed keys so they survive /reload (override bindings do not)
local function recordArm(rec)
	SkuCombatTestDB = SkuCombatTestDB or {}
	SkuCombatTestDB.arms = SkuCombatTestDB.arms or {}
	for i = #SkuCombatTestDB.arms, 1, -1 do
		if SkuCombatTestDB.arms[i].key == rec.key then table.remove(SkuCombatTestDB.arms, i) end
	end
	table.insert(SkuCombatTestDB.arms, rec)
end

--===========================================================================
-- shared override-binding owner
--===========================================================================
local bindOwner = CreateFrame("Frame", "SkuCombatTestBindOwner", UIParent)

--===========================================================================
-- bag slot secure buttons (one per bag/slot, macro = /use bag slot)
--===========================================================================
local function bagButtonName(bag, slot)
	return "SkuCombatTestBag" .. bag .. "_" .. slot
end

-- build / refresh the whole grid. MUST be out of combat (creates + mutates
-- secure frames). Bag *contents* may change freely in combat afterwards; the
-- slot-positional macro does not care.
local function ensureButtons()
	if inCombat() then
		clog("ensureButtons skipped: in combat (cannot build secure frames)")
		return false
	end
	local made = 0
	for bag = 0, 4 do
		local n = (GetContainerNumSlots and GetContainerNumSlots(bag)) or 0
		for slot = 1, n do
			local name = bagButtonName(bag, slot)
			local b = _G[name]
			if not b then
				b = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
				b:RegisterForClicks("AnyDown")
				b:SetSize(1, 1)
				b:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -200, -200) -- offscreen
				b:SetScript("PostClick", function(self)
					-- runs AFTER the secure macro; insecure, may read state + log
					local _, before = GetContainerItemInfo(self.bag, self.slot)
					local combat = inCombat()
					C_Timer.After(0.6, function()
						local _, after = GetContainerItemInfo(self.bag, self.slot)
						local cdStarted = false
						if GetContainerItemCooldown then
							local s, d = GetContainerItemCooldown(self.bag, self.slot)
							cdStarted = (s or 0) > 0 and (d or 0) > 0
						end
						clog(("USE bag %d slot %d: countBefore=%s countAfter=%s cdStarted=%s combat=%s")
							:format(self.bag, self.slot, tostring(before), tostring(after),
								tostring(cdStarted), tostring(combat)))
					end)
				end)
				made = made + 1
			end
			b.bag, b.slot = bag, slot
			b:SetAttribute("type", "macro")
			b:SetAttribute("macrotext", "/use " .. bag .. " " .. slot)
			b:Show()
		end
	end
	clog("buttons ready (new this build: " .. made .. ")")
	return true
end

--===========================================================================
-- arming keys to slots (override-binding click -> secure button)
--===========================================================================
local function armBag(key, bag, slot)
	if not key or not bag or not slot then
		clog("usage: /sct arm <KEY> <bag> <slot>   e.g. /sct arm SHIFT-Z 0 5")
		return
	end
	if inCombat() then
		clog("arm failed: in combat (cannot set bindings); arm BEFORE the fight")
		return
	end
	ensureButtons()
	local name = bagButtonName(bag, slot)
	if not _G[name] then
		clog(("arm failed: no button for bag %d slot %d (does that slot exist?)"):format(bag, slot))
		return
	end
	SetOverrideBindingClick(bindOwner, true, key:upper(), name)
	recordArm({key = key:upper(), kind = "bag", bag = bag, slot = slot})
	local _, _, _, _, _, _, link = GetContainerItemInfo(bag, slot)
	local nm = link and (GetItemInfo(link) or link) or "(empty)"
	clog(("armed %s -> bag %d slot %d  [%s]  (survives /reload)"):format(key:upper(), bag, slot, nm))
end

--===========================================================================
-- LAYER-1 CAPTURE PROTOTYPE (OnKeyDown/OnChar nav that works in combat)
--===========================================================================
-- A non-secure EnableKeyboard frame captures nav keys (works in combat, unlike
-- SetOverrideBinding). Arrows move a dummy cursor + announce via TTS. Letters flow
-- through OnChar (logged, to learn umlaut/layout behaviour). ENTER is PROPAGATED so
-- a persistent secure override-binding (armed out of combat) still fires a protected
-- action in combat -> proves insecure nav + secure action coexist while capturing.
local DUMMY = {"Apfel", "Banane", "Birne", "Oeltrank", "Übung", "Ähre", "Zwiebel"}
local capActive = false
local capIdx = 1

local capFrame = CreateFrame("Frame", "SkuCombatTestCapture", UIParent)
capFrame:EnableKeyboard(false)
capFrame:SetPropagateKeyboardInput(true)

local NAV = { UP = true, DOWN = true, LEFT = true, RIGHT = true,
	PAGEUP = true, PAGEDOWN = true, HOME = true, END = true, BACKSPACE = true }

local function capAnnounce()
	local item = DUMMY[capIdx]
	clog(("cap cursor %d/%d: %s"):format(capIdx, #DUMMY, tostring(item)))
	if SkuOptions and SkuOptions.Voice and SkuOptions.Voice.OutputString then
		pcall(function() SkuOptions.Voice:OutputString(item, true, true, 0.2) end)
	end
end

-- persistent secure ENTER button (armed out of combat, fires protected action in combat)
local capEnterBtn
local function ensureCapEnterButton()
	if inCombat() then return end
	if not capEnterBtn then
		capEnterBtn = CreateFrame("Button", "SkuCombatTestCapEnter", UIParent, "SecureActionButtonTemplate")
		capEnterBtn:RegisterForClicks("AnyDown")
		capEnterBtn:SetSize(1, 1)
		capEnterBtn:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -200, -280)
		capEnterBtn:SetAttribute("type", "macro")
		capEnterBtn:SetAttribute("macrotext", "/use 0 1")
		capEnterBtn:SetScript("PostClick", function()
			clog("cap ENTER secure action fired (/use 0 1) combat=" .. tostring(inCombat()))
		end)
		capEnterBtn:Show()
	end
end

local function capArm()
	if inCombat() then clog("caparm failed: in combat (arm out of combat)"); return end
	ensureCapEnterButton()
	SetOverrideBindingClick(bindOwner, true, "ENTER", "SkuCombatTestCapEnter")
	recordArm({key = "ENTER", kind = "capenter"})
	clog("cap ENTER armed -> secure /use 0 1 (put a usable item in backpack slot 1)")
end

local function capToggle(on)
	capActive = on and true or false
	capFrame:EnableKeyboard(capActive)
	clog(("capture %s combat=%s  (arrows=nav, letters=OnChar, ENTER=secure use, ESC=close)")
		:format(capActive and "ON" or "OFF", tostring(inCombat())))
	if capActive then capAnnounce() end
end

-- SetPropagateKeyboardInput is protected in combat (API doc HasRestrictions=true).
-- Guard it: only change propagation out of combat. In combat the frame keeps its
-- last (consume) state -> clean modal reading, no ADDON_ACTION_BLOCKED spam.
local function capSetProp(self, v)
	if not inCombat() then self:SetPropagateKeyboardInput(v) end
end

capFrame:SetScript("OnKeyDown", function(self, key)
	if not capActive then
		capSetProp(self, true)
		return
	end
	if key == "ENTER" then
		capSetProp(self, true)  -- (out of combat) let the persistent secure ENTER binding fire
		clog("cap ENTER, combat=" .. tostring(inCombat()))
		return
	end
	if key == "ESCAPE" then
		capSetProp(self, false)
		capToggle(false)
		return
	end
	if NAV[key] then
		capSetProp(self, false)  -- consume nav keys (out of combat)
		if key == "DOWN" or key == "RIGHT" or key == "PAGEDOWN" then
			capIdx = capIdx % #DUMMY + 1
		elseif key == "UP" or key == "LEFT" or key == "PAGEUP" then
			capIdx = (capIdx - 2) % #DUMMY + 1
		elseif key == "HOME" then capIdx = 1
		elseif key == "END" then capIdx = #DUMMY end
		capAnnounce()
		return
	end
	-- non-nav
	capSetProp(self, true)
end)

capFrame:SetScript("OnChar", function(self, ch)
	if not capActive then return end
	clog("cap OnChar char=" .. tostring(ch) .. " combat=" .. tostring(inCombat()))
	local lc = tostring(ch):lower()
	if lc == "" then return end
	for i = 1, #DUMMY do
		local idx = (capIdx + i - 1) % #DUMMY + 1
		if DUMMY[idx]:lower():sub(1, #lc) == lc then
			capIdx = idx
			capAnnounce()
			return
		end
	end
end)

--===========================================================================
-- SECURE CURSOR PROTOTYPE (navigate bag slots + left/right click in COMBAT)
--===========================================================================
-- A SecureHandlerClickTemplate owns a cursor over a pre-loaded list of occupied
-- bag slots. UP/DOWN move the cursor INSIDE A SECURE SNIPPET (works in combat) and
-- rewrite the use-button's macrotext to "/use <bag> <slot>" for the focused slot --
-- the one mutation allowed in combat only from secure context. An insecure
-- OnAttributeChanged speaks the focused item (TTS). RIGHT = use (secure /use),
-- LEFT = pickup (insecure PickupContainerItem). Proves navigate+act in combat.
local cursorOwner = CreateFrame("Frame", "SkuCTCursorOwner", UIParent)
local slotList = {}
local insecureIndex = 1
local cursorFramesReady = false

local function cursorEnsureFrames()
	if cursorFramesReady then return true end
	if inCombat() then return false end

	local use = CreateFrame("Button", "SkuCTUse", UIParent, "SecureActionButtonTemplate")
	use:RegisterForClicks("AnyDown")
	use:SetSize(1, 1); use:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -200, -360)
	use:SetAttribute("type", "macro")
	use:SetAttribute("macrotext", "")
	use:SetScript("PreClick", function(self)
		local e = slotList[insecureIndex]
		if e then
			local _, c = GetContainerItemInfo(e.bag, e.slot)
			self.b, self.s, self.before = e.bag, e.slot, c
		end
	end)
	use:SetScript("PostClick", function(self)
		local combat, b, s, before = inCombat(), self.b, self.s, self.before
		C_Timer.After(0.6, function()
			local _, after = GetContainerItemInfo(b or 0, s or 1)
			clog(("cursor USE bag %s slot %s: before=%s after=%s combat=%s")
				:format(tostring(b), tostring(s), tostring(before), tostring(after), tostring(combat)))
		end)
	end)
	use:Show()

	local pick = CreateFrame("Button", "SkuCTPickup", UIParent)
	pick:RegisterForClicks("AnyDown")
	pick:SetScript("OnClick", function()
		local e = slotList[insecureIndex]
		if e and PickupContainerItem then
			PickupContainerItem(e.bag, e.slot)
			clog(("cursor PICKUP bag %d slot %d combat=%s"):format(e.bag, e.slot, tostring(inCombat())))
			C_Timer.After(0.3, function() if ClearCursor then ClearCursor() end end)
		end
	end)

	local nav = CreateFrame("Button", "SkuCTNav", UIParent, "SecureHandlerClickTemplate")
	nav:SetFrameRef("use", use)
	nav:SetAttribute("_onclick", [=[
		local count = self:GetAttribute("count") or 0
		if count == 0 then return end
		local idx = self:GetAttribute("index") or 1
		if button == "NEXT" then
			idx = idx % count + 1
		elseif button == "PREV" then
			idx = (idx - 2) % count + 1
		end
		self:SetAttribute("index", idx)
		local bs = self:GetAttribute("s" .. idx)
		local use = self:GetFrameRef("use")
		if use and bs then
			use:SetAttribute("macrotext", "/use " .. bs)
		end
		self:SetAttribute("announce", idx)
	]=])
	nav:SetScript("OnAttributeChanged", function(self, name, value)
		if name == "announce" then
			insecureIndex = value
			local e = slotList[value]
			if e then
				clog(("cursor -> %d/%d bag %d slot %d: %s combat=%s")
					:format(value, #slotList, e.bag, e.slot, e.name, tostring(inCombat())))
				if SkuOptions and SkuOptions.Voice and SkuOptions.Voice.OutputString then
					pcall(function() SkuOptions.Voice:OutputString(e.name, true, true, 0.2) end)
				end
			end
		end
	end)

	cursorFramesReady = true
	return true
end

local function cursorBuild()
	if inCombat() then clog("cursor build skipped: in combat"); return end
	if not cursorEnsureFrames() then return end
	wipe(slotList)
	local nav = _G["SkuCTNav"]
	local n = 0
	for bag = 0, 4 do
		local num = GetContainerNumSlots(bag) or 0
		for slot = 1, num do
			local _, count, _, _, _, _, link = GetContainerItemInfo(bag, slot)
			if link then
				n = n + 1
				slotList[n] = { bag = bag, slot = slot, name = (GetItemInfo(link) or link), count = count }
				nav:SetAttribute("s" .. n, bag .. " " .. slot)
			end
		end
	end
	nav:SetAttribute("count", n)
	nav:SetAttribute("index", 1)
	insecureIndex = 1
	-- prime the use macrotext for slot 1 (out of combat) so first use works pre-nav
	if slotList[1] then
		_G["SkuCTUse"]:SetAttribute("macrotext", "/use " .. slotList[1].bag .. " " .. slotList[1].slot)
	end
	clog("cursor built: " .. n .. " occupied slots")
end

local function cursorOn()
	if inCombat() then clog("cursor on: do OUT of combat (it binds keys)"); return end
	cursorBuild()
	SetOverrideBindingClick(cursorOwner, true, "UP", "SkuCTNav", "PREV")
	SetOverrideBindingClick(cursorOwner, true, "DOWN", "SkuCTNav", "NEXT")
	SetOverrideBindingClick(cursorOwner, true, "RIGHT", "SkuCTUse")
	SetOverrideBindingClick(cursorOwner, true, "LEFT", "SkuCTPickup")
	clog("cursor ON: UP/DOWN move, RIGHT=use, LEFT=pickup (arrows hijacked until 'cursor off')")
	local e = slotList[1]
	if e then
		clog("cursor start 1/" .. #slotList .. ": " .. e.name)
		if SkuOptions and SkuOptions.Voice and SkuOptions.Voice.OutputString then
			pcall(function() SkuOptions.Voice:OutputString(e.name, true, true, 0.2) end)
		end
	end
end

local function cursorOff()
	if inCombat() then clog("cursor off: do OUT of combat (it clears bindings)"); return end
	ClearOverrideBindings(cursorOwner)
	clog("cursor OFF: arrows restored")
end

--===========================================================================
-- LINCHPIN PROBE: ONE key drives BOTH insecure nav AND a secure snippet
--===========================================================================
-- The make-or-break for "full lockstep, menu-driven" combat bags (option 1).
-- Question: in combat, can a SINGLE nav key fire (a) the menu's normal INSECURE
-- OnKeyDown (move cursor + speak) AND (b) a SECURE override-binding click whose
-- snippet advances its own cursor and re-arms the Enter button -- so a following
-- ENTER fires the freshly-armed "/use <bag> <slot>" for the focused slot?
--
-- Model under test: the keyboard frame PROPAGATES input (SetPropagateKeyboardInput
-- is set true ONCE, out of combat, and NEVER toggled in combat -- it is protected
-- in combat). With propagation on, each key first runs OnKeyDown (insecure), then,
-- because it was not consumed, also fires its override binding (secure snippet).
--
-- Read the result with /sct log: per DOWN press in combat we want to see BOTH a
--   "LINCH [insecure] OnKeyDown DOWN -> k/n ..."   and a
--   "LINCH [secure] cursor -> k/n armed /use ..."  line, with MATCHING k (lockstep).
-- If only the [insecure] line appears, propagation does not carry the key to the
-- binding in combat -> option 1 must use secure-master / insecure-follow instead.
-- Then ENTER should fire the secure use (count drops / cooldown), logged below.
--
-- Run with the real Sku menu CLOSED so this frame owns the keyboard cleanly.
local linchOwner = CreateFrame("Frame", "SkuCTLinchOwner", UIParent)
local linchSlots = {}
local linchInsecureIdx = 1
local linchFramesReady = false

local linchFrame = CreateFrame("Frame", "SkuCTLinchFrame", UIParent)
linchFrame:EnableKeyboard(false)

local function linchEnsureFrames()
	if linchFramesReady then return true end
	if inCombat() then return false end

	-- secure Enter button: fires "/use <bag> <slot>"; macrotext armed by the snippet
	local en = CreateFrame("Button", "SkuCTLinchEnter", UIParent, "SecureActionButtonTemplate")
	en:RegisterForClicks("AnyDown")
	en:SetSize(1, 1); en:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -200, -420)
	en:SetAttribute("type", "macro")
	en:SetAttribute("macrotext", "")
	en:SetScript("PreClick", function(self)
		local e = linchSlots[linchInsecureIdx]
		if e then
			local _, c = GetContainerItemInfo(e.bag, e.slot)
			self.b, self.s, self.before = e.bag, e.slot, c
		end
	end)
	en:SetScript("PostClick", function(self)
		local combat, b, s, before = inCombat(), self.b, self.s, self.before
		C_Timer.After(0.6, function()
			local _, after = GetContainerItemInfo(b or 0, s or 1)
			clog(("LINCH ENTER secure use bag %s slot %s: before=%s after=%s combat=%s")
				:format(tostring(b), tostring(s), tostring(before), tostring(after), tostring(combat)))
		end)
	end)
	en:Show()

	-- secure nav handler: advances its OWN index + re-arms the Enter macrotext IN COMBAT
	local nav = CreateFrame("Button", "SkuCTLinchNav", UIParent, "SecureHandlerClickTemplate")
	nav:SetFrameRef("en", en)
	nav:SetAttribute("_onclick", [=[
		local count = self:GetAttribute("count") or 0
		if count == 0 then return end
		local idx = self:GetAttribute("index") or 1
		if button == "NEXT" then
			idx = idx % count + 1
		elseif button == "PREV" then
			idx = (idx - 2) % count + 1
		end
		self:SetAttribute("index", idx)
		local bs = self:GetAttribute("s" .. idx)
		local en = self:GetFrameRef("en")
		if en and bs then
			en:SetAttribute("macrotext", "/use " .. bs)
		end
		self:SetAttribute("announce", idx)
	]=])
	nav:SetScript("OnAttributeChanged", function(self, name, value)
		if name == "announce" then
			local e = linchSlots[value]
			clog(("LINCH [secure] cursor -> %s/%d  armed /use %s  combat=%s")
				:format(tostring(value), #linchSlots, e and (e.bag .. " " .. e.slot) or "?", tostring(inCombat())))
		end
	end)

	linchFramesReady = true
	return true
end

local function linchBuild()
	if inCombat() then clog("linch build skipped: in combat"); return end
	if not linchEnsureFrames() then return end
	wipe(linchSlots)
	local nav = _G["SkuCTLinchNav"]
	local n = 0
	for bag = 0, 4 do
		local num = GetContainerNumSlots(bag) or 0
		for slot = 1, num do
			local _, count, _, _, _, _, link = GetContainerItemInfo(bag, slot)
			if link then
				n = n + 1
				linchSlots[n] = { bag = bag, slot = slot, name = (GetItemInfo(link) or link), count = count }
				nav:SetAttribute("s" .. n, bag .. " " .. slot)
			end
		end
	end
	nav:SetAttribute("count", n)
	nav:SetAttribute("index", 1)
	linchInsecureIdx = 1
	if linchSlots[1] then
		_G["SkuCTLinchEnter"]:SetAttribute("macrotext", "/use " .. linchSlots[1].bag .. " " .. linchSlots[1].slot)
	end
	clog("linch built: " .. n .. " occupied slots")
end

-- forward declaration so OnKeyDown can call it before it is assigned below
local linchOff

-- INSECURE nav: log + move a mirror index + speak. CRUCIAL: do NOT consume the key
-- and do NOT touch SetPropagateKeyboardInput here (propagation was set true out of
-- combat, in linchOn). So the key flows on to its override binding -> secure snippet.
linchFrame:SetScript("OnKeyDown", function(self, key)
	if key == "UP" or key == "DOWN" then
		local count = #linchSlots
		if count > 0 then
			if key == "DOWN" then
				linchInsecureIdx = linchInsecureIdx % count + 1
			else
				linchInsecureIdx = (linchInsecureIdx - 2) % count + 1
			end
		end
		local e = linchSlots[linchInsecureIdx]
		clog(("LINCH [insecure] OnKeyDown %s -> %d/%d %s  combat=%s")
			:format(key, linchInsecureIdx, count, e and e.name or "?", tostring(inCombat())))
		if e and SkuOptions and SkuOptions.Voice and SkuOptions.Voice.OutputString then
			pcall(function() SkuOptions.Voice:OutputString(e.name, true, true, 0.2) end)
		end
	elseif key == "ENTER" then
		clog("LINCH [insecure] OnKeyDown ENTER seen combat=" .. tostring(inCombat()))
	elseif key == "ESCAPE" then
		clog("LINCH [insecure] OnKeyDown ESCAPE")
		if linchOff and not inCombat() then linchOff() end
	end
end)

linchOff = function()
	if inCombat() then clog("linch off: do OUT of combat (it clears bindings)"); return end
	linchFrame:EnableKeyboard(false)
	ClearOverrideBindings(linchOwner)
	if SkuCombatTestDB then SkuCombatTestDB.linchOn = false end
	clog("LINCH OFF: keyboard capture + bindings cleared")
end

local function linchOn()
	if inCombat() then clog("linch on: do OUT of combat (it binds keys + sets propagation)"); return end
	linchBuild()
	linchFrame:EnableKeyboard(true)
	linchFrame:SetPropagateKeyboardInput(true) -- ONCE, out of combat; never toggled in combat
	SetOverrideBindingClick(linchOwner, true, "UP", "SkuCTLinchNav", "PREV")
	SetOverrideBindingClick(linchOwner, true, "DOWN", "SkuCTLinchNav", "NEXT")
	SetOverrideBindingClick(linchOwner, true, "ENTER", "SkuCTLinchEnter")
	if SkuCombatTestDB then SkuCombatTestDB.linchOn = true end
	clog("LINCH ON: UP/DOWN = insecure nav + secure snippet (SAME key); ENTER = secure /use.")
	clog("  -> enter combat, press DOWN a few times, then ENTER. Read with /sct log 20.")
	clog("  -> want BOTH [insecure] and [secure] lines per DOWN, matching index = lockstep OK.")
end

--===========================================================================
-- trade probes
--===========================================================================
local tradeBtn
local function ensureTradeButton()
	if inCombat() then return end
	if not tradeBtn then
		tradeBtn = CreateFrame("Button", "SkuCombatTestTradeAccept", UIParent, "SecureActionButtonTemplate")
		tradeBtn:RegisterForClicks("AnyDown")
		tradeBtn:SetSize(1, 1)
		tradeBtn:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -200, -240)
		tradeBtn:SetAttribute("type", "macro")
		tradeBtn:SetAttribute("macrotext", "/click TradeFrameTradeButton")
		tradeBtn:SetScript("PostClick", function()
			clog("trade-accept secure /click fired, combat=" .. tostring(inCombat()))
		end)
		tradeBtn:Show()
	end
end

local function tradeArm(key)
	if not key then clog("usage: /sct tradearm <KEY>"); return end
	if inCombat() then clog("tradearm failed: in combat"); return end
	ensureTradeButton()
	SetOverrideBindingClick(bindOwner, true, key:upper(), "SkuCombatTestTradeAccept")
	recordArm({key = key:upper(), kind = "trade"})
	clog("trade-accept armed to " .. key:upper() .. " (secure /click TradeFrameTradeButton, survives /reload)")
end

-- re-apply saved arms after a reload (out of combat)
local function reapplyArms()
	if inCombat() then return end
	local arms = SkuCombatTestDB and SkuCombatTestDB.arms
	if not arms or #arms == 0 then return end
	for _, a in ipairs(arms) do
		if a.kind == "bag" then
			local name = bagButtonName(a.bag, a.slot)
			if _G[name] then SetOverrideBindingClick(bindOwner, true, a.key, name) end
		elseif a.kind == "trade" then
			ensureTradeButton()
			SetOverrideBindingClick(bindOwner, true, a.key, "SkuCombatTestTradeAccept")
		elseif a.kind == "capenter" then
			ensureCapEnterButton()
			SetOverrideBindingClick(bindOwner, true, a.key, "SkuCombatTestCapEnter")
		end
	end
	clog("re-applied " .. #arms .. " saved key binding(s) from last session")
end

-- INSECURE direct calls: run these IN COMBAT to see if they are blocked.
-- If protected, ADDON_ACTION_BLOCKED/FORBIDDEN fires and we log the func name.
local function tradeInit()
	local exists = UnitExists("target")
	local isPlayer = UnitIsPlayer and UnitIsPlayer("target") and true or false
	local name = exists and (UnitName("target") or "?") or "(no target)"
	-- distance index 2 = trade range. CheckInteractDistance is protected in combat,
	-- so skip it there (it would just log a harmless ADDON_ACTION_BLOCKED).
	local inRange
	if inCombat() then
		inRange = "n/a(combat)"
	else
		inRange = CheckInteractDistance and CheckInteractDistance("target", 2) and true or false
	end
	clog(("tradeinit: target=%s isPlayer=%s tradeRange=%s combat=%s")
		:format(tostring(name), tostring(isPlayer), tostring(inRange), tostring(inCombat())))
	if not exists or not isPlayer then
		clog("  -> need a PLAYER targeted in trade range; not calling InitiateTrade")
		return
	end
	clog("  -> calling InitiateTrade('target')  (watch for TRADE_SHOW)")
	if InitiateTrade then InitiateTrade("target") end
end

local function tradePut(bag, slot)
	if not bag or not slot then clog("usage: /sct tradeput <bag> <slot>"); return end
	clog(("PickupContainerItem(%d,%d) + ClickTradeButton(1) combat=%s"):format(bag, slot, tostring(inCombat())))
	if PickupContainerItem then PickupContainerItem(bag, slot) end
	if ClickTradeButton then ClickTradeButton(1) end
end

--===========================================================================
-- listing / reporting
--===========================================================================
local function listSlots()
	local any = false
	for bag = 0, 4 do
		local n = (GetContainerNumSlots and GetContainerNumSlots(bag)) or 0
		for slot = 1, n do
			local _, count, _, _, _, _, link = GetContainerItemInfo(bag, slot)
			if link then
				any = true
				local nm = GetItemInfo(link) or link
				clog(("bag %d slot %d: %s x%s"):format(bag, slot, nm, tostring(count or 1)))
			end
		end
	end
	if not any then clog("no items found in bags 0-4") end
end

local function showLog(nLines)
	local db = SkuCombatTestDB
	if not db or not db.log or #db.log == 0 then print("|cff66ccff[SCT]|r log empty"); return end
	nLines = nLines or 15
	local startIdx = math.max(1, #db.log - nLines + 1)
	for i = startIdx, #db.log do
		print(("|cff66ccff[SCT]|r #%d %s %s"):format(db.log[i].seq, db.log[i].t, db.log[i].msg))
	end
end

--===========================================================================
-- slash
--===========================================================================
SLASH_SCT1 = "/sct"
SlashCmdList["SCT"] = function(msg)
	local args = {}
	for w in (msg or ""):gmatch("%S+") do args[#args + 1] = w end
	local cmd = (args[1] or "help"):lower()

	if cmd == "slots" then
		listSlots()
	elseif cmd == "arm" then
		armBag(args[2], tonumber(args[3]), tonumber(args[4]))
	elseif cmd == "clear" then
		if inCombat() then clog("cannot clear bindings in combat") else
			ClearOverrideBindings(bindOwner)
			if SkuCombatTestDB then SkuCombatTestDB.arms = {} end
			clog("all SCT key bindings cleared (saved arms wiped too)")
		end
	elseif cmd == "rebuild" then
		ensureButtons()
	elseif cmd == "tradearm" then
		tradeArm(args[2])
	elseif cmd == "tradeinit" then
		tradeInit()
	elseif cmd == "tradeput" then
		tradePut(tonumber(args[2]), tonumber(args[3]))
	elseif cmd == "pickup" then
		-- LEFT-click probe: insecure PickupContainerItem (expect: works in combat)
		local b, s = tonumber(args[2]), tonumber(args[3])
		clog(("PickupContainerItem(%s,%s) combat=%s"):format(tostring(b), tostring(s), tostring(inCombat())))
		if b and s and PickupContainerItem then PickupContainerItem(b, s) end
		C_Timer.After(0.3, function()
			local kind = GetCursorInfo and GetCursorInfo()
			clog("  after pickup: cursor=" .. tostring(kind) .. " (nil = pickup did NOT happen)")
			if ClearCursor then ClearCursor() end
		end)
	elseif cmd == "usec" then
		-- RIGHT-click/use probe: insecure UseContainerItem (the open question)
		local b, s = tonumber(args[2]), tonumber(args[3])
		local _, before = GetContainerItemInfo(b or 0, s or 1)
		clog(("UseContainerItem(%s,%s) combat=%s countBefore=%s"):format(tostring(b), tostring(s), tostring(inCombat()), tostring(before)))
		if b and s and UseContainerItem then UseContainerItem(b, s) end
		C_Timer.After(0.6, function()
			local _, after = GetContainerItemInfo(b or 0, s or 1)
			clog("  after usec: countAfter=" .. tostring(after) .. " (drop or block = use did NOT fire insecurely)")
		end)
	elseif cmd == "clickarm" then
		-- migrate-fully probe: a secure button that does the SAME context-sensitive
		-- /click ContainerFrameNItemM <L/R>Button the menu uses. Tests whether that
		-- works in combat (needs the Blizzard bag frame rendered).  out of combat only.
		if inCombat() then clog("clickarm: arm out of combat"); return end
		local key = args[2]
		local b, s = tonumber(args[3]), tonumber(args[4])
		local lr = (args[5] or "R"):upper()
		if not key or not b or not s then clog("usage: /sct clickarm <KEY> <bag> <slot> <L|R>"); return end
		local fn = "ContainerFrame" .. (b + 1) .. "Item" .. (((GetContainerNumSlots(b) or 0) - s + 1))
		local btn = _G["SkuCombatTestClick"]
		if not btn then
			btn = CreateFrame("Button", "SkuCombatTestClick", UIParent, "SecureActionButtonTemplate")
			btn:RegisterForClicks("AnyDown")
			btn:SetSize(1, 1)
			btn:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", -200, -320)
			btn:SetScript("PreClick", function(self)
				local _, c = GetContainerItemInfo(self.bag or 0, self.slot or 1)
				self.cbefore = c
			end)
			btn:SetScript("PostClick", function(self)
				local combat = inCombat()
				C_Timer.After(0.6, function()
					local _, after = GetContainerItemInfo(self.bag or 0, self.slot or 1)
					local err = ""
					if lastUIError and (GetTime() - lastUIErrorTime) < 1.5 then
						err = "  uiError=[" .. tostring(lastUIError) .. "]"
					end
					clog(("clickslot %s: countBefore=%s countAfter=%s combat=%s%s")
						:format(tostring(self.fn), tostring(self.cbefore), tostring(after), tostring(combat), err))
				end)
			end)
			btn:Show()
		end
		btn.bag, btn.slot = b, s
		btn.fn = fn
		btn:SetAttribute("type", "macro")
		btn:SetAttribute("macrotext", "/click " .. fn .. " " .. (lr == "L" and "LeftButton" or "RightButton"))
		SetOverrideBindingClick(bindOwner, true, key:upper(), "SkuCombatTestClick")
		clog(("clickarm %s -> /click %s %sButton  (open your bags, then test in combat)")
			:format(key:upper(), fn, (lr == "L" and "Left" or "Right")))
	elseif cmd == "cursor" then
		local sub = (args[2] or ""):lower()
		if sub == "on" then cursorOn()
		elseif sub == "off" then cursorOff()
		elseif sub == "build" then cursorBuild()
		else clog("usage: /sct cursor on|off|build") end
	elseif cmd == "linch" then
		local sub = (args[2] or ""):lower()
		if sub == "on" then linchOn()
		elseif sub == "off" then linchOff()
		elseif sub == "build" then linchBuild()
		else clog("usage: /sct linch on|off|build") end
	elseif cmd == "caparm" then
		capArm()
	elseif cmd == "cap" then
		local sub = (args[2] or ""):lower()
		if sub == "on" then capToggle(true)
		elseif sub == "off" then capToggle(false)
		else clog("usage: /sct cap on|off") end
	elseif cmd == "log" then
		showLog(tonumber(args[2]) or 15)
	elseif cmd == "clearlog" then
		SkuCombatTestDB = SkuCombatTestDB or {}
		SkuCombatTestDB.log = {}
		clog("log cleared")
	elseif cmd == "combat" then
		clog("InCombatLockdown=" .. tostring(inCombat()))
	else
		print("|cff66ccff[SCT]|r commands:")
		print("  /sct slots                 - list items in bags 0-4 (pick coordinates)")
		print("  /sct arm <KEY> <bag> <slot>- bind KEY to /use that slot (do OUT of combat)")
		print("  /sct clear                 - clear all SCT key bindings")
		print("  /sct rebuild               - rebuild the slot button grid (out of combat)")
		print("  /sct tradearm <KEY>        - bind KEY to secure /click TradeFrameTradeButton")
		print("  /sct tradeinit             - InitiateTrade('target') [run IN combat to test]")
		print("  /sct tradeput <bag> <slot> - pickup+drop item into trade slot 1 [IN combat]")
		print("  /sct pickup <bag> <slot>   - insecure PickupContainerItem probe (left-click)")
		print("  /sct usec <bag> <slot>     - insecure UseContainerItem probe (right-click/use)")
		print("  /sct clickarm <KEY> <bag> <slot> <L|R> - secure /click bag button probe (context-sensitive)")
		print("  /sct cursor on|off|build   - SECURE CURSOR: UP/DOWN move, RIGHT=use, LEFT=pickup (works in combat)")
		print("  /sct linch on|off|build    - LINCHPIN: one key drives insecure nav + secure snippet (option-1 test)")
		print("  /sct caparm                - arm ENTER->secure /use 0 1 (out of combat, once)")
		print("  /sct cap on|off            - toggle Layer-1 OnKeyDown capture (works in combat)")
		print("  /sct combat                - report combat lockdown state")
		print("  /sct log [n]               - show last n log lines")
		print("  /sct clearlog              - empty the log")
	end
end

--===========================================================================
-- events
--===========================================================================
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("ADDON_ACTION_BLOCKED")
f:RegisterEvent("ADDON_ACTION_FORBIDDEN")
f:RegisterEvent("TRADE_SHOW")
f:RegisterEvent("TRADE_CLOSED")
f:RegisterEvent("TRADE_ACCEPT_UPDATE")
f:RegisterEvent("TRADE_REQUEST_CANCEL")
f:RegisterEvent("UI_INFO_MESSAGE")
f:RegisterEvent("UI_ERROR_MESSAGE")
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:SetScript("OnEvent", function(self, event, a1, a2)
	if event == "PLAYER_LOGIN" then
		ensureButtons()
		reapplyArms()
		if SkuCombatTestDB and SkuCombatTestDB.linchOn then
			C_Timer.After(1, function() if not inCombat() then linchOn() end end)
		end
		clog("loaded. Type /sct for commands.")
	elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
		clog(event .. "  addon=" .. tostring(a1) .. "  func=" .. tostring(a2))
	elseif event == "TRADE_SHOW" then
		clog("TRADE_SHOW (trade window opened) combat=" .. tostring(inCombat()))
	elseif event == "TRADE_CLOSED" then
		clog("TRADE_CLOSED (trade ended: completed OR cancelled)")
	elseif event == "TRADE_ACCEPT_UPDATE" then
		-- a1 = your accept flag, a2 = partner accept flag (1/0)
		clog(("TRADE_ACCEPT_UPDATE you=%s partner=%s combat=%s")
			:format(tostring(a1), tostring(a2), tostring(inCombat())))
	elseif event == "UI_ERROR_MESSAGE" then
		lastUIError = a2 or a1
		lastUIErrorTime = (GetTime and GetTime()) or 0
	elseif event == "TRADE_REQUEST_CANCEL" then
		clog("TRADE_REQUEST_CANCEL (trade cancelled)")
	elseif event == "UI_INFO_MESSAGE" then
		if a2 and tostring(a2):lower():find("trade") then
			clog("UI_INFO_MESSAGE: " .. tostring(a2))
		end
	elseif event == "PLAYER_REGEN_DISABLED" then
		clog("== combat START ==")
	elseif event == "PLAYER_REGEN_ENABLED" then
		clog("== combat END ==")
	end
end)
