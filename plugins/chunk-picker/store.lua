-- Saved settings and state in the client's PersistentDB. Typed, immediate writes: no proxy
-- objects and no key values in diagnostics. Every call is guarded, so a storage error reads as
-- the default (get) or as unreadable (read), never as a crash.
local M = {}
-- Every key the plugin stores, listed in diagnostics as set or not set (never the value).
M.keys = {
  "server", "personalKey", "keyOwner",
  "sendSkills", "sendQuests", "sendAchievements", "sendItems",
  "showPanel", "showPartner", "warnLocked", "warnRoll",
  "shadeChunks", "shadeColours", "shadeWidth", "shadeWalls", "shadeGrid",
  "shadeFillLocked", "shadeFillRollable", "shadeFillStrength", "shadeFillStyle", "shadePartner",
  "shadeRgbPartner", "shadeRgbLocked", "shadeRgbRollable", "shadeRgbFillLocked", "shadeRgbFillRollable",
  "beta", "collapsed", "panelX", "panelY", "panelW", "panelH",
  "settingsWindow", "settingsX", "settingsY", "settingsW", "settingsH",
  "tasksWindow", "tasksView", "tasksX", "tasksY", "tasksW", "tasksH",
  "sequence", "itemJournal",
}
function M.new(db)
  local self = {db = db, writeOK = true}
  -- kind is the PersistentDB type suffix: "Bool", "Int" or "String".
  function self:get(key, kind, default)
    local ok, value = pcall(function()
      if not self.db:CheckExists(key) then return nil end
      return self.db["Get" .. kind](self.db, key)
    end)
    if ok and value ~= nil then return value end
    return default
  end
  function self:set(key, kind, value)
    local ok, saved = pcall(function() return self.db["Set" .. kind](self.db, key, value) end)
    self.writeOK = ok and saved ~= false
    return self.writeOK
  end
  -- Like get, but tells an absent key (true, nil) from an unreadable one (false).
  function self:read(key, kind)
    local ok, value = pcall(function()
      if not self.db:CheckExists(key) then return nil end
      return self.db["Get" .. kind](self.db, key)
    end)
    return ok, value
  end
  -- The owner goes only once the key is confirmed gone, so a failed delete can't leave an
  -- unbound key behind for the next character to pick up. Names default to the selected
  -- server's pair; identity.parked names another server's.
  function self:forget(keyName, ownerName)
    keyName, ownerName = keyName or "personalKey", ownerName or "keyOwner"
    pcall(function() self.db:Delete(keyName) end)
    local ok, exists = pcall(function() return self.db:CheckExists(keyName) end)
    if not ok or exists then return false end
    pcall(function() self.db:Delete(ownerName) end)
    return true
  end
  function self:present(key)
    local ok, exists = pcall(function() return self.db:CheckExists(key) end)
    return ok and exists and "set" or "not set"
  end
  return self
end
return M
