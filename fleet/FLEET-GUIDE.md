# Fleet Mining System: setup guide

Control a fleet of mining turtles from a touch-screen control room or your pocket computer. Turtles branch mine at the best Y level for the ore you pick, follow ore veins, quarry, dig tunnels, come home to unload and refuel on their own, and pick up where they left off after a chunk unload.

| File | Goes on | Install as |
|---|---|---|
| `gps_tower.lua` | 4 GPS computers | `startup.lua` (edit the coordinates) |
| `control.lua` | Control room computer | `startup.lua` |
| `miner.lua` | Every mining turtle | `startup.lua` |
| `remote.lua` | Your advanced pocket computer | `fleet` (or `startup.lua`) |

Upload each file to Pastebin like you did for the bank, then use `pastebin get <code> <name>` on each machine.

> ⚠️ **Every computer, turtle and pocket computer must have a different ID.** Don't copy them with middle-click in creative. Type `id` on any computer to check its ID.

---

## Step 0: What to craft

| Thing | Recipe / notes |
|---|---|
| **Mining turtle with ender modem** (one per turtle) | Craft a Turtle, then put the Turtle, a **Diamond Pickaxe** and an **Ender Modem** together in a crafting grid. |
| **Control room** | 1 Advanced Computer, 1 Ender Modem, Advanced Monitors (**4 wide × 3 tall** or bigger; minimum 3×2). |
| **Pocket remote** | Advanced Pocket Computer crafted together with an Ender Modem. |
| **GPS** | 4 Computers, 4 Ender Modems. |
| **Depot** | 2 Chests: one for fuel, one for drop-off. |
| **Fuel** | Coal, charcoal, coal blocks or lava buckets. |

Optional: put a **bucket** in a turtle and it will scoop up lava it finds while mining and burn it for free fuel (Settings → Collect lava).

---

## Step 1: GPS towers

Turtles use GPS to know exactly where they are, including after a reboot.

1. Go to your **spawn chunks** (near world spawn), which are always loaded. If GPS ever unloads, turtles can't find their way.
2. Place 4 computers that are **not all in one flat layer**. For example:
   - A at `(x, y, z)`
   - B 5 blocks east of A: `(x+5, y, z)`
   - C 5 blocks south of A: `(x, y, z+5)`
   - D 5 blocks **above** A, on a pillar: `(x, y+5, z)`
3. Put an **ender modem** on each.
4. On each computer:

```
label set GPS1
pastebin get <GPS_CODE> startup.lua
edit startup.lua
```

Set `local X, Y, Z = ...` to **that computer's own coordinates**. Look at the computer with **F3** open and read "Targeted Block". Save with Ctrl → Save, exit, then type `reboot`. It should say `GPS tower at ...` and `Serving GPS requests`.

5. **Test:** on any computer with a modem, type `gps locate`. It should print your position.

---

## Step 2: Build the depot

The depot is where turtles unload and refuel, and where idle turtles park. Build it **at ground level**, ideally in or near the spawn chunks too.

```
SIDE VIEW (looking north)                 TOP VIEW
                                                     N
    air   [FUEL CHEST]   air                         ^
 [ UP  ]  [   DOCK   ]  [DOWN ]           [UP][DOCK][DOWN]
 [shaft]  [DROP CHEST]  [shaft]           west        east
  (dug by turtles automatically)
```

- **DOCK**: an empty block where a turtle sits to unload. **Write down its X Y Z** (stand in it, or look at the block it sits in).
- **FUEL CHEST**: directly **above** the dock. Fill it with fuel.
- **DROP CHEST**: directly **below** the dock. Everything mined goes here. Tip: put hoppers under it, feeding a row of chests or your storage, so it never fills up.
- Leave the blocks **west** and **east** of the dock empty, with nothing above them. Turtles leave through the east side and come home through the west side, digging their own shafts down.
- Don't build anything directly **under** the drop chest. Idle turtles park in a column there, at their own lane depth.

**How traffic works:**
- Each turtle gets a **lane**: its own Y level 3 to 12 blocks below the dock, where it parks.
- **Going out:** it digs **straight down** the east shaft to the job's Y level, then tunnels across in X and Z to the start. (A job above the lane goes along the lane first, then up.)
- **Coming home:** it climbs to its lane, crosses at that depth so turtles never meet head-on, then queues in the west shaft to take turns at the dock.
- If one turtle is in another's way, it waits for it to move rather than digging it.

---

## Step 3: Control room

1. Place the Advanced Computer, the monitor wall touching it, and an ender modem on the computer.
2. Install:

```
label set Control
pastebin get <CONTROL_CODE> startup.lua
reboot
```

3. On the computer's own screen, set the dock coordinates from Step 2:

```
depot <x> <y> <z>
```

4. Note the **Computer ID** shown on screen. If turtles ever can't find the control room, set `CONTROL_ID` to this number at the top of `miner.lua` and `remote.lua`.

### Control computer commands

| Command | Does |
|---|---|
| `depot x y z` | Set the dock position |
| `junk add <id>` / `junk del <id>` / `junk list` | Edit the junk list (`junk add tuff` works too) |
| `rename <id> <name>` | Rename a turtle |
| `pause` / `resume` / `recall` / `refuel` / `cancel` `<id or all>` | Control turtles |
| `marker x y z` | Set a job start point by hand |
| `forget <id>` | Remove a turtle from the fleet (frees its lane) |
| `list` | List turtles, lanes and states |
| `resetstats` | Clear the ore totals |

---

## Step 4: Add turtles

For each turtle:
1. Put it **in the dock** spot. The dock must be empty.
2. Install:

```
pastebin get <MINER_CODE> startup.lua
reboot
```

3. It finds itself with GPS, gets a lane from the control room, takes some fuel from the fuel chest, then goes and **parks** under the depot.
4. Wait until it shows **Idle** on the control room before adding the next one.

---

## Step 5: Using the control room

### Tabs
- **Fleet**: every turtle with its state, a fuel bar, current job, progress with ETA, and inventory.
  - Tap a turtle for details, including **what it last got stuck on**, plus buttons: **Pause/Resume, Recall, Refuel, Cancel job, New job**.
  - The bottom buttons are **Pause all / Resume all / Recall all / Refuel all / Cancel all / + New job**. **Cancel all** asks you to confirm first.
  - **Refuel** sends a turtle to the depot to fill up. If it was mining, it goes straight back to the same spot afterwards.
- **Jobs**: active jobs with progress bars and ETAs.
- **Map**: a top-down live map with the depot (`D`), your marker (`+`), each turtle (numbered, coloured by state) and its job area.
- **Ores**: every ore with its **best Y level** and how many the fleet has mined. Tap **Mine** to start a branch mine at that ore's best Y.
- **Log**: ore finds with coordinates, jobs finished, alerts.
- **Settings**: **screen text size**, fuel reserve, refuel amount, burn mined coal, lava refuelling, and the junk list (tap to remove).

### Text size and scrolling
- **Settings → Screen text size**: `Auto`, or 0.5 (small) up to 3 (huge). It changes straight away.
  - On a 4×3 monitor, **1** is a good bigger size and **1.5** is the biggest that fits.
  - If you pick a size too big for your monitor, it uses the biggest one that fits and says so.
- On bigger text, screens switch to a compact layout: the tabs go onto two rows, and wide rows split over two lines.
- When a screen has more than fits, a **scroll bar** appears on the right:
  - Tap the **arrows** to move a few lines.
  - Tap **above or below the slider** to move a page.

### The job wizard (+ New job)
Use the `<` `>` and `-` `+` buttons to set:

| Job | Options |
|---|---|
| **Branch mine** | Target ore (sets the Y automatically), Y level, direction, start point, main tunnel length, branch length, branch spacing, branch sides, scan walls, follow veins, 2-high walkable tunnels, number of turtles |
| **Quarry** | Top Y, bottom Y, length, width, direction, start point, number of turtles (the area is split into strips) |
| **Tunnel / room** | Floor Y, width, height, length, direction, start point |

- **Start point:** "Depot + distance" goes that many blocks from the dock in the chosen direction. "Pocket marker" starts where you last pressed **Mark my position** on the pocket app.
- **Width** always extends to the **right** of the chosen direction.
- With **several turtles** on a branch job, each gets its own parallel tunnel system side by side.
- The estimate line shows the blocks to dig and the fuel needed per turtle.

### Best Y levels (1.20+)

| Ore | Y | Notes |
|---|---|---|
| Diamond | -58 | Most common near the bottom. Bedrock starts at -60 |
| Redstone | -58 | More the deeper you go |
| Lapis | 0 | |
| Gold | -16 | Badlands also have lots high up |
| Iron | 16 | Mountains have extra up high |
| Copper | 48 | Extra in dripstone caves |
| Coal | 45 | Peaks at 96, but that's inside mountains |
| Emerald | 100+ | Mountain biomes only |
| Evo stones | varies | Cobblemon evolution stone ores. Use "All ores" at the Y where you've found them |

### Recommended settings
- **Diamonds:** branch, Y -58, spacing 3, scan walls ON, follow veins ON. This finds nearly every diamond in the area.
- **Faster but less thorough:** scan walls OFF, spacing 4.
- **Everything at once:** target "All ores", which follows any ore vein it sees.

---

## Step 6: Pocket remote

```
pastebin get <REMOTE_CODE> fleet
fleet
```

- **Fleet**: all turtles with fuel and progress bars. Tap one for details and Pause / Recall / Refuel / Cancel.
- **Refuel all / Cancel all** are under the list. Cancel all needs a second tap within 4 seconds to confirm.
- **Mine here**: in a turtle's details, pick an ore and a direction, and that turtle starts a branch mine **from where you're standing**. Use F3 to see which way you're facing.
- **Mark my position**: saves your spot so the monitor's wizard can use "Pocket marker".
- **Log**: the latest finds and alerts.
- Press **Q** to close the app.

---

## How turtles behave

- **Inventory full:** junk is thrown away. If it's still full, the turtle goes home, unloads, refuels and comes back to the exact spot.
- **Low fuel:** it always keeps enough to get home plus the reserve, burns coal it mines (if enabled), and refuels at the depot.
- **Fuel chest empty / drop chest full:** it waits at the dock and shows an alert.
- **Chunk unloaded / server restart:** the turtle saves after every move, then uses GPS to resume exactly where it stopped. It shows as **Offline** on the control room while its chunk is unloaded.
- **Something it can't dig** (bedrock, a chest, an unbreakable block, a mob that won't move):
  - The turtle **logs what the block is and where**, e.g. `Blocked by bedrock below at 12,-59,40 - going around`.
  - It then tries to **go around**: over, under, left or right, then back onto its path.
- **No way around:**
  - **While mining:** it skips that bit of the job, logs `Skipped part of the job at ...`, and carries on with the rest.
  - **While travelling:** it stops and shows **ERROR** with the block's name and position. Fix it, then press **Resume**, or **Cancel** / **Recall** it home.
  - **Cancel** and **Recall** now work straight away, even after an error. No restart needed, and it takes a new job as soon as it's home.
- **Another turtle in the way:** it waits up to a minute for it to move, then goes around. Near the depot it always waits and never digs around, so the queue at the dock stays tidy.
- **Safety:** turtles never dig other turtles, computers, chests, barrels or shulker boxes.

## Troubleshooting

| Problem | Fix |
|---|---|
| Turtle says "No GPS signal" | GPS towers aren't running or are unloaded. Check `gps locate` on a computer |
| Turtle stuck on "Waiting for control room" | Set the depot (`depot x y z`), check the control room is running, and check the IDs are unique |
| Turtle shows Offline | Its chunk unloaded. It resumes when someone goes near. Chunk loaders help |
| "Can't work out which way I'm facing" | Give the turtle a little fuel by hand |
| Turtles dig into your base | Jobs go wherever you point them. Use the **Map** tab to check before launching big quarries |
| Want to move the depot | Recall all, wait until they're Idle, run `depot x y z` with the new spot, then move each turtle into the new dock and reboot it |

> Turtles only work in the dimension where your GPS and depot are, normally the Overworld.
