// No repo dependencies: point FENGARI_HOME at the external npm tooling directory.
const fs = require('node:fs');
const path = require('node:path');
const vm = require(path.join(process.env.FENGARI_HOME || 'C:/Users/User/Projects/chunk-picker-rs3/.local/claude-tools/lua-harness', 'node_modules/fengari'));
const {lua, lauxlib, lualib, to_luastring, to_jsstring} = vm;
const root = path.resolve(__dirname, '..');
function state() {
  const L = lauxlib.luaL_newstate(); lualib.luaL_openlibs(L);
  const setup = `package.path = ${JSON.stringify(root.replaceAll('\\','/') + '/plugins/chunk-picker/?.lua;')} .. package.path`;
  if (lauxlib.luaL_dostring(L,to_luastring(setup))) throw Error(to_jsstring(lua.lua_tostring(L,-1)));
  return L;
}
let count = 0;
function syntax(dir) {
  for (const e of fs.readdirSync(dir,{withFileTypes:true})) {
    const f=path.join(dir,e.name);
    if (e.isDirectory()) syntax(f);
    else if (f.endsWith('.lua')) {
      const L=state(); const code=lauxlib.luaL_loadfile(L,to_luastring(f));
      if(code) throw Error(`${f}: ${to_jsstring(lua.lua_tostring(L,-1))}`);
      lua.lua_close(L); count++;
    }
  }
}
syntax(path.join(root,'plugins')); syntax(__dirname);
console.log(`Fengari syntax: ${count} Lua files passed`);
for (const file of ['core.lua','progress.lua','shading.lua','tasks.lua','achievements.lua','items.lua','serverkeys.lua','lifecycle.lua']) {
  const L=state();
  if(lauxlib.luaL_dofile(L,to_luastring(path.join(__dirname,file)))) throw Error(`${file}: ${to_jsstring(lua.lua_tostring(L,-1))}`);
  lua.lua_close(L);
}
// Export requests built by the real net module for the isolated HTTP test.
if(process.argv[2]) {
  const L=state();
  const script=`local n=require('net'); local j=require('json'); local b=n.build(100,1792411200,{id=1,beta=true},{x=50,z=50,floor=0},{ATTACK={level=12,xp=1584}},{finished=j.array({"Cook's Assistant"}),started=j.array({"The Blood Pact"})}); return j.encode({requests=j.array({{method='POST',path=n.REPORT,body=b},{method='GET',path=n.STATUS},{method='GET',path=n.TASKS}})})`;
  if(lauxlib.luaL_dostring(L,to_luastring(script))) throw Error(to_jsstring(lua.lua_tostring(L,-1)));
  fs.writeFileSync(process.argv[2],to_jsstring(lua.lua_tostring(L,-1)));
  lua.lua_close(L); console.log('Exported exact net.lua request fixture');
}
