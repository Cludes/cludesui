if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CUI_Fonts_Options.lua
--
--  Global Settings > Fonts: the centralized fonts page.
--  Top block = the global font settings (moved from the old Fonts & Colors
--  page). Below it, one expandable card per module. Every control on this
--  page is a WRITE-THROUGH MIRROR: it reads and writes the exact same DB key
--  as the module's own options row and calls the same apply path, so editing
--  a value here or in the module page is identical. Settings that live behind
--  a module page's own selection state (per-bar, per-unit, per-icon stores)
--  are link rows that jump to the real setting instead of duplicating it.
--
--  The card header hosts the module's font override dropdown. That dropdown
--  IS the old "PER ADDON FONTS" list: it reads/writes the same
--  CludesUIDB.fonts.moduleFonts entries (lazily created on the first
--  non-global pick, pruned when font and outline both return to global), so
--  existing profiles and exports behave identically.
-------------------------------------------------------------------------------

local PAGE_FONTS = "Fonts"
local GLOBAL_KEY = "_CUIGlobal"

-- Options page pool (CludesUI_FramePool.lua): frames made here on a pool
-- host are reset and dressed again by the next build instead of made anew;
-- elsewhere this is CreateFrame.
local CreateFrame = CUI._Pool.CreateFrame

-- Session-only card expand state (never saved).
local _ftExpanded = {}

-------------------------------------------------------------------------------
--  Shared helpers
-------------------------------------------------------------------------------

-- Reload popup for font changes; same funnel contract as the module pages:
-- the resolution cache must drop even when the user picks Later, because the
-- new value is already live in the DB.
local function AskFontReload()
    CUI.InvalidateFontCache()
    CUI:ShowConfirmPopup({
        title = "Reload Required",
        message = "Font changed. A UI reload is needed to apply the new font.",
        confirmText = "Reload Now",
        cancelText = "Later",
        reload = true,
    })
end

-- moduleFonts accessors. No entry and an entry with font/outline "__global"
-- are behaviorally identical (GetModuleFontEntry falls through to the global
-- font either way), so the card rows lazily create entries and prune them
-- back out when both values return to global.
local function FindModuleFontEntry(folder)
    local fontsDB = CUI.GetFontsDB()
    local entries = fontsDB.moduleFonts
    if not entries then return nil end
    for i = 1, #entries do
        if entries[i].folder == folder then return entries[i], i end
    end
    return nil
end

local function EnsureModuleFontEntry(folder, display)
    local fontsDB = CUI.GetFontsDB()
    if not fontsDB.moduleFonts then fontsDB.moduleFonts = {} end
    local record = FindModuleFontEntry(folder)
    if not record then
        record = { folder = folder, display = display, font = "__global", outline = "__global" }
        fontsDB.moduleFonts[#fontsDB.moduleFonts + 1] = record
    end
    return record
end

local function PruneModuleFontEntry(folder)
    local fontsDB = CUI.GetFontsDB()
    local record, position = FindModuleFontEntry(folder)
    if
        record
        and position
        and (record.font or "__global") == "__global"
        and (record.outline or "__global") == "__global"
    then
        table.remove(fontsDB.moduleFonts, position)
    end
end

-- Shared outline dropdown data (safe to share by reference: dropdown menus
-- render only the keys their order lists).
local MODULE_OUTLINE_VALUES = {
    ["__global"] = { text = "CUI Global Outline" },
    ["none"] = { text = "Drop Shadow" },
    ["outline"] = { text = "Outline" },
    ["thick"] = { text = "Thick Outline" },
}
local MODULE_OUTLINE_ORDER = { "__global", "none", "outline", "thick" }

-- Per-module outline row config (left slot of each card's first row).
local function ModuleOutlineCfg(folder, display)
    return {
        type = "dropdown",
        text = "Module Outline",
        tooltip = "Outline style override for all "
            .. display
            .. " text. CUI Global Outline follows the global Outline Mode setting above.",
        values = MODULE_OUTLINE_VALUES,
        order = MODULE_OUTLINE_ORDER,
        getValue = function()
            local record = FindModuleFontEntry(folder)
            return (record and record.outline) or "__global"
        end,
        setValue = function(val)
            local record = FindModuleFontEntry(folder)
            local current = (record and record.outline) or "__global"
            if val == current then return end
            if val == "__global" then
                if record then
                    record.outline = "__global"
                    PruneModuleFontEntry(folder)
                end
            else
                EnsureModuleFontEntry(folder, display).outline = val
            end
            AskFontReload()
        end,
    }
end

local BLANK, LinkRow, NoteRow = CUI.BlankRowCfg, CUI.BuildLinkRow, CUI.BuildNoteRow

-------------------------------------------------------------------------------
--  Per-module card content builders
--
--  Each builder receives (parent, y, W, tile) and returns the new y. Every
--  row is a write-through mirror of the module's own options row: same DB
--  key, same defaults, same apply call. When the module is disabled its
--  namespace is nil and the card shows only the module font/outline layer.
-------------------------------------------------------------------------------

local NS = CUI.ModuleNS

local function TileActionBars(hostFrame, cursorY, W, tile)
    local mod = NS(tile.folder)
    local function barList()
        local ABAR = mod and mod.EAB
        return ABAR and ABAR.db and ABAR.db.profile and ABAR.db.profile.bars
    end
    local function dataBarCfg(labelText, barId)
        return {
            type = "slider",
            text = labelText,
            min = 6,
            max = 24,
            step = 1,
            getValue = function()
                local b = barList()
                local cfg = b and b[barId]
                return (cfg and cfg.textSize) or 9
            end,
            setValue = function(val)
                local b = barList()
                local cfg = b and b[barId]
                if not cfg then return end
                cfg.textSize = val
                if mod.ApplyDataBarLayout then mod.ApplyDataBarLayout(barId) end
            end,
        }
    end
    local _, height
    if mod then
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            ModuleOutlineCfg(tile.folder, tile.display),
            dataBarCfg("XP Bar Text Size", "XPBar")
        )
        cursorY = cursorY - height
        -- WoW Forever has no House Favor bar: its slot is blank there.
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            dataBarCfg("Reputation Bar Text Size", "RepBar"),
            CUI.IS_FOREVER and BLANK() or dataBarCfg("House Favor Bar Text Size", "FavorBar")
        )
        cursorY = cursorY - height
        cursorY = LinkRow(
            hostFrame,
            cursorY,
            "Keybind, Macro, Charges & Cooldown Text (per bar)",
            tile.folder,
            "Bar Display",
            "TEXT",
            "Keybind Text Size"
        )
    else
        _, height = W:DualRow(hostFrame, cursorY, ModuleOutlineCfg(tile.folder, tile.display), BLANK())
        cursorY = cursorY - height
        cursorY = NoteRow(
            hostFrame,
            cursorY,
            CUI.Lf("Enable %1$s to edit its text settings.", CUI.L(tile.display))
        )
    end
    return cursorY
end

local function TileNameplates(hostFrame, cursorY, W, tile)
    local mod = NS(tile.folder)
    local _, height
    if not mod then
        _, height = W:DualRow(hostFrame, cursorY, ModuleOutlineCfg(tile.folder, tile.display), BLANK())
        cursorY = cursorY - height
        return NoteRow(
            hostFrame,
            cursorY,
            CUI.Lf("Enable %1$s to edit its text settings.", CUI.L(tile.display))
        )
    end
    local function saved() return mod.db and mod.db.profile end
    local DEF = mod.defaults or {}
    -- applyFn: named ns refresher when the module publishes one, otherwise the
    -- module-wide reapply (same repaint the module's own castbar size rows use).
    local function sizeSlider(labelText, key, minV, maxV, def, applyName, legacyKey)
        return {
            type = "slider",
            text = labelText,
            min = minV,
            max = maxV,
            step = 1,
            getValue = function()
                local profile = saved()
                local val = profile and profile[key]
                if val == nil and legacyKey and profile then val = profile[legacyKey] end
                return val or DEF[key] or def
            end,
            setValue = function(val)
                local profile = saved()
                if not profile then return end
                profile[key] = val
                local func = (applyName and mod[applyName]) or mod.RefreshAllSettings
                if func then func() end
            end,
        }
    end
    _, height = W:DualRow(
        hostFrame,
        cursorY,
        ModuleOutlineCfg(tile.folder, tile.display),
        sizeSlider(
            "Friendly Name Size (Bar Mode)",
            "friendlyNameTextSize",
            6,
            30,
            12,
            "RefreshFriendlyNameTextSize"
        )
    )
    cursorY = cursorY - height
    _, height = W:DualRow(
        hostFrame,
        cursorY,
        sizeSlider("Friendly Name Size (Name Only)", "friendlyNameSize", 8, 30, 15, "RefreshFriendlyNameSize"),
        sizeSlider("Friendly NPC Name Size", "friendlyNPCNameSize", 6, 30, 13, "RefreshAllNPCOverlays")
    )
    cursorY = cursorY - height
    _, height = W:DualRow(
        hostFrame,
        cursorY,
        sizeSlider("Top Text Size", "textSlotTopSize", 6, 30, 10),
        sizeSlider("Center Text Size", "textSlotCenterSize", 6, 30, 10)
    )
    cursorY = cursorY - height
    _, height = W:DualRow(
        hostFrame,
        cursorY,
        sizeSlider("Left Text Size", "textSlotLeftSize", 6, 30, 10),
        sizeSlider("Right Text Size", "textSlotRightSize", 6, 30, 10)
    )
    cursorY = cursorY - height
    _, height = W:DualRow(
        hostFrame,
        cursorY,
        sizeSlider("Top Left Text Size", "textSlotTopLeftSize", 6, 30, 10),
        sizeSlider("Top Right Text Size", "textSlotTopRightSize", 6, 30, 10)
    )
    cursorY = cursorY - height
    _, height = W:DualRow(
        hostFrame,
        cursorY,
        sizeSlider("Bottom Left Text Size", "textSlotBottomLeftSize", 6, 30, 10),
        sizeSlider("Bottom Right Text Size", "textSlotBottomRightSize", 6, 30, 10)
    )
    cursorY = cursorY - height
    _, height = W:DualRow(
        hostFrame,
        cursorY,
        sizeSlider("Cast Name Size", "castNameSize", 6, 20, 10),
        sizeSlider("Cast Timer Size", "castTimerSize", 6, 20, 10)
    )
    cursorY = cursorY - height
    _, height = W:DualRow(hostFrame, cursorY, sizeSlider("Cast Target Size", "castTargetSize", 6, 20, 10), {
        type = "slider",
        text = "Aura Stacks Size",
        min = 6,
        max = 20,
        step = 1,
        getValue = function()
            local profile = saved()
            return (profile and profile.auraStackTextSize) or DEF.auraStackTextSize or 11
        end,
        setValue = function(val)
            local profile = saved()
            if not profile then return end
            profile.auraStackTextSize = val
            if mod.RefreshAllSettings then mod.RefreshAllSettings() end
            if mod.NPC_ReloadAll then mod.NPC_ReloadAll() end
        end,
    })
    cursorY = cursorY - height
    _, height = W:DualRow(
        hostFrame,
        cursorY,
        sizeSlider("Buff Duration Size", "buffDurationTextSize", 6, 20, 11, nil, "auraDurationTextSize"),
        sizeSlider("Debuff Duration Size", "debuffDurationTextSize", 6, 20, 11, nil, "auraDurationTextSize")
    )
    cursorY = cursorY - height
    _, height = W:DualRow(
        hostFrame,
        cursorY,
        sizeSlider("CC Duration Size", "ccDurationTextSize", 6, 20, 11, nil, "auraDurationTextSize"),
        sizeSlider("Focus Letter Size", "focusLetterSize", 6, 40, 18)
    )
    cursorY = cursorY - height
    _, height = W:DualRow(
        hostFrame,
        cursorY,
        sizeSlider("Distance Text Size", "rangeTextSize", 6, 32, 11, "RangeText_Refresh"),
        sizeSlider("Quest Objective Text Size", "questObjectiveTextSize", 6, 24, 14, "RefreshQuestObjective")
    )
    cursorY = cursorY - height
    return cursorY
end

local function TileUnitFrames(hostFrame, cursorY, W, tile)
    local mod = NS(tile.folder)
    local _, height = W:DualRow(hostFrame, cursorY, ModuleOutlineCfg(tile.folder, tile.display), BLANK())
    cursorY = cursorY - height
    if mod then
        cursorY = LinkRow(
            hostFrame,
            cursorY,
            "Player, Target & Focus Text Sizes (per unit)",
            tile.folder,
            "Main Frames",
            "HEALTH BAR"
        )
        cursorY = LinkRow(
            hostFrame,
            cursorY,
            "Pet & Target-of-Target Text Sizes (per unit)",
            tile.folder,
            "Mini Frames",
            "HEALTH BAR"
        )
        cursorY =
            LinkRow(hostFrame, cursorY, "Boss Frames Text Sizes", tile.folder, "Boss Frames", "HEALTH BAR")
        cursorY = LinkRow(
            hostFrame,
            cursorY,
            "Player Aura Bars Text (per bar)",
            tile.folder,
            "Player Aura Bars",
            nil
        )
    else
        cursorY = NoteRow(
            hostFrame,
            cursorY,
            CUI.Lf("Enable %1$s to edit its text settings.", CUI.L(tile.display))
        )
    end
    return cursorY
end

local function TileRaidFrames(hostFrame, cursorY, W, tile)
    local mod = NS(tile.folder)
    local _, height
    if not mod then
        _, height = W:DualRow(hostFrame, cursorY, ModuleOutlineCfg(tile.folder, tile.display), BLANK())
        cursorY = cursorY - height
        return NoteRow(
            hostFrame,
            cursorY,
            CUI.Lf("Enable %1$s to edit its text settings.", CUI.L(tile.display))
        )
    end
    local function saved() return mod.db and mod.db.profile end
    local function RFApply()
        if mod.ReloadFrames then mod.ReloadFrames() end
        if mod.ReloadPartyFrames then mod.ReloadPartyFrames() end
    end
    local function sizeSlider(labelText, key, minV, maxV, def)
        return {
            type = "slider",
            text = labelText,
            min = minV,
            max = maxV,
            step = 1,
            getValue = function()
                local profile = saved()
                return (profile and profile[key]) or def
            end,
            setValue = function(val)
                local profile = saved()
                if not profile then return end
                profile[key] = val
                RFApply()
            end,
        }
    end
    _, height = W:DualRow(
        hostFrame,
        cursorY,
        ModuleOutlineCfg(tile.folder, tile.display),
        sizeSlider("Name Size", "nameSize", 6, 26, 10)
    )
    cursorY = cursorY - height
    _, height = W:DualRow(
        hostFrame,
        cursorY,
        sizeSlider("Health Text Size", "healthTextSize", 6, 26, 9),
        sizeSlider("Power Text Size", "powerTextSize", 6, 26, 8)
    )
    cursorY = cursorY - height
    _, height = W:DualRow(
        hostFrame,
        cursorY,
        sizeSlider("Heal Absorb Text Size", "healAbsorbTextSize", 6, 26, 9),
        sizeSlider("Status Text Size", "statusTextSize", 6, 30, 14)
    )
    cursorY = cursorY - height
    _, height = W:DualRow(
        hostFrame,
        cursorY,
        sizeSlider("Group Number Size", "groupNumberSize", 6, 30, 10),
        sizeSlider("Top Name Bar Text Size", "topNameBarTextSize", 6, 30, 11)
    )
    cursorY = cursorY - height
    _, height = W:DualRow(hostFrame, cursorY, {
        type = "slider",
        text = "Healer Mana Text Size",
        min = 8,
        max = 24,
        step = 1,
        getValue = function()
            local profile = saved()
            local hm = profile and profile.healerMana
            return (hm and hm.textSize) or 12
        end,
        setValue = function(val)
            local profile = saved()
            if not profile then return end
            if not profile.healerMana then profile.healerMana = {} end
            profile.healerMana.textSize = val
            if mod.HM_Rebuild then
                mod.HM_Rebuild()
            else
                RFApply()
            end
        end,
    }, sizeSlider("Level Size", "levelTextSize", 6, 26, 10))
    cursorY = cursorY - height
    cursorY = LinkRow(hostFrame, cursorY, "Party-Specific Text Sizes", tile.folder, "Party", "TEXT DISPLAY")
    cursorY =
        LinkRow(hostFrame, cursorY, "Buff Manager Text (per indicator)", tile.folder, "Buff Manager", nil)
    cursorY =
        LinkRow(hostFrame, cursorY, "Debuff Manager Text (per tile)", tile.folder, "Debuff Manager", nil)
    return cursorY
end

local function TileCooldownManager(hostFrame, cursorY, W, tile)
    local mod = NS(tile.folder)
    local _, height = W:DualRow(hostFrame, cursorY, ModuleOutlineCfg(tile.folder, tile.display), BLANK())
    cursorY = cursorY - height
    if mod then
        cursorY = LinkRow(
            hostFrame,
            cursorY,
            "Icon Duration, Stack & Keybind Text (per bar)",
            tile.folder,
            "CDM Bars",
            "ICON DISPLAY",
            "Duration Size"
        )
        cursorY = LinkRow(
            hostFrame,
            cursorY,
            "Tracking Bar Name, Timer & Stacks Text (per bar)",
            tile.folder,
            "Tracking Bars",
            "BAR LAYOUT"
        )
    else
        cursorY = NoteRow(
            hostFrame,
            cursorY,
            CUI.Lf("Enable %1$s to edit its text settings.", CUI.L(tile.display))
        )
    end
    return cursorY
end

local function TileResourceBars(hostFrame, cursorY, W, tile)
    local mod = NS(tile.folder)
    local _, height
    if not mod then
        _, height = W:DualRow(hostFrame, cursorY, ModuleOutlineCfg(tile.folder, tile.display), BLANK())
        cursorY = cursorY - height
        return NoteRow(
            hostFrame,
            cursorY,
            CUI.Lf("Enable %1$s to edit its text settings.", CUI.L(tile.display))
        )
    end
    local function saved() return _G._CURB_AceDB and _G._CURB_AceDB.profile end
    local function RBApply()
        if _G._CURB_Apply then _G._CURB_Apply() end
    end
    local function sizeSlider(labelText, tableKey, key, minV, maxV, def)
        return {
            type = "slider",
            text = labelText,
            min = minV,
            max = maxV,
            step = 1,
            getValue = function()
                local profile = saved()
                local tbl = profile and profile[tableKey]
                return (tbl and tbl[key]) or def
            end,
            setValue = function(val)
                local profile = saved()
                local tbl = profile and profile[tableKey]
                if not tbl then return end
                tbl[key] = val
                RBApply()
            end,
        }
    end
    _, height = W:DualRow(
        hostFrame,
        cursorY,
        ModuleOutlineCfg(tile.folder, tile.display),
        sizeSlider("Health Text Size", "health", "textSize", 8, 24, 11)
    )
    cursorY = cursorY - height
    _, height = W:DualRow(
        hostFrame,
        cursorY,
        sizeSlider("Power Text Size", "primary", "textSize", 8, 24, 11),
        sizeSlider("Class Resource Text Size", "secondary", "textSize", 8, 24, 11)
    )
    cursorY = cursorY - height
    _, height = W:DualRow(
        hostFrame,
        cursorY,
        sizeSlider("Cast Bar Text Size", "castBar", "spellTextSize", 8, 24, 11),
        sizeSlider("Cast Bar Timer Size", "castBar", "timerSize", 8, 24, 11)
    )
    cursorY = cursorY - height
    _, height = W:DualRow(
        hostFrame,
        cursorY,
        sizeSlider("Totem Timer Size", "totemBar", "timerSize", 6, 24, 11),
        BLANK()
    )
    cursorY = cursorY - height
    return cursorY
end

local function TileAuraBuffReminders(hostFrame, cursorY, W, tile)
    local mod = NS(tile.folder)
    local _, height
    if not mod then
        _, height = W:DualRow(hostFrame, cursorY, ModuleOutlineCfg(tile.folder, tile.display), BLANK())
        cursorY = cursorY - height
        return NoteRow(
            hostFrame,
            cursorY,
            CUI.Lf("Enable %1$s to edit its text settings.", CUI.L(tile.display))
        )
    end
    local function saved() return _G._CUABR_AceDB and _G._CUABR_AceDB.profile end
    local nameFontValues, nameFontOrder = CUI.BuildFontDropdownData()
    _, height = W:DualRow(hostFrame, cursorY, ModuleOutlineCfg(tile.folder, tile.display), BLANK())
    cursorY = cursorY - height
    _, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Name Font",
        values = nameFontValues,
        order = nameFontOrder,
        getValue = function()
            local profile = saved()
            return (profile and profile.display and profile.display.nameFont) or "__global"
        end,
        setValue = function(val)
            local profile = saved()
            if not (profile and profile.display) then return end
            profile.display.nameFont = (val ~= "__global") and val or nil
            if _G._CUABR_RequestRefresh then _G._CUABR_RequestRefresh() end
        end,
    }, {
        type = "slider",
        text = "Name Text Size",
        min = 6,
        max = 30,
        step = 1,
        getValue = function()
            local profile = saved()
            return (profile and profile.display and profile.display.textSize) or 11
        end,
        setValue = function(val)
            local profile = saved()
            if not (profile and profile.display) then return end
            profile.display.textSize = val
            if _G._CUABR_RequestRefresh then _G._CUABR_RequestRefresh() end
        end,
    })
    cursorY = cursorY - height
    _, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Item Count Font",
        values = nameFontValues,
        order = nameFontOrder,
        getValue = function()
            local profile = saved()
            return (profile and profile.display and profile.display.countFont) or "__global"
        end,
        setValue = function(val)
            local profile = saved()
            if not (profile and profile.display) then return end
            profile.display.countFont = (val ~= "__global") and val or nil
            if _G._CUABR_RequestRefresh then _G._CUABR_RequestRefresh() end
        end,
    }, {
        type = "slider",
        text = "Item Count Text Size",
        min = 6,
        max = 30,
        step = 1,
        getValue = function()
            local profile = saved()
            return (profile and profile.display and profile.display.countSize) or 16
        end,
        setValue = function(val)
            local profile = saved()
            if not (profile and profile.display) then return end
            profile.display.countSize = val
            if _G._CUABR_RequestRefresh then _G._CUABR_RequestRefresh() end
        end,
    })
    cursorY = cursorY - height
    _, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Mana Warning Font",
        values = nameFontValues,
        order = nameFontOrder,
        getValue = function()
            local profile = saved()
            return (profile and profile.consumables and profile.consumables.rcManaWarnFont) or "__global"
        end,
        setValue = function(val)
            local profile = saved()
            if not (profile and profile.consumables) then return end
            profile.consumables.rcManaWarnFont = (val ~= "__global") and val or nil
            if _G._CUABR_RCWarnApply then _G._CUABR_RCWarnApply() end
        end,
    }, {
        type = "slider",
        text = "Mana Warning Text Size",
        min = 10,
        max = 72,
        step = 1,
        getValue = function()
            local profile = saved()
            return (profile and profile.consumables and profile.consumables.rcManaWarnSize) or 48
        end,
        setValue = function(val)
            local profile = saved()
            if not (profile and profile.consumables) then return end
            profile.consumables.rcManaWarnSize = val
            if _G._CUABR_RCWarnApply then _G._CUABR_RCWarnApply() end
        end,
    })
    cursorY = cursorY - height
    return cursorY
end

local function TileQoL(hostFrame, cursorY, W, tile)
    local mod = NS(tile.folder)
    local _, height
    if not mod then
        _, height = W:DualRow(hostFrame, cursorY, ModuleOutlineCfg(tile.folder, tile.display), BLANK())
        cursorY = cursorY - height
        return NoteRow(
            hostFrame,
            cursorY,
            CUI.Lf("Enable %1$s to edit its text settings.", CUI.L(tile.display))
        )
    end
    -- Flat CludesUIDB keys with a parent-published apply fn.
    local function gsize(labelText, key, minV, maxV, def, applyName)
        return {
            type = "slider",
            text = labelText,
            min = minV,
            max = maxV,
            step = 1,
            getValue = function() return (CludesUIDB and CludesUIDB[key]) or def end,
            setValue = function(val)
                if not CludesUIDB then CludesUIDB = {} end
                CludesUIDB[key] = val
                local func = CUI[applyName]
                if func then func() end
            end,
        }
    end
    local function brDB()
        local db = _G._CUI_BattleRes_DB and _G._CUI_BattleRes_DB()
        return db and db.profile and db.profile.battleRes
    end
    local function brSize(labelText, key, minV, maxV, def)
        return {
            type = "slider",
            text = labelText,
            min = minV,
            max = maxV,
            step = 1,
            getValue = function()
                local profile = brDB()
                return (profile and profile[key]) or def
            end,
            setValue = function(val)
                local profile = brDB()
                if not profile then return end
                profile[key] = val
                if _G._CUI_BattleRes_Apply then _G._CUI_BattleRes_Apply() end
            end,
        }
    end
    local function blDB()
        local db = _G._CUI_BattleRes_DB and _G._CUI_BattleRes_DB()
        return db and db.profile and db.profile.bloodlust
    end
    -- Bloodlust writes its own key but reads through the Battle Res value,
    -- exactly like the module's own sliders.
    local function blSize(labelText, key, minV, maxV, def)
        return {
            type = "slider",
            text = labelText,
            min = minV,
            max = maxV,
            step = 1,
            getValue = function()
                local bl, br = blDB(), brDB()
                return (bl and bl[key]) or (br and br[key]) or def
            end,
            setValue = function(val)
                local bl = blDB()
                if not bl then return end
                bl[key] = val
                if _G._CUI_Bloodlust_Apply then _G._CUI_Bloodlust_Apply() end
            end,
        }
    end
    -- Slots fill left to right, top to bottom. WoW Forever has no keystone
    -- popup, no Battle Res indicator and no Bloodlust Tracker, so their slots
    -- are left out there and the rest close up, with a blank only in an odd
    -- last slot.
    local FOREVER = CUI.IS_FOREVER
    local slots = {}
    local function addSlot(rowConf) slots[#slots + 1] = rowConf end
    addSlot(ModuleOutlineCfg(tile.folder, tile.display))
    addSlot(gsize("Map Coordinates Text Size", "mapCoordsTextSize", 8, 24, 12, "_applyMapCoords"))
    addSlot(gsize("Group Death Alert Text Size", "groupDeathTextSize", 14, 64, 34, "_applyGroupDeathAlert"))
    addSlot(gsize("Combat Alert Text Size", "combatAlertTextSize", 14, 64, 22, "_applyCombatAlertFrame"))
    addSlot({
        type = "slider",
        text = "FPS Counter Text Size",
        min = 8,
        max = 30,
        step = 1,
        getValue = function()
            if CUI.QoLExtrasGet then return CUI.QoLExtrasGet("fpsTextSize") or 12 end
            return (CludesUIDB and CludesUIDB.fpsTextSize) or 12
        end,
        setValue = function(val)
            if CUI.QoLExtrasSet then CUI.QoLExtrasSet("fpsTextSize", val) end
            if CUI._applyFPSDisplay then CUI._applyFPSDisplay() end
        end,
    })
    addSlot(gsize("Durability Warning Text Size", "durWarnTextSize", 10, 50, 30, "_durWarnApplySettings"))
    addSlot(
        gsize("Target Distance Text Size", "targetDistanceTextSize", 10, 48, 18, "_applyTargetDistanceFrame")
    )
    if not FOREVER then
        addSlot({
            type = "slider",
            text = "Keystone Popup Text Size",
            min = 8,
            max = 16,
            step = 1,
            getValue = function()
                local tbl = CludesUIDB and CludesUIDB.keystonePopup
                return (tbl and tbl.textSize) or 11
            end,
            setValue = function(val)
                if not CludesUIDB then CludesUIDB = {} end
                if not CludesUIDB.keystonePopup then CludesUIDB.keystonePopup = {} end
                CludesUIDB.keystonePopup.textSize = val
                if _G._CUI_RefreshKeystonePopup then _G._CUI_RefreshKeystonePopup() end
            end,
        })
    end
    if not FOREVER then
        addSlot(brSize("Battle Res Duration Size", "durationSize", 8, 30, 12))
        addSlot(brSize("Battle Res Count Size", "countSize", 8, 20, 11))
        addSlot(brSize("Battle Res Text Size", "textSize", 8, 40, 14))
        local brFontValues, brFontOrder = CUI.BuildFontDropdownData()
        addSlot({
            type = "dropdown",
            text = "Battle Res Font",
            values = brFontValues,
            order = brFontOrder,
            getValue = function()
                local profile = brDB()
                return (profile and profile.font) or "__global"
            end,
            setValue = function(val)
                local profile = brDB()
                if not profile then return end
                profile.font = val
                if _G._CUI_BattleRes_Apply then _G._CUI_BattleRes_Apply() end
            end,
        })
        addSlot({
            type = "dropdown",
            text = "Battle Res Outline",
            values = {
                ["__global"] = { text = "CUI Global Default" },
                ["none"] = { text = "Drop Shadow" },
                ["outline"] = { text = "Outline" },
                ["thick"] = { text = "Thick Outline" },
            },
            order = { "__global", "none", "outline", "thick" },
            getValue = function()
                local profile = brDB()
                return (profile and profile.outlineMode) or "__global"
            end,
            setValue = function(val)
                local profile = brDB()
                if not profile then return end
                profile.outlineMode = val
                if _G._CUI_BattleRes_Apply then _G._CUI_BattleRes_Apply() end
            end,
        })
        addSlot(blSize("Bloodlust Duration Size", "durationSize", 8, 30, 12))
        addSlot(blSize("Bloodlust Count Size", "countSize", 8, 20, 11))
    end
    addSlot({
        type = "slider",
        text = "Movement Alert Text Size",
        min = 8,
        max = 72,
        step = 1,
        tooltip = "Sizes the movement alert's free text, bar number and icon countdown. Switching the alert's Display Mode re-seeds this value.",
        getValue = function()
            local db = _G._CUI_MovementAlert_DB and _G._CUI_MovementAlert_DB()
            local ma = db and db.profile and db.profile.movementAlert
            return (ma and ma.textSize) or 24
        end,
        setValue = function(val)
            local db = _G._CUI_MovementAlert_DB and _G._CUI_MovementAlert_DB()
            local ma = db and db.profile and db.profile.movementAlert
            if not ma then return end
            ma.textSize = val
            if CUI._applyMovementAlert then CUI._applyMovementAlert() end
            if CUI._applyTimeSpiral then CUI._applyTimeSpiral() end
            if CUI._applyGateway then CUI._applyGateway() end
        end,
    })
    for i = 1, #slots, 2 do
        _, height = W:DualRow(hostFrame, cursorY, slots[i], slots[i + 1] or BLANK())
        cursorY = cursorY - height
    end
    return cursorY
end

local function TileChat(hostFrame, cursorY, W, tile)
    local mod = NS(tile.folder)
    local _, height
    if not mod then
        _, height = W:DualRow(hostFrame, cursorY, ModuleOutlineCfg(tile.folder, tile.display), BLANK())
        cursorY = cursorY - height
        return NoteRow(
            hostFrame,
            cursorY,
            CUI.Lf("Enable %1$s to edit its text settings.", CUI.L(tile.display))
        )
    end
    local CHAT = mod.ECHAT
    local function saved() return _G._CUCHAT_DB and _G._CUCHAT_DB.profile and _G._CUCHAT_DB.profile.chat end
    local fontValues, fontOrder = CUI.BuildFontDropdownData()
    -- Edit box picker: same faces plus a "Chat Font" inherit entry first,
    -- mirroring the module's own dropdown.
    local ebValues, ebOrder = CUI.BuildFontDropdownData()
    ebValues["__chat"] = { text = "Chat Font" }
    table.insert(ebOrder, 1, "__chat")
    local function ChatReload(msg)
        CUI:ShowConfirmPopup({
            title = "Reload Required",
            message = msg,
            confirmText = "Reload Now",
            cancelText = "Later",
            reload = true,
        })
    end
    _, height = W:DualRow(hostFrame, cursorY, ModuleOutlineCfg(tile.folder, tile.display), {
        type = "dropdown",
        text = "Chat Font",
        values = fontValues,
        order = fontOrder,
        getValue = function()
            local profile = saved()
            return (profile and profile.font) or "__global"
        end,
        setValue = function(val)
            local profile = saved()
            if not profile then return end
            profile.font = val
            ChatReload("Font changed. A UI reload is needed to apply the new font.")
        end,
    })
    cursorY = cursorY - height
    _, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Chat Outline Mode",
        values = {
            ["__global"] = { text = "CUI Global Default" },
            ["none"] = { text = "Drop Shadow" },
            ["outline"] = { text = "Outline" },
            ["thick"] = { text = "Thick Outline" },
        },
        order = { "__global", "none", "outline", "thick" },
        getValue = function()
            local profile = saved()
            return (profile and profile.outlineMode) or "__global"
        end,
        setValue = function(val)
            local profile = saved()
            if not profile then return end
            profile.outlineMode = val
            ChatReload("Outline mode changed. A UI reload is needed to apply.")
        end,
    }, {
        type = "slider",
        text = "Chat Font Size",
        min = 8,
        max = 27,
        step = 1,
        getValue = function()
            local profile = saved()
            if profile and profile.chatFontSize then return profile.chatFontSize end
            local castFrame = _G.ChatFrame1
            if castFrame and castFrame.GetFont then
                local _, fh = castFrame:GetFont()
                if fh and fh > 0 then return math.floor(fh + 0.5) end
            end
            return 14
        end,
        setValue = function(val)
            local profile = saved()
            if not profile then return end
            profile.chatFontSize = val
            if CHAT and CHAT.ApplyChatFontSize then CHAT.ApplyChatFontSize(val) end
        end,
    })
    cursorY = cursorY - height
    -- Blizzard Style shows Blizzard's own chat tabs (their stock font), so the
    -- tab font row hides there; Classic's painted tabs still use it.
    local BS = CUI.BlizzStyle
    local function TabFontGate(rowConf)
        if BS and BS.Active("chat") == "blizzard" then BS.Gate("chat", rowConf) end
        return rowConf
    end
    _, height = W:DualRow(
        hostFrame,
        cursorY,
        TabFontGate({
            type = "dropdown",
            text = "Tab Font",
            tooltip = "The tabs' font.",
            values = fontValues,
            order = fontOrder,
            getValue = function()
                local profile = saved()
                return (profile and profile.tabFont) or "__global"
            end,
            setValue = function(val)
                local profile = saved()
                if not profile then return end
                profile.tabFont = val
                if CHAT and CHAT.ApplyTabAppearance then CHAT.ApplyTabAppearance() end
                if CHAT and CHAT.ApplyTabLayout then CHAT.ApplyTabLayout() end
            end,
        }),
        TabFontGate({
            type = "slider",
            text = "Tab Font Size",
            tooltip = "How big the tab text is.",
            min = 8,
            max = 24,
            step = 1,
            getValue = function()
                local profile = saved()
                return (profile and profile.tabFontSize) or 11
            end,
            setValue = function(val)
                local profile = saved()
                if not profile then return end
                profile.tabFontSize = val
                if CHAT and CHAT.ApplyTabAppearance then CHAT.ApplyTabAppearance() end
                if CHAT and CHAT.ApplyTabLayout then CHAT.ApplyTabLayout() end
            end,
        })
    )
    cursorY = cursorY - height
    _, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Edit Box Font",
        tooltip = "The font of the box you type in.",
        values = ebValues,
        order = ebOrder,
        getValue = function()
            local profile = saved()
            return (profile and profile.editBoxFont) or "__chat"
        end,
        setValue = function(val)
            local profile = saved()
            if not profile then return end
            profile.editBoxFont = val
            if CHAT and CHAT.ApplyFonts then CHAT.ApplyFonts() end
        end,
    }, {
        type = "slider",
        text = "Edit Box Font Size",
        tooltip = "How big the text you type is.",
        min = 8,
        max = 24,
        step = 1,
        getValue = function()
            local profile = saved()
            if profile and profile.editBoxFontSize then return profile.editBoxFontSize end
            if FCF_GetChatWindowInfo then
                local _, sz = FCF_GetChatWindowInfo(1)
                if sz and sz > 0 then return math.floor(sz + 0.5) end
            end
            return 12
        end,
        setValue = function(val)
            local profile = saved()
            if not profile then return end
            profile.editBoxFontSize = val
            if CHAT and CHAT.ApplyFonts then CHAT.ApplyFonts() end
        end,
    })
    cursorY = cursorY - height
    return cursorY
end

local function TileMythicTimer(hostFrame, cursorY, W, tile)
    local mod = NS(tile.folder)
    local _, height
    if not mod then
        _, height = W:DualRow(hostFrame, cursorY, ModuleOutlineCfg(tile.folder, tile.display), BLANK())
        cursorY = cursorY - height
        return NoteRow(
            hostFrame,
            cursorY,
            CUI.Lf("Enable %1$s to edit its text settings.", CUI.L(tile.display))
        )
    end
    local function saved() return _G._CUMT_AceDB and _G._CUMT_AceDB.profile end
    local function MTApply()
        if _G._CUMT_ApplyTimer then _G._CUMT_ApplyTimer() end
    end
    local function sizeSlider(labelText, key, minV, maxV, def, fallbackKey)
        return {
            type = "slider",
            text = labelText,
            min = minV,
            max = maxV,
            step = 1,
            getValue = function()
                local profile = saved()
                if not profile then return def end
                return profile[key] or (fallbackKey and profile[fallbackKey]) or def
            end,
            setValue = function(val)
                local profile = saved()
                if not profile then return end
                profile[key] = val
                MTApply()
            end,
        }
    end
    local function subSizeSlider(labelText, getT, minV, maxV, def, key, applyName)
        return {
            type = "slider",
            text = labelText,
            min = minV,
            max = maxV,
            step = 1,
            getValue = function()
                local tbl = getT()
                return (tbl and tbl[key]) or def
            end,
            setValue = function(val)
                local tbl = getT()
                if not tbl then return end
                tbl[key] = val
                local func = mod[applyName]
                if func then
                    func()
                else
                    MTApply()
                end
            end,
        }
    end
    local function tsb()
        local profile = saved()
        return profile and profile.tsb
    end
    local function tfbT()
        local profile = saved()
        return profile and profile.tfb and profile.tfb.target
    end
    local function tfbF()
        local profile = saved()
        return profile and profile.tfb and profile.tfb.focus
    end
    local function kt()
        local profile = saved()
        return profile and profile.kickTracker
    end
    local fontValues, fontOrder = CUI.BuildFontDropdownData()
    _, height = W:DualRow(hostFrame, cursorY, ModuleOutlineCfg(tile.folder, tile.display), {
        type = "dropdown",
        text = "Timer Font",
        tooltip = "Typeface for the M+ timer clock. Every other Mythic+ text uses the module font.",
        values = fontValues,
        order = fontOrder,
        getValue = function()
            local profile = saved()
            return (profile and profile.timerFont) or "__global"
        end,
        setValue = function(val)
            local profile = saved()
            if not profile then return end
            profile.timerFont = val
            MTApply()
        end,
    })
    cursorY = cursorY - height
    _, height = W:DualRow(
        hostFrame,
        cursorY,
        sizeSlider("Title Size", "titleSize", 8, 24, 16),
        sizeSlider("Affix Size", "affixSize", 6, 20, 12)
    )
    cursorY = cursorY - height
    _, height = W:DualRow(
        hostFrame,
        cursorY,
        sizeSlider("Timer Size", "timerTextSize", 10, 32, 20),
        sizeSlider("Objectives Size", "objectivesSize", 8, 20, 12)
    )
    cursorY = cursorY - height
    _, height = W:DualRow(
        hostFrame,
        cursorY,
        sizeSlider("+3 Threshold Text Size", "thresholdPlusThreeSize", 6, 20, 12, "thresholdSize"),
        sizeSlider("+2 Threshold Text Size", "thresholdPlusTwoSize", 6, 20, 12, "thresholdSize")
    )
    cursorY = cursorY - height
    _, height = W:DualRow(
        hostFrame,
        cursorY,
        sizeSlider("+1 Threshold Text Size", "thresholdPlusOneSize", 6, 20, 12, "thresholdSize"),
        sizeSlider("Enemy Forces Text Size", "enemyForcesTextSize", 8, 24, 12, "objectivesSize")
    )
    cursorY = cursorY - height
    _, height = W:DualRow(
        hostFrame,
        cursorY,
        subSizeSlider("Cast Bars Name Size", tsb, 6, 20, 10, "nameSize", "TSB_Refresh"),
        subSizeSlider("Cast Bars Timer Size", tsb, 6, 20, 10, "timerSize", "TSB_Refresh")
    )
    cursorY = cursorY - height
    _, height = W:DualRow(
        hostFrame,
        cursorY,
        subSizeSlider("Cast Bars Target Size", tsb, 6, 20, 10, "targetSize", "TSB_Refresh"),
        subSizeSlider("Target Cast Bar Name Size", tfbT, 6, 22, 11, "nameSize", "TFB_Refresh")
    )
    cursorY = cursorY - height
    _, height = W:DualRow(
        hostFrame,
        cursorY,
        subSizeSlider("Target Cast Bar Timer Size", tfbT, 6, 22, 11, "timerSize", "TFB_Refresh"),
        subSizeSlider("Target Cast Bar Target Size", tfbT, 6, 20, 10, "targetSize", "TFB_Refresh")
    )
    cursorY = cursorY - height
    _, height = W:DualRow(
        hostFrame,
        cursorY,
        subSizeSlider("Focus Cast Bar Name Size", tfbF, 6, 22, 11, "nameSize", "TFB_Refresh"),
        subSizeSlider("Focus Cast Bar Timer Size", tfbF, 6, 22, 11, "timerSize", "TFB_Refresh")
    )
    cursorY = cursorY - height
    _, height = W:DualRow(
        hostFrame,
        cursorY,
        subSizeSlider("Focus Cast Bar Target Size", tfbF, 6, 20, 10, "targetSize", "TFB_Refresh"),
        subSizeSlider("Kick Tracker Timer Size", kt, 6, 24, 11, "timerSize", "KT_Refresh")
    )
    cursorY = cursorY - height
    _, height = W:DualRow(
        hostFrame,
        cursorY,
        subSizeSlider("Kick Tracker Bar Name Size", kt, 6, 24, 11, "barNameSize", "KT_Refresh"),
        subSizeSlider("Kick Tracker Bar Timer Size", kt, 6, 24, 11, "barTimerSize", "KT_Refresh")
    )
    cursorY = cursorY - height
    return cursorY
end

local function TileDamageMeters(hostFrame, cursorY, W, tile)
    local mod = NS(tile.folder)
    local _, height
    if not mod then
        _, height = W:DualRow(hostFrame, cursorY, ModuleOutlineCfg(tile.folder, tile.display), BLANK())
        cursorY = cursorY - height
        return NoteRow(
            hostFrame,
            cursorY,
            CUI.Lf("Enable %1$s to edit its text settings.", CUI.L(tile.display))
        )
    end
    local function saved() return _G._CUDM_DB and _G._CUDM_DB.profile and _G._CUDM_DB.profile.dm end
    _, height = W:DualRow(hostFrame, cursorY, ModuleOutlineCfg(tile.folder, tile.display), {
        type = "slider",
        text = "Header Text Size",
        min = 8,
        max = 18,
        step = 1,
        getValue = function()
            local profile = saved()
            return (profile and profile.hdrFontSize) or 11
        end,
        setValue = function(val)
            local profile = saved()
            if not profile then return end
            profile.hdrFontSize = val
            if mod.ApplyHeader then mod.ApplyHeader() end
        end,
    })
    cursorY = cursorY - height
    local function barSize(labelText, key)
        return {
            type = "slider",
            text = labelText,
            min = 8,
            max = 18,
            step = 1,
            getValue = function()
                local profile = saved()
                return (profile and (profile[key] or profile.fontSize)) or 11
            end,
            setValue = function(val)
                local profile = saved()
                if not profile then return end
                profile[key] = val
                if mod.RefreshMeter then mod.RefreshMeter() end
            end,
        }
    end
    _, height = W:DualRow(
        hostFrame,
        cursorY,
        barSize("Bar Left Text Size", "leftFontSize"),
        barSize("Bar Right Text Size", "rightFontSize")
    )
    cursorY = cursorY - height
    _, height = W:DualRow(hostFrame, cursorY, {
        type = "slider",
        text = "Standalone Timer Size",
        min = 10,
        max = 40,
        step = 1,
        getValue = function()
            local profile = saved()
            return (profile and profile.standaloneTimerSize) or 26
        end,
        setValue = function(val)
            local profile = saved()
            if not profile then return end
            profile.standaloneTimerSize = val
            if mod.ApplySATimer then mod.ApplySATimer() end
        end,
    }, {
        type = "slider",
        text = "Spell History Text Size",
        min = 8,
        max = 16,
        step = 1,
        getValue = function()
            local profile = saved()
            local sh = profile and profile.spellHistory
            return (sh and sh.textSize) or 11
        end,
        setValue = function(val)
            local profile = saved()
            if not (profile and profile.spellHistory) then return end
            profile.spellHistory.textSize = val
            if mod.ApplySpellHistory then mod.ApplySpellHistory() end
        end,
    })
    cursorY = cursorY - height
    return cursorY
end

local function TileBags(hostFrame, cursorY, W, tile)
    local mod = NS(tile.folder)
    local _, height
    if not mod then
        _, height = W:DualRow(hostFrame, cursorY, ModuleOutlineCfg(tile.folder, tile.display), BLANK())
        cursorY = cursorY - height
        return NoteRow(
            hostFrame,
            cursorY,
            CUI.Lf("Enable %1$s to edit its text settings.", CUI.L(tile.display))
        )
    end
    local function saved() return CUI._bagsDB and CUI._bagsDB.profile end
    local function TextSizes()
        if _G.CUI_Bags and _G.CUI_Bags.RefreshTextSizes then _G.CUI_Bags:RefreshTextSizes() end
        if _G.CUI_BankFrame and _G.CUI_BankFrame.RefreshTextSizes then _G.CUI_BankFrame:RefreshTextSizes() end
    end
    local function sizeSlider(labelText, key, minV, maxV, def, applyFn)
        return {
            type = "slider",
            text = labelText,
            min = minV,
            max = maxV,
            step = 1,
            getValue = function()
                local profile = saved()
                return (profile and profile[key]) or def
            end,
            setValue = function(val)
                local profile = saved()
                if not profile then return end
                profile[key] = val
                applyFn()
            end,
        }
    end
    _, height = W:DualRow(
        hostFrame,
        cursorY,
        ModuleOutlineCfg(tile.folder, tile.display),
        sizeSlider("Category Title Size", "bagCatTitleSize", 8, 16, 11, function()
            if _G.CUI_Bags and _G.CUI_Bags.RefreshInventory then _G.CUI_Bags:RefreshInventory() end
        end)
    )
    cursorY = cursorY - height
    _, height = W:DualRow(
        hostFrame,
        cursorY,
        sizeSlider("Item Count Text Size", "bagCountFontSize", 8, 16, 11, TextSizes),
        sizeSlider("Item Level Text Size", "itemlevelFontSize", 8, 16, 12, TextSizes)
    )
    cursorY = cursorY - height
    _, height = W:DualRow(
        hostFrame,
        cursorY,
        sizeSlider("Set Name Text Size", "bagSetNameFontSize", 7, 14, 9, TextSizes),
        sizeSlider("BoE / Warbound Text Size", "bagBindTypeFontSize", 8, 16, 11, TextSizes)
    )
    cursorY = cursorY - height
    _, height = W:DualRow(
        hostFrame,
        cursorY,
        sizeSlider("List Text Size", "bagListFontSize", 8, 16, 11, function()
            if _G.CUI_Bags and _G.CUI_Bags.RefreshInventory then _G.CUI_Bags:RefreshInventory() end
            if _G.CUI_BankFrame and _G.CUI_BankFrame.RefreshBank then _G.CUI_BankFrame:RefreshBank() end
        end),
        BLANK()
    )
    cursorY = cursorY - height
    return cursorY
end

local function TileMinimap(hostFrame, cursorY, W, tile)
    local mod = NS(tile.folder)
    local _, height
    if not mod then
        _, height = W:DualRow(hostFrame, cursorY, ModuleOutlineCfg(tile.folder, tile.display), BLANK())
        cursorY = cursorY - height
        return NoteRow(
            hostFrame,
            cursorY,
            CUI.Lf("Enable %1$s to edit its text settings.", CUI.L(tile.display))
        )
    end
    local function saved() return _G._CUMM_DB and _G._CUMM_DB.profile and _G._CUMM_DB.profile.minimap end
    local function sizeSlider(labelText, key, minV, maxV, def)
        return {
            type = "slider",
            text = labelText,
            min = minV,
            max = maxV,
            step = 1,
            getValue = function()
                local profile = saved()
                return (profile and profile[key]) or def
            end,
            setValue = function(val)
                local profile = saved()
                if not profile then return end
                profile[key] = val
                if _G._CUMM_ApplyMinimap then _G._CUMM_ApplyMinimap() end
            end,
        }
    end
    -- Scale rows apply exactly like the module's own cogs: SetScale on the
    -- text block's host frame, no full minimap reapply.
    local function scale(labelText, key, def, frameName)
        return {
            type = "slider",
            text = labelText,
            min = 0.5,
            max = 2.0,
            step = 0.01,
            getValue = function()
                local profile = saved()
                return (profile and profile[key]) or def
            end,
            setValue = function(val)
                local profile = saved()
                if not profile then return end
                profile[key] = val
                local frame = _G[frameName]
                if frame and frame.SetScale then frame:SetScale(val) end
            end,
        }
    end
    _, height = W:DualRow(
        hostFrame,
        cursorY,
        ModuleOutlineCfg(tile.folder, tile.display),
        sizeSlider("FPS Text Size", "fpsTextSize", 8, 30, 12)
    )
    cursorY = cursorY - height
    _, height = W:DualRow(
        hostFrame,
        cursorY,
        sizeSlider("Difficulty Text Size", "diffTextSize", 8, 24, 12),
        scale("Clock Scale", "clockScale", 1.15, "_CUBS_ClockBg")
    )
    cursorY = cursorY - height
    _, height = W:DualRow(
        hostFrame,
        cursorY,
        scale("Zone Text Scale", "locationScale", 1.15, "_CUBS_LocationBg"),
        scale("Coordinates Scale", "coordsScale", 1.0, "_CUBS_CoordFrame")
    )
    cursorY = cursorY - height
    _, height = W:DualRow(hostFrame, cursorY, scale("FPS/MS Scale", "fpsScale", 1.0, "_CUBS_FpsBg"), BLANK())
    cursorY = cursorY - height
    return cursorY
end

local function TileQuestTracker(hostFrame, cursorY, W, tile)
    local mod = NS(tile.folder)
    local _, height
    if not mod then
        _, height = W:DualRow(hostFrame, cursorY, ModuleOutlineCfg(tile.folder, tile.display), BLANK())
        cursorY = cursorY - height
        return NoteRow(
            hostFrame,
            cursorY,
            CUI.Lf("Enable %1$s to edit its text settings.", CUI.L(tile.display))
        )
    end
    -- Stock styles keep Blizzard's own tracker text (sized by Edit Mode's
    -- Text Size), so none of these settings apply there.
    local BS = CUI.BlizzStyle
    if BS and BS.Get("questtracker") then
        return NoteRow(
            hostFrame,
            cursorY,
            CUI.Lf(
                "%1$s is active: the tracker keeps Blizzard's own text.",
                CUI.L(BS.Label("questtracker"))
            )
        )
    end
    local function saved() return _G._CUQT_DB and _G._CUQT_DB.profile and _G._CUQT_DB.profile.questTracker end
    local function QTApply()
        local EQT = mod.EQT
        if not EQT then return end
        if EQT.RestyleAll then EQT.RestyleAll() end
        if EQT.UpdateVisibility then EQT.UpdateVisibility() end
        if EQT.ApplyBackground then EQT.ApplyBackground() end
        if EQT.RefreshStateDriver then EQT.RefreshStateDriver() end
    end
    local function sizeSlider(labelText, key, def)
        return {
            type = "slider",
            text = labelText,
            min = 8,
            max = 24,
            step = 1,
            getValue = function()
                local profile = saved()
                return (profile and profile[key]) or def
            end,
            setValue = function(val)
                local profile = saved()
                if not profile then return end
                profile[key] = val
                QTApply()
            end,
        }
    end
    local fontValues, fontOrder = CUI.BuildFontDropdownData()
    _, height = W:DualRow(hostFrame, cursorY, ModuleOutlineCfg(tile.folder, tile.display), {
        type = "dropdown",
        text = "Quest Tracker Font",
        tooltip = "Typeface for the quest tracker. This module-local pick wins over the module font override above.",
        values = fontValues,
        order = fontOrder,
        getValue = function()
            local profile = saved()
            return (profile and profile.font) or "__global"
        end,
        setValue = function(val)
            local profile = saved()
            if not profile then return end
            profile.font = val
            -- The custom tracker (WoW Forever) restyles live.
            if mod.UseCustomTracker and mod.UseCustomTracker() then
                CUI.InvalidateFontCache()
                QTApply()
                return
            end
            AskFontReload()
        end,
    })
    cursorY = cursorY - height
    _, height = W:DualRow(
        hostFrame,
        cursorY,
        sizeSlider("Header Font Size", "headerFontSize", 13),
        sizeSlider("Title Font Size", "titleFontSize", 12)
    )
    cursorY = cursorY - height
    if mod.UseCustomTracker and mod.UseCustomTracker() then
        _, height = W:DualRow(
            hostFrame,
            cursorY,
            sizeSlider("Objective Font Size", "objectiveFontSize", 10),
            sizeSlider("Zone Header Font Size", "customZoneFontSize", 13)
        )
        cursorY = cursorY - height
    else
        _, height =
            W:DualRow(hostFrame, cursorY, sizeSlider("Objective Font Size", "objectiveFontSize", 10), BLANK())
        cursorY = cursorY - height
    end
    return cursorY
end

local function TileBlizzardSkin(hostFrame, cursorY, W, tile)
    local mod = NS(tile.folder)
    local _, height
    if not mod then
        _, height = W:DualRow(hostFrame, cursorY, ModuleOutlineCfg(tile.folder, tile.display), BLANK())
        cursorY = cursorY - height
        return NoteRow(
            hostFrame,
            cursorY,
            CUI.Lf("Enable %1$s to edit its text settings.", CUI.L(tile.display))
        )
    end
    _, height = W:DualRow(hostFrame, cursorY, ModuleOutlineCfg(tile.folder, tile.display), {
        type = "slider",
        text = "Tooltip Font Size Scale",
        min = 0.7,
        max = 1.5,
        step = 0.05,
        format = "%.0f%%",
        displayMul = 100,
        tooltip = "Scales the text size of Blizzard tooltips.",
        getValue = function() return (CludesUIDB and CludesUIDB.tooltipFontScale) or 1.0 end,
        setValue = function(val)
            if not CludesUIDB then CludesUIDB = {} end
            CludesUIDB.tooltipFontScale = val
        end,
    })
    cursorY = cursorY - height
    local enchSizeCfg = {
        type = "slider",
        text = "Enchant Text Size",
        min = 6,
        max = 20,
        step = 1,
        getValue = function() return (CludesUIDB and CludesUIDB.charSheetEnchantSize) or 9 end,
        setValue = function(val)
            if not CludesUIDB then CludesUIDB = {} end
            CludesUIDB.charSheetEnchantSize = val
            if CUI._refreshCharSheetSlotLabels then CUI._refreshCharSheetSlotLabels() end
        end,
    }
    -- WoW Forever has no skyriding (the Dragon Riding HUD never loads there),
    -- so the enchant size sits alone in the last row.
    _, height = W:DualRow(hostFrame, cursorY, enchSizeCfg, CUI.IS_FOREVER and BLANK() or {
        type = "slider",
        text = "Dragonriding Speed Text Size",
        min = 6,
        max = 32,
        step = 1,
        getValue = function()
            local p = mod.edrDB and mod.edrDB.profile and mod.edrDB.profile.speedText
            return (p and p.size) or 12
        end,
        setValue = function(val)
            local p = mod.edrDB and mod.edrDB.profile and mod.edrDB.profile.speedText
            if not p then return end
            p.size = val
            if mod.edrRedraw then mod.edrRedraw() end
        end,
    })
    cursorY = cursorY - height
    return cursorY
end

local function TileDataBars(hostFrame, cursorY, W, tile)
    local mod = NS(tile.folder)
    local _, height = W:DualRow(hostFrame, cursorY, ModuleOutlineCfg(tile.folder, tile.display), BLANK())
    cursorY = cursorY - height
    if mod then
        cursorY = LinkRow(
            hostFrame,
            cursorY,
            "Text Scale (per data bar)",
            tile.folder,
            "Info Bar",
            "BAR SETTINGS",
            "Text Scale"
        )
    else
        cursorY = NoteRow(
            hostFrame,
            cursorY,
            CUI.Lf("Enable %1$s to edit its text settings.", CUI.L(tile.display))
        )
    end
    return cursorY
end

local function TileFontOnly(hostFrame, cursorY, W, tile)
    local _, height = W:DualRow(hostFrame, cursorY, ModuleOutlineCfg(tile.folder, tile.display), BLANK())
    return cursorY - height
end

-- Combat and world text: engine globals that only apply at login, plus the
-- floating combat text scale CVar. The font pickers stay on their original
-- pages (curated list + logout flow); this card mirrors the size and links
-- to the rest.
local function TileCombatText(hostFrame, cursorY, W, tile)
    local _, height = W:DualRow(hostFrame, cursorY, {
        type = "slider",
        text = "Combat Text Size",
        tooltip = "How big the combat text is.",
        min = 0.5,
        max = 2.5,
        step = 0.1,
        getValue = function() return tonumber(GetCVar("WorldTextScale_v2")) or 1 end,
        setValue = function(val)
            if InCombatLockdown() then return end
            val = math.floor(val * 10 + 0.5) / 10
            CUI.SetCVar("WorldTextScale_v2", val)
        end,
    }, BLANK())
    cursorY = cursorY - height
    cursorY = LinkRow(
        hostFrame,
        cursorY,
        "Combat Text Font (logout required)",
        GLOBAL_KEY,
        "General",
        "COMBAT",
        "Combat Text Font"
    )
    return cursorY
end

-------------------------------------------------------------------------------
--  Card list -- ADDON_ROSTER order (Party Mode is skipped: it has no font
--  consumers and no addon key in the per-module font system), plus the
--  synthetic Combat Text card at the end.
-------------------------------------------------------------------------------

-- Modules whose stock styles (Style page key) keep Blizzard's own text, so the
-- card's module font override is blocked while one of them is active.
local TILE_STYLE_KEYS = {
    CludesUIQuestTracker = "questtracker",
    CludesUIFriends = "friends",
}

local TILE_BUILDERS = {
    CludesUIActionBars = { TileActionBars, "Bar button text, XP/Rep bar text" },
    CludesUINameplates = { TileNameplates, "Names, cast bar and aura text on nameplates" },
    CludesUIUnitFrames = { TileUnitFrames, "Health, power, cast bar and aura text (per unit)" },
    CludesUIRaidFrames = { TileRaidFrames, "Names, health and indicator text on raid and party frames" },
    CludesUICooldownManager = {
        TileCooldownManager,
        "Icon duration, stacks, keybinds and tracking bar text",
    },
    CludesUIResourceBars = { TileResourceBars, "Health, power, class resource, cast and totem bar text" },
    CludesUIAuraBuffReminders = { TileAuraBuffReminders, "Reminder names, item counts and the mana warning" },
    CludesUIQoL = {
        TileQoL,
        CUI.IS_FOREVER and "Alert and tracker text" or "Alerts, trackers, battle res and popup text",
    },
    CludesUIForeverEssentials = { TileFontOnly, "Font face and outline only" },
    CludesUIBlizzardSkin = {
        TileBlizzardSkin,
        CUI.IS_FOREVER and "Tooltip text scale and enchant text"
            or "Tooltip text scale, enchant text and dragonriding speed",
    },
    CludesUIFriends = { TileFontOnly, "Font face and outline only" },
    CludesUIMythicTimer = { TileMythicTimer, "M+ timer, objectives, thresholds and spell bar text" },
    CludesUIQuestTracker = { TileQuestTracker, "Tracker font and per-line text sizes" },
    CludesUIMinimap = { TileMinimap, "Clock, zone, coordinates, FPS and difficulty text" },
    CludesUIChat = { TileChat, "Chat windows, tabs and the input field" },
    CludesUIDamageMeters = { TileDamageMeters, "Window header, bar and timer text" },
    CludesUIBags = { TileBags, "Item count, item level, category and label text" },
    CludesUIDataBars = { TileDataBars, "Per-bar text scale" },
    CludesUIQuickdraw = { TileFontOnly, "Font face and outline only" },
    CludesUISimpleLootCouncil = { TileFontOnly, "Font face and outline only" },
}

local function BuildTileList()
    local tiles = {}
    local roster = CUI.ADDON_ROSTER or {}
    for _, record in ipairs(roster) do
        local def = not record.comingSoon and TILE_BUILDERS[record.folder]
        if def then
            tiles[#tiles + 1] = {
                key = record.folder,
                folder = record.folder,
                display = record.display,
                desc = def[2],
                buildContent = def[1],
                hasFontDD = true,
            }
        end
    end
    tiles[#tiles + 1] = {
        key = "combatText",
        display = "Combat & World Text",
        desc = "Floating combat text and world name text (engine settings)",
        buildContent = TileCombatText,
        hasFontDD = false,
    }
    return tiles
end

-------------------------------------------------------------------------------
--  Font card (adapted from the Window Skins card pattern)
-------------------------------------------------------------------------------

local function BuildFontCard(hostFrame, cursorY, W, tile)
    return CUI.BuildModuleCard(hostFrame, cursorY, W, tile, {
        enabled = (not tile.folder) or NS(tile.folder) ~= nil,
        expanded = _ftExpanded,
        descW = 440,
        -- "Aa" glyph rendered in the module's currently resolved face, so the
        -- card shows the active font at a glance.
        glyph = function(heading, enabled)
            local Pix = CUI.PanelPP
            local icon = CreateFrame("Frame", nil, heading)
            Pix.Size(icon, 26, 20)
            Pix.Point(icon, "LEFT", heading, "LEFT", 14, 0)
            local glyphText = icon:CreateFontString(nil, "OVERLAY")
            glyphText:SetPoint("CENTER")
            local addonKey = tile.folder
                and CUI._folderToAddonKey
                and CUI._folderToAddonKey[tile.folder]
            local glyphPath = (CUI.GetFontPath(addonKey)) or "Fonts\\FRIZQT__.TTF"
            glyphText:SetFont(glyphPath, 15, "")
            glyphText:SetTextColor(1, 1, 1, enabled and 0.85 or 0.3)
            glyphText:SetText("Aa")
        end,
        -- Module font dropdown on the header: the per-module override layer
        -- (the old PER ADDON FONTS entry), editable without expanding the card.
        headerDD = tile.hasFontDD
                and function(heading)
                    local fontValues, fontOrder = CUI.BuildFontDropdownData()
                    local dropdown = CUI.BuildDropdownControl(
                        heading,
                        190,
                        heading:GetFrameLevel() + 2,
                        fontValues,
                        fontOrder,
                        function()
                            local record = FindModuleFontEntry(tile.folder)
                            return (record and record.font) or "__global"
                        end,
                        function(val)
                            local record = FindModuleFontEntry(tile.folder)
                            local current = (record and record.font) or "__global"
                            if val == current then return end
                            if val == "__global" then
                                if record then
                                    record.font = "__global"
                                    PruneModuleFontEntry(tile.folder)
                                end
                            else
                                EnsureModuleFontEntry(tile.folder, tile.display).font = val
                            end
                            AskFontReload()
                        end
                    )
                    CUI.PanelPP.Point(dropdown, "RIGHT", heading, "RIGHT", -44, 0)
                    -- A module whose stock style keeps Blizzard's own text: the override
                    -- has nothing to apply to there.
                    local styleKey = TILE_STYLE_KEYS[tile.folder]
                    if styleKey and CUI.BlizzStyle then
                        CUI.BlizzStyle.BlockInline(styleKey, dropdown)
                    end
                    return dropdown
                end
            or nil,
    })
end

-------------------------------------------------------------------------------
--  Deep-link pre-hook: expand every card before a jump into the Fonts page,
--  so section scroll/highlight can land inside card content (same pattern as
--  the Window Skins page).
-------------------------------------------------------------------------------
do
    local origNav = CUI.NavigateToElementSettings
    function CUI:NavigateToElementSettings(moduleName, page, sectionName, preSelectFn, highlightText)
        -- The original refuses in combat: no page state changes then.
        if InCombatLockdown() then
            return origNav(self, moduleName, page, sectionName, preSelectFn, highlightText)
        end
        if moduleName == GLOBAL_KEY and page == PAGE_FONTS and (sectionName or highlightText) then
            local changed = false
            for _, tile in ipairs(BuildTileList()) do
                if not _ftExpanded[tile.key] then
                    _ftExpanded[tile.key] = true
                    changed = true
                end
            end
            if changed and CUI.InvalidatePageCache then CUI:InvalidatePageCache() end
        end
        return origNav(self, moduleName, page, sectionName, preSelectFn, highlightText)
    end
end

-------------------------------------------------------------------------------
--  Page builder (dispatched from the Global Settings module registration in
--  CUI__General_Options.lua)
-------------------------------------------------------------------------------

function _G._CUI_BuildFontsPage(page, hostFrame, yOffset)
    local W = CUI.Widgets
    local Pix = CUI.PanelPP
    local cursorY = yOffset
    local _, height

    hostFrame._showRowDivider = true

    -- Reverse folder -> addonKey map for the card glyphs (built once).
    if not CUI._folderToAddonKey then
        local map = {}
        for key, folder in pairs(CUI._addonKeyToFolder or {}) do
            map[folder] = key
        end
        CUI._folderToAddonKey = map
    end

    -------------------------------------------------------------------
    --  GLOBAL FONT section (moved from the old Fonts & Colors page)
    -------------------------------------------------------------------
    _, height = W:SectionHeader(hostFrame, "GLOBAL FONT", cursorY)
    cursorY = cursorY - height

    -- Glyph-restricted locales (CJK, Cyrillic): most bundled fonts are Latin-only and cannot render the script, so the picker
    -- offers "System Default" plus external SharedMedia fonts (which may carry the right glyphs).
    local localeRestricted = CUI.LOCALE_FONT_FALLBACK ~= nil
    -- ruRU is only PARTLY restricted: the faces listed in FONT_CYRILLIC carry the full
    -- Cyrillic block (verified cmap), so they are offered as normal entries and
    -- ResolveFontName honours them. CJK keeps the old System-Default-only picker.
    local localeCyrillic = localeRestricted and CUI.LOCALE_SCRIPT == "cyrillic"

    local fontDropValues = {}
    local fontDropOrder = {}
    if localeRestricted then
        fontDropValues[CUI.SYSTEM_FONT_KEY] =
            { text = "System Default", font = CUI.LOCALE_FONT_FALLBACK }
        fontDropOrder[#fontDropOrder + 1] = CUI.SYSTEM_FONT_KEY
        if localeCyrillic then
            -- Cyrillic-capable bundled faces, kept in FONT_ORDER sequence so the
            -- picker matches the Latin-locale ordering. Latin-only bundles stay out.
            local FONT_DIR_CYR = CUI.MEDIA_PATH .. "fonts\\"
            local sepDone = false
            for _, name in ipairs(CUI.FONT_ORDER) do
                local cyrFile = name ~= "---" and CUI.FONT_CYRILLIC[name] and CUI.FONT_FILES[name]
                if cyrFile then
                    if not sepDone then
                        fontDropOrder[#fontDropOrder + 1] = "---"
                        sepDone = true
                    end
                    fontDropValues[name] = {
                        text = (CUI.FONT_DISPLAY_NAMES and CUI.FONT_DISPLAY_NAMES[name]) or name,
                        font = FONT_DIR_CYR .. cyrFile,
                    }
                    fontDropOrder[#fontDropOrder + 1] = name
                end
            end
        else
            -- Expressway is the informed Latin opt-in, using a distinct sentinel key so the untouched default still maps to System Default.
            fontDropValues[CUI.EXPRESSWAY_FORCED_KEY] = {
                text = "Expressway (Latin only)",
                font = CUI.MEDIA_PATH .. "fonts\\Expressway.TTF",
            }
            fontDropOrder[#fontDropOrder + 1] = CUI.EXPRESSWAY_FORCED_KEY
        end
        CUI.AppendExternalSharedMediaFonts(fontDropValues, fontDropOrder)
    else
        -- Blizzard Default first: the client's own standard UI font. The
        -- glyph-restricted branch above skips it (its "System Default" entry
        -- already is the client's own font).
        fontDropValues[CUI.BLIZZARD_FONT_KEY] =
            { text = "Blizzard Default", font = CUI.GetBlizzardFontPath() }
        fontDropOrder[#fontDropOrder + 1] = CUI.BLIZZARD_FONT_KEY
        fontDropOrder[#fontDropOrder + 1] = "---"
        local FONT_DIR_GLOBAL = CUI.MEDIA_PATH .. "fonts\\"
        for _, name in ipairs(CUI.FONT_ORDER) do
            if name == "---" then
                fontDropOrder[#fontDropOrder + 1] = "---"
            else
                local filePath = CUI.FONT_BLIZZARD[name]
                    or (FONT_DIR_GLOBAL .. (CUI.FONT_FILES[name] or "Expressway.TTF"))
                local displayName = (CUI.FONT_DISPLAY_NAMES and CUI.FONT_DISPLAY_NAMES[name])
                    or name
                fontDropValues[name] = { text = displayName, font = filePath }
                fontDropOrder[#fontDropOrder + 1] = name
            end
        end
        CUI.AppendSharedMediaFonts(fontDropValues, fontDropOrder, { keyByName = true })
    end

    local outlineModeValues = {
        ["none"] = { text = "Drop Shadow" },
        ["outline"] = { text = "Outline" },
        ["thick"] = { text = "Thick Outline" },
    }
    local outlineModeOrder = { "none", "outline", "thick" }

    -- Global Font (+ cog: Apply to All Game Text) | Outline Mode
    local globalFontRow
    globalFontRow, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Global Font",
        tooltip = "The font used across CludesUI.",
        values = fontDropValues,
        order = fontDropOrder,
        getValue = function()
            local g = CUI.GetFontsDB().global or CUI.DEFAULT_FONT_NAME
            -- Cyrillic locales list Expressway as a normal entry, so an older
            -- __expressway opt-in collapses onto it (same file) instead of falling
            -- through to System Default and misreporting the active face.
            if localeCyrillic and g == CUI.EXPRESSWAY_FORCED_KEY then return "Expressway" end
            -- In glyph-restricted locales a stored Latin-only bundled font maps to the System Default entry; a chosen SM font shows as-is.
            if localeRestricted and not fontDropValues[g] then return CUI.SYSTEM_FONT_KEY end
            return g
        end,
        setValue = function(val)
            CUI.GetFontsDB().global = val
            local refreshList = CUI._widgetRefreshList
            if refreshList then
                for i2 = 1, #refreshList do
                    refreshList[i2]()
                end
            end
            AskFontReload()
        end,
    }, {
        type = "dropdown",
        text = "Outline Mode",
        tooltip = "Controls the text rendering style used across all UI elements",
        values = outlineModeValues,
        order = outlineModeOrder,
        getValue = function()
            local val = CUI.GetFontsDB().outlineMode or "none"
            if val == "shadow" then val = "none" end
            return val
        end,
        setValue = function(val)
            CUI.GetFontsDB().outlineMode = val
            local refreshList = CUI._widgetRefreshList
            if refreshList then
                for i2 = 1, #refreshList do
                    refreshList[i2]()
                end
            end
            AskFontReload()
        end,
    })
    cursorY = cursorY - height
    if not CUI._prebuilding then
        CUI.BuildInlineCog(globalFontRow._leftRegion, {
            title = "Global Font",
            rows = {
                {
                    type = "toggle",
                    label = "Apply to All Game Text",
                    tooltip = "Applies your Global Font to Blizzard's default game text (menus, tooltips, quest log, character panes, and more). Requires a UI reload.",
                    get = function() return CUI.GetFontsDB().applyToAllGameText == true end,
                    set = function(val)
                        CUI.GetFontsDB().applyToAllGameText = val and true or false
                        AskFontReload()
                    end,
                },
            },
        })
    end

    -- Outline Icon Text: per-module control over icon-overlay text (stack
    -- counts, durations, keybinds). Checked (default) forces a crisp outline;
    -- unchecked follows Outline Mode above. Left slot = per-module checkbox
    -- dropdown, right = Disable Slug Outline: per-profile (rides profile
    -- export/import), drops the SLUG token from every outline (body/icon/aura
    -- text, Outline Mode itself). Off by default; needs reload.
    local oitRow
    oitRow, height = W:DualRow(hostFrame, cursorY, {
        type = "dropdown",
        text = "Outline Icon Text",
        tooltip = "Forces a crisp outline on icon text (stack counts, durations, keybinds). Uncheck a module to make its icon text follow the Outline Mode setting above instead.",
        values = { ["_placeholder"] = "..." },
        order = { "_placeholder" },
        getValue = function() return "_placeholder" end,
        setValue = function() end,
    }, {
        type = "toggle",
        text = "Disable Slug Outline",
        tooltip = "Slug outline renders higher quality outlines compared to the base WoW outline mode but may make outline effects appear slightly thicker.",
        getValue = function() return CUI.IsSlugDisabled() end,
        setValue = function(val)
            CUI.GetFontsDB().neverShowSlug = val and true or false
            AskFontReload()
        end,
    })
    cursorY = cursorY - height
    if not CUI._prebuilding then
        local oitItems = {
            { key = "actionBars", label = "Action Bars Icons" },
            { key = "unitFrames", label = "Unit Frames Icons" },
            { key = "cdm", label = "CDM Icons" },
            { key = "raidFrames", label = "Group Frames Icons" },
            { key = "bags", label = "Bags Icons" },
        }
        local region = oitRow._leftRegion
        if region._control then region._control:Hide() end
        local checkDrop, cbDDRefresh = CUI.BuildVisOptsCBDropdown(
            region,
            220,
            region:GetFrameLevel() + 2,
            oitItems,
            function(keyName)
                local fontsDB = CUI.GetFontsDB()
                local tbl = (fontsDB and fontsDB.outlineIconText)
                    or (CludesUIDB and CludesUIDB.outlineIconText)
                return not (tbl and tbl[keyName] == false)
            end,
            function(keyName, val)
                -- Per-profile (rides profile export); seed from the legacy account-global table on first write so other modules' choices carry over.
                local fontsDB = CUI.GetFontsDB()
                if type(fontsDB.outlineIconText) ~= "table" then
                    local tbl = {}
                    local seed = CludesUIDB and CludesUIDB.outlineIconText
                    if type(seed) == "table" then
                        for kk, vv in pairs(seed) do
                            tbl[kk] = vv
                        end
                    end
                    fontsDB.outlineIconText = tbl
                end
                fontsDB.outlineIconText[keyName] = val and true or false
                -- Reload prompt from setFn, NOT an onChanged callback: a non-nil onChanged re-anchors the open CB dropdown menu absolutely (for page rebuilds), visibly shifting it.
                AskFontReload()
            end
        )
        Pix.Point(checkDrop, "RIGHT", region, "RIGHT", -20, 0)
        region._control = checkDrop
        region._lastInline = nil
        CUI.RegisterWidgetRefresh(cbDDRefresh)
    end

    -- Name Font: text floating above characters/NPCs. Independent of
    -- Global Font, modelled on Combat Text Font: both drive a Blizzard global the engine reads once at login (UNIT_NAME_FONT /
    -- DAMAGE_TEXT_FONT), so both need a LOGOUT (not FontReload's reload) and treat "Blizzard Default" as leave-it-alone. Applied in CludesUI_Startup.lua.
    local NAME_FONT_DEFAULT = "__default"
    local nameFontValues, nameFontOrder = {}, {}
    do
        -- Same faces as Global Font (SharedMedia included) but a private copy: prepending a default entry to the shared tables would leak into the Global Font list too.
        nameFontValues[NAME_FONT_DEFAULT] = { text = "Blizzard Default", font = "Fonts\\FRIZQT__.TTF" }
        nameFontOrder[1] = NAME_FONT_DEFAULT
        nameFontOrder[2] = "---"
        for _, keyName in ipairs(fontDropOrder) do
            -- Skip the Blizzard Default sentinel: this list's own "__default"
            -- entry means "leave the engine's name font untouched", which is
            -- the same visual result with the correct do-nothing semantics.
            -- Collapse the separator that followed it so no doubled divider.
            if keyName ~= CUI.BLIZZARD_FONT_KEY then
                if keyName ~= "---" or nameFontOrder[#nameFontOrder] ~= "---" then
                    nameFontOrder[#nameFontOrder + 1] = keyName
                end
                if keyName ~= "---" then nameFontValues[keyName] = fontDropValues[keyName] end
            end
        end
    end

    -- Name Font | Game Text Scale. Game Text Scale multiplies Blizzard
    -- font-object sizes in the same login pass as Apply to All Game Text
    -- (CludesUI.ApplyGlobalFontToGameText) but works with or without the
    -- face swap. 100 = untouched (stored as nil); the pass runs once from
    -- native sizes, so no compounding. The reload prompt is drag-aware:
    -- mid-drag setValues only mark pending (CludesUI._sliderDragging, the
    -- same contract CommitInput reads), and EndDrag's final setValue runs with
    -- the counter already cleared, so one prompt fires per drag -- or
    -- immediately for a typed value.
    do
        local gtsPending
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Name Font",
            -- Coloured inline rather than via tooltipOpts.color, which would tint the explanation red along with the warning.
            tooltip = "Sets the font for the names that float above players, NPCs and enemies in the world.\n\nSeparate from Global Font - changing this does not affect the rest of the UI, and Global Font does not affect it.\n\nBlizzard Default leaves the name text completely untouched.\n\n|cffff4d4dRequires a re-log or restart of WoW to take effect.|r",
            values = nameFontValues,
            order = nameFontOrder,
            getValue = function()
                local num = CUI.GetFontsDB().unitNameFont
                if not num or not nameFontValues[num] then return NAME_FONT_DEFAULT end
                return num
            end,
            setValue = function(val)
                local fdb = CUI.GetFontsDB()
                -- nil, not the sentinel, so startup code can tell "leave Blizzard alone" without knowing the key.
                fdb.unitNameFont = (val ~= NAME_FONT_DEFAULT) and val or nil
                fdb.unitNameFontPath = (val ~= NAME_FONT_DEFAULT) and nameFontValues[val].font or nil
                -- No apply call: the engine already cached the global, so the change lands next login (same as Combat Text Font).
                CUI:ShowConfirmPopup({
                    title = "Logout Required",
                    message = "Name font changes require a logout to character select to take effect. This is a WoW engine limitation.",
                    confirmText = "Okay",
                    cancelText = "Later",
                })
            end,
        }, {
            type = "slider",
            text = "Game Text Scale",
            min = 75,
            max = 125,
            step = 5,
            tooltip = "Scales the size of Blizzard's default game text (menus, tooltips, quest log, and more). Requires a UI reload.",
            getValue = function() return CUI.GetFontsDB().gameTextScale or 100 end,
            setValue = function(val)
                local fontsDB = CUI.GetFontsDB()
                local changed = (fontsDB.gameTextScale or 100) ~= val
                if changed then fontsDB.gameTextScale = val ~= 100 and val or nil end
                if CUI._sliderDragging then
                    if changed then gtsPending = true end
                    return
                end
                if changed or gtsPending then
                    gtsPending = nil
                    AskFontReload()
                end
            end,
        })
        cursorY = cursorY - height
    end

    _, height = W:Spacer(hostFrame, cursorY, 20)
    cursorY = cursorY - height

    -------------------------------------------------------------------
    --  MODULE FONTS -- one expandable card per module. The header dropdown
    --  is the per-module font override; expanded content mirrors the
    --  module's own text settings.
    -------------------------------------------------------------------
    -- Orientation note above the section title: everything on this page is a
    -- write-through mirror, not a separate setting. Sized host + single
    -- TOPLEFT point per the search framework's geometry contract (raw
    -- parent-level regions are invisible to the search and float over
    -- filtered results).
    local introHost = CreateFrame("Frame", nil, hostFrame)
    Pix.Size(introHost, hostFrame:GetWidth() - CUI.CONTENT_PAD * 2, 44)
    -- 10px breathing room above; the host's slack below is trimmed the same
    -- amount so the section title sits tighter under the text.
    introHost:SetPoint("TOPLEFT", hostFrame, "TOPLEFT", CUI.CONTENT_PAD, cursorY - 10)
    local intro = CUI.MakeFont(introHost, 14, nil, 1, 1, 1, 0.65)
    intro:SetPoint("TOPLEFT", introHost, "TOPLEFT", 0, -2)
    intro:SetPoint("TOPRIGHT", introHost, "TOPRIGHT", 0, -2)
    intro:SetJustifyH("LEFT")
    intro:SetWordWrap(true)
    intro:SetText(
        CUI.L("A quick view of every font setting in one place.")
            .. "\n"
            .. CUI.L("These are the same settings found on each module's own pages, not separate ones.")
    )
    cursorY = cursorY - 48

    _, height = W:SectionHeader(hostFrame, "MODULE FONTS", cursorY)
    cursorY = cursorY - height

    for _, tile in ipairs(BuildTileList()) do
        cursorY = BuildFontCard(hostFrame, cursorY, W, tile)
    end

    -- Framework contract: return the positive total content height
    -- (contentFrame:SetHeight consumes it), never the final negative y.
    return math.abs(cursorY)
end
