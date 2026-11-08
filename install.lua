-- =====================================================
--  EMBER INSTALLER - downloads the latest version from GitHub
--  Use on any computer:
--    wget run https://raw.githubusercontent.com/Fieryyyyyy/ember-bank/main/install.lua <role>
--  Roles: bank atm shop gps control miner remote ember
--  Running it again updates the program. Your settings at the top of
--  the file (ATM password, bank ID, GPS coordinates...) are kept.
-- =====================================================

local BASE = "https://raw.githubusercontent.com/Fieryyyyyy/ember-bank/main/"

local ROLES = {
  bank    = { file = "server.lua",          to = "startup.lua", banner = "EMBER BANK - main bank server", what = "Bank server" },
  atm     = { file = "atm.lua",             to = "startup.lua", banner = "EMBER BANK - ATM",              what = "ATM" },
  shop    = { file = "shop.lua",            to = "startup.lua", banner = "EMBER BANK - vending shop",     what = "Vending shop" },
  gps     = { file = "fleet/gps_tower.lua", to = "startup.lua", banner = "GPS TOWER",                     what = "GPS tower" },
  control = { file = "fleet/control.lua",   to = "startup.lua", banner = "FLEET CONTROL",                 what = "Mining control room" },
  miner   = { file = "fleet/miner.lua",     to = "startup.lua", banner = "FLEET MINER",                   what = "Mining turtle" },
  remote  = { file = "fleet/remote.lua",    to = "fleet",       banner = "FLEET REMOTE",                  what = "Fleet pocket remote" },
  ember   = { file = "control/ember.lua",   to = "ember",       banner = "EMBER CONTROL",                 what = "Ember Control (admin app)" },
}
local ORDER = { "bank", "atm", "shop", "gps", "control", "miner", "remote", "ember" }

-- settings lines copied from the old file into the new one
local KEEP = { "local ADMIN_PASSWORD", "local BANK_ID", "local CONTROL_ID", "local X, Y, Z",
               "local START_BALANCE", "local CUR ", "local IDLE_LOGOUT" }

local function color(c) if term.isColor() then term.setTextColor(c) end end

local function usage()
  color(colors.orange); print("Ember installer")
  color(colors.white); print("Usage: install <role>")
  for _, r in ipairs(ORDER) do
    color(colors.yellow); write(("  %-8s"):format(r))
    color(colors.lightGray); print(ROLES[r].what)
  end
  color(colors.white)
end

local function readFile(path)
  if not fs.exists(path) or fs.isDir(path) then return nil end
  local f = fs.open(path, "r"); local s = f.readAll(); f.close()
  return s
end

local function bannerOf(src)
  if not src then return nil end
  local head = src:sub(1, 400)
  for _, r in ipairs(ORDER) do
    if head:find(ROLES[r].banner, 1, true) then return r end
  end
  return nil
end

local function download(file)
  local url = BASE .. file .. "?t=" .. os.epoch("utc")       -- skip GitHub's cache
  local res, err = http.get(url)
  if not res then return nil, err end
  local body = res.readAll(); res.close()
  return body
end

-- copy the user's settings from the old version
local function keepSettings(new, old)
  if not old then return new, 0 end
  local kept = 0
  for _, prefix in ipairs(KEEP) do
    local oldLine
    for line in (old .. "\n"):gmatch("(.-)\r?\n") do
      if line:sub(1, #prefix) == prefix then oldLine = line break end
    end
    if oldLine then
      local out, done = {}, false
      for ln in (new .. "\n"):gmatch("(.-)\r?\n") do
        local line = ln
        if not done and line:sub(1, #prefix) == prefix then
          if line ~= oldLine then kept = kept + 1 end
          line, done = oldLine, true
        end
        out[#out + 1] = line
      end
      new = table.concat(out, "\n")
    end
  end
  return new, kept
end

local function writeFile(path, s)
  local f = fs.open(path, "w"); f.write(s); f.close()
end

local args = { ... }
local role = args[1] and args[1]:lower()
local R = role and ROLES[role]
if not R then usage() return end
if not http then
  color(colors.red); print("HTTP is turned off on this server (config: [http] enabled = true).")
  return
end

-- don't replace a different Ember program by accident (e.g. the bank!)
local current = readFile(R.to)
local was = bannerOf(current)
if was and was ~= role then
  color(colors.red)
  print("This computer is running the " .. ROLES[was].what .. ".")
  print("Replace it with the " .. R.what .. "? (y/n)")
  color(colors.white)
  local a = read()
  if a:lower() ~= "y" then print("Nothing changed.") return end
  current = nil
end

color(colors.lightGray); print("Downloading " .. R.file .. " ...")
local body, err = download(R.file)
if not body then color(colors.red); print("Download failed: " .. tostring(err)); return end
if not body:find(R.banner, 1, true) then
  color(colors.red); print("That download doesn't look right - try again in a minute."); return
end

local kept
body, kept = keepSettings(body, current)
writeFile(R.to, body)

-- pocket apps installed as startup.lua too: update that copy as well
if R.to ~= "startup.lua" and bannerOf(readFile("startup.lua")) == role then
  local s = keepSettings(body, readFile("startup.lua"))
  writeFile("startup.lua", s)
end

color(colors.lime)
print((current and "Updated " or "Installed ") .. R.what .. " as '" .. R.to .. "'.")
if kept > 0 then color(colors.lightGray); print("Kept " .. kept .. " of your settings.") end
color(colors.white)
if R.to == "startup.lua" then
  if role == "gps" and body:find("local X, Y, Z = 0, 0, 0", 1, true) then
    print("Now set this tower's coordinates:  edit startup.lua")
  elseif role == "atm" and body:find('ADMIN_PASSWORD = "changeme"', 1, true) then
    color(colors.orange); print("Set your ATM password first:  edit startup.lua"); color(colors.white)
  else
    print("Type 'reboot' to start it.")
  end
else
  print("Type '" .. R.to .. "' to open it.")
end
