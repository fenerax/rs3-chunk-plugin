-- A short banner when you step into a locked chunk. Warns once per entry: walking around inside
-- the same locked chunk, or standing in it, stays quiet until you leave it.
local M = {}
M.SECONDS, M.WIDTH, M.HEIGHT = 5, 380, 84
function M.new(store)
  local self={warned=nil,shownAt=nil,count=0}
  function self:destroy()
    if self.window then pcall(function() self.window:Destroy() end) end
    self.window=nil; self.shownAt=nil
  end
  function self:show(chunk,name,now,rollable)
    self:destroy()
    local ok=pcall(function()
      local parent=ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
      if not parent then return end
      local w=prettyui.Window.new(parent,{title="Locked chunk",x=math.floor((parent.width-M.WIDTH)/2),y=90,
        width=M.WIDTH,height=M.HEIGHT,scrollable=false,onClose=function() self.dismissed=true end})
      local text=w:AddText({text="You walked into "..(name and (name.." (chunk "..chunk..")") or ("chunk "..chunk))..(rollable and ", which is locked. It can be picked next." or ", which is locked."),
        height=40,maxLines=2})
      text.rgba=0xFF7878FF
      self.window=w; self.shownAt=now; self.count=self.count+1
    end)
    if not ok then self.error="banner failed" end
  end
  -- status: the picker's answer for this chunk (already matched to the current position), or nil.
  function self:update(position,status,now)
    if self.shownAt and (now-self.shownAt>=M.SECONDS or self.dismissed) then self.dismissed=nil; self:destroy() end
    if not position then return end
    local chunk=tostring(position.chunk)
    if not status then return end
    -- "available" chunks can be picked next but are still locked.
    if status.state~="locked" and status.state~="available" then self.warned=nil; return end
    if self.warned==chunk then return end
    self.warned=chunk
    if store:get("warnLocked","Bool",true) then
      local name=type(status.chunkName)=="string" and status.chunkName:gsub("[<>%c]","") or nil
      self:show(chunk,name,now,status.state=="available")
    end
  end
  function self:reset() self.warned=nil; self:destroy() end
  function self:describe()
    return (self.error or "ready").."; shown="..self.count..(self.window and "; on screen" or "")
  end
  return self
end
return M
