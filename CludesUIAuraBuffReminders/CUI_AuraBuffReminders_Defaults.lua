if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CUI_AuraBuffReminders_Defaults.lua
--
--  Glow types, the profile defaults, the middle-click dismiss table and
--  the appear sounds.
--  Reads the earlier AuraBuff Reminders files through ns._abrInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._abrInternals
-- CludesUIAuraBuffReminders.lua or an earlier AuraBuff Reminders file
-- failed to load.
if not Inner or Inner.broken then return end
Inner.broken = true

local REMIND = Inner.EABR

local saved
Inner.dbSetters[#Inner.dbSetters + 1] = function(val) saved = val end

-------------------------------------------------------------------------------
--  Glow Types (shared with options)
-------------------------------------------------------------------------------
-- Saved glowType numbering (Action Button Glow first) as a view over the
-- shared style table; no Shape Glow (reminder icons have no shape mask).
local GLOW_VIEW = CUI.Glows.MakeView({ 2, 1, 3, 5, 6, 7 })

local StopAllGlows = CUI.Glows.StopAllGlows

-------------------------------------------------------------------------------
--  Defaults
-------------------------------------------------------------------------------
-- Reminder icons use the same border vocabulary and tuning as Player Aura
-- Bars, but keep their own registry key so the result does not depend on the
-- Unit Frames module being enabled.
do
    local function AllBorderSizes(ox, oy, sx, sy)
        local tbl = {}
        for size = 0, 4 do
            tbl[size] = { offsetX = ox, offsetY = oy, shiftX = sx, shiftY = sy }
        end
        return tbl
    end
    CUI.RegisterBorderDefaults("aurabuffreminders", {
        glow = { defaultSize = 1, sizes = AllBorderSizes(0, 0, 0, 0) },
        blizz = {
            defaultSize = 4,
            sizes = {
                [0] = { offsetX = 0, offsetY = 0, shiftX = 0, shiftY = 0 },
                [1] = { offsetX = 2, offsetY = 1, shiftX = 0, shiftY = 0 },
                [2] = { offsetX = 3, offsetY = 1, shiftX = 1, shiftY = 0 },
                [3] = { offsetX = 4, offsetY = 2, shiftX = 2, shiftY = 0 },
                [4] = { offsetX = 5, offsetY = 3, shiftX = 2, shiftY = 0 },
            },
        },
        dialog = {
            defaultSize = 2,
            sizes = {
                [0] = { offsetX = 0, offsetY = 0, shiftX = 0, shiftY = 0 },
                [1] = { offsetX = 2, offsetY = 2, shiftX = 0, shiftY = 0 },
                [2] = { offsetX = 2, offsetY = 2, shiftX = 0, shiftY = 0 },
                [3] = { offsetX = 4, offsetY = 4, shiftX = 0, shiftY = 0 },
                [4] = { offsetX = 8, offsetY = 8, shiftX = 0, shiftY = 0 },
            },
        },
        ["sm:Blizzard Achievement Wood"] = {
            defaultSize = 1,
            sizes = AllBorderSizes(1, 1, 0, 0),
        },
    })
end

local defaultSet = {
    profile = {
        display = {
            iconShape = "none",
            remindersEnabled = true,
            glowType = 0,
            scale = 1.0,
            xOffset = 0,
            yOffset = 200,
            showText = true,
            showTooltips = true,
            textColor = { r = 1, g = 1, b = 1 },
            textSize = 12,
            textXOffset = 0,
            textYOffset = -5,
            textAnchor = "BOTTOM",
            showCount = true,
            countSize = 16,
            countXOffset = 0,
            countYOffset = 0,
            iconSpacing = 14,
            growDirection = "CENTER",
            opacity = 1.0,
            frameStrata = "MEDIUM",
            cursorAttach = false,
            -- Attach Important Buffs to Cursor's cog: on the cursor only in combat.
            cursorAttachCombatOnly = false,
            -- Preserve the historical reminder look exactly: black, solid,
            -- pixel-perfect 1 px. Extra texture controls remain nil until the
            -- user customizes them.
            borderTexture = "solid",
            borderSize = 1,
            borderR = 0,
            borderG = 0,
            borderB = 0,
            borderA = 1,
            borderBehind = false,
            -- Global timing pair (minutes). showUnderMPlus is the pre-key
            -- (Mythic 0 / keystone lobby) threshold; active keys and combat
            -- ignore thresholds entirely (only fully-missing reminds there).
            showUnder = 5,
            showUnderMPlus = 40,
        },
        raidBuffs = {
            enabled = {
                motw = true,
                bshout = true,
                fort = true,
                ai = true,
                bronze = true,
                sky = true,
                hmark = true,
                -- WoW Forever's Divine Spirit (no key on retail).
                spirit = REMIND.FOREVER or nil,
            },
            -- Per-section "Where to Show". Stores only unchecked buckets
            -- (value false); an absent bucket = shown. Open world defaults
            -- off for raid buffs. Buckets: open_world, raid_mythic,
            -- raid_heroic, raid_normal_lfr, dungeon_mythic,
            -- dungeon_nonmythic, timewalking, delve, lair, scenario, in_combat.
            whereToShow = { open_world = false },
            -- Show When: othersMissing = remind when a groupmate lacks a
            -- buff I provide; iAmMissing = remind when I lack a buff a
            -- groupmate could give me (receiver view, off by default).
            showWhen = { othersMissing = true, iAmMissing = false },
            -- Left-click a receiver reminder (or Healthstone) to ask the
            -- group for it; requestCustom sends requestText (it holds the
            -- "[spell]" token) instead of the default line.
            requestOnClick = true,
            requestCustom = false,
            -- One reminder sound for the whole section (nil = silent),
            -- played once when a reminder newly appears.
        },
        auras = {
            enabled = {
                moonkin_form = false,
                symbiotic = true,
                battle_stance = true,
                def_stance = true,
                berserk_stance = true,
                shadowform = true,
                devo_aura = true,
                bol = true,
                bof = true,
                som = true,
                blistering_scales = true,
                bestow_weyrnstone = true,
                timelessness = true,
                -- Opt-in: enabling it also turns on group aura tracking for
                -- the class.
                soulstone = false,
            },
            -- All buckets (including open world) on by default.
            whereToShow = {},
        },
        consumables = {
            -- When false, bag/equip-derived consumables (rune/flask/food/weapon)
            -- are hidden entirely when the item isn't in bags, instead of
            -- showing a desaturated restock prompt.
            showWithoutItem = true,
            enabled = {
                deadly = true,
                instant = true,
                wound = true,
                amplifying = true,
                crippling = true,
                numbing = true,
                atrophic = true,
                rite_adj = true,
                rite_sanc = true,
                flametongue = true,
                windfury = true,
                earthliving = true,
                tidecaller = true,
                tstrike = true,
                ls = true,
                ws = true,
                es = true,
                -- Opt-in: Earth Shield on a group member (Elemental Orbit).
                es_ally = false,
                augment_rune = true,
                weapon_enchant = true,
                inky_black = true,
                flask = true,
                food = true,
            },
            -- Bag/equip consumables (open world off) and the old shared
            -- class-specials set (open world on). The per-section copies have
            -- no default on purpose, see EABR.SPECIALS.
            whereToShow = { open_world = false },
            specialsWhereToShow = {},
            -- Warlock-section reminders (Soulstone and Wrong Demon) have
            -- their own visibility settings.
            warlockWhereToShow = {},
            -- Pets allowed by the wrong-demon reminder. Absent/false = not allowed.
            wrongPetAllowed = { felguard = true },
            preferredFlask = "last_used",
            preferredFood = "last_used",
            preferredWeaponEnchant = "last_used",
            inkyBlackZones = "",
        },
        unlockPos = nil,
        talentReminders = {}, -- array of {zoneNames={} (zoneName = an older version's single zone, read while there is no list), spellID=number, spellName=string, notNeededMode="never"|"season"|"all", showNotNeeded=bool (the old checkbox, kept in step)}
        talentReminderYOffset = -50,
    },
}

-- WoW Forever section settings; only that client's profiles carry the table.
if REMIND.FOREVER then
    defaultSet.profile.forever = {
        camp = false, -- Camp Benefits reminder; opt-in, it shows whenever the buff is missing
        sleepingBag = false, -- Sleeping Bag reminder; opt-in, below max level with a Cozy Sleeping Bag in the bags
        gather = false, -- gathering tracking reminder; opt-in, it shows while no tracker is up
        gatherClassTrack = true, -- an active class tracking also hides it
        treasure = false, -- Find Treasure reminder (Dwarf); opt-in, it shows while it is off
        wellFed = false, -- Well Fed reminder; opt-in, matched by aura name (every food has its own spell ID)
        mageArmor = false, -- Mage armor reminder (Mage); opt-in, it shows while no Frost/Ice/Mage Armor rank is up
        weapon = false,
        weaponLowRank = false,
        weaponHideNoItem = true,
        weaponShowBelow = 1,
        weaponHands = {},
        -- Action Picker: right-clicking a spell group or class buff reminder
        -- with more than one spell picks the spell its click casts, and the
        -- wheel over a spell picks its rank; opt-in.
        pickerEnabled = false,
        classBuffActions = {}, -- class buff key -> { castSpellID, castRanks = { spell ID -> pinned rank } }
        classBuffPicks = {}, -- class buff key -> ticked (unset: the buff's own default)
        whereToShow = {}, -- section "Where to Show" (an absent bucket = shown)
        customIDs = {}, -- spell IDs the user tracks, in the order added
        customClasses = {}, -- spell ID -> { CLASS = false }: the classes a custom ID does not remind (unset: every class)
        customGroups = {}, -- { name = string, ids = { spell IDs } }: one reminder while none of ids is active
    }
end

-------------------------------------------------------------------------------
--  Middle-click dismiss hide a reminder until the next loading screen
-------------------------------------------------------------------------------
local _dismissedUntilLoad = {} -- [dismissKey] = true

-------------------------------------------------------------------------------
--  Per-section appear-sounds: one sound key per section (raid buffs / auras /
--  consumables / class specials), played once as a reminder NEWLY appears.
--  Two swapped sets avoid per-refresh allocation; the first primed pass is
--  skipped so login never replays a burst. Hung on EABR.
-------------------------------------------------------------------------------
-- Class-special keys (poisons/rites/imbues/shields) -> their section's sound
-- field, or nil; built once. Rogue reminders carry per-category keys.
function REMIND.SpecialSoundField(key)
    local set = REMIND._specialKeySet
    if not set then
        local S = REMIND.SPECIALS
        set = { rogue_lethal = S.ROGUE.sound, rogue_nonlethal = S.ROGUE.sound }
        local groups = {
            { Inner.ROGUE_POISONS, S.ROGUE.sound },
            { Inner.PALADIN_RITES, S.PALADIN.sound },
            { Inner.SHAMAN_IMBUES, S.SHAMAN.sound },
            { Inner.SHAMAN_SHIELDS, S.SHAMAN.sound },
        }
        for _, group in ipairs(groups) do
            if type(group[1]) == "table" then
                for _, it in ipairs(group[1]) do
                    if it.key then set[it.key] = group[2] end
                end
            end
        end
        REMIND._specialKeySet = set
    end
    return set[key]
end

-- Resolves the configured sound key for a reminder from its dismissKey.
function REMIND.ResolveReminderSound(dk)
    local prefixText, key = dk:match("^(%a+):(.+)$")
    if not prefixText then return nil end
    local profile = saved.profile
    if prefixText == "raidbuff" then
        return profile.raidBuffs.sectionSound
    elseif prefixText == "aura" then
        return profile.auras.sectionSound
    elseif prefixText == "consumable" then
        local co = profile.consumables
        local field = REMIND.SpecialSoundField(key)
        if field then return REMIND.SpecialsSound(co, field) end
        return co.sectionSound
    elseif prefixText == "forever" then
        local fo = profile.forever
        return fo and fo.sectionSound
    end
    return nil
end

function REMIND.HandleAppearSounds(missing)
    local previous = REMIND._soundPrev or {}
    local current = REMIND._soundCur or {}
    wipe(current)
    local primed = REMIND._soundPrimed
    for index = 1, #missing do
        local dk = missing[index].dismissKey
        if dk and not _dismissedUntilLoad[dk] then
            current[dk] = true
            if primed and not previous[dk] then
                local skey = REMIND.ResolveReminderSound(dk)
                if skey and skey ~= "none" then
                    local paths = CUI._groupDeathSoundPaths
                    local filePath = paths and paths[skey]
                    if filePath then PlaySoundFile(filePath, "Master") end
                end
            end
        end
    end
    REMIND._soundPrev, REMIND._soundCur, REMIND._soundPrimed = current, previous, true
end

Inner._dismissedUntilLoad, Inner.defaults, Inner.GLOW_VIEW = _dismissedUntilLoad, defaultSet, GLOW_VIEW
Inner.StopAllGlows = StopAllGlows
Inner.broken = false
