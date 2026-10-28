-- Each manifest server keeps its own key and owner; switching never hands one to another.
local values, broken = {}, {}
local function db(op, k) if broken[op .. ':' .. k] then error('storage unavailable') end end
PersistentDB = {CheckExists = function(_, k) db('get', k); return values[k] ~= nil end,
  Delete = function(_, k) db('delete', k); values[k] = nil end,
  GetString = function(_, k) db('get', k); return values[k] end,
  SetString = function(_, k, v) db('set', k); values[k] = v; return true end}
local who = 'Alpha'
Player = {GetEntity = function() return who and {displayName = who} or nil end}
local identity = require('identity')
local store = require('store').new(PersistentDB)
local check = identity.new(store)
local function select(to) return identity.switch(store, store:server(), to) end
local function key() return store:get('personalKey', 'String', '') end

-- Upgrade: a key saved before servers had their own belongs to the server selected now,
-- here the default, and goes with it when another is chosen.
values.personalKey, values.keyOwner = 'oldkey', 'Alpha'
assert(check:check(key()) == nil)
assert(select('home') == nil and values.server == 'home')
assert(values.personalKey == nil and values.keyOwner == nil, 'home has no key yet')
assert(values.personalKey_scratch == 'oldkey' and values.keyOwner_scratch == 'Alpha')
assert(check:check(key()) == identity.STORAGE, 'nothing to send without a key')

-- Saving on home leaves scratch's key alone; each comes back with its own server.
assert(identity.save(store, 'homekey') == nil and values.personalKey == 'homekey')
assert(select('scratch') == nil and key() == 'oldkey' and values.keyOwner == 'Alpha')
assert(values.personalKey_home == 'homekey' and values.personalKey_scratch == nil, 'the selected pair lives in one place')
assert(select('home') == nil and key() == 'homekey')
assert(select('home') == nil and key() == 'homekey', 'choosing the selected server changes nothing')

-- keyOwner travels with its key: Bravo's home key never becomes Alpha's scratch key.
who = 'Bravo'; assert(identity.save(store, 'bravokey') == nil and values.keyOwner == 'Bravo')
assert(select('scratch') == nil and values.keyOwner == 'Alpha' and check:check(key()) == identity.MISMATCH)
who = 'Alpha'; assert(check:check(key()) == nil)
assert(select('home') == nil and key() == 'bravokey' and check:check(key()) == identity.MISMATCH)
who = 'Bravo'; assert(check:check(key()) == nil)

-- An unbound key stays unbound across switches, so the first character to use it still gets it.
values.keyOwner = ''
assert(select('scratch') == nil and values.keyOwner_home == '')
assert(select('home') == nil and values.keyOwner == '' and check:check(key()) == nil and values.keyOwner == 'Bravo')

-- Forget removes only the selected server's key, and any parked copy of it.
assert(store:forget() and store:forget(identity.parked('home')))
assert(values.personalKey == nil and values.personalKey_home == nil)
assert(select('scratch') == nil and key() == 'oldkey')
assert(select('home') == nil and key() == '' and values.personalKey_scratch == 'oldkey')

-- Failures: nothing is sent with a key that belongs to another server or character.
assert(select('scratch') == nil and key() == 'oldkey')
broken['set:server'] = true
assert(select('home') ~= nil and values.server == 'scratch' and key() == 'oldkey' and values.keyOwner == 'Alpha', 'a refused switch changes nothing')
broken['set:server'] = nil
broken['get:keyOwner_home'] = true
assert(select('home') ~= nil and values.server == 'scratch' and values.keyOwner == 'Alpha', "unreadable parked owner")
broken['get:keyOwner_home'] = nil
values.personalKey_home, values.keyOwner_home = 'homekey', 'Alpha'
broken['set:personalKey'] = true
assert(select('home'):find('save the key again') and values.server == 'home')
assert(values.keyOwner == identity.PENDING and check:check(key()) == identity.UNFINISHED, "scratch's key never goes to home")
broken['set:personalKey'] = nil
assert(identity.save(store, 'homekey') == nil and check:check(key()) == nil)
-- A parked key whose owner went missing waits for Save rather than going to whoever is on.
values.personalKey_scratch, values.keyOwner_scratch = 'oldkey', nil
assert(select('scratch') == nil and key() == 'oldkey' and check:check(key()) == identity.UNFINISHED)

-- Before any choice: scratch while the manifest lists it (beta), else its first server, so a
-- Hub build with only production connects there.
values.server = nil
assert(store:server() == 'scratch', 'no manifest')
Plugin = {urls = {home = {}, production = {}, scratch = {}}}
assert(store:server() == 'scratch')
Plugin = {urls = {production = {}}}
assert(store:server() == 'production')
values.server = 'home'
assert(store:server() == 'home', 'a saved choice wins')
Plugin = nil
print('server key tests passed')
