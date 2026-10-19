-- Typed, immediate writes: no proxy objects and no key values in diagnostics.
local M = {}
M.keys = {"server", "personalKey", "sendSkills", "sendQuests", "showPanel", "shadeChunks", "beta", "collapsed", "panelX", "panelY", "sequence"}
function M.new(db)
  local self = {db = db, writeOK = true}
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
  function self:forget() pcall(function() self.db:Delete("personalKey") end) end
  function self:present(key)
    local ok, exists = pcall(function() return self.db:CheckExists(key) end)
    return ok and exists and "set" or "not set"
  end
  return self
end
return M
