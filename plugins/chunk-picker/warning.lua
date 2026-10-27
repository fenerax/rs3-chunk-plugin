-- Short banners: stepping into a locked chunk (once per entry: walking around inside the same
-- locked chunk, or standing in it, stays quiet until you leave it) and a roll waiting for a choice.
local M = {}
M.SECONDS, M.WIDTH, M.HEIGHT = 5, 380, 84
function M.new(store)
  local self={warned=nil,shownAt=nil,count=0,queue={}}
  function self:destroy()
    if self.window then pcall(function() self.window:Destroy() end) end
    self.window=nil; self.shownAt=nil
  end
  function self:show(chunk,name,now,rollable)
    local message="You walked into "..(name and (name.." (chunk "..chunk..")") or ("chunk "..chunk))
      ..(rollable and ", which is locked. It can be picked next." or ", which is locked.")
    self:notice("Locked chunk",message,0xFF7878FF,now)
  end
  -- One banner at a time; a second waits its turn instead of replacing the first.
  function self:notice(title,message,colour,now)
    if self.window then
      if #self.queue<3 then self.queue[#self.queue+1]={title,message,colour} end
      return
    end
    self:destroy()
    local ok=pcall(function()
      local parent=ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
      if not parent then return end
      local w=prettyui.Window.new(parent,{title=title,x=math.floor((parent.width-M.WIDTH)/2),y=90,
        width=M.WIDTH,height=M.HEIGHT,scrollable=false,onClose=function() self.dismissed=true end})
      local text=w:AddText({text=message,height=40,maxLines=2})
      text.rgba=colour
      self.window=w; self.shownAt=now; self.count=self.count+1
    end)
    if not ok then self.error="banner failed" end
  end
  -- status: the picker's answer for this chunk (already matched to the current position), or nil.
  function self:update(position,status,now)
    if self.shownAt and (now-self.shownAt>=M.SECONDS or self.dismissed) then
      self.dismissed=nil; self:destroy()
      local next=table.remove(self.queue,1)
      if next then self:notice(next[1],next[2],next[3],now) end
    end
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
  -- Once per distinct waiting roll; pendingRoll rows come from the picker's status.
  function self:roll(status,now)
    local rows=type(status)=="table" and type(status.pendingRoll)=="table" and status.pendingRoll or nil
    if not rows then return end
    local ids,names={},{}
    for i=1,math.min(#rows,2) do
      local row=rows[i]
      if type(row)=="table" and type(row.chunkId)=="string" then
        ids[#ids+1]=row.chunkId:sub(1,12)
        names[#names+1]=type(row.chunkName)=="string" and row.chunkName:gsub("[<>%c]",""):sub(1,40) or ("chunk "..row.chunkId:sub(1,12))
      end
    end
    local key=table.concat(ids,",")
    if key=="" then self.rollKey=nil; return end
    if key==self.rollKey then return end
    self.rollKey=key
    if store:get("warnRoll","Bool",true) then
      local message="Roll waiting: choose "..table.concat(names," or ").." in the picker."
      self:notice("Roll waiting",message,0xE5C66BFF,now)
    end
  end
  function self:reset() self.warned=nil; self.rollKey=nil; self.queue={}; self:destroy() end
  function self:describe()
    return (self.error or "ready").."; shown="..self.count..(self.window and "; on screen" or "")
  end
  return self
end
return M
