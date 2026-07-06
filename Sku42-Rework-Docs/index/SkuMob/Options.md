# SkuMob/Options.lua
- Purpose: Settings schema + defaults for SkuMob, plus the target/context action menu builder (SkuMob:MenuBuilder). W7: the module's top-level menu entry IS the target action menu (dynamic API list rebuilt per open against the current target), and the plain option toggles moved to Einstellungen -> Sonstiges. Contains a large commented-out block of the old Retail MenuUtil-mirror target menu (dead, kept as backup).

## Public API / exports
- SkuMob.options — AceConfig-style options table (toggles + InCombatSound select). W2-MC1: get/set removed on plain nodes (schema-managed via SkuSettings).
- SkuMob.defaults — default values table.
- SkuMob:CreateAndUpdateSkuMenuFrame() — intentionally EMPTY stub (old Retail-mirror path disabled; SkuCore:CheckFrames still calls it each tick).
- SkuMob:MenuBuilder(aParentEntry) — builds the target action menu via file-local tBuildTargetMenu.
- SkuSettings:Register("SkuMob", {...}) — declares all keys (profile scope), including enemyCombatStatusMode not present in the options args.

## Dependencies (outgoing)
- SkuOptions:InjectMenuItems, SkuGenericMenuItem, SkuOptions:IterateOptionsArgs, SkuOptions:CloseMenu, SkuOptions:EditBoxShow, SkuOptions.Voice:OutputStringBTtts.
- SkuSettings:Register / :Sub; SkuState:IsInCombat; SkuCore:ConfirmButtonShow; Sku.L.
- WoW APIs via a defensive tCall wrapper: InspectUnit, FollowUnit, InitiateTrade, StartDuel, InviteUnit/C_PartyInfo.InviteUnit, C_FriendList.AddFriend/AddOrDelIgnore, PromoteToLeader, UninviteUnit, SetRaidTarget, ReportPlayer, SetLootMethod, Pet{Aggressive,Defensive,Passive}Mode/PetAttack/PetFollow/PetAbandon/PetRename, ResetInstances, LeaveParty, FocusUnit, InteractUnit.

## Key data structures
- SkuMob.InCombatSounds — seeded here with just the default beep (Core rebuilds it).
- File-local tables: tRaidMarkers [0..8], tReportReasons, tLootMethods (label+method), each feeding a dynamic submenu builder.
- SkuMob.pendingPetRename — stashed sanitized name when PetRename fails (needs a secure /run retry).

## Events
- Timers: C_Timer.After for pet-rename prompt (0.3s), PetRelease confirm re-announce (0.5s). No WoW events registered in this file.

## Settings keys
- Registered profile-scope keys: enable, vocalizeRaidTargetOnly, dontVocalizePlayerReactionAndLevelInCombat, vocalizePlayerNamePlaceholders, vocalizePlayerNamePlaceholdersSkuTts, repeatRaidTargetMarkers, autoSetSkuRaidTargetsToInCombatCreatures, InCombatSound, enemyCombatStatusMode.

## Entry points
- Menu node: SkuMob:MenuBuilder = the target menu (top-level module entry). Branches by target kind: other player (inspect/follow/trade/duel/whisper/invite/friend/ignore/leader actions/report/raid-marker), own pet (hunter vs warlock/other — attack/recall/dismiss/release/rename/pet-mode), self or no target (reset instances/leave group/loot method/raid-marker), NPC (raid-marker only).
- Secure macros: PetDismiss ("/petdismiss"), PetRename ('/run PetRename(...)') use secureMacro to avoid ADDON_ACTION_FORBIDDEN.

## Invariants & gotchas
- Large commented-out old-menu block (lines ~101-189) is dead code kept as documented backup — CreateAndUpdateSkuMenuFrame is now a no-op stub but still called every tick by SkuCore:CheckFrames.
- Pet actions are duplicated between the HUNTER branch and the warlock/other branch (PetDismiss "do...end" block copy-pasted twice).
- PetAbandon is permanent — release path requires SkuCore:ConfirmButtonShow; guarded but a future editor must keep the confirm.
- tCall wraps every WoW API in pcall for TBC-vs-modern API drift; report/friend/ignore also branch C_FriendList vs legacy globals.
- The old commented builder used SkuSettings:Sub("SkuMob") for IterateOptionsArgs; the live path moved those toggles into SkuCore's Sonstiges menu, so this file's options args are only consumed elsewhere.
