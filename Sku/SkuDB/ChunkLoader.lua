-- [DB rework stage 2] Eager chunk loader for the converted SkuDB data files.
--
-- The nine big data files no longer execute their table constructors at file
-- load: _db_convert.py rewrote them so each big table is registered as chunks
-- of ~500 records in SkuDBChunks (verbatim byte slices of the original file,
-- wrapped as long-string "return { <records> }" builders). This file sits at
-- the END of the SkuDB TOC block and builds everything EAGERLY, synchronously:
-- the data exists at the same point of the load as the original constructors
-- did - stage 2 is format conversion with IDENTICAL timing, zero felt change
-- by design. Stage 3 will replace this eager call with the streamed build.
--
-- Failure semantics (risk A10): every chunk is compiled and run under pcall.
-- A failing chunk marks its dataset in SkuDB.chunkLoad.failed, and ONE error
-- is raised through geterrorhandler() at the end (audible via BugSack, caught
-- by BugGrabber/SkuErrorLog) - degraded but honest, never silently partial.
-- Chunk source strings are nil'ed as they are consumed, so stage 2 does not
-- regress memory (risk A9); the strings become garbage for the existing
-- forced GC at PLAYER_ENTERING_WORLD.

local function SkuDBResolvePath(aPath)
	local t = _G
	for tSeg in string.gmatch(aPath, "[^%.]+") do
		if type(t) ~= "table" then return nil end
		t = t[tSeg]
	end
	return t
end

SkuDB = SkuDB or {}
SkuDB.chunkLoad = {failed = {}, failedCount = 0, chunks = 0, ms = 0}

do
	local tChunks = SkuDBChunks
	SkuDBChunks = nil
	if type(tChunks) == "table" then
		local tT0 = debugprofilestop()
		local tState = SkuDB.chunkLoad
		for i = 1, #tChunks do
			local tPath, tBody = tChunks[i][1], tChunks[i][2]
			local tErr
			local tTarget = SkuDBResolvePath(tPath)
			if type(tTarget) ~= "table" then
				tErr = "target table missing"
			else
				local tFn, tCompileErr = loadstring(tBody, "SkuDBChunk:" .. tPath .. "#" .. i)
				if not tFn then
					tErr = "compile: " .. tostring(tCompileErr)
				else
					local tOk, tRows = pcall(tFn)
					if not tOk then
						tErr = "run: " .. tostring(tRows)
					elseif type(tRows) ~= "table" then
						tErr = "chunk did not return a table"
					else
						for k, v in pairs(tRows) do tTarget[k] = v end
					end
				end
			end
			if tErr then
				tState.failed[tPath] = tErr
				tState.failedCount = tState.failedCount + 1
			end
			tState.chunks = tState.chunks + 1
			tChunks[i] = nil                   -- free the chunk source string
		end
		tState.ms = debugprofilestop() - tT0
		if Sku and Sku.MetricPoint then
			Sku:MetricPoint(string.format("SkuDB chunk load (eager) = %.0f ms, %d chunks, %d failed",
				tState.ms, tState.chunks, tState.failedCount))
		end
		if tState.failedCount > 0 then
			local tFirst
			for tPath, tErr in pairs(tState.failed) do
				tFirst = tFirst or (tPath .. ": " .. tErr)
				print("|cffff4040SkuDB|r chunk load FAILED for " .. tPath .. ": " .. tErr)
			end
			geterrorhandler()(string.format("SkuDB chunk load: %d chunk(s) FAILED, first: %s",
				tState.failedCount, tFirst))
		end
	end
end
