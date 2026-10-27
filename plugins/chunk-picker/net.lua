-- HTTP to the picker: builds report bodies, sends them, and tracks connection state and retries.
-- All wire-format policy lives here. Aligned to the picker's docs/plugin-api.md (move/plugsync, 2026-10-21).
local json = require("json")
local taskList = require("tasks").list
local M = {
  REPORT = "/api/plugin/v1/report",
  STATUS = "/api/plugin/v1/status",
  TASKS = "/api/plugin/v1/tasks",
  MAX_BODY = 16384,
}
local months = {Jan = 1, Feb = 2, Mar = 3, Apr = 4, May = 5, Jun = 6,
  Jul = 7, Aug = 8, Sep = 9, Oct = 10, Nov = 11, Dec = 12}

-- Gregorian conversions also work when the client omits os/date/utf8.
-- Both use the usual civil-calendar arithmetic: years start on 1 March so the leap day falls at
-- the end, and 400-year eras of 146097 days. 719468 is the day count from 0000-03-01 to 1970-01-01.
local function days(y, m, d)
  y = y - (m <= 2 and 1 or 0)
  local era = math.floor(y / 400)
  local yearOfEra = y - era * 400
  local marchMonth = m + (m > 2 and -3 or 9)
  return era * 146097 + yearOfEra * 365 + math.floor(yearOfEra / 4) - math.floor(yearOfEra / 100)
    + math.floor((153 * marchMonth + 2) / 5) + d - 1 - 719468
end

-- Unix seconds -> "YYYY-MM-DDTHH:MM:SSZ".
function M.iso(epoch)
  local day = math.floor(epoch / 86400)
  local seconds = math.floor(epoch - day * 86400)
  local z = day + 719468
  local era = math.floor(z / 146097)
  local dayOfEra = z - era * 146097
  local yearOfEra = math.floor((dayOfEra - math.floor(dayOfEra / 1460) + math.floor(dayOfEra / 36524)
    - math.floor(dayOfEra / 146096)) / 365)
  local y = yearOfEra + era * 400
  local dayOfYear = dayOfEra - (365 * yearOfEra + math.floor(yearOfEra / 4) - math.floor(yearOfEra / 100))
  local marchMonth = math.floor((5 * dayOfYear + 2) / 153)
  local d = dayOfYear - math.floor((153 * marchMonth + 2) / 5) + 1
  local m = marchMonth + (marchMonth < 10 and 3 or -9)
  y = y + (m <= 2 and 1 or 0)
  return string.format("%04d-%02d-%02dT%02d:%02d:%02dZ", y, m, d,
    math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60)
end

-- An HTTP Date header ("Tue, 21 Oct 2026 18:00:00 GMT") -> Unix seconds, or nil.
-- Without os.time this is the plugin's only clock.
function M.dateEpoch(header)
  if type(header) ~= "string" then return nil end
  local d, m, y, h, mi, s = header:match("(%d%d?) (%a%a%a) (%d%d%d%d) (%d%d):(%d%d):(%d%d) GMT")
  if not d or not months[m] then return nil end
  return days(tonumber(y), months[m], tonumber(d)) * 86400
    + tonumber(h) * 3600 + tonumber(mi) * 60 + tonumber(s)
end

-- A response header, case-insensitively. The client may give headers as a table or as raw text.
local function header(request, name)
  local headers = request.header
  if type(headers) == "table" then
    for key, value in pairs(headers) do
      if tostring(key):lower() == name:lower() then return tostring(value) end
    end
  end
  if type(headers) == "string" then
    for line in headers:gmatch("[^\r\n]+") do
      local key, value = line:match("^([^:]+):%s*(.*)$")
      if key and key:lower() == name:lower() then return value end
    end
  end
  -- An explicit nil: tonumber() with no argument at all throws.
  return nil
end

-- Builds one report body. Returns the JSON text, the payload table, and a warning when quests
-- had to be held back.
function M.build(seq, epoch, world, position, skills, quests, diagnostics, achievements, items, bank)
  local payload = {v = 1, seq = seq, sentAt = M.iso(epoch),
    position = {x = position.x, z = position.z, floor = position.floor}}
  if world then payload.world = world end
  payload.skills = skills
  payload.quests = quests
  payload.achievements = achievements
  payload.items = items
  payload.bank = bank
  -- Picker contract: at most 80 single lines of up to 160 characters.
  if diagnostics and #diagnostics > 0 then
    local lines = {}
    for i = 1, math.min(80, #diagnostics) do
      lines[i] = (tostring(diagnostics[i]):gsub("[%c]", " "):sub(1, 160))
    end
    payload.diagnostics = lines
  end
  local warning
  -- Diagnostics are the first thing dropped when a report is too large.
  if payload.diagnostics and #json.encode(payload) > M.MAX_BODY then payload.diagnostics = nil end
  if quests and (#quests.finished > 500 or #quests.started > 500) then
    payload.quests = nil
    warning = "Quest snapshot exceeds 500 names; held locally"
  end
  local body = json.encode(payload)
  -- Quest objects replace prior lists; splitting them would silently lose progress.
  -- Send the complete snapshot or hold it with a visible diagnostic.
  -- Skills are dropped first to make room; they go again with the next report.
  if #body > M.MAX_BODY and payload.quests then
    payload.skills = nil
    body = json.encode(payload)
    if #body > M.MAX_BODY then
      payload.quests = nil
      payload.skills = skills
      warning = "Quest snapshot exceeds 16 KB; held locally"
    end
    body = json.encode(payload)
  end
  assert(#body <= M.MAX_BODY, "Report exceeds 16 KB")
  return body, payload, warning
end

local STATES = {unlocked = true, locked = true, available = true, unknown = true}
-- Status `nearby` rows become a map-square-id -> state map. Bad rows are dropped, never fatal:
-- the top-level state alone still drives the panel.
function M.nearby(rows)
  if type(rows) ~= "table" then return nil end
  local out, count = {}, 0
  for i = 1, math.min(#rows, 81) do
    local row = rows[i]
    local id = type(row) == "table" and type(row.chunkId) == "string" and #row.chunkId <= 5
      and row.chunkId:match("^%d+$") and math.tointeger(tonumber(row.chunkId))
    if id and id // 256 <= 199 and id % 256 <= 199 and STATES[row.state] then
      -- Shared access: a chunk only your partner unlocked is open to you but drawn in its own colour.
      out[id] = row.state == "unlocked" and row.by == "partner" and "partner" or row.state
      count = count + 1
    end
  end
  return count > 0 and out or nil
end

-- options: sequence (last saved report number), now() (the current plugin clock) and
-- saveSequence(n) (persists the report number).
function M.new(options)
  local self = {history = {}, busy = false, failures = 0, nextAt = 0, blocked = false,
    localhostConnected = false, message = "Not connected", sequence = options.sequence or 0,
    clockEpoch = nil, generation = 0}
  -- Wall-clock seconds: os.time when the client has it, else the picker's Date header plus
  -- the time elapsed since it arrived. nil until one of those is known.
  function self:epoch(now)
    if os and type(os.time) == "function" then
      local ok, value = pcall(os.time)
      if ok and type(value) == "number" then return value end
    end
    return self.clockEpoch and (self.clockEpoch + now - self.clockAt) or nil
  end
  -- Bumping the generation makes any callback from the cancelled request a no-op.
  function self:cancel()
    self.generation = self.generation + 1
    local request = self.request
    self.request = nil
    self.busy = false
    if request then pcall(function() request:Cancel() end) end
  end
  function self:reset()
    self:cancel()
    self.blocked = false
    self.nextAt = 0
    self.failures = 0
    self.status = nil
    self.lastSync = nil
    self.message = "Not connected"
    self.heldQuestJSON = nil
    self.payloadWarning = nil
    self.tasks = nil
    self.tasksNextAt = 0
    self.tasksMessage = nil
    self.tasksNoPaging = nil
  end
  -- A quest snapshot that was too large to send stays held until it changes.
  function self:filterQuests(quests)
    if quests and self.heldQuestJSON == json.encode(quests) then return nil end
    return quests
  end
  function self:ready(now) return not self.busy and not self.blocked and now >= self.nextAt end
  -- Optional report fields the picker has said it understands; it refuses unknown ones.
  function self:accepts(name)
    local list = self.status and self.status.accepts
    if type(list) ~= "table" then return false end
    for _, value in ipairs(list) do
      if value == name then return true end
    end
    return false
  end
  -- One request at a time. Status and report replies update the connection state and back off
  -- on failure; task-list replies keep their own retry clock. `done(ok, status, code)` runs after.
  function self:requestHTTP(now, handle, key, method, body, done, path)
    if not self:ready(now) then return false end
    self.busy = true
    self.startedAt = now
    local generation = self.generation
    local function complete(response)
      if generation ~= self.generation or not self.busy then return end
      self.busy = false
      self.request = nil
      local current = options.now and options.now() or now
      local code = tonumber(response.responseCode) or 0
      local info = tostring(response.errorInfo or "")
      -- Never log response bodies, URLs, headers, or credentials. Redact key even if echoed by transport.
      if key ~= "" then info = info:gsub(key:gsub("([^%w])", "%%%1"), "[redacted]") end
      info = info:gsub("gpk_[%w_-]+", "[redacted]"):gsub("https?://[^%s]+", "[URL]")
        :gsub("[%c]", " "):sub(1, 160)
      table.insert(self.history, 1, {code = code, timedOut = response.timedOut == true,
        failed = response.failed == true, errorInfo = info})
      if #self.history > 5 then table.remove(self.history) end
      if code > 0 then self.localhostConnected = true end
      local date = M.dateEpoch(header(response, "Date"))
      if date then
        self.clockEpoch = date
        self.clockAt = current
      end
      local ok, status = pcall(json.decode, response.data or "")
      if path and path:sub(1, #M.TASKS) == M.TASKS then
        -- Task lists have their own retry clock and never change the connection state: an older
        -- picker without this route answers 401, which must not block reports.
        local list = ok and code >= 200 and code < 300 and not response.failed and not response.timedOut
          and taskList(status) or nil
        -- A picker that can't page (or a client that mangles the query) falls back to the first rows.
        local askedFrom = path ~= M.TASKS
        if list and self.tasksNoPaging then list.allFrom = nil end
        if list then
          self.tasks = list
          self.tasksAt = current
          self.tasksMessage = nil
        elseif askedFrom and code ~= 429 then
          self.tasksNoPaging = true
          self.tasksNextAt = current
        elseif code == 401 or code == 404 then
          self.tasksMessage = "this picker has no in-game task list"
          self.tasksNextAt = current + 300
        elseif code == 429 then
          self.tasksMessage = "picker asked to slow down"
          self.tasksNextAt = current + (tonumber(header(response, "Retry-After")) or 60)
        else
          self.tasksMessage = "task list unavailable, retrying"
          self.tasksNextAt = current + 30
        end
        self.nextAt = math.max(self.nextAt, current + 1)
        if done then done(list ~= nil, list, code) end
        return
      end
      local success = code >= 200 and code < 300 and not response.failed and not response.timedOut and ok
        and type(status) == "table" and STATES[status.state] == true
      if success then
        status.nearby = M.nearby(status.nearby)
        self.failures = 0
        self.nextAt = current + 1
        self.status = status
        self.lastSync = current
        self.message = "Connected"
      elseif code == 401 then
        -- A refused key stays blocked until reset() (a new key, server or login).
        self.blocked = true
        self.status = nil
        self.message = "Key not accepted"
      else
        -- Exponential backoff: 2, 4, 8 ... seconds, capped at five minutes.
        self.failures = self.failures + 1
        local delay = math.min(300, 2 ^ math.min(self.failures, 9))
        if code == 429 then delay = math.max(delay, tonumber(header(response, "Retry-After")) or 60) end
        self.nextAt = current + delay
        self.status = nil
        self.message = code == 429 and "Picker asked to slow down, retrying" or "Picker unreachable, retrying"
        -- 409: the picker refused the sequence number as stale. Jump ahead using its clock.
        if code == 409 and date then self.sequence = math.max(self.sequence, math.floor(date * 1000)) end
      end
      if done then done(success, status, code) end
    end
    local ok = pcall(function()
      local request = HTTPRequest.new(handle, path or (method == "GET" and M.STATUS or M.REPORT))
      self.request = request
      request:AddHeader("Authorization", "Bearer " .. key)
      request:AddHeader("Content-Type", "application/json")
      if method == "GET" then request:Get(complete) else request:Post(body, complete) end
    end)
    if not ok then complete({responseCode = 0, failed = true, errorInfo = "HTTPRequest setup failed"}) end
    return true
  end
  function self:test(now, handle, key, done) return self:requestHTTP(now, handle, key, "GET", nil, done) end
  function self:tasksDue(now) return now >= (self.tasksNextAt or 0) end
  -- `from` > 0 asks for "All active" rows past the first reply; sent only to pickers that page.
  function self:fetchTasks(now, handle, key, done, from)
    if not self:tasksDue(now) then return false end
    local paged = math.type(from) == "integer" and from > 0 and not self.tasksNoPaging
    return self:requestHTTP(now, handle, key, "GET", nil, done,
      paged and (M.TASKS .. "?from=" .. from) or M.TASKS)
  end
  -- Sends one report. Without a clock yet, a status request goes first to read the Date header.
  -- Sequence numbers never go backwards: at least one more than the last, and at least the
  -- current time in milliseconds, so losing the saved number never reuses an old one.
  function self:report(now, handle, key, world, position, skills, quests, done,
                       diagnostics, achievements, items, bank)
    local epoch = self:epoch(now)
    if not epoch then
      self.message = "Checking picker clock"
      return self:test(now, handle, key, function(ok)
        if ok and not self:epoch(options.now and options.now() or now) then
          self.message = "Picker clock unavailable (HTTP Date missing)"
          self.nextAt = now + 60
        end
      end)
    end
    if not self:ready(now) then return false end
    self.sequence = math.max(self.sequence + 1, math.floor(epoch * 1000))
    if options.saveSequence then options.saveSequence(self.sequence) end
    local body, payload, warning = M.build(self.sequence, epoch, world, position, skills, quests,
      diagnostics, achievements, items, bank)
    if quests then
      self.payloadWarning = warning
      self.heldQuestJSON = not payload.quests and json.encode(quests) or nil
    end
    return self:requestHTTP(now, handle, key, "POST", body, function(ok, status, code)
      if done then done(ok, payload, status, code) end
    end)
  end
  function self:tick(now)
    -- Guard against a transport that never calls its callback; cancellation fences late callbacks.
    if self.busy and now - self.startedAt > 30 then
      self:cancel()
      self.failures = self.failures + 1
      self.nextAt = now + math.min(300, 2 ^ math.min(self.failures, 9))
      self.status = nil
      self.message = "Picker unreachable, retrying"
      table.insert(self.history, 1,
        {code = 0, timedOut = true, failed = false, errorInfo = "Local 30 s timeout"})
      if #self.history > 5 then table.remove(self.history) end
    end
  end
  return self
end
return M
