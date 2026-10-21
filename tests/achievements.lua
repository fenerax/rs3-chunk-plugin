-- Runner sets package.path to the plugin directory before loading this file.
local achievements = require("achievements")
local json = require("json")
local function eq(actual, expected, why)
  assert(actual == expected, (why or "") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local list
local function row(id, progress, name) return {id = id, name = name or ("Ach " .. id), category = 3, subCategory = -1, progress = progress} end
local function fixture(rows)
  list = rows
  config = {Achievement = setmetatable({}, {__pairs = function() return next, list, nil end})}
end
-- __pairs is Lua 5.2+; Fengari honours it, as the game's 5.4 does.
var = {VarPlayer = {CHEEVO_RECENT_COMPLETE_1 = {id = 501}, CHEEVO_RECENT_COMPLETE_2 = {id = 502},
  CHEEVO_RECENT_COMPLETE_3 = {id = 503}, CHEEVO_RECENT_COMPLETE_4 = {id = 504}}}

-- Only progress -2 counts; rows are sorted, de-duplicated and cleaned.
fixture({row(30, -2), row(10, -2, "Tab\there\nnewline"), row(20, 4000), row(40, -1), row(50, 0), row(60, -3), row(10, -2, "Tab\there\nnewline"),
  {id = "x", name = "bad id", progress = -2}, {id = 70, progress = -2}, row(80.5, -2)})
local rows = achievements.read()
eq(#rows, 2, "complete rows"); eq(rows[1][1], 10); eq(rows[2][1], 30)
eq(rows[1][2], "Tab here newline", "control characters"); eq(rows[1][3], 3); eq(rows[1][4], -1)
eq(json.encode(rows[1]), '[10,"Tab here newline",3,-1]', "row shape")
eq(achievements.read() ~= nil, true)
fixture({row(1, -2, string.rep("n", 300))}); eq(#achievements.read()[1][2], 120, "long names are cut")
-- A cut never splits a UTF-8 character: 119 ASCII bytes then a two-byte "é".
fixture({row(1, -2, string.rep("n", 119) .. "\xC3\xA9xyz")}); eq(achievements.read()[1][2], string.rep("n", 119), "cut on a character boundary")
fixture({row(1, -2, "  C1\xC2\x85control  ")}); eq(achievements.read()[1][2], "C1 control", "C1 controls and edge spaces")

-- Rows the picker would refuse are skipped, not sent: negative ids, empty or blank names.
-- Out-of-range categories become -1.
fixture({row(-1, -2), row(5, -2, ""), row(6, -2, " \t "), {id = 7, name = "Low category", category = -5, subCategory = 2.5, progress = -2}})
rows = achievements.read()
eq(#rows, 1, "only the valid row"); eq(json.encode(rows[1]), '[7,"Low category",-1,-1]', "categories clamped")

-- Missing or broken tables read as unavailable, never as "nothing complete".
config = {}; eq(achievements.read(), nil, "no config.Achievement")
config = {Achievement = setmetatable({}, {__pairs = function() error("boom") end})}; eq(achievements.read(), nil, "throwing table")
-- One achievement whose progress can't be read makes the read unavailable, rather than a smaller set.
fixture({row(1, -2), setmetatable({}, {__index = function() error("no access") end})}); eq(achievements.read(), nil, "throwing field")

-- Snapshot names are exact integers in both 32-bit (Fengari) and 64-bit (game) Lua.
-- Expected values come from arbitrary-precision arithmetic.
eq(achievements.checksum("1,2,3,4"), "29eba3f745243189", "checksum 1-4")
eq(achievements.checksum(""), "0000150500000007", "checksum empty")
eq(achievements.checksum("354,1201"), "7959414c0ea550c3", "checksum pair")
local ids = {}
for i = 1, 900 do ids[i] = i end
eq(achievements.checksum(table.concat(ids, ",")), "2dab8fa06b8e88fb", "checksum long")

-- Parts stay under the byte limit and keep every row once, in order.
local many = {}
for i = 1, 900 do many[#many + 1] = row(i, -2, "A fairly long achievement name number " .. i) end
fixture(many)
local parts = achievements.split(achievements.read())
assert(#parts > 1, "900 rows need several parts")
local seen = 0
for _, part in ipairs(parts) do
  assert(#json.encode(part) <= achievements.PART_BYTES, "part too big")
  for _, r in ipairs(part) do seen = seen + 1; eq(r[1], seen, "order") end
end
eq(seen, 900, "every row once")
eq(json.encode(achievements.split({})[1]), "[]", "no rows still sends one empty part")

-- The tracker: login read, parts in order, ack, unchanged sets stay quiet.
fixture({row(1, -2), row(2, -2)})
local t = achievements.new()
eq(t:pending(0), nil, "nothing before login")
t:login(0)
local p = t:pending(0)
eq(p.part, 1); eq(p.parts, 1); eq(#p.complete, 2); assert(p.snapshot:match("^" .. string.rep("%x", 16) .. "$"))
-- What the picker says it holds, as its status would.
local function holds(tracker, part, now, snapshot, parts)
  tracker:sync({achievements = {snapshot = snapshot or part.snapshot, received = part.part, parts = parts or part.parts}}, now or 0)
end
holds(t, p, 0, "other"); eq(t:pending(0).part, 1, "a picker holding another set")
holds(t, p, 0, nil, 2); eq(t:pending(0).part, 1, "a picker expecting a different part count")
t:sync({achievements = {snapshot = p.snapshot, received = "1", parts = 1}}, 0); eq(t:pending(0).part, 1, "a non-number count")
holds(t, p); eq(t:pending(0), nil, "sent"); assert(t:describe():find("^sent"))
-- A picker that forgot the set gets it again, but at most once a minute.
t:sync({}, 100); eq(t:pending(100).part, 1, "picker restart")
holds(t, p, 101); t:sync({}, 130); eq(t:pending(130), nil, "no second restart within a minute")
t:sync({}, 160); eq(t:pending(160).part, 1, "then once more"); holds(t, p, 161)
t:sync({achievements = {snapshot = p.snapshot, received = 9, parts = 1}}, 162); eq(t:pending(162), nil, "counts are clamped")
t:tick(599); eq(t:pending(599), nil)
t:tick(600); eq(t:pending(600), nil, "a periodic read of the same set sends nothing")
t:resend(); eq(t:pending(600).part, 1, "resend after reconnect")
holds(t, p, 600); eq(t:pending(600), nil, "the picker already had it")

-- A recent-completion var schedules a re-read a few seconds later; other vars don't.
list[#list + 1] = row(3, -2)
t:var({var = {id = 999}}, 700); t:tick(710); eq(t:pending(710), nil, "unrelated var")
t:var({var = {id = 502}}, 720); t:tick(722); eq(t:pending(722), nil, "waits for the delay")
t:tick(723); p = t:pending(723); eq(#p.complete, 3, "new completion read")
assert(t:describe():find("recent vars=yes"))

-- A refusal backs off for half an hour, then starts the set again.
t:refused(730); eq(t:pending(731), nil); eq(t:pending(2529), nil); eq(t:pending(2530).part, 1)
assert(t:describe():find("refused"))

-- Multi-part sets go one part at a time.
fixture(many); t:readNow(3000)
local first = t:pending(3000); eq(first.part, 1); eq(first.parts, #parts)
holds(t, first, 3000); eq(t:pending(3000).part, 2)
holds(t, t:pending(3000), 3000); eq(t:pending(3000).part, 3)

-- Too many parts: held locally, and the previous set isn't resent as if current.
local huge = {}
for i = 1, 3000 do huge[#huge + 1] = row(i, -2, string.rep("w", 110)) end
fixture(huge); local u = achievements.new(); u:login(0)
eq(u:pending(0), nil, "held"); assert(u:describe():find("held"))

fixture({row(1, -2)}); local w = achievements.new(); w:login(0); holds(w, w:pending(0))
fixture(huge); w:readNow(10); w:resend(); eq(w:pending(10), nil, "a held set drops the older one")
-- No table at login: unavailable, nothing sent; logout clears everything.
config = {}; local v = achievements.new(); v:login(0); eq(v:pending(0), nil); assert(v:describe():find("unavailable"))
t:reset(); eq(t:pending(5000), nil, "reset clears the set")
print("achievements tests passed")
