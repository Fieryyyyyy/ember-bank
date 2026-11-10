-- =====================================================
--  EMBER HOME - the TV in your house: Music + The Farm
--  Needs: an advanced computer, an advanced monitor (the TV), and wired
--  modems connecting it to your disc chest, a disk drive (the record player) and your farm chests.
--  Install / update:
--    wget run https://raw.githubusercontent.com/Fieryyyyyy/ember-bank/main/install.lua home
-- =====================================================

local VERSION  = "1.1"
local HOME_URL = "https://raw.githubusercontent.com/Fieryyyyyy/ember-bank/main/home/home.lua"
local DB_FILE  = "home.db"

-- ---------- colours (the 16 slots are re-painted into a dark "streaming app" theme) ----------
local P = {
  bg = colors.black, panel = colors.gray, card = colors.lightGray, line = colors.brown,
  text = colors.white, sub = colors.cyan, accent = colors.green,
  loot = colors.orange, breed = colors.pink, red = colors.red, yellow = colors.yellow,
  blue = colors.blue, purple = colors.purple, sky = colors.lightBlue, lime = colors.lime, magenta = colors.magenta,
}
local PALETTE = {
  [colors.black] = 0x0E0E11, [colors.gray] = 0x18181D, [colors.lightGray] = 0x26262D, [colors.brown] = 0x3C3C46,
  [colors.white] = 0xF4F4F6, [colors.cyan] = 0x9C9CAA, [colors.green] = 0x1ED760,
  [colors.orange] = 0xFF9F43, [colors.pink] = 0xFF6FAE, [colors.red] = 0xF0524F, [colors.yellow] = 0xFFD24A,
  [colors.blue] = 0x4C8DFF, [colors.purple] = 0x9B6CFF, [colors.lightBlue] = 0x3DD6F5, [colors.lime] = 0x9BE15D,
  [colors.magenta] = 0xD46CFF,
}
local ART_COLS = { P.yellow, P.lime, P.loot, P.red, P.purple, P.magenta, P.blue, P.sky, P.breed, P.accent }

-- vanilla discs: title, artist, length (seconds), cover colour
local DISCS = {
  ["13"] = { "13", "C418", 178, P.yellow },        cat = { "cat", "C418", 185, P.lime },
  blocks = { "blocks", "C418", 345, P.loot },       chirp = { "chirp", "C418", 185, P.red },
  far = { "far", "C418", 174, P.lime },             mall = { "mall", "C418", 197, P.purple },
  mellohi = { "mellohi", "C418", 96, P.magenta },   stal = { "stal", "C418", 150, P.line },
  strad = { "strad", "C418", 188, P.text },         ward = { "ward", "C418", 251, P.accent },
  ["11"] = { "11", "C418", 71, P.line },            wait = { "wait", "C418", 238, P.sky },
  pigstep = { "Pigstep", "Lena Raine", 149, P.red }, otherside = { "otherside", "Lena Raine", 195, P.sky },
  ["5"] = { "5", "Samuel Aberg", 178, P.sky },      relic = { "Relic", "Aaron Cherof", 218, P.blue },
  creator = { "Creator", "Lena Raine", 176, P.yellow },
  creator_music_box = { "Creator (Music Box)", "Lena Raine", 73, P.yellow },
  precipice = { "Precipice", "Aaron Cherof", 299, P.loot },
  tears = { "Tears", "Amos Roddy", 175, P.sky },    lava_chicken = { "Lava Chicken", "Hyper Potions", 134, P.loot },
}

-- ---------- saved settings ----------
local db = { cfg = {}, groups = {}, chests = {}, nextGroup = 1, queue = {} }
local DEFAULTS = { uiScale = 0, musicChests = {}, drive = nil, shuffle = false, rep = "all", lens = {}, titles = {}, scanEvery = 10 }

local function loadDb()
  if fs.exists(DB_FILE) then
    local f = fs.open(DB_FILE, "r"); local t = textutils.unserialize(f.readAll() or ""); f.close()
    if type(t) == "table" then for k, v in pairs(t) do db[k] = v end end
  end
  for k, v in pairs(DEFAULTS) do if db.cfg[k] == nil then db.cfg[k] = v end end
  if db.cfg.musicChest then db.cfg.musicChests[db.cfg.musicChest] = true; db.cfg.musicChest = nil; db.cfg.musicPicked = true end   -- older versions had one
  db.groups = db.groups or {}; db.chests = db.chests or {}; db.queue = db.queue or {}
end
local function saveDb()
  local f = fs.open(DB_FILE .. ".tmp", "w"); f.write(textutils.serialize(db)); f.close()
  if fs.exists(DB_FILE) then fs.delete(DB_FILE) end
  fs.move(DB_FILE .. ".tmp", DB_FILE)
end

-- ---------- small helpers ----------
local function fmtTime(s) s = math.max(0, math.floor(s)) return string.format("%d:%02d", math.floor(s / 60), s % 60) end
local function fmtLong(s)
  local m = math.floor(s / 60)
  if m >= 60 then return string.format("%dh %02dm", math.floor(m / 60), m % 60) end
  return m .. " min"
end
local function fmtNum(n)
  n = math.floor(n)
  if n >= 100000 then return string.format("%.0fk", n / 1000) elseif n >= 10000 then return string.format("%.1fk", n / 1000) end
  local s = tostring(n)
  local r = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  if r:sub(1, 1) == "," then r = r:sub(2) end
  return r
end
local function fit(s, n)
  s = tostring(s or "")
  if n <= 0 then return "" end
  if #s <= n then return s end
  if n <= 2 then return s:sub(1, n) end
  return s:sub(1, n - 2) .. ".."
end
local function pretty(id)
  local s = (id:match(":(.+)$") or id):gsub("_", " ")
  return (s:gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
end
local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
local atan2 = math.atan2 or math.atan

-- ---------- devices ----------
local dev = { monitor = nil, drives = {}, invs = {} }
local function hasType(n, t)
  if peripheral.hasType then return peripheral.hasType(n, t) end
  for _, x in ipairs({ peripheral.getType(n) }) do if x == t then return true end end
  return false
end
local function scanDevices()
  local best, mon = 0, nil
  dev.drives, dev.invs = {}, {}
  for _, n in ipairs(peripheral.getNames()) do
    if hasType(n, "monitor") then
      local m = peripheral.wrap(n)
      if m.isColour and m.isColour() then
        m.setTextScale(0.5)
        local w, h = m.getSize()
        if w * h > best then best, mon = w * h, n end
      end
    elseif hasType(n, "drive") then dev.drives[#dev.drives + 1] = n
    elseif hasType(n, "inventory") then dev.invs[#dev.invs + 1] = n end
  end
  table.sort(dev.drives); table.sort(dev.invs)
  dev.monitor = mon
end

-- ---------- screen + frame buffer ----------
local out, W, H = term, 51, 19
local ui = { app = "home", musicView = "library", farmView = "overview", group = nil, chest = nil,
             scroll = 0, maxScroll = 0, lastKey = nil, kb = nil, menu = nil, confirm = nil,
             toast = nil, toastUntil = 0, scaleUsed = 0.5, tooBig = false, updateMsg = nil }
local HEX = {}
for i = 0, 15 do HEX[2 ^ i] = ("0123456789abcdef"):sub(i + 1, i + 1) end
local fb, hits, clip = {}, {}, nil

local function setupScreen()
  if dev.monitor then
    out = peripheral.wrap(dev.monitor)
    local want = db.cfg.uiScale or 0
    local pick = 0.5
    if want == 0 then
      for _, s in ipairs({ 2, 1.5, 1 }) do
        out.setTextScale(s)
        local w, h = out.getSize()
        if w >= 80 and h >= 30 then pick = s break end
      end
      ui.tooBig = false
    else
      pick = want
      out.setTextScale(pick)
      local w, h = out.getSize()
      ui.tooBig = false
      while (w < 39 or h < 19) and pick > 0.5 do
        pick = pick - 0.5; ui.tooBig = true
        out.setTextScale(pick); w, h = out.getSize()
      end
    end
    out.setTextScale(pick)
    ui.scaleUsed = pick
  else
    out = term.current()
  end
  if out.setPaletteColour then for c, hex in pairs(PALETTE) do out.setPaletteColour(c, hex) end end
  W, H = out.getSize()
end

local function put(x, y, ch, fg, bg)
  if x < 1 or y < 1 or x > W or y > H then return end
  if clip and (x < clip[1] or x > clip[3] or y < clip[2] or y > clip[4]) then return end
  local r = fb[y]
  r.c[x] = ch
  if fg then r.f[x] = HEX[fg] end
  if bg then r.b[x] = HEX[bg] end
end
local function fill(x, y, w, h, bg) for yy = y, y + h - 1 do for xx = x, x + w - 1 do put(xx, yy, " ", P.text, bg) end end end
local function text(x, y, s, fg, bg) s = tostring(s) for i = 1, #s do put(x + i - 1, y, s:sub(i, i), fg, bg) end end
local function center(x, w, y, s, fg, bg) s = fit(s, w) text(x + math.floor((w - #s) / 2), y, s, fg, bg) end
local function hit(x, y, w, h, fn)
  local x1, y1, x2, y2 = x, y, x + w - 1, y + h - 1
  if clip then x1, y1, x2, y2 = math.max(x1, clip[1]), math.max(y1, clip[2]), math.min(x2, clip[3]), math.min(y2, clip[4]) end
  if x2 < x1 or y2 < y1 then return end
  hits[#hits + 1] = { x1, y1, x2, y2, fn }
end
local function beginFrame()
  hits, clip = {}, nil
  for y = 1, H do
    local r = { c = {}, f = {}, b = {} }
    for x = 1, W do r.c[x] = " "; r.f[x] = HEX[P.text]; r.b[x] = HEX[P.bg] end
    fb[y] = r
  end
end
local function flush()
  for y = 1, H do
    local r = fb[y]
    out.setCursorPos(1, y)
    out.blit(table.concat(r.c), table.concat(r.f), table.concat(r.b))
  end
end

-- 2x3 "pixels" per character using the teletext characters 128-159
local BITS = { 1, 2, 4, 8, 16 }
local function pixels(x, y, w, h, pix)
  for cy = 0, h - 1 do
    for cx = 0, w - 1 do
      local p = {
        pix(cx * 2 + 1, cy * 3 + 1), pix(cx * 2 + 2, cy * 3 + 1),
        pix(cx * 2 + 1, cy * 3 + 2), pix(cx * 2 + 2, cy * 3 + 2),
        pix(cx * 2 + 1, cy * 3 + 3), pix(cx * 2 + 2, cy * 3 + 3),
      }
      local bgc = p[6]
      local cnt, fgc, best = {}, nil, 0
      for i = 1, 5 do
        local c = p[i]
        if c ~= bgc then
          cnt[c] = (cnt[c] or 0) + 1
          if cnt[c] > best then best, fgc = cnt[c], c end
        end
      end
      if not fgc then put(x + cx, y + cy, " ", P.text, bgc)
      else
        local n = 0
        for i = 1, 5 do if p[i] == fgc then n = n + BITS[i] end end
        put(x + cx, y + cy, string.char(128 + n), fgc, bgc)
      end
    end
  end
end

-- a vinyl record on a coloured sleeve. spin = angle of the light sheen (when playing)
local function art(x, y, w, h, d, spin)
  if w < 1 or h < 1 then return end
  local col = d and d.col or P.line
  local PW, PH = w * 2, h * 3
  local cx, cy = (PW + 1) / 2, (PH + 1) / 2
  local r = math.min(PW, PH) / 2 - 0.6
  pixels(x, y, w, h, function(px, py)
    local dx, dy = px - cx, py - cy
    local dd = math.sqrt(dx * dx + dy * dy)
    if dd > r then return col end
    local labelCol = (col == P.text or col == P.line) and P.sub or col
    if r < 5 then return dd <= r * 0.45 and labelCol or P.bg end      -- tiny: just a dot
    if dd <= math.max(0.6, r * 0.09) then return P.bg end
    if dd <= r * 0.34 then return labelCol end
    if spin and dd > r * 0.45 and dd < r * 0.9 then
      local a = atan2(dy, dx) - spin
      a = (a + math.pi) % (2 * math.pi) - math.pi
      if math.abs(a) < 0.12 then return P.line end
    end
    if r > 6 and (math.abs(dd - r * 0.62) < 0.5 or math.abs(dd - r * 0.8) < 0.5) then return P.panel end
    return P.bg
  end)
end

-- big 3x5 digits for the clock
local FONT = {
  ["0"] = "111101101101111", ["1"] = "010110010010111", ["2"] = "111001111100111", ["3"] = "111001111001111",
  ["4"] = "101101111001001", ["5"] = "111100111001111", ["6"] = "111100111101111", ["7"] = "111001001001001",
  ["8"] = "111101111101111", ["9"] = "111101111001111", [":"] = "000010000010000", [" "] = "000000000000000",
}
local function bigText(x, y, s, col, bg, scale)
  local gw = 4 * scale
  local pw = #s * gw - scale
  local w, h = math.ceil(pw / 2), math.ceil(5 * scale / 3)
  pixels(x, y, w, h, function(px, py)
    local gi = math.floor((px - 1) / gw) + 1
    local g = FONT[s:sub(gi, gi)] or FONT[" "]
    local gx = math.floor(((px - 1) % gw) / scale)
    local gy = math.floor((py - 1) / scale)
    if gx < 3 and gy < 5 and g:sub(gy * 3 + gx + 1, gy * 3 + gx + 1) == "1" then return col end
    return bg
  end)
  return w, h
end

-- progress bar with half-cell precision
local function bar(x, y, w, frac, col, back)
  frac = clamp(frac or 0, 0, 1)
  local halves = math.floor(frac * w * 2 + 0.5)
  for i = 0, w - 1 do
    local n = halves - i * 2
    if n >= 2 then put(x + i, y, " ", P.text, col)
    elseif n == 1 then put(x + i, y, string.char(149), col, back)
    else put(x + i, y, " ", P.text, back) end
  end
end

local function button(x, y, label, bg, fg, fn, w, h)
  w, h = w or (#label + 2), h or 1
  fill(x, y, w, h, bg)
  center(x, w, y + math.floor((h - 1) / 2), label, fg, bg)
  if fn then hit(x, y, w, h, fn) end
  return x + w
end

local redraw, go, toast   -- defined further down

-- ============================================================
--  MUSIC
-- ============================================================
local lib = { list = {}, byKey = {}, total = 0, chest = nil }
local player = { qi = 0, playing = false, paused = false, started = 0, cur = nil }

local function isDisc(name) return name:find("music_disc", 1, true) and not name:find("fragment", 1, true) end
local function discInfo(name)
  local ns, rest = name:match("^([^:]+):(.+)$")
  ns, rest = ns or "minecraft", rest or name
  local short = rest:match("^music_disc_(.+)$")
  local sound = short and (ns .. ":music_disc." .. short) or name
  short = short or rest
  local v = ns == "minecraft" and DISCS[short]
  if v then return { key = name, title = v[1], artist = v[2], len = db.cfg.lens[name] or v[3], col = v[4], sound = sound } end
  local hsh = 0
  for i = 1, #name do hsh = (hsh * 31 + name:byte(i)) % 997 end
  local title, artist = pretty(short), ns ~= "minecraft" and pretty(ns) or "Unknown artist"
  local known = db.cfg.titles[name]          -- "Artist - Title", read from the drive once it has played
  if known then
    local a, t = known:match("^(.-) %- (.+)$")
    if a then artist, title = a, t else title = known end
  end
  return { key = name, title = title, artist = artist,
           len = db.cfg.lens[name] or 180, col = ART_COLS[hsh % #ART_COLS + 1], sound = sound }
end

local function countDiscs(n)
  local p = peripheral.wrap(n)
  local ok, list = pcall(p.list)
  if not ok or type(list) ~= "table" then return 0 end
  local c = 0
  for _, it in pairs(list) do if isDisc(it.name) then c = c + 1 end end
  return c
end

local function isMusic(n) return db.cfg.musicChests[n] == true end
local function musicChests()
  local t = {}
  for _, n in ipairs(dev.invs) do if isMusic(n) then t[#t + 1] = n end end
  return t
end

local function scanLibrary()
  -- nothing chosen yet: use the chest with the most discs
  if next(db.cfg.musicChests) == nil and not db.cfg.musicPicked then
    local best, pick = 0, nil
    for _, n in ipairs(dev.invs) do
      local c = countDiscs(n)
      if c > best then best, pick = c, n end
    end
    if pick then db.cfg.musicChests[pick] = true; saveDb() end
  end
  lib.chests = musicChests()
  lib.chest = lib.chests[1]
  lib.perChest = {}
  local seen, list = {}, {}
  for _, chest in ipairs(lib.chests) do
    local ok, items = pcall(peripheral.wrap(chest).list)
    local n = 0
    if ok and type(items) == "table" then
      for _, it in pairs(items) do
        if isDisc(it.name) then
          n = n + it.count
          if seen[it.name] then seen[it.name].count = seen[it.name].count + it.count
          else
            local d = discInfo(it.name); d.count = it.count
            local old = lib.byKey[it.name]
            if old and old.bad then d.bad = true end
            seen[it.name] = d; list[#list + 1] = d
          end
        end
      end
    end
    lib.perChest[chest] = n
  end
  -- the disc that's in the drive right now still belongs to the library
  local dn = db.cfg.drive
  if not (dn and peripheral.isPresent(dn)) then dn = dev.drives[1] end
  if dn then
    local okL, inDrive = pcall(peripheral.wrap(dn).list)
    if okL and type(inDrive) == "table" then
      for _, it in pairs(inDrive) do
        if isDisc(it.name) and not seen[it.name] then
          local d = discInfo(it.name); d.count = 1; d.inDrive = true
          seen[it.name] = d; list[#list + 1] = d
        end
      end
    end
  end
  table.sort(list, function(a, b) return a.title:lower() < b.title:lower() end)
  lib.list, lib.byKey, lib.total = list, seen, 0
  for _, d in ipairs(list) do lib.total = lib.total + d.len end
end

-- ---------- the disc player: discs move from the chest into a disk drive and back ----------
local function drive()
  local n = db.cfg.drive
  if not (n and peripheral.isPresent(n)) then n = dev.drives[1] end
  return n, n and peripheral.wrap(n)
end
local function stopSound()
  local _, drv = drive()
  if drv then pcall(drv.stopAudio) end
end
-- put whatever is in the drive back in the music chest
local function returnDisc()
  local dn, drv = drive()
  if not drv then return true end
  pcall(drv.stopAudio)
  local okP, present = pcall(drv.isDiskPresent)
  if okP and not present then return true end
  -- back to the chest it came from, or else any music chest with room
  local order = {}
  if player.from and isMusic(player.from) then order[1] = player.from end
  for _, n in ipairs(musicChests()) do if n ~= player.from then order[#order + 1] = n end end
  for _, n in ipairs(order) do
    if peripheral.isPresent(n) then
      local ok, moved = pcall(peripheral.wrap(n).pullItems, dn, 1)
      if ok and moved and moved > 0 then return true end
    end
  end
  return false
end
local function current() return player.cur and (lib.byKey[player.cur] or discInfo(player.cur)) end
local function elapsed() return player.playing and (os.clock() - player.started) or 0 end

local function startDisc(d)
  local dn, drv = drive()
  if not drv then toast("No disk drive connected", P.red) return false end
  local chests = musicChests()
  if #chests == 0 then toast("No music chest connected", P.red) return false end
  if not returnDisc() then toast("The music chests are full - can't put the disc back", P.red) return false end
  local chest, slot, from
  for _, n in ipairs(chests) do
    local c = peripheral.wrap(n)
    local ok, items = pcall(c.list)
    if ok and type(items) == "table" then
      for s, it in pairs(items) do if it.name == d.key then slot = s break end end
    end
    if slot then chest, from = c, n break end
  end
  if not slot then toast(d.title .. " isn't in a music chest", P.red) return false end
  local okM, moved = pcall(chest.pushItems, dn, slot, 1)
  if okM and moved and moved > 0 then player.from = from end
  if not okM or not moved or moved < 1 then
    toast("Couldn't put the disc in the drive" .. (okM and "" or (": " .. tostring(moved))), P.red)
    return false
  end
  local okA, has = pcall(drv.hasAudio)
  if okA and not has then d.bad = true; toast("Can't play " .. d.title, P.red); returnDisc() return false end
  local okT, title = pcall(drv.getAudioTitle)
  if okT and type(title) == "string" and title ~= "" and not DISCS[(d.key:match("music_disc_(.+)$") or "")] then
    if db.cfg.titles[d.key] ~= title then
      db.cfg.titles[d.key] = title
      local nd = discInfo(d.key)
      d.title, d.artist = nd.title, nd.artist
    end
  end
  drv.playAudio()
  player.cur, player.playing, player.paused, player.started = d.key, true, false, os.clock()
  return true
end

local function shuffled(keys)
  for i = #keys, 2, -1 do local j = math.random(i); keys[i], keys[j] = keys[j], keys[i] end
  return keys
end
local function libKeys() local t = {} for _, d in ipairs(lib.list) do t[#t + 1] = d.key end return t end

-- play queue position qi, skipping discs that are gone or can't play
local function playAt(qi)
  local q = db.queue
  for _ = 1, #q do
    if qi < 1 or qi > #q then break end
    local d = lib.byKey[q[qi]]
    if d and not d.bad then
      player.qi = qi
      if startDisc(d) then saveDb() return true end
    end
    qi = qi + 1
  end
  player.playing = false
  return false
end

local function playDisc(key)
  local keys = libKeys()
  if db.cfg.shuffle then
    local rest = {}
    for _, k in ipairs(keys) do if k ~= key then rest[#rest + 1] = k end end
    keys = shuffled(rest); table.insert(keys, 1, key)
    db.queue = keys; playAt(1)
  else
    db.queue = keys
    for i, k in ipairs(keys) do if k == key then playAt(i) return end end
  end
end
local function shufflePlay()
  if #lib.list == 0 then toast("No discs in the music chest", P.red) return end
  db.cfg.shuffle = true
  db.queue = shuffled(libKeys()); playAt(1)
end
local function playInOrder()
  if #lib.list == 0 then toast("No discs in the music chest", P.red) return end
  db.cfg.shuffle = false
  db.queue = libKeys(); playAt(1)
end

local function nextTrack(auto)
  if auto and db.cfg.rep == "one" and player.cur and lib.byKey[player.cur] then
    if playAt(player.qi) then return end
  end
  local n = player.qi + 1
  if n > #db.queue then
    if db.cfg.rep == "off" and auto then player.playing = false; player.paused = false; returnDisc() return end
    if db.cfg.shuffle then db.queue = shuffled(libKeys()) end
    n = 1
  end
  if not playAt(n) then returnDisc() end
end
local function prevTrack()
  if elapsed() > 5 or player.qi <= 1 then playAt(math.max(1, player.qi)) return end
  playAt(player.qi - 1)
end
local function togglePlay()
  if player.playing then
    stopSound(); player.playing = false; player.paused = true
  elseif player.cur and lib.byKey[player.cur] and player.qi > 0 then
    if playAt(player.qi) then toast("Discs start again from the beginning", P.sub) end
  else
    shufflePlay()
  end
end
local function toggleShuffle()
  db.cfg.shuffle = not db.cfg.shuffle
  local q, out2 = db.queue, {}
  local curKey = q[player.qi]
  if db.cfg.shuffle then
    local rest = {}
    for i = player.qi + 1, #q do rest[#rest + 1] = q[i] end
    for i = 1, player.qi do out2[#out2 + 1] = q[i] end
    for _, k in ipairs(shuffled(rest)) do out2[#out2 + 1] = k end
    db.queue = out2
  else
    db.queue = libKeys()
    player.qi = 0
    for i, k in ipairs(db.queue) do if k == curKey then player.qi = i end end
  end
  saveDb()
end
local REP_NEXT = { all = "one", one = "off", off = "all" }
local function cycleRepeat() db.cfg.rep = REP_NEXT[db.cfg.rep] or "all"; saveDb() end

local function musicTick()
  local d = current()
  if player.playing and d and elapsed() >= d.len + 1 then nextTrack(true) end
end

-- ============================================================
--  THE FARM
-- ============================================================
local farm = { data = {}, hist = {}, scanned = false }
local itemInfo = {}   -- item id -> { label, max }

local function scanChest(n)
  local p = peripheral.wrap(n)
  if not p then return nil end
  local ok, list = pcall(p.list)
  if not ok or type(list) ~= "table" then return nil end
  local okS, size = pcall(p.size)
  size = (okS and size) or 27
  local agg, used, fillSum, total = {}, 0, 0, 0
  for slot, it in pairs(list) do
    local inf = itemInfo[it.name]
    if not inf then
      local okD, d = pcall(p.getItemDetail, slot)
      inf = { label = okD and d and d.displayName or pretty(it.name), max = okD and d and d.maxCount or 64 }
      itemInfo[it.name] = inf
    end
    used = used + 1; total = total + it.count
    fillSum = fillSum + it.count / math.max(1, inf.max)
    if not agg[it.name] then agg[it.name] = { name = it.name, label = inf.label, count = 0, stacks = 0 } end
    agg[it.name].count = agg[it.name].count + it.count
    agg[it.name].stacks = agg[it.name].stacks + 1
  end
  local items = {}
  for _, v in pairs(agg) do items[#items + 1] = v end
  table.sort(items, function(a, b) return a.count > b.count end)
  return { size = size, used = used, fill = size > 0 and fillSum / size or 0, total = total, items = items }
end

local function rateOf(n)
  local h = farm.hist[n]
  if not h or #h < 2 then return nil end
  local a, b = h[1], h[#h]
  if b.t - a.t < 120 then return nil end
  return (b.total - a.total) / (b.t - a.t) * 3600
end

local function scanFarm()
  local now = os.epoch("utc") / 1000
  for _, n in ipairs(dev.invs) do
    if not isMusic(n) then
      local d = scanChest(n)
      farm.data[n] = d
      if d then
        local h = farm.hist[n] or {}
        if #h > 0 and d.total < h[#h].total then h = {} end      -- emptied: start counting again
        h[#h + 1] = { t = now, total = d.total }
        while #h > 2 and now - h[1].t > 3600 do table.remove(h, 1) end
        farm.hist[n] = h
      end
    end
  end
  farm.scanned = true
end

local function chestLabel(n) local c = db.chests[n] return (c and c.label) or pretty(n) end
local function groupById(id) for _, g in ipairs(db.groups) do if g.id == id then return g end end end
local function chestsOf(id)
  local t = {}
  for _, n in ipairs(dev.invs) do
    local c = db.chests[n]
    if not isMusic(n) and c and c.group == id then t[#t + 1] = n end
  end
  return t
end
local function groupStats(id)
  local s = { size = 0, fillW = 0, total = 0, rate = nil, chests = 0, items = {} }
  local merged = {}
  for _, n in ipairs(chestsOf(id)) do
    s.chests = s.chests + 1
    local d = farm.data[n]
    if d then
      s.size = s.size + d.size; s.fillW = s.fillW + d.fill * d.size; s.total = s.total + d.total
      local r = rateOf(n)
      if r then s.rate = (s.rate or 0) + r end
      for _, it in ipairs(d.items) do
        if not merged[it.name] then merged[it.name] = { name = it.name, label = it.label, count = 0 }; s.items[#s.items + 1] = merged[it.name] end
        merged[it.name].count = merged[it.name].count + it.count
      end
    end
  end
  table.sort(s.items, function(a, b) return a.count > b.count end)
  s.fill = s.size > 0 and s.fillW / s.size or 0
  return s
end
local function fillCol(f) if f >= 0.9 then return P.red elseif f >= 0.7 then return P.yellow end return P.accent end
local function kindCol(k) return k == "breed" and P.breed or P.loot end
local function kindName(k) return k == "breed" and "BREEDING PEN" or "LOOT FARM" end
local function kindIcon(k) return k == "breed" and "\3" or "\4" end
local function unassigned()
  local t = {}
  for _, n in ipairs(dev.invs) do
    local c = db.chests[n]
    if not isMusic(n) and not (c and c.group and groupById(c.group)) then t[#t + 1] = n end
  end
  return t
end
local function alerts()
  local t = {}
  for _, g in ipairs(db.groups) do
    for _, n in ipairs(chestsOf(g.id)) do
      local d = farm.data[n]
      if d and d.fill >= 0.9 then t[#t + 1] = chestLabel(n) .. " in " .. g.name .. " is " .. math.floor(d.fill * 100) .. "% full" end
    end
  end
  return t
end

-- ============================================================
--  UI pieces
-- ============================================================
function toast(msg, col) ui.toast = { msg = msg, col = col or P.accent }; ui.toastUntil = os.clock() + 4 end
local function screenKey()
  return table.concat({ ui.app, ui.musicView, ui.farmView, tostring(ui.group), tostring(ui.chest) }, "/")
end
function go(app) ui.app = app; ui.menu = nil end

local function openKeyboard(title, value, onDone) ui.kb = { title = title, value = value or "", onDone = onDone, lower = false } end
local function openMenu(title, options) ui.menu = { title = title, options = options } end
local function askConfirm(msg, yes) ui.confirm = { text = msg, yes = yes } end

local function scrollbar(x, y, h)
  fill(x, y, 1, h, P.panel)
  text(x, y, "\30", P.text, P.line); text(x, y + h - 1, "\31", P.text, P.line)
  if h > 2 and ui.maxScroll > 0 then
    local th = math.max(1, math.floor((h - 2) * (h / (h + ui.maxScroll))))
    local ty = y + 1 + math.floor((h - 2 - th) * (ui.scroll / ui.maxScroll))
    fill(x, ty, 1, th, P.sub)
  end
  local page = math.max(1, h - 2)
  hits[#hits + 1] = { x - 1, y, x, y + math.floor(h / 2) - 1, function() ui.scroll = math.max(0, ui.scroll - page) end }
  hits[#hits + 1] = { x - 1, y + math.floor(h / 2), x, y + h - 1, function() ui.scroll = math.min(ui.maxScroll, ui.scroll + page) end }
end
-- draws content of height contentH into a scrolling box; drawFn(x, y0, w) where y0 is the content's top
local function scrollArea(x, y, w, h, contentH, drawFn)
  ui.maxScroll = math.max(0, contentH - h)
  ui.scroll = clamp(ui.scroll, 0, ui.maxScroll)
  local cw = w
  if ui.maxScroll > 0 then cw = w - 2 end
  clip = { x, y, x + cw - 1, y + h - 1 }
  drawFn(x, y - ui.scroll, cw)
  clip = nil
  if ui.maxScroll > 0 then scrollbar(x + w - 1, y, h) end
end

local function chip(x, y, label, bg, fg) text(x, y, " " .. label .. " ", fg or P.text, bg) return x + #label + 3 end

-- ---------- top bar ----------
local APPS = { { "home", "Home" }, { "music", "Music" }, { "farm", "The Farm" }, { "settings", "Settings" } }
local function greeting()
  local t = os.time()
  if t >= 5 and t < 12 then return "Good morning" elseif t >= 12 and t < 18 then return "Good afternoon" end
  return "Good evening"
end
local function drawTop()
  local th = H >= 24 and 3 or 1
  fill(1, 1, W, th, P.panel)
  local ty = th == 3 and 2 or 1
  local x = 3
  text(x, ty, "\4", P.accent, P.panel)
  if W >= 70 then text(x + 2, ty, "EMBER HOME", P.text, P.panel); x = x + 14 else x = x + 3 end
  local clock = textutils.formatTime(os.time(), true)
  local right = (W >= 60 and ("Day " .. os.day() .. "  ") or "") .. clock
  for _, a in ipairs(APPS) do
    local on = ui.app == a[1]
    local lab = a[2]
    if W < 60 and a[1] == "farm" then lab = "Farm" elseif W < 60 and a[1] == "settings" then lab = "\15" end
    lab = " " .. lab .. " "
    if x + #lab > W - #right - 1 then break end
    text(x, ty, lab, on and P.bg or P.sub, on and P.text or P.panel)
    hit(x, 1, #lab, th, function() go(a[1]); if a[1] == "farm" then ui.farmView = "overview" end end)
    x = x + #lab + 1
  end
  text(W - #right - 1, ty, right, P.sub, P.panel)
  return th
end

-- ---------- now playing bar ----------
local function drawPlayer()
  local y0 = H - 2
  fill(1, y0 - 1, W, 4, P.panel)
  local d = current()
  local playing = player.playing
  local spin = playing and (os.clock() * 1.5) or nil
  art(2, y0, 4, 3, d, spin)
  hit(1, y0, 6, 3, function() go("music"); ui.musicView = "now" end)
  local compact = W < 70
  local ctrlW = compact and 17 or 40
  local cx = compact and (W - ctrlW) or math.floor((W - ctrlW) / 2) + 1
  local leftW = cx - 9
  if d then
    text(7, y0, fit(d.title, leftW), playing and P.accent or P.text, P.panel)
    text(7, y0 + 1, fit(d.artist, leftW), P.sub, P.panel)
  else
    text(7, y0, fit("Nothing playing", leftW), P.text, P.panel)
    text(7, y0 + 1, fit(#lib.list .. " discs ready", leftW), P.sub, P.panel)
  end
  hit(7, y0, math.max(1, leftW), 2, function() go("music"); ui.musicView = "now" end)
  -- controls
  local x = cx
  if not compact then
    local sh = db.cfg.shuffle
    x = button(x, y0, "Shuffle", P.panel, sh and P.accent or P.sub, function() toggleShuffle() end, 9) + 1
  end
  x = button(x, y0, "|\17", P.panel, P.text, function() prevTrack() end, 4) + 1
  x = button(x, y0, playing and "||" or "\16", P.text, P.bg, function() togglePlay() end, 5) + 1
  x = button(x, y0, "\16|", P.panel, P.text, function() nextTrack(false) end, 4) + 1
  if not compact then
    local rl = db.cfg.rep == "one" and "Repeat 1" or "Repeat"
    button(x, y0, rl, P.panel, db.cfg.rep ~= "off" and P.accent or P.sub, function() cycleRepeat() end, 10)
  end
  -- progress
  local len = d and d.len or 0
  local el = math.min(elapsed(), len)
  local pw = compact and (W - 16) or ctrlW
  local px = compact and 8 or cx
  local a, b = fmtTime(el), fmtTime(len)
  text(px, y0 + 2, a, P.sub, P.panel)
  bar(px + #a + 1, y0 + 2, pw - #a - #b - 2, len > 0 and el / len or 0, P.text, P.line)
  text(px + pw - #b, y0 + 2, b, P.sub, P.panel)
  -- record player status
  if not compact and W >= 96 then
    local vx = W - 20
    local dn = drive()
    text(vx, y0, "Record player", P.sub, P.panel)
    text(vx, y0 + 1, fit(dn and (player.playing and "\14 playing" or "ready") or "no disk drive!", 18), dn and (player.playing and P.accent or P.text) or P.red, P.panel)
  end
end

-- ============================================================
--  SCREENS
-- ============================================================
local S = {}

-- ---------- home ----------
local function musicTile(x, y, w, h)
  fill(x, y, w, h, P.card)
  local d = current() or lib.list[1]
  local ah = h - 2
  local aw = math.floor(ah * 1.5)
  if aw > math.floor(w * 0.45) then aw = math.floor(w * 0.45); ah = math.floor(aw / 1.5) end
  local tx = x + 2
  if ah >= 3 then
    art(x + 2, y + 1, aw, ah, d, player.playing and os.clock() * 1.5 or nil)
    hit(x + 2, y + 1, aw, ah, function() go("music"); ui.musicView = "now" end)
    tx = x + aw + 4
  end
  local tw = x + w - tx - 1
  local ty = y + 1
  text(tx, ty, "MUSIC", P.sub, P.card); ty = ty + 2
  if player.cur and d then
    text(tx, ty, fit(player.playing and "Now playing" or "Paused", tw), P.accent, P.card); ty = ty + 1
    text(tx, ty, fit(d.title, tw), P.text, P.card); ty = ty + 1
    text(tx, ty, fit(d.artist, tw), P.sub, P.card); ty = ty + 2
  elseif #lib.list > 0 then
    text(tx, ty, fit("Your disc collection", tw), P.text, P.card); ty = ty + 1
    text(tx, ty, fit(#lib.list .. " discs  \7  " .. fmtLong(lib.total), tw), P.sub, P.card); ty = ty + 2
  else
    text(tx, ty, fit("No discs found", tw), P.text, P.card); ty = ty + 1
    text(tx, ty, fit("Fill the music chest", tw), P.sub, P.card); ty = ty + 2
  end
  local bh = (y + h - 1 - ty >= 4) and 3 or 1
  if ty + bh <= y + h - 1 then
    local bx = button(tx, ty, "\16 Shuffle play", P.accent, P.bg, function() shufflePlay() end, math.min(tw, 18), bh)
    if bx + 10 <= x + w - 1 then button(bx + 1, ty, "Library", P.line, P.text, function() go("music"); ui.musicView = "library" end, 9, bh) end
    ty = ty + bh + 2
  end
  -- up next
  if player.cur and ty + 1 <= y + h - 2 then
    text(tx, ty, "Up next", P.sub, P.card); ty = ty + 1
    for i = player.qi + 1, #db.queue do
      if ty > y + h - 2 then break end
      local nd = lib.byKey[db.queue[i]]
      if nd then
        put(tx, ty, " ", P.text, nd.col)
        text(tx + 2, ty, fit(nd.title, tw - 8), P.text, P.card)
        text(tx + tw - 5, ty, fmtTime(nd.len), P.sub, P.card)
        ty = ty + 1
      end
    end
  end
end

local function farmTile(x, y, w, h)
  fill(x, y, w, h, P.card)
  hit(x, y, w, h, function() go("farm"); ui.farmView = "overview" end)
  text(x + 2, y + 1, "THE FARM", P.sub, P.card)
  local al = alerts()
  local ty = y + 3
  local last = y + h - 2
  if #db.groups == 0 then
    text(x + 2, ty, fit("No farms set up yet", w - 4), P.text, P.card)
    text(x + 2, ty + 1, fit("Open The Farm \16 Manage", w - 4), P.sub, P.card)
    return
  end
  local roomy = (last - ty + 1) >= #db.groups * 3 + (#al > 0 and 2 or 0)
  for _, g in ipairs(db.groups) do
    if ty > last - (#al > 0 and 1 or 0) then break end
    local s = groupStats(g.id)
    text(x + 2, ty, kindIcon(g.kind), kindCol(g.kind), P.card)
    local bw = math.max(4, math.floor(w * 0.3))
    local nw = w - bw - 11
    text(x + 4, ty, fit(g.name, nw), P.text, P.card)
    bar(x + w - bw - 7, ty, bw, s.fill, fillCol(s.fill), P.line)
    text(x + w - 5, ty, string.format("%3d%%", math.floor(s.fill * 100)), fillCol(s.fill), P.card)
    ty = ty + 1
    if roomy then
      local info = fmtNum(s.total) .. " items" .. (s.rate and ("  \7  " .. (s.rate >= 0 and "+" or "") .. fmtNum(s.rate) .. "/h") or "")
        .. (s.items[1] and ("  \7  most: " .. s.items[1].label) or "")
      text(x + 4, ty, fit(info, w - 6), P.sub, P.card)
      ty = ty + 2
    end
  end
  if #al > 0 and ty <= last then
    text(x + 2, last, fit("! " .. al[1] .. (#al > 1 and (" (+" .. (#al - 1) .. ")") or ""), w - 4), P.red, P.card)
  end
end

S.home = function(y1, y2)
  local h = y2 - y1 + 1
  local x = 3
  local hh
  if h >= 16 then
    local scale = (W >= 90 and h >= 28) and 2 or 1
    local cw, ch = bigText(x, y1 + 1, textutils.formatTime(os.time(), true), P.text, P.bg, scale)
    local gx = x + cw + 4
    local al = #alerts()
    local s = player.playing and ("\14 " .. (current() and current().title or "")) or (#lib.list .. " discs ready")
    local warn = al > 0 and ("! " .. al .. " chest" .. (al == 1 and "" or "s") .. " nearly full") or ""
    local sy = ch >= 3 and y1 + 3 or y1 + 2
    if ch >= 3 then
      text(gx, y1 + 1, greeting(), P.text, P.bg)
      text(gx, y1 + 2, "Day " .. os.day(), P.sub, P.bg)
    else
      text(gx, y1 + 1, fit(greeting() .. "  \7  Day " .. os.day(), W - gx), P.text, P.bg)
    end
    s = fit(s, W - gx)
    text(gx, sy, s, P.sub, P.bg)
    if warn ~= "" then text(gx + #s + 3, sy, fit(warn, W - gx - #s - 3), P.red, P.bg) end
    hh = ch + 2
  else
    text(x, y1 + 1, greeting(), P.text, P.bg)
    hh = 3
  end
  local ty, th = y1 + hh, y2 - y1 - hh
  if th < 4 then return end
  if W >= 70 then
    local mw = math.floor((W - 5) * 0.55)
    musicTile(3, ty, mw, th)
    farmTile(4 + mw, ty, W - 5 - mw - 1 + 1, th)
  else
    local h1 = math.floor(th / 2)
    musicTile(3, ty, W - 4, h1)
    farmTile(3, ty + h1 + 1, W - 4, th - h1 - 1)
  end
end

-- ---------- music ----------
local function discCard(x, y, w, d, artH)
  local playing = player.cur == d.key
  art(x, y, w, artH, d, (playing and player.playing) and os.clock() * 1.5 or nil)
  text(x, y + artH, fit((playing and "\14 " or "") .. d.title, w), playing and P.accent or (d.bad and P.red or P.text), P.bg)
  text(x, y + artH + 1, fit(d.artist .. "  " .. fmtTime(d.len), w), P.sub, P.bg)
  hit(x, y, w, artH + 2, function() playDisc(d.key) end)
end

local function musicLibrary(x, y1, w, y2)
  text(x + 1, y1, "Your Discs", P.text, P.bg)
  text(x + 13, y1, fit(#lib.list .. " discs  \7  " .. fmtLong(lib.total), w - 14), P.sub, P.bg)
  if #lib.list == 0 then
    text(x + 1, y1 + 2, fit("No music discs found.", w - 2), P.text, P.bg)
    text(x + 1, y1 + 3, fit(lib.chest and ("Put discs in: " .. chestLabel(lib.chest)) or "Connect a chest of discs with a wired modem, then pick it in Settings.", w - 2), P.sub, P.bg)
    return
  end
  local aw = w - 2
  local cols = math.max(1, math.floor((aw + 2) / 18))
  local cw = math.floor((aw + 2) / cols) - 2
  local ah = math.max(2, math.floor(cw * 2 / 3 + 0.5))
  local rowH = ah + 3
  local rows = math.ceil(#lib.list / cols)
  scrollArea(x + 1, y1 + 2, w - 1, y2 - y1 - 1, rows * rowH - 1, function(cx, cy, cwid)
    local cw2 = math.floor((cwid + 2) / cols) - 2
    for i, d in ipairs(lib.list) do
      local r, c = math.floor((i - 1) / cols), (i - 1) % cols
      discCard(cx + c * (cw2 + 2), cy + r * rowH, cw2, d, ah)
    end
  end)
end

local function musicQueue(x, y1, w, y2)
  text(x + 1, y1, "Queue", P.text, P.bg)
  text(x + 8, y1, fit((db.cfg.shuffle and "shuffled" or "in order") .. "  \7  " .. #db.queue .. " songs", w - 26), P.sub, P.bg)
  if #db.queue > 0 then button(x + w - 9, y1, "Clear", P.line, P.text, function() db.queue = {}; player.qi = 0; saveDb() end, 7) end
  if #db.queue == 0 then
    text(x + 1, y1 + 2, fit("The queue is empty - tap a disc or Shuffle play.", w - 2), P.sub, P.bg)
    return
  end
  scrollArea(x + 1, y1 + 2, w - 1, y2 - y1 - 1, #db.queue, function(cx, cy, cw)
    for i, k in ipairs(db.queue) do
      local d = lib.byKey[k] or discInfo(k)
      local yy = cy + i - 1
      local on = i == player.qi
      local bgc = on and P.card or P.bg
      fill(cx, yy, cw, 1, bgc)
      text(cx + 1, yy, on and "\14" or string.format("%2d", i), on and P.accent or P.sub, bgc)
      put(cx + 4, yy, " ", P.text, d.col)
      local tw = math.max(4, cw - 32)
      text(cx + 6, yy, fit(d.title, tw), on and P.accent or (lib.byKey[k] and P.text or P.sub), bgc)
      if cw >= 40 then text(cx + 7 + tw, yy, fit(d.artist, 14), P.sub, bgc) end
      text(cx + cw - 9, yy, fmtTime(d.len), P.sub, bgc)
      text(cx + cw - 2, yy, "x", P.red, bgc)
      hit(cx, yy, cw - 4, 1, function() playAt(i) end)
      hit(cx + cw - 4, yy, 4, 1, function()
        table.remove(db.queue, i)
        if i < player.qi then player.qi = player.qi - 1 elseif i == player.qi then returnDisc(); player.playing = false; player.qi = player.qi - 1 end
        saveDb()
      end)
    end
  end)
end

local function musicNow(x, y1, w, y2)
  local h = y2 - y1 + 1
  local d = current() or lib.list[1]
  local ah = h - 2
  local aw = math.floor(ah * 1.5)
  if aw > math.floor(w * 0.5) then aw = math.floor(w * 0.5); ah = math.floor(aw / 1.5) end
  local ax = x + 2
  local ay = y1 + math.floor((h - ah) / 2)
  local tx, tw = x + 2, w - 4
  if aw >= 6 and w >= 50 then
    art(ax, ay, aw, ah, d, player.playing and os.clock() * 1.5 or nil)
    tx = ax + aw + 3; tw = x + w - tx - 2
  end
  local ty = y1 + math.max(1, math.floor(h / 2) - 7)
  text(tx, ty, player.playing and "NOW PLAYING" or (player.cur and "PAUSED" or "READY TO PLAY"), player.playing and P.accent or P.sub, P.bg)
  ty = ty + 2
  if d then
    text(tx, ty, fit(d.title, tw), P.text, P.bg); ty = ty + 1
    text(tx, ty, fit(d.artist, tw), P.sub, P.bg); ty = ty + 2
  else
    text(tx, ty, fit("No discs in the music chest", tw), P.text, P.bg); ty = ty + 3
  end
  -- big progress bar
  local len = (player.cur and d) and d.len or 0
  local el = math.min(elapsed(), len)
  bar(tx, ty, tw, len > 0 and el / len or 0, P.accent, P.line); ty = ty + 1
  text(tx, ty, fmtTime(el), P.sub, P.bg)
  text(tx + tw - #fmtTime(len), ty, fmtTime(len), P.sub, P.bg); ty = ty + 2
  -- big controls: one row if it fits, otherwise shuffle/repeat go on a row underneath
  local bh = (y2 - ty >= 9) and 3 or 1
  local sh, on = db.cfg.shuffle, db.cfg.rep ~= "off"
  local oneRow = tw >= 45
  local bx = tx
  local function toggles(x0, y0, hh)
    x0 = button(x0, y0, "Shuffle", sh and P.accent or P.card, sh and P.bg or P.text, function() toggleShuffle() end, 9, hh) + 1
    return button(x0, y0, db.cfg.rep == "one" and "Repeat 1" or "Repeat", on and P.accent or P.card, on and P.bg or P.text, function() cycleRepeat() end, 10, hh) + 1
  end
  if oneRow then bx = toggles(bx, ty, bh) end
  bx = button(bx, ty, "|\17\17", P.card, P.text, function() prevTrack() end, 6, bh) + 1
  bx = button(bx, ty, player.playing and "||" or "\16", P.text, P.bg, function() togglePlay() end, 8, bh) + 1
  button(bx, ty, "\16\16|", P.card, P.text, function() nextTrack(false) end, 6, bh)
  ty = ty + bh + 1
  if not oneRow then toggles(tx, ty, 1); ty = ty + 2 end
  -- up next
  if ty + 1 <= y2 then
    text(tx, ty, "Up next", P.sub, P.bg); ty = ty + 1
    for i = player.qi + 1, #db.queue do
      if ty > y2 then break end
      local nd = lib.byKey[db.queue[i]]
      if nd then
        put(tx, ty, " ", P.text, nd.col)
        text(tx + 2, ty, fit(nd.title .. "  \7 " .. nd.artist, tw - 8), P.text, P.bg)
        text(tx + tw - 5, ty, fmtTime(nd.len), P.sub, P.bg)
        local qi = i
        hit(tx, ty, tw, 1, function() playAt(qi) end)
        ty = ty + 1
      end
    end
  end
end

S.music = function(y1, y2)
  local views = { { "now", "\16 Now playing" }, { "library", "\14 Library" }, { "queue", "\26 Queue" } }
  local mx, mw = 1, W
  if W >= 70 then
    local sw = 22
    fill(1, y1, sw, y2 - y1 + 1, P.panel)
    local yy = y1 + 1
    for _, v in ipairs(views) do
      local on = ui.musicView == v[1]
      fill(2, yy, sw - 2, 1, on and P.card or P.panel)
      text(3, yy, v[2], on and P.text or P.sub, on and P.card or P.panel)
      hit(1, yy, sw, 1, function() ui.musicView = v[1] end)
      yy = yy + 2
    end
    yy = yy + 1
    local bh = (y2 - yy >= 10) and 3 or 1
    button(3, yy, "\16 Shuffle play", P.accent, P.bg, function() shufflePlay() end, sw - 4, bh); yy = yy + bh + 1
    button(3, yy, "Play in order", P.line, P.text, function() playInOrder() end, sw - 4, bh); yy = yy + bh + 2
    if yy + 1 <= y2 then
      text(3, yy, #lib.list .. " discs", P.text, P.panel)
      text(3, yy + 1, fmtLong(lib.total) .. " of music", P.sub, P.panel)
    end
    mx, mw = sw + 2, W - sw - 2
  else
    local x = 2
    for _, v in ipairs(views) do
      local on = ui.musicView == v[1]
      local lab = " " .. (v[1] == "now" and "Playing" or v[2]:sub(3)) .. " "
      text(x, y1, lab, on and P.bg or P.sub, on and P.text or P.panel)
      hit(x, y1, #lab, 1, function() ui.musicView = v[1] end)
      x = x + #lab + 1
    end
    if x + 9 <= W then button(x, y1, "Shuffle", P.accent, P.bg, function() shufflePlay() end, 9) end
    y1 = y1 + 2
    mx, mw = 1, W
  end
  if ui.musicView == "now" then musicNow(mx, y1, mw, y2)
  elseif ui.musicView == "queue" then musicQueue(mx, y1 + 1, mw, y2)
  else musicLibrary(mx, y1 + 1, mw, y2) end
end

-- ---------- the farm ----------
local function farmHeader(y, title, back)
  local x = 2
  if back then x = button(2, y, "\17 Back", P.card, P.text, back, 8) + 2 end
  text(x, y, fit(title, W - x - 12), P.text, P.bg)
  return x
end

local function groupCard(x, y, w, h, g)
  local s = groupStats(g.id)
  fill(x, y, w, h, P.card)
  fill(x, y, 1, h, kindCol(g.kind))
  hit(x, y, w, h, function() ui.farmView = "group"; ui.group = g.id end)
  text(x + 2, y + 1, fit(g.name, w - 4), P.text, P.card)
  text(x + 2, y + 2, fit(kindIcon(g.kind) .. " " .. kindName(g.kind) .. "  \7  " .. s.chests .. " chest" .. (s.chests == 1 and "" or "s"), w - 4), kindCol(g.kind), P.card)
  bar(x + 2, y + 4, w - 9, s.fill, fillCol(s.fill), P.line)
  text(x + w - 6, y + 4, string.format("%3d%%", math.floor(s.fill * 100)), fillCol(s.fill), P.card)
  local info = fmtNum(s.total) .. " items" .. (s.rate and ("  \7  " .. (s.rate >= 0 and "+" or "") .. fmtNum(s.rate) .. "/h") or "")
  text(x + 2, y + 5, fit(info, w - 4), P.sub, P.card)
  local yy = y + 7
  for i = 1, math.min(#s.items, h - 8) do
    local it = s.items[i]
    local n = fmtNum(it.count)
    text(x + 2, yy, fit(it.label, w - #n - 5), P.text, P.card)
    text(x + w - #n - 2, yy, n, P.sub, P.card)
    yy = yy + 1
  end
  if #s.items == 0 then text(x + 2, yy, fit(s.chests == 0 and "No chests yet - use Manage" or "Empty", w - 4), P.sub, P.card) end
end

local function farmOverview(y1, y2)
  text(2, y1, "The Farm", P.text, P.bg)
  local x = 12
  local tot = { chests = 0, size = 0, fillW = 0 }
  for _, g in ipairs(db.groups) do
    local s = groupStats(g.id)
    tot.chests = tot.chests + s.chests; tot.size = tot.size + s.size; tot.fillW = tot.fillW + s.fillW
  end
  if W >= 60 then
    x = chip(x, y1, #db.groups .. " farms", P.panel, P.sub)
    x = chip(x, y1, tot.chests .. " chests", P.panel, P.sub)
    if tot.size > 0 then chip(x, y1, math.floor(tot.fillW / tot.size * 100) .. "% full", P.panel, P.sub) end
  end
  button(W - 9, y1, "Manage", P.line, P.text, function() ui.farmView = "manage" end, 8)
  local un = #unassigned()
  local top = y1 + 2
  if un > 0 then
    text(2, top, fit(un .. " connected chest" .. (un == 1 and " isn't" or "s aren't") .. " in a farm yet - tap Manage to add " .. (un == 1 and "it" or "them") .. ".", W - 3), P.yellow, P.bg)
    top = top + 2
  end
  if #db.groups == 0 then
    text(2, top, fit("Group your chests into farms: tap Manage, then + New farm.", W - 3), P.sub, P.bg)
    return
  end
  if not farm.scanned then text(2, top, "Reading chests...", P.sub, P.bg) return end
  local cols = math.max(1, math.floor((W - 2) / 32))
  local cw = math.floor((W - 2 - (cols - 1) * 2) / cols)
  local ch = 12
  local rows = math.ceil(#db.groups / cols)
  scrollArea(2, top, W - 2, y2 - top + 1, rows * (ch + 1) - 1, function(cx, cy, w)
    local cw2 = math.floor((w - (cols - 1) * 2) / cols)
    for i, g in ipairs(db.groups) do
      local r, c = math.floor((i - 1) / cols), (i - 1) % cols
      groupCard(cx + c * (cw2 + 2), cy + r * (ch + 1), cw2, ch, g)
    end
  end)
end

local function farmGroup(y1, y2)
  local g = groupById(ui.group)
  if not g then ui.farmView = "overview" return farmOverview(y1, y2) end
  local x = farmHeader(y1, g.name, function() ui.farmView = "overview" end)
  local s = groupStats(g.id)
  local kx = x + math.min(#g.name, W - x - 12) + 2
  if kx + 16 < W then text(kx, y1, " " .. kindIcon(g.kind) .. " " .. kindName(g.kind) .. " ", P.bg, kindCol(g.kind)) end
  bar(2, y1 + 2, W - 9, s.fill, fillCol(s.fill), P.line)
  text(W - 6, y1 + 2, string.format("%3d%%", math.floor(s.fill * 100)), fillCol(s.fill), P.bg)
  text(2, y1 + 3, fit(fmtNum(s.total) .. " items" .. (s.rate and ("  \7  " .. (s.rate >= 0 and "+" or "") .. fmtNum(s.rate) .. " per hour") or "") .. "  \7  " .. s.chests .. " chests", W - 3), P.sub, P.bg)
  local list = chestsOf(g.id)
  if #list == 0 then text(2, y1 + 5, "No chests in this farm. Add some in Manage.", P.sub, P.bg) return end
  scrollArea(2, y1 + 5, W - 2, y2 - y1 - 4, #list * 4 - 1, function(cx, cy, w)
    for i, n in ipairs(list) do
      local d = farm.data[n]
      local yy = cy + (i - 1) * 4
      fill(cx, yy, w, 3, P.card)
      hit(cx, yy, w, 3, function() ui.farmView = "chest"; ui.chest = n end)
      text(cx + 1, yy, fit(chestLabel(n), w - 22), P.text, P.card)
      if d then
        local info = d.used .. "/" .. d.size .. " slots"
        text(cx + w - #info - 1, yy, info, P.sub, P.card)
        bar(cx + 1, yy + 1, w - 8, d.fill, fillCol(d.fill), P.line)
        text(cx + w - 6, yy + 1, string.format("%3d%%", math.floor(d.fill * 100)), fillCol(d.fill), P.card)
        local parts = {}
        for j = 1, math.min(3, #d.items) do parts[#parts + 1] = d.items[j].label .. " " .. fmtNum(d.items[j].count) end
        text(cx + 1, yy + 2, fit(#parts > 0 and table.concat(parts, "  \7  ") or "Empty", w - 2), P.sub, P.card)
      else
        text(cx + 1, yy + 1, "Can't read this chest - is it still connected?", P.red, P.card)
      end
    end
  end)
end

local function farmChest(y1, y2)
  local n = ui.chest
  local d = farm.data[n]
  farmHeader(y1, chestLabel(n), function() ui.farmView = groupById(db.chests[n] and db.chests[n].group) and "group" or "manage" end)
  if not d then text(2, y1 + 2, "Can't read this chest.", P.red, P.bg) return end
  bar(2, y1 + 2, W - 9, d.fill, fillCol(d.fill), P.line)
  text(W - 6, y1 + 2, string.format("%3d%%", math.floor(d.fill * 100)), fillCol(d.fill), P.bg)
  local r = rateOf(n)
  text(2, y1 + 3, fit(d.used .. "/" .. d.size .. " slots used  \7  " .. fmtNum(d.total) .. " items" .. (r and ("  \7  " .. (r >= 0 and "+" or "") .. fmtNum(r) .. " per hour") or ""), W - 3), P.sub, P.bg)
  if #d.items == 0 then text(2, y1 + 5, "This chest is empty.", P.sub, P.bg) return end
  local cols = W >= 90 and 2 or 1
  local rows = math.ceil(#d.items / cols)
  local maxC = d.items[1].count
  scrollArea(2, y1 + 5, W - 2, y2 - y1 - 4, rows, function(cx, cy, w)
    local cw = math.floor((w - (cols - 1) * 3) / cols)
    for i, it in ipairs(d.items) do
      local rr, c = math.floor((i - 1) / cols), (i - 1) % cols
      local xx, yy = cx + c * (cw + 3), cy + rr
      local bgc = (rr % 2 == 0) and P.panel or P.bg
      fill(xx, yy, cw, 1, bgc)
      local num = fmtNum(it.count)
      local bw = math.max(0, math.min(12, cw - 30))
      text(xx + 1, yy, fit(it.label, cw - #num - bw - 12), P.text, bgc)
      if bw > 0 then bar(xx + cw - bw - #num - 10, yy, bw, it.count / maxC, P.sky, bgc) end
      text(xx + cw - #num - 8, yy, num, P.text, bgc)
      text(xx + cw - 7, yy, fit(it.stacks .. " stk", 6), P.sub, bgc)
    end
  end)
end

local function farmManage(y1, y2)
  farmHeader(y1, "Manage farms", function() ui.farmView = "overview" end)
  local rows = {}   -- each: { h = height, draw = function(x, y, w) }
  local function heading(t) rows[#rows + 1] = { h = 2, draw = function(x, y) text(x, y, t, P.sub, P.bg) end } end
  heading("FARMS")
  local wide = W - 4 >= 76
  for _, g in ipairs(db.groups) do
    rows[#rows + 1] = { h = wide and 2 or 3, draw = function(x, y, w)
      fill(x, y, w, wide and 1 or 2, P.card)
      fill(x, y, 1, wide and 1 or 2, kindCol(g.kind))
      local n = #chestsOf(g.id)
      local cs = n .. " chest" .. (n == 1 and "" or "s")
      local bx, by = x + w - 45, y
      if wide then
        text(x + 2, y, fit(g.name, w - 57), P.text, P.card)
        text(bx - 10, y, fit(cs, 9), P.sub, P.card)
      else
        text(x + 2, y, fit(g.name, w - 14), P.text, P.card)
        text(x + w - #cs - 1, y, cs, P.sub, P.card)
        bx, by = x + 2, y + 1
      end
      local kl = wide and (g.kind == "breed" and " Breeding pen" or " Loot farm") or (g.kind == "breed" and " Breed" or " Loot")
      bx = button(bx, by, kindIcon(g.kind) .. kl, kindCol(g.kind), P.bg, function()
        g.kind = g.kind == "breed" and "loot" or "breed"; saveDb()
      end, wide and 16 or 8) + 1
      bx = button(bx, by, "Rename", P.line, P.text, function()
        openKeyboard("Rename farm", g.name, function(v) if v ~= "" then g.name = v; saveDb() end end)
      end, 8) + 1
      bx = button(bx, by, "Open", P.line, P.text, function() ui.farmView = "group"; ui.group = g.id end, 6) + 1
      button(bx, by, wide and "Delete" or "Del", P.red, P.text, function()
        askConfirm("Delete the farm '" .. g.name .. "'? Its chests just become unassigned.", function()
          for i, gg in ipairs(db.groups) do if gg.id == g.id then table.remove(db.groups, i) break end end
          for _, c in pairs(db.chests) do if c.group == g.id then c.group = nil end end
          saveDb()
        end)
      end, wide and 8 or 5)
    end }
  end
  rows[#rows + 1] = { h = 3, draw = function(x, y)
    button(x, y, "+ New farm", P.accent, P.bg, function()
      openKeyboard("Name the new farm", "", function(v)
        if v == "" then return end
        local id = db.nextGroup; db.nextGroup = id + 1
        db.groups[#db.groups + 1] = { id = id, name = v, kind = "loot" }
        saveDb(); toast("Farm added - now put chests in it", P.accent)
      end)
    end, 14)
  end }
  heading("CHESTS")
  if #dev.invs == 0 then rows[#rows + 1] = { h = 1, draw = function(x, y) text(x, y, "No chests connected. Put a wired modem on each chest and turn it on.", P.sub, P.bg) end } end
  local ordered = musicChests()
  for _, n in ipairs(dev.invs) do if not isMusic(n) then ordered[#ordered + 1] = n end end
  for _, n in ipairs(ordered) do
    rows[#rows + 1] = { h = (wide or isMusic(n)) and 3 or 4, draw = function(x, y, w)
      fill(x, y, w, (wide or isMusic(n)) and 2 or 3, P.card)
      if isMusic(n) then
        text(x + 1, y, fit(chestLabel(n), w - 22), P.text, P.card)
        text(x + 1, y + 1, fit("\14 Music chest - " .. ((lib.perChest or {})[n] or 0) .. " discs", w - 22), P.accent, P.card)
        button(x + w - 20, y, "Not music", P.line, P.text, function()
          askConfirm("Stop using " .. chestLabel(n) .. " for music? Its discs leave the library.", function()
            db.cfg.musicChests[n] = nil; db.cfg.musicPicked = true; saveDb(); scanLibrary()
          end)
        end, 11, 2)
        button(x + w - 8, y, "Name", P.line, P.text, function()
          openKeyboard("Name this chest", (db.chests[n] or {}).label or "", function(v)
            db.chests[n] = db.chests[n] or {}; db.chests[n].label = v ~= "" and v or nil; saveDb()
          end)
        end, 7, 2)
        return
      end
      local c = db.chests[n] or {}
      local g = groupById(c.group)
      local d = farm.data[n]
      local tw = wide and (w - 46) or (w - 2)
      text(x + 1, y, fit(chestLabel(n), tw), P.text, P.card)
      local info = d and (d.size .. " slots  \7  " .. (d.items[1] and (d.items[1].label .. (#d.items > 1 and (" +" .. (#d.items - 1) .. " more") or "")) or "empty")) or "..."
      text(x + 1, y + 1, fit((c.label and (pretty(n) .. "  \7  ") or "") .. info, tw), P.sub, P.card)
      local bx, by, bh, fw = x + w - 44, y, 2, 20
      if not wide then bx, by, bh, fw = x + 1, y + 2, 1, 13 end
      bx = button(bx, by, fit(g and (kindIcon(g.kind) .. " " .. g.name) or "+ Add to farm", fw - 2), g and kindCol(g.kind) or P.accent, P.bg, function()
        local opts = {}
        for _, gg in ipairs(db.groups) do
          opts[#opts + 1] = { label = kindIcon(gg.kind) .. " " .. gg.name, col = kindCol(gg.kind), fn = function()
            db.chests[n] = db.chests[n] or {}; db.chests[n].group = gg.id; saveDb() end }
        end
        if g then opts[#opts + 1] = { label = "Remove from farm", col = P.red, fn = function() db.chests[n].group = nil; saveDb() end } end
        if #opts == 0 then toast("Make a farm first: + New farm", P.yellow) return end
        openMenu("Which farm is " .. chestLabel(n) .. " in?", opts)
      end, fw, bh) + 1
      bx = button(bx, by, wide and "Rename" or "Name", P.line, P.text, function()
        openKeyboard("Name this chest", c.label or "", function(v)
          db.chests[n] = db.chests[n] or {}; db.chests[n].label = v ~= "" and v or nil; saveDb()
        end)
      end, wide and 8 or 6, bh) + 1
      bx = button(bx, by, "Peek", P.line, P.text, function() ui.farmView = "chest"; ui.chest = n end, 6, bh) + 1
      button(bx, by, "Music", P.line, P.text, function()
        askConfirm("Make " .. chestLabel(n) .. " a music chest? Its discs join your library and it leaves its farm.", function() db.cfg.musicChests[n] = true; db.cfg.musicPicked = true; saveDb(); scanLibrary() end)
      end, 7, bh)
    end }
  end
  local total = 0
  for _, r in ipairs(rows) do total = total + r.h end
  scrollArea(2, y1 + 2, W - 2, y2 - y1 - 1, total, function(cx, cy, w)
    local yy = cy
    for _, r in ipairs(rows) do r.draw(cx, yy, w); yy = yy + r.h end
  end)
end

S.farm = function(y1, y2)
  if ui.farmView == "group" then farmGroup(y1, y2)
  elseif ui.farmView == "chest" and ui.chest then farmChest(y1, y2)
  elseif ui.farmView == "manage" then farmManage(y1, y2)
  else farmOverview(y1, y2) end
end

-- ---------- settings ----------
local SCALES = { 0, 0.5, 1, 1.5, 2, 2.5, 3 }
local function fetch(url)
  if not http then return nil, "HTTP is turned off" end
  local r, err = http.get(url .. "?t=" .. os.epoch("utc"))
  if not r then return nil, err or "download failed" end
  local body = r.readAll(); r.close()
  return body
end
local function selfUpdate()
  local body, err = fetch(HOME_URL)
  if not body then toast("Update failed: " .. tostring(err), P.red) return end
  if not body:sub(1, 400):find("EMBER HOME", 1, true) or not load(body) then toast("Update failed: bad download", P.red) return end
  local v = body:match('local VERSION%s*=%s*"([^"]+)"') or "?"
  local path = (shell and shell.getRunningProgram()) or "startup.lua"
  local f = fs.open(path .. ".new", "w"); f.write(body); f.close()
  if fs.exists(path) then fs.delete(path) end
  fs.move(path .. ".new", path)
  saveDb()
  toast("Updated to v" .. v .. " - restarting", P.accent)
  redraw()
  sleep(1.5)
  os.reboot()
end

S.settings = function(y1, y2)
  local rows = {}
  local function heading(t) rows[#rows + 1] = { h = 2, draw = function(x, y) text(x, y, t, P.sub, P.bg) end } end
  local narrowRows = W - 4 < 66
  local function row(label, drawRight)
    rows[#rows + 1] = { h = narrowRows and 3 or 2, draw = function(x, y, w)
      if narrowRows then
        fill(x, y, w, 2, P.card)
        text(x + 1, y, fit(label, w - 2), P.text, P.card)
        drawRight(x + 1, y + 1, w)
      else
        fill(x, y, w, 1, P.card)
        text(x + 1, y, fit(label, w - 34), P.text, P.card)
        drawRight(x + w - 32, y, w)
      end
    end }
  end
  heading("SCREEN")
  row("Text size", function(x, y)
    local cur = db.cfg.uiScale or 0
    local idx = 1
    for i, s in ipairs(SCALES) do if s == cur then idx = i end end
    button(x, y, "\17", P.line, P.text, function() db.cfg.uiScale = SCALES[math.max(1, idx - 1)]; saveDb(); setupScreen() end, 3)
    center(x + 4, 22, y, (cur == 0 and ("Auto (" .. ui.scaleUsed .. ")") or tostring(cur)) .. (ui.tooBig and " too big" or ""), ui.tooBig and P.yellow or P.text, P.card)
    button(x + 27, y, "\16", P.line, P.text, function() db.cfg.uiScale = SCALES[math.min(#SCALES, idx + 1)]; saveDb(); setupScreen() end, 3)
  end)
  heading("MUSIC")
  local nm = #(lib.chests or {})
  row("Music chests (" .. nm .. ")", function(x, y)
    button(x, y, fit(nm == 0 and "None - tap to choose" or (nm == 1 and chestLabel(lib.chests[1]) or (nm .. " chests, " .. #lib.list .. " discs")), 28), P.line, P.text, function()
      local opts = {}
      for _, n in ipairs(dev.invs) do
        local on = isMusic(n)
        local c = countDiscs(n)
        opts[#opts + 1] = { label = (on and "[x] " or "[ ] ") .. chestLabel(n) .. (c > 0 and ("  (" .. c .. " discs)") or ""),
          col = on and P.accent or (c > 0 and P.yellow or P.text),
          fn = function()
            db.cfg.musicChests[n] = (not on) or nil; db.cfg.musicPicked = true; saveDb(); scanLibrary()
            toast((on and "Removed " or "Added ") .. chestLabel(n) .. (on and " from" or " to") .. " the music chests", P.accent)
          end }
      end
      if #opts == 0 then toast("No chests connected", P.red) return end
      openMenu("Tap a chest to add or remove it", opts)
    end, 31)
  end)
  if #dev.drives == 0 then
    rows[#rows + 1] = { h = 2, draw = function(x, y, w) text(x + 1, y, fit("No disk drive found - it's the record player. Connect one with a wired modem.", w - 2), P.red, P.bg) end }
  else
    row("Record player (disk drive)", function(x, y)
      local dn = drive()
      button(x, y, fit(dn or "none", 28), P.line, P.text, function()
        local opts = {}
        for _, n in ipairs(dev.drives) do
          opts[#opts + 1] = { label = n, col = n == dn and P.accent or P.text, fn = function()
            returnDisc(); player.playing = false; db.cfg.drive = n; saveDb() end }
        end
        openMenu("Which disk drive plays the music?", opts)
      end, 31)
    end)
  end
  if player.cur then
    row("Length of '" .. (current() and current().title or "?") .. "'", function(x, y)
      local d = current()
      local function setLen(dl) d.len = clamp(d.len + dl, 10, 1200); db.cfg.lens[d.key] = d.len; saveDb() end
      button(x, y, "-10s", P.line, P.text, function() setLen(-10) end, 6)
      center(x + 7, 16, y, fmtTime(d.len), P.text, P.card)
      button(x + 24, y, "+10s", P.line, P.text, function() setLen(10) end, 6)
    end)
  end
  heading("DEVICES")
  row(#dev.invs .. " chests  \7  " .. #dev.drives .. " drive" .. (#dev.drives == 1 and "" or "s") .. "  \7  " .. (dev.monitor or "no monitor"), function(x, y)
    button(x, y, "Rescan", P.line, P.text, function() scanDevices(); setupScreen(); scanLibrary(); toast("Devices rescanned", P.accent) end, 10)
  end)
  heading("SOFTWARE")
  row("Ember Home v" .. VERSION .. (ui.updateMsg and ("  \7  " .. ui.updateMsg) or ""), function(x, y)
    button(x, y, "Check", P.line, P.text, function()
      local body, err = fetch(HOME_URL)
      local v = body and body:match('local VERSION%s*=%s*"([^"]+)"')
      ui.updateMsg = v and ("newest is v" .. v) or ("can't check: " .. tostring(err))
    end, 10)
    button(x + 12, y, "Update", P.accent, P.bg, function() askConfirm("Download the newest Ember Home and restart?", selfUpdate) end, 10)
  end)
  local total = 0
  for _, r in ipairs(rows) do total = total + r.h end
  text(2, y1, "Settings", P.text, P.bg)
  scrollArea(2, y1 + 2, W - 2, y2 - y1 - 1, total, function(cx, cy, w)
    local yy = cy
    for _, r in ipairs(rows) do r.draw(cx, yy, w); yy = yy + r.h end
  end)
end

-- ---------- overlays ----------
local function box(w, h, title)
  w, h = math.min(w, W - 2), math.min(h, H - 2)
  local x, y = math.floor((W - w) / 2) + 1, math.floor((H - h) / 2) + 1
  fill(x, y, w, h, P.card)
  fill(x, y, w, 1, P.line)
  text(x + 2, y, fit(title, w - 4), P.text, P.line)
  return x, y, w, h
end

local function drawConfirm()
  hits = {}
  hit(1, 1, W, H, function() end)
  local c = ui.confirm
  local w = math.min(W - 4, 50)
  local lines = {}
  local line = ""
  for word in c.text:gmatch("%S+") do
    if #line + #word + 1 > w - 4 then lines[#lines + 1] = line; line = word else line = (line == "" and word or (line .. " " .. word)) end
  end
  lines[#lines + 1] = line
  local x, y, bw, bh = box(w, #lines + 6, "Are you sure?")
  for i, l in ipairs(lines) do text(x + 2, y + 1 + i, l, P.text, P.card) end
  local by = y + bh - 2
  button(x + 2, by, "Yes", P.accent, P.bg, function() ui.confirm = nil; c.yes() end, 10)
  button(x + bw - 12, by, "Cancel", P.line, P.text, function() ui.confirm = nil end, 10)
end

local function drawMenu()
  hits = {}
  hit(1, 1, W, H, function() ui.menu = nil end)
  local m = ui.menu
  local n = math.min(#m.options, H - 7)
  local w = math.min(W - 4, 46)
  local x, y, bw, bh = box(w, n + 5, m.title)
  hit(x, y, bw, bh, function() end)
  for i = 1, n do
    local o = m.options[i]
    fill(x + 2, y + 1 + i, bw - 4, 1, P.panel)
    text(x + 3, y + 1 + i, fit(o.label, bw - 6), o.col or P.text, P.panel)
    hit(x + 2, y + 1 + i, bw - 4, 1, function() ui.menu = nil; o.fn() end)
  end
  button(x + bw - 12, y + bh - 2, "Cancel", P.line, P.text, function() ui.menu = nil end, 10)
end

local KB_ROWS = { "1234567890", "QWERTYUIOP", "ASDFGHJKL'", "ZXCVBNM-.&" }
local function drawKeyboard()
  hits = {}
  hit(1, 1, W, H, function() end)
  local k = ui.kb
  local kw = W >= 70 and 6 or (W >= 50 and 4 or 3)
  local kh = H >= 44 and 3 or 1
  local gap = H >= 24 and 1 or 0
  local w = 10 * kw + 4
  local h = 4 + 5 * (kh + gap) + 2
  local x, y, bw = box(w, h, k.title)
  fill(x + 2, y + 2, bw - 4, 1, P.bg)
  text(x + 3, y + 2, fit(k.value, bw - 7) .. "_", P.text, P.bg)
  local yy = y + 4
  for _, r in ipairs(KB_ROWS) do
    for i = 1, #r do
      local ch = r:sub(i, i)
      if k.lower then ch = ch:lower() end
      local kx = x + 2 + (i - 1) * kw
      button(kx, yy, ch, P.line, P.text, function() if #k.value < 24 then k.value = k.value .. ch end end, kw - 1, kh)
    end
    yy = yy + kh + gap
  end
  local bx = x + 2
  local unit = kw
  bx = button(bx, yy, k.lower and "ABC" or "abc", P.panel, P.text, function() k.lower = not k.lower end, unit * 2 - 1, kh) + 1
  bx = button(bx, yy, "Space", P.panel, P.text, function() if #k.value < 24 then k.value = k.value .. " " end end, unit * 3 - 1, kh) + 1
  bx = button(bx, yy, "Del", P.panel, P.text, function() k.value = k.value:sub(1, -2) end, unit * 2 - 1, kh) + 1
  bx = button(bx, yy, "Cancel", P.red, P.text, function() ui.kb = nil end, unit * 2 - 1, kh) + 1
  button(bx, yy, "OK", P.accent, P.bg, function() ui.kb = nil; k.onDone(k.value) end, unit - 1, kh)
end

-- ---------- full draw ----------
function redraw()
  local key = screenKey()
  if key ~= ui.lastKey then ui.scroll = 0; ui.lastKey = key end
  beginFrame()
  local th = drawTop()
  local y1, y2 = th + 2, H - 5
  if y2 > y1 then (S[ui.app] or S.home)(y1, y2) end
  clip = nil
  drawPlayer()
  if ui.toast and os.clock() < ui.toastUntil then
    local msg = fit(ui.toast.msg, W - 6)
    local tx = W - #msg - 3
    fill(tx - 1, H - 5, #msg + 4, 1, ui.toast.col)
    text(tx + 1, H - 5, msg, P.bg, ui.toast.col)
  end
  if ui.confirm then drawConfirm()
  elseif ui.menu then drawMenu()
  elseif ui.kb then drawKeyboard() end
  flush()
end

local function onTouch(x, y)
  for i = #hits, 1, -1 do
    local h = hits[i]
    if x >= h[1] and x <= h[3] and y >= h[2] and y <= h[4] then
      local ok, err = pcall(h[5])
      if not ok then toast("Error: " .. tostring(err), P.red) end
      return true
    end
  end
  return false
end

-- ---------- the computer's own screen ----------
local function termStatus()
  if out == term.current() then return end
  term.setBackgroundColor(colors.black); term.clear(); term.setCursorPos(1, 1)
  term.setTextColor(colors.lime); print("EMBER HOME v" .. VERSION)
  term.setTextColor(colors.white)
  print("Showing on monitor: " .. tostring(dev.monitor))
  print("Music chests: " .. #(lib.chests or {}) .. " (" .. #lib.list .. " discs)")
  print("Record player: " .. tostring((drive())) .. ", " .. #dev.invs .. " chests")
  print("")
  term.setTextColor(colors.lightGray)
  print("R = rescan devices   Q = quit")
end

-- ============================================================
--  MAIN
-- ============================================================
local function uiLoop()
  local timer = os.startTimer(1)
  redraw()
  while true do
    local ev = { os.pullEvent() }
    local e = ev[1]
    if e == "monitor_touch" then
      if ev[2] == dev.monitor then onTouch(ev[3], ev[4]); redraw() end
    elseif e == "mouse_click" then
      if not dev.monitor then onTouch(ev[3], ev[4]); redraw() end
    elseif e == "timer" and ev[2] == timer then
      musicTick()
      redraw()
      timer = os.startTimer(1)
    elseif e == "home_redraw" then redraw()
    elseif e == "monitor_resize" then setupScreen(); redraw()
    elseif e == "peripheral" or e == "peripheral_detach" then
      scanDevices(); setupScreen(); termStatus(); redraw()
    elseif e == "char" then
      local c = ev[2]:lower()
      if c == "q" then return
      elseif c == "r" then scanDevices(); setupScreen(); scanLibrary(); termStatus(); redraw() end
    end
  end
end

local function scanLoop()
  while true do
    scanLibrary()
    scanFarm()
    os.queueEvent("home_redraw")
    sleep(db.cfg.scanEvery or 10)
  end
end

local function main()
  math.randomseed(os.epoch("utc"))
  loadDb()
  scanDevices()
  setupScreen()
  scanLibrary()
  termStatus()
  parallel.waitForAny(uiLoop, scanLoop)
  returnDisc()
  if out.setPaletteColour then for c in pairs(PALETTE) do out.setPaletteColour(c, term.nativePaletteColour(c)) end end
  out.setBackgroundColor(colors.black); out.clear()
  term.setBackgroundColor(colors.black); term.clear(); term.setCursorPos(1, 1)
  print("Ember Home stopped.")
end

if HOME_TEST then
  return { main = main, redraw = redraw, onTouch = onTouch, ui = ui, db = db, lib = lib, player = player, farm = farm,
           dev = dev, scanDevices = scanDevices, setupScreen = setupScreen, scanLibrary = scanLibrary, scanFarm = scanFarm,
           musicTick = musicTick, nextTrack = nextTrack, playDisc = playDisc, shufflePlay = shufflePlay, togglePlay = togglePlay,
           hits = function() return hits end, fb = function() return fb end, size = function() return W, H end, loadDb = loadDb }
end
main()
