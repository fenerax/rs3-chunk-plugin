-- Chunk Picker beta companion. Own-player observations only; never executes game commands.
local store=require("store").new(PersistentDB)
local location=require("location")
local progress=require("progress").new()
local achievements=require("achievements").new()
local items=require("items").new(store)
local bank=require("bank").new()
local sync=require("sync").new()
local shadingModule=require("shading")
local shading=shadingModule.new({enabled=function() return store:get("shadeChunks","Bool",true) end,
  style=function() return shadingModule.style(function(...) return store:get(...) end) end})
local warning=require("warning").new(store)
local identity=require("identity").new(store)
local netModule=require("net")
local tasksModule=require("tasks")
local tasksWindow=tasksModule.new(store)
-- When the task list was last asked for, and for which reported chunk.
-- tasksFrom is the "All active" row it started at.
local tasksAt,tasksChunk,tasksFrom=-1000,nil,0
local now, alive, position, reason, playing=0,true,nil,"Waiting for login",false
local subscriptions, warned={},{}
local net=netModule.new({sequence=store:get("sequence","Int",0),now=function() return now end,
  saveSequence=function(n) store:set("sequence","Int",n) end})
local panel,settings,settingsWindow,diagnostics
local function guard(name,fn)
  return function(event)
    if not alive then return end
    local ok=pcall(fn,event)
    if not ok and not warned[name] then warned[name]=true; log("Chunk Picker: "..name.." unavailable; see beta diagnostics") end
  end
end
local function subscribe(name,fn)
  local ok=pcall(function()
    local event=Event[name]
    if not event then return end
    local ref="chunk-picker-"..name
    event.Subscribe(ref,guard(name,fn)); subscriptions[#subscriptions+1]={event=event,ref=ref}
  end)
  if not ok then log("Chunk Picker: event unavailable: "..name) end
end
local function permission(name)
  local ok,allowed=pcall(function() return Plugin.HasPermission(PluginPermissions[name or "httpAccess"]) end)
  return ok and allowed==true
end
local permissionEvents={}
local function connection()
  if not permission() then return nil,nil,"Allow web access in the plugin's permissions to connect" end
  local key=store:get("personalKey","String","")
  if key=="" then return nil,nil,"Open plugin Settings, paste your personal key and Save" end
  local paused=identity:check(key)
  if paused then return nil,nil,paused end
  local ok,handle=pcall(function() return Plugin.urls[store:get("server","String","scratch")] end)
  if not ok or not handle then return nil,nil,"Choose a manifest server in Settings" end
  return handle,key
end
local function changed()
  net:reset(); sync:reset()
  -- Resend progress after reconnect/server/world changes; leave its review to the picker.
  if playing then progress:reset(); progress:login(now) end
  achievements:resend(); items:resend(); bank:resend()
end
-- A send switch is on when saved on or never saved. One that can't be read stays off, so a
-- storage hiccup never overrides an opt-out.
local function allowed(name) local ok,value=store:read(name,"Bool"); return ok and value~=false end
local function world()
  -- The public API exposes no current-world number. ID 1 is our fixed companion channel;
  -- beta distinguishes imported/live character copies. No account/character identifier is sent.
  return {id=1,beta=store:get("beta","Bool",true)}
end
-- Sync now reads everything again and reports from the next game tick, without waiting for a
-- move or the timers. A reading the picker already holds isn't sent twice. Presses count ten
-- seconds apart, so they stay inside the picker's rate limit.
local lastDiagnostics,syncNowAt,syncing=nil,-1000,false
local function syncNow()
  if not playing or now-syncNowAt<10 then return end
  syncNowAt=now; syncing=true
  progress:reset(); progress:login(now); achievements:readNow(now); items:readNow(now); bank:readNow(now); bank:resend()
  sync:force(); lastDiagnostics=nil
end
panel=require("panel").new(store,function() end,function() tasksWindow:open() end,syncNow)
local settingsCallbacks={
  connectionChanged=changed,
  openWindow=function() settingsWindow:open() end,
  settingChanged=function(name)
    if name=="showPanel" then panel:build()
    elseif name:find("^shade") then shading:update(position,net.status,now)
    else changed() end
  end,
  test=function(done)
    local handle,key,message=connection()
    if not handle then done(message); return end
    if net.busy then done("Request in progress; try again shortly"); return end
    if not net:ready(now) then done(net.message.."; wait for retry or save a new key"); return end
    done("Testing connection…")
    net:test(now,handle,key,function(ok,_,code)
      done(ok and "Connected to picker" or (net.message.." (HTTP "..tostring(code)..")"))
    end)
  end}
settings=require("settings").new(store,settingsCallbacks)
settingsWindow=require("settings").new(store,settingsCallbacks,{windowed=true})
local function diagnosticLines()
  local lines={
    "Chunk Picker 0.1.0",
    "Stdlib: os="..type(os).." io="..type(io).." utf8="..type(utf8).." load="..type(load),
    "Quests: "..progress.questMethod.."; count="..progress.questCount,
    "Skills: "..progress.skillCount.."/29; quest vars mapped="..tostring(progress.varMapped),
    "World.IsRegion: "..tostring(World and type(World.IsRegion)=="function"),
    "Drag position saved: "..panel.positionSaved,
    "127.0.0.1 reached: "..tostring(net.localhostConnected),
    "Clock: "..(net:epoch(now) and "available" or "awaiting HTTP Date"),
    "World channel: id=1; beta="..tostring(store:get("beta","Bool",true)),
    "Panel: "..(panel.error or "ready").."; storage="..tostring(store.writeOK).."; edge resize="..tostring(panel.resizable),
    "Payload: "..(net.payloadWarning or "within 16 KB"),
    "Achievements: "..achievements:describe().."; picker accepts="..tostring(net:accepts("achievements")),
    "Items: "..items:describe().."; picker accepts="..tostring(net:accepts("items"))
      .."; pouch="..tostring(net:accepts("pouch")).."; belt="..tostring(net:accepts("toolbelt")),
    "Bank: "..bank:describe(now).."; picker accepts="..tostring(net:accepts("bank")),
    "Shading: "..shading:describe(),
    "Tasks window: "..tasksWindow:describe(),
    "Locked warning: "..warning:describe(),
    "Key character: "..identity:describe(),
    "Permissions now: http="..tostring(permission("httpAccess")).." chat="..tostring(permission("chatAccess"))
      .."; chat enum="..tostring(pcall(function() assert(PluginPermissions.chatAccess~=nil) end))
      .."; changes="..(#permissionEvents==0 and "none" or table.concat(permissionEvents,",")),
    "Settings page: "..(#settings.failures==0 and "built" or table.concat(settings.failures,"; ")),
    "Settings window: "..(not settingsWindow.window and (settingsWindow.error and "failed" or "closed")
      or (#settingsWindow.failures==0 and "built" or table.concat(settingsWindow.failures,"; "))
        .."; edge resize="..tostring(settingsWindow.resizable)),
  }
  for _,key in ipairs(require("store").keys) do lines[#lines+1]="DB "..key..": "..store:present(key) end
  -- Whether each server has a key of its own, never the key.
  pcall(function()
    local active,names=store:get("server","String","scratch"),{}
    for name in pairs(Plugin.urls) do names[#names+1]=tostring(name) end
    table.sort(names)
    for i,name in ipairs(names) do
      names[i]=name.."="..store:present(name==active and "personalKey" or (require("identity").parked(name)))
    end
    lines[#lines+1]="Keys by server: "..table.concat(names,", ")
  end)
  for i=1,5 do
    local r=net.history[i]
    lines[#lines+1]=r and ("HTTP "..i..": "..r.code.." timedOut="..tostring(r.timedOut).." failed="..tostring(r.failed).." errorInfo="..r.errorInfo)
      or ("HTTP "..i..": none")
  end
  return lines
end
-- The picker shows these under the key, so the probe goes there instead of the console.
local function pickerLines()
  local lines=diagnosticLines()
  for _,line in ipairs(shading:debugLines()) do lines[#lines+1]=line end
  return lines
end
diagnostics=require("diagnostics").new(diagnosticLines)
local function render()
  local _,_,message=connection()
  local status=not message and net.status or nil
  local text=message or net.message
  if not message and net.lastSync and net.status then text="Synced "..math.floor(now-net.lastSync).." s ago" end
  if not message and syncing then text="Syncing…" end
  if net.payloadWarning then text=net.payloadWarning end
  local ok=pcall(function() panel:render(position,reason,status,text) end)
  if not ok then panel:destroy(); panel:build() end
  tasksWindow:render(not message and net.tasks or nil,message or net.tasksMessage)
  diagnostics:refresh()
end
local function enterGame()
  playing=true; changed(); achievements:login(now); items:login(now); bank:login(now); panel:build()
end
subscribe("SettingsLayerReady",function(e) settings:mount(e.component) end)
subscribe("ContentLayerReady",function(e) diagnostics:mount(e.component) end)
subscribe("OptionalPermissionChanged",function(e)
  if #permissionEvents<8 then permissionEvents[#permissionEvents+1]=tostring(e.permissionName).."="..tostring(e.enabled) end
  if e.permissionName=="httpAccess" then changed(); render() end
  -- Granting chat posts one line straight away, so it's clear it worked.
  if e.permissionName=="chatAccess" and e.enabled then warning:post("chat messages are on.") end
end)
subscribe("GameStateChanged",function(e)
  local state=e.newState
  local numeric=tonumber(state)
  local game=state==30 or (GameState and state==GameState.GAME) or numeric==30
  if game then enterGame()
  else
    playing=false; syncing=false; position=nil; reason="Waiting for login"; net:reset(); sync:reset(); progress:reset(); achievements:reset(); items:reset(); bank:reset(); panel:destroy(); tasksWindow:destroy(); warning:reset(); shading:clear("waiting for login")
  end
end)
subscribe("WindowSizeChanged",function() panel:build(); settingsWindow:build() end)
-- Terrain heights may load after the shading was built.
subscribe("WorldCreated",function() shading:worldChanged() end)
subscribe("WorldUpdated",function() shading:worldChanged() end)
subscribe("SkillTransmit",function(e) if playing then progress:skill(e,now) end end)
subscribe("VarTransmit",function(e) if playing then progress:var(e,now); achievements:var(e,now) end end)
for _,name in ipairs({"InventoryAdded","InventoryUpdated","InventoryRemoved"}) do
  subscribe(name,function(e) if playing then items:inventory(now); bank:inventory(e,now) end end)
end
subscribe("ServerLogic",function()
  if not playing then
    local ok,available=pcall(Player.IsAvailable)
    if ok and available then enterGame() else return end
  end
  position,reason=location.read(); sync:observe(position,now); progress:tick(now); achievements:tick(now); items:tick(now); bank:tick(now); net:tick(now)
  local handle,key=connection()
  local skills,quests=progress:pending(now,allowed("sendSkills"),allowed("sendQuests"))
  quests=net:filterQuests(quests)
  -- Achievement parts travel on their own, and only to a picker that lists them in `accepts`.
  local part=allowed("sendAchievements") and net:accepts("achievements") and achievements:pending(now) or nil
  if part then skills,quests=nil,nil end
  -- Items go after achievements, also alone, and only to a picker that lists them.
  local held,heldKey
  if not part and allowed("sendItems") and net:accepts("items") then
    held,heldKey=items:pending(now,{pouch=net:accepts("pouch"),toolbelt=net:accepts("toolbelt")})
  end
  if held then skills,quests=nil,nil end
  -- Bank parts go last of the three, each alone, under the same items switch.
  local bankPart=not part and not held and allowed("sendItems") and net:accepts("bank") and bank:pending(now) or nil
  if bankPart then skills,quests=nil,nil end
  if handle and sync:due(now,skills~=nil or quests~=nil or part~=nil or held~=nil or bankPart~=nil) and net:ready(now) then
    local reported=position
    -- Diagnostics ride along at most once a minute, never with achievements or items.
    local lines=not part and not held and not bankPart and (not lastDiagnostics or now-lastDiagnostics>=60) and pickerLines() or nil
    if held then items:sent(heldKey,now) end
    net:report(now,handle,key,world(),reported,skills,quests,function(ok,payload,status,code)
      if ok then
        progress:ack(payload.skills,payload.quests); sync:ack(reported,now)
        if net:accepts("achievements") then achievements:sync(status,now) end
        if net:accepts("items") then items:sync(status,now) end
        if bankPart then bank:partSent(bankPart,now) end
        if net:accepts("bank") then bank:sync(status,now) end
        if payload.diagnostics then lastDiagnostics=now end
        -- The ordinary report goes last, after any achievement part and items.
        if not part and not held and not bankPart then syncing=false; sync:force(false) end
      elseif code==400 and payload and payload.achievements then achievements:refused(now)
      elseif code==400 and payload and payload.items then items:refused(now)
      elseif code==400 and payload and payload.bank then bank:refused(now) end
    end,lines,part,held,bankPart)
  elseif handle and tasksWindow:isOpen() and net:ready(now) and net:tasksDue(now) then
    -- "Here" follows the chunk the picker last accepted, so refresh soon after a report moves it.
    local chunk=net.status and net.status.chunkId
    -- More/Back past the rows held asks for that page at once; a repeat of the same ask waits.
    local want=tasksWindow.wantFrom
    if tasksWindow.wanted or now-tasksAt>=tasksModule.REFRESH or (chunk~=tasksChunk and now-tasksAt>=tasksModule.MIN_GAP)
      or (want and (want~=tasksFrom or now-tasksAt>=tasksModule.MIN_GAP)) then
      tasksWindow.wanted=nil; tasksAt=now; tasksChunk=chunk
      tasksFrom=want or (net.tasks and net.tasks.allFrom) or 0
      net:fetchTasks(now,handle,key,function() render() end,tasksFrom)
    end
  end
  shading:update(position,net.status,now); shading:marker()
  local status=net.status
  warning:update(position,position and status and tostring(status.chunkId)==tostring(position.chunk) and status or nil,now)
  warning:roll(status,now)
  render()
end)
-- Draw supplies a documented elapsed time even when the Lua os library is absent.
subscribe("Draw",function(e)
  local delta=tonumber(e.timeDeltaSecs)
  if delta and delta>=0 and delta<60 then now=now+delta end
end)
local lastRender=-1
subscribe("Logic",function()
  net:tick(now)
  if panel.rebuild or math.floor(now)~=lastRender then
    -- PrettyUI moves root in its own hooks. Persist a changed position about once a second,
    -- not on every client tick of a drag.
    lastRender=math.floor(now); panel:savePosition(); panel:ensure(); settingsWindow:tick()
    if playing then tasksWindow:tick() end
    render()
    if playing and store:get("showPanel","Bool",true) and not panel.window then panel:build() end
  end
end)
function PluginShutdown()
  if not alive then return end
  alive=false
  for _,s in ipairs(subscriptions) do pcall(function() s.event.Unsubscribe(s.ref) end) end
  subscriptions={}; net:cancel(); panel:destroy(); tasksWindow:destroy(); warning:destroy(); settings:destroy(); settingsWindow:destroy(); diagnostics:destroy(); shading:destroy()
end
panel:build(); settingsWindow:build()
local ok,available=pcall(Player.IsAvailable)
if ok and available then enterGame() end
diagnostics:console()
render()
