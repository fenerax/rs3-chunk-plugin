-- The plugin's content page: the diagnostic lines from main.lua, plus a button that prints
-- them to the console so a player can copy them into a bug report.
local M = {}
-- `lines` is a function returning the current lines; it is called on every refresh.
function M.new(lines)
  local self = {}
  function self:console()
    for _, line in ipairs(lines()) do log(line) end
  end
  function self:destroy()
    if self.view then pcall(function() self.view:Destroy() end) end
    self.view = nil
    self.labels = nil
  end
  function self:mount(parent)
    self:destroy()
    self.view = prettyui.SimpleView.new(parent, {width = parent.width, height = parent.height})
    self.view:AddTitle("Diagnostics")
    self.view:AddSimpleButton("Copy to console", function() self:console() end)
    self.labels = {}
    for _, line in ipairs(lines()) do
      self.labels[#self.labels + 1] = self.view:AddText({text = line, height = 40, maxLines = 2})
    end
  end
  -- Updates the existing labels in place; lines beyond the ones mounted are not shown.
  function self:refresh()
    if not self.labels then return end
    for i, line in ipairs(lines()) do
      if self.labels[i] then self.labels[i].content = line end
    end
  end
  return self
end
return M
