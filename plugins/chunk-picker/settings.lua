local shading = require("shading")
local lookcode = require("lookcode")
local identity = require("identity")
local M = {}
-- Swatches offered for every colour; the picker and the hex field cover anything else.
M.PALETTE = {{"Red",0xFF3B30},{"Orange",0xFF9F1C},{"Amber",0xFFB020},{"Yellow",0xFFE14D},
  {"Green",0x4CD964},{"Teal",0x2EC4B6},{"Blue",0x2F80FF},{"Purple",0x9B5DE5},
  {"Pink",0xFF4FA3},{"White",0xFFFFFF},{"Grey",0x8A8A8A},{"Black",0x000000}}
-- What the Colours tab can edit. Fills switch to "custom" when given a colour of their own.
M.TARGETS = {{"lockedBorder","Locked border"},{"rollableBorder","Rollable border"},
  {"lockedFill","Locked fill"},{"rollableFill","Rollable fill"},{"partner","Partner's chunks"}}
function M.hex(rgb) return string.format("#%06X", rgb) end
-- Text drawn in a dark colour vanishes on the dark settings background; lift it towards white.
function M.readable(rgb)
  local r,g,b=rgb>>16&0xFF,rgb>>8&0xFF,rgb&0xFF
  if r*299+g*587+b*114>=90000 then return rgb end
  local function lift(c) return math.floor(c+(255-c)*0.45) end
  return lift(r)<<16|lift(g)<<8|lift(b)
end
-- PrettyUI's resize strips are ten units wide, half of it outside the window, with no cursor change,
-- so they're hard to find. Re-place them after each of its refreshes: further out past the edges and
-- bigger at the bottom corners (the top corners stay small so the close button and title bar still work).
M.GRIP_OUT, M.GRIP_IN, M.GRIP_CORNER = 14, 6, 22
function M.widen(resize)
  if type(resize)~="table" or type(resize._Refresh)~="function" or type(resize.handles)~="table" then return false end
  local base=resize._Refresh
  resize._Refresh=function(self,raise)
    base(self,raise)
    local root,drag=self.root,self.dragState
    -- While dragging, the grabbed strip covers the whole screen; leave everything as PrettyUI set it.
    if not root or not self.handles or (drag and drag.captureExpanded) then return end
    local x,y,w,h=root.x,root.y,root.width,root.height
    local o,i,c=M.GRIP_OUT,M.GRIP_IN,M.GRIP_CORNER
    for key,handle in pairs(self.handles) do
      if not handle.hidden then
        local n,s=key:find("n")~=nil,key:find("s")~=nil
        local e,west=key:find("e")~=nil,key:find("w")~=nil
        local depth=(s and (e or west)) and c or i
        local hx=west and x-o or e and x+w-depth or x+(s and c or i)
        local hw=(west or e) and o+depth or w-2*(s and c or i)
        local hy=n and y-o or s and y+h-depth or y+i
        local hh=(n or s) and o+depth or h-i-c
        handle:SetPos(hx,hy); handle:SetSize(math.max(0,hw),math.max(0,hh))
      end
    end
  end
  pcall(function() resize:Refresh() end)
  return true
end
-- Size buttons in the window, for exact sizes.
M.SIZES = {{"Small",420,480},{"Medium",520,640},{"Large",640,820},{"Full height",560,100000}}
-- The resizable window: smallest size, and the room its title bar and padding take from the tabs.
M.MIN_W, M.MIN_H, M.CHROME = 360, 300, 90
-- options.windowed: build into our own movable, resizable window on the plugin layer instead of the
-- hub's settings page, whose size the hub fixes.
function M.new(store, callbacks, options)
  options=options or {}
  local self={failures={},labels={},previews={},windowed=options.windowed}
  local get=function(...) return store:get(...) end
  local function geometry()
    local ok,x,y,w,h=pcall(function() local r=self.window.root; return r.x,r.y,r.width,r.height end)
    if ok and type(x)=="number" and type(y)=="number" and type(w)=="number" and type(h)=="number" then
      return math.floor(x),math.floor(y),math.floor(w),math.floor(h)
    end
  end
  local function saveGeometry()
    local x,y,w,h=geometry()
    if not x then return end
    store:set("settingsX","Int",x); store:set("settingsY","Int",y); store:set("settingsW","Int",w); store:set("settingsH","Int",h)
  end
  function self:destroy()
    if self.window then saveGeometry() end
    if self.view then pcall(function() self.view:Destroy() end) end
    self.view=nil; self.window=nil; self.pending=nil; self.result=nil; self.labels={}; self.previews={}; self.picker=nil; self.codeField=nil; self.colourResult=nil
  end
  -- The Connection and Colours tabs each have a result line; both show the latest message.
  function self:message(value)
    for _,line in ipairs({self.result,self.colourResult}) do pcall(function() line.content=value end) end
  end
  -- Build each section on its own: on beta one failing control used to blank everything below it.
  local function section(name,fn)
    local ok,err=pcall(fn)
    if not ok then self.failures[#self.failures+1]=name..": "..tostring(err):gsub("[%c]"," "):sub(1,100) end
  end
  -- Current colour of a Colours-tab target, or nil when that fill is off.
  local function current(target)
    local style=shading.style(get)
    if target=="lockedBorder" then return style.rgb[2] elseif target=="rollableBorder" then return style.rgb[1]
    elseif target=="lockedFill" then return style.fill.locked elseif target=="partner" then return style.rgb.partner
    else return style.fill.available end
  end
  local function refresh()
    for key,entry in pairs(self.labels) do
      pcall(function() entry.text.content=entry.title..": "..entry.name(store:get(key,"String",entry.default)) end)
    end
    if self.codeField then pcall(function() self.codeField:SetText(lookcode.encode(get),false) end) end
    for target,entry in pairs(self.previews) do
      pcall(function()
        local rgb=current(target)
        entry.text.content=entry.title..": "..(rgb and M.hex(rgb) or "off")
        entry.text.rgba=M.readable(rgb or 0x808080)*256+0xFF
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
    elseif target=="partner" then
      store:set("shadeRgbPartner","String",M.hex(rgb))
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
        -- The key belongs to the character it was saved on; see identity.lua.
        store:set("keyOwner","String",identity.current() or "")
        callbacks.connectionChanged(); self:message("Key saved, ends "..text:sub(-4))
      end)
      page:AddSimpleButton("Test connection",function() callbacks.test(function(message) self:message(message) end) end,{inline=true})
      page:AddSimpleButton("Forget key",function()
        store:forget(); if key then key:SetText("",false) end; callbacks.connectionChanged(); self:message("Key forgotten")
      end,{inline=true})
      -- After a name change, or to move the key to this character on purpose.
      page:AddSimpleButton("Use key on this character",function()
        local name=identity.current()
        if not name then self:message("Log in to the character first"); return end
        if store:get("personalKey","String","")=="" then self:message("Save a key first"); return end
        store:set("keyOwner","String",name); callbacks.connectionChanged(); self:message("Key now used on this character")
      end)
      self.result=page:AddText({text="Save your key, then test the connection.",height=48,maxLines=2})
    end)
    section("options",function()
      checkboxes(page,{{"sendSkills","Send my levels"},{"sendQuests","Send my quests"},{"showPanel","Show panel"},{"beta","Beta world"}},true)
      page:AddText("Progress waits for review in the picker. Sending it never unlocks a chunk.")
    end)
  end
  local function look(page)
    section("borders",function()
      checkboxes(page,{{"shadeChunks","Show chunk borders and fills"},{"shadeGrid","Lines between locked chunks"},{"warnLocked","Warn when I walk into a locked chunk"},{"warnRoll","Tell me when a roll is waiting"},{"warnChat","Also put these in my chatbox (needs chat permission)"},{"showPartner","Show my partner on the panel"}},true)
      choiceRow(page,"shadeWidth","Line width","normal",{{"thin","Thin"},{"normal","Normal"},{"thick","Thick"}})
      choiceRow(page,"shadeWalls","Glow walls","low",{{"off","Off"},{"low","Low"},{"tall","Tall"}})
    end)
    section("fills",function()
      choiceRow(page,"shadeFillLocked","Fill locked chunks","dark",{{"dark","Dark"},{"grey","Grey"},{"tint","Border colour"},{"off","Off"}})
      choiceRow(page,"shadeFillRollable","Fill rollable chunks","tint",{{"tint","Border colour"},{"same","Same as locked"},{"off","Off"}})
      choiceRow(page,"shadeFillStyle","Fill style","haze",{{"haze","Haze box"},{"ground","Ground only"}})
      choiceRow(page,"shadeFillStrength","Fill strength","medium",{{"light","Light"},{"medium","Medium"},{"strong","Strong"},{"solid","Solid"}})
      choiceRow(page,"shadePartner","Chunks only your partner unlocked","outline",{{"outline","Outline"},{"tint","Light tint"},{"off","Off"}})
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
          {inline=(i-1)%4~=0,colour=M.readable(swatch[2])*256+0xFF,tooltip=M.hex(swatch[2])})
      end
    end)
    section("hex",function()
      local field=page:AddTextField({text="",placeholder="Colour code, e.g. #FF3B30",maxLength=7})
      page:AddSimpleButton("Use code",function()
        local rgb=shading.hex(field:GetText())
        if rgb then setColour(target,rgb); pcall(function() field:SetText("",false) end)
        else self:message("Colour codes look like #FF3B30") end
      end)
    end)
    section("share",function()
      page:AddText("Share your look: copy this code, or paste a partner's code and use it.")
      self.codeField=page:AddTextField({text=lookcode.encode(get),placeholder="Look code, starts CP1",maxLength=80})
      page:AddSimpleButton("Use look code",function()
        local entries=lookcode.decode(self.codeField:GetText())
        if not entries then self:message("That isn't a whole look code (it starts CP1.)"); return end
        for _,e in ipairs(entries) do store:set(e[1],e[2],e[3]) end
        if self.picker then pcall(function() self.picker:SetValue((current(target) or 0x808080)*256+0xFF,false) end) end
        changed("shadeColours"); self:message("Look code used")
      end)
      self.colourResult=page:AddText({text="",height=24,maxLines=1})
    end)
  end
  -- Tabs fill the given height; each page scrolls when its controls don't fit.
  local function fill(view,height)
    local pages
    section("tabs",function()
      if not view.AddTabs then return end
      local tabs=view:AddTabs({{text="Connection"},{text="Look"},{text="Colours"}},
        {scrollable=true,height=math.max(200,height)})
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
  -- The hub's own page: its size is fixed by the hub, so offer the window instead of a title.
  function self:mount(parent)
    self:destroy(); self.failures={}
    local view=prettyui.SimpleView.new(parent,{width=parent.width,height=parent.height}); self.view=view
    section("window button",function()
      view:AddSimpleButton("Open in a bigger window",function() callbacks.openWindow() end,
        {tooltip="Movable and resizable; remembers its size"})
    end)
    fill(view,parent.height-60)
  end
  function self:open()
    store:set("settingsWindow","Bool",true); self.error=nil; self:build()
  end
  function self:build()
    self:destroy(); self.failures={}
    if not store:get("settingsWindow","Bool",false) or self.error then return end
    local ok,err=pcall(function()
      local parent=ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)
      if not parent then return end
      local w=math.max(M.MIN_W,math.min(store:get("settingsW","Int",520),parent.width))
      local h=math.max(M.MIN_H,math.min(store:get("settingsH","Int",640),parent.height))
      local x=math.max(0,math.min(store:get("settingsX","Int",math.floor((parent.width-w)/2)),parent.width-w))
      local y=math.max(0,math.min(store:get("settingsY","Int",math.floor((parent.height-h)/2)),parent.height-h))
      local window=prettyui.Window.new(parent,{title="Chunk Picker settings",x=x,y=y,width=w,height=h,
        resizable=true,minWidth=M.MIN_W,minHeight=M.MIN_H,scrollable=false,
        -- Closing only marks it; tick() tears it down outside PrettyUI's own close handling.
        onClose=function() store:set("settingsWindow","Bool",false) end})
      self.window=window; self.view=window; self.built={x=x,y=y,w=w,h=h}
      self.resizable=window.resize~=nil and (M.widen(window.resize) and "wide" or "narrow") or false
      section("sizes",function()
        for i,size in ipairs(M.SIZES) do
          -- Applied on the next tick: rebuilding inside the button's own click would destroy it mid-call.
          window:AddSimpleButton(size[1],function()
            store:set("settingsW","Int",size[2]); store:set("settingsH","Int",size[3]); self.resized=true
          end,{inline=i>1,tooltip="Resize this window"})
        end
      end)
      fill(window,h-M.CHROME)
    end)
    -- Don't retry a window that failed to build every second; Open tries again.
    if not ok then self.error=tostring(err):gsub("[%c]"," "):sub(1,100); self.failures[#self.failures+1]="window: "..self.error end
  end
  -- Once a second: follow close, moves and resizes. A new size rebuilds the tabs to fill it, but only
  -- after it has held for a second so a resize in progress isn't interrupted.
  function self:tick()
    if not store:get("settingsWindow","Bool",false) then if self.window then self:destroy() end; return end
    if not self.window then if not self.error then self:build() end; return end
    if self.resized then self.resized=nil; self.window=nil; local view=self.view; self.view=nil
      pcall(function() view:Destroy() end); self:build(); return end
    local x,y,w,h=geometry()
    if not x then self:build(); return end
    if x~=self.built.x or y~=self.built.y then
      self.built.x=x; self.built.y=y; store:set("settingsX","Int",x); store:set("settingsY","Int",y)
    end
    if w==self.built.w and h==self.built.h then self.pending=nil
    elseif self.pending and self.pending.w==w and self.pending.h==h then self:build()
    else self.pending={w=w,h=h} end
  end
  return self
end
return M
