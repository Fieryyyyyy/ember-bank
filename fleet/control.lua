-- =====================================================
--  FLEET CONTROL - mining control room
--  Install on the control computer as startup.lua
--  Needs: advanced computer + ender modem + advanced monitor
--         (4 wide x 3 tall or bigger recommended)
-- =====================================================

local PROTOCOL      = "fleetmine"
local VERSION       = "2.2"
local REPO          = "https://raw.githubusercontent.com/Fieryyyyyy/ember-bank/main/"
local MINER_URL     = REPO .. "fleet/miner.lua"
local CONTROL_URL   = REPO .. "fleet/control.lua"
local DB_FILE       = "/fleet.db"
local OFFLINE_AFTER = 15            -- seconds without a report = offline

local DX = { [0] = 0, 1, 0, -1 }
local DZ = { [0] = -1, 0, 1, 0 }
local DIR_NAMES = { [0] = "North", "East", "South", "West" }

-- Best Y levels for 1.20+ world generation. "pat" is matched against block IDs.
local ORES = {
  { key = "diamond",  label = "Diamond",   pat = "diamond_ore",            y = -58, col = colors.lightBlue, note = "Peaks at the bottom of the world" },
  { key = "redstone", label = "Redstone",  pat = "redstone_ore",           y = -58, col = colors.red,       note = "More the deeper you go" },
  { key = "lapis",    label = "Lapis",     pat = "lapis_ore",              y = 0,   col = colors.blue,      note = "Peaks around Y 0" },
  { key = "gold",     label = "Gold",      pat = "gold_ore",               y = -16, col = colors.yellow,    note = "Badlands have extra up high" },
  { key = "iron",     label = "Iron",      pat = "iron_ore",               y = 16,  col = colors.lightGray, note = "Also huge veins in mountains" },
  { key = "copper",   label = "Copper",    pat = "copper_ore",             y = 48,  col = colors.orange,    note = "Extra in dripstone caves" },
  { key = "coal",     label = "Coal",      pat = "coal_ore",               y = 45,  col = colors.gray,      note = "Peaks at 96 inside mountains" },
  { key = "emerald",  label = "Emerald",   pat = "emerald_ore",            y = 100, col = colors.green,     note = "Mountain biomes only" },
  { key = "evo",      label = "Evo stones", pat = "^cobblemon:.*stone_ore", y = 0,  col = colors.purple,    note = "Cobblemon evolution stone ores" },
}
local DEFAULT_JUNK = {
  "minecraft:stone", "minecraft:cobblestone", "minecraft:deepslate", "minecraft:cobbled_deepslate",
  "minecraft:dirt", "minecraft:gravel", "minecraft:sand", "minecraft:tuff", "minecraft:andesite",
  "minecraft:diorite", "minecraft:granite", "minecraft:calcite", "minecraft:flint", "minecraft:netherrack",
  "minecraft:dripstone_block", "minecraft:pointed_dripstone", "minecraft:smooth_basalt", "minecraft:moss_block",
}

local function now() return os.epoch("utc") / 1000 end

-- ---------- database ----------
local db = {
  turtles = {}, totals = {}, log = {}, marker = nil,
  cfg = { dock = nil, junk = {}, reserve = 300, refuelTarget = 6000, burnCoal = true, lavaRefuel = true },
}
for _, j in ipairs(DEFAULT_JUNK) do db.cfg.junk[j] = true end

local function saveDb()
  local f = fs.open(DB_FILE .. ".tmp", "w")
  f.write(textutils.serialize(db))
  f.close()
  if fs.exists(DB_FILE) then fs.delete(DB_FILE) end
  fs.move(DB_FILE .. ".tmp", DB_FILE)
end

local function loadDb()
  local path = (fs.exists(DB_FILE) and DB_FILE) or (fs.exists(DB_FILE .. ".tmp") and DB_FILE .. ".tmp")
  if not path then return end
  local f = fs.open(path, "r")
  local t = textutils.unserialize(f.readAll())
  f.close()
  if type(t) ~= "table" then return end
  for k, v in pairs(t) do
    if k == "cfg" then for ck, cv in pairs(v) do db.cfg[ck] = cv end else db[k] = v end
  end
end

local function addLog(text, col)
  table.insert(db.log, 1, { t = textutils.formatTime(os.time(), true), text = text, col = col or colors.white })
  while #db.log > 100 do table.remove(db.log) end
end

local function oreByKey(k) for _, o in ipairs(ORES) do if o.key == k then return o end end end

local function turtleCfg()
  local ores = {}
  for _, o in ipairs(ORES) do ores[#ores + 1] = { key = o.key, label = o.label, pat = o.pat } end
  local c = db.cfg
  return { dock = c.dock, junk = c.junk, reserve = c.reserve, refuelTarget = c.refuelTarget,
           burnCoal = c.burnCoal, lavaRefuel = c.lavaRefuel, ores = ores }
end

local function pushCfg()
  for id, t in pairs(db.turtles) do rednet.send(id, { type = "welcome", lane = t.lane, cfg = turtleCfg() }, PROTOCOL) end
end

-- ---------- turtles ----------
local function sortedIds()
  local ids = {}
  for id in pairs(db.turtles) do ids[#ids + 1] = id end
  table.sort(ids)
  return ids
end
local function online(t) return t.lastSeen ~= nil and now() - t.lastSeen < OFFLINE_AFTER end
local function stateOf(t)
  if not online(t) then return "Offline" end
  return (t.st and t.st.state) or "?"
end
local function parked(t)
  local s = (t.st and t.st.state) or ""
  return s == "Idle" or s:find("^Recalled") ~= nil
end
-- free for a new job: online, parked at the depot and not running a job (a held job may be replaced)
local function canTakeJob(t) return t and online(t) and t.st and t.st.mode ~= "job" and parked(t) end
-- free and with nothing on hold: picked automatically for new jobs
local function isIdle(t) return canTakeJob(t) and not t.st.job end

local function fleetCounts()
  local c = { total = 0, working = 0, idle = 0, held = 0, problem = 0, offline = 0 }
  for _, t in pairs(db.turtles) do
    c.total = c.total + 1
    local st = t.st or {}
    if not online(t) then c.offline = c.offline + 1
    elseif st.state == "ERROR" or st.alert then c.problem = c.problem + 1
    elseif st.mode == "job" then c.working = c.working + 1
    elseif st.job then c.held = c.held + 1
    else c.idle = c.idle + 1 end
  end
  return c
end

-- ---------- software updates (from GitHub) ----------
local function fetch(url)
  if not http then return nil, "HTTP is turned off on this server" end
  local res, err = http.get(url .. "?t=" .. os.epoch("utc"))
  if not res then return nil, tostring(err) end
  local body = res.readAll(); res.close()
  return body
end
local function versionOf(body) return body and body:match('local VERSION%s*=%s*"([^"]+)"') end
local function freeLane()
  local used = {}
  for _, t in pairs(db.turtles) do if t.lane then used[t.lane] = true end end
  local l = 1
  while used[l] do l = l + 1 end
  return l
end
local function sendCmd(id, cmd, extra)
  local m = { type = "cmd", cmd = cmd }
  for k, v in pairs(extra or {}) do m[k] = v end
  rednet.send(id, m, PROTOCOL)
end

local function stateColor(s)
  s = (s or ""):lower()
  if s:find("error") or s:find("out of fuel") then return colors.red end
  if s:find("mining") then return colors.lime end
  if s:find("travel") or s:find("return") or s:find("dock") then return colors.lightBlue end
  if s:find("unload") or s:find("refuel") then return colors.cyan end
  if s:find("pause") or s:find("recall") then return colors.yellow end
  if s:find("block") or s:find("wait") or s:find("full") or s:find("locat") or s:find("finding") then return colors.orange end
  if s:find("offline") then return colors.gray end
  return colors.lightGray
end

local function fuelFrac(st)
  if not st or not st.fuel then return 0 end
  if st.fuel == "unlimited" then return 1 end
  return math.min(1, st.fuel / math.max(1, db.cfg.refuelTarget))
end
local function fuelColor(fr) return fr > 0.5 and colors.lime or (fr > 0.2 and colors.yellow or colors.red) end

local function eta(t)
  local p = t.st and t.st.progress
  if not p or not t.pStart then return nil end
  local el, dp = now() - t.pStart.t, p - t.pStart.p
  if el < 30 or dp <= 0 then return nil end
  return (1 - p) * el / dp
end
local function fmtTime(s)
  if not s then return "--" end
  s = math.floor(s)
  if s < 60 then return s .. "s" end
  if s < 3600 then return math.floor(s / 60) .. "m" end
  return math.floor(s / 3600) .. "h" .. string.format("%02d", math.floor(s % 3600 / 60)) .. "m"
end

local function onStatus(id, m)
  local t = db.turtles[id]
  if not t then
    t = { lane = freeLane(), name = m.label or ("Miner-" .. id), jobsDone = 0 }
    db.turtles[id] = t
    addLog("New turtle #" .. id .. " (" .. t.name .. ") joined on lane " .. t.lane, colors.lime)
    saveDb()
  end
  t.name = m.label or t.name
  if not t.welcomed or m.lane ~= t.lane or m.state == "Waiting for control room" then
    rednet.send(id, { type = "welcome", lane = t.lane, cfg = turtleCfg() }, PROTOCOL)
    t.welcomed = true
  end
  -- progress tracking for ETA
  local desc = m.job and m.job.desc
  if desc ~= t.jobDesc or (m.progress and t.pStart and m.progress < t.pStart.p) then t.pStart = nil end
  t.jobDesc = desc
  if m.progress and not t.pStart and m.state == "Mining" then t.pStart = { t = now(), p = m.progress } end

  if type(m.found) == "table" then
    for label, f in pairs(m.found) do
      db.totals[label] = (db.totals[label] or 0) + f.n
      local o
      for _, ore in ipairs(ORES) do if ore.label == label then o = ore end end
      if f.pos then
        addLog(string.format("%s found %dx %s at %d,%d,%d", t.name, f.n, label, f.pos.x, f.pos.y, f.pos.z), o and o.col or colors.white)
      end
    end
  end
  if m.alert and m.alert ~= t.lastAlert then addLog(t.name .. ": " .. m.alert, colors.orange) end
  t.lastAlert = m.alert
  t.lastStuck = type(m.stuck) == "string" and m.stuck or nil
  t.st = m
  t.lastSeen = now()
end

-- ---------- jobs ----------
local function newWizard(preset)
  local f = {
    kind = "branch", target = "diamond", y = -58, dir = 0, startMode = "depot", dist = 16,
    mainLen = 64, branchLen = 16, spacing = 3, sides = "both", walls = true, vein = true, tall = false,
    turtles = 1, length = 32, width = 16, height = 3, topY = 60, bottomY = -58, page = 1,
  }
  if db.cfg.dock then f.topY = db.cfg.dock.y - 1 end
  -- room corners start next to the depot so the numbers are close to where you are
  local D = db.cfg.dock or { x = 0, y = 64, z = 0 }
  f.ax, f.ay, f.az = D.x + 5, D.y - 1, D.z + 5
  f.bx, f.by, f.bz = D.x + 14, D.y - 4, D.z + 14
  for k, v in pairs(preset or {}) do f[k] = v end
  if preset and preset.target and not preset.y then
    local o = oreByKey(preset.target)
    if o then f.y = o.y end
  end
  return f
end

local function startXZ(f)
  if f.startMode == "marker" then
    if db.marker then return db.marker.x, db.marker.z end
    return nil
  end
  local D = db.cfg.dock
  if not D then return nil end
  return D.x + DX[f.dir] * f.dist, D.z + DZ[f.dir] * f.dist
end

local function targetLabel(k)
  if k == "all" then return "All ores" end
  local o = oreByKey(k)
  return o and o.label or k
end

local function buildJobs(f, ids)
  local jobs = {}
  local sx, sz = startXZ(f)
  local d, right = f.dir, (f.dir + 1) % 4
  local k = #ids
  if f.kind == "branch" then
    local sideW = (f.sides == "both") and (2 * f.branchLen) or f.branchLen
    local off = sideW + f.spacing
    local sdir = (f.sides == "left") and (d + 3) % 4 or right
    for i, id in ipairs(ids) do
      local o = (i - 1) * off
      jobs[id] = {
        kind = "branch", x = sx + DX[sdir] * o, y = f.y, z = sz + DZ[sdir] * o, dir = d,
        mainLen = f.mainLen, branchLen = f.branchLen, spacing = f.spacing, sides = f.sides,
        walls = f.walls, vein = f.vein, tall = f.tall, target = f.target,
        desc = "Branch " .. targetLabel(f.target) .. " Y" .. f.y,
      }
    end
  elseif f.kind == "room" then
    -- a box between two corners, split into slices along its longest side
    local x1, x2 = math.min(f.ax, f.bx), math.max(f.ax, f.bx)
    local z1, z2 = math.min(f.az, f.bz), math.max(f.az, f.bz)
    local y1, y2 = math.max(-59, math.min(f.ay, f.by)), math.max(f.ay, f.by)
    local alongX = (x2 - x1) >= (z2 - z1)
    local span = alongX and (x2 - x1 + 1) or (z2 - z1 + 1)
    local per = math.ceil(span / k)
    local size = (x2 - x1 + 1) .. "x" .. (z2 - z1 + 1) .. "x" .. (y2 - y1 + 1)
    for i, id in ipairs(ids) do
      local s0, s1 = (i - 1) * per, math.min(span, i * per) - 1
      if s0 <= s1 then
        local job = { kind = "box", x1 = x1, x2 = x2, z1 = z1, z2 = z2, y1 = y1, y2 = y2, desc = "Room " .. size }
        if alongX then job.x1, job.x2 = x1 + s0, x1 + s1 else job.z1, job.z2 = z1 + s0, z1 + s1 end
        jobs[id] = job
      end
    end
  else
    local L, Wd = f.length, f.width
    local y1, y2
    if f.kind == "quarry" then y1, y2 = math.max(-59, f.bottomY), f.topY else y1, y2 = f.y, f.y + f.height - 1 end
    local per = math.ceil(Wd / k)
    for i, id in ipairs(ids) do
      local w0, w1 = (i - 1) * per, math.min(Wd, i * per) - 1
      if w0 <= w1 then
        jobs[id] = {
          kind = "box",
          x1 = sx + DX[right] * w0, z1 = sz + DZ[right] * w0,
          x2 = sx + DX[d] * (L - 1) + DX[right] * w1, z2 = sz + DZ[d] * (L - 1) + DZ[right] * w1,
          y1 = y1, y2 = y2,
          desc = (f.kind == "quarry" and ("Quarry " .. L .. "x" .. (w1 - w0 + 1)) or ("Tunnel " .. Wd .. "x" .. f.height .. "x" .. L)),
        }
      end
    end
  end
  return jobs
end

local function estimate(f)
  local moves
  if f.kind == "branch" then
    local nb = math.floor(f.mainLen / f.spacing)
    moves = f.mainLen + nb * (f.sides == "both" and 2 or 1) * f.branchLen * 2
  elseif f.kind == "room" then
    local w = math.abs(f.ax - f.bx) + 1
    local l = math.abs(f.az - f.bz) + 1
    local h = math.max(f.ay, f.by) - math.max(-59, math.min(f.ay, f.by)) + 1
    moves = math.ceil(w * l * math.ceil(math.max(1, h) / 3) / math.max(1, f.only and 1 or f.turtles))
    local D = db.cfg.dock
    local travel = D and 2 * (math.abs(math.floor((f.ax + f.bx) / 2) - D.x) + math.abs(math.floor((f.az + f.bz) / 2) - D.z) + math.abs(D.y - math.min(f.ay, f.by)) + 20) or 0
    return moves, travel
  else
    local h = (f.kind == "quarry") and (f.topY - math.max(-59, f.bottomY) + 1) or f.height
    moves = f.length * f.width * math.ceil(math.max(1, h) / 3)
    moves = math.ceil(moves / math.max(1, f.kind == "tunnel" and 1 or f.turtles))
  end
  local travel = 0
  local D = db.cfg.dock
  local sx, sz = startXZ(f)
  if D and sx then
    local ty = (f.kind == "quarry") and f.topY or f.y
    travel = 2 * (math.abs(sx - D.x) + math.abs(sz - D.z) + math.abs(D.y - ty) + 20)
  end
  return moves, travel
end

local function launch(f)
  if not db.cfg.dock then return false, "Set the depot first (type: depot x y z on the PC)" end
  if f.startMode == "marker" and not db.marker then return false, "No pocket marker set yet" end
  if f.kind == "quarry" and f.topY < f.bottomY then return false, "Top Y must be above bottom Y" end
  if f.kind == "room" and math.max(f.ay, f.by) < -59 then return false, "The room is all bedrock - raise the Y" end
  local ids = {}
  if f.only then
    if not canTakeJob(db.turtles[f.only]) then return false, "That turtle is busy - wait until it's parked" end
    ids = { f.only }
  else
    local want = (f.kind == "tunnel") and 1 or f.turtles
    for _, id in ipairs(sortedIds()) do
      if #ids < want and isIdle(db.turtles[id]) then ids[#ids + 1] = id end
    end
  end
  if #ids == 0 then return false, "No idle turtles available" end
  for id, job in pairs(buildJobs(f, ids)) do
    rednet.send(id, { type = "job", job = job }, PROTOCOL)
    db.turtles[id].pStart = nil
    addLog("Sent " .. db.turtles[id].name .. ": " .. job.desc, colors.lightBlue)
  end
  saveDb()
  return true, "Job launched on " .. #ids .. " turtle" .. (#ids > 1 and "s" or "")
end

-- ---------- pocket remote requests ----------
local function compactFleet()
  local list = {}
  for _, id in ipairs(sortedIds()) do
    local t = db.turtles[id]
    local st = t.st or {}
    list[#list + 1] = {
      id = id, name = t.name, state = stateOf(t), fuel = st.fuel, fuelFrac = fuelFrac(st),
      progress = st.progress, alert = st.alert, job = st.job and st.job.desc, pos = st.pos,
      paused = st.paused, mode = st.mode, inv = st.inv, idle = isIdle(t), eta = fmtTime(eta(t)),
    }
  end
  return list
end

local function handleRemote(id, m)
  local r = { ok = true }
  if m.type == "r_fleet" then
    r.fleet = compactFleet()
    r.log = {}
    for i = 1, math.min(15, #db.log) do r.log[i] = db.log[i] end
    r.ores = {}
    for _, o in ipairs(ORES) do r.ores[#r.ores + 1] = { key = o.key, label = o.label, y = o.y } end
    r.marker, r.dock = db.marker, db.cfg.dock
  elseif m.type == "r_cmd" then
    if m.id == "all" then for tid in pairs(db.turtles) do sendCmd(tid, m.cmd) end
    elseif db.turtles[m.id] then sendCmd(m.id, m.cmd)
    else r = { ok = false, err = "Unknown turtle" } end
  elseif m.type == "r_marker" and type(m.pos) == "table" then
    db.marker = m.pos
    addLog("Pocket marker set at " .. m.pos.x .. "," .. m.pos.y .. "," .. m.pos.z, colors.lightBlue)
    saveDb()
  elseif m.type == "r_quick" and type(m.pos) == "table" then
    db.marker = m.pos
    local f = newWizard({ kind = "branch", target = m.target, dir = m.dir or 0, startMode = "marker", only = m.id })
    if m.y then f.y = m.y end
    local ok, msg = launch(f)
    r = { ok = ok, err = msg, msg = msg }
  else
    r = { ok = false, err = "Unknown request" }
  end
  r.rid = m.rid
  rednet.send(id, r, PROTOCOL)
end

local function netLoop()
  while true do
    local id, m = rednet.receive(PROTOCOL)
    if type(m) == "table" then
      if m.type == "status" then onStatus(id, m)
      elseif m.type == "log" and type(m.text) == "string" then addLog(m.text, colors.lightGray)
      elseif m.type == "done" then
        local t = db.turtles[id]
        if t then t.jobsDone = (t.jobsDone or 0) + 1 end
        addLog(m.text or ("#" .. id .. " finished its job"), colors.lime)
        saveDb()
      elseif m.rid ~= nil and type(m.type) == "string" and m.type:sub(1, 2) == "r_" then
        handleRemote(id, m)
      end
    end
  end
end

-- =====================================================
--  MONITOR UI
-- =====================================================
local mon = peripheral.find("monitor")
local W, H, CW = 0, 0, 0          -- CW = width for content (W minus the scroll bar when it shows)
local hits = {}
local ui = { tab = "fleet", detail = nil, wiz = nil, toast = nil, toastUntil = 0, cfgDirty = false,
             scroll = 0, confirm = nil, scaleUsed = nil }
local view = nil                  -- the scrolling area while it is being drawn

-- text size choices for Settings (0 = pick automatically)
local SCALES = { 0, 0.5, 1, 1.5, 2, 2.5, 3 }
local SCALE_NAMES = { "Auto", "0.5 (small)", "1", "1.5", "2", "2.5", "3 (huge)" }
local MIN_W, MIN_H = 26, 12

local function setupMonitor()
  if not mon then return end
  local want = db.cfg.uiScale or 0
  local s
  if want == 0 then
    s = 1; mon.setTextScale(1); W, H = mon.getSize()
    if W < 50 then s = 0.5; mon.setTextScale(0.5); W, H = mon.getSize() end
  else
    s = want; mon.setTextScale(s); W, H = mon.getSize()
    while (W < MIN_W or H < MIN_H) and s > 0.5 do      -- too big for this monitor: step down
      s = s - 0.5; mon.setTextScale(s); W, H = mon.getSize()
    end
  end
  ui.scaleUsed = s
  CW = W
  if W < MIN_W or H < MIN_H then error("Monitor too small - build it at least 2 wide x 2 tall", 0) end
end

local function narrow() return CW < 60 end

local function put(x, y, s, fg, bg)
  s = tostring(s)
  if view then
    if y > view.maxY then view.maxY = y end
    y = y - view.off
    if y < view.top or y > view.bottom then return end
  end
  if y < 1 or y > H or x > W then return end
  if x < 1 then s = s:sub(2 - x); x = 1 end
  s = s:sub(1, W - x + 1)
  mon.setCursorPos(x, y)
  mon.setTextColor(fg or colors.white)
  mon.setBackgroundColor(bg or colors.black)
  mon.write(s)
end
local function fill(x, y, w, h, bg)
  if w <= 0 then return end
  for yy = y, y + h - 1 do put(x, yy, string.rep(" ", w), colors.white, bg) end
end
local function hit(id, x, y, w, data)
  if view then
    y = y - view.off
    if y < view.top or y > view.bottom then return end
  end
  hits[#hits + 1] = { id = id, x1 = x, x2 = x + w - 1, y = y, data = data }
end
local function btn(id, x, y, w, label, bg, fg, data)
  if w <= 0 then return end
  fill(x, y, w, 1, bg)
  label = label:sub(1, w)
  put(x + math.floor((w - #label) / 2), y, label, fg or colors.white, bg)
  hit(id, x, y, w, data)
end
local function bar(x, y, w, frac, col, back)
  if w <= 0 then return end
  frac = math.max(0, math.min(1, frac or 0))
  fill(x, y, w, 1, back or colors.gray)
  local n = math.floor(frac * w + 0.5)
  if n > 0 then fill(x, y, n, 1, col) end
end
local function pad(s, w) s = tostring(s); if w <= 0 then return "" end if #s >= w then return s:sub(1, w) end return s .. string.rep(" ", w - #s) end
local function center(s, w) s = tostring(s); return pad(string.rep(" ", math.max(0, math.floor((w - #s) / 2))) .. s, w) end
local function pct(f) return string.format("%3d%%", math.floor((f or 0) * 100)) end

local function wrap(s, w)
  local lines = {}
  w = math.max(1, w)
  for para in (tostring(s) .. "\n"):gmatch("(.-)\n") do
    local line = ""
    for wd in para:gmatch("%S+") do
      local word = wd
      while #word > w do
        if line ~= "" then lines[#lines + 1] = line; line = "" end
        lines[#lines + 1] = word:sub(1, w); word = word:sub(w + 1)
      end
      if word ~= "" then
        if line == "" then line = word
        elseif #line + 1 + #word <= w then line = line .. " " .. word
        else lines[#lines + 1] = line; line = word end
      end
    end
    lines[#lines + 1] = line
  end
  return lines
end
-- wrapped text; returns the next free row
local function para(x, y, s, fg, w)
  for _, l in ipairs(wrap(s, w or (CW - x))) do put(x, y, l, fg); y = y + 1 end
  return y
end

local function toast(msg, good)
  ui.toast = { text = msg, col = good and colors.green or colors.red }
  ui.toastUntil = now() + 4
end

-- ---------- footer buttons (wrap onto extra rows when the screen is narrow) ----------
local function layoutRows(list)
  local need = 5
  for _, b in ipairs(list) do need = math.max(need, #b[2] + 1) end
  local per = math.max(1, math.min(#list, math.floor((W - 1) / (need + 1))))
  return per, math.ceil(#list / per)
end
local function drawFooter(list)
  local per, rows = layoutRows(list)
  for r = 1, rows do
    local y = H - rows + r
    local first = (r - 1) * per + 1
    local n = math.min(per, #list - first + 1)
    local w = math.floor((W - (n + 1)) / n)
    for i = 0, n - 1 do
      local b = list[first + i]
      btn(b[1], 2 + i * (w + 1), y, w, b[2], b[3], colors.white, b[4])
    end
  end
end

-- ---------- scrolling ----------
local function drawScrollbar(top, bottom, contentH)
  local viewH = bottom - top + 1
  local maxOff = math.max(0, contentH - viewH)
  local x = W - 1
  fill(x, top, 2, viewH, colors.gray)
  local tTop, tBot = top + 1, bottom - 1
  local tH = tBot - tTop + 1
  if tH >= 1 then
    local thumbH = math.max(1, math.floor(tH * viewH / contentH))
    local thumbY = tTop + math.floor((tH - thumbH) * (maxOff > 0 and ui.scroll / maxOff or 0) + 0.5)
    fill(x, thumbY, 2, thumbH, colors.lightGray)
    for y = tTop, tBot do
      if y < thumbY then hit("scroll", x, y, 2, -(viewH - 1))
      elseif y >= thumbY + thumbH then hit("scroll", x, y, 2, viewH - 1) end
    end
  end
  put(x, top, "\30\30", colors.white, colors.gray); hit("scroll", x, top, 2, -3)
  put(x, bottom, "\31\31", colors.white, colors.gray); hit("scroll", x, bottom, 2, 3)
end

-- draws fn(top) into rows top..bottom; if it is taller, adds a scroll bar on the right
local function scrollArea(top, bottom, fn)
  local base = #hits
  local function pass(cw)
    for i = #hits, base + 1, -1 do hits[i] = nil end
    fill(1, top, W, bottom - top + 1, colors.black)
    CW = cw
    view = { top = top, bottom = bottom, off = ui.scroll, maxY = top - 1 }
    local ok, err = pcall(fn, top)
    local m = view.maxY
    view = nil
    if not ok then error(err, 0) end
    return m - top + 1
  end
  local viewH = bottom - top + 1
  local h = pass(W)
  if h > viewH then
    h = pass(W - 2)
    local maxOff = math.max(0, h - viewH)
    if ui.scroll > maxOff then ui.scroll = maxOff; h = pass(W - 2) end
    drawScrollbar(top, bottom, h)
  elseif ui.scroll ~= 0 then
    ui.scroll = 0; pass(W)
  end
  CW = W
end

-- ---------- header + tabs (two rows of tabs on narrow screens) ----------
local TABS = { { "fleet", "Fleet" }, { "jobs", "Jobs" }, { "map", "Map" }, { "ores", "Ores" }, { "log", "Log" }, { "settings", "Settings" } }

local function drawHeader()
  fill(1, 1, W, 1, colors.orange)
  put(2, 1, W >= 40 and "FLEET CONTROL" or "FLEET", colors.black, colors.orange)
  local on, total = 0, 0
  for _, t in pairs(db.turtles) do total = total + 1; if online(t) then on = on + 1 end end
  local right = on .. "/" .. total .. " online"
  if W >= 60 then right = right .. "   Day " .. os.day() .. " " .. textutils.formatTime(os.time(), true) end
  right = right .. " "
  put(W - #right + 1, 1, right, colors.black, colors.orange)
  local perRow = (math.floor(W / #TABS) >= 9) and #TABS or math.ceil(#TABS / 2)
  local rows = math.ceil(#TABS / perRow)
  local tw = math.floor(W / perRow)
  for r = 1, rows do
    local y = 1 + r
    fill(1, y, W, 1, colors.gray)
    for i = 1, perRow do
      local t = TABS[(r - 1) * perRow + i]
      if t then
        local x = 1 + (i - 1) * tw
        local w = (i == perRow) and (W - x + 1) or tw
        local active = (ui.tab == t[1]) and not ui.wiz and not ui.detail
        btn("tab", x, y, w, t[2], active and colors.black or colors.gray, active and colors.orange or colors.white, t[1])
      end
    end
  end
  return 1 + rows
end

-- ---------- small layout helpers ----------
local function kv(y, label, value, col)
  value = tostring(value)
  local lw = narrow() and 10 or 12
  if 2 + lw + #value <= CW then
    put(2, y, pad(label, lw), colors.lightGray); put(2 + lw, y, value, col or colors.white)
    return y + 1
  end
  put(2, y, label, colors.lightGray)
  return para(4, y + 1, value, col or colors.white)
end
local function kvBar(y, label, frac, col, text)
  local lw = narrow() and 10 or 12
  put(2, y, pad(label, lw), colors.lightGray)
  local bw = math.min(30, CW - lw - 3 - #text)
  if bw >= 6 then
    bar(2 + lw, y, bw, frac, col); put(3 + lw + bw, y, text, colors.white)
    return y + 1
  end
  bar(2 + lw, y, math.max(4, CW - lw - 2), frac, col)
  put(4, y + 1, text, colors.white)
  return y + 2
end

-- ---------- fleet tab ----------
local function fleetList(y, ids)
  if narrow() then
    for _, id in ipairs(ids) do
      local t = db.turtles[id]
      local st = t.st or {}
      local state = stateOf(t)
      local sw = math.min(#state, math.floor(CW / 2))
      put(2, y, pad("#" .. id .. " " .. t.name, CW - sw - 3), colors.white)
      put(CW - sw, y, state:sub(1, sw), stateColor(state))
      hit("turtle", 1, y, CW, id)
      y = y + 1
      local fr = fuelFrac(st)
      local fw = math.floor((CW - 4) / 2)
      bar(3, y, fw - 5, fr, fuelColor(fr))
      put(fw - 1, y, st.fuel == "unlimited" and " inf" or pct(fr), colors.white)
      local px, pw = fw + 4, CW - fw - 4
      if st.progress then
        bar(px, y, pw - 5, st.progress, colors.lime)
        put(px + pw - 4, y, pct(st.progress), colors.white)
      else put(px, y, pad(st.job and st.job.desc or "-", pw), st.job and colors.white or colors.gray) end
      hit("turtle", 1, y, CW, id)
      y = y + 1
    end
    return y
  end
  local cols, x = {}, 1
  local function col(key, title, w) cols[#cols + 1] = { key = key, title = title, x = x, w = w }; x = x + w + 1 end
  col("name", "TURTLE", 13); col("state", "STATE", 14); col("fuel", "FUEL", 13)
  local rest = CW - x + 1
  if rest >= 34 then col("job", "JOB", rest - 27); col("prog", "PROGRESS", 18); col("inv", "INV", 5)
  elseif rest >= 12 then col("prog", "PROGRESS", rest - 1) end
  for _, c in ipairs(cols) do put(c.x + 1, y, c.title, colors.lightGray) end
  y = y + 1
  for _, id in ipairs(ids) do
    local t = db.turtles[id]
    local st = t.st or {}
    local state = stateOf(t)
    for _, c in ipairs(cols) do
      if c.key == "name" then put(c.x + 1, y, pad("#" .. id .. " " .. t.name, c.w), colors.white)
      elseif c.key == "state" then put(c.x + 1, y, pad(state, c.w), stateColor(state))
      elseif c.key == "fuel" then
        local fr = fuelFrac(st)
        bar(c.x + 1, y, c.w - 5, fr, fuelColor(fr))
        put(c.x + c.w - 3, y, st.fuel == "unlimited" and "inf" or pct(fr), colors.white)
      elseif c.key == "job" then put(c.x + 1, y, pad(st.job and st.job.desc or "-", c.w), st.job and colors.white or colors.gray)
      elseif c.key == "prog" then
        if st.progress then
          bar(c.x + 1, y, c.w - 10, st.progress, colors.lime)
          put(c.x + c.w - 8, y, pct(st.progress) .. " " .. fmtTime(eta(t)), colors.white)
        else put(c.x + 1, y, "-", colors.gray) end
      elseif c.key == "inv" then put(c.x + 1, y, (st.inv or 0) .. "/16", (st.inv or 0) >= 14 and colors.orange or colors.white) end
    end
    hit("turtle", 1, y, CW, id)
    y = y + 1
  end
  return y
end

local function fleetScreen()
  local footer = {
    { "cmdall", "Pause all", colors.gray, "pause" }, { "cmdall", "Resume all", colors.gray, "resume" },
    { "cmdall", "Recall all", colors.orange, "recall" }, { "cmdall", "Refuel all", colors.cyan, "refuel" },
    { "cancelall", "Cancel all", colors.red }, { "newjob", "+ New job", colors.green },
  }
  return footer, function(y)
    if not db.cfg.dock then
      y = para(2, y, "Depot not set! On the control computer type: depot <x> <y> <z>", colors.red)
    end
    local ids = sortedIds()
    if #ids == 0 then
      para(2, y + 1, "No turtles yet. Put a turtle in the dock and install miner.lua on it.", colors.lightGray)
      return
    end
    local c = fleetCounts()
    local chips = {
      { c.total .. " turtle" .. (c.total == 1 and "" or "s"), colors.black, colors.orange },
      { c.working .. " working", colors.black, colors.lime },
      { c.idle .. " idle", colors.black, colors.lightGray },
    }
    if c.held > 0 then chips[#chips + 1] = { c.held .. " on hold", colors.black, colors.yellow } end
    if c.problem > 0 then chips[#chips + 1] = { c.problem .. " need help", colors.white, colors.red } end
    if c.offline > 0 then chips[#chips + 1] = { c.offline .. " offline", colors.white, colors.gray } end
    local x = 2
    for _, ch in ipairs(chips) do
      local s = " " .. ch[1] .. " "
      if x > 2 and x + #s - 1 > CW then x = 2; y = y + 1 end
      put(x, y, s, ch[2], ch[3])
      x = x + #s + 1
    end
    y = y + 2
    fleetList(y, ids)
  end
end

-- ---------- turtle detail ----------
local function detailScreen()
  local id = ui.detail
  local t = db.turtles[id]
  local st = t.st or {}
  local state = stateOf(t)
  local paused = st.paused or st.mode == "recalled" or state == "ERROR"
  local footer = {
    { "tcmd", paused and "Resume" or "Pause", paused and colors.green or colors.gray, paused and "resume" or "pause" },
    { "tcmd", "Recall", colors.orange, "recall" },
    { "tcmd", "Refuel", colors.cyan, "refuel" },
    { "tcmd", "Cancel job", colors.red, "cancel" },
    { "tjob", "New job", colors.green },
    { "back", "Back", colors.gray },
  }
  return footer, function(y)
    local title = "#" .. id .. "  " .. t.name
    if #title + #state + 4 <= CW then
      put(2, y, title, colors.orange); put(CW - #state, y, state, stateColor(state)); y = y + 1
    else
      put(2, y, title, colors.orange); put(2, y + 1, state, stateColor(state)); y = y + 2
    end
    y = y + 1
    local p = st.pos
    y = kv(y, "Position", p and (p.x .. ", " .. p.y .. ", " .. p.z .. "  facing " .. (DIR_NAMES[st.facing or -1] or "?")) or "unknown")
    y = kv(y, "Lane", t.lane and (t.lane .. " (parks at Y " .. (db.cfg.dock and (db.cfg.dock.y - 2 - t.lane) or "?") .. ")") or "-")
    local fr = fuelFrac(st)
    y = kvBar(y, "Fuel", fr, fuelColor(fr), tostring(st.fuel or "?") .. " / " .. db.cfg.refuelTarget)
    y = kv(y, "Inventory", (st.inv or 0) .. " / 16 slots")
    y = kv(y, "Job", st.job and st.job.desc or "none", st.job and colors.white or colors.gray)
    if st.progress then
      y = kvBar(y, "Progress", st.progress, colors.lime, string.format("%d%% ETA %s", math.floor(st.progress * 100), fmtTime(eta(t))))
    end
    y = kv(y, "Mined", ((st.stats and st.stats.blocks) or 0) .. " blocks, " .. (t.jobsDone or 0) .. " jobs done")
    y = kv(y, "Software", st.version and ("v" .. st.version) or "old - update by hand once", st.version and colors.white or colors.orange)
    if st.alert then y = para(2, y + 1, st.alert, colors.red) end
    if t.lastStuck then
      y = para(2, y + 1, "Last stuck: " .. t.lastStuck, colors.orange)
    end
    y = y + 1
    if st.stats and st.stats.ores and next(st.stats.ores) then
      put(2, y, "Ores found by this turtle:", colors.lightGray); y = y + 1
      local x = 2
      for label, n in pairs(st.stats.ores) do
        local s = label .. " x" .. n
        if x > 2 and x + #s > CW then x = 2; y = y + 1 end
        put(x, y, s, colors.white)
        x = x + #s + 3
      end
    end
  end
end

-- ---------- jobs tab ----------
local function jobsScreen()
  local footer = {
    { "newjob", "+ New job", colors.green }, { "cmdall", "Resume all", colors.gray, "resume" },
    { "cmdall", "Recall all", colors.orange, "recall" }, { "cancelall", "Cancel all", colors.red },
  }
  return footer, function(y)
    put(2, y, "Active jobs", colors.lightGray)
    y = y + 1
    local any = false
    for _, id in ipairs(sortedIds()) do
      local t = db.turtles[id]
      local st = t.st or {}
      if st.job then
        any = true
        local state = stateOf(t)
        if narrow() then
          local sw = math.min(#state, math.floor(CW / 2))
          put(2, y, pad(t.name .. ": " .. (st.job.desc or "?"), CW - sw - 3), colors.white)
          put(CW - sw, y, state:sub(1, sw), stateColor(state))
          hit("turtle", 1, y, CW, id)
          y = y + 1
          local bw = CW - 16
          bar(3, y, bw, st.progress or 0, colors.lime)
          put(4 + bw, y, pct(st.progress) .. " " .. fmtTime(eta(t)), colors.lightGray)
          hit("turtle", 1, y, CW, id)
          y = y + 1
        else
          put(2, y, pad(t.name, 12), colors.white)
          put(15, y, pad(st.job.desc or "?", math.max(10, CW - 52)), colors.white)
          local bx = math.max(26, CW - 36)
          bar(bx, y, 14, st.progress or 0, colors.lime)
          put(bx + 15, y, pct(st.progress), colors.white)
          put(bx + 20, y, pad("ETA " .. fmtTime(eta(t)), 10), colors.lightGray)
          put(CW - 6, y, pad(state, 7), stateColor(state))
          hit("turtle", 1, y, CW, id)
          y = y + 1
        end
      end
    end
    if not any then para(2, y, "No active jobs. Tap + New job to put your turtles to work.", colors.gray) end
  end
end

-- ---------- map tab (fits itself to the screen, no scrolling) ----------
local function mapScreen()
  return {}, function(top, bottom)
    local mh = bottom - top
    local minX, maxX, minZ, maxZ
    local function inc(x, z)
      minX = minX and math.min(minX, x) or x; maxX = maxX and math.max(maxX, x) or x
      minZ = minZ and math.min(minZ, z) or z; maxZ = maxZ and math.max(maxZ, z) or z
    end
    local D = db.cfg.dock
    if D then inc(D.x, D.z) end
    local rects = {}
    local ids = sortedIds()
    for _, id in ipairs(ids) do
      local st = db.turtles[id].st
      if st and st.pos then inc(st.pos.x, st.pos.z) end
      local j = st and st.job
      if j then
        local r
        if j.kind == "box" then r = { j.x1, j.z1, j.x2, j.z2 }
        elseif j.kind == "branch" then
          local ex, ez = j.x + DX[j.dir] * j.mainLen, j.z + DZ[j.dir] * j.mainLen
          local lft, rgt = (j.dir + 3) % 4, (j.dir + 1) % 4
          local bl = j.sides ~= "right" and j.branchLen or 0
          local br = j.sides ~= "left" and j.branchLen or 0
          r = { j.x + DX[lft] * bl, j.z + DZ[lft] * bl, ex + DX[rgt] * br, ez + DZ[rgt] * br }
        end
        if r then rects[#rects + 1] = r; inc(r[1], r[2]); inc(r[3], r[4]) end
      end
    end
    if db.marker then inc(db.marker.x, db.marker.z) end
    if not minX then para(2, top + 1, "Nothing to show yet - set the depot and add turtles.", colors.gray) return end
    minX, maxX, minZ, maxZ = minX - 4, maxX + 4, minZ - 4, maxZ + 4
    local scale = math.max(1, math.ceil(math.max((maxX - minX + 1) / W, (maxZ - minZ + 1) / mh)))
    local cx, cz = (minX + maxX) / 2, (minZ + maxZ) / 2
    local function sx(x) return math.floor((x - cx) / scale + W / 2) + 1 end
    local function sy(z) return math.floor((z - cz) / scale + mh / 2) + top end
    for _, r in ipairs(rects) do
      local x1, x2 = math.min(sx(r[1]), sx(r[3])), math.max(sx(r[1]), sx(r[3]))
      local y1, y2 = math.min(sy(r[2]), sy(r[4])), math.max(sy(r[2]), sy(r[4]))
      x1, x2 = math.max(1, x1), math.min(W, x2)
      y1, y2 = math.max(top, y1), math.min(bottom - 1, y2)
      if x2 >= x1 and y2 >= y1 then fill(x1, y1, x2 - x1 + 1, y2 - y1 + 1, colors.gray) end
    end
    if db.marker then
      local my = sy(db.marker.z)
      if my >= top and my <= bottom - 1 then put(sx(db.marker.x), my, "+", colors.magenta, colors.black) end
    end
    if D then put(sx(D.x), sy(D.z), "D", colors.black, colors.orange) end
    local legend = "1:" .. scale .. "  N is up  D=depot +=marker  "
    for i, id in ipairs(ids) do
      local t = db.turtles[id]
      local st = t.st
      local ch = i <= 9 and tostring(i) or string.char(55 + i)
      if st and st.pos then
        local yy = sy(st.pos.z)
        if yy >= top and yy <= bottom - 1 then put(sx(st.pos.x), yy, ch, colors.black, stateColor(stateOf(t))) end
        legend = legend .. ch .. "=" .. t.name .. "(y" .. st.pos.y .. ") "
      end
    end
    fill(1, bottom, W, 1, colors.gray)
    put(2, bottom, legend, colors.white, colors.gray)
  end, true
end

-- ---------- ores tab ----------
local function oresScreen()
  return {}, function(y)
    local maxN = 1
    for _, n in pairs(db.totals) do maxN = math.max(maxN, n) end
    local nw = narrow()
    local showNote = CW >= 70
    local lw, yw = nw and 10 or 12, nw and 5 or 8
    local barW = CW - 2 - lw - yw - 8 - 8 - (showNote and 30 or 0)
    if not nw then barW = math.max(6, barW) end
    put(2, y, pad("ORE", lw) .. pad(nw and "Y" or "BEST Y", yw) .. (nw and "MINED" or "MINED BY THE FLEET"), colors.lightGray)
    y = y + 1
    local function row(label, col, yv, n, key)
      local c = col == colors.gray and colors.lightGray or col
      put(2, y, pad(label, lw), c)
      put(2 + lw, y, pad(yv, yw), yv == "-" and colors.gray or colors.white)
      local x = 2 + lw + yw
      if barW >= 4 then bar(x, y, barW, n / maxN, c, colors.black); x = x + barW + 1 end
      put(x, y, pad(tostring(n), 7), colors.white)
      if showNote and key then put(x + 8, y, (oreByKey(key) or {}).note or "", colors.gray) end
      if key then btn("mine", CW - 6, y, 6, "Mine", colors.green, colors.white, key) end
      y = y + 1
    end
    local known = {}
    for _, o in ipairs(ORES) do
      known[o.label] = true
      row(o.label, o.col, tostring(o.y), db.totals[o.label] or 0, o.key)
    end
    for label, n in pairs(db.totals) do
      if not known[label] then row(label, colors.white, "-", n, nil) end
    end
    para(2, y + 1, "Tap Mine to start a branch mine at that ore's best Y level.", colors.gray)
  end
end

-- ---------- log tab ----------
local function logScreen()
  return {}, function(y)
    if #db.log == 0 then put(2, y + 1, "Nothing logged yet.", colors.gray) return end
    for _, e in ipairs(db.log) do
      put(2, y, pad(e.t, 6), colors.gray)
      y = para(9, y, e.text, e.col or colors.white, CW - 9)
    end
  end
end

-- ---------- form widgets (wizard + settings) ----------
-- wide screens: label left, controls on the right. Narrow: label, then controls underneath.
local function formArea(y, label)
  if CW >= 50 then
    put(2, y, pad(label, CW - 33), colors.lightGray)
    return CW - 31, 31, y, y + 1
  end
  y = para(2, y, label, colors.lightGray, CW - 2)
  return 3, CW - 3, y, y + 1
end
local function numRow(y, label, obj, k, s1, s2, mn, mx, suffix)
  local x, aw, cy, ny = formArea(y, label)
  local m2, m1, p1, p2 = "-" .. s2, "-" .. s1, "+" .. s1, "+" .. s2
  local w2, w1 = #m2 + 1, #m1 + 1
  local vw = aw - 2 * w2 - 2 * w1 - 4
  if vw < 5 then m2, m1, p1, p2, w2, w1 = "<<", "<", ">", ">>", 3, 3; vw = aw - 16 end
  local function b(bx, w, lab, d) btn("num", bx, cy, w, lab, colors.gray, colors.white, { obj = obj, k = k, d = d, mn = mn, mx = mx }) end
  b(x, w2, m2, -s2)
  b(x + w2 + 1, w1, m1, -s1)
  put(x + w2 + w1 + 2, cy, center(tostring(obj[k]) .. (suffix or ""), vw), colors.white)
  b(x + w2 + w1 + vw + 3, w1, p1, s1)
  b(x + w2 + 2 * w1 + vw + 4, w2, p2, s2)
  return ny
end
local function choiceRow(y, label, obj, k, opts, names)
  local x, aw, cy, ny = formArea(y, label)
  local idx = 1
  for i, o in ipairs(opts) do if o == obj[k] then idx = i end end
  btn("choice", x, cy, 4, "<", colors.gray, colors.white, { obj = obj, k = k, opts = opts, d = -1 })
  put(x + 5, cy, center(names[idx] or tostring(obj[k]), aw - 10), colors.white)
  btn("choice", x + aw - 4, cy, 4, ">", colors.gray, colors.white, { obj = obj, k = k, opts = opts, d = 1 })
  return ny
end
local function toggleRow(y, label, obj, k)
  local x, aw, cy, ny = formArea(y, label)
  btn("toggle", x, cy, aw, obj[k] and "ON" or "OFF", obj[k] and colors.green or colors.red, colors.white, { obj = obj, k = k })
  return ny
end

-- ---------- job wizard ----------
local ORE_KEYS, ORE_NAMES = { "all" }, { "All ores" }
for _, o in ipairs(ORES) do ORE_KEYS[#ORE_KEYS + 1] = o.key; ORE_NAMES[#ORE_NAMES + 1] = o.label .. " (Y " .. o.y .. ")" end

local function isKind(...)
  local kinds = { ... }
  return function(f) for _, k in ipairs(kinds) do if f.kind == k then return true end end return false end
end
local FIELDS = {
  { k = "kind", label = "Job type", t = "choice", opts = { "branch", "quarry", "tunnel", "room" }, names = { "Branch mine", "Quarry", "Tunnel", "Room (2 corners)" } },
  { t = "corner", which = "a", label = "Corner 1 (e.g. top corner)", show = isKind("room") },
  { k = "ax", label = "  Corner 1 X", t = "num", s1 = 1, s2 = 16, mn = -30000000, mx = 30000000, show = isKind("room") },
  { k = "ay", label = "  Corner 1 Y", t = "num", s1 = 1, s2 = 10, mn = -64, mx = 319, show = isKind("room") },
  { k = "az", label = "  Corner 1 Z", t = "num", s1 = 1, s2 = 16, mn = -30000000, mx = 30000000, show = isKind("room") },
  { t = "corner", which = "b", label = "Corner 2 (the opposite bottom corner)", show = isKind("room") },
  { k = "bx", label = "  Corner 2 X", t = "num", s1 = 1, s2 = 16, mn = -30000000, mx = 30000000, show = isKind("room") },
  { k = "by", label = "  Corner 2 Y", t = "num", s1 = 1, s2 = 10, mn = -64, mx = 319, show = isKind("room") },
  { k = "bz", label = "  Corner 2 Z", t = "num", s1 = 1, s2 = 16, mn = -30000000, mx = 30000000, show = isKind("room") },
  { k = "target", label = "Target ore", t = "choice", opts = ORE_KEYS, names = ORE_NAMES, show = isKind("branch") },
  { k = "y", label = "Mining Y level", t = "num", s1 = 1, s2 = 10, mn = -59, mx = 319, show = isKind("branch") },
  { k = "y", label = "Floor Y level", t = "num", s1 = 1, s2 = 10, mn = -59, mx = 319, show = isKind("tunnel") },
  { k = "topY", label = "Top Y", t = "num", s1 = 1, s2 = 10, mn = -59, mx = 319, show = isKind("quarry") },
  { k = "bottomY", label = "Bottom Y", t = "num", s1 = 1, s2 = 10, mn = -59, mx = 319, show = isKind("quarry") },
  { k = "dir", label = "Direction", t = "choice", opts = { 0, 1, 2, 3 }, names = { "North", "East", "South", "West" }, show = function(f) return f.kind ~= "room" end },
  { k = "startMode", label = "Start point", t = "choice", opts = { "depot", "marker" }, names = { "Depot + distance", "Pocket marker" }, show = function(f) return f.kind ~= "room" end },
  { k = "dist", label = "Distance from depot", t = "num", s1 = 4, s2 = 32, mn = 3, mx = 5000, show = function(f) return f.startMode == "depot" and f.kind ~= "room" end },
  { k = "mainLen", label = "Main tunnel length", t = "num", s1 = 4, s2 = 16, mn = 4, mx = 2000, show = isKind("branch") },
  { k = "branchLen", label = "Branch length", t = "num", s1 = 1, s2 = 8, mn = 1, mx = 256, show = isKind("branch") },
  { k = "spacing", label = "Branch spacing", t = "num", s1 = 1, s2 = 2, mn = 2, mx = 16, show = isKind("branch") },
  { k = "sides", label = "Branch sides", t = "choice", opts = { "both", "left", "right" }, names = { "Both sides", "Left only", "Right only" }, show = isKind("branch") },
  { k = "walls", label = "Scan walls for ores", t = "toggle", show = isKind("branch") },
  { k = "vein", label = "Follow ore veins", t = "toggle", show = isKind("branch") },
  { k = "tall", label = "2-high tunnels (walkable)", t = "toggle", show = isKind("branch") },
  { k = "length", label = "Length", t = "num", s1 = 1, s2 = 16, mn = 1, mx = 1000, show = isKind("quarry", "tunnel") },
  { k = "width", label = "Width (to the right)", t = "num", s1 = 1, s2 = 8, mn = 1, mx = 256, show = isKind("quarry", "tunnel") },
  { k = "height", label = "Height", t = "num", s1 = 1, s2 = 4, mn = 1, mx = 64, show = isKind("tunnel") },
  { k = "turtles", label = "Turtles to use", t = "num", s1 = 1, s2 = 5, mn = 1, mx = 64, show = function(f) return f.kind ~= "tunnel" and not f.only end },
}

local function wizardScreen()
  local f = ui.wiz
  local footer = { { "wcancel", "Cancel", colors.red }, { "wlaunch", "LAUNCH", colors.green } }
  return footer, function(y)
    local title = f.only and ("NEW JOB for " .. (db.turtles[f.only] and db.turtles[f.only].name or "?")) or "NEW JOB"
    put(2, y, title, colors.orange)
    local moves, travel = estimate(f)
    local n = (f.kind == "tunnel" or f.only) and 1 or f.turtles
    local est = string.format("Estimate: ~%d blocks each, ~%d fuel (%d coal) per turtle", math.floor(moves), math.floor(moves + travel), math.ceil((moves + travel) / 80))
    if n > 1 then est = est .. ", " .. n .. " turtles" end
    y = para(2, y + 1, est, colors.lightGray) + 1
    for _, fd in ipairs(FIELDS) do
      if not fd.show or fd.show(f) then
        if fd.t == "corner" then
          local x, aw, cy, ny = formArea(y, fd.label)
          local hw = math.floor((aw - 1) / 2)
          btn("corner", x, cy, hw, "Use marker", db.marker and colors.blue or colors.gray, colors.white, { which = fd.which, src = "marker" })
          btn("corner", x + hw + 1, cy, aw - hw - 1, "Use depot", colors.gray, colors.white, { which = fd.which, src = "depot" })
          y = ny
        elseif fd.t == "num" then y = numRow(y, fd.label, f, fd.k, fd.s1, fd.s2, fd.mn, fd.mx)
        elseif fd.t == "choice" then y = choiceRow(y, fd.label, f, fd.k, fd.opts, fd.names)
        else y = toggleRow(y, fd.label, f, fd.k) end
      end
    end
  end
end

-- ---------- settings tab ----------
local function settingsScreen()
  return {}, function(y)
    local c = db.cfg
    y = kv(y, "Depot", c.dock and (c.dock.x .. ", " .. c.dock.y .. ", " .. c.dock.z) or "NOT SET (PC: depot x y z)", c.dock and colors.white or colors.red)
    y = kv(y, "Marker", db.marker and (db.marker.x .. ", " .. db.marker.y .. ", " .. db.marker.z) or "none")
    y = y + 1
    y = choiceRow(y, "Screen text size", c, "uiScale", SCALES, SCALE_NAMES)
    if (c.uiScale or 0) ~= 0 and ui.scaleUsed ~= c.uiScale then
      y = para(3, y, "Too big for this monitor - using " .. tostring(ui.scaleUsed), colors.orange)
    end
    y = numRow(y, "Fuel reserve (extra fuel kept to get home)", c, "reserve", 50, 500, 100, 20000)
    y = numRow(y, "Refuel up to (at the depot)", c, "refuelTarget", 500, 5000, 500, 100000)
    y = toggleRow(y, "Burn coal the turtles mine", c, "burnCoal")
    y = toggleRow(y, "Collect lava for fuel (needs a bucket)", c, "lavaRefuel")
    y = y + 1
    put(2, y, "Software", colors.orange); y = y + 1
    local vers, order = {}, {}
    for _, t in pairs(db.turtles) do
      local v = (t.st and t.st.version) or "old"
      if not vers[v] then vers[v] = 0; order[#order + 1] = v end
      vers[v] = vers[v] + 1
    end
    table.sort(order)
    local parts = {}
    for _, v in ipairs(order) do parts[#parts + 1] = vers[v] .. " on " .. (v == "old" and "old code" or ("v" .. v)) end
    y = kv(y, "Miners", #parts > 0 and table.concat(parts, ", ") or "none yet")
    y = kv(y, "Latest", ui.latest and ("v" .. ui.latest) or "tap Check for updates", ui.latest and colors.lime or colors.gray)
    y = kv(y, "This room", "v" .. VERSION .. ((ui.latestControl and ui.latestControl ~= VERSION) and ("  (v" .. ui.latestControl .. " out)") or ""))
    if vers.old then
      y = para(2, y, "Miners on old code can't update remotely yet. On each one, once: wget run " .. REPO .. "install.lua miner", colors.orange)
    end
    local b = { { "checkupd", "Check for updates", colors.gray }, { "updminers", "Update all miners", colors.green },
                { "updcontrol", "Update control room", colors.blue } }
    local per = (CW >= 66) and 3 or 1
    local bw = math.floor((CW - 1 - (per - 1)) / per)
    for i, it in ipairs(b) do
      local col = (i - 1) % per
      btn(it[1], 2 + col * (bw + 1), y, bw, it[2], it[3], colors.white)
      if col == per - 1 or i == #b then y = y + 1 end
    end
    y = para(2, y + 1, "Junk (thrown away while mining) - tap to remove. Add on PC: junk add <id>", colors.lightGray)
    local names = {}
    for name in pairs(c.junk) do names[#names + 1] = name end
    table.sort(names)
    local colW = math.min(28, CW - 1)
    local ncol = math.max(1, math.floor((CW - 1) / colW))
    for i, name in ipairs(names) do
      local cx = 2 + ((i - 1) % ncol) * colW
      local cy = y + math.floor((i - 1) / ncol)
      put(cx, cy, "x", colors.white, colors.red)
      put(cx + 2, cy, pad((name:gsub("^minecraft:", "")), colW - 3), colors.white)
      hit("junkdel", cx, cy, colW - 1, name)
    end
  end
end

local SCREENS = { fleet = fleetScreen, jobs = jobsScreen, map = mapScreen, ores = oresScreen, log = logScreen, settings = settingsScreen }

-- ---------- yes/no box ----------
local function drawConfirm()
  local c = ui.confirm
  hits = {}
  local bw = math.min(W - 2, 44)
  local lines = wrap(c.text, bw - 4)
  local bh = #lines + 4
  local x = math.floor((W - bw) / 2) + 1
  local y = math.max(1, math.floor((H - bh) / 2) + 1)
  fill(x, y, bw, bh, colors.gray)
  for i, l in ipairs(lines) do put(x + 2, y + i, l, colors.white, colors.gray) end
  local hw = math.floor((bw - 6) / 2)
  btn("cno", x + 2, y + bh - 2, hw, "No", colors.lightGray, colors.black)
  btn("cyes", x + bw - 2 - hw, y + bh - 2, hw, c.yesLabel or "Yes", colors.red, colors.white)
end

local function draw()
  if not mon then return end
  hits = {}
  CW = W
  mon.setBackgroundColor(colors.black)
  mon.clear()
  local top = drawHeader() + 1
  if ui.detail and not db.turtles[ui.detail] then ui.detail = nil end
  local footer, content, fixed
  if ui.wiz then footer, content, fixed = wizardScreen()
  elseif ui.detail then footer, content, fixed = detailScreen()
  else footer, content, fixed = (SCREENS[ui.tab] or fleetScreen)() end
  local _, frows = layoutRows(footer)
  local bottom = H - frows
  if fixed then content(top, bottom) else scrollArea(top, bottom, content) end
  drawFooter(footer)
  if ui.toast and now() < ui.toastUntil then
    fill(1, bottom, W, 1, ui.toast.col)
    put(2, bottom, ui.toast.text, colors.white, ui.toast.col)
  end
  if ui.confirm then drawConfirm() end
end

local function screenKey() return (ui.wiz and "wiz") or (ui.detail and ("d" .. ui.detail)) or ui.tab end

local function askCancelAll()
  ui.confirm = {
    text = "Cancel EVERY turtle's job? They stop mining and come home to the depot.",
    yesLabel = "Cancel all",
    yes = function()
      for id in pairs(db.turtles) do sendCmd(id, "cancel") end
      addLog("All jobs cancelled", colors.orange)
      toast("Cancelled all jobs", true)
    end,
  }
end

local function onTouch(x, y)
  local h
  for i = #hits, 1, -1 do
    local c = hits[i]
    if y == c.y and x >= c.x1 and x <= c.x2 then h = c break end
  end
  if not h then return end
  local before = screenKey()
  local d = h.data
  if h.id == "cyes" then local c = ui.confirm; ui.confirm = nil; c.yes()
  elseif h.id == "cno" then ui.confirm = nil
  elseif h.id == "scroll" then ui.scroll = math.max(0, ui.scroll + d)
  elseif h.id == "tab" then ui.tab, ui.detail, ui.wiz = d, nil, nil
  elseif h.id == "turtle" then ui.detail = d
  elseif h.id == "back" then ui.detail = nil
  elseif h.id == "cmdall" then
    for id in pairs(db.turtles) do sendCmd(id, d) end
    toast("Sent '" .. d .. "' to all turtles", true)
  elseif h.id == "cancelall" then askCancelAll()
  elseif h.id == "checkupd" then
    local body, err = fetch(MINER_URL)
    ui.latest = versionOf(body)
    ui.latestControl = versionOf(fetch(CONTROL_URL))
    if ui.latest then toast("Latest miner code is v" .. ui.latest, true) else toast("Couldn't check: " .. tostring(err), false) end
  elseif h.id == "updminers" then
    local n = 0
    for _, t in pairs(db.turtles) do if online(t) then n = n + 1 end end
    ui.confirm = {
      text = "Update all " .. n .. " online miners to the newest code from GitHub? Each one restarts and carries on where it was.",
      yesLabel = "Update all",
      yes = function()
        for id, t in pairs(db.turtles) do if online(t) then sendCmd(id, "update", { url = MINER_URL }) end end
        addLog("Sent update to " .. n .. " miners", colors.lightBlue)
        toast("Update sent to " .. n .. " miners", true)
      end,
    }
  elseif h.id == "updcontrol" then
    ui.confirm = {
      text = "Download the newest control room program from GitHub and restart? Your turtles, jobs and settings are kept.",
      yesLabel = "Update",
      yes = function()
        local body, err = fetch(CONTROL_URL)
        if not body or not body:find("FLEET CONTROL", 1, true) or not load(body) then
          toast("Update failed: " .. tostring(err or "bad download"), false) return
        end
        local prog = (shell and shell.getRunningProgram()) or "startup.lua"
        local f = fs.open(prog .. ".new", "w"); f.write(body); f.close()
        if fs.exists(prog) then fs.delete(prog) end
        fs.move(prog .. ".new", prog)
        addLog("Control room updated to v" .. (versionOf(body) or "?") .. " - restarting", colors.lime)
        saveDb()
        os.reboot()
      end,
    }
  elseif h.id == "tcmd" then
    sendCmd(ui.detail, d)
    toast("Sent '" .. d .. "' to " .. db.turtles[ui.detail].name, true)
  elseif h.id == "newjob" then ui.wiz = newWizard()
  elseif h.id == "tjob" then ui.wiz = newWizard({ only = ui.detail })
  elseif h.id == "mine" then ui.wiz = newWizard({ kind = "branch", target = d })
  elseif h.id == "wcancel" then ui.wiz = nil
  elseif h.id == "wlaunch" then
    local ok, msg = launch(ui.wiz)
    toast(msg, ok)
    if ok then ui.wiz, ui.detail, ui.tab = nil, nil, "jobs" end
  elseif h.id == "corner" then
    local p = (d.src == "marker") and db.marker or db.cfg.dock
    if not p then toast(d.src == "marker" and "No pocket marker yet - set one with the pocket remote" or "Set the depot first", false)
    elseif ui.wiz then
      ui.wiz[d.which .. "x"], ui.wiz[d.which .. "y"], ui.wiz[d.which .. "z"] = p.x, p.y, p.z
      toast("Corner " .. (d.which == "a" and 1 or 2) .. " set to " .. p.x .. ", " .. p.y .. ", " .. p.z, true)
    end
  elseif h.id == "num" then
    d.obj[d.k] = math.max(d.mn, math.min(d.mx, d.obj[d.k] + d.d))
    if d.obj == db.cfg then ui.cfgDirty = true end
  elseif h.id == "choice" then
    local idx = 1
    for i, o in ipairs(d.opts) do if o == d.obj[d.k] then idx = i end end
    idx = (idx - 1 + d.d) % #d.opts + 1
    d.obj[d.k] = d.opts[idx]
    if d.obj == ui.wiz and d.k == "target" and d.obj.target ~= "all" then d.obj.y = oreByKey(d.obj.target).y end
    if d.obj == db.cfg then
      ui.cfgDirty = true
      if d.k == "uiScale" then saveDb(); setupMonitor() end
    end
  elseif h.id == "toggle" then
    d.obj[d.k] = not d.obj[d.k]
    if d.obj == db.cfg then ui.cfgDirty = true end
  elseif h.id == "junkdel" then
    db.cfg.junk[d] = nil
    ui.cfgDirty = true
    toast("Removed " .. d .. " from junk", true)
  end
  if screenKey() ~= before then ui.scroll = 0 end
end

local function uiLoop()
  setupMonitor()
  local timer = os.startTimer(1)
  local ticks = 0
  while true do
    draw()
    local ev, a, b, c = os.pullEvent()
    if ev == "monitor_touch" then onTouch(b, c)
    elseif ev == "monitor_resize" then setupMonitor()
    elseif ev == "timer" and a == timer then
      timer = os.startTimer(1)
      ticks = ticks + 1
      if ui.cfgDirty then ui.cfgDirty = false; saveDb(); pushCfg() end
      if ticks % 30 == 0 then saveDb() end
    end
  end
end


-- =====================================================
--  CONSOLE (typed on the control computer)
-- =====================================================
local function color(c) if term.isColor() then term.setTextColor(c) end end
local commands, help = {}, {
  { "depot <x> <y> <z>", "set the dock position (where turtles unload)" },
  { "junk add <id> / junk del <id> / junk list", "edit the junk list" },
  { "marker <x> <y> <z>", "set the job marker by hand" },
  { "room <x1> <y1> <z1> <x2> <y2> <z2> [turtles]", "dig out a room between two corners (opens the job on the monitor)" },
  { "rename <id> <name>", "rename a turtle" },
  { "pause|resume|recall|refuel|cancel <id|all>", "control turtles" },
  { "forget <id>", "remove a turtle from the fleet" },
  { "list", "list turtles" },
  { "resetstats", "clear the ore totals" },
  { "update miners | update <id>", "send the newest miner code from GitHub" },
}
function commands.help()
  for _, h in ipairs(help) do color(colors.yellow); print(h[1]); color(colors.lightGray); print("   " .. h[2]) end
  color(colors.white)
end
function commands.depot(x, y, z)
  x, y, z = tonumber(x), tonumber(y), tonumber(z)
  if not (x and y and z) then error("Usage: depot <x> <y> <z>  (the dock block's coordinates)", 0) end
  db.cfg.dock = { x = x, y = y, z = z }
  saveDb(); pushCfg()
  addLog("Depot set to " .. x .. "," .. y .. "," .. z, colors.lime)
  print("Depot set. Turtles will use it now.")
end
function commands.junk(sub, id)
  if sub == "list" then
    for name in pairs(db.cfg.junk) do print(name) end
  elseif (sub == "add" or sub == "del") and id then
    if not id:find(":") then id = "minecraft:" .. id end
    db.cfg.junk[id] = (sub == "add") or nil
    saveDb(); pushCfg()
    print((sub == "add" and "Added " or "Removed ") .. id)
  else error("Usage: junk add <id> | junk del <id> | junk list", 0) end
end
function commands.marker(x, y, z)
  x, y, z = tonumber(x), tonumber(y), tonumber(z)
  if not (x and y and z) then error("Usage: marker <x> <y> <z>", 0) end
  db.marker = { x = x, y = y, z = z }
  saveDb(); print("Marker set.")
end
function commands.room(...)
  local a = {}
  for i, v in ipairs({ ... }) do a[i] = tonumber(v) end
  if #a < 6 or not (a[1] and a[2] and a[3] and a[4] and a[5] and a[6]) then
    error("Usage: room <x1> <y1> <z1> <x2> <y2> <z2> [turtles]", 0)
  end
  ui.wiz = newWizard({ kind = "room", ax = a[1], ay = a[2], az = a[3], bx = a[4], by = a[5], bz = a[6], turtles = a[7] or 1 })
  ui.detail, ui.scroll = nil, 0
  local f = ui.wiz
  print("Room " .. (math.abs(f.ax - f.bx) + 1) .. " x " .. (math.abs(f.az - f.bz) + 1) .. " wide, " .. (math.abs(f.ay - f.by) + 1) .. " high.")
  print("Check it on the monitor and press LAUNCH.")
end
function commands.rename(id, ...)
  id = tonumber(id)
  local name = table.concat({ ... }, " ")
  if not (id and db.turtles[id] and name ~= "") then error("Usage: rename <id> <name>", 0) end
  db.turtles[id].name = name
  sendCmd(id, "rename", { name = name })
  saveDb(); print("Renamed.")
end
local function control(cmd, target)
  if target == "all" then for id in pairs(db.turtles) do sendCmd(id, cmd) end print("Sent to all.") return end
  local id = tonumber(target)
  if not (id and db.turtles[id]) then error("Usage: " .. cmd .. " <id|all>", 0) end
  sendCmd(id, cmd); print("Sent.")
end
for _, c in ipairs({ "pause", "resume", "recall", "refuel", "cancel" }) do commands[c] = function(t) control(c, t) end end
function commands.forget(id)
  id = tonumber(id)
  if not (id and db.turtles[id]) then error("Usage: forget <id>", 0) end
  db.turtles[id] = nil
  saveDb(); print("Removed turtle #" .. id .. " (its lane is free again).")
end
function commands.list()
  for _, id in ipairs(sortedIds()) do
    local t = db.turtles[id]
    print(string.format("#%d %-12s lane %d  %s", id, t.name, t.lane, stateOf(t)))
  end
end
function commands.resetstats() db.totals = {}; saveDb(); print("Ore totals cleared.") end
function commands.update(target)
  if target == "miners" or target == "all" then
    for id in pairs(db.turtles) do sendCmd(id, "update", { url = MINER_URL }) end
    print("Update sent to all miners.")
  elseif tonumber(target) and db.turtles[tonumber(target)] then
    sendCmd(tonumber(target), "update", { url = MINER_URL }); print("Update sent.")
  else error("Usage: update miners | update <id>", 0) end
end

local function console()
  term.clear(); term.setCursorPos(1, 1)
  color(colors.orange); print("=== FLEET CONTROL v" .. VERSION .. " ===")
  color(colors.lightGray); print("Computer ID " .. os.getComputerID() .. " | type 'help' for commands")
  if not db.cfg.dock then color(colors.red); print("First: set the depot with  depot <x> <y> <z>") end
  color(colors.white)
  local hist = {}
  while true do
    color(colors.orange); write("fleet> "); color(colors.white)
    local line = read(nil, hist)
    if line ~= "" then hist[#hist + 1] = line end
    local args = {}
    for w in line:gmatch("%S+") do args[#args + 1] = w end
    local cmd = table.remove(args, 1)
    if cmd then
      local f = commands[cmd:lower()]
      if f then
        local ok, err = pcall(f, table.unpack(args))
        if not ok then color(colors.red); print(err); color(colors.white) end
      else print("Unknown command. Type 'help'.") end
    end
  end
end

-- ---------- start ----------
loadDb()
local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
if not modem then error("Attach an ender modem to the control computer!", 0) end
rednet.open(peripheral.getName(modem))
rednet.host(PROTOCOL, "control")
addLog("Control room started", colors.lime)
pushCfg()
parallel.waitForAny(netLoop, uiLoop, console)
