-- A short text code for the chunk look (borders, fills, colours) so players can share a setup.
-- There is no clipboard API: the code is shown in a field to copy, or typed by hand.
-- "CP1" then one letter per choice, then the five colours as hex ("-" when unset).
local M = {}
M.PREFIX = "CP1"
M.CHOICES = {
  {"shadeColours", {classic="c", colourblind="b", subtle="s", custom="x"}, "classic"},
  {"shadeWidth", {thin="t", normal="n", thick="k"}, "normal"},
  {"shadeWalls", {off="o", low="l", tall="t"}, "low"},
  {"shadeFillLocked", {dark="d", grey="g", tint="t", off="o", custom="x"}, "dark"},
  {"shadeFillRollable", {tint="t", same="s", off="o", custom="x"}, "tint"},
  {"shadeFillStrength", {light="l", medium="m", strong="s", solid="d"}, "medium"},
  {"shadeFillStyle", {haze="h", ground="g"}, "haze"},
  {"shadePartner", {outline="o", tint="t", off="f"}, "outline"},
}
M.COLOURS = {"shadeRgbLocked", "shadeRgbRollable", "shadeRgbFillLocked", "shadeRgbFillRollable", "shadeRgbPartner"}
function M.encode(get)
  local letters = {}
  for i, choice in ipairs(M.CHOICES) do
    letters[i] = choice[2][get(choice[1], "String", choice[3])] or choice[2][choice[3]]
  end
  letters[#letters + 1] = get("shadeGrid", "Bool", true) == false and "0" or "1"
  local parts = {M.PREFIX, table.concat(letters)}
  for _, key in ipairs(M.COLOURS) do
    local digits = tostring(get(key, "String", "")):match("^#?(%x%x%x%x%x%x)$")
    parts[#parts + 1] = digits and digits:upper() or "-"
  end
  return table.concat(parts, ".")
end
-- Returns a list of {key, kind, value} to store, or nil for anything that isn't a whole valid code.
function M.decode(text)
  if type(text) ~= "string" then return nil end
  local parts = {}
  for part in text:gsub("%s", ""):gmatch("[^%.]+") do parts[#parts + 1] = part end
  if parts[1] ~= M.PREFIX or #parts ~= 2 + #M.COLOURS or #parts[2] ~= #M.CHOICES + 1 then return nil end
  local out = {}
  for i, choice in ipairs(M.CHOICES) do
    local letter, value = parts[2]:sub(i, i), nil
    for name, code in pairs(choice[2]) do if code == letter then value = name end end
    if not value then return nil end
    out[#out + 1] = {choice[1], "String", value}
  end
  local grid = parts[2]:sub(-1)
  if grid ~= "0" and grid ~= "1" then return nil end
  out[#out + 1] = {"shadeGrid", "Bool", grid == "1"}
  for i, key in ipairs(M.COLOURS) do
    local hex = parts[2 + i]
    -- "-" clears the colour, so using a code reproduces that look exactly.
    if hex == "-" then out[#out + 1] = {key, "String", ""}
    elseif hex:match("^%x%x%x%x%x%x$") then out[#out + 1] = {key, "String", "#" .. hex:upper()}
    else return nil end
  end
  return out
end
return M
