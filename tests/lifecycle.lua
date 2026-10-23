-- Exercise the entry point against a small game/PrettyUI mock; never starts a client.
local values, handlers, logs, windows, views, requests = {}, {}, {}, {}, {}, {}
local allowed=false
local who,valid='Alpha',true -- the logged-in character's display name, and whether the entity is valid
-- broken['get:keyOwner'] (or set:, delete:) makes that storage call throw; a function decides per call.
local broken,lost={},{}
local function db(op,k) local b=broken[op..':'..k]; if b==true or type(b)=='function' and b() then error('storage unavailable') end end
-- Throws on the calls listed (1-based), counting from now.
local function nth(...) local fails,n={},0; for _,i in ipairs({...}) do fails[i]=true end; return function() n=n+1; return fails[n] end end
PersistentDB={CheckExists=function(_,k) db('get',k); return values[k]~=nil end,Delete=function(_,k) db('delete',k); values[k]=nil end}
for _,kind in ipairs({'Bool','Int','String'}) do
  PersistentDB['Get'..kind]=function(_,k) db('get',k); return values[k] end
  -- lost[k]: the write reports success but stores nothing. Like the game, strings stop at a NUL.
  PersistentDB['Set'..kind]=function(_,k,v) db('set',k)
    if kind=='String' and type(v)=='string' then v=v:match('^[^\0]*') end
    if not lost[k] then values[k]=v end; return true end
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
  function h:AddSimpleButton(text,action,o) local b=component(self,{text=text}); b.action=action; b.options=o; return b end
  -- Tab pages share the view's children so tests can find controls the same way.
  function h:AddTabs(tabs) self.tabs=tabs; return {GetPage=function() return self end} end
  function h:AddColourPicker(o)
    local p=component(self,o); p.options=o; p.value=o.value
    function p:SetValue(v) self.value=v end
    self.picker=p; return p
  end
  function h:AddTextField(o) local c=component(self,o); c.placeholder=o.placeholder; return c end
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
PluginPermissions={httpAccess=1,chatAccess=2}
local chat={}; Chat={AddMessage=function(m) chat[#chat+1]=m end}
Plugin={urls={home={},scratch={}},HasPermission=function(p) if p==2 then return true end; assert(p==1); return allowed end}
log=function(line) logs[#logs+1]=line end
GameState={GAME=30}
Player={IsAvailable=function() return true end,GetEntity=function() return {displayName=who,isValid=valid,coordGrid={mapSquareX=53,mapSquareZ=45,level=0}} end,
  GetLevelUncapped=function(s) assert(type(s)=='number'); return 10 end,GetXPUncapped=function(s) assert(type(s)=='number'); return 1000 end}
-- Beta shape: named numeric constants; FromID returns text the Player calls reject.
SkillType={FromID=function(n) return 'skill'..n end}
for n,name in ipairs({'ATTACK','DEFENCE','STRENGTH','HITPOINTS','RANGED','PRAYER','MAGIC','COOKING','WOODCUTTING',
  'FLETCHING','FISHING','FIREMAKING','CRAFTING','SMITHING','MINING','HERBLORE','AGILITY','THIEVING','SLAYER','FARMING',
  'RUNECRAFTING','HUNTER','CONSTRUCTION','SUMMONING','DUNGEONEERING','DIVINATION','INVENTION','ARCHAEOLOGY','NECROMANCY'}) do
  SkillType[name]=n-1
end
QuestType={NORMAL=0}
config={Quest={Q={id=1,type=0,name='Mock quest',hasStartedQuest=false,hasFinishedQuest=true,masterQuestVars={}}},
  Achievement={A={id=11,name='Mock achievement',category=3,subCategory=-1,progress=-2},B={id=12,name='Half done',category=3,subCategory=-1,progress=500}}}
World={IsRegion=function() return false end,GetGroundHeight=function() return 1500,true end}
local shapes={}
Vector3={new=function(x,y,z) return {x=x,y=y,z=z} end}
ShapeData={new=function() return {} end}
ShapeList={GetInstance=function(n) return shapes[n] end,CreateInstance=function(n)
  local i={isValid=true,visible=true,SetShapeData=function(self,d) self.data=d; return true end}; shapes[n]=i; return i
end,DestroyInstance=function(i) i.isValid=false; for k,v in pairs(shapes) do if v==i then shapes[k]=nil end end; return true end}
HTTPRequest={new=function(_,path)
  local r={path=path,AddHeader=function() end,Cancel=function(self) self.cancelled=true end,
    Get=function(self,cb) self.callback=cb end,Post=function(self,body,cb) self.body=body; self.callback=cb end}
  requests[#requests+1]=r; return r
end}
require('main')
assert(#logs>20); assert(#windows>=1)
emit('ServerLogic'); local w=windows[#windows]
assert(w.children[1].content:find('13613')); assert(w.children[5].content:find('Allow web access'))
assert(#requests==0)
w.root:SetPos(400,75); emit('Logic'); assert(values.panelX==400 and values.panelY==75)
w.root.children[1].action(); emit('Logic'); w=windows[#windows]
assert(values.collapsed==true); assert(w.options.height==37); assert(w.title:find('13613'))
w.root.children[1].action(); emit('Logic'); assert(values.collapsed==false)
emit('SettingsLayerReady',{component=root}); local settings=views[#views]
local save,test,forget,key
for _,c in ipairs(settings.children) do
  if c.content=='Save' then save=c elseif c.content=='Test connection' then test=c
  elseif c.content=='Forget key' then forget=c elseif c.placeholder and c.placeholder:find('key') then key=c end
end
assert(save and test and forget and key)
for _,c in ipairs(settings.children) do if c.content=='home' then c.action() end end; assert(values.server=='home')
for _,c in ipairs(settings.children) do if c.content=='scratch' then c.action() end end; assert(values.server=='scratch')save.action(); assert(values.personalKey==nil) -- an empty paste never clears a saved key
key.content='synthetic'; save.action(); assert(values.personalKey=='synthetic'); assert(key.content=='')
local function keyStatus() for _,c in ipairs(settings.children) do if (c.content or ''):find('^Personal key:') then return c.content end end end
assert(keyStatus()=='Personal key: saved, ends etic', keyStatus()) -- the status line follows a Save
assert(values.keyOwner=='Alpha') -- saved on this character
-- Each server button brings back that server's own key, or none.
local function pick(name) for _,c in ipairs(settings.children) do if c.content==name and c.action then c.action() end end end
local function said(text) for _,c in ipairs(settings.children) do if (c.content or ''):find(text,1,true) then return true end end end
pick('home'); assert(values.server=='home' and values.personalKey==nil and keyStatus()=='Personal key: not saved', keyStatus())
assert(said('No key saved for home yet'))
key.content='homekey'; save.action(); assert(values.personalKey=='homekey' and values.keyOwner=='Alpha')
pick('scratch'); assert(values.personalKey=='synthetic' and values.keyOwner=='Alpha' and keyStatus()=='Personal key: saved, ends etic', keyStatus())
assert(said('Using the key saved for scratch') and values.personalKey_home=='homekey')
allowed=true; emit('OptionalPermissionChanged',{permissionName='httpAccess',enabled=true})
test.action(); assert(#requests==1 and requests[1].path=='/api/plugin/v1/status')
requests[1].callback({responseCode=200,data='{"state":"unknown"}'})
for i=1,100 do emit('Draw',{timeDeltaSecs=0.02}) end
emit('ServerLogic'); emit('Draw',{timeDeltaSecs=1.1}); emit('ServerLogic'); assert(#requests==2)
local req=requests[2]; assert(req.path=='/api/plugin/v1/report')
local body=require('json').decode(req.body); assert(body.position.x==53 and body.world.beta)
assert(body.skills.ATTACK and body.quests.finished[1]=='Mock quest')
assert(#body.diagnostics>10 and #body.diagnostics<=80)
for _,line in ipairs(body.diagnostics) do assert(#line<=160 and not line:find('synthetic')) end
local built=false; for _,line in ipairs(body.diagnostics) do if line=='Settings page: built' then built=true end end; assert(built)
req.callback({responseCode=200,data='{"state":"locked","chunkId":"13613","chunkName":"Nardah","unlockedChunkCount":7,"pickableCount":3,'..
  '"partners":[{"name":"Pat<b>","chunkId":"12850","chunkName":"Lumbridge","seenAt":"x"}],'..
  '"pendingRoll":[{"chunkId":"12593","chunkName":"Draynor"},{"chunkId":"12594","chunkName":null}],'..
  '"nearby":[{"chunkId":"13613","state":"locked"},{"chunkId":"13614","state":"unlocked"}]}'})
emit('Draw',{timeDeltaSecs=1.1}); emit('Logic'); w=windows[#windows]
assert(w.children[1].content:find('Nardah')); assert(w.children[2].content:find("You're in a locked chunk"))
assert(w.children[3].content=='7 unlocked · 3 can be picked next')
assert(w.children[4].content=='Patb: Lumbridge (12850); Roll waiting: Draynor or 12594',w.children[4].content)
assert(w.children[2].rgba==0xFF7878FF)
emit('Draw',{timeDeltaSecs=60}); emit('ServerLogic')
local shape=shapes['chunk-picker-shading-1']; assert(shape and shape.visible and #shape.data.positions>0)
local wall=false
for name,s in pairs(shapes) do if name:find('^chunk%-picker%-shading%-%d+$') and s.visible and s.data.tris then wall=true end end
assert(wall) -- Nardah locked beside an unlocked chunk: a wall on their shared edge
-- Walking into a locked chunk shows a banner once, which clears itself.
local function banners() local n,last=0,nil
  for _,b in ipairs(windows) do if b.title=='Locked chunk' then n=n+1; last=b end end; return n,last
end
local function rollBanner() for _,b in ipairs(windows) do if b.title=='Roll waiting' then return b end end end
local n,banner=banners(); assert(n==1 and not banner.destroyed and banner.children[1].content:find('Nardah'))
assert(not rollBanner(),'the roll banner waits for the locked one')
emit('Draw',{timeDeltaSecs=2}); emit('ServerLogic'); assert(banners()==1 and not banner.destroyed)
emit('Draw',{timeDeltaSecs=4}); emit('ServerLogic'); assert(banner.destroyed and banners()==1) -- no repeat while still inside
local roll=rollBanner(); assert(roll and not roll.destroyed and roll.children[1].content:find('Draynor or chunk 12594'))
-- Both went to the chatbox straight away, once each.
assert(#chat==2 and chat[1]:find('Nardah') and chat[2]:find('Draynor or chunk 12594'),table.concat(chat,' | '))
-- Granting chat posts a confirmation line; the diagnostics show the live permission and the change.
emit('OptionalPermissionChanged',{permissionName='chatAccess',enabled=true})
assert(#chat==3 and chat[3]=='Chunk Picker: chat messages are on.')
emit('OptionalPermissionChanged',{permissionName='chatAccess',enabled=false}); assert(#chat==3)
emit('Draw',{timeDeltaSecs=6}); emit('ServerLogic'); assert(roll.destroyed and rollBanner()==roll) -- once per waiting roll
settings.checkboxes.options.onChange(nil,nil,'shadeChunks',false); assert(values.shadeChunks==false and not shape.visible)
settings.checkboxes.options.onChange(nil,nil,'shadeChunks',true); assert(shape.visible)
for _,c in ipairs(settings.children) do if c.content=='Thick' then c.action() end end
assert(values.shadeWidth=='thick' and shapes['chunk-picker-shading-1'].lineWidth==6)
assert(#settings.tabs==3)
local function click(label) local hit=false
  for _,c in ipairs(settings.children) do if c.content==label and c.action then c.action(); hit=true; break end end
  assert(hit,label)
end
-- Swatch for the locked fill: switches that fill to a custom colour and redraws.
click('Locked fill'); click('Blue'); assert(values.shadeFillLocked=='custom' and values.shadeRgbFillLocked=='#2F80FF')
assert(settings.picker.value==0x2F80FFFF)
-- The picker edits whichever colour is selected; leaving a preset keeps the other border colour.
click('Rollable border'); settings.picker.options.onChange(settings.picker,0x11223344)
assert(values.shadeColours=='custom' and values.shadeRgbRollable=='#112233' and values.shadeRgbLocked=='#FF3B30')
-- A typed code works too; nonsense leaves everything alone.
local field
for _,c in ipairs(settings.children) do if c.placeholder and c.placeholder:find('Colour code') then field=c end end
field.content='nope'; click('Use code'); assert(values.shadeRgbRollable=='#112233')
field.content='#abcdef'; click('Use code'); assert(values.shadeRgbRollable=='#ABCDEF')
click('Red and amber'); assert(values.shadeColours=='classic')
-- A partner's look code applies; nonsense is refused with a message.
local codeField
for _,c in ipairs(settings.children) do if c.placeholder and c.placeholder:find('Look code') then codeField=c end end
assert(codeField.content:find('^CP1%.ckox'),codeField.content) -- thick width from earlier
codeField.content='nope'; click('Use look code'); assert(values.shadeColours=='classic')
codeField.content='CP1.bnldtmho1.-.-.-.-.-'; click('Use look code'); assert(values.shadeColours=='colourblind' and values.shadeWidth=='normal')
assert(codeField.content=='CP1.bnldtmho1.-.-.-.-.-')
-- Begin another request before revoking permission, so cancellation is observable.
test.action(); req=requests[#requests]
allowed=false; emit('OptionalPermissionChanged',{permissionName='httpAccess',enabled=false}); assert(req.cancelled)
req.callback({responseCode=200,data='{"state":"unlocked","chunkId":"13613"}'})
forget.action(); assert(values.personalKey==nil and values.keyOwner==nil); assert(keyStatus()=='Personal key: not saved', keyStatus())
assert(values.personalKey_home=='homekey') -- Forget leaves the other server's key
emit('ContentLayerReady',{component=root}); assert(views[#views].children[1].content=='Diagnostics')
local keysLine
for _,c in ipairs(views[#views].children) do
  local text=c.content or ''; assert(not text:find('homekey') and not text:find('synthetic'),'a key value in diagnostics')
  if text:find('^Keys by server:') then keysLine=text end
end
assert(keysLine=='Keys by server: home=set, scratch=not set',keysLine)
local function panelWindow()
  for i=#windows,1,-1 do local t=windows[i].title or ''; if t=='Chunk Picker' or t:find(' · ') then return windows[i] end end
end
local old=panelWindow(); root=component(nil,{width=800,height=600}); emit('WindowSizeChanged'); assert(old.destroyed)
emit('GameStateChanged',{newState=37}); assert(panelWindow().destroyed)
emit('GameStateChanged',{newState=30}); assert(not panelWindow().destroyed)
-- Edge resize: the panel rebuilds at a size that has held for a second, and keeps it.
local pw=panelWindow(); assert(pw.options.resizable and pw.options.width==330 and pw.options.height==236)
pw.root:SetSize(420,300)
emit('Draw',{timeDeltaSecs=1.1}); emit('Logic'); assert(panelWindow()==pw)
emit('Draw',{timeDeltaSecs=1.1}); emit('Logic'); local bigger=panelWindow()
assert(bigger~=pw and pw.destroyed and bigger.options.width==420 and bigger.options.height==300)
assert(values.panelW==420 and values.panelH==300)
-- The hub page can't be resized, so it opens the same tabs in a movable, resizable window.
local function settingsWindow()
  for i=#windows,1,-1 do if windows[i].title=='Chunk Picker settings' then return windows[i] end end
end
assert(not settingsWindow())
click('Open in a bigger window'); local sw=settingsWindow()
assert(sw and sw.options.resizable and values.settingsWindow==true and #sw.tabs==3)
assert(sw.options.width==520 and sw.options.height==600) -- 640 clamped to the 800x600 layer
-- Resizing: rebuilt at the new size once it has held for a second, and remembered.
sw.root:SetSize(700,500)
emit('Draw',{timeDeltaSecs=1.1}); emit('Logic'); assert(settingsWindow()==sw)
emit('Draw',{timeDeltaSecs=1.1}); emit('Logic'); local resized=settingsWindow()
assert(resized~=sw and sw.destroyed and resized.options.width==700 and resized.options.height==500)
assert(values.settingsW==700 and values.settingsH==500)
-- Closing it stays closed after the next tick; reopening uses the remembered size.
resized.options.onClose(); emit('Draw',{timeDeltaSecs=1.1}); emit('Logic')
assert(resized.destroyed and values.settingsWindow==false)
emit('Draw',{timeDeltaSecs=1.1}); emit('Logic'); assert(settingsWindow()==resized)
click('Open in a bigger window'); assert(settingsWindow().options.width==700)
-- No size buttons: the edges resize it.
for _,c in ipairs(settingsWindow().children) do assert(c.content~='Large' and c.content~='Small',c.content) end
settingsWindow().options.onClose(); emit('Draw',{timeDeltaSecs=1.1}); emit('Logic')
-- Tasks: the panel's Tasks button opens a window that reads the picker's saved list.
allowed=true; values.personalKey='synthetic'; emit('OptionalPermissionChanged',{permissionName='httpAccess',enabled=true})
local tasks=require('tasks')
local function tasksWindow() for i=#windows,1,-1 do if (windows[i].title or ''):find('^Chunk tasks') then return windows[i] end end end
local function last() return requests[#requests] end
assert(not tasksWindow())
-- The button sits in the body: the title bar beyond the collapse toggle is PrettyUI's drag layer.
assert(#panelWindow().root.children==1, 'only the collapse toggle in the title bar')
local tasksButton; for _,c in ipairs(panelWindow().children) do if c.content=='Tasks' then tasksButton=c end end
tasksButton.action(); assert(values.tasksWindow==true)
local tw=tasksWindow(); assert(tw and not tw.destroyed)
emit('Draw',{timeDeltaSecs=1.1}); emit('ServerLogic')
assert(values.keyOwner=='Alpha') -- a key with no owner belongs to the first character that uses it
-- Opening asks straight away, before the position report is due.
assert(last().path=='/api/plugin/v1/tasks')
last().callback({responseCode=200,data='{"v":1,"ready":true,"stale":false,"stateRevision":5,"chunkId":"13613","hereKnown":true,'..
  '"here":[{"id":"a","label":"Mine copper","category":"Skills","level":5}],'..
  '"all":[{"id":"a","label":"Mine copper","category":"Skills","level":5},{"id":"b","label":"Visit Nardah","category":"Extra"}],"hereCount":1,"allCount":2}'})
-- The report that follows changes the picker's chunk, which asks for the list again.
emit('Draw',{timeDeltaSecs=1.1}); emit('ServerLogic')
assert(last().path=='/api/plugin/v1/report'); last().callback({responseCode=200,data='{"state":"locked","chunkId":"13613","chunkName":"Nardah"}'})
emit('Draw',{timeDeltaSecs=3.1}); emit('ServerLogic'); assert(last().path=='/api/plugin/v1/tasks')
last().callback({responseCode=200,data='{"v":1,"ready":true,"stale":false,"stateRevision":5,"chunkId":"13613","hereKnown":true,'..
  '"here":[{"id":"a","label":"Mine copper","category":"Skills","level":5}],'..
  '"all":[{"id":"a","label":"Mine copper","category":"Skills","level":5},{"id":"b","label":"Visit Nardah","category":"Extra"}],"hereCount":1,"allCount":2}'})
local reports=#requests
emit('Draw',{timeDeltaSecs=1.1}); emit('Logic'); tw=tasksWindow()
assert(tw.title=='Chunk tasks: here' and tw.children[5].content=='Here: 1 task',tw.children[5].content)
assert(tw.children[6].content=='Skills · Mine copper (5)' and tw.children[7].content=='')
tw.children[2].action(); emit('Draw',{timeDeltaSecs=1.1}); emit('Logic')
assert(tw.title=='Chunk tasks: all active' and values.tasksView=='all' and tw.children[7].content=='Extra · Visit Nardah')
-- Edge resize: a taller window shows more rows, a wider one more of each label; both are kept.
assert(tw.options.resizable and #tw.children==5+tasks.ROWS)
tw.root:SetSize(520,tasks.CHROME+20*tasks.ROW)
emit('Draw',{timeDeltaSecs=1.1}); emit('Logic'); assert(tasksWindow()==tw)
emit('Draw',{timeDeltaSecs=1.1}); emit('Logic'); local tall=tasksWindow()
assert(tall~=tw and tw.destroyed and tall.options.width==520 and #tall.children==5+20,#tall.children)
assert(values.tasksW==520 and values.tasksH==tasks.CHROME+20*tasks.ROW and tall.children[7].content=='Extra · Visit Nardah')
assert(tasks.rowsFor(0)==tasks.MIN_ROWS and tasks.rowsFor(5000)==tasks.MAX_ROWS)
tw=tall
-- No new request inside the refresh interval; a picker without the route never blocks reports.
emit('ServerLogic'); assert(#requests==reports)
emit('Draw',{timeDeltaSecs=16}); emit('ServerLogic')
if last().path=='/api/plugin/v1/report' then last().callback({responseCode=200,data='{"state":"locked","chunkId":"13613"}'}); emit('Draw',{timeDeltaSecs=1.1}); emit('ServerLogic') end
assert(last().path=='/api/plugin/v1/tasks'); last().callback({responseCode=401,data='{"message":"no"}'})
emit('Draw',{timeDeltaSecs=1.1}); emit('Logic')
assert(tw.children[5].content:find('no in%-game task list'),tw.children[5].content)
local count=#requests; emit('Draw',{timeDeltaSecs=20}); emit('ServerLogic')
assert(#requests==count or last().path=='/api/plugin/v1/report','a refused task list waits five minutes')
-- Another character on this PC: everything pauses until the key is moved on purpose.
-- Draw only counts deltas under 60 s, so time moves in 10 s steps.
local function advance(seconds) for _=1,math.ceil(seconds/10) do emit('Draw',{timeDeltaSecs=10}); emit('ServerLogic') end end
local function quiet(seconds,why) local n=#requests; advance(seconds); assert(#requests==n,why) end
local function sends(why) local n=#requests; advance(70)
  for _=1,3 do local r=last(); r.callback({responseCode=200,data='{"state":"locked","chunkId":"13613"}'}); advance(10) end
  assert(#requests>n,why)
end
local function settingsLine(text) for _,c in ipairs(settings.children) do if (c.content or ''):find(text) then return true end end end
advance(70); local inflight=last()
who='Bravo'
-- The reply to a request sent before the switch still lands, and nothing follows it.
inflight.callback({responseCode=200,data='{"state":"locked","chunkId":"13613"}'})
quiet(400,'no report or task fetch for another character')
emit('Logic'); assert(panelWindow().children[5].content:find('another character'),panelWindow().children[5].content)
local before=#requests; test.action(); assert(#requests==before)
who=''; quiet(70,'an empty name waits'); emit('Logic'); assert(panelWindow().children[5].content:find('Waiting for your character'))
who,valid='Alpha',false; quiet(70,'an invalid entity waits'); valid=true
who=nil; click('Use key on this character'); assert(values.keyOwner=='Alpha') -- no name yet: unchanged
quiet(70,'still paused')
who='Bravo'; click('Use key on this character'); assert(values.keyOwner=='Bravo')
sends('reports resume after re-binding')
-- Storage that can't be read or written never lets another character through.
broken['get:keyOwner']=true; who='Charlie'; quiet(70,'unreadable owner pauses'); assert(values.keyOwner=='Bravo')
broken['get:keyOwner']=nil; quiet(70,"still Bravo's key")
values.keyOwner=nil; broken['set:keyOwner']=true; quiet(70,'an unbound key whose binding fails to save pauses')
assert(values.keyOwner==nil); broken['set:keyOwner']=nil
sends('the binding saves on a later try'); assert(values.keyOwner=='Charlie')
-- A Forget that can't delete the key keeps its owner, says so, and the key stays bound.
broken['delete:personalKey']=true; forget.action()
assert(values.personalKey=='synthetic' and values.keyOwner=='Charlie' and settingsLine("Couldn't remove the key"))
broken['delete:personalKey']=nil; who='Delta'; quiet(70,'a key that survived Forget stays with its owner')
-- A key read that works once and then fails can't skip the owner check.
for _=1,4 do broken['get:personalKey']=nth(3,4); local n=#requests; test.action(); assert(#requests==n,"flaky key read sent Charlie's key as Delta") end
broken['get:personalKey']=nil
-- A Save that stops partway never leaves a key with the wrong character.
broken['set:keyOwner']=true; key.content='second'; save.action()
assert(values.personalKey=='synthetic' and values.keyOwner=='Charlie' and settingsLine("Couldn't save the key"))
broken['set:keyOwner']=nil; quiet(70,"the old key is still Charlie's")
broken['set:personalKey']=true; key.content='second'; save.action(); broken['set:personalKey']=nil
assert(values.personalKey=='synthetic' and values.keyOwner~='Delta' and settingsLine("Couldn't save the key"))
quiet(70,'Delta never gets the old key'); who='Charlie'; quiet(70,'nor does Charlie while the save is unfinished')
emit('Logic'); assert(panelWindow().children[5].content:find('save the key again'),panelWindow().children[5].content)
who='Delta'; key.content='second'; save.action(); assert(values.personalKey=='second' and values.keyOwner=='Delta')
sends('a repeated Save works')
who='Charlie'; broken['set:keyOwner']=nth(2); key.content='third'; save.action(); broken['set:keyOwner']=nil
assert(values.personalKey=='third' and values.keyOwner~='Charlie' and settingsLine('not tied to this character'))
quiet(70,'the new key waits'); who='Delta'; quiet(70,'and the old owner never sends it')
click('Use key on this character'); assert(values.keyOwner~='Delta' and settingsLine('Save the key again first'))
-- Nor when the owner can't be read at that moment: it may be an unfinished Save.
broken['get:keyOwner']=true; click('Use key on this character'); broken['get:keyOwner']=nil
assert(values.keyOwner==require('identity').PENDING,'rebind over an unreadable owner'); quiet(70,'and nothing is sent once reads recover')
local before=#requests; test.action(); assert(#requests==before)
who='Charlie'; key.content='third'; save.action(); assert(values.keyOwner=='Charlie')
sends('the key works once Save finishes')
-- Writes that claim success but don't stick, and read-backs that fail, are caught too.
lost.personalKey=true; key.content='fourth'; save.action(); lost.personalKey=nil
assert(values.personalKey=='third' and values.keyOwner~='Charlie' and settingsLine("Couldn't save the key"))
quiet(70,'a key write that did not stick pauses')
key.content='fourth'; save.action(); assert(values.personalKey=='fourth' and values.keyOwner=='Charlie'); sends('recovered')
lost.keyOwner=true; who='Delta'; key.content='fifth'; save.action(); lost.keyOwner=nil
assert(values.personalKey=='fourth' and values.keyOwner=='Charlie' and settingsLine("Couldn't save the key"))
quiet(70,"Delta never gets Charlie's key")
-- The key's read-back fails (each read is CheckExists then Get).
broken['get:personalKey']=nth(1,2); key.content='fifth'; save.action(); broken['get:personalKey']=nil
assert(values.keyOwner~='Delta' and values.keyOwner~='Charlie' and settingsLine("Couldn't save the key"))
quiet(70,'a failed key read-back pauses Delta'); who='Charlie'; quiet(70,'and Charlie')
who='Delta'; broken['get:keyOwner']=nth(3); key.content='fifth'; save.action(); broken['get:keyOwner']=nil
-- The owner write may have landed; either way the key is only ever pending or Delta's.
assert(values.personalKey=='fifth' and (values.keyOwner=='Delta' or values.keyOwner==require('identity').PENDING) and settingsLine('not tied'))
key.content='fifth'; save.action(); assert(values.keyOwner=='Delta'); sends('and Save recovers')
-- Achievements go only to a picker that lists them in `accepts`, each part in its own report.
local json=require('json')
local function bodies(from) local out={}
  for i=from,#requests do local b=requests[i].body; if b then out[#out+1]=json.decode(b) end end
  return out
end
for _,b in ipairs(bodies(1)) do assert(b.achievements==nil,'a picker that never listed achievements got them') end
-- Advance in 10 s steps, answering each new request with reply(body).
local function pump(seconds,reply) local from=#requests+1
  for _=1,math.ceil(seconds/10) do
    advance(10)
    for i=from,#requests do local r=requests[i]
      if r.callback and not r.answered then r.answered=true; r.callback(reply(r.body and json.decode(r.body))) end
    end
  end
  return bodies(from)
end
-- A fake picker that assembles parts like the real one and reports how far it got.
-- A set it already finished is acknowledged as complete, not assembled again.
local held,done=nil,{}
local function picker(b)
  local a=b and b.achievements
  if a and done[a.snapshot] then held={snapshot=a.snapshot,received=a.parts,parts=a.parts}
  elseif a and a.part==1 then held={snapshot=a.snapshot,received=1,parts=a.parts}
  elseif a and held and held.snapshot==a.snapshot and held.parts==a.parts and a.part==held.received+1 then held.received=a.part end
  if held and held.received==held.parts then done[held.snapshot]=true end
  return {responseCode=200,data=json.encode({state='locked',chunkId='13613',accepts=json.array({'achievements'}),achievements=held})}
end
local function withAchievements(list) local out={} for _,b in ipairs(list) do if b.achievements then out[#out+1]=b end end return out end
local got=withAchievements(pump(120,picker))
assert(#got==1,'one part for a small set: '..#got)
local a=got[1].achievements
assert(a.part==1 and a.parts==1 and #a.complete==1 and a.complete[1][1]==11 and a.complete[1][2]=='Mock achievement')
assert(got[1].diagnostics==nil and got[1].skills==nil and got[1].quests==nil,'a part travels alone')
assert(#withAchievements(pump(700,picker))==0,'an unchanged set is not sent again')
-- A picker restart forgets the set; the plugin notices from status and sends it once more.
held,done=nil,{}; assert(#withAchievements(pump(120,picker))==1,'resent after a picker restart')
-- A refusal backs off; a new completion waits out the back-off.
config.Achievement.B.progress=-2
local refuse=function(b) return b and b.achievements and {responseCode=400,data='{"message":"bad field"}'} or picker(b) end
got={}; for _=1,70 do got=withAchievements(pump(10,refuse)); if #got>0 then break end end
assert(#got>=1 and got[1].achievements.complete[2][1]==12,'the new completion is offered')
assert(#withAchievements(pump(1500,picker))==0,'a refused set waits half an hour')
assert(#withAchievements(pump(400,picker))>=1,'then tries again')
-- Turning the setting off stops them, even for a new set.
values.sendAchievements=false; config.Achievement.C={id=13,name='Third',category=3,subCategory=-1,progress=-2}
assert(#withAchievements(pump(700,picker))==0,'the setting turns them off')
-- A saved opt-out that can't be read stays an opt-out.
broken['get:sendAchievements']=true; config.Achievement.C.name='Third, renamed'
assert(#withAchievements(pump(700,picker))==0,'an unreadable opt-out still holds')
broken['get:sendAchievements']=nil; config.Achievement.C.name='Third'
values.sendAchievements=true
assert(#withAchievements(pump(120,picker))==1,'and back on')
-- Going back to a set the picker already finished (A, B, then A again) is one part, then quiet.
config.Achievement.C.progress=1
assert(#withAchievements(pump(700,picker))==1,'the earlier set is offered once')
assert(#withAchievements(pump(700,picker))==0,'and acknowledged, not resent')
-- Multi-part sets: parts go in order until the picker holds them all, through a 429,
-- a picker restart mid-set and a 400 on an ordinary report.
for i=1,700 do config.Achievement['M'..i]={id=1000+i,name='Multi part achievement number '..i,category=3,subCategory=-1,progress=-2} end
local function parts(list) local out={} for _,b in ipairs(list) do if b.achievements then out[#out+1]=b.achievements.part end end return out end
local busy=0
-- The 429 has no Retry-After header, which once threw inside the reply handler.
local slow=function(b) if b and b.achievements and busy<1 then busy=busy+1; return {responseCode=429,data='{}'} end return picker(b) end
local sent=parts(pump(700,slow)); assert(busy==1,'one 429')
assert(#sent>=3 and held.parts==sent[#sent] and held.received==held.parts,'every part arrives: '..table.concat(sent,','))
for i=2,#sent do assert(sent[i]==sent[i-1] or sent[i]==sent[i-1]+1,'parts in order: '..table.concat(sent,',')) end
local total=held.parts
-- A new completion mid-set, then the picker restarts after part 2: the plugin starts the new set over.
config.Achievement.M701={id=1701,name='One more',category=3,subCategory=-1,progress=-2}
local restarted=false
local forgetful=function(b) local r=picker(b); if not restarted and held and held.received==2 then restarted=true; held,done=nil,{} end; return r end
sent=parts(pump(900,forgetful)); assert(restarted,'the restart happened')
assert(held.received==held.parts and held.parts==total,'the set completes after a restart: '..table.concat(sent,','))
-- A 400 on an ordinary report (no achievements in it) doesn't stop parts.
config.Achievement.M702={id=1702,name='And one more',category=3,subCategory=-1,progress=-2}
local picky=function(b) if b and not b.achievements then return {responseCode=400,data='{"message":"bad position"}'} end return picker(b) end
pump(900,picky); assert(held.received==held.parts,'parts complete despite ordinary 400s')
for i=1,702 do config.Achievement['M'..i]=nil end
-- Closing stays closed; logging out and back in keeps it closed.
tw.options.onClose(); emit('Draw',{timeDeltaSecs=1.1}); emit('Logic'); assert(tw.destroyed and values.tasksWindow==false)
PluginShutdown(); assert(next(handlers)==nil); for _,w in ipairs(windows) do assert(w.destroyed,w.title) end; assert(next(shapes)==nil)
assert(views[#views].destroyed); PluginShutdown()
for _,line in ipairs(logs) do assert(not line:find('synthetic')) end
-- Wider resize grips: PrettyUI's strips are re-placed after each of its refreshes, except mid-drag.
do
  local settings=require('settings')
  local function strip() local s={}; function s:SetPos(x,y) self.x,self.y=x,y end; function s:SetSize(w,h) self.w,self.h=w,h end; return s end
  local r={root={x=100,y=50,width=400,height=300},handles={},calls=0}
  for _,k in ipairs({'n','s','e','w','nw','ne','sw','se'}) do r.handles[k]=strip() end
  function r:_Refresh() self.calls=self.calls+1; for _,s in pairs(self.handles) do s:SetPos(0,0); s:SetSize(10,10) end end
  function r:Refresh() self:_Refresh(true) end
  assert(settings.widen(r) and r.calls==1)
  local se,ne,west,south=r.handles.se,r.handles.ne,r.handles.w,r.handles.s
  assert(se.x==478 and se.y==328 and se.w==36 and se.h==36)
  assert(ne.x==494 and ne.y==36 and ne.w==20 and ne.h==20)
  assert(west.x==86 and west.y==56 and west.w==20 and west.h==272)
  assert(south.x==122 and south.y==344 and south.w==356 and south.h==20)
  r.dragState={captureExpanded=true}; r:Refresh(); assert(se.w==10)
  r.handles.e.hidden=true; r.dragState=nil; r:Refresh(); assert(r.handles.e.w==10 and se.w==36)
  assert(not settings.widen(nil) and not settings.widen({}))
end
print('lifecycle tests passed')

