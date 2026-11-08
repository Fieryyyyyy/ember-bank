-- =====================================================
--  EMBER BANK - main bank server
--  Install on the bank computer as startup.lua
--  Needs: computer + wireless modem (monitor optional, shows a live log)
-- =====================================================

local PROTOCOL      = "emberbank"
local CUR           = "EC"           -- currency symbol
local DATA_DIR      = "/bankdata"
local DATA_FILE     = DATA_DIR .. "/accounts.db"
local LOG_FILE      = DATA_DIR .. "/transactions.log"
local HISTORY_LEN   = 30             -- transactions kept per account
local START_BALANCE = 0              -- money new accounts start with

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
-- Same formula the ATMs and shops use, so the console can reset passwords
local function hashPw(user, pw) return sha256("emberbank:" .. user:lower() .. ":" .. pw) end

-- ---------- helpers ----------
math.randomseed(os.epoch("utc") + os.getComputerID() * 7919)
local function randomHex(n)
  local t = {}
  for i = 1, n do t[i] = string.format("%x", math.random(0, 15)) end
  return table.concat(t)
end
local function fmt(n) return string.format("%d", n) .. " " .. CUR end
local function now() return "Day " .. os.day() .. " " .. textutils.formatTime(os.time(), true) end
local function validName(u) return type(u) == "string" and #u >= 3 and #u <= 16 and not u:find("[^%w_]") end
local function validAmount(n) return type(n) == "number" and n > 0 and n == math.floor(n) and n <= 1e12 end
local function validHash(p) return type(p) == "string" and #p == 64 and not p:find("[^%x]") end

local mon = peripheral.find("monitor")
if mon then mon.setTextScale(0.5); mon.clear(); mon.setCursorPos(1, 1) end

local recent = {}   -- last log lines, for the admin app
local function log(text)
  local line = "[" .. now() .. "] " .. text
  table.insert(recent, 1, line)
  while #recent > 40 do table.remove(recent) end
  local f = fs.open(LOG_FILE, "a")
  if f then f.writeLine(line); f.close() end
  if mon then
    local _, h = mon.getSize()
    local _, y = mon.getCursorPos()
    if y > h then mon.scroll(1); y = h end
    mon.setCursorPos(1, y); mon.write(line); mon.setCursorPos(1, y + 1)
  end
end

-- ---------- data ----------
local data = { accounts = {}, shops = {}, nextShop = 1, nextTx = 1 }

local function save()
  local tmp = DATA_FILE .. ".tmp"
  local f = fs.open(tmp, "w")
  f.write(textutils.serialize(data))
  f.close()
  if fs.exists(DATA_FILE) then fs.delete(DATA_FILE) end
  fs.move(tmp, DATA_FILE)
end

local function load()
  if not fs.exists(DATA_DIR) then fs.makeDir(DATA_DIR) end
  local path = fs.exists(DATA_FILE) and DATA_FILE or (fs.exists(DATA_FILE .. ".tmp") and DATA_FILE .. ".tmp")
  if not path then return end
  local f = fs.open(path, "r")
  local loaded = textutils.unserialize(f.readAll())
  f.close()
  if type(loaded) ~= "table" then error("Bank data file is corrupted: " .. path, 0) end
  data = loaded
end

local function addHistory(acct, amount, desc)
  table.insert(acct.history, 1, { time = now(), amount = amount, desc = desc, bal = acct.balance })
  while #acct.history > HISTORY_LEN do table.remove(acct.history) end
end

-- Moves money between two accounts (caller has already checked everything)
local function transfer(from, to, amount, descFrom, descTo)
  local a, b = data.accounts[from], data.accounts[to]
  a.balance = a.balance - amount
  b.balance = b.balance + amount
  addHistory(a, -amount, descFrom)
  addHistory(b, amount, descTo)
  local tx = data.nextTx
  data.nextTx = tx + 1
  return tx
end

local function auth(msg)
  if type(msg.user) ~= "string" or type(msg.pass) ~= "string" then return nil, "Missing login details" end
  local user = msg.user:lower()
  local acct = data.accounts[user]
  if not acct or sha256(acct.salt .. msg.pass) ~= acct.hash then return nil, "Wrong username or password" end
  return acct, user
end

local function shopAuth(msg)
  local shop = data.shops[msg.shop]
  if not shop or shop.key ~= msg.key then return nil end
  return shop
end

-- ---------- network requests ----------
local handlers = {}

function handlers.ping() return { ok = true, currency = CUR } end

function handlers.register(msg)
  local user = type(msg.user) == "string" and msg.user:lower()
  if not validName(user) then return { ok = false, err = "Username must be 3-16 letters, numbers or _" } end
  if data.accounts[user] then return { ok = false, err = "That username is taken" } end
  if not validHash(msg.pass) then return { ok = false, err = "Bad password data" } end
  local salt = randomHex(16)
  local acct = { salt = salt, hash = sha256(salt .. msg.pass), balance = START_BALANCE, history = {}, created = now() }
  data.accounts[user] = acct
  addHistory(acct, START_BALANCE, "Account opened")
  save()
  log("New account: " .. user)
  return { ok = true }
end

function handlers.login(msg)
  local acct, user = auth(msg)
  if not acct then return { ok = false, err = user } end
  return { ok = true, user = user, balance = acct.balance }
end
handlers.balance = handlers.login

function handlers.history(msg)
  local acct, user = auth(msg)
  if not acct then return { ok = false, err = user } end
  return { ok = true, balance = acct.balance, history = acct.history }
end

function handlers.transfer(msg)
  local acct, user = auth(msg)
  if not acct then return { ok = false, err = user } end
  local to = type(msg.to) == "string" and msg.to:lower()
  if not to or not data.accounts[to] then return { ok = false, err = "No account called '" .. tostring(msg.to) .. "'" } end
  if to == user then return { ok = false, err = "You can't send money to yourself" } end
  if not validAmount(msg.amount) then return { ok = false, err = "Amount must be a whole number above 0" } end
  if acct.balance < msg.amount then return { ok = false, err = "Not enough money (you have " .. fmt(acct.balance) .. ")" } end
  local note = type(msg.note) == "string" and msg.note ~= "" and (" (" .. msg.note:sub(1, 30) .. ")") or ""
  transfer(user, to, msg.amount, "Sent to " .. to .. note, "From " .. user .. note)
  save()
  log(user .. " -> " .. to .. ": " .. fmt(msg.amount) .. note)
  return { ok = true, balance = acct.balance }
end

function handlers.change_pass(msg)
  local acct, user = auth(msg)
  if not acct then return { ok = false, err = user } end
  if not validHash(msg.newpass) then return { ok = false, err = "Bad password data" } end
  acct.salt = randomHex(16)
  acct.hash = sha256(acct.salt .. msg.newpass)
  save()
  log("Password changed: " .. user)
  return { ok = true }
end

function handlers.shop_register(msg)
  local acct, user = auth(msg)
  if not acct then return { ok = false, err = user } end
  local name = type(msg.name) == "string" and msg.name:sub(1, 24) or "Shop"
  local id = data.nextShop
  data.nextShop = id + 1
  local key = randomHex(32)
  data.shops[id] = { owner = user, name = name, key = key, sales = {} }
  save()
  log("Shop #" .. id .. " '" .. name .. "' registered by " .. user)
  return { ok = true, shop = id, key = key, owner = user }
end

-- A shop charging a customer. The customer's password is required.
function handlers.charge(msg)
  local shop = shopAuth(msg)
  if not shop then return { ok = false, err = "This shop is not registered with the bank" } end
  local acct, user = auth(msg)
  if not acct then return { ok = false, err = user } end
  if user == shop.owner then return { ok = false, err = "You can't buy from your own shop" } end
  if not data.accounts[shop.owner] then return { ok = false, err = "Shop owner's account no longer exists" } end
  if not validAmount(msg.amount) then return { ok = false, err = "Bad amount" } end
  if acct.balance < msg.amount then return { ok = false, err = "Not enough money (you have " .. fmt(acct.balance) .. ")" } end
  local what = type(msg.note) == "string" and msg.note:sub(1, 40) or "purchase"
  local tx = transfer(user, shop.owner, msg.amount, shop.name .. ": " .. what, "Sale @" .. shop.name .. ": " .. what .. " to " .. user)
  table.insert(shop.sales, 1, { tx = tx, buyer = user, amount = msg.amount, refunded = 0 })
  while #shop.sales > 50 do table.remove(shop.sales) end
  save()
  log(shop.name .. ": " .. user .. " paid " .. fmt(msg.amount) .. " for " .. what)
  return { ok = true, tx = tx, balance = acct.balance }
end

-- A shop refunding part of a recent sale (e.g. its output chest was full).
-- Only possible for real sales from that shop, and only back to the buyer.
function handlers.refund(msg)
  local shop = shopAuth(msg)
  if not shop then return { ok = false, err = "This shop is not registered with the bank" } end
  local sale
  for _, s in ipairs(shop.sales) do if s.tx == msg.tx then sale = s break end end
  if not sale then return { ok = false, err = "Sale not found" } end
  if not validAmount(msg.amount) or msg.amount > sale.amount - sale.refunded then return { ok = false, err = "Bad refund amount" } end
  local owner = data.accounts[shop.owner]
  if not owner or not data.accounts[sale.buyer] then return { ok = false, err = "Account missing" } end
  if owner.balance < msg.amount then return { ok = false, err = "Shop owner can't cover the refund" } end
  sale.refunded = sale.refunded + msg.amount
  transfer(shop.owner, sale.buyer, msg.amount, "Refund @" .. shop.name .. " to " .. sale.buyer, "Refund from " .. shop.name)
  save()
  log(shop.name .. ": refunded " .. fmt(msg.amount) .. " to " .. sale.buyer)
  return { ok = true }
end

-- The shop owner sets how much their shop may spend buying items from players.
-- This caps what a shop can ever pay out, even if its key were stolen.
function handlers.shop_budget(msg)
  local acct, user = auth(msg)
  if not acct then return { ok = false, err = user } end
  local shop = data.shops[msg.shop]
  if not shop or shop.owner ~= user then return { ok = false, err = "That's not your shop" } end
  local b = msg.budget
  if type(b) ~= "number" or b < 0 or b ~= math.floor(b) or b > 1e12 then return { ok = false, err = "Budget must be a whole number" } end
  shop.budget = b
  save()
  log(shop.name .. ": buying budget set to " .. fmt(b))
  return { ok = true, budget = b }
end

function handlers.shop_info(msg)
  local shop = shopAuth(msg)
  if not shop then return { ok = false, err = "This shop is not registered with the bank" } end
  local owner = data.accounts[shop.owner]
  return { ok = true, budget = shop.budget or 0, ownerBalance = owner and owner.balance or 0 }
end

-- A shop paying a player for items they sold to it (comes out of the owner's account).
function handlers.shop_pay(msg)
  local shop = shopAuth(msg)
  if not shop then return { ok = false, err = "This shop is not registered with the bank" } end
  local to = type(msg.to) == "string" and msg.to:lower()
  if not to or not data.accounts[to] then return { ok = false, err = "No account called '" .. tostring(msg.to) .. "'" } end
  if to == shop.owner then return { ok = false, err = "You can't sell to your own shop" } end
  if not validAmount(msg.amount) then return { ok = false, err = "Bad amount" } end
  local budget = shop.budget or 0
  if msg.amount > budget then return { ok = false, err = "The shop's buying budget is used up (" .. fmt(budget) .. " left)" } end
  local owner = data.accounts[shop.owner]
  if not owner then return { ok = false, err = "Shop owner's account no longer exists" } end
  if owner.balance < msg.amount then return { ok = false, err = "The shop owner can't afford this right now" } end
  shop.budget = budget - msg.amount
  local what = type(msg.note) == "string" and msg.note:sub(1, 40) or "items"
  transfer(shop.owner, to, msg.amount, "Bought @" .. shop.name .. ": " .. what .. " from " .. to, "Sold to " .. shop.name .. ": " .. what)
  save()
  log(shop.name .. ": paid " .. to .. " " .. fmt(msg.amount) .. " for " .. what)
  return { ok = true, budget = shop.budget }
end

-- ---------- admin core (used by the console AND the Ember Control app) ----------
local admin = {}
local function acctOf(user)
  user = type(user) == "string" and user:lower() or nil
  local a = user and data.accounts[user]
  if not a then error("No account called '" .. tostring(user) .. "'", 0) end
  return a, user
end
local function wholeAmount(n, allowZero)
  n = tonumber(n)
  if not n or n ~= math.floor(n) or n > 1e12 or n < 0 or (n == 0 and not allowZero) then
    error("Amount must be a whole number" .. (allowZero and ", 0 or more" or " above 0"), 0)
  end
  return n
end
function admin.mint(user, n)
  local a, u = acctOf(user); n = wholeAmount(n)
  a.balance = a.balance + n; addHistory(a, n, "Deposit from the bank")
  save(); log("ADMIN minted " .. fmt(n) .. " to " .. u)
  return u .. " now has " .. fmt(a.balance)
end
function admin.take(user, n)
  local a, u = acctOf(user); n = math.min(wholeAmount(n), a.balance)
  a.balance = a.balance - n; addHistory(a, -n, "Removed by the bank")
  save(); log("ADMIN took " .. fmt(n) .. " from " .. u)
  return u .. " now has " .. fmt(a.balance)
end
function admin.set(user, n)
  local a, u = acctOf(user); n = wholeAmount(n, true)
  local diff = n - a.balance
  a.balance = n; addHistory(a, diff, "Balance set by the bank")
  save(); log("ADMIN set " .. u .. " to " .. fmt(n))
  return u .. " now has " .. fmt(n)
end
function admin.resethash(user, clientHash)
  local a, u = acctOf(user)
  if not validHash(clientHash) then error("Bad password data", 0) end
  a.salt = randomHex(16); a.hash = sha256(a.salt .. clientHash)
  save(); log("ADMIN reset password for " .. u)
  return "Password reset for " .. u
end
function admin.delshop(id)
  id = tonumber(id)
  if not id or not data.shops[id] then error("No shop with that id", 0) end
  local name = data.shops[id].name
  data.shops[id] = nil
  save(); log("ADMIN removed shop #" .. id)
  return "Removed shop " .. name
end
function admin.setbudget(id, n)
  id = tonumber(id); n = wholeAmount(n, true)
  local shop = id and data.shops[id]
  if not shop then error("No shop with that id", 0) end
  shop.budget = n; save(); log("ADMIN set budget of " .. shop.name .. " to " .. fmt(n))
  return shop.name .. " can now spend " .. fmt(n)
end

-- Admin requests use a one-time challenge, so a sniffed message can't be replayed.
-- sig = sha256(nonce .. ":" .. adminHash .. ":" .. op .. ":" .. a .. ":" .. b)
-- adminHash = sha256("emberadmin:" .. password), set with the 'adminpw' console command.
local nonces = {}
function handlers.admin_challenge()
  if not data.adminHash then return { ok = false, err = "Admin access is off. On the bank computer type: adminpw <password>" } end
  local t = os.clock()
  for n, exp in pairs(nonces) do if exp < t then nonces[n] = nil end end
  local n = randomHex(32)
  nonces[n] = t + 30
  return { ok = true, nonce = n }
end
function handlers.admin(msg, id)
  if not data.adminHash then return { ok = false, err = "Admin access is off" } end
  local exp = type(msg.nonce) == "string" and nonces[msg.nonce]
  if exp then nonces[msg.nonce] = nil end
  if not exp or os.clock() > exp then return { ok = false, err = "Request expired, try again" } end
  local op = tostring(msg.op)
  local want = sha256(msg.nonce .. ":" .. data.adminHash .. ":" .. op .. ":" .. tostring(msg.a or "") .. ":" .. tostring(msg.b or ""))
  if msg.sig ~= want then
    log("Wrong admin password from computer #" .. tostring(id))
    return { ok = false, err = "Wrong admin password" }
  end
  if op == "overview" then
    local accts, total = {}, 0
    for name, a in pairs(data.accounts) do accts[#accts + 1] = { name = name, balance = a.balance }; total = total + a.balance end
    table.sort(accts, function(x, y) return x.balance > y.balance end)
    local shops = {}
    for sid, sh in pairs(data.shops) do
      shops[#shops + 1] = { id = sid, name = sh.name, owner = sh.owner, budget = sh.budget or 0, sales = #(sh.sales or {}) }
    end
    table.sort(shops, function(x, y) return x.id < y.id end)
    local lines = {}
    for i = 1, math.min(25, #recent) do lines[i] = recent[i] end
    return { ok = true, accounts = accts, total = total, shops = shops, log = lines, currency = CUR }
  elseif op == "history" then
    local a = acctOf(msg.a)
    local h = {}
    for i, e in ipairs(a.history) do h[i] = { time = e.time, amount = e.amount, desc = e.desc } end
    return { ok = true, balance = a.balance, history = h }
  elseif admin[op] then
    local ok, res = pcall(admin[op], msg.a, msg.b)
    if ok then return { ok = true, msg = res } end
    return { ok = false, err = tostring(res) }
  end
  return { ok = false, err = "Unknown admin action" }
end

local function serve()
  while true do
    if not rednet.isOpen() then -- modem was swapped/replaced: re-open it
      local m = peripheral.find("modem", function(_, x) return x.isWireless() end)
      if m then rednet.open(peripheral.getName(m)); log("Modem re-opened") end
    end
    local id, msg = rednet.receive(PROTOCOL, 5)
    if type(msg) == "table" and type(msg.action) == "string" and msg.rid ~= nil then
      local handler = handlers[msg.action]
      local reply
      if handler then
        local ok, res = pcall(handler, msg, id)
        if ok then reply = res else
          reply = { ok = false, err = "Bank server error" }
          log("ERROR in " .. msg.action .. ": " .. tostring(res))
        end
      else
        reply = { ok = false, err = "Unknown request" }
      end
      reply.rid = msg.rid
      rednet.send(id, reply, PROTOCOL)
    end
  end
end

-- ---------- admin console ----------
local function color(c) if term.isColor() then term.setTextColor(c) end end
local function need(user)
  user = user and user:lower()
  local acct = user and data.accounts[user]
  if not acct then error("No account called '" .. tostring(user) .. "'", 0) end
  return acct, user
end
local function needAmount(s)
  local n = tonumber(s)
  if not validAmount(n) then error("Amount must be a whole number above 0", 0) end
  return n
end

local commands = {}
local help = {
  { "list", "show all accounts and balances" },
  { "bal <user>", "show one balance" },
  { "history <user>", "show recent transactions" },
  { "mint <user> <amount>", "create money and give it" },
  { "take <user> <amount>", "remove money from an account" },
  { "set <user> <amount>", "set a balance exactly" },
  { "resetpw <user> <newpass>", "reset a password" },
  { "delete <user>", "delete an account" },
  { "shops", "list registered shops" },
  { "delshop <id>", "unregister a shop" },
  { "adminpw <password>", "password for the Ember Control app (blank = off)" },
  { "total", "total money in the economy" },
}
function commands.help()
  for _, h in ipairs(help) do color(colors.yellow); write(h[1]); color(colors.lightGray); print("  - " .. h[2]) end
  color(colors.white)
end
function commands.list()
  local names = {}
  for name in pairs(data.accounts) do names[#names + 1] = name end
  table.sort(names)
  if #names == 0 then print("No accounts yet.") return end
  local lines = {}
  for _, n in ipairs(names) do lines[#lines + 1] = string.format("%-16s %s", n, fmt(data.accounts[n].balance)) end
  textutils.pagedPrint(table.concat(lines, "\n"))
end
function commands.bal(user) local a, u = need(user); print(u .. ": " .. fmt(a.balance)) end
function commands.history(user)
  local a = need(user)
  local lines = {}
  for _, h in ipairs(a.history) do
    lines[#lines + 1] = string.format("%s  %+d  %s", h.time, h.amount, h.desc)
  end
  textutils.pagedPrint(#lines > 0 and table.concat(lines, "\n") or "No history.")
end
function commands.mint(user, amount) print(admin.mint(user, amount)) end
function commands.take(user, amount) print(admin.take(user, amount)) end
function commands.set(user, amount) print(admin.set(user, amount)) end
function commands.resetpw(user, newpass)
  local _, u = need(user)
  if not newpass or newpass == "" then error("Usage: resetpw <user> <newpass>", 0) end
  print(admin.resethash(u, hashPw(u, newpass)))
end
function commands.adminpw(pw)
  if not pw or pw == "" then
    data.adminHash = nil; save(); log("ADMIN app access turned off"); print("Admin app access is now OFF.")
    return
  end
  if #pw < 6 then error("Use at least 6 characters", 0) end
  data.adminHash = sha256("emberadmin:" .. pw)
  save(); log("ADMIN app password changed"); print("Admin app password set. Use it in Ember Control.")
  print("Tip: type 'clear' now so nobody sees it on screen.")
end
function commands.clear() term.clear(); term.setCursorPos(1, 1) end
function commands.delete(user)
  local a, u = need(user)
  write("Delete " .. u .. " (" .. fmt(a.balance) .. ")? Type yes: ")
  if read() ~= "yes" then print("Cancelled.") return end
  data.accounts[u] = nil
  save(); log("ADMIN deleted account " .. u); print("Deleted.")
end
function commands.shops()
  local any = false
  for id, s in pairs(data.shops) do any = true; print("#" .. id .. "  " .. s.name .. "  (owner: " .. s.owner .. ", " .. #s.sales .. " recent sales, buying budget " .. fmt(s.budget or 0) .. ")") end
  if not any then print("No shops registered.") end
end
function commands.delshop(id)
  id = tonumber(id)
  if not id or not data.shops[id] then error("No shop with that id (see 'shops')", 0) end
  data.shops[id] = nil
  save(); log("ADMIN removed shop #" .. id); print("Shop removed.")
end
function commands.total()
  local sum, count = 0, 0
  for _, a in pairs(data.accounts) do sum = sum + a.balance; count = count + 1 end
  print(count .. " accounts holding " .. fmt(sum))
end

local function console()
  local hist = {}
  while true do
    color(colors.orange); write("bank> "); color(colors.white)
    local line = read(nil, hist)
    if line ~= "" then table.insert(hist, line) end
    local args = {}
    for word in line:gmatch("%S+") do args[#args + 1] = word end
    local cmd = table.remove(args, 1)
    if cmd then
      local f = commands[cmd:lower()]
      if f then
        local ok, err = pcall(f, table.unpack(args))
        if not ok then color(colors.red); print(err); color(colors.white) end
      else
        print("Unknown command. Type 'help'.")
      end
    end
  end
end

-- ---------- start ----------
load()
local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
if not modem then error("Attach a wireless modem to the bank computer!", 0) end
rednet.open(peripheral.getName(modem))
rednet.host(PROTOCOL, "bank")

term.clear(); term.setCursorPos(1, 1)
color(colors.orange); print("=== EMBER BANK SERVER ===")
color(colors.lightGray); print("Computer ID " .. os.getComputerID() .. " | type 'help' for commands")
color(colors.white)
log("Bank server started")
parallel.waitForAny(serve, console)
