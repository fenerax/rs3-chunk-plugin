-- PrettyUI owns native chrome, dragging, flow and bounds. Only the title toggle is placed explicitly.
-- root/closeButton are source-verified PrettyUI fields, not documented API; guard them on beta.
local M = {}
function M.new(store, changed)
  local self={store=store, positionSaved="not moved", collapsed=store:get("collapsed","Bool",false)}
  function self:savePosition()
    if not self.window then return end
    local ok,x,y=pcall(function() return self.window.root.x,self.window.root.y end)
    if not ok or type(x)~="number" or type(y)~="number" then self.positionSaved="PrettyUI root unavailable"; return end
    x=math.floor(x); y=math.floor(y)
    if x~=self.x or y~=self.y then
      self.x=x; self.y=y
      local a=store:set("panelX","Int",x); local b=store:set("panelY","Int",y)
      self.positionSaved=a and b and "yes" or "write failed"
    end
  end
  function self:destroy()
    self:savePosition()
    -- This title control was created directly, so also release its tooltip bindings explicitly.
    if self.toggle then pcall(function() self.toggle:Destroy() end); self.toggle=nil end
    if self.window then pcall(function() self.window:Destroy() end) end
    self.window=nil
  end
  function self:ensure()
    if not self.window then return end
    -- Rebuild only when our window has stopped working (for example after the UI layer is recreated).
    -- Don't compare component handles: the client may return a fresh wrapper on every lookup, which
    -- would rebuild the window every second and interrupt dragging.
    local ok,width=pcall(function() return self.window.root.width end)
    if not ok or type(width)~="number" then self:build() end
  end
  function self:build()
    self:destroy()
    if not store:get("showPanel","Bool",true) then return end
    local ok=pcall(function()
      local parent=ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
      if not parent then self.error="Waiting for UI"; return end
      self.parent=parent
      local width=330
      local savedX=store:get("panelX","Int",math.floor((parent.width-width)/2))
      local savedY=store:get("panelY","Int",40)
      -- Collapsed: just the title bar. 40 left a sliver of empty frame under it on beta.
      local height=self.collapsed and 34 or 190
      local x=math.max(0,math.min(savedX,math.max(0,parent.width-width)))
      local y=math.max(0,math.min(savedY,math.max(0,parent.height-height)))
      local w=prettyui.Window.new(parent,{title="Chunk Picker",x=x,y=y,width=width,height=height,
        minWidth=220,minHeight=30,scrollable=false,onClose=function() store:set("showPanel","Bool",false); changed() end})
      self.window=w; self.x=x; self.y=y
      if x~=savedX or y~=savedY then
        local a=store:set("panelX","Int",x); local b=store:set("panelY","Int",y)
        self.positionSaved=a and b and "yes (clamped)" or "write failed"
      end
      -- Reuse native title area, leaving the rest to AddText flow layout.
      if w.closeButton then w.closeButton.hidden=true end
      self.toggle=prettyui.SimpleButton.new(w.root,self.collapsed and "+" or "-",function()
        self.collapsed=not self.collapsed; store:set("collapsed","Bool",self.collapsed); self.rebuild=true
      end,{x=-32,y=4,xAnchor=1,width=24,height=24,tooltip=self.collapsed and "Expand Chunk Picker" or "Collapse Chunk Picker"})
      if not self.collapsed then
        self.chunk=w:AddText({text="Waiting for location",height=22,maxLines=1})
        self.state=w:AddText({text="Not connected",height=36,maxLines=2})
        self.floor=w:AddText({text="",height=18,maxLines=1})
        self.sync=w:AddText({text="Open plugin Settings to connect",height=36,maxLines=2})
      end
      self.error=nil
    end)
    if not ok then self.error="Panel rebuild failed"; log("Chunk Picker: panel rebuild failed (PrettyUI compatibility)") end
  end
  function self:render(position,reason,status,syncText)
    if self.rebuild then self.rebuild=nil; self:build() end
    if not self.window then return end
    local chunk=position and tostring(position.chunk) or (reason or "Waiting")
    -- Ignore stale responses for another chunk, even during the location debounce.
    local matching=position and status and tostring(status.chunkId)==chunk
    local state=matching and status.state or "unknown"
    local label,colour="Not connected",0xA0A0A0FF
    if state=="unlocked" then label="Unlocked"; colour=0x75D87AFF
    elseif state=="locked" then label="Locked — You're in a locked chunk"; colour=0xFF7878FF
    elseif state=="available" then label="Can be picked next"; colour=0xE5C66BFF
    elseif matching then label="Unknown chunk" end
    if self.collapsed then
      self.window:SetTitle(chunk.." · "..(state=="locked" and "Locked" or label))
    else
      self.window:SetTitle("Chunk Picker")
      local name=matching and status.chunkName
      self.chunk.content=(position and "Chunk " or "")..chunk..(type(name)=="string" and (" · "..name:gsub("[<>%c]","")) or "")
      self.state.content=label; self.state.rgba=colour
      self.floor.content=position and position.floor~=0 and ("Floor "..position.floor) or ""
      self.sync.content=syncText
    end
  end
  return self
end
return M
