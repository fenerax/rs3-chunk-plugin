local shading = require("shading")
local M = {}
-- Swatches offered for every colour; the picker and the hex field cover anything else.
M.PALETTE = {{"Red",0xFF3B30},{"Orange",0xFF9F1C},{"Amber",0xFFB020},{"Yellow",0xFFE14D},
  {"Green",0x4CD964},{"Teal",0x2EC4B6},{"Blue",0x2F80FF},{"Purple",0x9B5DE5},
  {"Pink",0xFF4FA3},{"White",0xFFFFFF},{"Grey",0x8A8A8A},{"Black",0x000000}}
-- What the Colours tab can edit. Fills switch to "custom" when given a colour of their own.
M.TARGETS = {{"lockedBorder","Locked border"},{"rollableBorder","Rollable border"},
  {"lockedFill","Locked fill"},{"rollableFill","Rollable fill"}}
function M.hex(rgb) return string.format("#%06X", rgb) end
function M.new(store, callbacks)
  local self={failures={},labels={},previews={}}
  local get=function(...) return store:get(...) end
  function self:destroy()
    if self.view then pcall(function() self.view:Destroy() end) end
    self.view=nil; self.result=nil; self.labels={}; self.previews={}; self.picker=nil
  end
  function self:message(value) if self.result then pcall(function() self.result.content=value end) end end
  -- Build each section on its own: on beta one failing control used to blank everything below it.
  local function section(name,fn)
    local ok,err=pcall(fn)
    if not ok then self.failures[#self.failures+1]=name..": "..tostring(err):gsub("[%c]"," "):sub(1,100) end
  end
  -- Current colour of a Colours-tab target, or nil when that fill is off.
  local function current(target)
    local style=shading.style(get)
    if target=="lockedBorder" then return style.rgb[2] elseif target=="rollableBorder" then return style.rgb[1]
    elseif target=="lockedFill" then return style.fill.locked else return style.fill.available end
  end
  local function refresh()
    for key,entry in pairs(self.labels) do
      pcall(function() entry.text.content=entry.title..": "..entry.name(store:get(key,"String",entry.default)) end)
    end
    for target,entry in pairs(self.previews) do
      pcall(function()
        local rgb=current(target)
        entry.text.content=entry.title..": "..(rgb and M.hex(rgb) or "off")
        entry.text.rgba=(rgb or 0x808080)*256+0xFF
      end)
    end
  end
  local function changed(key) refresh(); callbacks.settingChanged(key) end
  local function setColour(target,rgb)
    if target=="lockedBorder" or target=="rollableBorder" then
      -- Keep the other border colour as it looks now when leaving a preset.
      local style=shading.style(get)
      store:set("shadeRgbLocked","String",M.hex(target=="lockedBorder" and rgb or style.rgb[2]))
      store:set("shadeRgbRollable","String",M.hex(target=="rollableBorder" and rgb or style.rgb[1]))
      store:set("shadeColours","String","custom")
    elseif target=="lockedFill" then
      store:set("shadeRgbFillLocked","String",M.hex(rgb)); store:set("shadeFillLocked","String","custom")
    else
      store:set("shadeRgbFillRollable","String",M.hex(rgb)); store:set("shadeFillRollable","String","custom")
    end
    if self.picker then pcall(function() self.picker:SetValue(rgb*256+0xFF,false) end) end
    changed("shadeColours")
  end
  -- A labelled row of buttons that stores one String choice.
  local function choiceRow(page,key,title,default,choices)
    local function name(value) for _,c in ipairs(choices) do if c[1]==value then return c[2] end end; return "Custom" end
    self.labels[key]={text=page:AddText(title..": "..name(store:get(key,"String",default))),title=title,name=name,default=default}
    for i,c in ipairs(choices) do
      page:AddSimpleButton(c[2],function() store:set(key,"String",c[1]); changed(key) end,{inline=i>1})
    end
  end
  local function checkboxes(page,entries,default)
    local choices={}
    for _,entry in ipairs(entries) do
      choices[#choices+1]={text=entry[2],value=entry[1],selected=store:get(entry[1],"Bool",default)}
    end
    page:AddCheckboxButton(choices,{onChange=function(_,_,name,selected)
      store:set(name,"Bool",selected); callbacks.settingChanged(name)
    end})
  end
  local function connection(page)
    local key
    section("intro",function()
      page:AddText("Sends your location, levels and quest status to the picker you choose, and nothing else.")
    end)
    section("server",function()
      local names={}
      -- Manifest-only extension: no server handles or hostnames are hardcoded in settings.
      for name in pairs(Plugin.urls) do names[#names+1]=tostring(name) end
      table.sort(names)
      if #names==0 then page:AddText("No servers in the manifest; see Diagnostics"); return end
      local label=page:AddText("Server: "..store:get("server","String","scratch"))
      -- Plain buttons, not a combo box: the combo box opened empty in the beta settings layer.
      for i,name in ipairs(names) do
        page:AddSimpleButton(name,function()
          store:set("server","String",name); label.content="Server: "..name; callbacks.connectionChanged()
        end,{inline=i>1})
      end
    end)
    section("key",function()
      -- A masked field reads back empty, so the field is visible only while pasting; a saved key is
      -- never put back into it, which keeps it out of later screenshots.
      local saved=store:get("personalKey","String","")
      page:AddText(saved~="" and ("Personal key: saved, ends "..saved:sub(-4)) or "Personal key: not saved")
      local options={text="",placeholder=saved~="" and "Paste a new key to replace it" or "Paste your personal plugin key",maxLength=256}
      local modes=ui and ui.TextContentVisibilityMode
      if modes and modes.VISIBLE~=nil then options.visibility=modes.VISIBLE end
      key=page:AddTextField(options)
    end)
    section("buttons",function()
      page:AddSimpleButton("Save",function()
        if not key then self:message("Key field unavailable; see Diagnostics"); return end
        local text=key:GetText():match("^%s*(.-)%s*$")
        if text=="" then self:message("Paste a key first; the saved key is unchanged"); return end
        if text:find("[%c]") then self:message("Key must be one line"); return end
        store:set("personalKey","String",text); pcall(function() key:SetText("",false) end)
        callbacks.connectionChanged(); self:message("Key saved, ends "..text:sub(-4))
      end)
      page:AddSimpleButton("Test connection",function() callbacks.test(function(message) self:message(message) end) end,{inline=true})
      page:AddSimpleButton("Forget key",function()
        store:forget(); if key then key:SetText("",false) end; callbacks.connectionChanged(); self:message("Key forgotten")
      end,{inline=true})
      self.result=page:AddText({text="Save your key, then test the connection.",height=48,maxLines=2})
    end)
    section("options",function()
      checkboxes(page,{{"sendSkills","Send my levels"},{"sendQuests","Send my quests"},{"showPanel","Show panel"},{"beta","Beta world"}},true)
      page:AddText("Progress waits for review in the picker. Sending it never unlocks a chunk.")
    end)
  end
  local function look(page)
    section("borders",function()
      checkboxes(page,{{"shadeChunks","Show chunk borders and fills"},{"shadeGrid","Lines between locked chunks"}},true)
      choiceRow(page,"shadeWidth","Line width","normal",{{"thin","Thin"},{"normal","Normal"},{"thick","Thick"}})
      choiceRow(page,"shadeWalls","Glow walls","low",{{"off","Off"},{"low","Low"},{"tall","Tall"}})
    end)
    section("fills",function()
      choiceRow(page,"shadeFillLocked","Fill locked chunks","dark",{{"dark","Dark"},{"grey","Grey"},{"tint","Border colour"},{"off","Off"}})
      choiceRow(page,"shadeFillRollable","Fill rollable chunks","tint",{{"tint","Border colour"},{"same","Same as locked"},{"off","Off"}})
      choiceRow(page,"shadeFillStyle","Fill style","haze",{{"haze","Haze box"},{"ground","Ground only"}})
      choiceRow(page,"shadeFillStrength","Fill strength","medium",{{"light","Light"},{"medium","Medium"},{"strong","Strong"},{"solid","Solid"}})
      page:AddText("Pick exact colours on the Colours tab.")
    end)
  end
  local function colours(page)
    local target=M.TARGETS[1][1]
    section("presets",function()
      choiceRow(page,"shadeColours","Border colours","classic",{{"classic","Red and amber"},{"colourblind","Blue and orange"},{"subtle","Subtle"}})
    end)
    section("previews",function()
      -- Each line is drawn in its own colour, so this list doubles as the preview.
      for _,t in ipairs(M.TARGETS) do self.previews[t[1]]={text=page:AddText(t[2]),title=t[2]} end
    end)
    section("target",function()
      local editing=page:AddText("Changing: "..M.TARGETS[1][2])
      for i,t in ipairs(M.TARGETS) do
        page:AddSimpleButton(t[2],function()
          target=t[1]; editing.content="Changing: "..t[2]
          if self.picker then pcall(function() self.picker:SetValue((current(target) or 0x808080)*256+0xFF,false) end) end
        end,{inline=i%2==0})
      end
    end)
    section("picker",function()
      if not page.AddColourPicker then error("this PrettyUI has no colour picker") end
      self.picker=page:AddColourPicker({value=(current(target) or 0x808080)*256+0xFF,title="Chunk colour",
        tooltip="Open the colour picker",onChange=function(_,colour) setColour(target,colour>>8) end})
    end)
    section("swatches",function()
      for i,swatch in ipairs(M.PALETTE) do
        page:AddSimpleButton(swatch[1],function() setColour(target,swatch[2]) end,
          {inline=(i-1)%4~=0,colour=swatch[2]*256+0xFF,tooltip=M.hex(swatch[2])})
      end
    end)
    section("hex",function()
      local field=page:AddTextField({text="",placeholder="Colour code, e.g. #FF3B30",maxLength=7})
      page:AddSimpleButton("Use code",function()
        local rgb=shading.hex(field:GetText())
        if rgb then setColour(target,rgb); pcall(function() field:SetText("",false) end)
        else self:message("Colour codes look like #FF3B30") end
      end,{inline=true})
    end)
  end
  function self:mount(parent)
    self:destroy(); self.failures={}
    local view=prettyui.SimpleView.new(parent,{width=parent.width,height=parent.height}); self.view=view
    view:AddTitle("Chunk Picker settings")
    local pages
    section("tabs",function()
      if not view.AddTabs then return end
      local tabs=view:AddTabs({{text="Connection"},{text="Look"},{text="Colours"}},
        {scrollable=true,height=math.max(200,parent.height-60)})
      pages={tabs:GetPage(1),tabs:GetPage(2),tabs:GetPage(3)}
    end)
    -- No tabs in this PrettyUI: one long page with headings instead.
    pages=pages or {view,view,view}
    connection(pages[1])
    if pages[2]==view then section("heading",function() view:AddTitle("Chunk borders") end) end
    look(pages[2])
    if pages[3]==view then section("heading",function() view:AddTitle("Colours") end) end
    colours(pages[3])
    refresh()
  end
  return self
end
return M
