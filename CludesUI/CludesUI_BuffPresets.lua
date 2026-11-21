if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-- A category's spells grouped by class: CLASS = { id, { id, field = value }, ... }
-- turned into the spellId -> { class = CLASS, field = value } table the
-- consumers read.
local function BySpellClass(byClass)
    local spells = {}
    for class, list in pairs(byClass) do
        for _, item in ipairs(list) do
            if type(item) == "table" then
                local entry = { class = class }
                for k, v in pairs(item) do
                    if k ~= 1 then entry[k] = v end
                end
                spells[item[1]] = entry
            else
                spells[item] = { class = class }
            end
        end
    end
    return spells
end
--------------------------------------------------------------------------------
--  CludesUI_BuffPresets.lua
--  THE single curation source for the 10 buff filter presets (Defensives,
--  Raid CDs, Externals, Core/Lesser Healing Buffs, Support, Offensive CDs,
--  Movement, Utility, Consumables). Two consumers, two shapes:
--    * Raid Frames Buff Manager v2 binds filters/spells directly (primary
--      ids are checkbox rows; alts ride include maps behind their primary).
--    * Player Aura Bars derives its filter seed + class hints at load,
--      flattening alts into their own rows (PAB has no primary/alt tiers).
--  Also the WoW Forever buff families (CludesUI.FOREVER_BUFF_FAMILIES, at
--  the end): every spell that gives each group buff there; and the combat
--  consumables (CludesUI.CONSUMABLES): healthstones and potions; and the
--  raid preparation buffs (CludesUI.RAID_PREP_IDS): flasks, runes, raid buffs.
--  ADD OR EDIT CURATED IDS HERE ONLY -- never in the consumer files.
--------------------------------------------------------------------------------

-- WoW Forever: the vanilla catalogue, in the same shape as the retail one
-- below. Primary = rank 1; alts = every higher rank plus any separate aura
-- id the buff lands under: the include maps match exact aura spell ids, so
-- every learnable rank must be listed. Where the retail catalogue also
-- curates rank 1 under the preset (unchecked there), rank 2 is the primary
-- and rank 1 an alt, so the two clients never share one stored checkbox
-- with different defaults. Active Mitigation, Lesser Healing Buffs and
-- Support are not offered on this client.
-- Both catalogues are built on every client: the running client's one
-- becomes CludesUI.BUFF_PRESETS; the other one only feeds the cross-client
-- id sets and preset list at the end of this file.
local function ForeverCatalogue()
    return {
        filters = {
            { key = "defensives", name = "Defensives" },
            { key = "raidcds", name = "Raid CDs" },
            { key = "externals", name = "Externals" },
            { key = "coreheals", name = "Core Healing Buffs" },
            { key = "offensive", name = "Offensive CDs" },
            { key = "movement", name = "Movement" },
            { key = "utility", name = "Utility" },
            { key = "consumables", name = "Consumables" },
        },
        spells = {
            defensives = {
                [22812] = { class = "DRUID" }, -- Barkskin
                [22842] = { class = "DRUID", alts = { 22845 } }, -- Frenzied Regeneration
                [11958] = { class = "MAGE" }, -- Ice Block
                -- Ice Barrier (rank 2 primary: retail curates rank 1 unchecked)
                [13031] = { class = "MAGE", alts = { 11426, 13032, 13033 } },
                [1463] = { class = "MAGE", alts = { 8494, 8495, 10191, 10192, 10193 } }, -- Mana Shield
                [642] = { class = "PALADIN", alts = { 1020 } }, -- Divine Shield
                [498] = { class = "PALADIN", alts = { 5573 } }, -- Divine Protection
                [586] = { class = "PRIEST", alts = { 9578, 9579, 9592, 10941, 10942 } }, -- Fade
                [27827] = { class = "PRIEST" }, -- Spirit of Redemption
                [5277] = { class = "ROGUE" }, -- Evasion
                -- Vanish (the buff lands as 11327 / 11329)
                [1856] = { class = "ROGUE", alts = { 1857, 11327, 11329 } },
                [871] = { class = "WARRIOR" }, -- Shield Wall
                [12975] = { class = "WARRIOR", alts = { 12976 } }, -- Last Stand
                [20230] = { class = "WARRIOR" }, -- Retaliation
                [19263] = { class = "HUNTER" }, -- Deterrence
                [6229] = { class = "WARLOCK", alts = { 11739, 11740, 28610 } }, -- Shadow Ward
            },
            raidcds = {
                -- Tranquility (rank 2 primary: retail curates rank 1 unchecked)
                [8918] = { class = "DRUID", alts = { 740, 9862, 9863 } },
            },
            externals = {
                [1022] = { class = "PALADIN", alts = { 5599, 10278 } }, -- Blessing of Protection
                [6940] = { class = "PALADIN", alts = { 20729 } }, -- Blessing of Sacrifice
                [10060] = { class = "PRIEST" }, -- Power Infusion
                [6346] = { class = "PRIEST" }, -- Fear Ward
                [29166] = { class = "DRUID" }, -- Innervate
            },
            coreheals = {
                -- Renew (rank 2 primary: retail curates rank 1 unchecked; 425268 to
                -- 425277 are the class's second set of ranks 1 to 10)
                [6074] = {
                    class = "PRIEST",
                    alts = {
                        139,
                        6075,
                        6076,
                        6077,
                        6078,
                        10927,
                        10928,
                        10929,
                        25315,
                        425268,
                        425269,
                        425270,
                        425271,
                        425272,
                        425273,
                        425274,
                        425275,
                        425276,
                        425277,
                    },
                },
                -- Power Word: Shield (rank 2 primary: retail curates rank 1 unchecked)
                [592] = {
                    class = "PRIEST",
                    alts = { 17, 600, 3747, 6065, 6066, 10898, 10899, 10900, 10901 },
                },
                -- Prayer of Mending (ranks 401859 / 1240826 / 1240827; the buff lands
                -- as 401877 / 1240848 / 1240849)
                [401859] = {
                    class = "PRIEST",
                    alts = { 1240826, 1240827, 401877, 1240848, 1240849 },
                },
                -- Rejuvenation (rank 2 primary: retail curates rank 1 unchecked)
                [1058] = {
                    class = "DRUID",
                    alts = { 774, 1430, 2090, 2091, 3627, 8910, 9839, 9840, 9841, 25299 },
                },
                -- Regrowth (rank 2 primary: retail curates rank 1 unchecked)
                [8938] = {
                    class = "DRUID",
                    alts = { 8936, 8939, 8940, 8941, 9750, 9856, 9857, 9858 },
                },
            },
            offensive = {
                [1719] = { class = "WARRIOR" }, -- Recklessness
                [12328] = { class = "WARRIOR" }, -- Death Wish
                [12292] = { class = "WARRIOR" }, -- Sweeping Strikes
                [18499] = { class = "WARRIOR" }, -- Berserker Rage
                [13750] = { class = "ROGUE" }, -- Adrenaline Rush
                [13877] = { class = "ROGUE" }, -- Blade Flurry
                [14177] = { class = "ROGUE" }, -- Cold Blood
                [12042] = { class = "MAGE" }, -- Arcane Power
                [11129] = { class = "MAGE" }, -- Combustion
                [12043] = { class = "MAGE" }, -- Presence of Mind
                [3045] = { class = "HUNTER" }, -- Rapid Fire
                [19574] = { class = "HUNTER" }, -- Bestial Wrath
                [10060] = { class = "PRIEST" }, -- Power Infusion
                [14751] = { class = "PRIEST" }, -- Inner Focus
                [16188] = { class = "SHAMAN" }, -- Nature's Swiftness
                [17116] = { class = "DRUID" }, -- Nature's Swiftness
                [5217] = { class = "DRUID" }, -- Tiger's Fury
                [20216] = { class = "PALADIN" }, -- Divine Favor
            },
            movement = {
                [1850] = { class = "DRUID", alts = { 9821 } }, -- Dash
                [783] = { class = "DRUID" }, -- Travel Form
                [5215] = { class = "DRUID", alts = { 6783, 9913 } }, -- Prowl
                [2983] = { class = "ROGUE", alts = { 8696, 11305 } }, -- Sprint
                [1784] = { class = "ROGUE", alts = { 1785, 1786, 1787 } }, -- Stealth
                [5118] = { class = "HUNTER" }, -- Aspect of the Cheetah
                [13159] = { class = "HUNTER" }, -- Aspect of the Pack
                [5384] = { class = "HUNTER" }, -- Feign Death
                [130] = { class = "MAGE" }, -- Slow Fall
                [1044] = { class = "PALADIN" }, -- Blessing of Freedom
                [2645] = { class = "SHAMAN" }, -- Ghost Wolf
                [1706] = { class = "PRIEST" }, -- Levitate
            },
            utility = {
                [29166] = { class = "DRUID" }, -- Innervate
                [1044] = { class = "PALADIN" }, -- Blessing of Freedom
                [546] = { class = "SHAMAN" }, -- Water Walking
                [131] = { class = "SHAMAN" }, -- Water Breathing
                [5697] = { class = "WARLOCK" }, -- Unending Breath
                [1008] = { class = "MAGE", alts = { 8455, 10169, 10170 } }, -- Amplify Magic
                [604] = { class = "MAGE", alts = { 8450, 8451, 10173, 10174 } }, -- Dampen Magic
            },
            -- Aura spell ids of the vanilla flasks, elixirs, potions, food and
            -- drink. Flasks, protection potions, Free Action and Limited
            -- Invulnerability are checked by default; the rest start unchecked.
            consumables = {
                -- Food and Drink: every eating or drinking aura a Forever item
                -- casts (each food and drink rank is its own id).
                [433] = {
                    class = "ALL",
                    disabled = true,
                    alts = {
                        434,
                        435,
                        1127,
                        1129,
                        1131,
                        2639,
                        5004,
                        5006,
                        5007,
                        6410,
                        7737,
                        10256,
                        24005,
                        24707,
                        24869,
                        25660,
                        29008,
                        29073,
                        470362,
                        470369,
                        1225769,
                        1225771,
                        1225772,
                    },
                }, -- Food
                [430] = {
                    class = "ALL",
                    disabled = true,
                    alts = { 431, 432, 1133, 1135, 1137, 22734, 24355, 29007, 468767 },
                }, -- Drink
                [17626] = { class = "ALL" }, -- Flask of the Titans
                [17628] = { class = "ALL" }, -- Flask of Supreme Power
                [17627] = { class = "ALL" }, -- Flask of Distilled Wisdom
                [17629] = { class = "ALL" }, -- Flask of Chromatic Resistance
                [17538] = { class = "ALL", disabled = true }, -- Elixir of the Mongoose
                [17539] = { class = "ALL", disabled = true }, -- Greater Arcane Elixir
                [11474] = { class = "ALL", disabled = true }, -- Elixir of Shadow Power
                [21920] = { class = "ALL", disabled = true }, -- Elixir of Frost Power
                [17537] = { class = "ALL", disabled = true }, -- Elixir of Brute Force
                [17535] = { class = "ALL", disabled = true }, -- Elixir of the Sages
                [6615] = { class = "ALL" }, -- Free Action Potion
                [3169] = { class = "ALL" }, -- Limited Invulnerability Potion
                [17540] = { class = "ALL", disabled = true }, -- Greater Stoneshield Potion
                [17528] = { class = "ALL", disabled = true }, -- Mighty Rage Potion
                [2379] = { class = "ALL", disabled = true }, -- Swiftness Potion
                [11359] = { class = "ALL", disabled = true }, -- Restorative Potion
                [11364] = { class = "ALL", disabled = true }, -- Magic Resistance Potion
                [17543] = { class = "ALL" }, -- Greater Fire Protection Potion
                [17546] = { class = "ALL" }, -- Greater Nature Protection Potion
                [17548] = { class = "ALL" }, -- Greater Shadow Protection Potion
                [17544] = { class = "ALL" }, -- Greater Frost Protection Potion
                [17549] = { class = "ALL" }, -- Greater Arcane Protection Potion
                [16323] = { class = "ALL", disabled = true }, -- Juju Power
                [16329] = { class = "ALL", disabled = true }, -- Juju Might
                [17038] = { class = "ALL", disabled = true }, -- Winterfall Firewater
            },
        },
    }
end

local RETAIL_PRESETS = {

    -- Order = display order. Indicators assign filters by numeric id, but preset
    -- identity rides the `preset` field so curated-data updates can find them.
    filters = {
        { key = "defensives", name = "Defensives" },
        { key = "activemitigation", name = "Active Mitigation" },
        { key = "raidcds", name = "Raid CDs" },
        { key = "externals", name = "Externals" },
        { key = "coreheals", name = "Core Healing Buffs" },
        { key = "lesserheals", name = "Lesser Healing Buffs" },
        { key = "support", name = "Support" },
        { key = "offensive", name = "Offensive CDs" },
        { key = "movement", name = "Movement" },
        { key = "utility", name = "Utility" },
        { key = "consumables", name = "Consumables" },
    },

    -- Curated spell lists per preset: [primaryID] = { class = "CLASSFILE"|"ALL",
    -- disabled = true|nil, alts = { id, ... } }. Enabled by default unless
    -- `disabled`. In BM2 the PRIMARY id is the checkbox row and alternates
    -- (talent/rank variants) follow the primary's state; in PAB every id becomes
    -- its own row with the primary's state and class hint.
    spells = {
        defensives = BySpellClass({
            DEATHKNIGHT = { { 48707, alts = { 444741 } }, 48792, { 49039, disabled = true }, 55233, 101568 },
            DEMONHUNTER = {
                { 442715, disabled = true },
                212800,
                { 1266616, alts = { 394933 }, disabled = true },
                { 427912, alts = { 258920 }, disabled = true },
                187827,
                207771,
                { 209426, disabled = true },
            },
            DRUID = { 22812, 22842, { 192081, disabled = true }, 61336, { 393903, disabled = true }, 1261872 },
            EVOKER = { 404381, 363916, 374349 },
            HUNTER = { 186265, { 472708, disabled = true }, 264735 },
            MAGE = {
                342246,
                { 235313, disabled = true },
                { 11426, disabled = true },
                45438,
                414658,
                { 235450, disabled = true },
                449336,
                1309793,
            },
            MONK = {
                122783,
                { 115203, alts = { 120954 } },
                125174,
                132578,
                322507,
                { 432180, disabled = true },
                1241059,
            },
            PALADIN = { { 498, alts = { 403876 } }, 642, { 184662, disabled = true }, 31850, 86659, 212641 },
            PRIEST = {
                { 114216, alts = { 114214 }, disabled = true },
                19236,
                47585,
                586,
                { 45242, alts = { 426401 }, disabled = true },
                193065,
                27827,
            },
            ROGUE = { 31224, 5277, 1966, 185311 },
            SHAMAN = { 108271, 260881, 381755 },
            WARLOCK = { 108416, 104773, 132413, 387636, { 389614, disabled = true } },
            WARRIOR = {
                118038,
                184364,
                { 190456, alts = { 1277297 } },
                147833,
                385391,
                871,
                { 202147, disabled = true },
            },
        }),
        activemitigation = BySpellClass({
            DEATHKNIGHT = { 77535 },
            DEMONHUNTER = { 203819 },
            DRUID = { 192081 },
            PALADIN = { 132403 },
            WARRIOR = { 132404 },
        }),
        raidcds = BySpellClass({
            DEATHKNIGHT = { { 145629, alts = { 51052 } } },
            DEMONHUNTER = { { 209426, alts = { 196718 } } },
            DRUID = { { 740, alts = { 157982, 1264623 }, disabled = true } },
            EVOKER = { { 359816, alts = { 362361 }, disabled = true }, { 363534, disabled = true }, 374227 },
            PALADIN = { { 31821, alts = { 317929 } } },
            PRIEST = { { 64843, alts = { 64844 }, disabled = true }, { 81782, alts = { 62618 } } },
            SHAMAN = { { 325174, alts = { 98008 } } },
            WARRIOR = { { 97463, alts = { 97462 } } },
        }),
        externals = BySpellClass({
            DRUID = { 102342 },
            EVOKER = { 357170 },
            HUNTER = { 53480 },
            MONK = { 116849 },
            PALADIN = { { 1022, alts = { 1309794 } }, 6940, 204018, 387804 },
            PRIEST = { 47788, 33206 },
        }),
        coreheals = BySpellClass({
            DRUID = {
                { 1278914, disabled = true },
                { 33763, alts = { 419207, 1227806 } },
                { 8936, alts = { 419287 }, disabled = true },
                { 774, alts = { 419204 }, disabled = true },
                { 155777, disabled = true },
                { 439530, disabled = true },
                { 474754, alts = { 474750 } },
                { 48438, alts = { 419344 }, disabled = true },
            },
            EVOKER = {
                { 409678, disabled = true },
                { 355941, alts = { 355936, 382614 }, disabled = true },
                { 376788, disabled = true },
                { 363502, disabled = true },
                364343,
                { 445740, disabled = true },
                373267,
                { 366155, disabled = true },
                { 367364, disabled = true },
                { 373862, disabled = true },
                { 1291636, disabled = true },
                { 409895, disabled = true },
            },
            MONK = {
                { 450769, alts = { 450521, 450711, 450526, 450531 }, disabled = true },
                { 1292922, disabled = true },
                { 124682, disabled = true },
                { 467281, alts = { 427296 }, disabled = true },
                { 388513, disabled = true },
                { 450805, disabled = true },
                119611,
                { 115175, alts = { 1260617, 198533 }, disabled = true },
            },
            PALADIN = {
                156910,
                53563,
                200025,
                1244893,
                { 431381, disabled = true },
                { 156322, alts = { 461432 }, disabled = true },
                { 432502, disabled = true },
                { 469703, disabled = true },
            },
            PRIEST = {
                194384,
                { 77489, disabled = true },
                { 17, alts = { 1246768, 1254306, 1300008 }, disabled = true },
                { 41635, disabled = true },
                { 139, disabled = true },
                { 453846, alts = { 453850 }, disabled = true },
                { 1253593, alts = { 1300009 }, disabled = true },
            },
            SHAMAN = {
                { 207400, disabled = true },
                { 383648, alts = { 974 } },
                { 444490, disabled = true },
                { 61295, disabled = true },
            },
        }),
        lesserheals = BySpellClass({
            DRUID = {
                1278914,
                { 33763, alts = { 419207, 1227806 }, disabled = true },
                { 8936, alts = { 419287 } },
                { 774, alts = { 419204 } },
                155777,
                { 439530, disabled = true },
                { 474754, alts = { 474750 }, disabled = true },
                { 48438, alts = { 419344 } },
            },
            EVOKER = {
                { 409678, disabled = true },
                { 355941, alts = { 355936, 382614 } },
                376788,
                { 363502, disabled = true },
                { 364343, disabled = true },
                { 445740, disabled = true },
                373267,
                366155,
                367364,
                { 373862, disabled = true },
                { 1291636, disabled = true },
                409895,
            },
            MONK = {
                { 450769, alts = { 450521, 450711, 450526, 450531 } },
                1292922,
                124682,
                { 467281, alts = { 427296 }, disabled = true },
                { 388513, disabled = true },
                { 450805, disabled = true },
                { 119611, disabled = true },
                { 115175, alts = { 1260617, 198533 } },
            },
            PALADIN = {
                { 156910, disabled = true },
                { 53563, disabled = true },
                { 200025, disabled = true },
                { 1244893, disabled = true },
                431381,
                { 156322, alts = { 461432 } },
                432502,
                469703,
            },
            PRIEST = {
                { 194384, disabled = true },
                77489,
                { 17, alts = { 1246768, 1254306, 1300008 } },
                41635,
                139,
                { 453846, alts = { 453850 }, disabled = true },
                { 1253593, alts = { 1300009 } },
            },
            SHAMAN = {
                { 207400, disabled = true },
                { 383648, alts = { 974 }, disabled = true },
                444490,
                61295,
            },
        }),
        support = BySpellClass({
            EVOKER = {
                360827,
                { 395152, alts = { 395296 } },
                { 410263, disabled = true },
                410089,
                { 413984, disabled = true },
                { 369459, disabled = true },
                { 406732, disabled = true },
                { 361021, disabled = true },
                { 361022, disabled = true },
            },
        }),
        offensive = BySpellClass({
            DEATHKNIGHT = { { 1249658, alts = { 152279 } }, 42650, 51271 },
            DEMONHUNTER = {
                { 191427, alts = { 187827, 321067, 321068, 162264 } },
                { 471306, alts = { 1217605, 473671, 1217607 } },
            },
            DRUID = {
                { 194223, alts = { 102560 } },
                { 106951, alts = { 102543 } },
                { 50334, alts = { 102558 }, disabled = true },
            },
            EVOKER = { { 403631, disabled = true }, 375087 },
            HUNTER = {
                { 186254, alts = { 1235388, 1285912, 19574 } },
                288613,
                { 1250646, alts = { 1251703 } },
            },
            MAGE = { 190319, { 365350, alts = { 365362 } }, 1247908 },
            MONK = { 1249625, { 1248992, disabled = true } },
            PALADIN = { { 31884, alts = { 231895, 454351, 216331 } } },
            PRIEST = { 10060, 194249 },
            ROGUE = { 13750, 121471, { 185422, disabled = true }, 1249810 },
            SHAMAN = { { 114050, alts = { 114051, 114052, 1219480 } }, 466772 },
            WARLOCK = { 442726, { 1276767, disabled = true }, 1276166, 266087, 417282 },
            WARRIOR = { 107574, 1719 },
        }),
        movement = {
            [48265] = { class = "DEATHKNIGHT" },
            [212552] = { class = "DEATHKNIGHT" },
            [444347] = { class = "DEATHKNIGHT" },
            [1850] = { class = "DRUID", alts = { 61684 } },
            [106898] = { class = "DRUID", alts = { 77761, 77764 } },
            [252216] = { class = "DRUID" },
            [5215] = { class = "DRUID" },
            [340546] = { class = "DRUID" },
            [400126] = { class = "DRUID" },
            [186257] = { class = "HUNTER", alts = { 186258 } },
            [118922] = { class = "HUNTER" },
            [5384] = { class = "HUNTER" },
            [199483] = { class = "HUNTER" },
            [1267208] = { class = "HUNTER" },
            [444754] = { class = "MAGE" },
            [130] = { class = "MAGE" },
            [55342] = { class = "MAGE" },
            [108843] = { class = "MAGE" },
            [110960] = { class = "MAGE" },
            [382294] = { class = "MAGE" },
            [119085] = { class = "MONK" },
            [443569] = { class = "MONK" },
            [101545] = { class = "MONK", disabled = true },
            [116841] = { class = "MONK" },
            [394112] = { class = "MONK" },
            [432180] = { class = "MONK" },
            [449609] = { class = "MONK" },
            [276111] = {
                class = "PALADIN",
                alts = {
                    221886,
                    221883,
                    276112,
                    254474,
                    254472,
                    254471,
                    221885,
                    254473,
                    363608,
                    294133,
                    221887,
                    1272854,
                    453804,
                    1253874,
                    1253723,
                    1253881,
                },
            },
            [1044] = { class = "PALADIN" },
            [121557] = { class = "PRIEST" },
            [65081] = { class = "PRIEST" },
            [111759] = { class = "PRIEST" },
            [2983] = { class = "ROGUE" },
            [1784] = { class = "ROGUE" },
            [31230] = { class = "ROGUE" },
            [36554] = { class = "ROGUE" },
            [114018] = { class = "ROGUE" },
            [192082] = { class = "SHAMAN" },
            [79206] = { class = "SHAMAN" },
            [58875] = { class = "SHAMAN", alts = { 90328 } },
            [2645] = { class = "SHAMAN" },
            [111400] = { class = "WARLOCK" },
            [333889] = { class = "WARLOCK" },
            [387626] = { class = "WARLOCK" },
            [387633] = { class = "WARLOCK" },
            [202164] = { class = "WARRIOR" },
            [1244157] = { class = "WARRIOR" },
            [358267] = { class = "EVOKER" },
            [358733] = { class = "EVOKER" },
            [370889] = { class = "EVOKER" },
            -- Time Spiral: the buff lands under a different spell id per RECIPIENT
            -- class (each class gets its own empowered-movement aura).
            [375234] = {
                class = "EVOKER",
                alts = {
                    375226,
                    375229,
                    375230,
                    375238,
                    375240,
                    375252,
                    375253,
                    375254,
                    375255,
                    375256,
                    375257,
                    375258,
                },
            },
            [406732] = { class = "EVOKER" },
        },
        utility = BySpellClass({
            DEATHKNIGHT = { 3714 },
            DRUID = { 29166 },
            EVOKER = {
                { 406732, alts = { 406789 } },
                { 390386, disabled = true },
                { 408233, disabled = true },
            },
            HUNTER = {
                { 1224810, alts = { 54216, 62305 } },
                { 466904, disabled = true },
                { 264667, alts = { 357650 }, disabled = true },
            },
            MAGE = { { 80353, disabled = true } },
            MONK = { 116841 },
            PALADIN = { { 1044, alts = { 299256 } } },
            ROGUE = { { 115834, alts = { 114018 } } },
            SHAMAN = { { 2825, disabled = true }, { 32182, disabled = true } },
        }),
        consumables = BySpellClass({
            ALL = { 1236998, 1236616, 1239479, 1236994 },
        }),
    },
}

local RUNNING, OTHER
if CUI.IS_FOREVER == true then
    RUNNING, OTHER = ForeverCatalogue(), RETAIL_PRESETS
else
    RUNNING, OTHER = RETAIL_PRESETS, ForeverCatalogue()
end
CUI.BUFF_PRESETS = RUNNING

-- Profiles travel between retail and WoW Forever (exported on one client,
-- imported on the other, and back). Both consumers keep what only the other
-- client curates stored untouched but inert and hidden here: its spell ids
-- and checkbox states inside shared preset filters, and its presets this
-- client does not offer. Id sets hold primaries and alts alike:
--   BUFF_PRESET_IDS[key][id]       this client's catalogue curates id under key
--   BUFF_PRESET_OTHER_IDS[key][id] the other client's catalogue does
--   BUFF_PRESET_OTHER_FILTERS      the other client's preset list (key, name)
local function IdSets(presets)
    local sets = {}
    for key, entries in pairs(presets.spells) do
        local set = {}
        for ident, details in pairs(entries) do
            set[ident] = true
            local alts = details.alts
            if alts then
                for idx = 1, #alts do
                    set[alts[idx]] = true
                end
            end
        end
        sets[key] = set
    end
    return sets
end
CUI.BUFF_PRESET_IDS = IdSets(RUNNING)
CUI.BUFF_PRESET_OTHER_IDS = IdSets(OTHER)
CUI.BUFF_PRESET_OTHER_FILTERS = OTHER.filters

-- WoW Forever buff families: one per group buff, every spell that gives it.
-- Read by the Raid Frames Missing Buffs indicator and by Aura Buff Reminders
-- (its Raid Buffs and the rank families of custom spells). names = spells
-- whose (localized) names cover every rank and the group version; single /
-- group = the trainable ranks of the buff and of its group version, lowest
-- first; ids = every spell that applies it (ranks, group version, NPC and
-- item casts, i.e. every spell of those names on the client). Built on WoW
-- Forever only.
if CUI.IS_FOREVER == true then
    CUI.FOREVER_BUFF_FAMILIES = {
        fort = {
            names = { 1243, 21562 },
            single = { 1243, 1244, 1245, 2791, 10937, 10938 },
            group = { 21562, 21564 },
            ids = {
                1243,
                1244,
                1245,
                2791,
                10937,
                10938,
                10939,
                10940,
                13864,
                23947,
                23948,
                21562,
                21564,
                450086,
            },
        },
        mark = {
            names = { 1126, 21849 },
            single = { 1126, 5232, 6756, 5234, 8907, 9884, 9885 },
            group = { 21849, 21850 },
            ids = {
                1126,
                5232,
                5234,
                5286,
                5287,
                6756,
                8907,
                8908,
                9884,
                9885,
                16878,
                24752,
                364163,
                1291335,
                1310503,
                21849,
                21850,
            },
        },
        spirit = {
            names = { 14752, 27681 },
            single = { 14752, 14818, 14819, 27841 },
            group = { 27681 },
            ids = { 14752, 14818, 14819, 16875, 27841, 27681 },
        },
        thorns = {
            names = { 467 },
            single = { 467, 782, 1075, 8914, 9756, 9910 },
            group = {},
            ids = {
                467,
                782,
                1075,
                8914,
                9756,
                9910,
                15438,
                16877,
                21335,
                21337,
                22128,
                22351,
                22696,
                25640,
                25777,
                438294,
                438326,
                1213813,
                1213816,
                1213834,
                1236308,
                1291338,
                1312955,
            },
        },
        -- Paladin blessings, each with its Greater version (1213408 is the
        -- client's non-trainable copy of Kings).
        might = {
            names = { 19740, 25782 },
            single = { 19740, 19834, 19835, 19836, 19837, 19838, 25291 },
            group = { 25782, 25916 },
            ids = { 19740, 19834, 19835, 19836, 19837, 19838, 25291, 25782, 25916 },
        },
        wisdom = {
            names = { 19742, 25894 },
            single = { 19742, 19850, 19852, 19853, 19854, 25290 },
            group = { 25894, 25918 },
            ids = { 19742, 19850, 19852, 19853, 19854, 25290, 25894, 25918 },
        },
        kings = {
            names = { 20217, 25898 },
            single = { 20217 },
            group = { 25898 },
            ids = { 20217, 1213408, 25898 },
        },
        -- Salvation and Mass Salvation (the blessings' names before build
        -- 70425; 1912 is the client's other copy).
        salvation = {
            names = { 1038, 25895 },
            single = { 1038 },
            group = { 25895 },
            ids = { 1038, 1912, 25895 },
        },
        -- beneficiaries: the classes the buff serves (every mana user,
        -- hunters included); a family without it serves everyone.
        ai = {
            names = { 1459, 23028 },
            single = { 1459, 1460, 1461, 10156, 10157 },
            group = { 23028 },
            ids = { 1459, 1460, 1461, 10156, 10157, 13326, 16876, 364161, 23028 },
            beneficiaries = {
                DRUID = true,
                HUNTER = true,
                MAGE = true,
                PALADIN = true,
                PRIEST = true,
                SHAMAN = true,
                WARLOCK = true,
            },
        },
        bshout = {
            names = { 6673 },
            single = { 6673, 5242, 6192, 11549, 11550, 11551, 25289 },
            group = {},
            ids = {
                6673,
                5242,
                6192,
                11549,
                11550,
                11551,
                25289,
                9128,
                24438,
                25101,
                26043,
                26099,
                27578,
            },
        },
    }
end

-- WoW Forever on-next-swing attacks per class (base spell IDs; every rank
-- shares the name the readers compare). While one is queued the Resource
-- Bars swing timer paints its melee rows and the Cooldown Manager lights the
-- attack's icons. Built on WoW Forever only: retail has no such attacks.
if CUI.IS_FOREVER == true then
    CUI.FOREVER_NEXT_SWING = {
        WARRIOR = { 78, 845 }, -- Heroic Strike, Cleave
        DRUID = { 6807 }, -- Maul
        HUNTER = { 2973 }, -- Raptor Strike
    }
end

-- SEASON UPDATE: a potion tier a new season adds joins its family below.
-- Combat consumables: healthstones and potions, one family per Cooldown
-- Manager preset key, in that module's preset fields. itemID: the family's
-- identity id (saved preset frames key on it). displayOrder: the dynamic
-- display, newest tier first (rank 2 before rank 1, Fleeting first at equal
-- rank). spellIDs: the cast ids known ahead (a buff potion casts its buff's
-- id); every other potion's cast id comes from its items (C_Item.GetItemSpell).
-- Read by the Cooldown Manager presets and Damage Meters' spell history. Built
-- on both clients; WoW Forever offers only the Healthstone family, whose items
-- there are FOREVER_HEALTHSTONES.
CUI.CONSUMABLES = {
    lights_potential = {
        itemID = 241308,
        altItemIDs = { 245898, 245897, 241309 },
        displayOrder = {
            245898, -- Fleeting Light's Potential r2
            241308, -- Light's Potential r2
            245897, -- Fleeting Light's Potential r1
            241309, -- Light's Potential r1
        },
        spellIDs = { 1236616 },
    },
    potion_recklessness = {
        itemID = 241288,
        altItemIDs = { 241289, 245902, 245903 },
        displayOrder = {
            245902, -- Fleeting Potion of Recklessness r2
            241288, -- Potion of Recklessness r2
            245903, -- Fleeting Potion of Recklessness r1
            241289, -- Potion of Recklessness r1
        },
        spellIDs = { 1236994 },
    },
    liquid_luster = {
        itemID = 271887,
        altItemIDs = { 274764, 274763, 271886 },
        displayOrder = {
            274764, -- Fleeting Liquid Luster r2
            271887, -- Liquid Luster r2
            274763, -- Fleeting Liquid Luster r1
            271886, -- Liquid Luster r1
        },
        spellIDs = { 1295132 },
    },
    -- The identity stays 241304 while the newer tier leads the display.
    silvermoon_health = {
        itemID = 241304,
        altItemIDs = { 241305, 271884, 271883 },
        displayOrder = {
            271884, -- Concentrated Silvermoon Health Potion r2
            271883, -- Concentrated Silvermoon Health Potion r1
            241304, -- Silvermoon Health Potion r2
            241305, -- Silvermoon Health Potion r1
        },
    },
    lightfused_mana = { itemID = 241300, altItemIDs = { 245917, 245916, 241301 } },
    invis_potion = {
        itemID = 241302,
        altItemIDs = { 241303 },
        spellIDs = { 371125, 431424, 371133, 371134, 1236551 },
    },
    -- Pact of Gluttony turns self-conjured stones into Demonic Healthstones.
    healthstone = { itemID = 5512, altItemIDs = { 224464 }, spellIDs = { 6262 } },
    demonic_healthstone = { itemID = 224464, spellIDs = { 452930 } },
}
-- Raid preparation buffs (retail): the flask, augment rune and vantus rune
-- buffs, and the raid buffs by the class that casts them. Read by AuraBuff
-- Reminders and Quality of Life's Raid Buff Check.
CUI.RAID_PREP_IDS = {
    flask = {
        1235110,
        1235108,
        1235111,
        1235057,
        1239355, -- Midnight
        1235113,
        1235114,
        1235115,
        1235116, -- Midnight, PvP variants
        432473,
        432021,
        431974,
        431973,
        431972,
        431971, -- The War Within
    },
    -- SEASON UPDATE: current augment runes: Tidesworn (12.1), Void-Touched (12.0);
    -- a rune the new season replaces moves to oldRune.
    rune = { 1295329, 1264426 },
    -- Older runes: Ethereal, Soulgorged, Crystallization (TWW), Draconic (DF), Veiled (SL).
    oldRune = { 1234969, 1242347, 453250, 393438, 347901 },
    -- SEASON UPDATE: add the new raid's Vantus Rune boss buffs.
    -- Midnight boss buffs of Vantus Runes (Season 1 and 2, both IDs of each boss).
    vantus = {
        1276666,
        1276669,
        1276682,
        1276683,
        1276685,
        1276686,
        1276687,
        1276688,
        1276691,
        1276698,
        1276704,
        1276705,
        1276708,
        1276709,
        1276711,
        1276712,
        1276714,
        1276715,
        1300173,
        1300174,
        1303172,
        1303173,
        1303174,
        1303175,
        1303176,
        1303177,
        1303178,
        1303179,
        1303180,
        1303181,
        1303182,
        1303183,
        1303184,
        1303185,
        1303186,
        1303187,
        1310437,
        1310439,
        1319284,
        1319286,
    },
    raidBuffs = {
        { key = "motw", class = "DRUID", castSpell = 1126, buffIDs = { 1126, 432661 } },
        { key = "bshout", class = "WARRIOR", castSpell = 6673, buffIDs = { 6673 } },
        { key = "fort", class = "PRIEST", castSpell = 21562, buffIDs = { 21562 } },
        { key = "ai", class = "MAGE", castSpell = 1459, buffIDs = { 1459, 432778 } },
        {
            key = "bronze",
            class = "EVOKER",
            castSpell = 364342,
            buffIDs = {
                381732,
                381741,
                381746,
                381748,
                381749,
                381750,
                381751,
                381752,
                381753,
                381754,
                381756,
                381757,
                381758,
            },
        },
        { key = "sky", class = "SHAMAN", castSpell = 462854, buffIDs = { 462854 } },
    },
}

-- WoW Forever's healthstones after the Minor stone (5512, still the family's
-- identity): the Major, Greater, Healthstone and Lesser tiers, each a base
-- stone and two improved-talent stones, then the improved Minor stones.
if CUI.IS_FOREVER == true then
    CUI.FOREVER_HEALTHSTONES = {
        9421,
        19012,
        19013,
        5510,
        19010,
        19011,
        5509,
        19008,
        19009,
        5511,
        19006,
        19007,
        19004,
        19005,
    }
end
