local _G = _G

SkuOptions = SkuOptions or LibStub("AceAddon-3.0"):NewAddon("SkuOptions", "AceConsole-3.0", "AceEvent-3.0")
local L = Sku.L

local MENU_MENU = 1
local MENU_DROPDOWN = 2
local MENU_DROPDOWN_MULTI = 3

-- [v43.0] One shared metatable per template. A menu node INHERITS the template's
-- fields through __index instead of getting a copy of all 28 of them, which is
-- what makes a node cheap to create - see the note on __add below.
--
-- Weak keys: a template is a long-lived global today, but nothing here should be
-- the reason one can never be collected.
local tNodeMetatables = setmetatable({}, {__mode = "k"})
local function tNodeMetatable(aTemplate)
	local tMT = tNodeMetatables[aTemplate]
	if not tMT then
		-- __tostring is carried over so tostring(node) still dumps a node the way
		-- tostring(template) always has. Resolved at call time, not at load time:
		-- SkuOptions.MenuMT does not exist yet while this function is being
		-- defined.
		tMT = {__index = aTemplate, __tostring = SkuOptions.MenuMT.__tostring}
		tNodeMetatables[aTemplate] = tMT
	end
	return tMT
end

SkuOptions.MenuMT = {
	-- [v43.0] A node is a nearly EMPTY table pointed at its template, not a deep
	-- copy of it. This runs once per menu entry, and the aura spell lists build
	-- 27,057 of them in one go: on a hardcore realm the old version did not
	-- merely lag, it hit the server's script execution limit and the list never
	-- opened at all (log 2026-08-23, "BuildChildren FAILED ... script ran too
	-- long | children now 11389" - it died about 40% of the way in, at a
	-- different point every time).
	--
	-- What the copy used to cost per node: a `seen` table, a pairs() walk of all
	-- 28 template fields with a type() call and three key comparisons each, 28
	-- table stores, and a recursive TableCopy of the `children` table. What it
	-- costs now: two table allocations and one store. Everything the node does
	-- not override is read straight off the template.
	--
	-- `children` MUST stay a fresh table per node - it is the one mutable
	-- table-valued field in the template, and inheriting it would give every menu
	-- entry in the addon the same children list.
	--
	-- Writing a field on a node still shadows the template as it always did; the
	-- one thing that changes is that pairs(node) now sees only what the node
	-- itself set. Audited: nothing in the addon iterates a node's own fields (the
	-- __tostring dump aside), and the single place that COPIES a node
	-- (SkuOptions:ApplyFilter, the filter entry) re-attaches the metatable.
	__add = function(thisTable, newTable)
		local tTable = setmetatable({children = {}}, tNodeMetatable(newTable))
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

-- [2026-08-19] Rebuilding a level's children OUTSIDE of OnPostSelect used to
-- silently break ENTER on every entry below it: the isSelect/isMultiselect
-- wiring (selectTarget on the level itself AND a copy on every child) is what
-- routes a leaf's ENTER to the owning list's OnAction. A raw
-- `node.children = {} node:BuildChildren(node)` leaves the fresh children with
-- selectTarget = nil, so OnPostSelect falls into its generic branch: no
-- OnAction runs and the cursor just steps up to the parent. That was the
-- "route list finished loading -> ENTER on a route point jumps to the top of
-- the list instead of starting navigation" bug (closing and reopening the menu
-- fixed it because the re-entry went through OnPostSelect again).
-- One source of truth for that rebuild; OnPostSelect's dynamic block calls it
-- too. aKeepSelectTarget = do not re-seed the target (a mid-list live refresh
-- must not throw away what the user already selected), only re-propagate it.
function SkuOptions:RebuildNodeChildren(aNode, aKeepSelectTarget)
	if not aNode or not aNode.BuildChildren then
		return
	end
	-- we need to free up the memory of the old children before we're re-building; otherwise we'll leak memory on next BuildChildren
	aNode.children = {}
	if aKeepSelectTarget ~= true then
		if aNode.isMultiselect == true then
			local tNewMenuEntry = SkuOptions:InjectMenuItems(aNode, {L["Nothing selected"]}, SkuGenericMenuItem)
			aNode.selectTarget = tNewMenuEntry
		end
		if aNode.isSelect == true then
			aNode.selectTarget = aNode
		end
	end
	aNode:BuildChildren(aNode)
	if aNode.selectTarget then
		for x = 1, #aNode.children do
			aNode.children[x].selectTarget = aNode.selectTarget
		end
	end
end

-- [v43.0] CONTINUE a level whose BuildChildren was cut off mid-way.
--
-- A hardcore realm kills an addon script that runs too long, and the aura spell
-- lists are 27,000 entries: the build died partway and left a TRUNCATED level
-- behind (log 2026-08-23, "children now 6869"). The guard at the vocalize call
-- site then saw a non-empty children list and never rebuilt it, so the second
-- arrow-right silently handed the user a list missing twenty thousand spells -
-- which reads as real data, not as a failure. That is the bug this fixes; the
-- node change already made the whole thing three times cheaper, this is about
-- what happens when it STILL does not fit.
--
-- The script budget is per execution, so the next frame gets a fresh one: the
-- continuation runs on a zero-delay timer and appends where the last pass
-- stopped, exactly the way the route data is sliced across frames. The user
-- hears the first entries immediately and the rest arrives behind them.
--
-- Only a builder that declares `resumableBuild` is re-entered. A normal
-- BuildChildren APPENDS, so calling it again on a level that already has
-- children would duplicate every entry - which is precisely why the guard at
-- the call site exists. A resumable builder is one that keeps its own cursor and
-- continues from it (see tBuildValueToggleList in SkuAuras/Options.lua).
local BUILD_CONTINUE_MAX = 40
function SkuOptions:ContinueInterruptedBuild(aNode)
	if type(aNode) ~= "table" or aNode.resumableBuild ~= true or not aNode.BuildChildren then
		return
	end
	if aNode.buildContinuePending == true then
		return
	end
	aNode.buildContinuePending = true
	local tPasses = 0
	local tStep
	tStep = function()
		aNode.buildContinuePending = nil
		-- Left the level, or something rebuilt it from scratch: drop the cursor
		-- and stop. Continuing into a level nobody is standing in would fill it
		-- for a user who has moved on, on a client that just proved it has no
		-- budget to spare.
		if aNode.buildChildrenIncomplete ~= true then
			return
		end
		local tBefore = aNode.children and #aNode.children or 0
		local tOk, tErr = pcall(function() aNode:BuildChildren(aNode) end)
		local tAfter = aNode.children and #aNode.children or 0
		tPasses = tPasses + 1
		if aNode.buildChildrenIncomplete ~= true then
			dprint("BuildChildren continued to completion for", tostring(aNode.name), "after", tPasses, "passes,", tAfter, "entries")
			return
		end
		-- No progress means it is not a budget problem at all (a builder that
		-- throws on the same entry every time), and repeating it forever would
		-- pin the client. Same for a runaway count.
		if tAfter <= tBefore or tPasses >= BUILD_CONTINUE_MAX then
			dprint("BuildChildren continuation GAVE UP for", tostring(aNode.name), "-- pass", tPasses,
				"went from", tBefore, "to", tAfter, "entries; last error", tostring(tErr))
			return
		end
		aNode.buildContinuePending = true
		C_Timer.After(0, tStep)
	end
	C_Timer.After(0, tStep)
end


-- =====================================================================
-- [v43.0] TWO-VALUE SETTING = ONE MENU ENTRY (a real toggle)
--
-- Sku used to render every boolean setting as a CONTAINER: the entry carried
-- the setting's name and nothing else, and the two values ("Ein"/"Aus",
-- "Ja"/"Nein", ...) lived one level down as its children. Reading the entry
-- therefore never told the user what the setting was actually set to - finding
-- that out cost a RIGHT arrow, and changing it cost RIGHT, an arrow to the
-- other value, and ENTER. For a setting with exactly two states that submenu
-- carries no information the entry could not carry itself.
--
-- The aura value lists (SkuAuras/Options.lua) already do the better thing via
-- `actionInPlace`: the entry reads "<name>;<state>", ENTER flips it, the cursor
-- does not move, and the key handler re-speaks the entry in its new state. This
-- is that pattern, generalized, so every two-value setting in the addon behaves
-- the same way and only ONE place has to get it right.
--
-- What a toggle node is:
--   * a LEAF - no children, `dynamic` off, so RIGHT does nothing on it (the key
--     handler only descends when there are children or the node is dynamic) and
--     nothing has to be built to read or change it
--   * `actionInPlace`, so ENTER runs its own OnAction and leaves the cursor
--     where it is (see the flag's note on SkuGenericMenuItem below)
--   * `RefreshLiveName`, so the state in the label is re-read from the setting
--     immediately before it is spoken. That is what keeps a mirrored entry (the
--     same setting rendered a second time in the quick menu) and an entry sitting
--     in a level that is not rebuilt from going stale - the OLD submenu got that
--     for free because it re-read GetCurrentValue on every descend.
--
-- Label order is name-first, state-after, exactly like the aura toggles: the
-- list is scanned by name and type-ahead keys off the first letter, while the
-- state is what the user needs to hear right after pressing ENTER.
--
-- aSpec:
--   label     - display name without the state (defaults to the node's name)
--   get       - function(node) -> truthy when the setting is ON. REQUIRED.
--   set       - function(node, aNewValue) writes the new boolean. REQUIRED.
--   onLabel   - state word for ON  (default L["On"])
--   offLabel  - state word for OFF (default L["Off"])
--   onChange  - optional function(node, aNewValue) run after a successful write
--               (announcements, applying the value to the game, ...)
--   canChange - optional function(node) -> false to refuse the flip (a locked
--               setting). It is responsible for saying why; the label is left
--               untouched, so the user hears the unchanged state back.
--   vocalizeAsIs - passed through to the node when set
-- =====================================================================
function SkuOptions:MakeToggleNode(aNode, aSpec)
	if type(aNode) ~= "table" or type(aSpec) ~= "table" then
		return aNode
	end
	if type(aSpec.get) ~= "function" or type(aSpec.set) ~= "function" then
		dprint("MakeToggleNode: refusing", tostring(aNode.name), "-- get/set are both required")
		return aNode
	end

	aNode.toggleLabel = aSpec.label or aNode.name
	aNode.toggleOnLabel = aSpec.onLabel or L["On"]
	aNode.toggleOffLabel = aSpec.offLabel or L["Off"]
	aNode.toggleGet = aSpec.get
	aNode.toggleSet = aSpec.set
	aNode.toggleOnChange = aSpec.onChange
	aNode.toggleCanChange = aSpec.canChange

	-- A two-value setting is a leaf now. Clearing these on the INSTANCE lets the
	-- shared template show through again (its BuildChildren is a no-op), which is
	-- what we want: nothing left to descend into, nothing left to build.
	aNode.isSkuToggle = true
	aNode.actionInPlace = true
	aNode.isSelect = false
	aNode.isMultiselect = false
	aNode.dynamic = false
	aNode.BuildChildren = nil
	aNode.GetCurrentValue = nil
	-- Only when there is something to drop: InjectMenuItems already hands over a
	-- node with its own fresh empty children table, and replacing that with a
	-- second empty one is an allocation per toggle for nothing.
	if type(aNode.children) ~= "table" or #aNode.children > 0 then
		aNode.children = {}
	end
	if aSpec.vocalizeAsIs ~= nil then
		aNode.vocalizeAsIs = aSpec.vocalizeAsIs
	end

	aNode.RefreshLiveName = function(self)
		local tOk, tOn = pcall(self.toggleGet, self)
		if tOk then
			self.name = self.toggleLabel..";"..(tOn and self.toggleOnLabel or self.toggleOffLabel)
		elseif self.toggleGetFailed ~= true then
			-- Once per node: a reader that throws leaves the entry reading as a
			-- bare label with no state at all, which sounds like a setting that
			-- simply has no value rather than like a defect. Not every call --
			-- this runs before EVERY announce, and a broken one would then own
			-- the debug ring. Counted for /skucheck menu, so it shows up as a
			-- number rather than as "that setting never says whether it is on".
			self.toggleGetFailed = true
			SkuOptions.tMenuToggleGetFailures = (SkuOptions.tMenuToggleGetFailures or 0) + 1
			SkuOptions.tMenuToggleGetFailureLast = tostring(self.toggleLabel)
			dprint("MakeToggleNode: get FAILED for", tostring(self.toggleLabel), "->", tostring(tOn))
		end
	end

	aNode.OnAction = function(self)
		if self.toggleCanChange and self.toggleCanChange(self) == false then
			return
		end
		local tOk, tOn = pcall(self.toggleGet, self)
		if not tOk then
			dprint("MakeToggleNode: get FAILED for", tostring(self.toggleLabel), "->", tostring(tOn))
			return
		end
		local tNew = not tOn
		local tSetOk, tErr = pcall(self.toggleSet, self, tNew)
		if not tSetOk then
			-- Do NOT relabel: the user must not hear a state the setting did not
			-- take. Same reason the aura toggles rewrite their name only after the
			-- store call returned.
			dprint("MakeToggleNode: set FAILED for", tostring(self.toggleLabel), "->", tostring(tErr))
			return
		end
		self:RefreshLiveName()
		if self.toggleOnChange then
			pcall(self.toggleOnChange, self, tNew)
		end
	end

	aNode:RefreshLiveName()
	return aNode
end

-- The same thing for a node that ALREADY has the classic on/off shape -
-- `isSelect` plus a GetCurrentValue that returns one of the two state labels
-- plus an OnAction that takes the chosen label. Those two functions are the
-- site's own reader and writer, so reusing them keeps every per-setting quirk
-- (talent-set indirection, .value sub-tables, side effects) exactly as it was
-- and the conversion is a single added line at the call site.
--
-- OnAction is invoked the way the menu framework invokes it for a value child
-- (self, chosenLabel, parentName), so a site that switches on `aName` needs no
-- change at all.
--
-- The two labels only have to BE the two strings GetCurrentValue can return -
-- which of them is passed as "on" does not matter. `get` answers true exactly
-- when the stored value is aOnLabel, and the label shown is aOnLabel in that
-- case, so the state the user hears is the stored one either way; flipping just
-- writes the other of the pair. That is what makes converting the ~50 existing
-- Ja/Nein, Ein/Aus and Low/High sites a mechanical one-liner per site instead of
-- a judgement call about which value counts as "on".
function SkuOptions:MakeInPlaceToggle(aNode, aOnLabel, aOffLabel, aLabel)
	if type(aNode) ~= "table" then
		return aNode
	end
	local tOn = aOnLabel or L["On"]
	local tOff = aOffLabel or L["Off"]
	local tGetCurrentValue = aNode.GetCurrentValue
	local tOnAction = aNode.OnAction
	if type(tGetCurrentValue) ~= "function" or type(tOnAction) ~= "function" then
		dprint("MakeInPlaceToggle: refusing", tostring(aNode.name), "-- needs GetCurrentValue and OnAction")
		return aNode
	end
	return SkuOptions:MakeToggleNode(aNode, {
		label = aLabel or aNode.name,
		onLabel = tOn,
		offLabel = tOff,
		get = function(self)
			return tGetCurrentValue(self) == tOn
		end,
		set = function(self, aNewValue)
			tOnAction(self, self, aNewValue and tOn or tOff, self.parent and self.parent.name)
		end,
	})
end


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
	-- [v43.0] "act here, stay here". ENTER on a node with this flag runs the
	-- node's OWN OnAction and leaves the cursor exactly where it is; the node's
	-- children are NOT freed. Everything else in this template moves the cursor
	-- on ENTER (to the level's select target, or up to the parent), which is why
	-- a MULTI-select list was not buildable before: every toggle threw the user
	-- out of the list they were toggling in.
	-- The node is expected to rewrite its own `name` inside OnAction; the key
	-- handler vocalizes currentMenuPosition after ENTER, so the user hears the
	-- item they just toggled, in its new state, without having moved.
	-- See SkuAuras/Options.lua for the first users (output list, condition value
	-- lists, the aura workbench's text prompts).
	--
	-- On a LEAF this flag is all that is needed. A node that also has children
	-- must additionally set `actionOnEnter = true`, otherwise ENTER descends
	-- (the descend branch below is checked first) and the flag never applies -
	-- RIGHT still descends in both cases, which is the point of the pairing.
	actionInPlace = false,
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

		-- swap out the children for a freshly built list. Through the shared
		-- helper so the fresh children keep the level's selectTarget (a raw
		-- rebuild left it nil and ENTER below such a list stopped acting - the
		-- same defect the waypoint-list push-refresh had). aKeepSelectTarget:
		-- this is a LIVE refresh mid-list, so the target the user may already
		-- have selected must survive it - only the propagation is redone.
		SkuOptions:RebuildNodeChildren(tParent, true)
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
				-- [v43.0] auraOutputKey: the aura output TOGGLES carry a state
				-- suffix in their name ("...#glas 1;ein"), so the exact-name
				-- comparison can no longer find them. The key identifies the
				-- output directly; the name comparison stays for every node built
				-- before the flag existed.
				if self.name == v.friendlyName or (self.auraOutputKey ~= nil and self.auraOutputKey == i) then
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
			self.skuClickStagingBlocked = nil
		else
			-- [v43.0] In combat SetAttribute and SetOverrideBindingClick are both
			-- refused, so NOTHING above ran: this node's secure left payload was
			-- never staged and the activate key clicks a secure button that holds
			-- either an empty or a stale macro. For most payloads that is correct
			-- (they need the hardware event anyway and cannot work in combat), but
			-- it silently killed the ones that are pure insecure Lua -- above all
			-- the StaticPopup buttons: a group invite arriving mid-fight could be
			-- read and navigated but not answered (2026-08-21 log, seq 47580: ENTER
			-- on "Annehmen" only re-announced the entry). Mark the node so the
			-- ENTER/RCLICK dispatcher can use a node-provided insecure fallback.
			self.skuClickStagingBlocked = true
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
			-- (the former inline rebuild lives in SkuOptions:RebuildNodeChildren now,
			-- so every out-of-band rebuild gets the identical selectTarget wiring)
			SkuOptions:RebuildNodeChildren(self)
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
			if self.actionInPlace == true then
				-- [v43.0] "act here, stay here" (see the flag on the template above).
				-- Checked BEFORE the selectTarget branch on purpose: ENTER inside a
				-- select level otherwise always dispatches to the LEVEL'S target and
				-- parks the cursor there, so a toggle node under such a level could
				-- never own its own ENTER.
				local tCleanValue = self.name
				local tPos = string.find(self.name, "#")
				if tPos then
					tCleanValue = string.sub(self.name, tPos + 1)
				end
				if self.OnAction == nil or self.OnAction == SkuGenericMenuItem.OnAction then
					-- Acts in place but has no action of its own: a silently dead
					-- ENTER, same defect class as the selectTarget miss below.
					SkuOptions.tMenuActionInPlaceMisses = (SkuOptions.tMenuActionInPlaceMisses or 0) + 1
					SkuOptions.tMenuActionInPlaceLast = tostring(self.name)
					dprint("skucheck", "VIOLATION menu: ENTER on", self.name, "-- actionInPlace without an own OnAction")
				else
					self:OnAction(self, tCleanValue, self.parent and self.parent.name)
				end
				-- children deliberately NOT freed and the cursor deliberately NOT
				-- moved -- that is the whole point of the flag. The node is expected
				-- to have rewritten its own `name`; the key handler vocalizes
				-- currentMenuPosition right after this, so the user hears the new
				-- state of the entry they are still standing on.
			elseif self.selectTarget and self.selectTarget ~= self then
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
				-- [skucheck invariant 4 tripwire, 2026-08-19] We are about to run the
				-- GENERIC action path: no selectTarget, so ENTER can only step up a
				-- level. That is correct for a plain leaf, but it is also exactly how
				-- the "route list finished loading" bug looked - a level rebuilt
				-- without SkuOptions:RebuildNodeChildren leaves its children (and
				-- everything below them) with selectTarget = nil, and the leaf's ENTER
				-- silently does nothing. A leaf that sits UNDER a select level must
				-- have inherited that level's target, so a missing one there is a real
				-- defect. Counted for /skucheck menu; the walk only runs on this
				-- branch and stops at the first select ancestor.
				if not self.selectTarget then
					local tAncestor, tDepth = self.parent, 0
					while type(tAncestor) == "table" and tDepth < 12 do
						if tAncestor.isSelect == true or tAncestor.isMultiselect == true then
							SkuOptions.tMenuSelectTargetMisses = (SkuOptions.tMenuSelectTargetMisses or 0) + 1
							SkuOptions.tMenuSelectTargetLast = tostring(self.name).." / "..tostring(tAncestor.name)
							dprint("skucheck", "VIOLATION menu: ENTER on", self.name, "-- no selectTarget although", tAncestor.name,
								"is a select level; those children were rebuilt without SkuOptions:RebuildNodeChildren")
							break
						end
						tAncestor = tAncestor.parent
						tDepth = tDepth + 1
					end
				end
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
