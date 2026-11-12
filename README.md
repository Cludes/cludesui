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

Title Line shows your Mythic+ rating against the 0.1% and 1% title lines, with a season graph and a projected date. Open it with `/titleline`. Its cutoff numbers come from Raider.IO and are refreshed in this repository once a day, so update CludesUI to get newer ones. If you also run the standalone TitleLine addon, that one takes over and this module stays off.

## Tank Kit

Tank Kit is for tanks. It shows your co-tank's health, debuffs and defensives in a small frame and alerts you when to taunt. Its settings are in the CludesUI panel under Tank Kit; `/ctank` opens them, and so does right-clicking the frame. If you also run the standalone CoTankAuras addon, that one takes over and this module stays off.

## Raid Lead

Raid Lead is for raid leaders and assistants. Out of combat:

- `/raidlead roles` sorts the raid into tanks, melee, ranged and healers, filling group 1 upward.
- `/raidlead split` makes two balanced halves for split runs.
- `/raidlead undo` puts everyone back where they were.
- `/raidlead stop` stops a sort that is under way.

Damage dealers are counted as melee or ranged by class, which is a guess for Druids, Shamans and Hunters.

## Profiles

Profiles > Import Profile accepts CludesUI strings (they start with `!CUI_`) and strings in the older `!EUI_` format, which it converts as it imports.

## Adding your own addon's settings

Other addons can add a settings page to the CludesUI panel. See [PLUGINS_API.md](CludesUI/PLUGINS_API.md) and [SKINNING_API.md](CludesUI/SKINNING_API.md).

## Releasing

1. Set the same version in `## Version` of every `.toc` file and in `CludesUI.VERSION` in `CludesUI/CludesUI.lua`.
2. Commit, then push a tag that matches, for example `v1.0.1`.
3. GitHub builds `CludesUI-v1.0.1.zip` and attaches it to a new release.

Every push to `master` runs a Lua syntax check and confirms that each file a `.toc` lists exists.
