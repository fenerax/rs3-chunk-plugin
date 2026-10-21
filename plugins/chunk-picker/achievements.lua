-- Completed achievements, for the picker to match against tasks. Diaries are achievements too.
-- Only AchievementType.progress == -2 (COMPLETE) counts; positive values are partial progress.
-- The CHEEVO_RECENT_COMPLETE_1..4 vars hold just the last four completions, so a change there
-- only schedules a full re-read. Reads at login and every ten minutes catch anything missed.
local json = require("json")
local M = {COMPLETE = -2, PERIOD = 600, PROMPT_DELAY = 3, PART_BYTES = 12000, MAX_PARTS = 8}
local function get(object, key)
  local ok, value = pcall(function() return object[key] end)
  if ok then return value end
end
local function varKey(variable) return get(variable, "id") or get(variable, "configName") or variable end
-- Two small polynomial hashes over the id list: the same set always gets the same snapshot
-- name. Values stay below 2^37, so they are exact with 32-bit, 64-bit or float arithmetic.
local function checksum(text)
  local a, b = 5381, 7
  for i = 1, #text do
    local byte = text:byte(i)
    a = (a * 33 + byte) % 2147483647
    b = (b * 31 + byte) % 2147483629
  end
  return string.format("%08x%08x", math.floor(a), math.floor(b))
end
-- Rows are [id, name, category, subCategory], sorted by id; nil when the table can't be read.
function M.read()
  local source = get(config, "Achievement")
  if source == nil then return nil end
  local rows, seen = {}, {}
  local ok = pcall(function()
    for _, achievement in pairs(source) do
      if get(achievement, "progress") == M.COMPLETE then
        local id, name = get(achievement, "id"), get(achievement, "name")
        if type(id) == "number" and id % 1 == 0 and type(name) == "string" and not seen[id] then
          seen[id] = true
          local category, sub = get(achievement, "category"), get(achievement, "subCategory")
          rows[#rows + 1] = json.array({math.tointeger(id), name:gsub("[%c]", " "):sub(1, 120),
            type(category) == "number" and math.tointeger(category) or -1, type(sub) == "number" and math.tointeger(sub) or -1})
        end
      end
    end
  end)
  if not ok then return nil end
  table.sort(rows, function(a, b) return a[1] < b[1] end)
  return rows
end
-- Split rows into parts whose encoded lists stay under PART_BYTES each.
function M.split(rows)
  local parts, current, size = {}, json.array(), 2
  for _, row in ipairs(rows) do
    local bytes = #json.encode(row) + 1
    if #current > 0 and size + bytes > M.PART_BYTES then parts[#parts + 1] = current; current, size = json.array(), 2 end
    current[#current + 1] = row; size = size + bytes
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
  function self:resend() if self.parts then self.sent = 0 end end
  function self:readNow(now)
    self.readAt, self.promptAt = now, nil
    local rows = M.read()
    if not rows then self.state = "unavailable"; return end
    local ids = {}
    for i, row in ipairs(rows) do ids[i] = row[1] end
    local snapshot = checksum(table.concat(ids, ","))
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
  function self:var(event, now)
    local variable = get(event, "var")
    if self.recent and variable ~= nil and self.recent[varKey(variable)] then
      self.promptAt = self.promptAt or now + M.PROMPT_DELAY
    end
  end
  function self:tick(now)
    if (self.promptAt and now >= self.promptAt) or (self.readAt and now - self.readAt >= M.PERIOD) then self:readNow(now) end
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
  function self:refused(now) self.refusedUntil, self.sent, self.state = now + 1800, 0, "refused by picker" end
  function self:describe()
    local count = self.rows and #self.rows or 0
    return self.state .. "; complete=" .. count .. "; parts=" .. self.sent .. "/" .. (self.parts and #self.parts or 0)
      .. "; recent vars=" .. (self.recent and (next(self.recent) and "yes" or "no") or "-")
  end
  self:reset()
  return self
end
return M
