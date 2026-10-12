
SkuDispatcher = LibStub("AceAddon-3.0"):NewAddon("SkuDispatcher", "AceConsole-3.0", "AceEvent-3.0")

---------------------------------------------------------------------------------------------------------------------------------------
SkuDispatcher.Registered = {}

---------------------------------------------------------------------------------------------------------------------------------------
function SkuDispatcher:TriggerSkuEvent(aEventName, ...)
	if SkuDispatcher[aEventName] then
		SkuDispatcher[aEventName](SkuDispatcher, aEventName, ...)
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuDispatcher:OnDisable()
	
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuDispatcher:OnInitialize()

end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuDispatcher:OnEnable()

end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuDispatcher:UnregisterEventCallback(aEventName, aCallbackFunc)
	if not SkuDispatcher.Registered[aEventName] then
		return
	end
	if not SkuDispatcher.Registered[aEventName].callbacks[aCallbackFunc] then
		-- Benign: several modules unregister defensively (DialTargetingDisable
		-- runs on both PLAYER_LOGIN and PLAYER_ENTERING_WORLD, for one), so this
		-- fires a few times per login. It used to log one nameless "Error:" line
		-- each time - 79 lines of pure noise in a 12000-line ring, and no way to
		-- tell WHICH event it was. Verbose channel, with the event name.
		dprintv("UnregisterEventCallback: no registered callback for", aEventName)
		return
	end

	SkuDispatcher.Registered[aEventName].callbacks[aCallbackFunc] = nil

	for i, v in pairs(SkuDispatcher.Registered[aEventName].callbacks) do
		return
	end

	-- no callbacks left > unregister event
	if string.sub(aEventName, 1, 4) ~= "SKU_" then
		-- Mirror the IsEventValid guard from RegisterEventCallback: an event skipped
		-- there was never registered on the frame, so don't try to unregister it either.
		if not C_EventUtils or C_EventUtils.IsEventValid(aEventName) then
			SkuDispatcher:UnregisterEvent(aEventName)
		end
	end
	SkuDispatcher[aEventName] = nil
	SkuDispatcher.Registered[aEventName] = nil
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuDispatcher:RegisterEventCallback(aEventName, aCallbackFunc, aOnlyOneCallbackFlag)
	aOnlyOneCallbackFlag = aOnlyOneCallbackFlag or false
	if not SkuDispatcher.Registered[aEventName] then
		SkuDispatcher[aEventName] = function(...)
			for callbackFunc, tOnlyOneCallbackFlag in pairs(SkuDispatcher.Registered[aEventName].callbacks) do
				-- [W6-B #17] isolate each subscriber: without this a single
				-- callback error propagates out of the loop and every LATER
				-- callback silently never runs for this dispatch. Several
				-- SkuCore-family files (aq, aqCombat, DialTargeting, turnToUnit,
				-- skuFocus, Core) subscribe to the SAME WoW event through here,
				-- so one faulty subscriber would suppress the others until a
				-- /reload. pcall forwards the varargs natively (Lua 5.1); on
				-- error log once and keep dispatching the rest.
				local tOk, tErr = pcall(callbackFunc, ...)
				if not tOk then
					local tMsg = string.format("dispatch '%s' callback error: %s", tostring(aEventName), tostring(tErr))
					if SkuErrorLog and SkuErrorLog.Log then pcall(function() SkuErrorLog:Log("skuDispatcher", tMsg) end) end
					dprint(tMsg)
				end
				if tOnlyOneCallbackFlag == true then
					SkuDispatcher:UnregisterEventCallback(aEventName, callbackFunc)
				end
			end
		end

		SkuDispatcher.Registered[aEventName] = {
			handler = SkuDispatcher[aEventName],
			callbacks = {},
		}

		if string.sub(aEventName, 1, 4) ~= "SKU_" then
			-- Some events Sku has always registered (e.g. TRADE_SKILL_UPDATE) don't
			-- exist on WoW Forever/Camelot anymore -> RegisterEvent would throw
			-- "Attempt to register unknown event". C_EventUtils.IsEventValid lets us
			-- skip just those, everywhere a callback comes through here, without a
			-- per-callsite isForever check for every renamed/removed event.
			if not C_EventUtils or C_EventUtils.IsEventValid(aEventName) then
				SkuDispatcher:RegisterEvent(aEventName)
			end
		end
	end

	if not SkuDispatcher.Registered[aEventName].callbacks[aCallbackFunc] then
		SkuDispatcher.Registered[aEventName].callbacks[aCallbackFunc] = aOnlyOneCallbackFlag
	end
end