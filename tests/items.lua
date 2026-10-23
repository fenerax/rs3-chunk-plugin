-- Runner sets package.path to the plugin directory before loading this file.
local items = require("items")
local json = require("json")
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
local saved = json.decode(values.itemJournal)
eq(saved.owner, "Alpha"); eq(saved.next, 3); eq(saved.id, body.journal.id)
local encoded = json.encode(body)
assert(encoded:find('"journal":{"events":%[%[1,'), encoded)
-- The same content waits a minute while the picker hasn't acknowledged it.
tracker:sent(key, 0)
eq(tracker:pending(30), nil, "no flood"); assert(tracker:pending(61), "then again")
-- The acknowledgement drops held events and stops resending.
tracker:sync({items = {snapshot = body.snapshot, journal = {id = body.journal.id, event = 1}}}, 61)
eq(#json.decode(values.itemJournal).events, 1, "event 1 dropped")
body = tracker:pending(62); eq(#body.journal.events, 1, "event 2 still offered"); eq(body.journal.events[1][1], 2)
tracker:sync({items = {snapshot = body.snapshot, journal = {id = body.journal.id, event = 2}}}, 62)
eq(tracker:pending(63), nil, "all acknowledged")
-- An ack for another journal id drops nothing.
tracker:tick(63)
invs[94] = inv({slot(1205, "Adamant dagger"), slot(34828, "Gud raider shield")})
tracker:inventory(64); tracker:tick(65); eq(tracker:pending(65), nil, "reads wait for the delay")
tracker:tick(66); body = tracker:pending(66); assert(body, "a change is offered")
eq(#body.journal.events, 1); eq(body.journal.events[1][2], 34828, "only the newly worn item")
tracker:sync({items = {snapshot = body.snapshot, journal = {id = "ffffffffffffffff", event = 9}}}, 66)
eq(#json.decode(values.itemJournal).events, 1, "foreign ack ignored")
-- A picker restart forgets everything; the plugin offers the reading again.
tracker:sync({items = {snapshot = body.snapshot, journal = {id = body.journal.id, event = 3}}}, 67)
eq(tracker:pending(67), nil); tracker:sync({state = "locked"}, 68); assert(tracker:pending(68), "resent after restart")
-- A refusal waits half an hour.
tracker:refused(68); eq(tracker:pending(1000), nil); assert(tracker:pending(68 + 1801))

-- The journal survives a restart of the plugin and keeps counting.
invs[94] = inv({slot(34828, "Gud raider shield"), slot(34832, "Gud raider axe")})
local id = json.decode(values.itemJournal).id
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
-- A key saved on a new character starts a new journal for it.
values.keyOwner = "Bravo"; tracker:readNow(201)
saved = json.decode(values.itemJournal); eq(saved.owner, "Bravo"); assert(saved.id ~= id, "new journal id")
-- A journal that can't be read is never overwritten.
values.keyOwner = "Alpha"; who = "Alpha"; values.itemJournal = stored; broken.itemJournal = true
tracker = items.new(store); tracker:login(300)
broken.itemJournal = nil; eq(values.itemJournal, stored, "unreadable journal kept")
assert(tracker:describe():find("memory only"))
-- Malformed journals start again.
for _, text in ipairs({"not json", '{"id":"zz","owner":"Alpha","next":1,"events":[]}', '{"id":"0123456789abcdef","owner":"Alpha","next":2,"events":[5]}',
  '{"id":"0123456789abcdef","owner":"Alpha","next":2,"events":[[1,5,"A"],[1,6,"B"]]}'}) do
  values.itemJournal = text; tracker = items.new(store); tracker:login(400)
  local fresh = json.decode(values.itemJournal); eq(fresh.owner, "Alpha", text); assert(fresh.id ~= "0123456789abcdef", text)
end

-- The journal holds at most 32 events; more worn items wait for room.
values.itemJournal = nil
local many = {}; for i = 1, 40 do many[i] = slot(1000 + i, "Ring " .. i) end
invs[94] = inv(many); tracker = items.new(store); tracker:login(500)
body = tracker:pending(500); eq(#body.journal.events, 32, "bounded"); assert(tracker:describe():find("journal full"))
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
invs[93] = inv(bag); tracker:readNow(601); body = tracker:pending(601)
assert(body and #json.encode(body) <= items.MAX_BYTES and #body.journal.events < 32, "journal trimmed")
-- Two full containers at the widest values still fit without the journal.
local wide = {}; for i = 1, 64 do wide[i] = slot(999990 + i % 10, long, 2147483647) end
invs[93], invs[94] = inv(wide), inv(wide); tracker:readNow(602)
body = tracker:pending(602); assert(body and #json.encode(body) <= items.MAX_BYTES, "widest containers fit")
-- Names never carry a NUL into storage.
assert(not values.itemJournal:find("\0", 1, true))
print("items tests passed")
