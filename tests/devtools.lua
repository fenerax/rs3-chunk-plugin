-- Runner puts dev/chunk-picker-dev on package.path for this file, after the plugin directory.
local cmd = require("devcmd")
local location = require("location")
local function eq(actual, expected, why)
  assert(actual == expected, (why or "") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end

-- Chunk ids agree with the real plugin's formula, both ways.
for _, s in ipairs({{50, 50}, {0, 0}, {199, 199}, {53, 45}}) do
  local p = location.fromGrid({mapSquareX = s[1], mapSquareZ = s[2], level = 0})
  eq(cmd.chunkOf(s[1], s[2]), p.chunk, "chunk formula matches location.lua")
  local x, z = cmd.squareOf(p.chunk); eq(x, s[1], "x back"); eq(z, s[2], "z back")
end
eq(cmd.chunkOf(50, 50), 12850, "Lumbridge")
eq(cmd.squareOf(200), nil, "z past 199"); eq(cmd.squareOf(-1), nil, "negative"); eq(cmd.squareOf(51200), nil, "x past 199")
eq(cmd.squareOf(1.5), nil, "not an integer")

-- Targets: chunk id, x,z and floor,x,z, with commas or underscores like !tele.
local t = cmd.parseTarget("12850"); eq(t.x, 50); eq(t.z, 50); eq(t.floor, nil, "no floor typed")
t = cmd.parseTarget(" 53,45 "); eq(t.x, 53); eq(t.z, 45); eq(t.floor, nil)
t = cmd.parseTarget("1_50_52"); eq(t.floor, 1); eq(t.x, 50); eq(t.z, 52)
for _, bad in ipairs({"", "abc", "50,", "50,200", "4,50,50", "1,2,3,4", "-1,5", "12850;!bank", "200"}) do
  local value, why = cmd.parseTarget(bad)
  eq(value, nil, "refuses " .. bad); assert(type(why) == "string" and #why > 0, "says why for " .. bad)
end
eq(cmd.parseTarget(nil), nil, "nil text")

-- Neighbours: north is +z, east is +x, nothing past the map's edge.
local x, z = cmd.neighbour(50, 50, "N"); eq(x, 50); eq(z, 51)
x, z = cmd.neighbour(50, 50, "E"); eq(x, 51); eq(z, 50)
x, z = cmd.neighbour(50, 50, "S"); eq(x, 50); eq(z, 49)
x, z = cmd.neighbour(50, 50, "W"); eq(x, 49); eq(z, 50)
eq(cmd.neighbour(0, 10, "W"), nil, "west edge"); eq(cmd.neighbour(10, 199, "N"), nil, "north edge")
eq(cmd.neighbour(10, 10, "up"), nil, "unknown direction")

-- The exact command strings.
eq(cmd.tele(0, 50, 50, 32, 32), "!tele 0,50,50,32,32", "tele")
eq(cmd.tele(4, 50, 50, 32, 32), nil, "floor 4"); eq(cmd.tele(0, 50, 50, 64, 0), nil, "local 64")
eq(cmd.tele(0, 50, 50, 1.5, 0), nil, "fractional local")
eq(cmd.give("logs", ""), "!give logs 1", "count defaults to 1")
eq(cmd.give("bronze_dagger", " 5 "), "!give bronze_dagger 5")
eq(cmd.give("coins", "2147483647"), "!give coins 2147483647")
eq(cmd.give("coins", "2147483648"), nil, "count too big"); eq(cmd.give("coins", "0"), nil, "zero")
eq(cmd.give("coins", "20m"), "!give coins 20000000"); eq(cmd.give("coins", "1.5K"), "!give coins 1500")
eq(cmd.give("coins", "2.3m"), "!give coins 2300000", "rounding"); eq(cmd.give("coins", "2b"), "!give coins 2000000000")
eq(cmd.give("coins", "20,000,000"), "!give coins 20000000"); eq(cmd.give("coins", " 7 k "), "!give coins 7000")
eq(cmd.give("coins", "3b"), nil, "over the max"); eq(cmd.give("coins", "1.5"), nil, "a fraction"); eq(cmd.give("coins", "5x"), nil)
eq(cmd.give("coins", "0.0001k"), nil, "rounds to a fraction"); eq(cmd.give("coins", "k"), nil)
eq(cmd.give("coins", "1e3"), nil, "not digits"); eq(cmd.give("logs bank", "1"), nil, "a name can't carry an inventory")

-- Item names: typed configNames pass, ids go through the lookup, nothing else gets through.
local lookups = {}
local function find(n) lookups[#lookups + 1] = n; if n == 1511 then return "logs" end; if n == 7 then error("no such obj") end; if n == 8 then return "bad name;!bank" end end
eq(cmd.itemName(" Bronze_dagger ", find), "Bronze_dagger", "typed name"); eq(#lookups, 0, "names aren't looked up")
eq(cmd.itemName("1511", find), "logs", "id looked up"); eq(lookups[1], 1511)
local name, why = cmd.itemName("99999", find); eq(name, nil, "unknown id"); assert(why:find("99999"), "names the id")
eq(cmd.itemName("7", find), nil, "a throwing lookup is a miss")
eq(cmd.itemName("8", find), nil, "a looked-up name must be a plain configName")
eq(cmd.itemName("logs; !tele 0,1,1", find), nil, "no second command"); eq(cmd.itemName("   ", find), nil, "blank")

-- Position line.
eq(cmd.positionLine({mapSquareX = 53, mapSquareZ = 45, localX = 35, localZ = 12, level = 0}),
  "Chunk 13613 · square 53,45 · local 35,12 · floor 0", "position line")
assert(cmd.positionLine({mapSquareX = 50, mapSquareZ = 50, localX = 1, localZ = 2, level = 1}, true):find("instance"), "instance note")
-- Noted copies: next to the item, same name, always stacks.
local objs = {
  [1511] = {id = 1511, name = "Logs", configName = "logs", stackType = 0},
  [1512] = {id = 1512, name = "Logs", configName = "logs_noted", stackType = 1},
  [995] = {id = 995, name = "Coins", configName = "coins", stackType = 1},
  [40] = {id = 40, name = "Thing", configName = "thing", stackType = 0},
  [41] = {id = 41, name = "Other", configName = "other", stackType = 1},
  [61] = {id = 61, name = "Back", configName = "back_noted", stackType = 1},
  [62] = {id = 62, name = "Back", configName = "back", stackType = 0}}
local function look(n) if n == 63 then error("boom") end; return objs[n] end
eq(cmd.notedOf(objs[1511], look), "logs_noted", "the note is the next id")
eq(cmd.notedOf(objs[62], look), "back_noted", "or the one before")
local nn, nwhy = cmd.notedOf(objs[995], look); eq(nn, nil); assert(nwhy:find("already stacks"), "stackables say so")
nn, nwhy = cmd.notedOf(objs[40], look); eq(nn, nil); assert(nwhy:find("Thing"), "a neighbour with another name is no note")
assert(nwhy:find("41=Other/1", 1, true), "says what sat next to it")
eq(cmd.notedOf(nil, look), nil, "unreadable item")
-- Item search: exact, then starts-with, then contains; noted copies left out.
local names = {[892] = "Rune arrow", [893] = "Rune arrow (p)", [1511] = "Logs", [1512] = "Logs", [4] = "Broad rune arrow", [11] = "Rune arrowheads"}
local found = cmd.search(names, " RUNE ARROW ")
eq(#found, 4); eq(found[1], 892, "exact first"); eq(found[2], 11, "then starts-with by id"); eq(found[3], 893); eq(found[4], 4, "then contains")
eq(#cmd.search(names, "logs"), 1, "the noted copy is left out"); eq(#cmd.search(names, "r"), 0, "needs 2 letters")
eq(#cmd.search(names, "rune", 2), 2, "capped"); eq(#cmd.search(names, nil), 0)
eq(cmd.positionLine(nil), "Position: waiting"); eq(cmd.positionLine({}), "Position: unreadable")

-- The plugin itself, against a mock client: commands come only from buttons, never from ticks.
local sent, buttons, texts, inputs, events = {}, {}, {}, {}, {}
local here = {mapSquareX = 50, mapSquareZ = 50, localX = 9, localZ = 56, level = 0}
ExecuteConsoleCommand = function(c) sent[#sent + 1] = c end
print = function() end
ui = {Interfaces = {GetComponent = function() return {width = 800, height = 600} end}}
id = {Component = {}}
Player = {IsAvailable = function() return true end, GetEntity = function() return {coordGrid = here} end}
World = {IsRegion = function() return false end}
config = {Obj = {FromID = function(n) local o = objs[n]; return o and {id = o.id + 0.0, name = o.name, configName = o.configName, stackType = o.stackType} end, LOGS = objs[1511], COINS = objs[995]}}
Event = {}
for _, name in ipairs({"Draw", "ServerLogic"}) do
  Event[name] = {Subscribe = function(_, fn) events[name] = fn end, Unsubscribe = function() events[name] = nil end}
end
prettyui = {Window = {new = function()
  return {
    AddText = function(_, o) local t = {content = type(o) == "table" and o.text or o}; texts[#texts + 1] = t; return t end,
    AddTextField = function(_, o) local f = {value = "", GetText = function(self) return self.value end, SetText = function(self, v) self.value = v end}; inputs[o.placeholder] = f; return f end,
    AddSimpleButton = function(_, label, fn) buttons[label] = fn end,
    Destroy = function() end}
end}}
local dir = package.searchpath("devcmd", package.path):gsub("devcmd%.lua$", "")
dofile(dir .. "main.lua")
local function tick(seconds) events.Draw({timeDeltaSecs = seconds or 3}); events.ServerLogic({}) end
for _ = 1, 5 do tick() end
eq(#sent, 0, "ticks never send a command")
eq(texts[1].content, "Chunk 12850 · square 50,50 · local 9,56 · floor 0", "position shown")
local result = texts[#texts]
inputs["12850 or 50,50"].value = "53,45"; buttons.Teleport()
eq(sent[1], "!tele 0,53,45,32,32", "teleport to the middle of the chunk")
buttons.N(); eq(#sent, 1, "a second press inside 2 seconds waits")
assert(result.content:find("Sent #1: !tele 0,53,45,32,32", 1, true) and result.content:find("ignored"), "keeps the last send and says the press was dropped")
tick(); buttons.N(); eq(sent[2], "!tele 0,50,51,9,56", "north keeps floor and spot")
tick(); inputs["logs or 1511"].value = "1511"; inputs["Count: 1, 5000, 20k, 1.5m, 2b"].value = "28"; buttons.Give()
eq(sent[3], "!give logs 28", "give by id")
tick(); inputs["logs or 1511"].value = "logs; !bank"; buttons.Give(); eq(#sent, 3, "a bad name sends nothing")
tick(); inputs["logs or 1511"].value = "logs"; inputs["Count: 1, 5000, 20k, 1.5m, 2b"].value = "5000"; buttons["Give noted"]()
eq(sent[4], "!give logs_noted 5000", "give noted by name"); eq(#sent, 4)
tick(); inputs["logs or 1511"].value = "coins"; buttons["Give noted"](); eq(#sent, 4, "coins have no note")
assert(result.content:find("already stacks"), "says why")
tick(); inputs["logs or 1511"].value = "rune_arrows"; inputs["Count: 1, 5000, 20k, 1.5m, 2b"].value = "50"; buttons.Give()
eq(sent[5], "!give rune_arrows 50", "an unknown name still goes"); assert(result.content:find("type its id", 1, true), "but warns")
tick(); inputs["logs or 1511"].value = "LOGS"; inputs["Count: 1, 5000, 20k, 1.5m, 2b"].value = "2"; buttons.Give()
eq(sent[6], "!give logs 2", "a known name goes as its exact configName"); assert(not result.content:find("check"), "no warning")
tick(); inputs["logs or 1511"].value = "1511"; inputs["Count: 1, 5000, 20k, 1.5m, 2b"].value = "3"; buttons["Give noted"]()
eq(sent[7], "!give logs_noted 3", "give noted by id"); eq(#sent, 7)
tick(); inputs["logs or 1511"].value = "nothing_here"; buttons["Give noted"](); eq(#sent, 7, "unknown name sends nothing")
assert(result.content:find("Couldn't look up nothing_here", 1, true), "names what failed")
tick(); buttons["Open bank"](); buttons["Where am I"](); eq(sent[8], "!bank"); eq(#sent, 8, "cooldown again")
tick(); buttons["Where am I"](); eq(sent[9], "!getcoord")
ExecuteConsoleCommand = function() error("not allowed here") end
tick(); buttons["Open bank"](); assert(result.content:find("type: !bank", 1, true), "a failed command is shown to type")
-- Search reads the item list over frames, then a number fills Give with that id.
local before = #sent
inputs["rune arrow"].value = "x"; buttons.Search(); assert(result.content:find("2 letters"), "too short")
inputs["rune arrow"].value = "logs"; buttons.Search(); assert(result.content:find("Reading"), "reads first")
for _ = 1, 200 do events.Draw({timeDeltaSecs = 0.016}) end
assert(result.content:find("1 found", 1, true), "found once read: " .. result.content)
local rows = {}; for i = 1, #texts do rows[#rows + 1] = texts[i].content end
assert(table.concat(rows, "|"):find("1. Logs (1511)", 1, true), "result row shown")
buttons["1"](); eq(inputs["logs or 1511"].value, "1511", "picking fills the id"); eq(#sent, before, "searching sends nothing")
inputs["rune arrow"].value = "zzz"; buttons.Search(); assert(result.content:find("No item names"), "none found")
PluginShutdown(); eq(events.ServerLogic, nil, "shutdown unsubscribes")
print = nil
io.write("devtools tests passed\n")
