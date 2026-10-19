-- Beta-only API probe, sent with the picker diagnostics. It counts achievement progress
-- and lists completed achievements by category, to plan automatic area-task completion.
-- It reads only the local player's own data and never prints stored settings.
local M = {}

local function short(value)
  local text = type(value) == "function" and "fn" or tostring(value)
  return (text:gsub("[%c]", " "):sub(1, 24))
end

local function categoryName(n)
  local ok, name = pcall(function() return id.Category.FromID(n) end)
  return ok and name ~= nil and tostring(name) or tostring(n)
end

-- Pack short items into lines of at most 150 characters.
local function pack(lines, prefix, items, maxLines)
  local line, used = prefix, 0
  for _, item in ipairs(items) do
    if #line + #item + 2 > 150 then
      used = used + 1
      if used > maxLines then return end
      lines[#lines + 1] = line; line = prefix
    end
    line = line .. (line == prefix and "" or "; ") .. item
  end
  if line ~= prefix and used < maxLines then lines[#lines + 1] = line end
end

-- Per the API docs, progress -2 means complete, -1 locked, 0 ready, -3 grace,
-- -4 deprecated, and 1..10000 is partial progress. Count those, then show completed
-- achievements grouped by category so diaries and area sets can be spotted.
local function achievementLines(lines)
  local ok, err = pcall(function()
    local buckets = {[-4] = 0, [-3] = 0, [-2] = 0, [-1] = 0, [0] = 0, partial = 0}
    local byCategory, done = {}, {}
    for _, achievement in pairs(config.Achievement) do
      local progress = achievement.progress
      if progress > 0 then buckets.partial = buckets.partial + 1 else buckets[progress] = (buckets[progress] or 0) + 1 end
      if progress == -2 then
        local category = achievement.category
        byCategory[category] = (byCategory[category] or 0) + 1
        done[#done + 1] = {category = category, name = tostring(achievement.name)}
      end
    end
    lines[#lines + 1] = "Ach progress: complete=" .. buckets[-2] .. " partial=" .. buckets.partial .. " ready=" .. buckets[0]
      .. " locked=" .. buckets[-1] .. " grace=" .. buckets[-3] .. " deprecated=" .. buckets[-4]
    local categories = {}
    for category, n in pairs(byCategory) do categories[#categories + 1] = {category = category, n = n} end
    table.sort(categories, function(a, b) return a.n > b.n end)
    local summary = {}
    for _, c in ipairs(categories) do summary[#summary + 1] = categoryName(c.category) .. "(" .. c.category .. ")=" .. c.n end
    pack(lines, "Ach done by category: ", summary, 6)
    table.sort(done, function(a, b) return a.category < b.category or (a.category == b.category and a.name < b.name) end)
    local names = {}
    for _, d in ipairs(done) do names[#names + 1] = d.category .. ":" .. short(d.name) end
    pack(lines, "Ach done: ", names, 22)
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
