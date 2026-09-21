local H = dofile("harness.lua")
local V, at, say = H.V, H.at, H.say
math.randomseed(tonumber(arg[3]))
local t = 0
local n = 0
while t < 180 do
	t = t + math.random() * (math.random() < 0.3 and 3.0 or 0.4)
	local r = math.random()
	n = n + 1
	local txt = "zeile " .. n .. string.rep(" wort", math.random(0, 8))
	if r < 0.55 then say(t, txt, true, {scope="menu"})
	elseif r < 0.70 then say(t, "chat " .. txt, false)
	elseif r < 0.85 then local c = string.char(96 + math.random(1, 26)); at(t, function() V:SpeakEcho(c) end)
	elseif r < 0.92 then at(t, function() V:EndScope("menu"); V:OutputStringBTtts("menue geschlossen " .. n, {overwrite=true, engine="blizz"}) end)
	elseif r < 0.96 then at(t, function() V:CancelBttsOutput(); V:OutputStringBTtts("abgebrochen " .. n, {overwrite=true, engine="blizz"}) end)
	else at(t, function() V:StopOutputEmptyQueue(true, false) end) end
end
H.run(200)
local maxId, ooo, late, worst = 0, 0, 0, 0
for _, h in ipairs(H.heard) do
	if h.id < maxId then ooo = ooo + 1 end
	if h.id > maxId then maxId = h.id end
	local d = h.startedAt - h.handedAt
	if d > 1.0 then late = late + 1 end
	if d > worst then worst = d end
end
if H.isWedged() then print("WEDGED") end
print(string.format("seed=%s lat=%s actions=%d audible=%d out-of-order=%d started>1s-after-handover=%d worst=%.2fs", arg[3], os.getenv("LAT") or "0.12", n, #H.heard, ooo, late, worst))
