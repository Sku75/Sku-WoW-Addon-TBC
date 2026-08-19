---------------------------------------------------------------------------------------------------------------------------------------
-- SkuCore/taxi.lua - flightmaster taxi flights: track the route, announce the
-- next flight point you could land at, and request an early landing from a Sku
-- keybind.
--
-- FLIGHTMASTER ONLY - NOT VEHICLES
-- UnitOnTaxi("player") is the exact discriminator and is the same test the
-- Blizzard code uses to pick the taxi branch over VehicleExit():
--    if UnitOnTaxi("player") then TaxiRequestEarlyLanding() else VehicleExit() end
-- (Blizzard_ActionBar/Shared/PossessActionBar.lua and .../VehicleLeaveButton.lua)
-- Self-flying and flying vehicles keep player control and leave UnitOnTaxi
-- false. Every entry point re-checks it; we NEVER fall through to VehicleExit().
--
-- ============ WHAT THE LIVE FLIGHTS ESTABLISHED (2026-08-03/04) ==============
-- CONFIRMED WORKING in game: the announcement names the right flight point and
-- the keybind lands the player there instead of carrying on one stop further.
-- The road there disproved three plausible assumptions - written down so nobody
-- re-derives them:
--
-- 1. THE REQUEST ALWAYS LANDS YOU AT THE **NEXT** FLIGHT POINT. The client's own
--    TAXI_CANCEL_DESCRIPTION says so ("Laesst Euch am naechsten Flugpunkt
--    landen"), and TAXI_CANCEL is "Flug unterbrechen" - the early-landing UI
--    does ship for TBC. So the only correct answer to "where would I land" is
--    the next unpassed stop on the route, which is what the route cursor tracks.
--    An earlier reading of the evidence - "the server ignores the request" -
--    was WRONG: those calls went out at arbitrary moments and simply had nothing
--    useful to do.
--
-- 2. IsPossessBarVisible() LIES ON THIS CLIENT. It returned false for entire
--    flights while PossessButton2:IsShown() was true at the same moment. The
--    real on-screen affordance is MainMenuBarVehicleLeaveButton (leaveVisible),
--    and PossessButton2 has its shown flag set under a hidden parent - which is
--    why availability is read with IsVisible(), never IsShown(). That button is
--    visible for the WHOLE flight, so there is no "offer appears" window either;
--    announcements are driven by the route cursor and by proximity.
--
-- 3. NEAREST NODE IS THE WRONG QUESTION. Answering it produced Brackenwall - a
--    HORDE node, 1455 yards off, unusable by an Alliance player - because
--    C_TaxiMap.GetTaxiNodesForMap returns all ~40 continent nodes regardless of
--    faction or discovery. The route capture (hooksecurefunc("TakeTaxiNode"),
--    the one window in which GetNumRoutes/TaxiGetNodeSlot/TaxiNodeName still
--    work) supersedes it: every captured stop is by definition usable by this
--    character. Nearest-node survives only as a labelled fallback for a /reload
--    mid-flight, faction-filtered and proximity-gated.
--
-- ============ ANNOUNCEMENTS ARE OPTIONAL, THE FEATURE IS NOT ================
-- Einstellungen -> Allgemein -> "Flugpunkte zum Landen ansagen" (default ON,
-- SkuCore.taxiAnnounceLandingPoints) silences the two spoken lines for players
-- who find them chatty. Nothing else changes: the route is still captured and
-- tracked, /skutaxi still answers, and SKU_KEY_TAXICANCEL still requests the
-- landing AND still speaks its own confirmation - that one answers a key the
-- player just pressed, so it is not chatter. See tAnnounceEnabled.
--
-- LOGGING: everything under the "taxi:" prefix, gated behind /skudebug log on.
--   py -3 dev/rework-docs/_dbgtail.py 400 taxi:
-- `/skutaxi` dumps live state on demand.
---------------------------------------------------------------------------------------------------------------------------------------
local L = Sku.L
local _G = _G
local sqrt = math.sqrt
local floor = math.floor

SkuCore = SkuCore or LibStub("AceAddon-3.0"):NewAddon("SkuCore", "AceConsole-3.0", "AceEvent-3.0")

local Taxi = SkuCore:NewModule("Taxi", "AceEvent-3.0")
SkuCore.Taxi = Taxi   -- published handle

SkuCore:RegisterToggleableModule("Taxi", function()
   return Sku.deEn("Taxiflug", "Taxi flight", "Vol en taxi")
end)

-- How close we must come to a route stop to count it as passed. The taxi flies
-- directly over its nodes (measured: 0 yards at a takeoff point), so this only
-- has to survive the 0.5s sampling gap at flight speed.
local PASS_RADIUS = 250

-- Poll interval while airborne. Nothing event-driven has proven to track flight
-- progress, so this ticker is the mechanism, not a safety net. It exists ONLY
-- during an actual flight.
local POLL_INTERVAL = 0.5

-- Node-resolution cache: the scan walks every flight point on the map through
-- GetWorldPosFromMapPos and cannot change meaningfully within one tick.
local NODE_CACHE_TTL = 1.0

-- How close the next flight point has to be before we say "you can land here
-- now". Measured: the fallback spoke at 783 yd and the landing request two
-- seconds later worked, so ~800 yd is roughly 25 seconds of lead at flight
-- speed - enough to react, not so early that it is forgotten. This also gates
-- the no-route fallback entirely: a nearest-node guess only means something
-- when the node is actually near.
local APPROACH_DIST = 800

-- Standing this close to a flight point at the first scan of a flight means you
-- are ON it - that is the takeoff node, not a landing target.
local ORIGIN_RADIUS = 150

-- ★How far past the stop we asked to be put down at we have to get before we
-- believe the landing is NOT happening. A granted request ends the flight within
-- seconds of passing the node (measured: touchdown 10s after the pass), so this
-- only ever fires if the server ignored the request - and then the route must
-- come back to life rather than stay silent for the rest of the flight.
local LANDING_ABANDONED_DIST = 1000

-- Per-flight state.
local gTicker = nil          -- non-nil only while airborne
local gRoute = nil           -- ordered stop names captured at takeoff, destination last
local gRouteDest = nil       -- final destination name
local gStopIndex = nil       -- index into gRoute of the next unpassed stop
local gOfferOpen = false     -- is the on-screen cancel affordance up right now?
local gOriginNode = nil      -- flight point we took off from (fallback mode only)
local gApproachAnnounced = false -- said "landing possible" for the current target?
local gAnnouncedStop = nil   -- last stop name we spoke
local gRequestedFor = nil    -- stop name the player last requested a landing at
local gLastState = nil       -- last availability signature, for change-only logging
local gScanAt, gScanResult = 0, nil
local gLoggedOnce = {}

-- ★"The flight is over" as a fact WE own, not one we re-read from the client.
--
-- Everything here hangs off UnitOnTaxi, and UnitOnTaxi is a client flag - on
-- exactly the client where IsPossessBarVisible() lies (see tReadOffer). If it
-- ever lagged true after a landing, the ticker would keep polling on the ground,
-- and in fallback mode the target is the NEAREST flight point, which changes as
-- the player walks: every node coming inside APPROACH_DIST would announce "early
-- landing possible" long after the flight ended. So regaining player control -
-- which cannot happen in the middle of a flightmaster flight - latches this and
-- nothing may speak or re-arm the watch until a new flight is actually taken.
-- Deliberate trade: a spurious PLAYER_CONTROL_GAINED mid-flight (never observed;
-- it would already break the watch today via OnFlightEdge) would silence the
-- rest of that flight rather than risk speaking on the ground.
local gLanded = false

-- ★The origin and the destination of the CURRENT flight, learned from the route
-- capture instead of from geometry.
--
-- Neither is ever an "early landing": the origin is where the flight started
-- (landing there is not landing early, it is not having flown), the destination
-- is where it ends anyway. The route cursor already keeps the destination quiet,
-- but only while a route is known - and both standing user reports ("it named
-- the flight point I took off from" / "...the one I was flying to") describe the
-- nearest-node FALLBACK, which knows neither. TaxiGetNodeSlot(index, 1, true) is
-- the source slot of the first hop (the same srcSlot Blizzard's TaxiFrame.lua:172
-- draws its route line from), so both names are free at capture time; keeping
-- them makes the guard work in every mode.
local gFlightOrigin = nil

-- Distance to the current FALLBACK target on the previous tick. Without a route
-- the target is a pure geometry guess, and a guess that is getting farther away
-- is by definition behind us - the takeoff node in the seconds after takeoff
-- being exactly the case the reports describe. Costs at most one extra 0.5s tick
-- of lead; route mode is unaffected.
local gLastTargetDist = nil

-- ★The stop an early landing was actually REQUESTED and accepted for.
--
-- Distinct from gRequestedFor, which is only a "do not spam the server with the
-- same request twice" latch and is cleared whenever the offer blinks or the leg
-- changes. This one records a decided OUTCOME: the flight now ends at this stop.
-- Without it the route cursor treated the requested stop as an ordinary passed
-- waypoint, so ten seconds before actually landing at Ratschet the player was
-- told "next flight point Astranaar" - naming the stop the taxi would have flown
-- on to if they had NOT just asked to get off. Both announcements are wrong once
-- the landing is settled, so this silences them and holds the cursor where the
-- flight really ends.
local gLandingRequestedAt = nil

local function tLogOnce(aKey, ...)
   if gLoggedOnce[aKey] then return end
   gLoggedOnce[aKey] = true
   dprint(...)
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Is the player on a FLIGHTMASTER taxi flight? The one gate everything hangs off.
local function tOnTaxi()
   return UnitOnTaxi and UnitOnTaxi("player") == true
end

---------------------------------------------------------------------------------------------------------------------------------------
local function tSpeak(aText)
   if not (SkuOptions and SkuOptions.Voice) then return end
   pcall(function()
      -- aDoNotOverwrite = true: never clobber whatever else is being read.
      SkuOptions.Voice:OutputStringBTtts(aText, false, true, 0.2, true, nil, nil, 1)
   end)
end

---------------------------------------------------------------------------------------------------------------------------------------
-- ANNOUNCEMENTS ON/OFF - Einstellungen -> Allgemein, default ON.
--
-- Gates SPEECH ONLY. Route capture, the cursor, the offer watch and the
-- SKU_KEY_TAXICANCEL keybind (including ITS spoken feedback, which answers a key
-- the player just pressed) all keep running: silencing the chatter must never
-- cost anybody the ability to actually request the landing.
local function tAnnounceEnabled()
   if not (SkuSettings and SkuSettings.Get) then return true end
   local tOk, tVal = pcall(SkuSettings.Get, SkuSettings, "SkuCore", "taxiAnnounceLandingPoints")
   if not tOk then return true end
   return tVal ~= false
end

local function tAnnounce(aText, aWhat)
   if not tAnnounceEnabled() then
      dprint("taxi: announcement muted by the setting", tostring(aWhat))
      return
   end
   tSpeak(aText)
end

---------------------------------------------------------------------------------------------------------------------------------------
-- THE FLIGHT RECORD - the captured route, kept across a /reload.
--
-- A reload mid-flight was the one routine way to LOSE the route: the capture
-- hook fired before the reload and cannot fire again, so OnEnable came back
-- airborne with nothing but the nearest-node fallback for the rest of the
-- flight - precisely the mode that names the takeoff node and then the arrival
-- node. Sku users reload often, which fits "several people report it and I can
-- never reproduce it". So the capture is written to char-scoped saved variables
-- (flushed on every reload/logout) and read back while still on the taxi.
--
-- Stored by reference: the stop list is a fresh table per capture and is never
-- mutated afterwards - only gStopIndex moves, and that is written through.
local FLIGHT_RECORD_TTL = 30 * 60

local function tFlightStore()
   if not (SkuSettings and SkuSettings.Sub and SkuOptions and SkuOptions.db) then return nil end
   local tOk, tTbl = pcall(SkuSettings.Sub, SkuSettings, "SkuCore", nil, "char")
   if not tOk then return nil end
   return tTbl
end

local function tSaveFlight()
   local tStore = tFlightStore()
   if not tStore then return end
   if not gRoute then
      tStore.taxiFlight = nil
      return
   end
   tStore.taxiFlight = {
      stops  = gRoute,
      dest   = gRouteDest,
      origin = gFlightOrigin,
      index  = gStopIndex,
      t      = time and time() or 0,
   }
end

local function tUpdateFlightIndex()
   local tStore = tFlightStore()
   if tStore and type(tStore.taxiFlight) == "table" then
      tStore.taxiFlight.index = gStopIndex
   end
end

local function tClearFlight(aWhy)
   local tStore = tFlightStore()
   if tStore and tStore.taxiFlight ~= nil then
      dprint("taxi: flight record cleared", tostring(aWhy))
      tStore.taxiFlight = nil
   end
end

-- Restore only while genuinely airborne, and only from a RECENT record: one that
-- outlived its flight (a crash, or a capture that failed on a later flight) must
-- never furnish a route for a different flight.
--
-- Known limitation, deliberately not guessed around: the cursor comes back on
-- the leg it was written on, and a stop flown over DURING the loading screen is
-- not re-passed (the pass test needs 250 yards). The cursor then trails by one
-- leg for the rest of the flight. That costs a stale "next flight point" line
-- and a stale answer from the keybind - it can NOT produce a false "early
-- landing possible", because a stop behind us is receding. Auto-advancing on
-- "the following stop is closer" would fix it on a straight route and skip a
-- real leg on a route that bends, which is the worse failure.
local function tRestoreFlight()
   if gRoute then return false end
   if not tOnTaxi() then return false end
   local tStore = tFlightStore()
   local tRec = tStore and tStore.taxiFlight
   if type(tRec) ~= "table" or type(tRec.stops) ~= "table" or #tRec.stops == 0 then return false end
   local tNow = time and time() or 0
   if tRec.t and tNow > 0 and (tNow - tRec.t) > FLIGHT_RECORD_TTL then
      tClearFlight("record too old")
      return false
   end
   gRoute, gRouteDest, gFlightOrigin = tRec.stops, tRec.dest, tRec.origin
   gStopIndex = tRec.index or 1
   if gStopIndex > #gRoute then gStopIndex = #gRoute end
   dprint("taxi: ROUTE restored from the flight record",
      "index", tostring(gStopIndex) .. "/" .. tostring(#gRoute),
      "origin", tostring(gFlightOrigin), "dest", tostring(gRouteDest),
      "stops", table.concat(gRoute, " > "))
   return true
end

---------------------------------------------------------------------------------------------------------------------------------------
-- ROUTE CAPTURE
--
-- TakeTaxiNode(index) is called by the TaxiButton OnClick (Blizzard's
-- TaxiFrame.xml) - including when Sku's window walker clicks the button - and it
-- runs while the taxi map is still open, which is the only window in which
-- GetNumRoutes / TaxiGetNodeSlot / TaxiNodeName return anything. So this hook is
-- our one chance to learn the route.
--
-- TaxiGetNodeSlot(index, hop, false) gives the DESTINATION slot of each hop, in
-- order, so the destination names are the stop list. Every one of them is a node
-- this character can actually use - which is exactly the filter v1 was missing.
local function tCaptureRoute(aIndex)
   gRoute, gRouteDest, gStopIndex, gFlightOrigin = nil, nil, nil, nil
   -- Taking a node IS the start of a new flight - the one unambiguous "we are
   -- flying again" signal, and it precedes every event the client fires. It is
   -- also the moment any leftover record stops describing the current flight:
   -- drop it FIRST, so a capture that fails below cannot leave a stale route
   -- lying around for the restore to pick up.
   gLanded = false
   tClearFlight("new flight")

   if not (aIndex and _G.GetNumRoutes and _G.TaxiGetNodeSlot and _G.TaxiNodeName) then
      dprint("taxi: route capture skipped - taxi API unavailable", "index", tostring(aIndex))
      return
   end

   local tOkDest, tDest = pcall(_G.TaxiNodeName, aIndex)
   gRouteDest = tOkDest and tDest or nil

   local tOkNum, tHops = pcall(_G.GetNumRoutes, aIndex)
   if not tOkNum or not tHops or tHops < 1 then
      dprint("taxi: route capture got no hops", "index", tostring(aIndex), "dest", tostring(gRouteDest))
      return
   end

   -- Hop 1's SOURCE slot is the flight point we are leaving.
   local tOkSrc, tSrcSlot = pcall(_G.TaxiGetNodeSlot, aIndex, 1, true)
   if tOkSrc and tSrcSlot then
      local tOkSrcName, tSrcName = pcall(_G.TaxiNodeName, tSrcSlot)
      if tOkSrcName and tSrcName and tSrcName ~= "" then gFlightOrigin = tSrcName end
   end

   local tStops = {}
   for tHop = 1, tHops do
      local tOkSlot, tSlot = pcall(_G.TaxiGetNodeSlot, aIndex, tHop, false)
      if tOkSlot and tSlot then
         local tOkName, tName = pcall(_G.TaxiNodeName, tSlot)
         if tOkName and tName and tName ~= "" then
            tStops[#tStops + 1] = tName
         end
      end
   end

   if #tStops == 0 then
      dprint("taxi: route capture produced no stop names", "hops", tostring(tHops))
      return
   end

   gRoute, gStopIndex = tStops, 1
   dprint("taxi: ROUTE captured", "dest", tostring(gRouteDest), "origin", tostring(gFlightOrigin),
      "hops", tostring(tHops), "stops", table.concat(tStops, " > "))
   tSaveFlight()
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Scan the flight points on the player's current map, nearest first.
--
-- Filtering (only relevant in the no-route fallback - route stops are usable by
-- definition): GetTaxiNodesForMap hands back every node on the continent,
-- including the other faction's and ones this character has never discovered.
-- Landing at either is impossible, so they must not be offered. Neutral nodes
-- (Enum.FlightPathFaction.Neutral) stay in.
--
-- Returns a table: { mapId = n, nodes = { {name=, dist=, faction=, undiscovered=}, ... } }
local function tScanNodesUncached()
   if not (C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap and C_Map) then
      tLogOnce("noApi", "taxi: node scan skipped - no C_TaxiMap/C_Map")
      return nil
   end

   local tMapId
   if SkuNav and SkuNav.GetBestMapForUnit then
      local tOk, tId = pcall(function() return SkuNav:GetBestMapForUnit("player") end)
      if tOk then tMapId = tId end
   end
   if not tMapId and C_Map.GetBestMapForUnit then
      tMapId = C_Map.GetBestMapForUnit("player")
   end
   if not tMapId then
      tLogOnce("noMap", "taxi: node scan failed - no uiMapId")
      return nil
   end

   -- Player position on that map. Can be nil for a moment after a zone hand-off
   -- mid-flight (same client quirk SkuCore/Core.lua:1531 documents).
   local tPlayerPos = C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(tMapId, "player")
   if not tPlayerPos then
      tLogOnce("noPlayerPos" .. tostring(tMapId), "taxi: node scan failed - GetPlayerMapPosition nil", "map", tostring(tMapId))
      return nil
   end

   -- Player and nodes both go through GetWorldPosFromMapPos, so whatever x/y
   -- convention the returned vector uses cancels out in the delta.
   local function tWorld(aX, aY)
      if not (C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
      local tOk, _, tPos = pcall(C_Map.GetWorldPosFromMapPos, tMapId, CreateVector2D(aX, aY))
      if not tOk or not tPos then return nil end
      return tPos:GetXY()
   end

   local tPx, tPy = tPlayerPos:GetXY()
   local tPwx, tPwy = tWorld(tPx, tPy)

   local tOk, tNodes = pcall(C_TaxiMap.GetTaxiNodesForMap, tMapId)
   if not tOk or not tNodes or #tNodes == 0 then
      tLogOnce("noNodes" .. tostring(tMapId), "taxi: node scan found no nodes", "map", tostring(tMapId))
      return nil
   end

   local tMyFaction = UnitFactionGroup and UnitFactionGroup("player")
   local tNeutral = (Enum and Enum.FlightPathFaction and Enum.FlightPathFaction.Neutral) or 0
   local tHorde = (Enum and Enum.FlightPathFaction and Enum.FlightPathFaction.Horde) or 1
   local tAlliance = (Enum and Enum.FlightPathFaction and Enum.FlightPathFaction.Alliance) or 2

   local tOut = {}
   for _, tNode in ipairs(tNodes) do
      if tNode.position and tNode.name then
         local tNx, tNy = tNode.position:GetXY()
         local tDist
         if tPwx and tPwy then
            local tWx, tWy = tWorld(tNx, tNy)
            if tWx and tWy then
               tDist = sqrt((tWx - tPwx) ^ 2 + (tWy - tPwy) ^ 2)   -- yards
            end
         end
         if not tDist then
            -- No world conversion: normalized map distance, used only for ORDERING.
            tDist = sqrt((tNx - tPx) ^ 2 + (tNy - tPy) ^ 2) * 10000
         end
         local tUsable = true
         if tNode.isUndiscovered == true then tUsable = false end
         if tNode.faction == tHorde and tMyFaction == "Alliance" then tUsable = false end
         if tNode.faction == tAlliance and tMyFaction == "Horde" then tUsable = false end
         tOut[#tOut + 1] = {
            name = tNode.name, dist = tDist, usable = tUsable,
            faction = tNode.faction, undiscovered = tNode.isUndiscovered,
         }
      end
   end
   table.sort(tOut, function(a, b) return a.dist < b.dist end)
   return { mapId = tMapId, nodes = tOut }
end

local function tScanNodes(aForce)
   local tNow = GetTime and GetTime() or 0
   if aForce ~= true and gScanAt > 0 and (tNow - gScanAt) < NODE_CACHE_TTL then
      return gScanResult
   end
   gScanResult = tScanNodesUncached()
   gScanAt = tNow
   return gScanResult
end

-- The route stop names come from TaxiNodeName, the positions from
-- C_TaxiMap.GetTaxiNodesForMap. Both look like "Ratschet, Brachland" - but if
-- the two APIs ever disagree on spelling, an exact match would silently never
-- fire, the route cursor would never advance, and we would announce the first
-- stop forever. So: exact match first, then a normalized match on the part
-- before the comma. The first match of either kind is logged with both raw
-- strings so a single flight proves which path is doing the work.
local function tNormalizeNodeName(aName)
   if type(aName) ~= "string" then return nil end
   local tShort = aName:match("^([^,]+)") or aName
   return tShort:lower():gsub("^%s+", ""):gsub("%s+$", "")
end

local function tDistanceToStop(aScan, aName)
   if not (aScan and aName) then return nil end
   for _, tNode in ipairs(aScan.nodes) do
      if tNode.name == aName then
         tLogOnce("nameMatchExact", "taxi: stop name matched exactly", tostring(aName))
         return tNode.dist
      end
   end
   local tWanted = tNormalizeNodeName(aName)
   if not tWanted then return nil end
   for _, tNode in ipairs(aScan.nodes) do
      if tNormalizeNodeName(tNode.name) == tWanted then
         tLogOnce("nameMatchFuzzy", "taxi: stop name matched only after normalizing",
            "route", tostring(aName), "map", tostring(tNode.name))
         return tNode.dist
      end
   end
   return nil
end

-- Do two node names mean the same flight point? Same exact-then-normalized rule
-- tDistanceToStop uses, so "Ratschet, Brachland" still matches "Ratschet".
local function tSameNode(aA, aB)
   local tA, tB = tNormalizeNodeName(aA), tNormalizeNodeName(aB)
   return tA ~= nil and tB ~= nil and tA == tB
end

-- Is this name the flight's own start or end point? Both come from the capture.
local function tIsFlightEdgeNode(aName)
   return tSameNode(aName, gFlightOrigin) or tSameNode(aName, gRouteDest)
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Nearest USABLE node - the fallback when no route was captured (a /reload
-- mid-flight, or a takeoff the hook missed). Explicitly a guess.
--
-- The node you are taking off FROM is excluded: at takeoff it is the nearest by
-- a mile (measured: 2 yards) and announcing it says "you could land at the place
-- you are leaving", which is never what an early landing does. TAXI_CANCEL_DESCRIPTION
-- on this client is "Laesst Euch am naechsten Flugpunkt landen" - the NEXT one.
local function tNearestUsable(aScan)
   if not aScan then return nil end
   for _, tNode in ipairs(aScan.nodes) do
      if tNode.usable then
         if gOriginNode == nil and tNode.dist < ORIGIN_RADIUS then
            -- First scan of the flight and we are still sitting on a node: that
            -- is the origin. Remember it so it stops winning every later scan.
            gOriginNode = tNode.name
            dprint("taxi: origin node noted (excluded from the fallback)", tNode.name,
               "dist", tostring(floor(tNode.dist)))
         end
         if tNode.name ~= gOriginNode and not tIsFlightEdgeNode(tNode.name) then
            return tNode.name, tNode.dist
         end
      end
   end
   return nil
end

---------------------------------------------------------------------------------------------------------------------------------------
-- What flight point would an early landing put us at right now?
-- Returns: name, distance, source ("route" | "nearest")
local function tCurrentTarget(aScan)
   if gRoute and gStopIndex and gRoute[gStopIndex] then
      local tName = gRoute[gStopIndex]
      return tName, tDistanceToStop(aScan, tName), "route"
   end
   local tName, tDist = tNearestUsable(aScan)
   return tName, tDist, "nearest"
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Advance the route cursor past every stop we have flown over. Announces the new
-- next stop when the cursor moves - one announcement per hop, which is also what
-- re-arms the request (the stale-target bug in v1 was gRequested freezing the
-- announced node for the rest of the flight).
--
-- ★2026-08-16: the cursor must STOP at the destination instead of walking off
-- the end of the route. The taxi flies right into its last node, so the old loop
-- "passed" it too, gStopIndex became #gRoute+1, gRoute[gStopIndex] went nil, and
-- tCurrentTarget quietly degraded to the nearest-node FALLBACK - which knows
-- nothing about the route, so tVia flipped to "nearest" and the final-leg guard
-- below (written as `tVia == "route" and gStopIndex >= #gRoute`) stopped
-- applying. The destination was by then well inside APPROACH_DIST, so every
-- flight ended with "Vorzeitige Landung moeglich bei <destination>" a few
-- seconds before simply arriving there. The destination is not a stop you pass;
-- it is where the flight ends. Holding the cursor on it keeps tVia == "route"
-- through touchdown, so the guard holds and the keybind can still name it.
local function tAdvanceRoute(aScan)
   if not (gRoute and gStopIndex) then return false end
   local tMoved = false
   while gRoute[gStopIndex] do
      if gStopIndex >= #gRoute then
         tLogOnce("destReached", "taxi: cursor is on the destination - not advancing past it",
            tostring(gRoute[gStopIndex]))
         break
      end
      local tDist = tDistanceToStop(aScan, gRoute[gStopIndex])

      -- ★The stop we asked to be put down at is where the flight ENDS, so the
      -- cursor must stop there exactly like it stops on the destination. Passing
      -- it is arriving, not a hop. The escape hatch is geometric, not a timer: if
      -- we are ever this far beyond it and still airborne, the request plainly did
      -- not take and the route resumes on the spot.
      if gLandingRequestedAt and tSameNode(gRoute[gStopIndex], gLandingRequestedAt) then
         if tDist and tDist > LANDING_ABANDONED_DIST then
            dprint("taxi: requested landing did not happen - route resumes",
               tostring(gRoute[gStopIndex]), "dist", tostring(floor(tDist)))
            gLandingRequestedAt = nil
         else
            tLogOnce("holdRequested",
               "taxi: cursor holds on the stop the landing was requested at - the flight ends here",
               tostring(gRoute[gStopIndex]))
            break
         end
      end

      if tDist and tDist <= PASS_RADIUS then
         dprint("taxi: stop passed", gRoute[gStopIndex], "dist", tostring(floor(tDist)),
            "index", tostring(gStopIndex) .. "/" .. tostring(#gRoute))
         gStopIndex = gStopIndex + 1
         gRequestedFor = nil   -- new leg, new request allowed
         tMoved = true
         tUpdateFlightIndex()  -- so a /reload resumes on the right leg
      else
         break
      end
   end
   return tMoved
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Read every "can I land early" signal there is, and decide from the ones that
-- describe what is actually ON SCREEN.
--
-- ★2026-08-03, second flight: this is where v1/v2 went wrong. IsPossessBarVisible()
-- returned false for entire flights - but PossessButton2:IsShown() was TRUE at the
-- same moment, and TAXI_CANCEL is "Flug unterbrechen", so the early-landing UI
-- very much ships on 2.5.6 and sighted players really do get a button. The API
-- predicate and the frame disagree; the FRAME is what the player sees, so the
-- frame wins. IsShown() only reports the frame's own flag, so IsVisible() (which
-- walks the parent chain) is what we actually key off - a shown button under a
-- hidden PossessActionBar is not a button anybody can click.
--
-- Returns: available, detail (a table of every raw signal, for logging)
local function tReadOffer()
   local tLeave = _G.MainMenuBarVehicleLeaveButton
   local tBtn = _G.PossessButton2
   local tBar = _G.PossessActionBar

   local tEnabled
   if _G.GetPossessInfo then
      local tOk, _, _, tEnabledRet = pcall(_G.GetPossessInfo, _G.POSSESS_CANCEL_SLOT or 2)
      if tOk then tEnabled = tEnabledRet end
   end

   local tDetail = {
      possessApi     = _G.IsPossessBarVisible and _G.IsPossessBarVisible() == true,
      possessSlotOn  = tEnabled,
      canExit        = _G.CanExitVehicle and _G.CanExitVehicle() == true,
      btnShown       = tBtn and tBtn:IsShown() or false,
      btnVisible     = tBtn and tBtn:IsVisible() or false,
      barShown       = tBar and tBar:IsShown() or false,
      barVisible     = tBar and tBar:IsVisible() or false,
      leaveShown     = tLeave and tLeave:IsShown() or false,
      leaveVisible   = tLeave and tLeave:IsVisible() or false,
   }

   -- On-screen affordance = the offer. Either button counts; the client drives
   -- one of them and we do not yet know which, but a visible one is a real one.
   local tAvailable = (tDetail.btnVisible == true) or (tDetail.leaveVisible == true)
   return tAvailable, tDetail
end

-- Log the whole signal set on every CHANGE while airborne. Deliberately not
-- once-per-flight: the entire open question is WHEN the offer appears, and a
-- single sample at an arbitrary moment is exactly what failed to answer it.
local function tLogOffer(aSource, aAvailable, aDetail)
   local tKey = table.concat({
      tostring(aAvailable), tostring(aDetail.possessApi), tostring(aDetail.possessSlotOn),
      tostring(aDetail.canExit), tostring(aDetail.btnShown), tostring(aDetail.btnVisible),
      tostring(aDetail.barShown), tostring(aDetail.barVisible),
      tostring(aDetail.leaveShown), tostring(aDetail.leaveVisible),
   }, "|")
   if tKey == gLastState then return end
   gLastState = tKey
   dprint("taxi: offer state", "source", tostring(aSource), "AVAILABLE", tostring(aAvailable),
      "possessBtnVisible", tostring(aDetail.btnVisible), "possessBtnShown", tostring(aDetail.btnShown),
      "possessBarVisible", tostring(aDetail.barVisible), "possessBarShown", tostring(aDetail.barShown),
      "leaveVisible", tostring(aDetail.leaveVisible), "leaveShown", tostring(aDetail.leaveShown),
      "IsPossessBarVisible", tostring(aDetail.possessApi), "slotEnabled", tostring(aDetail.possessSlotOn),
      "canExitVehicle", tostring(aDetail.canExit))
end

---------------------------------------------------------------------------------------------------------------------------------------
function Taxi:Evaluate(aSource)
   if not Taxi:IsEnabled() then return end

   -- The flight is over even if UnitOnTaxi has not caught up yet.
   if gLanded == true then
      if gTicker then dprint("taxi: evaluate after landing - watch dropped", "source", tostring(aSource)) end
      Taxi:StopWatch()
      return
   end

   if not tOnTaxi() then
      if gTicker then dprint("taxi: flight ended, state reset", "source", tostring(aSource)) end
      Taxi:StopWatch()
      return
   end

   tLogOnce("strings", "taxi: client strings", "TAXI_CANCEL", tostring(_G.TAXI_CANCEL),
      "TAXI_CANCEL_DESCRIPTION", tostring(_G.TAXI_CANCEL_DESCRIPTION))

   local tAvailable, tDetail = tReadOffer()
   tLogOffer(aSource, tAvailable, tDetail)

   local tScan = tScanNodes()
   tAdvanceRoute(tScan)

   -- The offer went away.
   --
   -- ★It must NOT re-arm the announcement latches. Those are keyed to the target
   -- NAME, and a target that is still the same stop has already been announced -
   -- so wiping them here bought nothing and cost a duplicate: the leave button
   -- reads invisible for a moment (a zone hand-off mid-flight is enough), the
   -- next 0.5s tick sees the same stop still inside APPROACH_DIST with a blank
   -- gAnnouncedStop, and "Vorzeitige Landung moeglich bei X" is spoken a second
   -- time for the node it just named. A genuinely new target still re-arms them
   -- itself further down (tChanged), and a real flight end clears everything in
   -- StopWatch. gRequestedFor is the exception and IS cleared: if the affordance
   -- went away, whatever the server did with the last request is unknowable, so
   -- a fresh keypress must be allowed to resend.
   if tAvailable ~= true then
      if gOfferOpen == true then
         dprint("taxi: offer closed", "source", tostring(aSource), "wasTarget", tostring(gAnnouncedStop))
         gOfferOpen, gRequestedFor = false, nil
      end
      return
   end

   local tTarget, tDist, tVia = tCurrentTarget(tScan)
   if not tTarget then return end

   gOfferOpen = true

   -- The last stop on the route IS the destination, so landing early there is
   -- the same as arriving. True but useless, and on a direct flight (one hop) it
   -- would fire for every taxi the player ever takes. The keybind still reports
   -- it on demand.
   if tVia == "route" and gStopIndex and gRoute and gStopIndex >= #gRoute then
      tLogOnce("lastLeg", "taxi: on the final leg - early landing equals arriving, no announcement",
         tostring(tTarget))
      return
   end

   -- ★The flight's OWN start and end point are never an early landing. The
   -- cursor rule above already covers the destination while a route is known;
   -- this covers both of them in every mode - including the nearest-node
   -- fallback, which is where the "it announced the flight point I started at /
   -- was flying to" reports come from (a /reload mid-flight drops you into it,
   -- and there the takeoff node is simply the closest node for a while, and the
   -- arrival node is the closest one right before you land).
   -- The landing is already settled: we are being put down at this stop, so
   -- neither "next flight point" nor "early landing possible" says anything true
   -- any more. The keybind still answers "landing already requested at X".
   if gLandingRequestedAt and tSameNode(tTarget, gLandingRequestedAt) then
      tLogOnce("settled" .. tostring(tTarget),
         "taxi: landing already requested here - nothing left to announce", tostring(tTarget))
      gLastTargetDist = tDist
      return
   end

   if tIsFlightEdgeNode(tTarget) then
      tLogOnce("edge" .. tostring(tTarget),
         "taxi: target is this flight's own origin/destination - not announced", tostring(tTarget),
         "origin", tostring(gFlightOrigin), "dest", tostring(gRouteDest), "via", tostring(tVia))
      gLastTargetDist = tDist
      return
   end

   -- TWO announcements per leg, because they answer different questions.
   --
   -- ★2026-08-04: the first route-mode flight named Thalanaar once, at takeoff,
   -- 4115 yards out - correct, and useless. By the time the player was actually
   -- near it (the moment you decide whether to get off) nothing was said, and
   -- the final-leg rule above then silenced the rest of the flight. The
   -- fallback's behaviour that felt right was purely proximity-driven (it spoke
   -- at 783 yd and the landing request two seconds later worked), so proximity
   -- is what has to drive the actionable announcement.
   --
   --   1. target CHANGED  -> "next flight point X"  : context, at takeoff and
   --      after each hop, at whatever distance.
   --   2. target APPROACHED -> "early landing available at X" : the decision
   --      moment, ~800 yd out, about 25 seconds of lead at flight speed.
   local tChanged = (tTarget ~= gAnnouncedStop)
   local tNear = (tDist ~= nil and tDist <= APPROACH_DIST)

   -- ★FALLBACK ONLY: the target must be getting CLOSER before we call it a
   -- landing option. Route mode knows what is ahead; the fallback does not, so
   -- without this a node we are flying AWAY from - the takeoff point, in the
   -- seconds after takeoff, while it is still inside APPROACH_DIST - reads
   -- exactly like one we are approaching. Two samples 0.5s apart settle it,
   -- which is nothing against ~25 seconds of lead.
   local tClosing = true
   if tVia ~= "route" then
      tClosing = (tChanged ~= true) and tDist ~= nil and gLastTargetDist ~= nil and tDist < gLastTargetDist
      if tNear and not tClosing then
         dprintv("taxi: fallback target near but not closing - held", tostring(tTarget),
            "dist", tostring(tDist and floor(tDist)), "prev", tostring(gLastTargetDist and floor(gLastTargetDist)))
      end
   end

   if tChanged then
      gAnnouncedStop = tTarget
      gApproachAnnounced = false
      gRequestedFor = nil   -- new leg -> a request is meaningful again

      -- Without a route the "target" is a geometry guess that changes constantly
      -- and means nothing at range - that is how v1 ended up naming a Horde
      -- outpost 1455 yd away mid-Barrens. In fallback mode only the proximity
      -- announcement below is allowed to speak.
      if tVia == "route" and not tNear then
         dprint("taxi: ANNOUNCE next stop", tostring(tTarget), "dist", tostring(tDist and floor(tDist)),
            "source", tostring(aSource), "index", tostring(gStopIndex) .. "/" .. tostring(gRoute and #gRoute))
         tAnnounce(Sku.deEn("Naechster Flugpunkt ", "Next flight point ", "Prochain point de vol ") .. tTarget, "next stop")
      elseif tVia == "nearest" then
         dprintv("taxi: fallback target changed (silent until near)", tostring(tTarget),
            "dist", tostring(tDist and floor(tDist)))
      end
   end

   if tNear and tClosing and gApproachAnnounced ~= true then
      gApproachAnnounced = true
      dprint("taxi: ANNOUNCE landing possible", tostring(tTarget), "dist", tostring(tDist and floor(tDist)),
         "via", tostring(tVia), "source", tostring(aSource),
         "index", tostring(gStopIndex) .. "/" .. tostring(gRoute and #gRoute))
      tAnnounce(Sku.deEn("Vorzeitige Landung moeglich bei ", "Early landing available at ", "Atterrissage anticipé possible à ") .. tTarget, "landing possible")
   end

   gLastTargetDist = tDist
end

---------------------------------------------------------------------------------------------------------------------------------------
-- The action behind SKU_KEY_TAXICANCEL. Called from the Sku keybind dispatch in
-- SkuCore/Core.lua, i.e. from a real key press, so any hardware-event
-- requirement is satisfied. Confirmed NOT taint-blocked (no addon_action_blocked
-- for it in SkuErrorLog across four live calls).
function Taxi:RequestEarlyLanding()
   if not Taxi:IsEnabled() then return end

   if not tOnTaxi() then
      dprint("taxi: key pressed but not on a flightmaster taxi - ignored")
      tSpeak(Sku.deEn("Kein Taxiflug", "Not on a taxi flight", "Pas en vol taxi"))
      return
   end

   local tScan = tScanNodes(true)
   local tTarget, tDist, tVia = tCurrentTarget(tScan)
   local tAvailable, tDetail = tReadOffer()

   dprint("taxi: KEY request", "target", tostring(tTarget), "dist", tostring(tDist and floor(tDist)),
      "via", tostring(tVia), "routeIndex", tostring(gStopIndex) .. "/" .. tostring(gRoute and #gRoute),
      "AVAILABLE", tostring(tAvailable), "possessBtnVisible", tostring(tDetail.btnVisible),
      "leaveVisible", tostring(tDetail.leaveVisible), "IsPossessBarVisible", tostring(tDetail.possessApi),
      "slotEnabled", tostring(tDetail.possessSlotOn), "canExitVehicle", tostring(tDetail.canExit),
      "alreadyRequestedFor", tostring(gRequestedFor))

   if not _G.TaxiRequestEarlyLanding then
      dprint("taxi: TaxiRequestEarlyLanding missing on this client")
      tSpeak(Sku.deEn("Nicht verfuegbar", "Not available", "Non disponible"))
      return
   end

   -- Repeat press for the same leg: say where it stands rather than spamming the
   -- server with a request it already has.
   if gRequestedFor and gRequestedFor == tTarget then
      dprint("taxi: repeat request for the same stop - not resent")
      tSpeak(Sku.deEn("Landung bereits angefordert bei ", "Landing already requested at ", "Atterrissage déjà demandé à ") .. tTarget)
      return
   end

   local tOk, tErr = pcall(_G.TaxiRequestEarlyLanding)
   dprint("taxi: TaxiRequestEarlyLanding called", "ok", tostring(tOk), "err", tostring(tErr),
      "target", tostring(tTarget))
   if not tOk then
      tSpeak(Sku.deEn("Anforderung fehlgeschlagen", "Request failed", "Échec de la demande"))
      return
   end

   gRequestedFor = tTarget
   gLandingRequestedAt = tTarget
   if tTarget then
      tSpeak(Sku.deEn("Landung angefordert bei ", "Landing requested at ", "Atterrissage demandé à ") .. tTarget)
   else
      tSpeak(Sku.deEn("Landung angefordert", "Landing requested", "Atterrissage demandé"))
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
function Taxi:StartWatch(aSource)
   if gTicker then return end
   -- Single chokepoint for the landed latch: no event may re-arm the watch
   -- between a landing and the next TakeTaxiNode / PLAYER_CONTROL_LOST.
   if gLanded == true then return end
   -- A /reload mid-flight arrives here airborne with no route (the capture hook
   -- fired before the reload): the flight record still has it.
   tRestoreFlight()
   dprint("taxi: watch started", "source", tostring(aSource),
      "route", tostring(gRoute and table.concat(gRoute, " > ")))
   gOfferOpen, gAnnouncedStop, gRequestedFor, gLastState, gApproachAnnounced = false, nil, nil, nil, false
   gScanAt, gScanResult, gLoggedOnce, gOriginNode = 0, nil, {}, nil
   gLastTargetDist, gLandingRequestedAt = nil, nil
   gTicker = C_Timer.NewTicker(POLL_INTERVAL, function() Taxi:Evaluate("poll") end)
   Taxi:Evaluate(aSource or "start")
end

function Taxi:StopWatch()
   -- ★The route must only be dropped by a real flight END, never by the
   -- teardown path running before the flight has begun. At takeoff the order is
   -- TakeTaxiNode (route captured) -> PLAYER_CONTROL_LOST (UnitOnTaxi STILL
   -- FALSE) -> PLAYER_MOUNT_DISPLAY_CHANGED (now true). The middle event took
   -- the "off taxi" branch and wiped the route a few milliseconds after it was
   -- captured, so every flight fell back to nearest-node guessing even though
   -- the capture itself had worked. Only tear the route down if we were
   -- genuinely watching a flight.
   local tWasWatching = gTicker ~= nil
   if gTicker then
      gTicker:Cancel()
      gTicker = nil
      dprint("taxi: watch stopped")
   end
   if tWasWatching then
      gRoute, gRouteDest, gStopIndex, gFlightOrigin = nil, nil, nil, nil
      tClearFlight("flight ended")
   end
   gOfferOpen, gAnnouncedStop, gRequestedFor, gLastState, gApproachAnnounced = false, nil, nil, nil, false
   gOriginNode = nil
   gLastTargetDist, gLandingRequestedAt = nil, nil
   gScanAt, gScanResult = 0, nil
end

---------------------------------------------------------------------------------------------------------------------------------------
-- UI errors while airborne. A server-side refusal of the landing request would
-- surface here and nowhere else - this is the evidence that settles finding 4.
function Taxi:UI_ERROR_MESSAGE(aEvent, ...)
   if not tOnTaxi() then return end
   local a1, a2 = ...
   dprint("taxi: UI_ERROR_MESSAGE while airborne", tostring(a1), tostring(a2))
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Raw event funnel. Kept broad on purpose: no event has yet proven to track
-- flight progress, so the log still has to show what the client does fire.
function Taxi:OnTaxiSignal(aEvent, ...)
   if not tOnTaxi() then
      if gTicker then Taxi:Evaluate(aEvent) end
      return
   end
   dprintv("taxi: event", tostring(aEvent), tostring((select(1, ...))))
   Taxi:StartWatch(aEvent)
   -- Evaluate on the event too, not just on the next poll tick: the offer-state
   -- log line then carries the event that coincided with the button appearing,
   -- which is what tells us whether the poll can be dropped later.
   Taxi:Evaluate(aEvent)
end

---------------------------------------------------------------------------------------------------------------------------------------
function Taxi:OnFlightEdge(aEvent)
   -- Control lost = a flight is beginning (UnitOnTaxi is still false at this
   -- point - see StopWatch); control gained = it is over, full stop.
   if aEvent == "PLAYER_CONTROL_LOST" then
      gLanded = false
   elseif aEvent == "PLAYER_CONTROL_GAINED" then
      if gTicker or gLanded ~= true then dprint("taxi: control regained -> flight over", tostring(aEvent)) end
      gLanded = true
      Taxi:StopWatch()
      -- StopWatch only drops the record when it was actually watching; a landing
      -- is the end of the flight either way.
      tClearFlight("control regained")
      return
   end

   if tOnTaxi() and gLanded ~= true then
      dprint("taxi: flight edge -> on taxi", tostring(aEvent))
      Taxi:StartWatch(aEvent)
   else
      if gTicker then dprint("taxi: flight edge -> off taxi", tostring(aEvent)) end
      Taxi:StopWatch()
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
local gTakeHookInstalled = false

function Taxi:OnEnable()
   -- Route capture. hooksecurefunc is permanent, so install once; the hook body
   -- guards on IsEnabled so a disabled module captures nothing.
   if not gTakeHookInstalled and _G.TakeTaxiNode then
      hooksecurefunc("TakeTaxiNode", function(aIndex)
         if not Taxi:IsEnabled() then return end
         tCaptureRoute(aIndex)
      end)
      gTakeHookInstalled = true
   end

   -- Signals worth watching. Demoted to dprintv (verbose) now that we know they
   -- do not mark an offer window - UPDATE_BONUS_ACTIONBAR alone would otherwise
   -- dominate the ring.
   Taxi:RegisterEvent("UPDATE_POSSESS_BAR", "OnTaxiSignal")
   Taxi:RegisterEvent("TAXI_NODE_STATUS_CHANGED", "OnTaxiSignal")
   Taxi:RegisterEvent("UPDATE_BONUS_ACTIONBAR", "OnTaxiSignal")
   Taxi:RegisterEvent("VEHICLE_UPDATE", "OnTaxiSignal")

   -- Server refusals of the landing request.
   Taxi:RegisterEvent("UI_ERROR_MESSAGE", "UI_ERROR_MESSAGE")

   -- Flight start/end. SkuCore/Core.lua already announces taxi;started /
   -- taxi;ended off this same pair; we only arm and disarm the watch.
   Taxi:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED", "OnFlightEdge")
   Taxi:RegisterEvent("PLAYER_CONTROL_LOST", "OnFlightEdge")
   Taxi:RegisterEvent("PLAYER_CONTROL_GAINED", "OnFlightEdge")
   Taxi:RegisterEvent("PLAYER_ENTERING_WORLD", "OnFlightEdge")

   if SkuOptions and SkuOptions.RegisterChatCommand then
      SkuOptions:RegisterChatCommand("skutaxi", function() Taxi:SlashDump() end)
   end

   -- A /reload mid-flight leaves us airborne with no edge event and no route
   -- (the hook fired before the reload) - StartWatch restores it from the flight
   -- record, and the nearest-usable fallback still covers a record-less case.
   -- Not airborne: whatever is on file describes a flight that is over. Dropped
   -- on a short delay because the AceDB may not be up yet this early.
   if tOnTaxi() then
      Taxi:StartWatch("OnEnable")
   elseif C_Timer and C_Timer.After then
      C_Timer.After(5, function() if not tOnTaxi() then tClearFlight("not airborne at load") end end)
   end
end

function Taxi:OnDisable()
   Taxi:UnregisterAllEvents()
   Taxi:StopWatch()
end

---------------------------------------------------------------------------------------------------------------------------------------
-- /skutaxi - live state, printed to chat so it can be captured without turning
-- the debug ring on first.
function Taxi:SlashDump()
   local tScan = tScanNodes(true)
   local tTarget, tDist, tVia = tCurrentTarget(tScan)
   local tAvailable, tDetail = tReadOffer()
   local function tOut(aLine) if SkuOptions and SkuOptions.Print then SkuOptions:Print(aLine) else print(aLine) end end

   tOut("Sku taxi: onTaxi=" .. tostring(tOnTaxi()) .. " available=" .. tostring(tAvailable) .. " TAXI_CANCEL=" .. tostring(_G.TAXI_CANCEL))
   tOut("  possessBtn visible=" .. tostring(tDetail.btnVisible) .. " shown=" .. tostring(tDetail.btnShown) ..
      " | bar visible=" .. tostring(tDetail.barVisible) .. " shown=" .. tostring(tDetail.barShown))
   tOut("  leaveBtn visible=" .. tostring(tDetail.leaveVisible) .. " shown=" .. tostring(tDetail.leaveShown) ..
      " | IsPossessBarVisible=" .. tostring(tDetail.possessApi) .. " slotEnabled=" .. tostring(tDetail.possessSlotOn) ..
      " canExitVehicle=" .. tostring(tDetail.canExit))
   if gRoute then
      tOut("  route(" .. tostring(gStopIndex) .. "/" .. tostring(#gRoute) .. ") -> " .. table.concat(gRoute, " > "))
   else
      tOut("  route: none captured (using nearest-usable fallback)")
   end
   tOut("  origin=" .. tostring(gFlightOrigin) .. " dest=" .. tostring(gRouteDest) ..
      " announce=" .. tostring(tAnnounceEnabled()))
   tOut("  target=" .. tostring(tTarget) .. " dist=" .. tostring(tDist and floor(tDist)) .. " via=" .. tostring(tVia))
   tOut("  landingRequestedAt=" .. tostring(gLandingRequestedAt))
   tOut("  requestedFor=" .. tostring(gRequestedFor) .. " watching=" .. tostring(gTicker ~= nil) ..
      " landed=" .. tostring(gLanded))
   if tScan then
      local tShown = 0
      for _, tNode in ipairs(tScan.nodes) do
         if tShown >= 5 then break end
         tShown = tShown + 1
         tOut("   node " .. tNode.name .. " " .. tostring(floor(tNode.dist)) ..
            (tNode.usable and "" or " [unusable faction=" .. tostring(tNode.faction) .. " undiscovered=" .. tostring(tNode.undiscovered) .. "]"))
      end
   end
   dprint("taxi: /skutaxi dump", "onTaxi", tostring(tOnTaxi()), "target", tostring(tTarget), "via", tostring(tVia))
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Einstellungen -> Allgemein: "Flugpunkte zum Landen ansagen" (default ON).
--
-- Built here rather than as an AceConfig node so the toggle sits next to the
-- feature it belongs to; SkuCore/Options.lua calls this from the Allgemein spec,
-- the same way it calls aqCombat.CombatMenuOpenMenuBuilder. SPEECH ONLY - the
-- keybind and the tracking stay on at "No" (see tAnnounceEnabled).
function Taxi.AnnounceMenuBuilder(aParentEntry)
   local tNewMenuEntry = SkuOptions:InjectMenuItems(aParentEntry, {
      Sku.deEn("Flugpunkte zum Landen ansagen", "Announce flight points you can land at",
         "Annoncer les points de vol où atterrir"),
   }, SkuGenericMenuItem)
   tNewMenuEntry.dynamic = true
   tNewMenuEntry.sorting = true
   tNewMenuEntry.isSelect = true
   tNewMenuEntry.GetCurrentValue = function(self, aValue, aName)
      if tAnnounceEnabled() == true then
         return L["Yes"]
      else
         return L["No"]
      end
   end
   tNewMenuEntry.OnAction = function(self, aValue, aName)
      if aName == L["No"] then
         SkuSettings:Set("SkuCore", "taxiAnnounceLandingPoints", false)
      elseif aName == L["Yes"] then
         SkuSettings:Set("SkuCore", "taxiAnnounceLandingPoints", true)
      end
   end
   tNewMenuEntry.BuildChildren = function(self)
      SkuOptions:InjectMenuItems(self, {L["No"]}, SkuGenericMenuItem)
      SkuOptions:InjectMenuItems(self, {L["Yes"]}, SkuGenericMenuItem)
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- /skucheck taxi - the tripwire for the fix above.
--
-- Invariant: an EARLY LANDING is never the flight's own start or end point.
-- Landing where you took off is not landing early, and landing at the
-- destination is just arriving - yet both were being announced (the reports this
-- shipped for), because the nearest-node fallback knows neither name.
--
-- Two parts, so the domain is never vacuous:
--   * a contract probe on the name comparison the guard is built out of - it
--     runs on the ground and pins the "Ratschet, Brachland" == "Ratschet" rule
--     that makes the guard fire at all;
--   * the live invariant, checked only while actually airborne.
function Taxi.SkuCheck()
   local tChecked, tViolations = 0, 0

   -- Contract probe: the guard is exactly as good as this comparison.
   local tProbe = {
      { "Ratschet, Brachland", "Ratschet",            true  },
      { "Ratschet",            "Ratschet, Brachland", true  },
      { "Ratschet",            "Ratschet",            true  },
      { "Ratschet",            "Beutebucht",          false },
      { "Ratschet",            nil,                   false },
      { nil,                   nil,                   false },
   }
   for x = 1, #tProbe do
      tChecked = tChecked + 1
      if tSameNode(tProbe[x][1], tProbe[x][2]) ~= tProbe[x][3] then
         tViolations = tViolations + 1
         dprint("skucheck", "VIOLATION taxi: node name compare", tostring(tProbe[x][1]), "vs",
            tostring(tProbe[x][2]), "-- expected", tostring(tProbe[x][3]),
            "-- the origin/destination guard cannot match names it should")
      end
   end

   if not tOnTaxi() then
      dprint("skucheck", "taxi: not on a flight - live invariant not applicable")
      return tChecked, 0, tViolations
   end

   -- Live: whatever we would announce right now must not be either end of the
   -- flight, and the route cursor must stay inside the route.
   local tTarget, _, tVia = tCurrentTarget(tScanNodes(true))
   tChecked = tChecked + 1
   if tTarget and tIsFlightEdgeNode(tTarget) then
      tViolations = tViolations + 1
      dprint("skucheck", "VIOLATION taxi: current target", tostring(tTarget), "is this flight's own",
         (tSameNode(tTarget, gFlightOrigin) and "ORIGIN" or "DESTINATION"), "-- via", tostring(tVia),
         "origin", tostring(gFlightOrigin), "dest", tostring(gRouteDest))
   end
   if gRoute then
      tChecked = tChecked + 1
      if not gStopIndex or gStopIndex < 1 or gStopIndex > #gRoute then
         tViolations = tViolations + 1
         dprint("skucheck", "VIOLATION taxi: route cursor", tostring(gStopIndex), "outside 1..", #gRoute,
            "-- the target silently degrades to the nearest-node fallback there")
      end
   else
      dprint("skucheck", "taxi: airborne with no route (fallback mode)", "landed", tostring(gLanded))
   end
   return tChecked, 0, tViolations
end
