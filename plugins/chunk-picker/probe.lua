-- Beta-only API probe for Diagnostics. It reports which skill and quest calls exist and
-- the first error text when one fails, so we can see what the client really exposes.
-- It reads only the local player's own data and never prints stored settings.
local M = {}

local function try(label, fn)
  local ok, value = pcall(fn)
  if ok then return label .. ": " .. tostring(value) end
  local message = tostring(value):gsub("[%c]", " "):sub(1, 120)
  return label .. ": error " .. message
end

local function count(container)
  local n = 0
  for _ in pairs(container) do n = n + 1 end
  return n
end

function M.lines()
  return {
    try("Probe SkillType", function() return type(SkillType) end),
    try("Probe SkillType.FromID", function() return type(SkillType.FromID) end),
    try("Probe SkillType.ATTACK", function() return tostring(SkillType.ATTACK) end),
    try("Probe SkillType.Attack", function() return tostring(SkillType.Attack) end),
    try("Probe FromID(0)", function() return tostring(SkillType.FromID(0)) end),
    try("Probe level ATTACK", function() return Player.GetLevelUncapped(SkillType.ATTACK) end),
    try("Probe level Attack", function() return Player.GetLevelUncapped(SkillType.Attack) end),
    try("Probe level FromID(0)", function() return Player.GetLevelUncapped(SkillType.FromID(0)) end),
    try("Probe XP ATTACK", function() return Player.GetXPUncapped(SkillType.ATTACK) end),
    try("Probe config.Quest", function() return type(config.Quest) end),
    try("Probe Quest.FromID", function() return type(config.Quest.FromID) end),
    try("Probe COOK_QUEST name", function() return config.Quest.COOK_QUEST.name end),
    try("Probe COOK_QUEST done", function() return config.Quest.COOK_QUEST.hasFinishedQuest end),
    try("Probe COOK_QUEST type", function() return tostring(config.Quest.COOK_QUEST.type) end),
    try("Probe QuestType.NORMAL", function() return tostring(QuestType.NORMAL) end),
    try("Probe FromID(1) name", function() return config.Quest.FromID(1).name end),
    try("Probe pairs(config.Quest)", function() return count(config.Quest) end),
    try("Probe pairs(id.Quest)", function() return count(id.Quest) end),
  }
end

return M
