-- In-game active tasks: "Here" (the chunk you're in) and "All active", read from the list the
-- picker last saved. The picker never calculates tasks for this window.
local M = {ROWS = 12, REFRESH = 15, MIN_GAP = 3, WIDTH = 360}
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
function M.list(data)
  if type(data) ~= "table" or data.v ~= 1 or type(data.ready) ~= "boolean" then return nil end
  return {ready = data.ready, stale = data.stale == true, hereKnown = data.hereKnown == true,
    chunkId = clean(data.chunkId, 12), here = rows(data.here, 50), all = rows(data.all, 100),
    hereCount = count(data.hereCount), allCount = count(data.allCount)}
end
function M.row(row)
  return (row.category ~= "" and (row.category .. " · ") or "") .. row.label .. (row.level and (" (" .. row.level .. ")") or "")
end
-- The header line and one page of rows for a view ("here" or "all").
function M.page(list, view, page, message)
  if not list then return message or "Loading tasks…", {}, 1, 1 end
  if not list.ready then return "No saved task list yet. Open your tasks in the picker once.", {}, 1, 1 end
  local here = view == "here"
  if here and not list.hereKnown then return "Waiting for your location in the picker.", {}, 1, 1 end
  local shown, total = here and list.here or list.all, here and list.hereCount or list.allCount
  local pages = math.max(1, math.ceil(#shown / M.ROWS)); page = math.max(1, math.min(page, pages))
  local out = {}
  for i = (page - 1) * M.ROWS + 1, math.min(#shown, page * M.ROWS) do out[#out + 1] = M.row(shown[i]) end
  local head
  if total == 0 then head = here and "No active tasks in this chunk." or "No active tasks."
  else
    head = (here and ("Here: " .. total .. (total == 1 and " task" or " tasks")) or ("All active: " .. total))
      .. (pages > 1 and (" · page " .. page .. "/" .. pages) or "")
      .. (#shown < total and (" · first " .. #shown) or "")
  end
  if list.stale then head = head .. " · saved before your last change" end
  if message then head = head .. " · " .. message end
  return head, out, page, pages
end
function M.new(store)
  local self = {page = 1, view = store:get("tasksView", "String", "here")}
  if self.view ~= "here" and self.view ~= "all" then self.view = "here" end
  function self:isOpen() return store:get("tasksWindow", "Bool", false) end
  function self:open() store:set("tasksWindow", "Bool", true); self.error = nil; self.wanted = true; self:build() end
  function self:destroy()
    if self.window then pcall(function() self.window:Destroy() end) end
    self.window = nil; self.lines = nil
  end
  function self:savePosition()
    if not self.window then return end
    local ok, x, y = pcall(function() return self.window.root.x, self.window.root.y end)
    if ok and type(x) == "number" and type(y) == "number" and (math.floor(x) ~= self.x or math.floor(y) ~= self.y) then
      self.x = math.floor(x); self.y = math.floor(y); store:set("tasksX", "Int", self.x); store:set("tasksY", "Int", self.y)
    end
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
      local height = 112 + M.ROWS * 18
      local x = math.max(0, math.min(store:get("tasksX", "Int", 40), math.max(0, parent.width - M.WIDTH)))
      local y = math.max(0, math.min(store:get("tasksY", "Int", 300), math.max(0, parent.height - height)))
      local w = prettyui.Window.new(parent, {title = "Chunk tasks", x = x, y = y, width = M.WIDTH, height = height,
        minWidth = 240, minHeight = 120, scrollable = false,
        -- Closing only marks it; tick() tears it down outside PrettyUI's own close handling.
        onClose = function() store:set("tasksWindow", "Bool", false) end})
      self.window = w; self.x = x; self.y = y
      w:AddSimpleButton("Here", function() choose("here") end, {tooltip = "Active tasks in the chunk you're in"})
      w:AddSimpleButton("All active", function() choose("all") end, {inline = true, tooltip = "Your whole active list"})
      w:AddSimpleButton("Back", function() self.page = math.max(1, self.page - 1) end, {inline = true})
      w:AddSimpleButton("More", function() self.page = self.page + 1 end, {inline = true})
      self.head = w:AddText({text = "Loading tasks…", height = 36, maxLines = 2})
      self.lines = {}
      for i = 1, M.ROWS do self.lines[i] = w:AddText({text = "", height = 18, maxLines = 1}) end
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
    local head, lines, page = M.page(list, self.view, self.page, message)
    self.page = page
    pcall(function()
      self.window:SetTitle(self.view == "here" and "Chunk tasks: here" or "Chunk tasks: all active")
      self.head.content = head
      for i = 1, M.ROWS do self.lines[i].content = lines[i] or "" end
    end)
  end
  function self:describe()
    return (self.error and ("failed: " .. self.error)) or (self.window and ("open, " .. self.view)) or "closed"
  end
  return self
end
return M
