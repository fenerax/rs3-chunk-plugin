local M = {}
function M.new(store, callbacks)
  local self={}
  function self:destroy() if self.view then pcall(function() self.view:Destroy() end) end; self.view=nil; self.result=nil end
  function self:message(value) if self.result then pcall(function() self.result.content=value end) end end
  function self:mount(parent)
    self:destroy()
    local view=prettyui.SimpleView.new(parent,{width=parent.width,height=parent.height}); self.view=view
    view:AddTitle("Chunk Picker settings")
    view:AddText("Sends your location, levels and quest status to the picker you choose, and nothing else.")
    view:AddText("Server")
    local entries={}
    -- Manifest-only extension: no server handles or hostnames are hardcoded in settings.
    local ok=pcall(function() for name in pairs(Plugin.urls) do entries[#entries+1]={label=tostring(name),id=tostring(name)} end end)
    table.sort(entries,function(a,b) return a.id<b.id end)
    if not ok or #entries==0 then view:AddText("Manifest URL enumeration unavailable; see Diagnostics")
    else view:AddComboBox({entries=entries,selectedID=store:get("server","String","scratch"),onChange=function(_,name)
      store:set("server","String",name); callbacks.connectionChanged()
    end}) end
    view:AddText("Personal key (visible; keep it out of screenshots)")
    local key=view:AddTextField({text=store:get("personalKey","String",""),placeholder="Paste your personal plugin key",maxLength=256,
      visibility=ui.TextContentVisibilityMode.VISIBLE})
    view:AddSimpleButton("Save",function()
      local text=key:GetText():match("^%s*(.-)%s*$")
      if text:find("[%c]") then self:message("Key must be one line"); return end
      store:set("personalKey","String",text); callbacks.connectionChanged(); self:message("Key saved")
    end)
    view:AddSimpleButton("Test connection",function() callbacks.test(function(message) self:message(message) end) end,{inline=true})
    view:AddSimpleButton("Forget key",function()
      store:forget(); key:SetText("",false); callbacks.connectionChanged(); self:message("Key forgotten")
    end)
    self.result=view:AddText({text="Save your key, then test the connection.",height=48,maxLines=2})
    local choices={}
    for _,entry in ipairs({{"sendSkills","Send my levels"},{"sendQuests","Send my quests"},{"showPanel","Show panel"},{"beta","Beta world"}}) do
      choices[#choices+1]={text=entry[2],value=entry[1],selected=store:get(entry[1],"Bool",true)}
    end
    view:AddCheckboxButton(choices,{onChange=function(_,_,name,selected)
      store:set(name,"Bool",selected); callbacks.settingChanged(name)
    end})
    view:AddText("Progress waits for review in the picker. Sending it never unlocks a chunk.")
  end
  return self
end
return M
