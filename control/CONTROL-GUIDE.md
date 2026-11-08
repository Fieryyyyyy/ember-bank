# Ember Control: your admin app

One pocket app that controls everything: the **Bank** and the **Mining Fleet**. It's built so new systems can be added later as a single file each.

| File | Goes where |
|---|---|
| `ember.lua` | Your Advanced Pocket Computer (with a wireless or ender modem) |
| `ember-app-template.lua` | Optional: a working example app to copy when you add a new system |
| `../server.lua` | **Updated.** Reinstall it on the bank computer so the app can use admin features |

---

## 1. Turn on admin access at the bank

1. Reinstall the new `server.lua` on the bank computer (Pastebin, the same as before). Accounts are kept.
2. At the `bank>` prompt type:
   ```
   adminpw <a long password only you know>
   clear
   ```
   (`clear` wipes it off the screen. `adminpw` on its own turns app access off again.)

**How it's protected:**
- The password itself never goes over the air.
- Each admin action asks the bank for a one-time code, then signs the action with your password.
- Someone listening with their own modem can't replay or change your request.
- Wrong attempts are written to the bank log.

## 2. Install the app

On your pocket computer:
```
pastebin get <CODE> ember
ember
```
(Optional) To make it open on boot: `pastebin get <CODE> startup.lua`

Open **Settings** (the `*` tile):
- **Bank admin password → Set it**, and type the same password as `adminpw`. It's stored on the pocket computer as a hash.
- **Set PIN** (optional). The app then asks for a PIN when opened, in case someone picks up your pocket computer.
- **System computer IDs**: leave these on `auto`. Only set one if a system shows "offline" while you're in range (e.g. two computers share an ID).

---

## 3. Using it

**Home screen:**
- A tile per system, with a live summary:
  - Bank: total EC in the economy
  - Mining: how many turtles are working, or any alerts
- Tap a tile to open it. **`<`** (top-left) goes back. **Q** on the home screen closes the app.
- Scroll with the mouse wheel or by dragging.

**Bank**
- **Accounts:** everyone, richest first. Tap a player to see their balance and history, and to:
  - **Mint**: create new money and give it to them
  - **Take**: remove money
  - **Set**: set a balance exactly
  - **Reset password**: asks you to confirm first
- **Shops:** every registered shop. Tap one to **Set budget** (its buying budget) or **Remove shop**.
- **Log:** the bank's live log. Admin actions are orange and failed admin logins are red.

**Mining**
- **Turtles:** each turtle's state and a fuel gauge. The coloured dot means:
  - green: working
  - grey: idle
  - yellow: needs help
  - red: offline
- **Pause all / Resume / Recall** and **Refuel all / Cancel all** apply to the whole fleet. Recall and Cancel all ask first.
- Tap a turtle for its job, progress, ETA, position and fuel, plus **Pause / Resume / Recall / Cancel job / Refuel**.
- **Log:** the fleet log.

---

## 4. Adding a new system later

Every system is an **app**: one Lua file that returns a table. The three built-in systems use exactly the same format.

1. Copy `ember-app-template.lua` onto the pocket computer as `/ember/apps/myapp.lua`:
   ```
   mkdir ember/apps
   pastebin get <CODE> ember/apps/myapp.lua
   ```
2. Restart `ember`. A new tile appears.

The template is a working **Notes** app. Its comments list every tool you get: buttons, tabs, scrolling lists, prompts, yes/no dialogs, progress bars, saved settings, and `ember.request(...)` for talking to a system over rednet.

For a new system (e.g. a casino, door locks or a reactor), the server program just needs to:
```lua
rednet.host("myproto", "myserver")
-- for each request: reply with the same rid
local id, msg = rednet.receive("myproto")
rednet.send(id, { rid = msg.rid, ok = true, ... }, "myproto")
```
and the app calls `ember.request("myproto", "myserver", { type = "status" })`.

Ask me when you build the next system and I'll write its Ember Control app alongside it.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| Bank tile says **offline** | Set the admin password in Settings. If it still fails, open the Bank tile to read the exact error |
| "Admin access is off" | Run `adminpw <password>` on the bank computer (needs the new `server.lua`) |
| "Wrong admin password" | The password in Settings must match `adminpw` exactly. Set it again |
| A system shows "not responding" | Out of range (use ender modems), or that computer isn't running. Duplicate computer IDs also cause this: check with `id` |
| An extra app shows "App error" | The error is shown on screen. Fix that file in `/ember/apps/` |
| Forgot the app PIN | `delete ember/config` on the pocket computer (you'll need to re-enter the admin password) |
