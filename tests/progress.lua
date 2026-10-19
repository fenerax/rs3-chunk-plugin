-- Runner sets package.path to the plugin directory before loading this file.
local progress = require("progress")
local function eq(actual, expected)
    assert(actual == expected, tostring(actual) .. " ~= " .. tostring(expected))
end
local ready, xp, quest, fromCalls
local function fixture(mode, mapped)
    ready, xp, fromCalls = true, 100, 0
    Player = {
        IsAvailable = function() return ready end,
        GetLevelUncapped = function() return 42 end,
        GetXPUncapped = function() return xp end,
        GetLevelCapped = function() return 5 end,
        GetXPCapped = function() return 50 end,
    }
    SkillType = {FromID = function(n) return n end}
    QuestType = {NORMAL = 0}
    quest = {id = 7, configName = "COOK", name = "Cook's Assistant", type = 0,
        deprecated = false, hasStartedQuest = false, hasFinishedQuest = false,
        masterQuestVars = mapped and {{varPlayer = {id = 99}}} or {}}
    local skipped = {id = 8, type = 1, name = "Seasonal"}
    local deprecated = {id = 9, type = 0, deprecated = true}
    config = {Quest = {FromID = function(n)
        fromCalls = fromCalls + 1
        if n == 7 then return quest elseif n == 8 then return skipped
        elseif n == 9 then return deprecated end
    end}}
    id = {Quest = {}}
    if mode == "config" then
        config.Quest.COOK, config.Quest.SEASONAL, config.Quest.OLD = quest, skipped, deprecated
        config.Quest.BROKEN = setmetatable({}, {__index = function() error("bad proxy") end})
    elseif mode == "id" then id.Quest = {COOK = 7, SEASONAL = 8, OLD = 9} end
    return progress.new()
end

local p = fixture("config", true)
local otherReads = 0
local other = {id = 10, configName = "OTHER", name = "Other quest", type = 0,
    masterQuestVars = {{varPlayer = {id = 100}}}}
setmetatable(other, {__index = function(_, key)
    if key == "hasStartedQuest" or key == "hasFinishedQuest" then
        otherReads = otherReads + 1
        return false
    end
end})
config.Quest.OTHER = other
eq(p:login(0), true)
eq(p.skillCount, 29); eq(p.questCount, 2); eq(p.questMethod, "config.Quest"); eq(p.varMapped, true)
local skills, quests = p:pending(0, true, true)
eq(skills.ATTACK.xp, 100); eq(skills.NECROMANCY.level, 42)
eq(#quests.finished, 0); eq(#quests.started, 0)
eq(p:pending(0, false, false), nil)
assert(p:pending(0, true, true)) -- pending never consumes
p:ack(skills, quests)
eq(p:pending(0, true, true), nil)

xp = 101; p:skill({skill = 0}, 1)
eq(p:pending(10, true, false), nil)
local first = p:pending(11, true, false)
eq(first.ATTACK.xp, 101)
eq(first.DEFENCE, nil) -- after login only observed skill changes are transmitted
xp = 102; p:skill({skill = 0}, 12)
p:ack(first, nil) -- preserve a newer change while HTTP was in flight
eq(p:pending(21, true, false), nil)
local second = p:pending(22, true, false)
eq(second.ATTACK.xp, 102)
p:ack(second, nil)
eq(p:pending(100, true, false), nil)

quest.hasStartedQuest = true
p:var({var = {id = 123}}, 23)
local _, none = p:pending(100, false, true); eq(none, nil)
p:var({var = {id = 99}}, 24)
eq(otherReads, 2) -- only the quest associated with this var is re-read
local _, early = p:pending(53, false, true); eq(early, nil)
local _, started = p:pending(54, false, true)
eq(started.started[1], "Cook's Assistant")
quest.hasFinishedQuest = true; p:var({var = {id = 99}}, 55)
p:ack(nil, started)
local _, finished = p:pending(85, false, true)
eq(finished.finished[1], "Cook's Assistant"); eq(#finished.started, 0)
p:ack(nil, finished)
-- A mapped quest needs no periodic full scan.
quest.hasFinishedQuest = false; p:tick(1000)
local _, unchanged = p:pending(1000, false, true); eq(unchanged, nil)

p = fixture("id", false); assert(p:login(0))
eq(p.questMethod, "id.Quest"); eq(p.varMapped, false)
skills, quests = p:pending(0, true, true); p:ack(skills, quests)
quest.hasFinishedQuest = true
p:tick(179)
local _, notYet = p:pending(179, false, true); eq(notYet, nil)
p:tick(180)
local _, fallback = p:pending(180, false, true)
eq(fallback.finished[1], "Cook's Assistant")

p = fixture("scan", true); assert(p:login(0))
eq(p.questMethod, "FromID(0..4095)"); eq(fromCalls, 4096)
-- Uncapped calls may be missing or fail on a client version.
Player.GetLevelUncapped = function() error("unavailable") end
Player.GetXPUncapped = nil
p:login(1)
skills = p:pending(1, true, false)
eq(skills.ATTACK.level, 5); eq(skills.ATTACK.xp, 50)

p:reset()
eq(p.skillCount, 0); eq(p.questCount, 0); eq(p.varMapped, false)
eq(p.questMethod, "unavailable"); eq(next(p.skills), nil); eq(next(p.varQuests), nil)
eq(#p.questConfigs, 0); eq(p.quests, nil); eq(p.lastQuestCheck, nil)
eq(next(p.questStatus), nil)
eq(p:pending(999, true, true), nil)
ready = false; eq(p:login(0), false)
p:tick(1); eq(p.skillCount, 0)
ready = true; p:tick(2)
eq(p.skillCount, 29); assert(p:pending(2, true, true))
-- Delay initial publication until all skill data are readable.
p = fixture("config", true)
Player.GetXPUncapped = function(skill) if skill ~= 28 then return 100 end end
Player.GetXPCapped = nil
eq(p:login(0), false); eq(p:pending(0, true, true), nil)
Player.GetXPUncapped = function() return 100 end
p:tick(1); eq(p.skillCount, 29)

-- Missing quest enumeration backs off without dropping skill changes.
p = fixture("scan", false)
local lookup = config.Quest.FromID
local exposeQuests = false
config.Quest.FromID = function(n)
    if exposeQuests then return lookup(n) end
    fromCalls = fromCalls + 1
end
eq(p:login(0), false); eq(fromCalls, 4096)
skills = p:pending(0, true, false); p:ack(skills, nil)
Player.GetXPUncapped = function(skill) return skill == 0 and xp or 100 end
xp = 123; p:skill({skill = 0}, 1)
p:tick(1); eq(fromCalls, 4096)
p:tick(4); eq(fromCalls, 4096)
exposeQuests = true; p:tick(5)
eq(fromCalls, 8192)
skills = p:pending(11, true, false)
eq(skills.ATTACK.xp, 123); eq(skills.DEFENCE, nil)

-- Acknowledging one skill must preserve another skill's later observation.
p:ack(skills, nil)
Player.GetXPUncapped = function() return xp end
xp = 124; p:skill({skill = 0}, 12)
local attack = p:pending(22, true, false)
xp = 125; p:skill({skill = 1}, 23)
p:ack(attack, nil)
skills = p:pending(33, true, false)
eq(skills.ATTACK, nil); eq(skills.DEFENCE.xp, 125)

-- Invalid values cannot become server observations.
for _, badLevel in ipairs({0, 121, 4.5}) do
    p = fixture("config", true)
    Player.GetLevelUncapped = function() return badLevel end
    eq(p:login(0), false); eq(p:pending(0, true, false), nil)
end
for _, badXP in ipairs({-1, 200000001, math.huge, 0/0}) do
    p = fixture("config", true)
    Player.GetXPUncapped = function() return badXP end
    eq(p:login(0), false); eq(p:pending(0, true, false), nil)
end

p = fixture("config", true); assert(p:login(0))
skills, quests = p:pending(0, true, true); p:ack(skills, quests)
xp = 123.5; p:skill({skill = 0}, 1)
skills = p:pending(11, true, false)
eq(skills.ATTACK.xp, 123.5); p:ack(skills, nil)
p:resend(12)
skills, quests = p:pending(12, true, true)
local count = 0; for _ in pairs(skills) do count = count + 1 end
eq(count, 29); assert(quests)
xp = 124.5; p:skill({skill = 0}, 13)
p:ack(skills, quests)
skills = p:pending(23, true, true)
eq(skills.ATTACK.xp, 124.5); eq(skills.DEFENCE, nil)
p:ack(skills, nil)

-- A mapped quest proxy can race the transmit event; retry without publishing a guess.
quest.hasStartedQuest, quest.hasFinishedQuest = true, nil
setmetatable(quest, {__index = function(_, key)
    if key == "hasFinishedQuest" then error("proxy temporarily unavailable") end
end})
p:var({var = {id = 99}}, 24)
eq(p.questRetryAt, 29)
local _, failedSnapshot = p:pending(100, false, true); eq(failedSnapshot, nil)
p:tick(28); eq(p.questRetryAt, 29)
p:tick(29); eq(p.questRetryAt, 34) -- repeated failure retains prior snapshot
quest.hasFinishedQuest = false
p:tick(34)
eq(p.questRetryAt, nil)
local _, retryEarly = p:pending(53, false, true); eq(retryEarly, nil)
local _, retried = p:pending(54, false, true)
eq(retried.started[1], "Cook's Assistant"); eq(#retried.finished, 0)
p:reset(); eq(p.questRetryAt, nil); eq(p.questRetryDue, nil)
print("progress tests passed")
