-- Pure helpers for the dev tools: chunk maths and the exact cheat command strings.
-- No game calls here, so the tests can check every command before it reaches a console.
local M = {}
M.MAX_SQUARE = 199
M.MAX_COUNT = 2147483647

local function integer(text)
  local n = text and text:match("^%s*(%d+)%s*$")
  return n and #n <= 10 and math.tointeger(tonumber(n)) or nil
end
local function square(n) return n and n >= 0 and n <= M.MAX_SQUARE end

-- Same formula as plugins/chunk-picker/location.lua: chunk = mapSquareX * 256 + mapSquareZ.
function M.chunkOf(x, z) return x * 256 + z end
function M.squareOf(chunk)
  if math.type(chunk) ~= "integer" or chunk < 0 then return nil end
  local x, z = chunk // 256, chunk % 256
  if not square(x) or not square(z) then return nil end
  return x, z
end

-- "12850" (chunk id), "50,50" (map square x,z) or "1,50,50" (floor,x,z, like !tele).
-- Returns {x, z, floor} or nil and a message. floor is nil when the text doesn't give one.
function M.parseTarget(text)
  if type(text) ~= "string" then return nil, "Type a chunk id or x,z" end
  local parts = {}
  for piece in (text .. ","):gmatch("([^,_]*)[,_]") do parts[#parts + 1] = piece end
  if #parts == 1 then
    local x, z = M.squareOf(integer(parts[1]))
    if not x then return nil, "Not a chunk id: x*256+z, with x and z from 0 to 199" end
    return {x = x, z = z}
  end
  local nums = {}
  for i, piece in ipairs(parts) do nums[i] = integer(piece); if not nums[i] then return nil, "Use numbers: x,z or floor,x,z" end end
  if #nums == 2 then nums = {nil, nums[1], nums[2]}
  elseif #nums ~= 3 then return nil, "Use a chunk id, x,z or floor,x,z" end
  local floor, x, z = nums[1], nums[2], nums[3]
  if not square(x) or not square(z) then return nil, "Map square x and z run from 0 to 199" end
  if floor and floor > 3 then return nil, "Floor runs from 0 to 3" end
  return {x = x, z = z, floor = floor}
end

-- One chunk over. North is +z, east is +x. Nil at the map's edge.
M.DIRECTIONS = {N = {0, 1}, E = {1, 0}, S = {0, -1}, W = {-1, 0}}
function M.neighbour(x, z, dir)
  local d = M.DIRECTIONS[dir]
  if not d then return nil end
  local nx, nz = x + d[1], z + d[2]
  if not square(nx) or not square(nz) then return nil end
  return nx, nz
end

-- !tele level,msX,msZ,localX,localZ
function M.tele(floor, x, z, lx, lz)
  for _, v in ipairs({floor, x, z, lx, lz}) do if math.type(v) ~= "integer" or v < 0 then return nil end end
  if floor > 3 or not square(x) or not square(z) or lx > 63 or lz > 63 then return nil end
  return "!tele " .. floor .. "," .. x .. "," .. z .. "," .. lx .. "," .. lz
end

-- configNames are letters, digits and underscores, so a typed name can't carry a second command.
local function configName(text)
  local name = type(text) == "string" and text:match("^%s*([%w_]+)%s*$")
  return name and #name <= 80 and name or nil
end
-- An item typed as a configName, or a numeric id looked up with find(id) -> configName or nil.
function M.itemName(text, find)
  if type(text) ~= "string" or text:match("^%s*$") then return nil, "Type an item name or id" end
  local id = integer(text)
  if id then
    local ok, name = pcall(find, id)
    name = ok and configName(name)
    if name then return name end
    return nil, "No configName found for id " .. id .. "; type its name (pan Obj lists them)"
  end
  local name = configName(text)
  if not name then return nil, "Item names are letters, digits and _ only" end
  return name
end
-- The noted copy of an item. ObjType has no cert link, so this leans on how the cache numbers
-- them: the note sits next to the item (usually id + 1), has the same name, and always stacks.
-- lookup(id) -> {id, name, configName, stackType} or nil. Returns configName, or nil and why.
M.STACK_ALWAYS = 1
function M.notedOf(item, lookup)
  if type(item) ~= "table" or math.type(item.id) ~= "integer" then return nil, "Couldn't read that item" end
  if item.stackType == M.STACK_ALWAYS then return nil, "That item already stacks; use Give" end
  local seen = {}
  for _, near in ipairs({item.id + 1, item.id - 1}) do
    local ok, note = pcall(lookup, near)
    if ok and type(note) == "table" then
      if note.name == item.name and note.stackType == M.STACK_ALWAYS and note.configName ~= item.configName then
        local name = configName(note.configName)
        if name then return name end
      end
      seen[#seen + 1] = near .. "=" .. tostring(note.name) .. "/" .. tostring(note.stackType)
    end
  end
  -- What sat next to it, so a miss can be checked: "1512=Logs/0".
  return nil, "No noted version found for " .. tostring(item.name or item.id)
    .. (#seen > 0 and " (next to it: " .. table.concat(seen, ", ") .. ")" or "")
end
function M.give(name, countText)
  if not configName(name) then return nil, "Bad item name" end
  local count = 1
  if type(countText) == "string" and not countText:match("^%s*$") then
    count = integer(countText)
    if not count or count < 1 or count > M.MAX_COUNT then return nil, "Count runs from 1 to 2147483647" end
  end
  return "!give " .. name .. " " .. count
end

-- "Chunk 12850 · square 50,50 · local 9,56 · floor 0", plus the instance note when mapped back.
function M.positionLine(grid, instance)
  if type(grid) ~= "table" and type(grid) ~= "userdata" then return "Position: waiting" end
  local ok, line = pcall(function()
    local x, z = grid.mapSquareX, grid.mapSquareZ
    return "Chunk " .. M.chunkOf(x, z) .. " · square " .. x .. "," .. z .. " · local " .. grid.localX .. "," .. grid.localZ
      .. " · floor " .. grid.level .. (instance and " (instance, mapped)" or "")
  end)
  return ok and line or "Position: unreadable"
end
return M
