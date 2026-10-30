-- Chunk Picker native UI test: BETA WORLD TESTING ONLY. Never ships, never goes to the Plugin Hub.
-- One movable, resizable window built only from the game's own components (no PrettyUI), to
-- learn on beta what the redesign can rely on: dragging, resizing, the native List with a
-- scrollbar, toggle buttons as tabs, and how many components a window like this costs.
-- It sends nothing anywhere, needs no permissions and types no commands.
-- The footer shows what the client reports (mouse, positions, the last few events); every
-- event is also printed in the console, so a test run can be copied from there.

local NAME = "cpNativeTest"
local HEADER, MIN_W, MIN_H = 26, 220, 150
local DEFAULT = {x = 60, y = 140, w = 300, h = 380}
local MODES = {"hold", "click-click", "native"}
local MODE_HELP = {
  hold = "press the title bar, move, release",
  ["click-click"] = "click the title bar, move, click again",
  native = "the game's own drag on the title bar",
}

local top, root, frame, handle, grip, list, footer
local btn = {}
local made, alive, built, minimised = 0, true, false, false
local box = {x = DEFAULT.x, y = DEFAULT.y, w = DEFAULT.w, h = DEFAULT.h}
local mode = 1
local drag, nativeStart = nil, nil
local events, holds = {}, 0
local tab = "here"
local labels = {}
local footerClock, scaleGuess = 0, nil

-- Fake tasks, shaped like the plugin's real "here" and "all" lists. Entries marked done show
-- how a finished task could look (disabled, so the game dims it).
local HERE = {
  {"Woodcutting 15: chop an oak tree"},
  {"Fishing 20: catch a trout"},
  {"Cooking 15: cook a trout"},
  {"Firemaking 15: burn oak logs", true},
  {"Quest: start Cook's Assistant"},
  {"Quest: finish The Restless Ghost", true},
  {"Thieving 5: steal from a cake stall"},
  {"Crafting 1: spin a ball of wool"},
  {"Diary: Lumbridge easy, task 3"},
  {"Other: open the bank here"},
  {"Glyph check: \226\156\147 \226\128\162 \194\183 \226\128\147 \195\169 (tick, bullet, dot, dash, e-acute)"},
  {"A long task name to see whether the list cuts it or wraps it onto a second line in the row"},
}
local SKILLS = {"Attack", "Strength", "Defence", "Ranged", "Prayer", "Magic", "Runecrafting",
  "Construction", "Dungeoneering", "Constitution", "Agility", "Herblore", "Thieving", "Crafting",
  "Fletching", "Slayer", "Hunter", "Mining", "Smithing", "Fishing", "Cooking", "Firemaking",
  "Woodcutting", "Farming", "Summoning", "Divination", "Invention", "Archaeology", "Necromancy"}
local ALL = {}
for i, skill in ipairs(SKILLS) do ALL[#ALL + 1] = {skill .. " " .. (i * 3) .. ": a task somewhere", i % 7 == 0} end
for i = 1, 12 do ALL[#ALL + 1] = {"Quest " .. i .. ": a quest step"} end

local function note(text)
  table.insert(events, 1, text)
  while #events > 3 do table.remove(events) end
  print("UI test: " .. text)
end

local function num(v)
  local n = tonumber(v)
  if not n then return "?" end
  return tostring(math.floor(n + 0.5))
end

-- Vector2 fields, whichever way the client exposes them.
local function xy(v)
  if v == nil then return nil end
  local ok, x, y = pcall(function() return v.x, v.y end)
  if ok and x ~= nil then return x, y end
  ok, x, y = pcall(function() return v[1], v[2] end)
  if ok then return x, y end
end

local function mouse()
  local ok, x, y = pcall(function()
    if not Mouse.IsAvailable() then return nil end
    return xy(Mouse.GetPosition())
  end)
  if ok then return x, y end
end

local function make(kind, parent)
  local ok, c = pcall(function() return ui[kind].new(parent) end)
  if not ok or not c then error("couldn't make a " .. kind .. ": " .. tostring(c)) end
  made = made + 1
  return c
end

local function hook(c, name, fn)
  local ok, err = pcall(function()
    c:Subscribe(ui.Hook[name], NAME .. name .. made, function(...)
      local fine, failure = pcall(fn, ...)
      if not fine then note(name .. " failed: " .. tostring(failure):gsub("[%c]", " "):sub(1, 80)) end
    end)
  end)
  if not ok then note("no " .. name .. " hook: " .. tostring(err):gsub("[%c]", " "):sub(1, 60)) end
end

local function loadInt(key, default)
  local ok, v = pcall(function()
    if not PersistentDB:CheckExists(key) then return nil end
    return PersistentDB:GetInt(key)
  end)
  if ok and v ~= nil then return v end
  return default
end

local function save()
  pcall(function()
    PersistentDB:SetInt("x", math.floor(box.x)); PersistentDB:SetInt("y", math.floor(box.y))
    PersistentDB:SetInt("w", math.floor(box.w)); PersistentDB:SetInt("h", math.floor(box.h))
  end)
end

local function parentSize()
  local ok, w, h = pcall(function() return top.width, top.height end)
  if ok and tonumber(w) and tonumber(h) and w > 0 and h > 0 then return w, h end
end

-- Keeps the title bar on screen and the window at least its minimum size.
local function clamp()
  box.w = math.max(MIN_W, box.w)
  box.h = math.max(MIN_H, box.h)
  local pw, ph = parentSize()
  if pw then
    box.w = math.min(box.w, pw)
    box.h = math.min(box.h, ph)
    box.x = math.max(0, math.min(box.x, pw - 60))
    box.y = math.max(0, math.min(box.y, ph - HEADER))
  end
end

local function place()
  pcall(function()
    root:SetPos(math.floor(box.x), math.floor(box.y))
    root:SetSize(math.floor(box.w), minimised and HEADER + 4 or math.floor(box.h))
  end)
end

local function fillList()
  local rows = tab == "here" and HERE or ALL
  labels = {}
  pcall(function() list:Clear() end)
  for i, row in ipairs(rows) do
    labels[i] = row[1]
    pcall(function()
      list:Add(row[2] and ("(done) " .. row[1]) or row[1], i)
      if row[2] then list:SetEntryEnabled(i, false) end
    end)
  end
  pcall(function()
    btn.here.isToggled = tab == "here"
    btn.all.isToggled = tab == "all"
    btn.here.label = "Here (" .. #HERE .. ")"
    btn.all.label = "All active (" .. #ALL .. ")"
  end)
end

local function startDrag(kind)
  local mx, my = mouse()
  if not mx then note("no mouse position, can't " .. kind); return end
  drag = {kind = kind, mx = mx, my = my, x = box.x, y = box.y, w = box.w, h = box.h}
  pcall(function() root:MoveToFront() end)
  note(kind .. " start at mouse " .. num(mx) .. "," .. num(my))
end

local function endDrag(why)
  if not drag then return end
  local kind = drag.kind
  drag = nil
  clamp(); place(); save()
  note(kind .. " end (" .. why .. ") at " .. num(box.x) .. "," .. num(box.y) .. " " .. num(box.w) .. "x" .. num(box.h))
end

local function followMouse()
  if not drag then return end
  local mx, my = mouse()
  if not mx then return end
  local dx, dy = mx - drag.mx, my - drag.my
  if drag.kind == "move" then
    box.x, box.y = drag.x + dx, drag.y + dy
  else
    box.w, box.h = drag.w + dx, drag.h + dy
  end
  clamp(); place()
end

-- The game's own drag: point it at the whole window while in native mode only, so it
-- can't swallow the clicks the other two modes need.
local function setNativeDrag(on)
  local ok, err = pcall(function()
    local cfg = handle.dragConfig
    cfg.draggedComponent = on and root or nil
    cfg.renderBehaviour = ui.DragRenderBehaviour.OPAQUE
    cfg.dragDelayTicks = 0
    cfg.deadZone = 4
    handle.dragConfig = cfg
  end)
  note("native drag " .. (on and "on" or "off") .. (ok and "" or (": " .. tostring(err):gsub("[%c]", " "):sub(1, 60))))
end

local function onHandleClick(x, y)
  note("title click " .. num(x) .. "," .. num(y))
  -- If the click position is local to the title bar, mouse / (title global + click) is the
  -- ratio between screen pixels and interface units. Shown in the footer, not used yet.
  pcall(function()
    local gx, gy = xy(handle.xyGlobal)
    local mx = mouse()
    if gx and mx and tonumber(x) and gx + x > 0 then scaleGuess = mx / (gx + x) end
  end)
  local m = MODES[mode]
  if m == "hold" then
    if drag then endDrag("click") else startDrag("move") end
  elseif m == "click-click" then
    if drag then endDrag("second click") else startDrag("move") end
  end
end

-- The grip has no native drag: hold mode ends on release, the others on a second click.
local function onGripClick()
  note("grip click")
  if drag then endDrag("second click") else startDrag("size") end
end

local function setMinimised(on)
  minimised = on
  for _, c in ipairs({list, footer, grip, btn.here, btn.all, btn.mode, btn.reset}) do
    pcall(function() c.hidden = on end)
  end
  pcall(function() btn.min.label = on and "+" or "-" end)
  place()
  note(on and "minimised" or "restored")
end

local function destroy()
  drag = nil
  if root then pcall(function() root:Destroy() end) end
  root, frame, handle, grip, list, footer, btn = nil, nil, nil, nil, nil, nil, {}
  built = false
end

local function build()
  top = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
  box.x, box.y = loadInt("x", DEFAULT.x), loadInt("y", DEFAULT.y)
  box.w, box.h = loadInt("w", DEFAULT.w), loadInt("h", DEFAULT.h)
  clamp()

  root = make("Layer", top)
  place()

  frame = make("GroupBox", root)
  frame.stylesheetID = id.StyleSheet.GROUPBOX_DEFAULT
  frame:SetPos(0, 0)
  frame:SetSize(0, 0, 1.0, 1.0)
  pcall(function()
    frame:SetHeaderLayout(200, HEADER, 0, 0, ui.GroupBoxHeaderAlignMode.LEFT)
    frame.headerText.content = "Chunk Picker (native test)"
    frame.headerText.font = id.Font.MUSEO_SANS_15PT_REGULAR
  end)

  -- Title bar hit area: a faint rectangle over the header, left of the two buttons.
  handle = make("Rectangle", root)
  handle:SetPos(0, 0)
  handle:SetSize(-56, HEADER, 1.0, 0)
  pcall(function() handle.fill = true end)
  handle.colour = Vector4.new(1.0, 1.0, 1.0, 0.06)
  hook(handle, "ONCLICK", function(_, x, y) onHandleClick(x, y) end)
  hook(handle, "ONRELEASE", function(_, x, y)
    note("title release " .. num(x) .. "," .. num(y) .. " after " .. holds .. " holds")
    holds = 0
    if MODES[mode] == "hold" then endDrag("release") end
  end)
  hook(handle, "ONHOLD", function() holds = holds + 1 end)
  hook(handle, "ONDRAG", function(_, sx, sy)
    note("native drag start " .. num(sx) .. "," .. num(sy))
    nativeStart = {x = box.x, y = box.y, sx = sx, sy = sy}
  end)
  hook(handle, "ONDRAGCOMPLETE", function(_, dest, ex, ey)
    note("native drag done " .. num(ex) .. "," .. num(ey) .. " onto " .. tostring(dest))
    if MODES[mode] ~= "native" or not nativeStart then return end
    if tonumber(ex) and tonumber(nativeStart.sx) then
      box.x = nativeStart.x + (ex - nativeStart.sx)
      box.y = nativeStart.y + (ey - nativeStart.sy)
      clamp(); place(); save()
    end
    nativeStart = nil
  end)

  btn.close = make("Button", root)
  btn.close.stylesheetID = id.StyleSheet.BUTTON_DEFAULT
  btn.close:SetSize(24, 20)
  btn.close:SetPos(-4, 3, 1.0, 0, 1.0, 0)
  btn.close.label = "x"
  hook(btn.close, "ONBUTTONPRESSED", function()
    print("UI test: closed. Type  prl ui-native-test  in the console to open it again.")
    alive = false
    destroy()
  end)

  btn.min = make("Button", root)
  btn.min.stylesheetID = id.StyleSheet.BUTTON_DEFAULT
  btn.min:SetSize(24, 20)
  btn.min:SetPos(-30, 3, 1.0, 0, 1.0, 0)
  btn.min.label = "-"
  hook(btn.min, "ONBUTTONPRESSED", function() setMinimised(not minimised) end)

  btn.here = make("Button", root)
  btn.here.stylesheetID = id.StyleSheet.BUTTON_DEFAULT
  btn.here.canToggle = true
  btn.here:SetSize(96, 24)
  btn.here:SetPos(8, HEADER + 4)
  hook(btn.here, "ONBUTTONPRESSED", function() tab = "here"; fillList(); note("tab: here") end)

  btn.all = make("Button", root)
  btn.all.stylesheetID = id.StyleSheet.BUTTON_DEFAULT
  btn.all.canToggle = true
  btn.all:SetSize(110, 24)
  btn.all:SetPos(108, HEADER + 4)
  hook(btn.all, "ONBUTTONPRESSED", function() tab = "all"; fillList(); note("tab: all") end)

  list = make("List", root)
  list.stylesheetID = id.StyleSheet.DROPDOWN_DEFAULT1
  pcall(function() list.dropdownMaxVisibleEntries = 0 end)
  pcall(function() list.maxSelected = 1 end)
  pcall(function() list.entryHeight = 22 end)
  pcall(function() list.scrollbar.visible = true end)
  list:SetPos(8, HEADER + 32)
  list:SetSize(-16, -(HEADER + 32 + 62), 1.0, 1.0)
  hook(list, "ONSELECTIONCHANGED", function(_, entryID, selected)
    note("picked " .. tostring(entryID) .. " (" .. tostring(selected) .. "): " .. tostring(labels[entryID] or "?"):sub(1, 40))
  end)
  hook(list, "ONSCROLLWHEEL", function(_, delta) note("list wheel " .. tostring(delta)) end)

  btn.mode = make("Button", root)
  btn.mode.stylesheetID = id.StyleSheet.BUTTON_DEFAULT
  btn.mode:SetSize(130, 22)
  btn.mode:SetPos(8, -58, 0, 1.0)
  btn.mode.label = "Drag: " .. MODES[mode]
  hook(btn.mode, "ONBUTTONPRESSED", function()
    endDrag("mode change")
    if MODES[mode] == "native" then setNativeDrag(false) end
    mode = mode % #MODES + 1
    if MODES[mode] == "native" then setNativeDrag(true) end
    btn.mode.label = "Drag: " .. MODES[mode]
    note("drag mode " .. MODES[mode] .. ": " .. MODE_HELP[MODES[mode]])
  end)

  btn.reset = make("Button", root)
  btn.reset.stylesheetID = id.StyleSheet.BUTTON_DEFAULT
  btn.reset:SetSize(60, 22)
  btn.reset:SetPos(142, -58, 0, 1.0)
  btn.reset.label = "Reset"
  hook(btn.reset, "ONBUTTONPRESSED", function()
    endDrag("reset")
    box = {x = DEFAULT.x, y = DEFAULT.y, w = DEFAULT.w, h = DEFAULT.h}
    clamp(); place(); save()
    note("reset to " .. num(box.x) .. "," .. num(box.y) .. " " .. num(box.w) .. "x" .. num(box.h))
  end)

  footer = make("Text", root)
  footer:SetPos(8, -32, 0, 1.0)
  footer:SetSize(-28, 30, 1.0, 0)
  pcall(function() footer.font = id.Font.MUSEO_SANS_15PT_REGULAR end)
  footer.content = "starting"

  -- Resize grip, bottom-right corner, created last so it sits on top.
  grip = make("Rectangle", root)
  grip:SetSize(16, 16)
  grip:SetPos(0, 0, 1.0, 1.0, 1.0, 1.0)
  pcall(function() grip.fill = true end)
  grip.colour = Vector4.new(1.0, 1.0, 1.0, 0.35)
  hook(grip, "ONCLICK", function() onGripClick() end)
  hook(grip, "ONRELEASE", function()
    note("grip release")
    if MODES[mode] == "hold" then endDrag("release") end
  end)

  fillList()
  built = true
  note("built with " .. made .. " components; drag mode " .. MODES[mode] .. ": " .. MODE_HELP[MODES[mode]])
end

local function updateFooter()
  if not footer then return end
  local mx, my = mouse()
  local rx, ry = nil, nil
  pcall(function() rx, ry = xy(root.xyGlobal) end)
  local pw, ph = parentSize()
  local line1 = string.format("%s | %d comps | win %s,%s %sx%s | screen %sx%s",
    MODES[mode], made, num(box.x), num(box.y), num(box.w), num(box.h), num(pw), num(ph))
  local line2 = string.format("mouse %s,%s | win global %s,%s%s | %s",
    num(mx), num(my), num(rx), num(ry),
    scaleGuess and string.format(" | scale %.2f", scaleGuess) or "",
    events[1] or "no events yet")
  pcall(function() footer.content = line1 .. "\n" .. line2 end)
end

Event.Draw.Subscribe(NAME .. "Draw", function(e)
  if not built then return end
  local ok, err = pcall(function()
    followMouse()
    footerClock = footerClock + (tonumber(e and e.timeDeltaSecs) or 0)
    if footerClock >= 0.2 then footerClock = 0; updateFooter() end
  end)
  if not ok then note("draw failed: " .. tostring(err):gsub("[%c]", " "):sub(1, 80)) end
end)

-- Built on the first game tick rather than at load, so the interface is ready.
Event.ServerLogic.Subscribe(NAME .. "Tick", function()
  if built or not alive then return end
  local ok, err = pcall(build)
  if not ok then
    print("UI test: build failed after " .. made .. " components: " .. tostring(err):gsub("[%c]", " "):sub(1, 160))
    alive = false
    destroy()
  end
end)

pcall(function()
  Event.WindowSizeChanged.Subscribe(NAME .. "Resize", function()
    if built then clamp(); place(); note("game window resized") end
  end)
end)

function PluginShutdown()
  pcall(function() Event.Draw.Unsubscribe(NAME .. "Draw") end)
  pcall(function() Event.ServerLogic.Unsubscribe(NAME .. "Tick") end)
  pcall(function() Event.WindowSizeChanged.Unsubscribe(NAME .. "Resize") end)
  destroy()
end

print("Chunk Picker native UI test loaded (beta only; sends nothing)")
