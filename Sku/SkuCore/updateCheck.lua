--[[
  SkuCore\updateCheck.lua  —  in-game "a newer Sku is available" nudge

  WHAT IT DOES
  ------------
  Tells the user, by voice, when a newer Sku version exists — WITHOUT the addon
  ever touching the internet (it can't) and WITHOUT spamming the shared Sku
  channel. The actual update is done by the external Sku Updater EXE; this is
  only a heads-up.

  WHERE THE VERSION INFO COMES FROM
  ---------------------------------
  Every Sku user permanently joins the "SkuChat" channel
  (SkuChat:JoinOrLeaveSkuChatChannel -> JoinPermanentChannel("SkuChat", ...)).
  So all Sku users already share one channel. We exchange version numbers over it
  as HIDDEN addon messages (SendAddonMessage with the "CHANNEL" distribution —
  invisible in chat). When we hear a version higher than ours, we nudge the user.

  THE ANTI-SPAM RULE (the important part)
  ---------------------------------------
  We do NOT broadcast on every login. With many users logging in/out that would
  flood the channel. Instead each client mostly LISTENS and only rarely SPEAKS,
  using suppression (the idea behind RFC 6206 "Trickle"):

    * On login we listen; we only consider announcing after a long, randomized
      delay (so clients don't fire together).
    * Before announcing we check how many "consistent" messages we heard this
      window — i.e. peers advertising a version >= ours. If at least K of them
      spoke, the info is already circulating, so we STAY SILENT.
    * Result: in a channel of N users, only ~K messages go out per interval,
      regardless of N. A busy channel is almost entirely silent.
    * If we hear an OUTDATED peer (version < ours) we schedule one quick,
      suppressed reply so an up-to-date client informs them — but only one
      actually sends; the rest hear it and suppress.

  TODO(review): add a user toggle (SkuOptionsDB) to disable the nudge; localize
  the spoken string; tune the cadence constants below.
]]

-- W4 Phase D: UpdateCheck is a real AceAddon SUBMODULE of SkuCore so it can be
-- turned on/off at runtime. Previously it self-wired via a file-scope frame that
-- registered PLAYER_ENTERING_WORLD + CHAT_MSG_ADDON forever. Now:
--   * OnEnable  arms the driver frame (registers those two events) — this runs on
--     every load (AceAddon auto-enables modules at SkuCore enable), so unlike the
--     old _booted one-shot it re-arms after a /reload too.
--   * OnDisable disarms it (unregisters the events, cancels the clock ticker), so
--     a disabled UpdateCheck does nothing — no listening, no announcing.
SkuCore = SkuCore or LibStub("AceAddon-3.0"):NewAddon("SkuCore", "AceConsole-3.0", "AceEvent-3.0")

local UpdateCheck = SkuCore:NewModule("UpdateCheck")
SkuCore.UpdateCheck = UpdateCheck   -- keep a published handle (harmless if unused)

-- Make this feature user-toggleable (Features menu + persisted on/off). One line;
-- the framework (SkuCore/ModuleManager.lua) handles the rest.
SkuCore:RegisterToggleableModule("UpdateCheck", function()
  return Sku.deEn("Aktualisierungspr\195\188fung", "Update check")
end)

local ADDON_NAME   = "Sku"
local COMM_PREFIX  = "SkuVer"       -- <= 16 chars
local CHANNEL_NAME = "SkuChat"      -- the shared channel every Sku user joins

-- Tunables — TODO(review): adjust cadence to taste.
local FIRST_ANNOUNCE_MIN = 90       -- seconds: earliest we'd consider speaking after login
local FIRST_ANNOUNCE_MAX = 240
local STEADY_MIN         = 20 * 60  -- steady-state re-check window (long; keeps it quiet)
local STEADY_MAX         = 40 * 60
local QUICK_MIN          = 5        -- quick reply window when an outdated peer is heard
local QUICK_MAX          = 20
local REDUNDANCY_K       = 1        -- suppress if we heard >= K consistent peers this window
local MIN_SEND_GAP       = 60       -- hard floor between our own sends

local C_ChatInfo = C_ChatInfo
local C_Timer = C_Timer
local GetAddOnMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata

-- --- version helpers -------------------------------------------------------

local _cachedVersion
local function GetOwnVersionString()
  if not _cachedVersion then
    _cachedVersion = GetAddOnMetadata(ADDON_NAME, "Version") or "0"
  end
  return _cachedVersion
end

local function ParseVersion(str)
  local parts = {}
  for n in tostring(str):gmatch("(%d+)") do parts[#parts + 1] = tonumber(n) end
  return parts
end

-- -1 / 0 / 1 comparing dotted numeric versions.
local function CompareVersions(a, b)
  local pa, pb = ParseVersion(a), ParseVersion(b)
  local n = math.max(#pa, #pb)
  for i = 1, n do
    local x, y = pa[i] or 0, pb[i] or 0
    if x ~= y then return (x < y) and -1 or 1 end
  end
  return 0
end

-- --- state -----------------------------------------------------------------

local _heardConsistent = 0          -- peers >= our version heard this window
local _highestSeen                  -- highest version string heard (or own)
local _lastSentAt = -MIN_SEND_GAP   -- so the FIRST broadcast isn't blocked by the gap
local _nudgedThisSession = false
local _now = 0                       -- maintained from a 1s ticker (no os.time reliance)
local _clockTicker                   -- handle for the 1s clock ticker (cancelled on disable)

local function Now() return _now end

-- Project logger (Sku/Core.lua). Guarded in case of load-order surprises.
local function Trace(...) if dprint then dprint("updateCheck:", ...) end end

-- --- the nudge -------------------------------------------------------------

local function Announce(latest)
  -- TODO(review): localize via L[] and finalize the wording.
  local msg = ("A newer Sku is available (%s). Run the Sku Updater to install it.")
              :format(latest)
  if SkuOptions and SkuOptions.Voice and SkuOptions.Voice.OutputStringBTtts then
    pcall(function()
      SkuOptions.Voice:OutputStringBTtts(msg, false, true, 0.3, true)
    end)
  else
    print("|cffffd200Sku:|r " .. msg)
  end
end

-- Persist the latest version we've heard so the external updater can read it as
-- a hint. TODO(review): confirm the SavedVariables table to use.
local function RememberHint(latest)
  if type(SkuOptionsDB) == "table" then
    SkuOptionsDB.updateHint = SkuOptionsDB.updateHint or {}
    SkuOptionsDB.updateHint.latestSeen = latest
    SkuOptionsDB.updateHint.ownVersion = GetOwnVersionString()
  end
end

-- --- sending (suppressed) --------------------------------------------------

local function ChannelId()
  if not GetChannelName then return 0 end
  local id = GetChannelName(CHANNEL_NAME)   -- 0 if we're not on the channel
  return id or 0
end

-- Send our version once, unless we should stay silent.
local function MaybeAnnounceVersion()
  if not UpdateCheck:IsEnabled() then return end   -- disabled: a pending timer must be a no-op
  -- Suppress: enough peers already advertised a version >= ours this window.
  if _heardConsistent >= REDUNDANCY_K then
    _heardConsistent = 0
    return
  end
  -- Hard floor between sends.
  if Now() - _lastSentAt < MIN_SEND_GAP then return end

  local cid = ChannelId()
  if cid == 0 then return end                -- not on the channel; nothing to do
  if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end

  C_ChatInfo.SendAddonMessage(COMM_PREFIX, GetOwnVersionString(), "CHANNEL", cid)
  _lastSentAt = Now()
  _heardConsistent = 0
  Trace("sent own version", GetOwnVersionString(), "to channel id", cid)
end

local function RandDelay(lo, hi) return math.random(lo, hi) end

local function ScheduleSteady()
  if not UpdateCheck:IsEnabled() then return end   -- stop the steady re-schedule loop when disabled
  if not C_Timer then return end
  C_Timer.After(RandDelay(STEADY_MIN, STEADY_MAX), function()
    MaybeAnnounceVersion()
    ScheduleSteady()
  end)
end

-- --- receiving -------------------------------------------------------------

local function OnPeerVersion(peerVersion)
  if not UpdateCheck:IsEnabled() then return end
  if type(peerVersion) ~= "string" or peerVersion == "" then return end
  local cmp = CompareVersions(peerVersion, GetOwnVersionString())
  Trace("heard peer version", peerVersion, "cmp", cmp, "consistentSoFar", _heardConsistent)

  if cmp >= 0 then
    -- Peer is as new or newer than us: this is a "consistent" advertisement.
    _heardConsistent = _heardConsistent + 1
    if cmp > 0 then
      -- Newer than us -> remember + nudge the user once.
      if (not _highestSeen) or CompareVersions(peerVersion, _highestSeen) > 0 then
        _highestSeen = peerVersion
      end
      RememberHint(peerVersion)
      if not _nudgedThisSession then
        if not (UnitAffectingCombat and UnitAffectingCombat("player")) then
          _nudgedThisSession = true
          Trace("newer version found", peerVersion, "-> nudging user")
          Announce(peerVersion)
        end
      end
    end
  else
    -- Peer is OUTDATED. Schedule one quick, suppressed reply so an up-to-date
    -- client informs the channel — only one will actually send.
    if C_Timer then
      C_Timer.After(RandDelay(QUICK_MIN, QUICK_MAX), MaybeAnnounceVersion)
    end
  end
end

-- --- wiring ----------------------------------------------------------------

-- The hidden driver frame. Created once and reused across enable/disable cycles;
-- OnEnable registers its events, OnDisable unregisters them.
local frame = CreateFrame("Frame")
local _booted = false

frame:SetScript("OnEvent", function(_, event, arg1, arg2)
  if event == "PLAYER_ENTERING_WORLD" then
    -- Boot once per session. (OnEnable already armed the per-load listening when
    -- the module enabled; this just seeds session state on the first PEW.)
    if _booted then return end
    _booted = true
    _highestSeen = GetOwnVersionString()
    Trace("boot, own version", GetOwnVersionString())

  elseif event == "CHAT_MSG_ADDON" then
    local prefix, message = arg1, arg2
    if prefix == COMM_PREFIX then
      OnPeerVersion(message)
    end
  end
end)

---------------------------------------------------------------------------------------------------------------------------------------
-- Arm the feature. Called automatically by AceAddon when the module is enabled
-- (at SkuCore enable, and again whenever the user toggles it back on). Unlike the
-- old _booted one-shot, this re-arms on every load (incl. /reload).
function UpdateCheck:OnEnable()
  _highestSeen = _highestSeen or GetOwnVersionString()

  frame:RegisterEvent("PLAYER_ENTERING_WORLD")
  frame:RegisterEvent("CHAT_MSG_ADDON")

  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(COMM_PREFIX)
  end

  -- 1-second ticker just to advance our clock (avoids os.time / date()).
  if C_Timer and not _clockTicker then
    _clockTicker = C_Timer.NewTicker(1, function() _now = _now + 1 end)
  end

  -- Listen first; consider speaking only after a long, randomized delay.
  if C_Timer then
    C_Timer.After(RandDelay(FIRST_ANNOUNCE_MIN, FIRST_ANNOUNCE_MAX), function()
      MaybeAnnounceVersion()
      ScheduleSteady()
    end)
  end
end

-- Disarm the feature: unregister events and cancel the clock ticker so a disabled
-- UpdateCheck does nothing. Any already-pending C_Timer callbacks become no-ops
-- via the IsEnabled() guards in MaybeAnnounceVersion/ScheduleSteady/OnPeerVersion.
function UpdateCheck:OnDisable()
  frame:UnregisterEvent("PLAYER_ENTERING_WORLD")
  frame:UnregisterEvent("CHAT_MSG_ADDON")
  if _clockTicker then
    _clockTicker:Cancel()
    _clockTicker = nil
  end
end

-- --- diagnostic slash command ----------------------------------------------
-- /skuver — prints the update-check status (NVDA reads it) AND logs it via
-- dprint, and does a one-off test broadcast to exercise the send path. Handy to
-- confirm the module loaded, the SkuChat channel is joined, and comms fire,
-- without waiting for the long announce timer.

SLASH_SKUVER1 = "/skuver"
SlashCmdList["SKUVER"] = function()
  if not UpdateCheck:IsEnabled() then
    print("|cffffd200SkuVer:|r update check is disabled (Features menu).")
    return
  end
  local own = GetOwnVersionString()
  local cid = ChannelId()
  local onChannel = cid ~= 0

  local sent = false
  if onChannel and C_ChatInfo and C_ChatInfo.SendAddonMessage then
    C_ChatInfo.SendAddonMessage(COMM_PREFIX, own, "CHANNEL", cid)  -- test broadcast
    sent = true
  end

  local msg = string.format(
    "own=%s, %s channel joined=%s (id %d), test-broadcast sent=%s, highestSeen=%s, nudgedThisSession=%s, now=%d",
    own, CHANNEL_NAME, tostring(onChannel), cid, tostring(sent),
    tostring(_highestSeen), tostring(_nudgedThisSession), _now)

  Trace("/skuver", msg)
  print("|cffffd200SkuVer:|r " .. msg)
end
