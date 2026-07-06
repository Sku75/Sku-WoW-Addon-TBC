# SkuCore/friends.lua
- Purpose: The "Friends" feature — renders the WoW friend list, Battle.net friend list, ignore/who/guild placeholders as a Sku screen-reader menu ("Social" → Contacts). Each friend entry exposes a submenu: edit note, remove, and (when online) invite + whisper. Toggleable AceAddon submodule of SkuCore (W4 Phase D + Phase E namespace extraction — methods live on the `Friends` module table). OnEnable registers FRIENDLIST_UPDATE and installs a one-time FriendsFrame "Show" hook that redirects the native frame into Sku's menu.

## Public API / exports
- Friends (module table, published as `SkuCore.Friends`); mixes in AceEvent-3.0.
- Friends:OnEnable() — RegisterEvent FRIENDLIST_UPDATE + one-time hooksecurefunc(FriendsFrame,"Show").
- Friends:OnDisable() — UnregisterAllEvents (Show hook stays, guarded by IsEnabled).
- Friends:ONSHOW() — when FriendsFrame opens, navigates Sku menu to short,Local,Social (IsEnabled-guarded).
- Friends:FRIENDLIST_UPDATE() — event handler, currently a no-op stub.
- Friends:FriendsMenuBuilder() — builds the Social menu tree: Contacts (Friend List with add-friend + per-friend entries, Ignore List stub), Who (stub), Guild (stub).

## Dependencies (outgoing)
- LibStub AceAddon-3.0 (SkuCore base) + AceEvent-3.0; SkuCore:RegisterToggleableModule (ModuleManager).
- SkuOptions:InjectMenuItems + SkuGenericMenuItem, SkuOptions:EditBoxShow, SkuOptions:SlashFunc, SkuOptions.currentMenuPosition, SkuOptions:VocalizeCurrentMenuName, SkuOptions.Voice:OutputStringBTtts.
- SkuChat:SetEditboxToCustom (whisper / BN_WHISPER); SkuEpochValueHelper (last-online formatting); Sku.L.
- WoW APIs: C_FriendList (GetNumFriends, GetFriendInfoByIndex, SetFriendNotesByIndex, AddOrRemoveFriend, AddFriend, ShowFriends), C_BattleNet.GetFriendAccountInfo, BNGetNumFriends, BNSetFriendNote, BNRemoveFriend, BNInviteFriend, C_PartyInfo.InviteUnit / InviteUnit, FriendsFrame, C_Timer.After, PlaySound(89).

## Key data structures
- Menu entries built via InjectMenuItems: dynamic entries with .textFull (multiline friend detail string built with \r\n), .BuildChildren (lazy submenu), .isSelect + .OnAction (leaf actions), .sorting (Friend List sortable).
- Friend info shape documented inline: C_FriendList.GetFriendInfoByIndex fields and the large C_BattleNet BNetAccountInfo/BNetGameAccountInfo/BNET_CLIENT reference block (comment-only).
- gShowHookInstalled — file-local bool ensuring the permanent Show hook installs once.

## Events
- WoW event via AceEvent: FRIENDLIST_UPDATE (handler is a no-op).
- hooksecurefunc(FriendsFrame, "Show") — permanent, installed once.
- Timers: C_Timer.After(0.65,...) to re-select parent menu + re-vocalize after note/remove/add; C_Timer.After(0.1,...) for the edit-box prompt voice.
- No AceComm, no SkuDispatcher.

## Settings keys
- none read/written directly. Toggle on/off state persisted by RegisterToggleableModule.

## Entry points
- FriendsMenuBuilder is referenced from SkuCore/Options.lua (the "Social" build), reached in-menu under Local→Social.
- Auto-open: FriendsFrame:Show hook navigates into the Sku Social menu.
- Features menu toggle node (label "Freunde"/"Friends").

## Invariants & gotchas
- tAddWowFriend / tAddBnetFriend are each called TWICE per build — once with aOnline=true then again with false — so online friends list before offline; the online/offline branch inside each guards on info.connected/isOnline matching aOnline. Editing the loop order changes the online-first grouping.
- The FRIENDLIST_UPDATE handler is a dead no-op stub — registered but does nothing; cleanup/refresh-live candidate.
- BNet invite logic (aOnline branch) is the fixed path noted in comments: earlier there was no BNet invite branch; now it assembles characterName-realmName or falls back to BNInviteFriend / "friend not playing wow" voice.
- Ignore List, Who, and Guild are "noch nicht implementiert" placeholder leaves — incomplete features.
- OnAction callbacks reach into SkuOptions.currentMenuPosition.parent(.parent) to re-select after an async C_FriendList mutation (0.65s settle) — depends on menu-position stability; the double .parent in the remove path vs single in edit-note path is intentional (different depth).
- `tNewMenuEntry` local is shadowed/re-declared many times within tAddFriendSubmenu and FriendsMenuBuilder — harmless but noisy; the last binding wins.
