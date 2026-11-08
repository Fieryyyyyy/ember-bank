-- =====================================================
--  GPS TOWER - install on each of the 4 GPS computers as startup.lua
--  Needs: computer + ender modem
--  EDIT the 3 numbers below to THIS computer's exact coordinates
--  (look at the computer block with F3 open: "Targeted Block")
-- =====================================================

local X, Y, Z = 0, 0, 0

if X == 0 and Y == 0 and Z == 0 then
  print("Edit this file first! Type:  edit startup.lua")
  print("and set X, Y, Z to this computer's coordinates.")
  return
end
if not peripheral.find("modem") then
  print("Attach an ender modem to this computer!")
  return
end
print("GPS tower at " .. X .. ", " .. Y .. ", " .. Z)
shell.run("gps", "host", X, Y, Z)
