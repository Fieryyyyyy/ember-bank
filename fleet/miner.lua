-- =====================================================
--  FLEET MINER - turtle program
--  Install on every MINING TURTLE (with an ender modem) as startup.lua
--  The control room tells it what to do - nothing to edit here
--  unless auto-discovery fails (then set CONTROL_ID).
-- =====================================================

local CONTROL_ID = nil          -- control computer's ID (shown on its screen). nil = find it automatically
local PROTOCOL   = "fleetmine"
local STATE_FILE = "/miner.state"
local VERSION    = "2.1"
local UPDATE_URL = "https://raw.githubusercontent.com/Fieryyyyyy/ember-bank/main/fleet/miner.lua"
local PROGRAM    = (shell and shell.getRunningProgram()) or "startup.lua"

-- facing: 0 = north (-z), 1 = east (+x), 2 = south (+z), 3 = west (-x)
local DX = { [0] = 0, 1, 0, -1 }
local DZ = { [0] = -1, 0, 1, 0 }
local DIR_NAMES = { [0] = "north", "east", "south", "west" }

-- ---------- saved state (survives reboots / chunk unloads) ----------
local S = {
  pos = nil, facing = nil, lane = nil,
  job = nil, step = 1, mode = "idle",      -- mode: idle | job | recalled
  paused = false, returnTo = nil,
  stats = { blocks = 0, ores = {} },
}
local cfg = { ores = {}, junk = {}, reserve = 300, refuelTarget = 6000, burnCoal = true, lavaRefuel = true }

local function save()
  local f = fs.open(STATE_FILE .. ".tmp", "w")
  f.write(textutils.serialize({ S = S, cfg = cfg }))
  f.close()
  if fs.exists(STATE_FILE) then fs.delete(STATE_FILE) end
  fs.move(STATE_FILE .. ".tmp", STATE_FILE)
end

local function load()
  local path = (fs.exists(STATE_FILE) and STATE_FILE) or (fs.exists(STATE_FILE .. ".tmp") and STATE_FILE .. ".tmp")
  if not path then return end
  local f = fs.open(path, "r")
  local t = textutils.unserialize(f.readAll())
  f.close()
  if type(t) == "table" then
    if type(t.S) == "table" then for k, v in pairs(t.S) do S[k] = v end end
    if type(t.cfg) == "table" then cfg = t.cfg end
  end
end

-- ---------- runtime ----------
local status, alert = "Starting", nil
local flags = { recall = false, cancel = false, refuel = false }
local found = {}                   -- ores found since last report
local wps, wpLen, wpTotal = nil, nil, 0
local BLOCKED = "Something is in my way - waiting"

local function posStr()
  if not S.pos then return "?" end
  return S.pos.x .. "," .. S.pos.y .. "," .. S.pos.z
end
local function samePos(a, b) return a and b and a.x == b.x and a.y == b.y and a.z == b.z end

-- ---------- network ----------
local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
if not modem then error("This turtle needs an ender modem (craft it onto the turtle)!", 0) end
rednet.open(peripheral.getName(modem))
local serverId = CONTROL_ID

local function send(msg)
  if not serverId then serverId = rednet.lookup(PROTOCOL, "control") end
  if serverId then rednet.send(serverId, msg, PROTOCOL) end
end

local function freeSlots()
  local n = 0
  for i = 1, 16 do if turtle.getItemCount(i) == 0 then n = n + 1 end end
  return n
end

local function progress()
  if not wps or wpTotal == 0 then return nil end
  return math.min(1, (wpLen[S.step - 1] or 0) / wpTotal)
end

local function sendStatus()
  local f = found
  found = {}
  send({
    type = "status", label = os.getComputerLabel(), pos = S.pos, facing = S.facing, lane = S.lane,
    fuel = turtle.getFuelLevel(), fuelLimit = turtle.getFuelLimit(),
    state = status, alert = alert, job = S.job, mode = S.mode, paused = S.paused,
    progress = progress(), inv = 16 - freeSlots(), stats = S.stats, found = f, stuck = S.lastStuck,
    version = VERSION,
  })
end

local function drawScreen()
  term.setBackgroundColor(colors.black); term.clear(); term.setCursorPos(1, 1)
  local c = term.isColor()
  if c then term.setTextColor(colors.orange) end
  print("== FLEET MINER: " .. (os.getComputerLabel() or "?") .. " ==")
  if c then term.setTextColor(colors.white) end
  print("State : " .. status .. (S.paused and " (PAUSED)" or ""))
  print("Fuel  : " .. tostring(turtle.getFuelLevel()))
  print("Pos   : " .. posStr() .. "  lane " .. tostring(S.lane))
  if S.job then
    local p = progress()
    print("Job   : " .. (S.job.desc or S.job.kind) .. (p and string.format("  %d%%", math.floor(p * 100)) or ""))
  end
  print("Mined : " .. S.stats.blocks .. " blocks")
  if alert then
    if c then term.setTextColor(colors.red) end
    print(); print(alert)
  end
  if c then term.setTextColor(colors.lightGray) end
  print(); print("Controlled from the control room.")
end

local updateWanted, rebootPending = nil, nil
local function rebootIfPending()
  if rebootPending then save(); os.reboot() end
end

local function handle(msg)
  if msg.type == "welcome" or msg.type == "cfg" then
    if type(msg.cfg) == "table" then cfg = msg.cfg end
    if msg.lane then S.lane = msg.lane end
    save()
  elseif msg.type == "job" then
    if S.mode == "job" and S.job then send({ type = "log", text = (os.getComputerLabel() or "?") .. " is busy - new job refused" }) return end
    S.job, S.step, S.mode, S.returnTo, S.lastStuck = msg.job, 1, "job", nil, nil
    flags.recall, flags.cancel = false, false
    save()
  elseif msg.type == "cmd" then
    local c = msg.cmd
    if c == "pause" then S.paused = true
    elseif c == "resume" then
      S.paused = false; flags.recall = false
      if S.mode == "recalled" and S.job then S.mode = "job" end
    elseif c == "recall" then
      S.paused = false
      if S.mode == "job" then flags.recall = true end
    elseif c == "cancel" then
      S.paused = false
      flags.recall = false
      if S.mode == "job" then flags.cancel = true
      else S.job, S.mode, S.step, S.returnTo = nil, "idle", 1, nil end
    elseif c == "refuel" then
      S.paused = false
      flags.refuel = true
    elseif c == "rename" and type(msg.name) == "string" then
      os.setComputerLabel(msg.name)
    elseif c == "reboot" then
      os.reboot()
    elseif c == "update" then
      updateWanted = (type(msg.url) == "string" and msg.url) or UPDATE_URL
    end
    save()
    sendStatus()
  end
end

-- ---------- remote update (sent from the control room) ----------
local function selfUpdate(url)
  local function log(t) send({ type = "log", text = (os.getComputerLabel() or "?") .. ": " .. t }) end
  if not http then log("update failed - HTTP is off on this server") return end
  local res, err = http.get(url .. "?t=" .. os.epoch("utc"))
  if not res then log("update failed - " .. tostring(err)) return end
  local body = res.readAll(); res.close()
  if not body:find("FLEET MINER", 1, true) or not _G.load(body) then log("update failed - bad download") return end
  local newVer = body:match('local VERSION%s*=%s*"([^"]+)"') or "?"
  -- keep this turtle's CONTROL_ID setting
  local f = fs.open(PROGRAM, "r")
  local old = f and f.readAll() or ""
  if f then f.close() end
  local keep = old:match("\n(local CONTROL_ID[^\n]*)")
  if keep then body = body:gsub("\nlocal CONTROL_ID[^\n]*", function() return "\n" .. keep end, 1) end
  local w = fs.open(PROGRAM .. ".new", "w"); w.write(body); w.close()
  if fs.exists(PROGRAM) then fs.delete(PROGRAM) end
  fs.move(PROGRAM .. ".new", PROGRAM)
  log("updated v" .. VERSION .. " -> v" .. newVer .. ", restarting")
  rebootPending = os.clock()
end

local function netLoop()
  local timer = os.startTimer(1)
  while true do
    local ev, a, b, c = os.pullEvent()
    if ev == "timer" and a == timer then
      sendStatus(); drawScreen()
      timer = os.startTimer(3)
    elseif ev == "rednet_message" and c == PROTOCOL and type(b) == "table" and serverId and a == serverId then
      handle(b)
    end
    if updateWanted then
      local url = updateWanted
      updateWanted = nil
      selfUpdate(url)
    end
    -- restart on the next move; if the turtle is sitting waiting, restart anyway after 20s
    if rebootPending and os.clock() - rebootPending > 20 then save(); os.reboot() end
  end
end

-- ---------- block classification ----------
local function prettify(name)
  local s = name:gsub("^.-:", ""):gsub("deepslate_", ""):gsub("nether_", ""):gsub("_ore$", ""):gsub("_", " ")
  return (s:gsub("^%l", string.upper))
end

local function classify(name, tags)
  for _, o in ipairs(cfg.ores or {}) do
    if name:find(o.pat) then return o.key, o.label end
  end
  if (tags and tags["c:ores"]) or name:find("_ore$") or name == "minecraft:ancient_debris" then
    return name, prettify(name)
  end
end

local function isProtected(name)
  return name:find("^computercraft:") or name:find("chest") or name:find("barrel") or name:find("shulker")
end

local function recordOre(label)
  S.stats.ores[label] = (S.stats.ores[label] or 0) + 1
  local f = found[label] or { n = 0 }
  f.n = f.n + 1
  f.pos = { x = S.pos.x, y = S.pos.y, z = S.pos.z }
  found[label] = f
end

-- ---------- inventory & fuel ----------
local function dropJunk()
  for i = 1, 16 do
    local d = turtle.getItemDetail(i)
    if d and cfg.junk[d.name] then
      turtle.select(i)
      if not turtle.dropDown() then turtle.drop() end
    end
  end
  turtle.select(1)
end

local function fuelLevel()
  local f = turtle.getFuelLevel()
  if f == "unlimited" then return math.huge end
  return f
end

local function burnCoal()
  if not cfg.burnCoal or fuelLevel() >= (cfg.refuelTarget or 6000) then return end
  for i = 1, 16 do
    local d = turtle.getItemDetail(i)
    if d and (d.name == "minecraft:coal" or d.name == "minecraft:charcoal" or d.name == "minecraft:coal_block") then
      turtle.select(i); turtle.refuel()
    end
  end
  turtle.select(1)
end

local function refuelFromInventory()
  for i = 1, 16 do
    turtle.select(i)
    if turtle.refuel(0) then turtle.refuel() end
  end
  turtle.select(1)
end

local function outOfFuel()
  local prev = status
  status = "OUT OF FUEL"
  alert = "Out of fuel at " .. posStr() .. " - put fuel in my inventory"
  while true do
    refuelFromInventory()
    if fuelLevel() > 0 then alert = nil; status = prev; return end
    os.pullEvent("turtle_inventory")
  end
end

-- collect lava with a bucket for free fuel
local function lavaFuel(dir, data)
  if not (cfg.lavaRefuel and data.name == "minecraft:lava" and data.state and data.state.level == 0) then return end
  if fuelLevel() > turtle.getFuelLimit() - 1000 then return end
  for i = 1, 16 do
    local d = turtle.getItemDetail(i)
    if d and d.name == "minecraft:bucket" then
      turtle.select(i)
      local place = (dir == "up" and turtle.placeUp) or (dir == "down" and turtle.placeDown) or turtle.place
      if place() then turtle.refuel() end
      break
    end
  end
  turtle.select(1)
end

-- ---------- movement ----------
local MOVE    = { fwd = turtle.forward, up = turtle.up, down = turtle.down }
local DIG     = { fwd = turtle.dig, up = turtle.digUp, down = turtle.digDown }
local DETECT  = { fwd = turtle.detect, up = turtle.detectUp, down = turtle.detectDown }
local INSPECT = { fwd = turtle.inspect, up = turtle.inspectUp, down = turtle.inspectDown }
local ATTACK  = { fwd = turtle.attack, up = turtle.attackUp, down = turtle.attackDown }

local function turnRight() turtle.turnRight(); S.facing = (S.facing + 1) % 4; save() end
local function turnLeft() turtle.turnLeft(); S.facing = (S.facing + 3) % 4; save() end
local function turnTo(f)
  f = f % 4
  local d = (f - S.facing) % 4
  if d == 3 then turnLeft() else for _ = 1, d do turnRight() end end
end

-- dig the block in a direction (if any). Returns true if the space is now clear.
local function digDir(dir)
  if not DETECT[dir]() then
    if cfg.lavaRefuel then
      local ok, data = INSPECT[dir]()
      if ok then lavaFuel(dir, data) end
    end
    return true
  end
  local ok, data = INSPECT[dir]()
  local label
  if ok then
    if isProtected(data.name) then return false, "protected", data.name end
    if data.name == "minecraft:bedrock" then return false, "bedrock", data.name end
    local _
    _, label = classify(data.name, data.tags)
  end
  turtle.select(1)
  if not DIG[dir]() then return false, "undiggable", ok and data.name or nil end
  S.stats.blocks = S.stats.blocks + 1
  if label then recordOre(label) end
  if turtle.getItemCount(16) > 0 or freeSlots() <= 1 then dropJunk() end
  return true
end

local inJob, noDetour = false, 0     -- noDetour > 0 near the depot: wait for traffic, never dig around
local lastBlock = nil                -- what stopped the last failed move: { name, dir }

-- Cancel / Recall can interrupt a job at any move, even while it is waiting
local function abortCheck()
  if not inJob then return end
  if flags.cancel then flags.cancel = false; error({ abort = "cancel" }, 0) end
  if flags.recall then flags.recall = false; error({ abort = "recall" }, 0) end
end
local function isTurtle(name) return name ~= nil and name:find("^computercraft:turtle") ~= nil end

local function move(dir)
  local tries = 0
  rebootIfPending()
  while true do
    abortCheck()
    if S.paused then
      local prev = status
      status = "Paused"
      while S.paused do sleep(1) end
      status = prev
      abortCheck()
    end
    if fuelLevel() < 1 then outOfFuel() end
    if MOVE[dir]() then
      if dir == "fwd" then
        S.pos.x = S.pos.x + DX[S.facing]; S.pos.z = S.pos.z + DZ[S.facing]
      elseif dir == "up" then S.pos.y = S.pos.y + 1
      else S.pos.y = S.pos.y - 1 end
      if alert == BLOCKED then alert = nil end
      save()
      return true
    end
    if DETECT[dir]() then
      local ok, why, name = digDir(dir)
      if not ok then
        lastBlock = { name = name or "an unknown block", dir = dir, facing = S.facing }
        if not isTurtle(name) then return false end      -- bedrock, chests, unbreakable blocks...
        -- another turtle: wait for it to move along
        tries = tries + 1
        alert = BLOCKED
        if tries > (noDetour > 0 and 600 or 60) then return false end
        sleep(1)
      end
    else
      ATTACK[dir]()                 -- a mob is in the way
      tries = tries + 1
      if tries > 40 then
        alert = BLOCKED
        lastBlock = { name = "a mob or entity", dir = dir, facing = S.facing }
        return false
      end
      sleep(0.2)
    end
  end
end

local function back()
  if turtle.back() then
    S.pos.x = S.pos.x - DX[S.facing]; S.pos.z = S.pos.z - DZ[S.facing]
    save()
    return true
  end
  turnRight(); turnRight()
  local ok = move("fwd")
  turnRight(); turnRight()
  return ok
end

local function blockText()
  local b = lastBlock
  if not b then return "something" end
  local n = b.name:gsub("^minecraft:", "")
  n = n:gsub("_", " ")
  local where = (b.dir == "up" and "above") or (b.dir == "down" and "below") or ("ahead (" .. (DIR_NAMES[b.facing or S.facing] or "?") .. ")")
  return n .. " " .. where
end

-- report a problem to the control room log (not repeated more than every 30s)
local lastNote, lastNoteAt = nil, -100
local function noteStuck(text)
  S.lastStuck = text
  save()
  if text ~= lastNote or os.clock() - lastNoteAt > 30 then
    send({ type = "log", text = (os.getComputerLabel() or "?") .. ": " .. text })
    lastNote, lastNoteAt = text, os.clock()
  end
end

local function must(ok)
  if not ok then
    local msg = "Stuck at " .. posStr() .. ": " .. blockText() .. ", no way around"
    noteStuck(msg)
    error(msg, 0)
  end
end

-- world directions: 0-3 = north/east/south/west, 4 = up, 5 = down
local OPP = { [0] = 2, 3, 0, 1, 5, 4 }
local function stepW(d)
  if d == 4 then return move("up") elseif d == 5 then return move("down") end
  turnTo(d)
  return move("fwd")
end
local function sidesOf(d)
  if d >= 4 then return { 0, 1, 2, 3 } end
  return { 4, 5, (d + 3) % 4, (d + 1) % 4 }     -- over, under, left, right
end

-- something we can't dig is in the way: step to the side, go past it, step back onto the line.
-- Returns how many blocks we got along the line (0 = no way around).
local function detour(d, maxAdv)
  local blocker = lastBlock
  noteStuck("Blocked by " .. blockText() .. " at " .. posStr() .. " - going around")
  for _, side in ipairs(sidesOf(d)) do
    local trail = {}
    local function go(dd) if stepW(dd) then trail[#trail + 1] = dd return true end return false end
    if go(side) then
      for k = 1, maxAdv do
        if not go(d) then break end
        if go(OPP[side]) then return k end
      end
      for i = #trail, 1, -1 do                      -- that way did not work: back out again
        if not stepW(OPP[trail[i]]) then lastBlock = blocker; return 0 end
      end
    end
  end
  lastBlock = blocker               -- report the block that started it, not the last side tried
  return 0
end

-- one step towards a target (going around obstacles unless near the depot)
local function advance(d, remaining)
  if stepW(d) then return 1 end
  if noDetour > 0 then return 0 end
  return detour(d, remaining)
end
local function goAxis(get, target, posDir, negDir)
  while get() ~= target do
    local d = (target > get()) and posDir or negDir
    if advance(d, math.abs(target - get())) <= 0 then return false end
  end
  return true
end
local function goX(x) return goAxis(function() return S.pos.x end, x, 1, 3) end
local function goZ(z) return goAxis(function() return S.pos.z end, z, 2, 0) end
local function goY(y) return goAxis(function() return S.pos.y end, y, 4, 5) end

-- around the depot turtles queue for each other instead of digging detours
local function carefully(fn)
  noDetour = noDetour + 1
  local ok, err = pcall(fn)
  noDetour = noDetour - 1
  if not ok then error(err, 0) end
end

-- ---------- depot routes ----------
--   West of the dock = UP shaft (turtles coming home)
--   East of the dock = DOWN shaft (turtles leaving)
--   Each turtle travels underground on its own lane (Y level) so they never meet head on,
--   and parks under the drop-off chest at its lane's Y level.
local function laneY() return cfg.dock.y - 2 - S.lane end
local function parkPos() return { x = cfg.dock.x, y = laneY(), z = cfg.dock.z } end
local function isParked() return samePos(S.pos, parkPos()) end

local function goDock()
  local D, ly = cfg.dock, laneY()
  if samePos(S.pos, D) then return end
  status = "Returning"
  local inUpShaft = S.pos.x == D.x - 1 and S.pos.z == D.z and S.pos.y >= ly and S.pos.y <= D.y
  if not inUpShaft then
    must(goY(ly)); must(goX(D.x - 1)); must(goZ(D.z))
  end
  carefully(function()
    must(goY(D.y))
    status = "Docking"
    must(goX(D.x))   -- waits here if another turtle is using the dock
  end)
end

local function leaveDock()
  carefully(function()
    must(goX(cfg.dock.x + 1))
    must(goY(laneY()))
  end)
end

local function service()
  status = "Unloading"
  local keptBucket = false
  for i = 1, 16 do
    local d = turtle.getItemDetail(i)
    if d then
      local keep = cfg.lavaRefuel and d.name == "minecraft:bucket" and not keptBucket
      if keep then keptBucket = true
      else
        turtle.select(i)
        while turtle.getItemCount(i) > 0 and not turtle.dropDown() do
          status = "Drop chest FULL"; alert = "The drop-off chest is full!"
          sleep(5)
        end
      end
    end
  end
  if alert == "The drop-off chest is full!" then alert = nil end

  status = "Refueling"
  local target = math.min(cfg.refuelTarget or 6000, turtle.getFuelLimit())
  while true do
    local tries = 0
    while fuelLevel() < target and tries < 40 do
      tries = tries + 1
      turtle.select(16)
      if turtle.getItemCount(16) > 0 then turtle.dropDown() end
      if not turtle.suckUp(8) then break end
      if not turtle.refuel() then turtle.dropDown() end    -- not fuel: send to drop chest
      local d = turtle.getItemDetail(16)
      if d then
        if d.name == "minecraft:bucket" then
          if cfg.lavaRefuel and not keptBucket then
            keptBucket = true
            for s = 1, 15 do if turtle.getItemCount(s) == 0 then turtle.transferTo(s) break end end
          else turtle.dropDown() end
        else turtle.dropUp() end
      end
    end
    turtle.select(1)
    if fuelLevel() >= math.min(target, (cfg.reserve or 300) * 3) then break end
    status = "Waiting for fuel"; alert = "Fuel chest is empty! Add coal or lava buckets."
    sleep(10)
  end
  if alert == "Fuel chest is empty! Add coal or lava buckets." then alert = nil end
end

local function goPark()
  carefully(function() must(goX(cfg.dock.x)) end)
  status = "Idle"
end

local function goHomeAndPark()
  goDock(); service(); leaveDock(); goPark()
end

-- travel to any spot: straight down the shaft to the target's Y level first,
-- then across in X and Z. (Targets above the lane still go along the lane, then up.)
local function goTravel(t)
  local D, ly = cfg.dock, laneY()
  status = "Travelling"
  if samePos(S.pos, D) then leaveDock() end
  if isParked() then carefully(function() must(goX(D.x + 1)) end) end
  local near = math.abs(S.pos.x - t.x) + math.abs(S.pos.z - t.z) <= 32 and S.pos.y < ly and t.y < ly
  if near then
    must(goX(t.x)); must(goZ(t.z)); must(goY(t.y))
  elseif t.y < ly then
    must(goY(t.y)); must(goZ(t.z)); must(goX(t.x))
  else
    must(goY(ly)); must(goZ(t.z)); must(goX(t.x)); must(goY(t.y))
  end
end

local function homeDistance()
  local D, ly = cfg.dock, laneY()
  return math.abs(S.pos.y - ly) + math.abs(S.pos.x - (D.x - 1)) + math.abs(S.pos.z - D.z) + math.abs(D.y - ly) + 2
end

local function serviceTrip(reason)
  S.returnTo = { x = S.pos.x, y = S.pos.y, z = S.pos.z, f = S.facing }
  save()
  send({ type = "log", text = (os.getComputerLabel() or "?") .. " heading home: " .. reason })
  goDock(); service(); goTravel(S.returnTo); turnTo(S.returnTo.f)
  S.returnTo = nil
  save()
  status = "Mining"
end

local function checkpoint()
  if flags.cancel then flags.cancel = false; error({ abort = "cancel" }, 0) end
  if flags.recall then flags.recall = false; error({ abort = "recall" }, 0) end
  burnCoal()
  if flags.refuel then flags.refuel = false; serviceTrip("refuel requested") return end
  if fuelLevel() < homeDistance() + (cfg.reserve or 300) then serviceTrip("low fuel") return end
  if freeSlots() == 0 then
    dropJunk()
    if freeSlots() == 0 then serviceTrip("inventory full") end
  end
end

-- ---------- ore veins ----------
local veinDepth = 0
local function isTarget(ok, data)
  if not ok or not S.job.vein then return false end
  local key = classify(data.name, data.tags)
  if not key then return false end
  return S.job.target == "all" or key == S.job.target
end

local explore
local function vein(dir)
  if veinDepth >= 64 then return end
  veinDepth = veinDepth + 1
  if move(dir) then
    explore()
    if dir == "fwd" then back() elseif dir == "up" then move("down") else move("up") end
  end
  veinDepth = veinDepth - 1
end

explore = function()
  if isTarget(turtle.inspectUp()) then vein("up") end
  if isTarget(turtle.inspectDown()) then vein("down") end
  for _ = 1, 4 do
    if isTarget(turtle.inspect()) then vein("fwd") end
    turnRight()
  end
end

local function scanHere(walls)
  if not S.job.vein then return end
  if isTarget(turtle.inspectUp()) then vein("up") end
  if isTarget(turtle.inspectDown()) then vein("down") end
  if walls then
    turnLeft()
    if isTarget(turtle.inspect()) then vein("fwd") end
    turnRight(); turnRight()
    if isTarget(turtle.inspect()) then vein("fwd") end
    turnLeft()
  end
end

-- ---------- job paths ----------
local function addWp(list, x, y, z, o)
  o = o or {}
  list[#list + 1] = { x = x, y = y, z = z, up = o.up, down = o.down, scan = o.scan }
end

local function genBranch(j)
  local L = {}
  local d, left, right = j.dir, (j.dir + 3) % 4, (j.dir + 1) % 4
  addWp(L, j.x, j.y, j.z, { up = j.tall })
  local i = 0
  while i < j.mainLen do
    local nxt = math.min(i + j.spacing, j.mainLen)
    local mx, mz = j.x + DX[d] * nxt, j.z + DZ[d] * nxt
    addWp(L, mx, j.y, mz, { up = j.tall, scan = true })
    i = nxt
    if i % j.spacing == 0 then
      if j.sides ~= "right" then
        addWp(L, mx + DX[left] * j.branchLen, j.y, mz + DZ[left] * j.branchLen, { up = j.tall, scan = true })
        addWp(L, mx, j.y, mz)
      end
      if j.sides ~= "left" then
        addWp(L, mx + DX[right] * j.branchLen, j.y, mz + DZ[right] * j.branchLen, { up = j.tall, scan = true })
        addWp(L, mx, j.y, mz)
      end
    end
  end
  return L
end

-- dig out every block in a box, 3 layers per pass (dig up + down while moving)
local function genBox(j)
  local L = {}
  local minX, maxX = math.min(j.x1, j.x2), math.max(j.x1, j.x2)
  local minY, maxY = math.min(j.y1, j.y2), math.max(j.y1, j.y2)
  local minZ, maxZ = math.min(j.z1, j.z2), math.max(j.z1, j.z2)
  local corners = {}
  if (maxX - minX) >= (maxZ - minZ) then
    local r = 0
    for z = minZ, maxZ do
      if r % 2 == 0 then corners[#corners + 1] = { minX, z }; corners[#corners + 1] = { maxX, z }
      else corners[#corners + 1] = { maxX, z }; corners[#corners + 1] = { minX, z } end
      r = r + 1
    end
  else
    local r = 0
    for x = minX, maxX do
      if r % 2 == 0 then corners[#corners + 1] = { x, minZ }; corners[#corners + 1] = { x, maxZ }
      else corners[#corners + 1] = { x, maxZ }; corners[#corners + 1] = { x, minZ } end
      r = r + 1
    end
  end
  local reversed = {}
  for i = #corners, 1, -1 do reversed[#reversed + 1] = corners[i] end

  local c, k = maxY - 1, 0
  while true do
    if c < minY then c = minY end
    k = k + 1
    local o = { up = c + 1 <= maxY, down = c - 1 >= minY }
    for _, p in ipairs(k % 2 == 1 and corners or reversed) do addWp(L, p[1], c, p[2], o) end
    if c - 1 <= minY then break end
    c = c - 3
  end
  return L
end

local function dist(a, b) return math.abs(a.x - b.x) + math.abs(a.y - b.y) + math.abs(a.z - b.z) end

local function buildWaypoints()
  wps = (S.job.kind == "branch") and genBranch(S.job) or genBox(S.job)
  wpLen, wpTotal = { [0] = 0, [1] = 0 }, 0
  for i = 2, #wps do
    wpTotal = wpTotal + dist(wps[i - 1], wps[i])
    wpLen[i] = wpTotal
  end
end

local function between(v, a, b) return v >= math.min(a, b) and v <= math.max(a, b) end
local function onLine(p, a, b)
  local same = (p.x == a.x and 1 or 0) + (p.y == a.y and 1 or 0) + (p.z == a.z and 1 or 0)
  return between(p.x, a.x, b.x) and between(p.y, a.y, b.y) and between(p.z, a.z, b.z) and same >= 2
end

local function runSegment(wp)
  if wp.up then digDir("up") end
  if wp.down then digDir("down") end
  while not samePos(S.pos, wp) do
    checkpoint()
    local d, rem
    if S.pos.x ~= wp.x then d, rem = (wp.x > S.pos.x) and 1 or 3, math.abs(wp.x - S.pos.x)
    elseif S.pos.z ~= wp.z then d, rem = (wp.z > S.pos.z) and 2 or 0, math.abs(wp.z - S.pos.z)
    elseif S.pos.y < wp.y then d, rem = 4, wp.y - S.pos.y
    else d, rem = 5, S.pos.y - wp.y end
    if advance(d, rem) <= 0 then
      noteStuck("Skipped part of the job at " .. posStr() .. ": " .. blockText() .. ", no way around")
      return
    end
    if wp.up then digDir("up") end
    if wp.down then digDir("down") end
    if wp.scan then scanHere(S.job.walls) end
  end
end

local function runJob()
  buildWaypoints()
  if S.step > #wps then return end
  if S.returnTo then
    goTravel(S.returnTo); turnTo(S.returnTo.f)
    S.returnTo = nil; save()
  else
    local prev = wps[S.step - 1] or wps[1]
    if not onLine(S.pos, prev, wps[S.step]) then goTravel(prev) end
  end
  status = "Mining"
  for k = S.step, #wps do
    runSegment(wps[k])
    S.step = k + 1
    save()
  end
end

-- ---------- start-up ----------
local function locate()
  local x, y, z = gps.locate(3)
  if x then return { x = math.floor(x + 0.5), y = math.floor(y + 0.5), z = math.floor(z + 0.5) } end
end

local function detectFacing()
  if fuelLevel() < 2 then refuelFromInventory() end
  if fuelLevel() < 2 then return false end
  local p1 = S.pos
  for attempt = 1, 8 do
    if attempt > 4 then
      local ok, d = turtle.inspect()
      if not (ok and isProtected(d.name)) then turtle.dig() end
    end
    if turtle.forward() then
      local p2 = locate()
      if not turtle.back() then S.pos = p2 or S.pos end
      if not p2 then return false end
      for f = 0, 3 do
        if p2.x - p1.x == DX[f] and p2.z - p1.z == DZ[f] then S.facing = f; save(); return true end
      end
      return false
    end
    turtle.turnRight()
  end
  return false
end

local function init()
  load()
  if not os.getComputerLabel() then os.setComputerLabel("Miner-" .. os.getComputerID()) end
  status = "Locating (GPS)"
  local p = locate()
  while not p do
    alert = "No GPS signal! Check the GPS towers are running."
    sleep(5)
    p = locate()
  end
  S.pos = p
  alert = nil
  save()

  status = "Waiting for control room"
  while not (cfg.dock and S.lane) do sleep(1) end

  -- a brand new turtle sitting in the dock can fuel itself up first
  if samePos(S.pos, cfg.dock) and fuelLevel() < 50 then
    turtle.select(16)
    for _ = 1, 4 do if turtle.suckUp(4) then turtle.refuel() end end
    turtle.select(1)
  end

  status = "Finding direction"
  while not detectFacing() do
    alert = "Can't work out which way I'm facing - give me some fuel"
    sleep(5)
  end
  alert = nil
end

local function mainLoop()
  while true do
    if flags.cancel then
      flags.cancel = false
      if S.mode ~= "idle" then S.job, S.mode, S.step, S.returnTo = nil, "idle", 1, nil; save() end
    end
    if S.mode == "job" and S.job then
      inJob = true
      local ok, err = pcall(runJob)
      inJob = false
      if ok then
        send({ type = "done", text = (os.getComputerLabel() or "?") .. " finished: " .. (S.job.desc or S.job.kind) })
        S.job, S.mode, S.step = nil, "idle", 1
        save()
        goHomeAndPark()
      elseif type(err) == "table" and err.abort then
        if err.abort == "cancel" then S.job, S.mode, S.step = nil, "idle", 1 else S.mode = "recalled" end
        S.returnTo = nil
        save()
        goHomeAndPark()
      else
        error(err, 0)
      end
    else
      if not isParked() then goHomeAndPark() end
      if S.mode == "recalled" and not S.job then S.mode = "idle"; save() end
      while not (S.mode == "job" and S.job) and not flags.refuel do
        -- keep the status in step with Cancel / Resume sent while parked
        if S.mode == "recalled" and not S.job then S.mode = "idle"; save() end
        status = (S.mode == "recalled") and "Recalled (job on hold)" or "Idle"
        rebootIfPending()
        sleep(1)
      end
      if flags.refuel then
        flags.refuel = false
        send({ type = "log", text = (os.getComputerLabel() or "?") .. " going to refuel" })
        goHomeAndPark()
      end
    end
  end
end

local function brain()
  init()
  while true do
    local _, err = pcall(mainLoop)
    status = "ERROR"
    alert = tostring(err)
    S.paused = true
    save()
    send({ type = "log", text = (os.getComputerLabel() or "?") .. " ERROR: " .. alert })
    -- wait for Resume / Recall / Cancel / Refuel from the control room
    while S.paused and not flags.cancel and not flags.recall and not flags.refuel do rebootIfPending(); sleep(1) end
    if flags.cancel then
      flags.cancel = false
      S.job, S.mode, S.step, S.returnTo = nil, "idle", 1, nil
      send({ type = "log", text = (os.getComputerLabel() or "?") .. " job cancelled - heading home" })
    elseif flags.recall then
      flags.recall = false
      S.mode, S.returnTo = "recalled", nil
    end
    S.paused = false
    save()
    alert = nil
  end
end

-- allows the test harness to load this file without running it
if ... == "test" then
  return { S = S, cfg = cfg, genBranch = genBranch, genBox = genBox, runJob = runJob, goHomeAndPark = goHomeAndPark,
           init = init, mainLoop = mainLoop, brain = brain, flags = flags, handle = handle, selfUpdate = selfUpdate,
           netStep = function() if updateWanted then local u = updateWanted; updateWanted = nil; selfUpdate(u) end end,
           rebootPending = function() return rebootPending end, VERSION = VERSION, setCfg = function(c) cfg = c end }
end

parallel.waitForAny(brain, netLoop)
