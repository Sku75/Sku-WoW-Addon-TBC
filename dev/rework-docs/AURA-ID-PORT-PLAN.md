# SkuAuras: from name matching to group (ID) matching

Date: 2026-08-20. Status: **IMPLEMENTED 2026-08-22 under v43.0. First in-game
pass done; one defect found and fixed (12.5), the fix itself is UNTESTED.** The
plan below is left as written; section 12 at the end records what was built,
where the implementation deviated from it and why, and what is still open. Read
section 12 before acting on anything above it.

Goal: an aura authored on a German client fires on an English or French client,
and the German-only default aura sets become available to every locale.

Everything marked **measured** was counted from the shipped data files or read
out of the client's own UI source. Everything marked **estimate** is a guess.
Do not act on an estimate as if it were a measurement.

## 0. Verdict

Feasible, and smaller than it looks, because the storage format already carries
tagged values and an ID attribute already exists. The port is **one**
transformation (introduce group identity), not a chain of steps.

Two decisions carry the whole design:

1. Group identity is the **enUS spell name**, read out of `SkuDB.SpellDataTBC`,
   which already ships and is already maintained. No new data file.
2. The user-visible shape does not change. Names stay names in the menu, in the
   aura name, and in speech. The enUS name is internal identity only.

**Estimate:** about two working days of implementation, plus in-game
verification spread over sessions.

## 1. What the system is today

It is not purely name-based. It is *tagged-value* based, and both forms exist:

- Stored condition values are strings like `"spell:Frostbolt"` or `"spell:116"`.
  The tag is stripped at match time by `SkuAuras:RemoveTags`
  (`Sku/SkuAuras/data.lua:49`), and the remainder is used directly as a lookup
  key into the live list.
- `spellId` and `itemId` are already full attributes with working `evaluate`
  functions (`data.lua:1765`), comparing numerically.
- The combat-log path already carries the ID: `CleuBase.spellId = 12`
  (`Core.lua:29`). Every CLEU-driven aura could already match by ID.

**Measured:** `SkuAuras.attributes` holds 44 attributes (`data.lua:1269`).
Name-only ones, 13 of them:

- `spellName`, `spellNameOnCd`, `spellNameUsable`
- `buffListTarget`, `debuffListTarget`, `buffListPlayer`, `debuffListPlayer`
- the four matching `*Duration` variants
- `weaponEnchantMainHand`, `weaponEnchantOffHand`
- `itemName`

They are name-only for one reason: the live list is built from `UnitAura`'s
first return.

- `Core.lua:1894` - `local name, icon, count, ... = UnitAura(unit, x, filter)`,
  then `tBuffList[name] = name`
- `Core.lua:1662` - the v43.0 membership-diff scan, names only

**Measured, from the client's own UI source:** on 2.5.6 `UnitAura` is a
compatibility shim over `C_UnitAuras.GetAuraDataByIndex`
(`Blizzard_Deprecated/Deprecated_2_5_5.lua`), and `AuraUtil.UnpackAuraData`
(`Blizzard_FrameXMLUtil/AuraUtil.lua:22`) returns `spellId` as **return value
10**. `C_UnitAuras.GetUnitAuraBySpellID(unit, spellID)` also exists
(`Blizzard_APIDocumentationGenerated/UnitAuraDocumentation.lua`).

So the ID is available at the existing call site for the cost of naming more
return values.

## 2. Measured data

From `Sku/SkuDB/assets/spells.lua` (5,303,275 bytes):

- 49,019 spell rows
- `enUS` and `deDE` sub-tables present on every row
- 27,054 distinct enUS names
- 6,184 names carry more than one ID
- 28,147 IDs sit under a name shared with another ID (57%)
- 20,872 names are unique to one ID

Largest name groups: Shadow Bolt 140, Fireball 137, Shoot 111, Frostbolt 103,
Lightning Bolt 94, Breath 94, Whirlwind 90, Food 85.

Frostbolt in detail:

- 103 IDs total
- 16 carry a `Rank N` subtext - the player ranks
- 87 carry no subtext - the NPC and proc variants
- lowest ID 116, highest seen 72166 (the dump spans past TBC content)

## 3. The design

### 3.1 Group identity = enUS name

`SkuDB.SpellDataTBC` is a fully materialized table indexed by spell ID with the
locale names nested inside each entry. It is always built
(`SkuDB/ChunkLoader.lua:140`) and deliberately not an `__index` proxy, so
`pairs()` traverses it (`ChunkLoader.lua:654`). SkuAuras already indexes it
per-ID at runtime in the weapon-enchant resolver:
`SkuDB.SpellDataTBC[id][Sku.Loc][1]` (`Core.lua:979`).

Therefore:

- live scan gives `spellId`
- `SkuDB.SpellDataTBC[spellId].enUS[1]` gives `"Frostbolt"`
- the stored value is `spellgroup:Frostbolt`
- match is one lookup, exactly as today

All 103 Frostbolt IDs resolve to the same string on every client in every
language, with no map, no generator, no new chunk, no TOC entry and no change to
release packaging.

### 3.2 Rejected: a generated repID table

An earlier version of this plan shipped a generated `spellId -> repID` chunk
(repID = lowest ID in the name group), following the `spellnames_frFR.lua`
precedent. Rejected, recorded here so it is not re-proposed:

- ~340 KB of additional shipped Lua (**estimate**) and ~2.6 MB of additional
  runtime tables (**estimate**) for identity data that already exists
- a second artifact to keep in sync with `spells.lua`
- repIDs get persisted into saved auras and shared between players, so a
  regeneration that introduces a lower ID into an existing name group would
  silently move the repID and orphan every saved aura holding the old one
- computing "lowest ID per name" at runtime needs two passes over the 49k rows,
  because `pairs` order is not ascending and must not be relied on for a value
  that gets persisted

The enUS name has none of these properties. It is stable, it is already shipped,
and it is already maintained.

### 3.3 Cost

Unchanged, not merely acceptable. The live list stays string-keyed exactly as it
is today, holding enUS strings instead of localized ones. One table index chain
(`SpellDataTBC[id].enUS[1]`) is added per aura per scan and per CLEU event,
replacing nothing and costing a few table reads. No new memory, no new parse
time, no new build pass.

This matters because the scan, the membership diff, the list caches and the
duration-deadline scheduler are all v43.0 work that was tuned for exactly this
path. The design deliberately does not perturb their cost model.

### 3.4 Why broad name grouping is required, not a compromise

The obvious worry is that grouping merges player and NPC variants: "target has
Frostbolt" would fire for any caster's rank. That merge is **wanted** - tracking
what an opponent casts ("announce if the mob casts Frostbolt") is a primary use
case, and the 87 subtext-less Frostbolt IDs are exactly the mob variants that
have to keep matching.

The merge never costs a distinction, because "I cast it" versus "the mob cast
it" is decided by the separate `sourceUnitId` attribute, not by spell identity.

## 4. Fallback lanes and staleness behaviour

The name lane does **not** go away. It becomes the permanent fallback, and
doubles as the insurance against a stale DB:

- **ID not in `SpellDataTBC`.** Fall back to comparing the live localized name,
  which is today's behaviour. The aura still fires. This is the case the mob
  auras care about most, since NPC IDs are the population most likely to drift
  as the Anniversary timeline cycles.
- **Genuinely new spell name.** Not selectable in the menu until the DB updates,
  but no saved aura can reference a name that was never in the list, so nothing
  breaks. Identical to today.
- **Blizzard renames a spell in enUS.** Saved auras holding the old group key
  stop resolving. Not a regression: today a deDE rename breaks the same auras
  the same way. The localized-name fallback covers it either way.
- **Missing `enUS` sub-table on a merged row.** SoD rows are merged in via
  `SkuDBMergeAbsent` (`ChunkLoader.lua:370`), and unguarded locale indexing has
  already thrown once in this project - see the comment at
  `ChunkLoader.lua:561-564`. The enUS read needs the same guard, with the
  localized name as fallback.

Every stale-data path degrades to current behaviour rather than to breakage.

## 5. Display stays localized

The enUS name is internal identity only. Today one string does both jobs; the
change splits them. In `BuildAttributeValueLists` (`Core.lua:559`):

- today: key = localized name, `friendlyName` = localized name
- after: key = **enUS** name, `friendlyName` = **still** the localized name

Three surfaces speak, all read `friendlyName` or live data:

- **Menu entries.** `NewAuraValueBuilder` injects each item as
  `tValueName(v)` (`Options.lua:486`), which returns
  `SkuAuras.values[key].friendlyName` (`Options.lua:439`). German client reads
  "Frostblitz". The enUS key lives only in `internalName`, which is not spoken.
- **The aura's own name.** `BuildAuraName` (`Options.lua:520`) composes the
  sentence from `friendlyName` lookups. Still German.
- **The announcement when the aura fires.** `data.lua:496-508` speaks
  `tEvaluateData.spellName`, assigned straight from the live event
  (`Core.lua:2082`, `CleuBase.spellName`). The client's own string, untouched.

Type-ahead keeps working on German names: both the sort comparator and the
injected item name go through `tValueName`.

### 5.1 Two places where English would leak if done sloppily

- `RemoveTags` (`data.lua:49`) strips `item:`, `spell:` and `output:`. It needs
  `spellgroup:` added. If a `friendlyName` lookup ever fails - stale key, spell
  missing from the DB - `BuildAuraName` falls back to the raw key, and without
  this the menu would read out "spellgroup:Frostbolt" verbatim.
- The nil-tolerant fallbacks `tFriendlyName` / `tFn` return `tostring(aKey)` for
  an unknown value. That fallback now reads English instead of German. It is the
  degraded path either way, but be aware of it.

## 6. Files that change

- `Sku/SkuAuras/Core.lua`
  - `Core.lua:1894` - take `spellId` from the `UnitAura` call, resolve to the
    enUS group name, key `tBuffList` by it (plus the own/exp scratch tables)
  - `Core.lua:1662` - same for the membership-diff scan, so the diff compares
    group identity rather than localized names
  - `Core.lua:961` / `Core.lua:1168` - `thingsNamesOnCd` is keyed
    `"spell:"..spellName` from CLEU; move to the group name
  - `Core.lua:559` `BuildAttributeValueLists` - key/friendlyName split (5.)
  - `Core.lua:973` `ResolveWeaponEnchantName` - enchants have no spellId; they
    stay in the name lane as single-member groups
- `Sku/SkuAuras/data.lua`
  - `data.lua:49` `RemoveTags` - add the `spellgroup:` tag
  - the 13 name-only attribute `evaluate` bodies - they already do
    "strip tag, look up in list", so the shape does not change; both sides
    simply become group names
- `Sku/SkuAuras/Options.lua`
  - `NewAuraValueBuilder` - inject the ID input node at index 0 (8.)
- `Sku/SkuAuras/defaultAuras.lua`
  - 30 `spell:` values become group values; lift the sets out of the
    `if Sku.Loc == "deDE"` gate at `defaultAuras.lua:7` so enUS and frFR users
    get default sets at all - currently they get none
- `Sku/SkuAuras/sharing.lua`
  - `SkuAuraSetV2` payloads, still accepting V1; drop the language tag. The
    header at the top of the file describes exactly this as "Stufe 4"; group
    identity makes the translator unnecessary rather than expensive.

## 7. Migration

Run-once, with `tMigrateQuickKeys` (`SkuZOptions/SkuKeyBinds.lua:361`) as the
precedent for the shape.

- On an enUS client `spell:Frostbolt` -> `spellgroup:Frostbolt` is a tag change.
- On a deDE client `spell:Frostblitz` -> id -> enUS -> `spellgroup:Frostbolt`,
  using the reverse lookup `BuildAttributeValueLists` effectively already
  constructs. One-time cost, irrelevant.
- A value that resolves to nothing stays a bare name and keeps working through
  the fallback lane.

## 8. The ID input field at index 0

For the case where the user knows an ID but not the name, mirroring the coin
input in the AH sell menu.

- The primitive exists and is already used in this very file:
  `SkuOptions:EditBoxShow(aText, aOkScript, aMultilineFlag)`
  (`SkuZOptions/Core.lua:7224`), called from `SkuAuras/Options.lua:996` and
  `sharing.lua:204`. It is the shared, screen-reader-aware edit box.
- Injecting the node first genuinely puts it at index 0: the menu uses
  **insertion order**, and the `sorting` flag selects filter-vs-type-ahead
  rather than sorting.
- It falls out of the tag space for free. The name list emits
  `spellgroup:<enUS name>` (any variant); the ID input emits `spell:<id>`
  (exactly that ID). Same `RemoveTags` machinery, no new parsing, and a typed
  ID gets exact semantics - which is what someone typing an ID wants.

## 9. Half-related: the aura key is a German sentence

This is a separate defect that blocks the same goal, and it is worth doing in
the same window even though it is not part of the ID port.

`SkuAuras:BuildAuraName` (`Options.lua:520`) composes the aura's name from
`L[]` tokens and `friendlyName` lookups - `"Wenn;ziel;gleich;...;dann;..."` -
**and that string is the table key** in
`SkuSettings:Sub("SkuAuras", nil, "char").Auras`.

So even with group values, a shared set still arrives with German key text on an
English client. Group identity fixes matching; it does not fix the name.

The fix is small, because `attributes` / `actions` / `outputs` are structural
and - once values are groups - fully locale-free. The name is derived data.
**Re-run `BuildAuraName` on import** and the aura renames itself into the
importer's language.

Three details that make this safe, all already in the code:

- **Auras can reference other auras.** `UpdateAttributesListWithCurrentAuras`
  (`Core.lua:839`) synthesises an attribute named `"skuAura"..baseName` per
  aura, so a rename must cascade. `UpdateAttributesWithUpdatedAuraName`
  (`Core.lua:902`) already does that cascade, recursively, and
  `AuraUsedInOtherAuras` (`Core.lua:875`) / `AuraHasOtherAuras`
  (`Core.lua:889`) already answer the questions around it.
- **Only `customName == true` auras can be referenced** - see the guard in
  `UpdateAttributesListWithCurrentAuras`. And `UpdateAura` keeps a custom name
  as-is (`Options.lua:575`), so a custom-named aura is never re-derived.
  Convenient: the referenced auras are exactly the ones whose names do not
  change on import, so cross-aura references survive untouched.
- **Footnote.** `GetBaseAuraName` (`Core.lua:440`) splits on the localized token
  `L["dann;"]`. On an enUS client that token is different, so an imported German
  custom name yields the whole string as its base name. Harmless for custom
  names, moot for re-derived ones, but do not build anything else on that
  function's output across locales.

## 10. Verification

Per the project rule that every regression fix contributes its invariant to
`/skucheck`, this port should add:

- every stored aura value resolves either to a known group or to a live name;
  none is a bare localized name after migration
- for a sample of known multi-ID spells, all IDs in the group resolve to one
  group key

Measurement channel for the cost claims: `BuildAttributeValueLists` already logs
`"%.0f ms wall"` and feeds `Sku:MetricPoint`, so the first run after the change
gives a real before/after number out of the debug ring - no sighted check
needed.

## 11. Open questions

- Weapon enchants and `itemName` keep their own resolvers as single-member
  groups. Confirm that is enough, or decide whether items deserve the same
  treatment via `SkuDB.itemLookup`.
- Cast-ID versus aura-ID divergence (a talent whose applied aura has a different
  name than the cast) is unchanged by this work - neither better nor worse.
  Worth a pass later to see whether it is worth a curated alias list.
---

## 12. Implementation record (2026-08-22, v43.0)

Everything in sections 1-10 was built. Syntax-checked with `luaparser`, the
build pass was modelled offline against the shipped `spells.lua`
(counts and order-stability verified), and the `UnitAura` return order was
re-confirmed against the client's own `AuraUtil.UnpackAuraData`. **Nothing has
been run in game.**

Files touched: `SkuAuras/Core.lua`, `SkuAuras/data.lua`, `SkuAuras/Options.lua`,
`SkuAuras/sharing.lua`, `SkuAuras/defaultAuras.lua`, `SkuCore/LocalMenu.lua`,
`locales/{enUS,deDE,frFR}.lua`, plus the three patch-notes files.

### 12.1 What the plan did not know: the reverse map is not injective

The plan assumed localized name -> enUS name is a usable mapping. Measured over
the shipped `spells.lua`: **838 of 26,603 German names (3.15%) cover more than
one English name**, spanning 1,899 groups. Not only junk rows - "Verblassen" is
`Fade` *and* `Fade Out`, "Geschwaechte Seele" is `Weakened Soul`, `Diminish
Soul` *and* `Weakened Spirit`, "Schattenwort: Schmerz" is `Shadow Word: Pain`
*and* `Shadow Word Pain Damage`.

Two consequences the plan did not anticipate, both handled:

- **Migration.** An ambiguous name is recorded in
  `SkuAuras.spellGroupAmbiguousLocName` and its saved values are left on the
  localized-name lane, where the compatibility alias keeps them matching every
  variant exactly as before. Converting one to a single group would silently
  drop the others.
  *(The reverse map itself no longer refuses these names - see 12.5.)*
- **The menu.** Each group is its own entry now, so those 1,899 groups would
  have produced two or three entries reading identically. Colliding entries get
  the English identity appended - "Verblassen (Fade Out)". Only the MENU label;
  `speakName` keeps the plain name for the announcement when an aura fires.

A related determinism problem: **545 groups (2%) hold ids with differing German
names** ("Ancestral Spirit" is both "Ahnengeist" and "Geist der Ahnen"), so the
display name depended on which row `pairs` reached first and could change
between sessions - which breaks type-ahead. The lowest id in the group now wins.
Verified order-stable offline over the real data (shuffled and reverse-sorted
input produce byte-identical labels, mapping and group set).

### 12.2 Deviations from the plan

- **Compatibility alias, additional to the plan's fallback lanes.** The live
  lists (`tBuffList`, the exp maps, the own-subsets, `thingsNamesOnCd`,
  `GetSpellNamesUsable`) carry the localized name *beside* the group key
  whenever the two differ. This is what makes an unmigrated or unmigratable
  value keep working instead of going silently dead. On an enUS client group ==
  live name, so the alias is never written and the cost is zero - the plan's
  cost claim in 3.3 holds unchanged there, and on deDE it is <=40 extra table
  stores per (cached) rebuild.
- **`AuraMembershipCheck` (Core.lua:1662) was deliberately NOT converted.** The
  plan lists it, but it is a pure change-detector comparing this client's
  previous scan against its current one. Group keying cannot make it more
  sensitive - it can only make it *less* (two ranks of the same spell swapping
  is invisible either way, and grouping merges more names, not fewer) - and it
  would add work to a per-frame path. Name keying stays.
- **The ID input (section 8) stores the GROUP value, not `spell:<id>`**, for
  every attribute except `spellId`. The plan's "a typed ID gets exact
  semantics" is not achievable for the list attributes: their live lists are
  name-keyed, so a bare id could never match one, and `spellName` compares
  names. The typed id is resolved to its group and Sku speaks back the spell it
  resolved to. `spellId`, where the id *is* the value, stores it as typed.
- **The ID input's ENTER goes through a wrapper on the level's `selectTarget`.**
  `SkuZOptions/templates.lua` `OnPostSelect` always dispatches ENTER to the
  select target, never to the focused node's own `OnAction`, so the node cannot
  own its ENTER. The wrapper recognises the node by an `auraIdInput` marker and
  re-points `SkuOptions.currentMenuPosition` back at it from the edit box's OK
  callback (the framework parks the cursor on the select target synchronously,
  long before the user types).
- **Sharing sends V2 ONLY** (section 6 said "still accepting V1", which it
  does). Sending an additional V1 packet would leave older clients holding auras
  with group values they cannot resolve - silent garbage is worse than nothing.

### 12.3 Fixed on the way

- `SkuAuras:ResolveWeaponEnchantName` read enchant-db column 1 for enUS and
  column 2 for deDE and left the name `nil` otherwise, so on a **French client it
  returned nil for every enchant** and the weapon-enchant value list came out
  empty - the condition could not be authored at all. Locale column, else
  English, like the rest of the naming system since v42.09.
- `tAddWeaponEnchantName` in `EvaluateAllAuras` was the third, diverged copy of
  the enchant resolver that the W6-C comment above it warns about. Folded onto
  the central resolvers.
- `spellNameUsable.updateValues` indexed `spellData[Sku.Loc]` unguarded (the
  exact shape that threw on frFR before) and filled its list in place. Guarded,
  deduped, built into a local and published atomically.
- The nil-tolerant `friendlyName` fallbacks (`tFriendlyName` / `tFn`) returned
  the RAW key, which after this port would read "spellgroup:Frostbolt" out loud.
  They strip tags now - with a type guard, because `RemoveTags` maps the strings
  "true"/"false" to booleans and the binary attributes' values are exactly those
  two keys (a boolean into a string concatenation is how the menu would have
  errored instead of merely reading a raw key).

### 12.4 Still open

- **Items (open question 11) were not ported.** `itemName` stays localized;
  `SkuDB.itemLookup.enUS[id]` would make the same treatment cheap, but the plan
  left this undecided and it is a decision, not an omission. A shared aura that
  conditions on an item name still only works within one language.
- **`defaultAuras.lua`**: the 29 resolvable values were converted to group
  values, one (`Verbessertes Verblassen`, no deDE row in the DB) stays on the
  name lane, and the `if Sku.Loc == "deDE"` gate is gone so every locale gets
  the sets. But the aura KEYS and the `friendlyNameShort` labels are German
  prose - not derived data, so nothing can regenerate them - and the menu that
  would apply these sets is still disabled behind the `[Fix Nr22] if false then`
  block in `Options.lua`. Nothing reads them today either way.
- **Cast-ID vs aura-ID divergence** is unchanged, as the plan said.
- **In-game verification.** Nothing here has been run. The first read-back is
  the value-list `dprint`, which now reports group count, loc->group mappings,
  ambiguous names and disambiguated entries, followed by the one-line group
  migration report. Then `/skucheck auras`.

### 12.5 In-game pass 2026-08-22: one defect, found and fixed

Most of it worked on the first run - duration conditions, aura-lost, and group
matching on `spellName` (a `spellgroup:Power Word: Fortitude` aura fired). One
class did not: **auras on "Verblassen (Fade)" and "Verblassen (Fade Out)" never
fired.**

Cause, confirmed from the shipped data rather than guessed: the dump carries the
priest's Verblassen **only at rank 1** (id 586). Ids 9578, 9579, 9592, 10941 and
10942 are absent - unusual, Renew, Power Word: Fortitude and Frostbolt all have
their full rank sets. So a levelled priest's cast arrives with an id
`SpellDataTBC` cannot resolve and drops to the localized-name lane - and there
"Verblassen" was one of the 838 ambiguous names, which 12.1 had deliberately
mapped to *nothing*. The value stayed "Verblassen", the stored value was
"Fade", nothing matched, and the aura was silent although the user had picked
the right entry in the menu.

The two decisions were separated, which is what 12.1 got wrong by conflating
them:

- **Resolution** (runtime, `spellGroupByLocName`): an ambiguous name now
  resolves to the candidate group whose **lowest spell id is lowest**, decided
  in one pass at the end of the build so it cannot depend on `pairs` order.
  Verified against the cases where the answer is known - Verblassen -> Fade (586
  vs 5543), Geschwaechte Seele -> Weakened Soul (6788 vs 36788), Schattenwort:
  Schmerz -> Shadow Word: Pain (589 vs 37603), Erneuerung -> Renew (139 vs
  37563), Gedankenkontrolle -> Mind Control (605 vs 7645): **5/5**. "Most ids in
  the group" instead scores 4/5 - it picks `Diminish Soul` (six ids) over
  `Weakened Soul` (one).
- **Migration** (`spellGroupAmbiguousLocName`): unchanged, still refuses. A
  saved localized value matches every variant today; rewriting it to the one
  group the runtime guesses would silently drop the others.

Strictly additive at runtime: before the fix an unknown id produced the single
key `"Verblassen"`, now it produces `"Fade"` plus `"Verblassen"` as the alias -
so group auras start working and legacy name auras are untouched.

Tripwire, per the project rule: `/skucheck auras` invariant 4 - every ambiguous
localized name must resolve to a group that exists in the value set. A
regression to "resolves to itself" fails it, because
`spellgroup:<that name>` is not a group.

**Not a defect:** the user's second aura, on "Verblassen (Fade Out)", still does
not fire for the priest's Fade, and should not - `Fade Out` (5543) is a
different spell. The disambiguated menu label is what makes that choice
visible; picking "Verblassen (Fade)" is the priest spell.

**Still untested:** the fix itself, and everything under 12.4.
