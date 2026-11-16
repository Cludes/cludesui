# CludesUI

A World of Warcraft interface suite for Retail (12.x, Midnight) and WoW Forever. It is a set of addons that share one settings panel: action bars, unit frames, raid and party frames, nameplates, cooldown manager, resource bars, bags, chat, minimap, damage meters, quest tracker, Mythic+ tools and more.

## Install

1. Download the latest `CludesUI-vX.Y.Z.zip` from [Releases](https://github.com/Cludes/cludesui/releases).
2. Copy every `CludesUI...` folder into `World of Warcraft\_retail_\Interface\AddOns` (on WoW Forever, that client's own `Interface\AddOns`). The folders must sit directly in `AddOns`, so `AddOns\CludesUI\CludesUI.toc` exists.
3. Restart the game and enable the CludesUI addons.

Do not run CludesUI together with another full interface suite. They change the same parts of the interface.

## Use

- `/cui` opens the settings panel. `/cludes` and `/cludesui` do the same.
- `/unlock` opens Layout Mode, where you move and resize frames.
- `/ce` opens the global settings.
- `/rl` reloads the interface.

Each addon has a shortcut to its own settings page:

| Command | Page |
|---|---|
| `/cab` | Action Bars |
| `/cuf` | Unit Frames |
| `/crf` | Raid and Party Frames |
| `/cnp` | Nameplates |
| `/crbopt` | Resource Bars |
| `/ccmeopt` | Cooldown Manager |
| `/cabr` | Buff Reminders |
| `/cbsk` | Window Skins |
| `/cmm` | Minimap |
| `/cdb` | Info Bar |
| `/cfr` | Friends |
| `/cqtopts` | Quest Tracker |
| `/cqd` | Action Wheel |
| `/qol` | Utilities |

## Title Line

Your Mythic+ rating against the 0.1% and 1% title lines, with a season graph and a projected date. Its settings are in the panel under Title Line, which also opens the graph; `/titleline` opens the graph directly. The cutoffs come from Raider.IO and are refreshed in this repository once a day, so update CludesUI to get newer ones. If the standalone TitleLine addon is also installed, that one takes over and this module stays off.

## Tank Kit

For tanks: your co-tank's health, debuffs and defensives in a small frame, taunt alerts, and a row of the external defensives other players put on you. Move both frames in Layout Mode (`/unlock`). Settings are under Tank Kit; `/ctank` or right-clicking the frame opens them. If the standalone CoTankAuras addon is also installed, that one takes over and this module stays off.

## Raid Lead

For raid leaders and assistants. Its buttons are in the panel under Raid Lead (`/raidlead` opens it), or use these commands out of combat:

| Command | What it does |
|---|---|
| `/raidlead roles` | Sorts the raid into tanks, melee, ranged and healers, filling group 1 upward. |
| `/raidlead split` | Makes two balanced halves for split runs. |
| `/raidlead undo` | Puts everyone back where they were. |
| `/raidlead stop` | Stops a sort that is under way. |
| `/raidlead break 5` | Starts a 5 minute break bar for every CludesUI user in the group; `break 0` ends it. |

It also has:

- **Kick rotation.** Put an `intstart` / `intend` block in a boss note, one line of names per rotation, or type a Kick Order under Setup. A box shows whose interrupt is next, yellow when you are next and red with a sound when it is your turn. Each cast of your focus (or boss 1) moves it on.
- **Encounter reminders.** Under Raid Lead > Reminders, add a boss and paste its note from wowutils, wowaudit or a Method Raid Tools note. When the boss is pulled, the lines meant for you show a few seconds before their time with a countdown, and can be spoken and play a sound. A line with player names is for those players; `{tank}`, `{healer}`, `{dps}` and `{everyone}` work too. The leader or an assistant can send a note to every CludesUI user in the group. Phase timers (`{time:1:30,p2}`) are skipped, because the game gives addons no phase events.
- **Invites and assistants.** Save a roster and invite it in one click; promote a list of assistants, or have them promoted as they join.
- **Version check.** Who in the group runs CludesUI, and which version.
- **Ready check gear and cooldowns.** On a ready check, every CludesUI user reports their lowest durability, item level, missing enchants, raid cooldowns that are not ready, and a missing flask, food, augment rune or healthstone. The leader and assistants get a list, with anyone who did not answer.
- **Immunities on You.** Icons for Divine Shield, Blessing of Protection, Blessing of Spellwarding, Ice Block, Aspect of the Turtle and Cloak of Shadows while they are on you; add more by spell ID.
- **Aura Glows.** Add buffs or debuffs by spell ID; while one is on you, its icon shows with a glowing border and its time. Works in boss fights.
- **Aura Sounds.** Pick a spell ID and a sound plays when that aura is applied to you, gains a stack or falls off. The game plays it, so it works in boss fights and keys.
- **Group helpers.** A chat line when a CludesUI user drops a feast, cauldron, Soulwell or repair bot; "Gateway usable" when you can click a Demonic Gateway; and a crit / haste / mastery / versatility panel. Under Raid Lead > Tracking.
- **Boss Pace.** A target kill time per boss, and a bar of the boss's health against where it should be by now: green ahead, red behind. The pace is a straight line, so phases and intermissions throw it off.
- **Boss Timelines.** Every Midnight raid boss's abilities by difficulty, coloured by kind of mechanic. `/cbt` shows a boss's timeline before the pull; during the fight, bars count down to the next abilities (all of them, or only your role's), and alerts call Soak, Spread or Defensives a few seconds ahead. Phase changes are read from the boss's own timeline.
- **Nicknames.** Set yours once; CludesUI sends it to your guild and group and shows everyone's on raid frames (and unit frames, with Show Nicknames on). You can also paste `Character=Nickname` lines.

Damage dealers are counted as melee or ranged by class, which is a guess for Druids, Shamans and Hunters.

## WoW Forever: Forever Tools

On WoW Forever, Forever Tools adds pages to the panel.

### Training

The spells your trainer has for you right now with their total price, then what each of the next levels brings and costs. Spells that wait on a talent or a quest are listed apart, with the spell they need. A chat line says what is new when you level up. Prices are the trainer's base prices, so a reputation discount makes the real bill a little lower.

### General

- **Tracking Reminder.** Icons for tracking you know but have not turned on; click one to turn it on.
- **Swing Timer.** A bar per weapon filling to your next auto attack.
- **Mana Bar.** A druid's mana while in a form (or any mana user's), with the five-second rule.
- **Consumable Bar.** Your potions, elixirs, food, bandages, scrolls, stones and oils on a clickable bar.
- **Raid Debuffs.** The debuffs you pick on your target, bright while up and dim while missing.
- **Gear Sets.** Your equipment sets on a bar, with optional swaps while mounted or resting.
- **Instance Tracker.** New dungeons and raids against the hourly cap, run times and a summary when you leave.
- **Group Inspect** (`/cinspect`). Everyone in your group with level, item level and unenchanted slots.
- **Combat extras.** A combat timer, combat alerts and a stealth reminder for rogues and cat druids.
- **Bag Space.** Free slots, and the cheapest items you carry on hover.
- **Quest Automation.** Accepts and turns in quests (hold Shift to do it yourself) and can post progress to your party.
- **Action Bar Profiles** (`/cbars`). Save your bars, and optionally keybinds, to load on any character of the same class.
- **Loot Sparkles.** Keeps the sparkle on lootable quest items.
- **Best in Slot** (`/cbis`). Alt+Shift-click an item to make it your pick for its slot; tooltips mark BiS items and Drop Alert warns when one drops.
- **Stat Weights.** "+9% upgrade" on gear that beats what you wear for your spec.
- **Dungeon Journal** (`/cjournal`). Every dungeon and raid with bosses in kill order, loot and drop chances, a tip per boss, the quests, maps floor by floor, and a Reputation section.
- **Healer Mana** and **Pet Tracker.** Your group's healers by mana; a warning when a pet is missing, passive or low.
- **Mana Efficiency.** Healing or damage per mana and per second on spell tooltips.
- **Restock Reminder.** What you are short on when you reach a city or inn, with reagent and ammo buying.
- **XP per Hour** (`/cxp`) and **Group XP.** Your rate and time to level; a bar per group member.
- **Layer Tracker** and **Auto-Accept Layer Swap.** Which layer you are on, and the swap prompt confirmed when you join a group.
- **Mail and Alts.** Alt item counts on tooltips, an Alts button and Quick Attach at the mailbox, and expiry warnings.
- **Boat and Zeppelin Timers.** Departure and arrival countdowns on dock pins and a zone list.
- **Player History** (`/chistory`). The players you group with, with notes that show on their tooltip.
- **Town Map.** Your faction's service NPCs, mailboxes and spirit healers on the world map and minimap.
- **Blessing Bar** (`/cbless`). A button per class that blesses whoever needs it next, plus aura, seal and Righteous Fury, with assignments for every paladin.
- **Discovery** (`/cdiscovery`). Library books, the Cozy Sleeping Bag chain, a Field Journal, every quest of every zone, rares and Rare Alerts.
- **Professions** (`/cprof`). Each profession's next rank, recipes that still give skill, and a Recipe Finder.

### PvP

`/cpvp`: enemy players around you with alerts and stealth warnings, Kill on Sight with reasons, the last hour, an ignore list, statistics with your wins and losses, sharing with your group and guild, a Kill on Sight button on the target frame, a watch list, a combat map, Local Defense announcements and zones to stay off in. While it is on, enemy nameplates reach 60 yards so players show up sooner.

## Profiles

Profiles > Import Profile accepts CludesUI strings (they start with `!CUI_`) and strings in the older `!EUI_` format, which it converts as it imports.

## Adding your own addon's settings

Other addons can add a settings page to the CludesUI panel. See [PLUGINS_API.md](CludesUI/PLUGINS_API.md) and [SKINNING_API.md](CludesUI/SKINNING_API.md).

## Releasing

Run `sh tools/release.sh` (or `minor`, `major`, or an exact `X.Y.Z`). It puts the new version in every `.toc` and in `CludesUI.VERSION`, commits, tags and pushes. The tag builds `CludesUI-vX.Y.Z.zip` and publishes a release listing every change since the last one.

Every push to `master` runs a Lua syntax check and confirms that each file a `.toc` lists exists.

## Licence

Copyright (c) 2026 Cludes. All rights reserved. CludesUI is not open source: you may install and use it for yourself, but you may not copy, share, re-upload, modify for others, rebrand or reuse any part of it without written permission. See [LICENSE](LICENSE) for the full terms.
