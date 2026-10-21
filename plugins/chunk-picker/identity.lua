-- Ties the saved key to the character it was saved on. PersistentDB is shared by every
-- character on this device, so without this a second character would report its progress
-- as the first one's. The name stays in local storage; it is never sent to the picker.
local M = {}
M.MISMATCH = "Key saved on another character; see Settings"
M.WAITING = "Waiting for your character name"
function M.current()
  local ok, name = pcall(function()
    local entity = Player.GetEntity()
    if not entity or entity.isValid == false then return nil end
    return entity.displayName
  end)
  if ok and type(name) == "string" and name:find("%S") then return name end
end
function M.new(store)
  local self = {state = "no key"}
  -- Returns nil when reports may go out, or the reason they are paused.
  function self:check()
    if store:get("personalKey", "String", "") == "" then self.state = "no key"; return nil end
    local name = M.current()
    if not name then self.state = "waiting"; return M.WAITING end
    local owner = store:get("keyOwner", "String", "")
    -- A key saved before keys were bound belongs to the first character that uses it.
    if owner == "" then store:set("keyOwner", "String", name); self.state = "bound now"; return nil end
    if owner ~= name then self.state = "other character"; return M.MISMATCH end
    if self.state ~= "bound now" then self.state = "this character" end
    return nil
  end
  -- Saving or re-binding a key: an unknown name leaves it to the first check in game.
  function self:bind() store:set("keyOwner", "String", M.current() or ""); self.state = "rebound" end
  function self:describe() return self.state end
  return self
end
return M
