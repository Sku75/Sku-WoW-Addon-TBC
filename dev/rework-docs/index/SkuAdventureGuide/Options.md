# SkuAdventureGuide/Options.lua
- Purpose: Options table + defaults for SkuAdventureGuide, and the wiki menu builder. MenuBuilder injects a "Wiki" node with dynamic children (Link History + All entries), each rendering wiki articles via SkuOptions:FormatAndBuildSectionTable, plus an "Options" node from the options args.

## Public API / exports
- SkuAdventureGuide.options — AceConfig group: formatEnumsInArticles (toggle), history (soundOnNewLinkInHistory select, ignoreSeenLinks toggle), links (enableLinksInTooltips toggle, tooltipLinksIndicator select). Uses explicit get/set into SkuOptions.db.profile[MODULE_NAME].
- SkuAdventureGuide.defaults — defaults for the above (soundOnNewLinkInHistory = "sound-notification15").
- SkuAdventureGuide:MenuBuilder(aParentEntry) — builds Wiki (dynamic) -> {Link History, All entries} + Options; each article entry's OnEnter sets currentMenuPosition.textFull from the wiki data, following redirects via GetLinkFinalRedirectTarget.

## Dependencies (outgoing)
- SkuOptions:InjectMenuItems, SkuGenericMenuItem, SkuOptions:IterateOptionsArgs, SkuOptions:GetLinkFinalRedirectTarget, SkuOptions:FormatAndBuildSectionTable, SkuOptions.currentMenuPosition.
- SkuDB.Wiki[Sku.Loc].lookup / .data; Sku.L, Sku.Loc; SkuAdventureGuide.linkHistory (from Core).
- string.lower.

## Key data structures
- Menu entries flagged dynamic + sorting with BuildChildren closures; History iterates linkHistory newest-first, All entries iterates the whole Wiki data table.
- References SkuAdventureGuide.HistoryNotifySounds (defined in Core) for the sound select values.

## Events
- none (pure menu/options definition).

## Settings keys
- SkuOptions.db.profile[MODULE_NAME] (profile scope): formatEnumsInArticles, history.soundOnNewLinkInHistory, history.ignoreSeenLinks, links.enableLinksInTooltips, links.tooltipLinksIndicator. (No SkuSettings:Register here — still uses raw db.profile get/set, unlike the W1/W2-migrated modules.)

## Entry points
- Menu node: "Wiki" (dynamic) with Link History / All entries article browsers + "Options".

## Invariants & gotchas
- This module still uses direct SkuOptions.db.profile get/set closures and has NO SkuSettings:Register schema — it was not migrated in W1/W2 like SkuMob/SkuQuest. Cleanup candidate for schema consistency.
- History and All-entries BuildChildren are near-identical copy-paste blocks (only the source iteration differs: linkHistory vs Wiki.data); consolidatable.
- Commented-out globalLinkListOnly option remains in the args table (dead).
- Article OnEnter relies on SkuDB.Wiki[Sku.Loc].data[link].content being a non-empty, non-"\r\n" string — guarded, but redirect resolution assumes GetLinkFinalRedirectTarget never loops.
