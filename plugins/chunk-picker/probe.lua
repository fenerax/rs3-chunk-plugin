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

local function short(value)
  local text = type(value) == "function" and "fn" or tostring(value)
  return (text:gsub("[%c]", " "):sub(1, 24))
end

-- Every member of one achievement with its value, several per line, plus a count of
-- true values across all achievements for each boolean member (to find "completed").
local function achievementLines(lines)
  local ok, err = pcall(function()
    local _, sample = first(config.Achievement)
    local mt, names = getmetatable(sample), {}
    for key in pairs(mt) do if type(key) == "string" and not key:find("^__") then names[#names + 1] = key end end
    table.sort(names)
    local row, booleans = {}, {}
    for _, name in ipairs(names) do
      local okValue, value = pcall(function() return sample[name] end)
      row[#row + 1] = name .. "=" .. (okValue and short(value) or "err")
      if okValue and type(value) == "boolean" then booleans[#booleans + 1] = name end
      if #row == 4 then lines[#lines + 1] = "Ach " .. table.concat(row, " "); row = {} end
    end
    if #row > 0 then lines[#lines + 1] = "Ach " .. table.concat(row, " ") end
    for _, name in ipairs(booleans) do
      local yes, total = 0, 0
      for _, achievement in pairs(config.Achievement) do
        total = total + 1
        local okValue, value = pcall(function() return achievement[name] end)
        if okValue and value == true then yes = yes + 1 end
      end
      lines[#lines + 1] = "Ach true " .. name .. ": " .. yes .. "/" .. total
    end
  end)
  if not ok then lines[#lines + 1] = "Ach error " .. tostring(err):gsub("[%c]", " "):sub(1, 100) end
end

-- The achievement scan walks ~5,000 records, so run it once and reuse the lines.
local cached
function M.lines()
  if not cached then cached = {}; achievementLines(cached) end
  return cached
end

return M
