if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUIRaidFrames.lua
--  Custom raid frames built on SecureGroupHeaderTemplate.
--  8 per-group headers (separated mode) + 1 combined header (flat mode).
--  Secret-value-safe absorb shields matching UnitFrames visuals.
-------------------------------------------------------------------------------
local ADDON_NAME, mod = ...
if
    not (
        CludesUI
        and CludesUI._ModuleNS
        and CludesUI.NewInternals
        and CludesUI.NewCombatQueue
        and CludesUI.SetFrameScale
        and CludesUI.HideFrame
        and CludesUI._Pool
        and CludesUI.NewFrameData
        and CludesUI.AbbreviateValue
        and CludesUI.IsZeroValue
        and CludesUI.UnitNameFormat
        and CludesUI.OwnSurnameHidden
        and CludesUI.ApplyModuleFontFamily
        and CludesUI.SetFontFamily
        and CludesUI.UIScaledAlpha
        and CludesUI.OnUIAlphaChanged
        and CludesUI.PREVIEW_ROSTER
    )
then
    CUI_CLIENT_BLOCKED = true
    return
end -- stale-parent guard: a partially updated install (old parent, new child) goes dormant via the line-1 failsafe instead of erroring (the Blizzard raid and party frame suppression hides and scales through the parent's HideFrame and SetFrameScale, and the health texts format through the parent's AbbreviateValue, the [absorb:abr] tags blank at zero through its IsZeroValue, and the Name Format asks its UnitNameFormat, and the [name:last] and [target:last] tags its OwnSurnameHidden, and the texts that show names take their font family through its ApplyModuleFontFamily and SetFontFamily, and the 3D portraits follow a faded UI through its UIScaledAlpha and OnUIAlphaChanged, and the preview names its members from its PREVIEW_ROSTER)
CludesUI._ModuleNS[ADDON_NAME] = mod -- LOD options files read this module ns via the registry

local ERF = CludesUI.Lite.NewAddon(ADDON_NAME)
mod.ERF = ERF
_G.CludesUIRaidFrames = ERF

-- Parent-addon table cached on ns: hot event paths (UNIT_AURA,
-- PLAYER_REGEN_DISABLED) reading the GLOBAL CludesUI from an event frame
-- still in a secure execution context raise benign self-taint; table-field
-- reads do not.
mod.CludesUI = CludesUI

-- Addon name external nickname providers key us by. Suite = the brand
-- "CludesUI" (what providers register support for); standalone = our
-- renamed folder name (ADDON_NAME), the per-addon key. "Standalone" survives
-- the standalone token rename, so detection is rename-immune and the
-- "CludesUI" literal is only reached in the suite.
mod.EXT_NICK = CludesUI.EXT_NICK
mod.NICK_ADDON = ADDON_NAME:find("Standalone") and ADDON_NAME or mod.EXT_NICK.addon

-- Keep subgroup identity separate from its visual slot. Invalid imported
-- orders fall back to the original layout without touching SavedVariables.
function mod._RFValidatedGroupOrder(sequence)
    if type(sequence) ~= "table" or #sequence ~= 8 then
        return nil
    end
    for index = 1, 8 do
        local set = sequence[index]
        if type(set) ~= "number" or set < 1 or set > 8 or set % 1 ~= 0 then
            return nil
        end
        for previous = 1, index - 1 do
            if sequence[previous] == set then
                return nil
            end
        end
    end
    return sequence
end

-------------------------------------------------------------------------------
--  Frame-level layout (offsets above the button / preview-frame level).
--  All aura VISUALS (debuffs, defensives/externals, private auras, dispel-type
--  icons, Buff Manager icons/squares/bars) share one band ABOVE the
--  threat/dispel/base border so the threat border renders behind them; each
--  aura unit renders children (cooldown/border/text) up to +5 above base.
--  Bottom to top: base border (+8/strips +9) -> dispel ring and Buff Manager
--  Frame Border (LVL_RAISE - 1, strips +10) -> hover/target/aggro raise (LVL_RAISE,
--  strips +11, covering base/threat/dispel border strips) -> text band
--  (LVL_TEXT: name/health text, role icon, leader crown) -> aura band ->
--  marker carrier (also hosts ready-check/summon/rez icons). The raise sits
--  BELOW text deliberately so borders never cover text and auras always draw
--  over text; it outranks only neighbor BORDERS, so with negative spacing a
--  neighbor's text/auras can clip it. Opt-out "Show Above Icons" (name cog)
--  lifts a button's text carrier to ns.LVL_AURA + 6, above the aura band's
--  children. On `ns`, shared with CUI_RaidFrames_BuffManager.lua.
-------------------------------------------------------------------------------
mod.LVL_DISPEL_OVERLAY = 7 -- Blizzard private-aura dispel gradient: below the border (+8) and name/health text (LVL_TEXT) so it renders BEHIND them (like the regular dispel overlay), but above the health bar so it stays visible. Per-slot private-aura icons stay above at LVL_AURA.
mod.LVL_ROLE_BEHIND = 7 -- role icon with Show Behind Border: just under the base border (+8; strips +9)
mod.LVL_RAISE = 10 -- hover/target/aggro-recolor border (strips +11: above base strips +9
-- and the dispel / Buff Manager border strips +10; ties threat
-- strips +11 but the raise container is created later so it
-- wins). MUST stay below ns.LVL_TEXT:
-- UpdateBorder creates strips lazily AFTER the text
-- carriers, so a tie with text puts the border on top.
mod.LVL_TEXT = 12 -- text band: name/health text, role icon, leader crown;
-- above every border incl. the raise, below the aura band
mod.LVL_AURA = 13 -- base level for every aura icon/bar (children at +1..+5)
mod.LVL_MARKER = 26 -- raid marker icon (always on top -- above the dispel
-- type icon band at +21..+25, which itself sits above
-- the aura band so it wins a corner shared with debuffs)

-------------------------------------------------------------------------------
--  Leader-icon host strata: keep the host on the button's own strata in the
--  text band (ns.LVL_AURA - 1 = ns.LVL_TEXT) so the crown clears every border
--  incl. the hover/target raise while auras still draw over it. Re-applied on
--  reload to recover from container SetFrameStrata cascade resets.
-------------------------------------------------------------------------------
function mod.ApplyLeaderStrata(widget)
    local hostFrame = widget:GetParent()
    if hostFrame then
        widget:SetFrameStrata(hostFrame:GetFrameStrata())
        widget:SetFrameLevel(hostFrame:GetFrameLevel() + (mod.LVL_AURA - 1))
    end
end

-------------------------------------------------------------------------------
--  CPU-attribution shell pool. The engine bills a handler's ENTIRE call tree to
--  the addon whose execution context CREATED the frame it entered through;
--  OnEnable setup runs under the parent's lifecycle dispatch, so a frame born
--  there bills the PARENT forever (see CludesUI_Ticker.lua). These are born
--  in this file's main chunk; event hosts adopt one via ns.TakeShell() instead
--  of CreateFrame("Frame"). Plain unnamed Frames, persistent hosts only: no
--  release. Sized for per-unit trackers (40 raid + party + boss + extra + pets)
--  plus standing watchers.
-------------------------------------------------------------------------------
do
    local pool = {}
    local num = 120
    for index = 1, num do
        pool[index] = CreateFrame("Frame")
    end
    mod.TakeShell = function()
        if num > 0 then
            local frame = pool[num]
            pool[num] = nil
            num = num - 1
            return frame
        end
        -- Pool exhausted (not expected): still works but bills the parent;
        -- bump the pool size if this ever happens.
        return CreateFrame("Frame")
    end
end

-- "Run once after combat" for one-shot combat-gated deferrals. The shell is taken
-- in the main chunk, so drained work bills RaidFrames. Keys are per purpose.
mod.CombatQueue = CludesUI.NewCombatQueue(mod.TakeShell())

-------------------------------------------------------------------------------
--  Locals & upvalues
-------------------------------------------------------------------------------
local Pix = nil -- set in OnEnable once parent is ready
local saved = nil
local floor = math.floor
local pairs = pairs
local ipairs = ipairs
local wipe = wipe
local type = type

local UnitClass = UnitClass
local UnitThreatSituation = UnitThreatSituation
local SUMMON_STATUS_PENDING = Enum.SummonStatus and Enum.SummonStatus.Pending or 1
local SUMMON_STATUS_ACCEPTED = Enum.SummonStatus and Enum.SummonStatus.Accepted or 2
local SUMMON_STATUS_DECLINED = Enum.SummonStatus and Enum.SummonStatus.Declined or 3
local IsInRaid = IsInRaid
local InCombatLockdown = InCombatLockdown
local GetNumGroupMembers = GetNumGroupMembers
local C_Timer = C_Timer
local issecretvalue = issecretvalue
-- WoW Forever: no number under 10,000 abbreviates (CludesUI_NumberFormat.lua).
local AbbreviateNumbers = (CludesUI.IS_FOREVER and CludesUI.ForeverAbbreviateNumbers) or AbbreviateNumbers
local CreateFrame = CreateFrame

-- Absorb shield textures (must match UnitFrames exactly)
local ABSORB_STYLE_TEX = {
    striped = "Interface\\AddOns\\CludesUI\\media\\textures\\shields\\striped-5.png",
    stripedReversed = "Interface\\AddOns\\CludesUI\\media\\textures\\shields\\striped-5-reversed.png",
    stripedThick = "Interface\\AddOns\\CludesUI\\media\\textures\\shields\\striped-thick.png",
    stripedThickR = "Interface\\AddOns\\CludesUI\\media\\textures\\shields\\striped-thick-r.png",
    clean = "Interface\\Buttons\\WHITE8X8",
    blizzard = "Interface\\AddOns\\CludesUI\\media\\textures\\shields\\blizzard.tga",
    healBlizzModern = "Interface\\AddOns\\CludesUI\\media\\textures\\shields\\louis-absorb.png",
    largeOutlinedStripes = "Interface\\AddOns\\CludesUI\\media\\textures\\shields\\large-habsorb-left.png",
    largeOutlinedStripesR = "Interface\\AddOns\\CludesUI\\media\\textures\\shields\\large-habsorb-right.png",
    largeStripes = "Interface\\AddOns\\CludesUI\\media\\textures\\shields\\large-absorb-left.png",
    largeStripesR = "Interface\\AddOns\\CludesUI\\media\\textures\\shields\\large-absorb-right.png",
    pixelsShield = "Interface\\AddOns\\CludesUI\\media\\textures\\shields\\pixels-shield.tga",
    pixelsShieldEdge = "Interface\\AddOns\\CludesUI\\media\\textures\\shields\\pixels-shield-edge.tga",
    pixelsShieldFill = "Interface\\AddOns\\CludesUI\\media\\textures\\shields\\pixels-shield-fill.tga",
}
local ABSORB_STYLE_ALPHA = {
    striped = 0.8,
    stripedReversed = 0.8,
    clean = 0.3,
    blizzard = 0.8,
}

-- Role icon definitions per style. _isTexture = true -> values are file paths
-- (SetTexture); otherwise atlas names (SetAtlas).
local ROLE_MEDIA = "Interface\\AddOns\\CludesUIRaidFrames\\Media\\"
local ROLE_ICON_STYLES = {
    modern = {
        _isTexture = true,
        TANK = ROLE_MEDIA .. "tank-modern.png",
        HEALER = ROLE_MEDIA .. "healer-modern.png",
        DAMAGER = ROLE_MEDIA .. "dps-modern.png",
    },
    modernCircle = {
        TANK = "UI-LFG-RoleIcon-Tank",
        HEALER = "UI-LFG-RoleIcon-Healer",
        DAMAGER = "UI-LFG-RoleIcon-DPS",
    },
    styled = {
        TANK = "UI-LFG-RoleIcon-Tank-Background",
        HEALER = "UI-LFG-RoleIcon-Healer-Background",
        DAMAGER = "UI-LFG-RoleIcon-DPS-Background",
    },
    classicCircle = {
        TANK = "UI-LFG-RoleIcon-Tank-Micro-GroupFinder",
        HEALER = "UI-LFG-RoleIcon-Healer-Micro-GroupFinder",
        DAMAGER = "UI-LFG-RoleIcon-DPS-Micro-GroupFinder",
    },
    classic = {
        TANK = "roleicon-tiny-tank",
        HEALER = "roleicon-tiny-healer",
        DAMAGER = "roleicon-tiny-dps",
    },
    blizzDefault = {
        TANK = "GM-icon-role-tank",
        HEALER = "GM-icon-role-healer",
        DAMAGER = "GM-icon-role-dps",
    },
    blizzLight = {
        _isTexture = true,
        TANK = ROLE_MEDIA .. "tank.png",
        HEALER = ROLE_MEDIA .. "healer.png",
        DAMAGER = ROLE_MEDIA .. "dps.png",
    },
    pixels = {
        _isTexture = true,
        TANK = ROLE_MEDIA .. "pixels-tank.tga",
        HEALER = ROLE_MEDIA .. "pixels-healer.tga",
        DAMAGER = ROLE_MEDIA .. "pixels-dps.tga",
    },
}
-- Read-only share with the options file's style preview (this file loads first).
mod.ROLE_ICON_STYLES = ROLE_ICON_STYLES

local function ApplyRoleIcon(texture, role, style)
    -- Caller supplies style from its own settings context (party proxy /
    -- preview override) so unsynced party roleIconStyle holds; raid profile only when omitted.
    style = style or (saved and saved.profile.roleIconStyle) or "modern"
    local map = ROLE_ICON_STYLES[style]
    if not map then
        return false
    end
    local iconTex = map[role]
    if not iconTex then
        return false
    end
    if map._isTexture then
        texture:SetTexture(iconTex)
        texture:SetTexCoord(0, 1, 0, 1)
    else
        texture:SetAtlas(iconTex)
    end
    return true
end

-- Text shares the icon's carrier and anchor, and is created only when enabled.
function mod.ApplyRoleText(iconTex, role, cfg)
    if not cfg.roleText then
        return
    end
    local textValue = iconTex._roleText
    if not textValue then
        textValue = iconTex:GetParent():CreateFontString(nil, "OVERLAY")
        iconTex._roleText = textValue
    end
    local colorKey = role == "TANK" and "roleTextTankColor"
        or role == "HEALER" and "roleTextHealerColor"
        or "roleTextDPSColor"
    local color = cfg[colorKey] or mod._internals.defaults.profile[colorKey]
    textValue:SetTextColor(color.r, color.g, color.b)
    CludesUI.ApplyModuleFont(textValue, nil, cfg.roleIconSize or 14, "raidFrames")
    local place = iconTex:GetPoint() or "CENTER"
    textValue:ClearAllPoints()
    textValue:SetPoint(place, iconTex, place, 0, 0)
    textValue:SetText(
        role == "TANK" and CludesUI.L("Tank")
            or role == "HEALER" and CludesUI.L("Healer")
            or CludesUI.L("DPS")
    )
    iconTex:Hide()
    textValue:Show()
end

-- Raid marker textures
local RAID_MARKER_TEXCOORDS = {
    [1] = { 0, 0.25, 0, 0.25 }, -- Star
    [2] = { 0.25, 0.5, 0, 0.25 }, -- Circle
    [3] = { 0.5, 0.75, 0, 0.25 }, -- Diamond
    [4] = { 0.75, 1, 0, 0.25 }, -- Triangle
    [5] = { 0, 0.25, 0.25, 0.5 }, -- Moon
    [6] = { 0.25, 0.5, 0.25, 0.5 }, -- Square
    [7] = { 0.5, 0.75, 0.25, 0.5 }, -- Cross
    [8] = { 0.75, 1, 0.25, 0.5 }, -- Skull
}

-- Dispel colors
local DISPEL_COLORS = {
    Magic = { r = 0.349, g = 0.475, b = 1.0 },
    Curse = { r = 0.636, g = 0.0, b = 0.64 },
    Disease = { r = 0.671, g = 0.384, b = 0.098 },
    Poison = { r = 0.0, g = 0.706, b = 0.286 },
    [""] = { r = 0.75, g = 0.15, b = 0.15 }, -- Bleed / physical (no dispelName)
}

-- Dispel type icon atlases
local DISPEL_ICON_ATLAS = {
    Magic = "RaidFrame-Icon-DebuffMagic",
    Curse = "RaidFrame-Icon-DebuffCurse",
    Disease = "RaidFrame-Icon-DebuffDisease",
    Poison = "RaidFrame-Icon-DebuffPoison",
    [""] = "RaidFrame-Icon-DebuffBleed",
}

-- Rez spells by class (for dead target range checking)
-- IsSpellInRange returns normal booleans, not secret values.
local REZ_SPELL_BY_CLASS = {
    DRUID = 20484, -- Rebirth
    PRIEST = 2006, -- Resurrection
    PALADIN = 461622, -- Intercession
    SHAMAN = 2008, -- Ancestral Spirit
    MONK = 115178, -- Resuscitate
    DEATHKNIGHT = 61999, -- Raise Ally
    WARLOCK = 20707, -- Soulstone
    EVOKER = 361227, -- Return
}
-- WoW Forever has no Intercession; Redemption rank 1 is the Paladin's rez there.
if CludesUI.IS_FOREVER then
    REZ_SPELL_BY_CLASS.PALADIN = 7328
end
local _, playerClassToken = UnitClass("player")
local playerRezSpell = REZ_SPELL_BY_CLASS[playerClassToken]

-- Classes that use IsSpellInRange instead of UnitInRange for living units.
-- These classes have shorter effective ranges that 43yd UnitInRange misrepresents.
local FRIENDLY_SPELL_BY_CLASS = {
    EVOKER = 361469, -- Living Flame (baseline all specs, unit-targeted friendly -> IsSpellInRange returns a real boolean; ~25yd, 30 talented). Emerald Blossom (355913) is a location/smart-heal whose IsSpellInRange can stay nil, which stranded Evoker frames at full alpha.
    ROGUE = 36554, -- Shadowstep (25yd)
}
local playerFriendlySpell = FRIENDLY_SPELL_BY_CLASS[playerClassToken]

-- Threat: active aggro only (states 2/3); white border in the hover style.
local THREAT_ACTIVE = { [2] = true, [3] = true }

-- Combat indicator media + class sprite coords (shared with the Unit Frames
-- combat icon assets).
mod._COMBAT_MEDIA = "Interface\\AddOns\\CludesUI\\media\\combat\\"
mod._COMBAT_CLASS_COORDS = CludesUI.CLASS_ICON_SPRITE_COORDS

-------------------------------------------------------------------------------
--  Default settings
-------------------------------------------------------------------------------
-- Level Text's default position: attached to the name on WoW Forever, None on
-- retail (the per-client default rule; every fallback below reads it).
mod.RF_LEVEL_DEFAULT = (CludesUI.IS_FOREVER == true) and "name" or "none"
local defaultSet = {
    profile = {
        -- Size & layout
        frameWidth = 125,
        frameHeight = 60,
        cellSpacing = -1,
        groupSpacing = -1,
        raidCompactMode = false,
        raidGridMode = false,
        partyCompactMode = false,
        groupGrowth = "RIGHT", -- "DOWN", "UP", "RIGHT", "LEFT", "DOWNRIGHT" (grid: ns._RF_GRID_ROWS per column)
        unitGrowth = "DOWN", -- any direction; same-axis as groupGrowth = one continuous line
        groupGrowthCentered = false, -- center the shown groups in the mover box along the group axis (not for DOWNRIGHT)
        sortMode = "ROLE", -- "INDEX" (by group) or "ROLE" (by assigned role)
        roleOrder = { "TANK", "HEALER", "DAMAGER" },
        prioritizeClass = false, -- sort by class within the main sort (raid)
        classOrder = nil, -- nil = all classes alphabetical by name
        showSelfFirst = true,
        showSelfLast = false,
        mergeGroups = false,
        customGroupOrder = false,
        visibleGroups = { true, true, true, true, true, true, false, false },
        hideEmptyGroups = true, -- collapse subgroups with no members (raid only, real frames)
        excludeHiddenGroupsFromSize = true, -- hidden Show Groups don't count toward the raid-size breakpoint
        mythicRaidHideGroups = false, -- Hide Groups 5-8 in Mythic Raid (on top of Show Groups)

        -- Visibility
        showWhenSolo = false,
        showWhenGroup = false,
        showWhenRaid = true,
        frameStrata = "LOW",

        -- Friendly Boss Frames (boss1-5 healable NPC frames; raid, plus party
        -- via the opt-in showInDungeons key -- absent = raid only, no default
        -- on purpose so existing users keep the raid-only behavior)
        friendlyBoss = {
            display = "never", -- "never" | "healers" | "always"
            position = "right", -- "left" | "right" | "free"
            freePos = { x = 100, y = 0 },
            freeHorizontal = false,
            healthColor = { r = 23 / 255, g = 172 / 255, b = 49 / 255 },
            extraWidth = 0, -- size offset on top of the raid frame size
            extraHeight = 0,
        },

        -- Extra Frames (duplicates of chosen raid members, raid only)
        extraFrames = {
            showTanks = false, -- auto-include the raid's tanks
            position = "right", -- "left" | "right" | "free"
            freePos = { x = 100, y = -120 },
            freeHorizontal = false,
            players = {}, -- manually added names (hotkey toggle)
            extraWidth = 0, -- size offset on top of the raid frame size
            extraHeight = 0,
            wrapAfter = 0, -- Free Move frames per row/column; 0 = single line
            -- growDirection / wrapDirection / freeRect: optional, no defaults.
            -- Unset, growth derives from freeHorizontal, wrap from the perpendicular
            -- default, anchoring from freePos. See XF.GrowInfo / XF.FreeAnchor.
        },

        -- Pet Frames (party and raid pets, beside the groups). Each tab reads the placement
        -- (position, freePos, freeRect) and extra size here until it sets its own party_/raid_
        -- key (PF.View).
        petFrames = {
            party = false,
            raid = false,
            position = "right", -- "left" | "right" | "free" | "owner" (Beside Owner, Party tab)
            freePos = { x = 100, y = -200 },
            healthColor = { r = 23 / 255, g = 172 / 255, b = 49 / 255 },
            extraWidth = 0, -- size offset on top of the party or raid frame size
            extraHeight = 0,
        },

        -- Healer Mana Text Display (Extras): one text row per group healer.
        healerMana = {
            mode = "none", -- "none" | "party" | "raid" | "both"
            textSize = 12,
            spacing = 2, -- vertical space between rows
            showNames = true, -- raid only; party shows the number alone
            classNames = true, -- class colored names
            align = "LEFT", -- "LEFT" | "CENTER" | "RIGHT"
            growth = "DOWN", -- "DOWN" | "UP" (row stacking direction)
            colorMode = "custom", -- "custom" | "power" (value text color)
            color = { r = 1, g = 1, b = 1 },
            -- unlockPos: saved by unlock mode (RF_HealerMana element)
        },

        -- Player Group Label (Extras); unset style keys follow the raid frames.
        playerGroup = {
            enabled = false,
            format = "number", -- "number" | "full"
            padding = 4,
            -- width/height: nil = content-sized; unlockPos: saved by unlock
            -- mode (RF_PlayerGroup element)
        },

        -- Position (saved by unlock mode)
        unlockPos = nil,

        -- Health bar
        healthBarTexture = "atrocity",
        healthBarOpacity = 100,
        textureBg = false, -- Textured Background (Health Bar Fill cog)
        healthColorMode = "class", -- "class", "dark", "classic", "custom", "customDynamic", "classReactive"
        customFillColor = { r = 37 / 255, g = 193 / 255, b = 29 / 255 },
        -- Custom Dynamic Colors: health-percent gradient stops; defaults match
        -- the Classic curve so switching from Classic looks identical at first.
        dynamicColor100 = { r = 0, g = 1, b = 0 }, -- full health
        dynamicColor50 = { r = 1, g = 1, b = 0 }, -- half health
        dynamicColor0 = { r = 1, g = 0, b = 0 }, -- empty health
        customBgColor = { r = 17 / 255, g = 17 / 255, b = 17 / 255 },
        bgClassColored = false,
        bgDarkness = 50,
        -- Fill axis: off = left-to-right, on = bottom-to-top. Party can hold its own (key is in the healthBar override section).
        healthVerticalFill = false,
        -- Invert health fill: when true the bar is full at low health and empty at high health.
        healthInvertFill = false,

        -- Power bar (on when any powerShowFor* role is true)
        showPowerBar = true,
        powerHeight = 4,
        powerBgDarkness = 40,
        powerBgColor = { r = 107 / 255, g = 107 / 255, b = 107 / 255 },
        powerBgPowerColored = false,
        powerBorderStyle = "cui", -- "cui", "divider", "border"
        powerBorderMatchFrame = false,
        powerBorderMatchColor = false,
        powerBorderSize = 1,
        powerBorderColor = { r = 0, g = 0, b = 0 },
        powerBorderAlpha = 1,
        powerShowForHealer = true,
        powerShowForTank = true,
        powerShowForDPS = false,
        -- Uniform Icon Anchoring: icons/text anchor as if no power bar existed, so per-role power bars never shift them.
        powerUniformAnchors = false,
        extendHealthBehindPower = false, -- health spans full frame; power bar overlays it

        -- Top Name Bar: reserves height from the frame TOP (as the power bar does from the bottom); suppresses the in-frame Name.
        topNameBarEnabled = false,
        topNameBarHeight = 20,
        topNameBarDivider = false,
        topNameBarDividerMatchColor = false,
        topNameBarBgColor = { r = 17 / 255, g = 17 / 255, b = 17 / 255 },
        topNameBarBgOpacity = 80,
        topNameBarTextSize = 11,
        topNameBarTextColorMode = "class", -- "class" or "custom"
        topNameBarTextColor = { r = 1, g = 1, b = 1 },
        topNameBarTextOffsetX = 0,
        topNameBarTextOffsetY = 0,
        topNameBarTextAlign = "center", -- "center", "left", "right"
        topNameBarBottom = false, -- Show on Bottom: the bar takes the frame's bottom edge

        -- Text
        nameSize = 10,
        nameMaxLength = 15, -- max characters shown for unit names (0 = off / no cap)
        nameColorMode = "custom", -- "class", "accent", "custom"
        nameCustomColor = { r = 1, g = 1, b = 1 },
        namePosition = "topleft", -- "topleft", "top", "topright", "left", "center", "right", "bottomleft", "bottom"
        nameOffsetX = 0,
        nameOffsetY = 0,
        -- Level Text: the unit's level in front of the name, or on its own spot in the name's colour
        -- (Health Text's host). None = nothing built.
        levelTextSize = 10,
        levelTextPosition = mod.RF_LEVEL_DEFAULT, -- "name" ("60 Name"), "nameDiv" ("60 | Name"), "none" or a 9-point spot
        levelTextOffsetX = 0,
        levelTextOffsetY = 0,
        healthTextMode = "none", -- "none", "percent", "number"
        healthTextColorMode = "custom", -- "class", "accent", "custom"
        healthTextCustomColor = { r = 1, g = 1, b = 1 },
        healthTextSize = 9,
        healthTextPosition = "center",
        healthTextOffsetX = 0,
        healthTextOffsetY = 0,
        -- Power Text (Health Text's controls, on the same health bar host): shown only where the power bar shows. None = nothing built.
        powerTextMode = "none", -- "none", "percent", "percentNoSign", "number", "numberPercent", "percentNumber"
        powerTextColorMode = "custom", -- "custom", "class", "accent", "power"
        powerTextCustomColor = { r = 1, g = 1, b = 1 },
        powerTextSize = 8,
        powerTextPosition = "bottom",
        powerTextOffsetX = 0,
        powerTextOffsetY = 0,
        -- Heal Absorb Text (1:1 with Health Text): amount in short/full format, hidden at zero. Red default = healer-UI convention.
        healAbsorbTextMode = "none", -- "none", "amount", "short"
        healAbsorbTextColorMode = "custom", -- "class", "accent", "custom"
        healAbsorbTextCustomColor = { r = 1, g = 0.3, b = 0.3 },
        healAbsorbTextSize = 9,
        healAbsorbTextPosition = "center",
        healAbsorbTextOffsetX = 0,
        healAbsorbTextOffsetY = 0,

        -- Border (unified style/size, recolored by state -- matches Unit Frames)
        borderSize = 1,
        borderColor = { r = 0, g = 0, b = 0 },
        borderAlpha = 1,
        borderTexture = "solid",
        borderBehind = false,
        cornerRadius = 0, -- rounded corners, 0 = off
        cornerMask = 15, -- the corners that round (bits: 1 TL, 2 TR, 4 BL, 8 BR)
        -- borderTextureOffset/OffsetY/ShiftX/ShiftY default via GetBorderDefaults

        -- Smooth bars
        smoothBars = true,
        smoothPowerBars = true,

        -- Absorb shields (must match UF options)
        absorbStyle = "striped", -- "none", "striped", "clean", "blizzard"
        absorbOpacity = 90,
        absorbColor = { r = 1, g = 1, b = 1 },
        -- Overshield = absorb exceeding empty health, backfilling over current health.
        -- Off: absorbs fill only the empty part (and on Default Blizz Frames the glow line stays pinned right).
        showOvershield = true,
        -- Blizzard Glow Line (absorbGlowLine) has NO default on purpose: unset follows the
        -- style (on for Default Blizz Frames only); a default would switch the line off for
        -- every profile already on that style.
        healAbsorbStyle = "clean",
        healAbsorbOpacity = 75,
        healAbsorbColor = { r = 0.8, g = 0.15, b = 0.15 },
        healPrediction = false,
        healPredOpacity = 75,
        healPredColor = { r = 102 / 255, g = 243 / 255, b = 102 / 255 },
        -- Absorb / heal absorb placement, independent per bar: "overlay" (over
        -- the health fill, default), "right" / "left" (from that frame edge).
        absorbEdgeMode = "overlay",
        healAbsorbEdgeMode = "overlay",
        -- Lift the heal-absorb overlay above the dispel gradient (off = below dispel).
        healAbsorbOverDispel = false,
        -- Black backing behind the heal-absorb texture (all styles); 0 = off.
        healAbsorbBgOpacity = 25,
        -- Reduced max-health overlay: always right-anchored, styled like Heal
        -- Absorb but with a dedicated "Max Health Stripes" texture, no placement option.
        maxHealthStyle = "maxHealthStripes",
        maxHealthColor = { r = 0.7, g = 0.1, b = 0.1 },
        maxHealthOpacity = 100,
        maxHealthBgOpacity = 100,
        -- Absorb Bar: solid bar above the frame, fills from the right edge
        absorbBarEnabled = false,
        absorbBarHeight = 4,
        absorbBarColor = { r = 1, g = 1, b = 1 },
        -- Fill direction for the vertical (Right/Left Edge) positions.
        absorbBarGrowDir = "up",
        -- Heal Absorb Bar: separate strip showing the heal-absorb amount
        healAbsorbBarPosition = "none",
        healAbsorbBarHeight = 4,
        healAbsorbBarColor = { r = 200 / 255, g = 29 / 255, b = 29 / 255 },
        healAbsorbBarGrowDir = "up",

        -- Indicators
        roleIconStyle = "modern", -- none/modern/modernCircle/styled/classicCircle/classic/blizzDefault/blizzLight/pixels
        roleText = false,
        roleTextTankColor = { r = 59 / 255, g = 130 / 255, b = 246 / 255 },
        roleTextHealerColor = { r = 32 / 255, g = 201 / 255, b = 151 / 255 },
        roleTextDPSColor = { r = 240 / 255, g = 100 / 255, b = 54 / 255 },
        roleIconSize = 13,
        roleIconPosition = "bottomleft", -- topleft/top/topright/left/center/right/bottomleft/bottom/bottomright
        roleIconOffsetX = 0,
        roleIconOffsetY = 0,
        roleIconHideInCombat = false,
        roleIconOnNameBar = false, -- Attach Role Icons: on the Top Name Bar, with its own position/offsets
        roleNameBarPosition = "left",
        roleNameBarOffsetX = 0,
        roleNameBarOffsetY = 0,
        roleIconBehindBorder = false, -- drop the carrier below the normal border so borders draw over the icon
        showRoleForTank = true,
        showRoleForHealer = true,
        showRoleForDPS = false,
        showRaidMarker = true,
        raidMarkerSize = 16,
        raidMarkerPosition = "center", -- "topleft", "top", "topright", "left", "center", "right", "bottomleft", "bottom"
        raidMarkerOffsetX = 0,
        raidMarkerOffsetY = 0,
        -- Ping marker: the mark a group member's ping puts on the pinged unit's frame (Blizzard art, 30 = native size)
        showPingMarker = true,
        pingMarkerSize = 30,
        pingMarkerPosition = "center",
        pingMarkerOffsetX = 0,
        pingMarkerOffsetY = 0,
        -- WoW Forever: Missing Buffs (CUI_RaidFrames_ForeverMissingBuffs.lua).
        -- Forever-only defaults, absent on every other client.
        showMissingBuffs = (CludesUI.IS_FOREVER == true) and true or nil,
        missingBuffsSize = (CludesUI.IS_FOREVER == true) and 22 or nil,
        missingBuffsPosition = (CludesUI.IS_FOREVER == true) and "top" or nil,
        missingBuffsOffsetX = (CludesUI.IS_FOREVER == true) and 0 or nil,
        missingBuffsOffsetY = (CludesUI.IS_FOREVER == true) and 0 or nil,
        -- Its icons' glow (shared prefix schema; 2 = Action Button Glow).
        missingBuffsGlowType = (CludesUI.IS_FOREVER == true) and 2 or nil,
        missingBuffsGlowColorMode = (CludesUI.IS_FOREVER == true) and "default" or nil,
        showReadyCheck = true,
        showSummonPending = true,
        showIncomingRez = true,
        readyCheckSize = 20,
        readyCheckPosition = "center", -- "topleft", "top", "topright", "left", "center", "right", "bottomleft", "bottom"
        readyCheckOffsetX = 0,
        readyCheckOffsetY = 0,
        threatBorderSize = 2, -- aggro warning border thickness; 0 = off
        threatCustomBorder = false, -- Color Custom Borders: the frame border recolored for aggro instead of the inner border
        showLeaderIcon = false,
        showLeaderIconInCombat = true, -- "Show In Combat" cog; off = hide in combat
        leaderIconPosition = "top",
        leaderIconSize = 14,
        leaderIconOffsetX = 0,
        leaderIconOffsetY = 0,
        -- Combat icon: shown on members who are in combat (M+ skip awareness)
        showCombatIndicator = false,
        combatIndicatorStyle = "standard", -- standard/class/combat0..5 (none handled by showCombatIndicator)
        combatIndicatorColor = "custom", -- custom/classcolor (standard/class styles only)
        combatIndicatorCustomColor = { r = 1, g = 0.2, b = 0.2 },
        combatIndicatorSize = 16,
        combatIndicatorPosition = "right",
        combatIndicatorOffsetX = 0,
        combatIndicatorOffsetY = 0,
        statusTextPosition = "center",
        statusTextOffsetX = 0,
        statusTextOffsetY = 0,
        statusTextSize = 12,
        statusTextColor = { r = 1, g = 1, b = 1 },
        statusShowAFK = false,
        -- Group numbers (raid only). Size/color shared with the preview; the toggle gates only real frames (preview always shows them).
        showGroupNumbers = false,
        groupNumberSize = 10,
        groupNumberColor = { r = 1, g = 1, b = 1, a = 0.75 },
        groupNumberOffsetX = 0,
        groupNumberOffsetY = 0,
        hoverBorderEnabled = true,
        hoverBorderSize = 1,
        hoverBorderColor = { r = 1, g = 1, b = 1 },
        hoverBorderAlpha = 1,
        targetBorderEnabled = true,
        targetBorderSize = 1,
        targetBorderColor = { r = 1, g = 1, b = 1 },
        targetBorderAlpha = 1,

        -- Dispels
        dispelBorderSize = 0,
        dispelOverlay = "fill", -- "none", "fill", "full", "gradient", "gradient_sharp", "gradient_reverse"
        dispelOverlayOpacity = 100,
        dispelShowAll = true, -- true = highlight any dispellable debuff; false = only player-dispellable
        dispelOverlayPosition = 0, -- 0=Top, 1=Bottom, 2=Left (aura-organization-type for private aura dispel container)
        showDispelIcons = false,
        dispelIconPosition = "right",
        dispelIconOffsetX = 0,
        dispelIconOffsetY = 0,
        dispelIconSize = 16,
        -- 12.1 dispel ring thickness in physical pixels (-1 follows the icon's own
        -- Border, 0 hides it). Stored explicitly rather than left to the `or 2`
        -- read fallback: ReloadPartyFrames temp-swaps party values onto db.profile
        -- and restores from a table keyed by the raid value, so a key with no
        -- default is absent from that table and its party value would stick.
        dispelIconBorderSize = 2,
        dispelCustomBorder = false, -- Color Custom Borders: the frame border copied in the dispel type color
        dispelClockBorder = false, -- animated clock-style dispel border (erases clockwise) on dispellable debuff icons
        dispelClockExtraBorder = 0, -- extra physical pixels added to the clock border thickness (on top of debuffBorderSize)
        dispellableDebuffLocation = "same", -- "same" = use the main debuff layout; else a separate anchor for dispellable debuffs
        dispellableDebuffGrowDirection = "RIGHT",
        dispellableDebuffOffsetX = 0,
        dispellableDebuffOffsetY = 0,
        dispellableDebuffSize = 0, -- icon size at the separate anchor (0 = match Debuff Size)
        -- Per-dispel-type colors (defaults mirror DISPEL_COLORS). "Bleed" is the
        -- no-dispelName/physical type (stored under the "" key in DISPEL_COLORS).
        dispelColorMagic = { r = 0.349, g = 0.475, b = 1.0 },
        dispelColorCurse = { r = 0.636, g = 0.0, b = 0.64 },
        dispelColorDisease = { r = 0.671, g = 0.384, b = 0.098 },
        dispelColorPoison = { r = 0.0, g = 0.706, b = 0.286 },
        dispelColorBleed = { r = 0.75, g = 0.15, b = 0.15 },
        -- Health background status tint (Status Colors swatch in Extras).
        statusColorOffline = { r = 0x66 / 255, g = 0x66 / 255, b = 0x66 / 255 }, -- #666666
        statusColorDead = { r = 0x24 / 255, g = 0x17 / 255, b = 0x17 / 255 }, -- #241717

        -- Buff Manager (indicator-centric model)
        bmIndicators = {}, -- { [specKey] = { indicator1, indicator2, ... } }

        -- Debuffs
        debuffFilter = "all", -- "none", "all", "raid", "dispellable"
        hideLustDebuff = true,
        -- Defensives & Externals
        showDefensives = true,
        showExternals = true,
        defPosition = "center",
        defOffsetX = 0,
        defOffsetY = 0,
        defGrowDirection = "CENTER",
        defSize = 22,
        defBorderSize = 1,
        defBorderColor = { r = 0, g = 0, b = 0 },
        defSpacing = 1,
        defShowSwipe = true,
        defShowDurText = false,
        defDurTextColor = { r = 1, g = 1, b = 1 },
        defDurTextSize = 8,
        defDurTextOffsetX = 0,
        defDurTextOffsetY = 0,

        -- Buff Manager "Simple Setup" (retired display): kept only as legacy
        -- input for the v2 conversion and spec-override banking; nothing renders it.
        bmSimple = {
            showBuffs = true,
            ownOnly = true,
            maxBuffs = 8,
            iconsPerRow = 4,
            position = "topright",
            offsetX = 0,
            offsetY = 0,
            growDirection = "LEFT", -- sensible default for the Top Right anchor
            size = 18,
            spacing = 1,
            borderSize = 1,
            borderColor = { r = 0, g = 0, b = 0 },
            showSwipe = true,
            showDurText = false,
            durTextColor = { r = 1, g = 1, b = 1 },
            durTextSize = 8,
            durTextOffsetX = 0,
            durTextOffsetY = 0,
            showStacks = true,
            stacksTextColor = { r = 1, g = 1, b = 1 },
            stacksTextSize = 8,
            stacksOffsetX = -1,
            stacksOffsetY = 2,
        },

        buffHideTooltips = true,
        debuffSize = 18,
        debuffCap = 3,
        debuffHideTooltips = true,
        debuffPosition = "bottomright",
        debuffOffsetX = 0,
        debuffOffsetY = 0,
        debuffGrowDirection = "LEFT",
        debuffPerRow = 5, -- icons per row (1 = single line, no wrap; >= 2 wraps)
        debuffWrapDirection = "UP",
        debuffSpacing = 1,
        debuffBorderSize = 1,
        debuffBorderColor = { r = 0, g = 0, b = 0 },
        debuffShowStacks = true,
        debuffStacksTextColor = { r = 1, g = 1, b = 1 },
        debuffStacksTextSize = 8,
        debuffStacksOffsetX = 0,
        debuffStacksOffsetY = 0,
        debuffShowSwipe = true,
        debuffShowDurText = false,
        debuffDurTextColor = { r = 1, g = 1, b = 1 },
        debuffDurTextSize = 8,
        debuffDurTextOffsetX = 0,
        debuffDurTextOffsetY = 0,

        -- Range & misc
        oorAlpha = 0.4,
        -- showTooltip is the on/off fallback the "Show Raid & Party Frames Tooltip"
        -- dropdown derives from (ns._ResolveTooltipMode); picking an option writes
        -- tooltipMode = always|outOfCombat|outOfBossCombat|never. Raid/party only.
        showTooltip = true,
        freeRightClickCamera = false, -- right-click + drag over a raid/party frame turns the camera (mouselook)

        -- Preview mode: "real", "overlay", "none"
        previewMode = "overlay",

        -- Raid size overrides: { [10] = { width=X, height=Y }, ... }
        raidSizeOverrides = nil,
        autoResizeIndicators = false,
        -- Tracked Buffs (Buff Manager) auto-resize ("Auto Resize Icons" dropdown); nil = on.
        autoResizeTrackedBuffs = true,

        -- Party frame overrides (sparse -- falls back to raid settings)
        partyFrameWidth = 125,
        partyFrameHeight = 60,
        partyShowWhenSolo = false,
        partySmallRaid = false, -- raid under 10 players: group 1 as party frames, others hidden
        partyShowTargets = false, -- opt-in secure target buttons beside party frames
        -- Party target frames (Party tab PARTY TARGETS section): party only, one value under
        -- every style. partyTargetPosition nil = beside stacked frames, below horizontal ones.
        partyTargetIncludeSelf = false, -- your own target beside your frame too
        partyTargetHealthColorMode = "class", -- "class" | "dark" | "classic" | "custom"
        partyTargetCustomFillColor = { r = 37 / 255, g = 193 / 255, b = 29 / 255 },
        partyTargetBgClassColored = false,
        partyTargetCustomBgColor = { r = 17 / 255, g = 17 / 255, b = 17 / 255 },
        partyTargetBgDarkness = 50,
        partyTargetOffsetX = 0, -- -100..100
        partyTargetOffsetY = 0,
        partyTargetWidth = 70,
        partyTargetHeight = 33,
        partyCenterWhenSolo = false, -- center the lone player frame in the container when solo
        partySyncSections = nil, -- nil = all synced; { healthBar=false } = healthBar custom
        partySortMode = "ROLE",
        partyPrioritizeClass = false, -- sort by class within the main sort (party only)
        partyClassOrder = nil, -- nil = all 13 classes alphabetical by name
        partyShowSelfFirst = true,
        partySelfLast = false,
        partyHorizontal = false,
        partyFlipGrowth = false, -- false=default growth, true=DOWN->UP / RIGHT->LEFT flip, "centered"=stack centered in the 5-slot container
        partyHideSelf = false,
        partyUnlockPos = nil,
        -- Party mirror of autoResizeTrackedBuffs ("Auto Resize Icons", Party tab); nil = on.
        partyAutoResizeTrackedBuffs = true,
        -- Party portrait (Party tab PORTRAIT section, CUI_RaidFrames_Portrait.lua):
        -- party only, one value under every style. Off by default.
        partyPortraitStyle = "none", -- "none" | "attached" | "detached"
        partyPortraitMode = "2d", -- Art Style: "2d" | "3d" | "class"
        partyPortraitClassStyle = "modern", -- class art set
        partyPortraitSide = "left", -- left|right|top|insideleft|insideright|insidecenter
        partyPortraitSize = 0, -- -50..100 (detached / inside)
        partyPortraitX = 0, -- -100..100 (detached)
        partyPortraitY = 0,
        partyPortraitShape = "portrait", -- none|portrait|circle|square|csquare|diamond|hexagon|shield
        partyPortraitBorderColor = { r = 0, g = 0, b = 0 },
        partyPortraitBorderClassColor = true,
        partyPortraitBorderOpacity = 100, -- 0..100
        partyPortraitBorderSize = 7, -- 1..7
        partyPortraitArtScale = 100, -- 2D Zoom 50..100
        partyPortrait3dZoom = 100, -- 3D Zoom 100..500 (above 300: whole character)
        partyPortraitCharScale = 100, -- Character Size % 50..200 (Inside, 3D)
    },
}

-------------------------------------------------------------------------------
--  State tables
-------------------------------------------------------------------------------
local allButtons = {} -- flat list of all created buttons
local unitToButton = {} -- unitToken -> button map (rebuilt on roster change)
mod._xfUnitToButton = {} -- unitToken -> Extra Frames duplicate (XF.CAP-bounded;
-- owned by XF_Apply, never by the rebuild paths)
local separatedHdrs = {} -- [1..8] group headers
local containerFrame = nil -- top-level positioning frame
mod._flatButtons = {} -- buttons owned by the flat (merged) header
mod._flatHeader = nil -- single header for merge-groups mode
mod._flatGfStr = nil -- merged groupFilter LayoutGroups would write (Self Position fallback)
local eventFrame = CreateFrame("Frame")
local unitTrackers = {} -- [unitToken] = tracker frame
local inCombat = false

-------------------------------------------------------------------------------
--  Tooltip mode resolver. tooltipMode = always | outOfCombat | outOfBossCombat
--  | never; governs ONLY raid/party frame tooltips (gated in their own OnEnter,
--  no global hook). Unset derives: showTooltip=false -> never; global "show in
--  combat" -> always; else outOfCombat. `s` = a scaled raid/party/extra proxy
--  or db.profile. On ns so OnEnter can reach it.
-------------------------------------------------------------------------------
mod._ResolveTooltipMode = function(cfg)
    if not cfg then
        return "outOfCombat"
    end
    local m = cfg.tooltipMode
    if m ~= nil then
        return m
    end
    if cfg.showTooltip == false then
        return "never"
    end
    if CludesUIDB and CludesUIDB.showUnitTooltipsInCombat then
        return "always"
    end
    return "outOfCombat"
end

-- Whether the frame's UNIT tooltip is allowed now (mode + combat state). Unit
-- tip only: aura-icon tips obey their own section's "Hide Tooltips" toggle.
function mod.RaidFrameTooltipAllowed(btnFrame)
    local fd = btnFrame and mod.GetFFD and mod.GetFFD(btnFrame)
    local s = (
        fd
        and (
            fd._isParty and mod._scaledPartyProxy
            or (fd._isExtra and mod._scaledExtraProxy)
            or mod._scaledProfile
        )
    ) or mod._scaledProfile
    -- The Blizz UI Enhanced peek modifier lifts the mode so a hidden tip can still be read on hover, matching the global tooltips.
    if CludesUI._tooltipPeekHeld and CludesUI._tooltipPeekHeld() then
        return true
    end
    local ttMode = mod._ResolveTooltipMode(s)
    if ttMode == "never" then
        return false
    end
    if ttMode == "outOfCombat" and inCombat then
        return false
    end
    if ttMode == "outOfBossCombat" and mod._inBossCombat then
        return false
    end
    return true
end

-------------------------------------------------------------------------------
--  Suppress Blizzard raid frames (zero CPU when ours are active). Raid
--  container unconditional here; party is conditional, from UpdateVisibility.
-------------------------------------------------------------------------------
mod._blizzHiddenParent = CreateFrame("Frame", nil, UIParent)
mod._blizzHiddenParent:SetAllPoints()
mod._blizzHiddenParent:Hide()

do
    local hookedFrames = {}
    local looseFrames = {}

    local watcher = mod.TakeShell()
    watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    watcher:SetScript("OnEvent", function()
        for widget in next, looseFrames do
            widget:SetParent(mod._blizzHiddenParent)
        end
        wipe(looseFrames)
    end)

    local function resetParent(self, hostFrame)
        if hostFrame ~= mod._blizzHiddenParent then
            if InCombatLockdown() and self:IsProtected() then
                looseFrames[self] = true
            else
                self:SetParent(mod._blizzHiddenParent)
            end
        end
    end

    local function handleFrame(widget, doNotReparent)
        if not widget then
            return
        end
        widget:UnregisterAllEvents()
        CludesUI.HideFrame(widget)
        if not doNotReparent then
            widget:SetParent(mod._blizzHiddenParent)
            if not hookedFrames[widget] then
                hooksecurefunc(widget, "SetParent", resetParent)
                hookedFrames[widget] = true
            end
        end
        local health = widget.healthBar
            or widget.healthbar
            or widget.HealthBar
            or (widget.HealthBarsContainer and widget.HealthBarsContainer.healthBar)
        if health then
            health:UnregisterAllEvents()
        end
        local power = widget.manabar or widget.ManaBar
        if power then
            power:UnregisterAllEvents()
        end
        local castbar = widget.castBar or widget.spellbar or widget.CastingBarFrame
        if castbar then
            castbar:UnregisterAllEvents()
        end
        local altpower = widget.powerBarAlt or widget.PowerBarAlt
        if altpower then
            altpower:UnregisterAllEvents()
        end
        local buffs = widget.BuffFrame or widget.AurasFrame
        if buffs then
            buffs:UnregisterAllEvents()
        end
        local debuffs = widget.DebuffFrame
        if debuffs then
            debuffs:UnregisterAllEvents()
        end
    end

    -- Suppress the Edit Mode selection overlay (mover box). Hide/reparent is NOT
    -- enough (Edit Mode force-shows registered systems): scale the system frame
    -- down so its Selection child renders invisibly small, plus alpha 0. SetScale
    -- is combat-blocked but Edit Mode is always entered OOC, so skip it when
    -- locked. pcall-wrapped: protected Blizzard frames. The scale goes through
    -- the saved C method (Edit Mode's override would flag its anchor sweep and
    -- snap state under our taint), keeping the frame's spot: Edit Mode's save
    -- recomputes a moved party or raid frame's anchor from its geometry times
    -- its scale.
    local function hideEditModeOverlay(widget)
        if not widget then
            return
        end
        pcall(function()
            widget:SetAlpha(0)
            if not InCombatLockdown() then
                CludesUI.SetFrameScale(widget, 0.001, true)
            end
            -- Per-frame Blizzard selection textures. No-op if absent.
            if widget.selectionHighlight and widget.selectionHighlight.SetShown then
                widget.selectionHighlight:SetShown(false)
            end
            if widget.selectionIndicator and widget.selectionIndicator.SetShown then
                widget.selectionIndicator:SetShown(false)
            end
        end)
    end

    -- CONTAINER always suppressed (we replace the raid unit frames). The MANAGER
    -- (left sidebar: ready check / markers) is deliberately NOT touched; the
    -- shared "Hide Blizzard Party Panel" toggle (CludesUI_BlizzardParty.lua)
    -- owns it. OnShow re-asserts the scale-down: Edit Mode re-shows the system
    -- (and may reset its scale) on every entry.
    if CompactRaidFrameContainer then
        handleFrame(CompactRaidFrameContainer)
        CompactRaidFrameContainer:HookScript("OnShow", function(self)
            -- A protected frame hides only out of combat; in combat
            -- resetParent above takes it back under the hidden parent (a
            -- protected one when combat ends).
            if not InCombatLockdown() then
                CludesUI.HideFrame(self)
            end
            hideEditModeOverlay(self)
        end)
    end

    -- Callable from UpdateVisibility when "Show When: In a Group" is active.
    -- early (OnEnable, login window): takes PartyFrame itself down so Blizzard's
    -- party frames can never stand in for ours (a group joined in combat), without
    -- latching -- the member frames, which Edit Mode can build later (raid-style),
    -- are handled the first time our party frames show out of combat.
    mod._SuppressBlizzParty = function(early)
        if mod._blizzPartySuppressed then
            return
        end
        if not early then
            mod._blizzPartySuppressed = true
        end
        if PartyFrame then
            handleFrame(PartyFrame)
            if early then
                return
            end
            if PartyFrame.PartyMemberFramePool then
                for mf in PartyFrame.PartyMemberFramePool:EnumerateActive() do
                    handleFrame(mf, true)
                end
            end
            local MEMBERS_PER_GROUP = _G.MEMBERS_PER_RAID_GROUP or 5
            for index = 1, MEMBERS_PER_GROUP do
                handleFrame(_G["CompactPartyFrameMember" .. index])
            end
            -- Party Edit Mode overlay: only while we own the party frames (from
            -- UpdateVisibility), so untouched Blizzard party frames keep movers.
            -- PartyFrame = standard; CompactPartyFrame = raid-style (may be absent).
            hideEditModeOverlay(PartyFrame)
            hideEditModeOverlay(_G["CompactPartyFrame"])
        end
    end

    -- Edit Mode re-shows registered systems (and can reset scale) on every entry,
    -- so one call at load is not enough: re-apply on PLAYER_ENTERING_WORLD,
    -- EDIT_MODE_LAYOUTS_UPDATED, EditModeManagerFrame show/hide, and the
    -- CompactRaidFrameManager_UpdateShown global.
    local function hideEditModeOverlays()
        -- Manager omitted on purpose: the shared "Hide Blizzard Party Panel" toggle owns it.
        hideEditModeOverlay(CompactRaidFrameContainer)
        -- Party overlays unconditional: Blizzard's party frame is empty/hidden when solo, so no group gate is needed.
        hideEditModeOverlay(PartyFrame)
        hideEditModeOverlay(_G["CompactPartyFrame"])
    end
    mod._ApplyEditModeOverlaySuppression = hideEditModeOverlays

    local editModeWatcher = mod.TakeShell()
    editModeWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
    editModeWatcher:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
    editModeWatcher:SetScript("OnEvent", function()
        C_Timer.After(0, hideEditModeOverlays)
    end)

    -- Edit Mode and the raid manager re-show the container through this global;
    -- re-assert our suppression whenever it fires.
    if type(_G.CompactRaidFrameManager_UpdateShown) == "function" then
        hooksecurefunc("CompactRaidFrameManager_UpdateShown", function()
            C_Timer.After(0, hideEditModeOverlays)
        end)
    end

    local function hookEditModeManager()
        if not EditModeManagerFrame then
            return
        end
        local fd = CludesUI._GetFFD(EditModeManagerFrame)
        if fd.rfOverlayHooked then
            return
        end
        fd.rfOverlayHooked = true
        -- OnShow = Edit Mode entered (overlay appears); Hide = Edit Mode closed.
        EditModeManagerFrame:HookScript("OnShow", function()
            C_Timer.After(0, hideEditModeOverlays)
        end)
        hooksecurefunc(EditModeManagerFrame, "Hide", function()
            C_Timer.After(0, hideEditModeOverlays)
        end)
    end
    if EditModeManagerFrame then
        hookEditModeManager()
    elseif EventUtil and EventUtil.ContinueOnAddOnLoaded then
        EventUtil.ContinueOnAddOnLoaded("Blizzard_EditMode", hookEditModeManager)
    end
end

-- FFD: external weak-keyed lookup for state on header-managed buttons
-- (SecureGroupHeader buttons are Blizzard-owned, never write custom keys)
local FFD, GetFFD = CludesUI.NewFrameData()

-------------------------------------------------------------------------------
--  Physical pixel snapping. PP.Scale uses PanelPP.mult, which can be 1 even
--  when the frame's effective scale is not 1.0; this snaps to the container's
--  real physical pixel grid via CludesUI.PP.perfect (real PP, not PanelPP).
-------------------------------------------------------------------------------
local function PixelSnap(value)
    if value == 0 then
        return 0
    end
    local realPP = CludesUI and CludesUI.PP
    local perfect = realPP and realPP.perfect
    if not perfect then
        return value
    end
    local es = containerFrame and containerFrame:GetEffectiveScale()
        or (UIParent and UIParent:GetEffectiveScale() or 1)
    local onePixel = perfect / es
    -- Epsilon-guarded round (matches PP.SnapForES): the CENTER->TOPLEFT
    -- derivation puts odd-footprint edges exactly on half-pixel boundaries,
    -- where uiScale float dust otherwise decides the direction per reload.
    return floor(value / onePixel + 0.5 + 0.001) * onePixel
end

-------------------------------------------------------------------------------
--  Font helper. The frames' texts show other players' names, so they take the
--  module font as a font family: the font draws the letters it has and the
--  client's own faces draw Cyrillic, Korean and Chinese. A plain SetFont would
--  pin a string's face for good, so every font write to these strings goes
--  through here.
-------------------------------------------------------------------------------
local function ApplyFont(fontStr, size)
    CludesUI.ApplyModuleFontFamily(fontStr, nil, size, "raidFrames")
end

-------------------------------------------------------------------------------
--  Health bar texture helpers
-------------------------------------------------------------------------------
local healthBarTextures = {}
local healthBarTextureNames = {}
local healthBarTextureOrder = {}

local function InitHealthBarTextures()
    -- Seed from the shared catalogue INTO the existing file-scope tables
    -- (their identity is load-bearing: resolver closures capture them).
    local t, num, o = CludesUI.BuildBarTextureTables(true)
    for key, val in pairs(t) do
        healthBarTextures[key] = val
    end
    for key, val in pairs(num) do
        healthBarTextureNames[key] = val
    end
    for index, key in ipairs(o) do
        healthBarTextureOrder[index] = key
    end
    -- RF-only divergence: "none" is a real solid texture here, not nil.
    healthBarTextures["none"] = "Interface\\Buttons\\WHITE8X8"
    -- The stock raid fills, as our own keys on the game files (the stock
    -- styles' first-visit defaults; no SharedMedia needed): the 12.1 flat
    -- fill (Blizzard Style) and the pre-10.0 gradient "Blizzard Raid Bar"
    -- (Classic WoW UI). The shared-media copy of the latter dedupes against
    -- this entry (same name and path).
    healthBarTextures.blizzardRaidModern = "Interface\\RaidFrame\\RaidFrameHPFill"
    healthBarTextureNames.blizzardRaidModern = "Default Blizz Frames"
    healthBarTextures.blizzardRaid = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill"
    healthBarTextureNames.blizzardRaid = "Blizzard Raid Bar"
    table.insert(healthBarTextureOrder, 2, "blizzardRaid")
    table.insert(healthBarTextureOrder, 2, "blizzardRaidModern")

    -- Append SharedMedia textures after built-ins
    CludesUI.AppendSharedMediaTextures(healthBarTextureNames, healthBarTextureOrder, nil, healthBarTextures)
end

-- s: the settings to read (the profile when nil).
local function ResolveHealthTexture(s)
    local key = (s or saved.profile).healthBarTexture or "atrocity"
    return CludesUI.ResolveTexturePath(
        healthBarTextures,
        key,
        healthBarTextures["atrocity"] or "Interface\\Buttons\\WHITE8X8"
    )
end

-- Expose for options panel
mod.healthBarTextures = healthBarTextures
mod.healthBarTextureNames = healthBarTextureNames
mod.healthBarTextureOrder = healthBarTextureOrder

-- Style page choice (Blizzard Style / Classic WoW UI, CUI_RaidFrames_Stock.lua):
-- "cui" | "blizzard" | "classic", read from the profile flags once and
-- latched for the session (every switch reloads). The runtime reads only
-- this, never the flags.
function mod.RF_Style()
    local val = mod._rfStyle
    if val then
        return val
    end
    local profile = saved and saved.profile
    if not profile then
        return "cui"
    end
    val = (profile.useClassicStyle and "classic") or (profile.useBlizzardStyle and "blizzard") or "cui"
    mod._rfStyle = val
    return val
end
function mod.RF_Stock()
    return mod.RF_Style() ~= "cui"
end
function mod.RF_Classic()
    return mod.RF_Style() == "classic"
end
-- Party page "Frame Style" under a stock style: the style key while the
-- party wears the stock portrait party frame ("Party Frames"), else false.
-- Latched like RF_Style (the choice reloads); the runtime reads only this.
-- The memo test is ~= nil: false is a real latched value.
function mod.RF_PartyKit()
    local val = mod._rfPartyKit
    if val ~= nil then
        return val
    end
    local profile = saved and saved.profile
    if not profile then
        return false
    end
    local st = mod.RF_Style()
    val = (st ~= "cui" and profile.partyFrameStyle == "party") and st or false
    mod._rfPartyKit = val
    return val
end
-- Settings the Party Frames layout replaces (its rows are hidden on the
-- Party page): the party settings view reads them neutral while it is on
-- (with the kit's debuff row: ns.RF_KitViewKeys, CUI_RaidFrames_Stock.lua).
mod.RF_KIT_NEUTRAL = {
    healthVerticalFill = false,
    healthInvertFill = false,
    topNameBarEnabled = false,
    powerUniformAnchors = false,
    extendHealthBehindPower = false,
}
-- The CludesUI border's effective size (0 under a stock style, whose edge
-- replaces it).
function mod.RF_EffBorderSize(cfg)
    if mod.RF_Stock() then
        return 0
    end
    return (cfg and cfg.borderSize) or 1
end
-- A custom border the Color Custom Borders options can recolor (Threat Borders
-- and Dispel Border cogs): a Border Style other than Solid with a size, under
-- the CludesUI style. Read from the saved keys, like the options gate.
function mod.RF_CustomBorderOn(cfg)
    local texture = cfg and cfg.borderTexture
    if texture == nil or texture == "" or texture == "solid" then
        return false
    end
    return mod.RF_EffBorderSize(cfg) > 0
end

-- Threat highlight (aggro: status 2-3; Threat Borders size 0 = off): the red
-- CludesUI border, or under a stock style the stock aggro rim. Color Custom
-- Borders (threatCustomBorder, over a custom border only) recolors the frame's
-- own border instead (ApplyBorderColor, below hover/target): no inner border is
-- drawn and the slider size does not gate it. The border repaints only when the
-- aggro state flips; d is the FFD table, never the Blizzard button.
function mod.RF_PaintThreat(skinData, cfg, unitToken)
    local tf = skinData.threatFrame
    if not tf then
        return
    end
    local bs = cfg.threatBorderSize or 0
    local compact = mod.RF_ButtonCompact(skinData, cfg)
    local rc = not compact and cfg.threatCustomBorder == true and mod.RF_CustomBorderOn(cfg)
    local status
    if bs > 0 or rc then
        status = UnitThreatSituation(unitToken)
        -- One group unit token reads plain (documented); a secret status still
        -- reads as no aggro rather than being indexed or compared.
        if issecretvalue(status) then
            status = nil
        end
    end
    local on = status and THREAT_ACTIVE[status] and Pix and true or false
    if skinData.stockHl then
        tf:Hide()
        mod.RF_StockAggro(skinData, on and status or nil)
        return
    end
    local agg = (rc and on) or nil
    if skinData._aggroBdr ~= agg then
        skinData._aggroBdr = agg
        if skinData.ApplyBorderColor then
            skinData.ApplyBorderColor()
        end
    end
    if on and not rc then
        Pix.UpdateBorder(tf, bs, 1, 0, 0, 1)
        tf:Show()
    else
        tf:Hide()
    end
end

-- Vertical health fill: SetOrientation drives the fill AXIS. Raid and party
-- resolve through the caller's settings table (party gets its own when the
-- Health Bar section is unsynced).
mod.RF_IsVerticalFill = function(s)
    return (s or saved.profile).healthVerticalFill and true or false
end

-- Fill-texture rotation, DERIVED (never set standalone) so it cannot go stale against
-- the bar axis or a texture swap. Stretch textures (shield.tga, striped3, blizzard,
-- WHITE8X8, every health texture) are one image scaled to the fill rect, drawn
-- wide-and-short, so a tall bar MUST rotate them or they smear. Tiled textures
-- (stripedReversed, the large* stripe sets, striped-maxhp, the modern absorb) repeat at
-- native size on BOTH axes and are correct at any bar shape -- rotating fights the
-- tiling and stretches them. Tiling is read off the LIVE fill texture, so this stays
-- correct no matter which style function last touched the bar.
mod.RF_ApplyFillRotation = function(barFrame)
    if not (barFrame and barFrame.SetRotatesTexture) then
        return
    end
    local vert = barFrame.GetOrientation and barFrame:GetOrientation() == "VERTICAL"
    local fillTex = barFrame.GetStatusBarTexture and barFrame:GetStatusBarTexture()
    local tiled = fillTex
        and ((fillTex.GetHorizTile and fillTex:GetHorizTile()) or (fillTex.GetVertTile and fillTex:GetVertTile()))
    barFrame:SetRotatesTexture((vert and not tiled) and true or false)
end

-- Inverted health fill: SetReverseFill swaps which SIDE of the seam the fill
-- texture paints -- missing health takes the bar colour and current health is
-- left to the background. Raid and party resolve through the caller's settings
-- table (party gets its own when the Health Bar section is unsynced).
mod.RF_IsInvertedFill = function(s)
    return (s or saved.profile).healthInvertFill and true or false
end

-------------------------------------------------------------------------------
--  Health-fill tint overlays
--
--  "Health Bar Color" indicators paint over the health FILL. A flat
--  SetColorTexture slab erases the bar's shading, so a tinted frame reads as a
--  solid block beside untinted ones; the overlay borrows the bar's own fill
--  texture instead and recolors it with a vertex color.
--
--  The overlay is anchored to the current-health area (ns.RF_AnchorCurHealth:
--  the fill texture, or under Inverted Fill the rest of the bar up to the fill's
--  HP edge), so it inherits the bar's fill geometry for free: these fills clip
--  by resizing rather than by moving their tex coords (measured -- identical
--  coords at full and at half fill), so the overlay stretches exactly as the bar
--  art does with nothing to update per tick. The coords are copied anyway so
--  anything the orientation pass does to them comes along, which is also why
--  the refresh runs after that pass (the anchor reads the direction it set).
--
--  Live BM/DM slots register on the bar, so a Health Bar Texture change can
--  re-anchor them to the new fill object and repaint (ReanchorAbsorbToFill for
--  frames built through StyleButton, FB.ApplyStyle for Focus/Boss). The options
--  previews are rebuilt wholesale and need no refresh.
-------------------------------------------------------------------------------

-- host and owner are kept on the overlay rather than in the entry, so a cleared
-- entry can be rebuilt by the next paint without losing either. host is stored only
-- when it is NOT the overlay itself -- the Debuff Manager hangs its overlay off a
-- wrapper frame, and that wrapper is what a fill swap has to re-anchor.
mod.RF_RegisterBarTint = function(barFrame, texture, owner, ownerFrame)
    if not (barFrame and texture) then
        return
    end
    if owner and owner ~= texture then
        texture._cuiTintHost = owner
    end
    if ownerFrame then
        texture._cuiTintOwner = ownerFrame
    end
    local reg = barFrame._cuiBarTints
    if not reg then
        reg = setmetatable({}, { __mode = "k" })
        barFrame._cuiBarTints = reg
    end
    if reg[texture] == nil then
        reg[texture] = {}
    end
end

-- Called when a container that owned overlays on this bar is released. Engine aura
-- buttons are never freed, so their overlays would otherwise pile up one set per
-- rebuild -- an indicator edit or a spec change is enough -- and every later layout
-- pass would walk the dead ones. Entries are re-added by the next paint.
--
-- Scoped to the owner being released. Clearing the whole registry would also drop
-- a live overlay belonging to another owner, and an overlay that is displayed but
-- not repainted never re-registers -- the next Health Bar Texture change would
-- then skip it and leave it on the old art.
mod.RF_ClearBarTints = function(barFrame, ownerFrame)
    local reg = barFrame and barFrame._cuiBarTints
    if not (reg and ownerFrame) then
        return
    end
    for texture in pairs(reg) do
        if texture._cuiTintOwner == ownerFrame then
            reg[texture] = nil
        end
    end
end

mod.RF_TintOverBarFill = function(texture, barFrame, red, green, blue, a)
    if not texture then
        return
    end
    mod.RF_RegisterBarTint(barFrame, texture)
    local reg = barFrame and barFrame._cuiBarTints
    local ent = reg and reg[texture]
    -- Stored pre-multiply: the refresh path calls back in with these, so folding
    -- the fill opacity in here would compound it on every pass.
    if ent then
        ent.r, ent.g, ent.b, ent.a = red, green, blue, a
    end
    -- Inherit the bar's configured Fill Opacity, so a tinted frame is as
    -- translucent as its untinted neighbours instead of the one solid bar in the
    -- group. Read from the stamp the style pass leaves, NOT from the live fill
    -- colour: _ApplyHealthBg drives that alpha down to 0.3 offline and 0.5 dead,
    -- and nothing repaints tints when a unit reconnects, so a tint painted during
    -- either would latch dimmed. Dark Mode is deliberately not inherited -- it
    -- dims the fill texture, and a colour the user picked should not be
    -- auto-dimmed.
    if barFrame then
        a = a * (barFrame._cuiFillOpacity or 1)
    end
    local fillTex = barFrame and barFrame.GetStatusBarTexture and barFrame:GetStatusBarTexture()
    local filePath = fillTex and fillTex.GetTexture and fillTex:GetTexture()
    if not filePath then
        -- Reset both: a texcoord from the textured branch survives the swap, and
        -- SetColorTexture bakes the color into the texture rather than into the
        -- vertex color, so a stale vertex color would multiply it.
        texture:SetTexCoord(0, 1, 0, 1)
        texture:SetColorTexture(red, green, blue, a)
        texture:SetVertexColor(1, 1, 1, 1)
        return
    end
    texture:SetTexture(filePath)
    if fillTex.GetTexCoord then
        texture:SetTexCoord(fillTex:GetTexCoord())
    end
    texture:SetVertexColor(red, green, blue, a)
end

-- Repaint BEFORE re-anchoring, and re-anchor with no ClearAllPoints
-- (RF_AnchorCurHealth only rewrites one TOPLEFT/BOTTOMRIGHT pair): the caller
-- isolates this, and a ClearAllPoints that succeeded ahead of a denied anchor
-- write would strand the overlay with no anchor at all for the rest of the session.
mod.RF_RefreshOneBarTint = function(barFrame, texture, ent, fillTex)
    if ent.r then
        mod.RF_TintOverBarFill(texture, barFrame, ent.r, ent.g, ent.b, ent.a)
    end
    if fillTex then
        mod.RF_AnchorCurHealth(texture._cuiTintHost or texture, barFrame, fillTex)
    end
end

-- Isolated per entry: the overlay can hang off an engine aura button, and this
-- runs from bare ReloadFrames calls where a throw would abort the styling loop
-- mid-iteration. RF_TintOverBarFill only ever rewrites an entry it was handed, so
-- the walk cannot gain keys mid-iteration.
mod.RF_RefreshBarTints = function(barFrame)
    local reg = barFrame and barFrame._cuiBarTints
    if not reg then
        return
    end
    local fillTex = barFrame.GetStatusBarTexture and barFrame:GetStatusBarTexture()
    for texture, ent in pairs(reg) do
        pcall(mod.RF_RefreshOneBarTint, barFrame, texture, ent, fillTex)
    end
end

-- Fill axis AND inversion, applied and returned together: axis via
-- SetOrientation, inversion via SetReverseFill. Sole owner of both -- callers
-- take the returns rather than re-reading the settings, so the flags and the
-- anchors derived from them cannot disagree. Restyle/style passes only
-- (StyleButton, ReanchorAbsorbToFill, FB.StyleVisuals for the boss and pet
-- frames, ApplyPreviewData); the per-tick value paths must never touch either
-- property. They read the _cuiInv stamp left on the bar (always our own
-- StatusBar) instead of the settings, so the value they paint -- current or
-- missing health -- always matches the fill direction set here.
mod.RF_ApplyHealthOrientation = function(barFrame, s)
    if not barFrame then
        return false
    end
    local vert = mod.RF_IsVerticalFill(s)
    local invert = mod.RF_IsInvertedFill(s)
    barFrame:SetOrientation(vert and "VERTICAL" or "HORIZONTAL")
    barFrame:SetReverseFill(invert)
    barFrame._cuiInv = invert
    mod.RF_ApplyFillRotation(barFrame)
    return vert, invert
end

-- The fill texture's two corners on its HP edge (the current-health seam) that
-- the absorb, heal and clip anchors hang off: its right edge, its top edge on a
-- vertical bar, and the opposite edge under Inverted Fill. Paired top then
-- bottom on the horizontal axis, left then right on the vertical one.
mod.RF_HpEdge = function(vert, invert)
    if vert then
        if invert then
            return "BOTTOMLEFT", "BOTTOMRIGHT"
        end
        return "TOPLEFT", "TOPRIGHT"
    end
    if invert then
        return "TOPLEFT", "BOTTOMLEFT"
    end
    return "TOPRIGHT", "BOTTOMRIGHT"
end

-- Anchors a tint or wash over the bar's CURRENT-health area: the fill texture,
-- or under Inverted Fill (the fill then paints missing health) the rest of the
-- bar up to the fill's HP edge, the rect the alive bg takes there
-- (ns._ApplyHealthBg). Region anchors only, so no health value is read, and one
-- TOPLEFT/BOTTOMRIGHT pair in every case, so a re-anchor overwrites both points
-- without a ClearAllPoints. vert/invert: the fill direction from the caller's
-- settings; omitted, it is read off the bar. Style passes only.
mod.RF_AnchorCurHealth = function(regionFrame, barFrame, fillTex, vert, invert)
    if invert == nil then
        invert = barFrame.GetReverseFill and barFrame:GetReverseFill()
    end
    if not (fillTex and invert) then
        regionFrame:SetAllPoints(fillTex or barFrame)
        return
    end
    if vert == nil then
        vert = barFrame.GetOrientation and barFrame:GetOrientation() == "VERTICAL"
    end
    if vert then
        regionFrame:SetPoint("TOPLEFT", fillTex, "BOTTOMLEFT", 0, 0)
        regionFrame:SetPoint("BOTTOMRIGHT", barFrame, "BOTTOMRIGHT", 0, 0)
    else
        regionFrame:SetPoint("TOPLEFT", barFrame, "TOPLEFT", 0, 0)
        regionFrame:SetPoint("BOTTOMRIGHT", fillTex, "BOTTOMLEFT", 0, 0)
    end
end

-- Resolve an absorb/heal/max-health style key to a texture path: built-ins from
-- ABSORB_STYLE_TEX, "sm:" SharedMedia keys through the health-bar lookup. Used
-- by live render AND preview so a saved SM key paints identically.
-- Caller-handled keys (blizzardModern / maxHealthStripes) never reach this.
function mod.ResolveAbsorbStyleTex(style, fallback)
    return ABSORB_STYLE_TEX[style]
        or (CludesUI.ResolveTexturePath(healthBarTextures, style, fallback))
        or fallback
end

-------------------------------------------------------------------------------
--  Power bar visibility (derived from role flags)
-------------------------------------------------------------------------------
local function IsPowerBarEnabled(cfg)
    return cfg.powerShowForHealer or cfg.powerShowForTank or cfg.powerShowForDPS
end

-- Uniform Icon Anchoring (powerUniformAnchors): decoration anchor host for a
-- health bar. On, returns _cuiUniformRef (stamped at creation, spanning where
-- the bar would sit with NO power bar) so per-role power bars never shift
-- icons/text. Visuals (fills, absorbs, dispel) keep the real bar.
-- Party Frames kit: the host is the visible party frame (_cuiKitRef, our
-- frame at the art's rect), whatever Uniform Icon Anchoring says.
function mod.RF_AnchorHost(health, cfg)
    local kit = health and health._cuiKitRef
    if kit then
        return kit
    end
    local ref = health and health._cuiUniformRef
    if ref and cfg and cfg.powerUniformAnchors then
        return ref
    end
    return health
end
-- Bar-relative texts (health, heal-absorb and status text): on the kit's
-- health bar under the Party Frames kit, where the stock frame puts them.
function mod.RF_BarHost(health, s)
    if health and health._cuiKitRef then
        return health
    end
    return mod.RF_AnchorHost(health, s)
end

-- "Extend Health Bar Behind Power": the health-height inset layout sites subtract for
-- the power bar. On returns 0 -- health spans the full frame and the power bar (higher
-- frame level, own bg) draws over its bottom strip; off returns powerH untouched.
function mod.RF_HealthPowerInset(cfg, powerH)
    if cfg and cfg.extendHealthBehindPower then
        return 0
    end
    return powerH
end

-- Role for POWER-BAR gating. Effective role (CludesUI.UnitEffectiveRole):
-- the player's spec wins over the assigned role, which covers both the solo
-- "NONE" case (a solo healer's mana bar must not fall through to the DPS
-- toggle) and a stale premade-listing role (listed as tank, playing dps).
-- Other units keep the assigned role.
mod._ResolvePowerRole = function(unitToken)
    return CludesUI.UnitEffectiveRole(unitToken)
end

-------------------------------------------------------------------------------
--  Raid size tier resolution: width/height for a group size from the defined
--  overrides, cascading toward 20-man (the base) when a tier is undefined.
--  Tiers: 10, 15, 20(base), 25, 30, 40
-------------------------------------------------------------------------------
mod._GetRaidSizeFrameDimensions = function(groupSize)
    local cfg = saved.profile
    local baseW = cfg.frameWidth or 125
    local baseH = cfg.frameHeight or 60
    -- Single cascade authority (ns._RFResolveTierOverride, defined in the
    -- growth-origin block): exact tier, then one step toward 20, then base.
    local _, shade = mod._RFResolveTierOverride(groupSize)
    if shade then
        return shade.width or baseW, shade.height or baseH
    end
    return baseW, baseH
end

-- Show Groups as the frames apply it; every Show Groups reader goes through
-- here. Hide Groups 5-8 in Mythic Raid (opt-in): inside a Mythic raid
-- (difficulty 16, groups 1-4 only) groups 5-8 hide on top of Show Groups.
-- The capped set is ONE reused table: read it at once, never hold it.
mod._mythicGroups = {}
mod._VisibleGroups = function()
    local cfg = saved.profile
    local vg = cfg.visibleGroups
    if not cfg.mythicRaidHideGroups then
        return vg
    end
    local _, _, difficultyID = GetInstanceInfo()
    if difficultyID ~= 16 then
        return vg
    end
    local tbl = mod._mythicGroups
    for g = 1, 8 do
        tbl[g] = g <= 4 and not (vg and vg[g] == false)
    end
    return tbl
end

-- Effective raid head count for size breakpoints. With "Exclude Hidden Groups
-- from Size" on (default), members of subgroups hidden via Show Groups are not
-- counted, so the breakpoint reflects visible members only. Explicitly off:
-- returns GetNumGroupMembers() verbatim.
mod._GetEffectiveRaidSize = function()
    local num = GetNumGroupMembers() or 0
    if num == 0 then
        return num
    end
    local cfg = saved.profile
    if cfg.excludeHiddenGroupsFromSize == false then
        return num
    end
    -- Subgroups only exist in a raid; party/solo has nothing to exclude.
    if not IsInRaid() then
        return num
    end
    local vg = mod._VisibleGroups()
    if not vg then
        return num
    end
    -- Skip the roster walk entirely when no group is actually hidden.
    local anyHidden = false
    for g = 1, 8 do
        if vg[g] == false then
            anyHidden = true
            break
        end
    end
    if not anyHidden then
        return num
    end
    local total = 0
    for ri = 1, num do
        local _, _, sub = GetRaidRosterInfo(ri)
        -- Fail OPEN on nil subgroup: while the roster streams in after joining,
        -- GetRaidRosterInfo returns nil for unarrived members; dropping them
        -- undercounts the raid onto the wrong tier. Count unknowns as visible;
        -- the next roster pass refines downward.
        if not sub or vg[sub] ~= false then
            total = total + 1
        end
    end
    -- Degenerate guard: every populated group hidden -> raw count, never a 0-man raid.
    if total == 0 then
        return num
    end
    return total
end

-- Track current active tier so we know when to re-layout
mod._currentSizeTier = 20

-- Main-chunk locals the CUI_RaidFrames_*.lua files re-import by name.
-- dbSetters and the five lists beside it: every file that reads one of
-- these keeps its own copy and adds a setter here; each place that assigns
-- it writes through the Set<Name> function built below, which runs them all.
-- broken: true while an CUI_RaidFrames_*.lua file loads; a file that fails
-- leaves it set, and the files behind it return at their first lines.
CludesUI.NewInternals(mod, "_internals", {
    AbbreviateNumbers = AbbreviateNumbers,
    ABSORB_STYLE_ALPHA = ABSORB_STYLE_ALPHA,
    ABSORB_STYLE_TEX = ABSORB_STYLE_TEX,
    allButtons = allButtons,
    ApplyFont = ApplyFont,
    ApplyRoleIcon = ApplyRoleIcon,
    defaults = defaultSet,
    DISPEL_COLORS = DISPEL_COLORS,
    DISPEL_ICON_ATLAS = DISPEL_ICON_ATLAS,
    ERF = ERF,
    eventFrame = eventFrame,
    FFD = FFD,
    GetFFD = GetFFD,
    InitHealthBarTextures = InitHealthBarTextures,
    IsPowerBarEnabled = IsPowerBarEnabled,
    PixelSnap = PixelSnap,
    -- false, not nil, for a class without one: a nil entry would trip the guard below
    playerFriendlySpell = playerFriendlySpell or false,
    playerRezSpell = playerRezSpell or false,
    RAID_MARKER_TEXCOORDS = RAID_MARKER_TEXCOORDS,
    ResolveHealthTexture = ResolveHealthTexture,
    separatedHdrs = separatedHdrs,
    SUMMON_STATUS_ACCEPTED = SUMMON_STATUS_ACCEPTED,
    SUMMON_STATUS_DECLINED = SUMMON_STATUS_DECLINED,
    SUMMON_STATUS_PENDING = SUMMON_STATUS_PENDING,
    unitToButton = unitToButton,
    unitTrackers = unitTrackers,
    dbSetters = {
        function(val)
            saved = val
        end,
    },
    PPSetters = {
        function(val)
            Pix = val
        end,
    },
    containerFrameSetters = {
        function(val)
            containerFrame = val
        end,
    },
    inCombatSetters = {
        function(val)
            inCombat = val
        end,
    },
    readyCheckActiveSetters = {},
    framesVisibleSetters = {},
}, {
    SetDB = "dbSetters",
    SetPP = "PPSetters",
    SetContainerFrame = "containerFrameSetters",
    SetInCombat = "inCombatSetters",
    SetReadyCheckActive = "readyCheckActiveSetters",
    SetFramesVisible = "framesVisibleSetters",
})
