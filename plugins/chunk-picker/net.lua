-- All wire-format policy lives here. Aligned to the picker's docs/plugin-api.md (move/plugsync, 2026-10-21).
local json = require("json")
local taskList = require("tasks").list
local M = {REPORT = "/api/plugin/v1/report", STATUS = "/api/plugin/v1/status", TASKS = "/api/plugin/v1/tasks", MAX_BODY = 16384}
local months = {Jan=1,Feb=2,Mar=3,Apr=4,May=5,Jun=6,Jul=7,Aug=8,Sep=9,Oct=10,Nov=11,Dec=12}
-- Gregorian conversions also work when the client omits os/date/utf8.
local function days(y,m,d)
  y=y-(m<=2 and 1 or 0); local era=math.floor(y/400); local yo=y-era*400
  local mp=m+(m>2 and -3 or 9)
  return era*146097+yo*365+math.floor(yo/4)-math.floor(yo/100)+math.floor((153*mp+2)/5)+d-1-719468
end
function M.iso(epoch)
  local day=math.floor(epoch/86400); local seconds=math.floor(epoch-day*86400)
  local z=day+719468; local era=math.floor(z/146097); local doe=z-era*146097
  local yo=math.floor((doe-math.floor(doe/1460)+math.floor(doe/36524)-math.floor(doe/146096))/365)
  local y=yo+era*400; local doy=doe-(365*yo+math.floor(yo/4)-math.floor(yo/100))
  local mp=math.floor((5*doy+2)/153); local d=doy-math.floor((153*mp+2)/5)+1
  local m=mp+(mp<10 and 3 or -9); y=y+(m<=2 and 1 or 0)
  return string.format("%04d-%02d-%02dT%02d:%02d:%02dZ",y,m,d,math.floor(seconds/3600),math.floor(seconds/60)%60,seconds%60)
end
function M.dateEpoch(header)
  if type(header) ~= "string" then return nil end
  local d,m,y,h,mi,s=header:match("(%d%d?) (%a%a%a) (%d%d%d%d) (%d%d):(%d%d):(%d%d) GMT")
  if not d or not months[m] then return nil end
  return days(tonumber(y),months[m],tonumber(d))*86400+tonumber(h)*3600+tonumber(mi)*60+tonumber(s)
end
local function header(request, name)
  local h=request.header
  if type(h)=="table" then for k,v in pairs(h) do if tostring(k):lower()==name:lower() then return tostring(v) end end end
  if type(h)=="string" then
    for line in h:gmatch("[^\r\n]+") do local k,v=line:match("^([^:]+):%s*(.*)$"); if k and k:lower()==name:lower() then return v end end
  end
  -- An explicit nil: tonumber() with no argument at all throws.
  return nil
end
function M.build(seq,epoch,world,position,skills,quests,diagnostics,achievements)
  local p={v=1,seq=seq,sentAt=M.iso(epoch),position={x=position.x,z=position.z,floor=position.floor}}
  if world then p.world=world end
  p.skills=skills; p.quests=quests; p.achievements=achievements
  -- Picker contract: at most 80 single lines of up to 160 characters.
  if diagnostics and #diagnostics>0 then
    local lines={}
    for i=1,math.min(80,#diagnostics) do lines[i]=(tostring(diagnostics[i]):gsub("[%c]"," "):sub(1,160)) end
    p.diagnostics=lines
  end
  local warning
  -- Diagnostics are the first thing dropped when a report is too large.
  if p.diagnostics and #json.encode(p)>M.MAX_BODY then p.diagnostics=nil end
  if quests and (#quests.finished>500 or #quests.started>500) then
    p.quests=nil; warning="Quest snapshot exceeds 500 names; held locally"
  end
  local body=json.encode(p)
  -- Quest objects replace prior lists; splitting them would silently lose progress.
  -- Send the complete snapshot or hold it with a visible diagnostic.
  if #body>M.MAX_BODY and p.quests then
    p.skills=nil; body=json.encode(p)
    if #body>M.MAX_BODY then p.quests=nil; p.skills=skills; warning="Quest snapshot exceeds 16 KB; held locally" end
    body=json.encode(p)
  end
  assert(#body<=M.MAX_BODY,"Report exceeds 16 KB")
  return body,p,warning
end
local STATES = {unlocked=true,locked=true,available=true,unknown=true}
-- Status `nearby` rows become a map-square-id -> state map. Bad rows are dropped, never fatal:
-- the top-level state alone still drives the panel.
function M.nearby(rows)
  if type(rows)~="table" then return nil end
  local out,count={},0
  for i=1,math.min(#rows,81) do
    local row=rows[i]
    local id=type(row)=="table" and type(row.chunkId)=="string" and #row.chunkId<=5 and row.chunkId:match("^%d+$")
      and math.tointeger(tonumber(row.chunkId))
    if id and id//256<=199 and id%256<=199 and STATES[row.state] then
      -- Shared access: a chunk only your partner unlocked is open to you but drawn in its own colour.
      out[id]=row.state=="unlocked" and row.by=="partner" and "partner" or row.state; count=count+1
    end
  end
  return count>0 and out or nil
end
function M.new(options)
  local self={history={}, busy=false, failures=0, nextAt=0, blocked=false, localhostConnected=false,
    message="Not connected", sequence=options.sequence or 0, clockEpoch=nil, generation=0}
  function self:epoch(now)
    if os and type(os.time)=="function" then local ok,v=pcall(os.time); if ok and type(v)=="number" then return v end end
    return self.clockEpoch and (self.clockEpoch+now-self.clockAt) or nil
  end
  function self:cancel()
    self.generation=self.generation+1
    local request=self.request; self.request=nil; self.busy=false
    if request then pcall(function() request:Cancel() end) end
  end
  function self:reset()
    self:cancel(); self.blocked=false; self.nextAt=0; self.failures=0; self.status=nil; self.lastSync=nil
    self.message="Not connected"
    self.heldQuestJSON=nil; self.payloadWarning=nil
    self.tasks=nil; self.tasksNextAt=0; self.tasksMessage=nil; self.tasksNoPaging=nil
  end
  function self:filterQuests(quests)
    if quests and self.heldQuestJSON==json.encode(quests) then return nil end
    return quests
  end
  function self:ready(now) return not self.busy and not self.blocked and now>=self.nextAt end
  -- Optional report fields the picker has said it understands; it refuses unknown ones.
  function self:accepts(name)
    local list=self.status and self.status.accepts
    if type(list)~="table" then return false end
    for _,value in ipairs(list) do if value==name then return true end end
    return false
  end
  function self:requestHTTP(now,handle,key,method,body,done,path)
    if not self:ready(now) then return false end
    self.busy=true; self.startedAt=now; local generation=self.generation
    local function complete(r)
      if generation~=self.generation or not self.busy then return end
      self.busy=false; self.request=nil
      local current=options.now and options.now() or now
      local code=tonumber(r.responseCode) or 0
      local info=tostring(r.errorInfo or "")
      -- Never log response bodies, URLs, headers, or credentials. Redact key even if echoed by transport.
      if key~="" then info=info:gsub(key:gsub("([^%w])","%%%1"),"[redacted]") end
      info=info:gsub("gpk_[%w_-]+","[redacted]"):gsub("https?://[^%s]+","[URL]"):gsub("[%c]"," "):sub(1,160)
      table.insert(self.history,1,{code=code,timedOut=r.timedOut==true,failed=r.failed==true,errorInfo=info})
      if #self.history>5 then table.remove(self.history) end
      if code>0 then self.localhostConnected=true end
      local date=M.dateEpoch(header(r,"Date")); if date then self.clockEpoch=date; self.clockAt=current end
      local ok,status=pcall(json.decode,r.data or "")
      if path and path:sub(1,#M.TASKS)==M.TASKS then
        -- Task lists have their own retry clock and never change the connection state: an older
        -- picker without this route answers 401, which must not block reports.
        local list=ok and code>=200 and code<300 and not r.failed and not r.timedOut and taskList(status) or nil
        -- A picker that can't page (or a client that mangles the query) falls back to the first rows.
        local askedFrom=path~=M.TASKS
        if list and self.tasksNoPaging then list.allFrom=nil end
        if list then self.tasks=list; self.tasksAt=current; self.tasksMessage=nil
        elseif askedFrom and code~=429 then self.tasksNoPaging=true; self.tasksNextAt=current
        elseif code==401 or code==404 then self.tasksMessage="this picker has no in-game task list"; self.tasksNextAt=current+300
        elseif code==429 then self.tasksMessage="picker asked to slow down"; self.tasksNextAt=current+(tonumber(header(r,"Retry-After")) or 60)
        else self.tasksMessage="task list unavailable, retrying"; self.tasksNextAt=current+30 end
        self.nextAt=math.max(self.nextAt,current+1)
        if done then done(list~=nil,list,code) end
        return
      end
      local success=code>=200 and code<300 and not r.failed and not r.timedOut and ok and type(status)=="table"
        and STATES[status.state]==true
      if success then
        status.nearby=M.nearby(status.nearby)
        self.failures=0; self.nextAt=current+1; self.status=status; self.lastSync=current; self.message="Connected"
      elseif code==401 then self.blocked=true; self.status=nil; self.message="Key not accepted"
      else
        self.failures=self.failures+1
        local delay=math.min(300,2^math.min(self.failures,9))
        if code==429 then delay=math.max(delay,tonumber(header(r,"Retry-After")) or 60) end
        self.nextAt=current+delay; self.status=nil
        self.message=code==429 and "Picker asked to slow down, retrying" or "Picker unreachable, retrying"
        if code==409 and date then self.sequence=math.max(self.sequence,math.floor(date*1000)) end
      end
      if done then done(success,status,code) end
    end
    local ok=pcall(function()
      local r=HTTPRequest.new(handle,path or (method=="GET" and M.STATUS or M.REPORT)); self.request=r
      r:AddHeader("Authorization","Bearer "..key); r:AddHeader("Content-Type","application/json")
      if method=="GET" then r:Get(complete) else r:Post(body,complete) end
    end)
    if not ok then complete({responseCode=0,failed=true,errorInfo="HTTPRequest setup failed"}) end
    return true
  end
  function self:test(now,handle,key,done) return self:requestHTTP(now,handle,key,"GET",nil,done) end
  function self:tasksDue(now) return now>=(self.tasksNextAt or 0) end
  -- `from` > 0 asks for "All active" rows past the first reply; sent only to pickers that page.
  function self:fetchTasks(now,handle,key,done,from)
    if not self:tasksDue(now) then return false end
    local paged=math.type(from)=="integer" and from>0 and not self.tasksNoPaging
    return self:requestHTTP(now,handle,key,"GET",nil,done,paged and (M.TASKS.."?from="..from) or M.TASKS)
  end
  function self:report(now,handle,key,world,position,skills,quests,done,diagnostics,achievements)
    local epoch=self:epoch(now)
    if not epoch then
      self.message="Checking picker clock"
      return self:test(now,handle,key,function(ok)
        if ok and not self:epoch(options.now and options.now() or now) then
          self.message="Picker clock unavailable (HTTP Date missing)"; self.nextAt=now+60
        end
      end)
    end
    if not self:ready(now) then return false end
    self.sequence=math.max(self.sequence+1,math.floor(epoch*1000))
    if options.saveSequence then options.saveSequence(self.sequence) end
    local body,payload,warning=M.build(self.sequence,epoch,world,position,skills,quests,diagnostics,achievements)
    if quests then
      self.payloadWarning=warning
      self.heldQuestJSON=not payload.quests and json.encode(quests) or nil
    end
    return self:requestHTTP(now,handle,key,"POST",body,function(ok,status,code)
      if done then done(ok,payload,status,code) end
    end)
  end
  function self:tick(now)
    -- Guard against a transport that never calls its callback; cancellation fences late callbacks.
    if self.busy and now-self.startedAt>30 then
      self:cancel(); self.failures=self.failures+1; self.nextAt=now+math.min(300,2^math.min(self.failures,9))
      self.status=nil; self.message="Picker unreachable, retrying"
      table.insert(self.history,1,{code=0,timedOut=true,failed=false,errorInfo="Local 30 s timeout"})
      if #self.history>5 then table.remove(self.history) end
    end
  end
  return self
end
return M
