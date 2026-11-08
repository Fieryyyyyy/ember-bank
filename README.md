# Ember systems for CC: Tweaked

ComputerCraft programs for our Cobbleverse server:
- **Ember Bank:** bank server, ATMs and vending shops.
- **Fleet Mining:** GPS towers, mining turtles, a control room and a pocket remote.
- **Ember Control:** an admin pocket app for all of it.

## Install or update

On each computer, run the line for its job. Running the same line again later updates it to the newest version. Settings you edited at the top of the file are kept: the ATM password, bank ID, control ID and GPS coordinates.

| Computer | Command |
|---|---|
| Bank server | `wget run https://raw.githubusercontent.com/Fieryyyyyy/ember-bank/main/install.lua bank` |
| ATM | `wget run https://raw.githubusercontent.com/Fieryyyyyy/ember-bank/main/install.lua atm` |
| Vending shop | `wget run https://raw.githubusercontent.com/Fieryyyyyy/ember-bank/main/install.lua shop` |
| GPS tower | `wget run https://raw.githubusercontent.com/Fieryyyyyy/ember-bank/main/install.lua gps` |
| Mining control room | `wget run https://raw.githubusercontent.com/Fieryyyyyy/ember-bank/main/install.lua control` |
| Mining turtle | `wget run https://raw.githubusercontent.com/Fieryyyyyy/ember-bank/main/install.lua miner` |
| Fleet pocket remote | `wget run https://raw.githubusercontent.com/Fieryyyyyy/ember-bank/main/install.lua remote` |
| Ember Control (admin pocket) | `wget run https://raw.githubusercontent.com/Fieryyyyyy/ember-bank/main/install.lua ember` |

Then type `reboot`. For the pocket apps, type `fleet` or `ember` to open them.

**Shortcut:** save the installer once with `wget https://raw.githubusercontent.com/Fieryyyyyy/ember-bank/main/install.lua install`. From then on, `install miner`, `install bank` and so on work on that computer.

## Guides

- [Bank, ATM and shop setup](SETUP-GUIDE.md)
- [Fleet mining setup](fleet/FLEET-GUIDE.md)
- [Ember Control](control/CONTROL-GUIDE.md)
