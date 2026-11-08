-- ============================================================
--  EMBER CONTROL  -  your personal admin app
--  One pocket app for every system: Bank, Mining Fleet...
--  Extra systems: drop an app file into /ember/apps/  (see ember-app-template.lua)
--  Needs: Advanced Pocket Computer with a wireless/ender modem
-- ============================================================
local VERSION = "1.0"
local DIR = "/ember"
local APPS_DIR = DIR .. "/apps"
local CFG_FILE = DIR .. "/config"
local args = { ... }
local TEST = args[1] == "test"

-- ---------- SHA-256 (pure Lua, uses bit32) ----------
local band, bxor, bnot, rrotate, rshift = bit32.band, bit32.bxor, bit32.bnot, bit32.rrotate, bit32.rshift
local K = {
  0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
  0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
  0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
  0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
  0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
  0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
  0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
  0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2,
}
local function sha256(msg)
  local H = {0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19}
  local len = #msg
  local bits = len * 8
  local tail = ""
  for i = 7, 0, -1 do tail = tail .. string.char(math.floor(bits / 2 ^ (i * 8)) % 256) end
  msg = msg .. "\128" .. string.rep("\0", (55 - len) % 64) .. tail
  local w = {}
  for chunk = 1, #msg, 64 do
    for i = 0, 15 do
      local a, b, c, d = msg:byte(chunk + i * 4, chunk + i * 4 + 3)
      w[i] = ((a * 256 + b) * 256 + c) * 256 + d
    end
    for i = 16, 63 do
      local x, y = w[i - 15], w[i - 2]
      local s0 = bxor(rrotate(x, 7), rrotate(x, 18), rshift(x, 3))
      local s1 = bxor(rrotate(y, 17), rrotate(y, 19), rshift(y, 10))
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) % 4294967296
    end
    local a, b, c, d, e, f, g, h = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
    for i = 0, 63 do
      local S1 = bxor(rrotate(e, 6), rrotate(e, 11), rrotate(e, 25))
      local ch = bxor(band(e, f), band(bnot(e), g))
      local t1 = (h + S1 + ch + K[i + 1] + w[i]) % 4294967296
      local S0 = bxor(rrotate(a, 2), rrotate(a, 13), rrotate(a, 22))
      local maj = bxor(band(a, b), band(a, c), band(b, c))
      local t2 = (S0 + maj) % 4294967296
      h, g, f, e, d, c, b, a = g, f, e, (d + t1) % 4294967296, c, b, a, (t1 + t2) % 4294967296
    end
    H[1] = (H[1] + a) % 4294967296; H[2] = (H[2] + b) % 4294967296
    H[3] = (H[3] + c) % 4294967296; H[4] = (H[4] + d) % 4294967296
    H[5] = (H[5] + e) % 4294967296; H[6] = (H[6] + f) % 4294967296
    H[7] = (H[7] + g) % 4294967296; H[8] = (H[8] + h) % 4294967296
  end
  return string.format(string.rep("%08x", 8), H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8])
end


-- ---------- config ----------
local function readFile(p)
  if not fs.exists(p) then return nil end
  local h = fs.open(p, "r"); local d = h.readAll(); h.close()
  return d and textutils.unserialize(d)
end
local function writeFile(p, v)
  local h = fs.open(p, "w"); h.write(textutils.serialize(v)); h.close()
end
local config = readFile(CFG_FILE) or {}
config.ids = config.ids or {}        -- [protocol] = fixed computer ID (optional)
config.apps = config.apps or {}      -- per-app saved settings
local function saveConfig()
  if not fs.exists(DIR) then fs.makeDir(DIR) end
  writeFile(CFG_FILE, config)
end

-- ---------- the toolkit every app gets (ctx) ----------
local W, H = term.getSize()
local ctx = { W = W, H = H, sha256 = sha256, version = VERSION, config = config }
local hits = {}
local apps, appById = {}, {}
local current = nil          -- nil = home screen
local toastMsg, toastCol, toastUntil = nil, nil, 0

function ctx.fmt(n)
  local s = tostring(math.floor(tonumber(n) or 0))
  local neg = s:sub(1, 1) == "-"
  if neg then s = s:sub(2) end
  s = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
  return (neg and "-" or "") .. s
end
function ctx.clip(s, n)
  s = tostring(s or "")
  if #s > n then return s:sub(1, math.max(0, n - 1)) .. "." end
  return s
end
function ctx.at(x, y, s, fg, bg)
  term.setCursorPos(x, y)
  if fg then term.setTextColor(fg) end
  if bg then term.setBackgroundColor(bg) end
  term.write(s)
end
function ctx.fill(x, y, w, h, bg)
  term.setBackgroundColor(bg)
  for yy = y, y + h - 1 do term.setCursorPos(x, yy); term.write(string.rep(" ", w)) end
end
-- a tappable button; fn runs when tapped. Returns the x after the button.
function ctx.button(x, y, label, fg, bg, fn, w)
  w = w or (#label + 2)
  ctx.fill(x, y, w, 1, bg)
  ctx.at(x + math.floor((w - #label) / 2), y, label, fg, bg)
  hits[#hits + 1] = { x1 = x, x2 = x + w - 1, y1 = y, y2 = y, fn = fn }
  return x + w + 1
end
-- make any rectangle tappable
function ctx.tap(x, y, w, h, fn) hits[#hits + 1] = { x1 = x, x2 = x + w - 1, y1 = y, y2 = y + h - 1, fn = fn } end
-- title bar with a back arrow (back goes home unless onBack is given)
function ctx.header(title, col, onBack)
  ctx.fill(1, 1, W, 1, col or colors.gray)
  ctx.at(1, 1, " < ", colors.white, col or colors.gray)
  hits[#hits + 1] = { x1 = 1, x2 = 3, y1 = 1, y2 = 1, fn = onBack or function() ctx.home() end }
  ctx.at(4, 1, ctx.clip(title, W - 4), colors.white, col or colors.gray)
end
-- row of tabs on line y. tabs = { {"id","Label"}, ... }; returns nothing
function ctx.tabs(y, tabs, active, onPick, col)
  ctx.fill(1, y, W, 1, colors.gray)
  local x = 1
  for _, t in ipairs(tabs) do
    local on = t[1] == active
    x = ctx.button(x, y, t[2], on and colors.black or colors.lightGray, on and (col or colors.white) or colors.gray,
      function() onPick(t[1]) end) - 1
  end
end
-- scrollable list between rows y1..y2. state is a table that keeps .scroll
function ctx.list(state, y1, y2, items, render, onTap)
  local rows = y2 - y1 + 1
  state.scroll = math.max(0, math.min(state.scroll or 0, #items - rows))
  state._listRows = { y1 = y1, y2 = y2 }
  for i = 1, rows do
    local item = items[i + state.scroll]
    if not item then break end
    local y = y1 + i - 1
    render(item, y, i + state.scroll)
    if onTap then ctx.tap(1, y, W, 1, function() onTap(item, i + state.scroll) end) end
  end
  if #items > rows then
    local frac = state.scroll / math.max(1, #items - rows)
    local pos = y1 + math.floor(frac * (rows - 1) + 0.5)
    ctx.at(W, pos, " ", nil, colors.lightGray)
  end
end
function ctx.bar(x, y, w, frac, col, back)
  frac = math.max(0, math.min(1, tonumber(frac) or 0))
  local n = math.floor(w * frac + 0.5)
  ctx.fill(x, y, n, 1, col); ctx.fill(x + n, y, w - n, 1, back or colors.gray)
end
function ctx.toast(msg, ok)
  toastMsg = tostring(msg); toastCol = ok == false and colors.red or colors.green; toastUntil = os.clock() + 3
end
-- ask for text at the bottom of the screen. Returns nil if left blank.
function ctx.prompt(question, hidden)
  ctx.fill(1, H - 3, W, 4, colors.gray)
  ctx.at(2, H - 3, ctx.clip(question, W - 2), colors.yellow, colors.gray)
  ctx.at(2, H, "(blank = cancel)", colors.lightGray, colors.gray)
  ctx.fill(2, H - 1, W - 2, 1, colors.black)
  term.setCursorPos(2, H - 1); term.setTextColor(colors.white); term.setBackgroundColor(colors.black)
  local s = read(hidden and "*" or nil)
  if s == nil or s == "" then return nil end
  return s
end
function ctx.promptNumber(question)
  local s = ctx.prompt(question)
  if not s then return nil end
  local n = tonumber(s)
  if not n or n < 0 or n ~= math.floor(n) then ctx.toast("Type a whole number", false); return nil end
  return n
end
-- yes/no dialog
function ctx.confirm(question)
  local saved = hits
  hits = {}
  ctx.fill(2, 6, W - 2, 7, colors.gray)
  local lines, line = {}, ""
  for word in question:gmatch("%S+") do
    if #line + #word + 1 > W - 4 then lines[#lines + 1] = line; line = word else line = (line == "" and word) or (line .. " " .. word) end
  end
  lines[#lines + 1] = line
  for i = 1, math.min(3, #lines) do ctx.at(3, 6 + i, lines[i], colors.white, colors.gray) end
  local answer
  ctx.button(3, 11, "Yes", colors.white, colors.green, function() answer = true end, 9)
  ctx.button(W - 11, 11, "No", colors.white, colors.red, function() answer = false end, 9)
  while answer == nil do
    local ev, p1, x, y = os.pullEvent()
    if ev == "mouse_click" then
      for _, h in ipairs(hits) do if x >= h.x1 and x <= h.x2 and y >= h.y1 and y <= h.y2 then h.fn() end end
    elseif ev == "key" then
      if p1 == keys.y then answer = true elseif p1 == keys.n then answer = false end
    end
  end
  hits = saved
  return answer
end

-- network: find a system by protocol + hostname, send a request, wait for the matching reply
local hostCache = {}
local ridN = 0
function ctx.request(proto, host, msg, timeout)
  local id = config.ids[proto] or hostCache[proto]
  if not id then
    id = rednet.lookup(proto, host)
    if not id then return nil, "Can't find " .. host .. " (" .. proto .. ")" end
    hostCache[proto] = id
  end
  ridN = ridN + 1
  local rid = os.getComputerID() .. ":" .. ridN .. ":" .. math.random(1, 999999)
  msg.rid = rid
  rednet.send(id, msg, proto)
  local deadline = os.clock() + (timeout or 3)
  while true do
    local left = deadline - os.clock()
    if left <= 0 then hostCache[proto] = nil; return nil, ctx.clip(host, 10) .. " not responding" end
    local from, r = rednet.receive(proto, left)
    if from == id and type(r) == "table" and r.rid == rid then return r end
  end
end
-- the bank admin password hash (stored on this pocket computer)
function ctx.secret() return config.adminHash end
function ctx.appConfig(id)
  config.apps[id] = config.apps[id] or {}
  return config.apps[id]
end
ctx.saveConfig = saveConfig
function ctx.open(id)
  local app = appById[id]
  if not app then return end
  current = app
  app.state = app.state or {}
  if app.onOpen then pcall(app.onOpen, app, ctx) end
  if app.refresh then
    local ok, err = pcall(app.refresh, app, ctx)
    if not ok then ctx.toast(err, false) end
    app.lastRefresh = os.clock()
  end
end
function ctx.home() current = nil end
function ctx.redraw() os.queueEvent("ember_redraw") end

-- ---------- apps ----------
local function register(app)
  assert(type(app) == "table" and app.id and app.name, "an app needs an id and a name")
  if appById[app.id] then return end
  app.color = app.color or colors.lightBlue
  app.icon = app.icon or app.name:sub(1, 1)
  app.state = app.state or {}
  apps[#apps + 1] = app
  appById[app.id] = app
end
ctx.register = register

-- ================= BUILT-IN APP: BANK =================
register({
  id = "bank", name = "Bank", icon = "$", color = colors.orange, protocol = "emberbank", interval = 5,
  admin = function(self, c, op, a, b, quick)
    local secret = c.secret()
    if not secret then return nil, "Set the admin password in Settings" end
    local r, e = c.request("emberbank", "bank", { action = "admin_challenge" }, quick and 1.5 or 3)
    if not r then return nil, e end
    if not r.ok then return nil, r.err end
    local sig = c.sha256(r.nonce .. ":" .. secret .. ":" .. op .. ":" .. tostring(a or "") .. ":" .. tostring(b or ""))
    local r2, e2 = c.request("emberbank", "bank", { action = "admin", nonce = r.nonce, op = op, a = a, b = b, sig = sig }, quick and 1.5 or 3)
    if not r2 then return nil, e2 end
    if not r2.ok then return nil, r2.err end
    return r2
  end,
  act = function(self, c, op, a, b)
    local r, e = self:admin(c, op, a, b)
    c.toast(r and r.msg or e, r ~= nil)
    self:refresh(c)
    if self.state.acct then self:loadHistory(c) end
  end,
  loadHistory = function(self, c)
    local r, e = self:admin(c, "history", self.state.acct)
    self.state.hist = r
    if not r then c.toast(e, false) end
  end,
  refresh = function(self, c, background)
    local r, e = self:admin(c, "overview", nil, nil, background)
    if r then self.data, self.err = r, nil else self.err = e end
  end,
  summary = function(self, c)
    if self.err and not self.data then return "offline", colors.red end
    if not self.data then return "..." end
    return c.fmt(self.data.total) .. " " .. (self.data.currency or "EC")
  end,
  draw = function(self, c)
    local st, d = self.state, self.data
    st.tab = st.tab or "accts"
    if st.acct then
      c.header(st.acct, colors.orange, function() st.acct, st.hist = nil, nil end)
      local bal = st.hist and st.hist.balance
      c.at(2, 3, "Balance: ", colors.lightGray, colors.black)
      c.at(11, 3, bal and (c.fmt(bal) .. " EC") or "...", colors.yellow, colors.black)
      local u = st.acct
      local x = c.button(2, 5, "Mint", colors.white, colors.green, function()
        local n = c.promptNumber("Give " .. u .. " how much (new money)?")
        if n then self:act(c, "mint", u, n) end
      end)
      x = c.button(x, 5, "Take", colors.white, colors.red, function()
        local n = c.promptNumber("Take how much from " .. u .. "?")
        if n then self:act(c, "take", u, n) end
      end)
      c.button(x, 5, "Set", colors.white, colors.blue, function()
        local n = c.promptNumber("Set " .. u .. "'s balance to?")
        if n then self:act(c, "set", u, n) end
      end)
      c.button(2, 6, "Reset password", colors.black, colors.lightGray, function()
        local pw = c.prompt("New password for " .. u, true)
        if pw and c.confirm("Reset " .. u .. "'s password?") then
          self:act(c, "resethash", u, c.sha256("emberbank:" .. u:lower() .. ":" .. pw))
        end
      end)
      c.at(2, 8, "History", colors.white, colors.black)
      local items = st.hist and st.hist.history or {}
      st.histList = st.histList or {}
      c.list(st, 9, c.H - 1, items, function(h, y)
        local amt = (h.amount >= 0 and "+" or "") .. c.fmt(h.amount)
        c.at(1, y, amt, h.amount >= 0 and colors.lime or colors.red, colors.black)
        c.at(#amt + 2, y, c.clip(h.desc, c.W - #amt - 2), colors.lightGray, colors.black)
      end)
      return
    end
    c.header("Bank" .. (d and ("  " .. c.fmt(d.total) .. " EC") or ""), colors.orange)
    c.tabs(2, { { "accts", "Accounts" }, { "shops", "Shops" }, { "log", "Log" } }, st.tab, function(t) st.tab = t; st.scroll = 0 end, colors.orange)
    if not d then c.at(2, 4, c.clip(self.err or "Loading...", c.W - 2), self.err and colors.red or colors.lightGray, colors.black); return end
    if st.tab == "accts" then
      c.list(st, 3, c.H - 1, d.accounts, function(a, y)
        local b = c.fmt(a.balance)
        c.at(2, y, c.clip(a.name, c.W - #b - 3), colors.white, colors.black)
        c.at(c.W - #b, y, b, colors.yellow, colors.black)
      end, function(a)
        st.acct = a.name; st.scroll = 0; self:loadHistory(c)
      end)
      if #d.accounts == 0 then c.at(2, 4, "No accounts yet", colors.lightGray, colors.black) end
    elseif st.tab == "shops" then
      if st.shop then
        local s = st.shop
        c.at(2, 4, c.clip("#" .. s.id .. " " .. s.name, c.W - 2), colors.white, colors.black)
        c.at(2, 5, c.clip("Owner: " .. s.owner, c.W - 2), colors.lightGray)
        c.at(2, 6, "Buying budget: " .. c.fmt(s.budget), colors.lightGray)
        c.at(2, 7, "Recent sales: " .. s.sales, colors.lightGray)
        c.button(2, 9, "Set budget", colors.white, colors.blue, function()
          local n = c.promptNumber("New buying budget for " .. s.name)
          if n then self:act(c, "setbudget", s.id, n); st.shop = nil end
        end)
        c.button(2, 11, "Remove shop", colors.white, colors.red, function()
          if c.confirm("Unregister " .. s.name .. "? It stops working until set up again.") then
            self:act(c, "delshop", s.id); st.shop = nil
          end
        end)
        c.button(2, c.H - 1, "< Back", colors.white, colors.gray, function() st.shop = nil end)
      else
        c.list(st, 3, c.H - 1, d.shops, function(s, y)
          c.at(2, y, c.clip("#" .. s.id .. " " .. s.name, 14), colors.white, colors.black)
          c.at(17, y, c.clip(s.owner, c.W - 17), colors.lightGray, colors.black)
        end, function(s) st.shop = s end)
        if #d.shops == 0 then c.at(2, 4, "No shops registered", colors.lightGray, colors.black) end
      end
    else
      local lines = {}
      for _, l in ipairs(d.log or {}) do
        local t = l:gsub("^%[[^%]]*%]%s*", "")
        lines[#lines + 1] = t
      end
      c.list(st, 3, c.H - 1, lines, function(l, y)
        local col = l:find("ADMIN") and colors.orange or (l:find("Wrong") and colors.red or colors.lightGray)
        c.at(1, y, c.clip(l, c.W), col, colors.black)
      end)
    end
  end,
})

-- ================= BUILT-IN APP: MINING FLEET =================
register({
  id = "fleet", name = "Mining", icon = "#", color = colors.blue, protocol = "fleetmine", interval = 3,
  refresh = function(self, c, background)
    local r, e = c.request("fleetmine", "control", { type = "r_fleet" }, background and 1.5 or 3)
    if r and r.ok then self.data, self.err = r, nil else self.err = e or (r and r.err) end
  end,
  cmd = function(self, c, id, cmd)
    local r, e = c.request("fleetmine", "control", { type = "r_cmd", id = id, cmd = cmd })
    c.toast(r and r.ok and ("Sent " .. cmd) or (e or r.err), r and r.ok)
    self:refresh(c)
  end,
  summary = function(self, c)
    if not self.data then return self.err and "offline" or "...", self.err and colors.red end
    local busy, alerts = 0, 0
    for _, t in ipairs(self.data.fleet) do
      if not t.idle and t.state ~= "Offline" then busy = busy + 1 end
      if t.alert then alerts = alerts + 1 end
    end
    if alerts > 0 then return alerts .. " alert" .. (alerts > 1 and "s!" or "!"), colors.yellow end
    return busy .. "/" .. #self.data.fleet .. " mining"
  end,
  draw = function(self, c)
    local st, d = self.state, self.data
    if st.sel and d then
      local t
      for _, x in ipairs(d.fleet) do if x.id == st.sel then t = x end end
      if not t then st.sel = nil else
        c.header(t.name or ("#" .. t.id), colors.blue, function() st.sel = nil end)
        local y = 3
        c.at(2, y, c.clip(t.state or "?", c.W - 2), t.state == "Offline" and colors.red or colors.yellow, colors.black)
        if t.alert then y = y + 1; c.at(2, y, c.clip("! " .. t.alert, c.W - 2), colors.red, colors.black) end
        y = y + 2
        c.at(2, y, "Fuel", colors.lightGray, colors.black)
        c.bar(7, y, 12, t.fuelFrac or 0, (t.fuelFrac or 0) < 0.2 and colors.red or colors.orange)
        c.at(20, y, c.fmt(t.fuel), colors.white, colors.black)
        y = y + 1
        if t.job then c.at(2, y, c.clip("Job: " .. t.job, c.W - 2), colors.lightGray, colors.black); y = y + 1 end
        if type(t.progress) == "number" then
          c.at(2, y, "Done", colors.lightGray, colors.black); c.bar(7, y, 12, t.progress, colors.lime)
          c.at(20, y, math.floor(t.progress * 100) .. "%", colors.white, colors.black); y = y + 1
        end
        if t.eta then c.at(2, y, "ETA " .. tostring(t.eta), colors.lightGray, colors.black); y = y + 1 end
        if t.pos then c.at(2, y, "At " .. t.pos.x .. ", " .. t.pos.y .. ", " .. t.pos.z, colors.lightGray, colors.black) end
        local by = c.H - 3
        c.button(2, by, t.paused and "Resume" or "Pause", colors.black, t.paused and colors.lime or colors.yellow,
          function() self:cmd(c, t.id, t.paused and "resume" or "pause") end, 11)
        c.button(14, by, "Recall", colors.white, colors.orange, function() self:cmd(c, t.id, "recall") end, 11)
        c.button(2, by + 2, "Cancel job", colors.white, colors.red, function()
          if c.confirm("Cancel " .. (t.name or "this turtle") .. "'s job?") then self:cmd(c, t.id, "cancel") end
        end, 11)
        c.button(14, by + 2, "Refuel", colors.white, colors.cyan, function() self:cmd(c, t.id, "refuel") end, 11)
        return
      end
    end
    c.header("Mining Fleet", colors.blue)
    st.tab = st.tab or "fleet"
    c.tabs(2, { { "fleet", "Turtles" }, { "log", "Log" } }, st.tab, function(t) st.tab = t; st.scroll = 0 end, colors.lightBlue)
    if not d then c.at(2, 4, c.clip(self.err or "Loading...", c.W - 2), self.err and colors.red or colors.lightGray, colors.black); return end
    if st.tab == "fleet" then
      local x = c.button(1, 3, "Pause all", colors.black, colors.yellow, function() self:cmd(c, "all", "pause") end)
      x = c.button(x, 3, "Resume", colors.black, colors.lime, function() self:cmd(c, "all", "resume") end)
      c.button(x, 3, "Recall", colors.white, colors.orange, function()
        if c.confirm("Recall every turtle home?") then self:cmd(c, "all", "recall") end
      end)
      x = c.button(1, 4, "Refuel all", colors.white, colors.cyan, function() self:cmd(c, "all", "refuel") end)
      c.button(x, 4, "Cancel all", colors.white, colors.red, function()
        if c.confirm("Cancel EVERY turtle's job? They all come home.") then self:cmd(c, "all", "cancel") end
      end)
      c.list(st, 6, c.H - 1, d.fleet, function(t, y)
        local off = t.state == "Offline"
        c.at(1, y, " ", nil, off and colors.red or (t.alert and colors.yellow or (t.idle and colors.gray or colors.lime)))
        c.at(3, y, c.clip(t.name or ("#" .. t.id), 9), colors.white, colors.black)
        c.at(13, y, c.clip(t.state or "?", 9), off and colors.red or colors.lightGray, colors.black)
        c.bar(c.W - 3, y, 3, t.fuelFrac or 0, (t.fuelFrac or 0) < 0.2 and colors.red or colors.orange)
      end, function(t) st.sel = t.id end)
      if #d.fleet == 0 then c.at(2, 7, "No turtles yet", colors.lightGray, colors.black) end
    else
      c.list(st, 3, c.H - 1, d.log or {}, function(e, y)
        c.at(1, y, c.clip(tostring(e.t or "") .. " " .. tostring(e.text or ""), c.W), e.col or colors.white, colors.black)
      end)
    end
  end,
})


-- ---------- home + settings ----------
local homeState = {}
local settings = { id = "settings", name = "Settings", icon = "*", color = colors.gray, state = {} }

function settings.draw(self, c)
  c.header("Settings", colors.gray)
  local y = 3
  c.at(2, y, "Bank admin password", colors.white, colors.black)
  c.button(2, y + 1, config.adminHash and "Change" or "Set it", colors.black, colors.orange, function()
    local pw = c.prompt("Admin password (same as 'adminpw' on the bank)", true)
    if pw then config.adminHash = sha256("emberadmin:" .. pw); saveConfig(); c.toast("Saved", true) end
  end)
  if config.adminHash then
    c.button(12, y + 1, "Forget", colors.white, colors.red, function()
      config.adminHash = nil; saveConfig(); c.toast("Forgotten", true)
    end)
  end
  y = y + 3
  c.at(2, y, "App PIN (asked when opened)", colors.white, colors.black)
  c.button(2, y + 1, config.pinHash and "Change PIN" or "Set PIN", colors.black, colors.lightBlue, function()
    local p = c.prompt("New PIN (blank = no PIN)", true)
    config.pinHash = p and sha256("emberpin:" .. p) or nil; saveConfig()
    c.toast(p and "PIN set" or "PIN removed", true)
  end)
  y = y + 3
  c.at(2, y, "System computer IDs", colors.white, colors.black)
  c.at(2, y + 1, "(only if auto-find fails)", colors.lightGray, colors.black)
  y = y + 2
  local protos = {}
  for _, a in ipairs(apps) do if a.protocol then protos[#protos + 1] = { a.protocol, a.name } end end
  for _, p in ipairs(protos) do
    if y > H - 2 then break end
    local v = config.ids[p[1]]
    c.at(2, y, c.clip(p[2], 10), colors.lightGray, colors.black)
    c.button(13, y, v and ("ID " .. v) or "auto", colors.white, colors.gray, function()
      local n = c.promptNumber(p[2] .. " computer ID (blank = auto)")
      config.ids[p[1]] = n; hostCache[p[1]] = nil; saveConfig()
    end, 10)
    y = y + 1
  end
  c.at(2, H, c.clip("v" .. VERSION .. "  apps: " .. #apps .. "  " .. APPS_DIR, W - 2), colors.gray, colors.black)
end

local function drawHome()
  ctx.fill(1, 1, W, 1, colors.orange)
  ctx.at(2, 1, "\4 EMBER CONTROL", colors.white, colors.orange)
  local clock = textutils.formatTime(os.time(), true)
  ctx.at(W - #clock, 1, clock, colors.white, colors.orange)
  local tiles = {}
  for _, a in ipairs(apps) do tiles[#tiles + 1] = a end
  tiles[#tiles + 1] = settings
  local tw, th = math.floor((W - 1) / 2), 4
  local rowsFit = math.floor((H - 2) / (th + 1))
  local perPage = rowsFit * 2
  homeState.scroll = math.max(0, math.min(homeState.scroll or 0, math.ceil(#tiles / 2) - rowsFit))
  for i = 1, perPage do
    local idx = i + homeState.scroll * 2
    local a = tiles[idx]
    if not a then break end
    local col = (i - 1) % 2
    local row = math.floor((i - 1) / 2)
    local x, y = 1 + col * (tw + 1), 3 + row * (th + 1)
    ctx.fill(x, y, tw, th, a.color)
    local fg = (a.color == colors.white or a.color == colors.yellow or a.color == colors.lime) and colors.black or colors.white
    ctx.at(x + 1, y + 1, ctx.clip(a.icon .. " " .. a.name, tw - 1), fg, a.color)
    local s, scol = nil, nil
    if a.summary then
      local ok, t, c2 = pcall(a.summary, a, ctx)
      if ok then s, scol = t, c2 end
    end
    if s then ctx.at(x + 1, y + 2, ctx.clip(s, tw - 1), scol or fg, a.color) end
    ctx.tap(x, y, tw, th, function()
      if a == settings then current = settings else ctx.open(a.id) end
    end)
  end
  if #tiles > perPage then ctx.at(1, H, "scroll for more", colors.gray, colors.black) end
end

local function draw()
  hits = {}
  term.setBackgroundColor(colors.black); term.clear()
  if current then
    local ok, err = pcall(current.draw, current, ctx)
    if not ok then
      ctx.fill(1, 3, W, 3, colors.red)
      ctx.at(2, 3, "App error:", colors.white, colors.red)
      ctx.at(2, 4, ctx.clip(err, W - 2), colors.white, colors.red)
      ctx.header(current.name, colors.red)
    end
  else
    drawHome()
  end
  if toastMsg and os.clock() < toastUntil then
    ctx.fill(1, H, W, 1, toastCol)
    ctx.at(1, H, ctx.clip(toastMsg, W), colors.white, toastCol)
  end
end

local function click(x, y)
  for i = #hits, 1, -1 do
    local h = hits[i]
    if x >= h.x1 and x <= h.x2 and y >= h.y1 and y <= h.y2 then
      local ok, err = pcall(h.fn)
      if not ok then ctx.toast(err, false) end
      return
    end
  end
end

local function scrollBy(d)
  if current then
    local st = current.state or {}
    st.scroll = (st.scroll or 0) + d
  else
    homeState.scroll = (homeState.scroll or 0) + d
  end
end

local function refreshDue()
  local now = os.clock()
  if current and current.refresh and now - (current.lastRefresh or 0) >= (current.interval or 3) then
    local ok, err = pcall(current.refresh, current, ctx)
    if not ok then ctx.toast(err, false) end
    current.lastRefresh = now
  elseif not current then
    for _, a in ipairs(apps) do
      if a.refresh and now - (a.lastRefresh or -999) >= 15 then
        pcall(a.refresh, a, ctx, true)
        a.lastRefresh = now
      end
    end
  end
end

local function loadApps()
  if not fs.exists(APPS_DIR) then return end
  for _, f in ipairs(fs.list(APPS_DIR)) do
    if f:find("%.lua$") then
      local path = fs.combine(APPS_DIR, f)
      local fn, err = loadfile(path, nil, setmetatable({ ember = ctx }, { __index = _ENV }))
      local ok, app = false, err
      if fn then ok, app = pcall(fn) end
      if ok and type(app) == "table" then
        local ok2, e2 = pcall(register, app)
        if not ok2 then print("App " .. f .. ": " .. e2); sleep(1) end
      else
        print("Couldn't load " .. f .. ": " .. tostring(app)); sleep(2)
      end
    end
  end
end

local function unlock()
  if not config.pinHash then return true end
  for _ = 1, 3 do
    term.setBackgroundColor(colors.black); term.clear()
    ctx.at(2, 3, "\4 EMBER CONTROL", colors.orange, colors.black)
    ctx.at(2, 5, "PIN: ", colors.white, colors.black)
    local p = read("*")
    if sha256("emberpin:" .. p) == config.pinHash then return true end
    ctx.at(2, 7, "Wrong PIN", colors.red, colors.black); sleep(1)
  end
  return false
end

if TEST then
  return { ctx = ctx, apps = apps, appById = appById, draw = draw, click = click, hits = function() return hits end,
    settings = settings, current = function() return current end, setCurrent = function(a) current = a end,
    refreshDue = refreshDue, scrollBy = scrollBy, loadApps = loadApps }
end

-- ---------- start ----------
if not term.isColor() then error("Ember Control needs an ADVANCED (gold) pocket computer", 0) end
local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
if not modem then error("Put a wireless or ender modem on this computer", 0) end
rednet.open(peripheral.getName(modem))
math.randomseed(os.epoch("utc"))
loadApps()
if not unlock() then term.clear(); term.setCursorPos(1, 1); print("Locked."); return end

local timer = os.startTimer(0.1)
local dragY
while true do
  draw()
  local ev, a, b, c = os.pullEvent()
  if ev == "mouse_click" then dragY = c; click(b, c); timer = os.startTimer(0.5)
  elseif ev == "mouse_drag" and dragY then scrollBy(dragY - c); dragY = c
  elseif ev == "mouse_up" then dragY = nil
  elseif ev == "mouse_scroll" then scrollBy(a)
  elseif ev == "key" and a == keys.q and not current then break
  elseif ev == "key" and (a == keys.backspace or a == keys.q) and current then current = nil
  elseif ev == "timer" and a == timer then
    refreshDue()
    timer = os.startTimer(1)
  end
end
term.setBackgroundColor(colors.black); term.clear(); term.setCursorPos(1, 1)
print("Ember Control closed. Type 'ember' to open it again.")
