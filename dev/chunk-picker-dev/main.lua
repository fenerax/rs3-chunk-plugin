-- Chunk Picker dev tools: BETA WORLD TESTING ONLY. Never ships, never goes to the Plugin Hub.
-- Buttons type Jagex's dev cheat commands (!tele, !give, !bank, !getcoord) into the console for
-- testing the Chunk Picker plugin. Jagex logs every cheat command, and abuse can mean a ban, so
-- a command only ever runs from a button press: nothing here runs on a timer or in a loop.
local cmd = require("devcmd")
local now, lastSent, alive = 0, -1000, true
local window, fields, labels = nil, {}, {}
local COOLDOWN = 2

local function grid()
  local ok, g, instance = pcall(function()
    if not Player.IsAvailable() then return nil end
    local g = Player.GetEntity().coordGrid
    if World and type(World.IsRegion) == "function" and World.IsRegion() then
      return World.GetRegionSourceForCoordGrid(g), true
    end
    return g, false
  end)
  if ok then return g, instance end
end

local function say(text)
  if labels.result then pcall(function() labels.result.content = text end) end
  print("Chunk Picker dev: " .. text)
end

-- Runs one cheat command, or says why not and prints it to type by hand.
-- "Sent" only means the console took it; the game's reply (or error) shows in the console.
local function run(command, err, note)
  if not command then say(err or "Couldn't build the command"); return end
  if now - lastSent < COOLDOWN then say("Wait a moment between commands"); return end
  lastSent = now
  local ok, failure = pcall(function()
    if type(ExecuteConsoleCommand) == "nil" then error("ExecuteConsoleCommand is missing") end
    ExecuteConsoleCommand(command)
  end)
  if ok then say("Sent: " .. command .. (note or ""))
  else say("Couldn't run it (" .. tostring(failure):gsub("[%c]", " "):sub(1, 60) .. "); type: " .. command) end
end

local function text(field)
  local ok, value = pcall(function() return field:GetText() end)
  return ok and value or nil
end

local function teleport()
  local target, err = cmd.parseTarget(text(fields.target))
  if not target then say(err); return end
  local here = grid()
  local floor = target.floor or (here and here.level) or 0
  run(cmd.tele(floor, target.x, target.z, 32, 32))
end

-- Same floor and spot inside the chunk, one chunk over: for chunk-crossing tests.
local function step(dir)
  local here = grid()
  if not here then say("Log in first"); return end
  local x, z = cmd.neighbour(here.mapSquareX, here.mapSquareZ, dir)
  if not x then say("That's the edge of the map"); return end
  run(cmd.tele(here.level, x, z, here.localX, here.localZ))
end

local function findName(objId)
  return config.Obj.FromID(objId).configName
end
-- An ObjType by id, or by configName as typed, upper-case or lower-case (config.Inv uses
-- upper-case names, so config.Obj may too). Returns its fields as a plain table, or nil and why.
local function objInfo(key)
  local o, last
  local keys = type(key) == "number" and {key} or {key, key:upper(), key:lower()}
  for _, k in ipairs(keys) do
    local ok, found = pcall(function()
      if type(k) == "number" then return config.Obj.FromID(k) end
      return config.Obj[k]
    end)
    if ok and found then o = found; break end
    last = ok and "not found" or tostring(found):gsub("[%c]", " "):sub(1, 40)
  end
  if not o then return nil, last or "not found" end
  local ok, info = pcall(function()
    -- stackType may come back as a number or an enum value; ALWAYS is 1 either way.
    local stack = o.stackType
    stack = math.tointeger(tonumber(stack)) or (tostring(stack):find("ALWAYS") and cmd.STACK_ALWAYS) or stack
    return {id = math.tointeger(tonumber(o.id)), name = o.name, configName = o.configName, stackType = stack}
  end)
  if not ok then return nil, "fields unreadable: " .. tostring(info):gsub("[%c]", " "):sub(1, 40) end
  if not info.id then return nil, "no id on it" end
  return info
end
local function give(noted)
  local typed = text(fields.item)
  local name, err = cmd.itemName(typed, findName)
  if not name then say(err); return end
  local typedId = math.tointeger(tonumber(typed))
  local info, why = objInfo(typedId or name)
  -- A typed name the game knows is sent as its exact configName; one it doesn't still goes,
  -- since !give may know names config.Obj doesn't, but with a warning.
  local note
  if not typedId then
    local exact = info and type(info.configName) == "string" and cmd.itemName(info.configName, findName)
    if exact then name = exact else note = ". Couldn't check that name: if nothing arrives, type its id" end
  end
  if noted then
    if not info then say("Couldn't look up " .. name .. " (" .. why .. "); try its id, e.g. 1511"); return end
    name, err = cmd.notedOf(info, objInfo)
    if not name then say(err); return end
    note = nil
  end
  local command, bad = cmd.give(name, text(fields.count))
  run(command, bad, note)
end

local function destroy()
  if window then pcall(function() window:Destroy() end) end
  window, fields, labels = nil, {}, {}
end

local function build()
  destroy()
  local ok, err = pcall(function()
    local parent = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
    if not parent then return end
    local w = prettyui.Window.new(parent, {title = "Chunk Picker dev (beta only)", x = 20, y = 120, width = 360, height = 420,
      resizable = true, minWidth = 300, minHeight = 360, scrollable = false, onClose = function() alive = false end})
    window = w
    labels.position = w:AddText({text = "Position: waiting", height = 36, maxLines = 2})
    w:AddText("Teleport: chunk id, x,z or floor,x,z")
    fields.target = w:AddTextField({text = "", placeholder = "12850 or 50,50", maxLength = 20})
    w:AddSimpleButton("Teleport", teleport, {tooltip = "!tele to the middle of that chunk"})
    for _, dir in ipairs({"N", "E", "S", "W"}) do
      w:AddSimpleButton(dir, function() step(dir) end, {inline = true, tooltip = "One chunk " .. dir})
    end
    w:AddText("Give: item name or id, then a count")
    fields.item = w:AddTextField({text = "", placeholder = "logs or 1511", maxLength = 80})
    fields.count = w:AddTextField({text = "", placeholder = "Count (1)", maxLength = 10})
    w:AddSimpleButton("Give", function() give(false) end, {tooltip = "!give into the backpack"})
    w:AddSimpleButton("Give noted", function() give(true) end, {inline = true, tooltip = "!give the noted version, so a big count fits"})
    w:AddSimpleButton("Open bank", function() run("!bank") end, {inline = true})
    w:AddSimpleButton("Where am I", function() run("!getcoord") end, {inline = true, tooltip = "Prints your coordinate in the console"})
    labels.result = w:AddText({text = "Cheats are logged by Jagex: test use only", height = 54, maxLines = 3})
  end)
  if not ok then destroy(); print("Chunk Picker dev: window failed: " .. tostring(err):gsub("[%c]", " "):sub(1, 100)) end
end

Event.Draw.Subscribe("chunkPickerDevDraw", function(e)
  local delta = tonumber(e.timeDeltaSecs)
  if delta and delta >= 0 and delta < 60 then now = now + delta end
end)
-- Reads the position only; never sends a command.
Event.ServerLogic.Subscribe("chunkPickerDevTick", function()
  if not alive then if window then destroy() end; return end
  if not window then build() end
  if labels.position then
    local g, instance = grid()
    pcall(function() labels.position.content = cmd.positionLine(g, instance) end)
  end
end)
function PluginShutdown()
  pcall(function() Event.Draw.Unsubscribe("chunkPickerDevDraw") end)
  pcall(function() Event.ServerLogic.Unsubscribe("chunkPickerDevTick") end)
  destroy()
end
print("Chunk Picker dev tools loaded (beta only; cheat commands are logged)")
