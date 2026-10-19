-- Read only the logged-in player's skills and quest status. No proxy enters a payload.
local json = require("json")
local M = {}
local Progress = {}
Progress.__index = Progress
local names = {
    "ATTACK", "DEFENCE", "STRENGTH", "HITPOINTS", "RANGED", "PRAYER", "MAGIC",
    "COOKING", "WOODCUTTING", "FLETCHING", "FISHING", "FIREMAKING", "CRAFTING",
    "SMITHING", "MINING", "HERBLORE", "AGILITY", "THIEVING", "SLAYER", "FARMING",
    "RUNECRAFTING", "HUNTER", "CONSTRUCTION", "SUMMONING", "DUNGEONEERING",
    "DIVINATION", "INVENTION", "ARCHAEOLOGY", "NECROMANCY",
}
local function get(object, key)
    local ok, value = pcall(function() return object[key] end)
    if ok then return value end
end
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok then return value end
end
local function available()
    return call(get(Player, "IsAvailable")) == true
end
local function equal(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for k, v in pairs(a) do if not equal(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = getmetatable(value) and json.array() or {}
    for k, v in pairs(value) do result[k] = copy(v) end
    return result
end
local function finite(value)
    return type(value) == "number" and value == value and value >= 0 and value < math.huge
end
local function skillValue(skill)
    local level = call(get(Player, "GetLevelUncapped"), skill)
    if level == nil then level = call(get(Player, "GetLevelCapped"), skill) end
    local xp = call(get(Player, "GetXPUncapped"), skill)
    if xp == nil then xp = call(get(Player, "GetXPCapped"), skill) end
    -- Official Player docs specify current XP; no internal fixed-point conversion.
    if finite(level) and level >= 1 and level <= 120 and level % 1 == 0
        and finite(xp) and xp <= 200000000 then
        return {level = level, xp = xp}
    end
end
local function normalQuest(quest)
    local normal = get(QuestType, "NORMAL") or 0
    return quest ~= nil and get(quest, "deprecated") ~= true and get(quest, "type") == normal
end
local function enumerate()
    local source = get(config, "Quest")
    local fromID = get(source, "FromID")
    local function collect(container, resolve)
        local found, seen = {}, {}
        pcall(function()
            for _, value in pairs(container) do
                local quest = resolve and call(fromID, value) or value
                local key = get(quest, "id") or get(quest, "configName")
                if key ~= nil and normalQuest(quest) and not seen[key] then
                    seen[key], found[#found + 1] = true, quest
                end
            end
        end)
        return found
    end
    local quests = collect(source, false)
    if #quests > 0 then return quests, "config.Quest" end
    quests = collect(get(id, "Quest"), true)
    if #quests > 0 then return quests, "id.Quest" end
    quests = {}
    for n = 0, 4095 do
        local quest = call(fromID, n)
        if normalQuest(quest) then quests[#quests + 1] = quest end
    end
    return quests, #quests > 0 and "FromID(0..4095)" or "unavailable"
end
local function varKey(variable)
    return get(variable, "id") or get(variable, "configName") or variable
end
function Progress:reset()
    self.skills, self.quests, self.questConfigs, self.varQuests, self.questStatus = {}, nil, {}, {}, {}
    self.skillDirty, self.questDirty, self.skillDue, self.questDue = {}, false, nil, nil
    self.skillCount, self.questCount, self.questMethod, self.varMapped = 0, 0, "unavailable", false
    self.loginPending, self.lastQuestCheck = false, nil
    self.nextQuestRetry = nil
    self.questRetryAt, self.questRetryDue = nil, nil
end
function M.new()
    local self = setmetatable({}, Progress)
    self:reset()
    return self
end
function Progress:readQuests(now, delay, matching)
    local snapshot = {finished = json.array(), started = json.array()}
    local statuses = {}
    for _, quest in ipairs(self.questConfigs) do
        local status = self.questStatus[quest]
        if not matching or matching[quest] or not status then
            status = {name = get(quest, "name"), finished = get(quest, "hasFinishedQuest"),
                started = get(quest, "hasStartedQuest")}
        end
        local name, finished, started = status.name, status.finished, status.started
        -- A not-yet-readable status must not masquerade as an unstarted quest.
        if type(name) ~= "string" or type(finished) ~= "boolean" or type(started) ~= "boolean" then
            -- A proxy can become unreadable between an event and this observation.
            -- Retain the last complete snapshot and retry even when every var is mapped.
            self.questRetryAt = now + 5
            self.questRetryDue = self.questRetryDue or now + delay
            return false
        end
        statuses[quest] = status
        if finished then snapshot.finished[#snapshot.finished + 1] = name
        elseif started then snapshot.started[#snapshot.started + 1] = name end
    end
    if #self.questConfigs == 0 then return false end
    self.questStatus = statuses
    table.sort(snapshot.finished)
    table.sort(snapshot.started)
    if not equal(snapshot, self.quests) then
        self.quests, self.questDirty, self.questDue = snapshot, true, now + delay
    end
    if not matching then self.questRetryAt, self.questRetryDue = nil, nil end
    self.lastQuestCheck = now
    return true
end
function Progress:login(now)
    self.loginPending = true
    if not available() then return false end
    local skills, count = {}, 0
    for n = 0, 28 do
        local skill = call(get(SkillType, "FromID"), n)
        local value = skill ~= nil and skillValue(skill) or nil
        if value then skills[names[n + 1]], count = value, count + 1 end
    end
    self.skillCount = count
    if count ~= 29 then return false end
    for name, value in pairs(skills) do
        if not equal(value, self.skills[name]) then
            self.skills[name], self.skillDirty[name], self.skillDue = value, true, now
        end
    end
    if self.questRetryAt and now < self.questRetryAt then return false end
    if self.nextQuestRetry and now < self.nextQuestRetry then return false end
    if #self.questConfigs == 0 then self.questConfigs, self.questMethod = enumerate() end
    self.nextQuestRetry = #self.questConfigs == 0 and now + 5 or nil
    self.questCount, self.varQuests = #self.questConfigs, {}
    local mapped = 0
    for _, quest in ipairs(self.questConfigs) do
        local hasMapping = false
        pcall(function()
            for _, descriptor in pairs(get(quest, "masterQuestVars")) do
                local variable = get(descriptor, "varPlayer")
                if variable ~= nil then
                    local key = varKey(variable)
                    self.varQuests[key] = self.varQuests[key] or {}
                    self.varQuests[key][quest] = true
                    hasMapping = true
                end
            end
        end)
        if hasMapping then mapped = mapped + 1 end
    end
    self.varMapped = self.questCount > 0 and mapped == self.questCount
    local questsReady = self:readQuests(now, 0)
    self.loginPending = not questsReady
    return questsReady
end
function Progress:skill(event, now)
    if self.skillCount ~= 29 or not available() then return end
    local skill = get(event, "skill")
    for n = 0, 28 do
        if skill ~= nil and skill == call(get(SkillType, "FromID"), n) then
            local value = skillValue(skill)
            local name = names[n + 1]
            if value and not equal(value, self.skills[name]) then
                self.skills[name], self.skillDirty[name], self.skillDue = value, true, now + 10
            end
            return
        end
    end
end
function Progress:var(event, now)
    if self.loginPending or not available() then return end
    local variable = get(event, "var")
    if variable ~= nil and self.varQuests[varKey(variable)] then
        self:readQuests(now, 30, self.varQuests[varKey(variable)])
    end
end
function Progress:tick(now)
    if self.loginPending then self:login(now); return end
    if not available() then return end
    if self.questRetryAt and now >= self.questRetryAt then
        self:readQuests(now, math.max(0, self.questRetryDue - now))
        return
    end
    if not self.varMapped and self.lastQuestCheck and now - self.lastQuestCheck >= 180 then
        self:readQuests(now, 0)
    end
end
function Progress:resend(now)
    for name in pairs(self.skills) do self.skillDirty[name] = true end
    if next(self.skillDirty) then self.skillDue = now end
    if self.quests then self.questDirty, self.questDue = true, now end
end
function Progress:pending(now, sendSkills, sendQuests)
    local skills, quests
    if sendSkills and next(self.skillDirty) and now >= self.skillDue then
        skills = {}
        for name in pairs(self.skillDirty) do skills[name] = copy(self.skills[name]) end
    end
    if sendQuests and self.questDirty and now >= self.questDue then quests = copy(self.quests) end
    return skills, quests
end
function Progress:ack(skills, quests)
    if skills ~= nil then
        for name, value in pairs(skills) do
            if equal(value, self.skills[name]) then self.skillDirty[name] = nil end
        end
    end
    if quests ~= nil and equal(quests, self.quests) then self.questDirty = false end
end
return M
