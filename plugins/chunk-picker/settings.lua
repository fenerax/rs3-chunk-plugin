local M = {}
function M.new(store, callbacks)
  local self={failures={}}
  function self:destroy() if self.view then pcall(function() self.view:Destroy() end) end; self.view=nil; self.result=nil end
  function self:message(value) if self.result then pcall(function() self.result.content=value end) end end
  -- Build each section on its own: on beta one failing control used to blank everything below it.
  local function section(name,fn)
    local ok,err=pcall(fn)
    if not ok then self.failures[#self.failures+1]=name..": "..tostring(err):gsub("[%c]"," "):sub(1,100) end
  end
  function self:mount(parent)
    self:destroy(); self.failures={}
    local view=prettyui.SimpleView.new(parent,{width=parent.width,height=parent.height}); self.view=view
    section("intro",function()
      view:AddTitle("Chunk Picker settings")
      view:AddText("Sends your location, levels and quest status to the picker you choose, and nothing else.")
    end)
    local key
    section("server",function()
      local names={}
      -- Manifest-only extension: no server handles or hostnames are hardcoded in settings.
      for name in pairs(Plugin.urls) do names[#names+1]=tostring(name) end
      table.sort(names)
      if #names==0 then view:AddText("No servers in the manifest; see Diagnostics"); return end
      local label=view:AddText("Server: "..store:get("server","String","scratch"))
      -- Plain buttons, not a combo box: the combo box opened empty in the beta settings layer.
      for i,name in ipairs(names) do
        view:AddSimpleButton(name,function()
          store:set("server","String",name); label.content="Server: "..name; callbacks.connectionChanged()
        end,{inline=i>1})
      end
    end)
    section("key",function()
      -- A masked field reads back empty, so the field is visible only while pasting; a saved key is
      -- never put back into it, which keeps it out of later screenshots.
      local saved=store:get("personalKey","String","")
      view:AddText(saved~="" and ("Personal key: saved, ends "..saved:sub(-4)) or "Personal key: not saved")
      local options={text="",placeholder=saved~="" and "Paste a new key to replace it" or "Paste your personal plugin key",maxLength=256}
      local modes=ui and ui.TextContentVisibilityMode
      if modes and modes.VISIBLE~=nil then options.visibility=modes.VISIBLE end
      key=view:AddTextField(options)
    end)
    section("buttons",function()
      view:AddSimpleButton("Save",function()
        if not key then self:message("Key field unavailable; see Diagnostics"); return end
        local text=key:GetText():match("^%s*(.-)%s*$")
        if text=="" then self:message("Paste a key first; the saved key is unchanged"); return end
        if text:find("[%c]") then self:message("Key must be one line"); return end
        store:set("personalKey","String",text); pcall(function() key:SetText("",false) end)
        callbacks.connectionChanged(); self:message("Key saved, ends "..text:sub(-4))
      end)
      view:AddSimpleButton("Test connection",function() callbacks.test(function(message) self:message(message) end) end,{inline=true})
      view:AddSimpleButton("Forget key",function()
        store:forget(); if key then key:SetText("",false) end; callbacks.connectionChanged(); self:message("Key forgotten")
      end,{inline=true})
      self.result=view:AddText({text="Save your key, then test the connection.",height=48,maxLines=2})
    end)
    section("options",function()
      local choices={}
      for _,entry in ipairs({{"sendSkills","Send my levels"},{"sendQuests","Send my quests"},{"showPanel","Show panel"},{"shadeChunks","Shade locked chunks"},{"beta","Beta world"}}) do
        choices[#choices+1]={text=entry[2],value=entry[1],selected=store:get(entry[1],"Bool",true)}
      end
      view:AddCheckboxButton(choices,{onChange=function(_,_,name,selected)
        store:set(name,"Bool",selected); callbacks.settingChanged(name)
      end})
      view:AddText("Progress waits for review in the picker. Sending it never unlocks a chunk.")
    end)
    section("shading",function()
      view:AddTitle("Chunk borders")
      local grid={{text="Lines between locked chunks",value="shadeGrid",selected=store:get("shadeGrid","Bool",true)}}
      view:AddCheckboxButton(grid,{onChange=function(_,_,name,selected)
        store:set(name,"Bool",selected); callbacks.settingChanged(name)
      end})
      -- Buttons rather than combo boxes, as for the server choice.
      for _,row in ipairs({
        {"shadeColours","Colours","classic",{{"classic","Red and amber"},{"colourblind","Blue and orange"},{"subtle","Subtle"}}},
        {"shadeWidth","Line width","normal",{{"thin","Thin"},{"normal","Normal"},{"thick","Thick"}}},
        {"shadeWalls","Glow walls","low",{{"off","Off"},{"low","Low"},{"tall","Tall"}}},
        {"shadeFillLocked","Fill locked chunks","grey",{{"grey","Grey"},{"dark","Dark"},{"tint","Border colour"},{"off","Off"}}},
        {"shadeFillRollable","Fill rollable chunks","tint",{{"tint","Border colour"},{"same","Same as locked"},{"off","Off"}}},
        {"shadeFillStyle","Fill style","haze",{{"haze","Haze box"},{"ground","Ground only"}}},
        {"shadeFillStrength","Fill strength","medium",{{"light","Light"},{"medium","Medium"},{"strong","Strong"},{"solid","Solid"}}},
      }) do
        local key,title,default,choices=row[1],row[2],row[3],row[4]
        local function name(value) for _,c in ipairs(choices) do if c[1]==value then return c[2] end end; return choices[1][2] end
        local label=view:AddText(title..": "..name(store:get(key,"String",default)))
        for i,c in ipairs(choices) do
          view:AddSimpleButton(c[2],function()
            store:set(key,"String",c[1]); label.content=title..": "..c[2]; callbacks.settingChanged(key)
          end,{inline=i>1})
        end
      end
    end)
  end
  return self
end
return M
