-- Completed achievements, for the picker to match against tasks. Diaries are achievements too.
-- Only AchievementType.progress == -2 (COMPLETE) counts; positive values are partial progress.
-- The CHEEVO_RECENT_COMPLETE_1..4 vars hold just the last four completions, so a change there
-- only schedules a full re-read. Reads at login and every ten minutes catch anything missed.
local json = require("json")
local M = {COMPLETE = -2, PERIOD = 600, PROMPT_DELAY = 3, PART_BYTES = 12000, MAX_PARTS = 8}
-- The picker reads numbers as JavaScript does, so ids and categories stay safe integers.
local MAX_SAFE = 9007199254740991
-- object[key], or nil when the client throws for it.
local function get(object, key)
  local ok, value = pcall(function() return object[key] end)
  if ok then return value end
end
-- What identifies a var across lookups: its id, else its name, else the object itself.
local function varKey(variable) return get(variable, "id") or get(variable, "configName") or variable end
-- Two small polynomial hashes over the id list: the same set always gets the same snapshot
-- name. The products are floats (exact below 2^53), so 32-bit test integers and the game's
-- 64-bit Lua give the same answer; integer products would overflow in 32 bits.
local function checksum(text)
  local first, second = 5381.0, 7.0
  for i = 1, #text do
    local byte = text:byte(i)
    first = (first * 33.0 + byte) % 2147483647
    second = (second * 31.0 + byte) % 2147483629
  end
  return string.format("%08x%08x", math.tointeger(first), math.tointeger(second))
end
M.checksum = checksum
-- Names the picker accepts: 1-120 bytes (or `limit`), no C0 or C1 controls, cut on a UTF-8 boundary.
local function clean(name, limit)
  limit = limit or 120
  name = name:gsub("%c", " "):gsub("\xC2[\x80-\x9F]", " "):match("^%s*(.-)%s*$")
  if #name > limit then
    -- Step back over continuation bytes (0x80-0xBF) so a character is never cut in half.
    local cut = limit
    while cut > 0 and (name:byte(cut + 1) or 0) >= 0x80 and name:byte(cut + 1) < 0xC0 do
      cut = cut - 1
    end
    name = name:sub(1, cut):match("^(.-)%s*$")
  end
  if name ~= "" then return name end
end
M.clean = clean
-- A category id, or -1 when there is none or it isn't a safe integer.
local function category(value)
  local n = type(value) == "number" and math.tointeger(value)
  return n and n >= -1 and n <= MAX_SAFE and n or -1
end
-- Rows are [id, name, category, subCategory], sorted by id; nil when the table can't be read.
-- A field that throws makes the whole read unavailable, so a hiccup never looks like a
-- smaller set. Rows the picker would refuse (bad id or name) are skipped.
function M.read()
  local source = get(config, "Achievement")
  if source == nil then return nil end
  local rows, seen = {}, {}
  local ok = pcall(function()
    for _, achievement in pairs(source) do
      if achievement.progress == M.COMPLETE then
        local id, name = achievement.id, achievement.name
        id = type(id) == "number" and math.tointeger(id)
        name = type(name) == "string" and clean(name)
        if id and id >= 0 and id <= MAX_SAFE and name and not seen[id] then
          seen[id] = true
          rows[#rows + 1] = json.array({id, name, category(get(achievement, "category")),
            category(get(achievement, "subCategory"))})
        end
      end
    end
  end)
  if not ok then return nil end
  table.sort(rows, function(a, b) return a[1] < b[1] end)
  return rows
end
-- Split rows into parts whose encoded lists stay under PART_BYTES each.
-- `size` starts at 2 for the list's brackets; each row adds its length plus a comma.
function M.split(rows)
  local parts, current, size = {}, json.array(), 2
  for _, row in ipairs(rows) do
    local bytes = #json.encode(row) + 1
    if #current > 0 and size + bytes > M.PART_BYTES then
      parts[#parts + 1] = current
      current, size = json.array(), 2
    end
    current[#current + 1] = row
    size = size + bytes
  end
  parts[#parts + 1] = current
  return parts
end
function M.new()
  local self = {}
  function self:reset()
    self.rows, self.snapshot, self.parts, self.sent = nil, nil, nil, 0
    self.readAt, self.promptAt, self.refusedUntil, self.recent = nil, nil, nil, nil
    self.state, self.warning = "waiting for login", nil
  end
  -- A new connection (server, key, permission or login) starts the set again and forgets
  -- an earlier refusal, which belonged to the previous picker or key.
  function self:resend()
    self.refusedUntil = nil
    if self.parts then
      self.sent = 0
      self.state = "read"
    end
  end
  function self:readNow(now)
    self.readAt, self.promptAt = now, nil
    local rows = M.read()
    if not rows then
      self.state = "unavailable"
      return
    end
    -- The name covers everything sent, so a corrected name or category is a new set too.
    local encoded = {}
    for i, row in ipairs(rows) do encoded[i] = json.encode(row) end
    local snapshot = checksum(table.concat(encoded, "\n"))
    if snapshot == self.snapshot then return end
    local parts = M.split(rows)
    if #parts > M.MAX_PARTS then
      -- Drop any older set too, so a reconnect can't resend it as if it were current.
      self.rows, self.snapshot, self.parts, self.sent = rows, snapshot, nil, 0
      self.state, self.warning = "held", #rows .. " achievements is too many to send; held locally"
      return
    end
    self.rows, self.snapshot, self.parts, self.sent, self.warning = rows, snapshot, parts, 0, nil
    self.state = "read"
  end
  function self:login(now)
    -- The recent-completion vars, if this client exposes them by name.
    self.recent = {}
    for i = 1, 4 do
      local variable = get(get(var, "VarPlayer"), "CHEEVO_RECENT_COMPLETE_" .. i)
      if variable ~= nil then self.recent[varKey(variable)] = true end
    end
    self:readNow(now)
  end
  -- A recent-completion var changed: re-read shortly, once the client has updated the table.
  function self:var(event, now)
    local variable = get(event, "var")
    if self.recent and variable ~= nil and self.recent[varKey(variable)] then
      self.promptAt = self.promptAt or now + M.PROMPT_DELAY
    end
  end
  function self:tick(now)
    if (self.promptAt and now >= self.promptAt) or (self.readAt and now - self.readAt >= M.PERIOD) then
      self:readNow(now)
    end
  end
  -- The next part to send, or nil when the picker has the whole current set.
  function self:pending(now)
    if not self.parts or self.sent >= #self.parts then return nil end
    if self.refusedUntil and now < self.refusedUntil then return nil end
    local index = self.sent + 1
    return {snapshot = self.snapshot, part = index, parts = #self.parts, complete = self.parts[index]}
  end
  -- The picker's status says which set it is assembling and how many parts it holds. It is
  -- the source of truth, so a picker restart means sending again, at most once a minute.
  function self:sync(status, now)
    if not self.parts or type(status) ~= "table" then return end
    local held, received = status.achievements, 0
    if type(held) == "table" and held.snapshot == self.snapshot and held.parts == #self.parts
      and type(held.received) == "number" and math.tointeger(held.received) then
      received = math.max(0, math.min(math.tointeger(held.received), #self.parts))
    end
    if received < self.sent then
      if self.restartAt and now < self.restartAt then return end
      self.restartAt = now + 60
    end
    self.sent = received
    self.state = received == #self.parts and "sent" or "sending"
  end
  -- A picker that advertised the field but refused it gets left alone for half an hour.
  function self:refused(now)
    self.refusedUntil, self.sent, self.state = now + 1800, 0, "refused by picker"
  end
  function self:describe()
    local count = self.rows and #self.rows or 0
    return self.state .. "; complete=" .. count
      .. "; parts=" .. self.sent .. "/" .. (self.parts and #self.parts or 0)
      .. "; recent vars=" .. (self.recent and (next(self.recent) and "yes" or "no") or "-")
  end
  self:reset()
  return self
end
return M
