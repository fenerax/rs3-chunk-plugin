-- Chunk Picker beta companion. Own-player observations only; never executes game commands.
local store=require("store").new(PersistentDB)
local location=require("location")
local progress=require("progress").new()
local sync=require("sync").new()
local netModule=require("net")
local now, alive, position, reason, playing=0,true,nil,"Waiting for login",false
local subscriptions, warned={},{}
local net=netModule.new({sequence=store:get("sequence","Int",0),now=function() return now end,
  saveSequence=function(n) store:set("sequence","Int",n) end})
local panel,settings,diagnostics
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
local function permission()
  local ok,allowed=pcall(function() return Plugin.HasPermission(PluginPermissions.httpAccess) end)
  return ok and allowed==true
end
local function connection()
  if not permission() then return nil,nil,"Allow web access in the plugin's permissions to connect" end
  local key=store:get("personalKey","String","")
  if key=="" then return nil,nil,"Open plugin Settings, paste your personal key and Save" end
  local ok,handle=pcall(function() return Plugin.urls[store:get("server","String","scratch")] end)
  if not ok or not handle then return nil,nil,"Choose a manifest server in Settings" end
  return handle,key
end
local function changed()
  net:reset(); sync:reset()
  -- Resend progress after reconnect/server/world changes; leave its review to the picker.
  if playing then progress:reset(); progress:login(now) end
end
local function world()
  -- The public API exposes no current-world number. ID 1 is our fixed companion channel;
  -- beta distinguishes imported/live character copies. No account/character identifier is sent.
  return {id=1,beta=store:get("beta","Bool",true)}
end
panel=require("panel").new(store,function() end)
settings=require("settings").new(store,{
  connectionChanged=changed,
  settingChanged=function(name)
    if name=="showPanel" then panel:build()
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
  end})
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
    "Panel: "..(panel.error or "ready").."; storage="..tostring(store.writeOK),
    "Payload: "..(net.payloadWarning or "within 16 KB"),
  }
  for _,key in ipairs(require("store").keys) do lines[#lines+1]="DB "..key..": "..store:present(key) end
  for i=1,5 do
    local r=net.history[i]
    lines[#lines+1]=r and ("HTTP "..i..": "..r.code.." timedOut="..tostring(r.timedOut).." failed="..tostring(r.failed).." errorInfo="..r.errorInfo)
      or ("HTTP "..i..": none")
  end
  for _,line in ipairs(require("probe").lines()) do lines[#lines+1]=line end
  return lines
end
diagnostics=require("diagnostics").new(diagnosticLines)
local function render()
  local _,_,message=connection()
  local status=not message and net.status or nil
  local text=message or net.message
  if not message and net.lastSync and net.status then text="Synced "..math.floor(now-net.lastSync).." s ago" end
  if net.payloadWarning then text=net.payloadWarning end
  local ok=pcall(function() panel:render(position,reason,status,text) end)
  if not ok then panel:destroy(); panel:build() end
  diagnostics:refresh()
end
local function enterGame()
  playing=true; changed(); panel:build()
end
subscribe("SettingsLayerReady",function(e) settings:mount(e.component) end)
subscribe("ContentLayerReady",function(e) diagnostics:mount(e.component) end)
subscribe("OptionalPermissionChanged",function(e)
  if e.permissionName=="httpAccess" then changed(); render() end
end)
subscribe("GameStateChanged",function(e)
  local state=e.newState
  local numeric=tonumber(state)
  local game=state==30 or (GameState and state==GameState.GAME) or numeric==30
  if game then enterGame()
  else
    playing=false; position=nil; reason="Waiting for login"; net:reset(); sync:reset(); progress:reset(); panel:destroy()
  end
end)
subscribe("WindowSizeChanged",function() panel:build() end)
subscribe("SkillTransmit",function(e) if playing then progress:skill(e,now) end end)
subscribe("VarTransmit",function(e) if playing then progress:var(e,now) end end)
subscribe("ServerLogic",function()
  if not playing then
    local ok,available=pcall(Player.IsAvailable)
    if ok and available then enterGame() else return end
  end
  position,reason=location.read(); sync:observe(position,now); progress:tick(now); net:tick(now)
  local handle,key=connection()
  local skills,quests=progress:pending(now,store:get("sendSkills","Bool",true),store:get("sendQuests","Bool",true))
  quests=net:filterQuests(quests)
  if handle and sync:due(now,skills~=nil or quests~=nil) and net:ready(now) then
    local reported=position
    net:report(now,handle,key,world(),reported,skills,quests,function(ok,payload)
      if ok then progress:ack(payload.skills,payload.quests); sync:ack(reported,now) end
    end)
  end
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
    lastRender=math.floor(now); panel:savePosition(); panel:ensure(); render()
    if playing and store:get("showPanel","Bool",true) and not panel.window then panel:build() end
  end
end)
function PluginShutdown()
  if not alive then return end
  alive=false
  for _,s in ipairs(subscriptions) do pcall(function() s.event.Unsubscribe(s.ref) end) end
  subscriptions={}; net:cancel(); panel:destroy(); settings:destroy(); diagnostics:destroy()
end
panel:build()
local ok,available=pcall(Player.IsAvailable)
if ok and available then enterGame() end
diagnostics:console()
render()
