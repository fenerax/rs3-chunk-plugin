-- Ties the saved key to the character it was saved on. PersistentDB is shared by every
-- character on this device, so without this a second character would report its progress
-- as the first one's. The name stays in local storage; it is never sent to the picker.
-- Anything uncertain (no name yet, storage that can't be read or written) pauses sending.
local M = {}
M.MISMATCH = "Key saved on another character; see Settings"
M.WAITING = "Waiting for your character name"
M.STORAGE = "Can't check which character owns the key; paused"
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
    local readable, owner = store:read("keyOwner", "String")
    if not readable then self.state = "owner unreadable"; return M.STORAGE end
    if owner == nil or owner == "" then
      -- A key saved before keys were bound belongs to the first character that uses it,
      -- but only once that binding is stored.
      store:set("keyOwner", "String", name)
      local saved, stored = store:read("keyOwner", "String")
      if not saved or stored ~= name then self.state = "binding not saved"; return M.STORAGE end
      self.state = "bound now"; return nil
    end
    if owner ~= name then self.state = "other character"; return M.MISMATCH end
    if self.state ~= "bound now" then self.state = "this character" end
    return nil
  end
  function self:describe() return self.state end
  return self
end
return M
