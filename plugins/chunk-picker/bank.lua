-- The bank, for the picker's item evidence and coin count. The client only fills the bank
-- container once the bank has been opened this login, and only updates it while it is open, so
-- deposit boxes and porters change the real bank unseen. Each set says how long ago the plugin
-- last saw the bank open or changed, and the picker shows that age.
-- Rows are [id, count] in slot order, sent in numbered parts, one part per report and nothing
-- else in it. The picker's status names the set once it holds every part.
local json = require("json")
local checksum = require("achievements").checksum
-- Times are in seconds. MAX_AGE (a week) caps the age sent; FRESHEN is how much newer a sighting
-- must be before a set the picker already holds goes again.
local M = {ID = 95, MAX_SLOTS = 5600, MAX_ID = 1000000, MAX_COUNT = 2147483647,
  PART_ROWS = 700, PART_BYTES = 12000, MAX_PARTS = 8, MAX_AGE = 604800,
  PERIOD = 60, DELAY = 2, RESTART = 60, FRESHEN = 600, REFUSED = 1800}
-- object[key], or nil when the client throws for it.
local function get(object, key)
  local ok, value = pcall(function() return object[key] end)
  if ok then return value end
end
-- The bank container, by config name when the client has one, else by the classic id.
local function find()
  local ok, inv = pcall(function()
    local named = get(config, "Inv") and get(config.Inv, "BANK")
    return Inventory.Find(named or M.ID)
  end)
  if ok and inv ~= nil and get(inv, "isValid") ~= false then return inv end
end
-- Rows, or nil when the bank can't be read or holds nothing yet (not opened this login). A
-- slot that throws makes the whole read unavailable, so a hiccup never looks like a smaller bank.
function M.read()
  local inv = find()
  if not inv then return nil end
  local rows = json.array()
  local ok = pcall(function()
    local total = math.tointeger(inv.slotCount)
    assert(total and total >= 0 and total <= M.MAX_SLOTS)
    for i = 1, total do
      local slot = inv:GetSlot(i)
      local obj, count = slot and slot.obj, slot and slot.count
      count = type(count) == "number" and count >= 1 and count == math.floor(count)
        and math.tointeger(math.min(count, M.MAX_COUNT))
      if obj ~= nil and count then
        local id = obj
        if type(obj) ~= "number" then id = obj.id end
        id = type(id) == "number" and math.tointeger(id)
        -- Empty slots carry id -1; placeholders have no count.
        if id and id >= 0 and id <= M.MAX_ID then rows[#rows + 1] = json.array({id, count}) end
      end
    end
  end)
  if ok and #rows > 0 then return rows end
end
-- At most PART_ROWS rows and PART_BYTES of encoded rows per part.
function M.split(rows)
  local parts, current, size = {}, json.array(), 2
  for _, row in ipairs(rows) do
    local bytes = #json.encode(row) + 1
    if #current > 0 and (#current >= M.PART_ROWS or size + bytes > M.PART_BYTES) then
      parts[#parts + 1] = current
      current, size = json.array(), 2
    end
    current[#current + 1] = row
    size = size + bytes
  end
  parts[#parts + 1] = current
  return parts
end
-- Whether an inventory event is about the bank. Events for it come while the bank is open.
local function isBank(event)
  local inv = get(event, "inv")
  if inv == nil then return false end
  local id, name = get(inv, "id"), get(inv, "configName")
  return id == M.ID or name == "BANK"
end
function M.new()
  local self = {}
  -- seenAt is when the bank was last seen open or changed; sentSeenAt is the seenAt the picker
  -- has, from the first part of the set it holds.
  function self:reset()
    self.rows, self.snapshot, self.parts, self.sent, self.acked = nil, nil, nil, 0, false
    self.seenAt, self.sentSeenAt, self.lastPartAt = nil, nil, nil
    self.readAt, self.promptAt, self.refusedUntil, self.warning = nil, nil, nil, nil
    self.state = "not opened yet"
  end
  -- A new connection starts the set again and forgets an earlier refusal.
  function self:resend()
    self.refusedUntil = nil
    if self.parts and not self.acked then self.sent = 0 end
  end
  function self:readNow(now, seen)
    self.readAt, self.promptAt = now, nil
    local rows = M.read()
    if not rows then return end
    local encoded = {}
    for i, row in ipairs(rows) do encoded[i] = json.encode(row) end
    local snapshot = checksum(table.concat(encoded, ","))
    if seen or snapshot ~= self.snapshot or not self.seenAt then self.seenAt = now end
    if snapshot == self.snapshot and (self.parts or self.warning) then return end
    local parts = M.split(rows)
    self.rows, self.snapshot, self.sent, self.acked = rows, snapshot, 0, false
    if #parts > M.MAX_PARTS then
      -- Drop any older set, so a reconnect can't resend it as if it were current.
      self.parts, self.warning, self.state = nil, #rows .. " bank items is too many to send; held", "held"
      return
    end
    self.parts, self.warning, self.state = parts, nil, "read"
  end
  function self:login(now)
    self:reset()
    self:readNow(now)
  end
  -- Bank events mean it is open now: read it soon and count it as seen.
  -- Other containers' events (a busy backpack while skilling) wait for the minute read; an
  -- event that doesn't say which container it is still brings the read forward.
  function self:inventory(event, now)
    local bankEvent = isBank(event)
    if bankEvent then self.seenNext = true end
    if bankEvent or get(event, "inv") == nil then self.promptAt = self.promptAt or now + M.DELAY end
  end
  function self:tick(now)
    if (self.promptAt and now >= self.promptAt) or (self.readAt and now - self.readAt >= M.PERIOD)
      or not self.readAt then
      local seen = self.seenNext
      self.seenNext = nil
      self:readNow(now, seen)
    end
  end
  -- The next part to send, or nil. A set the picker holds goes again only when the bank was seen
  -- again ten minutes after the time the picker has, so its age stays honest.
  function self:pending(now)
    if not self.parts or (self.refusedUntil and now < self.refusedUntil) then return nil end
    if self.acked then
      if not (self.sentSeenAt and self.seenAt - self.sentSeenAt >= M.FRESHEN) then return nil end
      self.acked, self.sent = false, 0
    end
    if self.sent >= #self.parts then
      -- Every part went but the status doesn't name the set: a picker restart.
      -- Start over, at most once a minute.
      if self.lastPartAt and now - self.lastPartAt < M.RESTART then return nil end
      self.sent = 0
    end
    local index = self.sent + 1
    local age = math.max(0, math.min(M.MAX_AGE, math.floor(now - self.seenAt)))
    return {snapshot = self.snapshot, part = index, parts = #self.parts, age = age,
      rows = self.parts[index]}
  end
  -- A part the picker answered 200 to.
  function self:partSent(part, now)
    if part.snapshot ~= self.snapshot then return end
    self.sent = math.max(self.sent, part.part)
    self.lastPartAt = now
    if part.part == 1 then self.sentSeenAt = self.seenAt end
    self.state = self.sent >= part.parts and "sent, waiting for the picker" or "sending"
  end
  function self:sync(status, now)
    if not self.parts or type(status) ~= "table" then return end
    local held = status.bank
    local acked = type(held) == "table" and held.snapshot == self.snapshot
    -- Only a set fully sent counts as acknowledged; the status may name an older copy of it.
    if acked and self.sent >= #self.parts then
      self.acked = true
      self.state = "sent"
    elseif acked and not self.sentSeenAt then
      self.acked = true
      self.sentSeenAt = self.seenAt
      self.state = "sent"
    elseif not acked and self.acked then
      -- The picker forgot a set it held (a restart): offer it again.
      self.acked, self.sent, self.lastPartAt, self.state = false, #self.parts, nil, "read"
    end
  end
  function self:refused(now)
    self.refusedUntil, self.sent, self.state = now + M.REFUSED, 0, "refused by picker"
  end
  function self:describe(now)
    if not self.rows then return "open it once this login to share it" end
    local minutes = math.floor((now - self.seenAt) / 60)
    return #self.rows .. " items in " .. (self.parts and #self.parts or 0) .. " parts, seen "
      .. (minutes < 1 and "just now" or (minutes .. " min ago")) .. "; " .. (self.warning or self.state)
  end
  self:reset()
  return self
end
return M
