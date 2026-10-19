-- Only the local player's map square is read. Never report instance-local coordinates.
local M = {}
local function integer(n, max) return type(n) == "number" and n == math.floor(n) and n >= 0 and n <= max end
function M.fromGrid(grid)
  if not grid then return nil end
  local x, z, floor = grid.mapSquareX, grid.mapSquareZ, grid.level
  if not integer(x, 199) or not integer(z, 199) or not integer(floor, 3) then return nil end
  return {x = x, z = z, floor = floor, chunk = x * 256 + z}
end
function M.read()
  local ok, value, reason = pcall(function()
    if not Player.IsAvailable() then return nil, "Not logged in" end
    local entity = Player.GetEntity()
    if not entity or entity.isValid == false then return nil, "Waiting for location" end
    local grid = entity.coordGrid
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
function M.signature(p) return p and (p.x .. ":" .. p.z .. ":" .. p.floor) or "none" end
return M
