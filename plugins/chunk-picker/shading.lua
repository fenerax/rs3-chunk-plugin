-- Draws chunk borders in the 3D world from the picker's nearby states.
-- One persistent ShapeInstance holds every line and wall, so nothing runs per frame:
-- geometry is rebuilt only when the states, floor, toggle or loaded terrain change.
local M = {}
M.NAME = "chunk-picker-shading"
M.TILE = 512                 -- fine units per tile
M.TILES = 64                 -- tiles per map square (chunk)
M.LIFT = 32                  -- keeps ground lines just above the terrain
M.WALL = 320                 -- height of the translucent wall on a state boundary
M.DEBUG = false              -- beta debugging: draw through terrain, show a marker, report coordinates
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
  local out = {positions = {}, rgba = {}, lines = {}, tris = {}, parts = {}, edges = 0, walls = 0, missing = 0,
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
    local p0, l0, t0 = #out.positions, #out.lines, #out.tris
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
    if #out.lines > l0 or #out.tris > t0 then
      out.parts[#out.parts + 1] = {p0 = p0, p1 = #out.positions, l0 = l0, l1 = #out.lines, t0 = t0, t1 = #out.tris}
    end
  end
  local function rank(id) local s = rows[id]; return s and (RANK[s] or 0) or nil end
  local ids = {}
  for id in pairs(rows) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local state = rows[id]
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

-- One shape per edge, anchored at the edge's middle vertex. On beta a single shape covering
-- the whole 5x5 block (4,808 points) drew nothing while a 4-point square drew fine.
function M.split(g)
  local parts = {}
  for _, r in ipairs(g.parts) do
    local mid = g.positions[r.p0 + (r.p1 - r.p0) // 2 + 1]
    local part = {positions = {}, rgba = {}, lines = {}, tris = {},
      originX = g.originX + mid[1], originZ = g.originZ + mid[3]}
    for i = r.p0 + 1, r.p1 do
      local p = g.positions[i]
      part.positions[#part.positions + 1] = {p[1] - mid[1], p[2], p[3] - mid[3]}
      part.rgba[#part.rgba + 1] = g.rgba[i]
    end
    for i = r.l0 + 1, r.l1 do part.lines[#part.lines + 1] = g.lines[i] - r.p0 end
    for i = r.t0 + 1, r.t1 do part.tris[#part.tris + 1] = g.tris[i] - r.p0 end
    parts[#parts + 1] = part
  end
  return parts
end

function M.new(options)
  options = options or {}
  local self = {state = "waiting", edges = 0, walls = 0}
  local function api()
    return type(ShapeList) == "table" and type(ShapeData) == "table" and type(Vector3) == "table"
      and type(World) == "table" and type(World.GetGroundHeight) == "function"
  end
  self.shapes = {}
  local function instance(i)
    local name = M.NAME .. "-" .. i
    local current = self.shapes[i]
    if current then
      local ok, valid = pcall(function() return current.isValid end)
      if ok and valid ~= false then return current end
    end
    local ok, value = pcall(function() return ShapeList.GetInstance(name) or ShapeList.CreateInstance(name) end)
    self.shapes[i] = ok and value or nil
    return self.shapes[i]
  end
  local function hide(from)
    for i = from, #self.shapes do local s = self.shapes[i]; if s then pcall(function() s.visible = false end) end end
  end
  function self:clear(state)
    self.signature = nil; self.incomplete = false; self.edges = 0; self.walls = 0
    if state then self.state = state end
    hide(1)
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
      hide(1)
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
    local parts = M.split(geometry)
    if #parts == 0 then
      hide(1)
      self.state = geometry.missing > 0 and "terrain not loaded yet" or "nothing locked nearby"
      return
    end
    local drawn, rejected = 0, 0
    for i, part in ipairs(parts) do
      local shape = instance(i)
      if not shape then self.state = "could not create shape instance"; hide(i); return end
      local data = ShapeData.new()
      local positions = {}
      for j, p in ipairs(part.positions) do positions[j] = Vector3.new(p[1], p[2], p[3]) end
      data.positions = positions; data.rgba = part.rgba; data.lines = part.lines
      if #part.tris > 0 then data.tris = part.tris end
      if shape:SetShapeData(data) == false then
        rejected = rejected + 1; shape.visible = false
      else
        shape.translation = Vector3.new(part.originX, 0, part.originZ)
        -- Debug builds draw through terrain; normal builds let buildings and trees hide the lines.
        shape.lineWidth = 3; shape.ignoreDepth = M.DEBUG; shape.visible = true
        drawn = drawn + 1
      end
    end
    hide(#parts + 1)
    self.parts = #parts
    self.state = (drawn > 0 and "drawn" or "shape data rejected") .. (self.incomplete and " (some terrain not loaded)" or "")
    local largest = 0
    for _, part in ipairs(parts) do largest = math.max(largest, #part.positions) end
    self.debug = string.format("parts=%d drawn=%d rejected=%d largest=%d points; first at %d,%d",
      #parts, drawn, rejected, largest, parts[1].originX, parts[1].originZ)
  end
  function self:describe()
    return self.state .. "; edges=" .. self.edges .. " walls=" .. self.walls
  end
  -- Temporary: a bright square at the player's feet proves whether instances draw at all,
  -- and the lines below compare its coordinates with the chunk geometry.
  function self:marker()
    if not M.DEBUG or not api() then return end
    pcall(function()
      local p = Player.GetEntity().position
      local floor = Player.GetEntity().coordGrid.level
      local h = World.GetGroundHeight(floor, math.floor(p.x), math.floor(p.z))
      self.player = string.format("player=%.0f,%.0f,%.0f ground=%s floor=%s", p.x, p.y, p.z, tostring(h), tostring(floor))
      local m = ShapeList.GetInstance(M.NAME .. "-marker")
      if not m then
        m = ShapeList.CreateInstance(M.NAME .. "-marker")
        local data = ShapeData.new()
        data.positions = {Vector3.new(-250, 0, -250), Vector3.new(250, 0, -250), Vector3.new(250, 0, 250), Vector3.new(-250, 0, 250)}
        data.lines = {0, 1, 1, 2, 2, 3, 3, 0}
        m:SetShapeData(data)
        m.colour = 0xFFFF00FF; m.lineWidth = 6; m.ignoreDepth = true
      end
      m.translation = Vector3.new(p.x, p.y + 40, p.z)
      self.markerState = "marker valid=" .. tostring(m.isValid) .. " data=" .. tostring(m.hasData) .. " visible=" .. tostring(m.visible)
    end)
  end
  function self:debugLines()
    local lines = {}
    if self.debug then lines[#lines + 1] = "Shading geometry: " .. self.debug end
    if self.player then lines[#lines + 1] = "Shading " .. self.player end
    if self.markerState then lines[#lines + 1] = "Shading " .. self.markerState end
    if self.shapes[1] then
      pcall(function()
        local s, t = self.shapes[1], self.shapes[1].translation
        lines[#lines + 1] = string.format("Shading instance valid=%s data=%s visible=%s depth=%s at=%.0f,%.0f,%.0f",
          tostring(s.isValid), tostring(s.hasData), tostring(s.visible), tostring(s.ignoreDepth), t.x, t.y, t.z)
      end)
    end
    local ok, all = pcall(function() return ShapeList.GetAllInstances() end)
    if ok and type(all) == "table" then lines[#lines + 1] = "Shading instances: " .. #all end
    return lines
  end
  function self:destroy()
    self:clear("stopped")
    for _, s in ipairs(self.shapes) do pcall(function() ShapeList.DestroyInstance(s) end) end
    pcall(function() ShapeList.DestroyInstance(M.NAME .. "-marker") end)
    self.shapes = {}
  end
  return self
end
return M
