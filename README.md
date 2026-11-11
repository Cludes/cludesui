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
| `/cpm` | Party Mode |

## Profiles

Profiles > Import Profile accepts CludesUI strings (they start with `!CUI_`) and strings in the older `!EUI_` format, which it converts as it imports.

## Adding your own addon's settings

Other addons can add a settings page to the CludesUI panel. See [PLUGINS_API.md](CludesUI/PLUGINS_API.md) and [SKINNING_API.md](CludesUI/SKINNING_API.md).

## Releasing

1. Set the same version in `## Version` of every `.toc` file and in `CludesUI.VERSION` in `CludesUI/CludesUI.lua`.
2. Commit, then push a tag that matches, for example `v1.0.1`.
3. GitHub builds `CludesUI-v1.0.1.zip` and attaches it to a new release.

Every push to `master` runs a Lua syntax check and confirms that each file a `.toc` lists exists.
