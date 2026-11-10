# Ember Home: your house TV

One advanced monitor on the wall becomes a touchscreen TV with:
- **Music:** every disc in your disc chest shows as an album. Tap one to play it, or hit **Shuffle play**.
- **The Farm:** your farm chests, grouped into farms. Each farm is a **Breeding pen** or a **Loot farm** and shows how full it is, what's in it and how fast it's filling.

## What you need

| Block | Where |
|---|---|
| Advanced computer | Behind the TV wall, runs the program |
| Advanced monitors | The TV. Bigger is better, for example 6×4 or 8×5 |
| Disk drive | The record player. Put it in the middle of the house: everyone within 64 blocks hears it |
| Chest for your discs | Anywhere |
| Your farm chests | Breeding room, loot farm dungeon, and so on |
| Wired modems + networking cable | One modem on the computer, the disk drive and each chest |

The monitor right next to the computer works without a modem. The disk drive and the disc chest must both be on the cable network, so the computer can move discs between them.

**Connecting:** put a wired modem on each chest and on the disk drive, and run networking cable between them back to the computer. Then **right-click every modem** so it turns red (on). The chat message tells you its name, like `minecraft:chest_3`.

Chests next to each other share one cable network, so a big breeding room only needs one cable run.

## Install

On the advanced computer:
```
wget run https://raw.githubusercontent.com/Fieryyyyyy/ember-bank/main/install.lua home
```
then type `reboot`. It finds the monitor, the disk drive and the chests by itself.

On the computer's own screen: **R** rescans devices, **Q** quits.

## Music

- **Home** shows what's playing with a big **Shuffle play** button.
- **Music → Library:** all your discs as album covers. Tap one to play it. The next ones keep playing after it.
- **Music → Now playing:** the big player with previous, play/pause, next, **Shuffle**, **Repeat** (all / one / off) and what's up next.
- **Music → Queue:** the play order. Tap a song to jump to it, or **x** to take it out.
- The bar along the bottom of every screen controls the music too. Tap the album to open Now playing.

**How it plays:** when a song starts, the computer moves that disc from the chest into the disk drive and plays it. When the song ends, the disc goes back into the chest and the next one comes out. Discs don't wear out.

Leave the drive alone while music is on. A disc you put in by hand gets moved into a music chest.
- **Music chests:** you can have as many as you like. All their discs show up as one library.
  - The first time it starts, the program picks the chest with the most discs.
  - To add more: put a wired modem on the chest, connect it to the cable and right-click the modem so it turns red. Then do one of these:
    - **Settings → Music chests:** tap the button and tap a chest to tick it (**[x]**) or untick it.
    - **The Farm → Manage:** tap **Music** on the chest. Music chests are listed at the top, with **Not music** to remove one.
  - A disc goes back into the chest it came from. If that chest is full, it goes into another music chest.
- **Adding music:** put a disc in the chest and it shows up within 10 seconds. Take it out and it's gone from the list.
- **Modded discs**, like Cobbleverse's Poké Discs, work too.
  - The names come from the disc itself. When nothing is playing, the computer slips each new disc into the drive for a moment and reads its song name, such as "Yellow - Bike Theme". New discs show as "New disc" for a few seconds until then.
  - Poké Discs that look like the same item but hold different songs show up as separate discs.
  - If a disc can't play, its name goes red and it gets skipped.

**Two things the game can't do:**
- **No real pause.** Pause stops the song. Play starts it again from the beginning.
- **No volume control.** A disk drive plays as loud as a jukebox.

**Song lengths:** the program knows every vanilla disc's length, so it moves on at the right moment. The game doesn't tell it how long a modded song is, so those start at a guess of 3:00, shown in yellow as **Length (guess)** on **Now playing**. While the song plays, fix it with the **-10 / -1 / +1 / +10** buttons there. It's remembered for that disc. If the next song starts too early or late, adjust it again.

## The Farm

1. Open **The Farm → Manage**.
2. Tap **+ New farm** and type a name with the on-screen keyboard (for example "Spider Dungeon" or "Cow Pen").
3. Tap the coloured button on each farm to switch it between **Loot farm** and **Breeding pen**.
4. In the **Chests** list, tap **+ Add to farm** on each chest and pick its farm. A farm can have as many chests as you like.
5. Tap **Rename** on a chest to give it a name, like "Wool chest". Not sure which chest is which? Tap **Peek** to see what's in it.

**On The Farm screen:**
- Every farm is a card showing how full it is, how many items it holds, items per hour and what's in it most.
- Tap a farm to see its chests. Tap a chest to see everything inside, sorted by amount.
- Fullness bars turn yellow at 70% and red at 90%. The Home screen warns you when a chest is nearly full.
- Items per hour shows up after the farm has been watched for a couple of minutes. It resets when you empty a chest.

## Settings

- **Text size:** Auto picks the biggest text that still fits the TV. Turn it up or down with the arrows.
- **Music chests** and **Record player:** pick which chests hold discs and which disk drive plays them.
- **Rescan:** use after adding monitors, drives or chests. The program also does this by itself when a modem is turned on or off.
- **Software:** **Check** shows the newest version, **Update** downloads it and restarts. Your farms and settings are kept in `home.db`.
