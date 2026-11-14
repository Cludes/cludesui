if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUI_Colors.lua
--  Class, power and resource colour defaults, the custom-colour cache and
--  getters, Dark Mode palette and toggles. Loads right after CludesUI_Popups.lua.
-------------------------------------------------------------------------------
local CludesUI = _G.CludesUI

local CLASS_COLOR_MAP = CludesUI.CLASS_COLOR_MAP

-------------------------------------------------------------------------------
--  Global Color System -- central source of truth for class, power, and resource colors;
--  stored in CludesUIDB.customColors, falls back to WoW defaults.
-------------------------------------------------------------------------------

-- Default power colors (from WoW's PowerBarColor)
CludesUI.DEFAULT_POWER_COLORS = {
    -- Standard power types
    MANA = { r = 0.000, g = 0.550, b = 1.000 },
    RAGE = { r = 0.900, g = 0.150, b = 0.150 },
    FOCUS = { r = 0xDD / 255, g = 0x92 / 255, b = 0x37 / 255 },
    ENERGY = { r = 1.000, g = 0.960, b = 0.410 },
    RUNIC_POWER = { r = 0xC4 / 255, g = 0x1F / 255, b = 0x3B / 255 },
    LUNAR_POWER = { r = 0xFF / 255, g = 0x7D / 255, b = 0x0A / 255 },
    INSANITY = { r = 0.400, g = 0.000, b = 0.800 },
    MAELSTROM = { r = 0x00 / 255, g = 0x70 / 255, b = 0xDE / 255 },
    FURY = { r = 0xA3 / 255, g = 0x30 / 255, b = 0xC9 / 255 },
    PAIN = { r = 1.000, g = 0.612, b = 0.000 },
    EBON_MIGHT = { r = 0xE6 / 255, g = 0x8C / 255, b = 0x4D / 255 },
}

-- Default resource colors (class-specific resource pips)
CludesUI.DEFAULT_RESOURCE_COLORS = {
    ROGUE = { r = 1.00, g = 0.96, b = 0.41 },
    DRUID = { r = 1.00, g = 0.49, b = 0.04 },
    PALADIN = { r = 0.96, g = 0.55, b = 0.73 },
    MONK = { r = 0.00, g = 1.00, b = 0.60 },
    WARLOCK = { r = 0.58, g = 0.51, b = 0.79 },
    MAGE = { r = 0.25, g = 0.78, b = 0.92 },
    EVOKER = { r = 0.20, g = 0.58, b = 0.50 },
    DEATHKNIGHT = { r = 0.77, g = 0.12, b = 0.23 },
    DEMONHUNTER = { r = 0.34, g = 0.06, b = 0.46 },
}

-- Default class-resource colors keyed by the RESOURCE, not the class (classes with multiple resources get distinct colors); customized via customColors.classResource.
CludesUI.DEFAULT_CLASS_RESOURCE_COLORS = {
    ComboPoints = { r = 1.0, g = 0.9608, b = 0.4118 },
    Runes = { r = 0.0, g = 0.8196, b = 1.0 },
    SoulShards = { r = 0.5059, g = 0.3412, b = 0.8431 },
    HolyPower = { r = 0.949, g = 0.902, b = 0.6 },
    ArcaneCharges = { r = 0.7176, g = 0.4902, b = 0.8118 },
    Icicles = { r = 0.7098, g = 1.0, b = 0.9216 },
    Chi = { r = 0.0, g = 1.0, b = 0.6 },
    Essence = { r = 0.2, g = 0.58, b = 0.502 },
    SoulFragments = { r = 0.6, g = 0.8, b = 0.2 },
    MaelstromWeapon = { r = 0.0, g = 0.4392, b = 0.8706 },
    TipOfTheSpear = { r = 0.6667, g = 0.8275, b = 0.4471 },
    WhirlwindStacks = { r = 0.7765, g = 0.6078, b = 0.4275 },
    SweepingStrikes = { r = 0.8510, g = 0.4157, b = 0.3373 },
}

-- Get a class-resource color (custom override or default), keyed by resource.
function CludesUI.GetClassResourceColor(key)
    if not key then
        return nil
    end
    if CludesUI._colorCacheDirty then
        CludesUI._RebuildColorCache()
    end
    return CludesUI._colorCache.classResource[key]
end

-- Class -> primary power type name mapping
CludesUI.CLASS_POWER_MAP = {
    WARRIOR = "RAGE",
    PALADIN = "MANA",
    HUNTER = "FOCUS",
    ROGUE = "ENERGY",
    PRIEST = "MANA",
    DEATHKNIGHT = "RUNIC_POWER",
    SHAMAN = "MANA",
    MAGE = "MANA",
    WARLOCK = "MANA",
    MONK = "ENERGY",
    DRUID = "MANA",
    DEMONHUNTER = "FURY",
    EVOKER = "MANA",
}

-- Canonical 13-class token sequence (role order) for class pickers/grids, read-only; sites needing a DIFFERENT order (e.g. alphabetical) keep local lists.
CludesUI.CLASS_TOKEN_ORDER = {
    "WARRIOR",
    "PALADIN",
    "HUNTER",
    "ROGUE",
    "PRIEST",
    "DEATHKNIGHT",
    "SHAMAN",
    "MAGE",
    "WARLOCK",
    "MONK",
    "DRUID",
    "DEMONHUNTER",
    "EVOKER",
}

-- Class -> resource type mapping (nil = no class resource)
CludesUI.CLASS_RESOURCE_MAP = {
    ROGUE = "ComboPoints",
    DRUID = "ComboPoints",
    PALADIN = "HolyPower",
    MONK = "Chi",
    WARLOCK = "SoulShards",
    MAGE = "ArcaneCharges",
    EVOKER = "Essence",
    DEATHKNIGHT = "Runes",
    DEMONHUNTER = "SoulFragments",
}

-- Darken a color by a fraction (for default gradient secondary)
function CludesUI.DarkenColor(r, g, b, frac)
    frac = frac or 0.10
    return r * (1 - frac), g * (1 - frac), b * (1 - frac)
end

-- Effective in-game custom colours for all rendering consumers (lazy-init). Stored PER
-- PROFILE (db.profiles[name].customColors: class / power / classResource / resource).
-- Each colour SECTION of the Colors page picks its own palette source (class, power,
-- classResource; resource rides classResource):
--   "Apply to All Profiles" ON (default): ONE chosen profile's section (its "Pull
--        Colors From", default the first profile) shared across EVERY profile.
--   OFF (per-profile): the ACTIVE profile's own section.
-- The per-section keys (CludesUIDB.colorsSectionApplyAll / colorsSectionPullFrom,
-- keyed by section) are account-wide like the original pair (colorsApplyToAllProfiles
-- / colorsPullFrom), which a section with no key of its own still reads -- an account
-- from before the split resolves exactly as it did, nothing migrated.
-- Nothing is wiped/restored on a profile switch (the getter just resolves different
-- tables), so a spec-switch colour wipe cannot happen. Missing tables -> defaults.
CludesUI.COLOR_SECTIONS = { "class", "power", "classResource" }
CludesUI._COLOR_SECTION_OF =
    { class = "class", power = "power", classResource = "classResource", resource = "classResource" }
-- The palette GetCustomColorsDB hands out: its four category fields are the LIVE
-- tables of each section's source profile, so in-place writes (db.class[token] = c)
-- land where the section resolves and a DeepCopy of it is the effective palette.
-- One reused table, refreshed every call; callers never keep it.
CludesUI._ccComposite = {}

function CludesUI.ColorSectionApplyAll(section)
    local saved = CludesUIDB
    local own = saved and saved.colorsSectionApplyAll and saved.colorsSectionApplyAll[section]
    if own ~= nil then
        return own
    end
    return not (saved and saved.colorsApplyToAllProfiles == false)
end

-- The NAME of the profile a section pulls from in global mode. Dangling pointers
-- (a profile removed by a path that missed the DeleteProfile/RenameProfile cleanup,
-- or a DB saved before that cleanup existed) are dropped, so the section falls back
-- to the shared pointer, then the first profile, instead of the legacy table.
function CludesUI.ColorSectionPullFrom(section)
    local saved = CludesUIDB
    if not (saved and CludesUI.GetProfilesDB) then
        return nil
    end
    local pdb = CludesUI.GetProfilesDB()
    local profiles = pdb.profiles
    local t = saved.colorsSectionPullFrom
    local own = t and t[section]
    if own and not (profiles and profiles[own]) then
        t[section] = nil
        own = nil
    end
    local shared = saved.colorsPullFrom
    if shared and not (profiles and profiles[shared]) then
        saved.colorsPullFrom = nil
        shared = nil
    end
    return own or shared or (pdb.profileOrder and pdb.profileOrder[1])
end

function CludesUI.SetColorSectionApplyAll(section, enabled)
    if not CludesUIDB then
        return
    end
    CludesUIDB.colorsSectionApplyAll = CludesUIDB.colorsSectionApplyAll or {}
    CludesUIDB.colorsSectionApplyAll[section] = enabled and true or false
end

function CludesUI.SetColorSectionPullFrom(section, name)
    if not CludesUIDB then
        return
    end
    CludesUIDB.colorsSectionPullFrom = CludesUIDB.colorsSectionPullFrom or {}
    CludesUIDB.colorsSectionPullFrom[section] = name
end

-- True while any section reads the active profile's own colours (a profile switch
-- then changes what renders).
function CludesUI.AnyColorSectionPerProfile()
    for _, s in ipairs(CludesUI.COLOR_SECTIONS) do
        if not CludesUI.ColorSectionApplyAll(s) then
            return true
        end
    end
    return false
end

-- Point every global-mode section at profile `name` (an import that carries colours
-- shows them): its own pointer when it has one, else the shared pointer it reads.
-- Per-profile sections already read the active profile.
function CludesUI.PointColorSectionsAt(name)
    if not CludesUIDB then
        return
    end
    local t = CludesUIDB.colorsSectionPullFrom
    local sharedUsed = false
    for _, s in ipairs(CludesUI.COLOR_SECTIONS) do
        if CludesUI.ColorSectionApplyAll(s) then
            if t and t[s] ~= nil then
                t[s] = name
            else
                sharedUsed = true
            end
        end
    end
    if sharedUsed then
        CludesUIDB.colorsPullFrom = name
    end
end

-- A deleted profile drops out of every source pointer (nil = the default); returns
-- true when one pointed at it. A renamed profile is followed (same palette tables).
function CludesUI.ColorSourcesProfileRemoved(name)
    if not CludesUIDB then
        return false
    end
    local hit = false
    if CludesUIDB.colorsPullFrom == name then
        CludesUIDB.colorsPullFrom = nil
        hit = true
    end
    local t = CludesUIDB.colorsSectionPullFrom
    if t then
        for s, num in pairs(t) do
            if num == name then
                t[s] = nil
                hit = true
            end
        end
    end
    return hit
end
function CludesUI.ColorSourcesProfileRenamed(oldName, newName)
    if not CludesUIDB then
        return
    end
    if CludesUIDB.colorsPullFrom == oldName then
        CludesUIDB.colorsPullFrom = newName
    end
    local t = CludesUIDB.colorsSectionPullFrom
    if t then
        for s, num in pairs(t) do
            if num == oldName then
                t[s] = newName
            end
        end
    end
end

-- The profile whose customColors feed `section` (nil without profiles).
function CludesUI._ColorSectionProfile(section)
    if not CludesUI.GetProfilesDB then
        return nil
    end
    local pdb = CludesUI.GetProfilesDB()
    local name
    if CludesUI.ColorSectionApplyAll(section) then
        name = CludesUI.ColorSectionPullFrom(section)
    else
        name = pdb.activeProfile or "Default"
    end
    return name and pdb.profiles and pdb.profiles[name]
end

function CludesUI.GetCustomColorsDB()
    if not CludesUIDB then
        CludesUIDB = {}
    end
    if not CludesUIDB.customColors then
        CludesUIDB.customColors = {}
    end
    local result = CludesUI._ccComposite
    for key, section in pairs(CludesUI._COLOR_SECTION_OF) do
        local prof = CludesUI._ColorSectionProfile(section)
        local cc
        if prof then
            prof.customColors = prof.customColors or {}
            cc = prof.customColors
        else
            cc = CludesUIDB.customColors
        end
        local category = cc[key]
        if type(category) ~= "table" then
            category = {}
            cc[key] = category
        end
        result[key] = category
    end
    return result
end

-- A section's colour editing locks ONLY in global mode while viewing a profile other
-- than its source (editing a dormant palette would mislead). Per-profile mode is always
-- editable; global mode is editable on the source profile. No section = Class.
function CludesUI.IsColorEditingLocked(section)
    section = section or "class"
    if not (CludesUIDB and CludesUI.GetProfilesDB) then
        return false
    end
    if not CludesUI.ColorSectionApplyAll(section) then
        return false
    end
    local pdb = CludesUI.GetProfilesDB()
    local source = CludesUI.ColorSectionPullFrom(section)
    return source ~= nil and source ~= (pdb.activeProfile or "Default")
end

-------------------------------------------------------------------------------
--  Dark Mode (per-profile)
--  One shared palette feeds the Dark Mode look of Unit Frames, Raid Frames and
--  Resource Bars, plus "darken" amounts that blacken class/power/class-resource
--  colours inside the colour getters below (every consumer gets adjusted values,
--  no per-module logic). Stored at CludesUIDB.profiles[name].darkMode (sibling
--  of customColors) and ALWAYS the ACTIVE profile's own table -- no "Apply to All
--  Profiles" redirect. Defaults: #111111 fill @ 90%, #4f4f4f bg @ 100%, zero darken.
-------------------------------------------------------------------------------
CludesUI.DEFAULT_DARK_MODE = {
    fillR = 0x11 / 255,
    fillG = 0x11 / 255,
    fillB = 0x11 / 255,
    fillA = 0.90,
    bgR = 0x4f / 255,
    bgG = 0x4f / 255,
    bgB = 0x4f / 255,
    bgA = 1.0,
    classDarken = 0,
    powerDarken = 0,
    resourceDarken = 0,
    powerBgDarken = 0,
}

-- The active profile's dark-mode table (lazily created, may be sparse -- callers
-- fall back to DEFAULT_DARK_MODE per field). Never returns nil.
function CludesUI.GetDarkModeDB()
    if CludesUI.GetProfilesDB then
        local pdb = CludesUI.GetProfilesDB()
        if pdb and pdb.profiles then
            local isActive = pdb.profiles[pdb.activeProfile or "Default"]
            if isActive then
                isActive.darkMode = isActive.darkMode or {}
                return isActive.darkMode
            end
        end
    end
    if not CludesUIDB then
        CludesUIDB = {}
    end
    CludesUIDB.darkMode = CludesUIDB.darkMode or {}
    return CludesUIDB.darkMode
end

-- Materialized Dark Mode palette. The fill and background quadruples are read on
-- every raid-frame and unit-frame health tick, so they are served from this cache
-- instead of walking to the active profile per read. Rebuilt lazily after an
-- invalidation; the generation is bumped by InvalidateColorCache, which every
-- writer reaches: the swatches and darken sliders (RefreshDarkMode), the master
-- toggle (RefreshDarkMode), every profile repoint (RefreshDarkMode in the profile
-- apply pass) and ApplyColorsToOUF. Lives on the namespace: this file sits at the
-- 200-local cap.
CludesUI._dmGen = 0
CludesUI._dmCache = { gen = -1 }

function CludesUI._RebuildDarkModeCache()
    local c = CludesUI._dmCache
    local d = CludesUI.GetDarkModeDB()
    local spec_def = CludesUI.DEFAULT_DARK_MODE
    c.fr, c.fg, c.fb, c.fa =
        d.fillR or spec_def.fillR,
        d.fillG or spec_def.fillG,
        d.fillB or spec_def.fillB,
        d.fillA or spec_def.fillA
    c.br, c.bg, c.bb, c.ba =
        d.bgR or spec_def.bgR, d.bgG or spec_def.bgG, d.bgB or spec_def.bgB, d.bgA or spec_def.bgA
    c.gen = CludesUI._dmGen
end

-- Dark Mode fill colour (r, g, b, a). Opacity is honoured by Unit Frames and
-- Raid Frames; Resource Bars ignore the alpha and keep their own.
function CludesUI.GetDarkModeFill()
    local c = CludesUI._dmCache
    if c.gen ~= CludesUI._dmGen then
        CludesUI._RebuildDarkModeCache()
    end
    return c.fr, c.fg, c.fb, c.fa
end

-- Dark Mode background colour (r, g, b, a). Same opacity rules as the fill.
function CludesUI.GetDarkModeBg()
    local c = CludesUI._dmCache
    if c.gen ~= CludesUI._dmGen then
        CludesUI._RebuildDarkModeCache()
    end
    return c.br, c.bg, c.bb, c.ba
end

-- Effective-colour cache. Class/power/resource getters run in hot render paths, so the FINAL
-- colours (palette + darken) are precomputed once and served as cached {r,g,b} tables: rebuilt
-- lazily on first read after invalidation, reads are one lookup with zero allocation.
-- Invalidation inputs: ApplyColorsToOUF (the universal "colours changed" chokepoint -- swatch
-- edits, resets, mode toggles, profile switches) and RefreshDarkMode. READ-ONLY derived cache: worst failure is a stale colour.
CludesUI._colorCache =
    { class = {}, classRaw = {}, power = {}, classResource = {}, resource = {}, classCustomized = {} }
CludesUI._colorCacheDirty = true
CludesUI._COLOR_WHITE = { r = 1, g = 1, b = 1 }
CludesUI._powerBgDarkenFactor = 1

function CludesUI.InvalidateColorCache()
    CludesUI._colorCacheDirty = true
    -- The dark palette cache above shares every invalidation input.
    CludesUI._dmGen = CludesUI._dmGen + 1
end

-- Fill `out` with {r,g,b} per key: defaults overlaid by custom, blackened by darkenPct (0-100); sub-tables are recreated each rebuild (rare) so hot-path reads never allocate.
function CludesUI._BuildColorPalette(result, defaultSet, custom, darkenPct)
    wipe(result)
    if defaultSet then
        for k, spec_def in pairs(defaultSet) do
            result[k] = { r = spec_def.r, g = spec_def.g, b = spec_def.b }
        end
    end
    if custom then
        for k, c in pairs(custom) do
            result[k] = { r = c.r, g = c.g, b = c.b }
        end
    end
    if darkenPct and darkenPct > 0 then
        local f = 1 - darkenPct / 100
        if f < 0 then
            f = 0
        end
        for _, column in pairs(result) do
            column.r = column.r * f
            column.g = column.g * f
            column.b = column.b * f
        end
    end
end

function CludesUI._RebuildColorCache()
    local cc = CludesUI.GetCustomColorsDB()
    local dm = CludesUI.GetDarkModeDB()
    local cache = CludesUI._colorCache
    CludesUI._BuildColorPalette(cache.class, CludesUI.CLASS_COLOR_MAP, cc and cc.class, dm and dm.classDarken)
    CludesUI._BuildColorPalette(cache.classRaw, CludesUI.CLASS_COLOR_MAP, cc and cc.class, 0)
    CludesUI._BuildColorPalette(
        cache.power,
        CludesUI.DEFAULT_POWER_COLORS,
        cc and cc.power,
        dm and dm.powerDarken
    )
    CludesUI._BuildColorPalette(
        cache.classResource,
        CludesUI.DEFAULT_CLASS_RESOURCE_COLORS,
        cc and cc.classResource,
        dm and dm.resourceDarken
    )
    CludesUI._BuildColorPalette(
        cache.resource,
        CludesUI.DEFAULT_RESOURCE_COLORS,
        cc and cc.resource,
        dm and dm.resourceDarken
    )
    -- BG Power Color Darken: extra blacken for power-COLORED bar backgrounds, kept as a multiplier (not a palette) so it stacks on whatever power color a consumer resolved.
    local bgd = (dm and dm.powerBgDarken) or 0
    CludesUI._powerBgDarkenFactor = bgd > 0 and math.max(0, 1 - bgd / 100) or 1
    -- Classes whose effective colour no longer matches Blizzard's default (a swatch edit, or any
    -- nonzero class darken). Only these need the restricted-unit recovery below; an untouched
    -- palette leaves the table empty, so that path costs one next() and stops.
    local customized = cache.classCustomized
    wipe(customized)
    for token, spec_def in pairs(CludesUI.CLASS_COLOR_MAP) do
        local column = cache.class[token]
        if
            column
            and (
                math.abs(column.r - spec_def.r) > 0.004
                or math.abs(column.g - spec_def.g) > 0.004
                or math.abs(column.b - spec_def.b) > 0.004
            )
        then
            customized[token] = column
        end
    end
    CludesUI._restrictedCandidatesDirty = true
    CludesUI._colorCacheDirty = false
end

-- Modules register a callback re-reading the dark palette and repainting their frames; RefreshDarkMode() runs them all and re-pushes class/power colours via ApplyColorsToOUF.
CludesUI._darkModeRefreshers = CludesUI._darkModeRefreshers or {}
function CludesUI.RegisterDarkModeRefresh(func)
    if type(func) == "function" then
        CludesUI._darkModeRefreshers[#CludesUI._darkModeRefreshers + 1] = func
    end
end
function CludesUI.RefreshDarkMode()
    -- Darken amounts feed the colour cache; drop it so refreshers + the OUF push below resolve freshly darkened colours.
    CludesUI.InvalidateColorCache()
    for _, func in ipairs(CludesUI._darkModeRefreshers) do
        pcall(func)
    end
    if CludesUI.ApplyColorsToOUF then
        CludesUI.ApplyColorsToOUF()
    end
end

-- Global Dark Mode providers. Each module stores its own flag in its own DB shape (UF
-- darkTheme; RB secondary.darkTheme; RF healthColorMode == "dark"), so each registers a
-- provider that reads/flips its flag AND repaints its frames. The Colors page's Dark Mode
-- dropdown is a pure view over them (one row each): no stored key, so it can never desync from the per-module toggles.
CludesUI._darkModeToggles = CludesUI._darkModeToggles or {}
function CludesUI.RegisterDarkModeToggle(provider)
    if
        type(provider) == "table"
        and type(provider.isOn) == "function"
        and type(provider.setOn) == "function"
    then
        CludesUI._darkModeToggles[#CludesUI._darkModeToggles + 1] = provider
    end
end

-- True only when every registered module has Dark Mode on (and at least one is registered).
-- Optional `filter(provider) -> boolean` narrows which providers count, so one checkbox can view a single group and read "on" only when that group is all dark.
function CludesUI.IsDarkModeAllOn(filter)
    local matched = false
    for _, p in ipairs(CludesUI._darkModeToggles) do
        if not filter or filter(p) then
            matched = true
            local success, enabled = pcall(p.isOn)
            if not success or not enabled then
                return false
            end
        end
    end
    return matched
end

-- Flip every module's Dark Mode to `on`, then refresh the shared palette so palette-listening modules repaint too. `filter` narrows as in IsDarkModeAllOn.
function CludesUI.SetDarkModeAll(enabled, filter)
    enabled = enabled and true or false
    for _, p in ipairs(CludesUI._darkModeToggles) do
        if not filter or filter(p) then
            pcall(p.setOn, enabled)
        end
    end
    CludesUI.RefreshDarkMode()
    -- Dark Mode feeds the conditional-override "darkmode" condition. Deliberately here, NOT in
    -- RefreshDarkMode: SetDarkModeAll is only called by the Colors page's Dark Mode dropdown
    -- (pure user action), while RefreshDarkMode is also reached from the profile-apply pipeline
    -- where an extra recheck could interleave with the conditions establish choreography (cheap no-op with no darkmode group; self-defers in combat).
    if CludesUI.Conditions_Recheck then
        CludesUI.Conditions_Recheck()
    end
end

-- Class color (custom or default) with Class Color Darken baked in by the cache, so every consumer gets the adjusted colour with no per-module logic. Unknown -> white.
function CludesUI.GetClassColor(classToken)
    if CludesUI._colorCacheDirty then
        CludesUI._RebuildColorCache()
    end
    return CludesUI._colorCache.class[classToken] or CludesUI._COLOR_WHITE
end

-- Class color (custom or default) WITHOUT Class Color Darken, for accents and cursors
-- rather than bars. Unknown -> nil.
function CludesUI.GetRawClassColor(classToken)
    if CludesUI._colorCacheDirty then
        CludesUI._RebuildColorCache()
    end
    return CludesUI._colorCache.classRaw[classToken]
end

-- Class token from a localized class name (friend list entries carry only that).
-- Male and female forms both map; built once on first use. Unknown or secret -> nil.
function CludesUI.ClassTokenFromLocalized(name)
    if type(name) ~= "string" or issecretvalue(name) then
        return nil
    end
    local map = CludesUI._classByLocalName
    if not map then
        map = {}
        if LOCALIZED_CLASS_NAMES_MALE then
            for token, num in pairs(LOCALIZED_CLASS_NAMES_MALE) do
                map[num] = token
            end
        end
        if LOCALIZED_CLASS_NAMES_FEMALE then
            for token, num in pairs(LOCALIZED_CLASS_NAMES_FEMALE) do
                map[num] = token
            end
        end
        CludesUI._classByLocalName = map
    end
    return map[name]
end

-- Custom class colour for a unit whose identity is RESTRICTED (target-of-target, focus-target):
-- UnitClass hands back a SECRET token there, and a secret cannot be a table key, so the palette
-- above is unreachable and callers fall back to C_ClassColor.GetClassColor(secretToken) -- right
-- class, but Blizzard's default shade instead of the user's.
-- Such a unit is nearly always someone in the group, whose own token IS readable, so the class
-- can be recovered without ever naming the unit: UnitIsUnit does the identity compare in C (its
-- answer is itself secret when the comparison is restricted) and C_CurveUtil picks between two
-- colour components from that secret boolean, also in C. Lua only ever handles opaque values.
-- Returns ok, r, g, b -- ok is a PLAIN boolean, r/g/b may be SECRET numbers: feed them straight
-- to a setter, never inspect or do arithmetic on them.
--
-- SCOPE, measured in a 12.1 dungeon: under an identity restriction the client will answer "is
-- this unit me?" (CanCompareUnitTokens true, UnitIsUnit a SECRET boolean) and REFUSES every
-- other pairing (CanCompareUnitTokens false, UnitIsUnit returns nil, both argument orders).
-- Refuses by returning nothing, not by erroring, which is why the loop below type-checks the
-- answer instead of trusting it. So in practice this recovers the colour when the restricted
-- unit is the player, and other group members keep Blizzard's shade -- knowing WHICH other
-- player an enemy is on is the exact fact the restriction exists to hide. The roster loop is
-- kept general rather than hardcoded to "player" so it starts working if that ever relaxes.
--
-- Which group members are worth comparing against only changes on a roster or palette edit, so
-- the list is cached as a flat unit/colour array (no per-call allocation, no per-call UnitClass
-- or token concat). Only the compares themselves have to run live.
CludesUI._restrictedCandidates = {}
CludesUI._restrictedCandidatesDirty = true

-- Namespaced, not file-locals: this chunk sits at Lua's 200-local ceiling.
function CludesUI._RebuildRestrictedCandidates()
    local result = CludesUI._restrictedCandidates
    wipe(result)
    local customized = CludesUI._colorCache.classCustomized
    if next(customized) then
        local inRaid = IsInRaid()
        local members = GetNumGroupMembers() or 0
        -- Raid rosters run raid1..raidN (player included); party rosters are player + party1..N-1.
        local first = inRaid and 1 or 0
        local last = inRaid and members or (members > 0 and members - 1 or 0)
        for idx = first, last do
            local u = (idx == 0) and "player" or ((inRaid and "raid" or "party") .. idx)
            local _, token = UnitClass(u)
            local column = (type(token) == "string" and not issecretvalue(token)) and customized[token]
            if column then
                result[#result + 1] = u
                result[#result + 1] = column
            end
        end
    end
    CludesUI._restrictedCandidatesDirty = false
end

-- Created on the first restricted lookup, so a profile that never needs one never registers it.
function CludesUI._EnsureRestrictedRosterWatcher()
    if CludesUI._restrictedRosterWatcher then
        return
    end
    local f = CreateFrame("Frame")
    f:RegisterEvent("GROUP_ROSTER_UPDATE")
    f:SetScript("OnEvent", function()
        CludesUI._restrictedCandidatesDirty = true
    end)
    CludesUI._restrictedRosterWatcher = f
end

function CludesUI.GetClassColorForRestrictedUnit(unitToken, secretClassToken)
    if CludesUI._colorCacheDirty then
        CludesUI._RebuildColorCache()
    end
    if not next(CludesUI._colorCache.classCustomized) then
        return false
    end
    local pick = C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean
    if not (pick and C_ClassColor and C_ClassColor.GetClassColor) then
        return false
    end
    CludesUI._EnsureRestrictedRosterWatcher()
    if CludesUI._restrictedCandidatesDirty then
        CludesUI._RebuildRestrictedCandidates()
    end
    local candidates = CludesUI._restrictedCandidates
    local total = #candidates
    -- Nobody around wears a customised colour: let the caller take Blizzard's shade unchanged.
    if total == 0 then
        return false
    end
    local baseValue = C_ClassColor.GetClassColor(secretClassToken)
    if not baseValue then
        return false
    end
    local r, g, b = baseValue.r, baseValue.g, baseValue.b
    local canCompare = C_Secrets and C_Secrets.CanCompareUnitTokens
    for idx = 1, total, 2 do
        local u = candidates[idx]
        -- CanCompareUnitTokens false means UnitIsUnit answers nothing, not that it goes secret.
        if (not canCompare) or canCompare(unitToken, u) then
            local isSameUnit = UnitIsUnit(unitToken, u)
            -- Belt and braces: the predicate above should have caught a refusal, and a nil
            -- reaching pick() would throw. type() reports a secret's underlying type, so a
            -- secret boolean -- the whole point of this fold -- passes here.
            if type(isSameUnit) == "boolean" then
                local column = candidates[idx + 1]
                r = pick(isSameUnit, column.r, r)
                g = pick(isSameUnit, column.g, g)
                b = pick(isSameUnit, column.b, b)
            end
        end
    end
    return true, r, g, b
end

-- Get power color (cached, darken baked in). Returns nil for unknown keys.
function CludesUI.GetPowerColor(powerKey)
    if CludesUI._colorCacheDirty then
        CludesUI._RebuildColorCache()
    end
    return CludesUI._colorCache.power[powerKey]
end

-- Multiplier (0-1) for power-COLORED bar backgrounds (Dark Mode "BG Power Color
-- Darken"); stacks on the consumer's resolved power color. 1 = identity (slider at 0).
function CludesUI.GetPowerBgDarkenFactor()
    if CludesUI._colorCacheDirty then
        CludesUI._RebuildColorCache()
    end
    return CludesUI._powerBgDarkenFactor
end

-- Get resource color (cached, darken baked in). Returns nil for unknown keys.
-- Shares Resource Color Darken with GetClassResourceColor.
function CludesUI.GetResourceColor(classToken)
    if CludesUI._colorCacheDirty then
        CludesUI._RebuildColorCache()
    end
    return CludesUI._colorCache.resource[classToken]
end

-- Reset a specific power color
function CludesUI.ResetPowerColor(powerKey)
    local saved = CludesUI.GetCustomColorsDB()
    if saved.power then
        saved.power[powerKey] = nil
    end
    CludesUI.InvalidateColorCache()
end

-- Power key string -> Enum.PowerType mapping
CludesUI.POWER_KEY_TO_ENUM = {
    MANA = 0,
    RAGE = 1,
    FOCUS = 2,
    ENERGY = 3,
    RUNIC_POWER = 6,
    LUNAR_POWER = 8,
    INSANITY = 13,
    MAELSTROM = 11,
    FURY = 17,
    PAIN = 18,
}

-- Integer power-type -> string key (reverse of POWER_KEY_TO_ENUM). UnitPowerType's 1st return
-- is readable on EVERY unit, so it recovers a color key when the string token (2nd return) is unreadable, as on non-player units (boss/target/focus).
CludesUI.POWER_ENUM_TO_KEY = {}
for k, val in pairs(CludesUI.POWER_KEY_TO_ENUM) do
    CludesUI.POWER_ENUM_TO_KEY[val] = k
end

-- CUI power color (r,g,b or nil) for a unit's CURRENT power. Mirrors oUF's bar ladder so
-- unit-frame TEXT matches the bar on EVERY unit, including non-player:
--   1) Named token -> custom/default color (all standard types; the player lands here).
--   2) NON-STANDARD types (creatures/NPCs) report an unmapped token but an integer type
--      colliding with a standard slot (cosmic energy -> 3 = Energy); the engine returns
--      the REAL color in altR/altG/altB (what oUF paints the bar with), so use it.
--   3) Token unmatched, no alt color, standard integer type -> custom color (safety net).
function CludesUI.ResolveUnitPowerColor(unitToken)
    -- Player: the forced display power type (UF Power Type dropdown) wins over
    -- the real one, resolved live so it never lags a setting or spec change.
    if unitToken == "player" and CludesUI.GetPlayerPowerOverride then
        local override = CludesUI.GetPlayerPowerOverride()
        if override ~= nil then
            local overrideKey = CludesUI.POWER_ENUM_TO_KEY[override]
            local overrideInfo = overrideKey and CludesUI.GetPowerColor(overrideKey)
            if overrideInfo then
                return overrideInfo.r, overrideInfo.g, overrideInfo.b
            end
        end
    end
    local pType, pToken, altR, altG, altB = UnitPowerType(unitToken)
    local details = CludesUI.GetPowerColor(pToken)
    if details then
        return details.r, details.g, details.b
    end
    if altR then
        -- UnitPowerType may hand back 0-255 or 0-1 ranges; normalize (per oUF).
        if altR > 1 or altG > 1 or altB > 1 then
            return altR / 255, altG / 255, altB / 255
        end
        return altR, altG, altB
    end
    local key = CludesUI.POWER_ENUM_TO_KEY[pType]
    details = key and CludesUI.GetPowerColor(key)
    if details then
        return details.r, details.g, details.b
    end
    return nil
end

-- The unit-frame engine's shared color objects (class and power) from the current
-- palette. ApplyColorsToOUF runs it first; Unit Frames runs it alone at login, before
-- its frames spawn, where repainting every module would change nothing (each paints
-- the current palette as it builds).
function CludesUI.SyncUFColors()
    -- Drop the effective-colour cache; the GetClassColor/GetPowerColor reads below
    -- rebuild it from the palette + darken.
    CludesUI.InvalidateColorCache()
    -- NEVER modify _G.RAID_CLASS_COLORS: taint.
    local colors = CludesUI._UFColors
    if not colors then
        return
    end
    if colors.class then
        for classToken, _ in pairs(CLASS_COLOR_MAP) do
            local cc = CludesUI.GetClassColor(classToken)
            local record = colors.class[classToken]
            if record and record.SetRGBA then
                record:SetRGBA(cc.r, cc.g, cc.b, 1)
            else
                colors.class[classToken] = CreateColor(cc.r, cc.g, cc.b, 1)
            end
        end
    end
    if colors.power then
        for powerKey, enumVal in pairs(CludesUI.POWER_KEY_TO_ENUM) do
            local pc = CludesUI.GetPowerColor(powerKey)
            local record = colors.power[enumVal]
            if record and record.SetRGBA then
                record:SetRGBA(pc.r, pc.g, pc.b, 1)
            else
                colors.power[enumVal] = CreateColor(pc.r, pc.g, pc.b, 1)
            end
        end
    end
end

-- Apply custom class colors to oUF (call after settings change)
function CludesUI.ApplyColorsToOUF()
    -- Universal "colours changed" entry point (swatch edits, resets, global-mode toggle,
    -- Pull Colors From, profile switches).
    -- 1. The unit-frame engine's shared color objects, then a repaint of its frames.
    CludesUI.SyncUFColors()
    if CludesUI._UFColors and CludesUI._UFEngineForceAll then
        CludesUI._UFEngineForceAll("ForceUpdate")
    end
    if CludesUI._UFRecolorAllTexts then
        CludesUI._UFRecolorAllTexts()
    end
    -- 3. Refresh nameplates (enemy + friendly)
    local ns_NP = _G.CludesNameplates_NS
    if ns_NP then
        if ns_NP.plates then
            for _, backing in pairs(ns_NP.plates) do
                if backing.UpdateHealthColor then
                    backing:UpdateHealthColor()
                end
            end
        end
        -- Friendly full plates repaint through the module, which respects Class
        -- Colored Health Bar being off and repaints class-coloured names and
        -- guild lines too.
        if ns_NP.RefreshFriendlyColors then
            ns_NP.RefreshFriendlyColors(true)
        end
    end
    -- 4. Refresh raid frames
    local ERF = _G.CludesUIRaidFrames
    if ERF and ERF.UpdateAllFrames then
        ERF:UpdateAllFrames()
    end
    -- 5. Refresh action bar borders (class-colored borders read RAID_CLASS_COLORS)
    local success, ABAR = pcall(function()
        return CludesUI.Lite and CludesUI.Lite.GetAddon("CludesUIActionBars", true)
    end)
    if success and ABAR and ABAR.ApplyBorders and not InCombatLockdown() then
        ABAR:ApplyBorders()
        if ABAR.ApplyShapes then
            ABAR:ApplyShapes()
        end
    end
    -- 6. Refresh damage meters (bars/text class colors)
    if CludesUI._DM_RefreshColors then
        CludesUI._DM_RefreshColors()
    end
    -- 7. A class-colored accent or cursor follows a class swatch edit; the accent
    -- re-applies only when it changed (that path redraws the options page).
    do
        local r, g, b = CludesUI.ResolveActiveAccent()
        local cr, cg, cb = CludesUI.GetAccentColor()
        if r ~= cr or g ~= cg or b ~= cb then
            CludesUI.RefreshAccent()
        end
    end
    if _G._CUCL_Apply then
        _G._CUCL_Apply()
    end
    if _G._CUCL_ApplyTrail then
        _G._CUCL_ApplyTrail()
    end
    if _G._CUCL_ApplyGCDCircle then
        _G._CUCL_ApplyGCDCircle()
    end
    if _G._CUCL_ApplyCastCircle then
        _G._CUCL_ApplyCastCircle()
    end
end

-------------------------------------------------------------------------------
--  WoW Forever stat hues (hex, no |cff), one per stat, shared by the Quality
--  of Life Secondary Stats block (CludesUIQoL_ForeverStats.lua) and Forever
--  Essentials' Simplified Stats tooltip lines. Forever only.
-------------------------------------------------------------------------------
if CludesUI.IS_FOREVER then
    CludesUI.FOREVER_STAT_HUES = {
        str = "c79c6e",
        agi = "abd473",
        sta = "ef5350",
        int = "69ccf0",
        spi = "ffe082",
        health = "ef5350",
        mana = "4fc3f7",
        ap = "ff8c42",
        crit = "ffd100",
        haste = "7fe3d4",
        hit = "ffa94d",
        sp = "c77dff",
        healing = "4ec9b0",
        spen = "b39ddb",
        holy = "fff2b0",
        fire = "ff6b35",
        frost = "3fc7eb",
        nature = "4caf50",
        shadow = "a335ee",
        arcane = "ff7eb6",
        armor = "b0bec5",
        avoid = "64b5f6",
        mp5 = "4fc3f7",
        hp5 = "e57373",
        speed = "81c784",
    }
end
