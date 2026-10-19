-- Beta-only API probe, sent with the picker diagnostics. It looks for undocumented
-- achievement/diary configs and inventory names, reporting the first error text when a
-- lookup fails. It reads only the local player's own data and never prints stored settings.
local M = {}

local function try(label, fn)
  local ok, value = pcall(fn)
  if ok then return label .. ": " .. tostring(value) end
  local message = tostring(value):gsub("[%c]", " "):sub(1, 100)
  return label .. ": error " .. message
end

local function count(container)
  local n = 0
  for _ in pairs(container) do n = n + 1 end
  return n
end

-- First entry of a config table, to see what one record looks like.
local function first(container)
  for key, value in pairs(container) do return key, value end
end

-- Usertype metatables sometimes list their property names; show up to 12.
local function members(value)
  local names, mt = {}, getmetatable(value)
  if type(mt) ~= "table" then return "no metatable table" end
  for key in pairs(mt) do
    if type(key) == "string" and not key:find("^__") then names[#names + 1] = key end
  end
  table.sort(names)
  return #names .. " [" .. table.concat(names, ",", 1, math.min(12, #names)) .. "]"
end

function M.lines()
  local lines = {}
  local function add(label, fn) lines[#lines + 1] = try(label, fn) end
  for _, name in ipairs({"Achievement", "AchievementCategory", "Diary", "Task"}) do
    add("Probe config." .. name, function()
      local source = config[name]
      if source == nil then return "nil" end
      return type(source) .. " count=" .. count(source)
    end)
  end
  add("Probe id.Achievement", function() return id.Achievement == nil and "nil" or (type(id.Achievement) .. " count=" .. count(id.Achievement)) end)
  add("Probe first achievement", function()
    local key, value = first(config.Achievement)
    return tostring(key) .. " name=" .. tostring(value.name)
  end)
  add("Probe achievement members", function() return members(select(2, first(config.Achievement))) end)
  add("Probe quest members", function() return members(config.Quest.COOK_QUEST) end)
  for _, name in ipairs({"BACKPACK", "INV", "INVENTORY", "WORN", "EQUIPMENT", "BANK"}) do
    add("Probe Inv." .. name, function() return tostring(config.Inv[name]) end)
  end
  add("Probe VarPlayer count", function() return count(var.VarPlayer) end)
  add("Probe VarBit", function() return var.VarBit == nil and "nil" or type(var.VarBit) end)
  return lines
end

return M
