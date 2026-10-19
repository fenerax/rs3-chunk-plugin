-- Exercise the entry point against a small game/PrettyUI mock; never starts a client.
local values, handlers, logs, windows, views, requests = {}, {}, {}, {}, {}, {}
local allowed=false
PersistentDB={CheckExists=function(_,k) return values[k]~=nil end,Delete=function(_,k) values[k]=nil end}
for _,kind in ipairs({'Bool','Int','String'}) do
  PersistentDB['Get'..kind]=function(_,k) return values[k] end
  PersistentDB['Set'..kind]=function(_,k,v) values[k]=v; return true end
end
Event=setmetatable({},{__index=function(t,k)
  local event={Subscribe=function(ref,fn) handlers[k]={ref=ref,fn=fn} end,Unsubscribe=function(ref)
    assert(handlers[k].ref==ref); handlers[k]=nil
  end}; rawset(t,k,event); return event
end})
local function emit(name,event) assert(handlers[name],name); handlers[name].fn(event or {}) end
local function component(parent,opts)
  opts=opts or {}
  local c={width=opts.width or 100,height=opts.height or 24,x=opts.x or 0,y=opts.y or 0,content=opts.text or '',children={}}
  function c:SetPos(x,y) self.x=x; self.y=y end
  function c:SetSize(w,h) self.width=w; self.height=h end
  function c:Destroy() self.destroyed=true end
  function c:SetText(text) self.content=text end
  function c:GetText() return self.content end
  if parent then parent.children[#parent.children+1]=c end
  return c
end
local function host(parent,opts,isWindow)
  local h=component(nil,opts); h.parent=parent; h.root=component(nil,opts); h.closeButton={}
  h.title=opts.title; h.options=opts
  function h:SetTitle(t) self.title=t end
  function h:AddText(v) return component(self,type(v)=='string' and {text=v} or v) end
  function h:AddTitle(t) return self:AddText(t) end
  function h:AddSimpleButton(text,action) local b=component(self,{text=text}); b.action=action; return b end
  function h:AddTextField(o) return component(self,o) end
  function h:AddComboBox(o) local b=component(self,o); b.options=o; return b end
  function h:AddCheckboxButton(choices,o) self.checkboxes={choices=choices,options=o} end
  if isWindow then windows[#windows+1]=h else views[#views+1]=h end
  return h
end
local root=component(nil,{width=1400,height=900})
ui={Interfaces={GetComponent=function() return root end},TextContentVisibilityMode={VISIBLE=0}}
id={Component={TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP=1},Quest={}}
prettyui={Window={new=function(p,o) return host(p,o,true) end},SimpleView={new=function(p,o) return host(p,o,false) end},
  SimpleButton={new=function(p,text,action,o) local b=component(p,o); b.action=action; return b end}}
PluginPermissions={httpAccess=1}
Plugin={urls={home={},scratch={}},HasPermission=function(p) assert(p==1); return allowed end}
log=function(line) logs[#logs+1]=line end
GameState={GAME=30}
Player={IsAvailable=function() return true end,GetEntity=function() return {coordGrid={mapSquareX=53,mapSquareZ=45,level=0}} end,
  GetLevelUncapped=function() return 10 end,GetXPUncapped=function() return 1000 end}
SkillType={FromID=function(n) return n end}
QuestType={NORMAL=0}
config={Quest={Q={id=1,type=0,name='Mock quest',hasStartedQuest=false,hasFinishedQuest=true,masterQuestVars={}}}}
World={IsRegion=function() return false end}
HTTPRequest={new=function(_,path)
  local r={path=path,AddHeader=function() end,Cancel=function(self) self.cancelled=true end,
    Get=function(self,cb) self.callback=cb end,Post=function(self,body,cb) self.body=body; self.callback=cb end}
  requests[#requests+1]=r; return r
end}
require('main')
assert(#logs>20); assert(#windows>=1)
emit('ServerLogic'); local w=windows[#windows]
assert(w.children[1].content:find('13613')); assert(w.children[4].content:find('Allow web access'))
assert(#requests==0)
w.root:SetPos(400,75); emit('Logic'); assert(values.panelX==400 and values.panelY==75)
w.root.children[1].action(); emit('Logic'); w=windows[#windows]
assert(values.collapsed==true); assert(w.options.height==37); assert(w.title:find('13613'))
w.root.children[1].action(); emit('Logic'); assert(values.collapsed==false)
emit('SettingsLayerReady',{component=root}); local settings=views[#views]
local save,test,forget,key
for _,c in ipairs(settings.children) do
  if c.content=='Save' then save=c elseif c.content=='Test connection' then test=c
  elseif c.content=='Forget key' then forget=c elseif c.GetText and c.content=='' then key=c end
end
assert(save and test and forget and key)
key.content='synthetic'; save.action(); assert(values.personalKey=='synthetic')
allowed=true; emit('OptionalPermissionChanged',{permissionName='httpAccess',enabled=true})
test.action(); assert(#requests==1 and requests[1].path=='/api/plugin/v1/status')
requests[1].callback({responseCode=200,data='{"state":"unknown"}'})
for i=1,100 do emit('Draw',{timeDeltaSecs=0.02}) end
emit('ServerLogic'); emit('Draw',{timeDeltaSecs=1.1}); emit('ServerLogic'); assert(#requests==2)
local req=requests[2]; assert(req.path=='/api/plugin/v1/report')
local body=require('json').decode(req.body); assert(body.position.x==53 and body.world.beta)
assert(body.skills.ATTACK and body.quests.finished[1]=='Mock quest')
req.callback({responseCode=200,data='{"state":"locked","chunkId":"13613","chunkName":"Nardah"}'})
emit('Draw',{timeDeltaSecs=1.1}); emit('Logic'); w=windows[#windows]
assert(w.children[1].content:find('Nardah')); assert(w.children[2].content:find("You're in a locked chunk"))
assert(w.children[2].rgba==0xFF7878FF)
emit('Draw',{timeDeltaSecs=60}); emit('ServerLogic')
-- Begin another request before revoking permission, so cancellation is observable.
test.action(); req=requests[#requests]
allowed=false; emit('OptionalPermissionChanged',{permissionName='httpAccess',enabled=false}); assert(req.cancelled)
req.callback({responseCode=200,data='{"state":"unlocked","chunkId":"13613"}'})
forget.action(); assert(values.personalKey==nil)
emit('ContentLayerReady',{component=root}); assert(views[#views].children[1].content=='Diagnostics')
local old=windows[#windows]; root=component(nil,{width=800,height=600}); emit('WindowSizeChanged'); assert(old.destroyed)
emit('GameStateChanged',{newState=37}); assert(windows[#windows].destroyed)
emit('GameStateChanged',{newState=30}); assert(not windows[#windows].destroyed)
PluginShutdown(); assert(next(handlers)==nil); assert(windows[#windows].destroyed)
assert(views[#views].destroyed); PluginShutdown()
for _,line in ipairs(logs) do assert(not line:find('synthetic')) end
print('lifecycle tests passed')
