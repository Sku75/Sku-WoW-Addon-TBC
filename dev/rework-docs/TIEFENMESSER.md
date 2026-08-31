# Tiefenmesser beim Schwimmen — Archiv eines verworfenen Features

Stand 2026-08-31. Gebaut, in drei Iterationen im Spiel getestet, dann auf
Nutzerentscheid WIEDER AUSGEBAUT (Commit nach 650f69a). Dieses Dokument
enthaelt alles, um das System bei Bedarf 1:1 wiederherzustellen: die
Messergebnisse, die Sackgassen, den finalen Code und die offene Idee, die
es doch noch retten koennte (Pet-Orakel, unten).

## Warum verworfen

Der Zaehler stimmt beim Aufsteigen (nutzerbestaetigt: reines Leertaste-
Steigen und Leertaste+W liefern dieselbe Tiefe), aber beim Absinken zaehlt
er weiter, sobald man auf dem TIEFEN Gewaesserboden aufsitzt und die
Sinktaste haelt — im Test 120 Phantom-Meter. Der blinde Nutzer haelt X
gedrueckt, bis er GLAUBT unten zu sein, und bekommt dann eine
Fantasiezahl. Ohne Grund-Erkennung in tiefem Wasser ist das Feature mehr
verwirrend als nuetzlich. Fuers Fliegen ist eine Hoehenansage ebenso
wertlos: der Boden unter einem aendert seine Hoehe laufend, "Hoehe ueber
Startpunkt" sagt nichts ueber "Hoehe ueber Grund".

## Die harten Messergebnisse (alle im Spiel belegt, SkuDebugLog 2026-08-31)

1. **`GetUnitSpeed("player")` ist BEFEHLS-Geschwindigkeit, nicht Ist.**
   Am Meeresboden festgepinnt mit gehaltenem X meldet sie dauerhaft volle
   4.7 bei gemessener Horizontalbewegung 0.0 (Log 10:31–10:33; Aufstieg
   von angeblich "143 m" dauerte 5 s = echte Tiefe ~25 m). Folgen:
   "Speed < 0.3" kann den Boden NIE erkennen, und ein reiner
   Senkrecht-Tauchgang ist vom Auf-dem-Grund-Sitzen nicht unterscheidbar
   (beides h = 0).
2. **Die Engine VERWIRFT den blockierten Bewegungsanteil, statt ihn
   umzuleiten.** Beim Schleifen ueber den Boden mit X+W bleibt die
   gemessene Horizontalgeschwindigkeit beim befohlenen Anteil (~0.7 ×
   Gesamt) — identisch mit freiem Schraegtauchen. KEIN
   Geschwindigkeitsvergleich kann den Boden sehen.
3. **In tiefem Wasser gibt es KEINEN Zustandswechsel bei Bodenkontakt.**
   `IsSwimming()` bleibt an (Log 11:14–11:15: Gauge-Zeilen liefen durch
   jede Pinned-Phase). Der Steh-Zustand "running at the bottom"
   (`IsSwimming()` aus + `IsSubmerged()` an, warcraft.wiki.gg/API_IsSubmerged)
   existiert NUR auf BEGEHBAREM Grund (Watttiefe, Uferhaenge) — dort
   feuerte er korrekt ("Grund (stehend) bei 37.3 m" beim Aufschwimmen auf
   eine Uferboeschung).
4. **Der Untergetaucht-Marker** `IsSubmerged() and MirrorTimer1:IsVisible()`
   (derselbe, den die Schwimmen/Tauchen-Ansage in SkuCore/Core.lua ~1900
   seit jeher benutzt) ist zuverlaessig und gepollt — Oberflaeche = jeden
   Tick Anker 0, Querung nach unten = mindestens ~2 m.
   Wasseratmungs-Buffs VERLAENGERN die Atemleiste nur (Marker
   funktioniert); nur Zustaende ganz ohne Leiste (Wassergestalt) lesen
   dauerhaft 0.
5. **`GetUnitPitch` fehlt auf 2.5.6** (retail mit 7.1 wegen eines Exploits
   entfernt, nie in die Classic-Clients zurueckgekommen). `UnitPosition`
   liefert kein Z (fest 0). Es gibt KEINE lesbare Hoehe und KEINE lesbare
   Kollision.

## Was funktionierte

- Vertikal-Geschwindigkeit ableiten: `vert = sqrt(gesamt² − horizontal²)`
  mit `gesamt = GetUnitSpeed("player")` (Befehls-Geschwindigkeit — fuer
  Koppelnavigation genau richtig, solange nichts blockiert) und
  `horizontal` aus UnitPosition-X/Y-Deltas.
- Vorzeichen aus den gehookten Steig-/Sinktasten
  (`hooksecurefunc` auf JumpOrAscendStart/AscendStop/
  SitStandOrDescendStart/DescendStop → `SkuCore.ascendKeyHeld` /
  `descendKeyHeld`) — tastenbelegungs-unabhaengig.
- Drei Integrationsfaelle: reine Vertikaltaste (h < 0.6) → volle
  Befehls-Geschwindigkeit; Taste+Fahrt (0.6 ≤ h < 0.95·gesamt) → Defizit;
  ohne Taste mit Defizit (Anflug) → abwaerts angenommen.
- Ansagen: 5-m-Stufen ("N Meter"), "Oberflaeche" (nur nach Tauchgang
  tiefer 4 m), "Grund" beim Steh-Zustand (mit Watt-Schutz tDepth > 2,
  sonst spricht das Hineinwaten vom Strand Unsinn).
- Aufwaertszaehlung plausibel und konsistent; Loslassen der Sinktaste
  friert den Zaehler sofort ein (Befehls-Geschwindigkeit faellt auf 0).

## Die offene Rettungsidee: das Pet-Orakel (BlindSlash)

Das Retail-Blindenaddon BlindSlash (`interessante addons/BlindSlash/`,
core.lua ~8438, Modus "walle") nutzt `GetUnitSpeed("pet")`: fuer ANDERE
Einheiten ist das die ECHTE, servergemeldete Geschwindigkeit. Ein
folgendes Pet spiegelt die eigene Ist-Bewegung — Spieler befiehlt
Bewegung, Pet steht ≥1 s → Spieler steckt fest. Das waere der fehlende
Tiefwasser-Grund-Detektor (Pet stoppt, wenn man aufsitzt) — aber nur fuer
Jaeger/Hexer, Pet muss auf Folgen stehen (GetPetActionInfo /
PET_ACTION_FOLLOW gaten), und ob Pet-Speed auf 2.5.6 wirklich Ist-Wert
ist, ist UNGEPRUEFT. Ausserdem dort gefunden: "landed" beim Fliegen =
`IsFlying()`-Flip auf false beim Sinken (fuers Schwimmen gibt es kein
Analogon). Details: memory/blindslash-collision-study.

## Wiederherstellung — der komplette finale Code (v3)

Alles war im Neigungssperren-Block von `Sku/SkuCore/Core.lua` (nach
`SkuCore:TogglePitchLock`) integriert; der Tick existiert dort weiterhin
fuer die Neigungssperre. Zum Wiedereinbau:

### 1. SkuCore/Core.lua — Enabled-Getter (vor dem Tick-do-Block)

```lua
function SkuCore:DepthMeterEnabled()
   if not (SkuSettings and SkuSettings.Get) then return true end
   local tOk, tVal = pcall(SkuSettings.Get, SkuSettings, "SkuCore", "depthMeter")
   if not tOk then return true end
   return tVal ~= false
end
```

### 2. Tick-Locals (im do-Block neben den Gauge-Locals)

```lua
   local tDepth = 0
   local tDepthSpokenBucket = 0
   local tDepthLastSpoke = 0
   local tWasSubmerged = false
   local tWasOnBottom = false
```

### 3. Trocken-Zweig (im `if tWet ~= true then`, nach den Gauge-Resets;
ersetzt das einfache Zuruecksetzen)

```lua
         tWasSubmerged = false
         local tOnBottom = IsSubmerged() == true and _G["MirrorTimer1"] and _G["MirrorTimer1"]:IsVisible() == true
         if tOnBottom == true then
            if tWasOnBottom ~= true then
               tWasOnBottom = true
               dprint("DepthMeter", string.format("Grund (stehend) bei %.1f m", tDepth))
               -- Watt-Schutz: beim Hineinwaten vom Strand ist tDepth 0.
               if tDepth > 2 and SkuCore:DepthMeterEnabled() == true then
                  SkuOptions.Voice:OutputStringBTtts(L["Bottom"], false, true, 0.2)
               end
            end
         else
            tWasOnBottom = false
            tDepth, tDepthSpokenBucket = 0, 0
         end
```

### 4. Nass-Zweig (nach dem PitchGauge-Block, vor dem Anflug-Puls)

```lua
      if IsSwimming() == true then
         local tSubmerged = IsSubmerged() == true and _G["MirrorTimer1"] and _G["MirrorTimer1"]:IsVisible() == true
         if tSubmerged ~= true then
            if tDepth > 4 then
               dprint("DepthMeter", string.format("Anker 0 (war %.1f m)", tDepth))
               if SkuCore:DepthMeterEnabled() == true then
                  SkuOptions.Voice:OutputStringBTtts(L["Surface"], false, true, 0.2)
               end
            end
            tDepth, tDepthSpokenBucket = 0, 0
         else
            if tWasSubmerged ~= true then
               if tDepth < 2 then tDepth = 2 end
            end
            if tHTick and tDt and tSpeed and tSpeed > 0.3 then
               local tSign = 1
               if SkuCore.ascendKeyHeld == true and SkuCore.descendKeyHeld ~= true then tSign = -1 end
               local tVertKey = SkuCore.ascendKeyHeld == true or SkuCore.descendKeyHeld == true
               local tVert = 0
               if tVertKey and tHTick < 0.6 then
                  tVert = tSpeed
               elseif tHTick >= 0.6 and tHTick < 0.95 * tSpeed then
                  local tVertSq = tSpeed * tSpeed - tHTick * tHTick
                  tVert = tVertSq > 0 and math.sqrt(tVertSq) or 0
                  if tVert <= 0.5 then tVert = 0 end
               end
               if tVert > 0 then
                  tDepth = math.max(0, tDepth + tSign * tVert * tDt)
               end
            end
            if SkuCore:DepthMeterEnabled() == true then
               local tBucket = math.floor(tDepth / 5)
               if tBucket ~= tDepthSpokenBucket and tNow - tDepthLastSpoke > 1.2 then
                  if tBucket >= 1 then
                     SkuOptions.Voice:OutputStringBTtts((tBucket * 5).." "..L["Meter"], false, true, 0.2)
                  end
                  tDepthSpokenBucket = tBucket
                  tDepthLastSpoke = tNow
                  dprint("DepthMeter", string.format("%.1f m (Stufe %d)", tDepth, tBucket))
               end
            end
         end
         tWasSubmerged = tSubmerged == true
         tWasOnBottom = false
      else
         tDepth, tDepthSpokenBucket, tWasSubmerged, tWasOnBottom = 0, 0, false, false
      end
```

Voraussetzung: `tHTick`, `tDt`, `tSpeed`, `tNow` liefert der
Gauge-Abschnitt des Ticks (Instantanwert pro 0.25-s-Tick).

### 5. Tasten-Merker (in den vier bestehenden hooksecurefunc-Lambdas)

```lua
   if type(JumpOrAscendStart) == "function" then hooksecurefunc("JumpOrAscendStart", function() SkuCore.ascendKeyHeld = true tVerticalKeyPulse("ascendStart") end) end
   if type(AscendStop) == "function" then hooksecurefunc("AscendStop", function() SkuCore.ascendKeyHeld = false tVerticalKeyPulse("ascendStop") end) end
   if type(SitStandOrDescendStart) == "function" then hooksecurefunc("SitStandOrDescendStart", function() SkuCore.descendKeyHeld = true tVerticalKeyPulse("descendStart") end) end
   if type(DescendStop) == "function" then hooksecurefunc("DescendStop", function() SkuCore.descendKeyHeld = false tVerticalKeyPulse("descendStop") end) end
```

### 6. Menue-Toggle (SkuCore/Core.lua, neben PitchLockAutoMenuBuilder)

```lua
function SkuCore.DepthMeterMenuBuilder(aParentEntry)
   local tNewMenuEntry = SkuOptions:InjectMenuItems(aParentEntry, {
      Sku.deEn("Tiefenmesser beim Schwimmen",
         "Depth meter while swimming",
         "Profondimètre en nage"),
   }, SkuGenericMenuItem)
   tNewMenuEntry.sorting = true
   tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
      if SkuCore:DepthMeterEnabled() == true then return L["Yes"] else return L["No"] end
   end
   tNewMenuEntry.OnAction = function(self, aValue, aName)
      if aName == L["No"] then
         SkuSettings:Set("SkuCore", "depthMeter", false)
      elseif aName == L["Yes"] then
         SkuSettings:Set("SkuCore", "depthMeter", true)
      end
   end
   SkuOptions:MakeInPlaceToggle(tNewMenuEntry, L["No"], L["Yes"])
end
```

### 7. SkuCore/Options.lua

- In `SkuCore.defaults`: `depthMeter = true,`
- Im `SkuSettings:Register("SkuCore", {...})`-Schema:
  `["depthMeter"] = { scope = "profile", default = true, type = "boolean" },`
- Im Allgemein-`build`: `if SkuCore.DepthMeterMenuBuilder then SkuCore.DepthMeterMenuBuilder(self) end`

### 8. Locale-Schluessel

- enUS: `L["Surface"] = "Surface"`, `L["Bottom"] = "Bottom"`
- deDE: `L["Surface"] = "Oberfläche"`, `L["Bottom"] = "Grund"`
- frFR ueber den Store: `dev/rework-docs/_frfr_scratch/parts/frfr_keys.tsv`
  Zeilen `Surface<TAB>Surface` und `Bottom<TAB>Fond`, dann
  `py -3 dev/rework-docs/_frfr_locale.py assemble` + `verify`.
  (`L["Meter"]` existiert bereits in allen drei Locales.)

## Verwandt / weiterlebend

- Die Neigungssperre samt Geradestell-Impulsen (Commit 650f69a) bleibt im
  Addon — der Tick, `PitchLockLevelPulse`, die Tasten-Hooks und der
  PitchGauge (Log-Diagnose, misst BAHN-Winkel, nicht Koerperneigung)
  stammen aus derselben Arbeit.
- memory/camera-pitch-api-gap: die komplette Beweiskette.
- memory/blindslash-collision-study: das Pet-Orakel und der
  IsFlying-Flip als "gelandet".
