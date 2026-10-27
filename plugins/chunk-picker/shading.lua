-- Draws chunk borders in the 3D world from the picker's nearby states.
-- Small persistent ShapeInstances (one per edge) hold the lines and walls, so nothing runs per frame:
-- geometry is rebuilt only when the states, floor, style, toggle or loaded terrain change.
local M = {}
M.NAME = "chunk-picker-shading"
M.TILE = 512                 -- fine units per tile
M.TILES = 64                 -- tiles per map square (chunk)
M.LIFT = 32                  -- keeps ground lines just above the terrain
M.WALL = 320                 -- height of the translucent wall on a state boundary
M.DEBUG = false              -- beta debugging: draw through terrain, show a marker, report coordinates
-- Rank decides which side of an edge colours it. Unlocked and unknown draw nothing.
local RANK = {locked = 2, available = 1}
-- Player-chosen looks. Colours are {locked, available}; walls are heights in fine units.
M.COLOURS = {
  classic = {0xFF3B30, 0xFFB020},
  colourblind = {0x2F80FF, 0xFF9F1C},
  subtle = {0xA83A32, 0xB8923E},
}
M.WIDTHS = {thin = 2, normal = 3, thick = 6}
M.WALLS = {off = 0, low = 320, tall = 768}
-- Whole-chunk fills, like the OSRS picker greying out chunks you can't use.
M.FILLS = {grey = 0x8A8A8A, dark = 0x000000}
M.FILL_ALPHA = {light = 0x40, medium = 0x70, strong = 0xA8, solid = 0xE8}
-- Haze: a translucent box (raised lid plus curtains) so trees and buildings inside look greyed too.
-- The client has no API to recolour the scene itself, which is how RuneLite's Region Locker greys chunks.
M.HAZE = 3072                -- lid height in fine units (6 tiles)
M.FILL_STEP = 4              -- tiles between fill samples: 17x17 points per chunk
M.FILL_LIFT = 20             -- below the border lines so they stay on top
-- Chunks only your partner has unlocked (shared access): an outline, a light ground tint, or nothing.
M.PARTNER = 0x2EC4B6
M.PARTNER_MODES = {outline = true, tint = true, off = true}
-- "#RRGGBB" or "RRGGBB" -> 0xRRGGBB; anything else -> nil.
function M.hex(text)
  local digits = type(text) == "string" and text:match("^%s*#?(%x%x%x%x%x%x)%s*$")
  return digits and tonumber(digits, 16) or nil
end
-- The drawing style from the saved settings. `get(key, kind, default)` reads one setting, as
-- store:get does; without it every setting takes its default. Unknown or incomplete values
-- fall back to the defaults, so a bad saved value can't break the drawing.
function M.style(get)
  get = get or function(_, _, default) return default end
  local colours = get("shadeColours", "String", "classic")
  local customLocked = M.hex(get("shadeRgbLocked", "String", ""))
  local customRollable = M.hex(get("shadeRgbRollable", "String", ""))
  if not (M.COLOURS[colours] or colours == "custom" and customLocked and customRollable) then
    colours = "classic"
  end
  local width = get("shadeWidth", "String", "normal")
  if not M.WIDTHS[width] then width = "normal" end
  -- Off by default: on beta walls over a haze box looked odd. Strong haze reads as greyed out.
  local walls = get("shadeWalls", "String", "off")
  if not M.WALLS[walls] then walls = "off" end
  local grid = get("shadeGrid", "Bool", true) ~= false
  local fillLocked = M.hex(get("shadeRgbFillLocked", "String", ""))
  local fillRollable = M.hex(get("shadeRgbFillRollable", "String", ""))
  local locked = get("shadeFillLocked", "String", "dark")
  if not (M.FILLS[locked] or locked == "tint" or locked == "off" or locked == "custom" and fillLocked) then
    locked = "dark"
  end
  local rollable = get("shadeFillRollable", "String", "tint")
  if not (rollable == "same" or rollable == "tint" or rollable == "off"
      or rollable == "custom" and fillRollable) then
    rollable = "tint"
  end
  local strength = get("shadeFillStrength", "String", "strong")
  if not M.FILL_ALPHA[strength] then strength = "strong" end
  local shape = get("shadeFillStyle", "String", "haze")
  if shape ~= "ground" then shape = "haze" end
  local partner = get("shadePartner", "String", "outline")
  if not M.PARTNER_MODES[partner] then partner = "outline" end
  local partnerRgb = M.hex(get("shadeRgbPartner", "String", "")) or M.PARTNER
  -- {locked, available} border colours.
  local border = colours == "custom" and {customLocked, customRollable} or M.COLOURS[colours]
  local fill = {locked = locked == "tint" and border[1] or locked == "custom" and fillLocked
    or M.FILLS[locked]}
  fill.available = rollable == "same" and fill.locked or rollable == "tint" and border[2]
    or rollable == "custom" and fillRollable or nil
  fill.partner = partner == "tint" and partnerRgb or nil
  -- rgb is indexed by RANK (2 locked, 1 available), plus "partner".
  return {rgb = {[2] = border[1], [1] = border[2], partner = partnerRgb},
    width = M.WIDTHS[width], wall = M.WALLS[walls], grid = grid,
    partner = partner,
    -- Bright tints read far heavier than dark ones (beta: amber at medium looked like a solid wall),
    -- so a rollable chunk in its own colour gets half the strength; you still want to see into it.
    fill = fill, fillAlpha = M.FILL_ALPHA[strength], tintAlpha = M.FILL_ALPHA[strength] // 2,
    haze = shape == "haze" and M.HAZE or 0,
    -- Everything above as one string; a changed key rebuilds the geometry.
    key = table.concat({colours, width, walls, tostring(grid), locked, rollable, strength, shape,
      colours == "custom" and border[1] .. "," .. border[2] or "",
      locked == "custom" and fillLocked or "",
      rollable == "custom" and fillRollable or "",
      partner, partner ~= "off" and partnerRgb or ""}, "/")}
end
local ALPHA = {line = 0xE6, grid = 0x80, wallBase = 0x70, wallTop = 0x00}
local function rgba(rgb, alpha) return rgb * 256 + alpha end

-- A map square id (x * 256 + z) on the 200x200 world map.
local function square(id)
  return math.type(id) == "integer" and id >= 0 and id // 256 <= 199 and id % 256 <= 199
end
-- Map square id -> state, from net.lua's checked `nearby` map. Older pickers send only the
-- current chunk, so fall back to it.
function M.rows(status)
  if type(status) ~= "table" then return nil end
  local rows, count = {}, 0
  if type(status.nearby) == "table" then
    for id, state in pairs(status.nearby) do
      if square(id) and type(state) == "string" then
        rows[id] = state
        count = count + 1
      end
    end
  end
  if count > 0 then return rows end
  local id = type(status.chunkId) == "string" and status.chunkId:match("^%d+$")
    and math.tointeger(tonumber(status.chunkId))
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
function M.geometry(rows, height, style)
  style = style or M.style()
  local minX, minZ
  for id in pairs(rows) do
    local x, z = id // 256, id % 256
    minX = math.min(minX or x, x)
    minZ = math.min(minZ or z, z)
  end
  -- parts holds index ranges into positions, lines and tris, one per edge or fill; see M.split.
  local out = {positions = {}, rgba = {}, lines = {}, tris = {}, parts = {},
    edges = 0, walls = 0, fills = 0, missing = 0,
    originX = (minX or 0) * M.TILES * M.TILE, originZ = (minZ or 0) * M.TILES * M.TILE}
  if not minX then return out end
  -- Terrain heights, cached per tile; false marks a tile already found unloaded.
  local cache = {}
  local function ground(tx, tz)
    local key = tx * 16384 + tz
    local h = cache[key]
    if h == nil then
      h = height(tx, tz) or false
      cache[key] = h
    end
    return h or nil
  end
  -- Adds a point and returns its 0-based index.
  local function vertex(tx, tz, y, colour)
    local positions = out.positions
    positions[#positions + 1] = {tx * M.TILE - out.originX, y, tz * M.TILE - out.originZ}
    out.rgba[#out.rgba + 1] = colour
    return #positions - 1
  end
  -- An edge runs 64 tiles from (tx,tz) along +x (dx=1) or +z (dz=1).
  local function edge(tx, tz, dx, dz, rank, boundary)
    if not boundary and not style.grid then return end
    out.edges = out.edges + 1
    local p0, l0, t0 = #out.positions, #out.lines, #out.tris
    local rgb = style.rgb[rank]
    -- Partner outlines mark ownership, not a barrier: no glow wall.
    local wall = boundary and style.wall > 0 and rank ~= "partner"
    local lineColour = rgba(rgb, boundary and ALPHA.line or ALPHA.grid)
    local previous, previousBase, previousTop
    for step = 0, M.TILES do
      local x, z = tx + dx * step, tz + dz * step
      local h = ground(x, z)
      if not h then
        -- An unloaded tile breaks the line; the build is retried once terrain loads.
        out.missing = out.missing + 1
        previous = nil
      else
        local line = vertex(x, z, h + M.LIFT, lineColour)
        local base, top
        if wall then
          base = vertex(x, z, h + M.LIFT // 2, rgba(rgb, ALPHA.wallBase))
          top = vertex(x, z, h + style.wall, rgba(rgb, ALPHA.wallTop))
        end
        if previous then
          local lines = out.lines
          lines[#lines + 1] = previous
          lines[#lines + 1] = line
          if wall then
            -- Both windings, so the wall shows from either side whatever the culling mode.
            local tris = out.tris
            for _, v in ipairs({previousBase, base, top, previousBase, top, previousTop,
                                previousBase, top, base, previousBase, previousTop, top}) do
              tris[#tris + 1] = v
            end
          end
        end
        previous, previousBase, previousTop = line, base, top
      end
    end
    if wall then out.walls = out.walls + 1 end
    if #out.lines > l0 or #out.tris > t0 then
      out.parts[#out.parts + 1] = {p0 = p0, p1 = #out.positions, l0 = l0, l1 = #out.lines,
        t0 = t0, t1 = #out.tris}
    end
  end
  -- A coarse terrain-following sheet over one chunk, both windings like the walls.
  local function fill(id, rgb)
    local step, n = M.FILL_STEP, M.TILES // M.FILL_STEP
    local tx, tz = (id // 256) * M.TILES, (id % 256) * M.TILES
    local tinted = rows[id] == "available" and rgb ~= style.fill.locked
    local partner = rows[id] == "partner"
    local alpha = partner and M.FILL_ALPHA.light // 2 or tinted and style.tintAlpha or style.fillAlpha
    local p0, t0, colour, index = #out.positions, #out.tris, rgba(rgb, alpha), {}
    -- A partner's chunk is open to you: a faint tint on the ground, never a haze box.
    local lift = not partner and style.haze > 0 and style.haze or M.FILL_LIFT
    for i = 0, n do
      for j = 0, n do
        local h = ground(tx + i * step, tz + j * step)
        if h then
          index[i * (n + 1) + j] = vertex(tx + i * step, tz + j * step, h + lift, colour)
        else
          out.missing = out.missing + 1
        end
      end
    end
    local tris = out.tris
    -- Two triangles per grid cell (corners a, b, c, d going round), skipped where a corner is unloaded.
    for i = 0, n - 1 do
      for j = 0, n - 1 do
        local a, b = index[i * (n + 1) + j], index[(i + 1) * (n + 1) + j]
        local c, d = index[(i + 1) * (n + 1) + j + 1], index[i * (n + 1) + j + 1]
        if a and b and c and d then
          for _, v in ipairs({a, b, c, a, c, d, a, c, b, a, d, c}) do tris[#tris + 1] = v end
        end
      end
    end
    if style.haze > 0 and not partner then
      -- Curtains close the box only toward chunks with a different (or no) fill, so neighbouring
      -- locked chunks read as one continuous haze. Chunks beyond the nearby block stay open.
      local cx, cz = id // 256, id % 256
      -- {neighbour id, step x, step z, start x, start z}, in fill-sample units.
      local sides = {{cz > 0 and id - 1, 1, 0, 0, 0}, {cz < 199 and id + 1, 1, 0, 0, n},
        {cx > 0 and id - 256, 0, 1, 0, 0}, {cx < 199 and id + 256, 0, 1, n, 0}}
      for _, side in ipairs(sides) do
        local other = side[1] and rows[side[1]]
        if other ~= nil and style.fill[other] ~= rgb then
          local previousBase, previousTop
          for k = 0, n do
            local x, z = tx + (side[4] + side[2] * k) * step, tz + (side[5] + side[3] * k) * step
            local h = ground(x, z)
            if h then
              local base, top = vertex(x, z, h + M.FILL_LIFT, colour), vertex(x, z, h + style.haze, colour)
              if previousBase then
                for _, v in ipairs({previousBase, base, top, previousBase, top, previousTop,
                                    previousBase, top, base, previousBase, previousTop, top}) do
                  tris[#tris + 1] = v
                end
              end
              previousBase, previousTop = base, top
            else
              out.missing = out.missing + 1
              previousBase = nil
            end
          end
        end
      end
    end
    if #out.tris > t0 then
      out.fills = out.fills + 1
      out.parts[#out.parts + 1] = {p0 = p0, p1 = #out.positions, l0 = #out.lines, l1 = #out.lines,
        t0 = t0, t1 = #out.tris}
    end
  end
  -- A chunk's rank, 0 for states that draw nothing, nil outside the rows.
  local function rank(id)
    local state = rows[id]
    return state and (RANK[state] or 0) or nil
  end
  local ids = {}
  for id in pairs(rows) do ids[#ids + 1] = id end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local state = rows[id]
    local cx, cz = id // 256, id % 256
    local own = RANK[state] or 0
    local tx, tz = cx * M.TILES, cz * M.TILES
    -- Each shared edge belongs to the chunk north or east of it; perimeter edges to the inside chunk.
    -- {start x, start z, dx, dz, neighbour rank, neighbour id}
    local sides = {
      {tx, tz, 1, 0, cz > 0 and rank(id - 1) or nil, cz > 0 and id - 1},              -- south
      {tx, tz, 0, 1, cx > 0 and rank(id - 256) or nil, cx > 0 and id - 256},          -- west
    }
    if not (cz < 199 and rank(id + 1)) then
      sides[#sides + 1] = {tx, tz + M.TILES, 1, 0, nil}                               -- north
    end
    if not (cx < 199 and rank(id + 256)) then
      sides[#sides + 1] = {tx + M.TILES, tz, 0, 1, nil}                               -- east
    end
    for _, side in ipairs(sides) do
      local other = side[5]
      local top = math.max(own, other or 0)
      -- A wall marks where the state changes; matching or unseen neighbours get a faint grid line.
      if top > 0 then edge(side[1], side[2], side[3], side[4], top, other ~= nil and other ~= own)
      elseif other ~= nil and style.partner == "outline"
        and (state == "partner") ~= (rows[side[6]] == "partner") then
        -- Between your own open chunk and one only your partner opened.
        edge(side[1], side[2], side[3], side[4], "partner", true)
      end
    end
  end
  for _, id in ipairs(ids) do
    local rgb = style.fill and style.fill[rows[id]]
    if rgb then fill(id, rgb) end
  end
  return out
end

-- One shape per edge, anchored at the edge's middle vertex. On beta a single shape covering
-- the whole 5x5 block (4,808 points) drew nothing while a 4-point square drew fine.
function M.split(geometry)
  local parts = {}
  for _, range in ipairs(geometry.parts) do
    local mid = geometry.positions[range.p0 + (range.p1 - range.p0) // 2 + 1]
    local part = {positions = {}, rgba = {}, lines = {}, tris = {},
      originX = geometry.originX + mid[1], originZ = geometry.originZ + mid[3]}
    for i = range.p0 + 1, range.p1 do
      local p = geometry.positions[i]
      part.positions[#part.positions + 1] = {p[1] - mid[1], p[2], p[3] - mid[3]}
      part.rgba[#part.rgba + 1] = geometry.rgba[i]
    end
    -- Indices are rebased so each part counts its points from 0.
    for i = range.l0 + 1, range.l1 do part.lines[#part.lines + 1] = geometry.lines[i] - range.p0 end
    for i = range.t0 + 1, range.t1 do part.tris[#part.tris + 1] = geometry.tris[i] - range.p0 end
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
  -- The i-th shape instance, reused while valid; named so a reload finds the old one.
  local function instance(i)
    local name = M.NAME .. "-" .. i
    local current = self.shapes[i]
    if current then
      local ok, valid = pcall(function() return current.isValid end)
      if ok and valid ~= false then return current end
    end
    local ok, value = pcall(function()
      return ShapeList.GetInstance(name) or ShapeList.CreateInstance(name)
    end)
    self.shapes[i] = ok and value or nil
    return self.shapes[i]
  end
  -- Hides shapes from index `from` on; they are kept for reuse rather than destroyed.
  local function hide(from)
    for i = from, #self.shapes do
      local shape = self.shapes[i]
      if shape then pcall(function() shape.visible = false end) end
    end
  end
  function self:clear(state)
    self.signature = nil
    self.incomplete = false
    self.edges = 0
    self.walls = 0
    self.fills = 0
    if state then self.state = state end
    hide(1)
  end
  function self:worldChanged() if self.incomplete then self.retry = true end end
  -- Called every tick and on settings changes; cheap unless something the drawing depends on changed.
  function self:update(position, status, now)
    now = now or 0
    if options.enabled and not options.enabled() then return self:clear("off") end
    if not position then return self:clear("waiting for location") end
    local okRegion, region = pcall(function() return World.IsRegion() end)
    if okRegion and region then return self:clear("hidden in instances") end
    local rows = M.rows(status)
    if not rows then return self:clear("waiting for picker states") end
    if not api() then return self:clear("Shapes API unavailable") end
    local style = options.style and options.style() or M.style()
    local signature = M.signature(rows, position.floor) .. "|" .. style.key
    -- Unloaded terrain is retried after a world update (at most every two seconds), or every
    -- fifteen seconds in case that event never arrives.
    local age = now - (self.builtAt or 0)
    local retry = self.incomplete and (self.retry and age >= 2 or age >= 15)
    if signature == self.signature and not retry then return end
    self.retry = false
    local ok, err = pcall(function() self:build(rows, position.floor, now, style) end)
    self.signature = signature
    if not ok then
      self.state = "build failed: " .. tostring(err):gsub("[%c]", " "):sub(1, 80)
      hide(1)
    end
  end
  function self:build(rows, floor, now, style)
    style = style or M.style()
    local geometry = M.geometry(rows, function(tx, tz)
      local h, ok = World.GetGroundHeight(floor, tx * M.TILE, tz * M.TILE)
      if ok == false or type(h) ~= "number" or h < 0 then return nil end
      return h
    end, style)
    self.builtAt = now
    self.incomplete = geometry.missing > 0
    self.edges = geometry.edges
    self.walls = geometry.walls
    self.fills = geometry.fills
    local parts = M.split(geometry)
    if #parts == 0 then
      hide(1)
      self.state = geometry.missing > 0 and "terrain not loaded yet" or "nothing locked nearby"
      return
    end
    local drawn, rejected = 0, 0
    for i, part in ipairs(parts) do
      local shape = instance(i)
      if not shape then
        self.state = "could not create shape instance"
        hide(i)
        return
      end
      local data = ShapeData.new()
      local positions = {}
      for j, p in ipairs(part.positions) do positions[j] = Vector3.new(p[1], p[2], p[3]) end
      data.positions = positions
      data.rgba = part.rgba
      if #part.lines > 0 then data.lines = part.lines end
      if #part.tris > 0 then data.tris = part.tris end
      if shape:SetShapeData(data) == false then
        rejected = rejected + 1
        shape.visible = false
      else
        shape.translation = Vector3.new(part.originX, 0, part.originZ)
        -- Debug builds draw through terrain; normal builds let buildings and trees hide the lines.
        shape.lineWidth = style.width
        shape.ignoreDepth = M.DEBUG
        shape.visible = true
        drawn = drawn + 1
      end
    end
    hide(#parts + 1)
    self.parts = #parts
    self.state = (drawn > 0 and "drawn" or "shape data rejected")
      .. (self.incomplete and " (some terrain not loaded)" or "")
    local largest = 0
    for _, part in ipairs(parts) do largest = math.max(largest, #part.positions) end
    self.debug = string.format("parts=%d drawn=%d rejected=%d largest=%d points; first at %d,%d",
      #parts, drawn, rejected, largest, parts[1].originX, parts[1].originZ)
  end
  function self:describe()
    return self.state .. "; edges=" .. self.edges .. " walls=" .. self.walls .. " fills=" .. (self.fills or 0)
  end
  -- Temporary: a bright square at the player's feet proves whether instances draw at all,
  -- and the lines below compare its coordinates with the chunk geometry.
  function self:marker()
    if not M.DEBUG or not api() then return end
    pcall(function()
      local p = Player.GetEntity().position
      local floor = Player.GetEntity().coordGrid.level
      local h = World.GetGroundHeight(floor, math.floor(p.x), math.floor(p.z))
      self.player = string.format("player=%.0f,%.0f,%.0f ground=%s floor=%s",
        p.x, p.y, p.z, tostring(h), tostring(floor))
      local marker = ShapeList.GetInstance(M.NAME .. "-marker")
      if not marker then
        marker = ShapeList.CreateInstance(M.NAME .. "-marker")
        local data = ShapeData.new()
        data.positions = {Vector3.new(-250, 0, -250), Vector3.new(250, 0, -250),
          Vector3.new(250, 0, 250), Vector3.new(-250, 0, 250)}
        data.lines = {0, 1, 1, 2, 2, 3, 3, 0}
        marker:SetShapeData(data)
        marker.colour = 0xFFFF00FF
        marker.lineWidth = 6
        marker.ignoreDepth = true
      end
      marker.translation = Vector3.new(p.x, p.y + 40, p.z)
      self.markerState = "marker valid=" .. tostring(marker.isValid) .. " data=" .. tostring(marker.hasData)
        .. " visible=" .. tostring(marker.visible)
    end)
  end
  function self:debugLines()
    local lines = {}
    if self.debug then lines[#lines + 1] = "Shading geometry: " .. self.debug end
    if self.player then lines[#lines + 1] = "Shading " .. self.player end
    if self.markerState then lines[#lines + 1] = "Shading " .. self.markerState end
    if self.shapes[1] then
      pcall(function()
        local shape, at = self.shapes[1], self.shapes[1].translation
        lines[#lines + 1] = string.format(
          "Shading instance valid=%s data=%s visible=%s depth=%s at=%.0f,%.0f,%.0f",
          tostring(shape.isValid), tostring(shape.hasData), tostring(shape.visible),
          tostring(shape.ignoreDepth), at.x, at.y, at.z)
      end)
    end
    local ok, all = pcall(function() return ShapeList.GetAllInstances() end)
    if ok and type(all) == "table" then lines[#lines + 1] = "Shading instances: " .. #all end
    return lines
  end
  function self:destroy()
    self:clear("stopped")
    for _, shape in ipairs(self.shapes) do pcall(function() ShapeList.DestroyInstance(shape) end) end
    pcall(function() ShapeList.DestroyInstance(M.NAME .. "-marker") end)
    self.shapes = {}
  end
  return self
end
return M
