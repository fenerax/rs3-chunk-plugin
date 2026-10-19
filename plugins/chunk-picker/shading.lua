-- Draws chunk borders in the 3D world from the picker's nearby states.
-- One persistent ShapeInstance holds every line and wall, so nothing runs per frame:
-- geometry is rebuilt only when the states, floor, toggle or loaded terrain change.
local M = {}
M.NAME = "chunk-picker-shading"
M.TILE = 512                 -- fine units per tile
M.TILES = 64                 -- tiles per map square (chunk)
M.LIFT = 16                  -- keeps ground lines just above the terrain
M.WALL = 320                 -- height of the translucent wall on a state boundary
-- Rank decides which side of an edge colours it. Unlocked and unknown draw nothing.
local RANK = {locked = 2, available = 1}
local RGB = {[2] = 0xFF3B30, [1] = 0xFFB020}
local ALPHA = {line = 0xE6, grid = 0x80, wallBase = 0x70, wallTop = 0x00}
local function rgba(rgb, alpha) return rgb * 256 + alpha end

local function square(id) return math.type(id) == "integer" and id >= 0 and id // 256 <= 199 and id % 256 <= 199 end
-- Map square id -> state, from net.lua's checked `nearby` map. Older pickers send only the
-- current chunk, so fall back to it.
function M.rows(status)
  if type(status) ~= "table" then return nil end
  local rows, count = {}, 0
  if type(status.nearby) == "table" then
    for id, state in pairs(status.nearby) do
      if square(id) and type(state) == "string" then rows[id] = state; count = count + 1 end
    end
  end
  if count > 0 then return rows end
  local id = type(status.chunkId) == "string" and status.chunkId:match("^%d+$") and math.tointeger(tonumber(status.chunkId))
  if id and square(id) and RANK[status.state] then return {[id] = status.state} end
  return nil
end

-- Signature of what the geometry depends on; equal signatures never rebuild.
function M.signature(rows, floor)
  local ids = {}
  for id in pairs(rows) do ids[#ids + 1] = id end
  table.sort(ids)
  local parts = {tostring(floor)}
  for i, id in ipairs(ids) do parts[i + 1] = id .. "=" .. rows[id] end
  return table.concat(parts, ",")
end

-- Pure geometry: returns positions as {x,y,z} triples relative to origin, plus colours and
-- 0-based indices. height(tileX, tileZ) returns world fine height or nil when unloaded.
function M.geometry(rows, height)
  local minX, minZ
  for id in pairs(rows) do
    local x, z = id // 256, id % 256
    minX = math.min(minX or x, x); minZ = math.min(minZ or z, z)
  end
  local out = {positions = {}, rgba = {}, lines = {}, tris = {}, edges = 0, walls = 0, missing = 0,
    originX = (minX or 0) * M.TILES * M.TILE, originZ = (minZ or 0) * M.TILES * M.TILE}
  if not minX then return out end
  local cache = {}
  local function ground(tx, tz)
    local key = tx * 16384 + tz
    local h = cache[key]
    if h == nil then h = height(tx, tz) or false; cache[key] = h end
    return h or nil
  end
  local function vertex(tx, tz, y, colour)
    local p = out.positions
    p[#p + 1] = {tx * M.TILE - out.originX, y, tz * M.TILE - out.originZ}
    out.rgba[#out.rgba + 1] = colour
    return #p - 1
  end
  -- An edge runs 64 tiles from (tx,tz) along +x (dx=1) or +z (dz=1).
  local function edge(tx, tz, dx, dz, rank, boundary)
    out.edges = out.edges + 1
    local rgb = RGB[rank]
    local lineColour = rgba(rgb, boundary and ALPHA.line or ALPHA.grid)
    local previous, previousBase, previousTop
    for step = 0, M.TILES do
      local x, z = tx + dx * step, tz + dz * step
      local h = ground(x, z)
      if not h then
        out.missing = out.missing + 1; previous = nil
      else
        local line = vertex(x, z, h + M.LIFT, lineColour)
        local base, top
        if boundary then
          base = vertex(x, z, h + M.LIFT // 2, rgba(rgb, ALPHA.wallBase))
          top = vertex(x, z, h + M.WALL, rgba(rgb, ALPHA.wallTop))
        end
        if previous then
          local l = out.lines; l[#l + 1] = previous; l[#l + 1] = line
          if boundary then
            -- Both windings, so the wall shows from either side whatever the culling mode.
            local t = out.tris
            for _, v in ipairs({previousBase, base, top, previousBase, top, previousTop,
                                previousBase, top, base, previousBase, previousTop, top}) do t[#t + 1] = v end
          end
        end
        previous, previousBase, previousTop = line, base, top
      end
    end
    if boundary then out.walls = out.walls + 1 end
  end
  local function rank(id) local s = rows[id]; return s and (RANK[s] or 0) or nil end
  for id, state in pairs(rows) do
    local cx, cz = id // 256, id % 256
    local own = RANK[state] or 0
    local tx, tz = cx * M.TILES, cz * M.TILES
    -- Each shared edge belongs to the chunk north or east of it; perimeter edges to the inside chunk.
    local sides = {
      {tx, tz, 1, 0, cz > 0 and rank(id - 1) or nil},              -- south
      {tx, tz, 0, 1, cx > 0 and rank(id - 256) or nil},            -- west
    }
    if not (cz < 199 and rank(id + 1)) then sides[#sides + 1] = {tx, tz + M.TILES, 1, 0, nil} end       -- north
    if not (cx < 199 and rank(id + 256)) then sides[#sides + 1] = {tx + M.TILES, tz, 0, 1, nil} end     -- east
    for _, side in ipairs(sides) do
      local other = side[5]
      local top = math.max(own, other or 0)
      -- A wall marks where the state changes; matching or unseen neighbours get a faint grid line.
      if top > 0 then edge(side[1], side[2], side[3], side[4], top, other ~= nil and other ~= own) end
    end
  end
  return out
end

function M.new(options)
  options = options or {}
  local self = {state = "waiting", edges = 0, walls = 0}
  local function api()
    return type(ShapeList) == "table" and type(ShapeData) == "table" and type(Vector3) == "table"
      and type(World) == "table" and type(World.GetGroundHeight) == "function"
  end
  local function instance()
    if self.instance then
      local ok, valid = pcall(function() return self.instance.isValid end)
      if ok and valid ~= false then return self.instance end
      self.instance = nil
    end
    local ok, value = pcall(function() return ShapeList.GetInstance(M.NAME) or ShapeList.CreateInstance(M.NAME) end)
    self.instance = ok and value or nil
    return self.instance
  end
  function self:clear(state)
    self.signature = nil; self.incomplete = false; self.edges = 0; self.walls = 0
    if state then self.state = state end
    if self.instance then pcall(function() self.instance.visible = false end) end
  end
  function self:worldChanged() if self.incomplete then self.retry = true end end
  function self:update(position, status, now)
    now = now or 0
    if options.enabled and not options.enabled() then return self:clear("off") end
    if not position then return self:clear("waiting for location") end
    local okRegion, region = pcall(function() return World.IsRegion() end)
    if okRegion and region then return self:clear("hidden in instances") end
    local rows = M.rows(status)
    if not rows then return self:clear("waiting for picker states") end
    if not api() then return self:clear("Shapes API unavailable") end
    local signature = M.signature(rows, position.floor)
    -- Unloaded terrain is retried after a world update (at most every two seconds), or every
    -- fifteen seconds in case that event never arrives.
    local age = now - (self.builtAt or 0)
    local retry = self.incomplete and (self.retry and age >= 2 or age >= 15)
    if signature == self.signature and not retry then return end
    self.retry = false
    local ok, err = pcall(function() self:build(rows, position.floor, now) end)
    self.signature = signature
    if not ok then
      self.state = "build failed: " .. tostring(err):gsub("[%c]", " "):sub(1, 80)
      if self.instance then pcall(function() self.instance.visible = false end) end
    end
  end
  function self:build(rows, floor, now)
    local geometry = M.geometry(rows, function(tx, tz)
      local h, ok = World.GetGroundHeight(floor, tx * M.TILE, tz * M.TILE)
      if ok == false or type(h) ~= "number" or h < 0 then return nil end
      return h
    end)
    self.builtAt = now; self.incomplete = geometry.missing > 0
    self.edges = geometry.edges; self.walls = geometry.walls
    local shape = instance()
    if not shape then self.state = "could not create shape instance"; return end
    if #geometry.positions == 0 or (#geometry.lines == 0 and #geometry.tris == 0) then
      shape.visible = false
      self.state = geometry.missing > 0 and "terrain not loaded yet" or "nothing locked nearby"
      return
    end
    local data = ShapeData.new()
    local positions = {}
    for i, p in ipairs(geometry.positions) do positions[i] = Vector3.new(p[1], p[2], p[3]) end
    data.positions = positions; data.rgba = geometry.rgba; data.lines = geometry.lines
    if #geometry.tris > 0 then data.tris = geometry.tris end
    if shape:SetShapeData(data) == false then self.state = "shape data rejected"; shape.visible = false; return end
    shape.translation = Vector3.new(geometry.originX, 0, geometry.originZ)
    shape.lineWidth = 3; shape.ignoreDepth = false; shape.visible = true
    self.state = "drawn" .. (self.incomplete and " (some terrain not loaded)" or "")
  end
  function self:describe()
    return self.state .. "; edges=" .. self.edges .. " walls=" .. self.walls
  end
  function self:destroy()
    self:clear("stopped")
    if self.instance then pcall(function() ShapeList.DestroyInstance(self.instance) end) end
    self.instance = nil
  end
  return self
end
return M
