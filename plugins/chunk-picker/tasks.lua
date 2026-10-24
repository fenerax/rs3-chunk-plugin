-- In-game active tasks: "Here" (the chunk you're in) and "All active", read from the list the
-- picker last saved. The picker never calculates tasks for this window.
-- CHUNK is the most "All active" rows one reply carries; pickers that send `allFrom` give the rest
-- through `?from=`.
local M = {ROWS = 12, REFRESH = 15, MIN_GAP = 3, WIDTH = 360, CHUNK = 100}
-- Resizable: a taller window shows more rows per page. CHROME is the title bar, buttons and header.
M.CHROME, M.ROW, M.MIN_W, M.MIN_ROWS, M.MAX_ROWS = 112, 18, 300, 3, 40
function M.rowsFor(height) return math.max(M.MIN_ROWS, math.min(M.MAX_ROWS, math.floor((height - M.CHROME) / M.ROW))) end
local function clean(text, limit) return type(text) == "string" and (text:gsub("[<>%c]", "")):sub(1, limit) or nil end
local function count(n) return math.type(n) == "integer" and n >= 0 and n or 0 end
local function rows(list, max)
  local out = {}
  if type(list) ~= "table" then return out end
  for i = 1, math.min(#list, max) do
    local row = list[i]
    local label = type(row) == "table" and clean(row.label, 120)
    if label and label ~= "" then
      out[#out + 1] = {label = label, category = clean(row.category, 40) or "",
        level = math.type(row.level) == "integer" and row.level > 0 and row.level or nil}
    end
  end
  return out
end
-- Response body -> plain table, or nil when it isn't a v1 task list. Bad rows are dropped.
-- `allFrom` (nil from older pickers) is where `all` starts; `allHeld` counts the rows as sent, so a
-- dropped row can't make the window ask for the same rows again.
function M.list(data)
  if type(data) ~= "table" or data.v ~= 1 or type(data.ready) ~= "boolean" then return nil end
  return {ready = data.ready, stale = data.stale == true, hereKnown = data.hereKnown == true,
    chunkId = clean(data.chunkId, 12), here = rows(data.here, 50), all = rows(data.all, M.CHUNK),
    allFrom = math.type(data.allFrom) == "integer" and data.allFrom >= 0 and data.allFrom or nil,
    allHeld = type(data.all) == "table" and math.min(#data.all, M.CHUNK) or 0,
    hereCount = count(data.hereCount), allCount = count(data.allCount)}
end
function M.row(row)
  return (row.category ~= "" and (row.category .. " · ") or "") .. row.label .. (row.level and (" (" .. row.level .. ")") or "")
end
-- The header line and one page of rows for a view ("here" or "all"); `size` rows a page.
-- When the picker pages ("all" with `allFrom`), pages run over the whole list and a page outside
-- the rows held returns a fifth value: the `from` to ask for.
function M.page(list, view, page, message, size)
  size = size or M.ROWS
  if not list then return message or "Loading tasks…", {}, 1, 1 end
  if not list.ready then return "No saved task list yet. Open your tasks in the picker once.", {}, 1, 1 end
  local here = view == "here"
  if here and not list.hereKnown then return "Waiting for your location in the picker.", {}, 1, 1 end
  local shown, total = here and list.here or list.all, here and list.hereCount or list.allCount
  local paged = not here and list.allFrom ~= nil
  local pages = math.max(1, math.ceil((paged and total or #shown) / size)); page = math.max(1, math.min(page, pages))
  local out, want = {}, nil
  local first, last = (page - 1) * size + 1, math.min(paged and total or #shown, page * size)
  local from = paged and list.allFrom or 0
  if paged and first <= last and (first <= from or last > from + list.allHeld) then
    -- Going back asks for the rows that end at this page, so Back doesn't refetch on every press.
    want = first <= from and math.max(0, last - M.CHUNK) or first - 1
  else
    for i = first, last do if shown[i - from] then out[#out + 1] = M.row(shown[i - from]) end end
  end
  local head
  if total == 0 then head = here and "No active tasks in this chunk." or "No active tasks."
  else
    head = (here and ("Here: " .. total .. (total == 1 and " task" or " tasks")) or ("All active: " .. total))
      .. (pages > 1 and (" · page " .. page .. "/" .. pages) or "")
      .. (not paged and #shown < total and (" · first " .. #shown) or "")
      .. (want and " · loading…" or "")
  end
  if list.stale then head = head .. " · saved before your last change" end
  if message then head = head .. " · " .. message end
  return head, out, page, pages, want
end
function M.new(store)
  local self = {page = 1, view = store:get("tasksView", "String", "here")}
  if self.view ~= "here" and self.view ~= "all" then self.view = "here" end
  function self:isOpen() return store:get("tasksWindow", "Bool", false) end
  function self:open() store:set("tasksWindow", "Bool", true); self.error = nil; self.wanted = true; self:build() end
  function self:destroy()
    if self.window then pcall(function() self.window:Destroy() end) end
    self.window = nil; self.lines = nil; self.pending = nil
  end
  function self:savePosition()
    if not self.window then return end
    local ok, x, y, w, h = pcall(function() local r = self.window.root; return r.x, r.y, r.width, r.height end)
    if not ok or type(x) ~= "number" or type(y) ~= "number" then return end
    if math.floor(x) ~= self.x or math.floor(y) ~= self.y then
      self.x = math.floor(x); self.y = math.floor(y); store:set("tasksX", "Int", self.x); store:set("tasksY", "Int", self.y)
    end
    if type(w) ~= "number" or type(h) ~= "number" then return end
    w, h = math.floor(w), math.floor(h)
    -- A new size rebuilds the rows to fill it once it has held for a second, so a drag in
    -- progress isn't interrupted.
    if w == self.w and h == self.h then self.pending = nil
    elseif self.pending and self.pending.w == w and self.pending.h == h then
      store:set("tasksW", "Int", w); store:set("tasksH", "Int", h); self:build()
    else self.pending = {w = w, h = h} end
  end
  local function choose(view)
    -- Applied on the next render, not inside the button's own click.
    self.view = view; self.page = 1; store:set("tasksView", "String", view)
  end
  function self:build()
    self:destroy()
    if not self:isOpen() or self.error then return end
    local ok, err = pcall(function()
      local parent = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
      if not parent then return end
      local width = math.max(M.MIN_W, math.min(store:get("tasksW", "Int", M.WIDTH), parent.width))
      local height = math.max(M.CHROME + M.MIN_ROWS * M.ROW, math.min(store:get("tasksH", "Int", M.CHROME + M.ROWS * M.ROW), parent.height))
      self.rows = M.rowsFor(height)
      local x = math.max(0, math.min(store:get("tasksX", "Int", 40), math.max(0, parent.width - width)))
      local y = math.max(0, math.min(store:get("tasksY", "Int", 300), math.max(0, parent.height - height)))
      local w = prettyui.Window.new(parent, {title = "Chunk tasks", x = x, y = y, width = width, height = height,
        resizable = true, minWidth = M.MIN_W, minHeight = M.CHROME + M.MIN_ROWS * M.ROW, scrollable = false,
        -- Closing only marks it; tick() tears it down outside PrettyUI's own close handling.
        onClose = function() store:set("tasksWindow", "Bool", false) end})
      self.window = w; self.x = x; self.y = y; self.w = width; self.h = height
      self.resizable = w.resize ~= nil and (require("settings").widen(w.resize) and "wide" or "narrow") or false
      w:AddSimpleButton("Here", function() choose("here") end, {tooltip = "Active tasks in the chunk you're in"})
      w:AddSimpleButton("All active", function() choose("all") end, {inline = true, tooltip = "Your whole active list"})
      w:AddSimpleButton("Back", function() self.page = math.max(1, self.page - 1) end, {inline = true})
      w:AddSimpleButton("More", function() self.page = self.page + 1 end, {inline = true})
      self.head = w:AddText({text = "Loading tasks…", height = 36, maxLines = 2})
      self.lines = {}
      for i = 1, self.rows do self.lines[i] = w:AddText({text = "", height = M.ROW, maxLines = 1}) end
    end)
    -- Don't retry a window that failed to build every second; the Tasks button tries again.
    if not ok then self.error = tostring(err):gsub("[%c]", " "):sub(1, 100); self:destroy() end
  end
  -- Once a second, from the main loop.
  function self:tick()
    if not self:isOpen() then if self.window then self:destroy() end; return end
    if not self.window and not self.error then self:build() end
    self:savePosition()
  end
  function self:render(list, message)
    if not self.window or not self.lines then return end
    local head, lines, page, _, want = M.page(list, self.view, self.page, message, #self.lines)
    self.page = page; self.wantFrom = want
    pcall(function()
      self.window:SetTitle(self.view == "here" and "Chunk tasks: here" or "Chunk tasks: all active")
      self.head.content = head
      for i = 1, #self.lines do self.lines[i].content = lines[i] or "" end
    end)
  end
  function self:describe()
    return (self.error and ("failed: " .. self.error))
      or (self.window and ("open, " .. self.view .. "; " .. #self.lines .. " rows; edge resize=" .. tostring(self.resizable))) or "closed"
  end
  return self
end
return M
