# Turn to beacon: what Sku measured, and what WowVision can take from it

Written 2026-09-21 after a day of in-game measurement on the TBC Anniversary
client (2.5.6), about 450 measured turns at 80 to 106 frames per second, on
foot and mounted. Input for the WowVision `port-sku-feature` skill: WowVision
already HAS a turn to waypoint (`core/navigation/maps/turnTo.lua`), so this is
an "extend what exists" port, not a new feature. Everything here is facts and
ideas. Sku is GPLv3: carry over knowledge, never code.

Sku implementation: `GameWorldObjects:TurnToWorldPosition` in
`Sku/SkuCore/gameWorldObjects.lua` (turn core, calibration, logging) and the
pitch lock in `Sku/SkuCore/Core.lua` (`SkuCore:TogglePitchLock`,
`SkuCore:PitchLockLevelPulse`, the automatic tick below them). Commits
`62e6b62` and `ccb4c00` and the one carrying this file.

## The shared mechanism

Addons cannot turn the character (`TurnLeftStart`, `TurnRightStart` and
`SetFacing` are protected; Sku tried a closed loop with them on 2026-08-29 and
got `ADDON_ACTION_FORBIDDEN`). Both addons rotate the CAMERA with
`MoveViewLeftStart` / `MoveViewRightStart`, stop it after a timer, then fire
`MouselookStart()` and `MouselookStop()` in the same frame. That pulse snaps
the character's facing to the camera yaw. It works in combat.

## Measured engine facts (the valuable part)

1. `cameraYawMoveSpeed` has NO effect above 360. CVar values 376, 453 and 731
   all turned about 88 degrees in a 0.25 second timer; "1440" turned 40
   degrees in 115 ms. Real speed at CVar 360 or more and argument 1 is about
   355 degrees per second.
2. The argument of `MoveViewLeftStart(factor)` multiplies the CVar and is NOT
   capped at 360. CVar 360 with factor 4 really turns at 1300 to 1400 degrees
   per second. Fractional factors work (1.6, 2.36 and so on). WowVision already
   uses this (CVar 400, factor 4). Note that its CVar 400 is above the cap, so
   the real base is about 355, not 400, and the real fast tier is about 1400,
   not 1600. The self-calibration absorbs that, the assumed constants are just
   wrong by that much before the first fit.
3. The camera has MOMENTUM. After `MoveViewXStop` it glides on; at top speed
   the glide is worth roughly 30 degrees. A single sweep is still repeatable,
   because the glide is the same every time and any calibration learns it as
   part of the sweep. But any command issued DURING the glide is poison: a
   reverse command meant to take back 4 to 6 degrees cost about 35, a forward
   command meant to add 2 to 5 degrees overshot by 7 to 21. WowVision's
   `SETTLE_DELAY` comment describes the same ease-out. Consequence: no
   braking, no in-press correction sweep, unless you first wait for the glide
   to end (about 100 ms). Sku built the in-press correction, measured it,
   and removed it the same day.
4. The stop lands on a frame boundary. Stop scatter is plus or minus half a
   frame time multiplied by the sweep speed: at 1440 degrees per second and
   100 fps about 7 degrees, at 30 fps about 24. No calibration can remove it,
   only a lower speed can. Measured spread of real speed over asked speed on
   big turns: about 3 percent.
5. The mouselook pulse applies the new facing one frame LATER. Reading
   `GetPlayerFacing()` right after `MouselookStop()` returns the old value.
   Both projects found this independently. A key press that arrives in that
   gap computes its bearing from the stale facing and commands the same turn
   again. Sku's busy guard therefore covers the timer plus a settle of 0.1
   seconds or 3 frames, whichever is longer.
6. Start and stop lag of a sweep from rest is small, about minus 5 to minus
   15 ms (the camera needs a moment to get going). For sweeps under about
   40 ms the real speed is clearly below the asked speed (ratio 0.4 to 0.8),
   so small turns need their own fit, or a fit with an intercept.
7. Standing and moving turns fall on the same calibration line. The follow
   camera (`cameraSmoothStyle` 2) does not disturb a sweep of up to 0.25
   seconds. WowVision excludes moving turns from calibration; on a route
   that means it almost never learns. Sku counts them.
8. A turn that ends slightly past 180 degrees reads as minus 179 when the
   facing difference is wrapped naively. Pick the full-circle equivalent
   nearest to the asked angle.
9. Swimming and flying: the pulse also copies the camera PITCH onto the
   character. The camera always looks slightly down, so every pulse is a
   small dive. Confirmed without any addon: a bare right mouse click while
   swimming dives you. There is no getter for camera or character pitch on
   this client (`GetUnitPitch` missing, `UnitPosition` height is always 0,
   `GetCVar("pitchLimit")` returns nil).
10. `ConsoleExec("pitchlimit 0")` caps how far the character can pitch while
    moving, `pitchlimit 88` restores it. It works IN COMBAT (probed in game
    2026-09-21, no blocked-action error). Sku's automatic lock used to wait
    for combat to end on an untested assumption; the log showed 6 seconds of
    unlocked swimming with three turn pulses, which was the dive on entering
    water in a fight.
11. The lock is a cap, not a leveller: it holds whatever tilt exists. To
    re-level, put the camera into a known near-level attitude
    (`ResetView(slot)` then `SetView(slot)` on a scratch slot) and fire one
    pulse. That pulse must come at least about 0.5 seconds after a turn's
    own pulse, or it transfers the old yaw and undoes the turn. Interact to
    move pierces the lock (engine-steered descent); re-level when the NPC
    window opens, and on the ascend and descend keys.
12. `pitchlimit 0` also caps the VIEW pitch on land. A partially sighted
    player cannot tilt the camera with it on. Engage it only while swimming
    or flying, never on taxis (`UnitOnTaxi`), and keep a user toggle.

## What Sku does now (design, not code)

- Rest zone: bearing within 3 degrees does nothing at all. No sweep, no
  pulse. Ends the swinging around the beacon ping and saves dive nudges.
  WowVision has the 3 degree tolerance but fires its alignment pulse first.
- One pulse per turn. Camera and character are aligned at the start with a
  camera snap (`SetView(2)`, Sku's own saved view), not with a pulse.
- Two gears: CVar alone up to 360, above that CVar 360 times a factor up to
  1440 degrees per second. Per gear the model is
  turned = k * asked speed * (timer + L). k from the median ratio from the
  first sample on; from 8 samples with spread durations a line fit for k and
  L. Samples are stored per machine (account-wide), 80 in a ring.
- Speed follows the frame rate. Allowed stop scatter J is 3 degrees, or 6
  percent of the angle for big turns; speed = 2 * J * fps, capped at 1440.
  Never slower than angle divided by 0.25 seconds. Slowed down when the timer
  would be shorter than 2 frames, because such an angle cannot be hit
  otherwise.
- Safety: if the factor turns out not to multiply on a client (6 fast
  samples still under 450 real), the fast gear retires itself for good.
- A press during a running turn is ignored, never restarts the turn.
- Lead compensation while moving: aim at the bearing the waypoint will have
  when the turn lands. Predict the position ahead by speed times (planned
  timer + 0.05 s) along the facing, clamp the lead to half the remaining
  distance so the aim never goes behind the waypoint. Measured: it only
  matters within about 5 yards (median landing error 2.5 instead of 4.2
  degrees on foot and mounted, 7 instead of 16 in the first mounted run),
  and is neutral to slightly positive beyond. The old 0.15 s buffer aimed
  about 30 percent too far.
- What killed the orbiting around close waypoints was mostly speed and
  precision (press to landing 0.3 s down to 0.1 s), the lead is the
  close-range helper. Expect it to matter more at epic flying speed
  (27 to 29 yards per second, not measured) and on slow machines where the
  timer runs the full 0.25 seconds.

## Measured results on the test machine (about 97 fps)

- Under 10 degrees: mean error 1.8, worst 4.3, timer about 22 ms.
- 10 to 30 degrees: mean error 1.9.
- 30 to 90 degrees: mean error 2.3, timer about 85 ms.
- Over 90 degrees: mean error 3.1 after the calibration matured (about 5
  while learning), worst 7.5, timer about 100 to 130 ms.
- Before: every press was capped at about 88 degrees, a half turn always
  took two presses and 0.25 seconds each.

## Planned behaviour at other frame rates (from the planner, not measured)

Angle, then planned speed, timer and stop scatter.

- 20 fps: 15 degrees at 120 per second, 130 ms, plus or minus 3. 45 degrees
  at 180, 255 ms, plus or minus 4.5. 180 degrees at 720, 255 ms, plus or
  minus 18.
- 30 fps: 15 degrees at 180, 88 ms, plus or minus 3. 45 degrees at 180,
  255 ms, plus or minus 3. 180 degrees at 720, 255 ms, plus or minus 12.
- 60 fps: 15 degrees at 360, 46 ms. 45 degrees at 360, 130 ms. 180 degrees
  at 1296, 143 ms, plus or minus 11.
- 144 fps: 45 degrees at 864, 57 ms. 180 degrees at 1440, 130 ms, plus or
  minus 5.

The 0.25 second floor is the point where a slow machine stops buying
precision with time and accepts a second press instead. `/console maxfps 30`
reproduces a slow machine for testing.

## Findings in WowVision's turnTo.lua (as of its 2026-07-19 state)

1. No dive guard of any kind. No `pitchlimit`, no level pulse, no swim or fly
   check in the turn code. Facts 9 to 12 above are the fix.
2. Two pulses per turn (align first, land at the end). Each pulse is a dive
   nudge in water, and the first one copies whatever pitch the user's camera
   happens to have. Replacing the alignment pulse costs a dependency on a
   camera view slot; WowVision chose the pulse deliberately to avoid that.
   With a pitch lock in place the second pulse is harmless, so fix 1 first
   and then decide.
3. Restart bug. `turnToWaypoint` cancels a running turn and starts a new one,
   but the OLD sweep's `C_Timer.After(duration, ...)` callback calls
   `stopCamera()` without checking that it still owns the turn, so it stops
   the NEW sweep mid-flight. The old settle callback then only checks
   `turning == nil`, takes the NEW state as `current`, snaps early, records a
   calibration sample with the wrong duration, and ends the new turn. Quick
   double presses therefore corrupt the calibration. Guard every callback
   with `turning ~= state`, or ignore presses while a turn runs.
4. No lead compensation, while turning on the move is allowed. Expect stable
   orbits around close waypoints, worst when mounted or flying.
5. Moving turns are excluded from calibration (see fact 7): on routes it
   never learns.
6. Slow tier is fixed at CVar 400 (really about 355, see fact 2): a 129
   degree turn takes about 0.3 seconds plus 0.1 settle plus two waits of
   0.05, about half a second in all. Sku measured that a habitual second
   press lands inside turns longer than about 0.25 seconds. The fast tier
   only starts at 130 degrees because of its measured floor of about 95
   degrees; a speed that follows the angle (factor between 1 and 4) removes
   the gap between the tiers.
7. Fixed speeds ignore the frame rate. At 30 fps the fast tier scatters by
   about plus or minus 27 degrees.
8. The 180 degree wrap (fact 8) is not handled in the `turned` measurement.

## What Sku took from WowVision

The MoveView factor for real speed, and the idea of measuring every turn and
fitting the result. Both were right, and Sku's own 1440 had never been real.

## Suggested test plan for a WowVision port

1. Standing: 10 big turns (over 90 degrees), 10 small ones. After a few
   learning presses a second press should be skipped as already facing.
2. Double press quickly on a big turn: the turn must still land, and the
   calibration dump must not show a sample with an absurd duration.
3. Ride past a waypoint at under 5 yards while pressing: no circling.
4. Enter water during a fight and press the key several times: you must stay
   at the surface. Swim a route with turns: no creeping dive.
5. `/console maxfps 30`, repeat 1 and 3.
