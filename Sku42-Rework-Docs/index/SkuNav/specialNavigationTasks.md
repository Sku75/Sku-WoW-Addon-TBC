# SkuNav/specialNavigationTasks.lua
- Purpose: "Navigation mode without coordinates" — a small step-sequencer that guides the player through scripted movement tasks (turn to heading, move forward for N seconds, ascend, pitch to angle) in places where world coordinates are unavailable or useless, mainly vehicle/taxi-style sequences. Tasks are defined as data in SkuDB.Tasks; start/end are triggered by matching arbitrary trigger strings (events, or strings sent from elsewhere), and progress is driven by the player's movement key events. Also announces vehicle health/power/pitch changes by voice.

## Public API / exports
- SkuNav:NavigationModeWoCoordinatesCheckTaskTrigger(aStringToCheck, arg1, arg2) — matches the (unescaped) string against SkuDB.Tasks keys (start) and the current task's endTriggers (abort); callable from anywhere with any string.
- SkuNav:NavigationModeWoCoordinatesNextStep(aTaskId, aStart, aStop) — state machine: start a task, advance to next step (announcing the instruction by voice + chat print), or stop/reset; announces completion after the last step.
- SkuNav:NavigationModeWoCoordinates_ON_MOVEMENT(aTriggerName) — evaluates movement trigger names (TurnLeft/Right, MoveForward, JumpOrAscend Start/Stop...) against the current step's triggers; measures forward/up durations via GetTimePreciseSec and auto-advances when the remaining value reaches ~0 or the heading/pitch is within tolerance.
- SkuNav:NavigationModeWoCoordinatesRecordForwardStart/Stop() and RecordForward/RecordUp(aTriggerName) — recording helpers that accumulate movement durations (for authoring task data; results only ever printed, print commented out).
- NavigationModeWoCoordinatesGetDirection() — GLOBAL helper (no SkuNav namespace) returning the player heading in degrees via SkuNav:GetDirectionTo.

## Dependencies (outgoing)
- SkuDB.Tasks (task definitions), SkuNav:GetDirectionTo (Core.lua), SkuUtil:Unescape, SkuOptions.Voice (OutputString sound + OutputStringBTtts speech), Sku.L.
- WoW API: CreateFrame, UnitPosition, UnitPower/UnitPowerMax/UnitHealth/UnitHealthMax("vehicle"), GetTimePreciseSec.

## Key data structures
- SkuDB.Tasks[taskName] = array of steps { action = "turn"|"forward"|"up"|"pitch"|"pitchEndless", value = degrees|seconds|pitch, triggers = {movement trigger names}, comment }, plus .endTriggers = {abort strings}; task START is matched by string.find of the incoming trigger string against the task's table KEY.
- File-local state: tCurrentTask, tCurrentStep (0 = idle), tCurrentMovementStartAt, tCurrentMovementLeft (seconds remaining, -1 idle), tPitch/tVHealth/tVPower (last announced vehicle values); recording pair tCurrentMovementStartAtRec/tCurrentMovementDone.
- Tolerances: turn ±2 degrees, pitch ±0.02, movement done at <= 0.04 s left; vehicle announce thresholds 10% power / 5% health.

## Events
- Control frame SkuNavNavigationModeWoCoordinatesControl registers LOADING_SCREEN_ENABLED, VEHICLE_ANGLE_UPDATE, UNIT_POWER_FREQUENT, UNIT_HEALTH_FREQUENT, UNIT_EXITED_VEHICLE (raw registration, not via SkuDispatcher); every event is also funneled into CheckTaskTrigger as a potential start/end trigger string.
- Movement triggers arrive as calls to NavigationModeWoCoordinates_ON_MOVEMENT from SkuNav's movement-key hooks elsewhere.

## Settings keys
- none

## Entry points
- No slash commands/keybinds here; entered via the event frame and via other modules calling CheckTaskTrigger / _ON_MOVEMENT with trigger strings.

## Invariants & gotchas
- Task keys double as start-trigger substrings (string.find(aStringToCheck, i)) — task names containing Lua pattern magic characters would misbehave; incoming strings are SkuUtil:Unescape'd first.
- CheckTaskTrigger restarts matching tasks unconditionally: a matching start trigger first force-stops (NextStep aStop) then starts fresh.
- "up" measurement pairs JumpOrAscendStart with AscendStop (not JumpOrAscendStop) — asymmetric on purpose.
- SkuNav is re-created defensively at top (SkuNav = SkuNav or NewAddon...) — same idiom repeated in several SkuNav files; load order tolerant but means AceAddon name collision if ever loaded standalone.
- NavigationModeWoCoordinatesGetDirection leaks into the global namespace without a Sku prefix.
