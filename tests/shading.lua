-- Shading geometry and rebuild policy against a small Shapes API mock; never starts a client.
local shading=require('shading')
local net=require('net')
local json=require('json')
local function eq(a,b) assert(a==b,tostring(a)..' ~= '..tostring(b)) end
local NARDAH=53*256+45
-- Wire rows -> map; bad rows are dropped, not fatal.
local rows=net.nearby(json.decode('[{"chunkId":"13613","state":"unlocked"},{"chunkId":"13614","state":"locked"},'..
  '{"chunkId":"x","state":"locked"},{"chunkId":"13612","state":"maybe"},{"chunkId":"51400","state":"locked"},7]'))
eq(rows[NARDAH],'unlocked'); eq(rows[NARDAH+1],'locked'); eq(rows[NARDAH-1],nil); eq(rows[51400],nil)
eq(net.nearby(json.null),nil); eq(net.nearby(json.decode('[]')),nil); eq(net.nearby('13613'),nil)
-- Older pickers without nearby: the current chunk alone, and only when it has a drawable state.
eq(shading.rows({chunkId='13613',state='locked'})[NARDAH],'locked')
eq(shading.rows({chunkId='13613',state='unlocked'}),nil); eq(shading.rows(nil),nil)
eq(shading.rows({chunkId='13613',state='locked',nearby={[NARDAH]='unlocked'}})[NARDAH],'unlocked')

local flat=function() return 1000 end
local function validate(g)
  local n=#g.positions; eq(#g.rgba,n); eq(#g.lines%2,0); eq(#g.tris%3,0)
  for _,i in ipairs(g.lines) do assert(math.type(i)=='integer' and i>=0 and i<n) end
  for _,i in ipairs(g.tris) do assert(math.type(i)=='integer' and i>=0 and i<n) end
end
-- Unlocked centre, one locked neighbour to the north: one boundary wall plus faint perimeter lines.
local g=shading.geometry({[NARDAH]='unlocked',[NARDAH+1]='locked'},flat); validate(g)
eq(g.walls,1); eq(g.edges,4); eq(g.missing,0)
eq(g.originX,53*64*512); eq(g.originZ,45*64*512)
-- The wall sits on the shared edge z=46*64 tiles, i.e. 64 tiles north of the origin.
local wallZ={}
for i,p in ipairs(g.positions) do if p[2]==1000+shading.WALL then wallZ[p[3]]=true; eq(g.rgba[i]&0xFF,0) end end
assert(wallZ[64*512]); eq(next(wallZ,next(wallZ)),nil)
eq(#g.tris,64*12) -- 64 tile-quads, two triangles each, both windings
-- Locked everywhere: grid lines but no walls. Available next to locked: red wall.
g=shading.geometry({[NARDAH]='locked',[NARDAH+1]='locked'},flat); validate(g); eq(g.walls,0); eq(g.edges,7)
g=shading.geometry({[NARDAH]='available',[NARDAH+256]='locked'},flat); validate(g); eq(g.walls,1)
local red=false
for i in ipairs(g.positions) do if g.rgba[i]>>8==0xFF3B30 then red=true end end
assert(red)
-- Unlocked and unknown draw nothing at all.
g=shading.geometry({[NARDAH]='unlocked',[NARDAH+1]='unknown'},flat); eq(#g.positions,0); eq(g.edges,0)
-- Unloaded terrain breaks lines rather than drawing at a wrong height.
g=shading.geometry({[NARDAH]='locked'},function(tx) if tx<53*64+10 then return nil end return 500 end); validate(g)
assert(g.missing>0); for _,p in ipairs(g.positions) do assert(p[2]>=500) end
-- A full 5x5 block stays small enough to rebuild on a chunk change.
local block={}
for dx=-2,2 do for dz=-2,2 do block[NARDAH+dx*256+dz]=(dx==0 and dz==0) and 'unlocked' or 'locked' end end
g=shading.geometry(block,flat); validate(g); eq(g.walls,4); eq(g.edges,60); assert(#g.positions<10000)
eq(shading.signature(block,0),shading.signature(block,0)); assert(shading.signature(block,0)~=shading.signature(block,1))

-- Instance lifecycle against the documented ShapeList surface.
local instances,heightCalls,region={},0,false
Vector3={new=function(x,y,z) return {x=x,y=y,z=z} end}
ShapeData={new=function() return {} end}
ShapeList={
  GetInstance=function(name) return instances[name] end,
  CreateInstance=function(name)
    assert(not instances[name]); local i={name=name,isValid=true,visible=true,sets=0}
    function i:SetShapeData(d)
      local n=#d.positions; assert(n>0); eq(#d.rgba,n); assert(#d.lines>0 or (d.tris and #d.tris>0))
      for _,v in ipairs(d.lines) do assert(v>=0 and v<n) end
      for _,v in ipairs(d.tris or {}) do assert(v>=0 and v<n) end
      self.data=d; self.sets=self.sets+1; return true
    end
    instances[name]=i; return i
  end,
  DestroyInstance=function(i) i.isValid=false; instances[i.name]=nil; return true end,
}
World={IsRegion=function() return region end,GetGroundHeight=function(level,x,z)
  heightCalls=heightCalls+1; assert(math.type(x)=='integer' and math.type(z)=='integer')
  if level~=0 then return -1,false end
  return 1200,true
end}
local enabled=true
local s=shading.new({enabled=function() return enabled end})
local pos={x=53,z=45,floor=0}
local status={chunkId='13613',state='unlocked',nearby={[NARDAH]='unlocked',[NARDAH+1]='locked',[NARDAH-1]='locked'}}
s:update(pos,status,1)
local inst=instances[shading.NAME]; assert(inst and inst.visible); eq(inst.sets,1); eq(inst.lineWidth,3); eq(inst.ignoreDepth,shading.DEBUG)
eq(inst.translation.x,53*64*512); eq(inst.translation.y,0); eq(inst.translation.z,44*64*512)
assert(s:describe():find('^drawn; edges=%d+ walls=2'))
local calls=heightCalls
for t=2,30 do s:update(pos,status,t) end
eq(inst.sets,1); eq(heightCalls,calls) -- unchanged states never rebuild or resample terrain
s:worldChanged(); s:update(pos,status,31); eq(inst.sets,1) -- complete builds ignore world updates
status={chunkId='13613',state='unlocked',nearby={[NARDAH]='unlocked',[NARDAH+1]='available'}}
s:update(pos,status,32); eq(inst.sets,2)
s:update({x=53,z=45,floor=1},status,33); eq(inst.sets,2) -- floor 1 has no terrain in this mock
eq(inst.visible,false)
World.GetGroundHeight=function() return -1,false end
s:update({x=53,z=45,floor=1},status,34); assert(s:describe():find('terrain not loaded'))
World.GetGroundHeight=function(level) return level==1 and 900 or 1200,true end
s:update({x=53,z=45,floor=1},status,35); eq(inst.sets,2) -- needs a world update or the slow retry
s:worldChanged(); s:update({x=53,z=45,floor=1},status,36); eq(inst.sets,3); assert(inst.visible)
enabled=false; s:update(pos,status,37); eq(inst.visible,false); assert(s:describe():find('^off'))
enabled=true; s:update(pos,status,38); assert(inst.visible); eq(inst.sets,4)
region=true; s:update(pos,status,39); eq(inst.visible,false); assert(s:describe():find('instances'))
region=false; s:update(pos,nil,40); eq(inst.visible,false)
s:update(nil,status,41); eq(inst.visible,false)
s:update(pos,status,42); assert(inst.visible)
s:destroy(); eq(instances[shading.NAME],nil); eq(inst.isValid,false)
-- A missing Shapes API is reported, never thrown.
ShapeList=nil; local quiet=shading.new(); quiet:update(pos,status,1); assert(quiet:describe():find('unavailable'))
print('shading tests passed')
