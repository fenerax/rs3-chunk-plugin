-- Worn, backpack and coin pouch items, and tool belt tools, for the picker's item evidence
-- review. Only this character's own containers: slot, numeric item id, count and the game's
-- name. The picker matches ids only.
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
  RESEND = 60, REFUSED = 1800, MAX_BYTES = 14000, KEY = "itemJournal", BELT_ROWS = 128, BELT_MAX = 1000, BELT_RETRY = 600,
  BACKPACK = {"INV", "BACKPACK", "INVENTORY", 93}, WORN = {"WORN", "EQUIPMENT", "WORNITEMS", 94}, POUCH = {"MONEY_POUCH", 623}}
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
-- The tool belt has no container. Each tool is a varbit named TOOLBELT_<TOOL> (1 when it's on the
-- belt; hatchet, pickaxe and mattock hold a tier). Bookkeeping varbits are left out: random-event
-- copies, last-used and category state, purchase and switch flags, and the old tier vars.
local function beltName(name)
  if type(name) ~= "string" or name:sub(1, 9) ~= "TOOLBELT_" then return nil end
  local short = name:sub(10)
  if not short:match("^[A-Z0-9_]+$") or #short > 40 then return nil end
  for _, prefix in ipairs({"RAND_", "LAST_", "CURRENT_", "GOLD_ACC"}) do if short:sub(1, #prefix) == prefix then return nil end end
  for _, suffix in ipairs({"_OLD", "_BOUGHT", "_ENABLED"}) do if short:sub(-#suffix) == suffix then return nil end end
  return short
end
M.beltName = beltName
-- One pass over var.VarPlayer (about 62,000 entries): the keys of the tool varbits, or nil when
-- the list can't be read or holds none, so missing names never look like an empty belt.
function M.beltVars()
  local found = {}
  local ok = pcall(function()
    for key, variable in pairs(var.VarPlayer) do
      local name = beltName(get(variable, "configName"))
      local id = get(variable, "id")
      if name and ((type(id) == "number" and id < 0) or get(variable, "isVarBit") == true) then
        found[#found + 1] = {name = name, key = key, variable = variable}
      end
    end
  end)
  if not ok or #found == 0 then return nil end
  table.sort(found, function(a, b) return a.name < b.name end)
  return found
end
-- Rows are [name, value] for tools with a value from 1 to 1000, sorted by name; nil when any
-- value can't be read. Each read looks the var up again, in case the objects don't update.
function M.belt(vars)
  if not vars then return nil end
  local rows, seen = json.array(), {}
  local ok = pcall(function()
    for _, entry in ipairs(vars) do
      local variable = get(var.VarPlayer, entry.key) or entry.variable
      local value = variable.value
      assert(value == nil or type(value) == "number")
      value = value and math.tointeger(value)
      if value and value >= 1 and value <= M.BELT_MAX and not seen[entry.name] and #rows < M.BELT_ROWS then
        seen[entry.name] = true
        rows[#rows + 1] = json.array({entry.name, value})
      end
    end
  end)
  if ok then return rows end
end
local function hex16(text) return achievements.checksum(text) end
-- Coins in pouch rows, for diagnostics: stacks of 995, plus 54830 counting billions.
function M.coins(rows)
  local total = 0
  for _, row in ipairs(rows or {}) do
    if row[2] == 995 then total = total + row[3] elseif row[2] == 54830 then total = total + row[3] * 1e9 end
  end
  return string.format("%.0f", total)
end
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
    self.worn, self.backpack, self.pouch, self.toolbelt, self.snapshot, self.via = nil, nil, nil, nil, nil, {}
    self.beltVars, self.beltTriedAt, self.read = nil, nil, false
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
    local pouch, pouchVia = M.container(M.POUCH)
    -- The varbit list is found once per login; a failed search waits ten minutes to try again.
    if not self.beltVars and (not self.beltTriedAt or now - self.beltTriedAt >= M.BELT_RETRY) then
      self.beltTriedAt = now; self.beltVars = M.beltVars()
    end
    self.worn, self.backpack, self.pouch, self.toolbelt = worn, backpack, pouch, M.belt(self.beltVars)
    self.via = {worn = wornVia, backpack = backpackVia, pouch = pouchVia}
    if worn then self:note(worn) end
    self.read = true
    self.state = (worn or backpack) and "read" or "unavailable"
  end
  function self:login(now) self:reset(); self:readNow(now) end
  -- Inventory events fire for every container, so they only bring the next read forward.
  function self:inventory(now) if self.readAt then self.promptAt = self.promptAt or now + M.DELAY end end
  function self:tick(now)
    if (self.promptAt and now >= self.promptAt) or (self.readAt and now - self.readAt >= M.PERIOD) then self:readNow(now) end
  end
  -- The items field for the next report, or nil when the picker has this reading and journal.
  -- extras.pouch and extras.toolbelt add those fields, for a picker that accepts them. The
  -- snapshot names exactly the containers sent.
  function self:pending(now, extras)
    if not self.read or (self.refusedUntil and now < self.refusedUntil) then return nil end
    extras = extras or {}
    local function content(belt)
      local list = {self.worn or json.null, self.backpack or json.null}
      if extras.pouch then list[#list + 1] = self.pouch or json.null end
      if extras.toolbelt then list[#list + 1] = belt or json.null end
      return hex16(json.encode(list))
    end
    self.snapshot = content(self.toolbelt)
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
    if extras.pouch then items.pouch = self.pouch or json.null end
    if extras.toolbelt then items.toolbelt = self.toolbelt or json.null end
    -- Reports stop at 16 KB. The newest journal events wait for a later report, then the tool
    -- belt goes as unreadable; containers that alone are too big are held, with a diagnostic.
    while #events > 0 and #json.encode(items) > M.MAX_BYTES do events[#events] = nil end
    if #json.encode(items) > M.MAX_BYTES and extras.toolbelt and self.toolbelt then
      items.toolbelt = json.null; self.snapshot = content(nil); items.snapshot = self.snapshot
      key = self.snapshot .. ":" .. j.id .. ":" .. last
      if acked and acked.snapshot == self.snapshot and last <= ackedEvent then return nil end
      if key == self.sentKey and now - self.sentAt < M.RESEND then return nil end
    end
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
      .. "; pouch=" .. (self.pouch and (M.coins(self.pouch) .. " coins") or "unreadable")
      .. "; belt=" .. (self.toolbelt and #self.toolbelt or "unreadable")
      .. "; journal=" .. (j and (#j.events .. (j.owner and (self.saved == false and " (not saved)" or "") or " (memory only)")) or "-")
      .. (self.full and "; journal full" or "")
  end
  self:reset()
  return self
end
return M
