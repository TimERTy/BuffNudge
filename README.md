# BuffNudge

A World of Warcraft: Midnight addon that reminds you about missing buffs when entering a dungeon or raid.

## Checks

- **Food buff** — alerts if you have no food/well-fed buff
- **Flask / Phial** — alerts if you have no flask or phial buff
- **Soulstone** — alerts if no soulstone is placed on anyone in your group
- **Enchants** — checks main hand, off hand, rings, and cloak for missing permanent enchants
- **Raid buffs** — alerts for any missing class buffs (Arcane Intellect, Battle Shout, Fort, MotW)

Only activates inside raid and party instances. Hides automatically when everything is covered.

## Install

Copy the `BuffNudge` folder into:

```
World of Warcraft/_retail_/Interface/AddOns/BuffNudge/
```

Then enable it in the AddOns menu on the character select screen.

## Setup

Spell IDs change between patches. Use the built-in setup panel to tag your own buffs:

1. Get buffed — eat food, drink your flask, grab raid buffs
2. Run `/bn setup`
3. Your current buffs appear as a list — click **+Food**, **+Flask**, or **+Raid** to tag each one
4. Click **Re-scan** if you apply more buffs while the panel is open
5. Close when done — tags are saved automatically

## Commands

| Command | Description |
|---|---|
| `/bn setup` | Open the buff tagging panel |
| `/bn check` | Run a check now |
| `/bn hide` | Hide the reminder panel |
| `/bn show` | Show the reminder panel |

## Notes

- Built for WoW: Midnight (patch 12.x) — does not use restricted combat APIs
- Reminder panel is draggable
- All tagged spell IDs persist across sessions via SavedVariables
