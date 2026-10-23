-- Worn and backpack items, for the picker's item evidence review. Only this character's own
-- containers: slot, numeric item id, count and the game's name. The picker matches ids only.
-- The container names are undocumented, so each read tries likely config.Inv names, then the
-- classic ids (93 backpack, 94 worn). A container that can't be read is sent as null, never as
-- empty, so a hiccup never looks like having nothing.
-- Worn items also go into a small journal kept in PersistentDB for the key's character, so
-- something worn while the picker wasn't listening still reaches it. Events leave the journal
-- once the picker's status acknowledges them.
local json = require("json")
local achievements = require("achievements")
local identity = require("identity")
local M = {MAX_SLOTS = 64, MAX_ID = 1000000, MAX_COUNT = 2147483647, JOURNAL = 32, PERIOD = 60, DELAY = 2,
  RESEND = 60, REFUSED = 1800, MAX_BYTES = 14000, KEY = "itemJournal",
  BACKPACK = {"INV", "BACKPACK", "INVENTORY", 93}, WORN = {"WORN", "EQUIPMENT", "WORNITEMS", 94}}
local function get(object, key)
  local ok, value = pcall(function() return object[key] end)
  if ok then return value end
end
local function find(names)
  for _, name in ipairs(names) do
    local ok, inv = pcall(function()
      local which = name
      if type(name) == "string" then which = config.Inv[name] end
      if which == nil then return nil end
      return Inventory.Find(which)
    end)
    if ok and inv ~= nil and get(inv, "isValid") ~= false then return inv, name end
  end
end
-- Rows are [slot from 0, id, count, name], or nil when the container can't be read. A field
-- that throws, or an item past slot 64, makes the whole container unavailable.
function M.container(names)
  local inv, via = find(names)
  if not inv then return nil end
  local rows = json.array()
  local ok = pcall(function()
    local total = math.tointeger(inv.slotCount)
    assert(total and total >= 0)
    for i = 1, total do
      local slot = inv:GetSlot(i)
      local obj, count = slot and slot.obj, slot and slot.count
      -- Capped first: stacks can pass 2^31, and 32-bit test Lua has no wider integers.
      count = type(count) == "number" and count >= 1 and count == math.floor(count) and math.tointeger(math.min(count, M.MAX_COUNT))
      if obj ~= nil and count then
        local id, name = obj, nil
        if type(obj) ~= "number" then id, name = obj.id, obj.name end
        id = type(id) == "number" and math.tointeger(id)
        -- Empty slots carry id -1 in the game cache.
        if id and id >= 0 and id <= M.MAX_ID then
          assert(i <= M.MAX_SLOTS)
          name = type(name) == "string" and achievements.clean(name, 80) or ("Item " .. id)
          rows[#rows + 1] = json.array({i - 1, id, count, name})
        end
      end
    end
  end)
  if ok then return rows, via end
end
local function hex16(text) return achievements.checksum(text) end
-- The journal belongs to the character the key was saved on, and only that character adds to it.
local function owner(store)
  local name = identity.current()
  local ok, keyOwner = store:read("keyOwner", "String")
  if name and ok and keyOwner == name then return name end
end
local function parse(text, name)
  local value = json.decode(text)
  if type(value) ~= "table" or value.owner ~= name or type(value.id) ~= "string"
    or not value.id:match("^%x+$") or #value.id ~= 16 or type(value.events) ~= "table" then return nil end
  local nextEvent = math.tointeger(value.next)
  if not nextEvent or nextEvent < 1 then return nil end
  local events, last = {}, 0
  for _, event in ipairs(value.events) do
    local n, id = math.tointeger(event[1]), math.tointeger(event[2])
    local label = type(event[3]) == "string" and achievements.clean(event[3], 80)
    if not n or n <= last or n >= nextEvent or not id or id < 0 or id > M.MAX_ID or not label then return nil end
    events[#events + 1] = {n, id, label}; last = n
  end
  if #events > M.JOURNAL then return nil end
  return {id = value.id:lower(), owner = name, next = nextEvent, events = events}
end
local function decode(text, name)
  local ok, journal = pcall(parse, text, name)
  if ok then return journal end
end
function M.new(store)
  local self = {}
  function self:reset()
    self.worn, self.backpack, self.snapshot, self.via = nil, nil, nil, {}
    self.lastWorn, self.journal, self.saved = nil, nil, nil
    self.readAt, self.promptAt, self.refusedUntil, self.acked = nil, nil, nil, nil
    self.sentKey, self.sentAt, self.full = nil, nil, false
    self.state = "waiting for login"
  end
  -- A new connection forgets the picker's acknowledgement and any refusal; both belonged to it.
  function self:resend() self.acked, self.refusedUntil, self.sentKey = nil, nil, nil end
  function self:save()
    local j = self.journal
    if not j or not j.owner then return end
    local events = json.array()
    for i, event in ipairs(j.events) do events[i] = json.array({event[1], event[2], event[3]}) end
    self.saved = store:set(M.KEY, "String", json.encode({id = j.id, owner = j.owner, next = j.next, events = events}))
  end
  -- Loads this character's journal, or starts a new one with a fresh id. A journal that can't
  -- be read stays in memory only, so it never overwrites one that might still be there.
  function self:open(now)
    local name = owner(store)
    if self.journal and self.journal.owner == name then return end
    local fresh = {id = hex16(tostring(now) .. "|" .. tostring(math.random and math.random() or 0) .. "|" .. tostring(self.journal and self.journal.id)),
      owner = name, next = 1, events = {}}
    if not name then self.journal = fresh; self.journal.owner = nil; return end
    local readable, text = store:read(M.KEY, "String")
    if not readable then self.journal = fresh; self.journal.owner = nil; self.saved = false; return end
    local loaded = type(text) == "string" and decode(text, name)
    if loaded then self.journal = loaded; return end
    self.journal = fresh; self:save()
  end
  function self:note(rows)
    local j, worn, changed = self.journal, {}, false
    -- Slot order, so the same outfit always gets the same event numbers.
    for _, row in ipairs(rows) do
      local id, name = row[2], row[4]
      if not worn[id] and not (self.lastWorn and self.lastWorn[id]) then
        local listed = false
        for _, event in ipairs(j.events) do if event[2] == id then listed = true end end
        if not listed then
          if #j.events >= M.JOURNAL then self.full = true
          else j.events[#j.events + 1] = {j.next, id, name}; j.next = j.next + 1; changed = true end
        end
      end
      worn[id] = true
    end
    self.lastWorn = worn
    if changed then self:save() end
  end
  function self:readNow(now)
    self.readAt, self.promptAt = now, nil
    self:open(now)
    local worn, wornVia = M.container(M.WORN)
    local backpack, backpackVia = M.container(M.BACKPACK)
    self.worn, self.backpack, self.via = worn, backpack, {worn = wornVia, backpack = backpackVia}
    if worn then self:note(worn) end
    self.snapshot = hex16(json.encode({worn or json.null, backpack or json.null}))
    self.state = (worn or backpack) and "read" or "unavailable"
  end
  function self:login(now) self:reset(); self:readNow(now) end
  -- Inventory events fire for every container, so they only bring the next read forward.
  function self:inventory(now) if self.readAt then self.promptAt = self.promptAt or now + M.DELAY end end
  function self:tick(now)
    if (self.promptAt and now >= self.promptAt) or (self.readAt and now - self.readAt >= M.PERIOD) then self:readNow(now) end
  end
  -- The items field for the next report, or nil when the picker has this reading and journal.
  function self:pending(now)
    if not self.snapshot or (self.refusedUntil and now < self.refusedUntil) then return nil end
    local j, acked = self.journal, self.acked
    local last = j.events[#j.events] and j.events[#j.events][1] or 0
    local ackedEvent = acked and type(acked.journal) == "table" and acked.journal.id == j.id and math.tointeger(acked.journal.event) or 0
    if acked and acked.snapshot == self.snapshot and last <= ackedEvent then return nil end
    -- The same content again waits a minute, so a picker that keeps not acknowledging isn't flooded.
    local key = self.snapshot .. ":" .. j.id .. ":" .. last
    if key == self.sentKey and now - self.sentAt < M.RESEND then return nil end
    local events = json.array()
    for _, event in ipairs(j.events) do if event[1] > ackedEvent then events[#events + 1] = json.array({event[1], event[2], event[3]}) end end
    local items = {snapshot = self.snapshot, worn = self.worn or json.null, backpack = self.backpack or json.null,
      journal = {id = j.id, events = events}}
    -- Reports stop at 16 KB. The newest journal events wait for a later report; containers that
    -- alone are too big are held, with a diagnostic.
    while #events > 0 and #json.encode(items) > M.MAX_BYTES do events[#events] = nil end
    if #json.encode(items) > M.MAX_BYTES then self.state = "too large to send; held"; return nil end
    return items, key
  end
  function self:sent(key, now) self.sentKey, self.sentAt = key, now end
  -- The picker's status names the last reading and journal event it holds; events it holds leave
  -- the journal.
  function self:sync(status, now)
    if type(status) ~= "table" then return end
    local held = status.items
    if type(held) ~= "table" then self.acked = nil; return end
    self.acked = held
    if held.snapshot == self.snapshot then self.state = "sent" end
    local j = self.journal
    local ack = type(held.journal) == "table" and held.journal
    local event = ack and ack.id == (j and j.id) and math.tointeger(ack.event)
    if not event then return end
    local kept = {}
    for _, row in ipairs(j.events) do if row[1] > event then kept[#kept + 1] = row end end
    if #kept ~= #j.events then j.events = kept; self.full = false; self:save() end
  end
  function self:refused(now) self.refusedUntil, self.sentKey, self.state = now + M.REFUSED, nil, "refused by picker" end
  function self:describe()
    local function count(rows, via) return rows and (#rows .. " via " .. tostring(via)) or "unreadable" end
    local j = self.journal
    return self.state .. "; worn=" .. count(self.worn, self.via.worn) .. "; backpack=" .. count(self.backpack, self.via.backpack)
      .. "; journal=" .. (j and (#j.events .. (j.owner and (self.saved == false and " (not saved)" or "") or " (memory only)")) or "-")
      .. (self.full and "; journal full" or "")
  end
  self:reset()
  return self
end
return M
