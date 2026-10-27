-- Ties the saved key to the character it was saved on. PersistentDB is shared by every
-- character on this device, so without this a second character would report its progress
-- as the first one's. The name stays in local storage; it is never sent to the picker.
-- Anything uncertain (no name yet, storage that can't be read or written) pauses sending.
local M = {}
M.MISMATCH = "Key saved on another character; see Settings"
M.WAITING = "Waiting for your character name"
M.STORAGE = "Can't check which character owns the key; paused"
M.UNFINISHED = "Key save didn't finish; save the key again"
-- Held in keyOwner while Save swaps the key, so a save that stops halfway pauses every
-- character instead of handing a key to the wrong one.
-- Display names are at most 12 letters, digits, spaces, hyphens or underscores, so this
-- can't be one. Keep it printable: the game's storage cuts strings at a NUL, so the old
-- "\0saving" never read back and every Save failed.
M.PENDING = "<key save in progress>"
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
  -- `key` is the key the caller is about to send, so a second read can't disagree with it.
  function self:check(key)
    if key == nil or key == "" then
      self.state = "no key"
      return M.STORAGE
    end
    local name = M.current()
    if not name then
      self.state = "waiting"
      return M.WAITING
    end
    local readable, owner = store:read("keyOwner", "String")
    if not readable then
      self.state = "owner unreadable"
      return M.STORAGE
    end
    if owner == M.PENDING then
      self.state = "save unfinished"
      return M.UNFINISHED
    end
    if owner == nil or owner == "" then
      -- A key saved before keys were bound belongs to the first character that uses it,
      -- but only once that binding is stored.
      store:set("keyOwner", "String", name)
      local saved, stored = store:read("keyOwner", "String")
      if not saved or stored ~= name then
        self.state = "binding not saved"
        return M.STORAGE
      end
      self.state = "bound now"
      return nil
    end
    if owner ~= name then
      self.state = "other character"
      return M.MISMATCH
    end
    if self.state ~= "bound now" then self.state = "this character" end
    return nil
  end
  function self:describe() return self.state end
  return self
end
-- Writes a string and reads it back; true only when the stored value matches.
local function wrote(store, name, value)
  store:set(name, "String", value)
  local ok, stored = store:read(name, "String")
  return ok and stored == value
end
-- Saves a new key for the current character (or for whoever uses it first when no name is
-- known yet). Returns nil when saved, or the reason it wasn't.
function M.save(store, key)
  if not wrote(store, "keyOwner", M.PENDING) then return "Couldn't save the key; try again" end
  if not wrote(store, "personalKey", key) then return "Couldn't save the key; try again" end
  if not wrote(store, "keyOwner", M.current() or "") then
    return "Key saved but not tied to this character; Save again"
  end
end
-- Each manifest server keeps its own key and owner. The selected server's pair stays in
-- personalKey and keyOwner, so a key saved before servers had their own belongs to the one
-- selected now; the others wait under these names until their server is chosen again.
function M.parked(server) return "personalKey_" .. server, "keyOwner_" .. server end
-- Selects `to`, parking the current pair under `from` and bringing back `to`'s, or none.
-- Returns nil when switched, or the reason it wasn't. keyOwner holds PENDING from before the
-- server changes until the new pair is in, so a switch that stops halfway pauses sending
-- rather than using one server's key on another, or one character's key on another.
function M.switch(store, from, to)
  if from == to then return nil end
  local failed = "Couldn't switch servers; try again"
  local readKey, key = store:read("personalKey", "String")
  local readOwner, owner = store:read("keyOwner", "String")
  if not readKey or not readOwner then return failed end
  local fromKey, fromOwner = M.parked(from)
  if key and key ~= "" then
    -- Park the current pair under `from`, PENDING first so a half-written copy pauses sending.
    if not (wrote(store, fromOwner, M.PENDING) and wrote(store, fromKey, key)
        and wrote(store, fromOwner, owner or "")) then
      return failed
    end
  elseif not store:forget(fromKey, fromOwner) then
    return failed
  end
  local toKey, toOwner = M.parked(to)
  local readSaved, saved = store:read(toKey, "String")
  local readSavedOwner, savedOwner = store:read(toOwner, "String")
  if not readSaved or not readSavedOwner then return failed end
  -- An empty owner reads as unbound, the same as none.
  local function undo() store:set("keyOwner", "String", owner or "") end
  if not wrote(store, "keyOwner", M.PENDING) then
    undo()
    return failed
  end
  if not wrote(store, "server", to) then
    undo()
    return failed
  end
  -- A parked key always has an owner; if that went missing, Save settles it.
  local loaded
  if saved and saved ~= "" then
    loaded = wrote(store, "personalKey", saved) and wrote(store, "keyOwner", savedOwner or M.PENDING)
  else
    loaded = store:forget()
  end
  if not loaded then return "Server changed but its key didn't load; save the key again" end
  -- The pair now lives only in personalKey and keyOwner, so Forget leaves no copy behind.
  store:forget(toKey, toOwner)
end
return M
