--[[
  Phoenix Music 3.6.2 for CC: Tweaked
  (c) 2026 Phoenix Software - https://github.com/MADDXSTUDIOS/phoenix-music

  A music player built on terreng's computercraft-streaming-music.
  Modifications Copyright (c) 2026 Phoenix Software, released under the same
  MIT License as the original (reproduced below). The music server and the
  way audio is decoded and fed to the speakers are his; everything else here
  is new: the interface, playback controls, queue, favourites and playlists,
  Speaker Link (synced wireless speakers), the remote, the visualiser,
  timers, themes, the song cache and auto-updates.

  Usage:  phoenixmusic                 run on this computer's screen
          phoenixmusic <monitor> [s]   run on a monitor (s = text scale, default 0.5)
          phoenixmusic link [name]     be a wireless speaker on Speaker Link "name"
                                       (a standard grey computer always starts as one)
          phoenixmusic remote          remote control (pocket computer + ender modem)
          (Settings can switch between player, remote and linked speaker too.)

  Speaker Link: give the player, linked speakers and remotes a wireless or
  ender modem. Linked speakers play whatever the player on their Link is
  playing; remotes control it. The Link name and PIN are set from the
  Settings tab (or on a linked speaker, with the l and p keys). The player
  doesn't need its own speaker if it has linked ones.

  Keys:   space play/pause   s stop   n next   p previous   r restart
          left/right seek 10s   +/- volume   m mute   l loop   / search
          f favourite   h shuffle   v visualiser
          tab switch tab   q quit

  ---------------------------------------------------------------------------
  Original work: https://github.com/terreng/computercraft-streaming-music

  MIT License

  Copyright (c) 2024 Terren Gurule

  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in all
  copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
  SOFTWARE.
]]

-- Server settings (unchanged from the original; the server checks "v")
local api_base_url = "https://ipod-2to6magyna-uc.a.run.app/"
local version = "2.1"

-- About info (shown on the About tab)
local APP = {
  name = "Phoenix Music",
  version = "3.6.2",
  publisher = "Phoenix Software",
  year = "2026",
  original = "computercraft-streaming-music",
  original_author = "Terren Gurule (terreng)",
  original_url = "github.com/terreng/computercraft-streaming-music",
}

local dfpwm = require "cc.audio.dfpwm"

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------
local CHUNK = 16 * 1024          -- bytes per chunk, same size the original used
local BYTES_PER_SEC = 6000       -- DFPWM: 48 kHz, 1 bit per sample
local VOLUME_MAX = 3
local VOLUME_STEP = 0.25
local SEEK_STEP = 10             -- seconds per arrow-key seek
local HISTORY_MAX = 50
local STATE_FILE = ".phoenix_music"  -- saved queue, history and settings
local LIBRARY_FILE = ".phoenix_library"  -- favourites and playlists
local PLAYLIST_MAX, PLAYLIST_TRACKS_MAX = 50, 500

-- Glyphs from the CC font
local G = {
  note = "\14", play = "\16", left = "\17", prev = "\171", next = "\187",
  pause = "\149\149", stop = "\143", up = "\30", down = "\31", dot = "\7",
  heart = "\3", more = "\183\183\183", close = "\215",
}

---------------------------------------------------------------------------
-- Speaker Link (wireless speakers over rednet)
---------------------------------------------------------------------------
local PROTOCOL = "phoenix_music"
local RECEIVER_TIMEOUT = 15        -- seconds before a silent receiver is dropped

settings.define("phoenix_music.group", {
  description = "Phoenix Music Speaker Link name this computer plays to or listens on",
  default = "default",
  type = "string",
})

settings.define("phoenix_music.pin", {
  description = "Optional PIN shared by a Phoenix Music player and its linked speakers and remotes",
  default = "",
  type = "string",
})
settings.define("phoenix_music.background", {
  description = "Phoenix Music background: Dark, Midnight or Light",
  default = "Dark",
  type = "string",
})
settings.define("phoenix_music.accent", {
  description = "Phoenix Music accent colour",
  default = "Orange",
  type = "string",
})
settings.define("phoenix_music.smoothing", {
  description = "Phoenix Music audio smoothing: off, light or strong",
  default = "off",
  type = "string",
})
settings.define("phoenix_music.hide_long", {
  description = "Hide search results over 15 minutes (the server can't play them)",
  default = true,
  type = "boolean",
})
settings.define("phoenix_music.nospeaker_mode", {
  description = "What a computer with no speaker does: remote or player",
  default = "",
  type = "string",
})
settings.define("phoenix_music.update_channel", {
  description = "Phoenix Music update branch on GitHub (main, or dev for testing)",
  default = "main",
  type = "string",
})
settings.define("phoenix_music.rx_volume", {
  description = "This linked speaker's own volume, in percent of the player's",
  default = 100,
  type = "number",
})

local SYNC_LEAD = 600              -- ms between sending a fresh start and everyone playing it
local LEAD_AHEAD = 3000            -- ms ahead a player with no speaker sends audio to linked ones

-- Small helpers shared by the player, receivers and remotes.
local P = {}
function P.trim(str)
  return (tostring(str or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end
-- Smoothing: a simple low-pass filter over the decoded audio. DFPWM comes
-- out as harsh little steps; rounding them off takes the fizz out of it at
-- the cost of a bit of treble. Lower number = smoother.
P.SMOOTH = { light = 0.6, strong = 0.6 } -- "strong" was dropped; it now means light

-- Filters buf in place. "last" carries the filter on from the previous chunk
-- so there's no click at the joins; returns the new value to pass next time.
function P.smooth(buf, level, last)
  local a = P.SMOOTH[level]
  if not a then return nil end
  local y = last or buf[1] or 0
  local floor = math.floor
  for i = 1, #buf do
    y = y + a * (buf[i] - y)
    local v = floor(y + 0.5)
    if v > 127 then v = 127 elseif v < -128 then v = -128 end
    buf[i] = v
  end
  return y
end

-- A message for our group, with the right PIN?
function P.ok(msg, group, pin)
  return type(msg) == "table" and msg.group == group and tostring(msg.pin or "") == (pin or "")
end

---------------------------------------------------------------------------
-- Updates from GitHub (no UI here, so the player, linked speakers and
-- remotes can all use it)
---------------------------------------------------------------------------
P.REPO = "MADDXSTUDIOS/phoenix-music"
P.FILE = "phoenixmusic.lua"

-- Where this program lives, so updates and restarts go to the right file.
P.self_path = (shell and shell.getRunningProgram and shell.getRunningProgram()) or P.FILE

function P.rawUrl(name)
  local channel = P.trim(settings.get("phoenix_music.update_channel"))
  if channel == "" then channel = "main" end
  -- The timestamp stops GitHub's cache handing us an old copy
  return "https://raw.githubusercontent.com/" .. P.REPO .. "/" .. channel .. "/" .. name
    .. "?t=" .. os.epoch("utc")
end

function P.fetch(url)
  local ok, h = pcall(http.get, { url = url, binary = true })
  if not ok or not h then return nil end
  local body = h.readAll()
  h.close()
  return body
end

-- True if version a is newer than b ("3.10.0" beats "3.9.2").
function P.newer(a, b)
  local pa, pb = {}, {}
  for n in tostring(a):gmatch("%d+") do pa[#pa + 1] = tonumber(n) end
  for n in tostring(b):gmatch("%d+") do pb[#pb + 1] = tonumber(n) end
  for i = 1, math.max(#pa, #pb) do
    local x, y = pa[i] or 0, pb[i] or 0
    if x ~= y then return x > y end
  end
  return false
end

-- Reads version.txt from the repo: the first line is the version, the rest
-- is what's new. Returns { version, notes, newer } or nil and a reason.
function P.checkUpdate()
  local body = P.fetch(P.rawUrl("version.txt"))
  if not body then return nil, "Couldn't reach GitHub" end
  local lines = {}
  for l in body:gmatch("[^\r\n]+") do lines[#lines + 1] = l end
  local v = lines[1] and lines[1]:match("^%s*v?([%d%.]+)%s*$")
  if not v then return nil, "Bad version file" end
  table.remove(lines, 1)
  return { version = v, notes = lines, newer = P.newer(v, APP.version) }
end

-- Downloads the latest version over this program, keeping the old one as a
-- .bak. The download has to load cleanly first, so a bad upload can't break
-- anyone's install.
function P.installUpdate()
  local code = P.fetch(P.rawUrl(P.FILE))
  if not code or #code < 1000 then return false, "Download failed" end
  if not load(code, "=" .. P.FILE, "t", {}) then return false, "The new version didn't pass its check" end
  if not code:find("Phoenix Music", 1, true) then return false, "That download isn't Phoenix Music" end
  local path = P.self_path
  local backup = path .. ".bak"
  if fs.exists(backup) then fs.delete(backup) end
  if fs.exists(path) then fs.copy(path, backup) end
  local f = fs.open(path, "wb")
  if not f then return false, "Couldn't save the update" end
  f.write(code)
  f.close()
  return true
end

-- Runs this program again (after an update, or to switch modes).
function P.relaunch(list)
  list = list or {}
  if shell and shell.run then
    shell.run(P.self_path, table.unpack(list))
  else
    os.run({ shell = shell }, P.self_path, table.unpack(list))
  end
end

-- Opens rednet on every modem attached. Returns true if there was one.
-- Most functions live in F: CC's Lua caps how many locals can be in scope.
local F = {}

-- Speakers on a wired modem network are found like any other speaker. Speaker
-- Link and the remote need a wireless or ender modem; when there is one,
-- wired modems join in too so linked computers on the cable hear us as well.
-- Returns true if there's a wireless (or ender) modem.
function F.openModems()
  local wifi = false
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.hasType(name, "modem") then
      local m = peripheral.wrap(name)
      if m and m.isWireless and m.isWireless() then wifi = true end
    end
  end
  if wifi then
    for _, name in ipairs(peripheral.getNames()) do
      if peripheral.hasType(name, "modem") and not rednet.isOpen(name) then rednet.open(name) end
    end
  end
  return wifi
end

-- Linked speaker mode: plays whatever the player on our Link sends.
-- Returns "player" or "restart" if we should run again in another mode.
function F.runReceiver(group, pin)
  local rx_speakers = { peripheral.find("speaker") }
  if #rx_speakers == 0 then
    error("No speakers attached. A linked speaker needs at least one speaker.", 0)
  end
  if not F.openModems() then
    error("No modem attached. A linked speaker needs a wireless or ender modem.", 0)
  end

  local decoder = dfpwm.make_decoder()
  local pending = {}               -- decoded chunks waiting for the speakers
  local until_ms = nil             -- when the audio we've handed the speakers runs out
  local title, artist = nil, nil
  local last_audio = nil
  local typing = false
  local btns = {}                  -- clickable buttons on this screen
  local smooth_last = nil          -- low-pass filter state between chunks
  local upd, note = nil, nil       -- newer version on GitHub; a one-line message
  local result = nil               -- "player" / "restart" once we're asked to leave
  local rx_volume = math.max(0, math.min(150, tonumber(settings.get("phoenix_music.rx_volume")) or 100))
  local colourful = term.isColour()
  local accent = colourful and colours.orange or colours.white

  local function draw()
    if typing then return end
    local w, h = term.getSize()
    term.setBackgroundColour(colours.black)
    term.clear()
    term.setCursorPos(2, 2)
    term.setTextColour(accent)
    term.write(APP.name .. " - Speaker Link")
    term.setCursorPos(2, 3)
    term.setTextColour(colours.lightGrey)
    term.write(("Link: " .. group .. (pin ~= "" and "  (PIN set)" or "")):sub(1, w - 2))

    local active = last_audio and os.clock() - last_audio < 5
    term.setCursorPos(2, 5)
    if title then
      term.setTextColour(active and accent or colours.lightGrey)
      term.write(active and "Playing" or "Last played")
      term.setCursorPos(2, 6)
      term.setTextColour(colours.white)
      term.write(tostring(title):sub(1, w - 2))
      term.setCursorPos(2, 7)
      term.setTextColour(colours.lightGrey)
      term.write(tostring(artist or ""):sub(1, w - 2))
    else
      term.setTextColour(colours.lightGrey)
      term.write("Waiting for music...")
    end
    term.setCursorPos(2, 9)
    term.setTextColour(colours.white)
    term.write("Volume: " .. rx_volume .. "%")
    term.setCursorPos(2, 10)
    term.setTextColour(colours.lightGrey)
    term.write(#rx_speakers .. " speaker" .. (#rx_speakers == 1 and "" or "s"))

    if note or upd then
      term.setCursorPos(2, 12)
      term.setTextColour(accent)
      term.write((note or ("Update available: v" .. upd.version .. " - press u to install")):sub(1, w - 2))
    end

    -- Buttons (advanced computers can click them) and the key help
    btns = {}
    if colourful then
      local list = { { " Link ", "link" }, { " PIN ", "pin" }, { " - ", "down" }, { " + ", "up" } }
      list[#list + 1] = upd and { " Update ", "update" } or { " Check ", "update" }
      list[#list + 1] = { " Player ", "player" }
      local x = 2
      for _, b in ipairs(list) do
        if x + #b[1] - 1 <= w - 1 then
          term.setCursorPos(x, h - 2)
          term.setBackgroundColour(colours.grey)
          term.setTextColour(colours.white)
          term.write(b[1])
          btns[#btns + 1] = { x = x, y = h - 2, w = #b[1], action = b[2] }
          x = x + #b[1] + 1
        end
      end
      term.setBackgroundColour(colours.black)
    end
    term.setCursorPos(2, h)
    term.setTextColour(colours.lightGrey)
    term.write(("Keys: l link  p PIN  +/- volume  u update  q quit"):sub(1, w - 2))
  end

  local function hello(to)
    local msg = {
      type = "hello", group = group, pin = pin, label = os.getComputerLabel(),
      speakers = #rx_speakers, volume = rx_volume,
    }
    if to then rednet.send(to, msg, PROTOCOL) else rednet.broadcast(msg, PROTOCOL) end
  end

  -- Stop the speakers but keep the audio that's waiting, so we drop straight
  -- back into step with everyone else (CC only takes a new volume when the
  -- speaker starts afresh).
  local function rejoin()
    for _, s in ipairs(rx_speakers) do s.stop() end
    until_ms = nil
    for _, it in ipairs(pending) do it.done = {}; it.started = nil end
    os.queueEvent("phoenix_rx")
  end

  local function setRxVolume(v)
    rx_volume = math.max(0, math.min(150, math.floor(v + 0.5)))
    settings.set("phoenix_music.rx_volume", rx_volume)
    settings.save()
    hello()
    rejoin()
    draw()
  end

  local function stopAll()
    pending = {}
    until_ms = nil
    smooth_last = nil
    decoder = dfpwm.make_decoder()
    for _, s in ipairs(rx_speakers) do s.stop() end
    os.queueEvent("phoenix_rx")
  end

  local function net()
    while true do
      local id, msg = rednet.receive(PROTOCOL)
      if P.ok(msg, group, pin) then
        if msg.type == "audio" and type(msg.data) == "string" then
          local changed = msg.name ~= title
          title, artist = msg.name, msg.artist
          if not last_audio or os.clock() - last_audio >= 5 then changed = true end
          last_audio = os.clock()
          -- Keep the raw audio; it's only unpacked when it's next to play, so a
          -- burst of messages (someone dragging through a song) can't bog us down
          table.insert(pending, {
            data = msg.data, smoothing = msg.smoothing,
            vol = tonumber(msg.volume) or 1, at = tonumber(msg.at), done = {},
          })
          -- If we've fallen well behind, drop the oldest audio rather than lag forever
          while #pending > 6 do table.remove(pending, 1) end
          os.queueEvent("phoenix_rx")
          if changed then draw() end
        elseif msg.type == "stop" then
          stopAll()
        elseif msg.type == "ping" then
          hello(id)
        elseif msg.type == "rxvol" and msg.target == os.getComputerID() then
          setRxVolume(tonumber(msg.value) or rx_volume)
        end
      end
    end
  end

  -- Every chunk says when it should start playing (on the server clock). When
  -- we start from silence we wait for that moment - or, if we've joined late,
  -- skip what everyone else has already played - so we're in step with the
  -- player. After that, the speaker's own queue keeps us there.
  local function player()
    while true do
      local item = pending[1]
      if not item then
        os.pullEvent("phoenix_rx")
      else
        if not item.buf then
          item.buf = decoder(item.data)
          smooth_last = P.smooth(item.buf, item.smoothing, smooth_last)
          item.data = nil
        end
        local now = os.epoch("utc")
        if until_ms and now > until_ms + 250 then until_ms = nil end -- we ran dry
        local ready = true
        if not until_ms and not item.started and item.at then
          if item.at > now + 15 then
            ready = false
            local timer = os.startTimer((item.at - now) / 1000)
            repeat
              local ev, p = os.pullEvent()
            until (ev == "timer" and p == timer) or pending[1] ~= item
          elseif now - item.at > 30 then
            local skip = math.floor((now - item.at) * 48) -- 48 samples per ms
            if skip >= #item.buf then
              ready = false
              if pending[1] == item then table.remove(pending, 1) end
            else
              local cut = {}
              for i = skip + 1, #item.buf do cut[#cut + 1] = item.buf[i] end
              item.buf, item.at = cut, now
            end
          end
        end
        if ready and pending[1] == item then
          local vol = math.min(3, item.vol * rx_volume / 100)
          local all = true
          for i, s in ipairs(rx_speakers) do
            if not item.done[i] then
              if s.playAudio(item.buf, vol) then item.done[i] = true else all = false end
            end
          end
          if not item.started then
            item.started = true
            if not until_ms then until_ms = item.at or os.epoch("utc") end
          end
          if all then
            until_ms = until_ms + #item.buf / 48
            if pending[1] == item then table.remove(pending, 1) end
          else
            os.pullEvent() -- speaker_audio_empty, new audio or a stop
          end
        end
      end
    end
  end

  local function heartbeat()
    while true do
      hello()
      sleep(5)
      draw() -- flips Playing/Last played when the music stops
    end
  end

  -- Checks on start, every 15 minutes (linked speakers are left running for
  -- ages), and whenever someone presses u / Check.
  local by_hand = false
  local function updater()
    sleep(3)
    while true do
      local info = P.checkUpdate()
      if info and info.newer then
        upd, note = info, nil
      elseif by_hand then
        note = info and ("Up to date (v" .. APP.version .. ")") or "Couldn't check for updates"
      end
      by_hand = false
      draw()
      local timer = os.startTimer(15 * 60)
      repeat
        local ev, p = os.pullEvent()
      until (ev == "timer" and p == timer) or ev == "phoenix_check"
    end
  end

  -- Typing on the bottom line (Link name or PIN).
  local function ask(label, mask)
    typing = true
    local _, h = term.getSize()
    term.setCursorPos(1, h)
    term.setBackgroundColour(colours.black)
    term.clearLine()
    term.setTextColour(colours.white)
    term.write(" " .. label)
    local v = read(mask)
    typing = false
    return v
  end

  local KEYS = {
    q = "quit", ["+"] = "up", ["="] = "up", ["-"] = "down", ["_"] = "down",
    l = "link", p = "pin", u = "update",
  }

  local function keyLoop()
    while true do
      local ev, a, x, y = os.pullEvent()
      local action
      if ev == "char" then
        action = KEYS[a]
      elseif ev == "mouse_click" then
        for _, b in ipairs(btns) do
          if y == b.y and x >= b.x and x < b.x + b.w then action = b.action end
        end
      end
      if action == "quit" then
        return
      elseif action == "player" then
        result = "player"
        return
      elseif action == "up" then
        setRxVolume(rx_volume + 10)
      elseif action == "down" then
        setRxVolume(rx_volume - 10)
      elseif action == "update" and not upd then
        by_hand = true
        note = "Checking for updates..."
        draw()
        os.queueEvent("phoenix_check")
      elseif action == "update" and upd then
        note = "Updating..."
        draw()
        local ok, err = P.installUpdate()
        if ok then
          result = "restart"
          return
        end
        note = "Update failed: " .. tostring(err)
        draw()
      elseif action == "link" then
        local v = P.trim(ask("Link name (now " .. group .. "): ")):sub(1, 24)
        if v ~= "" and v ~= group then
          stopAll()
          group, title = v, nil
          settings.set("phoenix_music.group", group)
          settings.save()
          hello()
        end
        draw()
      elseif action == "pin" then
        local v = P.trim(ask("PIN (blank for none): ", "*")):sub(1, 12)
        stopAll()
        pin, title = v, nil
        settings.set("phoenix_music.pin", pin)
        settings.save()
        hello()
        draw()
      end
    end
  end

  draw()
  local ok, err = pcall(parallel.waitForAny, net, player, heartbeat, keyLoop, updater)
  for _, s in ipairs(rx_speakers) do s.stop() end
  term.setBackgroundColour(colours.black)
  term.setTextColour(colours.white)
  term.clear()
  term.setCursorPos(1, 1)
  if not ok and err ~= "Terminated" then printError(err) end
  return result
end

---------------------------------------------------------------------------
-- Display setup (monitor support + palette)
---------------------------------------------------------------------------
local args = { ... }

-- What to call ourselves in help text: whatever this file is saved as.
local CMD = "phoenixmusic"
if shell and shell.getRunningProgram then
  CMD = (fs.getName(shell.getRunningProgram()):gsub("%.lua$", ""))
end

if args[1] == "link" or args[1] == "receiver" then -- "receiver" was the old name
  local r = F.runReceiver(args[2] or settings.get("phoenix_music.group"), P.trim(settings.get("phoenix_music.pin")))
  if r == "player" then P.relaunch({ "player" }) elseif r == "restart" then P.relaunch(args) end
  return
end

local remote_mode = args[1] == "remote"
local force_player = args[1] == "player"   -- skips the "no speaker here" choice
local parent = term.current()
local monitor_name = nil

if args[1] and not remote_mode and not force_player then
  local mon = peripheral.wrap(args[1])
  if not mon or peripheral.getType(args[1]) ~= "monitor" then
    error("'" .. args[1] .. "' isn't a monitor.", 0)
  end
  mon.setTextScale(tonumber(args[2]) or 0.5)
  parent = mon
  monitor_name = args[1]
end

if not parent.isColour() then
  -- A standard (grey) computer can't show the player, but it makes a fine
  -- linked speaker, so that's what it becomes.
  if not monitor_name and not remote_mode then
    local r = F.runReceiver(settings.get("phoenix_music.group"), P.trim(settings.get("phoenix_music.pin")))
    if r == "restart" then P.relaunch(args) end
    return
  end
  error("This needs an advanced computer or advanced monitor.", 0)
end

local speakers = { peripheral.find("speaker") }
local wireless = F.openModems()
local group = settings.get("phoenix_music.group")
local pin = P.trim(settings.get("phoenix_music.pin"))
local receivers = {}               -- [computer id] = { label, speakers, volume, seen }

-- A computer with no speaker but a modem can be a remote instead. Once
-- someone picks that, it starts as a remote from then on.
local ask_nospeaker = false
local is_pocket = pocket ~= nil
if not remote_mode and not force_player and not monitor_name and #speakers == 0 and wireless then
  local choice = settings.get("phoenix_music.nospeaker_mode")
  if choice == "remote" then remote_mode = true
  elseif choice ~= "player" then ask_nospeaker = true end
end
if remote_mode and not wireless then
  error("The remote needs a wireless or ender modem.", 0)
end
if not remote_mode and #speakers == 0 and not wireless then
  error("No speakers found. Connect a speaker (directly or through a wired modem), or add a wireless or ender modem to play through linked speakers ('" .. CMD .. " link'). If this is an Advanced Noisy Pocket Computer, try restarting your Minecraft game.", 0)
end

-- Theme: remap a few palette slots so the UI isn't stuck with stock colours.
local THEME = {
  [colours.black]     = 0x101217, -- background
  [colours.grey]      = 0x1d2129, -- panels
  [colours.brown]     = 0x2f3540, -- buttons / bar track
  [colours.lightGrey] = 0x8b93a3, -- muted text
  [colours.white]     = 0xeceef3, -- text
  [colours.orange]    = 0xff8a2b, -- accent
  [colours.red]       = 0xe5484d, -- errors
  [colours.lime]      = 0x4cc38a, -- good / active toggles
}
local C = {
  bg = colours.black, panel = colours.grey, btn = colours.brown,
  muted = colours.lightGrey, text = colours.white, accent = colours.orange,
  err = colours.red, ok = colours.lime,
}

local saved_palette = {}
for c, rgb in pairs(THEME) do
  saved_palette[c] = { parent.getPaletteColour(c) }
  parent.setPaletteColour(c, rgb)
end

function F.restorePalette()
  for c, rgb in pairs(saved_palette) do
    parent.setPaletteColour(c, table.unpack(rgb))
  end
end

local W, H = parent.getSize()
local win = window.create(parent, 1, 1, W, H, true)
local old_term = term.redirect(win)

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local tab = 1                      -- 1 now playing, 2 search, 3 queue
local modal = nil                  -- { title, sub, options = { {label, fn} } }
local scroll = { [2] = 0, [3] = 0, [4] = 0, [5] = 0 }

local waiting_for_input = false
local prompt = nil                 -- { title, initial, onDone } while typing a name
local favourites, playlists = {}, {}
local open_playlist = nil          -- playlist being viewed on the Search tab
local last_search, last_search_url = nil, nil
local search_results, search_error = nil, false

local queue, history = {}, {}
local now_playing = nil
local looping = 0                  -- 0 off, 1 queue, 2 song
local volume, muted = 1.5, false

local playing = false              -- we want audio coming out (or loading)
local paused = false
local stopped = false              -- paused at 0 after pressing stop
local playing_id = nil
local last_download_url = nil
local playing_status = 0           -- 1 once the download handle is ready
local needs_next_chunk = 0
local is_loading, is_error = false, false

local player_handle = nil
local decoder = dfpwm.make_decoder()
local total_bytes = nil            -- nil when the length is unknown
local seekable = false
local byte_pos = 0                 -- next byte the player will read

-- Playback clock: position = anchor_pos + time since anchor_time
local anchor_pos, anchor_time = 0, 0
local clock_running, need_anchor = false, true
local audio_gen = 0                -- bumped to cancel whatever is playing
local resume_bytes = nil           -- where to jump to once a saved track loads

local hits = {}                    -- clickable regions for the current frame

-- Newer features keep their state and functions in here (Lua only allows
-- 200 locals at the top of a file, and this one is getting big).
local X = {
  shuffle = false,                 -- pick the next song at random
  viz = true,                      -- visualiser instead of Up next
  sync_start = true,               -- next chunk is a fresh start for receivers
  viz_bufs = {}, viz_levels = {},
  redstone = nil,                  -- { kind = "toggle" | "next" | "list", name = ... }
  sleep_at = nil,                  -- os.epoch time to pause at
  sleep_after_song = false,
  alarm = nil,                     -- { time = 7.5, list = name or nil }
  last_mc_time = nil,
  MAX_LEN = 15 * 60,               -- the server can't convert videos longer than this
  error_text = nil,                -- why the last song failed
  skip_at = nil,                   -- auto-skip to the next song after a failure
  cache = {},                      -- songs downloaded this session: { id, data }
  CACHE_MAX = 4,                   -- songs kept in memory
  CACHE_BYTES = 6 * 1024 * 1024,   -- and at most this much audio
  start_at = nil,                  -- when the next song should start (gapless)
  vol_dirty_at = nil,              -- re-apply the volume at this time (CC needs a restart)
  upd = { state = "idle" },        -- update check: idle/checking/none/available/error/installing/installed
  upd_offered = false,             -- asked about this update already this session
  switch_to = nil,                 -- args to run again with when we quit (mode switch / update)
  progress_row = 7,                -- where the progress bar is this frame
  all_results = nil,               -- search results before hiding long videos
  prefetch = nil,                  -- next song downloading in the background: { id, url }
  prefetch_failed = {},            -- songs the server couldn't give us (don't keep asking)
  next_pick = nil,                 -- in shuffle mode, the song chosen to play next
}

-- Length in seconds from an artist line like "3:33 - Alan Walker".
function X.durationOf(item)
  if type(item) ~= "table" then return nil end
  local a, b, c = tostring(item.artist or ""):match("^(%d+):(%d+):?(%d*)")
  if not a then return nil end
  if c ~= "" then return tonumber(a) * 3600 + tonumber(b) * 60 + tonumber(c) end
  return tonumber(a) * 60 + tonumber(b)
end

function X.tooLong(item)
  local d = X.durationOf(item)
  return d ~= nil and d > X.MAX_LEN
end
local volume_row = 13               -- where the volume bar ended up this frame

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
function F.now_ms() return os.epoch("utc") end

function F.fmtTime(sec)
  if not sec then return "--:--" end
  sec = math.max(0, math.floor(sec))
  local h = math.floor(sec / 3600)
  local m = math.floor(sec / 60) % 60
  local s = sec % 60
  if h > 0 then return string.format("%d:%02d:%02d", h, m, s) end
  return string.format("%d:%02d", m, s)
end

function F.trunc(s, w)
  s = tostring(s or "")
  if w <= 0 then return "" end
  if #s <= w then return s end
  if w <= 2 then return s:sub(1, w) end
  return s:sub(1, w - 2) .. ".."
end

function F.fill(x, y, w, h, bg)
  if w <= 0 or h <= 0 then return end
  term.setBackgroundColour(bg)
  local line = string.rep(" ", w)
  for i = 0, h - 1 do
    term.setCursorPos(x, y + i)
    term.write(line)
  end
end

local function text(x, y, s, fg, bg)
  term.setCursorPos(x, y)
  if fg then term.setTextColour(fg) end
  if bg then term.setBackgroundColour(bg) end
  term.write(s)
end

function F.addHit(x, y, w, h, fn)
  hits[#hits + 1] = { x = x, y = y, w = w, h = h, fn = fn }
end

function F.addHitFirst(x, y, w, h, fn)
  table.insert(hits, 1, { x = x, y = y, w = w, h = h, fn = fn })
end

-- Tappable scroll arrows (monitors have no scroll wheel).
function F.scrollArrows(key, top, maxScroll, page)
  if scroll[key] > 0 then
    text(W, top, G.up, C.accent, C.bg)
    F.addHitFirst(W - 1, top, 2, 1, function()
      scroll[key] = math.max(0, scroll[key] - page)
      F.redraw()
    end)
  end
  if scroll[key] < maxScroll then
    text(W, H, G.down, C.accent, C.bg)
    F.addHitFirst(W - 1, H, 2, 1, function()
      scroll[key] = math.min(maxScroll, scroll[key] + page)
      F.redraw()
    end)
  end
end

function F.button(x, y, label, fg, bg, fn)
  text(x, y, label, fg, bg)
  if fn then F.addHit(x, y, #label, 1, fn) end
  return #label
end

function F.effectiveVolume()
  return muted and 0 or volume
end

function F.elapsedBytes()
  local pos = anchor_pos
  if clock_running then
    pos = anchor_pos + math.max(0, F.now_ms() - anchor_time) * BYTES_PER_SEC / 1000
    if pos > byte_pos then pos = byte_pos end
  end
  if total_bytes and pos > total_bytes then pos = total_bytes end
  return math.max(0, pos)
end

local net_primed = false           -- first chunk after a stop goes out unpaced

-- Receivers we've heard from recently (and how many speakers they have).
function F.activeReceivers()
  local count, spk = 0, 0
  local now = os.clock()
  for _, r in pairs(receivers) do
    if now - r.seen <= RECEIVER_TIMEOUT then
      count = count + 1
      spk = spk + r.speakers
    end
  end
  return count, spk
end

function F.stopSpeakers()
  for _, speaker in ipairs(speakers) do
    speaker.stop()
    os.queueEvent("playback_stopped")
  end
  if #speakers == 0 then os.queueEvent("playback_stopped") end
  net_primed = false
  X.sync_start = true
  X.smooth_last = nil
  if wireless then
    rednet.broadcast({ type = "stop", group = group, pin = pin }, PROTOCOL)
  end
end

-- Sends a raw DFPWM chunk to every receiver in our group. "at" is set on a
-- fresh start: the moment (server clock, ms) everyone should begin playing.
function F.broadcastChunk(chunk, at)
  if not wireless or F.activeReceivers() == 0 then return end
  rednet.broadcast({
    type = "audio", group = group, pin = pin, data = chunk, at = at,
    smoothing = settings.get("phoenix_music.smoothing"),
    volume = muted and 0 or volume,
    name = now_playing and now_playing.name, artist = now_playing and now_playing.artist,
  }, PROTOCOL)
end

function F.closeHandle()
  X.seek_target, X.seek_due = nil, nil -- a pending seek belonged to the old song
  if player_handle then pcall(player_handle.close) end
  player_handle = nil
  playing_status = 0
  needs_next_chunk = 0
  total_bytes, seekable = nil, false
  byte_pos, anchor_pos = 0, 0
  clock_running, need_anchor = false, true
end

function F.redraw() os.queueEvent("redraw_screen") end

---------------------------------------------------------------------------
-- Song cache: the last few songs stay in memory, so replaying, going back,
-- looping the queue or picking from Recently played starts straight away.
---------------------------------------------------------------------------
function X.cacheGet(id)
  for i, c in ipairs(X.cache) do
    if c.id == id then
      table.remove(X.cache, i)
      table.insert(X.cache, c) -- most recently used goes last
      return c.data
    end
  end
end

function X.cachePut(id, data)
  for i = #X.cache, 1, -1 do
    if X.cache[i].id == id then table.remove(X.cache, i) end
  end
  table.insert(X.cache, { id = id, data = data })
  local total = 0
  for _, c in ipairs(X.cache) do total = total + #c.data end
  while #X.cache > 1 and (#X.cache > X.CACHE_MAX or total > X.CACHE_BYTES) do
    total = total - #X.cache[1].data
    table.remove(X.cache, 1)
  end
end

-- A file-like handle over a string, so a song plays (and seeks) the same
-- whether it was just downloaded or came from the cache.
function X.memHandle(data)
  local pos = 0
  local h = {}
  function h.read(n)
    if pos >= #data then return nil end
    local chunk = data:sub(pos + 1, pos + (n or 1))
    pos = pos + #chunk
    return chunk
  end
  function h.seek(whence, offset)
    offset = offset or 0
    if whence == "end" then pos = #data + offset
    elseif whence == "cur" then pos = pos + offset
    else pos = offset end
    pos = math.max(0, math.min(pos, #data))
    return pos
  end
  function h.close() end
  return h
end

-- Starts the current song from its audio (downloaded or cached).
function X.openAudio(data)
  is_loading = false
  player_handle = X.memHandle(data)
  total_bytes, seekable = #data, true
  byte_pos, anchor_pos = 0, 0
  clock_running, need_anchor = false, true
  decoder = dfpwm.make_decoder()
  -- Picking up a saved track: jump to where we left off.
  if resume_bytes and resume_bytes < total_bytes then
    player_handle.seek("set", resume_bytes)
    byte_pos, anchor_pos = resume_bytes, resume_bytes
  end
  resume_bytes = nil
  playing_status = 1
  needs_next_chunk = 1
  F.redraw()
  os.queueEvent("audio_update")
end

-- Waits until the server clock reaches t (ms), unless playback is stopped.
function X.waitUntil(t)
  local wait = (t - F.now_ms()) / 1000
  if wait > 0 then
    parallel.waitForAny(
      function() sleep(wait) end,
      function() os.pullEvent("playback_stopped") end
    )
  end
end

---------------------------------------------------------------------------
-- Tidying titles: CC's font only has Latin characters, so emoji and other
-- scripts turned into "?????". Search results are fetched as raw bytes and
-- decoded here instead, so we know which characters can't be shown.
---------------------------------------------------------------------------
X.PUNCT = {
  [0x2018] = "'", [0x2019] = "'", [0x201C] = "'", [0x201D] = "'",
  [0x2013] = "-", [0x2014] = "-", [0x2022] = "-", [0x2026] = "...",
}
local UNSHOWN = "\127" -- stands in for a character CC can't draw

function X.fromUtf8(s)
  local out, i, n = {}, 1, #s
  while i <= n do
    local b = s:byte(i)
    local cp, len
    if b < 0x80 then
      cp, len = b, 1
    elseif b >= 0xF0 then
      cp, len = nil, 4
    elseif b >= 0xE0 then
      local b2, b3 = s:byte(i + 1) or 0, s:byte(i + 2) or 0
      cp, len = (b % 16) * 4096 + (b2 % 64) * 64 + (b3 % 64), 3
    elseif b >= 0xC0 then
      cp, len = (b % 32) * 64 + ((s:byte(i + 1) or 0) % 64), 2
    else
      cp, len = nil, 1
    end
    if cp and cp < 256 then out[#out + 1] = string.char(cp)
    elseif cp and X.PUNCT[cp] then out[#out + 1] = X.PUNCT[cp]
    else out[#out + 1] = UNSHOWN end
    i = i + len
  end
  return table.concat(out)
end

function X.cleanText(s)
  s = tostring(s or ""):gsub(UNSHOWN .. "+", " "):gsub("%?%?+", " "):gsub("  +", " ")
  return F.trim(s)
end

-- Makes a result readable: strips what CC can't show, and if the title is
-- (almost) all foreign script, calls it "Video from <channel>" instead.
function X.tidyItem(r)
  if type(r) ~= "table" then return end
  local raw = tostring(r.name or "")
  local mangled = raw:find(UNSHOWN, 1, true) or raw:find("??", 1, true)
  r.name, r.artist = X.cleanText(r.name), X.cleanText(r.artist)
  -- "3:33 . Channel": the separator can arrive as any symbol, so don't rely on it
  local dur, sep, chan = r.artist:match("^(%d+:%d[%d:]*)(%s*[^%w%s]*%s*)(.*)$")
  if dur and chan == "" then
    chan = "unknown channel"
    r.artist = dur .. sep .. "Unknown channel"
  end
  -- Live streams come back with no length (the line starts "undefined",
  -- "null" or "LIVE"); the server can't convert them, so they're marked and
  -- hidden like the long ones. Anything we can't read stays as it is.
  if r.type ~= "playlist" and not dur then
    local lower = r.artist:lower()
    local word = lower:match("^(%a+)")
    if word == "undefined" or word == "null" or word == "live" then
      local rest = r.artist:match("^%a+%s*[^%w%s]*%s*(.*)$") or ""
      r.live = true
      chan = rest ~= "" and rest or "unknown channel"
      r.artist = "LIVE - " .. chan
    end
  end
  local _, letters = r.name:gsub("%w", "")
  if letters < 3 and (mangled or r.name == "") then r.name = "Video from " .. (chan or "unknown channel") end
  if type(r.playlist_items) == "table" then
    for _, it in ipairs(r.playlist_items) do X.tidyItem(it) end
  end
end

-- What the search tab shows: everything, or without the long videos.
function X.filterResults()
  if not X.all_results then return end
  local hide = settings.get("phoenix_music.hide_long")
  search_results = {}
  for _, r in ipairs(X.all_results) do
    if not (hide and r.too_long) then search_results[#search_results + 1] = r end
  end
  -- Never hide everything: if the filter would leave nothing, show it all
  if #search_results == 0 then
    for _, r in ipairs(X.all_results) do search_results[#search_results + 1] = r end
  end
  X.hidden_count = #X.all_results - #search_results
end

-- Takes the next song off the queue: the first, or a random one in shuffle mode.
-- The song that will play next, so it can download in the background. In
-- shuffle mode the random pick is made now and kept, so that's what plays.
function X.peekNext()
  if looping == 2 or #queue == 0 then return nil end -- looping a song: it's already here
  if X.shuffle and #queue > 1 then
    for _, it in ipairs(queue) do
      if it == X.next_pick then return it end
    end
    X.next_pick = queue[math.random(#queue)]
    return X.next_pick
  end
  return queue[1]
end

-- Takes the next song off the queue: the first, or the shuffle pick.
function X.takeNext()
  local pick = X.peekNext()
  X.next_pick = nil
  for i, it in ipairs(queue) do
    if it == pick then return table.remove(queue, i) end
  end
  return table.remove(queue, 1)
end

-- While a song plays, fetch the next one so it starts the moment this ends
-- (the wait between songs was the server fetching and converting it).
function X.maybePrefetch()
  if X.prefetch or not playing or playing_status ~= 1 then return end
  local nxt = X.peekNext()
  if not nxt or not nxt.id or X.prefetch_failed[nxt.id] or X.tooLong(nxt) then return end
  if tostring(nxt.artist):find("^LIVE %- ") then return end
  for _, c in ipairs(X.cache) do
    if c.id == nxt.id then return end -- already downloaded
  end
  local url = api_base_url .. "?v=" .. version .. "&id=" .. textutils.urlEncode(nxt.id)
  X.prefetch = { id = nxt.id, url = url }
  http.request({ url = url, binary = true })
end

function X.toggleShuffle()
  X.shuffle = not X.shuffle
  F.redraw()
end

---------------------------------------------------------------------------
-- Saving and restoring (queue, history, now playing, settings)
---------------------------------------------------------------------------
-- Keep only what's needed to play a track again.
function F.slim(item)
  if type(item) ~= "table" or not item.id then return nil end
  return { id = item.id, name = item.name, artist = item.artist }
end

function F.slimList(list)
  local out = {}
  for _, it in ipairs(list) do out[#out + 1] = F.slim(it) end
  return out
end

local last_saved = nil

-- Writes the state file, but only when something actually changed.
function F.saveState()
  local pos = nil
  if now_playing then
    -- Rounded to 5s so we're not rewriting the file every half second
    local sec = math.floor(F.elapsedBytes() / BYTES_PER_SEC / 5) * 5
    if not playing and resume_bytes then sec = math.floor(resume_bytes / BYTES_PER_SEC) end
    pos = sec
  end
  local data = {
    version = 1,
    volume = volume, muted = muted, looping = looping,
    now_playing = F.slim(now_playing), position = pos,
    queue = F.slimList(queue), history = F.slimList(history),
    shuffle = X.shuffle, viz = X.viz, redstone = X.redstone, alarm = X.alarm,
  }
  local ok, s = pcall(textutils.serialise, data)
  if not ok or s == last_saved then return end
  local f = fs.open(STATE_FILE, "w")
  if f then
    f.write(s)
    f.close()
    last_saved = s
  end
end

function F.loadState()
  if not fs.exists(STATE_FILE) then return end
  local f = fs.open(STATE_FILE, "r")
  if not f then return end
  local s = f.readAll()
  f.close()
  local data = textutils.unserialise(s or "")
  if type(data) ~= "table" then return end

  volume = math.max(0, math.min(VOLUME_MAX, tonumber(data.volume) or volume))
  muted = data.muted == true
  looping = (data.looping == 1 or data.looping == 2) and data.looping or 0
  queue = type(data.queue) == "table" and F.slimList(data.queue) or {}
  history = type(data.history) == "table" and F.slimList(data.history) or {}
  now_playing = F.slim(data.now_playing)
  X.shuffle = data.shuffle == true
  X.viz = data.viz ~= false
  if type(data.redstone) == "table" and type(data.redstone.kind) == "string" then X.redstone = data.redstone end
  if type(data.alarm) == "table" and tonumber(data.alarm.time) then X.alarm = data.alarm end

  -- Come back stopped, showing where we left off; play picks up from there.
  if now_playing and tonumber(data.position) and data.position > 0 then
    resume_bytes = math.floor(data.position * BYTES_PER_SEC)
    anchor_pos = resume_bytes
  end
  last_saved = s
end

---------------------------------------------------------------------------
-- Playback control
---------------------------------------------------------------------------
function F.pushHistory(item)
  if not item then return end
  table.insert(history, item)
  if #history > HISTORY_MAX then table.remove(history, 1) end
end

-- Switch to a track and start it from the top. start_at is set when the last
-- song ended by itself: the speakers are still playing its tail end, so we
-- carry straight on from there instead of cutting them off.
function F.loadTrack(item, start_at)
  resume_bytes = nil
  audio_gen = audio_gen + 1
  if start_at then
    X.sync_start, X.start_at = true, start_at
  else
    F.stopSpeakers()
  end
  F.closeHandle()
  now_playing = item
  playing_id = nil
  is_error, is_loading = false, false
  X.error_text, X.skip_at = nil, nil
  paused, stopped = false, false
  playing = item ~= nil
  decoder = dfpwm.make_decoder()
  os.queueEvent("audio_update")
  F.redraw()
end

-- Move the read position (bytes). Needs a seekable handle.
function F.seekBytes(b)
  if not (player_handle and seekable and total_bytes) then return false end
  b = math.max(0, math.min(math.floor(b), total_bytes))
  local ok = pcall(player_handle.seek, "set", b)
  if not ok then return false end
  audio_gen = audio_gen + 1
  F.stopSpeakers()
  decoder = dfpwm.make_decoder()
  byte_pos, anchor_pos = b, b
  clock_running, need_anchor = false, true
  needs_next_chunk = 1
  os.queueEvent("audio_update")
  F.redraw()
  return true
end

function F.seekSeconds(sec) return F.seekBytes(sec * BYTES_PER_SEC) end

local function pause()
  if not playing or paused then return end
  anchor_pos = F.elapsedBytes()
  clock_running = false
  paused = true
  audio_gen = audio_gen + 1
  F.stopSpeakers()
  -- Rewind to what we actually heard, so nothing buffered gets skipped.
  if player_handle and seekable then
    if pcall(player_handle.seek, "set", math.floor(anchor_pos)) then
      byte_pos = math.floor(anchor_pos)
      decoder = dfpwm.make_decoder()
    end
  else
    anchor_pos = byte_pos
  end
  F.redraw()
end

function F.resume()
  if not now_playing then
    if #queue > 0 then F.loadTrack(X.takeNext()) end
    return
  end
  if not playing then
    -- Fully stopped with no handle: start the track again (from the saved
    -- position if we just came back from a restart).
    local rb = resume_bytes
    F.loadTrack(now_playing)
    resume_bytes = rb
    if rb then anchor_pos = rb end
    return
  end
  paused, stopped = false, false
  is_error = false
  need_anchor = true
  if player_handle and playing_status == 1 then needs_next_chunk = 1 end
  os.queueEvent("audio_update")
  F.redraw()
end

function F.togglePause()
  if playing and not paused then pause() else F.resume() end
end

-- Stop ends the current song. The queue stays put; play starts the next
-- song and previous brings this one back.
local function stop()
  if not now_playing then return end
  audio_gen = audio_gen + 1
  F.stopSpeakers()
  F.closeHandle()
  F.pushHistory(now_playing)
  now_playing, playing_id = nil, nil
  playing, paused, stopped = false, false, false
  is_loading, is_error = false, false
  resume_bytes, X.error_text, X.skip_at = nil, nil, nil
  F.redraw()
end

local function restart()
  if not now_playing then return end
  if not F.seekBytes(0) then F.loadTrack(now_playing) end
  if paused then F.resume() end
end

function F.nextTrack()
  if not now_playing and #queue == 0 then return end
  if looping == 1 and now_playing then table.insert(queue, now_playing) end
  F.pushHistory(now_playing)
  if #queue > 0 then
    F.loadTrack(X.takeNext())
  else
    audio_gen = audio_gen + 1
    F.stopSpeakers()
    F.closeHandle()
    now_playing, playing_id = nil, nil
    playing, paused, stopped = false, false, false
    is_loading, is_error = false, false
    F.redraw()
  end
end

function F.prevTrack()
  -- More than 3 seconds in: restart. Otherwise go back a track.
  if now_playing and F.elapsedBytes() > 3 * BYTES_PER_SEC then
    restart()
    return
  end
  if #history > 0 then
    if now_playing then table.insert(queue, 1, now_playing) end
    F.loadTrack(table.remove(history))
  elseif now_playing then
    restart()
  end
end

-- Called by the audio loop when a track runs out.
function F.onTrackEnd()
  if X.sleep_after_song then
    -- Sleep timer set to "after this song": stop here.
    X.sleep_after_song = false
    F.closeHandle()
    playing, paused, stopped = false, false, false
    playing_id = nil
    is_loading, is_error = false, false
    F.redraw()
    return
  end
  -- When the audio we've already handed the speakers runs out
  local end_at = anchor_time + (byte_pos - anchor_pos) * 1000 / BYTES_PER_SEC
  if looping == 2 or (looping == 1 and #queue == 0) then
    -- Go round again without stopping the speakers
    if player_handle and pcall(player_handle.seek, "set", 0) then
      byte_pos = 0
      decoder = dfpwm.make_decoder()
      X.sync_start, X.start_at = true, end_at
      needs_next_chunk = 1
      os.queueEvent("audio_update")
    else
      F.loadTrack(now_playing, end_at)
    end
    return
  end
  if looping == 1 then table.insert(queue, now_playing) end
  F.pushHistory(now_playing)
  if #queue > 0 then
    F.loadTrack(X.takeNext(), end_at)
  else
    F.closeHandle()
    now_playing, playing_id = nil, nil
    playing, paused, stopped = false, false, false
    is_loading, is_error = false, false
    F.redraw()
  end
end

-- CC's speakers only take a new volume when they start afresh, so after a
-- change (once you've stopped fiddling with it) we quietly pick the song
-- straight back up from the same spot.
function F.setVolume(v)
  volume = math.max(0, math.min(VOLUME_MAX, v))
  muted = false
  X.vol_dirty_at = F.now_ms() + 700
  F.redraw()
end

function F.toggleMute()
  muted = not muted
  X.vol_dirty_at = F.now_ms() + 300
  F.redraw()
end

function F.cycleLoop()
  looping = (looping + 1) % 3
  F.redraw()
end

function F.shuffleQueue()
  for i = #queue, 2, -1 do
    local j = math.random(i)
    queue[i], queue[j] = queue[j], queue[i]
  end
  F.redraw()
end

-- Expand a search result into a list of tracks (playlists hold several).
function F.itemsOf(result)
  if result.type == "playlist" then return result.playlist_items or {} end
  return { result }
end

function F.playNow(result)
  local items = F.itemsOf(result)
  if #items == 0 then return end
  F.pushHistory(now_playing)
  queue = {}
  for i = 2, #items do table.insert(queue, items[i]) end
  F.loadTrack(items[1])
  tab = 1
end

function F.playNext(result)
  local items = F.itemsOf(result)
  for i = #items, 1, -1 do table.insert(queue, 1, items[i]) end
  if not now_playing then F.resume() end
  F.redraw()
end

function F.addToQueue(result)
  for _, item in ipairs(F.itemsOf(result)) do table.insert(queue, item) end
  if not now_playing then F.resume() end
  F.redraw()
end

---------------------------------------------------------------------------
-- Library: favourites and playlists (saved to LIBRARY_FILE)
---------------------------------------------------------------------------
-- Fresh, minimal copies so lists never share track tables with each other.
function F.copyTracks(list)
  local out = {}
  for _, it in ipairs(list or {}) do
    if type(it) == "table" and it.id then
      out[#out + 1] = { id = it.id, name = it.name, artist = it.artist }
    end
  end
  return out
end

function F.trim(str)
  return (tostring(str or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

function F.saveLibrary()
  local data = { version = 1, favourites = F.copyTracks(favourites), playlists = {} }
  for _, pl in ipairs(playlists) do
    data.playlists[#data.playlists + 1] = { name = pl.name, tracks = F.copyTracks(pl.tracks) }
  end
  local ok, out = pcall(textutils.serialise, data)
  if not ok then return end
  local f = fs.open(LIBRARY_FILE, "w")
  if f then
    f.write(out)
    f.close()
  end
end

function F.loadLibrary()
  if not fs.exists(LIBRARY_FILE) then return end
  local f = fs.open(LIBRARY_FILE, "r")
  if not f then return end
  local data = textutils.unserialise(f.readAll() or "")
  f.close()
  if type(data) ~= "table" then return end
  if type(data.favourites) == "table" then favourites = F.copyTracks(data.favourites) end
  playlists = {}
  if type(data.playlists) == "table" then
    for _, pl in ipairs(data.playlists) do
      if type(pl) == "table" and type(pl.name) == "string" and type(pl.tracks) == "table" then
        playlists[#playlists + 1] = { name = pl.name, tracks = F.copyTracks(pl.tracks) }
      end
    end
  end
end

-- Favourites behave like a playlist that can't be renamed or deleted.
function F.favList()
  return { name = "Favourites", tracks = favourites, fav = true }
end

function F.isFavourite(item)
  if type(item) ~= "table" or not item.id then return false end
  for _, t in ipairs(favourites) do
    if t.id == item.id then return true end
  end
  return false
end

function F.toggleFavourite(item)
  if type(item) ~= "table" or not item.id then return end
  for i, t in ipairs(favourites) do
    if t.id == item.id then
      table.remove(favourites, i)
      F.saveLibrary()
      F.redraw()
      return
    end
  end
  table.insert(favourites, 1, { id = item.id, name = item.name, artist = item.artist })
  F.saveLibrary()
  F.redraw()
end

function F.findPlaylist(name)
  for i, pl in ipairs(playlists) do
    if pl.name:lower() == name:lower() then return pl, i end
  end
end

-- "Chill" -> "Chill (2)" if it's taken.
function F.uniqueName(name)
  name = F.trim(name):sub(1, 32)
  if name == "" then name = "Playlist" end
  local base, n = name, 2
  while F.findPlaylist(name) do
    name = base .. " (" .. n .. ")"
    n = n + 1
  end
  return name
end

function F.newPlaylist(name, tracks)
  if #playlists >= PLAYLIST_MAX then return nil end
  local pl = { name = F.uniqueName(name), tracks = {} }
  for _, t in ipairs(F.copyTracks(tracks)) do
    if #pl.tracks < PLAYLIST_TRACKS_MAX then pl.tracks[#pl.tracks + 1] = t end
  end
  table.insert(playlists, pl)
  F.saveLibrary()
  F.redraw()
  return pl
end

-- Adds tracks to a playlist, skipping ones already in it.
function F.addTracksTo(pl, items)
  local have = {}
  for _, t in ipairs(pl.tracks) do have[t.id] = true end
  for _, t in ipairs(F.copyTracks(items)) do
    if not have[t.id] and #pl.tracks < PLAYLIST_TRACKS_MAX then
      pl.tracks[#pl.tracks + 1] = t
      have[t.id] = true
    end
  end
  F.saveLibrary()
  F.redraw()
end

-- Opens the name box; onDone gets the text when Enter is pressed.
function F.askText(title, initial, onDone)
  prompt = { title = title, initial = initial or "", onDone = onDone }
  F.redraw()
end

-- "Add to playlist" picker, with a shortcut to make a new one.
function F.choosePlaylistFor(items, label)
  local opts = {
    { G.heart .. " Favourites", function() F.addTracksTo(F.favList(), items) end },
  }
  for _, pl in ipairs(playlists) do
    opts[#opts + 1] = { G.note .. " " .. pl.name, function() F.addTracksTo(pl, items) end }
  end
  if #playlists < PLAYLIST_MAX then
    opts[#opts + 1] = { "+ New playlist...", function()
      F.askText("Name the new playlist", "", function(name)
        if F.trim(name) ~= "" then F.newPlaylist(name, items) end
      end)
    end }
  end
  modal = { title = "Add to playlist", sub = label, options = opts }
  F.redraw()
end

-- The two extra options every song menu gets.
function F.libraryOptions(opts, item)
  opts[#opts + 1] = { "Add to playlist...", function()
    F.choosePlaylistFor(F.itemsOf(item), item.name)
  end }
  if item.type ~= "playlist" and item.id then
    opts[#opts + 1] = { F.isFavourite(item) and "Unfavourite" or "Favourite", function()
      F.toggleFavourite(item)
    end }
  end
  return opts
end

-- Replace the queue with a playlist (optionally shuffled) and start it.
function F.playTracks(tracks, shuffled)
  local list = F.copyTracks(tracks)
  if #list == 0 then return end
  if shuffled then
    for i = #list, 2, -1 do
      local j = math.random(i)
      list[i], list[j] = list[j], list[i]
    end
  end
  F.pushHistory(now_playing)
  queue = {}
  for i = 2, #list do queue[#queue + 1] = list[i] end
  F.loadTrack(list[1])
  tab = 1
end

function F.playlistMenu(pl)
  local n = #pl.tracks
  local opts = {
    { "Play", function() F.playTracks(pl.tracks, false) end },
    { "Shuffle play", function() F.playTracks(pl.tracks, true) end },
    { "Add to queue", function()
      for _, t in ipairs(F.copyTracks(pl.tracks)) do queue[#queue + 1] = t end
      if not now_playing then F.resume() end
    end },
    { "Open", function()
      open_playlist = pl
      scroll[2] = 0
    end },
  }
  if not pl.fav then
    opts[#opts + 1] = { "Rename", function()
      F.askText("Rename playlist", pl.name, function(name)
        name = F.trim(name)
        if name == "" or name == pl.name then return end
        if name:lower() ~= pl.name:lower() then name = F.uniqueName(name) end
        pl.name = name:sub(1, 32)
        F.saveLibrary()
      end)
    end }
    opts[#opts + 1] = { "Delete", function()
      modal = {
        title = "Delete " .. pl.name .. "?",
        sub = "This can't be undone.",
        options = {
          { "Delete playlist", function()
            for i, p in ipairs(playlists) do
              if p == pl then table.remove(playlists, i) break end
            end
            if open_playlist == pl then open_playlist = nil end
            F.saveLibrary()
          end },
        },
      }
    end }
  end
  modal = { title = pl.name, sub = n .. (n == 1 and " song" or " songs"), options = opts }
  F.redraw()
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------
local TAB_NAMES_LONG = { "Now Playing", "Search", "Queue", "Settings", "About" }
local TAB_NAMES_MID = { "Playing", "Search", "Queue", "Settings", "About" }
local TAB_NAMES_SHORT = { "Now", "Find", "Queue", "Set" } -- About lives in Settings here

function F.drawTabs()
  F.fill(1, 1, W, 1, C.panel)
  local names = (W >= 60 and TAB_NAMES_LONG) or (W >= 34 and TAB_NAMES_MID) or TAB_NAMES_SHORT
  local slot = W / #names
  for i, name in ipairs(names) do
    local label = name
    if i == 3 and #queue > 0 and #label + #tostring(#queue) + 3 <= slot then
      label = label .. " " .. #queue
    end
    if #label + 2 <= slot then label = " " .. label .. " " end
    local x1 = math.floor(slot * (i - 1)) + 1
    local x2 = math.floor(slot * i)
    local lx = x1 + math.floor((x2 - x1 + 1 - #label) / 2)
    if i == tab or (i == 4 and tab == 5 and #names == 4) then
      F.fill(x1, 1, x2 - x1 + 1, 1, C.bg)
      text(lx, 1, label, C.accent, C.bg)
    else
      text(lx, 1, label, C.muted, C.panel)
    end
    F.addHit(x1, 1, x2 - x1 + 1, 1, function()
      tab = i
      modal = nil
      F.redraw()
    end)
  end
end

-- "2 speakers" / "1 + 3 wireless" etc.
function F.speakerSummary()
  local rx, rxSpk = F.activeReceivers()
  if rx == 0 then
    return #speakers .. " speaker" .. (#speakers == 1 and "" or "s")
  end
  return #speakers .. " + " .. rxSpk .. " wireless"
end

function F.statusLine()
  if is_error then
    local msg = X.error_text or "Network error"
    if X.skip_at then msg = msg .. " - skipping" end
    return msg, C.err
  end
  if is_loading then return "Loading...", C.muted end
  if not now_playing then return "Nothing playing", C.muted end
  if stopped then return "Stopped", C.muted end
  if paused then return "Paused", C.muted end
  if playing then
    local label = G.note .. " Playing"
    if X.sleep_at then
      label = label .. "  (sleep " .. math.max(1, math.ceil((X.sleep_at - F.now_ms()) / 60000)) .. "m)"
    elseif X.sleep_after_song then
      label = label .. "  (sleep after song)"
    end
    return label, C.accent
  end
  return "Stopped", C.muted
end

-- Seeking: dragging (or holding an arrow key) only moves the bar; the actual
-- seek happens once you let go. Every seek restarts the speakers and sends
-- linked ones fresh audio, so dozens a second knocks them out of step.
function X.requestSeek(b, delay)
  if not (seekable and total_bytes) then return end
  X.seek_target = math.max(0, math.min(b, total_bytes))
  X.seek_due = F.now_ms() + (delay or 0)
  F.redraw()
end

function X.applySeek()
  if X.seek_target and X.seek_due and F.now_ms() >= X.seek_due then
    local b = X.seek_target
    X.seek_target, X.seek_due = nil, nil
    F.seekBytes(b)
  end
end

function F.drawProgress(y)
  local cur = F.elapsedBytes() / BYTES_PER_SEC
  if X.seek_target then cur = X.seek_target / BYTES_PER_SEC end
  local tot = total_bytes and total_bytes / BYTES_PER_SEC or nil
  local left = F.fmtTime(now_playing and cur or nil)
  local right = F.fmtTime(tot)
  local bx = 2 + #left + 1
  local bw = W - 2 - #left - #right - 2
  text(2, y, left, C.muted, C.bg)
  text(W - #right, y, right, C.muted, C.bg)
  if bw < 3 then return end

  F.fill(bx, y, bw, 1, C.btn)
  if tot and tot > 0 then
    local filled = math.floor(bw * math.min(1, cur / tot) + 0.5)
    if filled > 0 then F.fill(bx, y, filled, 1, C.accent) end
  end
  if seekable and total_bytes then
    F.addHit(bx, y, bw, 1, function(x)
      -- applied on release (mouse_up); monitors have no release, so shortly after
      X.requestSeek((x - bx) / math.max(1, bw - 1) * total_bytes, 400)
    end)
  end
end

-- Transport icons as teletext pixel art. Each button is 5 cells x 3 rows,
-- which is a 10 x 9 pixel grid. Every icon sits in the same 6 x 5 area,
-- dead centre, with a 2 pixel border all round.
local ICONS = {
  prev = {
    "..........",
    "..........",
    "....#..#..",
    "...##.##..",
    "..######..",
    "...##.##..",
    "....#..#..",
    "..........",
    "..........",
  },
  play = {
    "..........",
    "..........",
    "...##.....",
    "...###....",
    "...####...",
    "...###....",
    "...##.....",
    "..........",
    "..........",
  },
  pause = {
    "..........",
    "..........",
    "..##..##..",
    "..##..##..",
    "..##..##..",
    "..##..##..",
    "..##..##..",
    "..........",
    "..........",
  },
  stop = {
    "..........",
    "..........",
    "..######..",
    "..######..",
    "..######..",
    "..######..",
    "..######..",
    "..........",
    "..........",
  },
  next = {
    "..........",
    "..........",
    "..#..#....",
    "..##.##...",
    "..######..",
    "..##.##...",
    "..#..#....",
    "..........",
    "..........",
  },
  restart = {
    "..........",
    "....###...",
    ".#.#...#..",
    ".##.....#.",
    ".###....#.",
    "........#.",
    "..#....#..",
    "...####...",
    "..........",
  },
  loop = {
    "..........",
    "......#...",
    ".#######..",
    ".#....#.#.",
    ".#......#.",
    ".#.#....#.",
    "..#######.",
    "...#......",
    "..........",
  },
  shuffle = {
    "..........",
    ".......#..",
    ".##..####.",
    "...#.#.#..",
    "....#.....",
    "...#.#.#..",
    ".##..####.",
    ".......#..",
    "..........",
  },
  loop_one = {
    "..........",
    "......#...",
    ".#######..",
    ".#...##.#.",
    ".#....#.#.",
    ".#.#..#.#.",
    "..#######.",
    "...#......",
    "..........",
  },
}
local BTN_W, BTN_H = 5, 3

-- Narrow screens (pocket computers) get the buttons on two rows and tighter spacing.
function X.compact() return W < 7 * BTN_W + 6 + 2 end
local BIT = { 1, 2, 4, 8, 16, 32 }

-- Draw a pixel grid ("#" = on) using teletext characters (2x3 pixels each).
function F.drawIcon(x, y, rows, fg, bg)
  local fgc, bgc = colours.toBlit(fg), colours.toBlit(bg)
  local cw, ch = math.floor(#rows[1] / 2), math.floor(#rows / 3)
  for cy = 0, ch - 1 do
    local s, f, b = {}, {}, {}
    for cx = 0, cw - 1 do
      local bits = 0
      for py = 0, 2 do
        local row = rows[cy * 3 + py + 1]
        for px = 0, 1 do
          local i = cx * 2 + px + 1
          if row:sub(i, i) == "#" then bits = bits + BIT[py * 2 + px + 1] end
        end
      end
      -- The bottom-right pixel can't be set directly: invert the cell instead.
      if bits >= 32 then
        s[#s + 1] = string.char(128 + 63 - bits)
        f[#f + 1], b[#b + 1] = bgc, fgc
      else
        s[#s + 1] = string.char(128 + bits)
        f[#f + 1], b[#b + 1] = fgc, bgc
      end
    end
    term.setCursorPos(x, y + cy)
    term.blit(table.concat(s), table.concat(f), table.concat(b))
  end
end

-- Draws a row of icon buttons centred on the screen.
-- Each item: { icon, fg, bg, fn, enabled }
function F.drawButtonRow(y, items)
  local total = #items * BTN_W + (#items - 1)
  local x = math.floor((W - total) / 2) + 1
  for _, it in ipairs(items) do
    local enabled = it[5] ~= false
    F.drawIcon(x, y, it[1], enabled and it[2] or C.muted, it[3])
    if enabled then F.addHit(x, y, BTN_W, BTN_H, it[4]) end
    x = x + BTN_W + 1
  end
end

-- Transport row. On wide screens restart and loop sit either side of it;
-- on narrow ones they get their own row underneath.
-- Returns the first free row below the buttons.
function F.drawControls(y)
  local has = now_playing ~= nil or #queue > 0
  local isPlaying = playing and not paused

  -- Loop: grey = off, orange = loop queue, green with a 1 = loop song
  local loopBtn
  if looping == 0 then
    loopBtn = { ICONS.loop, C.muted, C.btn, F.cycleLoop }
  elseif looping == 1 then
    loopBtn = { ICONS.loop, C.bg, C.accent, F.cycleLoop }
  else
    loopBtn = { ICONS.loop_one, C.bg, C.ok, F.cycleLoop }
  end
  local restartBtn = { ICONS.restart, C.text, C.btn, restart, now_playing ~= nil }
  local shuffleBtn = X.shuffle and { ICONS.shuffle, C.bg, C.accent, X.toggleShuffle }
    or { ICONS.shuffle, C.muted, C.btn, X.toggleShuffle }

  local transport = {
    { ICONS.prev, C.text, C.btn, F.prevTrack, has or #history > 0 },
    { isPlaying and ICONS.pause or ICONS.play, C.bg, C.accent, F.togglePause, has },
    { ICONS.stop, C.text, C.btn, stop, has },
    { ICONS.next, C.text, C.btn, F.nextTrack, has },
  }

  if W >= 7 * BTN_W + 6 + 2 then
    table.insert(transport, 1, restartBtn)
    table.insert(transport, 1, shuffleBtn)
    table.insert(transport, loopBtn)
    F.drawButtonRow(y, transport)
    return y + BTN_H + 1
  end

  F.drawButtonRow(y, transport)
  F.drawButtonRow(y + BTN_H + 1, { restartBtn, shuffleBtn, loopBtn })
  return y + 2 * (BTN_H + 1)
end

function F.drawVolume(y)
  local pct = math.floor(100 * F.effectiveVolume() / VOLUME_MAX + 0.5)
  local pctLabel = muted and "Mute" or (pct .. "%")
  pctLabel = string.rep(" ", 4 - #pctLabel) .. pctLabel
  local x = 2
  x = x + F.button(x, y, " - ", C.text, C.btn, function() F.setVolume(volume - VOLUME_STEP) end) + 1
  local bw = W - 2 - 3 - 1 - 3 - 1 - #pctLabel - 1
  if bw >= 3 then
    local bx = x
    F.fill(bx, y, bw, 1, C.btn)
    local filled = math.floor(bw * F.effectiveVolume() / VOLUME_MAX + 0.5)
    if filled > 0 then F.fill(bx, y, filled, 1, muted and C.muted or C.text) end
    F.addHit(bx, y, bw, 1, function(cx)
      F.setVolume((cx - bx + 1) / bw * VOLUME_MAX)
    end)
    x = x + bw + 1
  end
  x = x + F.button(x, y, " + ", C.text, C.btn, function() F.setVolume(volume + VOLUME_STEP) end) + 1
  F.button(x, y, pctLabel, C.muted, C.bg, F.toggleMute)
end

function F.drawNowPlaying()
  local status, statusCol = F.statusLine()
  text(2, 3, F.trunc(status, W - 2), statusCol, C.bg)
  if wireless then
    local spk = F.speakerSummary()
    if #status + #spk + 4 <= W then text(W - #spk, 3, spk, C.muted, C.bg) end
  end

  if now_playing then
    local np = now_playing
    text(2, 4, F.trunc(np.name, W - 6), C.text, C.bg)
    text(2, 5, F.trunc(np.artist, W - 6), C.muted, C.bg)
    -- Heart: red when it's a favourite. Tapping the title opens a song menu.
    local fav = F.isFavourite(np)
    text(W - 3, 4, " " .. G.heart .. " ", fav and C.err or C.muted, C.btn)
    F.addHit(W - 3, 4, 3, 2, function() F.toggleFavourite(np) end)
    F.addHit(1, 4, W - 5, 2, function()
      modal = { title = np.name, sub = np.artist, options = F.libraryOptions({}, np) }
      F.redraw()
    end)
  else
    text(2, 4, F.trunc("Pick something in Search", W - 2), C.text, C.bg)
  end

  local compact = X.compact()
  X.progress_row = compact and 6 or 7
  F.drawProgress(X.progress_row)
  local vy = F.drawControls(compact and 8 or 9)
  volume_row = vy
  F.drawVolume(vy)

  -- Up next / Visualiser: tap the heading to switch between them
  local y = vy + (compact and 1 or 2)
  if y > H then return end
  local upLabel, vizLabel = "Up next", "Visualiser"
  text(2, y, upLabel, X.viz and C.muted or C.text, C.bg)
  text(2 + #upLabel, y, "  " .. G.dot .. "  ", C.btn, C.bg)
  text(2 + #upLabel + 5, y, vizLabel, X.viz and C.text or C.muted, C.bg)
  F.addHit(1, y, #upLabel + 3, 1, function() X.viz = false; F.redraw() end)
  F.addHit(2 + #upLabel + 3, y, #vizLabel + 3, 1, function() X.viz = true; F.redraw() end)
  y = y + 1
  if y > H then return end
  if X.viz then
    X.drawViz(y, H - y + 1)
    return
  end
  if #queue == 0 then
    text(2, y, "Queue is empty", C.muted, C.bg)
    return
  end
  local room = H - y + 1
  local shown = math.min(#queue, room)
  if #queue > room then shown = room - 1 end
  for i = 1, shown do
    local it = queue[i]
    local line = F.trunc(it.name, W - 4)
    text(2, y, G.dot .. " ", C.accent, C.bg)
    text(4, y, line, C.text, C.bg)
    local rest = W - 4 - #line - 3
    if rest > 3 and it.artist then
      text(4 + #line, y, " - " .. F.trunc(it.artist, rest), C.muted, C.bg)
    end
    y = y + 1
  end
  if #queue > shown then
    text(2, y, F.trunc("+" .. (#queue - shown) .. " more in Queue", W - 2), C.muted, C.bg)
    F.addHit(1, y, W, 1, function() tab = 3; F.redraw() end)
  end
end

-- Draws a scrollable two-line-per-item list. Returns nothing.
function F.drawList(tabIndex, list, y0, onClick, decorate)
  local rows = math.floor((H - y0 + 1) / 2)
  local maxScroll = math.max(0, #list - rows)
  if scroll[tabIndex] > maxScroll then scroll[tabIndex] = maxScroll end
  local first = scroll[tabIndex] + 1
  for i = first, math.min(#list, first + rows - 1) do
    local y = y0 + (i - first) * 2
    local it = list[i]
    local prefix, suffix = "", ""
    if decorate then prefix, suffix = decorate(i, it) end
    local nameW = W - 2 - #prefix - #suffix
    text(2, y, prefix, C.accent, C.bg)
    if it.kind == "header" then
      text(2 + #prefix, y + 1, F.trunc(it.name, nameW), C.muted, C.bg)
    else
      text(2 + #prefix, y, F.trunc(it.name, nameW), it.too_long and C.muted or C.text, C.bg)
      if #suffix > 0 then text(W - #suffix, y, suffix, it.too_long and C.muted or C.accent, C.bg) end
      text(2 + #prefix, y + 1, F.trunc(it.artist, W - 2 - #prefix), C.muted, C.bg)
      F.addHit(1, y, W, 2, function() onClick(i, it) end)
    end
  end
  F.scrollArrows(tabIndex, y0, maxScroll, math.max(1, rows - 1))
end

-- Word-wrap a string to width w.
function F.wrap(s, w)
  local lines, line = {}, ""
  for word in tostring(s):gmatch("%S+") do
    while #word > w do
      if #line > 0 then lines[#lines + 1] = line; line = "" end
      lines[#lines + 1] = word:sub(1, w)
      word = word:sub(w + 1)
    end
    if #line == 0 then line = word
    elseif #line + 1 + #word <= w then line = line .. " " .. word
    else lines[#lines + 1] = line; line = word end
  end
  if #line > 0 then lines[#lines + 1] = line end
  return lines
end

-- Recently played, newest first, no repeats.
function F.recentTracks()
  local recent, seen = {}, {}
  for i = #history, 1, -1 do
    local it = history[i]
    if it.id and not seen[it.id] then
      seen[it.id] = true
      recent[#recent + 1] = it
    end
  end
  return recent
end

function F.recentMenu(it)
  modal = {
    title = it.name, sub = it.artist,
    options = F.libraryOptions({
      -- Unlike a search result, this keeps your queue as it is
      { "Play now", function()
        F.pushHistory(now_playing)
        F.loadTrack(F.copyTracks({ it })[1])
        tab = 1
      end },
      { "Play next", function() F.playNext(F.copyTracks({ it })[1]) end },
      { "Add to queue", function() F.addToQueue(F.copyTracks({ it })[1]) end },
    }, it),
  }
  F.redraw()
end

-- Library home: favourites, playlists, then recently played.
function F.drawLibrary()
  local entries = {
    { kind = "list", pl = F.favList(), name = "Favourites", artist = #favourites .. (#favourites == 1 and " song" or " songs") },
  }
  for _, pl in ipairs(playlists) do
    entries[#entries + 1] = { kind = "list", pl = pl, name = pl.name, artist = #pl.tracks .. (#pl.tracks == 1 and " song" or " songs") }
  end
  if #playlists < PLAYLIST_MAX then
    entries[#entries + 1] = { kind = "new", name = "+ New playlist", artist = "Start an empty one" }
  end
  local recent = F.recentTracks()
  if #recent > 0 then
    entries[#entries + 1] = { kind = "header", name = "Recently played" }
    for _, it in ipairs(recent) do
      entries[#entries + 1] = { kind = "track", it = it, name = it.name, artist = it.artist }
    end
  end

  text(2, 7, "Library", C.muted, C.bg)
  if #history > 0 then
    local clearLabel = W >= 34 and " Clear recent " or " Clear "
    F.button(W - #clearLabel, 7, clearLabel, C.text, C.btn, function()
      history = {}
      scroll[2] = 0
      F.redraw()
    end)
  end

  F.drawList(2, entries, 9, function(_, e)
    if e.kind == "list" then
      F.playlistMenu(e.pl)
    elseif e.kind == "new" then
      F.askText("Name the new playlist", "", function(name)
        if F.trim(name) ~= "" then F.newPlaylist(name, {}) end
      end)
    elseif e.kind == "track" then
      F.recentMenu(e.it)
    end
  end, function(_, e)
    if e.kind == "list" then return (e.pl.fav and G.heart or G.note) .. " ", "" end
    return "", ""
  end)
end

-- One playlist's songs, opened from the library.
function F.drawPlaylist(pl)
  local menuLabel, playLabel = " " .. G.more .. " ", " Play "
  local mx = W - #menuLabel
  local px = mx - 1 - #playLabel
  text(2, 7, F.trunc((pl.fav and G.heart or G.note) .. " " .. pl.name, px - 3), C.accent, C.bg)
  F.button(px, 7, playLabel, #pl.tracks > 0 and C.bg or C.muted, C.accent,
    #pl.tracks > 0 and function() F.playTracks(pl.tracks, false) end or nil)
  F.button(mx, 7, menuLabel, C.text, C.btn, function() F.playlistMenu(pl) end)

  if #pl.tracks == 0 then
    local msg = pl.fav and "Tap the heart on Now Playing to add songs here."
      or "Empty. Use 'Add to playlist' on any song."
    local y = 9
    for _, l in ipairs(F.wrap(msg, W - 2)) do
      text(2, y, l, C.muted, C.bg)
      y = y + 1
    end
    return
  end

  local function indexOf(it)
    for k, v in ipairs(pl.tracks) do if v == it then return k end end
  end

  F.drawList(2, pl.tracks, 9, function(_, it)
    modal = {
      title = it.name, sub = it.artist,
      options = {
        { "Play now", function()
          F.pushHistory(now_playing)
          F.loadTrack(F.copyTracks({ it })[1])
          tab = 1
        end },
        { "Play next", function() F.playNext(F.copyTracks({ it })[1]) end },
        { "Add to queue", function() F.addToQueue(F.copyTracks({ it })[1]) end },
        { "Move up", function()
          local i = indexOf(it)
          if i and i > 1 then
            pl.tracks[i], pl.tracks[i - 1] = pl.tracks[i - 1], pl.tracks[i]
            F.saveLibrary()
          end
        end },
        { "Move down", function()
          local i = indexOf(it)
          if i and i < #pl.tracks then
            pl.tracks[i], pl.tracks[i + 1] = pl.tracks[i + 1], pl.tracks[i]
            F.saveLibrary()
          end
        end },
        { pl.fav and "Unfavourite" or "Remove from playlist", function()
          local i = indexOf(it)
          if i then
            table.remove(pl.tracks, i)
            F.saveLibrary()
          end
        end },
      },
    }
    F.redraw()
  end, function(i)
    return i .. ". ", ""
  end)
end

function F.drawSearch()
  F.fill(2, 3, W - 2, 3, C.panel)
  local boxW = W - 4
  -- An x to clear the search (or close a playlist) and go back to the library
  if last_search or open_playlist then
    boxW = W - 7
    text(W - 4, 4, " " .. G.close .. " ", C.muted, C.panel)
    F.addHit(W - 4, 3, 3, 3, function()
      last_search, last_search_url = nil, nil
      search_results, search_error = nil, false
      open_playlist = nil
      scroll[2] = 0
      F.redraw()
    end)
  end
  if last_search then
    text(3, 4, F.trunc(last_search, boxW), C.text, C.panel)
  else
    text(3, 4, F.trunc("Search or paste a YouTube link", boxW), C.muted, C.panel)
  end
  F.addHit(2, 3, W - 2, 3, function() waiting_for_input = true end)

  if search_results then
    if #search_results == 0 then
      text(2, 7, "No results", C.muted, C.bg)
      return
    end
    F.drawList(2, search_results, 7, function(i, it)
      modal = {
        title = it.name,
        sub = (it.live and "Live streams can't be played")
          or (it.too_long and "Over 15 min - the server usually can't play these") or it.artist,
        options = F.libraryOptions({
          { "Play now", function() F.playNow(it) end },
          { "Play next", function() F.playNext(it) end },
          { "Add to queue", function() F.addToQueue(it) end },
        }, it),
      }
      F.redraw()
    end, function(i, it)
      if it.type == "playlist" then return "", " [list]" end
      if it.live then return "", " LIVE" end
      return "", it.too_long and " >15m" or ""
    end)
  elseif search_error then
    text(2, 7, "Network error", C.err, C.bg)
  elseif last_search_url then
    text(2, 7, "Searching...", C.muted, C.bg)
  elseif open_playlist then
    F.drawPlaylist(open_playlist)
  else
    F.drawLibrary()
  end
end

function F.drawQueue()
  -- Header buttons, laid out from the right: Clear, Shuffle, Save
  local x = W
  local function place(label, fn)
    x = x - #label
    F.button(x, 3, label, fn and C.text or C.muted, C.btn, fn)
    x = x - 1
  end
  place(" Clear ", #queue > 0 and function()
    queue = {}; scroll[3] = 0; F.redraw()
  end or nil)
  place((x - 9 - 7 >= 12) and " Shuffle " or " Mix ", #queue > 1 and F.shuffleQueue or nil)
  place(" Save ", (now_playing or #queue > 0) and function()
    F.askText("Save queue as a playlist", "", function(name)
      if F.trim(name) == "" then return end
      local tracks = {}
      if now_playing then tracks[1] = now_playing end
      for _, t in ipairs(queue) do tracks[#tracks + 1] = t end
      F.newPlaylist(name, tracks)
    end)
  end or nil)
  local title = "Queue (" .. #queue .. ")"
  if 2 + #title >= x then title = "(" .. #queue .. ")" end
  if 2 + #title < x then text(2, 3, title, C.text, C.bg) end

  if #queue == 0 then
    text(2, 5, "Nothing queued. Add songs from Search.", C.muted, C.bg)
    return
  end

  -- Look the item up again when an option runs: the queue may have moved on.
  local function indexOf(it)
    for k, v in ipairs(queue) do if v == it then return k end end
  end

  F.drawList(3, queue, 5, function(_, it)
    modal = {
      title = it.name, sub = it.artist,
      options = {
        { "Play now", function()
          local i = indexOf(it)
          if i then table.remove(queue, i) end
          F.pushHistory(now_playing)
          F.loadTrack(it)
        end },
        { "Move up", function()
          local i = indexOf(it)
          if i and i > 1 then queue[i], queue[i - 1] = queue[i - 1], queue[i] end
        end },
        { "Move down", function()
          local i = indexOf(it)
          if i and i < #queue then queue[i], queue[i + 1] = queue[i + 1], queue[i] end
        end },
        { "Remove", function()
          local i = indexOf(it)
          if i then table.remove(queue, i) end
        end },
        { "Add to playlist...", function() F.choosePlaylistFor({ it }, it.name) end },
      },
    }
    F.redraw()
  end, function(i)
    return i .. ". ", ""
  end)
end

function F.setGroup(name)
  name = F.trim(name):sub(1, 24)
  if name == "" or name == group then return end
  if wireless then
    -- Silence the old group's speakers before we leave it
    rednet.broadcast({ type = "stop", group = group, pin = pin }, PROTOCOL)
  end
  group = name
  settings.set("phoenix_music.group", name)
  settings.save()
  receivers = {}
  if wireless then rednet.broadcast({ type = "ping", group = group, pin = pin }, PROTOCOL) end
  F.redraw()
end

function F.drawAbout()
  local top = 3
  local y = top - scroll[5]
  local function visible(row) return row >= top and row <= H end
  local function line(s, fg)
    if visible(y) then text(2, y, F.trunc(s, W - 2), fg, C.bg) end
    y = y + 1
  end
  local function para(s, fg)
    for _, l in ipairs(F.wrap(s, W - 2)) do line(l, fg) end
  end
  local function gap() y = y + 1 end

  -- Title and version
  if visible(y) then
    text(2, y, F.trunc(G.note .. " " .. APP.name, W - 2), C.accent, C.bg)
    local ver = "v" .. APP.version
    if 2 + #APP.name + 2 + 1 + #ver <= W - 1 then text(W - #ver, y, ver, C.muted, C.bg) end
  end
  y = y + 1
  if 2 + #APP.name + 2 + 1 + #("v" .. APP.version) > W - 1 then line("v" .. APP.version, C.muted) end
  para("(c) " .. APP.year .. " " .. APP.publisher, C.text)
  gap()

  -- Credits
  para("Based on " .. APP.original, C.muted)
  para("by " .. APP.original_author, C.text)
  para(APP.original_url, C.muted)
  para("Original server and audio engine by terreng. New interface and controls by " .. APP.publisher .. ".", C.muted)
  para("Released under the MIT License.", C.muted)
  para("Speaker Link and playlists inspired by JzJad's Jukebox (craftfm.cc).", C.muted)
  gap()
  para("The music server is free but costs terreng money to run. Support it: patreon.com/exclamatory", C.accent)
  gap()

  line("v" .. APP.version .. "  " .. W .. "x" .. H, C.muted)

  -- Scrolling: clamp, and show arrows when there's more
  local maxScroll = math.max(0, (y - 1) - H + scroll[5])
  if scroll[5] > maxScroll then
    scroll[5] = maxScroll
    F.redraw()
  end
  F.scrollArrows(5, top, maxScroll, math.max(1, H - top))
end

function F.drawModal()
  hits = {} -- only the modal is clickable while it's open
  local opts = modal.options
  local spacing, shown = 2, #opts
  if 4 + shown * 2 + 1 > H then spacing = 1 end
  if 4 + shown * spacing + 1 > H then shown = math.max(1, H - 5) end
  local bw = math.min(W - 2, 30)
  local bh = 4 + shown * spacing + 1
  local bx = math.floor((W - bw) / 2) + 1
  local by = math.max(1, math.floor((H - bh) / 2) + 1)
  F.fill(bx, by, bw, bh, C.panel)
  text(bx + 1, by + 1, F.trunc(modal.title, bw - 2), C.text, C.panel)
  text(bx + 1, by + 2, F.trunc(modal.sub, bw - 2), C.muted, C.panel)
  local y = by + 4
  for i = 1, shown do
    local opt = opts[i]
    F.fill(bx + 1, y, bw - 2, 1, C.btn)
    text(bx + 2, y, F.trunc(opt[1], bw - 4), C.text, C.btn)
    F.addHit(bx + 1, y, bw - 2, 1, function()
      modal = nil
      opt[2]()
      F.redraw()
    end)
    y = y + spacing
  end
  local cancel = "Cancel"
  text(bx + bw - #cancel - 1, by + bh - 1, cancel, C.accent, C.panel)
  F.addHit(bx + bw - #cancel - 1, by + bh - 1, #cancel, 1, function()
    modal = nil
    F.redraw()
  end)
  -- Clicks on the box itself do nothing; clicks outside it close it
  F.addHit(bx, by, bw, bh, function() end)
  F.addHit(1, 1, W, H, function() modal = nil; F.redraw() end)
end

function F.drawFrame()
  win.setVisible(false)
  hits = {}
  term.setCursorBlink(false)
  term.setBackgroundColour(C.bg)
  term.clear()

  F.drawTabs()
  if tab == 1 then F.drawNowPlaying()
  elseif tab == 2 then F.drawSearch()
  elseif tab == 3 then F.drawQueue()
  elseif tab == 4 then X.drawSettings()
  else F.drawAbout() end

  if modal then F.drawModal() end
  win.setVisible(true)
end

function F.redrawScreen()
  if waiting_for_input or prompt then return end
  F.drawFrame()
end

---------------------------------------------------------------------------
-- Input
---------------------------------------------------------------------------
function F.handleClick(x, y)
  for _, h in ipairs(hits) do
    if x >= h.x and x < h.x + h.w and y >= h.y and y < h.y + h.h then
      h.fn(x, y)
      return true
    end
  end
  return false
end

function F.startSearchInput()
  tab = 2
  modal = nil
  F.redrawScreen()
  waiting_for_input = true
end

function F.handleChar(ch)
  if ch == " " then F.togglePause()
  elseif ch == "n" then F.nextTrack()
  elseif ch == "p" then F.prevTrack()
  elseif ch == "s" then stop()
  elseif ch == "r" then restart()
  elseif ch == "l" then F.cycleLoop()
  elseif ch == "m" then F.toggleMute()
  elseif ch == "f" then F.toggleFavourite(now_playing)
  elseif ch == "h" then X.toggleShuffle()
  elseif ch == "v" then X.viz = not X.viz; F.redraw()
  elseif ch == "+" or ch == "=" then F.setVolume(volume + VOLUME_STEP)
  elseif ch == "-" or ch == "_" then F.setVolume(volume - VOLUME_STEP)
  elseif ch == "/" then F.startSearchInput()
  elseif ch == "q" then return "quit"
  end
end

function F.handleKey(key)
  if key == keys.left or key == keys.right then
    local from = X.seek_target or F.elapsedBytes()
    local step = SEEK_STEP * BYTES_PER_SEC * (key == keys.left and -1 or 1)
    X.requestSeek(from + step, 500)
  elseif key == keys.tab then tab = tab % 5 + 1; modal = nil; F.redraw()
  elseif key == keys.up and scroll[tab] then scroll[tab] = math.max(0, scroll[tab] - 1); F.redraw()
  elseif key == keys.down and scroll[tab] then scroll[tab] = scroll[tab] + 1; F.redraw()
  end
end

function F.doSearchInput()
  F.fill(2, 3, W - 2, 3, C.text)
  term.setCursorPos(3, 4)
  term.setBackgroundColour(C.text)
  term.setTextColour(C.bg)

  parallel.waitForAny(
    function()
      local input = read()
      if #input > 0 then
        last_search = input
        last_search_url = api_base_url .. "?v=" .. version .. "&search=" .. textutils.urlEncode(input)
        http.request({ url = last_search_url, binary = true })
        search_results = nil
        search_error = false
        open_playlist = nil
        scroll[2] = 0
      else
        last_search, last_search_url = nil, nil
        search_results, search_error = nil, false
      end
    end,
    function()
      -- Click (or tap) outside the box cancels typing
      while true do
        local ev, a, x, y = os.pullEvent()
        if ev == "mouse_click" or (ev == "monitor_touch" and a == monitor_name) then
          if y < 3 or y > 5 or x < 2 or x > W - 1 then break end
        end
      end
    end
  )
  waiting_for_input = false
  F.redraw()
end

-- Small box for typing a name. Enter saves, clicking outside cancels.
function F.doPrompt()
  local p = prompt
  F.drawFrame()
  local bw = math.min(W - 2, 30)
  local bh = 7
  local bx = math.floor((W - bw) / 2) + 1
  local by = math.max(1, math.floor((H - bh) / 2) + 1)
  F.fill(bx, by, bw, bh, C.panel)
  text(bx + 1, by + 1, F.trunc(p.title, bw - 2), C.text, C.panel)
  text(bx + 1, by + 5, F.trunc("Enter to save, tap away to cancel", bw - 2), C.muted, C.panel)

  local field = window.create(term.current(), bx + 1, by + 3, bw - 2, 1, true)
  field.setBackgroundColour(C.text)
  field.setTextColour(C.bg)
  field.clear()
  field.setCursorPos(2, 1)

  local result
  parallel.waitForAny(
    function()
      local prev = term.redirect(field)
      result = read(nil, nil, nil, p.initial)
      term.redirect(prev)
    end,
    function()
      while true do
        local ev, a, x, y = os.pullEvent()
        if ev == "mouse_click" or (ev == "monitor_touch" and a == monitor_name) then
          if x < bx or x >= bx + bw or y < by or y >= by + bh then break end
        end
      end
    end
  )
  term.redirect(win)
  prompt = nil
  if result and p.onDone then p.onDone(result) end
  F.redraw()
end

function F.uiLoop()
  F.redrawScreen()
  while true do
    if waiting_for_input then
      F.doSearchInput()
    elseif prompt then
      F.doPrompt()
    else
      local ev, a, b, c = os.pullEvent()
      if ev == "phoenix_quit" then
        return
      elseif ev == "mouse_click" and a == 1 then
        F.handleClick(b, c)
      elseif ev == "monitor_touch" and a == monitor_name then
        F.handleClick(b, c)
      elseif ev == "mouse_up" then
        if X.seek_target then X.seek_due = F.now_ms(); X.applySeek() end
      elseif ev == "mouse_drag" and a == 1 and not modal then
        -- Dragging along the progress or volume bar scrubs it
        if (tab == 1 and (c == X.progress_row or c == volume_row)) then F.handleClick(b, c) end
      elseif ev == "mouse_scroll" and scroll[tab] and not modal then
        scroll[tab] = math.max(0, scroll[tab] + a)
        F.redraw()
      elseif ev == "char" and not modal then
        if F.handleChar(a) == "quit" then return end
      elseif ev == "key" and modal then
        if a == keys.backspace or a == keys.enter then modal = nil; F.redraw() end
      elseif ev == "key" then
        F.handleKey(a)
      elseif ev == "redraw_screen" then
        F.redrawScreen()
      elseif ev == "term_resize" or ev == "monitor_resize" then
        W, H = parent.getSize()
        win.reposition(1, 1, W, H)
        F.redrawScreen()
      end
    end
  end
end

---------------------------------------------------------------------------
-- Audio (same pipeline as the original: 16 KiB chunks -> DFPWM decoder ->
-- speaker.playAudio, waiting on speaker_audio_empty / playback_stopped)
---------------------------------------------------------------------------
function F.feedSpeakers(buffer, still_valid)
  -- No speaker here: the audio loop paces itself off the clock instead.
  if #speakers == 0 then return true end

  -- Every speaker waits until it has room for this chunk, so none of them
  -- skips audio (that matters when one song runs straight into the next and
  -- the speakers are still finishing the last one).
  local fn = {}
  for i, speaker in ipairs(speakers) do
    fn[i] = function()
      local name = peripheral.getName(speaker)
      while not speaker.playAudio(buffer, F.effectiveVolume()) do
        parallel.waitForAny(
          function()
            repeat until select(2, os.pullEvent("speaker_audio_empty")) == name
          end,
          function()
            os.pullEvent("playback_stopped")
          end
        )
        if not still_valid() then return end
      end
    end
  end
  return pcall(parallel.waitForAll, table.unpack(fn))
end

function F.audioLoop()
  while true do
    if playing and not paused and now_playing then
      local this_id = now_playing.id
      if playing_id ~= this_id then
        playing_id = this_id
        playing_status = 0
        needs_next_chunk = 1
        local cached = X.cacheGet(this_id)
        if cached then
          last_download_url = nil
          X.openAudio(cached)
        elseif X.prefetch and X.prefetch.id == this_id then
          -- Already on its way in the background: just wait for that
          last_download_url = X.prefetch.url
          X.prefetch = nil
          is_loading = true
          F.redraw()
        else
          last_download_url = api_base_url .. "?v=" .. version .. "&id=" .. textutils.urlEncode(playing_id)
          http.request({ url = last_download_url, binary = true })
          is_loading = true
          F.redraw()
        end
      elseif playing_status == 1 and needs_next_chunk == 1 then
        local my_gen = audio_gen
        local function still_valid()
          return playing and not paused and playing_id == this_id and audio_gen == my_gen
        end

        while true do
          local chunk_start = byte_pos
          local chunk = player_handle.read(CHUNK)
          if not chunk then
            needs_next_chunk = 0
            F.onTrackEnd()
            break
          end
          byte_pos = byte_pos + #chunk

          local buffer = decoder(chunk)
          X.smooth_last = P.smooth(buffer, settings.get("phoenix_music.smoothing"), X.smooth_last)
          X.rememberBuffer(chunk_start, buffer)

          -- When this chunk should start playing, on the server clock. A fresh
          -- start (play, skip, seek, pause) picks a moment just ahead so every
          -- speaker - ours and linked ones - starts on the same tick; after
          -- that each chunk follows straight on from the last. Linked
          -- speakers use these times to start (or join) in step.
          local fresh, natural = X.sync_start, false
          local at
          if fresh then
            X.sync_start = false
            local linked = wireless and F.activeReceivers() > 0
            at = F.now_ms() + (linked and SYNC_LEAD or 0)
            if X.start_at and X.start_at > at then at, natural = X.start_at, true end
            X.start_at = nil
            anchor_pos, anchor_time, clock_running, need_anchor = chunk_start, at, true, false
          else
            at = anchor_time + (chunk_start - anchor_pos) * 1000 / BYTES_PER_SEC
          end

          if #speakers == 0 then
            -- No speaker here to set the pace: keep a few seconds ahead of
            -- the linked speakers, timed off the clock.
            X.waitUntil(at - LEAD_AHEAD)
            if not still_valid() then break end
          end
          F.broadcastChunk(chunk, at)
          if fresh and not natural and #speakers > 0 then
            X.waitUntil(at)
            if not still_valid() then break end
          end

          local ok = F.feedSpeakers(buffer, still_valid)
          if not ok then
            needs_next_chunk = 2
            is_error = true
            F.redraw()
            break
          end

          if not still_valid() then break end
        end
      end
    end
    os.pullEvent("audio_update")
  end
end

function F.httpLoop()
  while true do
    local ev, url, handle = os.pullEvent()
    if ev == "http_success" then
      if url == last_search_url then
        search_results = textutils.unserialiseJSON(X.fromUtf8(handle.readAll() or ""))
        handle.close()
        if type(search_results) ~= "table" then
          search_results, search_error = nil, true
        else
          -- The server slips a donation banner in as a fake first result.
          -- Real results always have an id; the banner links to Patreon.
          -- (The About tab credits the server and links his Patreon instead.)
          local real = {}
          for _, r in ipairs(search_results) do
            if type(r) == "table" and r.id then
              local blob = tostring(r.name or "") .. " " .. tostring(r.artist or "")
              if not blob:lower():find("patreon", 1, true) then
                X.tidyItem(r)
                r.too_long = r.type ~= "playlist" and (X.tooLong(r) or r.live)
                real[#real + 1] = r
              end
            end
          end
          X.all_results = real
          X.filterResults()
        end
        F.redraw()
      elseif url == last_download_url and playing_status == 0 then
        local data = handle.readAll() or ""
        handle.close()
        if now_playing and now_playing.id then X.cachePut(now_playing.id, data) end
        X.openAudio(data)
      elseif X.prefetch and url == X.prefetch.url then
        local data = handle.readAll() or ""
        handle.close()
        X.cachePut(X.prefetch.id, data)
        X.prefetch = nil
      elseif type(url) == "string" and url:sub(1, #api_base_url) == api_base_url then
        pcall(handle.close) -- an old request we no longer want
      end
    elseif ev == "http_failure" then
      if url == last_search_url then
        search_error = true
        F.redraw()
      elseif url == last_download_url then
        is_loading = false
        is_error = true
        local live = now_playing and tostring(now_playing.artist):find("^LIVE %- ")
        X.error_text = (live and "Live streams can't be played")
          or (X.tooLong(now_playing) and "Too long for the server (15 min max)")
          or "Couldn't load this song"
        if #queue > 0 then X.skip_at = F.now_ms() + 3000 end
        playing = false
        playing_id = nil
        F.redraw()
        os.queueEvent("audio_update")
      elseif X.prefetch and url == X.prefetch.url then
        X.prefetch_failed[X.prefetch.id] = true
        X.prefetch = nil
      end
    end
  end
end

-- Keeps track of receivers in our speaker group and answers remotes.
function F.netLoop()
  if not wireless then
    while true do os.pullEvent("phoenix_music_never") end
  end
  rednet.broadcast({ type = "ping", group = group, pin = pin }, PROTOCOL)
  while true do
    local id, msg = rednet.receive(PROTOCOL, 5)
    if id and P.ok(msg, group, pin) then
      if msg.type == "hello" then
        local isNew = receivers[id] == nil
        receivers[id] = {
          label = msg.label, speakers = tonumber(msg.speakers) or 1,
          volume = tonumber(msg.volume) or 100, seen = os.clock(),
        }
        if isNew then F.redraw() end
      elseif msg.type == "cmd" then
        X.remoteCommand(msg)
        X.broadcastState()
      elseif msg.type == "remote_hello" then
        X.broadcastState()
      end
    end
    for rid, r in pairs(receivers) do
      if os.clock() - r.seen > RECEIVER_TIMEOUT then
        receivers[rid] = nil
        F.redraw()
      end
    end
  end
end

-- Keeps the progress bar and clock ticking, and runs the timers.
function F.tickLoop()
  while true do
    sleep(0.5)
    if tab == 1 and not modal and playing and not paused then F.redraw() end
    pcall(F.saveState)

    X.dueUpdateCheck()
    X.maybePrefetch()

    -- Volume changed: pick the song back up at the same spot so it applies
    if X.vol_dirty_at and F.now_ms() >= X.vol_dirty_at then
      X.vol_dirty_at = nil
      if playing and not paused and playing_status == 1 then
        pause()
        F.resume()
      end
    end

    -- After a song fails to load, move on to the next one
    if X.skip_at and F.now_ms() >= X.skip_at then
      X.skip_at = nil
      if is_error and #queue > 0 then F.nextTrack() end
    end

    -- Sleep timer
    if X.sleep_at and F.now_ms() >= X.sleep_at then
      X.sleep_at = nil
      pause()
    end

    -- Alarm: fires when the Minecraft clock passes the alarm time
    local t = os.time()
    if X.alarm and X.last_mc_time then
      local a, p = tonumber(X.alarm.time), X.last_mc_time
      local crossed
      if p <= t then crossed = a > p and a <= t
      else crossed = a > p or a <= t end -- the day rolled over (or someone slept)
      if crossed then X.fireAlarm() end
    end
    X.last_mc_time = t

    if wireless then X.broadcastState() end
    if tab == 4 then F.redraw() end -- keeps the Settings countdowns fresh
  end
end

---------------------------------------------------------------------------
-- Visualiser
---------------------------------------------------------------------------
-- Keeps the last few decoded chunks so we can look at what's playing now.
function X.rememberBuffer(start, buf)
  table.insert(X.viz_bufs, { start = start, buf = buf })
  if #X.viz_bufs > 4 then table.remove(X.viz_bufs, 1) end
end

-- Bar heights (0-1) for the audio playing right now. Low bars follow the
-- loudness, high bars follow how fast the wave is changing (the treble), so
-- it behaves roughly like a spectrum without needing an FFT.
function X.vizLevels(n)
  local levels = X.viz_levels
  local buf, off
  if playing and not paused and clock_running then
    local pos = F.elapsedBytes() * 8 -- 8 samples per DFPWM byte
    for i = #X.viz_bufs, 1, -1 do
      local b = X.viz_bufs[i]
      local s0 = b.start * 8
      if pos >= s0 and pos < s0 + #b.buf then
        buf, off = b.buf, math.floor(pos - s0) + 1
        break
      end
    end
  end
  local seg = math.max(8, math.floor(2400 / n)) -- 50 ms of audio across the bars
  for i = 1, n do
    local target = 0
    if buf then
      local a = off + (i - 1) * seg
      local b = math.min(#buf, a + seg - 1)
      local sum, dsum, cnt, prev = 0, 0, 0, buf[a] or 0
      for j = a, b, 2 do
        local v = buf[j]
        sum = sum + v * v
        local d = v - prev
        dsum = dsum + d * d
        prev = v
        cnt = cnt + 1
      end
      if cnt > 0 then
        local f = n > 1 and (i - 1) / (n - 1) or 0
        local rms = math.sqrt(sum / cnt) / 128
        local drms = math.sqrt(dsum / cnt) / 256
        target = math.min(1, ((1 - f) * rms + f * drms * 1.4) * 1.5) ^ 0.7
      end
    end
    local cur = levels[i] or 0
    levels[i] = target > cur and target or cur * 0.7
  end
  for i = n + 1, #levels do levels[i] = nil end
  return levels
end

-- Bars, 2 wide with a 1 gap, using teletext thirds for smoother heights.
function X.drawViz(y0, rows)
  if rows < 1 then return end
  local n = math.max(1, math.floor((W - 2 + 1) / 3))
  local levels = X.vizLevels(n)
  local x0 = math.floor((W - (n * 3 - 1)) / 2) + 1
  local steps = rows * 3
  for i = 1, n do
    local h = math.floor((levels[i] or 0) * steps + 0.5)
    local x = x0 + (i - 1) * 3
    for r = 0, rows - 1 do
      local y = y0 + rows - 1 - r
      local f = h - r * 3
      if f >= 3 then
        F.fill(x, y, 2, 1, C.accent)
      elseif f == 2 then
        text(x, y, "\131\131", C.bg, C.accent)
      elseif f == 1 then
        text(x, y, "\143\143", C.bg, C.accent)
      elseif r == 0 then
        text(x, y, "\143\143", C.bg, C.btn) -- faint baseline
      end
    end
  end
end

-- Redraws quickly while the visualiser is on screen.
function X.vizLoop()
  while true do
    sleep(0.1)
    X.applySeek()
    if tab == 1 and X.viz and not modal and not prompt and not waiting_for_input
      and playing and not paused then
      F.redraw()
    end
  end
end

---------------------------------------------------------------------------
-- Redstone trigger, sleep timer and alarm
---------------------------------------------------------------------------
-- Favourites are stored as "__fav"; anything else is a playlist name.
function X.listByName(name)
  if name == "__fav" then return F.favList() end
  if type(name) == "string" then return F.findPlaylist(name) end
end

function X.listLabel(name)
  if name == "__fav" then return "Favourites" end
  return name or "?"
end

function X.runTrigger(t)
  if t.kind == "toggle" then
    F.togglePause()
  elseif t.kind == "next" then
    F.nextTrack()
  elseif t.kind == "list" then
    local pl = X.listByName(t.name)
    if pl and #pl.tracks > 0 then F.playTracks(pl.tracks, false) end
  end
  F.redraw()
end

-- A redstone signal turning on (any side) runs the chosen action.
function X.redstoneLoop()
  if not redstone then
    while true do os.pullEvent("phoenix_music_never") end -- pocket computers
  end
  local sides = redstone.getSides()
  local prev = {}
  for _, side in ipairs(sides) do prev[side] = redstone.getInput(side) end
  while true do
    os.pullEvent("redstone")
    local rising = false
    for _, side in ipairs(sides) do
      local v = redstone.getInput(side)
      if v and not prev[side] then rising = true end
      prev[side] = v
    end
    if rising and X.redstone then X.runTrigger(X.redstone) end
  end
end

function X.fireAlarm()
  local pl = X.alarm and X.listByName(X.alarm.list)
  if pl and #pl.tracks > 0 then
    F.playTracks(pl.tracks, false)
  elseif not (playing and not paused) then
    F.resume()
  end
  F.redraw()
end

function X.fmtClock(t)
  t = tonumber(t) or 0
  local h = math.floor(t)
  local m = math.floor((t - h) * 60 + 0.5)
  if m == 60 then h, m = (h + 1) % 24, 0 end
  return string.format("%d:%02d", h, m)
end

-- "7", "7:30", "19:05" -> hours as a number, or nil.
function X.parseClock(str)
  str = P.trim(str)
  local h, m = str:match("^(%d+):(%d%d)$")
  if not h then h, m = str:match("^(%d+)$"), "0" end
  h, m = tonumber(h), tonumber(m)
  if not h or not m or h > 23 or m > 59 then return nil end
  return h + m / 60
end

-- Modal listing Favourites and every playlist; fn gets the stored name.
function X.pickList(title, sub, fn, extra)
  local opts = {}
  for _, e in ipairs(extra or {}) do opts[#opts + 1] = e end
  opts[#opts + 1] = { G.heart .. " Favourites", function() fn("__fav") end }
  for _, pl in ipairs(playlists) do
    local name = pl.name
    opts[#opts + 1] = { G.note .. " " .. name, function() fn(name) end }
  end
  modal = { title = title, sub = sub, options = opts }
  F.redraw()
end

function X.sleepMenu()
  local function after(mins)
    return function()
      X.sleep_after_song = false
      X.sleep_at = F.now_ms() + mins * 60000
    end
  end
  modal = {
    title = "Sleep timer", sub = "Pause the music after...",
    options = {
      { "15 minutes", after(15) },
      { "30 minutes", after(30) },
      { "1 hour", after(60) },
      { "90 minutes", after(90) },
      { "The end of this song", function() X.sleep_at = nil; X.sleep_after_song = true end },
      { "Turn off", function() X.sleep_at = nil; X.sleep_after_song = false end },
    },
  }
  F.redraw()
end

function X.alarmMenu()
  local function setAlarm()
    F.askText("Alarm time (Minecraft clock, e.g. 7:00)", X.alarm and X.fmtClock(X.alarm.time) or "7:00", function(v)
      local t = X.parseClock(v)
      if not t then return end
      X.pickList("Play what at " .. X.fmtClock(t) .. "?", "Or carry on with the queue", function(name)
        X.alarm = { time = t, list = name }
      end, {
        { "Resume the queue", function() X.alarm = { time = t } end },
      })
    end)
  end
  if not X.alarm then
    setAlarm()
    return
  end
  modal = {
    title = "Alarm", sub = X.fmtClock(X.alarm.time) .. " every day",
    options = {
      { "Change alarm", setAlarm },
      { "Turn off", function() X.alarm = nil end },
    },
  }
  F.redraw()
end

function X.redstoneMenu()
  local function set(t) return function() X.redstone = t end end
  X.pickList("Redstone trigger", "When a redstone signal turns on...", function(name)
    X.redstone = { kind = "list", name = name }
  end, {
    { "Off", set(nil) },
    { "Play / pause", set({ kind = "toggle" }) },
    { "Next song", set({ kind = "next" }) },
  })
end

function X.redstoneLabel()
  local t = X.redstone
  if not t then return "Off" end
  if t.kind == "toggle" then return "Play / pause" end
  if t.kind == "next" then return "Next song" end
  return "Play " .. X.listLabel(t.name)
end

---------------------------------------------------------------------------
-- Settings tab
---------------------------------------------------------------------------
function X.setPin(v)
  v = P.trim(v):sub(1, 12)
  if v == pin then return end
  if wireless then rednet.broadcast({ type = "stop", group = group, pin = pin }, PROTOCOL) end
  pin = v
  settings.set("phoenix_music.pin", pin)
  settings.save()
  receivers = {}
  if wireless then rednet.broadcast({ type = "ping", group = group, pin = pin }, PROTOCOL) end
  F.redraw()
end

function X.pinMenu()
  local opts = {
    { pin == "" and "Set a PIN..." or "Change PIN...", function()
      F.askText("PIN for this Speaker Link", "", X.setPin)
    end },
  }
  if pin ~= "" then opts[#opts + 1] = { "Remove PIN", function() X.setPin("") end } end
  modal = {
    title = "Speaker Link PIN",
    sub = "Linked speakers and remotes need the same PIN",
    options = opts,
  }
  F.redraw()
end

function X.sendRxVolume(id, value)
  local r = receivers[id]
  if not r then return end
  r.volume = math.max(0, math.min(150, value))
  rednet.send(id, { type = "rxvol", group = group, pin = pin, target = id, value = r.volume }, PROTOCOL)
  F.redraw()
end

---------------------------------------------------------------------------
-- Colour themes (background + accent, picked in Settings)
---------------------------------------------------------------------------
X.BACKGROUNDS = {
  { name = "Dark",     bg = 0x101217, panel = 0x1d2129, btn = 0x2f3540, muted = 0x8b93a3, text = 0xeceef3 },
  { name = "Midnight", bg = 0x0b1020, panel = 0x141b30, btn = 0x232d4a, muted = 0x8590b0, text = 0xe8ecf8 },
  { name = "Light",    bg = 0xf2f3f5, panel = 0xe1e4e9, btn = 0xc9ced6, muted = 0x667085, text = 0x14171c },
}
X.ACCENTS = {
  { name = "Orange", rgb = 0xff8a2b },
  { name = "Blue",   rgb = 0x3d8bfd },
  { name = "Green",  rgb = 0x3fb950 },
  { name = "Purple", rgb = 0x9d6bff },
  { name = "Red",    rgb = 0xf04848 },
  { name = "Pink",   rgb = 0xff5fa2 },
  { name = "Gold",   rgb = 0xf2c12e },
  { name = "Teal",   rgb = 0x22c3b5 },
}

local function findByName(list, name)
  for _, item in ipairs(list) do
    if item.name == name then return item end
  end
  return list[1]
end

-- Recolours the whole interface from the saved choices. The palette goes on
-- our window so it survives redraws; quitting restores the stock colours.
function X.applyTheme()
  local base = findByName(X.BACKGROUNDS, settings.get("phoenix_music.background"))
  local accent = findByName(X.ACCENTS, settings.get("phoenix_music.accent"))
  win.setPaletteColour(colours.black, base.bg)
  win.setPaletteColour(colours.grey, base.panel)
  win.setPaletteColour(colours.brown, base.btn)
  win.setPaletteColour(colours.lightGrey, base.muted)
  win.setPaletteColour(colours.white, base.text)
  win.setPaletteColour(colours.orange, accent.rgb)
  F.redraw()
end

function X.themeMenu(kind)
  local list = kind == "background" and X.BACKGROUNDS or X.ACCENTS
  local key = "phoenix_music." .. kind
  local current = settings.get(key)
  local opts = {}
  for _, item in ipairs(list) do
    local name = item.name
    opts[#opts + 1] = { (name == current and (G.dot .. " ") or "  ") .. name, function()
      settings.set(key, name)
      settings.save()
      X.applyTheme()
    end }
  end
  modal = {
    title = kind == "background" and "Background" or "Accent colour",
    sub = "Changes straight away",
    options = opts,
  }
  F.redraw()
end

---------------------------------------------------------------------------
-- Switching modes and updating
---------------------------------------------------------------------------
-- Quits and runs again with these arguments (e.g. { "remote" }).
function X.switchMode(list)
  X.switch_to = list or {}
  os.queueEvent("phoenix_quit")
end

function X.confirmSwitch(mode)
  modal = {
    title = mode == "remote" and "Use this as a remote?" or "Use this as a linked speaker?",
    sub = "Music playing here will stop",
    options = { { "Switch", function() X.switchMode({ mode }) end } },
  }
  F.redraw()
end

function X.requestCheck() os.queueEvent("phoenix_update", "check", true) end

-- The app is often left open for hours, so it re-checks every half hour.
function X.dueUpdateCheck()
  if X.next_check and F.now_ms() >= X.next_check and X.upd.state ~= "installing" then
    X.next_check = nil
    os.queueEvent("phoenix_update", "check", false)
  end
end
function X.requestInstall() os.queueEvent("phoenix_update", "install") end

function X.offerUpdate()
  local u = X.upd
  if u.state ~= "available" or remote_mode then return end
  modal = {
    title = "Update available: v" .. u.version,
    sub = "You have v" .. APP.version,
    options = {
      { "Update now", X.requestInstall },
      { "What's new", function() X.showNotes() end },
    },
  }
  F.redraw()
end

function X.showNotes()
  local opts = {}
  for _, n in ipairs(X.upd.notes or {}) do opts[#opts + 1] = { n, X.offerUpdate } end
  if #opts == 0 then opts[1] = { "No notes for this one", X.offerUpdate } end
  modal = { title = "What's new in v" .. tostring(X.upd.version), sub = "Tap a line to go back", options = opts }
  F.redraw()
end

-- Checks GitHub when the app opens and whenever someone asks; installs on request.
function X.updateLoop()
  sleep(2)
  os.queueEvent("phoenix_update", "check", false)
  while true do
    local _, what, manual = os.pullEvent("phoenix_update")
    if what == "check" and X.upd.state ~= "installing" then
      X.upd = { state = "checking" }
      F.redraw()
      local info, err = P.checkUpdate()
      if not info then
        X.upd = { state = "error", err = err }
      elseif info.newer then
        X.upd = { state = "available", version = info.version, notes = info.notes }
        -- Ask once per new version (and whenever someone checks by hand)
        if (manual or X.upd_offered ~= info.version) and not modal and not prompt and not waiting_for_input then
          X.upd_offered = info.version
          X.offerUpdate()
        end
      else
        X.upd = { state = "none" }
      end
      X.next_check = F.now_ms() + 30 * 60 * 1000 -- look again in half an hour
      F.redraw()
    elseif what == "install" and X.upd.state == "available" then
      local u = X.upd
      X.upd = { state = "installing", version = u.version, notes = u.notes }
      F.redraw()
      local ok, err = P.installUpdate()
      if ok then
        X.upd = { state = "installed", version = u.version }
        if not remote_mode then
          modal = {
            title = "Updated to v" .. u.version,
            sub = "Restart to start using it",
            options = { { "Restart now", function() X.switchMode(args) end } },
          }
        end
      else
        X.upd = { state = "available", version = u.version, notes = u.notes }
        if not remote_mode then
          modal = { title = "Update failed", sub = tostring(err), options = { { "Try again", X.requestInstall } } }
        end
      end
      F.redraw()
    end
  end
end

function X.drawSettings()
  local top = 3
  local y = top - scroll[4]
  local narrow = W < 40
  local BW = narrow and 8 or 10 -- every button on this page is the same width
  local function visible(row) return row >= top and row <= H end
  local function line(str, fg)
    if visible(y) then text(2, y, F.trunc(str, W - 3), fg, C.bg) end
    y = y + 1
  end
  local function para(str, fg)
    for _, l in ipairs(F.wrap(str, W - 3)) do line(l, fg) end
  end
  local function btn(label, fn, fg, bg)
    local pad = BW - #label
    local l = string.rep(" ", math.floor(pad / 2)) .. label .. string.rep(" ", pad - math.floor(pad / 2))
    F.button(W - BW, y, l, fg or C.text, bg or C.btn, fn)
  end
  -- "Label: value" on the left, a button on the right
  local function row(label, value, b, fn, valueCol)
    if visible(y) then
      local room = W - 2 - BW - 1
      text(2, y, F.trunc(label, room), C.muted, C.bg)
      if #label < room then text(2 + #label, y, F.trunc(value, room - #label), valueCol or C.text, C.bg) end
      btn(b, fn)
    end
    y = y + 1
  end
  -- A switch: the button shows (and flips) the state
  local function toggle(label, on, fn, onText, offText)
    if visible(y) then
      text(2, y, F.trunc(label, W - 3 - BW), C.muted, C.bg)
      btn(on and (onText or "On") or (offText or "Off"), fn, on and C.bg or C.text, on and C.accent or C.btn)
    end
    y = y + 1
  end
  local function gap() y = y + 1 end

  -- Speaker Link
  line("Speaker Link", C.accent)
  if wireless then
    row("Link: ", group, "Change", function()
      F.askText("New Link name (now " .. group .. ")", "", F.setGroup)
    end)
    row("PIN: ", pin == "" and "none" or string.rep("*", #pin), "PIN", X.pinMenu)
    line("Speakers here: " .. #speakers, C.muted)
    local rx, rxSpk = F.activeReceivers()
    if rx == 0 then
      para("Nothing linked yet. Run '" .. CMD .. " link' on another computer with a speaker and a modem.", C.muted)
    else
      line("Linked: " .. rx .. (narrow and "" or (" computer" .. (rx == 1 and "" or "s")))
        .. " (" .. rxSpk .. " speaker" .. (rxSpk == 1 and "" or "s") .. ")", C.muted)
      local now = os.clock()
      for id, r in pairs(receivers) do
        if now - r.seen <= RECEIVER_TIMEOUT then
          if visible(y) then
            local vol = (r.volume or 100) .. "%"
            local name = r.label or ("Computer " .. id)
            local rid = id
            text(2, y, G.dot .. " " .. F.trunc(name, W - 17), C.text, C.bg)
            text(W - 12, y, string.rep(" ", 4 - #vol) .. vol, C.muted, C.bg)
            F.button(W - 7, y, " - ", C.text, C.btn, function() X.sendRxVolume(rid, (r.volume or 100) - 10) end)
            F.button(W - 3, y, " + ", C.text, C.btn, function() X.sendRxVolume(rid, (r.volume or 100) + 10) end)
          end
          y = y + 1
        end
      end
    end
    row("Use as remote", "", "Switch", function() X.confirmSwitch("remote") end)
    if #speakers > 0 and not is_pocket then -- a pocket makes a poor fixed speaker
      row("Use as speaker", "", "Switch", function() X.confirmSwitch("link") end)
    end
  else
    para("Add a wireless or ender modem to link speakers on other computers or use a remote.", C.muted)
  end
  gap()

  -- Playback
  line("Playback", C.accent)
  toggle("Visualiser", X.viz, function() X.viz = not X.viz; F.redraw() end)
  toggle("Shuffle", X.shuffle, X.toggleShuffle)
  local sm = settings.get("phoenix_music.smoothing")
  local smoothOn = sm == "light" or sm == "strong"
  toggle("Smoothing", smoothOn, function()
    settings.set("phoenix_music.smoothing", smoothOn and "off" or "light")
    settings.save()
    F.redraw()
  end)
  local hide = settings.get("phoenix_music.hide_long")
  toggle(narrow and "Long & live" or "Long & live videos", hide, function()
    settings.set("phoenix_music.hide_long", not hide)
    settings.save()
    X.filterResults()
    F.redraw()
  end, "Hidden", "Shown")
  gap()

  -- Appearance
  line("Appearance", C.accent)
  row("Background: ", findByName(X.BACKGROUNDS, settings.get("phoenix_music.background")).name, "Change",
    function() X.themeMenu("background") end)
  row("Accent: ", findByName(X.ACCENTS, settings.get("phoenix_music.accent")).name, "Change",
    function() X.themeMenu("accent") end, C.accent)
  gap()

  -- Timers and triggers
  line("Timers", C.accent)
  local sleepVal = "Off"
  if X.sleep_at then
    sleepVal = math.max(1, math.ceil((X.sleep_at - F.now_ms()) / 60000)) .. " min left"
  elseif X.sleep_after_song then
    sleepVal = "After song"
  end
  row("Sleep: ", sleepVal, "Set", X.sleepMenu)
  local alarmVal = "Off"
  if X.alarm then
    alarmVal = X.fmtClock(X.alarm.time) .. (X.alarm.list and (", " .. X.listLabel(X.alarm.list)) or "")
  end
  row("Alarm: ", alarmVal, "Set", X.alarmMenu)
  if redstone then
    row("Redstone: ", X.redstoneLabel(), "Set", X.redstoneMenu)
  end
  line("Minecraft time: " .. X.fmtClock(os.time()), C.muted)
  gap()

  -- Updates
  line("Updates", C.accent)
  local u = X.upd
  row("Version: ", "v" .. APP.version, "Check", X.requestCheck)
  if u.state == "available" then
    row("New: ", "v" .. u.version, "Update", X.requestInstall, C.accent)
  elseif u.state == "installed" then
    row("Updated: ", "v" .. u.version, "Restart", function() X.switchMode(args) end, C.accent)
  else
    local msg = ({
      idle = "Not checked yet", checking = "Checking...", none = "Up to date",
      installing = "Updating...", error = "Couldn't check: " .. tostring(u.err),
    })[u.state] or ""
    line(msg, C.muted)
  end
  local branch = settings.get("phoenix_music.update_channel")
  if branch ~= "main" and branch ~= "" then line("Update branch: " .. branch, C.muted) end

  -- On pocket computers About isn't a tab, so it's reached from here
  if W < 34 then
    gap()
    line("About", C.accent)
    row(APP.name .. " ", "", "Open", function() tab = 5; F.redraw() end)
  end

  -- Scrolling: clamp, and tappable arrows when there's more
  local maxScroll = math.max(0, (y - 1) - H + scroll[4])
  if scroll[4] > maxScroll then
    scroll[4] = maxScroll
    F.redraw()
  end
  F.scrollArrows(4, top, maxScroll, math.max(1, H - top))
end

---------------------------------------------------------------------------
-- Remote control (player side)
---------------------------------------------------------------------------
-- What remotes see. Sent every half second and after every command.
function X.broadcastState()
  if not wireless then return end
  local np = now_playing
  rednet.broadcast({
    type = "state", group = group, pin = pin,
    name = np and np.name, artist = np and np.artist,
    playing = playing and not paused, loading = is_loading, error = is_error,
    pos = np and F.elapsedBytes() / BYTES_PER_SEC or 0,
    total = total_bytes and total_bytes / BYTES_PER_SEC or nil,
    seekable = seekable, volume = volume, muted = muted,
    looping = looping, shuffle = X.shuffle, fav = np and F.isFavourite(np) or false,
    queue = #queue,
  }, PROTOCOL)
end

function X.remoteCommand(msg)
  local c, v = msg.cmd, tonumber(msg.value)
  if c == "toggle" then F.togglePause()
  elseif c == "next" then F.nextTrack()
  elseif c == "prev" then F.prevTrack()
  elseif c == "stop" then stop()
  elseif c == "restart" then restart()
  elseif c == "loop" then F.cycleLoop()
  elseif c == "shuffle" then X.toggleShuffle()
  elseif c == "fav" then F.toggleFavourite(now_playing)
  elseif c == "mute" then F.toggleMute()
  elseif c == "volume" and v then F.setVolume(v)
  elseif c == "seek" and v then F.seekSeconds(v)
  end
  F.redraw()
end

---------------------------------------------------------------------------
-- Remote control (the remote itself: "phoenixmusic remote")
---------------------------------------------------------------------------
function X.runRemote()
  local st, st_at, host = nil, -100, nil
  local want = nil                 -- "group" / "pin" once a button asks for typing
  local typing = false
  local suggest_player = is_pocket and #speakers > 0
  local seek_preview = nil        -- seconds, while dragging along the bar

  local function send(cmd, value)
    local m = { type = "cmd", group = group, pin = pin, cmd = cmd, value = value }
    if host then rednet.send(host, m, PROTOCOL) else rednet.broadcast(m, PROTOCOL) end
  end

  local function online() return st and os.clock() - st_at < 4 end

  local function draw()
    if typing then return end
    win.setVisible(false)
    hits = {}
    term.setCursorBlink(false)
    term.setBackgroundColour(C.bg)
    term.clear()
    F.fill(1, 1, W, 1, C.panel)
    -- Title bar: the name, or an update to tap; x goes back to the full player
    local u = X.upd
    local title, titleFn = G.note .. (W < 30 and " Music Remote" or (" " .. APP.name .. " Remote")), nil
    if u.state == "available" then
      title, titleFn = "Update to v" .. u.version .. " - tap", X.requestInstall
    elseif u.state == "installing" then
      title = "Updating..."
    elseif u.state == "installed" then
      title, titleFn = "Updated - tap to restart", function() X.switchMode({ "remote" }) end
    end
    text(2, 1, F.trunc(title, W - 5), C.accent, C.panel)
    if titleFn then F.addHit(1, 1, W - 4, 1, titleFn) end
    if not (is_pocket and #speakers == 0) then -- a speakerless pocket has nothing else to be
      F.button(W - 2, 1, " " .. G.close .. " ", C.muted, C.btn, function()
        if #speakers == 0 then
          settings.set("phoenix_music.nospeaker_mode", "player")
          settings.save()
        end
        X.switchMode({ "player" })
      end)
    end

    -- A Noisy Pocket can play music itself: offer the player instead
    if suggest_player then
      local lines = F.wrap("This pocket has a speaker, so it can play music itself.", W - 4)
      local y = 3
      for _, l in ipairs(lines) do text(3, y, l, C.text, C.bg); y = y + 1 end
      y = y + 1
      F.button(3, y, " Open the player ", C.bg, C.accent, function() X.switchMode({ "player" }) end)
      F.button(3, y + 2, " Stay as a remote ", C.text, C.btn, function() suggest_player = false end)
      win.setVisible(true)
      return
    end

    -- Bottom row: which Link, and buttons to change Link / PIN
    local pinLabel, groupLabel = " PIN ", " Link "
    text(2, H, F.trunc(group, W - #pinLabel - #groupLabel - 4), C.muted, C.bg)
    F.button(W - #pinLabel - #groupLabel, H, groupLabel, C.text, C.btn, function() want = "group" end)
    F.button(W - #pinLabel + 1, H, pinLabel, pin ~= "" and C.accent or C.text, C.btn, function() want = "pin" end)

    if not online() then
      local y = 3
      text(2, y, "Looking for a player...", C.muted, C.bg)
      y = y + 2
      for _, l in ipairs(F.wrap("Run " .. CMD .. " on the player with the same Speaker Link and PIN, and give both an ender modem.", W - 2)) do
        if y < H - 1 then text(2, y, l, C.muted, C.bg) end
        y = y + 1
      end
      win.setVisible(true)
      return
    end

    -- Status, song and favourite heart
    local status = st.error and "Network error" or st.loading and "Loading..."
      or (st.name and (st.playing and (G.note .. " Playing") or "Paused") or "Nothing playing")
    text(2, 3, F.trunc(status, W - 6), st.playing and C.accent or C.muted, C.bg)
    text(2, 4, F.trunc(st.name or "Pick something on the player", W - 6), C.text, C.bg)
    text(2, 5, F.trunc(st.artist or "", W - 6), C.muted, C.bg)
    if st.name then
      text(W - 3, 4, " " .. G.heart .. " ", st.fav and C.err or C.muted, C.btn)
      F.addHit(W - 3, 4, 3, 2, function() send("fav") end)
    end

    local compact = X.compact()
    local py = 7

    -- Progress (moves on between updates while playing)
    local cur = st.pos or 0
    if st.playing then cur = cur + (os.clock() - st_at) end
    if st.total then cur = math.min(cur, st.total) end
    if seek_preview then cur = seek_preview end
    local left, right = F.fmtTime(st.name and cur or nil), F.fmtTime(st.total)
    local bx, bw = 2 + #left + 1, W - 2 - #left - #right - 2
    text(2, py, left, C.muted, C.bg)
    text(W - #right, py, right, C.muted, C.bg)
    if bw >= 3 then
      F.fill(bx, py, bw, 1, C.btn)
      if st.total and st.total > 0 then
        local filled = math.floor(bw * math.min(1, cur / st.total) + 0.5)
        if filled > 0 then F.fill(bx, py, filled, 1, C.accent) end
      end
      if st.seekable and st.total then
        -- Sent once on release, not for every step of a drag
        F.addHit(bx, py, bw, 1, function(x) seek_preview = (x - bx) / math.max(1, bw - 1) * st.total end)
      end
    end

    -- Buttons (same icons as the player)
    local has = st.name ~= nil or (st.queue or 0) > 0
    local loopBtn
    if st.looping == 1 then loopBtn = { ICONS.loop, C.bg, C.accent, function() send("loop") end }
    elseif st.looping == 2 then loopBtn = { ICONS.loop_one, C.bg, C.ok, function() send("loop") end }
    else loopBtn = { ICONS.loop, C.muted, C.btn, function() send("loop") end } end
    local shuffleBtn = st.shuffle and { ICONS.shuffle, C.bg, C.accent, function() send("shuffle") end }
      or { ICONS.shuffle, C.muted, C.btn, function() send("shuffle") end }
    local restartBtn = { ICONS.restart, C.text, C.btn, function() send("restart") end, st.name ~= nil }
    local transport = {
      { ICONS.prev, C.text, C.btn, function() send("prev") end, has },
      { st.playing and ICONS.pause or ICONS.play, C.bg, C.accent, function() send("toggle") end, has },
      { ICONS.stop, C.text, C.btn, function() send("stop") end, has },
      { ICONS.next, C.text, C.btn, function() send("next") end, has },
    }
    local vy
    local by = 9
    if not compact then
      table.insert(transport, 1, restartBtn)
      table.insert(transport, 1, shuffleBtn)
      table.insert(transport, loopBtn)
      F.drawButtonRow(by, transport)
      vy = by + BTN_H + 1
    else
      F.drawButtonRow(by, transport)
      F.drawButtonRow(by + BTN_H + 1, { restartBtn, shuffleBtn, loopBtn })
      vy = by + 2 * (BTN_H + 1)
    end

    -- Volume
    if vy < H - 1 then
      local vol = st.volume or 0
      local pct = st.muted and "Mute" or (math.floor(100 * vol / VOLUME_MAX + 0.5) .. "%")
      pct = string.rep(" ", 4 - #pct) .. pct
      local x = 2
      x = x + F.button(x, vy, " - ", C.text, C.btn, function() send("volume", vol - VOLUME_STEP) end) + 1
      local vw = W - 2 - 3 - 1 - 3 - 1 - #pct - 1
      if vw >= 3 then
        local vx = x
        F.fill(vx, vy, vw, 1, C.btn)
        local filled = math.floor(vw * (st.muted and 0 or vol) / VOLUME_MAX + 0.5)
        if filled > 0 then F.fill(vx, vy, filled, 1, C.text) end
        F.addHit(vx, vy, vw, 1, function(cx) send("volume", (cx - vx + 1) / vw * VOLUME_MAX) end)
        x = x + vw + 1
      end
      x = x + F.button(x, vy, " + ", C.text, C.btn, function() send("volume", vol + VOLUME_STEP) end) + 1
      F.button(x, vy, pct, C.muted, C.bg, function() send("mute") end)
    end
    win.setVisible(true)
  end

  -- Typing a new group or PIN on the bottom line.
  local function ask(label, mask)
    typing = true
    term.setCursorPos(1, H)
    term.setBackgroundColour(C.panel)
    term.clearLine()
    term.setTextColour(C.text)
    term.write(" " .. label)
    local v = read(mask)
    typing = false
    return v
  end

  local function netR()
    rednet.broadcast({ type = "remote_hello", group = group, pin = pin }, PROTOCOL)
    while true do
      local id, msg = rednet.receive(PROTOCOL)
      if P.ok(msg, group, pin) and msg.type == "state" then
        st, st_at, host = msg, os.clock(), id
        os.queueEvent("remote_redraw")
      end
    end
  end

  local function tickR()
    while true do
      sleep(0.5)
      X.dueUpdateCheck()
      if not online() then
        host = nil
        rednet.broadcast({ type = "remote_hello", group = group, pin = pin }, PROTOCOL)
      end
      os.queueEvent("remote_redraw")
    end
  end

  local function uiR()
    draw()
    while true do
      if want then
        local what = want
        want = nil
        if what == "group" then
          local v = P.trim(ask("Link name (now " .. group .. "): ")):sub(1, 24)
          if v ~= "" then
            group, st, host = v, nil, nil
            settings.set("phoenix_music.group", group)
            settings.save()
          end
        else
          local v = P.trim(ask("PIN (blank for none): ", "*")):sub(1, 12)
          pin, st, host = v, nil, nil
          settings.set("phoenix_music.pin", pin)
          settings.save()
        end
        rednet.broadcast({ type = "remote_hello", group = group, pin = pin }, PROTOCOL)
        draw()
      end
      local ev, a, b, c = os.pullEvent()
      if ev == "mouse_click" or ev == "monitor_touch" then
        F.handleClick(b, c)
        draw()
      elseif ev == "mouse_drag" and c == 7 then
        F.handleClick(b, c)
        draw()
      elseif ev == "mouse_up" then
        if seek_preview then
          send("seek", seek_preview)
          seek_preview = nil
        end
      elseif ev == "char" then
        if a == "q" then return
        elseif online() then
          local vol = st.volume or 0
          if a == " " then send("toggle")
          elseif a == "n" then send("next")
          elseif a == "p" then send("prev")
          elseif a == "s" then send("stop")
          elseif a == "r" then send("restart")
          elseif a == "l" then send("loop")
          elseif a == "h" then send("shuffle")
          elseif a == "f" then send("fav")
          elseif a == "m" then send("mute")
          elseif a == "+" or a == "=" then send("volume", vol + VOLUME_STEP)
          elseif a == "-" or a == "_" then send("volume", vol - VOLUME_STEP)
          end
        end
      elseif ev == "remote_redraw" or ev == "redraw_screen" then
        draw()
      elseif ev == "phoenix_quit" then
        return
      elseif ev == "term_resize" then
        W, H = parent.getSize()
        win.reposition(1, 1, W, H)
        draw()
      end
    end
  end

  parallel.waitForAny(uiR, netR, tickR)
end

---------------------------------------------------------------------------
-- Run
---------------------------------------------------------------------------
pcall(X.applyTheme)
local ok, err
if remote_mode then
  ok, err = pcall(parallel.waitForAny, X.runRemote, X.updateLoop)
else
  pcall(F.loadState)
  pcall(F.loadLibrary)
  if ask_nospeaker and is_pocket then
    -- A pocket with no speaker can't play anything itself: it's a remote
    modal = {
      title = "No speaker in this pocket",
      sub = "Use it as a remote instead?",
      options = {
        { "Switch to the remote", function()
          settings.set("phoenix_music.nospeaker_mode", "remote")
          settings.save()
          X.switchMode({ "remote" })
        end },
      },
    }
  elseif ask_nospeaker then
    modal = {
      title = "No speaker on this computer",
      sub = "What should it do?",
      options = {
        { "Be a remote for a player", function()
          settings.set("phoenix_music.nospeaker_mode", "remote")
          settings.save()
          X.switchMode({ "remote" })
        end },
        { "Play through linked speakers", function()
          settings.set("phoenix_music.nospeaker_mode", "player")
          settings.save()
        end },
      },
    }
  end
  ok, err = pcall(parallel.waitForAny, F.uiLoop, F.audioLoop, F.httpLoop, F.netLoop, F.tickLoop,
    X.vizLoop, X.redstoneLoop, X.updateLoop)
  pcall(F.saveState)
  F.stopSpeakers()
  if player_handle then pcall(player_handle.close) end
end

term.redirect(old_term)
F.restorePalette()
parent.setBackgroundColour(colours.black)
parent.setTextColour(colours.white)
parent.clear()
parent.setCursorPos(1, 1)

if not ok and err ~= "Terminated" then
  printError(err)
end

-- Switching to the remote / a linked speaker, or restarting after an update
if X.switch_to then P.relaunch(X.switch_to) end
