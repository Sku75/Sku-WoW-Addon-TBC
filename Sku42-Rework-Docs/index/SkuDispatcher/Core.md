# SkuDispatcher/Core.lua
- Purpose: The addon's central event broker. Modules register callbacks here for a named event (either a real WoW event name or a synthetic `SKU_*` event) instead of wiring `RegisterEvent` themselves. On the first callback for a real WoW event, the dispatcher registers that event with itself; a single generated per-event handler then fans the event out to every registered callback. It is a tiny AceAddon (AceConsole/AceEvent) with no features of its own beyond this fan-out.

## Public API / exports
- `SkuDispatcher` — global AceAddon object ("SkuDispatcher").
- `SkuDispatcher.Registered` — table keyed by event name of `{handler, callbacks}` registration records.
- `SkuDispatcher:RegisterEventCallback(aEventName, aCallbackFunc, aOnlyOneCallbackFlag)` — subscribe a callback to an event; on first subscription for a non-`SKU_` name it also `RegisterEvent`s the real WoW event. `aOnlyOneCallbackFlag=true` makes it fire once then auto-unregister.
- `SkuDispatcher:UnregisterEventCallback(aEventName, aCallbackFunc)` — remove a callback; when the last callback for a real WoW event is gone it `UnregisterEvent`s and drops the record.
- `SkuDispatcher:TriggerSkuEvent(aEventName, ...)` — manually fire an event's handler (the publish side for synthetic `SKU_*` events); no-op if nothing is registered.
- `SkuDispatcher:OnInitialize()` / `:OnEnable()` / `:OnDisable()` — Ace lifecycle stubs, all empty.

## Dependencies (outgoing)
- LibStub `AceAddon-3.0`, `AceConsole-3.0`, `AceEvent-3.0` (the `RegisterEvent`/`UnregisterEvent` methods come from AceEvent).
- Globals: `Sku.L` (assigned to local `L` but unused here), `dprint` (logger, on the no-registered-callback error path).

## Key data structures
- `SkuDispatcher.Registered[aEventName] = {handler = <fn>, callbacks = {[fn] = onlyOnceFlag}}` — `callbacks` is a set keyed by the callback function itself, value is the per-callback "fire once" boolean.
- `SkuDispatcher[aEventName]` — the generated dispatch closure, also serves as the AceEvent handler method name for real events (AceEvent calls `self[event](self, event, ...)`).

## Events
- Registers ANY WoW event on demand via AceEvent `RegisterEvent(aEventName)` — only for names not starting with `SKU_`. Synthetic `SKU_*` events are never registered with WoW; they only fire through `TriggerSkuEvent`.
- No fixed event list, no AceComm, no timers of its own.

## Settings keys
- none

## Entry points
- none directly (no slash commands/keybinds). It is the injection point every other module publishes/subscribes through.

## Invariants & gotchas
- The dispatch closure (lines 61-68) is created once per event name and closes over `aEventName`; it iterates `SkuDispatcher.Registered[aEventName].callbacks` live and may unregister a callback mid-iteration (the fire-once path). Removing the map entry during `pairs` is the auto-unregister mechanism — editors must keep that record present until the loop reads it.
- `callbacks` is keyed by the function value, so the same function cannot be registered twice for one event, and unregister needs the exact same function reference.
- The `for i,v in pairs(...) do return end` block in `UnregisterEventCallback` (lines 45-47) is a "is the table non-empty?" probe: it returns early if ANY callback remains. Non-obvious idiom.
- The generated handler is invoked two ways with different arg shapes: AceEvent calls it as `(self, event, ...)`, and `TriggerSkuEvent` calls it as `(SkuDispatcher, aEventName, ...)` — callbacks receive `self, eventName, ...` in both. Callbacks must tolerate that signature.
- Real WoW events get unregistered when their last callback leaves, but the generated `SkuDispatcher[aEventName]` closure is also niled — re-subscribing rebuilds it.
