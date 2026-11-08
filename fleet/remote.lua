-- =====================================================
--  FLEET REMOTE - pocket computer app
--  Install on an ADVANCED POCKET COMPUTER with an ender modem
--  (craft the pocket computer together with an ender modem)
--  Save as startup.lua to open it automatically, or as "fleet" to run on demand.
-- =====================================================

local CONTROL_ID = nil     -- control computer's ID. nil = find it automatically
local PROTOCOL   = "fleetmine"
local DIRS       = { "N", "E", "S", "W" }

if not term.isColor() then error("Needs an ADVANCED pocket computer", 0) end
local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
if not modem then error("Craft an ender modem onto this pocket computer first!", 0) end
rednet.open(peripheral.getName(modem))

local serverId = CONTROL_ID
local function request(msg)
  if not serverId then serverId = rednet.lookup(PROTOCOL, "control") end
  if not serverId then return { ok = false, err = "Control room not found" } end
  msg.rid = tostring(math.random(1, 2 ^ 30)) .. ":" .. os.clock()
  rednet.send(serverId, msg, PROTOCOL)
  local deadline = os.clock() + 4
  while true do
    local left = deadline - os.clock()
    if left <= 0 then break end
    local id, r = rednet.receive(PROTOCOL, left)
    if not id then break end
    if id == serverId and type(r) == "table" and r.rid == msg.rid then return r end
  end
  if not CONTROL_ID then serverId = nil end
  return { ok = false, err = "Control room not responding" }
end

local W, H = term.getSize()
local data = nil            -- last reply from the control room
local view = { name = "fleet", id = nil, ore = nil, scroll = 0 }
local toast, toastUntil = nil, 0
local hits = {}

local function put(x, y, s, fg, bg)
  s = tostring(s)
  if y < 1 or y > H then return end
  s = s:sub(1, W - x + 1)
  term.setCursorPos(x, y); term.setTextColor(fg or colors.white); term.setBackgroundColor(bg or colors.black)
  term.write(s)
end
local function fill(y, bg) put(1, y, string.rep(" ", W), colors.white, bg) end
local function btn(id, x, y, w, label, bg, d)
  put(x, y, string.rep(" ", w), colors.white, bg)
  label = label:sub(1, w)
  put(x + math.floor((w - #label) / 2), y, label, colors.white, bg)
  hits[#hits + 1] = { id = id, x1 = x, x2 = x + w - 1, y = y, d = d }
end
local function bar(x, y, w, frac, col)
  frac = math.max(0, math.min(1, frac or 0))
  put(x, y, string.rep(" ", w), colors.white, colors.gray)
  local n = math.floor(frac * w + 0.5)
  if n > 0 then put(x, y, string.rep(" ", n), colors.white, col) end
end
local function stateColor(s)
  s = (s or ""):lower()
  if s:find("error") or s:find("out of fuel") then return colors.red end
  if s:find("mining") then return colors.lime end
  if s:find("travel") or s:find("return") or s:find("dock") then return colors.lightBlue end
  if s:find("unload") or s:find("refuel") then return colors.cyan end
  if s:find("pause") or s:find("recall") then return colors.yellow end
  if s:find("block") or s:find("wait") or s:find("full") then return colors.orange end
  if s:find("offline") then return colors.gray end
  return colors.lightGray
end
local function say(msg, good) toast = { msg, good and colors.green or colors.red }; toastUntil = os.clock() + 3 end
local function findTurtle(id)
  for _, t in ipairs(data and data.fleet or {}) do if t.id == id then return t end end
end

local function locate()
  local x, y, z = gps.locate(3)
  if x then return { x = math.floor(x + 0.5), y = math.floor(y + 0.5), z = math.floor(z + 0.5) } end
end

-- ---------- screens ----------
local function header(title)
  fill(1, colors.orange)
  put(2, 1, title, colors.black, colors.orange)
  if data and data.fleet then
    local on = 0
    for _, t in ipairs(data.fleet) do if t.state ~= "Offline" then on = on + 1 end end
    local s = on .. "/" .. #data.fleet
    put(W - #s, 1, s, colors.black, colors.orange)
  end
end

local function tabs()
  fill(2, colors.gray)
  local list = { { "fleet", "Fleet" }, { "log", "Log" } }
  local w = math.floor(W / #list)
  for i, t in ipairs(list) do
    local active = view.name == t[1]
    btn("tab", 1 + (i - 1) * w, 2, w, t[2], active and colors.black or colors.gray, t[1])
  end
end

local function drawFleet()
  header("FLEET"); tabs()
  if not data then put(2, 5, "Connecting...", colors.lightGray) return end
  if not data.ok and data.err then put(2, 5, data.err, colors.red) return end
  local y = 3
  local fleet = data.fleet or {}
  if #fleet == 0 then put(2, 5, "No turtles yet", colors.gray) end
  local per = math.floor((H - 5) / 2)
  view.scroll = math.max(0, math.min(view.scroll, #fleet - per))
  for i = view.scroll + 1, math.min(#fleet, view.scroll + per) do
    local t = fleet[i]
    put(1, y, ("#" .. t.id .. " " .. t.name):sub(1, W - 12), colors.white)
    put(W - 10, y, (t.state .. "          "):sub(1, 11), stateColor(t.state))
    bar(2, y + 1, 8, t.fuelFrac, (t.fuelFrac or 0) > 0.5 and colors.lime or ((t.fuelFrac or 0) > 0.2 and colors.yellow or colors.red))
    if t.progress then
      bar(12, y + 1, 8, t.progress, colors.lightBlue)
      put(21, y + 1, string.format("%d%%", math.floor(t.progress * 100)), colors.lightGray)
    else put(12, y + 1, t.job and "" or "no job", colors.gray) end
    hits[#hits + 1] = { id = "turtle", x1 = 1, x2 = W, y = y, d = t.id }
    hits[#hits + 1] = { id = "turtle", x1 = 1, x2 = W, y = y + 1, d = t.id }
    y = y + 2
  end
  if #fleet > per then
    btn("scroll", W - 2, 3, 3, "^", colors.gray, -1)
    btn("scroll", W - 2, H - 3, 3, "v", colors.gray, 1)
  end
  btn("all", 1, H - 2, 12, "Refuel all", colors.cyan, "refuel")
  local armed = view.armCancel and os.clock() < view.armCancel
  btn("cancelall", 14, H - 2, 13, armed and "Tap again" or "Cancel all", colors.red)
  btn("all", 1, H - 1, 12, "Recall all", colors.orange, "recall")
  btn("all", 14, H - 1, 13, "Resume all", colors.gray, "resume")
  btn("mark", 1, H, W, "Mark my position", colors.blue)
end

local function drawDetail()
  local t = findTurtle(view.id)
  if not t then view.name = "fleet" return drawFleet() end
  header("#" .. t.id .. " " .. t.name)
  put(1, 3, t.state, stateColor(t.state))
  put(1, 4, "Pos ", colors.lightGray)
  put(5, 4, t.pos and (t.pos.x .. "," .. t.pos.y .. "," .. t.pos.z) or "?", colors.white)
  put(1, 5, "Fuel", colors.lightGray)
  bar(6, 5, 10, t.fuelFrac, (t.fuelFrac or 0) > 0.2 and colors.lime or colors.red)
  put(17, 5, tostring(t.fuel or "?"), colors.white)
  put(1, 6, "Inv ", colors.lightGray); put(6, 6, (t.inv or 0) .. "/16", colors.white)
  put(1, 7, "Job ", colors.lightGray); put(6, 7, t.job or "none", t.job and colors.white or colors.gray)
  if t.progress then
    bar(6, 8, 10, t.progress, colors.lime)
    put(17, 8, string.format("%d%% %s", math.floor(t.progress * 100), t.eta or ""), colors.white)
  end
  if t.alert then
    local a = t.alert
    put(1, 10, a:sub(1, W), colors.red); put(1, 11, a:sub(W + 1, 2 * W), colors.red)
  end
  local paused = t.paused or t.mode == "recalled" or t.state == "ERROR"
  btn("cmd", 1, H - 4, 12, paused and "Resume" or "Pause", paused and colors.green or colors.gray, paused and "resume" or "pause")
  btn("cmd", 14, H - 4, 13, "Recall", colors.orange, "recall")
  btn("cmd", 1, H - 3, 12, "Cancel job", colors.red, "cancel")
  btn("quick", 14, H - 3, 13, "Mine here", colors.green)
  btn("cmd", 1, H - 2, 12, "Refuel", colors.cyan, "refuel")
  btn("back", 1, H - 1, W, "Back", colors.gray)
end

local function drawQuickOre()
  header("MINE HERE: ORE")
  put(1, 3, "Branch mine from where", colors.lightGray)
  put(1, 4, "you stand. Pick an ore:", colors.lightGray)
  local y = 6
  btn("ore", 1, y, W, "All ores (Y here)", colors.gray, { key = "all" }); y = y + 1
  for _, o in ipairs(data and data.ores or {}) do
    if y < H - 1 then btn("ore", 1, y, W, o.label .. "  (Y " .. o.y .. ")", colors.gray, o); y = y + 1 end
  end
  btn("back", 1, H, W, "Back", colors.red)
end

local function drawQuickDir()
  header("MINE HERE: DIRECTION")
  put(1, 3, "Ore: " .. view.ore.label, colors.white)
  put(1, 4, "Which way should the", colors.lightGray)
  put(1, 5, "main tunnel go? (F3)", colors.lightGray)
  btn("dir", 10, 7, 7, "North", colors.blue, 0)
  btn("dir", 1, 9, 8, "West", colors.blue, 3)
  btn("dir", 18, 9, 8, "East", colors.blue, 1)
  btn("dir", 10, 11, 7, "South", colors.blue, 2)
  btn("back", 1, H, W, "Back", colors.red)
end

local function drawLog()
  header("FLEET LOG"); tabs()
  local y = 3
  for _, e in ipairs(data and data.log or {}) do
    if y > H then break end
    local text = e.t .. " " .. e.text
    put(1, y, text:sub(1, W), e.col or colors.white); y = y + 1
    if #text > W and y <= H then put(3, y, text:sub(W + 1, 2 * W - 2), e.col or colors.white); y = y + 1 end
  end
end

local function draw()
  hits = {}
  term.setBackgroundColor(colors.black); term.clear()
  if view.name == "fleet" then drawFleet()
  elseif view.name == "detail" then drawDetail()
  elseif view.name == "quickore" then drawQuickOre()
  elseif view.name == "quickdir" then drawQuickDir()
  elseif view.name == "log" then drawLog() end
  if toast and os.clock() < toastUntil then
    fill(H, toast[2]); put(1, H, toast[1], colors.white, toast[2])
  end
end

local function onClick(x, y)
  local h
  for i = #hits, 1, -1 do
    local c = hits[i]
    if y == c.y and x >= c.x1 and x <= c.x2 then h = c break end
  end
  if not h then return end
  local d = h.d
  if h.id == "tab" then view.name = d
  elseif h.id == "turtle" then view.name, view.id = "detail", d
  elseif h.id == "back" then view.name = (view.name == "quickdir") and "quickore" or ((view.name == "quickore") and "detail" or "fleet")
  elseif h.id == "scroll" then view.scroll = view.scroll + d
  elseif h.id == "all" then
    local r = request({ type = "r_cmd", id = "all", cmd = d })
    say(r.ok and ("Sent " .. d .. " to all") or r.err, r.ok)
  elseif h.id == "cancelall" then
    if view.armCancel and os.clock() < view.armCancel then
      view.armCancel = nil
      local r = request({ type = "r_cmd", id = "all", cmd = "cancel" })
      say(r.ok and "Cancelled all jobs" or r.err, r.ok)
    else
      view.armCancel = os.clock() + 4
      say("Tap again to cancel ALL jobs", false)
    end
  elseif h.id == "cmd" then
    local r = request({ type = "r_cmd", id = view.id, cmd = d })
    say(r.ok and ("Sent " .. d) or r.err, r.ok)
  elseif h.id == "mark" then
    local p = locate()
    if not p then say("No GPS signal") return end
    local r = request({ type = "r_marker", pos = p })
    say(r.ok and ("Marker set " .. p.x .. "," .. p.z) or r.err, r.ok)
  elseif h.id == "quick" then view.name = "quickore"
  elseif h.id == "ore" then view.ore = d; view.name = "quickdir"
  elseif h.id == "dir" then
    local p = locate()
    if not p then say("No GPS signal") return end
    local y = (view.ore.key == "all") and p.y or view.ore.y
    local r = request({ type = "r_quick", id = view.id, target = view.ore.key, dir = d, pos = p, y = y })
    say(r.msg or r.err or "?", r.ok)
    if r.ok then view.name = "detail" end
  end
end

local function poll()
  while true do
    local r = request({ type = "r_fleet" })
    if r.ok or not data then data = r end
    os.queueEvent("fleet_update")
    sleep(2)
  end
end

local function uiLoop()
  while true do
    draw()
    local ev, a, b, c = os.pullEvent()
    if ev == "mouse_click" then onClick(b, c)
    elseif ev == "mouse_scroll" and view.name == "fleet" then view.scroll = view.scroll + a
    elseif ev == "key" and a == keys.q then return end
  end
end

parallel.waitForAny(poll, uiLoop)
term.setBackgroundColor(colors.black); term.clear(); term.setCursorPos(1, 1)
print("Fleet remote closed. Type 'fleet' or reboot to open it again.")
