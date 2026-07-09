local MODULE_NAME = "SkuOptions"
local L = Sku.L
local _G = _G

---------------------------------------------------------------------------------------------------------------------------------------
-- bit shifts for 64 bit; lua don't has them; why? :D
---------------------------------------------------------------------------------------------------------------------------------------
local band, bor, bxor, bnot = bit.band, bit.bor, bit.bxor, bit.bnot
local lshift, rshift, arshift = bit.lshift, bit.rshift, bit.arshift

---------------------------------------------------------------------------------------------------------------------------------------
function SkuU64join(hi, lo)
	local rshift, band = rshift, band
	hi = rshift(hi, 1) * 2 + band(hi, 1)
	lo = rshift(lo, 1) * 2 + band(lo, 1)
	return (hi * 0x100000000) + (lo % 0x100000000)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuU64split(x)
	return tonumber(x / 0x100000000),  tonumber(x % 0x100000000)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuU64lshift(x, n)
	if band(n, 0x3F) == 0 then return x end
	local hi, lo = SkuU64split(x)
	if band(n, 0x20) == 0 then
		 lo, hi = lshift(lo, n), bor(lshift(hi, n), rshift(lo, 32 - n))
	else
		 lo, hi = 0, lshift(lo, n)
	end
	return SkuU64join(hi, lo)
end

---------------------------------------------------------------------------------------------------------------------------------------
function SkuU64rshift(x, n)
	if band(n, 0x3F) == 0 then return x end
	local hi, lo = SkuU64split(x)
	if band(n, 0x20) == 0 then
		 lo, hi = bor(rshift(lo, n), lshift(hi, 32 - n)), rshift(hi, n)
	else
		 lo, hi = rshift(hi, n - 32), 0
	end
	return SkuU64join(hi, lo)
end

---------------------------------------------------------------------------------------------------------------------------------------
--different helpers
---------------------------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------------
function SkuSpairs(t, order)
	local keys = {}
	for k in pairs(t) do keys[#keys+1] = k end
	if order then
		table.sort(keys, function(a,b) return order(t, a, b) end)
	else
		table.sort(keys)
	end
	local i = 0
	return function()
		i = i + 1
		if keys[i] then
			return keys[i], t[keys[i]]
		end
	end
end

---------------------------------------------------------------------------------------------------------------------------------------
---@param tbl table
---@param indent string
local function tprint (tbl, indent)
	if not indent then indent = 0 end
	for k, v in pairs(tbl) do
		local formatting = string.rep("  ", indent)..k..": "
		if k == 'obj' then
			if v ~= nil then
				print(formatting.."<obj>")
			else
				print(formatting.."nil")
			end
		elseif k == 'func' then
			if v ~= nil then
				print(formatting.."<func>")
			else
				print(formatting.."nil")
			end
		elseif k == 'onActionFunc' then
			if v ~= nil then
				print(formatting.."<onActionFunc>")
			else
				print(formatting.."nil")
			end
		else
			if type(v) == "table" then
				print(formatting)
				tprint(v, indent+1)
			elseif type(v) == 'boolean' then
				print(formatting..tostring(v))      
			elseif type(v) == 'string' then
				print(formatting..string.gsub(v, "\r\n", " "))
			else
				print(formatting..v)
			end
		end
	end
end

