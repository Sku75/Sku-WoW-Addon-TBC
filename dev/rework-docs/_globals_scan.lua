-- Lists every global a Lua file writes (GSET) or, with "all", also reads (GGET),
-- with file and line, from LuaJIT bytecode - exact, no text matching.
-- Run from the repo root:
--   luajit dev/rework-docs/_globals_scan.lua Sku/SkuCore/Core.lua [more files] [all]
-- A Sku file should write no globals except its module table (SkuCore, SkuChat ...),
-- SLASH_*/BINDING_* names and the few documented in dev/FOREVER-PRS.md.
local jutil = require("jit.util")
local bcnames = require("jit.vmdef").bcnames
local showReads = false
local function opname(ins)
	local op = bit.band(ins, 0xff)
	return (bcnames:sub(op * 6 + 1, op * 6 + 6):gsub(" ", ""))
end
local function walk(fn, file, seen)
	if seen[fn] then return end
	seen[fn] = true
	local pc = 1
	while true do
		local ins = jutil.funcbc(fn, pc)
		if not ins then break end
		local op = opname(ins)
		if op == "GSET" or (showReads and op == "GGET") then
			local name = jutil.funck(fn, -bit.rshift(ins, 16) - 1)
			print(op .. "\t" .. tostring(name) .. "\t" .. file .. ":" .. tostring(jutil.funcinfo(fn, pc).currentline))
		end
		pc = pc + 1
	end
	local i = -1
	while true do
		local k = jutil.funck(fn, i)
		if k == nil then break end
		if type(k) == "proto" then walk(k, file, seen) end
		i = i - 1
	end
end
for _, a in ipairs(arg) do
	if a == "all" then showReads = true end
end
for _, file in ipairs(arg) do
	if file ~= "all" then
		local f, e = loadfile(file)
		if f then walk(f, file, {}) else io.stderr:write(e .. "\n") end
	end
end
