-- =====================================================
--  EMBER BANK - vending shop
--  Install on each shop computer as startup.lua
--  Needs: advanced computer + wireless modem + advanced monitor
--         (4 wide x 3 tall recommended) + a STOCK chest and an
--         OUTPUT chest, both touching the computer
--         (or connected to it with wired modems + cable)
--  Optional: a SELL chest, so players can sell items TO the shop
-- =====================================================

local BANK_ID        = 0          -- the bank computer's ID (shown on its screen). nil = find it automatically
local PROTOCOL = "emberbank"
local CUR      = "EC"
local CFG_FILE = "/shop.cfg"

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
  serverId = BANK_ID
  return { ok = false, err = "The bank isn't responding" }
end

-- ---------- config ----------
local cfg
local function saveCfg()
  local f = fs.open(CFG_FILE, "w"); f.write(textutils.serialize(cfg)); f.close()
end
local function loadCfg()
  if not fs.exists(CFG_FILE) then return false end
  local f = fs.open(CFG_FILE, "r"); cfg = textutils.unserialize(f.readAll()); f.close()
  return type(cfg) == "table"
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
local function wrap(text, width)
  local lines, line = {}, ""
  for word in text:gmatch("%S+") do
    if #line + #word + 1 > width and line ~= "" then lines[#lines + 1] = line; line = word
    else line = (line == "" and word) or (line .. " " .. word) end
  end
  if line ~= "" then lines[#lines + 1] = line end
  return lines
end
local function header(title)
  mon.setBackgroundColor(colors.orange); mon.setCursorPos(1, 1); mon.write(string.rep(" ", W))
  center(1, title, colors.black, colors.orange)
end
local function region(id, x1, y, x2) buttons[#buttons + 1] = { id = id, x1 = x1, x2 = x2, y = y } end
local function button(id, x, y, w, label, bg)
  mon.setBackgroundColor(bg); mon.setTextColor(colors.white)
  mon.setCursorPos(x, y); mon.write(string.rep(" ", w))
  label = label:sub(1, w)
  mon.setCursorPos(x + math.floor((w - #label) / 2), y); mon.write(label)
  region(id, x, y, x + w - 1)
end
local function wide(id, y, label, bg) button(id, 3, y, W - 4, label, bg) end
local function hit(x, y)
  for _, b in ipairs(buttons) do
    if y == b.y and x >= b.x1 and x <= b.x2 then return b.id end
  end
end

-- ---------- computer screen ----------
local function color(c) term.setTextColor(c) end
local function termTitle(text)
  term.setBackgroundColor(colors.black); term.clear(); term.setCursorPos(1, 1)
  color(colors.orange); print("=== " .. (cfg and cfg.name or "EMBER SHOP") .. " ===")
  color(colors.white); if text then print(text) end
  print()
end
local function termIdle()
  termTitle("Tap the screen to buy" .. ((cfg.intake and #cfg.buys > 0) and " or sell" or "") .. ". Uses your Ember Bank account.")
  color(colors.lightGray); print("Shop owner (" .. cfg.owner .. ")? Press O for the owner menu.")
  color(colors.white)
end

local ownerMenu -- defined later

-- Waits for a monitor button. Returns its id, "timeout" or "owner".
local function waitButton(timeout)
  local timer = timeout and os.startTimer(timeout)
  while true do
    local ev, a, b, c = os.pullEventRaw()
    if ev == "monitor_touch" then
      local id = hit(b, c)
      if id then if timer then os.cancelTimer(timer) end return id end
    elseif ev == "timer" and a == timer then
      return "timeout"
    elseif ev == "terminate" or (ev == "char" and a:lower() == "o") then
      if timer then os.cancelTimer(timer) end
      return "owner"
    end
  end
end

-- Typed input on the computer; nil on cancel/timeout. Monitor needs a "cancel" button.
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

local function working(text)
  clearMon(); header(cfg.name); center(math.floor(H / 2), text or "Please wait...", colors.yellow)
end

local function message(title, text, good)
  clearMon(); header(title)
  for i, l in ipairs(wrap(text, W - 2)) do center(2 + i, l, good and colors.lime or colors.red) end
  wide("ok", H - 1, "OK", colors.gray)
  waitButton(15)
end

-- ---------- inventory ----------
local function stockInv() return peripheral.wrap(cfg.stock) end
local function matches(item, listing) return item.name == listing.name and item.nbt == listing.nbt end

local function countStock(listing)
  local inv = stockInv()
  if not inv then return 0 end
  local total = 0
  for _, item in pairs(inv.list()) do
    if matches(item, listing) then total = total + item.count end
  end
  return total
end

local function deliver(listing, count)
  local inv = stockInv()
  local moved = 0
  for slot, item in pairs(inv.list()) do
    if moved >= count then break end
    if matches(item, listing) then
      moved = moved + inv.pushItems(cfg.output, slot, count - moved)
    end
  end
  return moved
end

-- ---------- buying FROM players ----------
local function countByName(invName, name)
  local inv = invName and peripheral.wrap(invName)
  local n = 0
  if inv then for _, it in pairs(inv.list()) do if it.name == name then n = n + it.count end end end
  return n
end

-- move up to `count` items called `name` from one chest to another; returns how many moved
local function moveByName(fromName, toName, name, count)
  local inv = peripheral.wrap(fromName)
  local moved = 0
  if not inv or count <= 0 then return 0 end
  for slot, it in pairs(inv.list()) do
    if moved >= count then break end
    if it.name == name then moved = moved + inv.pushItems(toName, slot, count - moved) end
  end
  return moved
end

-- how many more of this item the shop will take before it's "full"
local function roomFor(b)
  if not b.maxStock or b.maxStock <= 0 then return math.huge end
  return math.max(0, b.maxStock - countByName(cfg.stock, b.name))
end

local budgetCache = { value = nil, t = -1000 }
local function shopBudget(force)
  if force or os.clock() - budgetCache.t > 20 then
    local r = request({ action = "shop_info", shop = cfg.shopId, key = cfg.key })
    budgetCache = { value = r.ok and r.budget or nil, t = os.clock() }
  end
  return budgetCache.value
end
local function buyingEnabled() return cfg.intake ~= nil and #cfg.buys > 0 end

-- ---------- buying ----------
local function buy(listing, bundles)
  local items = bundles * listing.qty
  local total = bundles * listing.price
  clearMon(); header("PAY " .. fmt(total))
  center(3, bundles .. " x " .. listing.label .. (listing.qty > 1 and (" (x" .. listing.qty .. ")") or ""), colors.white)
  center(5, "Enter your Ember Bank", colors.lightGray)
  center(6, "username and password", colors.lightGray)
  center(7, "<< type on the computer >>", colors.yellow)
  wide("cancel", H - 1, "Cancel", colors.red)
  termTitle("PAY " .. fmt(total) .. " for " .. bundles .. " x " .. listing.label .. "  (blank = cancel)")
  local user = prompt("Username: ")
  local pw = user and prompt("Password: ", "*")
  termIdle()
  if not pw then return end
  user = user:lower()

  if countStock(listing) < items then message("SORRY", "Not enough stock left for that order.") return end

  working("Paying...")
  local note = bundles .. "x " .. listing.label
  local r = request({ action = "charge", shop = cfg.shopId, key = cfg.key, user = user, pass = hashPw(user, pw), amount = total, note = note })
  if not r.ok then message("PAYMENT FAILED", r.err) return end

  working("Dispensing...")
  local delivered = deliver(listing, items)
  if delivered < items then
    -- customer only pays for what they actually got
    local fair = math.floor(listing.price * delivered / listing.qty)
    local refund = total - fair
    local rr = { ok = true }
    if refund > 0 then rr = request({ action = "refund", shop = cfg.shopId, key = cfg.key, tx = r.tx, amount = refund }) end
    if rr.ok then
      message("PARTLY DELIVERED", "Only " .. delivered .. " of " .. items .. " items fit / were in stock. Refunded " .. fmt(refund) .. ".")
    else
      message("PROBLEM", "Only " .. delivered .. " of " .. items .. " items delivered and the refund failed (" .. rr.err .. "). Contact " .. cfg.owner .. ".")
    end
    return
  end
  message("THANK YOU!", "Collect your items from the chest. New balance: " .. fmt(r.balance), true)
end

local function productScreen(listing)
  local bundles = 1
  while true do
    local available = math.floor(countStock(listing) / listing.qty)
    if available < 1 then message("SOLD OUT", listing.label .. " is out of stock.") return end
    bundles = math.max(1, math.min(bundles, available))
    clearMon(); header(cfg.name)
    center(3, listing.label, colors.yellow)
    center(4, fmt(listing.price) .. (listing.qty > 1 and (" per " .. listing.qty) or " each"), colors.white)
    center(5, "Available: " .. available, colors.lightGray)
    local y = 7
    button("m10", 2, y, 5, "-10", colors.gray)
    button("m1", 8, y, 3, "-", colors.gray)
    button("p1", W - 9, y, 3, "+", colors.gray)
    button("p10", W - 5, y, 5, "+10", colors.gray)
    center(y, tostring(bundles), colors.white)
    center(9, "Total: " .. fmt(bundles * listing.price), colors.lime)
    wide("buy", H - 2, "Buy", colors.green)
    wide("back", H, "Back", colors.red)
    local b = waitButton(30)
    if b == "m10" then bundles = bundles - 10
    elseif b == "m1" then bundles = bundles - 1
    elseif b == "p1" then bundles = bundles + 1
    elseif b == "p10" then bundles = bundles + 10
    elseif b == "buy" then buy(listing, bundles) return
    elseif b == "owner" then ownerMenu() return
    else return end
  end
end

-- a player sells items to the shop through the SELL chest
local function sellFlow()
  clearMon(); header("SELL TO " .. cfg.name)
  center(3, "Put the items you want to sell", colors.white)
  center(4, "in the SELL chest, then tap Done.", colors.white)
  center(6, "Anything we don't buy stays in", colors.lightGray)
  center(7, "the chest for you to take back.", colors.lightGray)
  wide("done", H - 2, "Done", colors.green)
  wide("cancel", H, "Cancel", colors.red)
  local b = waitButton(120)
  if b == "owner" then ownerMenu() return end
  if b ~= "done" then return end

  working("Checking your items...")
  if not peripheral.wrap(cfg.intake) then message("ERROR", "The sell chest is missing - tell " .. cfg.owner .. ".") return end
  local budget = shopBudget(true)
  if not budget then message("ERROR", "Can't reach the bank right now. Try again soon.") return end
  local plan, total = {}, 0
  for _, bl in ipairs(cfg.buys) do
    local can = math.min(countByName(cfg.intake, bl.name), roomFor(bl))
    local bundles = math.min(math.floor(can / bl.qty), math.floor((budget - total) / bl.price))
    if bundles > 0 then
      plan[#plan + 1] = { b = bl, bundles = bundles }
      total = total + bundles * bl.price
    end
  end
  if #plan == 0 then
    message("NOTHING TO BUY", "We can't buy anything in the chest right now. It may not be on our list, we may be full, or the shop's budget is used up. Please take your items back.")
    return
  end

  clearMon(); header("SELL FOR " .. fmt(total))
  center(3, "Type your Ember Bank username", colors.white)
  center(4, "on the computer to get paid.", colors.white)
  center(6, "<< type on the computer >>", colors.yellow)
  wide("cancel", H - 1, "Cancel", colors.red)
  termTitle("SELLING for " .. fmt(total) .. "  (blank = cancel)")
  local user = prompt("Your username: ")
  termIdle()
  if not user then return end
  user = user:lower()

  clearMon(); header("CONFIRM SALE")
  local y = 3
  for _, p in ipairs(plan) do
    if y <= H - 5 then
      center(y, (p.bundles * p.b.qty) .. "x " .. p.b.label .. " = " .. fmt(p.bundles * p.b.price), colors.white)
      y = y + 1
    end
  end
  center(y + 1, "Pay " .. fmt(total) .. " to " .. user .. "?", colors.lime)
  local half = math.floor((W - 3) / 2)
  button("yes", 2, H - 1, half, "Sell", colors.green)
  button("no", W - half, H - 1, half, "Cancel", colors.red)
  if waitButton(30) ~= "yes" then return end

  working("Taking items...")
  local paid, moved, parts = 0, {}, {}
  for _, p in ipairs(plan) do
    local got = moveByName(cfg.intake, cfg.stock, p.b.name, p.bundles * p.b.qty)
    local extra = got % p.b.qty                 -- only whole bundles are bought
    if extra > 0 then got = got - moveByName(cfg.stock, cfg.intake, p.b.name, extra) end
    if got > 0 then
      moved[#moved + 1] = { name = p.b.name, n = got }
      paid = paid + math.floor(got / p.b.qty) * p.b.price
      parts[#parts + 1] = got .. "x " .. p.b.label
    end
  end
  if paid == 0 then
    message("PROBLEM", "Couldn't take the items (the shop's storage may be full). Your items are still in the chest.")
    return
  end
  working("Paying...")
  local r = request({ action = "shop_pay", shop = cfg.shopId, key = cfg.key, to = user, amount = paid, note = table.concat(parts, ", ") })
  if not r.ok then
    for _, m in ipairs(moved) do moveByName(cfg.stock, cfg.intake, m.name, m.n) end
    message("SALE FAILED", r.err .. ". Your items are back in the chest.")
    return
  end
  budgetCache.value = r.budget
  message("SOLD!", "Paid " .. fmt(paid) .. " to " .. user .. ". Anything we didn't buy is still in the chest.", true)
end

local shopMode = "buy"
local sellPage = 1

local function modeTabs()
  local half = math.floor(W / 2)
  button("mode:buy", 1, 2, half, "BUY", shopMode == "buy" and colors.green or colors.gray)
  button("mode:sell", half + 1, 2, W - half, "SELL TO US", shopMode == "sell" and colors.blue or colors.gray)
end

local function sellFront()
  clearMon(); header(cfg.name); modeTabs()
  local perPage = H - 5
  local pages = math.max(1, math.ceil(#cfg.buys / perPage))
  sellPage = math.min(sellPage, pages)
  for i = 1, perPage do
    local bl = cfg.buys[(sellPage - 1) * perPage + i]
    if bl then
      local y = 2 + i
      local full = roomFor(bl) < bl.qty
      local bg = (i % 2 == 0) and colors.gray or colors.black
      local right = full and "FULL" or ("pays " .. fmt(bl.price))
      local left = (bl.label .. (bl.qty > 1 and (" x" .. bl.qty) or "")):sub(1, W - #right - 2)
      mon.setBackgroundColor(bg); mon.setCursorPos(1, y); mon.write(string.rep(" ", W))
      mon.setCursorPos(2, y); mon.setTextColor(full and colors.lightGray or colors.white); mon.write(left)
      mon.setCursorPos(W - #right, y); mon.setTextColor(full and colors.red or colors.lightBlue); mon.write(right)
    end
  end
  local budget = shopBudget()
  center(H - 2, budget and ("Shop can still spend " .. fmt(budget)) or "Budget: can't reach bank", colors.lightGray)
  if pages > 1 then
    button("sprev", 2, H - 1, 5, "<", colors.gray)
    button("snext", W - 5, H - 1, 5, ">", colors.gray)
  end
  wide("sell", H, "SELL ITEMS", colors.blue)
  local b = waitButton(30)
  if b == "mode:buy" then shopMode = "buy"
  elseif b == "sprev" then sellPage = math.max(1, sellPage - 1)
  elseif b == "snext" then sellPage = math.min(pages, sellPage + 1)
  elseif b == "sell" then sellFlow()
  elseif b == "owner" then ownerMenu() end
end

local page = 1
local function shopFront()
  if not buyingEnabled() then shopMode = "buy" end
  if shopMode == "sell" then return sellFront() end
  clearMon(); header(cfg.name)
  if buyingEnabled() then modeTabs() else center(2, "Tap an item to buy", colors.lightGray) end
  local perPage = H - 4
  local pages = math.max(1, math.ceil(#cfg.listings / perPage))
  page = math.min(page, pages)
  if #cfg.listings == 0 then center(4, "Nothing for sale yet", colors.gray) end
  for i = 1, perPage do
    local idx = (page - 1) * perPage + i
    local l = cfg.listings[idx]
    if l then
      local y = 2 + i
      local stock = math.floor(countStock(l) / l.qty)
      local bg = (i % 2 == 0) and colors.gray or colors.black
      local right = stock > 0 and fmt(l.price) or "SOLD OUT"
      local left = l.label .. (l.qty > 1 and (" x" .. l.qty) or "")
      left = left:sub(1, W - #right - 2)
      mon.setBackgroundColor(bg); mon.setCursorPos(1, y); mon.write(string.rep(" ", W))
      mon.setCursorPos(2, y); mon.setTextColor(stock > 0 and colors.white or colors.lightGray); mon.write(left)
      mon.setCursorPos(W - #right, y); mon.setTextColor(stock > 0 and colors.lime or colors.red); mon.write(right)
      region("item:" .. idx, 1, y, W)
    end
  end
  if pages > 1 then
    local third = math.floor((W - 4) / 3)
    button("prev", 2, H, third, "< Prev", colors.gray)
    mon.setBackgroundColor(colors.black); center(H, page .. "/" .. pages, colors.lightGray)
    button("next", W - third, H, third, "Next >", colors.gray)
  end
  local b = waitButton(30) -- redraws every 30s so stock stays up to date
  if b == "mode:sell" then shopMode = "sell"
  elseif b == "mode:buy" then shopMode = "buy"
  elseif b == "prev" then page = math.max(1, page - 1)
  elseif b == "next" then page = math.min(pages, page + 1)
  elseif b == "owner" then ownerMenu()
  elseif b:sub(1, 5) == "item:" then productScreen(cfg.listings[tonumber(b:sub(6))]) end
end

-- ---------- owner menu (on the computer) ----------
local function ask(label, default)
  color(colors.yellow); write(label)
  if default then color(colors.lightGray); write("[" .. default .. "] ") end
  color(colors.white)
  local s = read()
  if s == "" then return default or "" end
  return s
end
local function askNumber(label, default)
  while true do
    local n = tonumber(ask(label, default and tostring(default)))
    if n and n > 0 and n == math.floor(n) then return n end
    color(colors.red); print("Enter a whole number above 0."); color(colors.white)
  end
end
local function pause() color(colors.lightGray); write("Press Enter..."); read(); color(colors.white) end

-- distinct items in the stock chest
local function scanStock()
  local inv = stockInv()
  local found, order = {}, {}
  for slot, item in pairs(inv.list()) do
    local key = item.name .. "|" .. tostring(item.nbt)
    if not found[key] then
      local detail = inv.getItemDetail(slot)
      found[key] = { name = item.name, nbt = item.nbt, label = detail and detail.displayName or item.name, count = 0 }
      order[#order + 1] = found[key]
    end
    found[key].count = found[key].count + item.count
  end
  return order
end

local function listListings()
  if #cfg.listings == 0 then print("No items listed.") return false end
  for i, l in ipairs(cfg.listings) do
    print(i .. ") " .. l.label .. "  " .. l.qty .. " for " .. fmt(l.price) .. "  (stock: " .. countStock(l) .. ")")
  end
  return true
end

local function addListing()
  local items = scanStock()
  if #items == 0 then print("The stock chest is empty. Put items in it first."); pause() return end
  print("Items in the stock chest:")
  for i, it in ipairs(items) do print(i .. ") " .. it.label .. " x" .. it.count) end
  local n = tonumber(ask("Which number? "))
  local it = n and items[n]
  if not it then return end
  local label = ask("Name shown on screen: ", it.label):sub(1, 20)
  local qty = askNumber("Items per purchase: ", 1)
  local price = askNumber("Price for " .. qty .. " (" .. CUR .. "): ")
  for _, l in ipairs(cfg.listings) do
    if l.name == it.name and l.nbt == it.nbt and l.qty == qty then
      l.price, l.label = price, label
      saveCfg(); print("Updated existing listing."); pause() return
    end
  end
  table.insert(cfg.listings, { name = it.name, nbt = it.nbt, label = label, qty = qty, price = price })
  saveCfg(); print("Added: " .. label .. ", " .. qty .. " for " .. fmt(price)); pause()
end

local function editListing()
  if not listListings() then pause() return end
  local l = cfg.listings[tonumber(ask("Which number? ")) or 0]
  if not l then return end
  l.label = ask("Name shown on screen: ", l.label):sub(1, 20)
  l.qty = askNumber("Items per purchase: ", l.qty)
  l.price = askNumber("Price for " .. l.qty .. " (" .. CUR .. "): ", l.price)
  saveCfg(); print("Saved."); pause()
end

local function removeListing()
  if not listListings() then pause() return end
  local n = tonumber(ask("Remove which number? ")) or 0
  if cfg.listings[n] then table.remove(cfg.listings, n); saveCfg(); print("Removed.") end
  pause()
end

local function moveListing()
  if not listListings() then pause() return end
  local n = tonumber(ask("Move which number to the top? ")) or 0
  if cfg.listings[n] then table.insert(cfg.listings, 1, table.remove(cfg.listings, n)); saveCfg() end
end

-- ----- items the shop BUYS from players -----
local function otherChests()
  local list = {}
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.hasType(name, "inventory") and name ~= cfg.stock and name ~= cfg.output then list[#list + 1] = name end
  end
  return list
end

local function chooseIntake()
  local invs = otherChests()
  if #invs == 0 then
    print("No spare chest found. Place a third chest (the SELL chest")
    print("customers put items into) touching the computer or on its")
    print("wired network, then try again.")
    pause()
    return false
  end
  print("Which chest is the SELL chest (customers put items in it)?")
  for i, n in ipairs(invs) do print(i .. ") " .. n) end
  local c = invs[tonumber(ask("Number: ")) or 0]
  if not c then return false end
  cfg.intake = c
  saveCfg()
  print("Sell chest set.")
  return true
end

local function niceName(id)
  local s = id:gsub("^.-:", ""):gsub("_", " ")
  return (s:gsub("^%l", string.upper))
end

local function listBuys()
  if #cfg.buys == 0 then print("You're not buying anything yet.") return false end
  for i, b in ipairs(cfg.buys) do
    print(i .. ") " .. b.label .. ": pay " .. fmt(b.price) .. " per " .. b.qty ..
      ((b.maxStock and b.maxStock > 0) and ("  (until " .. b.maxStock .. " in stock, have " .. countByName(cfg.stock, b.name) .. ")") or ""))
  end
  return true
end

local function askBuyDetails(b)
  b.label = ask("Name shown on screen: ", b.label):sub(1, 20)
  b.qty = askNumber("Items per sale (bundle size): ", b.qty or 1)
  b.price = askNumber("You PAY for " .. b.qty .. " (" .. CUR .. "): ", b.price)
  local m = tonumber(ask("Stop buying when you have this many in stock (0 = never): ", tostring(b.maxStock or 0)))
  b.maxStock = (m and m > 0) and math.floor(m) or 0
end

local function addBuy()
  if not cfg.intake and not chooseIntake() then return end
  local seen, opts = {}, {}
  for _, invName in ipairs({ cfg.intake, cfg.stock }) do
    local inv = peripheral.wrap(invName)
    if inv then
      for slot, it in pairs(inv.list()) do
        if not seen[it.name] and #opts < 12 then
          seen[it.name] = true
          local d = inv.getItemDetail(slot)
          opts[#opts + 1] = { name = it.name, label = d and d.displayName or niceName(it.name) }
        end
      end
    end
  end
  print("Pick an item in the SELL/STOCK chest, or type an item ID")
  print("(e.g. minecraft:oak_log  - F3+H shows IDs on tooltips):")
  for i, o in ipairs(opts) do print(i .. ") " .. o.label .. "  " .. o.name) end
  local s = ask("Number or ID: ")
  local item
  if tonumber(s) then item = opts[tonumber(s)]
  elseif s ~= "" then
    if not s:find(":") then s = "minecraft:" .. s end
    item = { name = s, label = niceName(s) }
  end
  if not item then return end
  local b = { name = item.name, label = item.label }
  for i, old in ipairs(cfg.buys) do
    if old.name == item.name then b = old; table.remove(cfg.buys, i) break end
  end
  askBuyDetails(b)
  table.insert(cfg.buys, b)
  saveCfg()
  print("Now buying " .. b.label .. ": " .. fmt(b.price) .. " per " .. b.qty)
  pause()
end

local function editBuy()
  if not listBuys() then pause() return end
  local b = cfg.buys[tonumber(ask("Which number? ")) or 0]
  if not b then return end
  askBuyDetails(b)
  saveCfg(); print("Saved."); pause()
end

local function removeBuy()
  if not listBuys() then pause() return end
  local n = tonumber(ask("Stop buying which number? ")) or 0
  if cfg.buys[n] then table.remove(cfg.buys, n); saveCfg(); print("Removed.") end
  pause()
end

local function setBudget(passHash)
  local now = shopBudget(true)
  print("Buying budget left: " .. (now and fmt(now) or "unknown (can't reach bank)"))
  print("This is the most the shop will pay players in total,")
  print("taken from your account. Top it up whenever it runs low.")
  local n = tonumber(ask("New budget (" .. CUR .. "), blank = keep: "))
  if not n then return end
  if n < 0 or n ~= math.floor(n) then print("Must be a whole number."); pause() return end
  local r = request({ action = "shop_budget", user = cfg.owner, pass = passHash, shop = cfg.shopId, budget = n })
  if r.ok then budgetCache.value = r.budget; print("Budget set to " .. fmt(r.budget))
  else color(colors.red); print(r.err); color(colors.white) end
  pause()
end

function ownerMenu()
  clearMon(); header(cfg.name); center(math.floor(H / 2), "Shop is being restocked", colors.yellow)
  termTitle("OWNER LOGIN for " .. cfg.owner .. "  (blank = cancel)")
  local pw
  parallel.waitForAny(function() pw = read("*") end, function() sleep(30) end)
  if not pw or pw == "" then return end
  local passHash = hashPw(cfg.owner, pw)
  local r = request({ action = "login", user = cfg.owner, pass = passHash })
  if not r.ok then color(colors.red); print(r.err); sleep(2) return end

  while true do
    term.setBackgroundColor(colors.black); term.clear(); term.setCursorPos(1, 1)
    color(colors.orange); print("== OWNER MENU: " .. cfg.name .. " ==  balance " .. fmt(r.balance))
    color(colors.lime); print("SELLING to players:"); color(colors.white)
    print(" 1) Add item   2) Change item   3) Remove item")
    print(" 4) Move item to top   5) Show items and stock")
    color(colors.lightBlue); print("BUYING from players:"); color(colors.white)
    print(" 6) Add item   7) Change item   8) Remove item")
    print(" 9) Show items   B) Set buying budget")
    print(" C) Change sell chest" .. (cfg.intake and (" (now: " .. cfg.intake .. ")") or " (not set)"))
    color(colors.lightGray); print("SHOP:"); color(colors.white)
    print(" R) Rename shop   S) Stop the shop   0) Back")
    local c = ask("> "):lower()
    if c == "1" then addListing()
    elseif c == "2" then editListing()
    elseif c == "3" then removeListing()
    elseif c == "4" then moveListing()
    elseif c == "5" then listListings(); pause()
    elseif c == "6" then addBuy()
    elseif c == "7" then editBuy()
    elseif c == "8" then removeBuy()
    elseif c == "9" then listBuys(); pause()
    elseif c == "b" then setBudget(passHash)
    elseif c == "c" then chooseIntake()
    elseif c == "r" then cfg.name = ask("New name: ", cfg.name):sub(1, 24); saveCfg()
    elseif c == "s" then error("ADMIN_EXIT", 0)
    elseif c == "0" or c == "" then return end
  end
end

-- ---------- first-time setup ----------
local function setup()
  os.pullEvent = os.pullEventRaw
  term.clear(); term.setCursorPos(1, 1)
  color(colors.orange); print("=== EMBER SHOP SETUP ==="); color(colors.white)
  cfg = { listings = {}, buys = {} }

  local invs = {}
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.hasType(name, "inventory") then invs[#invs + 1] = name end
  end
  if #invs < 2 then
    error("Need 2 chests touching the computer (or on its wired network). Found " .. #invs .. ".", 0)
  end
  print("Chests found:")
  for i, name in ipairs(invs) do
    local inv = peripheral.wrap(name)
    local used = 0
    for _ in pairs(inv.list()) do used = used + 1 end
    print(i .. ") " .. name .. "  (" .. used .. "/" .. inv.size() .. " slots used)")
  end
  local s = invs[tonumber(ask("Which is the STOCK chest (hidden, holds items for sale)? ")) or 0]
  local o = invs[tonumber(ask("Which is the OUTPUT chest (customers take items from it)? ")) or 0]
  if not s or not o or s == o then error("Pick two different chests. Run the program again.", 0) end
  cfg.stock, cfg.output = s, o
  if #invs >= 3 then
    local i = ask("Which is the SELL chest (players put items in to sell)? Enter = none: ")
    local c = invs[tonumber(i) or 0]
    if c and c ~= s and c ~= o then cfg.intake = c end
  end

  cfg.name = ask("Shop name: ", "Ember Shop"):sub(1, 24)
  print()
  print("Now log in with YOUR Ember Bank account. Money from sales goes to this account.")
  local user = ask("Username: ")
  if user == "" then error("Cancelled.", 0) end
  user = user:lower()
  color(colors.yellow); write("Password: "); color(colors.white)
  local pw = read("*")
  local r = request({ action = "shop_register", user = user, pass = hashPw(user, pw), name = cfg.name })
  if not r.ok then error("Bank said: " .. r.err, 0) end
  cfg.shopId, cfg.key, cfg.owner = r.shop, r.key, r.owner
  saveCfg()
  color(colors.lime); print("Shop registered! (shop #" .. r.shop .. ")"); color(colors.white)
  print("Next: add items for sale. Put them in the stock chest first.")
  pause()
  while true do
    addListing()
    if ask("Add another item? (y/n) ", "y") ~= "y" then break end
  end
end

-- ---------- run ----------
local oldPull = os.pullEvent
os.pullEvent = os.pullEventRaw -- customers can't Ctrl+T out (Ctrl+T opens the owner login)
if not loadCfg() then
  local ok, err = pcall(setup)
  if not ok then
    os.pullEvent = oldPull
    if fs.exists(CFG_FILE) and not (cfg and cfg.key) then fs.delete(CFG_FILE) end
    printError(err) return
  end
end
if not cfg.listings then cfg.listings = {} end
if not cfg.buys then cfg.buys = {} end

while true do
  termIdle()
  local ok, err = pcall(shopFront)
  if not ok then
    if err == "ADMIN_EXIT" then break end
    pcall(function() clearMon(); header("SHOP ERROR"); center(4, "Restarting...", colors.red) end)
    term.setTextColor(colors.red); print(err); sleep(5)
  end
end
os.pullEvent = oldPull
clearMon(); center(2, "Shop closed", colors.red)
term.clear(); term.setCursorPos(1, 1); print("Shop stopped. Type 'reboot' to open it again.")
