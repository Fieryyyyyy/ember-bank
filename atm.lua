-- =====================================================
--  EMBER BANK - ATM
--  Install on each ATM computer as startup.lua
--  Needs: advanced computer + wireless modem + advanced monitor
--         (at least 3 wide x 2 tall)
-- =====================================================

local ADMIN_PASSWORD = "changeme"   -- !! CHANGE THIS !! Needed to stop the ATM with Ctrl+T
local BANK_ID        = 0          -- the bank computer's ID (shown on its screen). nil = find it automatically
local PROTOCOL       = "emberbank"
local CUR            = "EC"
local IDLE_LOGOUT    = 60           -- seconds before an idle player is logged out

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
-- The password itself never leaves this computer, only this hash does
local function hashPw(user, pw) return sha256("emberbank:" .. user:lower() .. ":" .. pw) end

-- ---------- network ----------
local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
if not modem then error("Attach a wireless modem to this computer!", 0) end
rednet.open(peripheral.getName(modem))

-- re-opens the modem if it was swapped/replaced while running
local function ensureModem()
  if rednet.isOpen() then return true end
  local m = peripheral.find("modem", function(_, x) return x.isWireless() end)
  if m then rednet.open(peripheral.getName(m)) return true end
  return false
end

local serverId = BANK_ID
local function request(msg)
  if not ensureModem() then return { ok = false, err = "No wireless/ender modem attached" } end
  if not serverId then serverId = rednet.lookup(PROTOCOL, "bank") end
  if not serverId then return { ok = false, err = "Can't reach the bank (out of range?)" } end
  msg.rid = tostring(math.random(1, 2 ^ 30)) .. ":" .. os.clock()
  rednet.send(serverId, msg, PROTOCOL)
  local deadline = os.clock() + 5
  while true do
    local left = deadline - os.clock()
    if left <= 0 then break end
    local id, reply = rednet.receive(PROTOCOL, left)
    if not id then break end
    if id == serverId and type(reply) == "table" and reply.rid == msg.rid then return reply end
  end
  serverId = BANK_ID -- look the bank up again next time
  return { ok = false, err = "The bank isn't responding" }
end

-- ---------- monitor UI ----------
local mon = peripheral.find("monitor")
if not mon or not mon.isColor() then error("Attach an ADVANCED (gold) monitor!", 0) end
mon.setTextScale(1)
local W, H = mon.getSize()
if W < 26 then mon.setTextScale(0.5); W, H = mon.getSize() end
if W < 26 or H < 10 then error("Monitor too small - build it at least 3 wide x 2 tall", 0) end

local buttons = {}
local function fmt(n) return string.format("%d", n) .. " " .. CUR end
local function clearMon()
  mon.setBackgroundColor(colors.black); mon.clear(); buttons = {}
end
local function center(y, text, fg, bg)
  text = text:sub(1, W)
  mon.setBackgroundColor(bg or colors.black); mon.setTextColor(fg or colors.white)
  mon.setCursorPos(math.floor((W - #text) / 2) + 1, y); mon.write(text)
end
local function header(title)
  mon.setBackgroundColor(colors.orange); mon.setCursorPos(1, 1); mon.write(string.rep(" ", W))
  center(1, title, colors.black, colors.orange)
end
local function button(id, x, y, w, label, bg)
  mon.setBackgroundColor(bg); mon.setTextColor(colors.white)
  mon.setCursorPos(x, y); mon.write(string.rep(" ", w))
  label = label:sub(1, w)
  mon.setCursorPos(x + math.floor((w - #label) / 2), y); mon.write(label)
  buttons[#buttons + 1] = { id = id, x1 = x, x2 = x + w - 1, y = y }
end
local function wide(id, y, label, bg) button(id, 3, y, W - 4, label, bg) end
local function pair(y, id1, l1, c1, id2, l2, c2)
  local hw = math.floor((W - 5) / 2)
  button(id1, 2, y, hw, l1, c1)
  button(id2, W - hw, y, hw, l2, c2)
end
local function hit(x, y)
  for _, b in ipairs(buttons) do
    if y == b.y and x >= b.x1 and x <= b.x2 then return b.id end
  end
end

-- ---------- computer screen ----------
local function color(c) term.setTextColor(c) end
local function termTitle(text)
  term.setBackgroundColor(colors.black); term.clear(); term.setCursorPos(1, 1)
  color(colors.orange); print("=== EMBER BANK ATM ===")
  color(colors.white); if text then print(text) end
  print()
end
local function termIdle() termTitle("Use the touch screen to get started.") end

local function adminCheck()
  termTitle("Stopping the ATM requires the admin password.")
  write("Admin password: ")
  local pw
  parallel.waitForAny(function() pw = read("*") end, function() sleep(20) end)
  if pw == ADMIN_PASSWORD then error("ADMIN_EXIT", 0) end
  termIdle()
end

-- Waits for a monitor button. Returns its id, or "timeout".
local function waitButton(timeout)
  local timer = timeout and os.startTimer(timeout)
  while true do
    local ev, a, b, c = os.pullEventRaw()
    if ev == "monitor_touch" then
      local id = hit(b, c)
      if id then if timer then os.cancelTimer(timer) end return id end
    elseif ev == "timer" and a == timer then
      return "timeout"
    elseif ev == "terminate" then
      adminCheck()
    end
  end
end

-- Asks for typed input on the computer. Returns nil on cancel/timeout.
-- The monitor must already show a button with id "cancel".
local function prompt(label, mask)
  color(colors.yellow); write(label); color(colors.white)
  local result
  parallel.waitForAny(
    function() result = read(mask) end,
    function() sleep(45) end,
    function()
      while true do
        local _, _, x, y = os.pullEventRaw("monitor_touch")
        if hit(x, y) == "cancel" then return end
      end
    end)
  print()
  if result == "" then return nil end
  return result
end

local function typeScreen(title, lines)
  clearMon(); header(title)
  for i, l in ipairs(lines) do center(2 + i, l, colors.lightGray) end
  center(4 + #lines, "<< type on the computer >>", colors.yellow)
  wide("cancel", H - 1, "Cancel", colors.red)
end

local function working()
  clearMon(); header("EMBER BANK"); center(math.floor(H / 2), "Please wait...", colors.yellow)
end

local function message(title, lines, good)
  clearMon(); header(title)
  local y = 3
  for _, text in ipairs(lines) do
    local line = ""
    for word in text:gmatch("%S+") do -- word-wrap long messages
      if #line + #word + 1 > W - 2 and line ~= "" then center(y, line, good and colors.lime or colors.red); y = y + 1; line = word
      else line = (line == "" and word) or (line .. " " .. word) end
    end
    center(y, line, good and colors.lime or colors.red); y = y + 1
  end
  wide("ok", H - 1, "OK", colors.gray)
  waitButton(15)
end

-- ---------- screens ----------
local session -- { user = ..., pass = hash }

local function doSend()
  typeScreen("SEND MONEY", { "Enter who to pay and", "how much." })
  termTitle("SEND MONEY  (leave blank to cancel)")
  local to = prompt("Send to (username): ")
  if not to then return end
  to = to:lower()
  local amountText = prompt("Amount (" .. CUR .. "): ")
  if not amountText then return end
  local amount = tonumber(amountText)
  if not amount or amount <= 0 or amount ~= math.floor(amount) then
    termIdle(); message("ERROR", { "Amount must be a", "whole number above 0" }) return
  end
  local note = prompt("Note (optional): ") or ""
  termIdle()

  clearMon(); header("CONFIRM")
  center(3, "Send", colors.lightGray)
  center(4, fmt(amount), colors.lime)
  center(5, "to " .. to, colors.white)
  if note ~= "" then center(6, '"' .. note:sub(1, 30) .. '"', colors.lightGray) end
  pair(H - 1, "yes", "Confirm", colors.green, "no", "Cancel", colors.red)
  if waitButton(30) ~= "yes" then return end

  working()
  local r = request({ action = "transfer", user = session.user, pass = session.pass, to = to, amount = amount, note = note })
  if r.ok then message("SENT!", { fmt(amount) .. " sent to " .. to, "New balance: " .. fmt(r.balance) }, true)
  else message("FAILED", { r.err }) end
end

local function doHistory()
  working()
  local r = request({ action = "history", user = session.user, pass = session.pass })
  if not r.ok then message("ERROR", { r.err }) return end
  local list = r.history

  -- full detail on the computer screen
  termTitle("Recent transactions for " .. session.user .. ":")
  for i = 1, math.min(#list, 14) do
    local h = list[i]
    color(h.amount >= 0 and colors.lime or colors.red)
    write(string.format("%+8d ", h.amount)); color(colors.lightGray)
    print((h.time .. " " .. h.desc):sub(1, 40))
  end
  color(colors.white)

  local perPage = H - 3
  local pages = math.max(1, math.ceil(#list / perPage))
  local page = 1
  while true do
    clearMon(); header("HISTORY " .. page .. "/" .. pages)
    if #list == 0 then center(3, "No transactions yet", colors.lightGray) end
    for i = 1, perPage do
      local h = list[(page - 1) * perPage + i]
      if h then
        local amt = string.format("%+d ", h.amount)
        mon.setCursorPos(1, 1 + i)
        mon.setBackgroundColor(colors.black)
        mon.setTextColor(h.amount >= 0 and colors.lime or colors.red); mon.write(amt)
        mon.setTextColor(colors.white); mon.write(h.desc:sub(1, W - #amt))
      end
    end
    local third = math.floor((W - 4) / 3)
    button("prev", 2, H, third, "<", colors.gray)
    button("back", 3 + third, H, W - 4 - 2 * third, "Back", colors.orange)
    button("next", W - third, H, third, ">", colors.gray)
    local b = waitButton(IDLE_LOGOUT)
    if b == "prev" then page = math.max(1, page - 1)
    elseif b == "next" then page = math.min(pages, page + 1)
    else termIdle() return end
  end
end

local function doChangePassword()
  typeScreen("NEW PASSWORD", { "Change your password." })
  termTitle("CHANGE PASSWORD  (leave blank to cancel)")
  local old = prompt("Current password: ", "*")
  if not old then termIdle() return end
  local new1 = prompt("New password: ", "*")
  if not new1 then termIdle() return end
  local new2 = prompt("New password again: ", "*")
  termIdle()
  if new1 ~= new2 then message("ERROR", { "Passwords didn't match" }) return end
  if #new1 < 4 then message("ERROR", { "Use at least 4 characters" }) return end
  working()
  local r = request({ action = "change_pass", user = session.user, pass = hashPw(session.user, old), newpass = hashPw(session.user, new1) })
  if r.ok then
    session.pass = hashPw(session.user, new1)
    message("DONE", { "Password changed" }, true)
  else message("FAILED", { r.err }) end
end

local function accountMenu()
  while session do
    working()
    local r = request({ action = "balance", user = session.user, pass = session.pass })
    if not r.ok then message("ERROR", { r.err }) return end
    clearMon(); header("EMBER BANK")
    center(3, "Hello, " .. session.user .. "!", colors.white)
    center(5, "Your balance", colors.lightGray)
    center(6, fmt(r.balance), colors.lime)
    pair(H - 3, "send", "Send money", colors.green, "history", "History", colors.blue)
    pair(H - 1, "password", "Password", colors.gray, "logout", "Log out", colors.red)
    local b = waitButton(IDLE_LOGOUT)
    if b == "send" then doSend()
    elseif b == "history" then doHistory()
    elseif b == "password" then doChangePassword()
    else session = nil end
  end
end

local function doLogin()
  typeScreen("LOG IN", { "Enter your username", "and password." })
  termTitle("LOG IN  (leave blank to cancel)")
  local user = prompt("Username: ")
  if not user then termIdle() return end
  local pw = prompt("Password: ", "*")
  termIdle()
  if not pw then return end
  user = user:lower()
  working()
  local pass = hashPw(user, pw)
  local r = request({ action = "login", user = user, pass = pass })
  if not r.ok then message("LOGIN FAILED", { r.err }) return end
  session = { user = user, pass = pass }
  accountMenu()
  session = nil
end

local function doRegister()
  typeScreen("OPEN ACCOUNT", { "Choose a username and", "a password." })
  termTitle("OPEN AN ACCOUNT  (leave blank to cancel)\nUsername: 3-16 letters, numbers or _")
  local user = prompt("Username: ")
  if not user then termIdle() return end
  local pw1 = prompt("Password: ", "*")
  if not pw1 then termIdle() return end
  local pw2 = prompt("Password again: ", "*")
  termIdle()
  if pw1 ~= pw2 then message("ERROR", { "Passwords didn't match" }) return end
  if #pw1 < 4 then message("ERROR", { "Use at least 4 characters" }) return end
  user = user:lower()
  working()
  local pass = hashPw(user, pw1)
  local r = request({ action = "register", user = user, pass = pass })
  if not r.ok then message("ERROR", { r.err }) return end
  message("WELCOME!", { "Account '" .. user .. "' created", "Remember your password!" }, true)
  session = { user = user, pass = pass }
  accountMenu()
  session = nil
end

local function main()
  while true do
    session = nil
    termIdle()
    clearMon(); header("EMBER BANK")
    center(3, "Welcome!", colors.yellow)
    center(4, "Currency: Ember Coins (" .. CUR .. ")", colors.lightGray)
    wide("login", H - 3, "Log in", colors.green)
    wide("register", H - 1, "Open an account", colors.blue)
    local b = waitButton(60) -- redraws every minute
    if b == "login" then doLogin()
    elseif b == "register" then doRegister() end
  end
end

-- ---------- run (restarts itself on errors) ----------
local oldPull = os.pullEvent
os.pullEvent = os.pullEventRaw -- players can't Ctrl+T out
while true do
  local ok, err = pcall(main)
  if not ok then
    if err == "ADMIN_EXIT" then break end
    pcall(function()
      clearMon(); header("ATM ERROR"); center(4, "Restarting...", colors.red)
    end)
    term.setTextColor(colors.red); print(err); sleep(5)
  end
end
os.pullEvent = oldPull
clearMon(); center(2, "ATM offline", colors.red)
term.clear(); term.setCursorPos(1, 1); print("ATM stopped. Type 'reboot' to start it again.")
