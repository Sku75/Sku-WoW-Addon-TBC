# SkuCore/alIntegration.lua

- Purpose: AtlasLoot integration — exposes the AtlasLoot(Classic) loot database as a browsable Sku menu (Search / Lists by expansion / Wishlist / Loot history), maintains a per-character item wishlist with loot-drop and chat-link sound alerts, and provides the Ctrl+Shift+L shortcut that jumps to the Atlas Loot menu entry. Implemented as AceAddon submodule `AtlasLootIntegration` of SkuCore (W4 Phase D toggleable, Phase E namespace-extracted); published handle `SkuCore.AtlasLootIntegration`. Works only when the third-party AtlasLoot addon is installed; every entry point guards via a lazy `EnsureAtlasLoot()` resolver so Sku-without-AtlasLoot is a silent no-op.

## Public API / exports
- `AtlasLootIntegration:OnEnable()` / `:OnDisable()` — arm (settings init, wishlist cache rebuild, loot/chat event registration, keybind apply) / disarm (unregister events, clear override binding).
- `AtlasLootIntegration:alItegrationLogin()` — settings-table init + event registration (called from OnEnable; note the "Itegration" typo family).
- `AtlasLootIntegration:alItegrationGetItemDropTable(aId)` — lazy-builds and returns the drop-source list for an itemID.
- `AtlasLootIntegration:alIntegrationQueryAll()` — full AtlasLoot DB crawl: fills tItemDropTable, tItemNameTable, alLookupBosses/alLookupInstances, alDropsByBoss/alDropsByInstance (expensive, one-shot per session).
- `AtlasLootIntegration:alIntegrationMenuBuilder()` — top-level Atlas Loot menu builder (Search, Lists, Wishlist "Nach Dungeon"/"Nach Slot", Loot history); called with `self` = the parent menu node (colon-call from the Options.lua build hook).
- `AtlasLootIntegration:alIntegrationItemMenuBuilder(aParent, aType, aId, aNpcId, aInternalDungeonName, aBossIndex, aTypeId, aDiffId)` — renders one item/set/spell/collection menu entry incl. tooltip text and wishlist add/remove children.
- Wishlist cache family: `RebuildWishlistCache()`, `WishlistEmpty()`, `IsItemInWishlist(itemID)`, `RemoveItemFromWishlist(itemID)` — O(1) itemID→true cache, rebuilt only when `wishlistCacheDirty`.
- Event handlers: `CHAT_MSG_LOOT` (loot-history record + wishlist-hit sound + auto-remove), `START_LOOT_ROLL` (wishlist-hit sound on roll dialog), `CHAT_MSG_PARTY` (wishlist-hit sound on chat item links; `CHAT_MSG_PARTY_LEADER`/`RAID`/`RAID_LEADER`/`SAY`/`YELL` are aliases of the same function).
- `AtlasLootIntegration:BuildContextualWishlistEntry(aParent, aDropMap)` — wishlist-∩-dropmap submenu (only reachable via alShortcutContext, which is currently never set — see gotchas).
- `AtlasLootIntegration:AtlasLootShortcut()` — opens the Sku menu and SlashFunc-navigates to Addons → Atlas Loot.
- `AtlasLootIntegration:AtlasLootApplyKeyBinding()` — creates/refreshes hidden button `SkuAtlasLootShortcutButton` and applies the SKU_KEY_OPENATLASLOOT override binding.
- `SkuCore:AtlasLootApplyKeyBinding()` — thin forwarding shim so the SkuKeyBinds string-dispatch (object="SkuCore") still resolves.
- Internal helper families: `EnsureAtlasLoot()` (resolve _G.AtlasLoot or _G.AtlasLootClassic, map fork onto _G.AtlasLoot), `BuildSource()` (instance/boss/profession source string), `stripColorCodes()`, `addToItemsRepos()`, `tSetShortcutContext()`, `tCurrentInstanceDifficultyName()`, `tFindAtlasLootContext()`, `tExpansionLabel()`, `tCategoryLabel()`.

## Dependencies (outgoing)
- AtlasLoot addon (external, optional): `AtlasLoot.Loader` (GetLootModuleList/IsModuleLoaded/LoadModule), `AtlasLoot.ItemDB` (Get/GetModuleList/GetItemTable/GetBossTable/GetNameData_UNSAFE/GetNpcID_UNSAFE), `AtlasLoot.Data` (ItemSet, Droprate, Profession), optional source-annotation globals `Sources`/`Recipe`/`Profession`/`SOURCE_DATA`/`SOURCE_TYPES`.
- SkuZOptions menu framework: `SkuOptions:InjectMenuItems`, `SkuGenericMenuItem`, `SkuOptions.currentMenuPosition` (textFirstLine/textFull writes), `SkuOptions:SlashFunc`, `SkuOptions:IsMenuOpen`.
- SkuSettings facade, `SkuOptions.Voice:OutputStringBTtts`, `SkuUtil:Unescape`, `SkuCore:getItemComparisnSections` / `SkuCore:ItemName_helper`, `TooltipLines_helper` + `SkuScanningTooltip` frame, `SkuDB.itemDataTBC`, `SkuCore:RegisterToggleableModule` (ModuleManager), `dprint`.
- WoW APIs: C_Item (GetItemNameByID/GetItemQualityByID/GetItemInventoryTypeByID/RequestLoadItemDataByID), GetItemInfo/GetItemInfoInstant, GetSpellInfo, GetLootRollItemLink, PlaySoundFile, C_Timer, SetOverrideBindingClick/ClearOverrideBindings, GetInstanceInfo/IsInInstance/GetDungeonDifficulty/GetRaidDifficulty, UnitName/UnitExists/UnitIsPlayer.

## Key data structures
- `AtlasLootIntegration.favoriteSlots` — array [1..27]: {INVTYPE string, {equip slot numbers}}; index doubles as the invType key of the favorites store.
- Favorites store (SavedVariables): `SkuSettings:Sub("SkuCore",nil,"char").alIntegration.favorites[invType][n] = itemLink`; `...lootHistory[n] = itemID` (quality>2 loot, capped at 1000).
- `tItemDropTable` (file-local) — [itemID] = array of "Instance - Boss (Difficulty) (drop%)" strings; `tItemNameTable` — [itemName] = {itemID, npcId, internalName, bossIndex, ttype, difficultyIndex}; both nil until first `alIntegrationQueryAll()`.
- `wishlistIdCache` [itemID]=true + `wishlistCacheDirty` flag — the O(1) raid-combat lookup (rebuilt lazily, dirty set on every favorites mutation).
- `alLookupBosses[bossName]` / `alLookupInstances[instanceName]` — path info {pluginTitle, gameVersion, contentIndex, instanceName, bossName, isWorldBoss, difficulties} for the (removed) contextual shortcut jump.
- `alDropsByBoss[bossName][itemID]=true` / `alDropsByInstance[instName][itemID]=true` — drop filters for the contextual wishlist.
- `alShortcutContext` (+120 s auto-clear timer) — context flag gating BuildContextualWishlistEntry splices in the menu builders; currently always nil (shortcut clears it).
- `tExpansions` [1]="Classic", [2]="The Burning Crusade" — expansion tabs matching AtlasLoot gameVersion numbering (gameVersion 0 = shown in every tab).

## Events
- AceEvent on the module (registered in alItegrationLogin, unregistered in OnDisable): CHAT_MSG_LOOT, START_LOOT_ROLL, CHAT_MSG_PARTY, CHAT_MSG_PARTY_LEADER, CHAT_MSG_RAID, CHAT_MSG_RAID_LEADER, CHAT_MSG_SAY, CHAT_MSG_YELL.
- File-scope frame `tAlInitFrame`: PLAYER_ENTERING_WORLD (once) → +2 s AtlasLootApplyKeyBinding.
- File-scope frame `tAlLookupInitFrame`: PLAYER_LOGIN (schedules eager QueryAll retries at 5/10/20/35/60 s), PLAYER_ENTERING_WORLD + ZONE_CHANGED_NEW_AREA (fallback +3 s retry until alLookupBosses is populated). These frames stay registered even when the module is toggled off.
- Timers: C_Timer.After 0.1/0.3 s retries for uncached items, 120 s NewTimer for shortcut-context expiry.

## Settings keys
- `SkuSettings:Sub("SkuCore", nil, "char").alIntegration.favorites` (read/write) and `.lootHistory` (read/write) — char scope.
- `SkuOptions.db.profile["SkuOptions"].SkuKeyBinds["SKU_KEY_OPENATLASLOOT"].key` (read) and `["SKU_KEY_OPENMENU"].key` (read).
- Module on/off persisted by the RegisterToggleableModule framework (ModuleManager).

## Entry points
- Keybind SKU_KEY_OPENATLASLOOT → hidden button `SkuAtlasLootShortcutButton` (SetOverrideBindingClick) → AtlasLootShortcut; rebind flows through the skuDefaultKeyBindings string-dispatch to the `SkuCore:AtlasLootApplyKeyBinding` shim.
- Menu node: Addons → Atlas Loot; its build hook in SkuCore/Options.lua points at `SkuCore.AtlasLootIntegration.alIntegrationMenuBuilder`. SkuZOptions also reads `SkuCore.AtlasLootIntegration.favoriteSlots` directly.
- Features menu toggle via `SkuCore:RegisterToggleableModule("AtlasLootIntegration", ...)`.

## Invariants & gotchas
- AtlasLoot has no `## OptionalDeps` entry in Sku.toc, so it may load AFTER Sku — never capture AtlasLoot symbols at file-load time; always resolve lazily through `EnsureAtlasLoot()` (it also maps a `_G.AtlasLootClassic` fork onto `_G.AtlasLoot`).
- Every favorites mutation MUST set `wishlistCacheDirty = true` or combat chat handlers will use a stale cache; `WishlistEmpty()` is the cheap early-out on the raid-spam path (do not remove).
- The keybind string-dispatch can only reach `_G` global objects — the `SkuCore:AtlasLootApplyKeyBinding` shim must stay even though the real method lives on the module.
- Line 53 writes the GLOBAL `INVTYPE_RANGEDRIGHT = RANGED`, mutating a Blizzard global for all addons.
- The wishlist-hit sounds hardcode `Interface\AddOns\Sku\SkuAudioData\assets\audio\<loc>\Tutorial_Success_01.mp3` (and `audio\I feel Good.mp3`) instead of going through the W5 `Sku:AudioFile()` resolver.
- AtlasLootShortcut navigates by SlashFunc label path ("Addons" → localized "Atlas Loot") — renaming/moving that menu node breaks the shortcut (W7 label-coupling sweep rule).
- `SkuCore = SkuCore or ...NewAddon(...)` first-wins idiom at the top; per-file MODULE_NAME/MODULE_PART convention.
- Files start with a UTF-8 BOM; lint with `luaparser` + `encoding='utf-8-sig'`.

## Cleanup candidates observed
- `addToItemsRepos` (line 1562) stores `npcId = aNnpcID` — a typo (parameter is `aNpcID`), so every tItemNameTable entry has npcId=nil and the Search path never gets drop rates.
- Contextual-shortcut machinery is dead: `AtlasLootShortcut` now always calls `tSetShortcutContext(nil)`, so `tFindAtlasLootContext`, `tCurrentInstanceDifficultyName`, `tExpansionLabel`, `tCategoryLabel` and every `alShortcutContext`-gated wishlist splice in the menu builders can never fire.
- `tBuildInstancesGroup` (lines 1161-1279, ~120 lines) is defined but never called — replaced by `tBuildGroup` per the comment at 1281.
- The item/set/spell dispatch loop over `items[itemIndex][2]` (set-name check, profession-spell check, >1000000 set-ID suffix trick) is copy-pasted four times (standard lists, professions, world bosses, dead tBuildInstancesGroup) — prime extraction target.
- CHAT_MSG_LOOT history cap removes the entry it just appended (`lootHistory[#lootHistory] = nil` when >1000), so once full the NEWEST loot is discarded instead of the oldest; also the "Nach Slot" and "Loot history" OnEnter closures reference `aNpcId`, which is nil-global there (dead Droprate branch).
