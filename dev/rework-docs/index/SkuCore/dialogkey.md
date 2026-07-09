# SkuCore/dialogkey.lua
- Purpose: The "Dialog key" feature — a hidden keyboard-driver frame that lets SPACE accept/complete/continue quests and pick gossip options, and number keys 1-9 select a quest reward, without touching the mouse. Reads live Blizzard quest/gossip frames and clicks the appropriate button. Runs as a toggleable AceAddon submodule of SkuCore (W4 Phase D); OnEnable creates+shows the driver frame, OnDisable hides+disables it.

## Public API / exports
- DialogKey (module table, published as `SkuCore.DialogKey`) — the AceAddon submodule handle.
- DialogKey:OnEnable() — creates (idempotent) and shows/enables the OnKeyDown driver frame.
- DialogKey:OnDisable() — disables keyboard + hides the frame so it swallows nothing.
- DialogKey:DialogKeyLogin() — legacy entry point; just calls the frame creator (kept for compatibility).

## Dependencies (outgoing)
- LibStub AceAddon-3.0 (SkuCore base).
- SkuCore.inCombat flag; SkuCore:RegisterToggleableModule (ModuleManager).
- SkuUtil:Unescape (strip color codes from quest button text).
- SkuQuest:CheckQuestProgress (decide whether an active quest is completable before auto-clicking it).
- WoW APIs/frames: CreateFrame, EnableKeyboard, SetPropagateKeyboardInput, PlaySound(847), UIParent; Blizzard quest/gossip frames — QuestFrameAcceptButton, QuestFrameCompleteButton, QuestFrameCompleteQuestButton, GossipFrame.GreetingPanel.ScrollBox, QuestFrameGreetingPanel, QuestTitleButton1..10, QuestInfoRewardsFrameQuestInfoItem1..9.

## Key data structures
- DialogkeyControlFrame — module-private single hidden Frame, EnableKeyboard(true) + SetPropagateKeyboardInput(true), reused across enable/disable cycles.
- Per-keystroke locals: tActiveQuests / tAvailableQuests / tGossipOptions (index→button) + tHas* flags, built by scanning the gossip ScrollBox element data (buttonType 3=gossip, 4=active quest, 5=available quest) and the classic QuestTitleButton list.

## Events
- No WoW events registered, no SkuDispatcher subscriptions, no AceComm, no timers. Input arrives via the frame's OnKeyDown script only.

## Settings keys
- Toggle on/off state persisted by RegisterToggleableModule (ModuleManager). No other db reads/writes.

## Entry points
- The hidden OnKeyDown driver frame is the entry surface (SPACE and 1-9 handled). SetPropagateKeyboardInput(true) means keys still pass through to the game.
- Features menu toggle node (label "Dialogtaste"/"Dialog key").

## Invariants & gotchas
- OnKeyDown guards: no-op if not IsEnabled() or if SkuCore.inCombat — do not remove these or the frame will click protected buttons in combat.
- SPACE priority order is hardcoded: active quests first, then available, then gossip options — the first matching entry (lowest index in a 1..20 scan) is clicked and the loop breaks.
- Gossip scan reaches deep into Blizzard internals: `GossipFrame.GreetingPanel.ScrollBox:GetChildren()` then that child's `:GetChildren()` and each button's `:GetElementData()` — fragile against Blizzard UI changes.
- DialogKeyLogin() is now redundant with OnEnable (both just call DialogkeyCreateControlFrame) — legacy shim, cleanup candidate.
