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
- `/raidlead break 5` starts a 5 minute break bar for every CludesUI user in the group; `/raidlead break 0` ends it.

Raid Lead also has:

- **Encounter reminders.** Under Raid Lead > Reminders, add a boss and paste its note from wowutils, wowaudit or a Method Raid Tools note. When the boss is pulled, the lines meant for you show a few seconds before their time with a countdown, and can be spoken and play a sound. A line with player names on it is for those players; `{tank}`, `{healer}`, `{dps}` and `{everyone}` work too. The leader or an assistant can send a note to every CludesUI user in the group. Phase timers (`{time:1:30,p2}`) are skipped, because the game gives addons no phase events. Move the reminders in Layout Mode.
- **Invites and assistants.** Save a roster and invite it in one click; promote a list of assistants, or have them promoted as they join.
- **Version check.** See who in the group runs CludesUI and which version.
- **Ready check gear and cooldowns.** On a ready check, every CludesUI user reports their lowest durability, item level, missing enchants (head, shoulders, chest, feet, rings, weapons), raid cooldowns that are not ready, and a missing flask, food, augment rune or healthstone. The leader and assistants get a list, with anyone who did not answer.
- **Immunities on You.** Icons for Divine Shield, Blessing of Protection, Blessing of Spellwarding, Ice Block, Aspect of the Turtle and Cloak of Shadows while they are on you; add more by spell ID.
- **Boss Pace.** Set a target kill time per boss. A bar shows the boss's health against where it should be by now: green ahead, red behind. The pace is a straight line, so phases and intermissions throw it off.
- **Nicknames.** Set your nickname once; CludesUI sends it to your guild and group, and shows everyone's on raid frames (and unit frames, with their Show Nicknames setting on). You can also paste `Character=Nickname` lines.

Aura Sounds: pick a spell ID and it plays a sound when that aura is applied to you, gains a stack or falls off. The game plays the sound itself, so it works in boss fights and keys.

Damage dealers are counted as melee or ranged by class, which is a guess for Druids, Shamans and Hunters.

## WoW Forever: Training Planner

On WoW Forever, Forever Tools has a Training page in the CludesUI panel. It lists the spells your trainer has for you right now with their total price, then what each of the next levels brings and costs. Spells that wait on a talent or a quest are listed apart, with the spell they need. When you level up, a chat line says what is new; turn it off on the same page. Prices are the trainer's base prices, so a reputation discount makes the real bill a little lower.

The spell list and prices come from [What's Training](https://github.com/fusionpit/WhatsTraining) (MIT licence).

## Profiles

Profiles > Import Profile accepts CludesUI strings (they start with `!CUI_`) and strings in the older `!EUI_` format, which it converts as it imports.

## Adding your own addon's settings

Other addons can add a settings page to the CludesUI panel. See [PLUGINS_API.md](CludesUI/PLUGINS_API.md) and [SKINNING_API.md](CludesUI/SKINNING_API.md).

## Releasing

1. Set the same version in `## Version` of every `.toc` file and in `CludesUI.VERSION` in `CludesUI/CludesUI.lua`.
2. Commit, then push a tag that matches, for example `v1.0.1`.
3. GitHub builds `CludesUI-v1.0.1.zip` and attaches it to a new release.

Every push to `master` runs a Lua syntax check and confirms that each file a `.toc` lists exists.
