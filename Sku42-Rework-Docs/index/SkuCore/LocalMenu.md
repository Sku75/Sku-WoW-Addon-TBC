# SkuCore/LocalMenu.lua
- Purpose: The window-mirroring builders for the "Local" container: for each supported Blizzard window (bags, bank, guild bank, character sheet, talents, class trainer, trade, tradeskill/craft, pet stable, gossip, quest frames, item text, role poll, SoD runes) a `Build_*`/`*Frame` function reads the live Blizzard frames/APIs and emits a Sku menu-node subtree into the `aParentChilds` table it is handed. These builders are invoked by the SkuCore window pipeline (`SkuCore:CheckFrames` in the frames/windows build code) when the matching Blizzard frame is visible; the resulting node tables are then rendered/navigated by the SkuZOptions menu framework. The file also captures the combat mirrors (`combatBagOrder`, `combatBagTree`, `combatCharTree`) as the single source of truth for the in-combat secure navigation, and contains the coroutine-driven bag sorting/cleanup actions.
- Pipeline pattern (used by every builder): probe frames via `_G[name]` + `:IsVisible()`/`:IsEnabled()`, extract text via GetText or by replaying the button's OnEnter into GameTooltip / SkuScanningTooltip and scanning FontString regions, clean with `SkuUtil:Unescape` + `ItemName_helper` (short line + full text split), then append a node into the dual array+hash `aParentChilds`.

## Public API / exports
- SkuCore:IsItemSoulbound(bag, slot) — tooltip-scan check for the localized "Soulbound" line.
- SkuCore:getItemComparisnSections(itemId, cache) — tooltip texts of currently equipped items comparable to itemId (invType→slot map, 2H/offhand special case).
- SkuCore:InsertComparisnSections(itemId, textFull, cache) — inserts "currently equipped" sections into a textFull table for equippable items.
- SkuCore:Build_GuildBankFrame(aParentChilds) — guild bank tabs, 7x14 slot grid (item info stuffed into `obj.info` with gbanktab/gbankslot), item log and money log tabs (last 100 transactions).
- SkuCore:Build_BankFrame(aParentChilds) — only calls OpenAllBagsHelper(); bank content itself comes through Build_BagsFrame (bank bag ids). Nearly empty.
- SkuCore:Build_BagsFrame(aParentChilds) — container-API driven bag enumeration (bags need NOT be open/rendered); per-bag nodes + flat sorted "all items" list (new items first) + bag-slot buttons + bank bag purchase + "Sorting and cleanup" submenus; captures SkuCore.combatBagOrder and SkuCore.combatBagTree.
- SkuCore:PLAYER_TALENT_UPDATE() — re-runs currentMenuPosition:OnUpdate() 0.3s later while the talent frame is open.
- SkuCore:ACTIVE_TALENT_GROUP_CHANGED() — full CheckFrames + top-level OnUpdate rebuild on dual-spec switch (updates "(aktiv)" markers).
- SkuCore:Build_TalentFrame(aParentChilds) — dispatcher: single spec = flat UI-driven build (tBuildActiveSpecUI); dual spec (server-backported, detected purely via talent-group count) = one submenu per spec, inactive spec built API-driven read-only plus an activation entry (secure macrotext + Lua fallback, dprint-logged).
- SkuCore:Build_RolePollPopup(aParentChilds) — tank/healer/dps pick with directAction select-then-accept.
- SkuCore:BuildEngravingFrame(aParentChilds) — SoD rune list per category with "Engrave" action (C_Engraving.CastRune). Only called when Sku.IsEraSoD.
- SkuCore:Build_CharacterFrame(aParentChilds) — level text, Equipment (via SkuCore:IterateChildren on PaperDollItemsFrame), Stats (TBC path re-runs Blizzard PaperDollFrame_Set* setters via loadstring on a shared stat frame, with `liveName` re-read closures), Resistances, Berufe (professions open/unlearn with confirm popup), Ausrüstungssets (delegates to SkuCore.EquipmentSets:BuildChilds); captures the full combatCharTree mirror at the end.
- SkuCore:Build_ClassTrainerFrame(aParentChilds) — trainer skill list with difficulty derived from text color, scroll up/down entries (double-click), selected-skill detail node, Train button with post-click re-pin/re-vocalize.
- SkuCore:Build_TradeFrame(aParentChilds) — full trade window as read nodes (partner/your items+gold, enchant slot 7 clickable via containerFrameName), Refresh and Accept actions with re-pin.
- SkuCore:Build_TradeSkillFrame(aParentChilds) — tradeskill list (color→difficulty), scroll buttons, selected-recipe detail (reagents/requirements/description/item tooltip), Create and Create All.
- SkuCore:Build_CraftFrame(aParentChilds) — enchanting-style craft list; Create uses directAction + directClickButton="CraftCreateButton" because DoCraft is taint- AND hardware-event-protected (see gotchas).
- SkuCore:Build_PetStableFrame(aParentChilds) — current pet + 4 stable slots (func = drag/receive-drag pickup swap), buy-slot button.
- SkuCore:ItemTextFrame(aParent) — readable item text (books/plaques) with prev/next page buttons.
- SkuCore:GossipFrame(aParentChilds) — two code paths: legacy GossipTitleButtonN frames, else C_GossipInfo APIs (options via SelectOption with SelectGossipOption(index) TBC fallback; available/active quests with SkuDB blacklist marker).
- SkuCore:QuestFrame(aParentChilds) — greeting/progress/detail/reward panels, all W7-flattened directly into the window node; state prefixed onto the quest title ("Annehmen/Fortschritt/Abgabe <name>"); rewards via local QuestInfoRewardsFrameHelper (choose/receive items with comparison sections, money, XP, talent points); Accept/Decline/Complete buttons.
- Internal helper families (locals): tooltip readers (GetButtonTooltipLines, GetTooltipLines, getItemTooltipTextHelper, getItemTooltipTextFromBagItem, getEquippedItemTooltipText), ItemName_helper (local copy; SkuCore:ItemName_helper method lives elsewhere), OpenAllBagsHelper, bag sort machinery (BagSortMenuHelper with collapse + SortByQualityHelper + SortByNameHelper coroutines, SortProcessingSoundHelper ticker), talent helpers (tGetNumTalentGroups, tGetActiveTalentGroup, tSwitchSpec, tGetSpecName, tBuildInactiveSpec, tBuildActiveSpecUI), round.

## Dependencies (outgoing)
- SkuZOptions menu framework — consumes the emitted node tables; relies on SkuOptions.currentMenuPosition / :OnUpdate() / :VocalizeCurrentMenuName() / SkuOptions:IsMenuOpen for refresh + re-pin after actions; SkuCore:CheckFrames re-entry.
- SkuUtil:Unescape (W4 shared escape stripper), global TooltipLines_helper (defined elsewhere in SkuCore), SkuGetCoinText, SkuCore:ItemName_helper and SkuCore:IterateChildren (defined in other SkuCore files), SkuCore:ConfirmButtonShow (confirm popup), SkuCore.maxItemNameLength.
- SkuCore.AuctionHouse:AuctionHouseGetAuctionPriceHistoryData (price history into bag/guild-bank item textFull), SkuCore.EquipmentSets:BuildChilds.
- SkuOptions.Voice (OutputStringBTtts, StopOutputEmptyQueue, TutorialPlaying flag), SkuCore.CursorSilent flag, dprint, SkuLogCombat (optional combat logger).
- SkuDB.questDataTBC / SkuDB.questLookup / SkuDB.questKeys (quest blacklist markers), Sku.Loc, Sku.isTBC, Sku.IsEraSoD.
- SkuSettings (itemSettings.ShowItemQality), SkuOptions.db (indirect).
- WoW APIs: container (GetContainerNumSlots/ItemID/ItemInfo, PickupContainerItem path via .bag/.slot fields, IsBagOpen, OpenBag, C_NewItems), guild bank, trade (GetTrade*ItemInfo/Link, money), talents (GetTalentInfo family, C_SpecializationInfo backport), gossip (C_GossipInfo, SelectGossipOption), C_Engraving, GetStablePetInfo, skill lines (GetNumSkillLines/GetSkillLineInfo/AbandonSkill/ExpandSkillHeader), GameTooltip + SkuScanningTooltip, ITEM_QUALITY_COLORS, InCombatLockdown, hooksecurefunc, C_Timer, loadstring (Blizzard PaperDollFrame_Set* snippets), coroutine.

## Key data structures
- Menu node table (the file's core currency): { frameName, RoC="Child", type ("Button"/"FontString"/"Text"/"string"), obj (live frame or nil), textFirstLine, textFull (string OR array of sections), childs (dual array+hash), func, click, noMenuNumbers, directAction, macrotext, directClickButton, onActionFunc, containerFrameName, liveName (live re-read closure), bag/slot/bagSlot ("bag:slot" stable identity), itemId, stackSize, isNewItem, isBag, isPurchasable }. aParentChilds is always array-of-names + name-keyed hash in the same table.
- tBagSlotList (bagId → localized display name, includes -1 bank / -2 keyring / -3 reagent bank) and tBagSlotListSorted (display order → bagId).
- SkuCore.combatBagOrder — array of {bag, slot} matching the "all items" sorted display order exactly (combat secure /use lockstep).
- SkuCore.combatBagTree — array of {label, items={ {bag,slot}, ... }} per top-level bag view in display order.
- SkuCore.combatCharTree / combatCharStart — flat node array {parent, kids, use ("/use <slotID>" on equipment slot nodes, "" otherwise), down/up/right/left/first/last precomputed neighbour indices}; slot nodes detected by key pattern "^Character.+Slot$"; secure snippet follows pointers only.
- tTradeSkillTypeColor (TWO separate locals with the same name: line 2811 trainer variant, line 3274 tradeskill/craft variant) — {r,g,b} → localized difficulty word, matched against rounded text colors.
- tIsProcessing / tIsProcessingHandle — sort-in-progress counter + 0.5s ticker for the finished-notification sound.

## Events
- SkuCore:PLAYER_TALENT_UPDATE and SkuCore:ACTIVE_TALENT_GROUP_CHANGED are AceEvent handler methods (registration lives in SkuCore's core event wiring, not this file).
- hooksecurefunc(ContainerFrame1, "Hide") — installed lazily on first Build_BagsFrame; hides ContainerFrame2..15 along with it.
- Timers: C_Timer.NewTicker 0.5s (collapse coroutine pump + processing sound) and 0.01s (quality/name sort pumps); many C_Timer.After delays (0.1–1.2s) for popup focus, re-pin, re-vocalize sequencing.
- No direct RegisterEvent / SkuDispatcher / AceComm use in this file.

## Settings keys
- SkuSettings:Sub("SkuCore").itemSettings.ShowItemQality (read; appends "(quality)" to the first tooltip line).

## Entry points
- All Build_*/GossipFrame/QuestFrame/ItemTextFrame functions are called from the SkuCore window pipeline (CheckFrames frame-name → builder mapping) when their Blizzard window is up; none are slash commands or keybinds themselves.
- directClickButton = "CraftCreateButton" (Build_CraftFrame) — the menu's Enter key is bound directly to the real Blizzard button while focused.
- macrotext entries: spec activation (/script C_SpecializationInfo.SetActiveSpecGroup...), profession open (/cast <name>) — routed through the secure ENTER button.
- Blizzard hook: ContainerFrame1 Hide (see Events).

## Invariants & gotchas
- Node tables MUST stay dual array+hash and keys must be unique friendly names; several builders dedupe with " #N" suffixes — collisions silently overwrite the hash part otherwise.
- The gossip menu only attaches click actions when a node has BOTH click==true AND a func — hence the never-called no-op `func = function() end` placeholder on empty bag slots (line ~1190); removing it breaks dropping a held item into an empty slot.
- combatBagOrder/combatBagTree/combatCharTree are the combat lockstep contract with SkuCore/combatMenuKeys.lua: any change to bag "all items" sorting or the character-tree shape must keep these captures in sync (they are re-captured on every build, but shape assumptions — slot key pattern "^Character.+Slot$", view order — are load-bearing).
- Combat guards: OpenAllBagsHelper skips force-open in combat (OpenBag is protected); Build_CharacterFrame skips GearManagerToggleButton:Click in combat; IterateChildren is visibility-gated so the character frame must be shown.
- DoCraft (Build_CraftFrame) is both taint-protected AND hardware-event-gated: /click and :Click() silently no-op; only the directClickButton key→real-button binding works. Same class of constraint as the AH bid arm-gate.
- Bag sort/collapse runs a coroutine pumped by a ticker doing real PickupContainerItem-style clicks; it sets SkuCore.CursorSilent=true and Voice.TutorialPlaying=1 to mute the cursor while shuffling and restores them in the ticker's completion branch — an error mid-coroutine can leave the voice muted.
- Talent stats (TBC branch) execute Blizzard PaperDollFrame_Set* code via loadstring against the shared PlayerStatFrameLeft1 frame; `liveName` closures re-run these on focus — they mutate a real Blizzard frame each read.
- Profession unlearn must open its confirm popup DELAYED (0.5s) because the directAction wrapper synchronously re-anchors + refreshes the menu, which would steal the editbox focus (long comment at ~2580); AbandonSkill needs the skill-line INDEX resolved at confirm time, not the name.
- Talent-switch UX timing: confirmation TTS is delayed 1.2s past the directAction auto re-read; rebuild walks up to the top-level node before OnUpdate.
- Difficulty labels for trainer/tradeskill/craft come from matching ROUNDED text/vertex colors against localized-keyed color tables — locale strings and exact color values are load-bearing.
- "asd" is a sentinel return value of TooltipLines_helper meaning "no tooltip"; comparisons against it look bizarre but are intentional.
- Dual-spec support is gated ONLY on the server-reported talent-group count (Anniversary backport), never on interface version.
