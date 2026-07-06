# SkuCore/updateCheck.lua
- Purpose: Voice "a newer Sku is available" nudge without any internet access. Sku users all share the "SkuChat" channel, so version numbers are exchanged as hidden addon messages (SendAddonMessage CHANNEL distribution). Uses a Trickle/RFC-6206-style suppression scheme so a channel of N users emits only ~K messages per interval. A user-toggleable AceAddon submodule (`SkuCore.UpdateCheck`); the external Sku Updater EXE does the actual update.

## Public API / exports
- `UpdateCheck:OnEnable()` — register events, register the comm prefix, start the 1s clock ticker, schedule the first (delayed, randomized) announce attempt.
- `UpdateCheck:OnDisable()` — unregister events, cancel the clock ticker (pending timers no-op via IsEnabled guards).
- (module-local) GetOwnVersionString, ParseVersion, CompareVersions, Announce, RememberHint, ChannelId, MaybeAnnounceVersion, ScheduleSteady, OnPeerVersion, Now, Trace.

## Dependencies (outgoing)
- C_ChatInfo.SendAddonMessage / RegisterAddonMessagePrefix, GetChannelName, C_Timer (After/NewTicker), C_AddOns.GetAddOnMetadata (or GetAddOnMetadata), UnitAffectingCombat.
- SkuOptions.Voice:OutputStringBTtts, SkuOptionsDB (SavedVariables), dprint. Relies on SkuChat joining the permanent "SkuChat" channel.

## Key data structures
- Module-local state: _heardConsistent (peers >= own version this window), _highestSeen, _lastSentAt, _nudgedThisSession, _now (ticker-maintained clock), _clockTicker, _booted.
- Tunable constants: FIRST_ANNOUNCE_MIN/MAX, STEADY_MIN/MAX, QUICK_MIN/MAX, REDUNDANCY_K=1, MIN_SEND_GAP=60.
- COMM_PREFIX = "SkuVer", CHANNEL_NAME = "SkuChat".

## Events
- WoW (on a private CreateFrame): PLAYER_ENTERING_WORLD (boot-once session seed), CHAT_MSG_ADDON (filter prefix → OnPeerVersion).
- AceComm-style prefix registered via C_ChatInfo.RegisterAddonMessagePrefix("SkuVer").
- Timers: 1s clock ticker; C_Timer.After for first announce, steady re-schedule loop, and quick suppressed replies.

## Settings keys
- SkuOptionsDB.updateHint = { latestSeen, ownVersion } — persisted hint for the external updater (SavedVariables, not a Sub scope).

## Entry points
- Slash `/skuver` — prints + logs status and does a one-off test broadcast. Feature toggle via RegisterToggleableModule. No keybind/menu.

## Invariants & gotchas
- Multiple TODO(review) markers in-file: no user-facing toggle beyond the Features menu, unlocalized English announce string (line 122), unconfirmed SavedVariables table, untuned cadence constants.
- The driver `frame` is created at file scope and reused across enable/disable (not destroyed); _booted is session-global so PEW seeding runs once per session, not per enable.
- Suppression correctness depends on SkuChat actually being joined (ChannelId()==0 means silent no-op) and on all peers using the same COMM_PREFIX/channel.
- Announce guards on not-in-combat and _nudgedThisSession (once per session only).
