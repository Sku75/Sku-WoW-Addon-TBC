# SkuDB restructuring — risk analysis and staged plan (2026-07-05)

Companion to LOAD-PERF-OPTIONS.md (context, A/B measurement) and
LOAD-PERF-NOTES.md (W3 handoff). This document is ANALYSIS ONLY — no
implementation has been done. Sources: four fresh deep dives run 2026-07-05:
a byte-level inventory of every SkuDB data file, a complete consumer audit
(782 SkuDB references in 26 files, all classified, AST-verified for
file-scope execution), a review of the existing deferred-data tooling, and a
line-level study of Questie's installed compiler source including measured
SavedVariables costs from the live install. No tables in this doc by design
(screen-reader formatting).

## TL;DR

- Phase A (string literals + chunked streamed builders) removes Sku's
  loading-screen bill (~1.3 s file compile, ~0.7 s route build, ~0.3 s aura
  lists, plus the merge) but does NOT reduce memory. Phase B (compile-once
  binary cache with random-access reads) is the only thing that cuts the
  610-950 MB heap — and its worthwhile scope is unknown until we measure
  which tables actually hold the memory (stage 4 below).
- The dangerous corruption channels are NOT byte encoding. They are
  semantic: the SkuQuest login fix+merge that rewrites every dataset in
  place, the SessionRouteData tables that ARE the route data (aliases, not
  copies, and edited every session), waypoint identities persisted in
  SkuOptionsDB that embed raw array positions of the route table, and the
  shared key tables that three files overwrite in load order with DIFFERENT
  values. Each has a defined mitigation and a mechanical check below.
- Verification backbone, all runnable out-of-game with py -3 or audible
  in-game: (1) the converter only REGROUPS verbatim record bytes, so old
  and new files can be byte-compared record by record and as a full
  reassembly; (2) a committed hash manifest pins the pristine inputs (the
  data files are gitignored — git alone cannot protect them); (3) an
  in-game deterministic table fingerprint (/skudbcheck) proves the built
  tables are IDENTICAL before and after each stage; (4) for phase B, a
  shadow-verify soak that compares every decoded record against the live
  table — the same 22-to-0-mismatches method that certified the aura cache.
- Staging: 0 tooling+baseline, 1 free the route source strings (~50 MB,
  trivial), 2 format conversion with UNCHANGED timing (zero felt change,
  pure risk retirement), 3 streamed build + consumer guards (the felt login
  win), 4 measurement gate (memory ranking + SavedVariables dry run),
  5 binary cache one dataset at a time. Routes stay OUT of phase B.
- Recommendation: do stages 0-3. Commit to stage 5 only after stage 4's
  numbers. Realistic expectation: phase B on the read-only datasets gets
  ~950 MB down to maybe 600-700 MB, not to 100 — the route tables and the
  WaypointCache are excluded and may hold the larger half. Stage 4 tells us.

## 1. Facts on the ground

### 1.1 What ships and what executes

- Sku.toc force-loads ~48 MB of SkuDB data as real table constructors during
  the loading screen: base assets ~23.9 MB (creatures 5.9, items 5.7,
  spells 5.3, quests 3.9, objects 1.8, maps 0.6, default_waypoints 0.3,
  polygons 0.07, fixes files, tasks), WotLK ~23.6 MB (creatures 7.9,
  items 7.6, quests 5.1, objects 2.7, enchantIDs 0.2), SoD ~0.6 MB.
- The two route files (~50.5 MB source) are already deferred string-literal
  builders (W3 codemod): construction runs at PLAYER_LOGIN via
  Sku:EnsureData("routes"). BUT the source strings stay resident forever —
  nothing nils the builder globals after use, so ~48 MB of dead string sits
  in the heap permanently on top of the built tables (stage 1 fixes this).
- Dead weight on disk, never loaded: wiki.lua 29 MB, the Era tree 14 MB,
  routedata_global.lua.bak 19 MB.
- Layout note for THIS worktree: WotLK, SoD, and Era live under
  Sku/SkuDB/assets/ (TOC lines 100-118 say SkuDB\assets\WotLK\... etc.).
- Git status: EVERY SkuDB data file is gitignored (Sku/.gitignore line 20
  ignores /SkuDB/assets/ entirely, line 19 the wotlk route file, line 25
  *.bak). Only SkuDB/Core.lua (7 lines) is tracked. Consequence: git revert
  can never restore data files; the pristine state lives in (a) the sibling
  .bak files and (b) the upstream-src git blobs (remote of the maintainer's
  source repo, commit 22e81c0, byte-identical sizes) — two independent
  copies we can hash-check against each other.
- Memory (A/B measurement): ~610 MB at PEW after the forced GC
  (673 -> 616), ~950 MB after the waypoint-cache build. Game baseline 65 MB.

### 1.2 Data-shape hazards found in the files

Encoding and text facts:
- All loaded asset files are valid UTF-8 with RAW umlauts and ß in deDE
  strings (no escape sequences for them). objects.lua even uses umlaut
  STRING KEYS (objectResourceNames, e.g. "Adamantitablagerung").
- The section sign § (2 bytes in UTF-8) is the language separator inside
  route waypoint names ("Quick Waypoint;1§Schnellwegpunkt;1") — ~50k lines
  per route file. Zero § in the non-route files.
- The only escape sequences anywhere are backslash-doublequote and
  backslash-singlequote. No \n, no \\ pairs beyond those, no \ddd bytes.
- None of the loaded asset files has a UTF-8 BOM (only SkuDB/Core.lua and
  the unloaded wiki.lua do). All files are CRLF on disk and untracked, so
  git's LF normalization never applies to them.
- wiki.lua (unloaded) contains literal ]] sequences (MediaWiki markup) —
  any long-string wrapping MUST pick bracket levels by scanning, never
  assume level 0 or 1 is safe (the existing pick_level does this right).

Structural hazards for any serializer or chunker:
- Every big file is MULTIPLE top-level statements: small keys/legend tables
  (questKeys, itemKeys, NpcData.Keys, spellKeys, objectKeys...), then one or
  two locale lookup tables, then the big data table. The keys tables live
  INSIDE the data files, not in SkuDB/Core.lua.
- Shared globals written three times in load order with DIFFERENT content:
  SkuDB.raceKeys/classKeys/QuestFlags/questKeys are assigned by base
  quests.lua, WotLK quests.lua, and SoD quests.lua — and the classKeys BIT
  VALUES DIFFER (base TBC: SHAMAN=32; WotLK: SHAMAN=64, DEATHKNIGHT=32).
  Last writer (SoD) wins today. objectKeys 3x, spellKeys 2x. Any change to
  WHEN these execute changes what every consumer sees.
- Environment-dependent values: quests.lua raceKeys contains
  "VANILLA and 77 or 1101" evaluated from GetBuildInfo() at load; WotLK/SoD
  quests.lua read VANILLA as an (accidentally) undefined global.
- Locale-dependent keys: tasks.lua table keys are L["..."] AceLocale lookups
  — the table literally has different keys per client language.
- Functions inside the "data" layer: every *_fixes.lua defines methods
  (SkuDB:FixQuestDB etc.) over file-local fix tables, using computed keys
  like [questKeys.triggerEnd].
- A metatable: polygons.lua line 3592 does
  setmetatable(SkuDB.Polygons.data, SkuPrintMT), with SkuPrintMT/SkuPrintMTWo
  (tables holding __tostring FUNCTIONS) defined in the same data file.
- Mixed array+hash in one table: default_waypoints.lua has positional
  entries AND named keys in the same constructor.
- Nil holes in positional record arrays everywhere (a naive ipairs- or
  length-based walker silently truncates records).
- Placeholder records: route WaypointsNew contains {false} tombstones
  (~1,565 of them) that MUST survive round-trips because array positions
  are waypoint identity (see 1.3).
- Three float regimes: 2-decimal map coordinates (creatures/objects/quests),
  ~11-digit polygon coordinates, and full-double-precision route/waypoint
  values (e.g. -512.2133178710938). Lossless round-trip needs %.17g.
- Negative numbers are common (quest level -1, sort -370, negative world
  coordinates). Route tables use integer keys UP TO ~2^44 (packed waypoint
  IDs like 13743913385288) — beyond 32-bit encodings.

### 1.3 Consumer landmines (the audit's core results)

Load-time presence assumptions:
- Exactly ONE true file-scope SkuDB read outside SkuDB/:
  SkuQuest/Core.lua:71 writes SkuDB.QuestFlagsFriendly (needs only the
  SkuDB global). Everything else reads at event time — good news, the
  file-scope surface is tiny.
- Login-window readers that break if data is late: SkuQuest:PLAYER_LOGIN
  (the fix+merge, below), SkuNav PLAYER_LOGIN/PEW + the waypoint-cache
  passes (NpcData.Names/Data, objectLookup/objectDataTBC/
  objectResourceNames, InternalAreaTable, ContinentIds, SessionRouteData),
  SkuAuras:PLAYER_ENTERING_WORLD (iterates ALL of itemLookup and
  SpellDataTBC plus WotLK.enchantIDs, UNGUARDED — with late data it builds
  EMPTY aura attribute lists and auras silently never fire),
  aqCombat:OnEnable (caches SkuDB.NpcData.Keys.rank into an upvalue),
  SkuQuest:QUEST_LOG_UPDATE (reads questDataTBC and can fire very early).
- maps.lua (InternalAreaTable/ExternalMapID/ContinentIds) is read by
  SkuNav's most basic coordinate functions which everything calls
  constantly — it must stay eager forever.
- Profile-change re-entry: SkuOptions:OnProfileChanged/Copied/Reset re-run
  PLAYER_ENTERING_WORLD handlers and every module's OnEnable mid-session,
  and OnProfileReset reads SkuDB.routedata directly. Any readiness logic
  must survive being re-entered at arbitrary times.
- Unguarded RUNTIME consumers (fine today, crash sites with async data):
  auction house menus (itemDataTBC/itemLookup, including a chunked full-scan
  that caches table references across frames), tooltip/character-sheet
  enchant resolution (SpellDataTBC, WotLK.enchantIDs — used DURING COMBAT
  by SkuAuras' getAuraList), gossip/quest-reward menus (questDataTBC),
  gameWorldObjects scan closures (iterate NpcData.Names, objectLookup, and
  ALL of SpellDataTBC per scan hit), SkuMM map menus, specialNavigationTasks
  (SkuDB.Tasks), SkuChat quest-link resolution (already guarded — the model:
  degrades silently instead of erroring).

The SkuQuest login fix+merge (SkuQuest/Core.lua ~1101-1296) — landmine 1:
- At PLAYER_LOGIN it calls SkuDB:FixQuestDB/FixItemDB/FixCreaturesDB/
  FixObjectsDB (+ WotLK and SoD variants), which PATCH the raw tables in
  place, then MERGES SkuDB.WotLK.* and SkuDB.SoD.* into the base tables
  (NpcData.Data/Names, itemDataTBC/itemLookup, objectDataTBC/objectLookup —
  it even CREATES objectLookup.enUS from scratch — questDataTBC/questLookup,
  SpellDataTBC). The copied rows are REFERENCES, so base and expansion
  tables share row tables after login.
- Consequence: "the dataset" that consumers see is really
  "file data + fixups + cross-expansion merge". Any cache or rebuild that
  snapshots PRE-merge state changes lookup results everywhere (names,
  levels, spawn positions), silently. Waypoint names in the cache embed
  MERGED localized creature names, so even build ORDER relative to the
  merge changes cache keys.

The route-data aliasing web — landmine 2:
- SkuDB.SessionRouteData.Waypoints/Links ARE the built route tables
  (SkuNav/Core.lua:3385-3393 assigns references INTO routedata / SkuDBTMP,
  and the alias is re-pointed in the PEW wotlkMapReset branch, profile
  reset, and the showGatherWaypoints setting).
- The route data is READ-WRITE BY DESIGN: the en§de name split rewrites all
  ~50k waypoint names once per login and nils WaypointsNew; stale-link
  pruning DELETES thousands of Links entries every login;
  SaveLinkDataToProfile() wholesale-REPLACES SessionRouteData.Links with a
  fresh table (silently breaking the alias from that moment); waypoint
  create/update/delete and link edit functions write into it; PLAYER_LEAVING_WORLD
  can empty it; import replaces it.
- WaypointCache entries alias route subtables (cache "comments" IS the
  waypoint's lComments table; mutations flow both directions), and
  SavedVariables capture references (TmpWaypoints stores a live reference
  to a cache comments table; dev translate tools store references INTO
  routedata in SkuTranslatedData).
- Waypoint IDENTITY leaks into SavedVariables: custom waypoint IDs embed
  dbIndex = the ARRAY POSITION in routedata.global.Waypoints, and names/IDs
  are persisted in SkuOptionsDB (recent waypoints, quick waypoints, metapath
  data) and inside Links keys. Any rebuild that changes array order or row
  identity silently re-targets every persisted reference — landmine 3.
- External: WowVision (when enabled) reads AND MUTATES _G.SkuDBTMP directly
  (does its own WaypointsNew split on Sku's table).
- Conclusion drawn throughout this plan: route data is NOT a candidate for
  a read-only binary cache. It stays as Lua tables. (A future copy-on-write
  overlay design could change that — parked, see stage 6.)

### 1.4 Current tooling — what exists and what is missing

- _wrap_deferred.py: operates on raw bytes (preserves BOM/CRLF), creates a
  one-time .bak and always regenerates from it (idempotent, --unwrap
  reverts), picks safe long-bracket levels by scanning. It does NO chunking
  (one builder per file) and NO verification of its output (no parse check,
  no round-trip, no checksum).
- SkuDeferredData.lua / Sku:EnsureData: idempotent chokepoint, BUT the
  ready flag is set BEFORE the builders run (an error mid-build leaves
  ready=true with partial data), builders run WITHOUT pcall, and builder
  globals are never nil'ed (the ~48 MB string leak). Sku:IsDataReady exists
  with zero callers today.
- No old-vs-new comparison or checksum tooling exists anywhere yet. The
  luaparser Python package is installed and proven as a syntax gate but no
  script imports it yet. The in-game precedent for correctness soaks is the
  aura-cache verify mode (22 mismatches found, fixed, then 0 over a raid).

### 1.5 What Questie proves, and its warts (from their installed source)

- Their DB files are giant [[return {...}]] strings: loading a file only
  interns a string. First login per (addon version, UI locale, expansion)
  key: loadstring, apply corrections+localization IN PLACE, then transcode
  every record into a packed binary string + an id-to-offset pointer map,
  both stored in SavedVariables. Every later login skips all of it; the raw
  strings and tables are nil'ed (QuestieCleanup) followed by one forced
  collectgarbage.
- Runtime reads are random access: string.byte/string.sub into the blob at
  pointer offsets, fixed-size fields first, arithmetic "skippers" for
  dynamic fields. Decoded entities are memoized in caches that grow with
  usage.
- They HAVE a validator (dev-only, debugEnabled): it decodes EVERY record
  and deep-compares against the source tables, and a QueryValidator runs
  skipper and reader in lockstep and errors when their end pointers
  diverge — the classic corruption source for this design, treated as a
  first-class failure mode.
- Corruption self-heal exists because corruption HAPPENS in the wild: a
  guard inside the hot reader detects reads past the blob end, clears the
  compiled flag, and tells the user to /reload (recompile). Plus a manual
  "Recompile Database" button. Raw strings always ship, so recovery is
  always possible.
- Measured on OUR live SavedVariables file: Questie.lua is 19.6 MB; the
  four binary blobs are ~5.7 MB of Lua string, serialized to ~11.6 MB on
  disk (WoW escapes bytes as \ddd; measured blowup 1.5x-2.1x, average
  ~1.9x). WoW doubles that again with its automatic .bak. So: arbitrary
  8-bit strings in SavedVariables are SAFE (string.char bytes round-trip
  fine through WoW's serializer) but cost ~2x on disk and are written out
  at EVERY logout and /reload.
- Warts to avoid in a port: nil strings encoded as the literal text "nil"
  (sentinel ambiguity, their own comment says "I hate this"); lossy
  coordinate quantization (12-bit, ~0.025 precision, validator needs a
  tolerance because of it); a purely positional schema where one wrong
  field type corrupts everything after it in the record.

## 2. Phase A risk catalog — string literals, chunked builders, streamed build

Phase A converts the big data files from executed table constructors into
string-literal chunks (~500 records per loadstring builder) and streams the
construction through a coroutine after login. Memory is NOT reduced (the
same tables get built); the loading-screen cost is removed. Each risk below
ends with its mechanical verification.

Risk A1 — byte-level corruption during conversion (umlauts, ß, §, CRLF,
BOM, quote escapes).
- How it would happen: any text-mode processing (Python default encodings,
  regex over decoded text, newline translation) can silently mangle bytes.
- Mitigation: the converter works on RAW BYTES only, like _wrap_deferred.py
  (binary read/write, no decode step for the data body).
- Verification (mechanical, out-of-game): the converter never rewrites
  record text — it only REGROUPS verbatim byte slices (see A3). Therefore:
  concatenating all record slices from the NEW files in key order must be
  BYTE-IDENTICAL to the record slices of the ORIGINAL file in key order.
  The converter performs this reassembly check itself and refuses to write
  output on mismatch. Additionally SHA-256 of every input and output goes
  into a committed manifest (see section 4, tool 2).

Risk A2 — long-string bracket collision: data containing ]] or ]=]
terminates the literal early; everything after is silently dropped or
becomes garbage code.
- Known concrete case: wiki.lua is full of literal ]] (MediaWiki links).
  The route files happen to contain none, but the converter must never
  assume.
- Mitigation: per-chunk bracket-level scan (extend pick_level): choose the
  smallest level whose close token does not appear in the chunk bytes.
- Verification: (1) the converter asserts zero occurrences of the chosen
  close token inside each chunk body; (2) every generated file must parse
  clean with luaparser (py -3, utf-8-sig); (3) the reassembly byte-check of
  A1 catches any truncation because dropped bytes cannot reassemble.

Risk A3 — record-boundary mistakes when chunking: splitting mid-record
drops, merges, or duplicates records — the classic silent-corruption case
the user fears, and it would surface weeks later as one wrong quest
or creature.
- Mitigation (design rule, the single most important one in phase A): the
  converter NEVER rewrites record text. It scans the original file with a
  brace-depth counter that is string- and comment-aware (the proven method
  from this project's log tooling), identifies top-level records of the
  form [key] = {...}, at depth 1, and REGROUPS the verbatim byte slices
  into chunks. Only scaffolding (the surrounding "SkuDB.x = {" head, chunk
  wrappers, closers) is generated.
- Verification: (1) the set of record keys in old vs new must be IDENTICAL
  (the scanner extracts keys from both and compares as sets AND as
  sequences); (2) per-record byte identity — each record slice in the
  output is located and byte-compared against its original slice;
  (3) the full reassembly check from A1; (4) record counts per dataset go
  into the manifest and are re-checked in-game by /skudbcheck (tool 3).
  Any anomaly (a record not matching [key]= form, a duplicate key, an
  unbalanced brace at EOF) is a HARD converter error, never a warning.

Risk A4 — wrapping something that is not constant data: VANILLA
(GetBuildInfo at load), L["..."] locale keys in tasks.lua, the fixes-file
functions, the polygons metatable, computed keys like [questKeys.x]. Frozen
into a string and executed later, these evaluate at a different time (or
against different globals) and produce silently different tables.
- Mitigation (whitelist, not blacklist): ONLY these nine files are
  converted, and within them only the big pure-literal statements —
  base creatures.lua (Names, Data), items.lua (itemLookup, itemDataTBC),
  spells.lua (SpellDataTBC), quests.lua (questLookup, questDataTBC),
  objects.lua (objectDataTBC, objectLookup), and the WotLK
  creatures/items/quests/objects equivalents. ALL header statements (keys
  tables, raceKeys with VANILLA, objectResourceNames) stay eager and
  execute at their original TOC position. maps.lua, default_waypoints.lua,
  polygons.lua, tasks.lua, all *_fixes.lua, enchantIDs.lua, and the whole
  SoD tree (0.6 MB) are NOT converted at all.
- Verification: (1) the converter parses each chunk with luaparser and
  ASSERTS the AST contains only literals and table constructors — any
  identifier, function call, or operator outside a string literal is a hard
  error; (2) after conversion, an AST scan over all remaining eager SkuDB
  files confirms none of them reads a wrapped table path at file scope
  (guards against a hidden dependency like a fixes file indexing
  questDataTBC while building its local tables).

Risk A5 — semantic drift from one constructor to N assignments: duplicate
keys inside one constructor follow last-wins; records split across chunks
could reorder that. Array-part entries (no explicit [key]=) would change
indices if regrouped.
- Mitigation: the scanner enforces that EVERY top-level record in a wrapped
  table is explicitly [key]= keyed (true for all nine files' big tables;
  default_waypoints, which mixes forms, is excluded anyway) and fails hard
  on duplicate keys (none are expected; if one exists we want to KNOW).
- Verification: the in-game fingerprint (tool 3) compares the fully built
  tables old vs new — any semantic drift that somehow passed the byte
  checks shows up as a fingerprint mismatch.

Risk A6 — shared-global overwrite order (raceKeys/classKeys/questKeys/
objectKeys/spellKeys written up to three times with different values).
- Mitigation: keys tables are never wrapped; their execution order is
  untouched. The wrapped tables are each single-writer (base and WotLK
  write DIFFERENT paths: SkuDB.x vs SkuDB.WotLK.x).
- Verification: a grep audit (scripted, part of the converter's post-check)
  that every wrapped global path is assigned exactly once across the tree;
  fingerprints of the keys tables before/after.

Risk A7 — consumers reading before the streamed build finishes (stage 3
only; stage 2 keeps timing identical). Failure modes: hard nil-errors in
menus (annoying but LOUD), and the dangerous silent ones — SkuAuras builds
empty attribute lists and auras never fire this session; gameWorldObjects
scans miss everything; aqCombat caches a nil rank key.
- Mitigation: one master init coroutine with a strict order: datasets ->
  fixes+merge (sliced with the existing yield helper) -> readiness flag +
  ONE spoken announcement -> SkuAuras list build -> waypoint cache (which
  already streams and already has its own wpCacheReady + "Wegpunkte werden
  noch geladen" pattern — we extend that proven pattern, not invent one).
  A single POST-MERGE readiness flag (Sku:IsDataReady("skudb"), finally
  getting callers), not per-dataset flags — consumers must never see
  pre-merge data (see A8). Guard sweep over the audit's consumer list:
  menu entry points get the "wird geladen" non-actionable hint; scanner
  ticks (gameWorldObjects, SkuMob) skip cheaply when not ready; aqCombat's
  upvalue moves behind the flag or reads lazily; SkuAuras runs inside the
  sequence; the early QUEST_LOG_UPDATE read gets a bail-out guard.
  Profile-change re-entry paths call the same guarded entry points.
- Verification (audible + mechanical): scripted in-game drill — log in and
  IMMEDIATELY open the auction house / quest menu: must hear the loading
  hint, never an error sound; after the readiness announcement, re-open:
  real content. BugGrabber/SkuErrorLog empty after a full session
  (_read_buggrabber.py / _readerrlog.py). One known aura must fire in the
  first fight AFTER readiness. MetricPoint records readiness latency;
  _readperf.py shows it stays within budget (target: readiness announced
  well before the loading screen would have released you anyway on a fresh
  login, and a few seconds after a /reload).

Risk A8 — merge-window inconsistency: between dataset build and merge
completion, base tables exist WITHOUT WotLK rows — consumers reading in
that window see TBC-only data, and anything they cache (waypoint names
embedding merged creature names!) is silently wrong for the session.
- Mitigation: the single post-merge readiness flag (A7); the waypoint cache
  build is sequenced strictly after the merge, exactly as today's implicit
  order (PLAYER_LOGIN merge, PEW cache build) guarantees.
- Verification: /skudbcheck captures fingerprints at BOTH moments
  (post-build pre-merge, and post-merge); the post-merge fingerprint must
  equal the stage-0 baseline. A waypoint-cache spot fingerprint (names of N
  fixed cache entries) must match baseline too.

Risk A9 — memory REGRESSION from phase A: after conversion, the ~44 MB of
source strings are function constants; if builders stay referenced (like
the route builders do today), heap grows by that amount permanently, on top
of the built tables. During the build both string and table are resident
(peak).
- Mitigation: the new builder registry nils each builder global after its
  successful run; one forced collectgarbage at the end of the init sequence
  (the PEW forced GC already exists). This also retires the existing
  ~48 MB route-string leak (stage 1, shippable alone).
- Verification: in-code assert that every builder global is nil after
  build (logged to SkuDebugLog); /lsw (LoadStopwatch) memory numbers
  compared via _read_stopwatch.py — stage 1 alone must show ~50 MB less at
  settle; stage 3 must show no regression vs stage 2.

Risk A10 — partial build marked ready: today EnsureData sets ready=true
BEFORE running builders and calls them without pcall. With one builder that
was acceptable; with ~100 chunk builders, one bad chunk means a partially
built dataset that reports ready, forever, silently.
- Mitigation: the new registry pcalls EVERY chunk builder; on failure it
  marks the dataset FAILED (a third state, not ready), logs to SkuErrorLog
  with the chunk name, and SPEAKS a clear error ("Sku Datenbank Fehler,
  Datensatz X"). Consumers treat failed like not-ready (guards stay up) —
  degraded but honest, never silently partial.
- Verification (failure drill, run once per release of the converter):
  a py fault-injector deliberately corrupts one chunk in a scratch copy of
  one generated file; in-game you must HEAR the error announcement, and
  SkuErrorLog must name the chunk; restore the file, error gone. This
  proves the failure path exists before we ever need it.

Risk A11 — Lua 5.1 limits: a single chunk with >65536 constants fails to
compile ("constant table overflow"); the client is Lua 5.1 (no string.pack,
no goto).
- Mitigation: chunking per ~500 records keeps every loadstring chunk's
  constant pool small (this is exactly why Questie's per-chunk loadstring
  works); the generated OUTER file holds only N long-string constants and N
  function names — far below limits.
- Verification: luaparser parse (it is a 5.1 parser) + the stage-2 full
  in-game build behind the loading screen proves compilability of every
  chunk before any timing changes ship.

Risk A12 — /reload and mid-session re-entry: PLAYER_LOGIN fires on /reload
too (established), but profile switches re-run OnEnable/PEW handlers at
arbitrary times, and PLAYER_LEAVING_WORLD wipes SessionRouteData in some
configurations.
- Mitigation: the master init is idempotent (same EnsureData chokepoint
  semantics), readiness flags are only ever set forward within a session,
  and re-entry paths route through the same guarded entry points.
- Verification: scripted drill — three consecutive /reloads, one profile
  switch, one instance port, then _read_buggrabber.py + fingerprint check.
  All clean = pass.

Risk A13 — the data files are OUTSIDE git: a converter bug, a stray editor
save, or a bad regeneration cannot be detected or reverted by git.
- Mitigation and verification: the committed MANIFEST (tool 2) pins
  SHA-256 of every pristine .bak AND every generated output; a py check
  script re-hashes the tree and reports drift (run before and after any
  data work, and any time paranoia strikes — it is cheap). The .baks
  themselves are verified once against the upstream-src git blobs (two
  independent pristine copies). Revert of data = re-run the converter from
  .bak (deterministic) or --unwrap; revert of code = git revert.

## 3. Phase B risk catalog — compile-once binary cache in SavedVariables

Phase B applies ONLY to the read-only-after-merge, id-keyed datasets:
NpcData.Data, itemDataTBC, questDataTBC, objectDataTBC, SpellDataTBC (with
the WotLK merge BAKED IN at compile time — the compile pipeline is: build
from strings, run fixes+merge, encode the MERGED result). The locale lookup
tables (NpcData.Names, itemLookup, questLookup, objectLookup) STAY as Lua
tables — they are iterated wholesale by scanners (gameWorldObjects,
SkuAuras) and are the natural name-to-id indexes; random access cannot
serve full iteration efficiently. Route data, WaypointCache, Polygons,
DefaultWaypoints, maps, keys tables: excluded (mutable, aliased, metatabled,
or hot).

Risk B1 — lossy or wrong field encoding (the Questie warts): integer widths
too small, negative numbers mis-encoded, float quantization, huge keys.
- Mitigation (design rule): LOSSLESS BY CONSTRUCTION, accepting a size
  premium. Tagged self-describing values (one type byte per value: nil,
  false, true, small-int, negative-int, float-as-%.17g-string, string,
  table-begin/end) instead of Questie's positional schema. Numbers either
  exact scaled integers where the source has fixed decimals, or %.17g text
  — never binary IEEE packing (no string.pack in Lua 5.1, hand-packing
  doubles is exactly the subtle-bug surface we refuse).
- Verification: the validator demands EXACT equality (no tolerance — we
  have no quantization, so any difference is a bug), see B8. Plus golden
  vectors (tool 6): a tiny synthetic dataset containing every nasty shape
  (nil hole, empty string, false, 0, -1, -370, umlaut, ß, §, a 2^44 key, a
  17-digit float, deep nesting, {false} record) encoded and decoded
  in-game with the result spoken as pass/fail, and byte-compared against a
  committed expected blob by py.

Risk B2 — sentinel ambiguity (nil vs empty string vs false vs 0) — the
exact wart Questie codified ("nil" as literal text).
- Mitigation: the tagged format has distinct tags for each; there are no
  in-band sentinels at all.
- Verification: golden vectors cover every pair; the exact-equality
  validator would catch any conflation on real data.

Risk B3 — skipper/reader divergence (the classic corruption mode of
offset-based formats: the code that SKIPS a field disagrees with the code
that READS it, and every later field in the record shifts).
- Mitigation: with a fully tagged format the skipper IS the reader's
  structure walk (one code path), which removes most of the risk by
  design. Records additionally get an explicit length prefix, so record
  boundaries never depend on field-level walking.
- Verification: Questie's lockstep idea, kept anyway: a validator mode
  walks each record with the skipper and the reader and asserts identical
  end offsets, for EVERY record, at compile time (dev/verify runs).

Risk B4 — SavedVariables size, logout write cost, login parse cost: WoW
escapes binary as \ddd (~1.9x measured on Questie), writes the WHOLE file
at EVERY logout AND /reload, keeps a .bak copy, and parses it at login.
Our five datasets are bigger than Questie's (~6 MB blobs): plausibly
15-40 MB of blob = 30-80 MB on disk. A reload-heavy DEV workflow pays that
write every single time. This could eat the win.
- Mitigation: (1) blobs live in a separate tiny companion addon
  ("SkuDBCache", its own TOC, its own SavedVariables file) so Sku.lua stays
  small and parseable by all our py tooling, and the write cost is isolated
  and measurable; (2) per-dataset opt-in — stage 5 ships one dataset at a
  time and each must pay for itself; (3) the stage-4 DRY RUN measures the
  real cost with dummy blobs BEFORE any encoder is written.
- Verification: stage-4 numbers (logout time, login time, /reload time,
  file sizes at 10/30/60 MB dummy blobs) via LoadStopwatch and file stat;
  go/no-go thresholds agreed before stage 5 starts.

Risk B5 — stale cache after data or code changes: Questie keys on addon
version + locale + expansion, but OUR data files are edited live in dev
(symlink) without a version bump — a stale blob would serve last week's
data silently, the definition of "notice weeks later".
- Mitigation: the cache key includes a CONTENT HASH of each dataset's
  source (computed by the converter at generation time and embedded as a
  constant in the generated file), plus schema version, addon version,
  locale, and client build. Any data edit changes the embedded hash =>
  automatic recompile with a spoken notice ("Sku Datenbank wird neu
  erstellt"). Locale stays in the key as cheap insurance even though our
  data carries both locales.
- Verification (drill): edit one record in one source file, regenerate,
  /reload — must HEAR the recompile notice; query the changed record
  in-game (its menu entry) — must speak the new value. Then revert.

Risk B6 — blob corruption on disk (crash mid-logout, WTF copied between
machines, disk error). Questie ships user-facing recovery because this
genuinely happens.
- Mitigation: header magic + total length + per-record CRC in the blob;
  the reader treats ANY check failure as "cache invalid": clears the
  compiled flag, speaks a notice, and recompiles from the shipped strings
  next login (which always ship — full recovery is always possible; worst
  case is one slow login).
- Verification (drill): py fault-injector flips bytes inside the blob in
  the SavedVariables file while logged out; next login must announce the
  recompile (audible pass), and a subsequent /skudbverify run must be
  clean. Also an interrupted-compile drill: force-quit mid-compile; next
  login must detect the unset flag and restart cleanly (B10).

Risk B7 — writers and iterators against a read-only cache: consumers that
WRITE to the five datasets (only the fixes+merge, now baked at compile
time; the dev tool SkuSwitchDataToLK which REBINDS the tables — must be
disabled or adapted; nothing else per the audit) and consumers that
ITERATE them (pairs/next/#) — a proxy table serves lookups transparently
but iterates as EMPTY, a silent wrongness.
- Mitigation: access compatibility via a proxy table with an __index
  metamethod (decode on demand + memoize), so the hundreds of
  `SkuDB.questDataTBC[id]` read sites stay untouched. Iteration sites are
  found by grep (pairs/next/ipairs/# over the five paths — the audit
  already names the areas: SkuAuras PEW build, gameWorldObjects closures,
  waypoint-cache passes) and converted to an explicit iterator API that
  walks the pointer map. Lua 5.1 has no __pairs, so this is a hard
  boundary: the grep sweep plus a canary (in verify builds, a scripted
  pairs() over each proxy must yield zero non-memoized entries and logs a
  loud error if any code path relied on it).
- Verification: the grep sweep is scripted and its result (list of
  iterator sites + their conversion) is committed to this doc's appendix
  when stage 5 runs; the shadow-verify soak (B8) catches any missed reader
  behaviorally.

Risk B8 — the master risk: ANY encoder/decoder bug shipping unnoticed.
- Mitigation and verification in one: the SHADOW-VERIFY SOAK, the same
  method that certified the aura cache (22 mismatches found, then 0 over a
  raid). A verify mode builds BOTH the Lua tables (old path) and the blob
  (new path); the proxy serves from the blob but DEEP-COMPARES every
  decoded record against the live table on access, counting mismatches; a
  background coroutine additionally sweeps ALL records once per session
  comparing exhaustively (this is Questie's validator, promoted from
  dev-only to our acceptance gate). /skudbverify speaks the result ("Null
  Abweichungen bei dreißigtausend Datensätzen"), persisted to
  SavedVariables and read by py. Acceptance per dataset: full-sweep clean
  AND access-compare clean over at least 3 real play sessions including
  one instance/raid, THEN the dataset flips to blob-only. The old path
  stays in the code (behind the verify flag) until ALL datasets are done —
  flipping back is a one-line toggle.

Risk B9 — compile-time memory peak: raw tables + blob resident
simultaneously during the one-time compile (Questie has the same).
- Mitigation: compile streams per dataset and releases each dataset's raw
  tables before the next (unlike Questie, which frees only at the end);
  forced GC after. It is one announced slow login per cache key change.
- Verification: MetricPoint memory stamps during compile, read by
  _readperf.py; no action needed unless it approaches client limits.

Risk B10 — interrupted compile (logout/crash mid-compile).
- Mitigation: the compiled flag is written LAST, after all blobs and
  checks; a partial SavedVariables state without the flag is simply
  recompiled next login.
- Verification: the force-quit drill in B6.

Risk B11 — phase B under-delivers: if stage 4 shows the memory lives
mostly in route tables + WaypointCache (both excluded), the five-dataset
cache saves less than hoped and weeks of effort chase the wrong bytes.
- Mitigation: stage 4 IS the mitigation — a hard go/no-go gate with
  numbers, before any encoder code is written. The alternative lever
  (slimming the WaypointCache representation itself: interned strings,
  fewer duplicated subtables) is evaluated with the same numbers and may
  be the better buy. No commitment to B before that.

## 4. The verification toolkit (build once at stage 0, use every stage)

1. _db_convert.py — the converter, with verification BUILT IN (refuses to
   write on any failed check): raw-bytes record scanner (string/comment-
   aware brace depth), verbatim regrouping, bracket-level picking, luaparser
   literal-only AST assert per chunk, key-set + per-record byte compare +
   full reassembly compare, record counts, embedded content hashes,
   deterministic regeneration from .bak, and --unwrap (restore .bak).
2. MANIFEST-DB (committed to git, small): SHA-256 + size + record count for
   every pristine .bak and every generated output, plus the one-time
   cross-check of .baks against the upstream-src git blobs.
   _db_manifest.py --check re-hashes everything and prints PASS or the
   drifted files. This is the answer to "the data files are gitignored".
3. /skudbcheck (in-game) — deterministic per-dataset fingerprint of the
   BUILT tables: sorted-key deep walk (numbers formatted %.17g, strings
   raw), FNV-1a via the client's bit library, plus record counts; captured
   at two moments (post-build, post-merge); written to a dedicated
   SavedVariables field (eviction-proof, like wpcResult); speaks a short
   summary ("Prüfsumme geschrieben, sechs Datensätze"). The same fingerprint
   code runs on old and new builds — comparison never crosses languages.
4. _dbcheck.py — diffs two /skudbcheck captures (e.g. baseline commit vs
   converted commit) and prints PASS/FAIL per dataset with counts.
5. /skudbmem (in-game) — per-subtree memory estimator (walk SkuDB.*,
   SessionRouteData, WaypointCache: count tables/strings/numbers, sum
   string bytes) + collectgarbage("count") totals; dumped to
   SavedVariables; _dbmem.py ranks the results. Stage 4's ranking tool.
6. Golden vectors — committed synthetic mini-dataset covering every nasty
   shape (section 3, B1); encoded/decoded in-game with spoken pass/fail and
   byte-compared against a committed expected blob by py. Runs as the first
   step of every /skudbverify.
7. /skudbverify (in-game, phase B) — the shadow-verify soak: per-access
   deep compare + full background sweep, mismatch counter spoken and
   persisted; _dbverify.py reads the history.
8. Fault injectors (py) — corrupt one chunk (phase A drill) or flip blob
   bytes / truncate (phase B drill), with automatic restore. Failure paths
   get TESTED, not just written.

## 5. The staged plan

Every stage: separately shippable, has an audible in-game pass/fail, and a
one-command revert. Commit a checkpoint before each stage (standing rule).
Code reverts are git revert <sha>; data-file reverts are the converter's
--unwrap or regeneration from .bak (git cannot carry the ignored files —
that is exactly why the manifest exists).

Stage 0 — baseline and tooling. No addon behavior change.
- Build tools 1-5; capture the baseline: fingerprints (two /reloads must
  produce IDENTICAL fingerprints — proves determinism), memory ranking,
  manifest of pristine hashes (including the upstream-src cross-check).
- Pass: _dbcheck.py PASS on repeat captures; _db_manifest.py PASS.
- Revert: nothing to revert (new files only).
- Buys: nothing yet — it buys TRUST for everything after.

Stage 1 — free the route source strings. Tiny, ships alone.
- New builder registry behavior: pcall + nil the builder global after
  success + forced GC (retires risks A9/A10 for the EXISTING route path
  too). No format changes.
- Pass (audible/CLI): /lsw settle memory ~50 MB lower than baseline
  (_read_stopwatch.py); routes still work — "Nahe Routen" list non-empty
  after load, navigation beacon audible; BugGrabber clean.
- Revert: git revert <sha> (code only).
- Buys: ~50 MB of the heap, permanently. Also the error-path
  infrastructure phase A builds on.

Stage 2 — phase A1: format conversion with IDENTICAL timing.
- Convert the nine files (whitelist in A4). A tiny loader file at the END
  of the SkuDB TOC block calls the builders EAGERLY, synchronously — data
  exists at the same point in the load as today, semantics identical, zero
  felt change BY DESIGN. Keys/headers stay eager at original positions.
- Pass: fingerprints IDENTICAL to stage-0 baseline (both capture moments,
  _dbcheck.py PASS); record counts match manifest; error logs clean over a
  normal session; load time unchanged per stopwatch (within variance).
- Revert: git revert <sha> PLUS py -3 _db_convert.py --unwrap (restores
  the .baks). Two commands, scripted as one (_db_convert.py --revert-all).
- Buys: no felt change (deliberately). Retires the ENTIRE data-conversion
  risk class (A1-A6, A11, A13) while the old timing still guarantees no
  consumer can be surprised. This is the stage where subtle corruption
  would be caught, with the old behavior as a safety net.

Stage 3 — phase A2: streamed build + consumer guards. The felt login win.
- Master init coroutine (order per A7/A8): datasets -> fixes+merge
  (sliced) -> readiness flag + one announcement -> SkuAuras -> waypoint
  cache. Big per-frame budget while the loading screen is still up,
  standard budget after. Guard sweep per the audit list. Builder globals
  nil'ed as they complete; forced GC at the end.
- Pass (all audible or CLI): login speaks readiness within budget; opening
  AH/quest menus early yields the loading hint, never an error; a known
  aura fires in the first fight; near-waypoints correct after the existing
  cache announcement; fingerprints still match baseline; readiness latency
  and worst-frame stats via _readperf.py / _read_stopwatch.py; BugGrabber
  clean over three /reloads + profile switch + instance port (A12 drill).
- Revert: git revert of the stage-3 commits (stage 2's format stays in).
- Buys: removes Sku's remaining loading-screen bill — the ~1.3 s file
  compile, the ~0.7 s route build (now chunk-streamed too), the ~0.3 s
  SkuAuras build, and the merge — from blocking time into sliced
  background time. Sku's felt share of login drops from ~3.4 s toward
  ~0.5-1 s; /reload benefits the most (that is where the compile hurt).
  Memory: unchanged (that is phase B's job).

Stage 4 — measurement gate. No shipping, produces numbers and a decision.
- /skudbmem ranking: where do the ~880 MB actually live (five data tables
  vs lookup tables vs route tables vs WaypointCache vs the rest)?
- SavedVariables dry run: companion addon writes dummy blobs of 10, 30,
  60 MB; measure logout hang, login parse, /reload cost, file sizes, with
  _read_stopwatch.py. Establish the acceptable-blob-size budget.
- Output: appended to this doc as "Stage 4 results", with an explicit
  go/no-go per dataset for stage 5, and a comparison against the
  alternative WaypointCache-slimming lever (B11).

Stage 5 — phase B, one dataset at a time (order by stage-4 ranking;
tentatively items, creatures, quests, objects, spells).
- Per dataset: compile-once (merged, per B's design) into the companion
  SavedVariables; tagged lossless codec; per-record CRC; proxy __index +
  memoization; iterator-site conversion (B7 sweep); golden vectors; then
  the SHADOW-VERIFY SOAK (B8) — at least 3 sessions including an instance,
  zero mismatches spoken by /skudbverify — and only then flip that dataset
  to blob-only and measure the memory drop.
- Pass per dataset: "Null Abweichungen" spoken across the soak; /lsw
  memory drop recorded; recompile drill (B5) and corruption drill (B6)
  pass audibly.
- Revert per dataset: git revert of its flip commit — the table path
  remains in code behind the verify flag until ALL datasets are done.
- Buys: the memory. Rough expectation IF stage 4 confirms the data tables
  dominate their share: on the order of 150-350 MB off the heap, plus
  near-zero login data cost on every cached login (even the streamed build
  disappears except after updates). Honest bound: route tables and
  WaypointCache stay, so the floor is NOT 100 MB.

Stage 6 — explicitly parked: route data and WaypointCache memory.
- Needs a different design (copy-on-write overlay over a read-only shipped
  blob, plus reworking waypoint identity away from array positions — the
  audit shows wpIds, Links keys, and SavedVariables all embed positions
  today). That is a separate analysis with its own risk doc, only worth
  opening if stage 4 shows routes/cache dominate AND stage 5's pattern has
  proven itself in production. Not now.

## 6. What each stage buys — summary

- Stage 1: ~50 MB memory, immediately. No time change.
- Stage 2: zero felt change (by design); converts the risk of "subtle data
  corruption weeks later" into byte-verified certainty while old timing
  still guards behavior.
- Stage 3: the remaining ~2.5-3 s of Sku's loading-screen bill (file
  compile ~1.3 s + route build ~0.7 s + auras ~0.3 s + merge) moves into
  sliced background time with honest "loading" hints. Memory unchanged.
- Stage 4: numbers only — but they decide whether stage 5 targets the
  right bytes (risk B11).
- Stage 5: the only memory cure on the table. Plausible 150-350 MB
  reduction (pending stage 4), plus near-instant cached logins. The
  610-950 MB figure does NOT drop to double digits in any variant that
  excludes routes/cache — saying otherwise would be dishonest.
- The ~1.3 s file compile specifically: hidden from you at stage 3
  (streamed), actually GONE on cached logins at stage 5.

## 7. Recommendation

1. Do stages 0-3 (phase A) now. The conversion risk — the thing the user
   rightly fears — is fully mechanically verifiable (bytes in, bytes out,
   fingerprints equal), and stage 2 deliberately ships with UNCHANGED
   timing so the entire format risk retires while behavior cannot change.
   Stage 3 then delivers the felt login/reload win with the guard
   patterns we already proved on the waypoint cache.
2. Phase B: yes IN PRINCIPLE — it is the only cure for the memory, and the
   A/B measurement showed memory is Sku's real contribution to the
   combined-setup stall. But commit only after stage 4's numbers, dataset
   by dataset, each behind a zero-mismatch shadow soak. If stage 4 shows
   the route/cache half dominates, pivot to the cache-slimming lever
   before writing any binary codec.
3. Deliberately NOT doing, on the record:
   - No route data or WaypointCache in phase B (mutable, aliased, identity
     tied to array positions — the three landmines live there).
   - No lossy encodings, no quantization, no positional schemas, no
     hand-packed IEEE doubles. Lossless tagged format only, even if bigger.
   - No rewriting of record text during conversion — regroup verbatim
     bytes only; anything else forfeits byte-level verifiability.
   - No conversion of fixes files, tasks.lua, polygons.lua,
     default_waypoints.lua, maps.lua, enchantIDs.lua, keys tables, or the
     SoD tree (env-dependent, locale-dependent, metatabled, mixed-shape,
     hot, or too small to matter).
   - No blobs inside Sku's own SavedVariables file (separate companion
     addon — protects logout cost isolation AND all our py log tooling).
   - No LoadOnDemand split of SkuDB (option 4 of the report — relocates
     the freeze without removing it).
   - No big-bang: every stage ships alone, every dataset flips alone.
   - Not touching wiki.lua / the Era tree (not loaded; removing them from
     the ship is a packaging question for another day).

## Key references

- LOAD-PERF-OPTIONS.md (A/B results, option definitions),
  LOAD-PERF-NOTES.md (W3 handoff, option-B sketch), _wrap_deferred.py.
- Sku/SkuDeferredData.lua (EnsureData semantics; ready-before-build at
  line 25, no pcall at line 31, registration line 53).
- Sku/SkuNav/Core.lua: 3364 (EnsureData chokepoint), 3366-3393 (name split
  + SessionRouteData aliasing), 342-620 (cache passes), 3982
  (GetNonAutoLevel unguarded read), 3652-3720 (waypoint writes),
  771-855 (link pruning / SaveLinkDataToProfile alias break).
- Sku/SkuQuest/Core.lua: 71 (file-scope write), 1101-1296 (fix+merge),
  1744/1782 (early QUEST_LOG_UPDATE read).
- Sku/SkuAuras/Core.lua: 303-365 (unguarded PEW build), 590-598 + 1104-1140
  (enchant resolution, in-combat reads).
- Sku/SkuCore/aqCombat.lua: 887 (Keys upvalue). auctionHouse.lua: 3639-3641
  (cross-frame table captures).
- SkuDB/assets/polygons.lua: 3540-3592 (metatable). quests.lua: 3 (VANILLA).
  tasks.lua (L[] keys). Sku/.gitignore: 19-25 (what git cannot see).
- Questie (installed source): Database/compiler.lua (writers 55-92,
  validation 1115-1423, GetDBHandle 1425-1679, cache flags 1100-1112),
  Modules/QuestieStream.lua (raw byte stream 130-137, corruption guard
  242-253), Modules/QuestieInit.lua (cache-key check 166-226, staged
  progress 112-134), Modules/QuestieCleanup.lua (free + GC),
  Modules/Libs/ThreadLib.lua (ticker pump).
- Measured Questie SavedVariables: 19.6 MB file, ~5.7 MB blobs -> ~11.6 MB
  escaped on disk (~1.9x), doubled by WoW's .bak.

## Appendix: implementation log

### Stages 0-2 implemented (2026-07-06)

Commits: stage 0 = a66176a (toolkit), stage 1 = 15e4296 (registry), stage 2 =
the conversion commit that follows. Out-of-game verification is COMPLETE; the
in-game fingerprint comparison is still pending (drill below).

What shipped, and deviations from the plan text:
- Tools 1-5 built as planned (_db_convert.py, _db_manifest.py + MANIFEST-DB.txt,
  SkuDBTools.lua with /skudbcheck + /skudbmem, _dbcheck.py, _dbmem.py). Tools
  6-8 (golden vectors, /skudbverify, fault injectors) are phase-B tools and are
  deliberately NOT built yet.
- /skudbcheck is a MANUAL post-login command (captures the post-merge moment;
  runs sliced, speaks when done, keeps the last 12 captures). The automatic
  post-build/pre-merge capture of A8 is deferred to stage 3, where the master
  init sequence gives it a natural hook.
- The four lookup tables nest per locale; the converter chunks INSIDE each
  locale subtable (target paths like SkuDB.itemLookup.deDE). Duplicate locale
  keys are a hard error; duplicate RECORD keys are allowed, counted, and
  reported, because the data genuinely has them - creatures.lua deDE carries
  9104 duplicate ids (a second, partially untranslated block). Constructor
  last-wins semantics are preserved exactly by the ordered chunk merge; the
  key-SEQUENCE identity check pins this.
- Verification substitutions, both STRONGER than the letter of the plan: the
  per-chunk "AST literal-only assert" runs as a byte tokenizer with identical
  strength (identifiers/calls/operators outside strings are hard errors,
  unary minus before a number allowed) because ANTLR-based luaparser cannot
  chew 44 MB of table constructors; IN ADDITION all nine GENERATED files
  full-parse clean with luaparser (the long-string bodies lex as single
  tokens, ~25 s total), and the scaffolding also parses with bodies stubbed.
  Reassembly is checked on the WHOLE interior (chunk bodies concatenate to
  the byte-identical original interior including separators/comments), which
  subsumes the per-record byte compare.
- Numbers: stage-0 baseline manifest = 34 pristine files, ALL matching the
  upstream-src blobs (commit 22e81c0; SkuDB/Core.lua matches after CRLF->LF,
  it is git-tracked anyway). Stage 2 = 25 datasets, 471,132 records, 955
  chunks; regeneration is byte-deterministic (verified by re-run + rehash).
- SkuDBChunkHashes[path] = sha256 of each dataset's pristine interior is
  embedded in the generated files - that is the phase-B cache-key content
  hash (B5), free to carry now.
- SkuNav gained DevGetWaypointCacheTables() (dev accessor over the file-local
  cache tables) so /skudbmem can rank them for stage 4.

### Stage 4 results (2026-07-06) - memory ranking, go/no-go for stage 5

/skudbmem capture 09:45, Lua heap 1068 MB total (NOTE: whole Lua state incl.
28 other addons). Estimates are a ranking proxy (crude cost model, interned
strings counted per slot, aliases overlap by design) - ratios solid,
absolute MB approximate.

The ranking, grouped:
- NAV COMPLEX (mutable/aliased, excluded from phase B): WaypointCache
  221 MB (597k tables, 3.0M strings with 27.8 MB text, 2.2M numbers),
  routedata ~71 MB (SessionRouteData 72 MB = the same tables via the
  alias), SkuDBTMP (WotLK routes) 61 MB, the three name-lookup tables +
  index ~44 MB (largely the same interned strings, but 3x slot overhead).
  Rough non-overlapping total: ~350-400 MB - THE DOMINANT BLOCK.
- PHASE-B CANDIDATES: creatures 54+55 MB base+WotLK (post-merge they share
  row tables, true unique lower, incl. the Names lookups that stay Lua),
  SpellDataTBC 33.6 MB (best single target: one tree, no expansion twin),
  items 24+23 MB, objects 19+20 MB, quests 14+14 MB. Realistic phase-B
  addressable: ~150-200 MB.
- Everything else (maps, SoD, polygons, keys, enchants): < 6 MB combined.

Decision (risk B11 materialized - the excluded half dominates):
1. NO-GO for stage 5 as next step. A five-dataset binary codec buys maybe
   15-20% of the heap for weeks of work.
2. The better first buy is the WAYPOINTCACHE-SLIMMING lever: 221 MB for
   ~145k waypoints is ~4 tables and ~21 strings per waypoint - duplicated
   subtables/per-entry copies that interning/flattening can cut without
   any binary format, SavedVariables cost, or route-landmine contact.
   Needs its own analysis doc (stage-6 adjacent) before touching anything.
3. Second observation, analysis-only: the WotLK trees stay fully resident
   next to the merged base tables (~100 MB for creatures alone). Whether
   they can be dropped post-merge needs a consumer audit (enchantIDs and
   the enUS name lookups ARE read directly) - possible follow-up, not a
   blind win.
4. The stage-4 SavedVariables dry run (dummy blobs) is DEFERRED until/if a
   phase-B dataset is actually greenlit; the cache-slimming lever needs no
   SavedVariables at all.

### Stage 3 first in-game results (2026-07-06, same day)

- Works by user report: routes, auras, and "reloading felt quite fast".
- FINGERPRINT GATE PASSED: /skudbcheck "stage3" vs the pristine baseline -
  all 37 datasets identical. The streamed family-ordered build (fixes+merge
  reordered per family) produces bit-identical data.
- LoadStopwatch, comparable 29-addon reloads: stage 2 eager = to PEW 5.3 s /
  first frame 6.0 s; stage 3 = to PEW 3.6 s / first frame 3.8 s. About 1.7 s
  less loading screen, 2.2 s faster to first frame; worst post-load frame
  925 ms (was ~2000 ms). More small 50-ms spikes during the stream window -
  that IS the sliced build, by design. Memory unchanged (phase B's job).
- One BugSack error on every load, FIXED same day (commit 4d22621): the
  quest-marker path (QUEST_LOG_UPDATE -> UpdateZoneAvailableQuestList ->
  GetUnsortedAvailableQuestsTable) crashed on CROSS-FAMILY CHAINED indexing
  (NpcData.Data[npcId][zoneID] while quests were ready but creatures not;
  same latent chains in GetResultingWps through itemDataTBC). Lesson for
  the guard model: single-level indexed reads are nil-safe by shape, but
  CHAINS whose head id comes from an already-ready family are not - guard
  entry points of any path that RESOLVES ids across families. Guards added:
  UpdateZoneAvailableQuestList (4 family flags - not the global flag, the
  master tail runs before it is set), GetUnsortedAvailableQuestsTable,
  GetResultingWps; master tail refreshes the beacon list once at stream end.
- Still open: re-test after the fix (2 reloads, BugGrabber clean), aura in
  first fight, profile switch + instance port drill, /skudbmem capture.

### Stage 3 implemented (2026-07-06) - in-game test PENDING

The eager stage-2 loader is now the streamed master init in
SkuDB/ChunkLoader.lua. Loading-screen work removed: chunk compile+build
(~1.3 s), fixes+merge, SkuAuras lists. The route build (~0.7 s) deliberately
STAYS at PLAYER_LOGIN: it is one atomic loadstring blob (positional arrays =
not chunkable under the A5 rule), and moving it would trade hidden screen
time for a visible post-login freeze.

Design as built, including the deviations from the plan text:
- FAMILY-ORDERED streaming (user request: most relevant data first): quests
  -> creatures -> objects -> items -> spells. Per family: base+WotLK chunks
  -> that family's fix functions -> that family's merges (sliced) -> flag
  Sku:IsDataReady("skudb.<family>"). The fixes/merge audit showed the
  families are independent (fixes touch only their own tables plus the
  eager keys/zoneIDs), so per-family flags are SAFE and consumers get data
  in ~relevance order instead of waiting for one global gate. Risk A8 holds
  per family: a flag only flips AFTER that family's merge.
- The fix+merge block MOVED out of SkuQuest:PLAYER_LOGIN into the master
  (verbatim operations, same relative order per family; quest zone cache +
  UpdateAllQuestObjects + a silent CheckQuestProgress(true) run as the quest
  tail). SkuQuest:PLAYER_LOGIN keeps only its settings/timer lines.
- Guards, per the consumer audit: stage 2's scaffolding pre-creates every
  table and locale subtable, so ALL indexed reads are nil-safe by shape
  (same as an unknown id today) and menu/scan iterations degrade to empty
  for a few seconds and self-heal on the next tick/open. Only the ONE-TIME
  builds needed explicit sequencing: SkuAuras value lists (extracted to
  BuildAttributeValueLists, gated at PEW, built by the master - the
  silently-empty-auras case), the waypoint cache (CreateWaypointCache
  defers until creatures+objects are ready; master re-issues it async;
  wpCacheReady=false keeps the existing "Wegpunkte werden noch geladen"
  hint honest), and the quest zone cache (master tail).
- Escape hatch: SkuDB.ChunkStreamForceFinish() force-drains the stream
  synchronously; EnsureWaypointCacheComplete uses it so any path demanding
  the complete cache immediately still gets it (cost = the old freeze).
- Budget: 30 ms/frame for the first 8 s, 10 ms after. One readiness line
  ("Sku Datenbank bereit") when all families are up, then one forced GC.
- Failures: pcall everywhere, family marked FAILED (flag never set,
  consumers keep degrading), SkuErrorLog + spoken error, other families
  continue. PLAYER_LOGIN restart on /reload; profile re-entry sees flags.
- Fingerprint gate stays authoritative: /skudbcheck AFTER the readiness
  announcement must still equal the stage-0/2 baseline (the merge content
  is order-independent across families).

Stage-3 in-game drill (~10 min): (1) /reload - loading screen should be
~1.5-2 s shorter; hear "Sku Datenbank bereit" a few seconds after control
returns. (2) Immediately after a /reload open the quest menu and near
waypoints - at worst a brief loading hint, no error sound. (3) After the
announcement run /skudbcheck stage3, /reload, then _dbcheck.py against the
pristine capture - must PASS. (4) One aura must fire in the first fight.
(5) Three /reloads + a profile switch + an instance port, then
_read_buggrabber.py clean. (6) /skuperf load shows the family readiness
stamps, stream-complete ms and stream-GC ms.

### Stage-2 in-game acceptance: PASSED 2026-07-06

Executed (reverse order of the drill below - the converted files were already
live, so the pristine capture came last; equivalent proof):
- /skudbcheck baseline1 + baseline2 on the CONVERTED files (00:52, 00:56):
  _dbcheck.py 1 2 = PASS, all 37 datasets - fingerprint determinism across
  /reload AND the chunk loader building identically twice; zero MISSING
  datasets; BugGrabber free of chunk/SkuDB errors.
- --unwrap, then /skudbcheck pristine on the ORIGINAL files (01:03):
  _dbcheck.py 2 3 = PASS, all 37 datasets identical in count and fingerprint.
  Old format and new format build bit-identical tables through the full
  in-game pipeline (load, ordered chunk merge incl. the 9104 deDE dupe
  overwrites, SkuQuest fix+merge).
- Re-converted afterwards (deterministic); _db_manifest.py --check PASS.
The chunk format is the live format from here on. Still open from the drill:
/skudbmem ranking capture (stage-4 input) and the /lsw stage-1 memory
confirmation - both can ride along any future session.

### Stage-2 in-game acceptance drill (as originally planned; kept for reference)

The converted files are LIVE on disk (symlink). The baseline fingerprint must
come from the ORIGINAL format, so the drill flips the data files (code stays):

1. Out-of-game: py -3 Sku42-Rework-Docs/_db_convert.py --unwrap
   (restores pristine data files; .baks stay).
2. Log in fully. Run /skudbcheck baseline1 - it speaks "Datenbankpruefung
   gestartet", then after a while "Pruefsumme geschrieben, N Datensaetze".
3. /reload, run /skudbcheck baseline2, /reload (persists it).
4. Out-of-game: py -3 Sku42-Rework-Docs/_dbcheck.py 1 2 -> must PASS
   (proves the fingerprint itself is deterministic across reloads).
5. Out-of-game: py -3 Sku42-Rework-Docs/_db_convert.py --no-filescope-scan
   (regenerates the converted files, deterministic).
6. Log in fully. Errors check: BugSack must stay silent. Run
   /skudbcheck converted, then /reload.
7. Out-of-game: py -3 Sku42-Rework-Docs/_dbcheck.py 2 3 -> PASS = stage 2
   accepted (identical fingerprints and record counts, old vs new format).
8. Optional while there: /skudbmem once (stage-4 ranking data, ~1 min), and
   /lsw before/after to confirm stage 1's ~50 MB and unchanged load time.
9. py -3 Sku42-Rework-Docs/_db_manifest.py --check must PASS at the end.

If step 7 FAILS: py -3 _db_convert.py --unwrap + git revert of the stage-2
commit restores everything; the fingerprints tell WHICH dataset drifted.
