-- Reads the local player's map square (the picker's "chunk") and nothing else.
-- Inside an instance the client's coordinates are instance-local, so they are mapped back to
-- the real map square or not reported at all.
local M = {}
local function integer(n, max) return type(n) == "number" and n == math.floor(n) and n >= 0 and n <= max end

-- Coord grid -> {x, z, floor, chunk}, or nil when it isn't a square on the 200x200 world map.
-- The chunk id packs x and z as x * 256 + z, the same ids the picker uses.
function M.fromGrid(grid)
  if not grid then return nil end
  local x, z, floor = grid.mapSquareX, grid.mapSquareZ, grid.level
  if not integer(x, 199) or not integer(z, 199) or not integer(floor, 3) then return nil end
  return {x = x, z = z, floor = floor, chunk = x * 256 + z}
end

-- Returns the position (or nil) and a short reason the panel shows while there is none.
-- Any client call that throws counts as "Waiting for location".
function M.read()
  local ok, value, reason = pcall(function()
    if not Player.IsAvailable() then return nil, "Not logged in" end
    local entity = Player.GetEntity()
    if not entity or entity.isValid == false then return nil, "Waiting for location" end
    local grid = entity.coordGrid
    -- Without a way to tell instances apart, instance-local squares could be reported as real.
    if not World or type(World.IsRegion) ~= "function" then return nil, "Instance check unavailable" end
    if World.IsRegion() then
      if type(World.GetRegionSourceForCoordGrid) ~= "function" then return nil, "Instance" end
      local mapped, source = pcall(World.GetRegionSourceForCoordGrid, grid)
      if not mapped or not source then return nil, "Instance" end
      grid = source
    end
    return M.fromGrid(grid), "Waiting for location"
  end)
  if not ok then return nil, "Waiting for location" end
  return value, reason
end

-- Text that changes whenever the position does; sync.lua compares these.
function M.signature(p) return p and (p.x .. ":" .. p.z .. ":" .. p.floor) or "none" end
return M
