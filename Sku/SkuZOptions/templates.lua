local _G = _G

SkuOptions = SkuOptions or LibStub("AceAddon-3.0"):NewAddon("SkuOptions", "AceConsole-3.0", "AceEvent-3.0")
local L = Sku.L

local MENU_MENU = 1
local MENU_DROPDOWN = 2
local MENU_DROPDOWN_MULTI = 3

SkuOptions.MenuMT = {
	__add = function(thisTable, newTable)

		-- Widget-safe deep copy, consolidated to SkuUtil (W6-B #3).
		local seen = {}
		local tTable = SkuUtil.TableCopy(newTable, true, seen)
		table.insert(thisTable, tTable)
		return thisTable
	end,
	__tostring = function(thisTable)
		local tStr = ""
		local function tf(ttable, tTab)
			for k, v in pairs(ttable) do
				if k ~= "parent" and v ~= "parent" and k ~= "prev" and v ~= "prev" and k ~= "next" and v ~= "next"  then
					if type(v) ~= "userdata" and k ~= "frame" and k ~= 0  then
						if type(v) == 'table' then
							print(tTab..k..": tab")
							tf(v, tTab.."  ")
						elseif type(v) == "function" then
							--dprint(tTab..k..": function")
						elseif type(v) == "boolean" then
							print(tTab..k..": "..tostring(v))
						else
							print(tTab..k..": "..v)
						end
					end
				end
			end
		end
		tf(thisTable, "")
	end,
	}

local tPrevErrorUtterance
local tCurrentErrorUtteranceTimerHandle
SkuGenericMenuItem = {
	name = "SkuGenericMenuItem name",
	type = MENU_MENU,
	parent = nil,
	children = {},
	prev = nil,
	next = nil,
	isSelect = false,
	isMultiselect = false,
	selectTarget = nil,
	dynamic = false,
	sorting = false,
	OnUpdate = function(self, aKey)
		C_Timer.After(0.01, function()

			dprint("++ OnUpdate generic")
			local tCurrentItemNumber
			local tCurrentItemName = self.name
			local tParent = self.parent

			if not self.parent then
				return
			end
			if not self.parent.children then
				return
			end

			local tMenuItems = self.parent.children
			for x = 1, #tMenuItems do
				if tMenuItems[x].name == tCurrentItemName then
					tCurrentItemNumber = x
				end
			end

			tCurrentItemNumber = tCurrentItemNumber or 1
			
			self.parent.children = {}
			SkuCore:CheckFrames(nil, true)						
			tParent:BuildChildren(self.parent)

			tParent:OnSelect()
			if self.parent.children[tCurrentItemNumber] then
				SkuOptions.currentMenuPosition = self.parent.children[tCurrentItemNumber]
			elseif self.parent.children[tCurrentItemNumber - 1] then
				SkuOptions.currentMenuPosition = self.parent.children[tCurrentItemNumber - 1]
			else
				SkuOptions.currentMenuPosition = self.parent.children[1]
			end

			-- Defensiver Nil-Schutz: in Edge-Cases (z. B. wenn ein
			-- vorheriger Lua-Error in einer parallelen Pipeline den
			-- Menü-State beschädigt hat) kann self.parent.children
			-- leer sein → currentMenuPosition wird nil. Statt hier
			-- mit "attempt to index nil"-Folgefehler weiter zu crashen,
			-- lassen wir den OnUpdate-Schritt still aussetzen — der
			-- nächste Tastendruck/Refresh reanimiert den State sauber.
			if SkuOptions.currentMenuPosition and SkuOptions.currentMenuPosition.OnEnter then
				SkuOptions.currentMenuPosition:OnEnter()
			end

			if SkuOptions.currentMenuPosition
				and SkuOptions.TTS.MainFrame:IsVisible() ~= true then
				SkuOptions:VocalizeCurrentMenuName()
			end
		end)
	end,
	OnKey = function(self, aKey)
		if SkuOptions.bindingMode == true then
			return
		end
		dprint("OnKey", aKey, SkuOptions.bindingMode)
		SkuOptions.currentMenuPosition:OnLeave(self, value, aValue)

		local tNewMenuItem = nil
		local tMenuItems = nil
		if self.parent.name then
			tMenuItems = self.parent.children
		else
			tMenuItems = self.parent
		end
		
		if SkuOptions.MenuAccessKeysChars[aKey] then
			for x= 1, #tMenuItems do
				if not tNewMenuItem then
					if string.lower(string.sub(tMenuItems[x].name, 1, 1)) == string.lower(aKey) then
						tNewMenuItem = tMenuItems[x]
					end
				end
			end
		elseif SkuOptions.MenuAccessKeysNumbers[aKey] then
			if not tNewMenuItem then
				aKey = tonumber(aKey)
				if tMenuItems[aKey] then
					tNewMenuItem = tMenuItems[aKey]
				end
			end
		end
		if tNewMenuItem then
			SkuOptions.currentMenuPosition = tNewMenuItem
		end
		SkuOptions.currentMenuPosition:OnEnter()
	end,
	BuildChildren = function(self)
		--dprint("BuildChildren generic", self.name)
	end,
	-- Stable node identity (W6-B #14). `id` is an OPTIONAL per-instance string set
	-- on STRUCTURAL ANCHOR nodes (never on this shared template — it would copy to
	-- every node). It gives menu navigation a language-independent handle so paths
	-- and re-pins no longer depend on the localized display `name` or on counting
	-- fixed .parent hops.
	--
	-- FindAncestorById walks up the .parent chain (including self) to the nearest
	-- node whose id == aId; returns it or nil. Use this to re-pin the cursor after
	-- an action instead of `self.parent.parent.parent`, which breaks whenever the
	-- menu depth changes.
	FindAncestorById = function(self, aId)
		local tNode = self
		while tNode do
			if tNode.id == aId then
				return tNode
			end
			tNode = tNode.parent
		end
		return nil
	end,
	-- Option-2 "live data" support for node-based menus.
	--
	-- A level whose children grow/change while the menu sits open (e.g.
	-- nearby routes streaming in) can set `volatileChildren = true` on the
	-- PARENT node. Then, on each navigation step within that level, we
	-- silently rebuild the level's children in place — no speech, no
	-- re-anchor (we never go through CheckFrames/SlashFunc) — and re-resolve
	-- the cursor by name. The user hears nothing extra; the NEXT arrow press
	-- simply reflects fresh data. Throttled so fast scrolling can't thrash.
	RebuildVolatileSiblings = function(self)
		local tParent = self.parent
		if not tParent or not tParent.children or not tParent.BuildChildren then
			return self
		end

		-- throttle: at most ~2x/second per level
		local tNow = GetTime()
		if tParent._lastVolatileRebuild and (tNow - tParent._lastVolatileRebuild) < 0.5 then
			return self
		end
		tParent._lastVolatileRebuild = tNow

		local tCurrentName = self.name
		local tCurrentIndex = 1
		for x = 1, #tParent.children do
			if tParent.children[x].name == tCurrentName then
				tCurrentIndex = x
			end
		end

		-- swap out the children for a freshly built list
		tParent.children = {}
		tParent:BuildChildren(tParent)
		dprint("volatile refresh", tParent.name, "->", #tParent.children, "items")

		-- re-resolve the cursor: prefer the same entry by name, else fall
		-- back to the nearest surviving index, else the first entry.
		for x = 1, #tParent.children do
			if tParent.children[x].name == tCurrentName then
				return tParent.children[x]
			end
		end
		return tParent.children[tCurrentIndex] or tParent.children[tCurrentIndex - 1] or tParent.children[1] or self
	end,
	MaybeRebuildVolatile = function(self)
		if not (self.parent and self.parent.volatileChildren == true) then
			return self
		end
		local ok, res = pcall(function() return self:RebuildVolatileSiblings() end)
		if ok and res then
			return res
		end
		return self
	end,
	OnPrev = function(self)
		--dprint("OnPrev generic", self.name)
		SkuOptions.currentMenuPosition:OnLeave(self, value, aValue)

		local tNode = self:MaybeRebuildVolatile()
		if tNode.prev then
			SkuOptions.currentMenuPosition = tNode.prev
		else
			PlaySound(681)
			-- Flag the boundary so the key handler suppresses its per-step nav
			-- click (811) — only the boundary sound should play at a list edge.
			SkuOptions.tBoundaryHitThisKey = true
			SkuOptions.currentMenuPosition = tNode
		end
		SkuOptions.currentMenuPosition:OnEnter()
	end,
	OnNext = function(self)
		--dprint("OnNext generic", self.name)
		SkuOptions.currentMenuPosition:OnLeave(self, value, aValue)

		local tNode = self:MaybeRebuildVolatile()
		if tNode.next then
			SkuOptions.currentMenuPosition = tNode.next
		else
			PlaySound(681)
			-- Flag the boundary so the key handler suppresses its per-step nav
			-- click (811) — only the boundary sound should play at a list edge.
			SkuOptions.tBoundaryHitThisKey = true
			SkuOptions.currentMenuPosition = tNode
		end
		SkuOptions.currentMenuPosition:OnEnter()
	end,
	OnFirst = function(self)
		--dprint("OnFirst generic", self.name)
		SkuOptions.currentMenuPosition:OnLeave(self, value, aValue)

		local tNode = self:MaybeRebuildVolatile()
		if tNode.parent then
			-- At the root level the parent IS the sibling list (the SkuOptions.Menu
			-- array, no .children field); everywhere else siblings live in
			-- parent.children. Resolve the list once so HOME works at both levels.
			local tSiblings = tNode.parent.children or tNode.parent
			SkuOptions.currentMenuPosition = tSiblings[1]
		end
		SkuOptions.currentMenuPosition:OnEnter()
	end,
	OnLast = function(self)
		--dprint("OnLast generic", self.name)
		SkuOptions.currentMenuPosition:OnLeave(self, value, aValue)

		local tNode = self:MaybeRebuildVolatile()
		if tNode.parent then
			-- Same as OnFirst: at root the sibling list is parent itself. Previously
			-- the root branch used parent[1], so END jumped to the FIRST entry instead
			-- of the last -- now it correctly lands on the last sibling.
			local tSiblings = tNode.parent.children or tNode.parent
			SkuOptions.currentMenuPosition = tSiblings[#tSiblings]
		end
		SkuOptions.currentMenuPosition:OnEnter()
	end,
	OnBack = function(self)
		--dprint("OnBack generic", self.name, self.parent.name)
		SkuOptions.currentMenuPosition:OnLeave(self, value, aValue)

		if self.parent.name then
			SkuOptions.currentMenuPosition = self.parent
		else
			-- W7: at the root level (parent is the root array, no name) Left no longer
			-- CLOSES the menu — it lands on the first top-level entry so the user stays
			-- in the root list (e.g. stepping Left out of Lokal returns to root instead
			-- of closing everything). Closing is still done via Escape / the open key.
			if SkuOptions.Menu and SkuOptions.Menu[1] then
				SkuOptions.currentMenuPosition = SkuOptions.Menu[1]
			end
		end
		SkuOptions.currentMenuPosition:OnEnter()
	end,
	OnAction = function(self, value, aValue)
		--print("OnAction generic", self.name, value.name, value, aValue)
	end,
	OnLeave = function(self, value, aValue)
		--print("OnLeave generic", self.name, value, aValue)
		if tCurrentErrorUtteranceTimerHandle then
			tCurrentErrorUtteranceTimerHandle:Cancel()
		end
	end,
	OnEnter = function(self, value, aValue)
		--print("OnEnter generic", self.name, value, aValue)

		-- Mirror the default UI: focusing a bag item clears its "new" (neu) glow,
		-- so the next bag rebuild re-sorts it out of the new-items block and drops
		-- the "New" prefix. Before the Container-API migration this was a side
		-- effect of the rendered button's OnEnter; these obj-less nodes carry
		-- (bag, slot) instead (set in the gossip->menu converter) and clear it here.
		if self.bag ~= nil and self.slot ~= nil and _G.C_NewItems
			and _G.C_NewItems.IsNewItem and _G.C_NewItems.RemoveNewItem then
			if _G.C_NewItems.IsNewItem(self.bag, self.slot) then
				pcall(_G.C_NewItems.RemoveNewItem, self.bag, self.slot)
			end
		end

		if string.find(self.name, L["error;sound"].."#") then
			for i, v in pairs(SkuCore.Errors.Sounds) do
				if self.name == v then
					C_Timer.After(1.5, function()
						if tPrevErrorUtterance then
							StopSound(tPrevErrorUtterance)
						end
						local willPlay, soundHandle = PlaySoundFile(i, SkuOptions.db.profile.SkuCore.UIErrors.ErrorSoundChannel or "Talking Head")
						if willPlay then
							tPrevErrorUtterance = soundHandle
						end
					end)
				end
			end
		elseif string.find(self.name, L["aura;sound"].."#") then
			for i, v in pairs(SkuAuras.outputs) do
				if self.name == v.friendlyName then
					SkuOptions.Voice:OutputStringBTtts(v.outputString, false, false, 0.3, true)
				end
			end
		elseif string.find(self.name, L["sound"].."#") then
			for i, v in pairs(SkuCore.RangeCheckSounds) do
				if self.name == v then
					C_Timer.After(1.5, function()
						if tPrevErrorUtterance then
							StopSound(tPrevErrorUtterance)
						end
						local willPlay, soundHandle = PlaySoundFile(i, "Talking Head")
						if willPlay then
							tPrevErrorUtterance = soundHandle
						end
					end)
				end
			end
		elseif self.errorPreviewFile then
			-- Fehlerfeedback: audition the beep / spoken clip when this leaf gets focus.
			if tCurrentErrorUtteranceTimerHandle then
				tCurrentErrorUtteranceTimerHandle:Cancel()
			end
			tCurrentErrorUtteranceTimerHandle = C_Timer.NewTimer(0.4, function()
				if tPrevErrorUtterance then
					StopSound(tPrevErrorUtterance)
				end
				local willPlay, soundHandle = PlaySoundFile(self.errorPreviewFile, SkuOptions.db.profile.SkuCore.UIErrors.ErrorSoundChannel or "Talking Head")
				if willPlay then
					tPrevErrorUtterance = soundHandle
				end
			end)
		elseif self.errorPreviewVoiceIndex ~= nil then
			-- Fehlerfeedback: audition a TTS voice (0 => the user's global voice) by
			-- speaking the error's label in it. overwrite=true so scrolling the voice
			-- list replaces the previous audition instead of piling up.
			local tText = self.errorPreviewText or "TTS"
			local tVoice = (self.errorPreviewVoiceIndex ~= 0) and self.errorPreviewVoiceIndex or nil
			if tCurrentErrorUtteranceTimerHandle then
				tCurrentErrorUtteranceTimerHandle:Cancel()
			end
			tCurrentErrorUtteranceTimerHandle = C_Timer.NewTimer(0.35, function()
				pcall(function()
					SkuOptions.Voice:OutputStringBTtts(tText, {overwrite = true, wait = false, length = 0.3, engine = 1, instant = true, voice = tVoice})
				end)
			end)
		end

		if SkuState:IsInCombat() ~= true then
			-- Stage this node's secure click payloads (left + right button). The body
			-- lives in SkuOptions:StageClickMacros (SkuZOptions/Core.lua) so the exact
			-- same staging can be re-run WITHOUT re-announcing the entry when the
			-- pending-spell state changes -- focus-time staging alone only covers
			-- "targeting starts (craft button / using the kit), THEN the target item
			-- is focused", not the equally natural reverse order.
			SkuOptions:StageClickMacros(self)
			if _G["SecureOnSkuOptionsMainOption1"] then
				-- directClickButton: for TAINT-protected buttons whose effect is a
				-- protected/hardware-gated action (e.g. the enchant CraftCreateButton
				-- -> DoCraft), the normal "/click <btn>" secure macro is routed through
				-- the chat SlashCommand parser (RunMacro -> SendText -> /click ->
				-- btn:Click()), which drops the genuine hardware event, so the action
				-- silently no-ops. Instead, bind the menu's activate key(s) DIRECTLY
				-- to the real Blizzard button while this entry is focused: a native
				-- key->button hardware event, exactly like a mouse click, no chat
				-- parser. Every other focused entry restores the key(s) to the normal
				-- secure menu button. The key is configurable (SKU_KEY_MENULEFTCLICK,
				-- default/fallback ENTER); the virtual click button stays "ENTER".
				--
				-- ZOMBIE-BINDING GUARD: only (re)arm the click-key bindings while the
				-- secure button is SHOWN (= menu visually open). OnEnter also runs
				-- AFTER a select-action that just CLOSED the menu (OnPostSelect
				-- re-focuses the selectTarget below, ~631) and from async re-pins;
				-- SetOverrideBindingClick on the then-HIDDEN button resurrected the
				-- ENTER binding right after OnHide had cleared it -- Enter kept
				-- clicking the invisible menu (and never reached chat) until the
				-- next full open/close cycle. While hidden, the button's own
				-- OnShow/OnHide exclusively own these bindings.
				if _G["SecureOnSkuOptionsMainOption1"]:IsShown() then
					local tLeftKeys = SkuOptions:SkuKeyBindsGetKeys("SKU_KEY_MENULEFTCLICK", "ENTER")
					if self.directClickButton and _G[self.directClickButton] then
						for _, tKey in ipairs(tLeftKeys) do
							pcall(SetOverrideBindingClick, _G["SecureOnSkuOptionsMainOption1"], true,
								tKey, self.directClickButton, "LeftButton")
						end
					else
						for _, tKey in ipairs(tLeftKeys) do
							pcall(SetOverrideBindingClick, _G["SecureOnSkuOptionsMainOption1"], true,
								tKey, "SecureOnSkuOptionsMainOption1", "ENTER")
						end
					end
				end
			end
			-- (The right-click button's rightMacrotext staging moved into
			-- SkuOptions:StageClickMacros above, together with the left one.)
		end
	end,
	OnSelect = function(self, aEnterFlag)
		--print("OnSelect generic", self.name, aEnterFlag, self.isSelect, self.isMultiselect, self.dynamic)
		local spellID
		local itemID
		local macroID

		local tCollectValuesFrom

		if self.selectTarget then
			spellID = self.selectTarget.spellID
			itemID = self.selectTarget.itemID
			macroID = self.selectTarget.macroID

			tCollectValuesFrom = self.selectTarget.collectValuesFrom
		end

		SkuOptions.Filterstring = ""
		SkuOptions:ApplyFilter(SkuOptions.Filterstring)

		if tCollectValuesFrom then
			self.selectTarget.collectValuesFrom = tCollectValuesFrom
		end


		if self.selectTarget then
			--dprint("   ", self.selectTarget.name)
			self.selectTarget.spellID = spellID
			self.selectTarget.itemID = itemID
			self.selectTarget.macroID = macroID
	
		end

		if string.find(self.name, L["Filter"]..";") then
			return
		end

		-- skuWpLoadingHint: the waypoint "still loading" hint carries a live
		-- percentage in its name now (SkuNav:GetWpcLoadingText), so it can no
		-- longer be recognised by a fixed string - the tag comes first, the name
		-- comparison stays for any hint built before the tag existed.
		if self.name == L["Empty;list"] or self.skuWpLoadingHint == true or self.name == L["Wegpunkte werden noch geladen"] then
			return
		end

		self:OnPostSelect(aEnterFlag)
	end,
	OnPostSelect = function(self, aEnterFlag)
		--print("++ OnPostSelect generic", self.name, self.actionOnEnter, aEnterFlag, self.isSelect, self.isMultiselect, self.dynamic)
		if self.dynamic == true then
			self.children = {}
			if self.isMultiselect == true then
				local tNewMenuEntry = SkuOptions:InjectMenuItems(self, {L["Nothing selected"]}, SkuGenericMenuItem)
				self.selectTarget = tNewMenuEntry
			end
			if self.isSelect == true then
				self.selectTarget = self
			end

			-- we need to free up the memory of the old children before we're re-building; otherwise we'll leak memory on next BuildChildren
			-- we can't do that for multi select menu items now, as we do need to collect the result from the selected sub items first
			if self.isMultiselect ~= true then
				self.children = {}
				--collectgarbage("collect")
			end

			self:BuildChildren(self)
			if self.selectTarget then
				for x = 1, #self.children do
					self.children[x].selectTarget = self.selectTarget
				end
			end		
		end
		if #self.children > 0 and (self.actionOnEnter ~= true or aEnterFlag ~= true) then
			SkuOptions.currentMenuPosition = self.children[1]
			if self.GetCurrentValue then
				local tGetCurrentValue = self:GetCurrentValue()
				for i, v in pairs(self.children) do
					if v.name == tGetCurrentValue then
						SkuOptions.currentMenuPosition = self.children[i]
					end
				end
			end			
		else
			if self.selectTarget and self.selectTarget ~= self then
				if self.selectTarget.parent.isMultiselect == true then
					if self.selectTarget.name == L["Nothing selected"] and (self.name ~= L["Small"] and self.name ~= L["Large"]) then
						self.selectTarget.name = L["Selected"]..";"..self.name
					else
						if self.name ~= L["Small"] and self.name ~= L["Large"] then
							self.selectTarget.name = self.selectTarget.name..";"..self.name
						end
					end
					SkuOptions.currentMenuPosition = self.selectTarget
				end
				if self.selectTarget.isSelect == true then
					if not string.find(self.name, L["Filter"]..";") then
						local rValue = self.name
						if string.sub(rValue, 1, string.len(L["Selected"]..";")) == L["Selected"]..";" then
							rValue = string.sub(rValue,  string.len(L["Selected"]..";") + 1)
						end

						local tUncleanValue = self.name
						local tCleanValue = self.name
						local tPos = string.find(tUncleanValue, "#")
						local tErrorSoundFound = string.find(tUncleanValue, L["error;sound"].."#")
						if tPos and not tErrorSoundFound then
							tCleanValue = string.sub(tUncleanValue,  tPos + 1)
						end

						self.selectTarget:OnAction(self, tCleanValue, self.parent.name)----------------
						-- we need to free up the memory of the old children before we're re-building on next acces of menu item
						-- now it's safe to do that, as multi select menu items are handled with the above OnAction
						self.children = {}
						--collectgarbage("collect")

						SkuOptions.currentMenuPosition = self.selectTarget

						-- W6-B: after setting a value, STAY on the setting entry
						-- (selectTarget) — the user just changed it, so the cursor
						-- should remain there to speak the new value and allow another
						-- change, not jump up a level. The old default stepped UP to
						-- the parent category (landing "one level too high"), which the
						-- vast majority of call sites already opted out of via
						-- noStepUpAfterSelect (auction coin/filter entries, mail,
						-- gameOptions, visualAids, aura config, ...). The step-up is now
						-- OPT-IN via `stepUpAfterSelect` for the rare node that really
						-- wants to land on the category level.
						-- (No OnUpdate here — that would rebuild the parent's children
						-- via the OnPostSelect/CheckFrames path and partially close the
						-- menu; we only move the cursor by pointer assignment.)
						if self.selectTarget.stepUpAfterSelect
							and self.selectTarget.parent
							and self.selectTarget.parent.name
							and SkuOptions.currentMenuPosition then
							pcall(function() SkuOptions:VocalizeCurrentMenuName() end)
							SkuOptions.currentMenuPosition = self.selectTarget.parent
						end
					else
						if SkuOptions.TTS.MainFrame:IsVisible() ~= true then
							SkuOptions:VocalizeCurrentMenuName()
						end
				
					end					
				end
			else
				local rValue = self.name
				local tUncleanValue = self.name
				local tCleanValue = self.name
				local tPos = string.find(tUncleanValue, "#")
				if tPos then
					tCleanValue = string.sub(tUncleanValue,  tPos + 1)
				end
				
				if string.sub(rValue, 1, string.len(L["Selected"]..";")) == L["Selected"]..";" then
					rValue = string.sub(rValue,  string.len(L["Selected"]..";") + 1)
				end
				if #self.children > 0 or self.selectTarget == self then
					self.parent:OnAction(self, tCleanValue, self.parent.name)
				else
					self:OnAction(self, tCleanValue, self.parent.name)------------
				end
				-- we need to free up the memory of the old children before we're re-building on next acces of menu item
				-- now it's safe to do that, as multi select menu items are handled with the above OnAction
				self.children = {}
				--collectgarbage("collect")
				SkuOptions.currentMenuPosition = self.parent
			end			
		end

		-- If the action above CLOSED the menu (e.g. waypoint "Auswählen" ->
		-- SkuOptions:CloseMenu()), stop here: re-focusing a node now would speak a
		-- stale entry and (pre-guard) re-armed the secure click bindings on the
		-- hidden menu -- the zombie-ENTER bug. The headless combat menu is not
		-- visually open but IS logically open (combatMenuActive), so keep firing
		-- OnEnter there -- it carries the in-combat announcements.
		if SkuOptions:IsMenuOpen() ~= true and SkuOptions.combatMenuActive ~= true then
			return
		end
		if SkuOptions.currentMenuPosition.OnEnter then
			SkuOptions.currentMenuPosition:OnEnter(aEnterFlag)
		end
		--if self.removeFilter then
			--SkuOptions.Filterstring = ""
			--SkuOptions:ApplyFilter(SkuOptions.Filterstring)
		--end
	end,
	}
setmetatable(SkuGenericMenuItem, SkuOptions.MenuMT)

-- (W6-B #4) Removed SkuOptions:BuildMenuSegment_TitleBuilder here: a ~188-line
-- SkuNav/SkuDB/SkuQuest-domain waypoint-naming submenu that did not belong in
-- the generic menu-node template file. Its only caller (the "New waypoint"
-- builder in SkuNav/Options.lua) was already commented out, so it was dead code.
