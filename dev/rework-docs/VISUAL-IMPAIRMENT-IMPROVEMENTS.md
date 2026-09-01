# Low vision in Sku — what is still open

Date: 2026-09-01. Written after the v43.2 visual-aids pass, which came out of
reports that partially sighted players struggle with the bags and with Sku's
menus in general.

Sku is built for **blind** users, and that is the right priority. But a real part
of the user base has residual sight, and for them Sku currently does very little
on purpose and a few things against them by accident. This file lists what was
**not** done, so the next pass does not have to re-derive it.

Shipped in v43.2 (not repeated below): nameplate-colour arming at login, the
reading bar in combat and showing the full spoken line, a configurable text
window (font/size/colour pair/opacity/outline) plus font and colour choices for
the reading bar, and the native `Namensplaketten` CVar menu. See the v43.2 patch
notes.

★ Nothing here is verified by sight. Everything visual in this file needs a
tester with residual vision; the author of the code and the maintainer are both
blind, so "it looks right" is not a check either of us can perform. Prefer
changes whose effect can also be confirmed from a log, a CVar read-back or a
`/run` probe.

---

## 1. The text window still cannot show where you are

**Biggest remaining item.** `SkuTTS:Output` (`Libs/SkuTTS-1.0/SkuTTS-1.0.lua`)
writes the whole text into the FontString **once** and never touches it again.
`NextLine` / `PreviousLine` / `ReadLineNumber` move only the *speech* cursor. So
a partially sighted user reading a quest has no visual indication of which line
is being spoken — the text just sits there.

Two things need doing, and they are related:

- **Highlight the current line.** The section and line indices already exist in
  `ReadLineNumber`; what is missing is re-rendering the display string with the
  active line wrapped in a colour code (or a highlight texture positioned behind
  it). Needs a render function that can be called on every line move rather than
  only from `Output`.
- **Deal with clipping.** The frame is `SetAllPoints()` on UIParent with
  `SetJustifyV("TOP")` and no scrollbar, so anything past the bottom edge is
  simply cut off. This was already true at the old hardcoded 12 px; at the new
  sizes (up to 44 px) it bites much sooner. Either add a scroll frame, or — much
  cheaper — scroll the text so the current line stays visible, which falls out of
  the highlight work almost for free.

Doing the highlight without the scrolling would be half a feature: the marked
line would often be below the visible area.

## 2. Nothing highlights the element the menu is pointing at

Sku's menu focus and the game's own frames are completely unlinked. When the
menu focuses bag slot 3, or a merchant item, or a mail, **nothing on the visible
frame changes**. A search across the addon for `SetHighlight`, `LockHighlight`,
glow overlays and vertex tinting finds only the nameplate tinting in
`SkuCore/Core.lua:1233-1390`, and that is gated behind `Sku.testMode` — dev-only.

For someone who can still see shapes, a highlight on the focused item button is
probably the single largest usability win available, larger than any font
setting. It is also the most work: the menu would have to resolve its current
node back to a real frame, which it deliberately stopped doing for bags when the
tree became Container-API driven (see item 4).

Scope suggestion: start with the bag list only, where the entries already carry
`bag`/`slot` and the button name is derivable, and see whether testers report it
helps before generalising.

## 3. The Sku menu itself has no visual form at all

`OnSkuOptionsMain` (`SkuZOptions/Core.lua:1488`) is an 80x22 button parked
1500 px off-screen. It is a key-catcher, not a display. Apart from the optional
reading bar there is **no on-screen representation of the menu whatsoever** — no
list, no focus ring, no breadcrumb.

The reading bar covers the current entry, which is the important part, and after
v43.2 it also shows the value and works in combat. A fuller visual menu (a few
lines of context above and below the cursor) would be the next step, and could
reuse the whole styling layer added in v43.2. Worth asking testers whether the
one-line bar is enough before building it.

## 4. Bags: deliberately not force-opened — do not "fix" this

`SkuCore:Build_BagsFrame` (`SkuCore/LocalMenu.lua:1290`) is fully Container-API
driven and **no longer force-opens any bag frame**; the removed
`OpenAllBagsHelper()` call was the login-stuck-menu cause. That was a considered
decision and the maintainer has confirmed it stays: a blind user presses B like
anyone else.

Verified from the client source, so nobody re-litigates it: Blizzard opens the
bags **itself** at the places where it matters — `MerchantFrame.lua:88`,
`BankFrame.lua:304`, `MailFrame.lua:99` and
`Blizzard_AuctionHouseFrame.lua:402` all call `OpenAllBags(self)` on show. That
happens in combat too, because it is Blizzard's own untainted code.

One consequence worth acting on: **`SkuCore:Build_BankFrame`
(`SkuCore/LocalMenu.lua:970`) still calls `OpenAllBagsHelper()` and is now
redundant** — Blizzard's own BankFrame already opened them. Removing it drops one
more force-open path for free. The guild-bank call
(`SkuCore/LocalMenu.lua:660`) is *not* redundant; no Blizzard path covers
`GuildBankFrame`.

## 5. The quest log is force-hidden

`SkuQuest/Core.lua` calls `HideUIPanel(QuestLogFrame)` at lines 243, 356 and 892
— including once on **every** `VARIABLES_LOADED`. The quest menu opens the frame
to scrape it and closes it in the same handler.

So a partially sighted player can never see the quest log, even though the data
they are hearing comes straight out of it. Whether the frame could simply be left
open while Sku reads it is an open question; the scrape may depend on a
controlled show/hide cycle. Worth checking before changing anything, and worth a
setting rather than a behaviour change if it works.

## 6. The camera lock works against residual sight

Sku forces `cameraOptions.skuStandard = true` on **every**
`PLAYER_ENTERING_WORLD` (`SkuCore/Core.lua:3395`), plus `ResetView(2)` /
`SetView(2)`. The "Sku standard" set includes `cameraDistanceMaxZoomFactor = 1`,
which pins the player to a close view.

This is deliberate and correct for blind users — `dev/rework-docs/Standard-Einstellungen-Review.md`
lines 64-67 say so explicitly ("Die aggressive Kamera-Fixierung bleibt so — sie
ist richtig für blinde Nutzer"), and `SetView(2)` is load-bearing for yaw in
turn-to-target. But somebody with residual sight who zooms out to see more gets
snapped back at every login unless `preferFree` happens to be set.

This is the one place where blind and low-vision needs genuinely conflict. Any
change here is a policy decision for the maintainer, not a bug to fix. The
cheapest honest option is probably to respect an explicit unlock across logins
rather than re-asserting the flag unconditionally.

## 7. Nameplate CVars not yet exposed

v43.2 exposes size, target emphasis, dimming, class colours and friendly
names-only. Measured as existing on 2.5.6.69546 but **not** yet offered:

- `nameplateMinScaleDistance`, `nameplateMaxScaleDistance` — the distances the
  min/max scales apply at. Only meaningful if we ever offer distance-dependent
  scaling, which the current menu deliberately avoids.
- `nameplateOccludedAlphaMult` — opacity of plates behind geometry.
- `nameplateAuraScale`, `nameplateSimplifiedScale`.
- `nameplateMotion` (already in Blizzard's own options UI), `nameplateMaxDistance`
  (owned by Sku's camera set — see the ownership split below).

★ `NameplateScale` (capital N) does **not** exist on this build; it was probed
and came back MISSING.

**CVar ownership split, as agreed:** the camera set owns *which* plates show
(`nameplateShowEnemies`, the friendly list, `nameplateMaxDistance`); the
`Namensplaketten` menu owns *how big, what colour, how opaque*. No overlap, so
they cannot fight at login. Keep it that way.

## 8. Friendly nameplates are off, which silently disables half of item 7

Sku's "Sku standard" camera set writes the friendly-nameplate CVars to 0. A
friendly unit with no nameplate has nothing to scale and nothing to class-colour,
so `Klassenfarben Verbuendete` and `Nur Namen bei freundlichen Spielern` do
nothing at all for such a user — and the older `Plaketten-Farben` cannot colour a
friendly target either.

This is not a bug in either feature, it is an interaction nobody has decided on.
Either the nameplate menu should be allowed to turn friendly plates on, or the
menu should say plainly that they are off. Currently it does neither.

## 9. The old `Plaketten-Farben` is structurally weak — consider retiring it

`VisualAids:VisualAidsColorOnePlate` creates its texture with
`np:CreateTexture(nil, "BACKGROUND")` on the **base** nameplate frame, while
Blizzard's `UnitFrame` is a **child button**. Child frames render above every
layer of their parent, so the coloured square sits behind the entire plate and is
visible only in the margin around the art. It is also a fixed 20-60 px square
regardless of plate size, needs event bookkeeping, and breaks whenever Blizzard
reworks nameplates — which happened in July 2026.

The native CVars now do the same job better. The feature was left working in
v43.2 because users may have enabled it, but it should probably be demoted in the
menu and eventually retired, with its users migrated to the native settings.

## 10. Smaller items

- **Reading bar clips long lines.** `SetWordWrap(false)`, fixed single-line
  height, no truncation and no scroll. At 68 or 84 px a bag entry runs off the
  right edge silently. Marquee, shrink-to-fit or an ellipsis would all work.
- **`SkuTTS:Create` still has one unguarded `SetFont`.** `SkuTTS-1.0.lua:69`
  sets Playfair 12 with no `pcall` and no fallback. In practice
  `VisualAids:TextWindowLayout` re-applies a checked font before every show, so
  a missing TTF no longer blanks the pane — but the raw call is still there and
  should get the same fallback treatment for safety. Note the bundled fonts are
  gitignored (`Sku/.gitignore:9-10`) and ship only in the release ZIP, so a
  **repo clone is not a valid install** for testing this.
- **Minimap can be left displaced.** `minimapScanner.lua:881` sets
  `Minimap:SetAlpha(0)` and shrinks it to 15x15 for a scan;
  `MinimapScanner:RestoreMinimap` returns early in combat
  (`minimapScanner.lua:530`), so a scan interrupted by combat can leave the
  minimap parked at the cursor. Cosmetic and transient, but visible.
- **No UI scale or gamma control of Sku's own.** Blizzard's UI Scale should be
  reachable through Sku's Spieloptionen mirror (`SkuCore/gameOptions.lua` wraps
  Blizzard's panels generically), but this was never verified. Worth confirming
  before building anything.

## 11. What Blizzard's own options UI does and does not expose

Verified against the installed client. Useful because anything in the first list
is already reachable through Sku's Spieloptionen mirror and does **not** need its
own Sku menu:

**Exposed by Blizzard:** show enemies / friends / minions / minus, the
`nameplateMaxDistance` slider, cast bars, the `nameplateMotion` dropdown, aggro
flash, personal resource display.

**Not exposed anywhere in the options UI:** every size, colour and contrast CVar
listed in item 7 and in the v43.2 menu. Classic even stubs out retail's "Larger
Nameplates" checkbox — `InterfaceOverrides.CreateLargerNameplateSetting` is a
function whose entire body is the comment "no setting in Classic".

★ **Do not read `_anniversary_/BlizzardInterfaceCode/` as current.** It is a
March/April 2026 dump, older than the July nameplate change, and it names retail
CVars that do not exist in the shipped exe. Grep the exe strings instead — see
`[[anniversary-nameplate-cvar-split]]` for the recipe. This cost one wrong
feature plan already.
