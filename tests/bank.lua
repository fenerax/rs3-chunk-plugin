-- Runner sets package.path to the plugin directory before loading this file.
local bank = require("bank")
local json = require("json")
local function eq(actual, expected, why)
  assert(actual == expected, (why or "") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local invs = {}
local function slot(id, count) return {obj = {id = id, name = "Item " .. id}, count = count or 1} end
local function inv(slots, total)
  return {slotCount = total or #slots, isValid = true, GetSlot = function(_, i) return slots[i] end}
end
config = {Inv = {}}
Inventory = {Find = function(which) return invs[which] end}

-- Not opened this login: the container is missing or empty, and nothing is offered.
local b = bank.new()
b:login(0); eq(b:pending(0), nil, "no bank before it is opened")
assert(b:describe(0):find("open it once"), b:describe(0))
invs[95] = inv({false, slot(-1, 0)}, 1920); b:readNow(1); eq(b:pending(1), nil, "an empty container is not a bank")

-- Rows are [id, count]; placeholders (no count), empty slots and bad ids are skipped, counts capped.
invs[95] = inv({slot(995, 82094), slot(1351, 0), false, slot(-1, 1), slot(54830, 3), slot(1359, 12345678901), slot(1000001, 1), {obj = 4151, count = 1}})
local rows = bank.read()
eq(#rows, 4, "rows"); eq(json.encode(rows[1]), "[995,82094]"); eq(rows[3][2], 2147483647, "capped"); eq(rows[4][1], 4151, "bare id")
invs[95] = inv({slot(1, 1), setmetatable({}, {__index = function() error("no access") end})}); eq(bank.read(), nil, "a throwing slot")
invs[95] = {slotCount = 2, isValid = false, GetSlot = function() end}; eq(bank.read(), nil, "invalid container")
config.Inv.BANK = "named"; invs.named = inv({slot(7, 2)}); eq(bank.read()[1][1], 7, "the named container first")
config.Inv.BANK = nil

-- One small set: one part with its age, then quiet once the status names it.
invs[95] = inv({slot(995, 500), slot(1359, 1)})
b = bank.new(); b:login(100)
local part = b:pending(100)
eq(part.part, 1); eq(part.parts, 1); eq(part.age, 0); eq(#part.snapshot, 16); eq(#part.rows, 2)
b:partSent(part, 100); eq(b:pending(130), nil, "waits for the status")
b:sync({bank = {snapshot = part.snapshot}}, 130); eq(b:pending(10000), nil, "acknowledged")
assert(b:describe(400):find("seen 5 min ago"), b:describe(400))
-- An unchanged bank seen again soon isn't sent again; seen ten minutes later it goes again with a fresh age.
b:inventory({inv = {id = 95}}, 200); b:tick(202); eq(b:pending(202), nil, "seen again soon")
b:inventory({inv = {configName = "BANK"}}, 800); b:tick(802)
part = b:pending(805); assert(part, "seen ten minutes later"); eq(part.age, 3, "age since it was seen")
b:partSent(part, 805); b:sync({bank = {snapshot = part.snapshot}}, 806); eq(b:pending(807), nil)
-- Other containers' events don't count as seeing the bank.
b:inventory({inv = {id = 93}}, 1500); b:tick(1502); eq(b:pending(1502), nil, "a backpack event is not the bank")
-- A change is a new set.
invs[95] = inv({slot(995, 400), slot(1359, 1)}); b:tick(1600)
part = b:pending(1600); assert(part and part.rows[1][2] == 400, "a change goes")
-- A picker restart: every part went but the status never names it, so it starts over after a minute.
b:partSent(part, 1600); b:sync({state = "locked"}, 1601)
eq(b:pending(1630), nil, "not at once"); assert(b:pending(1661), "after a minute")
-- A refusal waits half an hour; a reconnect forgets it.
b:refused(1700); eq(b:pending(3000), nil); assert(b:pending(3501), "then again")
b:refused(3600); b:resend(); assert(b:pending(3600), "a new connection tries again")

-- A full bank: parts of at most 700 rows and 12 KB, in order, acknowledged only when complete.
local big = {}
for i = 1, 1920 do big[i] = slot(990000 + i, 2000000000 + i) end
invs[95] = inv(big)
b = bank.new(); b:login(0)
local sent, total = {}, nil
for t = 1, 10 do
  part = b:pending(t)
  if not part then break end
  total = part.parts
  assert(#part.rows <= 700 and #json.encode(part.rows) <= 12000, "part size")
  local body = require("net").build(1, 1792411200, {id = 1, beta = true}, {x = 50, z = 50, floor = 0}, nil, nil, nil, nil, nil, part)
  assert(#body < 14000, "report body " .. #body)
  sent[#sent + 1] = part.part
  b:partSent(part, t)
  if part.part < part.parts then b:sync({bank = {snapshot = "0000000000000000"}}, t) end
end
eq(table.concat(sent, ","), "1,2,3,4", "parts in order")
local count = 0
for _, p in ipairs(b.parts) do count = count + #p end
eq(count, 1920, "every row once"); eq(total, 4)
b:sync({bank = {snapshot = b.snapshot}}, 11); eq(b:pending(12), nil, "complete")
-- A picker that forgets a set it held gets it again from part 1.
b:sync({state = "locked"}, 13); part = b:pending(13); assert(part and part.part == 1, "a forgotten set goes again")
-- Too many to send is held with a warning, and an older set is dropped.
local huge = {}
for i = 1, 5600 do huge[i] = slot(990000 + i % 9999, 2000000000) end
invs[95] = inv(huge); b:readNow(20); eq(b:pending(20), nil, "held")
assert(b:describe(20):find("too many"), b:describe(20))
print("bank tests passed")
