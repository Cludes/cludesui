# CludesUI

A World of Warcraft interface suite for Retail (12.x, Midnight). It is a set of addons that share one settings panel: action bars, unit frames, raid and party frames, nameplates, cooldown manager, resource bars, bags, chat, minimap, damage meters, quest tracker, Mythic+ tools and more.

## Install

1. Download the latest zip from [Releases](https://github.com/Cludes/cludesui/releases), or download this repository as a zip.
2. Copy every `CludesUI...` folder into `World of Warcraft\_retail_\Interface\AddOns`. The folders must sit directly in `AddOns`, so `AddOns\CludesUI\CludesUI.toc` exists. If you downloaded the repository zip, open the `cludesui-master` folder inside it and copy the folders from there.
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

Title Line shows your Mythic+ rating against the 0.1% and 1% title lines, with a season graph and a projected date. Its settings are in the CludesUI panel under Title Line, which also opens the graph; `/titleline` opens the graph directly. Its cutoff numbers come from Raider.IO and are refreshed in this repository once a day, so update CludesUI to get newer ones. If you also run the standalone TitleLine addon, that one takes over and this module stays off.

## Tank Kit

Tank Kit is for tanks. It shows your co-tank's health, debuffs and defensives in a small frame, alerts you when to taunt, and shows a row of the external defensives other players put on you. Move both frames in Layout Mode (`/unlock`). Its settings are in the CludesUI panel under Tank Kit; `/ctank` opens them, and so does right-clicking the frame. If you also run the standalone CoTankAuras addon, that one takes over and this module stays off.

## Raid Lead

Raid Lead is for raid leaders and assistants. Its buttons are in the CludesUI panel under Raid Lead (`/raidlead` opens it), or use the commands, out of combat:

- `/raidlead roles` sorts the raid into tanks, melee, ranged and healers, filling group 1 upward.
- `/raidlead split` makes two balanced halves for split runs.
- `/raidlead undo` puts everyone back where they were.
- `/raidlead stop` stops a sort that is under way.
- **Kick rotation.** Put an `intstart` / `intend` block in a boss note, one line of names per rotation, or type a Kick Order under Setup. A box shows whose interrupt is next, yellow when you are next and red with a sound when it is your turn. Each cast of your focus (or boss 1) moves it on.
- `/raidlead break 5` starts a 5 minute break bar for every CludesUI user in the group; `/raidlead break 0` ends it.

Raid Lead also has:

- **Encounter reminders.** Under Raid Lead > Reminders, add a boss and paste its note from wowutils, wowaudit or a Method Raid Tools note. When the boss is pulled, the lines meant for you show a few seconds before their time with a countdown, and can be spoken and play a sound. A line with player names on it is for those players; `{tank}`, `{healer}`, `{dps}` and `{everyone}` work too. The leader or an assistant can send a note to every CludesUI user in the group. Phase timers (`{time:1:30,p2}`) are skipped, because the game gives addons no phase events. Move the reminders in Layout Mode.
- **Invites and assistants.** Save a roster and invite it in one click; promote a list of assistants, or have them promoted as they join.
- **Version check.** See who in the group runs CludesUI and which version.
- **Ready check gear and cooldowns.** On a ready check, every CludesUI user reports their lowest durability, item level, missing enchants (head, shoulders, chest, feet, rings, weapons), raid cooldowns that are not ready, and a missing flask, food, augment rune or healthstone. The leader and assistants get a list, with anyone who did not answer.
- **Immunities on You.** Icons for Divine Shield, Blessing of Protection, Blessing of Spellwarding, Ice Block, Aspect of the Turtle and Cloak of Shadows while they are on you; add more by spell ID.
- **Aura Glows.** Add buffs or debuffs by spell ID; while one is on you, its icon shows with a glowing border and its time. Works in boss fights.
- **Group helpers.** A chat line when a CludesUI user drops a feast, cauldron, Soulwell or repair bot; "Gateway usable" when you can click a Demonic Gateway; and a crit / haste / mastery / versatility panel. Under Raid Lead > Tracking.
- **Boss Pace.** Set a target kill time per boss. A bar shows the boss's health against where it should be by now: green ahead, red behind. The pace is a straight line, so phases and intermissions throw it off.
- **Nicknames.** Set your nickname once; CludesUI sends it to your guild and group, and shows everyone's on raid frames (and unit frames, with their Show Nicknames setting on). You can also paste `Character=Nickname` lines.

Aura Sounds: pick a spell ID and it plays a sound when that aura is applied to you, gains a stack or falls off. The game plays the sound itself, so it works in boss fights and keys.

Damage dealers are counted as melee or ranged by class, which is a guess for Druids, Shamans and Hunters.

## WoW Forever: Training Planner

On WoW Forever, Forever Tools has a Training page in the CludesUI panel. It lists the spells your trainer has for you right now with their total price, then what each of the next levels brings and costs. Spells that wait on a talent or a quest are listed apart, with the spell they need. When you level up, a chat line says what is new; turn it off on the same page. Prices are the trainer's base prices, so a reputation discount makes the real bill a little lower.

Forever Tools > General also has a **Tracking Reminder**: a row of icons for tracking you know but have not turned on (Find Treasure, hunter tracks, Track Humanoids in Cat Form, Sense Undead, Sense Demons, and optionally Find Herbs and Find Minerals). Click one to turn it on. The row hides in combat; move it in Layout Mode. The same page has a **Swing Timer**: a bar per weapon (main hand, off hand, ranged) filling to your next auto attack, using the swing length the game sends. A **Mana Bar** shows a druid's mana while in a form (or always, for any mana user), with a line counting down the five-second rule after you spend mana. A **Consumable Bar** puts the potions, elixirs, food, bandages, scrolls, stones and oils in your bags on a clickable bar with counts and cooldowns. **Raid Debuffs** shows the debuffs you pick (Sunder Armor, Faerie Fire, the curses and more) on your target, bright while up and dim while missing. **Gear Sets** puts your equipment sets on a bar to swap with a click, and can swap to a set while mounted or resting and put your gear back afterwards. The **Instance Tracker** counts new dungeons and raids against the hourly cap (10 per account on Forever), times your runs and prints a summary when you leave. **Group Inspect** (`/cinspect`) lists everyone in your group with level, item level and unenchanted slots. **Combat extras**: a combat timer, a + Combat / - Combat alert, and a stealth reminder for rogues and cat druids. **Bag Space** shows your free slots and, on hover, the cheapest items you carry. **Quest Automation** accepts and turns in quests (hold Shift to do it yourself) and can post objective progress to your party. **Action Bar Profiles** (`/cbars`) save your bars, and optionally keybinds, under a name to load on any character of the same class. **Loot Sparkles** keeps the sparkle on lootable quest items after graphics presets turn it off. **Best in Slot** (`/cbis`): Alt+Shift-click any item to make it your pick for its slot; the window shows which you have, tooltips mark BiS items, and Drop Alert warns when one drops. **Stat Weights** puts "+9% upgrade" on gear that beats what you wear for your spec, and each BiS pick's gain in the BiS window. The **Dungeon Journal** (`/cjournal`) lists every dungeon and raid with bosses in kill order, loot and drop chances, a tip per boss and the quests. **Healer Mana** lists your group's healers by mana, lowest first, and the **Pet Tracker** warns a hunter or warlock whose pet is missing, passive or low. **Mana Efficiency** adds healing or damage per mana and per second to mana spell tooltips. The **Restock Reminder** lists what you are short on (reagents, ammo, food, drink, junk, bag space) when you reach a city or inn, and can buy reagents and ammo for you; lockbox tooltips show the Lockpicking needed, an icon reminds you to swap gear with a drawback, and text shows unspent talent points. **XP per Hour** shows your rate, time to level and level times (`/cxp`), and **Group XP** shows a bar per group member running CludesUI or Naowh Forever. The **Layer Tracker** shows which layer you are on, with a countdown when the game is about to move you, and **Auto-Accept Layer Swap** confirms the swap prompt when you join a group. **Mail and Alts** adds alt item counts to tooltips, an Alts button and Quick Attach to the mailbox, and a warning when an alt's mail is about to expire.

Forever Tools also has a **PvP** page (`/cpvp`): enemy players around you with alerts and stealth warnings, Kill on Sight with reasons and a guild warning, the last hour, an ignore list, statistics with your wins and losses, sharing with your group and guild (compatible with Spy), announcing to chat, a Kill on Sight button on the target frame, enemy details on the minimap tooltip, a watch list for players of your own faction, a combat map of your wins and losses, Local Defense announcements (put in your chat box for you to send), and zones to stay off in.

## Profiles

Profiles > Import Profile accepts CludesUI strings (they start with `!CUI_`) and strings in the older `!EUI_` format, which it converts as it imports.

## Adding your own addon's settings

Other addons can add a settings page to the CludesUI panel. See [PLUGINS_API.md](CludesUI/PLUGINS_API.md) and [SKINNING_API.md](CludesUI/SKINNING_API.md).

## Releasing

1. Set the same version in `## Version` of every `.toc` file and in `CludesUI.VERSION` in `CludesUI/CludesUI.lua`.
2. Commit, then push a tag that matches, for example `v1.0.1`.
3. GitHub builds `CludesUI-v1.0.1.zip` and attaches it to a new release.

Every push to `master` runs a Lua syntax check and confirms that each file a `.toc` lists exists.

## Licence

Copyright (c) 2026 Cludes. All rights reserved. CludesUI is not open source: you may install and use it for yourself, but you may not copy, share, re-upload, modify for others, rebrand or reuse any part of it without written permission. See [LICENSE](LICENSE) for the full terms.
