-- Chunk picker test plugin: shows which chunk you are standing in.
-- Read-only. It sends nothing anywhere and needs no permissions.
-- The picker's chunk id is the game's map square: mapSquareX * 256 + mapSquareZ
-- (Lumbridge is 50, 50 -> 12850).

print("Chunk picker test loaded")

local game_window = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)

local box = ui.GroupBox.new(game_window)
box:SetHeaderLayout(0, 0, 0, 0, 0)
box:SetSize(240, 70)
box:SetPos(0, 0, 0.02, 0.25)
box.stylesheetID = id.StyleSheet.DEFAULT

local label = ui.Text.new(box)
label:SetSize(0, 0, 1.0, 1.0)
label:SetPos(0, 0)
label.font = id.Font.MUSEO_SANS_15PT_REGULAR
label.content = "Chunk: waiting for login"
label:AlignTo(ui.AlignMode.CENTRE)

local lastText

local function chunkText()
  if not Player.IsAvailable() then return "Chunk: not logged in" end
  local grid = Player.GetEntity().coordGrid
  local chunk = grid.mapSquareX * 256 + grid.mapSquareZ
  return formatStr("Chunk {} ({}, {})  floor {}", chunk, grid.mapSquareX, grid.mapSquareZ, grid.level)
end

Event.ServerLogic.Subscribe("chunkPickerTestTick", function()
  local ok, text = pcall(chunkText)
  if not ok then text = "Chunk: error, see console" end
  if text ~= lastText then
    lastText = text
    label.content = text
    log(text)
  end
end)
