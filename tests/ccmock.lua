-- Smoke test for Phoenix Music outside Minecraft.
--
-- Fakes just enough of CC: Tweaked (screen, speakers, modems, rednet, http,
-- files, settings, events and timers) to run phoenixmusic.lua, then throws
-- random clicks, taps and keypresses at it for a few simulated minutes. Any
-- crash, or any error the app prints, fails the run.
--
-- Usage: lua5.2 tests/ccmock.lua <scenario> <seed>
-- Scenarios: computer, pocket, medium, monitor, nospeaker, remote,
--            remote_wide, link, link_basic

local real_clock = os.clock
local scenario = arg[1] or "computer"
local seed = tonumber(arg[2]) or 1
math.randomseed(seed)

local SETUPS = {
  computer   = { w = 51, h = 19, speakers = 1, modem = true },
  pocket     = { w = 26, h = 20, speakers = 1, modem = true },
  medium     = { w = 39, h = 13, speakers = 2, modem = true },
  monitor    = { w = 57, h = 24, speakers = 1, modem = true, monitor = true, args = { "monitor_0", "0.5" } },
  nospeaker  = { w = 51, h = 19, speakers = 0, modem = true },
  remote     = { w = 26, h = 20, speakers = 0, modem = true, args = { "remote" } },
  remote_wide = { w = 51, h = 19, speakers = 0, modem = true, args = { "remote" } },
  link       = { w = 51, h = 19, speakers = 1, modem = true, args = { "link" } },
  link_basic = { w = 51, h = 19, speakers = 1, modem = true, args = { "link" }, basic = true },
  wired      = { w = 51, h = 19, speakers = 2, modem = true, wired = true },
  basic_auto = { w = 51, h = 19, speakers = 1, modem = true, basic = true },
  pocket_nospeaker = { w = 26, h = 20, speakers = 0, modem = true, pocket = true },
  pocket_noisy_remote = { w = 26, h = 20, speakers = 1, modem = true, pocket = true, args = { "remote" } },
}
local setup = assert(SETUPS[scenario], "unknown scenario " .. scenario)
local SIM_SECONDS = 240

local failures = {}
local stats = { chunks = 0, searches = 0, songs = 0, failed_songs = 0, updates = 0, link_audio = 0 }
local function fail(msg)
  failures[#failures + 1] = msg
  io.stderr:write("[" .. scenario .. " seed " .. seed .. "] " .. msg .. "\n")
end

---------------------------------------------------------------------------
-- Simulated time, events and timers
---------------------------------------------------------------------------
local now = 0                 -- simulated seconds
local queue = {}              -- events waiting to be delivered
local timers = {}             -- id -> fire time
local scripted = {}           -- { t = time, ev = {...} }, sorted when consumed
local next_timer = 1

-- Watchdog: CC kills code that runs too long without yielding, so do the
-- same, with a traceback showing where it got stuck.
local budget = 0
local function watchdog()
  budget = budget + 1
  if budget > 40 then
    budget = 0
    error("too long without yielding (stuck in a loop?)", 2)
  end
end
local real_create = coroutine.create
coroutine.create = function(f)
  local co = real_create(f)
  debug.sethook(co, watchdog, "", 5000000)
  return co
end
local real_resume = coroutine.resume
coroutine.resume = function(co, ...)
  budget = 0
  return real_resume(co, ...)
end

local function push(...) queue[#queue + 1] = table.pack(...) end
local function at(t, ...) scripted[#scripted + 1] = { t = t, ev = table.pack(...) } end

local function startTimer(secs)
  local id = next_timer
  next_timer = next_timer + 1
  timers[id] = now + math.max(0, tonumber(secs) or 0)
  return id
end

local function nextEvent()
  if #queue > 0 then return table.remove(queue, 1) end
  -- Nothing waiting: jump ahead to the next timer or scripted event
  local best_t, best_kind, best_key = math.huge, nil, nil
  for id, t in pairs(timers) do
    if t < best_t or (t == best_t and best_kind == "timer" and id < best_key) then
      best_t, best_kind, best_key = t, "timer", id
    end
  end
  for i, s in ipairs(scripted) do
    if s.t < best_t then best_t, best_kind, best_key = s.t, "script", i end
  end
  if not best_kind or best_t > SIM_SECONDS then return nil end
  now = math.max(now, best_t)
  if best_kind == "timer" then
    timers[best_key] = nil
    return table.pack("timer", best_key)
  end
  return table.remove(scripted, best_key).ev
end

---------------------------------------------------------------------------
-- Globals CC provides
---------------------------------------------------------------------------
os.epoch = function() return math.floor(now * 1000) + 1700000000000 end
os.clock = function() return now end
os.time = function() return (7 + now / 50) % 24 end
os.startTimer = startTimer
os.cancelTimer = function(id) timers[id] = nil end
os.queueEvent = function(...) push(...) end
os.getComputerID = function() return 1 end
os.getComputerLabel = function() return nil end
os.pullEventRaw = function(filter) return coroutine.yield(filter) end
os.pullEvent = function(filter)
  local ev = table.pack(coroutine.yield(filter))
  if ev[1] == "terminate" then error("Terminated", 0) end
  return table.unpack(ev, 1, ev.n)
end
os.run = function() return true end

function sleep(t)
  local id = startTimer(t)
  repeat local _, p = os.pullEvent("timer") until p == id
end

function printError(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
  fail("app printed an error: " .. table.concat(parts, " "))
end

-- parallel: the same logic as CC's own
local function create(...)
  local fns = table.pack(...)
  local cos = {}
  for i = 1, fns.n do
    local f = fns[i]
    if type(f) ~= "function" then error("bad argument #" .. i .. " (function expected, got " .. type(f) .. ")", 3) end
    cos[i] = coroutine.create(f)
  end
  return cos
end
local function runUntilLimit(cos, limit)
  local count = #cos
  if count < 1 then return 0 end
  local living = count
  local filters = {}
  local ev = { n = 0 }
  while true do
    for n = 1, count do
      local r = cos[n]
      if r and (filters[r] == nil or filters[r] == ev[1] or ev[1] == "terminate") then
        local ok, param = coroutine.resume(r, table.unpack(ev, 1, ev.n))
        if not ok then error(tostring(param) .. "\n" .. debug.traceback(r), 0) end
        filters[r] = param
        if coroutine.status(r) == "dead" then
          cos[n] = nil
          living = living - 1
          if living <= limit then return n end
        end
      end
    end
    ev = table.pack(os.pullEventRaw())
  end
end
parallel = {
  waitForAny = function(...) local c = create(...); return runUntilLimit(c, #c - 1) end,
  waitForAll = function(...) local c = create(...); return runUntilLimit(c, 0) end,
}

-- colours and keys
colours = {}
local names = { "white", "orange", "magenta", "lightBlue", "yellow", "lime", "pink", "grey",
  "lightGrey", "cyan", "purple", "blue", "brown", "green", "red", "black" }
for i, n in ipairs(names) do colours[n] = 2 ^ (i - 1) end
colours.gray, colours.lightGray = colours.grey, colours.lightGrey
function colours.toBlit(c)
  for i = 0, 15 do if 2 ^ i == c then return ("0123456789abcdef"):sub(i + 1, i + 1) end end
  error("toBlit: not a colour: " .. tostring(c), 2)
end
colors = colours
keys = { left = 203, right = 205, up = 200, down = 208, tab = 15, enter = 28, backspace = 14 }

-- Screens
local function checkPos(t, what)
  if type(t.cx) ~= "number" or type(t.cy) ~= "number" then error(what .. ": bad cursor position", 3) end
end
local function makeTerm(w, h, colour)
  local t = { cx = 1, cy = 1, fg = colours.white, bg = colours.black }
  function t.getSize() return w, h end
  function t.setCursorPos(x, y)
    if type(x) ~= "number" or type(y) ~= "number" then error("setCursorPos expects numbers", 2) end
    t.cx, t.cy = x, y
  end
  function t.getCursorPos() return t.cx, t.cy end
  function t.write(s)
    if type(s) ~= "string" and type(s) ~= "number" then error("write expects a string, got " .. type(s), 2) end
    checkPos(t, "write")
    t.cx = t.cx + #tostring(s)
  end
  function t.blit(a, b, c)
    if type(a) ~= "string" or #a ~= #b or #b ~= #c then error("blit: arguments must be strings of equal length", 2) end
    if b:find("[^0-9a-f]") or c:find("[^0-9a-f]") then error("blit: bad colour code", 2) end
    t.cx = t.cx + #a
  end
  function t.clear() end
  function t.clearLine() end
  function t.scroll() end
  local function setc(field)
    return function(c)
      if type(c) ~= "number" then error("colour expected, got " .. type(c), 2) end
      colours.toBlit(c)
      t[field] = c
    end
  end
  t.setTextColour, t.setTextColor = setc("fg"), setc("fg")
  t.setBackgroundColour, t.setBackgroundColor = setc("bg"), setc("bg")
  function t.getTextColour() return t.fg end
  t.getTextColor = t.getTextColour
  function t.getBackgroundColour() return t.bg end
  t.getBackgroundColor = t.getBackgroundColour
  function t.isColour() return colour end
  t.isColor = t.isColour
  function t.setCursorBlink() end
  function t.getPaletteColour() return 0, 0, 0 end
  t.getPaletteColor = t.getPaletteColour
  function t.setPaletteColour(c, r)
    colours.toBlit(c)
    if type(r) ~= "number" then error("palette colour expected", 2) end
  end
  t.setPaletteColor = t.setPaletteColour
  function t.setVisible() end
  function t.redraw() end
  function t.reposition() end
  function t.setTextScale(s) if type(s) ~= "number" then error("text scale must be a number", 2) end end
  return t
end

local screen = makeTerm(setup.monitor and 51 or setup.w, setup.monitor and 19 or setup.h, not setup.basic)
local current = screen
term = setmetatable({
  current = function() return current end,
  redirect = function(t) local old = current; current = t; return old end,
  native = function() return screen end,
}, { __index = function(_, k)
  return function(...) local f = current[k]; if not f then error("term." .. k .. " missing", 2) end; return f(...) end
end })

window = {
  create = function(parent, x, y, w, h)
    if type(parent) ~= "table" then error("window.create: bad parent", 2) end
    return makeTerm(w, h, parent.isColour())
  end,
}

-- read(): typing ends with Enter; anything else is ignored
function read(mask, history, complete, default)
  local s = default or ""
  while true do
    local ev, p = os.pullEvent()
    if ev == "char" then s = s .. p
    elseif ev == "key" and p == keys.enter then return s
    elseif ev == "key" and p == keys.backspace then s = s:sub(1, -2) end
  end
end

-- Files and settings
local files = {}
fs = {
  exists = function(p) return files[p] ~= nil end,
  delete = function(p) files[p] = nil end,
  copy = function(a, b) files[b] = files[a] end,
  getName = function(p) return (p:match("[^/]+$")) or p end,
  open = function(p, mode)
    if mode:sub(1, 1) == "r" then
      if not files[p] then return nil end
      local data = files[p]
      return { readAll = function() return data end, close = function() end }
    end
    local buf = {}
    return {
      write = function(s) buf[#buf + 1] = tostring(s) end,
      close = function() files[p] = table.concat(buf) end,
    }
  end,
}
local prog_path = "phoenixmusic.lua"
do
  local f = assert(io.open(prog_path, "rb"))
  files[prog_path] = f:read("*a")
  f:close()
end

local defs, vals = {}, {}
settings = {
  define = function(k, o) defs[k] = o end,
  get = function(k, d)
    if vals[k] ~= nil then return vals[k] end
    if d ~= nil then return d end
    return defs[k] and defs[k].default
  end,
  set = function(k, v)
    if defs[k] and defs[k].type and type(v) ~= defs[k].type then
      error("setting " .. k .. " expects " .. defs[k].type .. ", got " .. type(v), 2)
    end
    vals[k] = v
  end,
  save = function() return true end,
}

local relaunched = nil
shell = {
  getRunningProgram = function() return prog_path end,
  run = function(p, ...) relaunched = table.pack(...); return true end,
}

-- textutils
local function serialise(v, indent)
  if type(v) == "table" then
    local out = {}
    for k, x in pairs(v) do
      out[#out + 1] = "[" .. serialise(k) .. "]=" .. serialise(x)
    end
    return "{" .. table.concat(out, ",") .. "}"
  elseif type(v) == "string" then return string.format("%q", v)
  elseif type(v) == "number" or type(v) == "boolean" or v == nil then return tostring(v)
  else error("can't serialise " .. type(v), 2) end
end

local function decodeJSON(s)
  local i = 1
  local function ws() i = s:find("[^ \t\r\n]", i) or #s + 1 end
  local value
  local function str()
    i = i + 1
    local out = {}
    while true do
      local c = s:sub(i, i)
      if c == "" then error("unterminated string") end
      if c == '"' then i = i + 1; break end
      if c == "\\" then
        local e = s:sub(i + 1, i + 1)
        local map = { n = "\n", t = "\t", r = "\r", b = "\b", f = "\f", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
        if e == "u" then
          local code = tonumber(s:sub(i + 2, i + 5), 16)
          out[#out + 1] = code < 256 and string.char(code) or "?"
          i = i + 6
        else
          out[#out + 1] = map[e] or e
          i = i + 2
        end
      else
        out[#out + 1] = c
        i = i + 1
      end
    end
    return table.concat(out)
  end
  function value()
    ws()
    local c = s:sub(i, i)
    if c == "{" then
      i = i + 1
      local t = {}
      ws()
      if s:sub(i, i) == "}" then i = i + 1; return t end
      while true do
        ws()
        local k = str()
        ws(); i = i + 1 -- :
        t[k] = value()
        ws()
        local d = s:sub(i, i); i = i + 1
        if d == "}" then return t end
      end
    elseif c == "[" then
      i = i + 1
      local t = {}
      ws()
      if s:sub(i, i) == "]" then i = i + 1; return t end
      while true do
        t[#t + 1] = value()
        ws()
        local d = s:sub(i, i); i = i + 1
        if d == "]" then return t end
      end
    elseif c == '"' then return str()
    elseif s:sub(i, i + 3) == "true" then i = i + 4; return true
    elseif s:sub(i, i + 4) == "false" then i = i + 5; return false
    elseif s:sub(i, i + 3) == "null" then i = i + 4; return nil
    else
      local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
      i = i + #num
      return tonumber(num)
    end
  end
  local ok, v = pcall(value)
  if ok then return v end
  return nil
end

textutils = {
  serialise = serialise,
  serialize = serialise,
  unserialise = function(s) local f = load("return " .. s, "=unserialise", "t", {}); if f then local ok, v = pcall(f); if ok then return v end end end,
  unserialiseJSON = decodeJSON,
  urlEncode = function(s) return (tostring(s):gsub("[^%w]", function(c) return string.format("%%%02X", c:byte()) end)) end,
}
textutils.unserialize = textutils.unserialise

-- The audio decoder (just the right shape: 8 samples per byte)
package.preload["cc.audio.dfpwm"] = function()
  return {
    make_decoder = function()
      return function(chunk)
        if type(chunk) ~= "string" then error("decoder expects a string", 2) end
        local out = {}
        for k = 1, #chunk * 8 do out[k] = (k % 7) * 9 - 27 end
        return out
      end
    end,
  }
end

-- Peripherals
local speakers = {}
local function makeSpeaker(name)
  local sp = { name = name, free_at = 0, end_at = 0 }
  function sp.playAudio(buf, vol)
    if type(buf) ~= "table" then error("playAudio expects a table", 2) end
    if #buf > 128 * 1024 then error("playAudio: buffer too big (" .. #buf .. ")", 2) end
    if vol ~= nil and (type(vol) ~= "number" or vol < 0 or vol > 3) then error("playAudio: bad volume " .. tostring(vol), 2) end
    for k = 1, math.min(#buf, 64) do
      local v = buf[k]
      if type(v) ~= "number" or v < -128 or v > 127 or v ~= math.floor(v) then error("playAudio: bad sample " .. tostring(v), 2) end
    end
    if now < sp.free_at then return false end
    stats.chunks = stats.chunks + 1
    local start = math.max(now, sp.end_at)
    sp.end_at = start + #buf / 48000
    sp.free_at = start
    -- deliver speaker_audio_empty when there's room again
    scripted[#scripted + 1] = { t = math.max(now, start) + 0.001, ev = table.pack("speaker_audio_empty", sp.name) }
    return true
  end
  function sp.stop() sp.free_at, sp.end_at = 0, 0 end
  return sp
end
for k = 1, setup.speakers do speakers["speaker_" .. k] = makeSpeaker("speaker_" .. k) end

local modem = { isWireless = function() return not setup.wired end }
if setup.pocket then pocket = {} end
local monitor = makeTerm(setup.w, setup.h, true)

local function typeOf(name)
  if speakers[name] then return "speaker" end
  if name == "back" and setup.modem then return "modem" end
  if name == "monitor_0" and setup.monitor then return "monitor" end
end
peripheral = {
  getNames = function()
    local list = {}
    for n in pairs(speakers) do list[#list + 1] = n end
    if setup.modem then list[#list + 1] = "back" end
    if setup.monitor then list[#list + 1] = "monitor_0" end
    table.sort(list)
    return list
  end,
  getType = function(n) return typeOf(n) end,
  hasType = function(n, t) return typeOf(n) == t end,
  wrap = function(n)
    if speakers[n] then return speakers[n] end
    if n == "back" and setup.modem then return modem end
    if n == "monitor_0" and setup.monitor then return monitor end
  end,
  find = function(t)
    local out = {}
    for _, n in ipairs(peripheral.getNames()) do
      if typeOf(n) == t then out[#out + 1] = peripheral.wrap(n) end
    end
    return table.unpack(out)
  end,
  getName = function(obj)
    for n, sp in pairs(speakers) do if sp == obj then return n end end
    if obj == monitor then return "monitor_0" end
    return "back"
  end,
}

-- rednet
local sent = 0
rednet = {
  open = function() end,
  isOpen = function() return false end,
  broadcast = function(msg, proto)
    if type(msg) ~= "table" then error("rednet message should be a table here", 2) end
    if msg.type == "audio" then stats.link_audio = stats.link_audio + 1 end
    sent = sent + 1
  end,
  send = function(id, msg, proto) sent = sent + 1 end,
  receive = function(proto, timeout)
    local timer = timeout and startTimer(timeout)
    while true do
      local ev, a, b, c = os.pullEvent()
      if ev == "rednet_message" and (proto == nil or c == proto) then return a, b, c end
      if ev == "timer" and a == timer then return nil end
    end
  end,
}

-- http
local function utf8char(cp)
  if cp < 0x80 then return string.char(cp) end
  if cp < 0x800 then return string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64) end
  if cp < 0x10000 then
    return string.char(0xE0 + math.floor(cp / 4096), 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
  end
  return string.char(0xF0 + math.floor(cp / 262144), 0x80 + math.floor(cp / 4096) % 64,
    0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
end
local dot = utf8char(0xB7)
local note = utf8char(0x1F3B5)
local bengali = utf8char(0x0986) .. utf8char(0x09AE) .. utf8char(0x09BE) .. utf8char(0x09B0)
local SEARCH_JSON = '['
  .. '{"name":"Hosting is expensive! Please help.","artist":"patreon.com/exclamatory"},'
  .. '{"id":"aaa","name":"Alan Walker - Faded","artist":"3:33 ' .. dot .. ' Alan Walker"},'
  .. '{"id":"bbb","name":"Greatest Hits Mix","artist":"1:09:27 ' .. dot .. ' EDM Plus"},'
  .. '{"id":"ccc","name":"' .. bengali .. ' ' .. bengali .. '","artist":"2:23 ' .. dot .. ' Ekattor TV"},'
  .. '{"id":"ddd","name":"' .. note .. 'BGM' .. note .. 'Top 50","artist":"3:05:50 ' .. dot .. ' ' .. note .. note .. 'Music"},'
  .. '{"id":"eee","name":"It' .. utf8char(0x2019) .. 's a song ' .. utf8char(0x2013) .. ' live","artist":"4:01 ' .. dot .. ' Someone"},'
  .. '{"id":"pl1","type":"playlist","name":"A playlist","artist":"Playlist ' .. dot .. ' 2 videos ' .. dot .. ' Me",'
  .. '"playlist_items":[{"id":"p1","name":"One","artist":"1:00 ' .. dot .. ' Me"},{"id":"p2","name":"Two","artist":"1:30 ' .. dot .. ' Me"}]}'
  .. ']'

local function makeHandle(body)
  local pos = 0
  return {
    readAll = function() local r = body:sub(pos + 1); pos = #body; return r end,
    read = function(n) if pos >= #body then return nil end local r = body:sub(pos + 1, pos + (n or 1)); pos = pos + #r; return r end,
    close = function() end,
    getResponseHeaders = function() return {} end,
  }
end

local function respond(url)
  if url:find("raw.githubusercontent.com", 1, true) then
    -- Only some runs see an update, so the others get to run for the whole time
    if url:find("version.txt", 1, true) then
      return (seed % 3 == 0) and "9.9.9\nA test update\nAnother line" or "1.0.0\nOld"
    end
    stats.updates = stats.updates + 1
    return files[prog_path]
  end
  if url:find("search=", 1, true) then
    stats.searches = stats.searches + 1
    return SEARCH_JSON
  end
  if url:find("&id=", 1, true) then
    if url:find("id=bbb", 1, true) then -- a long video: the server gives up
      stats.failed_songs = stats.failed_songs + 1
      return nil
    end
    stats.songs = stats.songs + 1
    return string.rep("\170\85", 22000) -- about 7 seconds of audio
  end
  return nil
end

http = {
  request = function(req)
    local url = type(req) == "table" and req.url or req
    if type(url) ~= "string" then error("http.request: bad url", 2) end
    local body = respond(url)
    if body then
      scripted[#scripted + 1] = { t = now + 0.4, ev = table.pack("http_success", url, makeHandle(body)) }
    else
      scripted[#scripted + 1] = { t = now + 0.4, ev = table.pack("http_failure", url, "Not found") }
    end
    return true
  end,
}
http.get = function(req)
  local url = type(req) == "table" and req.url or req
  http.request(req)
  while true do
    local ev, u, h = os.pullEvent()
    if ev == "http_success" and u == url then return h end
    if ev == "http_failure" and u == url then return nil, h end
  end
end

---------------------------------------------------------------------------
-- What happens during the run
---------------------------------------------------------------------------
local W, H = setup.w, setup.h
local function click(x, y)
  if setup.monitor then return "monitor_touch", "monitor_0", x, y end
  return "mouse_click", 1, x, y
end

-- A linked speaker and a remote say hello now and then (player scenarios)
local function hostChatter()
  for t = 1, SIM_SECONDS, 5 do
    at(t, "rednet_message", 7, { type = "hello", group = "default", pin = "", label = "Kitchen", speakers = 2, volume = 100 }, "phoenix_music")
  end
  for t = 20, SIM_SECONDS, 37 do
    local cmds = { "toggle", "next", "prev", "volume", "mute", "seek", "fav", "loop", "shuffle", "restart", "stop" }
    at(t, "rednet_message", 9, { type = "cmd", group = "default", pin = "", cmd = cmds[math.random(#cmds)], value = math.random() * 3 }, "phoenix_music")
  end
end

-- Kick things off with a search and play, then go wild
local function playerScript()
  at(2, click(3, 1))                          -- (some tab)
  at(2.5, "char", "/")                         -- search
  for k, c in ipairs({ "a", "l", "a", "n" }) do at(2.6 + k * 0.05, "char", c) end
  at(3, "key", keys.enter)
  at(4, click(math.floor(W / 2), 7))           -- first result
  at(4.5, click(math.floor(W / 2), math.floor(H / 2) - 2)) -- an option in the menu
  at(5, "char", " ")
  hostChatter()
end

local function linkScript()
  local t0 = 3
  for k = 0, 60 do
    local t = t0 + k * 2.7
    at(t, "rednet_message", 5, {
      type = "audio", group = "default", pin = "", data = string.rep("\85", 16384),
      at = math.floor((t + (k % 9 == 0 and -1 or 2.5)) * 1000) + 1700000000000, volume = 1.5,
      name = "Song " .. k, artist = "3:00 - Someone", smoothing = (k % 2 == 0) and "light" or "off",
    }, "phoenix_music")
    if k % 13 == 12 then at(t + 1, "rednet_message", 5, { type = "stop", group = "default", pin = "" }, "phoenix_music") end
    if k % 17 == 5 then at(t + 0.5, "rednet_message", 5, { type = "rxvol", group = "default", pin = "", target = 1, value = 60 }, "phoenix_music") end
    if k % 11 == 3 then at(t + 0.2, "rednet_message", 5, { type = "ping", group = "default", pin = "" }, "phoenix_music") end
  end
end

local function remoteScript()
  for t = 1, SIM_SECONDS, 0.5 do
    at(t, "rednet_message", 3, {
      type = "state", group = "default", pin = "",
      name = (t % 40 < 30) and "A song" or nil, artist = "3:00 - Someone", playing = t % 20 < 15,
      loading = false, error = false, pos = t % 180, total = 180, seekable = true,
      volume = 1.5, muted = false, looping = math.floor(t) % 3, shuffle = t % 30 < 10, fav = t % 50 < 5, queue = 3,
    }, "phoenix_music")
  end
end

-- Random clicks, taps, keys and typing (never "q", which quits)
local function monkey()
  local chars = { " ", "n", "p", "s", "r", "l", "m", "f", "h", "v", "+", "-", "/", "a", "b", "u", "g" }
  if scenario:find("^link") or scenario == "basic_auto" then
    -- Don't let it rename the Link or PIN, or it stops hearing the fake player
    chars = { " ", "+", "-", "a", "b", "+", "-", "u" }
  end
  local keylist = { keys.left, keys.right, keys.up, keys.down, keys.tab, keys.enter, keys.enter, keys.backspace }
  local t = 6
  while t < SIM_SECONDS - 5 do
    t = t + 0.15 + math.random() * 0.6
    local r = math.random()
    if r < 0.62 then
      -- (the bottom row of the remote holds the Link and PIN buttons)
      at(t, click(math.random(1, W), math.random(1, scenario:find("^remote") and H - 1 or H)))
    elseif r < 0.70 then
      local x, y = math.random(1, W), math.random(1, H)
      at(t, "mouse_drag", 1, x, y)
      if math.random() < 0.5 then at(t + 0.05, "mouse_up", 1, x, y) end
    elseif r < 0.80 then
      at(t, "key", keylist[math.random(#keylist)])
    elseif r < 0.95 then
      at(t, "char", chars[math.random(#chars)])
    else
      at(t, "mouse_scroll", math.random(0, 1) * 2 - 1, math.random(1, W), math.random(1, H))
    end
  end
end

if scenario:find("^link") or scenario == "basic_auto" then linkScript()
elseif scenario:find("^remote") then remoteScript()
else playerScript() end
monkey()

---------------------------------------------------------------------------
-- Run it
---------------------------------------------------------------------------
local chunk, err = loadfile(prog_path)
if not chunk then
  fail("doesn't compile: " .. tostring(err))
  os.exit(1)
end

local args = setup.args or {}
local main = coroutine.create(function() return chunk(table.unpack(args)) end)
local ok, filter = coroutine.resume(main)
if not ok then fail("crashed: " .. tostring(filter) .. "\n" .. debug.traceback(main)) end
local delivered = 0
local last_now, same_time = -1, 0
local recent = {}
while ok and coroutine.status(main) ~= "dead" do
  local ev = nextEvent()
  if not ev then break end
  -- Events piling up without time moving on means something keeps
  -- re-queueing itself forever.
  if now == last_now then
    same_time = same_time + 1
    if same_time > 50000 then
      fail("event storm at " .. now .. "s: the last event was " .. tostring(ev[1]))
      break
    end
  else
    last_now, same_time = now, 0
  end
  recent[#recent + 1] = string.format("%.3f %s %s", now, tostring(ev[1]), tostring(ev[2]))
  if #recent > 40 then table.remove(recent, 1) end
  if real_clock() > 25 then
    fail("too slow / stuck at " .. now .. "s sim after " .. delivered .. " events. Last events:\n"
      .. table.concat(recent, "\n") .. "\nstats: chunks " .. stats.chunks .. ", songs " .. stats.songs)
    break
  end
  if filter == nil or filter == ev[1] or ev[1] == "terminate" then
    delivered = delivered + 1
    ok, filter = coroutine.resume(main, table.unpack(ev, 1, ev.n))
    if not ok then fail("crashed: " .. tostring(filter) .. "\n" .. debug.traceback(main)) end
  end
end

local ended = coroutine.status(main) == "dead" and "app quit" or "time up"
local extra = relaunched and (" (relaunched with: " .. table.concat(relaunched, " ") .. ")") or ""
print(string.format("[%s seed %d] %s after %.0fs sim, %d events; downloads %d (+%d failed), searches %d, "
  .. "speaker chunks %d, link audio sent %d, update downloads %d%s",
  scenario, seed, ended, now, delivered, stats.songs, stats.failed_songs, stats.searches,
  stats.chunks, stats.link_audio, stats.updates, extra))
os.exit(#failures == 0 and 0 or 1)
