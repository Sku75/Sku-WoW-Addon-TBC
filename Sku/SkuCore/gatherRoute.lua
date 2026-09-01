---------------------------------------------------------------------------------------------------------------------------------------
-- SkuCore/gatherRoute.lua - native gather routes (ore / herbs / gas / chests).
--
-- Pick a resource, and Sku walks you from node to node: nearest first, each one
-- reached over a REAL route through the link graph where one exists, with the
-- minimap scanner confirming whether the node is actually there before you have
-- walked all the way to a spot that was mined out ten minutes ago.
--
-- Design derived from ZenqFR's SkuGatherRoute addon (survey item 5,
-- dev/rework-docs/ZENQFR-COMPANION-ADDONS.md), rebuilt natively per
-- dev/rework-docs/GATHER-ROUTES-PLAN.md. Native means no GatherMate2 and no
-- companion addon: the node positions are the waypoints SkuNav already has, and
-- the presence check rides Sku's own minimap scanner.
--
-- ============================ WHERE THE NODES COME FROM ======================
-- ★From SkuNav's WAYPOINT CACHE, not from the raw spawn tables - the cache
-- already contains every gather node, ore and herb and chest and gas cloud, with
-- world coordinates computed and with the RESOURCE AS THE WAYPOINT'S BASE NAME.
-- See the block above tZoneBaseNameBuckets for what that means and why building
-- our own waypoints instead was actively wrong (it duplicates every node in the
-- user's waypoint lists), plus the two things a caller has to know: gas clouds
-- are CREATURES, and the object half depends on "Sammelwegpunkte anzeigen".
--
-- Resource identity is an INDEX into SkuCore.RessourceTypes (minimapScanner.lua),
-- never a bare string, because the two names this feature juggles come from
-- different locales and only the index ties them together:
--   * what the user hears, and what the waypoint cache embeds, is Sku.Loc
--     (enUS / deDE / frFR, the locales Sku ships),
--   * what a minimap scan reports is Sku.LocP (which additionally keeps zhCN /
--     ruRU instead of falling back to English).
-- Holding the index and deriving both from it means the node list, the spoken
-- name and the presence check cannot drift apart, on any client.
--
-- ============================ THE PRESENCE CHECK =============================
-- Every scan path in the addon - the passive "bei Ressourcen benachrichtigen"
-- notifier, the manual scan, and this feature - funnels through
-- MinimapScanner:MinimapScanFastStop, which is where our hook sits. Two modes,
-- and the user never has to choose between them:
--   * Notifier ON: the ambient 0.5 s scans already produce exactly the result we
--     need, so the route schedules NO scans of its own and costs nothing. The
--     ore's name being spoken as it comes into minimap range IS the natural
--     confirmation; our own messages are worded differently, so nothing is
--     suppressed and nothing overlaps confusingly.
--   * Notifier OFF (or the player standing still, which stops the ambient
--     scans): the route self-scans, throttled, ONLY inside presence range of the
--     current node, out of combat, respecting the shared scan lock. Those scans
--     are flagged so the generic name announce stays silent for them - with the
--     notifier off the user hears route outcomes only, never bare ore names.
--
-- WHAT THE CHECK CAN AND CANNOT PROVE. MinimapScanFast reports ONE name per scan
-- (the first blip its tooltip trick lands on) and no positions. So:
--   * a scan naming the expected resource while we are in range CONFIRMS it;
--   * a scan naming something else proves NOTHING - it may simply have hit a
--     different blip first.
-- Absence is therefore concluded only after PRESENCE_GIVE_UP_AFTER consecutive
-- non-matching scans inside presence range. The bias throughout is: WHEN UNSURE,
-- NEVER SKIP. A node wrongly kept costs a short walk; a node wrongly skipped is
-- ore the player never sees, and they cannot tell it happened.
--
-- PRECONDITIONS DEGRADE, THEY DO NOT BLOCK. Scanner module off, tracking spell
-- not cast, or a category with no blips at all (chests) - each just turns the
-- verification off and the route keeps routing. The one thing we DO fix for the
-- user is the per-resource scan toggle, which is auto-enabled (spoken) at route
-- start; casting the tracking spell stays the player's job and only earns a
-- one-time spoken hint.
--
-- ============================ THE SKIP KEY ===================================
-- SKU_KEY_MOVETONEXTWP ("nächster Routenwegpunkt", default Ctrl+Shift+W) means
-- "skip this node" while a route runs - see the branch in SkuNav's key handler
-- (SkuNav/Core.lua). No new keybind. Reaching and gathering a node advances
-- automatically; the key is the manual override for "I do not care about this
-- one" and for "the check is wrong".
--
-- ============================ ACCEPTED LIMITATION ============================
-- The final approach from the path network to the node itself is a straight
-- beacon and can point into a wall or over a cave. The value of the feature is
-- picking nodes automatically and warning about absent ones, not solving
-- terrain. Nodes from the wrong Anniversary phase need no special handling
-- either: the presence check finds nothing and the node is skipped.
--
-- STUCK DETECTION IS NOT HERE ON PURPOSE. Sku's own self-collision warning
-- (SkuCore/Core.lua, the EngineMoving arm) is the same measurement ZenqFR
-- reimplemented - commanded movement with near-zero real displacement - and it
-- is armed by held movement keys, so it already fires while walking a route.
--
-- LOGGING: everything under the "gatherRoute:" prefix, behind /skudebug log on.
--   py -3 dev/rework-docs/_dbgtail.py 400 gatherRoute:
-- `/skugather` dumps live state on demand.
---------------------------------------------------------------------------------------------------------------------------------------
local MODULE_NAME, MODULE_PART = "SkuCore", "gatherRoute"
local L = Sku.L
local _G = _G
local slower = string.lower
local sfind = string.find
local floor = math.floor

SkuCore = SkuCore or LibStub("AceAddon-3.0"):NewAddon("SkuCore", "AceConsole-3.0", "AceEvent-3.0")

local GatherRoute = SkuCore:NewModule("GatherRoute", "AceEvent-3.0")
SkuCore.GatherRoute = GatherRoute   -- published handle (SkuNav's key handler reads it)

SkuCore:RegisterToggleableModule("GatherRoute", function()
   return Sku.deEn("Sammelrouten", "Gather routes", "Itinéraires de récolte")
end)

---------------------------------------------------------------------------------------------------------------------------------------
-- Tuning constants.

-- How close we have to be to a node before the presence check means anything.
-- User-settable (Prüfradius); this is the fallback default. 50 yd is inside the
-- minimap's blip radius at zoom 0 for every scan path.
local PRESENCE_RANGE_DEFAULT = 50

-- Leaving presence range by this factor resets the presence window instead of
-- letting a half-finished miss count carry over to the next approach.
local PRESENCE_LEAVE_FACTOR = 1.5

-- "We are AT the node." The straight final hop is unreliable terrain-wise, so
-- this is deliberately generous - it gates the gather watch, not navigation.
local ARRIVAL_RADIUS = 14

-- Consecutive non-matching scans inside presence range before a node counts as
-- absent. At the ambient 0.5 s cadence that is ~5 s of looking. Generous on
-- purpose: see "WHEN UNSURE, NEVER SKIP" above.
local PRESENCE_GIVE_UP_AFTER = 10

-- Consecutive scans that no longer name a CONFIRMED node before we call it
-- gathered. Only ever evaluated at the node, and only as the fallback for the
-- definitive signal (a loot window opening there).
local VANISH_AFTER = 4

-- Same, once a loot window has opened at the node: the loot corroborates it, so
-- two scans are enough. Not one - a single scan that happened to land on another
-- blip would otherwise end the node while it is still standing there.
local VANISH_AFTER_LOOT = 2

-- Self-scan throttle when the ambient notifier is not feeding us.
local SELF_SCAN_INTERVAL = 1.0

-- Only used when the node CANNOT be verified (scanner off / no tracking /
-- chests): having arrived, wait this long for the player to do their thing and
-- then move on, because nothing else will ever advance the route. Combat pauses
-- it - being attacked at a node is not "done here".
--
-- ★12 s, down from 25 (2026-09-01). The 25 was measured in the field as a HANG:
-- SkuNav announces "Ziel erreicht" when its route ends, and then, with no
-- tracking spell up, the gather route sat silent for another 25 seconds before
-- saying anything. Twice in one run the player gave up waiting and opened the
-- menu to see what was wrong. Gathering short-circuits this anyway (LOOT_CLOSED
-- advances immediately), so the window only has to cover walking the last few
-- yards and starting a cast - it is not a "time to mine" budget.
local UNVERIFIED_GATHER_WINDOW = 12

-- Driver cadence. An OnUpdate with an accumulated-time gate, never a timer
-- chain: hardcore realms kill long script runs and C_Timer chains with them.
local TICK_INTERVAL = 0.2

-- Hard ceiling on nodes per route, independent of the user's setting - the
-- family is built as temporary waypoints in one pass and every one of them costs
-- a SetWaypoint.
local MAX_NODES_HARD = 100

-- Categories offered, in menu order. The key is the SkuCore.RessourceTypes
-- field; scanOption is the ressourceScanning toggle table that gates whether the
-- minimap scanner will even look for it (nil = no blips exist, no verification).
local CATEGORIES = {
   { key = "mining",       scanOption = "miningNodes",  label = function() return Sku.deEn("Erze", "Ore", "Minerais") end },
   { key = "herbs",        scanOption = "herbs",        label = function() return Sku.deEn("Kräuter", "Herbs", "Herbes") end },
   { key = "gasCollector", scanOption = "gasCollector", label = function() return Sku.deEn("Gaswolken", "Gas clouds", "Nuages de gaz") end },
   { key = "chests",       scanOption = nil,            label = function() return Sku.deEn("Truhen", "Chests", "Coffres") end },
}

---------------------------------------------------------------------------------------------------------------------------------------
-- Spoken strings. Kept as functions in one block so every line the feature can
-- say is visible in one place; ";" is the TTS separator, so the parts are
-- readable individually and never glued to a number.

-- ★Everything this feature says goes through BLIZZARD TTS, forced.
--
-- OutputStringBTtts is not "the Blizzard TTS output" - it hands straight BACK to
-- the audio-file voice (SkuVoice:OutputString) unless a truthy `engine` is
-- passed (SkuVoice-1.0.lua:1240). The audio-file voice can only say words that
-- exist as recorded mp3s, and this feature's vocabulary is exactly the part of
-- the game that has none: long compound resource names like
-- "Brühschlammbedecktes reiches Thoriumvorkommen", and every resource whose name
-- is not localized at all on this client. Those come out mangled or silent.
--
-- Blizzard TTS speaks arbitrary text, so it is the only correct engine here. It
-- also settles the French case by construction rather than by luck: there is no
-- French Sku voice pack, and while a missing pack does fall through to Blizzard
-- TTS on its own, that fallback depends on Sku.AudiodataPath being empty - which
-- is not something a route announcement should be betting on.
--
-- engine = 2 is what SkuChat and the menu use for ordinary informational speech.
local function tSay(aText)
   if not aText then return end
   SkuOptions.Voice:OutputStringBTtts(aText, {
      overwrite = false,
      wait = true,
      length = 0.2,
      engine = 2,
   })
end

local tTxt = {
   started      = function() return Sku.deEn("Sammelroute gestartet", "Gather route started", "Itinéraire de récolte démarré") end,
   noNodes      = function() return Sku.deEn("Keine Vorkommen in dieser Zone", "No nodes in this zone", "Aucun gisement dans cette zone") end,
   confirmed    = function() return Sku.deEn("Vorkommen bestätigt", "Node confirmed", "Gisement confirmé") end,
   gathered     = function() return Sku.deEn("Abgebaut", "Gathered", "Récolté") end,
   absent       = function() return Sku.deEn("Nicht vorhanden", "Not present", "Absent") end,
   skipped      = function() return Sku.deEn("Übersprungen", "Skipped", "Ignoré") end,
   moveOn       = function() return Sku.deEn("Weiter", "Moving on", "Suite") end,
   finished     = function() return Sku.deEn("Sammelroute beendet", "Gather route finished", "Itinéraire de récolte terminé") end,
   cancelled    = function() return Sku.deEn("Sammelroute abgebrochen", "Gather route cancelled", "Itinéraire de récolte annulé") end,
   remaining    = function(n) return n .. ";" .. Sku.deEn("übrig", "left", "restants") end,
   noTracking   = function() return Sku.deEn("Suche nicht aktiv, Vorkommen können nicht geprüft werden",
                     "Tracking inactive, nodes cannot be verified",
                     "Pistage inactif, les gisements ne peuvent pas être vérifiés") end,
   scanEnabled  = function() return Sku.deEn("Ressourcenscan für diese Ressource eingeschaltet",
                     "Resource scan enabled for this resource",
                     "Scan de ressources activé pour cette ressource") end,
   directBeacon = function() return Sku.deEn("Keine Route in der Nähe, direkter Peilton",
                     "No route nearby, direct beacon",
                     "Aucun itinéraire à proximité, balise directe") end,
   notReady     = function() return Sku.deEn("Daten werden noch geladen", "Data still loading", "Données en cours de chargement") end,
   -- Ore/herb/chest waypoints only exist in the cache while "Sammelwegpunkte
   -- anzeigen" is on. Name the setting rather than saying "no nodes", which
   -- would be a lie that sends the player to another zone.
   needGatherWps = function() return Sku.deEn(
      "Sammelwegpunkte sind ausgeschaltet; in den Navigations-Einstellungen einschalten",
      "Gather waypoints are switched off; enable them in the navigation settings",
      "Les points de récolte sont désactivés ; activez-les dans les réglages de navigation") end,
}

---------------------------------------------------------------------------------------------------------------------------------------
-- Live route state. Module-local: exactly one gather route can run at a time,
-- and nothing outside this file has any business reading these.
local gActive = false
local gCatKey = nil            -- SkuCore.RessourceTypes field ("mining", ...)
local gResIndex = nil          -- index into that table - THE resource identity
local gScanName = nil          -- expected name in Sku.LocP (what a scan reports)
local gNodeNames = {}          -- remaining temporary waypoint names, ordered as created
local gTarget = nil            -- waypoint name of the node we are heading for
local gNodeState = "idle"      -- idle | routing | near | arrived
local gConfirmed = false       -- has a scan named this node while we were in range?
local gMissCount = 0           -- consecutive non-matching scans inside range
local gVanishCount = 0         -- consecutive scans no longer naming a confirmed node
local gArrivedAt = 0
local gLastSelfScan = 0
local gLootedHere = false      -- a loot window opened at this node
local gVerify = false          -- is the presence check usable for this route at all?
local gFrame = nil

---------------------------------------------------------------------------------------------------------------------------------------
-- Resource name as the user hears it AND as the waypoint cache spells it - the
-- cache embeds objectLookup[Sku.Loc] / NpcData.Names[Sku.Loc], which is the same
-- locale RessourceTypes[..][Sku.Loc] gives. One name, both jobs.
local function tResDisplayName(aCatKey, aIndex)
   local tList = SkuCore.RessourceTypes[aCatKey]
   local tEntry = tList and tList[aIndex]
   return tEntry and (tEntry[Sku.Loc] or tEntry.enUS)
end

-- Resource name in the locale the MINIMAP SCANNER matches by.
local function tResScanName(aCatKey, aIndex)
   local tList = SkuCore.RessourceTypes[aCatKey]
   local tEntry = tList and tList[aIndex]
   return tEntry and (tEntry[Sku.LocP] or tEntry.enUS)
end

local function tPresenceRange()
   local tValue = SkuSettings:Get("SkuCore", "gatherRoute.presenceRange")
   return tonumber(tValue) or PRESENCE_RANGE_DEFAULT
end

local function tMaxNodes()
   local tValue = tonumber(SkuSettings:Get("SkuCore", "gatherRoute.maxNodes")) or 40
   if tValue > MAX_NODES_HARD then tValue = MAX_NODES_HARD end
   if tValue < 1 then tValue = 1 end
   return tValue
end

local function tPresenceCheckWanted()
   return SkuSettings:Get("SkuCore", "gatherRoute.presenceCheck") ~= false
end

---------------------------------------------------------------------------------------------------------------------------------------
-- ★NODE SOURCE: THE WAYPOINT CACHE, NOT THE RAW SPAWN TABLES.
--
-- SkuNav's waypoint cache already holds every gather node as a real waypoint,
-- with its world coordinates computed - and, the part that makes this feature
-- nearly free, with its name built so that THE RESOURCE IS THE BASE NAME. What
-- CreateWaypointCache writes (SkuNav/Core.lua:743 and :807):
--   objects:   OBJEKT;1731;Kupfervorkommen;Bergbau;Elwynn;1;45.24;58.91
--   creatures: Sumpfgas;Zangarmarsh;1;80.31;79.08
-- and SkuNav:StripBaseNameFromWaypointName strips the object prefix and cuts at
-- the first ";" - giving "Kupfervorkommen" / "Sumpfgas". A resource IS a
-- waypoint family in this cache, by construction. Nothing here has to be built.
--
-- This file first read the raw spawn tables and materialised its own temporary
-- waypoints. That was not merely duplicated work, it was wrong: with
-- "Sammelwegpunkte anzeigen" on, every ore would then exist TWICE in the
-- waypoint lists - once as the cache record, once as ours.
--
-- Two consequences worth knowing:
--   * ★GAS CLOUDS ARE CREATURES, NOT OBJECTS. They are in SkuDB.NpcData.Data
--     with full spawn tables (Swamp Gas 17378 Zangarmarsh, Felmist 17407
--     Shadowmoon, Arcane Vortex 17408 Netherstorm, Windy Cloud 24222 Nagrand,
--     plus Steam / Cinder / Arctic Cloud in Northrend) and reach the cache
--     through the CREATURE pass, which has no gather filter - so they are there
--     unconditionally. Nothing needs to special-case them: a base name is a base
--     name. Searching only objects.lua is what made an earlier version of this
--     file conclude, wrongly, that gas had no data.
--   * The OBJECT half (ore, herbs, chests) is in the cache only while
--     SkuSettings:Sub("SkuNav").showGatherWaypoints is on. That setting is a
--     BUILD-TIME FILTER on the cache (SkuNav/Core.lua:784), not a data gate -
--     the spawn tables are resident either way. With it off we find no ore nodes
--     and say exactly that, rather than guessing or silently doing nothing.

-- The current zone's waypoints bucketed by base name. ONE pass over
-- ListWaypoints2 (continent-wide before it filters, so not free), cached until
-- the zone or the waypoint cache changes: the settings SEARCH walks all four
-- category levels in a single frame, and the route asks again at every start.
local gBucket, gBucketFor, gBucketGen = nil, nil, nil

-- objectLookup.deDE writes the TYPOGRAPHIC apostrophe U+2019 ("Arthas’ Tränen")
-- where SkuCore.RessourceTypes writes the ASCII one. Those two strings are not
-- equal, so the one German herb with an apostrophe would never match its own
-- waypoints. Normalise both sides of every comparison.
local function tNormName(aName)
   if not aName then return nil end
   return (string.gsub(aName, "\226\128\153", "'"))
end

local function tZoneBaseNameBuckets()
   local tUiMapId = SkuNav.Geo:GetBestMapForUnit("player")
   if not tUiMapId then return nil end
   if gBucketFor == tUiMapId and gBucketGen == SkuNav._wpcGen and gBucket then
      return gBucket
   end
   local tZoneAreaId = SkuNav.Geo:GetAreaIdFromUiMapId(tUiMapId)
   if not tZoneAreaId then return nil end

   -- Sub-areas need no special handling: ListWaypoints2 filters on the record's
   -- DERIVED uiMapId, and GetUiMapIdFromAreaId walks ParentAreaID up to the zone
   -- map, so a spawn in a named subzone resolves to this same map and is kept.
   local tList = SkuNav:ListWaypoints2(false, "creature;object", tZoneAreaId, nil, nil, true)
   if not tList then return nil end

   local tBuckets = {}
   for i = 1, #tList do
      local tBase = tNormName(SkuNav:StripBaseNameFromWaypointName(tList[i]))
      if tBase then
         local tEntry = tBuckets[tBase]
         if not tEntry then tEntry = {}; tBuckets[tBase] = tEntry end
         tEntry[#tEntry + 1] = tList[i]
      end
   end

   gBucket, gBucketFor, gBucketGen = tBuckets, tUiMapId, SkuNav._wpcGen
   dprint("gatherRoute: zone buckets rebuilt for uiMap", tUiMapId, "waypoints", #tList)
   return tBuckets
end

-- How many nodes of this resource are on the current map. Free once the bucket
-- exists - which is the point of bucketing instead of asking per resource.
local function tCountZoneNodes(aCatKey, aIndex, aBuckets)
   if not aBuckets then return 0 end
   local tEntry = aBuckets[tNormName(tResDisplayName(aCatKey, aIndex))]
   return tEntry and #tEntry or 0
end

-- The route's candidate list: this resource's waypoints on the current map,
-- nearest first, capped. Names only - the waypoints already exist.
local function tCollectZoneNodes(aCatKey, aIndex)
   local tBuckets = tZoneBaseNameBuckets()
   if not tBuckets then return nil end
   local tNames = tBuckets[tNormName(tResDisplayName(aCatKey, aIndex))]
   if not tNames then return {} end

   local tPlayX, tPlayY = UnitPosition("player")
   if not tPlayX then return nil end

   local tFound = {}
   for i = 1, #tNames do
      local tData = SkuNav:GetWaypointData2(tNames[i])
      if tData and tData.worldX then
         tFound[#tFound + 1] = {
            name = tNames[i],
            dist = SkuNav.Geo:Distance(tPlayX, tPlayY, tData.worldX, tData.worldY),
         }
      end
   end

   table.sort(tFound, function(a, b) return a.dist < b.dist end)
   local tMax = tMaxNodes()
   while #tFound > tMax do
      table.remove(tFound)
   end
   return tFound
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Navigation glue.

-- Stop whatever navigation is running WITHOUT the "Folgen beendet" announce and
-- WITHOUT clearing temporary waypoints. Both matter: this runs between every two
-- nodes, so the announce would be constant chatter, and
-- SkuNav:CancelNavigationSilent additionally calls ClearWaypointsTemporary -
-- which would delete the rest of our own node family mid-route.
local function tStopNavSilent()
   local tNavS = SkuSettings:Sub("SkuNav")
   local tSelected = tNavS.selectedWaypoint
   if tSelected and tSelected ~= "" then
      if SkuOptions.BeaconLib:GetBeaconStatus("SkuOptions", tSelected) then
         SkuOptions.BeaconLib:DestroyBeacon("SkuOptions", tSelected)
      end
   end
   tNavS.metapathFollowing = nil
   tNavS.metapathFollowingTargetName = nil
   SkuNav:SelectWP("", true)
end

-- ★ALWAYS ROUTE WHEN THERE IS ROUTE DATA. Distance is not evidence about
-- terrain: a node 20 yards away with a wall in between is still 20 yards of wall,
-- and the straight beacon will happily walk the player into it. The only thing
-- that decides between a real route and a beacon is whether the link graph
-- actually covers this node - which is what StartCloseRouteToWaypoint answers,
-- and it answers it from data rather than from a guess.
--
-- Two earlier revisions of this gated the route computation behind a minimum
-- distance (120 yd, then 60) to save its cost. That was wrong twice over: gather
-- nodes are dense - Darkshore alone carries 109 copper spawns - so the threshold
-- meant the metaroute path essentially never ran (measured in the first live
-- run: nodes at 32 and 115 yd, both beaconed straight), and "close" never meant
-- "reachable in a straight line" in the first place.
--
-- The cost is accepted deliberately: up to two Dijkstra floods of the link
-- graph, ONCE PER NODE ADVANCE - the same work the Nav menu's "Nahe Routen" does
-- for one user action, and a node advance happens every half minute or so, not
-- every frame. This is not the shape the script watchdog kills.
--
-- ★In the AIR there is no terrain, so there is no reason to route.
--
-- The link graph is a network of GROUND paths: it walks around cliffs, lakes and
-- buildings that a flying player simply crosses. Following one while airborne
-- means being sent along a road you are hundreds of feet above. Flying, the
-- straight line IS the shortest usable path, which is the one case where the
-- beacon is not a compromise but the right answer.
--
-- UnitOnTaxi is included for the same reason and a stronger one: on a taxi the
-- player has no control at all, so a route is not merely pointless, it is noise.
--
-- Evaluated when a target is CHOSEN. A metaroute that is already running when
-- the player takes off keeps running - taking off does not re-plan the current
-- hop, it just means the next node is beaconed straight.
local function tIsAirborne()
   if UnitOnTaxi and UnitOnTaxi("player") == true then return true end
   if IsFlying and IsFlying() == true then return true end
   return false
end

-- Returns true when a metaroute is running.
local function tStartNavToNode(aWpName, aDistance)
   tStopNavSilent()
   local tAirborne = tIsAirborne()
   -- The other exception is about OUR OWN state machine rather than terrain:
   -- inside the arrival radius the node counts as reached on the very next tick,
   -- so a route here could only send the player back to an entry waypoint behind
   -- them to reach something they are already standing at.
   if not tAirborne and (aDistance == nil or aDistance > ARRIVAL_RADIUS)
      and SkuNav:StartCloseRouteToWaypoint(aWpName) then
      dprint("gatherRoute: close route to", aWpName)
      return true
   end
   SkuNav.lastSelectedWaypointFullName = aWpName
   SkuNav:SelectWP(aWpName, true)
   dprint("gatherRoute: direct beacon to", aWpName, "dist", aDistance and floor(aDistance),
      tAirborne and "(airborne)" or "(no close route)")
   return false, tAirborne
end

-- ★Finished nodes are FORGOTTEN, not deleted.
--
-- These are the shared cache waypoints, so deleting them is neither possible
-- (SkuNav:DeleteWaypoint refuses anything but typeId 1) nor wanted - they belong
-- to the whole addon, not to this route. And SkuNav's own "visited" mechanism is
-- not the answer either: SkuNav:setWaypointVisited is gated on the trackVisited
-- setting and TIME-EXPIRES (SkuNav/Visited.lua), so a route would silently
-- re-offer a vein the player mined ten minutes ago, and would do nothing at all
-- for a player who has trackVisited off.
--
-- The route does not need SkuNav to forget anything. It needs to not pick the
-- same node twice, and its own list is the whole mechanism.
local function tRemoveNodeFromList(aWpName)
   for i = 1, #gNodeNames do
      if gNodeNames[i] == aWpName then
         table.remove(gNodeNames, i)
         return
      end
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Preconditions for the presence check. Each failure DEGRADES the route to
-- "route only, no verification" - none of them blocks it.

local function tSpellTrackingActive()
   local tCount = (GetNumTrackingTypes and GetNumTrackingTypes()) or 0
   for i = 1, tCount do
      local tResult = GetTrackingInfo(i)
      local tActive, tCategory
      -- C_Minimap.GetTrackingInfo returns a table on TBC Anniversary, separate
      -- return values on older clients (same split MinimapScanner handles).
      if type(tResult) == "table" then
         tActive = tResult.active
         tCategory = tResult.type or tResult.category
      else
         local _, _, a, c = GetTrackingInfo(i)
         tActive, tCategory = a, c
      end
      if tActive and tCategory == "spell" then return true end
   end
   return false
end

local function tScannerUsable()
   local tMS = SkuCore.MinimapScanner
   return tMS ~= nil and tMS.IsEnabled ~= nil and tMS:IsEnabled() == true
end

-- ★Is verification actually WORKING right now - not just "was it configured at
-- route start". This is the single most important guard in the file.
--
-- gVerify only records that the route was set up to verify. If the player has
-- not cast Find Minerals / Find Herbs, the minimap carries no blips at all, so
-- every scan comes back naming something else or nothing - and the miss counter
-- would run to PRESENCE_GIVE_UP_AFTER at EVERY node and declare the entire zone
-- empty. The same goes for the scanner module being switched off mid-route.
-- Re-checked live rather than latched at start so casting the tracking spell
-- half way through a route simply turns verification on from there.
--
-- Cached for VERIFY_RECHECK_SECONDS because Tick runs five times a second and
-- this walks every tracking type through a C API call.
local gVerifyNowValue, gVerifyNowAt = false, 0
local VERIFY_RECHECK_SECONDS = 2

local function tVerifyNow()
   if not gVerify then return false end
   local tNow = GetTime()
   if tNow - gVerifyNowAt < VERIFY_RECHECK_SECONDS then
      return gVerifyNowValue
   end
   gVerifyNowAt = tNow
   gVerifyNowValue = tScannerUsable() and tSpellTrackingActive()
   return gVerifyNowValue
end

local function tCategorySpec(aCatKey)
   for _, tCat in ipairs(CATEGORIES) do
      if tCat.key == aCatKey then return tCat end
   end
end

-- Ask the scanner for one scan of our own, flagged so its result is not
-- announced as a bare resource name. Every guard is checked BEFORE the flag is
-- set: a flag set for a scan that never starts would silence the next AMBIENT
-- announcement instead of ours.
function GatherRoute:RequestScan()
   local tMS = SkuCore.MinimapScanner
   if not tScannerUsable() then return false end
   if tMS.MinimapScanFastRunning == true or tMS.IsMMScanning == true then return false end
   if SkuCore.inCombat == true then return false end

   tMS.IsMMScanning = true
   tMS.routeScanSilent = true
   local tOk = pcall(tMS.MinimapScanFast, tMS)
   if not tOk then
      tMS.IsMMScanning = false
      tMS.MinimapScanFastRunning = false
      tMS.routeScanSilent = nil
      return false
   end
   return true
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Node lifecycle.

local function tResetNodeState()
   gNodeState = "routing"
   gConfirmed = false
   gMissCount = 0
   gVanishCount = 0
   gArrivedAt = 0
   gLootedHere = false
end

-- Pick the nearest remaining node FROM WHERE THE PLAYER ACTUALLY IS and route to
-- it. Recomputed every time rather than following a precomputed order: the
-- player's position after finishing one node is not the position the route was
-- planned from, and the nearest node from here is a better answer than the next
-- entry of a stale ordering.
function GatherRoute:PickNextTarget(aAnnounceRemaining)
   gTarget = nil
   if #gNodeNames == 0 then
      GatherRoute:Stop(tTxt.finished())
      return
   end

   local tPlayX, tPlayY = UnitPosition("player")
   local tBest, tBestDist = nil, nil
   for i = 1, #gNodeNames do
      local tData = SkuNav:GetWaypointData2(gNodeNames[i])
      if tData and tPlayX then
         local tDist = SkuNav.Geo:Distance(tPlayX, tPlayY, tData.worldX, tData.worldY)
         if not tBestDist or tDist < tBestDist then
            tBest, tBestDist = gNodeNames[i], tDist
         end
      end
   end

   if not tBest then
      -- Every remaining name has lost its waypoint record (a global temporary
      -- clear, a cache rebuild). There is nothing left to route to.
      dprint("gatherRoute: no surviving node waypoints, ending route")
      GatherRoute:Stop(tTxt.finished())
      return
   end

   gTarget = tBest
   tResetNodeState()
   local tHasRoute, tAirborne = tStartNavToNode(gTarget, tBestDist)

   if aAnnounceRemaining then
      tSay(tTxt.remaining(#gNodeNames))
   end
   -- Say it whenever a route was WANTED and the graph could not supply one: the
   -- straight beacon can point through a wall, so the player should know that is
   -- what they are following. Not said when flying (the beacon is the correct
   -- answer up there, not a fallback), and not for the arrival-radius case,
   -- where no route was attempted and none was needed.
   if not tHasRoute and not tAirborne and (tBestDist == nil or tBestDist > ARRIVAL_RADIUS) then
      tSay(tTxt.directBeacon())
   end
   dprint("gatherRoute: next target", gTarget, "remaining", #gNodeNames, "dist", tBestDist and floor(tBestDist))
end

-- Finish the current node for aReasonText and move on. The waypoint itself is
-- left alone (see tRemoveNodeFromList above) - it is dropped from THIS route's
-- list, which is all that "finished" has to mean.
function GatherRoute:FinishCurrentNode(aReasonText, aReasonTag)
   if not gTarget then return end
   dprint("gatherRoute: node finished", gTarget, aReasonTag or "?")
   local tFinished = gTarget
   gTarget = nil
   gNodeState = "idle"
   tRemoveNodeFromList(tFinished)
   tStopNavSilent()
   if aReasonText then tSay(aReasonText) end
   GatherRoute:PickNextTarget(true)
end

-- The skip key (SkuNav's SKU_KEY_MOVETONEXTWP branch). Unconditional by design:
-- it must work regardless of what the presence check currently believes, because
-- "the check is wrong" is one of the two reasons to press it.
function GatherRoute:SkipCurrentTarget()
   if not gActive then return end
   GatherRoute:FinishCurrentNode(tTxt.skipped(), "skipped")
end

function GatherRoute:IsActive()
   return gActive == true
end

---------------------------------------------------------------------------------------------------------------------------------------
-- The scan result hook. Called from MinimapScanner:MinimapScanFastStop for EVERY
-- scan, ambient or ours, with the raw matched name (or nil for "nothing found").
function GatherRoute:OnMinimapScanResult(aResult, aWasRouteScan)
   if not gActive or not gTarget or not gScanName then return end
   -- No live verification (tracking spell not up, scanner off) means a scan
   -- proves nothing in EITHER direction - see tVerifyNow.
   if not tVerifyNow() then return end
   -- Out of presence range a scan says nothing about THIS node.
   if gNodeState == "routing" then return end

   local tMatch = false
   if aResult then
      local tLower = slower(aResult)
      local tExpected = slower(gScanName)
      tMatch = (tLower == tExpected) or (sfind(tLower, tExpected, 1, true) ~= nil)
   end

   if tMatch then
      gMissCount = 0
      gVanishCount = 0
      if not gConfirmed then
         gConfirmed = true
         dprint("gatherRoute: presence confirmed for", gTarget)
         tSay(tTxt.confirmed())
      end
      return
   end

   if gConfirmed then
      -- It was there and now it is not being reported any more. Only meaningful
      -- standing AT the node - farther out the scanner simply has other blips to
      -- pick from.
      --
      -- A loot window having opened here CORROBORATES that (shortening the window
      -- to VANISH_AFTER_LOOT) but is deliberately not the trigger on its own:
      -- LOOT_OPENED fires for a killed mob exactly as it does for a mined vein,
      -- and mobs stand next to ore. Two scans that no longer name the node, after
      -- a loot, is a gathered node; a loot with the node still being reported is
      -- somebody's corpse.
      if gNodeState == "arrived" then
         gVanishCount = gVanishCount + 1
         local tNeeded = gLootedHere and VANISH_AFTER_LOOT or VANISH_AFTER
         if gVanishCount >= tNeeded then
            GatherRoute:FinishCurrentNode(tTxt.gathered(), gLootedHere and "looted+vanished" or "vanished")
         end
      end
   else
      gMissCount = gMissCount + 1
      if gMissCount >= PRESENCE_GIVE_UP_AFTER then
         GatherRoute:FinishCurrentNode(tTxt.absent(), "absent")
      end
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Loot events. Language-free and immediate, but NOT unambiguous: a killed mob
-- opens the same window as a mined vein, and mobs stand next to ore. So the
-- signal is used two different ways:
--   * verification live -> corroboration only. It shortens the "the scans have
--     stopped naming this node" window (see OnMinimapScanResult); the scans
--     still have the last word, so looting a corpse at the node advances nothing.
--   * no verification -> it IS the trigger, because nothing else can be. The
--     alternative there is the arrival timeout, which is slower and no more
--     certain. Acted on at window CLOSE so the announcement does not talk over
--     the player taking the items.
function GatherRoute:LOOT_OPENED()
   if not gActive or not gTarget then return end
   if gNodeState ~= "arrived" then return end
   gLootedHere = true
   dprint("gatherRoute: loot opened at", gTarget)
end

function GatherRoute:LOOT_CLOSED()
   if not gActive or not gTarget then return end
   if not gLootedHere then return end
   if tVerifyNow() then
      -- Corroboration: let the next scans decide, but take one NOW rather than
      -- waiting out the throttle - the answer is worth a second of the player's
      -- time, not five.
      gLastSelfScan = 0
      return
   end
   GatherRoute:FinishCurrentNode(tTxt.gathered(), "looted")
end

---------------------------------------------------------------------------------------------------------------------------------------
-- The driver. Distance is measured against the CURRENT NODE, never against
-- SkuSettings:Sub("SkuNav").selectedWaypoint - that cycles through the
-- intermediate hops of the close route, so arrival at hop 7 of 12 would read as
-- arrival at the node.
function GatherRoute:Tick()
   if not gActive or not gTarget then return end

   if not SkuNav:GetWaypointData2(gTarget) then
      -- Our waypoint was deleted underneath us (global temporary clear, cache
      -- rebuild). Say so by ending cleanly rather than beaconing at nothing.
      dprint("gatherRoute: target waypoint vanished:", gTarget)
      GatherRoute:Stop(tTxt.finished())
      return
   end

   local tDist = SkuNav:GetDistanceToWp(gTarget)
   if not tDist then return end
   local tRange = tPresenceRange()

   if gNodeState == "routing" then
      if tDist <= tRange then
         gNodeState = "near"
         gMissCount = 0
         dprint("gatherRoute: entered presence range of", gTarget, floor(tDist))
      end
   elseif tDist > tRange * PRESENCE_LEAVE_FACTOR then
      -- Walked back out. Drop the half-finished presence window instead of
      -- carrying its miss count into the next approach.
      gNodeState = "routing"
      gMissCount = 0
      gVanishCount = 0
      gLootedHere = false
   elseif gNodeState == "near" and tDist <= ARRIVAL_RADIUS then
      gNodeState = "arrived"
      gArrivedAt = GetTime()
      dprint("gatherRoute: arrived at", gTarget)
      -- SkuNav has just said "Ziel erreicht" - that is ITS route ending, and it
      -- says nothing about what the gather route is now doing. When the presence
      -- check is live the scanner fills that gap by naming the resource as it
      -- comes into range; when it is NOT live nothing else speaks at all, and
      -- the player is left listening to silence until the window expires. Name
      -- the resource ourselves in that case: it says "you are at the copper
      -- vein" and it explains the pause, in one word the player wants anyway.
      if not tVerifyNow() and gCatKey and gResIndex then
         tSay(tResDisplayName(gCatKey, gResIndex))
      end
   end

   if gNodeState == "routing" then return end

   -- Presence checking from here on.
   if tVerifyNow() then
      -- Only self-scan when the ambient notifier is NOT producing results: it is
      -- gated on notifyOnRessources AND on the player actually moving.
      local tAmbient = (SkuSettings:Sub("SkuCore").ressourceScanning.notifyOnRessources == true)
         and ((GetUnitSpeed("player") or 0) > 0)
      if not tAmbient and GetTime() - gLastSelfScan >= SELF_SCAN_INTERVAL then
         gLastSelfScan = GetTime()
         GatherRoute:RequestScan()
      end
      return
   end

   -- No verification available (never configured, or the tracking spell is not
   -- up right now). Arrival plus a grace window is then the ONLY thing that can
   -- advance the route, so it has to. Combat pauses the window - being attacked
   -- at a node is not being done with it.
   if gNodeState == "arrived" then
      if SkuCore.inCombat == true then
         gArrivedAt = GetTime()
      elseif GetTime() - gArrivedAt > UNVERIFIED_GATHER_WINDOW then
         GatherRoute:FinishCurrentNode(tTxt.moveOn(), "unverified timeout")
      end
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Start / stop.

function GatherRoute:Start(aCatKey, aIndex)
   if not GatherRoute:IsEnabled() then return end

   if gActive then
      GatherRoute:Stop(nil)
   end

   local tSpec = tCategorySpec(aCatKey)
   local tResName = tResDisplayName(aCatKey, aIndex)
   if not tSpec or not tResName then return end

   if SkuNav.wpCacheReady ~= true then
      -- The waypoint cache is still streaming in after login; an empty answer
      -- now would read as "no ore in this zone".
      tSay(tTxt.notReady())
      return
   end

   local tNodes = tCollectZoneNodes(aCatKey, aIndex)
   if not tNodes or #tNodes == 0 then
      tSay(tResName)
      -- Distinguish the two very different reasons for an empty list. Ore, herbs
      -- and chests are only IN the waypoint cache while "Sammelwegpunkte
      -- anzeigen" is on (SkuNav/Core.lua:784 filters them out otherwise), so for
      -- those categories the likeliest cause is a setting, not an empty zone -
      -- and "no nodes here" would send the player somewhere else for nothing.
      -- Gas comes through the creature pass and is never filtered, so for gas an
      -- empty list really does mean an empty zone.
      if aCatKey ~= "gasCollector" and SkuSettings:Sub("SkuNav").showGatherWaypoints ~= true then
         tSay(tTxt.needGatherWps())
      else
         tSay(tTxt.noNodes())
      end
      return
   end

   gCatKey = aCatKey
   gResIndex = aIndex
   gScanName = tResScanName(aCatKey, aIndex)

   gNodeNames = {}
   for i = 1, #tNodes do
      gNodeNames[i] = tNodes[i].name
   end

   -- Auto-enable the per-resource scan toggle (open question 1): the presence
   -- check matches against the enabled resources, so a route for a resource the
   -- user has switched off in the scan settings could never confirm anything.
   -- Turning it on is what they asked for by starting the route; saying so keeps
   -- the setting change from being invisible.
   if tSpec.scanOption then
      local tToggles = SkuSettings:Sub("SkuCore").ressourceScanning[tSpec.scanOption]
      if tToggles and tToggles[aIndex] ~= true then
         tToggles[aIndex] = true
         tSay(tTxt.scanEnabled())
      end
   end

   -- Can we verify at all? Each precondition only downgrades the route.
   gVerify = tPresenceCheckWanted() and tSpec.scanOption ~= nil and tScannerUsable() and gScanName ~= nil
   local tTrackingMissing = gVerify and not tSpellTrackingActive()
   if tTrackingMissing then
      -- Casting the tracking spell stays the player's job (open question 2). The
      -- route still works; only the verification does not, until they cast it -
      -- so gVerify stays true and the check starts working the moment it is on.
      tSay(tTxt.noTracking())
   end

   gActive = true
   gTarget = nil
   gLastSelfScan = 0
   gVerifyNowAt = 0   -- force a fresh tracking check on the first tick

   tSay(tTxt.started())
   tSay(tResName)
   tSay(#gNodeNames .. ";" .. Sku.deEn("Vorkommen", "nodes", "gisements"))
   -- Log WHY verification is or is not live, not just the configured flag: with
   -- no gathering profession on the character there is no tracking spell, so
   -- every run looks like "verify true" while the check never actually fires.
   dprint("gatherRoute: started", aCatKey, aIndex, tResName, "nodes", #gNodeNames,
      "verify", tostring(gVerify), "verifyNow", tostring(tVerifyNow()),
      "scanner", tostring(tScannerUsable()), "tracking", tostring(tSpellTrackingActive()))

   GatherRoute:PickNextTarget(false)
end

function GatherRoute:Stop(aSpokenText)
   local tWasActive = gActive
   gActive = false
   gTarget = nil
   gNodeState = "idle"
   gCatKey, gResIndex, gScanName = nil, nil, nil
   gVerify = false
   gVerifyNowValue, gVerifyNowAt = false, 0
   if tWasActive then
      tStopNavSilent()
   end
   -- Nothing to clean up: the nodes are shared cache waypoints, so stopping a
   -- route is just forgetting the list.
   gNodeNames = {}
   if aSpokenText then tSay(aSpokenText) end
   if tWasActive then
      dprint("gatherRoute: stopped")
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Menu: Einstellungen -> Scan -> Ressourcen Scan -> Sammelrouten.
--
-- Built here and injected by SkuCore/Options.lua rather than declared as an
-- AceConfig node, because the resource lists are per-zone and live: only
-- resources that actually have spawns where the player is standing are offered,
-- with their node count, and that cannot come out of a static args table.
function GatherRoute:MenuBuilder(aParentEntry)
   -- Feature switched off in Einstellungen -> Module: contribute nothing at all
   -- rather than a submenu whose every entry silently does nothing (Start bails
   -- on IsEnabled). The Module menu is where it gets turned back on.
   if not GatherRoute:IsEnabled() then return end

   local tEntry = SkuOptions:InjectMenuItems(aParentEntry, {
      Sku.deEn("Sammelrouten", "Gather routes", "Itinéraires de récolte"),
   }, SkuGenericMenuItem)
   tEntry.dynamic = true
   -- The zone (and therefore the whole list) changes as the player walks; re-read
   -- the level every time it is entered instead of serving a stale build.
   tEntry.volatileChildren = true
   tEntry.BuildChildren = function(self)
      if gActive then
         local tStop = SkuOptions:InjectMenuItems(self, {
            Sku.deEn("Sammelroute beenden", "Stop gather route", "Arrêter l'itinéraire de récolte"),
         }, SkuGenericMenuItem)
         tStop.OnAction = function()
            GatherRoute:Stop(tTxt.cancelled())
            SkuOptions:CloseMenu()
         end
      end

      for _, tCat in ipairs(CATEGORIES) do
         local tCatEntry = SkuOptions:InjectMenuItems(self, {tCat.label()}, SkuGenericMenuItem)
         tCatEntry.dynamic = true
         tCatEntry.volatileChildren = true
         tCatEntry.sorting = true
         tCatEntry.BuildChildren = function(self)
            -- Zone resolved HERE, not captured from the level above: the player
            -- can walk into the next zone while standing in this menu, and a
            -- captured bucket would then list the zone they just left.
            if SkuNav.wpCacheReady ~= true then
               SkuNav:InjectWpListEmptyHint(self)
               return
            end
            local tBuckets = tZoneBaseNameBuckets()
            if not tBuckets then
               SkuOptions:InjectMenuItems(self, {tTxt.notReady()}, SkuGenericMenuItem)
               return
            end
            local tList = SkuCore.RessourceTypes[tCat.key]
            local tAny = false
            for x = 1, #tList do
               local tCount = tCountZoneNodes(tCat.key, x, tBuckets)
               if tCount > 0 then
                  tAny = true
                  local tResEntry = SkuOptions:InjectMenuItems(self, {
                     tResDisplayName(tCat.key, x) .. ";" .. tCount,
                  }, SkuGenericMenuItem)
                  tResEntry.OnAction = function()
                     -- Close FIRST, speak after: starting the route talks, and a
                     -- menu still closing over the top of it swallows the lines.
                     SkuOptions:CloseMenu()
                     GatherRoute:Start(tCat.key, x)
                  end
               end
            end
            if not tAny then
               -- An empty ore/herb/chest category is far more often the
               -- "Sammelwegpunkte anzeigen" filter than an empty zone; say which.
               if tCat.key ~= "gasCollector" and SkuSettings:Sub("SkuNav").showGatherWaypoints ~= true then
                  SkuOptions:InjectMenuItems(self, {tTxt.needGatherWps()}, SkuGenericMenuItem)
               else
                  SkuNav:InjectWpListEmptyHint(self)
               end
            end
         end
      end

      -- Prüfradius
      local tRangeValues = {20, 30, 50, 75, 100}
      local tRangeEntry = SkuOptions:InjectMenuItems(self, {
         Sku.deEn("Prüfradius", "Check radius", "Rayon de vérification"),
      }, SkuGenericMenuItem)
      tRangeEntry.dynamic = true
      tRangeEntry.isSelect = true
      tRangeEntry.BuildChildren = function(self)
         for _, v in ipairs(tRangeValues) do
            SkuOptions:InjectMenuItems(self, {tostring(v)}, SkuGenericMenuItem)
         end
      end
      tRangeEntry.GetCurrentValue = function() return tostring(tPresenceRange()) end
      tRangeEntry.OnAction = function(self, aValue, aName)
         local tValue = tonumber(aName)
         if tValue then SkuSettings:Set("SkuCore", "gatherRoute.presenceRange", tValue) end
      end

      -- Anzahl Knoten
      local tCountValues = {10, 20, 40, 60, 100}
      local tCountEntry = SkuOptions:InjectMenuItems(self, {
         Sku.deEn("Anzahl Vorkommen je Route", "Nodes per route", "Gisements par itinéraire"),
      }, SkuGenericMenuItem)
      tCountEntry.dynamic = true
      tCountEntry.isSelect = true
      tCountEntry.BuildChildren = function(self)
         for _, v in ipairs(tCountValues) do
            SkuOptions:InjectMenuItems(self, {tostring(v)}, SkuGenericMenuItem)
         end
      end
      tCountEntry.GetCurrentValue = function() return tostring(tMaxNodes()) end
      tCountEntry.OnAction = function(self, aValue, aName)
         local tValue = tonumber(aName)
         if tValue then SkuSettings:Set("SkuCore", "gatherRoute.maxNodes", tValue) end
      end

      -- Präsenzprüfung an/aus
      local tCheckEntry = SkuOptions:InjectMenuItems(self, {
         Sku.deEn("Vorkommen prüfen", "Verify nodes", "Vérifier les gisements"),
      }, SkuGenericMenuItem)
      tCheckEntry.GetCurrentValue = function()
         if tPresenceCheckWanted() then return L["Yes"] end
         return L["No"]
      end
      tCheckEntry.OnAction = function(self, aValue, aName)
         if aName == L["No"] then
            SkuSettings:Set("SkuCore", "gatherRoute.presenceCheck", false)
         elseif aName == L["Yes"] then
            SkuSettings:Set("SkuCore", "gatherRoute.presenceCheck", true)
         end
      end
      SkuOptions:MakeInPlaceToggle(tCheckEntry, L["No"], L["Yes"])
   end
end

---------------------------------------------------------------------------------------------------------------------------------------
-- /skugather - live state, printed to chat so it can be captured without turning
-- the debug ring on first.
function GatherRoute:SlashDump()
   local function tOut(aLine)
      if SkuOptions and SkuOptions.Print then SkuOptions:Print(aLine) else print(aLine) end
   end
   tOut("Sku gatherRoute: active=" .. tostring(gActive) .. " verify=" .. tostring(gVerify) ..
      " verifyNow=" .. tostring(tVerifyNow()) .. " state=" .. tostring(gNodeState))
   tOut("  resource=" .. tostring(gCatKey) .. "/" .. tostring(gResIndex) ..
      " scanName=" .. tostring(gScanName))
   tOut("  target=" .. tostring(gTarget) .. " remaining=" .. tostring(#gNodeNames) ..
      " dist=" .. tostring(gTarget and SkuNav:GetDistanceToWp(gTarget)))
   tOut("  confirmed=" .. tostring(gConfirmed) .. " miss=" .. tostring(gMissCount) ..
      " vanish=" .. tostring(gVanishCount) .. " looted=" .. tostring(gLootedHere))
   tOut("  scannerUsable=" .. tostring(tScannerUsable()) .. " spellTracking=" .. tostring(tSpellTrackingActive()) ..
      " notify=" .. tostring(SkuSettings:Sub("SkuCore").ressourceScanning.notifyOnRessources))
   tOut("  range=" .. tostring(tPresenceRange()) .. " maxNodes=" .. tostring(tMaxNodes()) ..
      " wpCacheReady=" .. tostring(SkuNav.wpCacheReady) ..
      " showGatherWps=" .. tostring(SkuSettings:Sub("SkuNav").showGatherWaypoints))
end

---------------------------------------------------------------------------------------------------------------------------------------
function GatherRoute:OnEnable()
   GatherRoute:RegisterEvent("LOOT_OPENED", "LOOT_OPENED")
   GatherRoute:RegisterEvent("LOOT_CLOSED", "LOOT_CLOSED")
   -- A loading screen almost always means a different zone, and the node list is
   -- this zone's. End the route rather than keep beaconing at waypoints the
   -- player has left behind.
   GatherRoute:RegisterEvent("PLAYER_LEAVING_WORLD", "OnWorldEdge")

   if SkuOptions and SkuOptions.RegisterChatCommand then
      SkuOptions:RegisterChatCommand("skugather", function() GatherRoute:SlashDump() end)
   end

   if not gFrame then
      gFrame = CreateFrame("Frame", nil, UIParent)
   end
   gFrame.t = 0
   gFrame:SetScript("OnUpdate", function(self, aElapsed)
      if not gActive then return end
      self.t = (self.t or 0) + aElapsed
      if self.t < TICK_INTERVAL then return end
      self.t = 0
      local tOk, tErr = pcall(GatherRoute.Tick, GatherRoute)
      if not tOk then
         dprint("gatherRoute: Tick failed:", tostring(tErr))
         if SkuErrorLog and SkuErrorLog.Log then
            pcall(function() SkuErrorLog:Log("gatherRoute", "Tick: " .. tostring(tErr)) end)
         end
         GatherRoute:Stop(nil)
      end
   end)
end

function GatherRoute:OnWorldEdge()
   if gActive then
      dprint("gatherRoute: loading screen, ending route")
      GatherRoute:Stop(nil)
   end
end

function GatherRoute:OnDisable()
   GatherRoute:UnregisterAllEvents()
   GatherRoute:Stop(nil)
   if gFrame then
      gFrame:SetScript("OnUpdate", nil)
   end
end
