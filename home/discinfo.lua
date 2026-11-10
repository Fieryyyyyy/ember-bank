-- DISC INFO - shows what the game tells a computer about your music discs.
-- Run it on the Ember Home computer while no music is playing:
--   wget run https://raw.githubusercontent.com/Fieryyyyyy/ember-bank/main/home/discinfo.lua
-- It writes everything to discinfo.txt too.

local out = {}
local function say(s) s = tostring(s) print(s) out[#out + 1] = s end
local SIDES = { top = true, bottom = true, left = true, right = true, front = true, back = true }

local drives, chests = {}, {}
for _, n in ipairs(peripheral.getNames()) do
  if peripheral.hasType(n, "drive") then drives[#drives + 1] = n
  elseif peripheral.hasType(n, "inventory") then chests[#chests + 1] = n end
end
local dn
for _, d in ipairs(drives) do if not SIDES[d] then dn = d break end end
dn = dn or drives[1]
say("Drives: " .. table.concat(drives, ", ") .. "  (using " .. tostring(dn) .. ")")

local shown = 0
for _, c in ipairs(chests) do
  local p = peripheral.wrap(c)
  local ok, items = pcall(p.list)
  if ok and type(items) == "table" then
    for slot, it in pairs(items) do
      if shown < 4 and it.name:find("music_disc", 1, true) then
        shown = shown + 1
        say("")
        say("== " .. c .. " slot " .. slot)
        say("name: " .. it.name .. "   nbt: " .. tostring(it.nbt))
        local okD, d = pcall(p.getItemDetail, slot)
        if okD and type(d) == "table" then
          say("displayName: " .. tostring(d.displayName))
          local keys = {}
          for k in pairs(d) do keys[#keys + 1] = k end
          table.sort(keys)
          say("detail fields: " .. table.concat(keys, ", "))
          if type(d.lore) == "table" then for i, l in ipairs(d.lore) do say("lore " .. i .. ": " .. tostring(l)) end end
        end
        if dn then
          local okM, moved = pcall(p.pushItems, dn, slot, 1)
          if okM and moved and moved > 0 then
            local drv = peripheral.wrap(dn)
            local _, has = pcall(drv.hasAudio)
            local _, title = pcall(drv.getAudioTitle)
            say("drive: hasAudio=" .. tostring(has) .. "  title=" .. tostring(title))
            pcall(p.pullItems, dn, 1, 1, slot)
          else
            say("couldn't put it in the drive: " .. tostring(moved))
          end
        end
      end
    end
  end
end
if shown == 0 then say("No music discs found in any connected chest.") end

local f = fs.open("discinfo.txt", "w"); f.write(table.concat(out, "\n")); f.close()
print("")
print("Saved to discinfo.txt. To share it: pastebin put discinfo.txt")
