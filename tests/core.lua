local json=require('json')
local location=require('location')
local net=require('net')
local function eq(a,b) assert(a==b,tostring(a)..' ~= '..tostring(b)) end
local function rejects(fn) assert(not pcall(fn),'Expected rejection') end
eq(json.encode(json.array()),'[]'); eq(json.encode({}),'{}')
local str='Café "quote" \\ \0\1\n\t'
eq(json.decode(json.encode(str)),str)
eq(json.decode('"\\uD83D\\uDE80"'),'🚀')
eq(json.decode('null'),json.null); eq(json.decode('[false,null,1.5e2]')[3],150)
for _,bad in ipairs({'01','1.','1e','1.e2','[1,]','{"x":1,"x":2}','"\\uD800"','true false','+1','-.2','"\n"'}) do rejects(function() json.decode(bad) end) end
local cyclic={}; cyclic.self=cyclic; rejects(function() json.encode(cyclic) end)
rejects(function() json.encode(0/0) end)
eq(location.fromGrid({mapSquareX=50,mapSquareZ=50,level=0}).chunk,12850)
eq(location.fromGrid({mapSquareX=53,mapSquareZ=45,level=3}).chunk,13613)
eq(location.fromGrid({mapSquareX=200,mapSquareZ=0,level=0}),nil)
Player={IsAvailable=function() return true end,GetEntity=function() return {coordGrid={mapSquareX=53,mapSquareZ=45,level=0}} end}
World={IsRegion=function() return true end,GetRegionSourceForCoordGrid=function() return nil end}
local p,why=location.read(); eq(p,nil); eq(why,'Instance')
World.GetRegionSourceForCoordGrid=function() return {mapSquareX=50,mapSquareZ=50,level=1} end
eq(location.read().chunk,12850); World.GetRegionSourceForCoordGrid=function() error('not mapped') end
p,why=location.read(); eq(p,nil); eq(why,'Instance')
World.IsRegion=nil; p,why=location.read(); eq(p,nil); eq(why,'Instance check unavailable')
local sync=require('sync').new(); local pos={x=50,z=50,floor=0}
sync:observe(pos,0); eq(sync:due(0.99,false),false); assert(sync:due(1,false))
sync:ack(pos,1); eq(sync:due(60,false),false); assert(sync:due(61,false))
sync:observe({x=50,z=50,floor=1},62); eq(sync:due(62.9,true),false); assert(sync:due(63,false))
sync:observe(nil,64); eq(sync:due(99,true),false)
eq(net.iso(0),'1970-01-01T00:00:00Z'); eq(net.iso(951782400),'2000-02-29T00:00:00Z')
eq(net.dateEpoch('Mon, 19 Oct 2026 12:00:00 GMT'),1792411200)
local body,payload=net.build(1,1792411200,{id=1,beta=true},pos,{ATTACK={level=1,xp=0}},{finished=json.array(),started=json.array()})
assert(#body<=16384); eq(json.decode(body).sentAt,'2026-10-19T12:00:00Z'); eq(payload.world.beta,true)
local huge=json.array(); for i=1,400 do huge[i]=string.rep('q',80)..i end
local _,held,warning=net.build(2,1792411200,nil,pos,nil,{finished=huge,started=json.array()})
eq(held.quests,nil); assert(warning)
local many=json.array(); for i=1,501 do many[i]='q'..i end
local _,overCount,countWarning=net.build(3,1792411200,nil,pos,nil,{finished=many,started=json.array()})
eq(overCount.quests,nil); assert(countWarning)
local request,callback,clock,created= nil,nil,0,0
HTTPRequest={new=function(handle,path)
  created=created+1
  request={headers={},path=path,AddHeader=function(self,k,v) self.headers[k]=v end,
    Get=function(self,cb) callback=cb end,Post=function(self,b,cb) self.body=b; callback=cb end,
    Cancel=function(self) self.cancelled=true end}
  return request
end}
local client=net.new({now=function() return clock end})
assert(client:report(0,{},'synthetic',nil,pos)); eq(request.path,net.REPORT)
eq(request.headers.Authorization,'Bearer synthetic'); eq(request.headers['Content-Type'],'application/json')
eq(client:report(0,{},'synthetic',nil,pos),false); eq(created,1)
callback({responseCode=500,data='{}',failed=false,timedOut=false,errorInfo='synthetic'})
eq(client.nextAt,2); eq(client.history[1].errorInfo,'[redacted]')
eq(client:test(1,{},'synthetic'),false); clock=2; assert(client:test(2,{},'synthetic'))
callback({responseCode=429,data='{}',header={['Retry-After']='9'}}); eq(client.nextAt,11)
clock=11; assert(client:test(11,{},'synthetic')); callback({responseCode=200,data='{"state":"unlocked","chunkId":"12850"}'})
eq(client.failures,0); eq(client.lastSync,11)
clock=12; client:test(12,{},'synthetic'); callback({responseCode=401,data='{}'}); assert(client.blocked)
eq(client:test(100,{},'synthetic'),false); client:reset(); assert(client:test(100,{},'synthetic'))
local stale=callback; client:cancel(); stale({responseCode=200,data='{"state":"unlocked"}'}); eq(client.status,nil)
clock=101; client:test(101,{},'synthetic'); client:tick(132); assert(request.cancelled); assert(client.nextAt>132)
local capped=net.new({now=function() return clock end})
for i=1,12 do
  clock=capped.nextAt; capped:test(clock,{},'synthetic'); callback({responseCode=503,data='{}'})
  assert(capped.nextAt-clock<=300)
end
eq(capped.nextAt-clock,300); eq(#capped.history,5)
local savedOS=os; os=nil
local fallback=net.new({now=function() return clock end}); clock=200
fallback:report(200,{},'synthetic',nil,pos); eq(request.path,net.STATUS)
callback({responseCode=200,data='{"state":"unknown"}',header='Date: Mon, 19 Oct 2026 12:00:00 GMT\r\n'})
eq(fallback:epoch(205),1792411205); os=savedOS
print('core tests passed')
