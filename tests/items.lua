-- Runner sets package.path to the plugin directory before loading this file.
local items = require("items")
local json = require("json")
local sha256 = require("sha256")
local function eq(actual, expected, why)
  assert(actual == expected, (why or "") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
-- PersistentDB mock: strings stop at a NUL, as in the game. broken[key] makes calls on it throw.
local values, broken = {}, {}
local db = {CheckExists = function(_, k) if broken[k] then error("storage") end return values[k] ~= nil end}
for _, kind in ipairs({"Bool", "Int", "String"}) do
  db["Get" .. kind] = function(_, k) if broken[k] then error("storage") end return values[k] end
  db["Set" .. kind] = function(_, k, v) if broken[k] then error("storage") end
    if type(v) == "string" then v = v:match("^[^\0]*") end
    values[k] = v; return true end
end
local store = require("store").new(db)
local who = "Alpha"
Player = {GetEntity = function() return {displayName = who, isValid = true} end}
values.keyOwner = "Alpha"
values.personalKey = "synthetic-alpha-key"
values.server = "scratch"
local function savedJournal()
  local saved = json.decode(values.itemJournal)
  if saved.version ~= 2 then return saved end
  local destination = sha256.hex(json.encode(json.array({values.server, values.personalKey})))
  for _, journal in ipairs(saved.journals) do
    if journal.owner == who and journal.destination == destination then return journal end
  end
end
eq(sha256.hex(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "SHA-256 empty")
eq(sha256.hex("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "SHA-256 abc")
eq(sha256.hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
  "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1", "SHA-256 multiple blocks")
-- Containers by numeric id; config.Inv names are absent unless a test adds them.
local invs = {}
local function slot(id, name, count) return {obj = {id = id, name = name}, count = count or 1} end
local function inv(slots, total)
  return {slotCount = total or #slots, isValid = true, GetSlot = function(_, i) return slots[i] end}
end
config = {Inv = {}}
Inventory = {Find = function(which) return invs[which] end}

-- Rows are [slot from 0, id, count, name]; empty slots, id -1 and bad counts are skipped.
invs[93] = inv({slot(857, "Yew shortbow"), false, slot(-1, "", 0), slot(995, "Coins", 12345678901),
  slot(1205, "Tab\tname\0cut"), {obj = 1351, count = 1}, slot(4587, nil, 2.0), slot(30, "Zero", 0)})
local rows, via = items.container(items.BACKPACK)
eq(via, 93, "falls back to the classic id"); eq(#rows, 5, "backpack rows")
eq(json.encode(rows[1]), '[0,857,1,"Yew shortbow"]', "row shape")
eq(rows[2][1], 3, "slots count from 0"); eq(rows[2][3], 2147483647, "counts are capped")
eq(rows[3][4], "Tab name cut", "control characters"); eq(rows[4][4], "Item 1351", "a bare id gets a placeholder name")
eq(rows[5][3], 2, "integral float counts")
config.Inv.INV = "named"; invs.named = inv({slot(1, "Named")}); eq(select(2, items.container(items.BACKPACK)), "INV", "names first")
config.Inv.INV = nil
-- Unreadable is nil, never an empty list.
eq(items.container({94}), nil, "absent container")
invs[94] = inv({}); eq(#items.container({94}), 0, "empty but readable")
invs[94] = {slotCount = 2, isValid = false, GetSlot = function() end}; eq(items.container({94}), nil, "invalid container")
invs[94] = inv({slot(1, "One"), setmetatable({}, {__index = function() error("no access") end})}); eq(items.container({94}), nil, "throwing slot")
local far = {}; for i = 1, 70 do far[i] = false end; far[65] = slot(5, "Far")
invs[94] = inv(far); eq(items.container({94}), nil, "an item past slot 64 makes the read unavailable")
far[65] = false; eq(#items.container({94}), 0, "empty slots past 64 are fine")
Inventory = nil; eq(items.container({94}), nil, "no Inventory API")
Inventory = {Find = function(which) return invs[which] end}

-- First read: the journal starts, worn items become events and the payload names both containers.
invs[93] = inv({slot(857, "Yew shortbow")})
invs[94] = inv({slot(34830, "Gud raider chainbody"), slot(1205, "Adamant dagger")})
local tracker = items.new(store)
eq(tracker:pending(0), nil, "nothing before a read")
tracker:login(0)
local body, key = tracker:pending(0)
eq(#body.snapshot, 16, "snapshot"); eq(#body.worn, 2); eq(#body.backpack, 1)
eq(#body.journal.id, 16, "journal id"); eq(#body.journal.events, 2, "worn items journalled")
local saved = savedJournal()
eq(saved.owner, "Alpha"); eq(saved.next, 3); eq(saved.id, body.journal.id)
local encoded = json.encode(body)
assert(encoded:find('"journal":{"events":%[%[1,'), encoded)
-- The same content waits a minute while the picker hasn't acknowledged it.
tracker:sent(key, 0)
eq(tracker:pending(30), nil, "no flood"); assert(tracker:pending(61), "then again")
-- The acknowledgement drops held events and stops resending.
tracker:sync({items = {snapshot = body.snapshot, journal = {id = body.journal.id, event = 1}}}, 61)
eq(#savedJournal().events, 1, "event 1 dropped")
body = tracker:pending(62); eq(#body.journal.events, 1, "event 2 still offered"); eq(body.journal.events[1][1], 2)
tracker:sync({items = {snapshot = body.snapshot, journal = {id = body.journal.id, event = 2}}}, 62)
eq(tracker:pending(63), nil, "all acknowledged")
-- An ack for another journal id drops nothing.
tracker:tick(63)
invs[94] = inv({slot(1205, "Adamant dagger"), slot(34828, "Gud raider shield")})
tracker:inventory(64); tracker:tick(65); eq(tracker:pending(65), nil, "reads wait for the delay")
tracker:tick(66); body, key = tracker:pending(66); assert(body, "a change is offered"); tracker:sent(key, 66)
eq(#body.journal.events, 1); eq(body.journal.events[1][2], 34828, "only the newly worn item")
tracker:sync({items = {snapshot = body.snapshot, journal = {id = "ffffffffffffffff", event = 9}}}, 66)
eq(#savedJournal().events, 1, "foreign ack ignored")
-- A picker restart forgets everything; the plugin offers the reading again.
tracker:sync({items = {snapshot = body.snapshot, journal = {id = body.journal.id, event = 3}}}, 67)
eq(tracker:pending(67), nil); tracker:sync({state = "locked"}, 68); assert(tracker:pending(68), "resent after restart")
-- A refusal waits half an hour.
tracker:refused(68); eq(tracker:pending(1000), nil); assert(tracker:pending(68 + 1801))

-- The journal survives a restart of the plugin and keeps counting.
invs[94] = inv({slot(34828, "Gud raider shield"), slot(34832, "Gud raider axe")})
local id = savedJournal().id
tracker = items.new(store); tracker:login(100)
body = tracker:pending(100); eq(body.journal.id, id, "same journal")
-- Its acknowledged events are gone, so a new session notes the shield again (4), then the axe (5).
local numbers = {}
for i, event in ipairs(body.journal.events) do numbers[i] = event[1] .. ":" .. event[2] end
eq(table.concat(numbers, ","), "4:34828,5:34832", "counting continues")

-- An unreadable container is null, and a different reading.
local before = body.snapshot
invs[93] = nil; tracker:readNow(101); body = tracker:pending(101)
eq(body.backpack, json.null); assert(json.encode(body):find('"backpack":null')); assert(body.snapshot ~= before)
invs[93] = inv({}); tracker:readNow(102); assert(tracker:pending(102).snapshot ~= body.snapshot, "empty differs from unreadable")

-- Only the key's character journals. Another character keeps the journal untouched.
local stored = values.itemJournal
who = "Bravo"; tracker = items.new(store); tracker:login(200)
eq(values.itemJournal, stored, "another character leaves the journal alone")
assert(tracker:describe():find("memory only"), tracker:describe())
eq(tracker:pending(200), nil, "another character cannot upload even a memory journal")
-- A second legitimate key gets a separate slot while Alpha's brief wearing stays pending.
values.keyOwner, values.personalKey = "Bravo", "synthetic-bravo-key"
invs[94] = inv({slot(2222, "Bravo boots")}); tracker:readNow(201)
saved = savedJournal(); eq(saved.owner, "Bravo"); assert(saved.id ~= id, "new journal id")
eq(#json.decode(values.itemJournal).journals, 2, "both legitimate destinations retained")
body, key = tracker:pending(201); tracker:sent(key, 201)
eq(#body.journal.events, 1); eq(body.journal.events[1][2], 2222, "no Alpha items under Bravo key")
local bravoId = body.journal.id
-- A late Alpha ack cannot remove Bravo events.
tracker:sync({items = {journal = {id = id, event = 99}}}, 202)
eq(#savedJournal().events, 1, "foreign destination ack ignored")
tracker:sync({items = {snapshot = body.snapshot, journal = {id = bravoId, event = 1}}}, 202)
eq(#savedJournal().events, 0, "only Bravo delivered prefix removed")
values.keyOwner, values.personalKey, who = "Alpha", "synthetic-alpha-key", "Alpha"
invs[94] = inv({}) -- Alpha no longer wears the items; only the retained journal observes them.
tracker = items.new(store); tracker:login(203)
body = tracker:pending(203); eq(body.journal.id, id); eq(#body.journal.events, 2, "Alpha pending observations survive")
eq(body.journal.events[2][2], 34832, "briefly worn axe still offered")
-- Changing just the key, or just the server, also selects an independent journal immediately.
local alphaPending = json.encode(savedJournal())
values.personalKey = "synthetic-alpha-second-key"
tracker:sync({items = {journal = {id = id, event = 99}}}, 204)
values.personalKey = "synthetic-alpha-key"
eq(json.encode(savedJournal()), alphaPending, "late ack after key change cannot remove old events")
values.personalKey = "synthetic-alpha-second-key"
body = tracker:pending(204); assert(body.journal.id ~= id); eq(#body.journal.events, 0, "old events cannot use a new key")
values.server = "home"; body = tracker:pending(205); eq(#body.journal.events, 0, "server has its own destination")
values.server, values.personalKey = "scratch", "synthetic-alpha-key"
body = tracker:pending(206); eq(json.encode(savedJournal()), alphaPending, "key and server switches preserve pending journal")
eq(body.journal.id, id)
-- A journal that can't be read is never overwritten.
values.keyOwner = "Alpha"; who = "Alpha"; values.itemJournal = stored; broken.itemJournal = true
tracker = items.new(store); tracker:login(300)
broken.itemJournal = nil; eq(values.itemJournal, stored, "unreadable journal kept")
assert(tracker:describe():find("memory only"))
-- Malformed single-slot journals start again; undecodable storage is preserved.
values.itemJournal = "not json"; tracker = items.new(store); tracker:login(399)
eq(values.itemJournal, "not json"); assert(tracker:describe():find("memory only"))
for _, text in ipairs({'{"id":"zz","owner":"Alpha","next":1,"events":[]}', '{"id":"0123456789abcdef","owner":"Alpha","next":2,"events":[5]}',
  '{"id":"0123456789abcdef","owner":"Alpha","next":2,"events":[[1,5,"A"],[1,6,"B"]]}'}) do
  values.itemJournal = text; tracker = items.new(store); tracker:login(400)
  local fresh = savedJournal(); eq(fresh.owner, "Alpha", text); assert(fresh.id ~= "0123456789abcdef", text)
end

-- Migration follows the recorded owner even when another properly bound character opens first.
local legacy = '{"id":"0123456789abcdef","owner":"Alpha","next":3,"events":[[1,51,"Old hat"],[2,52,"Old boots"]]}'
values.itemJournal = legacy
who, values.keyOwner, values.personalKey = "Bravo", "Bravo", "synthetic-bravo-key"
invs[94] = inv({slot(2222, "Bravo boots")}); tracker = items.new(store); tracker:login(410)
eq(#json.decode(values.itemJournal).journals, 2, "legacy slot migrated alongside Bravo")
body, key = tracker:pending(410); tracker:sent(key, 410)
tracker:sync({items = {snapshot = body.snapshot, journal = {id = body.journal.id, event = 1}}}, 411)
local migrated = json.decode(values.itemJournal).journals[1]
eq(migrated.owner, "Alpha"); eq(migrated.destination, nil, "unrelated key never claims old slot")
eq(#migrated.events, 2, "Bravo ack keeps migrated Alpha events")
who, values.keyOwner, values.personalKey = "Alpha", "Alpha", "synthetic-alpha-key"
invs[94] = inv({}); tracker = items.new(store); tracker:login(412)
body, key = tracker:pending(412); eq(body.journal.id, "0123456789abcdef"); eq(#body.journal.events, 2)
tracker:sent(key, 412)
tracker:sync({items = {snapshot = body.snapshot, journal = {id = body.journal.id, event = 1}}}, 413)
eq(#savedJournal().events, 1); eq(savedJournal().events[1][1], 2, "migration retains unacknowledged suffix")
tracker = items.new(store); tracker:login(414); eq(#tracker:pending(414).journal.events, 1, "migration survives restart")

-- Capacity never evicts pending observations, and acknowledged empty slots can be reused.
values.itemJournal = nil
for i = 1, items.MAX_JOURNALS do
  who, values.keyOwner, values.personalKey = "Character" .. i, "Character" .. i, "synthetic-key-" .. i
  local outfit = {}; for n = 1, items.JOURNAL do outfit[n] = slot(i * 100 + n, string.rep('"', 80)) end
  invs[94] = inv(outfit); tracker = items.new(store); tracker:login(420 + i)
  eq(#savedJournal().events, items.JOURNAL); assert(#values.itemJournal <= items.STORE_BYTES)
end
local atCapacity = values.itemJournal
who, values.keyOwner, values.personalKey = "Overflow", "Overflow", "synthetic-overflow-key"
tracker = items.new(store); tracker:login(440)
eq(values.itemJournal, atCapacity, "all pending slots kept at capacity")
assert(tracker:describe():find("journal storage full")); assert(tracker:describe():find("memory only"))
who, values.keyOwner, values.personalKey = "Character1", "Character1", "synthetic-key-1"
invs[94] = inv({}); tracker = items.new(store); tracker:login(441)
body, key = tracker:pending(441); tracker:sent(key, 441)
tracker:sync({items = {snapshot = body.snapshot, journal = {id = body.journal.id, event = items.JOURNAL}}}, 442)
who, values.keyOwner, values.personalKey = "Overflow", "Overflow", "synthetic-overflow-key"
tracker = items.new(store); tracker:login(443)
eq(#json.decode(values.itemJournal).journals, items.MAX_JOURNALS, "empty slot reused within bound")
assert(savedJournal(), "new destination persisted after room made")
-- Oversized persisted documents are never overwritten or decoded into an unbounded store.
values.itemJournal = string.rep(" ", items.STORE_BYTES) .. atCapacity
local oversized = values.itemJournal
tracker = items.new(store); tracker:login(444); eq(values.itemJournal, oversized)
assert(tracker:describe():find("memory only"))
who, values.keyOwner, values.personalKey = "Alpha", "Alpha", "synthetic-alpha-key"

-- The journal holds at most 32 events; more worn items wait for room.
values.itemJournal = nil
local many = {}; for i = 1, 40 do many[i] = slot(1000 + i, "Ring " .. i) end
invs[94] = inv(many); tracker = items.new(store); tracker:login(500)
body, key = tracker:pending(500); tracker:sent(key, 500)
eq(#body.journal.events, 32, "bounded"); assert(tracker:describe():find("journal full"))
tracker:sync({items = {snapshot = body.snapshot, journal = {id = body.journal.id, event = 32}}}, 501)
assert(not tracker:describe():find("journal full"), "room again")
-- Reports stay under 16 KB: the newest journal events wait, and oversized containers are held.
local long = string.rep("n", 80)
local full, bag = {}, {}
for i = 1, 64 do full[i] = slot(2000 + i, long); bag[i] = slot(3000 + i, long) end
values.itemJournal = nil; invs[94] = inv(full); invs[93] = inv({slot(1, "One")})
tracker = items.new(store); tracker:login(600)
body = tracker:pending(600)
assert(#json.encode(body) <= items.MAX_BYTES, "within the cap"); eq(#body.journal.events, 32, "fits")
invs[93] = inv(bag); tracker:readNow(601); body, key = tracker:pending(601)
assert(body and #json.encode(body) <= items.MAX_BYTES and #body.journal.events < 32, "journal trimmed")
local delivered = #body.journal.events
tracker:sent(key, 601)
tracker:sync({items = {snapshot = body.snapshot, journal = {id = body.journal.id, event = 999}}}, 601)
eq(#savedJournal().events, 32 - delivered, "ack cannot discard events omitted to fit report")
-- Two full containers at the widest values still fit without the journal.
local wide = {}; for i = 1, 64 do wide[i] = slot(999990 + i % 10, long, 2147483647) end
invs[93], invs[94] = inv(wide), inv(wide); tracker:readNow(602)
body = tracker:pending(602); assert(body and #json.encode(body) <= items.MAX_BYTES, "widest containers fit")
-- Names never carry a NUL into storage.
assert(not values.itemJournal:find("\0", 1, true))
-- Tool belt: TOOLBELT_<TOOL> varbits only, bookkeeping left out, nonzero values from 1 to 1000.
eq(items.beltName("TOOLBELT_NOOSE_WAND"), "NOOSE_WAND"); eq(items.beltName("TOOLBELT_HATCHET_LEVEL"), "HATCHET_LEVEL")
for _, name in ipairs({"TOOLBELT_RAND_CHISEL", "TOOLBELT_LAST_SLOT", "TOOLBELT_CURRENT_CATEGORY", "TOOLBELT_HATCHET_LEVEL_OLD",
  "TOOLBELT_BONECRUSHER_BOUGHT", "TOOLBELT_BONECRUSHER_ENABLED", "TOOLBELT_GOLD_ACC", "CHEEVO_TOOLBELT", "TASK_TOOLBELT_ADD_SHEARS",
  "TOOLBELT_lower", "TOOLBELT_", "TOOLBELT_" .. string.rep("A", 41)}) do
  eq(items.beltName(name), nil, name)
end
local vars = {}
local function variable(key, name, id, value, varbit) vars[key] = {configName = name, id = id, value = value, isVarBit = varbit} end
variable(1, "TOOLBELT_NOOSE_WAND", -3008, 1, true); variable(2, "TOOLBELT_HATCHET", -2986, 1, true)
variable(3, "TOOLBELT_HATCHET_LEVEL", -18523, 6, true); variable(4, "TOOLBELT_HOLY_MOULD", -2973, 0, true)
variable(5, "TOOLBELT_FREE_TOOLS", 1102, 806354927, false); variable(6, "TOOLBELT_STRUCT", 7863, nil, false)
variable(7, "TOOLBELT_RAND_HATCHET", -3010, 6, true); variable(8, "TOOLBELT_MATTOCK", -46000, 3, true)
variable(9, "TOOLBELT_SEXTANT", -686, 5000, true); variable(10, "QUEST_POINTS", 101, 50, false)
var = {VarPlayer = vars}
local found = items.beltVars(); eq(#found, 6, "tool varbits")
eq(json.encode(items.belt(found)), '[["HATCHET",1],["HATCHET_LEVEL",6],["MATTOCK",3],["NOOSE_WAND",1]]', "belt rows")
-- Each read looks the var up again, so a change shows.
vars[4] = {configName = "TOOLBELT_HOLY_MOULD", id = -2973, value = 1, isVarBit = true}
assert(json.encode(items.belt(found)):find('"HOLY_MOULD",1'), "a new tool")
vars[4] = setmetatable({}, {__index = function() error("gone") end}); eq(items.belt(found), nil, "a throwing value")
vars[4] = {configName = "TOOLBELT_HOLY_MOULD", id = -2973, value = "x"}; eq(items.belt(found), nil, "a value that isn't a number")
vars[4] = {configName = "TOOLBELT_HOLY_MOULD", id = -2973, value = 0}
var = {VarPlayer = {{configName = "QUEST_POINTS", id = 1, value = 3}}}; eq(items.beltVars(), nil, "no tool names is unreadable, not empty")
var = nil; eq(items.beltVars(), nil, "no var API")
var = {VarPlayer = vars}

-- Coin pouch and belt ride along only for a picker that accepts them, and change the snapshot.
values.itemJournal = nil
invs[93] = inv({slot(995, "Coins", 120)}); invs[94] = inv({slot(1205, "Adamant dagger")})
invs[623] = inv({slot(995, "Coins", 82094), slot(54830, "Coins (billions)", 2)})
tracker = items.new(store); tracker:login(700)
body = tracker:pending(700)
eq(body.pouch, nil, "no pouch for an older picker"); eq(body.toolbelt, nil, "no belt for an older picker")
local plainSnapshot = body.snapshot
body, key = tracker:pending(700, {pouch = true, toolbelt = true})
eq(json.encode(body.pouch), '[[0,995,82094,"Coins"],[1,54830,2,"Coins (billions)"]]', "pouch rows")
eq(#body.toolbelt, 4, "belt rows"); assert(body.snapshot ~= plainSnapshot, "the snapshot covers what is sent")
eq(items.coins(body.pouch), "2000082094", "coins with billions")
assert(tracker:describe():find("pouch=2000082094 coins; belt=4"), tracker:describe())
tracker:sent(key, 700)
tracker:sync({items = {snapshot = body.snapshot, journal = {id = body.journal.id, event = body.journal.events[#body.journal.events][1]}}}, 701)
eq(tracker:pending(702, {pouch = true, toolbelt = true}), nil, "acknowledged")
-- A tool added to the belt is a new reading.
vars[4] = {configName = "TOOLBELT_HOLY_MOULD", id = -2973, value = 1, isVarBit = true}
tracker:readNow(800); body = tracker:pending(800, {pouch = true, toolbelt = true})
assert(body and #body.toolbelt == 5, "the belt change goes")
-- An unreadable pouch or belt is null, never empty.
invs[623] = nil; var = nil
tracker = items.new(store); tracker:login(900); body = tracker:pending(900, {pouch = true, toolbelt = true})
eq(body.pouch, json.null); eq(body.toolbelt, json.null); assert(json.encode(body):find('"toolbelt":null'))
assert(tracker:describe():find("pouch=unreadable; belt=unreadable"), tracker:describe())
-- The belt search isn't repeated on every read; it tries again after ten minutes.
var = {VarPlayer = vars}; tracker:readNow(905); eq(tracker.toolbelt, nil, "not searched again yet")
tracker:readNow(1501); eq(#tracker.toolbelt, 5, "searched again")
-- Too big with two full containers: the belt goes as unreadable before the whole report is held.
local beltVars = {}
for i = 1, 128 do beltVars[i] = {configName = "TOOLBELT_" .. string.rep("T", 36) .. string.format("%04d", i), id = -i, value = 1000, isVarBit = true} end
var = {VarPlayer = beltVars}
values.itemJournal = nil; invs[93], invs[94] = inv(wide), inv(wide)
tracker = items.new(store); tracker:login(2000)
body, key = tracker:pending(2000, {pouch = true, toolbelt = true})
assert(body and #json.encode(body) <= items.MAX_BYTES, "within the cap"); eq(body.toolbelt, json.null, "belt dropped")
local initialEvents = #savedJournal().events
tracker:sent(key, 2000); tracker:sync({items = {snapshot = body.snapshot, journal = {id = body.journal.id, event = 1000}}}, 2001)
eq(#savedJournal().events, initialEvents - #body.journal.events, "only delivered events leave the trimmed reading")
assert(tracker:pending(2100, {pouch = true, toolbelt = true}), "omitted events remain retryable")
var = nil
print("items tests passed")
