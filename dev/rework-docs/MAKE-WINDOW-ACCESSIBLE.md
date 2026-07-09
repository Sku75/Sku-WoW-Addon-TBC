# Making a Blizzard window accessible through Sku's menu

A reusable recipe for exposing an inaccessible Blizzard frame (settings, LFG,
socketing, any panel) as a Sku menu a screen-reader user can drive. Proven on
**Game Options** (`SkuCore/gameOptions.lua`) and the **Dungeon Browser**
(`SkuCore/dungeonBrowser.lua`). The sibling project WowVision does the same job a
different way (live-widget mirror); reading its `tbc/*.lua` next to this is a good
cross-check.

---

## 0. Pick the approach (there are three)

Blizzard windows differ in whether there's a clean **data/action API** behind the
widgets, and in how **protected** the actions are. Choose per window:

1. **Data-API render** — read the underlying data API and render your own menu,
   driving each control through its read/write functions. Best when the API is
   clean and unprotected. *Example: Game Options* — `SettingsPanel:GetAllCategories()`
   → `layout:GetInitializers()` → `setting:GetValue()/SetValue(v)`.

2. **Read-API + macrotext-write** — read state from the data API, but perform the
   *protected* actions through a Sku `.macrotext` node (hardware-event context).
   Best when reads are clean but writes are protected. *Example: Dungeon Browser*
   — read via `C_LFGList.GetActivityInfoTable` / `GetSearchResultInfo`; write via
   macrotext `C_LFGList.CreateListing` / `RemoveListing` / `InviteUnit`.

3. **Live-widget mirror** — drive the *real* Blizzard widgets via secure clicks
   (`SecureActionButton`, `type=click`, `clickbutton=<real frame>`). The only
   option when the action is **secure-only** (cannot be called from addon code at
   all, even in a hardware event) and the state lives in the frame. *This is
   WowVision's default; in Sku it's the `directClickButton` escape hatch (see the
   enchanting/DoCraft fix).*

Rule of thumb: try 1, fall back to 2 for protected writes, and only reach for 3
when a protected function is secure-only (see §2).

---

## 1. Recon with a throwaway probe (do NOT guess the layout)

Never guess the frame's widget names / API shapes from docs or from WowVision —
backports differ. Confirm on the live client with a disposable probe.

Use `Sku42-Rework-Docs/window-recon-probe.lua` (a generalized template — same
shape as `SkuCore/DualSpecProbe.lua`):

1. Copy it to `Sku/SkuCore/windowRecon.lua` and add a line to `Sku.toc`.
2. In game: open the target window, then `/skuprobe <FrameName>` (it forces
   `Sku.debug.log = true`, so capture works without `/skudebug` first).
   - `/skuprobe <FrameName>`        — full dump (API-ish checks + frame tree)
   - `/skuprobe <FrameName> tree`   — recursive widget tree only
   - `/skuprobe <FrameName> scroll <ScrollBoxName>` — retail ScrollBox: size,
     data-provider methods, and a sample of element-data tables
   - `/skuprobe <FrameName> methods <ObjName> <pat>` — function-valued keys of an
     object matching a substring (finds the real method name when an accessor
     returns nil)
3. `/reload` to flush, then read `...SavedVariables/Sku.lua` (`SkuDebugLog.lines`)
   with `py -3` (brace-depth + line scan — see the CLAUDE.md log-parsing notes).
4. Delete the file + its `.toc` line when done.

What the probe tells you: exact frame/child names, object types, shown flags,
FontString text, whether a control is a retail ScrollBox (`GetDataProviderSize`)
or dropdown (`OpenMenu`), the **keys inside element-data tables** (row payloads),
and **GetSearchResultInfo/GetActivityInfoTable-style return shapes**.

---

## 2. Taint & protected functions — the rules that actually bite

WoW blocks "protected" functions unless the call context is trusted. Three tiers,
and the fix differs for each:

- **Unprotected (reads, most getters).** Call freely from Lua: `GetValue`,
  `GetActivityInfoTable`, `GetSearchResultInfo`, `GetChecked`, CVars, etc.

- **Hardware-event-gated protected functions.** Allowed only when the call runs
  inside a real hardware event (keypress/click). Sku's mechanism: a menu node
  with `.macrotext = "/run …"` is wired to a hidden `SecureActionButton`
  (`type=macro`) that your Enter key clicks via `SetOverrideBindingClick`, so the
  macro runs in hardware context. **Put the protected call in a `.macrotext`
  node, never in `OnAction`** (plain Lua = no hardware event = `ADDON_ACTION_
  BLOCKED`). Examples: `C_LFGList.CreateListing` / `RemoveListing` / `Search`,
  AH `PlaceAuctionBid`, `InviteUnit`.

- **Secure-only protected functions.** Cannot be called from addon code at all.
  Blizzard only calls them from a secure widget's own click. Drive the **real
  widget** via a `SecureActionButton` (`type=click`, `clickbutton=<frame>`) bound
  to your key — this is Blizzard-sanctioned and taint-free. If the action reads
  frame state (e.g. a selection table), that state must ALSO have been set by
  secure clicks (tainted state poisons the action). Secure clicks are
  **one-per-keypress** — you cannot batch them.

### The silent-no-op gotcha (cost us a full debugging round)

A protected API that takes a **table** can **silently do nothing** — no Lua
error, `pcall` returns `ok=true`, but the action never happens — if you pass
**extra/unexpected fields**. The Dungeon Browser's `CreateListing` posted nothing
until we removed bogus `playstyle` / `isNewPlayerFriendly` keys and matched
Blizzard's exact table. **Confirmation signal:** the game's own success sound /
event fires only when the call really took effect — use that (not just your own
"started" message) as ground truth.

**Always match Blizzard's exact call.** Read the real code under
`_anniversary_/BlizzardInterfaceCode/Interface/AddOns/…` and copy the argument
shape verbatim. For the LFG listing it was
`Blizzard_GroupFinder_VanillaStyle/Blizzard_LFGVanilla_Listing.lua`:
`C_LFGList.CreateListing({ activityIDs = …, newPlayerFriendly = … })`.

---

## 3. Render with Sku's standard menu elements

Build a `Module:XxxMenuBuilder(aParent)` (or a top-level entry with
`BuildChildren`) using `SkuOptions:InjectMenuItems(parent, {name}, SkuGenericMenuItem)`:

- **Action** → `entry.OnAction = function() … end` (unprotected) OR
  `entry.macrotext = "/run …"` (protected — see §2).
- **Select / dropdown** → `entry.isSelect = true`, `entry.noStepUpAfterSelect =
  true`, `entry.GetCurrentValue = function() return <live label> end`,
  `entry.OnAction = function(self, _, aSelName) <set by label> end`,
  `entry.BuildChildren` injects the option labels.
- **Toggle / checkbox** → show state in the label; toggle via a macrotext helper
  that mutates + relabels in place + re-announces (keeps the cursor put).
- **Submenu / list** → `entry.dynamic = true`, `entry.sorting = true` for sorted
  lists, `entry.BuildChildren` builds children lazily each descent.
- **Text field** → `SkuOptions:EditBoxShow(initial, function() … end)` and read
  `SkuOptionsEditBoxEditBox:GetText()` in the callback (see `SkuCore/mail.lua`).

---

## 4. Auto-open on the real frame's Show

So opening the Blizzard window lands the user in the Sku menu:

- `hooksecurefunc`/`HookScript` the frame's `OnShow` (and the toggle functions as
  a safety net), then `SkuOptions:SlashFunc("short," .. lower(node path))` —
  deferred one frame via `C_Timer.After(0, …)` so you don't fight Blizzard's Show.
- **Verify the container name on the live build** — e.g. the LFG window is
  `LFGParentFrame`, not `PVEFrame` (which does not exist on Anniversary).
- **Do not force-open the real frame** from a keybind for a screen-reader user:
  it's not needed (the Sku menu is the interface) and can provoke the frame's own
  taint-prone code (e.g. LFG's auto-search → `ADDON_ACTION_BLOCKED`).
- **Open the Sku menu on the NEXT frame**, not synchronously inside the keybind's
  `OnKeyDown` — otherwise the same keypress falls through to the menu type-ahead
  and the hotkey's own letter becomes a filter. (Deferring one frame is why quest
  log / character / Shift-F1 don't have this bug.)

---

## Case studies

- **Game Options** (`SkuCore/gameOptions.lua`) — approach 1 (data-API render).
- **Dungeon Browser** (`SkuCore/dungeonBrowser.lua`) — approach 2 (read-API +
  macrotext-write); mirrors `LFGParentFrame`'s two tabs (Eintrag erstellen /
  Gruppensuche) as Sku menus.
- **WowVision `tbc/lfg.lua`** — approach 3 (live-widget mirror via `Proxy*` +
  `SecureActionButton`); the reference for secure-only actions.
