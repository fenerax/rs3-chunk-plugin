-- Shading geometry and rebuild policy against a small Shapes API mock; never starts a client.
local shading=require('shading')
local net=require('net')
local json=require('json')
local function eq(a,b) if a~=b then error(tostring(a)..' ~= '..tostring(b),2) end end
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
local nofill=shading.style(function(key,_,default) if key:find('^shadeFill') and key~='shadeFillStrength' then return 'off' end return default end)
local function validate(g)
  local n=#g.positions; eq(#g.rgba,n); eq(#g.lines%2,0); eq(#g.tris%3,0)
  for _,i in ipairs(g.lines) do assert(math.type(i)=='integer' and i>=0 and i<n) end
  for _,i in ipairs(g.tris) do assert(math.type(i)=='integer' and i>=0 and i<n) end
end
-- Unlocked centre, one locked neighbour to the north: one boundary wall plus faint perimeter lines.
local g=shading.geometry({[NARDAH]='unlocked',[NARDAH+1]='locked'},flat,nofill); validate(g)
eq(g.walls,1); eq(g.edges,4); eq(g.missing,0)
eq(g.originX,53*64*512); eq(g.originZ,45*64*512)
-- The wall sits on the shared edge z=46*64 tiles, i.e. 64 tiles north of the origin.
local wallZ={}
for i,p in ipairs(g.positions) do if p[2]==1000+shading.WALL then wallZ[p[3]]=true; eq(g.rgba[i]&0xFF,0) end end
assert(wallZ[64*512]); eq(next(wallZ,next(wallZ)),nil)
eq(#g.tris,64*12) -- 64 tile-quads, two triangles each, both windings
-- Locked everywhere: grid lines but no walls. Available next to locked: red wall.
g=shading.geometry({[NARDAH]='locked',[NARDAH+1]='locked'},flat,nofill); validate(g); eq(g.walls,0); eq(g.edges,7)
g=shading.geometry({[NARDAH]='available',[NARDAH+256]='locked'},flat,nofill); validate(g); eq(g.walls,1)
local red=false
for i in ipairs(g.positions) do if g.rgba[i]>>8==0xFF3B30 then red=true end end
assert(red)
-- Unlocked and unknown draw nothing at all.
g=shading.geometry({[NARDAH]='unlocked',[NARDAH+1]='unknown'},flat,nofill); eq(#g.positions,0); eq(g.edges,0)
-- Unloaded terrain breaks lines rather than drawing at a wrong height.
g=shading.geometry({[NARDAH]='locked'},function(tx) if tx<53*64+10 then return nil end return 500 end,nofill); validate(g)
assert(g.missing>0); for _,p in ipairs(g.positions) do assert(p[2]>=500) end
-- A full 5x5 block stays small enough to rebuild on a chunk change.
local block={}
for dx=-2,2 do for dz=-2,2 do block[NARDAH+dx*256+dz]=(dx==0 and dz==0) and 'unlocked' or 'locked' end end
g=shading.geometry(block,flat,nofill); validate(g); eq(g.walls,4); eq(g.edges,60); assert(#g.positions<10000)
-- Split into one small shape per edge; together the parts keep every point.
local parts,total=shading.split(g),0
eq(#parts,60)
for _,part in ipairs(parts) do
  validate(part); assert(#part.positions>0 and #part.positions<=200); total=total+#part.positions
  assert(part.originX>=51*64*512 and part.originX<=56*64*512 and part.originZ>=43*64*512 and part.originZ<=48*64*512)
end
eq(total,#g.positions)
-- Styles: unknown values fall back, grid lines and walls can be turned off, colours swap.
local style=shading.style(function(key,_,default)
  local v=({shadeColours='colourblind',shadeWidth='nonsense',shadeWalls='off',shadeGrid=false,shadeFillLocked='off',shadeFillRollable='off'})[key]
  if v==nil then return default end; return v
end)
eq(style.width,3); eq(style.wall,0); eq(style.grid,false); eq(style.rgb[2],0x2F80FF)
g=shading.geometry(block,flat,style); validate(g); eq(#g.tris,0); eq(g.walls,0); eq(g.edges,4) -- only the boundary edges
for i in ipairs(g.positions) do eq(g.rgba[i]>>8,0x2F80FF) end
eq(shading.style().key,'classic/normal/low/true/dark/tint/medium/haze////outline/3065014')
-- Shared access: a chunk only the partner unlocked arrives as its own state.
local duo=net.nearby(json.decode('[{"chunkId":"13613","state":"unlocked","by":"me"},{"chunkId":"13614","state":"unlocked","by":"partner"},'..
  '{"chunkId":"13612","state":"unlocked","by":"both"},{"chunkId":"13615","state":"locked","by":"partner"}]'))
eq(duo[NARDAH],'unlocked'); eq(duo[NARDAH+1],'partner'); eq(duo[NARDAH-1],'unlocked'); eq(duo[NARDAH+2],'locked')
-- Outline (default): one line where your open chunk meets the partner's, in the partner colour, no wall.
local function partnerStyle(mode) return shading.style(function(key,_,default)
  if key=='shadePartner' then return mode end
  if key:find('^shadeFill') and key~='shadeFillStrength' then return 'off' end return default end) end
g=shading.geometry({[NARDAH]='unlocked',[NARDAH+1]='partner'},flat,partnerStyle('outline')); validate(g)
eq(g.edges,1); eq(g.walls,0); eq(#g.tris,0); for i in ipairs(g.positions) do eq(g.rgba[i]>>8,shading.PARTNER) end
-- Locked beside the partner's chunk keeps the locked colour and wall.
g=shading.geometry({[NARDAH]='locked',[NARDAH+1]='partner'},flat,partnerStyle('outline')); validate(g)
eq(g.walls,1); for i in ipairs(g.positions) do assert(g.rgba[i]>>8==0xFF3B30) end
-- Light tint: a faint ground sheet, never a haze box; off draws nothing.
g=shading.geometry({[NARDAH]='unlocked',[NARDAH+1]='partner'},flat,partnerStyle('tint')); validate(g)
eq(g.edges,0); eq(g.fills,1)
for i,p in ipairs(g.positions) do eq(p[2],1000+shading.FILL_LIFT); eq(g.rgba[i],shading.PARTNER*256+0x20) end
g=shading.geometry({[NARDAH]='unlocked',[NARDAH+1]='partner'},flat,partnerStyle('off')); eq(#g.positions,0)
-- Custom colours: hex parsing, and a custom choice without a valid colour falls back to the default.
eq(shading.hex('#ff3b30'),0xFF3B30); eq(shading.hex(' 2F80FF '),0x2F80FF); eq(shading.hex('#12345'),nil); eq(shading.hex(nil),nil)
local custom=shading.style(function(key,_,default) return ({shadeColours='custom',shadeRgbLocked='#112233',shadeRgbRollable='#445566',
  shadeFillLocked='custom',shadeRgbFillLocked='#778899',shadeFillRollable='custom',shadeRgbFillRollable='#AABBCC'})[key] or default end)
eq(custom.rgb[2],0x112233); eq(custom.rgb[1],0x445566); eq(custom.fill.locked,0x778899); eq(custom.fill.available,0xAABBCC)
assert(custom.key:find('1122867,4478310',1,true) and custom.key:find('7833753',1,true))
local broken=shading.style(function(key,_,default) return ({shadeColours='custom',shadeFillLocked='custom',shadeRgbFillLocked='nope'})[key] or default end)
eq(broken.rgb[2],0xFF3B30); eq(broken.fill.locked,0); eq(shading.style().wall,shading.WALL)
-- Fills: locked chunks grey, rollable ones in their border colour, unlocked and unknown never.
local fills={[NARDAH]='unlocked',[NARDAH+1]='locked',[NARDAH+2]='available',[NARDAH+3]='unknown'}
local ground=shading.style(function(key,_,default) return ({shadeFillStyle='ground',shadeFillLocked='grey'})[key] or default end)
g=shading.geometry(fills,flat,ground); validate(g); eq(g.fills,2)
local seen={}
for i in ipairs(g.positions) do if g.positions[i][2]==1000+shading.FILL_LIFT then seen[g.rgba[i]]=(seen[g.rgba[i]] or 0)+1 end end
eq(seen[0x8A8A8A70],17*17); eq(seen[0xFFB02038],17*17) -- the bright rollable tint at half strength
parts=shading.split(g); for _,part in ipairs(parts) do validate(part); assert(#part.positions<=17*17) end
-- Haze: a lid at HAZE above the ground, and curtains only toward differently filled neighbours.
g=shading.geometry(fills,flat); validate(g); eq(g.fills,2)
local lid,curtainBase=0,0
for i,p in ipairs(g.positions) do
  if p[2]==1000+shading.HAZE then lid=lid+1 elseif p[2]==1000+shading.FILL_LIFT then curtainBase=curtainBase+1 end
end
-- Locked: curtains to unlocked (south) and rollable (north). Rollable: to locked (south) and unknown (north).
eq(curtainBase,4*17); eq(lid,2*17*17+4*17)
parts=shading.split(g); for _,part in ipairs(parts) do validate(part); assert(#part.positions<=17*17+4*2*17) end
-- Neighbouring chunks with the same fill share one haze: no curtain between them.
g=shading.geometry({[NARDAH]='locked',[NARDAH+1]='locked'},flat); validate(g); curtainBase=0
for _,p in ipairs(g.positions) do if p[2]==1000+shading.FILL_LIFT then curtainBase=curtainBase+1 end end
eq(curtainBase,0)
-- Rollable "same as locked" follows the locked choice; strong and dark apply.
local same=shading.style(function(key,_,default) return ({shadeFillRollable='same',shadeFillLocked='dark',shadeFillStrength='strong'})[key] or default end)
eq(same.fill.locked,0); eq(same.fill.available,0); eq(same.fillAlpha,0xA8)
-- A fill skips quads over unloaded terrain instead of guessing a height.
g=shading.geometry({[NARDAH]='locked'},function(tx) if tx<53*64+10 then return nil end return 500 end); validate(g)
eq(g.fills,1); assert(g.missing>0)
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
      local n=#d.positions; assert(n>0); eq(#d.rgba,n); assert(d.lines==nil or #d.lines>0); assert(d.lines or (d.tris and #d.tris>0))
      for _,v in ipairs(d.lines or {}) do assert(v>=0 and v<n) end
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
local enabled,chosen=true,{}
local s=shading.new({enabled=function() return enabled end,
  style=function() return shading.style(function(key,_,default) return chosen[key] or default end) end})
local pos={x=53,z=45,floor=0}
local status={chunkId='13613',state='unlocked',nearby={[NARDAH]='unlocked',[NARDAH+1]='locked',[NARDAH-1]='locked'}}
local function visibleCount() local n=0 for _,i in pairs(instances) do if i.visible then n=n+1 end end return n end
s:update(pos,status,1)
local inst=instances[shading.NAME..'-1']; assert(inst and inst.visible); eq(inst.sets,1); eq(inst.lineWidth,3); eq(inst.ignoreDepth,shading.DEBUG)
eq(inst.translation.y,0); assert(inst.translation.x>=51*64*512 and inst.translation.z>=43*64*512)
assert(s.parts>1); eq(visibleCount(),s.parts); assert(instances[shading.NAME..'-'..s.parts].visible)
assert(s:describe():find('^drawn; edges=%d+ walls=2'))
local firstParts=s.parts
local calls=heightCalls
for t=2,30 do s:update(pos,status,t) end
eq(inst.sets,1); eq(heightCalls,calls) -- unchanged states never rebuild or resample terrain
s:worldChanged(); s:update(pos,status,31); eq(inst.sets,1) -- complete builds ignore world updates
-- A style change rebuilds once and applies the width; the same style again does nothing.
chosen.shadeWidth='thick'; s:update(pos,status,31); eq(inst.sets,2); eq(inst.lineWidth,6)
s:update(pos,status,31); eq(inst.sets,2)
chosen.shadeWidth=nil; s:update(pos,status,31); eq(inst.sets,3); eq(inst.lineWidth,3)
inst.sets=1
status={chunkId='13613',state='unlocked',nearby={[NARDAH]='unlocked',[NARDAH+1]='available'}}
s:update(pos,status,32); eq(inst.sets,2)
-- Fewer edges now: leftover shapes from the bigger build are hidden, not left drawing.
assert(s.parts<firstParts); eq(visibleCount(),s.parts)
s:update({x=53,z=45,floor=1},status,33); eq(inst.sets,2) -- floor 1 has no terrain in this mock
eq(inst.visible,false); eq(visibleCount(),0)
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
s:destroy(); eq(next(instances),nil); eq(inst.isValid,false)
-- A missing Shapes API is reported, never thrown.
ShapeList=nil; local quiet=shading.new(); quiet:update(pos,status,1); assert(quiet:describe():find('unavailable'))
print('shading tests passed')
