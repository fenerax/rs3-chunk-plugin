-- Small pure Lua JSON codec. Explicit arrays preserve [] for empty quest lists.
local M = {null = {}}
local arrayMT = {}
function M.array(t) return setmetatable(t or {}, arrayMT) end
local function quote(s)
  return '"' .. s:gsub('[%z\1-\31\\"]', function(c)
    local escapes = {['"']='\\"', ['\\']='\\\\', ['\n']='\\n', ['\r']='\\r', ['\t']='\\t'}
    return escapes[c] or string.format('\\u%04x', string.byte(c))
  end) .. '"'
end
function M.encode(value)
  local seen = {}
  local function encode(v, depth)
    if depth > 64 then error("JSON nesting limit") end
    if v == M.null then return "null" end
    local kind = type(v)
    if kind == "nil" then return "null" end
    if kind == "boolean" then return v and "true" or "false" end
    if kind == "string" then return quote(v) end
    if kind == "number" then
      if v ~= v or v == math.huge or v == -math.huge then error("Non-finite JSON number") end
      return string.format("%.17g", v)
    end
    if kind ~= "table" or seen[v] then error("Unsupported/cyclic JSON value") end
    seen[v] = true
    local items, isArray = {}, getmetatable(v) == arrayMT or #v > 0
    if isArray then
      local count = 0
      for k in pairs(v) do if type(k) ~= "number" or k < 1 or k > #v or k % 1 ~= 0 then error("Sparse JSON array") end; count = count + 1 end
      if count ~= #v then error("Sparse JSON array") end
      for i = 1, #v do items[i] = encode(v[i], depth + 1) end
    else
      local keys = {}
      for k in pairs(v) do if type(k) ~= "string" then error("JSON object keys must be strings") end; keys[#keys+1] = k end
      table.sort(keys)
      for i, k in ipairs(keys) do items[i] = quote(k) .. ":" .. encode(v[k], depth + 1) end
    end
    seen[v] = nil
    return (isArray and "[" or "{") .. table.concat(items, ",") .. (isArray and "]" or "}")
  end
  return encode(value, 0)
end
local function utf(code)
  if code < 128 then return string.char(code) end
  if code < 2048 then return string.char(192+math.floor(code/64),128+code%64) end
  if code < 65536 then return string.char(224+math.floor(code/4096),128+math.floor(code/64)%64,128+code%64) end
  return string.char(240+math.floor(code/262144),128+math.floor(code/4096)%64,128+math.floor(code/64)%64,128+code%64)
end
function M.decode(s)
  assert(type(s) == "string" and #s <= 65536, "Invalid/oversized JSON response")
  local i, parse = 1, nil
  local function skip() local _, last = s:find("^[ \t\r\n]*", i); i = (last or i-1)+1 end
  local function fail() error("Invalid JSON at byte " .. i) end
  local function hex()
    local h = s:sub(i,i+3)
    if #h ~= 4 or h:find("[^%x]") then fail() end
    i = i+4; return tonumber(h,16)
  end
  local function str()
    i=i+1; local parts = {}
    while i <= #s do
      local c=s:sub(i,i); i=i+1
      if c == '"' then return table.concat(parts) end
      if c == "\\" then
        c=s:sub(i,i); i=i+1
        local escapes={['"']='"',['\\']='\\',['/']='/',b='\b',f='\f',n='\n',r='\r',t='\t'}
        if c == "u" then
          local n=hex()
          if n >= 0xD800 and n <= 0xDBFF then
            if s:sub(i,i+1) ~= "\\u" then fail() end
            i=i+2; local low=hex()
            if low < 0xDC00 or low > 0xDFFF then fail() end
            n=65536+(n-0xD800)*1024+low-0xDC00
          elseif n >= 0xDC00 and n <= 0xDFFF then fail() end
          parts[#parts+1]=utf(n)
        elseif escapes[c] then parts[#parts+1]=escapes[c] else fail() end
      elseif c:byte() < 32 then fail() else parts[#parts+1]=c end
    end
    fail()
  end
  parse=function(depth)
    if depth > 64 then fail() end
    skip(); local c=s:sub(i,i)
    if c == '"' then return str() end
    if c == "{" or c == "[" then
      local array=c == "["; local out=array and M.array() or {}; local close=array and "]" or "}"
      i=i+1; skip(); if s:sub(i,i)==close then i=i+1; return out end
      while true do
        local key
        if not array then if s:sub(i,i) ~= '"' then fail() end; key=str(); skip(); if s:sub(i,i) ~= ":" then fail() end; i=i+1 end
        local v=parse(depth+1)
        if array then out[#out+1]=v else if out[key] ~= nil then fail() end; out[key]=v end
        skip(); c=s:sub(i,i); i=i+1
        if c==close then return out end
        if c~="," then fail() end; skip()
      end
    end
    for literal,value in pairs({["true"]=true,["false"]=false,["null"]=M.null}) do
      if s:sub(i,i+#literal-1)==literal then i=i+#literal; return value end
    end
    local token=s:sub(i):match("^%-?%d+%.?%d*[eE]?[+%-]?%d*")
    if not token or token:match("^%-?0%d") or token:match("%.$") or token:match("[eE][+%-]?$") or token:match("%.[eE]") then fail() end
    local n=tonumber(token); if not n or n ~= n or n == math.huge or n == -math.huge then fail() end
    i=i+#token; return n
  end
  local value=parse(0); skip(); if i <= #s then fail() end; return value
end
return M
