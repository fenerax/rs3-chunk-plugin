-- Small pure Lua JSON codec for report bodies and picker replies.
-- Lua tables don't say whether they are arrays, so M.array marks one; that keeps an empty
-- quest list encoding as [] rather than {}.
local M = {null = {}}
local arrayMT = {}
function M.array(t) return setmetatable(t or {}, arrayMT) end

-- Escapes quotes, backslashes and every control character.
local function quote(s)
  return '"' .. s:gsub('[%z\1-\31\\"]', function(c)
    local escapes = {['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t'}
    return escapes[c] or string.format('\\u%04x', string.byte(c))
  end) .. '"'
end

-- Object keys are sorted so the same table always encodes to the same text; callers compare
-- and checksum encoded text.
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
      -- Every key must be 1..#v, or values would be silently dropped.
      local count = 0
      for k in pairs(v) do
        if type(k) ~= "number" or k < 1 or k > #v or k % 1 ~= 0 then error("Sparse JSON array") end
        count = count + 1
      end
      if count ~= #v then error("Sparse JSON array") end
      for i = 1, #v do items[i] = encode(v[i], depth + 1) end
    else
      local keys = {}
      for k in pairs(v) do
        if type(k) ~= "string" then error("JSON object keys must be strings") end
        keys[#keys + 1] = k
      end
      table.sort(keys)
      for i, k in ipairs(keys) do items[i] = quote(k) .. ":" .. encode(v[k], depth + 1) end
    end
    seen[v] = nil
    return (isArray and "[" or "{") .. table.concat(items, ",") .. (isArray and "]" or "}")
  end
  return encode(value, 0)
end

-- One code point as UTF-8 bytes. Written out by hand because the client may not have utf8.
local function utf8Char(code)
  if code < 128 then return string.char(code) end
  if code < 2048 then
    return string.char(192 + math.floor(code / 64), 128 + code % 64)
  end
  if code < 65536 then
    return string.char(224 + math.floor(code / 4096), 128 + math.floor(code / 64) % 64, 128 + code % 64)
  end
  return string.char(240 + math.floor(code / 262144), 128 + math.floor(code / 4096) % 64,
    128 + math.floor(code / 64) % 64, 128 + code % 64)
end

-- Strict decoder: anything that isn't valid JSON raises an error naming the byte offset.
-- Arrays come back marked with M.array, and JSON null as M.null.
function M.decode(s)
  assert(type(s) == "string" and #s <= 65536, "Invalid/oversized JSON response")
  local i, parse = 1, nil  -- i is the read position in s
  local function skipSpace()
    local _, last = s:find("^[ \t\r\n]*", i)
    i = (last or i - 1) + 1
  end
  local function fail() error("Invalid JSON at byte " .. i) end
  local function readHex4()
    local digits = s:sub(i, i + 3)
    if #digits ~= 4 or digits:find("[^%x]") then fail() end
    i = i + 4
    return tonumber(digits, 16)
  end
  local function readString()
    i = i + 1
    local parts = {}
    while i <= #s do
      local c = s:sub(i, i)
      i = i + 1
      if c == '"' then return table.concat(parts) end
      if c == "\\" then
        c = s:sub(i, i)
        i = i + 1
        local escapes = {['"'] = '"', ['\\'] = '\\', ['/'] = '/', b = '\b', f = '\f', n = '\n', r = '\r', t = '\t'}
        if c == "u" then
          local code = readHex4()
          if code >= 0xD800 and code <= 0xDBFF then
            -- A high surrogate must be followed by a low one; together they make one code point.
            if s:sub(i, i + 1) ~= "\\u" then fail() end
            i = i + 2
            local low = readHex4()
            if low < 0xDC00 or low > 0xDFFF then fail() end
            code = 65536 + (code - 0xD800) * 1024 + low - 0xDC00
          elseif code >= 0xDC00 and code <= 0xDFFF then
            fail()
          end
          parts[#parts + 1] = utf8Char(code)
        elseif escapes[c] then
          parts[#parts + 1] = escapes[c]
        else
          fail()
        end
      elseif c:byte() < 32 then
        fail()
      else
        parts[#parts + 1] = c
      end
    end
    fail()
  end
  parse = function(depth)
    if depth > 64 then fail() end
    skipSpace()
    local c = s:sub(i, i)
    if c == '"' then return readString() end
    if c == "{" or c == "[" then
      local array = c == "["
      local out = array and M.array() or {}
      local close = array and "]" or "}"
      i = i + 1
      skipSpace()
      if s:sub(i, i) == close then
        i = i + 1
        return out
      end
      while true do
        local key
        if not array then
          if s:sub(i, i) ~= '"' then fail() end
          key = readString()
          skipSpace()
          if s:sub(i, i) ~= ":" then fail() end
          i = i + 1
        end
        local v = parse(depth + 1)
        if array then
          out[#out + 1] = v
        else
          -- Duplicate keys are refused rather than letting the last one win.
          if out[key] ~= nil then fail() end
          out[key] = v
        end
        skipSpace()
        c = s:sub(i, i)
        i = i + 1
        if c == close then return out end
        if c ~= "," then fail() end
        skipSpace()
      end
    end
    for literal, value in pairs({["true"] = true, ["false"] = false, ["null"] = M.null}) do
      if s:sub(i, i + #literal - 1) == literal then
        i = i + #literal
        return value
      end
    end
    -- The pattern is loose, so the checks after it refuse what JSON doesn't allow:
    -- leading zeros, "1." and an exponent with no digits.
    local token = s:sub(i):match("^%-?%d+%.?%d*[eE]?[+%-]?%d*")
    if not token or token:match("^%-?0%d") or token:match("%.$") or token:match("[eE][+%-]?$")
      or token:match("%.[eE]") then
      fail()
    end
    local n = tonumber(token)
    if not n or n ~= n or n == math.huge or n == -math.huge then fail() end
    i = i + #token
    return n
  end
  local value = parse(0)
  skipSpace()
  if i <= #s then fail() end
  return value
end
return M
