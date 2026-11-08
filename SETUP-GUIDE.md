# Ember Bank: setup guide

A banking system for CC: Tweaked (Fabric, MC 1.20+) using the currency **Ember Coins (EC)**.

| File | Goes on | Does |
|---|---|---|
| `server.lua` | 1 bank computer | Stores every account and balance, and has your admin console |
| `atm.lua` | Any number of ATMs | Open an account, check balance, send money, view history, change password |
| `shop.lua` | Any number of shops | Vending machine: owner sets items and prices, customers pay and items drop into a chest |

Players log in with a **username and password** (no physical card). Passwords are hashed before they are sent, so the actual password never travels over the network.

---

## Step 0: What to craft

| Machine | Blocks needed |
|---|---|
| Bank server | 1 Advanced Computer, 1 Wireless Modem (an Advanced Monitor is optional and shows a live transaction log) |
| Each ATM | 1 Advanced Computer, 1 Wireless Modem, **6 Advanced Monitors** (3 wide × 2 tall) |
| Each shop | 1 Advanced Computer, 1 Wireless Modem, **12 Advanced Monitors** (4 wide × 3 tall recommended, 3×2 minimum), 2 chests |

> **Monitors must be Advanced (gold).** Normal monitors can't be tapped.

---

## Step 1: Upload the code to Pastebin

1. Go to <https://pastebin.com>. A free account helps but isn't required.
2. Paste the entire contents of `server.lua` and click **Create New Paste**.
3. The URL will look like `pastebin.com/AbC123xY`. The code is the part after the slash (`AbC123xY`). Write it down.
4. Repeat for `atm.lua` and `shop.lua`. You now have **3 codes**.

> If `pastebin get` fails in-game, HTTP may be turned off. Check `config/computercraft-server.toml` (in the server's `config` folder) and make sure `[http] enabled = true`. It is on by default.

---

## Step 2: Build and start the bank server

**Location matters:**
- **Wireless modems reach about 64 blocks**, and further the higher up they are (both ends count). Put the bank **high up and central**, such as the top of a tower in town.
- **The bank's chunk must be loaded**, or every ATM and shop will say "The bank isn't responding" when nobody is nearby. Build it in the **spawn chunks** (always loaded), or keep it in a chunk loaded by a chunk-loader mod.
- Lock it away. Anyone who can get to it can use the admin console.

**Build:** place the Advanced Computer, then right-click any side of it with the Wireless Modem. Optionally place an Advanced Monitor touching it for the live log.

**Install:** right-click the computer and type:

```
label set Bank
pastebin get <SERVER_CODE> startup.lua
reboot
```

(`label set` makes the computer keep its files if it is ever broken and picked up. Do this on **every** computer.)

You should see `=== EMBER BANK SERVER ===` and a `bank>` prompt.

### Admin commands (typed at `bank>`)

| Command | What it does |
|---|---|
| `help` | List all commands |
| `list` | All accounts and balances |
| `bal steve` | One player's balance |
| `history steve` | A player's recent transactions |
| `mint steve 500` | **Create 500 EC** and give it to steve. This is the only way new money enters the economy |
| `take steve 50` | Remove money |
| `set steve 1000` | Set a balance exactly |
| `resetpw steve newpass` | Reset a forgotten password |
| `delete steve` | Delete an account (asks for confirmation) |
| `shops` / `delshop 3` | List or unregister shops |
| `total` | Total EC in circulation |

Data is saved to `/bankdata/accounts.db` after every change, and a full log is kept in `/bankdata/transactions.log`.

---

## Step 3: Build an ATM

**Build (from the front):**

```
   [M][M][M]      <- Advanced Monitors, 3 wide x 2 tall
   [M][M][M]
      [C]         <- Advanced Computer, directly under the monitor
```

- The monitor must **touch the computer**. Placing it directly above works well.
- Put the **Wireless Modem on the back or side** of the computer.
- Players tap the monitor and type their username and password on the computer.

**Install:**

```
label set ATM1
pastebin get <ATM_CODE> startup.lua
edit startup.lua
```

In the editor, **change the line `local ADMIN_PASSWORD = "changeme"`** to your own password. Save with Ctrl → Save → Enter, then exit with Ctrl → Exit → Enter. Then run:

```
reboot
```

**Using it (players):**
1. Tap **Open an account**, then type a username and password on the computer.
2. Tap **Log in** to see your balance, then **Send money**, **History** or **Password**.
3. Players are logged out after 60 seconds of no activity.

**To stop or edit an ATM:** hold **Ctrl+T** and enter the admin password. Players can't Ctrl+T out of it.

---

## Step 4: Build a shop

**Build (top-down view, customer stands at the bottom):**

```
        [Wall / hidden room]
   [STOCK]  [C]  [Modem]        STOCK chest is touching the computer, hidden behind the wall
           [OUT]                OUTPUT chest is under the computer (customers open it)
```

A simple setup that works:
- **Computer** facing the customer, built into a wall.
- **Advanced Monitor** (4×3) directly **above** the computer.
- **Wireless Modem** on the back of the computer.
- **Stock chest** on the computer's left or right side, **on the owner's side of the wall** so customers can't reach it.
- **Output chest** touching another side of the computer where customers can open it, such as directly underneath, sticking out of the wall.

> **Can't fit both chests next to the computer?** Put a **Wired Modem** on the computer and on each chest, connect them with **Networking Cable**, and right-click each wired modem to turn it on (it turns red). The chests can then be anywhere along the cable. Setup will list them by names like `minecraft:chest_0`.

**Install:**

```
label set Shop1
pastebin get <SHOP_CODE> startup.lua
reboot
```

**First-time setup** runs automatically:
1. It lists the chests it can see. Pick which one is **STOCK** and which is **OUTPUT**.
   (Tip: put one item in the stock chest first so you can tell them apart by "slots used".)
2. Name your shop.
3. Log in with **your own Ember Bank account**. Make one at an ATM first. All sales money goes into this account.
4. Add items: it lists what's in the stock chest. Pick one, then set:
   - **Name shown on screen**, e.g. `Diamond`
   - **Items per purchase**: `1` sells them singly, `16` sells packs of 16
   - **Price** for that many, in EC

The shop then opens. Customers tap an item, choose a quantity with the `-` and `+` buttons, tap **Buy**, and type their username and password on the computer. The items move into the output chest.

**Owner menu:** press **O** (or Ctrl+T) on the shop computer and enter your password. From there you can manage what you sell and what you buy, rename the shop (**R**), or stop it (**S**).

### Buying items FROM players (e.g. "I pay 10 EC per log")

1. Place a **third chest**, the **SELL chest**, touching the computer (or on its wired network) where customers can reach it.
2. Open the owner menu → **6) Add item** under BUYING. The first time, it asks which chest is the SELL chest.
3. Pick the item. Either put one in the SELL or stock chest and choose it from the list, or type its ID (e.g. `minecraft:oak_log`; press F3+H in-game to see IDs on item tooltips). Then set:
   - **Items per sale**: `1` pays per log, `16` pays per 16 logs
   - **You PAY**: how much the player gets for that many
   - **Stop buying at**: stop when you have this many in stock (0 = never stop)
4. Press **B) Set buying budget**. This is the **most the shop can pay out in total**, and it comes from your account. When it runs out, the shop stops buying until you top it up. This means the shop can never drain your account by accident.

The monitor now shows **BUY | SELL TO US** tabs. To sell:
1. The player taps **SELL TO US → SELL ITEMS**, puts their items in the SELL chest and taps **Done**.
2. The shop works out what it can buy and asks for their **username** (no password needed, since they're receiving money).
3. They check the total and tap **Sell**. The items move into your stock chest and they're paid straight away.
4. Anything the shop doesn't want (not on the list, over the stock limit, or past the budget) **stays in the SELL chest** for them to take back.

Items you buy go into the **stock chest**. So if you also list them for sale, players can buy them back from you, at a markup of course.

**Restocking:** just put more items in the stock chest. The screen updates every 30 seconds, and items show **SOLD OUT** when empty.

**Safety net:** if the output chest is full and not everything fits, the customer is automatically refunded for the items they didn't get.

---

## Step 5: Give people money

There is no starting balance. Once a player opens an account at an ATM, give them money from the bank server:

```
mint steve 100
```

---

## Troubleshooting

| Problem | Fix |
|---|---|
| "Can't reach the bank (out of range?)" | Too far for a wireless modem. Move the bank higher or closer. Or swap **all** wireless modems for **Ender Modems**, which have unlimited range and need no code changes |
| "The bank isn't responding" | The bank's chunk isn't loaded, or the server program stopped. Go to the bank computer and check it shows `bank>` |
| "Attach an ADVANCED (gold) monitor" | Normal monitors don't support touch. Replace them |
| "Monitor too small" | Build at least 3 wide × 2 tall |
| Shop setup finds 0 or 1 chest | The chests must touch the computer directly, or be on a wired-modem network with the modems turned on (red) |
| Shop says PAYMENT FAILED | The message says why: wrong password, not enough money, or you're the owner (owners can't buy from their own shop) |
| Shop says "budget is used up" | Owner menu → **B** and raise the buying budget |
| Want to redo a shop's setup | Owner menu → **S** (stop), then `delete shop.cfg`, then `reboot`. Run `delshop <id>` on the server to remove the old registration |
| Bank computer broken by accident | If it was labelled, place it again and all data is still there. Back up `/bankdata/accounts.db` now and then |

## Security notes (friends-only setup)

- Passwords are salted and hashed, and the real password never leaves the ATM or shop computer.
- A shop's secret key only lets it **charge customers who type their own password**, refund recent sales back to the buyer, and pay players for items **up to the buying budget its owner set**. It can't take money from anyone.
- This isn't hardened against a determined cheater. For example, someone with a disk drive could boot a computer from their own disk. That's fine for friends, but lock your bank computer in a room only you can get into.
