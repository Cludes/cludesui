if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_PlayerAuraBars_ManagerPages.lua
--  Single "Player Aura Bars" tab: sidebar lists the two fixed default bars
--  (Buffs, Debuffs -- always present, not deletable) plus any custom bars,
--  with "Add Buff Bar" / "Add Debuff Bar" actions. Selecting any entry shows
--  its settings in the detail pane, split into ASSIGNED (content selection,
--  model-specific) / CORE / DISPLAY sections (RaidFrames layout pattern) --
--  default and custom bars share the same field-building helpers since both
--  are just cfg tables with the same shape (see
--  CUI_PlayerAuraBars_Config.lua's DefaultBuffsCfg/DefaultDebuffsCfg and
--  the custom-bar CRUD in CUI_PlayerAuraBars_Filters.lua).
--
-- redesign: default Buffs bar unified onto the same BM2/filters
--  model custom buff bars already used (Filters dropdown + Extra Spells
--  dropdown, ns.PAB_Filters registry) -- classFilters no longer applies to
--  ANY buff-side bar. Debuff bars (default + custom) keep the class-token
--  model, now with a "Show All Debuffs" toggle that bypasses classFilters
--  without discarding it (mirrors RaidFrames' DebuffManager). The Filter
--  Editor modal (ns.PABMP_ShowFilterEditor) is implemented below -- see its
--  doc comment for what was deliberately NOT ported from RaidFrames' BM2
--  (curated preset spell database, own-only tracking).
-------------------------------------------------------------------------------

local mod = CludesUI._ModuleNS["CludesUIUnitFrames"] -- module namespace (published by the module at its load)
if not mod then
    return
end -- module disabled: no options page

-- Page reuse: the manager root and the Filter Editor are kept for the session
-- (Pool.Kept below) and every frame this file builds under them goes through
-- the options frame pool (CludesUI_FramePool.lua), which hands the next
-- render the previous render's frames reset to new; on any other parent it
-- is the plain CreateFrame.
local CreateFrame = CludesUI._Pool.CreateFrame
-- The pool's other calls this file makes, read once here as CreateFrame is:
-- the page path never calls the pool through its public slot, which
-- another addon could replace.
local PoolKept = CludesUI._Pool.Kept
local PoolOwned = CludesUI._Pool.Owned
-- The root's render, for the refresh callbacks it registers (_BeginRootRender).
local PAB_RENDER_KEY = "CludesUIUnitFrames::Player Aura Bars::root"

local floor, max = math.floor, math.max

local function L(s)
    return CludesUI.L(s) or s
end

local TILE_H = 58

-- Forward-declared: defined below (verbatim port of RaidFrames' editor scroll helper),
-- used by WrapCompensatedBody -- which is itself defined ABOVE that point in the file
-- -- to give the detail pane's body a real scrollbar (fix: the body previously had no
-- scroll mechanism at all, just silent SetClipsChildren cropping; content taller than
-- the visible area was simply unreachable, a pre-existing gap that only became visible
-- once the new preview box pushed settings fields below the fold).
local AttachEditorScroll

-- Selection state: {kind="buff"|"debuff", id=barId|"default"} or nil.
local barPick = { kind = "buff", id = "default" }
-- Editing-spec bucket: "allspecs" (the legacy bar arrays), a group bucket
-- key, or a concrete "spec<ID>". Session-sticky like pabSel.
local pabSpecSel = "allspecs"
-- Inherited-bar selection ({kind, group, id}); wins over pabSel while set.
local inheritPick = nil

-- Exported selection setter for What's New deep links (same pattern as
-- CludesUI._setUnitFrameUnit / _setMiniUnit): the sidebar selection is a
-- session-sticky file local defaulting to the Buffs bar, so a nav targeting a
-- debuff-side section must pre-select the right pane or the section scan
-- silently misses.
--
-- `bucket` = the bar's owning editing-spec bucket, passed by unlock mode's
-- "Element Options". The view is session-sticky too and BuildPage validates the
-- selection against the current view's bucket only, so a bar from another bucket
-- would be dropped back to the default tile. Same move as the inherited pane's
-- "Edit in <group>" link.
CludesUI._setPABSelection = function(kindName, ident, bucket)
    barPick = { kind = kindName, id = ident or "default" }
    inheritPick = nil
    if bucket then
        pabSpecSel = bucket
    elseif
        barPick.id == "default"
        and pabSpecSel ~= "allspecs"
        and not (type(pabSpecSel) == "string" and pabSpecSel:match("^spec%d"))
    then
        -- The two built-in bars are All Specs content: they are listed in the All
        -- Specs view and in concrete spec views, but never in a group bucket, so a
        -- stale group view would drop this selection. Concrete spec views list
        -- them, so those stay untouched.
        pabSpecSel = "allspecs"
    end
end

local SPEC_GROUP_INFO = CludesUI.SPEC_GROUP_BUCKET_INFO
-- Filter Editor's own selected-filter state (independent of pabSel, since
-- the editor is a modal that can be opened from any buff-side detail pane).
local pabFilterSel
-- Preserves the spell-list scroll position across Rebuild() calls (add/ remove/rename
-- all rebuild the whole editor) -- same reasoning as BM2's fdScrollPos.
local pabFilterScrollPos = 0

-- Standard WoW anchor points -- verified against AK's own usage:
-- style.durationPoint/stackPoint feed SetPoint(point, button, point, ...)
-- directly (CludesUI_AuraKit.lua's ApplyStyleToRegions), NOT the old
-- module's lowercase "top"/"bottom" convention.
local AURA_POINT_VALUES = {
    TOP = "Top",
    BOTTOM = "Bottom",
    LEFT = "Left",
    RIGHT = "Right",
    TOPLEFT = "Top Left",
    TOPRIGHT = "Top Right",
    BOTTOMLEFT = "Bottom Left",
    BOTTOMRIGHT = "Bottom Right",
    CENTER = "Center",
}
local AURA_POINT_ORDER = {
    "TOP",
    "BOTTOM",
    "LEFT",
    "RIGHT",
    "TOPLEFT",
    "TOPRIGHT",
    "BOTTOMLEFT",
    "BOTTOMRIGHT",
    "CENTER",
}
-- "Default" = the house icon-text rule: forced crisp outline unless the
-- user unchecks Unit Frames in Global Settings' "Outline Icon Text".
local FONT_OUTLINE_VALUES = {
    default = "Default",
    none = "Drop Shadow",
    outline = "Outline",
    thick = "Thick Outline",
}
local FONT_OUTLINE_ORDER = { "default", "none", "outline", "thick" }
local GROW_DIR_VALUES = {
    LEFT = "Left",
    RIGHT = "Right",
    CENTER_HORIZONTAL = "Centered Horizontal",
    CENTER_VERTICAL = "Centered Vertical",
    UP = "Up",
    DOWN = "Down",
}
local GROW_DIR_ORDER = { "LEFT", "RIGHT", "CENTER_HORIZONTAL", "CENTER_VERTICAL", "UP", "DOWN" }
local ICON_WRAP_VALUES = { LEFT = "Left", RIGHT = "Right", UP = "Up", DOWN = "Down" }
local ICON_WRAP_ORDER = { "LEFT", "RIGHT", "UP", "DOWN" }

-- Cropped uses a rectangular icon without the masked shapes' overhang.
local SHAPE_VALUES = {
    none = "None",
    cropped = "Cropped",
    square = "Square",
    circle = "Circle",
    csquare = "Curved Square",
    diamond = "Diamond",
    hexagon = "Hexagon",
    portrait = "Portrait",
    shield = "Shield",
}
local SHAPE_ORDER =
    { "none", "cropped", "---", "square", "circle", "csquare", "diamond", "hexagon", "portrait", "shield" }
-- A masked shape, ringed by its own border; None and Cropped keep the square
-- border and its pixel size.
local function IsMaskShape(shape)
    return shape ~= nil and shape ~= "none" and shape ~= "cropped"
end

-- Levels map 1:1 to Action Bars' ns.BORDER_THICKNESS regular values (thin=1, normal=2,
-- heavy=3, strong=4), so cfg.borderSize stays the same plain 0-4 number used elsewhere
-- (regular border thickness, per-filter Icon Effects override).
local BORDER_SIZE_LEVELS = { "none", "thin", "normal", "heavy", "strong" }
local BORDER_SIZE_VALUES =
    { none = "None", thin = "Thin", normal = "Normal", heavy = "Heavy", strong = "Strong" }
local BORDER_SIZE_NUM = { none = 0, thin = 1, normal = 2, heavy = 3, strong = 4 }
local BORDER_SIZE_KEY = { [0] = "none", [1] = "thin", [2] = "normal", [3] = "heavy", [4] = "strong" }
-- Levels with no distinct shape-border rendering (PabShapeBorderSize collapses them
-- all to "off"); Strong is the only one worth keeping enabled once a shape is active.
local BORDER_SIZE_SHAPE_DISABLED = { thin = true, normal = true, heavy = true }
local BORDER_SIZE_DEFAULT_SHAPE = "strong"

-- Every PAB bar (default Buffs/Debuffs plus any custom ones), for the sync-icon
-- "Apply to: All | Multiple" rows. entry.cfg is the live table, not a copy.
local function PabAllBarEntries()
    local s = mod.db and mod.db.profile and mod.db.profile.playerAuraBars
    if not s then
        return {}
    end
    local entries = {}
    entries[#entries + 1] =
        { key = "buffs", label = "Buffs", isBuff = true, cfg = mod.PAB_DefaultBuffsCfg(s) }
    entries[#entries + 1] =
        { key = "debuffs", label = "Debuffs", isBuff = false, cfg = mod.PAB_DefaultDebuffsCfg(s) }
    local buffBars = mod.PAB_CustomBuffBars and mod.PAB_CustomBuffBars()
    if buffBars then
        for idx = 1, #buffBars do
            local barConf = buffBars[idx]
            entries[#entries + 1] = {
                key = "custombuff_" .. barConf.id,
                label = barConf.name or "Buff Bar",
                isBuff = true,
                cfg = barConf,
            }
        end
    end
    local debuffBars = mod.PAB_CustomDebuffBars and mod.PAB_CustomDebuffBars()
    if debuffBars then
        for idx = 1, #debuffBars do
            local barConf = debuffBars[idx]
            entries[#entries + 1] = {
                key = "customdebuff_" .. barConf.id,
                label = barConf.name or "Debuff Bar",
                isBuff = false,
                cfg = barConf,
            }
        end
    end
    return entries
end

-- Which PabAllBarEntries() row a given (cfg, isBuff) pair is.
local function PabBarKeyOf(rowConf, buffBar)
    local s = mod.db and mod.db.profile and mod.db.profile.playerAuraBars
    if s then
        if rowConf == mod.PAB_DefaultBuffsCfg(s) then
            return "buffs"
        end
        if rowConf == mod.PAB_DefaultDebuffsCfg(s) then
            return "debuffs"
        end
    end
    if rowConf.id then
        return (buffBar and "custombuff_" or "customdebuff_") .. rowConf.id
    end
    return ""
end

-- Restyles one bar live after the caller has written fields onto entry.cfg.
local function PabApplyBarEntry(record)
    if record.key == "buffs" or record.key == "debuffs" then
        if mod.PAB_Restyle then
            mod.PAB_Restyle()
        end
        if mod.PAB_ApplyLiveConfig then
            mod.PAB_ApplyLiveConfig(record.isBuff)
        end
    elseif record.isBuff then
        if mod.PAB_ReloadCustomBuffBar then
            mod.PAB_ReloadCustomBuffBar(record.cfg.id)
        end
    else
        if mod.PAB_ReloadCustomDebuffBar then
            mod.PAB_ReloadCustomDebuffBar(record.cfg.id)
        end
    end
end

-- Native AuraContainerSortMethod/AuraContainerSortDirection enum names
-- (in-game dump: AuraContainerSortMethod = {Default=0,
-- BigDefensive=1, UnitFrameDebuff=2, ImportantOnly=3, Expiration=4,
-- ExpirationOnly=5, Name=6, NameOnly=7, AuraInstanceIDOnly=8},
-- AuraContainerSortDirection = {Normal=0, Reverse=1}). Curated down
-- to the 4 values whose names are unambiguous for an aura bar.
-- "Expiration"/"Name" are saved under these keys but resolve to the native
-- ExpirationOnly/NameOnly at apply time (ResolveSortMethod in the PAB module): the
-- plain variants rank player-cast/canApplyAura ahead of the named criterion.
-- BigDefensive/UnitFrameDebuff/AuraInstanceIDOnly are other-UI-specific variants
-- and are left out of this dropdown.
--
-- "Important" (native key ImportantOnly) sorts by `C_Spell.IsSpellImportant` (verified
-- against Blizzard's PTR source, AuraUtil.lua's ImportantOnlyAuraCompare) -- a native
-- per-spell flag, not dispel-type- based and not debuff-specific, so it's equally
-- meaningful for buffs. (Originally hidden from the buff-side dropdown under a wrong
-- assumption that it meant "dispellable debuffs first"; corrected, now shared.)
local SORT_METHOD_VALUES = {
    Default = "Default",
    ImportantOnly = "Important",
    Expiration = "Expiration",
    Name = "Name",
}
local SORT_METHOD_ORDER = { "Default", "Expiration", "Name", "ImportantOnly" }
local SORT_DIR_VALUES = { Normal = "Normal", Reverse = "Reverse" }
local SORT_DIR_ORDER = { "Normal", "Reverse" }

local DISPEL_COLOR_ROWS = {
    { key = "dispelColorMagic", label = "Magic", fallback = { 0.349, 0.475, 1.0 } },
    { key = "dispelColorCurse", label = "Curse", fallback = { 0.636, 0.0, 0.64 } },
    { key = "dispelColorDisease", label = "Disease", fallback = { 0.671, 0.384, 0.098 } },
    { key = "dispelColorPoison", label = "Poison", fallback = { 0.0, 0.706, 0.286 } },
    { key = "dispelColorBleed", label = "Bleed", fallback = { 0.75, 0.15, 0.15 } },
}

-- ns.PAB_AllPresetSpells() intentionally contains resolved `alts` as their own entries
-- (rank/talent-variant spellIDs of the same buff family, see that function's own doc
-- comment) -- correct for PAB_ResolveSpells (any of them tracks the buff), but every UI
-- list drawing from that universe (Extra Spells' Presets group, Filter Editor's Search
-- Spells) showed them as same-named duplicate rows, which read as a bug rather than a
-- feature. Deduped here, display-only, by resolved spell name -- first (lowest) spellID
-- per name wins, matching table.sort's ascending id order. A spell whose name can't be
-- resolved yet (not cached client-side) falls back to its own id as the dedup key so it
-- never collapses into an unrelated entry.
local function DedupedPresetSpellUniverse()
    local universe = (mod.PAB_AllPresetSpells and mod.PAB_AllPresetSpells()) or {}
    local seenSet, result = {}, {}
    for idx = 1, #universe do
        local ident = universe[idx]
        local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(ident)
        local dedupKey = name or ("id:" .. ident)
        if not seenSet[dedupKey] then
            seenSet[dedupKey] = true
            result[#result + 1] = ident
        end
    end
    return result
end

-- Same display-only dedup pass, applied to the "Filters" assignment dropdown (ASSIGNED
-- BUFFS' Filters -- distinct from the Filter Editor's own sidebar list, which manages
-- the real filter objects individually and must NOT be deduped or renaming/deleting the
-- "hidden" duplicate becomes impossible). ns.PAB_Filters() can end up with same-named
-- entries (e.g. two user-created filters both left at the "New Filter" default, or
-- duplicate presets from an earlier import-migration bug) -- first (lowest id, i.e.
-- oldest) entry per name wins. Ordering is Buff Manager PARITY (newer request,
-- supersedes the old always-alphabetical rule): preset filters first in the curated
-- catalogue order (Defensives leads), then user filters in creation (list) order --
-- applied to both the Filters assignment dropdown (via DedupedFilterItems below) and
-- the Filter Editor's own sidebar (ns.PABMP_ShowFilterEditor). Always returns a FRESH
-- copy -- ns.PAB_Filters() hands back the live persisted list
-- (CUI_PlayerAuraBars_Filters.lua's ns.PAB_Filters, `store.list` directly),
-- so sorting in place would silently reorder SavedVariables every time the editor is
-- opened. Rank is matched by NAME, not the preset flag, so filters copied from the
-- Buff Manager order identically on both sides.
local function SortFiltersCanonical(entries)
    local rank = {}
    local BP = CludesUI.BUFF_PRESETS
    if BP and BP.filters then
        for idx = 1, #BP.filters do
            rank[BP.filters[idx].name] = idx
        end
    end
    local result, place = {}, {}
    for idx = 1, #entries do
        result[idx] = entries[idx]
        place[entries[idx]] = idx
    end
    table.sort(result, function(lhs, rhs)
        return (rank[lhs.name] or (1000 + place[lhs])) < (rank[rhs.name] or (1000 + place[rhs]))
    end)
    return result
end

local function DedupedFilterItems()
    local filters = (mod.PAB_Filters and mod.PAB_Filters()) or {}
    local seenSet, result = {}, {}
    for idx = 1, #filters do
        local f = filters[idx]
        if not seenSet[f.name] then
            seenSet[f.name] = true
            result[#result + 1] = f
        end
    end
    return SortFiltersCanonical(result)
end

-- Custom buff bar sidebar tile subtitle -- was a flat "N spells" (the
-- RESOLVED spell count, filters expanded), which didn't tell the user
-- WHICH selection mode a bar was actually in. Now reflects the bar's
-- actual ASSIGNED BUFFS config instead of the resolved count:
--   Show All Buffs on:  "Show All Buffs" (+ " + N spells" if Extra Spells
--     also has entries -- Extra Spells stays active/visible regardless of
--     Show All Buffs, see BuildAssignedBuffsFields' exRow, so it's still
--     meaningful to surface here).
--   Show All Buffs off: first 3 selected filters' names, comma-joined, in
--     ns.PAB_Filters() list order (map iteration via bar.filters alone is
--     unordered -- would make the tile flicker between refreshes). If 3+
--     filters are selected the 3rd shown name is truncated to its first 3
--     characters + "..." as an overflow hint. Falls back to the Extra
--     Spells count when no filters are selected at all (e.g. a bar with
--     only Extra Spells and Show All Buffs off) -- the ASSIGNED count, not
--     the resolved one, which expands curated spell families.
local function TruncateFilterName(name)
    return (name or ""):sub(1, 3) .. "..."
end

-- Defined in CUI_PlayerAuraBars_Config.lua next to the cfg it
-- reads, so this page and the unlock-mode mover label cannot drift apart. The
-- module returns the raw English key; only the options page translates it.
local function DefaultBuffBarName(rowConf)
    return L(mod.PAB_DefaultBuffsName and mod.PAB_DefaultBuffsName(rowConf) or "Buffs")
end

local function BuildBuffBarSubtitle(barConf)
    local extraCount = barConf.spells and #barConf.spells or 0
    local hiddenCount = 0
    -- Presets only the other client offers are not listed here, so they do not count.
    if barConf.negFilters then
        for fid in pairs(barConf.negFilters) do
            if not mod.PAB_HiddenPresetFilter(fid) then
                hiddenCount = hiddenCount + 1
            end
        end
    end

    if barConf.showAllBuffs ~= false or barConf.hasDuration == true then
        local textObj = (barConf.showAllBuffs ~= false) and L("All Buffs") or L("Has Duration")
        if extraCount > 0 then
            textObj = textObj .. " + " .. extraCount .. " " .. L("spells")
        end
        if hiddenCount > 0 then
            textObj = textObj .. ", " .. hiddenCount .. " " .. L("hidden")
        end
        return textObj
    end

    local nameList, totalSelected = {}, 0
    if barConf.filters then
        local allFilters = mod.PAB_Filters and mod.PAB_Filters()
        if allFilters then
            for idx = 1, #allFilters do
                local f = allFilters[idx]
                if barConf.filters[f.id] then
                    totalSelected = totalSelected + 1
                    -- L() before the truncate below: preset filters carry raw
                    -- English names (see PAB's BM2_FILTER_SEED), and truncating
                    -- first would leave the tail untranslatable.
                    if #nameList < 3 then
                        nameList[#nameList + 1] = L(f.name)
                    end
                end
            end
        end
    end

    if #nameList == 0 then
        return tostring(extraCount) .. " " .. L("spells")
    end

    if totalSelected >= 3 then
        nameList[#nameList] = TruncateFilterName(nameList[#nameList])
    end

    local labelText = table.concat(nameList, ", ")
    if extraCount > 0 then
        labelText = labelText .. " + " .. extraCount .. " " .. L("spells")
    end
    if hiddenCount > 0 then
        labelText = labelText .. ", " .. hiddenCount .. " " .. L("hidden")
    end
    return labelText
end

-- Custom debuff bar sidebar tile subtitle -- same "reflect the actual
-- ASSIGNED DEBUFFS config" fix as BuildBuffBarSubtitle above, just for the
-- debuff shape (bar.showAllDebuffs + bar.classFilters, no filters/extra
-- spells concept on the debuff side -- custom debuff bars are pure
-- class-token selection, see ns.PAB_AddCustomDebuffBar).
local function BuildDebuffBarSubtitle(barConf)
    local nc = 0
    if barConf.classFilters then
        for _ in pairs(barConf.classFilters) do
            nc = nc + 1
        end
    end
    local hiddenCount = 0
    if barConf.negClassFilters then
        for _ in pairs(barConf.negClassFilters) do
            hiddenCount = hiddenCount + 1
        end
    end
    if barConf.showAllDebuffs ~= false then
        if hiddenCount > 0 then
            return L("All Debuffs") .. ", " .. hiddenCount .. " " .. L("hidden")
        end
        return L("All Debuffs")
    end
    local textObj = tostring(nc) .. " " .. (nc == 1 and L("class") or L("classes"))
    if hiddenCount > 0 then
        textObj = textObj .. ", " .. hiddenCount .. " " .. L("hidden")
    end
    return textObj
end

-------------------------------------------------------------------------------
--  Shared field builders -- used by BOTH the default bars and custom bars.
--  cfg is whatever table the caller wants read/written: DefaultBuffsCfg(s),
--  DefaultDebuffsCfg(s), or a custom bar object itself (custom bar objects
--  carry the same field names directly on themselves, see the CRUD comment
--  in CUI_PlayerAuraBars_Filters.lua). apply() is called after
--  every field edit; callers decide what that means for them (Restyle()+
--  ApplyLiveConfig() for default bars, PAB_ReloadCustomBuffBar/DebuffBar
--  for custom bars).
-------------------------------------------------------------------------------

-- Empty-selection warning for the buff/debuff Filters dropdowns: the shared
-- builder CludesUI.AttachEmptyFilterWarn (CludesUI_Widgets.lua), also
-- used by the RF Debuff Manager's base Filters dropdown. hasContentFn here
-- is the engine's own content predicate (broad mode / Show lane / Extra
-- Spells / enchants / fx-forced classes), so a bar that still renders
-- anything never warns.

-- "Assigned Buffs": Filters checkbox dropdown (references the shared PAB Filters
-- registry, CUI_PlayerAuraBars_Filters.lua) + Extra Spells checkbox
-- dropdown (direct SpellIDs, cfg.spells). Mirrors ns.BMP_BuildAssignedFilters
-- (CUI_RaidFrames_ManagerPages.lua) 1:1 in widget structure. Deliberately NOT a full
-- port: PAB has no curated preset-spell universe (see PAB_Filters' doc comment), so
-- the Extra Spells dropdown only ever lists the bar's own already-added spells under
-- "Selected" plus the "Custom Spell ID" action -- no "Presets" group, there is
-- nothing to browse. Used by BOTH the default Buffs bar and every custom buff bar
-- (unified onto one model).
local function BuildAssignedBuffsFields(widget, fontFile, startY, rowConf, applyFn, isDefault)
    -- Row accessors over conf: a key read (or its default) and written.
    local function ConfFieldGet(key)
        return function()
            return rowConf[key]
        end
    end
    local W = CludesUI.Widgets
    local Pix = CludesUI.PanelPP
    local _, hh = 0, 0
    local heading

    heading, hh = W:SectionHeader(widget, "ASSIGNED BUFFS", startY)
    startY = startY - hh
    -- The Move in Unlock Mode button on the bar's first section: the key reads
    -- the sidebar selection at the click, so it highlights the selected bar.
    CludesUI.BuildSectionUnlockJump(heading, {
        key = function()
            if barPick.id == "default" then
                return "PAB_Buffs"
            end
            return "PAB_CustomBuff_" .. barPick.id
        end,
    })

    -- "Filters": single unified checkbox dropdown -- pinned pseudo-filter
    -- rows above a divider, then the real (user-editable) PAB_Filters
    -- entries:
    --
    --   Edit Filters      (pinned top action)
    --   [ ] All Buffs     (cfg.showAllBuffs, nil == on)
    --   [ ] Has Duration  (cfg.hasDuration -- a broad-content mode of
    --                      its own, MUTUALLY EXCLUSIVE with All Buffs:
    --                      the catch-all narrowed to duration-carrying
    --                      buffs via candidateFilters.maxDuration)
    --   (weapon enchants have no row of their own: the default Buffs
    --    bar's enchant cells ride All Buffs / Has Duration --
    --    ns.PAB_EnchantsOn)
    --   ------------------ (isHeader divider)
    --   [ ] <real filters, alphabetical>
    --
    -- Real-filter rows are TWO-LANE (same model as every filter dropdown in the
    -- suite): the left checkbox SHOWS a filter (cfg.filters, add mode only -- while a
    -- broad mode is on everything already shows, so the lane is dimmed), the right red
    -- box HIDES it (cfg.negFilters -- catch-all excludeSpellIDs under a broad mode,
    -- dropped from the spells-group union in add mode; see BuffBarChain /
    -- PAB_ResolveSpells). Lanes are mutually exclusive per filter and PERSIST across
    -- mode flips. The pinned pseudo-filters are never locked and are not
    -- ns.PAB_Filters() entries, so they never appear in the Filter Editor sidebar.
    -- (An Own Only pseudo-filter was tried and removed: the PLAYER token did not
    -- filter reliably on live engine groups, and the filter registry covers the need
    -- better.)
    --
    -- Extra Spells (direct SpellIDs) shares this same row and stays
    -- additive in both modes -- see the RIGHT-region block below.
    local ffRow
    ffRow, hh = W:DualRow(widget, startY, {
        type = "dropdown",
        text = "Filters",
        values = { __placeholder = "..." },
        order = { "__placeholder" },
        getValue = function()
            return "__placeholder"
        end,
        setValue = function() end,
    }, {
        type = "dropdown",
        text = "Extra Spells",
        values = { __placeholder = "..." },
        order = { "__placeholder" },
        getValue = function()
            return "__placeholder"
        end,
        setValue = function() end,
    })
    startY = startY - hh

    local PAB_ALL_BUFFS_KEY, PAB_HAS_DURATION_KEY = "__allBuffs", "__hasDuration"

    -- Empty selections are LEGAL (user directive 2026-08-15, reversing the
    -- phase-2 no-empty rule on PAB): any content source can be unchecked,
    -- including the last one. AttachEmptyFilterWarn owns the loud feedback
    -- (red dropdown border + persistent bubble + close-pulse) while the bar
    -- displays nothing.
    local function BuffBarHasContent()
        if not mod.PAB_BuffBarHasContent then
            return true
        end
        if not mod.PAB_BuffBarHasContent(rowConf, isDefault) then
            return false
        end
        -- WoW Forever: visibleOnly counts only the Show-lane filters this client
        -- lists, so a bar whose sole content is a hidden retail preset warns.
        local visibleOnly = CludesUI.IS_FOREVER
            and rowConf.filters
            and rowConf.showAllBuffs == false
            and rowConf.hasDuration ~= true
            and not (rowConf.spells and #rowConf.spells > 0)
        if not visibleOnly then
            return true
        end
        for fid in pairs(rowConf.filters) do
            if not mod.PAB_HiddenPresetFilter(fid) then
                return true
            end
        end
        return false
    end

    -- LEFT: Filters checkbox dropdown, "Edit Filters" pinned top action.
    do
        local region = ffRow._leftRegion
        if region._control then
            region._control:Hide()
        end
        local function AllBuffsOn()
            return rowConf.showAllBuffs ~= false
        end
        local function BroadOn()
            return rowConf.showAllBuffs ~= false or rowConf.hasDuration == true
        end
        local function FilterItems()
            local filters = DedupedFilterItems()
            local itemList = {
                {
                    isTopAction = true,
                    label = "Edit Filters",
                    onClick = function()
                        mod.PABMP_ShowFilterEditor()
                    end,
                },
                -- Blacklist editing only matters while broad content is on
                -- (All Buffs / Has Duration); with neither, the bar shows
                -- only explicit picks and unchecking covers the need.
                {
                    isTopAction = true,
                    label = "Edit Blacklist",
                    lockedFn = function()
                        return rowConf.showAllBuffs == false and rowConf.hasDuration ~= true
                    end,
                    lockedTooltip = function()
                        return CludesUI.DisabledTooltip("All Buffs or Has Duration", "enabled")
                    end,
                    onClick = function()
                        CludesUI.ShowSpellBlacklistPopup({
                            title = "Buff Blacklist",
                            get = ConfFieldGet("blacklist"),
                            add = function(ident)
                                rowConf.blacklist = rowConf.blacklist or {}
                                rowConf.blacklist[ident] = true
                            end,
                            remove = function(ident)
                                if rowConf.blacklist then
                                    rowConf.blacklist[ident] = nil
                                    if not next(rowConf.blacklist) then
                                        rowConf.blacklist = nil
                                    end
                                end
                            end,
                            onChanged = function()
                                applyFn()
                            end,
                        })
                    end,
                },
                {
                    key = PAB_ALL_BUFFS_KEY,
                    label = "All Buffs",
                    tooltip = "Show every buff. Use the Hide lane below to remove specific filters.",
                },
                {
                    key = PAB_HAS_DURATION_KEY,
                    label = "Has Duration",
                    tooltip = "Show every buff that has a duration (hides permanent buffs). Use the Hide lane below to remove specific filters.",
                },
            }
            itemList[#itemList + 1] = { isHeader = true, label = "Show", rightLabel = "Hide" }
            for idx = 1, #filters do
                itemList[#itemList + 1] = {
                    key = filters[idx].id,
                    label = filters[idx].name,
                    dual = true,
                    showLockedFn = BroadOn,
                }
            end
            return itemList
        end
        local warnClosed
        local checkDrop, cbRefresh = CludesUI.BuildVisOptsCBDropdown(
            region,
            190,
            region:GetFrameLevel() + 2,
            FilterItems,
            function(keyName, neg)
                if keyName == PAB_ALL_BUFFS_KEY then
                    return AllBuffsOn()
                end
                if keyName == PAB_HAS_DURATION_KEY then
                    return rowConf.hasDuration == true
                end
                if neg then
                    local nf = rowConf.negFilters
                    return nf and nf[keyName] == true
                end
                local f = rowConf.filters
                return f and f[keyName] == true
            end,
            function(keyName, val, neg)
                if keyName == PAB_ALL_BUFFS_KEY then
                    rowConf.showAllBuffs = val
                    -- Mutually exclusive with Has Duration -- both are broad-content
                    -- modes. The show/hide lanes PERSIST across mode flips (the hide
                    -- lane subtracts in both modes; the show lane simply goes dormant
                    -- while broad content is on). Extra Spells stay untouched.
                    rowConf.hasDuration = nil
                    applyFn()
                    -- Non-force, same as every other row: the open menu
                    -- refreshes its own checks/locks in place, so a mode
                    -- flip must not tear the page down under it.
                    CludesUI:RefreshPage()
                    return
                end
                if keyName == PAB_HAS_DURATION_KEY then
                    rowConf.hasDuration = val or nil
                    -- Mutually exclusive with All Buffs (a broad-content mode of its
                    -- own); lanes persist, same as All Buffs.
                    if val then
                        rowConf.showAllBuffs = false
                    end
                    applyFn()
                    CludesUI:RefreshPage()
                    return
                end
                -- Two-lane real-filter write: checking one lane clears the other;
                -- emptied lane tables drop to nil (saved-variable hygiene).
                if neg then
                    rowConf.negFilters = rowConf.negFilters or {}
                    rowConf.negFilters[keyName] = val or nil
                    if not next(rowConf.negFilters) then
                        rowConf.negFilters = nil
                    end
                    if val and rowConf.filters then
                        rowConf.filters[keyName] = nil
                    end
                else
                    rowConf.filters = rowConf.filters or {}
                    rowConf.filters[keyName] = val or nil
                    if val and rowConf.negFilters then
                        rowConf.negFilters[keyName] = nil
                        if not next(rowConf.negFilters) then
                            rowConf.negFilters = nil
                        end
                    end
                end
                if rowConf.filters and not next(rowConf.filters) then
                    rowConf.filters = nil
                end
                applyFn()
                -- Non-force: runs only the registered lightweight refresh callbacks
                -- (e.g. the sidebar tile's subtitleFn) in-place, unlike
                -- RefreshPage(true) which would tear down and rebuild the whole page --
                -- and close this open dropdown mid multi-select.
                CludesUI:RefreshPage()
            end,
            nil,
            12,
            nil,
            nil,
            function()
                if warnClosed then
                    warnClosed()
                end
            end
        )
        Pix.Point(checkDrop, "RIGHT", region, "RIGHT", -20, 0)
        region._control = checkDrop
        region._lastInline = nil
        CludesUI.RegisterWidgetRefresh(cbRefresh)
        warnClosed = CludesUI.AttachEmptyFilterWarn(
            region,
            checkDrop,
            L("You are displaying NO buffs at all."),
            BuffBarHasContent
        )
    end

    -- RIGHT: Extra Spells checkbox dropdown (direct cfg.spells only, see
    -- doc comment above for why there is no "Presets" group here). Shares
    -- ffRow with Filters (redesign) instead of its own row.
    do
        local region = ffRow._rightRegion
        if region._control then
            region._control:Hide()
        end
        local function HasDirect(ident)
            local sp = rowConf.spells
            if not sp then
                return false
            end
            for idx = 1, #sp do
                if sp[idx] == ident then
                    return true
                end
            end
            return false
        end
        local function ShowCustomIdPopup()
            CludesUI:ShowInputPopup({
                title = L("Add Spell ID"),
                message = L("Enter the spell ID to track."),
                confirmText = L("Add"),
                cancelText = L("Cancel"),
                onConfirm = function(textValue)
                    local ident = tonumber(textValue or "")
                    if ident and ident > 0 and not HasDirect(ident) then
                        rowConf.spells = rowConf.spells or {}
                        rowConf.spells[#rowConf.spells + 1] = ident
                        applyFn()
                        CludesUI:RefreshPage(true)
                    end
                end,
            })
        end
        local function SpellEntry(ident)
            local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(ident)
            return {
                key = ident,
                label = (name or ("Spell " .. tostring(ident))),
                icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(ident),
            }
        end
        local function ByLabel(a, b)
            return a.label < b.label
        end
        local function ExtraItems()
            -- Spells already provided by ASSIGNED FILTERS' enabled spells
            -- are excluded from Presets (adding them as extras would be
            -- redundant) -- same exclusion BM2 applies.
            local covered = {}
            if rowConf.filters then
                for fid in pairs(rowConf.filters) do
                    local f = mod.PAB_GetFilter and mod.PAB_GetFilter(fid)
                    if f then
                        for ident, on in pairs(f.spells) do
                            if on and not mod.PAB_OtherClientSpell(f, ident) then
                                covered[ident] = true
                            end
                        end
                    end
                end
            end
            local universe = DedupedPresetSpellUniverse()
            local selected, rest = {}, {}
            local seen = {}
            local sp = rowConf.spells or {}
            for idx = 1, #sp do
                seen[sp[idx]] = true
                selected[#selected + 1] = SpellEntry(sp[idx])
            end
            for idx = 1, #universe do
                local ident = universe[idx]
                if not seen[ident] and not covered[ident] then
                    rest[#rest + 1] = SpellEntry(ident)
                end
            end
            table.sort(selected, ByLabel)
            table.sort(rest, ByLabel)
            local itemList = {
                { isTopAction = true, label = "Custom Spell ID", onClick = ShowCustomIdPopup },
            }
            if #selected > 0 then
                itemList[#itemList + 1] = { isHeader = true, label = "Selected" }
                for idx = 1, #selected do
                    itemList[#itemList + 1] = selected[idx]
                end
            end
            itemList[#itemList + 1] = { isHeader = true, label = "Presets" }
            for idx = 1, #rest do
                itemList[#itemList + 1] = rest[idx]
            end
            return itemList
        end
        local checkDrop, cbRefresh = CludesUI.BuildVisOptsCBDropdown(
            region,
            190,
            region:GetFrameLevel() + 2,
            ExtraItems,
            HasDirect,
            function(keyName, val)
                rowConf.spells = rowConf.spells or {}
                if val then
                    if not HasDirect(keyName) then
                        rowConf.spells[#rowConf.spells + 1] = keyName
                    end
                else
                    -- Unchecking drops the whole curated family, not just this id:
                    -- PAB_ResolveSpells expands a family from any member, so a
                    -- differently-named sibling left in the list would keep the buff
                    -- tracked behind an unchecked box. Same family = same table.
                    local fam = mod.PAB_SPELL_FAMILY and mod.PAB_SPELL_FAMILY[keyName]
                    for idx = #rowConf.spells, 1, -1 do
                        local ident = rowConf.spells[idx]
                        if ident == keyName or (fam and mod.PAB_SPELL_FAMILY[ident] == fam) then
                            table.remove(rowConf.spells, idx)
                        end
                    end
                end
                applyFn()
                -- Same reasoning as the Filters dropdown above: lightweight
                -- refresh only, so this checkbox dropdown stays open. The
                -- Filters dropdown's empty warning re-evaluates through the
                -- widget-refresh pass, so emptying a bar from THIS dropdown
                -- lights it up too.
                CludesUI:RefreshPage()
            end,
            nil,
            10,
            true
        )
        Pix.Point(checkDrop, "RIGHT", region, "RIGHT", -20, 0)
        region._control = checkDrop
        region._lastInline = nil
        CludesUI.RegisterWidgetRefresh(cbRefresh)
    end

    return startY
end

-- "Assigned Debuffs": unified Filters dropdown (same model as Raid Frames' Debuff
-- Manager base grid): pinned "All Debuffs" row above a Show/Hide caption row, then
-- TWO-LANE class rows -- ONE control, live in both modes. The left checkbox SHOWS a
-- class (cfg.classFilters, add mode; dimmed while All Debuffs is on), the right red
-- box HIDES it (cfg.negClassFilters -- hidden chain links / inverted candidates in
-- both modes, see DebuffSubtractFn/BuildChain). Lanes are mutually exclusive per
-- class and persist across mode flips. Used by BOTH the default Debuffs bar and
-- every custom debuff bar.
local function BuildAssignedDebuffsFields(widget, fontFile, startY, rowConf, applyFn)
    local W = CludesUI.Widgets
    local Pix = CludesUI.PanelPP
    local _, hh = 0, 0
    local heading

    heading, hh = W:SectionHeader(widget, "ASSIGNED DEBUFFS", startY)
    startY = startY - hh
    -- The Move in Unlock Mode button on the bar's first section: the key reads
    -- the sidebar selection at the click, so it highlights the selected bar.
    CludesUI.BuildSectionUnlockJump(heading, {
        key = function()
            if barPick.id == "default" then
                return "PAB_Debuffs"
            end
            return "PAB_CustomDebuff_" .. barPick.id
        end,
    })

    local safRow
    safRow, hh = W:DualRow(
        widget,
        startY,
        {
            type = "dropdown",
            text = "Filters",
            values = { __placeholder = "..." },
            order = { "__placeholder" },
            getValue = function()
                return "__placeholder"
            end,
            setValue = function() end,
        },
        CludesUI.MaxDurationDropdown(function()
            return rowConf.maxDurSec
        end, function(val)
            rowConf.maxDurSec = val
        end, applyFn)
    )
    startY = startY - hh
    do
        local region = safRow._leftRegion
        if region._control then
            region._control:Hide()
        end
        local PAB_ALL_DEBUFFS_KEY = "__allDebuffs"
        local PAB_DEBUFF_HAS_DUR_KEY = "__debuffHasDuration"
        local PAB_HIDE_EXH_KEY = "__hideExhaustion"
        local PAB_MATCH_ANY_KEY = "__matchAny"
        local PAB_MATCH_ALL_KEY = "__matchAll"
        local function AllOn()
            return rowConf.showAllDebuffs ~= false
        end
        local function MatchAll()
            return rowConf.debuffMatch == "all"
        end
        -- Hovering a dimmed Show box explains the dim (the lane is inert
        -- while All Debuffs already shows everything). Has Duration is an
        -- AND-modifier, not a mode: it never locks the lane.
        local lockedTip = L(
            "All Debuffs is selected, so every debuff already shows. Use the red Hide box to exclude these instead."
        )
        local function FilterItems()
            local itemList = {
                {
                    key = PAB_ALL_DEBUFFS_KEY,
                    label = "All Debuffs",
                    tooltip = "Show every debuff. Use the Hide lane below to remove specific filters.",
                },
                {
                    key = PAB_DEBUFF_HAS_DUR_KEY,
                    label = "Has Duration",
                    tooltip = "Only show debuffs that have a duration, excluding permanent ones. Combines with the filters below; checked alone it shows every timed debuff.",
                },
                -- Hide Exhaustion (cfg.hideExhaustion, off by default): the
                -- Bloodlust lockouts leave the bar (DebuffCandidateExtras). Kept out
                -- of the summary, like the Raid Frames row.
                {
                    key = PAB_HIDE_EXH_KEY,
                    label = "Hide Exhaustion",
                    tooltip = "Hides Sated, Exhaustion, Temporal Displacement and the other Bloodlust lockout debuffs.",
                    excludeFromSummaryFn = function()
                        return true
                    end,
                },
                -- Modifiers, not filters: how the Show picks combine (engine side:
                -- DebuffChainFor). A radio pair over cfg.debuffMatch (nil = Match
                -- Any, the union), kept out of the summary; locked while All
                -- Debuffs leaves nothing to combine. Never in ns.PAB_ClassItems:
                -- the player frame's dropdown shares that list.
                { isHeader = true, label = CludesUI.L("Match Mode") },
                {
                    key = PAB_MATCH_ANY_KEY,
                    label = CludesUI.L("Match Any Filter"),
                    isModifier = true,
                    lockedFn = AllOn,
                    lockedTooltip = CludesUI.L("Uncheck All Debuffs to choose how the Show filters combine."),
                    tooltip = CludesUI.L("Shows debuffs that match any checked Show filter (the default)."),
                },
                {
                    key = PAB_MATCH_ALL_KEY,
                    label = CludesUI.L("Match All Filters"),
                    isModifier = true,
                    lockedFn = AllOn,
                    lockedTooltip = CludesUI.L("Uncheck All Debuffs to choose how the Show filters combine."),
                    tooltip = CludesUI.L(
                        "Shows only debuffs that match every checked Show filter (dispel types count as one); opposites like Non-Player Auras with Cast By You show nothing."
                    ),
                },
                { isHeader = true, label = "Show", rightLabel = "Hide" },
            }
            local classItems = mod.PAB_ClassItems and mod.PAB_ClassItems(false) or {}
            for idx = 1, #classItems do
                local ci = classItems[idx]
                if ci.isHeader then
                    itemList[#itemList + 1] = { isHeader = true, label = ci.label }
                else
                    itemList[#itemList + 1] = {
                        key = ci.key,
                        label = ci.label,
                        tooltip = ci.tooltip,
                        dual = true,
                        showLockedFn = AllOn,
                        showLockedTooltip = lockedTip,
                    }
                end
            end
            return itemList
        end
        -- Non-Player / From Any Player share one engine field: a check in either
        -- lane clears the sibling from both lanes.
        local function ClearExclusive(keyName)
            local other = mod.PAB_ExclusiveSkey and mod.PAB_ExclusiveSkey[keyName]
            if not other then
                return
            end
            if rowConf.classFilters then
                rowConf.classFilters[other] = nil
                if not next(rowConf.classFilters) then
                    rowConf.classFilters = nil
                end
            end
            if rowConf.negClassFilters then
                rowConf.negClassFilters[other] = nil
                if not next(rowConf.negClassFilters) then
                    rowConf.negClassFilters = nil
                end
            end
        end
        local warnClosed
        local checkDrop, cbRefresh = CludesUI.BuildVisOptsCBDropdown(
            region,
            190,
            region:GetFrameLevel() + 2,
            FilterItems,
            function(keyName, neg)
                if keyName == PAB_ALL_DEBUFFS_KEY then
                    return AllOn()
                end
                if keyName == PAB_DEBUFF_HAS_DUR_KEY then
                    return rowConf.hasDuration == true
                end
                if keyName == PAB_HIDE_EXH_KEY then
                    return rowConf.hideExhaustion == true
                end
                if keyName == PAB_MATCH_ANY_KEY or keyName == PAB_MATCH_ALL_KEY then
                    return (keyName == PAB_MATCH_ALL_KEY) == MatchAll()
                end
                if neg then
                    local nf = rowConf.negClassFilters
                    return nf and nf[keyName] == true
                end
                local f = rowConf.classFilters
                return f and f[keyName] == true
            end,
            function(keyName, val, neg)
                if keyName == PAB_ALL_DEBUFFS_KEY then
                    -- Stores the raw boolean directly (nil must mean "on",
                    -- same convention as showAllBuffs). Lanes persist across
                    -- mode flips (the hide lane subtracts in both modes).
                    rowConf.showAllDebuffs = val
                    applyFn()
                    CludesUI:RefreshPage()
                    return
                end
                if keyName == PAB_DEBUFF_HAS_DUR_KEY then
                    -- AND-modifier (native maxDuration on every debuff group;
                    -- permanents excluded): combines with All Debuffs or any
                    -- class-filter selection; alone it acts as the timed
                    -- catch-all (DebuffCatchAllOn).
                    rowConf.hasDuration = val or nil
                    applyFn()
                    CludesUI:RefreshPage()
                    return
                end
                if keyName == PAB_HIDE_EXH_KEY then
                    rowConf.hideExhaustion = val or nil
                    applyFn()
                    CludesUI:RefreshPage()
                    return
                end
                if keyName == PAB_MATCH_ANY_KEY or keyName == PAB_MATCH_ALL_KEY then
                    -- Radio pair: the clicked row always wins (the toggled value
                    -- is ignored), so clicking the active row keeps it. nil =
                    -- Match Any keeps untouched bars byte-identical.
                    local wanted = (keyName == PAB_MATCH_ALL_KEY) and "all" or nil
                    if rowConf.debuffMatch == wanted then
                        return
                    end
                    rowConf.debuffMatch = wanted
                    applyFn()
                    CludesUI:RefreshPage()
                    return
                end
                -- Two-lane class write: checking one lane clears the other;
                -- emptied lane tables drop to nil (saved-variable hygiene).
                if val then
                    ClearExclusive(keyName)
                end
                if neg then
                    rowConf.negClassFilters = rowConf.negClassFilters or {}
                    rowConf.negClassFilters[keyName] = val or nil
                    if not next(rowConf.negClassFilters) then
                        rowConf.negClassFilters = nil
                    end
                    if val and rowConf.classFilters then
                        rowConf.classFilters[keyName] = nil
                    end
                else
                    rowConf.classFilters = rowConf.classFilters or {}
                    rowConf.classFilters[keyName] = val or nil
                    if val and rowConf.negClassFilters then
                        rowConf.negClassFilters[keyName] = nil
                        if not next(rowConf.negClassFilters) then
                            rowConf.negClassFilters = nil
                        end
                    end
                end
                if rowConf.classFilters and not next(rowConf.classFilters) then
                    rowConf.classFilters = nil
                end
                applyFn()
                -- Non-force: runs only the registered lightweight refresh
                -- callbacks (e.g. the sidebar tile's subtitleFn) in place,
                -- without closing this open dropdown.
                CludesUI:RefreshPage()
            end,
            nil,
            12,
            nil,
            nil,
            function()
                if warnClosed then
                    warnClosed()
                end
            end,
            -- The summary joins picks the way they combine.
            {
                separatorFn = function()
                    return (MatchAll() and not AllOn()) and " & " or ", "
                end,
            }
        )
        Pix.Point(checkDrop, "RIGHT", region, "RIGHT", -20, 0)
        region._control = checkDrop
        region._lastInline = nil
        CludesUI.RegisterWidgetRefresh(cbRefresh)
        warnClosed = CludesUI.AttachEmptyFilterWarn(
            region,
            checkDrop,
            L("You are displaying NO debuffs at all."),
            function()
                if not mod.PAB_DebuffBarHasContent then
                    return true
                end
                -- Match All picks that can never match together build nothing.
                if mod.PAB_DebuffMatchEmpty and mod.PAB_DebuffMatchEmpty(rowConf) then
                    return false
                end
                return mod.PAB_DebuffBarHasContent(rowConf) and true or false
            end
        )
    end

    return startY
end

-- "Core": Icon Size (+Icon Zoom cog) | Growth Direction;
--         Sort Method | Sort Direction;
--         Duration [+expand][swatch][toggle] | Stacks [+expand][swatch][toggle].
-- Shared by every bar (default + custom, buff + debuff) -- growDirection is generic
-- (BuildContainerSpec doesn't care about slots vs. groups). isBuff is currently unused
-- here (Sort Method's option set is now shared between buffs/debuffs, see
-- SORT_METHOD_VALUES' doc comment) but kept for callers/future per-polarity fields.
local function BuildCoreFields(widget, fontFile, startY, rowConf, applyFn, buffBar)
    -- Row accessors over conf: a key read (or its default) and written.
    local function ConfFieldThen(key)
        return function(value)
            rowConf[key] = value
            applyFn()
        end
    end
    local function ConfFieldOr(key, default)
        return function()
            return rowConf[key] or default
        end
    end
    local W = CludesUI.Widgets
    local Pix = CludesUI.PanelPP
    local _, hh = 0, 0

    _, hh = W:SectionHeader(widget, "CORE", startY)
    startY = startY - hh

    local sizeRow
    sizeRow, hh = W:DualRow(widget, startY, {
        type = "slider",
        text = "Icon Size",
        min = 16,
        max = 400,
        step = 1,
        trackWidth = 120,
        getValue = ConfFieldOr("iconSize", 32),
        setValue = ConfFieldThen("iconSize"),
    }, {
        type = "dropdown",
        text = "Growth Direction",
        values = GROW_DIR_VALUES,
        order = GROW_DIR_ORDER,
        getValue = ConfFieldOr("growDirection", "LEFT"),
        setValue = function(val)
            -- Change the wrap direction to be a valid value from the new growth direction
            if val == "UP" or val == "DOWN" then
                if rowConf.iconWrapDirection ~= "LEFT" and rowConf.iconWrapDirection ~= "RIGHT" then
                    rowConf.iconWrapDirection = "LEFT"
                end
            elseif val == "LEFT" or val == "RIGHT" then
                if rowConf.iconWrapDirection ~= "UP" and rowConf.iconWrapDirection ~= "DOWN" then
                    rowConf.iconWrapDirection = "DOWN"
                end
            end

            rowConf.growDirection = val
            applyFn()
        end,
    })
    startY = startY - hh

    _, hh = W:DualRow(widget, startY, {
        type = "dropdown",
        text = "Sort Method",
        values = SORT_METHOD_VALUES,
        order = SORT_METHOD_ORDER,
        getValue = ConfFieldOr("sortMethod", "Default"),
        setValue = ConfFieldThen("sortMethod"),
    }, {
        type = "dropdown",
        text = "Sort Direction",
        values = SORT_DIR_VALUES,
        order = SORT_DIR_ORDER,
        getValue = ConfFieldOr("sortDirection", "Normal"),
        setValue = ConfFieldThen("sortDirection"),
    })
    startY = startY - hh
    do
        local region = sizeRow._leftRegion
        CludesUI.BuildInlineCog(region, {
            title = "Icon Size",
            rows = {
                {
                    type = "slider",
                    label = "Icon Zoom",
                    min = 0,
                    max = 0.20,
                    step = 0.01,
                    get = ConfFieldOr("iconZoom", 0.055),
                    set = ConfFieldThen("iconZoom"),
                },
            },
        })
    end
    do
        -- Icon Wrap: only meaningful for vertical growth (Up/Down) and horizontal growth (Left/Right) -- decides which
        -- side additional columns stack toward when Icons Per Row/Column > 1. Cog-only,
        -- no separate dropdown row, and only shown while Growth Direction is Up/Down or Left/Right.
        local region = sizeRow._rightRegion
        local cogBtn = CludesUI.BuildInlineCog(region, {
            title = "Growth",
            rows = {
                {
                    type = "dropdown",
                    label = "Icon Wrap",
                    values = ICON_WRAP_VALUES,
                    order = ICON_WRAP_ORDER,
                    get = ConfFieldOr("iconWrapDirection", "LEFT"),
                    set = ConfFieldThen("iconWrapDirection"),
                    itemDisabled = function(val)
                        if rowConf.growDirection == "LEFT" or rowConf.growDirection == "RIGHT" then
                            return val == "LEFT" or val == "RIGHT"
                        elseif rowConf.growDirection == "UP" or rowConf.growDirection == "DOWN" then
                            return val == "UP" or val == "DOWN"
                        end
                        return false
                    end,
                },
            },
        })
        local function UpdateWrapCogVisibility()
            local dir = rowConf.growDirection or "LEFT"
            if cogBtn then
                cogBtn:SetShown(dir == "UP" or dir == "DOWN" or dir == "LEFT" or dir == "RIGHT")
            end
        end
        CludesUI.RegisterWidgetRefresh(UpdateWrapCogVisibility)
        UpdateWrapCogVisibility()
    end

    local dsRow
    dsRow, hh = W:DualRow(widget, startY, {
        type = "toggle",
        text = "Duration",
        getValue = function()
            return rowConf.durationShow ~= false
        end,
        setValue = ConfFieldThen("durationShow"),
    }, {
        type = "toggle",
        text = "Stacks",
        getValue = function()
            return rowConf.stackShow ~= false
        end,
        setValue = ConfFieldThen("stackShow"),
    })
    startY = startY - hh
    do
        local region = dsRow._leftRegion
        CludesUI.BuildInlineCog(region, {
            title = "Duration Text",
            rows = {
                {
                    type = "slider",
                    label = "Text Size",
                    min = 6,
                    max = 60,
                    step = 1,
                    get = ConfFieldOr("durationTextSize", 11),
                    set = ConfFieldThen("durationTextSize"),
                },
                {
                    type = "slider",
                    label = "Offset X",
                    min = -50,
                    max = 50,
                    step = 1,
                    get = ConfFieldOr("durationOffsetX", 0),
                    set = ConfFieldThen("durationOffsetX"),
                },
                {
                    type = "slider",
                    label = "Offset Y",
                    min = -50,
                    max = 50,
                    step = 1,
                    get = ConfFieldOr("durationOffsetY", 0),
                    set = ConfFieldThen("durationOffsetY"),
                },
                {
                    type = "dropdown",
                    label = "Position",
                    values = AURA_POINT_VALUES,
                    order = AURA_POINT_ORDER,
                    get = ConfFieldOr("durationPosition", "CENTER"),
                    set = ConfFieldThen("durationPosition"),
                },
                {
                    type = "toggle",
                    label = "Show S for Seconds",
                    get = function()
                        return rowConf.durationShowSeconds == true
                    end,
                    set = function(val)
                        rowConf.durationShowSeconds = val and true or nil
                        applyFn()
                    end,
                },
                {
                    type = "slider",
                    label = "Precise Below (minutes, 0 = off)",
                    min = 0,
                    max = 90,
                    step = 1,
                    get = function()
                        return rowConf.durationPrecisionThreshold and rowConf.durationPrecisionThreshold / 60 or 0
                    end,
                    set = function(val)
                        rowConf.durationPrecisionThreshold = val > 0 and math.floor(val * 60 + 0.5) or nil
                        applyFn()
                    end,
                },
            },
        })
        local colorSwatch, updateSwatch = CludesUI.BuildColorSwatch(region, dsRow:GetFrameLevel() + 3, function()
            return (rowConf.durationColorR or 1), (rowConf.durationColorG or 1), (rowConf.durationColorB or 1), 1
        end, function(red, green, blue)
            rowConf.durationColorR, rowConf.durationColorG, rowConf.durationColorB = red, green, blue
            applyFn()
        end, false, 20)
        colorSwatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
        region._lastInline = colorSwatch
        CludesUI.RegisterWidgetRefresh(updateSwatch)
    end
    do
        local region = dsRow._rightRegion
        CludesUI.BuildInlineCog(region, {
            title = "Stacks Text",
            rows = {
                {
                    type = "slider",
                    label = "Text Size",
                    min = 6,
                    max = 60,
                    step = 1,
                    get = ConfFieldOr("stackTextSize", 11),
                    set = ConfFieldThen("stackTextSize"),
                },
                {
                    type = "slider",
                    label = "Offset X",
                    min = -50,
                    max = 50,
                    step = 1,
                    get = ConfFieldOr("stackOffsetX", 0),
                    set = ConfFieldThen("stackOffsetX"),
                },
                {
                    type = "slider",
                    label = "Offset Y",
                    min = -50,
                    max = 50,
                    step = 1,
                    get = ConfFieldOr("stackOffsetY", 0),
                    set = ConfFieldThen("stackOffsetY"),
                },
                {
                    type = "dropdown",
                    label = "Position",
                    values = AURA_POINT_VALUES,
                    order = AURA_POINT_ORDER,
                    get = ConfFieldOr("stackPosition", "BOTTOMRIGHT"),
                    set = ConfFieldThen("stackPosition"),
                },
            },
        })
        local colorSwatch, updateSwatch = CludesUI.BuildColorSwatch(region, dsRow:GetFrameLevel() + 3, function()
            return (rowConf.stackColorR or 1), (rowConf.stackColorG or 1), (rowConf.stackColorB or 1), 1
        end, function(red, green, blue)
            rowConf.stackColorR, rowConf.stackColorG, rowConf.stackColorB = red, green, blue
            applyFn()
        end, false, 20)
        colorSwatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
        region._lastInline = colorSwatch
        CludesUI.RegisterWidgetRefresh(updateSwatch)
    end

    return startY
end

local function FontOutlineField(rowConf, applyFn)
    -- Row accessors over conf: a key read (or its default) and written.
    local function ConfFieldThen(key)
        return function(value)
            rowConf[key] = value
            applyFn()
        end
    end
    local function ConfFieldOr(key, default)
        return function()
            return rowConf[key] or default
        end
    end
    return {
        type = "dropdown",
        text = "Font Outline",
        values = FONT_OUTLINE_VALUES,
        order = FONT_OUTLINE_ORDER,
        getValue = ConfFieldOr("fontOutline", "default"),
        setValue = ConfFieldThen("fontOutline"),
    }
end

-- "Display": Border Style (+shift/behind cog) | Border Size [swatch]; Width
-- Offset | Height Offset (textured style only); Icons Per Row (+grid cog) |
-- Spacing (+row-spacing cog); Icon Shape | Icon Zoom; remaining toggles are
-- packed by polarity without placeholder slots.
local function BuildDisplayFields(widget, fontFile, startY, rowConf, applyFn, buffBar)
    -- Row accessors over conf: a key read (or its default) and written.
    local function ConfFieldThen(key)
        return function(value)
            rowConf[key] = value
            applyFn()
        end
    end
    local function ConfFieldOr(key, default)
        return function()
            return rowConf[key] or default
        end
    end
    local W = CludesUI.Widgets
    local Pix = CludesUI.PanelPP
    local _, hh = 0, 0

    _, hh = W:SectionHeader(widget, "DISPLAY", startY)
    startY = startY - hh
    startY = CludesUI.BlizzStyle.Note(widget, startY, "playerauras")

    local textureValues, textureOrder = CludesUI.GetBorderTextureDropdown()
    -- Border Size: the pixel slider over cfg.borderSize and its borderSizePx
    -- companion (CludesUI.BorderPxSliderCfg). A custom Icon Shape keeps the
    -- None..Strong dropdown instead: its ring is on/off (PabShapeBorderSize), so a
    -- pixel count means nothing there. The Icon Shape setter rebuilds the page when
    -- the shape crosses none/custom, which swaps the control in this slot.
    local sizeCfg
    if IsMaskShape(rowConf.iconShape) then
        sizeCfg = {
            type = "dropdown",
            text = "Border Size",
            values = BORDER_SIZE_VALUES,
            order = BORDER_SIZE_LEVELS,
            itemDisabled = function(val)
                return IsMaskShape(rowConf.iconShape) and BORDER_SIZE_SHAPE_DISABLED[val] or false
            end,
            itemDisabledTooltip = function()
                return "This option requires a non-custom shape to be selected"
            end,
            getValue = function()
                return BORDER_SIZE_KEY[rowConf.borderSize or 1] or "thin"
            end,
            setValue = function(val)
                rowConf.borderSize = BORDER_SIZE_NUM[val] or 1
                applyFn()
            end,
        }
    else
        sizeCfg = CludesUI.BorderPxSliderCfg({
            text = "Border Size",
            trackWidth = 120,
            -- The step BuildStyle renders with (cfg.borderSize or 1), as a number.
            getStep = function()
                return rowConf.borderSize or 1
            end,
            setStep = function(step)
                rowConf.borderSize = step
            end,
            getTex = function()
                return rowConf.borderTexture or "solid"
            end,
            getPx = function()
                return rowConf.borderSizePx
            end,
            setPx = function(val)
                rowConf.borderSizePx = val
            end,
            apply = applyFn,
        })
    end
    local styleRow
    styleRow, hh = W:DualRow(
        widget,
        startY,
        CludesUI.BlizzStyle.Gate("playerauras", {
            type = "dropdown",
            text = "Border Style",
            disabled = function()
                return IsMaskShape(rowConf.iconShape)
            end,
            disabledTooltip = "This option requires a non-custom shape to be selected",
            rawTooltip = true,
            values = textureValues,
            order = textureOrder,
            getValue = ConfFieldOr("borderTexture", "solid"),
            setValue = function(val)
                rowConf.borderTexture = val
                rowConf.borderTextureOffset = nil
                rowConf.borderTextureOffsetY = nil
                rowConf.borderTextureShiftX = nil
                rowConf.borderTextureShiftY = nil
                local color, behind = CludesUI.GetBorderStyleSelectDefaults(val)
                rowConf.borderR, rowConf.borderG, rowConf.borderB, rowConf.borderA = color.r, color.g, color.b, 1
                rowConf.borderBehind = behind
                local defaultSize = CludesUI.GetBorderDefaultSize("unitframes", val)
                if defaultSize then
                    rowConf.borderSize = defaultSize
                end
                -- A style pick resets the size: the exact size paired with the old
                -- step and texture goes with it (false, never nil, once it was set).
                if rowConf.borderSizePx then
                    rowConf.borderSizePx = false
                end
                applyFn()
                -- The Width Offset | Height Offset row below exists only for a
                -- textured style: a Solid/textured crossing rebuilds the page.
                CludesUI:RefreshPage(true)
            end,
        }),
        CludesUI.BlizzStyle.Gate("playerauras", sizeCfg)
    )
    startY = startY - hh
    do
        local region = styleRow._leftRegion
        local borderCogRows = {
            {
                type = "slider",
                label = "Shift X",
                min = -10,
                max = 10,
                step = 1,
                get = function()
                    if rowConf.borderTextureShiftX ~= nil then
                        return rowConf.borderTextureShiftX
                    end
                    local _, _, posX = CludesUI.GetBorderDefaults(
                        "unitframes",
                        rowConf.borderTexture or "solid",
                        rowConf.borderSize or 1
                    )
                    return posX
                end,
                set = function(val)
                    if val == 0 then
                        val = nil
                    end
                    rowConf.borderTextureShiftX = val
                    applyFn()
                end,
            },
            {
                type = "slider",
                label = "Shift Y",
                min = -10,
                max = 10,
                step = 1,
                get = function()
                    if rowConf.borderTextureShiftY ~= nil then
                        return rowConf.borderTextureShiftY
                    end
                    local _, _, _, posY = CludesUI.GetBorderDefaults(
                        "unitframes",
                        rowConf.borderTexture or "solid",
                        rowConf.borderSize or 1
                    )
                    return posY
                end,
                set = function(val)
                    if val == 0 then
                        val = nil
                    end
                    rowConf.borderTextureShiftY = val
                    applyFn()
                end,
            },
            {
                type = "toggle",
                label = "Show Behind",
                get = function()
                    return rowConf.borderBehind == true
                end,
                set = ConfFieldThen("borderBehind"),
            },
        }
        -- Debuff bars only: their engine dispel ring can take this border's art.
        if not buffBar then
            borderCogRows[#borderCogRows + 1] = {
                type = "toggle",
                label = "Textured Dispel Ring",
                tooltip = "Draws the dispel-colored ring in this border style's shape instead of flat lines.",
                get = function()
                    return rowConf.borderDispelTextured == true
                end,
                set = function(val)
                    rowConf.borderDispelTextured = val and true or false
                    applyFn()
                end,
            }
        end
        local cogBtn = CludesUI.BuildInlineCog(region, {
            title = "Border Options",
            rows = borderCogRows,
        })
        local function UpdateBorderCogVisibility()
            if cogBtn then
                cogBtn:SetShown(
                    (rowConf.borderTexture or "solid") ~= "solid"
                        and not IsMaskShape(rowConf.iconShape)
                        and not CludesUI.BlizzStyle.Get("playerauras")
                )
            end
        end
        CludesUI.RegisterWidgetRefresh(UpdateBorderCogVisibility)
        UpdateBorderCogVisibility()

        local keyList, labels = {}, {}
        for _, record in ipairs(PabAllBarEntries()) do
            keyList[#keyList + 1] = record.key
            labels[record.key] = record.label
        end
        local function CopyBorderStyleTo(record)
            local target = record.cfg
            target.borderTexture = rowConf.borderTexture
            target.borderTextureOffset = rowConf.borderTextureOffset
            target.borderTextureOffsetY = rowConf.borderTextureOffsetY
            target.borderTextureShiftX = rowConf.borderTextureShiftX
            target.borderTextureShiftY = rowConf.borderTextureShiftY
            target.borderBehind = rowConf.borderBehind
            -- Textured Dispel Ring is a debuff-bar setting: it travels only from
            -- a debuff bar to debuff bars.
            if not buffBar and not record.isBuff then
                target.borderDispelTextured = rowConf.borderDispelTextured
            end
            target.borderR, target.borderG, target.borderB, target.borderA =
                rowConf.borderR, rowConf.borderG, rowConf.borderB, rowConf.borderA
            -- Border textures and custom shape masks are mutually exclusive in
            -- the editor. A bulk style sync follows the same "last choice wins"
            -- rule as a direct selection so it cannot create a locked combination.
            if (rowConf.borderTexture or "solid") ~= "solid" then
                target.iconShape = "none"
            end
            PabApplyBarEntry(record)
        end
        CludesUI.BuildSyncIcon({
            region = region,
            tooltip = "Apply Border Style to all Bars",
            onClick = function()
                for _, record in ipairs(PabAllBarEntries()) do
                    if record.cfg ~= rowConf then
                        CopyBorderStyleTo(record)
                    end
                end
                CludesUI:RefreshPage()
            end,
            isSynced = function()
                local texture = rowConf.borderTexture or "solid"
                for _, record in ipairs(PabAllBarEntries()) do
                    local c = record.cfg
                    if
                        (c.borderTexture or "solid") ~= texture
                        or c.borderTextureOffset ~= rowConf.borderTextureOffset
                        or c.borderTextureOffsetY ~= rowConf.borderTextureOffsetY
                        or c.borderTextureShiftX ~= rowConf.borderTextureShiftX
                        or c.borderTextureShiftY ~= rowConf.borderTextureShiftY
                        or (c.borderBehind == true) ~= (rowConf.borderBehind == true)
                        or (
                            not buffBar
                            and not record.isBuff
                            and (c.borderDispelTextured == true) ~= (rowConf.borderDispelTextured == true)
                        )
                    then
                        return false
                    end
                end
                return true
            end,
            flashTargets = function()
                return { region }
            end,
            multiApply = {
                elementKeys = keyList,
                elementLabels = labels,
                getCurrentKey = function()
                    return PabBarKeyOf(rowConf, buffBar)
                end,
                onApply = function(checkedKeys)
                    local byKey = {}
                    for _, record in ipairs(PabAllBarEntries()) do
                        byKey[record.key] = record
                    end
                    for _, key in ipairs(checkedKeys) do
                        local record = byKey[key]
                        if record then
                            CopyBorderStyleTo(record)
                        end
                    end
                    CludesUI:RefreshPage()
                end,
            },
        })
    end

    -- Width Offset | Height Offset: the textured border's outward offsets, their
    -- own row right under the style row and present only for a textured style
    -- (the Border Style setter rebuilds the page on a Solid/textured crossing).
    -- addonKey/getSizeKey mirror what BuildStyle hands AuraKit ("unitframes",
    -- sizeKey = the borderSize step), so the shown default is the drawn one.
    do
        local texture = rowConf.borderTexture
        if texture and texture ~= "" and texture ~= "solid" then
            local ocfgL, ocfgR = CludesUI.BorderOffsetRowCfgs({
                addonKey = "unitframes",
                trackWidth = 120,
                getTex = function()
                    return rowConf.borderTexture or "solid"
                end,
                getStep = function()
                    return rowConf.borderSize or 1
                end,
                getSizeKey = function()
                    return rowConf.borderSize or 1
                end,
                getPx = function()
                    return rowConf.borderSizePx
                end,
                getX = function()
                    return rowConf.borderTextureOffset
                end,
                setX = function(val)
                    rowConf.borderTextureOffset = val
                end,
                getY = function()
                    return rowConf.borderTextureOffsetY
                end,
                setY = function(val)
                    rowConf.borderTextureOffsetY = val
                end,
                apply = applyFn,
            })
            _, hh = W:DualRow(
                widget,
                startY,
                CludesUI.BlizzStyle.Gate("playerauras", ocfgL),
                CludesUI.BlizzStyle.Gate("playerauras", ocfgR)
            )
            startY = startY - hh
        end
    end

    local rowRow
    rowRow, hh = W:DualRow(widget, startY, {
        type = "slider",
        text = "Icons Per Row",
        min = 1,
        max = 20,
        step = 1,
        trackWidth = 120,
        getValue = function()
            return rowConf.iconsPerRow or (buffBar and 11 or 8)
        end,
        setValue = ConfFieldThen("iconsPerRow"),
    }, {
        type = "slider",
        text = "Spacing",
        min = -5,
        max = 20,
        step = 1,
        trackWidth = 120,
        getValue = ConfFieldOr("padding", 5),
        setValue = ConfFieldThen("padding"),
    })
    startY = startY - hh
    do
        local region = styleRow._rightRegion
        local colorSwatch, updateSwatch = CludesUI.BuildColorSwatch(
            region,
            styleRow:GetFrameLevel() + 3,
            function()
                return (rowConf.borderR or 0), (rowConf.borderG or 0), (rowConf.borderB or 0), (rowConf.borderA or 1)
            end,
            function(red, green, blue, a)
                rowConf.borderR, rowConf.borderG, rowConf.borderB, rowConf.borderA = red, green, blue, a
                applyFn()
            end,
            true,
            20
        )
        colorSwatch:SetPoint("RIGHT", region._lastInline or region._control, "LEFT", -8, 0)
        region._lastInline = colorSwatch
        CludesUI.RegisterWidgetRefresh(updateSwatch)
    end
    do
        local region = styleRow._rightRegion
        local keyList, labels = {}, {}
        for _, record in ipairs(PabAllBarEntries()) do
            keyList[#keyList + 1] = record.key
            labels[record.key] = record.label
        end
        local function CopyBorderTo(record)
            record.cfg.borderSize = rowConf.borderSize
            -- The exact size travels with its step, verbatim (string/false/nil);
            -- a target whose value was set is cleared with false, never nil.
            local px = rowConf.borderSizePx
            if px == nil and record.cfg.borderSizePx ~= nil then
                px = false
            end
            record.cfg.borderSizePx = px
            -- A SHAPED target can't render Thin/Normal/Heavy (its shape border
            -- has only off/Strong states; the dropdown disables those levels).
            -- Snap to Strong so a sync can't strand a shaped bar on a level it
            -- could never pick, silently losing its border and dispel ring.
            local sz = record.cfg.borderSize or 1
            if IsMaskShape(record.cfg.iconShape) and sz >= 1 and sz <= 3 then
                record.cfg.borderSize = BORDER_SIZE_NUM[BORDER_SIZE_DEFAULT_SHAPE]
            end
            record.cfg.borderR, record.cfg.borderG, record.cfg.borderB, record.cfg.borderA =
                rowConf.borderR, rowConf.borderG, rowConf.borderB, rowConf.borderA
            PabApplyBarEntry(record)
        end
        CludesUI.BuildSyncIcon({
            region = region,
            tooltip = "Apply Border Size and Color to all Bars",
            onClick = function()
                for _, record in ipairs(PabAllBarEntries()) do
                    if record.cfg ~= rowConf then
                        CopyBorderTo(record)
                    end
                end
                CludesUI:RefreshPage()
            end,
            isSynced = function()
                local size = rowConf.borderSize or 1
                local red, green, blue, a = rowConf.borderR or 0, rowConf.borderG or 0, rowConf.borderB or 0, rowConf.borderA or 1
                for _, record in ipairs(PabAllBarEntries()) do
                    local c = record.cfg
                    if
                        (c.borderSize or 1) ~= size
                        or (c.borderR or 0) ~= red
                        or (c.borderG or 0) ~= green
                        or (c.borderB or 0) ~= blue
                        or (c.borderA or 1) ~= a
                        or (c.borderSizePx or false) ~= (rowConf.borderSizePx or false)
                    then
                        return false
                    end
                end
                return true
            end,
            flashTargets = function()
                return { region }
            end,
            multiApply = {
                elementKeys = keyList,
                elementLabels = labels,
                getCurrentKey = function()
                    return PabBarKeyOf(rowConf, buffBar)
                end,
                onApply = function(checkedKeys)
                    local byKey = {}
                    for _, record in ipairs(PabAllBarEntries()) do
                        byKey[record.key] = record
                    end
                    for _, key in ipairs(checkedKeys) do
                        local record = byKey[key]
                        if record then
                            CopyBorderTo(record)
                        end
                    end
                    CludesUI:RefreshPage()
                end,
            },
        })
    end
    do
        -- Row Spacing lives here, not in Icons Per Row's cog -- it's spacing between
        -- rows, same family as Spacing (icon-to-icon gap), not a grid-size concern like
        -- Icons Per Row/ Max Rows/Max Total.
        local region = rowRow._rightRegion
        CludesUI.BuildInlineCog(region, {
            title = "Spacing",
            rows = {
                -- nil = 12px default -- deliberately
                -- decoupled from Spacing/padding, no longer mirrors it.
                {
                    type = "slider",
                    label = "Row Spacing",
                    min = -5,
                    max = 20,
                    step = 1,
                    get = ConfFieldOr("rowSpacing", 12),
                    set = ConfFieldThen("rowSpacing"),
                },
            },
        })
    end

    do
        -- Verified against CUI_RaidFrames_BuffManager.lua's "legacy layout"
        -- branch: perRowCfg paired with a blank spacer, cog on
        -- gridRow._leftRegion -- i.e. directly on Icons Per Row's own
        -- region. Same trackWidth=120 slider + cog combo used there.
        local region = rowRow._leftRegion
        CludesUI.BuildInlineCog(region, {
            title = "Icons Per Row",
            rows = {
                {
                    type = "slider",
                    label = "Max Rows",
                    min = 1,
                    max = 10,
                    step = 1,
                    get = function()
                        return rowConf.maxRows or (buffBar and 3 or 2)
                    end,
                    set = ConfFieldThen("maxRows"),
                },
                {
                    type = "slider",
                    label = "Max Total",
                    min = 1,
                    max = 40,
                    step = 1,
                    get = function()
                        return rowConf.maxTotal or (buffBar and 32 or 16)
                    end,
                    set = ConfFieldThen("maxTotal"),
                },
            },
        })
    end

    -- Icon Shape reuses the base Border Size/Color above -- no separate shape fields.
    local shapeRow
    shapeRow, hh = W:DualRow(
        widget,
        startY,
        {
            type = "dropdown",
            text = "Icon Shape",
            values = SHAPE_VALUES,
            order = SHAPE_ORDER,
            itemDisabled = function(val)
                return IsMaskShape(val) and (rowConf.borderTexture or "solid") ~= "solid"
            end,
            itemDisabledTooltip = function(val)
                if IsMaskShape(val) and (rowConf.borderTexture or "solid") ~= "solid" then
                    return "This option requires the Border Style to be set to Solid"
                end
            end,
            getValue = ConfFieldOr("iconShape", "none"),
            setValue = function(val)
                local wasShaped = IsMaskShape(rowConf.iconShape)
                rowConf.iconShape = val
                -- Entering shape mode with a now-disabled Border Size level selected:
                -- snap to the shape default, same as Action Bars' own shape dropdown
                -- resetting border thickness on every shape change.
                local curKey = BORDER_SIZE_KEY[rowConf.borderSize or 1] or "thin"
                if IsMaskShape(val) and BORDER_SIZE_SHAPE_DISABLED[curKey] then
                    rowConf.borderSize = BORDER_SIZE_NUM[BORDER_SIZE_DEFAULT_SHAPE]
                end
                applyFn()
                -- The Border Size slots (here and in Icon Effects) hold a pixel
                -- slider without a shape and the None..Strong dropdown with one, so
                -- a none/custom crossing rebuilds the page to swap the control.
                if wasShaped ~= IsMaskShape(val) then
                    CludesUI:RefreshPage(true)
                end
            end,
        },
        CludesUI.BlizzStyle.Gate("playerauras", {
            -- cfg.iconZoom stays a raw 0-1 fraction (SetTexCoord's own units); the
            -- slider itself works in percent, like Action Bars' Icon Zoom.
            -- Blizzard Style draws the whole icon (zoom 0).
            type = "slider",
            text = "Icon Zoom",
            min = 0,
            max = 15,
            step = 0.5,
            trackWidth = 120,
            getValue = function()
                return (rowConf.iconZoom or 0.055) * 100
            end,
            setValue = function(val)
                rowConf.iconZoom = val / 100
                applyFn()
            end,
        })
    )
    startY = startY - hh
    do
        local region = shapeRow._leftRegion
        CludesUI.BuildInlineCog(region, {
            title = "Icon Shape",
            disabled = function()
                return rowConf.iconShape ~= "cropped"
            end,
            disabledTooltip = "This option requires Icon Shape to be set to Cropped",
            rows = {
                {
                    type = "slider",
                    label = "Adjust Crop",
                    min = 5,
                    max = 25,
                    step = 1,
                    tooltip = "How much is trimmed from the icon's top and bottom, as a percentage per side. 10% is the classic cropped look.",
                    get = function()
                        return mod.PAB_CropPercent(rowConf)
                    end,
                    set = ConfFieldThen("iconCropPercent"),
                },
            },
        })
        local keyList, labels = {}, {}
        for _, record in ipairs(PabAllBarEntries()) do
            keyList[#keyList + 1] = record.key
            labels[record.key] = record.label
        end
        -- Same snap rule as the Icon Shape dropdown's own setValue: a bar
        -- ENTERING shape mode while sitting on Thin/Normal/Heavy would render
        -- no shape border at those levels (and the dropdown disables them), so
        -- the sync snaps it to Strong exactly as a manual shape pick would.
        local function CopyShapeTo(record)
            local shape = rowConf.iconShape
            record.cfg.iconShape = shape
            if shape == "cropped" then
                record.cfg.iconCropPercent = mod.PAB_CropPercent(rowConf)
            end
            if IsMaskShape(shape) then
                record.cfg.borderTexture = "solid"
                record.cfg.borderTextureOffset = nil
                record.cfg.borderTextureOffsetY = nil
                record.cfg.borderTextureShiftX = nil
                record.cfg.borderTextureShiftY = nil
                record.cfg.borderBehind = false
            end
            local sz = record.cfg.borderSize or 1
            if IsMaskShape(shape) and sz >= 1 and sz <= 3 then
                record.cfg.borderSize = BORDER_SIZE_NUM[BORDER_SIZE_DEFAULT_SHAPE]
            end
            PabApplyBarEntry(record)
        end
        CludesUI.BuildSyncIcon({
            region = region,
            tooltip = "Apply Icon Shape to all Bars",
            onClick = function()
                for _, record in ipairs(PabAllBarEntries()) do
                    if record.cfg ~= rowConf then
                        CopyShapeTo(record)
                    end
                end
                CludesUI:RefreshPage()
            end,
            isSynced = function()
                local shape = rowConf.iconShape or "none"
                for _, record in ipairs(PabAllBarEntries()) do
                    if (record.cfg.iconShape or "none") ~= shape then
                        return false
                    end
                    if
                        shape == "cropped"
                        and mod.PAB_CropPercent(record.cfg) ~= mod.PAB_CropPercent(rowConf)
                    then
                        return false
                    end
                end
                return true
            end,
            flashTargets = function()
                return { region }
            end,
            multiApply = {
                elementKeys = keyList,
                elementLabels = labels,
                getCurrentKey = function()
                    return PabBarKeyOf(rowConf, buffBar)
                end,
                onApply = function(checkedKeys)
                    local byKey = {}
                    for _, record in ipairs(PabAllBarEntries()) do
                        byKey[record.key] = record
                    end
                    for _, key in ipairs(checkedKeys) do
                        local record = byKey[key]
                        if record then
                            CopyShapeTo(record)
                        end
                    end
                    CludesUI:RefreshPage()
                end,
            },
        })
    end

    local swipeRow
    swipeRow, hh = W:DualRow(widget, startY, {
        type = "toggle",
        text = "Show Duration Swipe",
        getValue = function()
            return rowConf.showSwipe ~= false
        end,
        setValue = ConfFieldThen("showSwipe"),
    }, {
        type = "toggle",
        text = "Show Tooltips",
        tooltip = "Show aura tooltips when hovering this bar's icons.",
        getValue = function()
            return rowConf.showTooltips ~= false
        end,
        setValue = ConfFieldThen("showTooltips"),
    })
    startY = startY - hh
    do
        local region = swipeRow._leftRegion
        CludesUI.BuildInlineCog(region, {
            title = "Duration Swipe",
            rows = {
                -- Default on = the swipe UNCOVERS the icon as time runs out
                -- (the module's shipped look); off = Blizzard's standard
                -- direction, darkness growing over the icon instead.
                {
                    type = "toggle",
                    label = "Reverse Swipe",
                    get = function()
                        return rowConf.reverseSwipe ~= false
                    end,
                    set = ConfFieldThen("reverseSwipe"),
                },
            },
        })
    end

    -- Buff bars only: debuffs are never player-cancelable, so the row would
    -- be a dead switch there.
    if buffBar then
        _, hh = W:DualRow(widget, startY, FontOutlineField(rowConf, applyFn), {
            type = "toggle",
            text = "Right-Click to Cancel",
            tooltip = "Right-clicking a buff icon cancels the buff. Turning this off makes the bar's icons click-through; tooltips still follow the Show Tooltips setting.",
            getValue = function()
                return rowConf.rightClickCancel ~= false
            end,
            setValue = ConfFieldThen("rightClickCancel"),
        })
        startY = startY - hh
    end

    return startY
end

-- Debuff-category bars only (default debuffs + custom debuff bars).
local DISPEL_ICON_POS_VALUES = {
    none = "None",
    topleft = "Top Left",
    top = "Top",
    topright = "Top Right",
    left = "Left",
    center = "Center",
    right = "Right",
    bottomleft = "Bottom Left",
    bottom = "Bottom",
    bottomright = "Bottom Right",
}
local DISPEL_ICON_POS_ORDER =
    { "none", "topleft", "top", "topright", "left", "center", "right", "bottomleft", "bottom", "bottomright" }

local function BuildDispelColorFields(widget, fontFile, startY, rowConf, applyFn)
    -- Row accessors over conf: a key read (or its default) and written.
    local function ConfFieldThen(key)
        return function(value)
            rowConf[key] = value
            applyFn()
        end
    end
    local function ConfFieldOr(key, default)
        return function()
            return rowConf[key] or default
        end
    end
    local W = CludesUI.Widgets
    local Pix = CludesUI.PanelPP
    local _, hh = 0, 0

    -- Dispel-type indicator icon on each debuff bar (engine-driven, mirrors
    -- Raid Frames' "Type Icon Position"). "none" (default) = feature off.
    _, hh = W:SectionHeader(widget, "DEBUFF DISPLAY", startY)
    startY = startY - hh
    do
        local function IconOn()
            return (rowConf.dispelIconPosition or "none") ~= "none"
        end
        local row
        row, hh = W:DualRow(widget, startY, {
            type = "dropdown",
            text = "Type Icon Position",
            tooltip = "Shows the debuff's dispel type icon (Magic, Curse, Disease, Poison, Bleed) on the bar.",
            values = DISPEL_ICON_POS_VALUES,
            order = DISPEL_ICON_POS_ORDER,
            getValue = ConfFieldOr("dispelIconPosition", "none"),
            setValue = function(val)
                rowConf.dispelIconPosition = val
                applyFn()
                CludesUI:RefreshPage()
            end,
        }, FontOutlineField(rowConf, applyFn))
        startY = startY - hh
        local region = row._leftRegion
        CludesUI.BuildInlineCog(region, {
            disabled = function()
                return not IconOn()
            end,
            disabledTooltip = "This option requires a Type Icon Position other than None.",
            title = "Type Icon",
            rows = {
                {
                    type = "slider",
                    label = "Icon Size",
                    min = 8,
                    max = 48,
                    step = 1,
                    get = ConfFieldOr("dispelIconSize", 16),
                    set = ConfFieldThen("dispelIconSize"),
                },
                {
                    type = "slider",
                    label = "Offset X",
                    min = -50,
                    max = 50,
                    step = 1,
                    get = ConfFieldOr("dispelIconOffsetX", 0),
                    set = ConfFieldThen("dispelIconOffsetX"),
                },
                {
                    type = "slider",
                    label = "Offset Y",
                    min = -50,
                    max = 50,
                    step = 1,
                    get = ConfFieldOr("dispelIconOffsetY", 0),
                    set = ConfFieldThen("dispelIconOffsetY"),
                },
            },
        })
    end

    -- Blizzard Style paints the stock per-type border art, so the palette has
    -- nothing to colour: the whole section stays out (fully gated rows hide).
    if CludesUI.BlizzStyle.Get("playerauras") then
        return startY
    end

    _, hh = W:SectionHeader(widget, "DISPEL COLORS", startY)
    startY = startY - hh

    local function AddDispelSwatch(region, record)
        local colorSwatch, updateSwatch = CludesUI.BuildColorSwatch(region, region:GetFrameLevel() + 3, function()
            local color = rowConf[record.key]
            if color then
                return color.r or 1, color.g or 1, color.b or 1, 1
            end
            return record.fallback[1], record.fallback[2], record.fallback[3], 1
        end, function(red, green, blue)
            rowConf[record.key] = { r = red, g = green, b = blue }
            applyFn()
        end, false, 18)
        Pix.Point(colorSwatch, "RIGHT", region, "RIGHT", -20, 0)
        CludesUI.RegisterWidgetRefresh(updateSwatch)
    end
    for idx = 1, #DISPEL_COLOR_ROWS, 2 do
        local leftX, right = DISPEL_COLOR_ROWS[idx], DISPEL_COLOR_ROWS[idx + 1]
        local row
        row, hh = W:DualRow(
            widget,
            startY,
            { type = "label", text = leftX.label },
            right and { type = "label", text = right.label } or { type = "label", text = "" }
        )
        startY = startY - hh
        AddDispelSwatch(row._leftRegion, leftX)
        if right then
            AddDispelSwatch(row._rightRegion, right)
        end
    end

    return startY
end

-------------------------------------------------------------------------------
--  Icon Effects Per-Filter (debuffs only) -- ported from Raid Frames'
--  BuildFxEffects (CUI_RaidFrames_ManagerPages.lua), NOT shared code. Each
--  cfg.fxList entry: a Filters set (ns.PAB_FxClassItems -- PAB's debuff
--  category vocabulary keyed by the lowercase engine group key, plus a
--  synthetic "all" catch-all) + optional Icon Glow + Border override + Size
--  override. The engine side (CludesUIUnitFrames_PlayerAuraBars.lua)
--  matches the FIRST active block whose filters include a button's
--  category -- see PAB_ApplyDmFx/PAB_FxBlockFor there.
-------------------------------------------------------------------------------

local function BuildFxEffects(widget, startY, rowConf, applyFn)
    -- Real AuraButtons forbid driver-ticked glows (Blizzard_AuraButton.xml:
    -- ForbiddenAspects baked into the template), so the icon glow is an engine
    -- host: the shared controls offer only what renders there.
    return CludesUI.BuildIconEffects(widget, startY, {
        entries = rowConf.fxList or {},
        apply = applyFn,
        sizeMax = 400,
        fontKey = "unitFrames",
        filters = function(region, e)
            if region._control then
                region._control:Hide()
            end
            local itemList = mod.PAB_FxClassItems and mod.PAB_FxClassItems() or {}
            local checkDrop, cbRefresh = CludesUI.BuildVisOptsCBDropdown(
                region,
                190,
                region:GetFrameLevel() + 2,
                itemList,
                function(keyName)
                    return e.filters[keyName] == true
                end,
                function(keyName, val)
                    e.filters[keyName] = val or nil
                    applyFn()
                    CludesUI:RefreshPage()
                end
            )
            CludesUI.PanelPP.Point(checkDrop, "RIGHT", region, "RIGHT", -20, 0)
            region._control = checkDrop
            region._lastInline = nil
            if cbRefresh then
                CludesUI.RegisterWidgetRefresh(cbRefresh)
            end
        end,
        -- Border: solid px only (no Border Style here), so a plain 0-4 slider view
        -- over e.borderSize, the same number the dropdown wrote. A custom Icon
        -- Shape keeps the None..Strong dropdown (the shape ring is on/off); the
        -- Icon Shape setter rebuilds the page on a none/custom crossing.
        borderCfg = function(e)
            if IsMaskShape(rowConf.iconShape) then
                return {
                    type = "dropdown",
                    text = "Border",
                    values = BORDER_SIZE_VALUES,
                    order = BORDER_SIZE_LEVELS,
                    itemDisabled = function(val)
                        return IsMaskShape(rowConf.iconShape) and BORDER_SIZE_SHAPE_DISABLED[val] or false
                    end,
                    itemDisabledTooltip = function()
                        return "This option requires a non-custom shape to be selected"
                    end,
                    getValue = function()
                        return BORDER_SIZE_KEY[e.borderSize or 0] or "none"
                    end,
                    setValue = function(val)
                        e.borderSize = BORDER_SIZE_NUM[val] or 0
                        applyFn()
                    end,
                }
            end
        end,
        addEntry = function()
            rowConf.fxList = rowConf.fxList or {}
            rowConf.fxList[#rowConf.fxList + 1] = { filters = {} }
        end,
    })
end

-------------------------------------------------------------------------------
--  Default bar detail (Buffs / Debuffs -- fixed identity, not deletable)
-------------------------------------------------------------------------------

-- W:DualRow/W:SectionHeader compute their internal label/control proportions assuming
-- a frame padded like a standard single-column options page (CludesUI.CONTENT_PAD
-- margins on both sides, typically 45px). PAB's two-pane layout only reserves 20px for
-- its detail pane (PABMP_BuildPage), so DualRow's internal math runs against a
-- narrower frame than it expects and rows overlap -- confirmed by screenshots where
-- the overlap persists regardless of which region (left/right) carries the extra
-- widgets. Verified fix, ported from RaidFrames' ns.DMP_BuildPage (the exact page the
-- reference screenshot came from): oversize the frame actually handed to DualRow by
-- `padDiff` on both sides, shift it left by `padDiff` so its effective left edge still
-- lines up with the visible 20px inset, and clip the overflow on an outer frame
-- (RaidFrames: "DualRow width compensated so rows align with the 20px PAD"). fix:
-- `clip` is now a real ScrollFrame (was a plain Frame with SetClipsChildren --
-- silently cropped any overflow with no way to reach it, a pre-existing gap that only
-- became visible once the new preview box pushed settings fields below the fold).
-- Callers MUST call FinalizeCompensatedBody(body, finalSy) once after building all
-- their fields, so the scroll child's real height (and therefore the scrollbar's
-- thumb/track visibility) reflects actual content instead of a guess. fix:
-- restructured to put the padDiff shift on `scroll` itself (matching RaidFrames'
-- ns.DMP_BuildPage settingsScroll line-for-line) instead of on `body` inside an
-- unshifted scroll. Both are mathematically equivalent for where DualRow/SectionHeader
-- content ends up (verified via /fstack + a full frame-tree dump: both put rows at
-- parentFrame_left + PAD) -- but there is a REAL ~30px visual difference in-game (PAB
-- ~50px, RaidFrames Debuff Manager ~20px) that this math could not explain and
-- multiple manual measurements confirmed. Rather than keep guessing why the two
-- structurally- different-but-equivalent approaches render differently, this mirrors
-- DM's approach exactly since that one is confirmed correct.
local function WrapCompensatedBody(hostFrame, topOffset)
    local contentPad = CludesUI.CONTENT_PAD or 45
    local PAD = 20 -- matches PABMP_BuildPage's own detail-pane inset
    local padDiff = contentPad - PAD
    local visibleW = hostFrame:GetWidth()

    local scroller = CreateFrame("ScrollFrame", nil, hostFrame)
    scroller:SetPoint("TOPLEFT", hostFrame, "TOPLEFT", -padDiff, topOffset or 0)
    scroller:SetPoint("BOTTOMRIGHT", hostFrame, "BOTTOMRIGHT", padDiff, 0)
    scroller:SetFrameLevel(hostFrame:GetFrameLevel() + 1)
    scroller:SetClipsChildren(true)

    local bodyFrame = CreateFrame("Frame", nil, scroller)
    bodyFrame:SetSize(visibleW + padDiff * 2, 10) -- finalized by FinalizeCompensatedBody
    bodyFrame._showRowDivider = true
    scroller:SetScrollChild(bodyFrame)
    bodyFrame._pabUpdateThumb = AttachEditorScroll(scroller, bodyFrame, nil, padDiff + 2, true)

    -- Every WrapCompensatedBody call in this file immediately follows a
    -- PAB_BuildPreviewBox call on the same `parentFrame` (see the four BuildXDetail
    -- functions below) -- registering here, instead of at each call site, keeps the
    -- preview's live-resize wiring in one place. Reanchors this scroll frame's top edge
    -- whenever PAB_MaybeRefreshPreview resizes the preview box above it (Icons Per
    -- Row/Max Rows/Max Total/Icon Size/ Row Spacing change), so the settings area below
    -- never overlaps a grown box or leaves a stale gap under a shrunk one -- and
    -- refreshes the scrollbar thumb/track right after, since MaxScroll()/UpdateThumb
    -- read scroll:GetHeight() live and would otherwise stay stale (wrong thumb size, or
    -- a track that should now show/hide) until the next scroll interaction. Registered
    -- last (after body._pabUpdateThumb exists) so the closure can call it.
    if mod.PAB_SetPreviewResizeHandler then
        mod.PAB_SetPreviewResizeHandler(function(newTopOffset)
            scroller:ClearAllPoints()
            scroller:SetPoint("TOPLEFT", hostFrame, "TOPLEFT", -padDiff, newTopOffset)
            scroller:SetPoint("BOTTOMRIGHT", hostFrame, "BOTTOMRIGHT", padDiff, 0)
            if bodyFrame._pabUpdateThumb then
                bodyFrame._pabUpdateThumb()
            end
        end)
    end

    return bodyFrame
end

-- Sizes the scroll child to its real content height and refreshes the scrollbar's
-- thumb/track visibility. Call once, after all of a detail pane's fields have been
-- built into `body` and the final sy/by accumulator value is known.
local function FinalizeCompensatedBody(bodyFrame, startY)
    bodyFrame:SetHeight(max(10, math.abs(startY) + 20))
    if bodyFrame._pabUpdateThumb then
        bodyFrame._pabUpdateThumb()
    end
end

-- Settings-section header (Raid Frames Buff Manager parity): accent-colored title with
-- the gray parenthesized subtitle inline to its right, rendered INSIDE the compensated
-- settings body directly above the first section (ASSIGNED BUFFS/DEBUFFS, or CORE where
-- no assigned section exists). Bar renames go through CludesUI:RefreshPage(true),
-- which rebuilds this pane, so a plain SetText at build time is already live. Takes and
-- returns the body's running y like every section builder.
local function BuildBarTitle(widget, fontFile, name, subtitle, posY)
    local pad = CludesUI.CONTENT_PAD or 45
    local title = widget:CreateFontString(nil, "OVERLAY")
    title:SetFont(fontFile, 18, "")
    title:SetPoint("TOPLEFT", widget, "TOPLEFT", pad, posY - 11)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    local ac = CludesUI.CLUDES_GREEN
    if ac then
        title:SetTextColor(ac.r, ac.g, ac.b)
    else
        title:SetTextColor(0.30, 0.79, 0.94)
    end
    title:SetText(name)
    local subMenu = widget:CreateFontString(nil, "OVERLAY")
    subMenu:SetFont(fontFile, 13, "")
    subMenu:SetPoint("LEFT", title, "RIGHT", 4, 0)
    subMenu:SetPoint("RIGHT", widget, "RIGHT", -pad, 0)
    subMenu:SetJustifyH("LEFT")
    subMenu:SetWordWrap(false)
    subMenu:SetTextColor(0.75, 0.75, 0.75, 0.65)
    subMenu:SetText("(" .. (subtitle or "") .. ")")
    return posY - 11 - 18 - 5
end

local function BuildDefaultBarDetail(widget, fontFile, buffBar)
    local W = CludesUI.Widgets
    if not W then
        return
    end

    local s = mod.db and mod.db.profile and mod.db.profile.playerAuraBars
    if not s then
        return
    end
    -- Defensive: the lane split + enable migration normally run in CreateBars,
    -- but make the page unable to write pre-migration data even if it is ever
    -- reachable without them.
    if mod.PAB_EnsureBarEnable then
        mod.PAB_EnsureBarEnable(s)
    end
    local rowConf = buffBar and mod.PAB_DefaultBuffsCfg(s) or mod.PAB_DefaultDebuffsCfg(s)

    local function ApplyBar()
        if mod.PAB_Restyle then
            mod.PAB_Restyle()
        end
        if mod.PAB_ApplyLiveConfig then
            mod.PAB_ApplyLiveConfig(buffBar)
        end
    end

    local scrollTop = 0
    if mod.PAB_BuildPreviewBox then
        scrollTop =
            mod.PAB_BuildPreviewBox(widget, fontFile, 0, buffBar and "buff" or "debuff", "default", rowConf)
    end
    local bodyFrame = WrapCompensatedBody(widget, scrollTop)
    local startY = 0
    startY = BuildBarTitle(
        bodyFrame,
        fontFile,
        buffBar and DefaultBuffBarName(rowConf) or L("Debuffs"),
        L("Built-in bar. Cannot be deleted"),
        startY
    )

    if buffBar then
        startY = BuildAssignedBuffsFields(bodyFrame, fontFile, startY, rowConf, ApplyBar, true)
    else
        startY = BuildAssignedDebuffsFields(bodyFrame, fontFile, startY, rowConf, ApplyBar)
    end
    startY = BuildCoreFields(bodyFrame, fontFile, startY, rowConf, ApplyBar, buffBar)
    startY = BuildDisplayFields(bodyFrame, fontFile, startY, rowConf, ApplyBar, buffBar)
    if not buffBar then
        startY = BuildDispelColorFields(bodyFrame, fontFile, startY, rowConf, ApplyBar)
        startY = BuildFxEffects(bodyFrame, startY, rowConf, ApplyBar)
    end
    FinalizeCompensatedBody(bodyFrame, startY)
end
-- Sidebar tile: the shared manager tile at this page's 58px height, with a
-- 14px pencil and a narrower text inset when there is no pill.
local function BuildTile(hostFrame, posY, options)
    options.height, options.textRight = TILE_H, options.showToggle and -52 or -16
    options.editSize, options.editSnap = 14, true
    return CludesUI.BuildManagerTile(hostFrame, posY, options)
end

-- Sidebar "Add New" button (Raid Frames Buff Manager parity: solid green
-- accent button, 60% of the sidebar width, centered; background brightens
-- from 0.8 to full alpha on hover).
local function AddNewButton(hostFrame, posY, width, labelText, onClick)
    local btnW = floor(width * 0.6)
    local addBtn = CreateFrame("Button", nil, hostFrame)
    addBtn:SetSize(btnW, 30)
    addBtn:SetPoint("TOP", hostFrame, "TOPLEFT", floor(width / 2), posY - 10)
    addBtn:SetFrameLevel(hostFrame:GetFrameLevel() + 1)
    local accentColor = CludesUI.CLUDES_GREEN or { r = 0.30, g = 0.79, b = 0.94 }
    local addBg = addBtn:CreateTexture(nil, "BACKGROUND")
    addBg:SetAllPoints()
    addBg:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 0.8)
    CludesUI.RoundBody(addBtn, addBg)
    local labelFS = addBtn:CreateFontString(nil, "OVERLAY")
    -- Drop shadow via the shadow FontObject, primed BEFORE SetFont
    -- (SetShadowOffset alone does not render). Module font, same as the
    -- sibling managers' Add New labels.
    CludesUI.PrimeFontShadow(labelFS, true)
    labelFS:SetFont((CludesUI.GetFontPath("unitFrames")) or "Fonts\\FRIZQT__.TTF", 12, "")
    labelFS:SetTextColor(1, 1, 1)
    labelFS:SetPoint("CENTER")
    labelFS:SetText(labelText)
    addBtn:SetScript("OnEnter", nil) -- CludesUI.OutlineButton below sets the hover
    CludesUI.OutlineButton(addBtn, addBg, true)
    addBtn:SetScript("OnClick", onClick)
    return 50
end

-------------------------------------------------------------------------------
--  Custom Buff Bar detail pane
--  Shares BuildAssignedBuffsFields/BuildCoreFields/BuildDisplayFields with
--  the default Buffs bar -- same cfg shape (filters/spells), same fields.
-------------------------------------------------------------------------------

local function Apply(buffBar, barId)
    if buffBar then
        if mod.PAB_ReloadCustomBuffBar then
            mod.PAB_ReloadCustomBuffBar(barId)
        end
    else
        if mod.PAB_ReloadCustomDebuffBar then
            mod.PAB_ReloadCustomDebuffBar(barId)
        end
    end
end

-- Title bar: bar.name (falls back to the placeholder used at creation) +
-- a static subtitle, same TOPLEFT title/BOTTOMLEFT desc metrics as
-- BuildDefaultBarDetail's "Buffs"/"Built-in bar. Cannot be deleted."
-- header, so both default and custom bar detail panes look consistent.
-- Naming itself is handled exclusively through the sidebar now -- the
local function BuildBuffBarDetail(widget, fontFile, barConf)
    local W = CludesUI.Widgets
    if not W then
        return
    end
    -- Defensive lane split + enable migration, same as BuildDefaultBarDetail.
    local sPAB = mod.db and mod.db.profile and mod.db.profile.playerAuraBars
    if sPAB and mod.PAB_EnsureBarEnable then
        mod.PAB_EnsureBarEnable(sPAB)
    end
    local function ApplyBar()
        Apply(true, barConf.id)
    end

    local scrollTop = 0
    if mod.PAB_BuildPreviewBox then
        scrollTop = mod.PAB_BuildPreviewBox(widget, fontFile, 0, "buff", barConf.id, barConf)
    end
    local bodyFrame = WrapCompensatedBody(widget, scrollTop)
    local by = 0
    by = BuildBarTitle(bodyFrame, fontFile, L(barConf.name or "Buff Bar"), L("Custom buff bar"), by)
    by = BuildAssignedBuffsFields(bodyFrame, fontFile, by, barConf, ApplyBar)
    by = BuildCoreFields(bodyFrame, fontFile, by, barConf, ApplyBar, true)
    by = BuildDisplayFields(bodyFrame, fontFile, by, barConf, ApplyBar, true)
    FinalizeCompensatedBody(bodyFrame, by)
end

-------------------------------------------------------------------------------
--  Custom Debuff Bar detail pane -- category/class-token based, no SpellID
-- popup (by design: debuffs stay category-based, same as
--  RaidFrames).
-------------------------------------------------------------------------------

local function BuildDebuffBarDetail(widget, fontFile, barConf)
    local W = CludesUI.Widgets
    if not W then
        return
    end
    -- Defensive lane split + enable migration, same as BuildDefaultBarDetail.
    local sPAB = mod.db and mod.db.profile and mod.db.profile.playerAuraBars
    if sPAB and mod.PAB_EnsureBarEnable then
        mod.PAB_EnsureBarEnable(sPAB)
    end
    local function ApplyBar()
        Apply(false, barConf.id)
    end

    local scrollTop = 0
    if mod.PAB_BuildPreviewBox then
        scrollTop = mod.PAB_BuildPreviewBox(widget, fontFile, 0, "debuff", barConf.id, barConf)
    end
    local bodyFrame = WrapCompensatedBody(widget, scrollTop)
    local by = 0
    by = BuildBarTitle(bodyFrame, fontFile, L(barConf.name or "Debuff Bar"), L("Custom debuff bar"), by)
    by = BuildAssignedDebuffsFields(bodyFrame, fontFile, by, barConf, ApplyBar)
    by = BuildCoreFields(bodyFrame, fontFile, by, barConf, ApplyBar, false)
    by = BuildDisplayFields(bodyFrame, fontFile, by, barConf, ApplyBar, false)
    by = BuildDispelColorFields(bodyFrame, fontFile, by, barConf, ApplyBar)
    by = BuildFxEffects(bodyFrame, by, barConf, ApplyBar)
    FinalizeCompensatedBody(bodyFrame, by)
end

-------------------------------------------------------------------------------
--  Filter Editor modal -- 1:1 structural port of ns.BMP_ShowFilterEditor
--  (CUI_RaidFrames_ManagerPages.lua): same dimmer+popup+sidebar+detail
--  shape, same smooth-scroll+thumb, same icon-based sidebar rename/delete,
--  same Search Spells dropdown + Add Spell ID button layout, same class-
--  grouped checkbox-style spell list, same Selected/Presets Extra Spells
--  grouping. Two things differ from a byte-identical port:
--    * ns.PAB_AllPresetSpells() (the universe both Search Spells and Extra
--      Spells' Presets group draw from) is built from BM2_FILTER_SEED, not
--      from a live BM2_DEFAULT_FILTER_SPELLS reference -- same content,
--      just PAB's own copy (see that seed table's doc comment for why).
--    * No preset/custom distinction at the SPELL level -- filters
--      themselves ARE protected once imported (f.preset, see PAB_Filters'
--      doc comment), but every spell row within a filter stays equally
--      editable, unlike BM2 which only shows the delete-X on "custom"
--      (non-curated) spells.
--    * Own-only tracking (ind.ownFilters/ownExtras) -- explicitly out of
--      scope for this pass, matches PAB_ResolveSpells' doc comment.
--  Class grouping/coloring uses ns.PAB_SPELL_CLASS_HINTS (display-only,
--  extracted from the same BM2 source data as the seed filters) --
--  spells with no hint land in "Custom", exactly like BM2's own spells
--  with no curated class land in its Custom group.
-------------------------------------------------------------------------------

local CLASS_ORDER = {
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

-- Editor scroll (manager-page style bar). Returns UpdateThumb and SetScrollTo(v).
-- rightInset (default 2): only WrapCompensatedBody passes more, since its scroll
-- extends padDiff (~25px) past the pane's visible right edge. panelWheel: a pane
-- inside the options panel (Shift + wheel scales the panel), not a popup editor.
AttachEditorScroll = function(scroller, childFrame, onScroll, rightInset, panelWheel)
    return CludesUI.AttachSmoothScrollbar(scroller, {
        step = 60,
        thumbMin = 20,
        rightInset = rightInset,
        topInset = 2,
        level = 5,
        trackAlpha = 0.05,
        thumbAlpha = 0.22,
        child = childFrame,
        onScroll = onScroll,
        panelWheel = panelWheel,
    })
end

function mod.PABMP_ShowFilterEditor()
    -- A shown editor is not hidden here: PoolKept below dresses the same
    -- window again, and its reset hides it first (its OnHide hooks run with
    -- the old scripts) and notes the control under a still cursor for the
    -- pool's hover replay. A window the pool cannot reset is hidden as the
    -- pool replaces it.
    mod._pabFilterEditor = nil
    local filters = SortFiltersCanonical((mod.PAB_Filters and mod.PAB_Filters()) or {})
    local fontFile = (CludesUI.GetFontPath("unitFrames")) or "Fonts\\FRIZQT__.TTF"
    local ar, ag, ab = 1, 0.82, 0.30
    if CludesUI.GetAccentColor then
        ar, ag, ab = CludesUI.GetAccentColor()
    end
    local brandGreen = CludesUI.CLUDES_GREEN or { r = 0.30, g = 0.79, b = 0.94 }
    local MEDIA_FE = "Interface\\AddOns\\CludesUI\\media\\icons\\"

    local POPUP_W, POPUP_H, SIDE_W = 620, 520, 180

    -- One editor for the session: every open and every Rebuild() dresses the
    -- same dimmer again, and the frames below it come back from the pool.
    local shade, dialog =
        CludesUI.BuildFilterEditorShell(mod, "_pabFilterEditor", "pabFilterEditor", POPUP_W, POPUP_H)

    if pabFilterSel then
        local success = false
        for idx = 1, #filters do
            if filters[idx].id == pabFilterSel then
                success = true
            end
        end
        if not success then
            pabFilterSel = nil
        end
    end
    if not pabFilterSel and filters[1] then
        pabFilterSel = filters[1].id
    end

    local function Rebuild()
        mod.PABMP_ShowFilterEditor()
    end
    local function ApplyAll()
        if mod.PAB_ApplyLiveConfig then
            mod.PAB_ApplyLiveConfig(true)
        end
        -- Every custom bar, editing-spec buckets included: a filter edit
        -- changes any bar assigned to it, whichever bucket owns the bar.
        if mod.PAB_ReloadAllCustomBars then
            mod.PAB_ReloadAllCustomBars()
        end
    end
    local function EditorInput(options)
        CludesUI:ShowInputPopup(options)
        local d = _G.CUIInputDimmer
        if d and mod._pabFilterEditor then
            d:SetFrameLevel(dialog:GetFrameLevel() + 40)
            local p = _G.CUIInputPopup
            if p then
                p:SetFrameLevel(d:GetFrameLevel() + 10)
            end
        end
    end

    -- RIGHT: filter list.
    local side = CreateFrame("Frame", nil, dialog)
    side:SetWidth(SIDE_W)
    side:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", 0, -44)
    side:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", 0, 0)
    side:SetFrameLevel(dialog:GetFrameLevel() + 1)
    local sideBg = CludesUI.SolidTex(side, "BACKGROUND", 0, 0, 0, 0.35)
    sideBg:SetAllPoints()
    -- Flush with the popup's bottom-right corner: same shape, rows clipped to it.
    CludesUI.MakeRoundedBorder(side, 1, 1, 1, 0.10, sideBg, nil, true)

    local sideScroll, sideChild, fy = CludesUI.BuildFilterSidebar(side, SIDE_W, filters, {
        selected = pabFilterSel,
        onPick = function(barId)
            pabFilterSel = barId
            pabFilterScrollPos = 0
        end,
        onAdded = function(barId)
            pabFilterSel = barId
        end,
        delete = mod.PAB_DeleteFilter,
        rename = mod.PAB_RenameFilter,
        add = mod.PAB_AddFilter,
        deleteMessage = "Delete this filter? It is removed from every bar using it.",
        -- Imported Buff Manager presets (f.preset = true) stay protected (no
        -- rename or delete), matching BM2's own guard.
        renamePlaceholder = function(f)
            return L(f.name)
        end,
        apply = ApplyAll,
        rebuild = Rebuild,
        input = EditorInput,
        accent = brandGreen,
    })
    local sideBottom = fy - 8 - 26
    -- One-time copy of the Raid Frames Buff Manager filter library into this
    -- registry (same-named filters replaced, missing ones created; see
    -- PAB_CopyBM2FiltersIn). Hidden while that module is disabled.
    if CludesUI._BM2FilterBridge then
        local copyBtn = CludesUI.BuildPopupButton(
            sideChild,
            SIDE_W - 16,
            26,
            L("Copy Raid & Party Filters"),
            function()
                CludesUI:ShowConfirmPopup({
                    title = L("Copy Raid & Party Filters"),
                    message = L(
                        "One-time copy of the Raid & Party Frames Buff Manager filters into these filters. Same-named filters are OVERWRITTEN; the two lists stay separate afterwards."
                    ),
                    confirmText = L("Copy"),
                    cancelText = L("Cancel"),
                    typeToConfirm = "Confirm",
                    onConfirm = function()
                        if mod.PAB_CopyBM2FiltersIn and mod.PAB_CopyBM2FiltersIn() then
                            ApplyAll()
                            Rebuild()
                        end
                    end,
                })
            end
        )
        copyBtn:SetPoint("TOPLEFT", sideChild, "TOPLEFT", 8, sideBottom - 6)
        sideBottom = sideBottom - 6 - 26
    end
    sideChild:SetHeight(math.abs(sideBottom) + 8)
    local updSideThumb = AttachEditorScroll(sideScroll, sideChild)
    updSideThumb()

    -- LEFT: selected filter detail.
    local sel
    for idx = 1, #filters do
        if filters[idx].id == pabFilterSel then
            sel = filters[idx]
        end
    end
    if not sel then
        return
    end

    local function SpellName(ident)
        return C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(ident)
    end
    local leftX, scroller, childFrame = CludesUI.BuildFilterDetail(dialog, SIDE_W, POPUP_W, sel, {
        -- Same curated (deduped) universe as the Extra Spells dropdown.
        searchIds = function()
            local universe = DedupedPresetSpellUniverse()
            local ids = {}
            for idx = 1, #universe do
                local ident = universe[idx]
                -- An id kept only for the other client is not on the filter here.
                if sel.spells[ident] == nil or mod.PAB_OtherClientSpell(sel, ident) then
                    ids[#ids + 1] = ident
                end
            end
            return ids
        end,
        label = SpellName,
        addPicked = function(ident)
            return mod.PAB_AddSpellToFilter and mod.PAB_AddSpellToFilter(sel.id, ident)
        end,
        addTyped = function(ident)
            return mod.PAB_AddSpellToFilter(sel.id, ident)
        end,
        rename = mod.PAB_RenameFilter,
        renamePlaceholder = L(sel.name),
        apply = ApplyAll,
        rebuild = Rebuild,
        input = EditorInput,
    })
    local _updSpellThumb, setSpellScroll = AttachEditorScroll(scroller, childFrame, function(val)
        pabFilterScrollPos = val
    end)

    local function NameOf(ident)
        return (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(ident)) or tostring(ident)
    end

    -- Display-only dedup by name, same reasoning/pattern as DedupedPresetSpellUniverse:
    -- sel.spells legitimately contains both a primary spellID and its rank/talent
    -- `alts` as separate keys (BM2_ FILTER_SEED already flattens alts in -- see that
    -- table's own doc comment), which BM2's own checkbox list never shows as separate
    -- rows (it only iterates primary keys). Without this, curated filters like "Raid
    -- CDs" show the same buff (e.g. Rallying Cry) twice. First (lowest) spellID per
    -- name wins and keeps its row -- ids are visited in sorted order (pairs() has no
    -- defined order) so the winner is deterministic across rebuilds. ResolveSpells
    -- still unions every enabled id in sel.spells regardless of which one has a visible
    -- checkbox, so this changes nothing about which auras get tracked -- only which row
    -- the user toggles them from.
    local hints = mod.PAB_SPELL_CLASS_HINTS or {}
    local allIds = {}
    for ident in pairs(sel.spells) do
        -- Ids kept only for the other client (ns.PAB_OtherClientSpell) get no row.
        if not mod.PAB_OtherClientSpell(sel, ident) then
            allIds[#allIds + 1] = ident
        end
    end
    table.sort(allIds)
    local byClass, customList = {}, {}
    local seenSet = {}
    for idx = 1, #allIds do
        local ident = allIds[idx]
        local dedupKey = NameOf(ident)
        if not seenSet[dedupKey] then
            seenSet[dedupKey] = true
            local cls = hints[ident]
            if cls then
                byClass[cls] = byClass[cls] or {}
                table.insert(byClass[cls], ident)
            else
                table.insert(customList, ident)
            end
        end
    end
    local function ByName(a, b)
        local na, nb = NameOf(a), NameOf(b)
        if na == nb then
            return a < b
        end
        return na < nb
    end
    for _, entries in pairs(byClass) do
        table.sort(entries, ByName)
    end
    table.sort(customList, ByName)

    CludesUI.BuildFilterSpellList(
        childFrame,
        {
            { L("Custom"), customList },
        },
        byClass,
        CLASS_ORDER,
        {
            spells = sel.spells,
            label = SpellName,
            removable = function()
                return true
            end,
            set = function(ident, value)
                mod.PAB_SetSpellState(sel.id, ident, value)
                ApplyAll()
            end,
            rebuild = Rebuild,
            emptyText = L("No spells yet. Add spell IDs above."),
            accent = brandGreen,
        }
    )

    setSpellScroll(pabFilterScrollPos or 0)
end

-------------------------------------------------------------------------------
--  "Add New" popup -- small Name-only popup shown below the Add Buff Bar /
--  Add Debuff Bar button, mirrors RaidFrames' DebuffManager "Add New"
--  popup chrome (dark fill + border, POPUP_PAD/ROW_H metrics, accent
--  Create button, auto-close on outside click, CUI_RaidFrames_ManagerPages
--  .lua ~line 2244) -- simplified to a single Name field since PAB custom
--  bars don't need a type/filter picker at creation time (everything else
--  is editable afterward in the detail pane, unlike DM's tiles). One
--  shared popup instance toggled/repurposed for both buff and debuff
--  creation via `kind`, same as DM's single ns._dmAddPopup.
-------------------------------------------------------------------------------

local pabAddPopup

local function ShowAddBarPopup(anchorBtn, kindName, fontFile)
    if pabAddPopup and pabAddPopup:IsShown() and pabAddPopup._kind == kindName then
        pabAddPopup:Hide()
        return
    end

    if not pabAddPopup then
        local POPUP_W, POPUP_PAD, ROW_H, LABEL_H, LBL_GAP, GAP = 220, 10, 30, 14, 4, 10
        local dialog = CreateFrame("Frame", nil, UIParent)
        dialog:Hide() -- start hidden so Show() triggers OnShow
        dialog:SetFrameStrata("DIALOG")
        dialog:SetFrameLevel(200)
        dialog:SetSize(POPUP_W, POPUP_PAD + LABEL_H + LBL_GAP + ROW_H + GAP + ROW_H + POPUP_PAD)
        dialog:EnableMouse(true)
        dialog:SetClampedToScreen(true)

        local backdrop = dialog:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(0.067, 0.067, 0.067, 0.95)
        CludesUI.MakeRoundedBorder(dialog, 1, 1, 1, 0.2, backdrop)

        -- Auto-close on outside click, same pattern as DM's Add New popup.
        dialog:SetScript("OnShow", function(p2)
            p2:SetScript("OnUpdate", function(frame)
                if not (frame._anchorBtn and frame._anchorBtn:IsMouseOver()) and not frame:IsMouseOver() then
                    if IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton") then
                        frame:Hide()
                    end
                end
            end)
        end)
        dialog:SetScript("OnHide", function(p2)
            p2:SetScript("OnUpdate", nil)
            if p2._nameBox then
                p2._nameBox:SetText("")
            end
        end)

        local py = -POPUP_PAD
        local nmLbl = dialog:CreateFontString(nil, "OVERLAY")
        nmLbl:SetFont(fontFile, 11, "")
        nmLbl:SetPoint("TOPLEFT", dialog, "TOPLEFT", POPUP_PAD, py)
        nmLbl:SetText(L("Name"))
        nmLbl:SetTextColor(1, 1, 1, 0.6)
        py = py - LABEL_H - LBL_GAP

        local ddW = POPUP_W - POPUP_PAD * 2
        local nameBox = CreateFrame("EditBox", nil, dialog)
        nameBox:SetSize(ddW, ROW_H)
        nameBox:SetPoint("TOPLEFT", dialog, "TOPLEFT", POPUP_PAD, py)
        nameBox:SetAutoFocus(true)
        nameBox:SetFont(fontFile, 12, "")
        nameBox:SetJustifyH("LEFT")
        nameBox:SetTextColor(1, 1, 1, 0.9)
        nameBox:SetTextInsets(10, 10, 0, 0)
        local nbBg = nameBox:CreateTexture(nil, "BACKGROUND")
        nbBg:SetAllPoints()
        nbBg:SetColorTexture(0, 0, 0, 0.5)
        CludesUI.MakeRoundedBorder(nameBox, 1, 1, 1, 0.2, nbBg)
        dialog._nameBox = nameBox
        py = py - ROW_H - GAP

        local accentColor = CludesUI.CLUDES_GREEN or { r = 0.30, g = 0.79, b = 0.94 }
        local cBtn = CreateFrame("Button", nil, dialog)
        cBtn:SetSize(ddW, ROW_H)
        cBtn:SetPoint("TOPLEFT", dialog, "TOPLEFT", POPUP_PAD, py)
        cBtn:SetFrameLevel(dialog:GetFrameLevel() + 1)
        local cBg = cBtn:CreateTexture(nil, "BACKGROUND")
        cBg:SetAllPoints()
        cBg:SetColorTexture(accentColor.r, accentColor.g, accentColor.b, 0.8)
        CludesUI.RoundBody(cBtn, cBg)
        local cTx = cBtn:CreateFontString(nil, "OVERLAY")
        cTx:SetPoint("CENTER")
        cTx:SetFont(fontFile, 12, "")
        cTx:SetText(L("Create"))
        cTx:SetTextColor(1, 1, 1)
        cBtn:SetScript("OnEnter", nil) -- CludesUI.OutlineButton below sets the hover
        CludesUI.OutlineButton(cBtn, cBg, true)
        dialog._createBtn = cBtn

        nameBox:SetScript("OnEnterPressed", function()
            cBtn:Click()
        end)
        nameBox:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
            dialog:Hide()
        end)

        pabAddPopup = dialog
    end

    local dialog = pabAddPopup
    dialog._kind = kindName
    dialog._anchorBtn = anchorBtn
    dialog._nameBox:SetText("")
    dialog._createBtn:SetScript("OnClick", function()
        local textValue = dialog._nameBox:GetText()
        local name = (textValue and textValue ~= "") and textValue or nil
        local barConf
        -- New bars land in the EDITED editing-spec bucket ("allspecs" =
        -- the legacy arrays, today's behavior).
        if kindName == "buff" then
            barConf = mod.PAB_AddCustomBuffBar and mod.PAB_AddCustomBuffBar(name, pabSpecSel)
        else
            barConf = mod.PAB_AddCustomDebuffBar and mod.PAB_AddCustomDebuffBar(name, pabSpecSel)
        end
        dialog:Hide()
        if barConf then
            barPick = { kind = kindName, id = barConf.id }
            inheritPick = nil
            Apply(kindName == "buff", barConf.id)
            CludesUI:RefreshPage(true)
        end
    end)

    dialog:ClearAllPoints()
    local sc = anchorBtn:GetEffectiveScale() / UIParent:GetEffectiveScale()
    dialog:SetScale(sc)
    dialog:SetPoint("TOP", anchorBtn, "BOTTOM", 0, -12)
    dialog:Show()
    dialog._nameBox:SetFocus()
end

-------------------------------------------------------------------------------
--  Page entry point
-------------------------------------------------------------------------------

-- Between renders the kept root waits hidden under a holder of its own (made
-- once), off the shared scroll frame whose children the other manager pages'
-- roots join; its next render (Pool.Kept) puts it back on the scroll frame.
-- ns._pabRoot = nil means "needs a render". Called where the page is left.
local pabRootPark
function mod.PABMP_ParkRoot()
    local rootFrame = mod._pabRoot
    if not rootFrame then
        return
    end
    mod._pabRoot = nil
    rootFrame:Hide()
    if not pabRootPark then
        pabRootPark = CreateFrame("Frame", nil, UIParent)
        pabRootPark:Hide()
    end
    rootFrame:SetParent(pabRootPark)
end

function mod.PABMP_BuildPage(page, hostFrame, yOffset)
    local scrollFrame = CludesUI._scrollFrame
    if not scrollFrame then
        return 0
    end
    -- The refresh callbacks of the previous render of this root leave the live
    -- list before this render records its own (also for the render the panel's
    -- on-show runs outside a page pass).
    CludesUI._BeginRootRender(PAB_RENDER_KEY)
    local fontFile = (CludesUI.GetFontPath("unitFrames")) or "Fonts\\FRIZQT__.TTF"

    -- Runs every time this page opens, not just when empty: creates any
    -- missing curated presets AND retroactively re-flags already-existing
    -- ones as protected (f.preset = true) -- needed once to fix filters
    -- imported before that flag existed, and keeps future seed-data
    -- changes in sync. Fully idempotent and cheap (name lookup over 10
    -- entries). Presets are no longer deletable via the UI, so there's no
    -- "silently reappears after deletion" concern any more either.
    if mod.PAB_ImportBM2Filters then
        mod.PAB_ImportBM2Filters()
    end

    local parentW = scrollFrame:GetWidth()
    local fullH = scrollFrame:GetHeight()
    local sidebarW = floor(parentW * 0.28) - 20
    local leftW = parentW - sidebarW

    -- One root for the session: every render dresses it again (the reset hides
    -- and parks the previous render's frames) on the scroll frame; a root it
    -- replaced is parked.
    local outerRoot = PoolKept(mod, "pabRoot", "Frame", scrollFrame)
    outerRoot:SetAllPoints(scrollFrame)
    outerRoot:SetFrameLevel(scrollFrame:GetFrameLevel() + 5)
    if mod._pabRoot ~= outerRoot then
        mod.PABMP_ParkRoot()
    end
    if CludesUI._pickMenu then
        CludesUI._pickMenu:Hide()
    end
    -- The Add Bar popup hangs on an Add button of the previous render, which
    -- this render dresses again (maybe as another control): it closes, as the
    -- pick menu does.
    if pabAddPopup then
        pabAddPopup:Hide()
    end
    mod._pabRoot = outerRoot

    -- Editing-spec bucket sanity: stale/unknown keys reset to All Specs.
    if
        pabSpecSel ~= "allspecs"
        and not SPEC_GROUP_INFO[pabSpecSel]
        and not (type(pabSpecSel) == "string" and pabSpecSel:match("^spec%d"))
    then
        pabSpecSel = "allspecs"
    end
    -- WoW Forever lists All Specs and one row per class, keyed to the bucket
    -- that class renders now: a group view resets to All Specs and a spec
    -- view follows its class's current bucket (it moves with the profile and
    -- when that bucket loses its last bar or per-spec disable).
    if CludesUI.IS_FOREVER and pabSpecSel ~= "allspecs" then
        local m = type(pabSpecSel) == "string" and pabSpecSel:match("^spec(%d+)$")
        local cls = m and CludesUI.SpecClassOf(tonumber(m))
        pabSpecSel = (cls and mod.PAB_ForeverKey(cls)) or "allspecs"
    end
    local buffBars = mod.PAB_BucketBars and mod.PAB_BucketBars(true, pabSpecSel) or {}
    local debuffBars = mod.PAB_BucketBars and mod.PAB_BucketBars(false, pabSpecSel) or {}

    -- Group buckets this view inherits from (concrete "spec<ID>" views
    -- only): their bars lead each section as read-only tiles.
    local inhGroups = mod.PAB_InheritedGroupsFor and mod.PAB_InheritedGroupsFor(pabSpecSel) or nil

    -- Inherited selection: resolve against the owning group's bucket; drop
    -- it when the view no longer inherits that group or the bar is gone.
    local pabInhBar = nil
    if inheritPick and inhGroups then
        for gi = 1, #inhGroups do
            if inhGroups[gi] == inheritPick.group then
                local gl = mod.PAB_BucketBars
                    and mod.PAB_BucketBars(inheritPick.kind == "buff", inheritPick.group)
                for idx = 1, #(gl or {}) do
                    if gl[idx].id == inheritPick.id then
                        pabInhBar = gl[idx]
                        break
                    end
                end
                break
            end
        end
    end
    if not pabInhBar then
        inheritPick = nil
    end

    -- Validate selection against current data (bar may have been deleted
    -- elsewhere, e.g. profile switch). "default" is always valid (the two
    -- fixed built-in bars, not custom-bar list entries).
    if barPick and barPick.id ~= "default" then
        local success = false
        local entries = (barPick.kind == "buff") and buffBars or debuffBars
        for idx = 1, #entries do
            if entries[idx].id == barPick.id then
                success = true
            end
        end
        if not success then
            barPick = { kind = "buff", id = "default" }
        end
    end

    -- Use Blizzard Buffs: the built-in bars stand down (Blizzard's native
    -- display owns buffs/debuffs) and their sidebar tiles hide everywhere.
    local sPABTop = mod.db and mod.db.profile and mod.db.profile.playerAuraBars
    -- Defensive migrations (lane split + empty-bar -> All + disabled): the
    -- default tiles below read cfg.enabled, so the enable migration must
    -- have run.
    if sPABTop and mod.PAB_EnsureBarEnable then
        mod.PAB_EnsureBarEnable(sPABTop)
    end
    local useBlizz = (sPABTop and sPABTop.useBlizzardBuffs == true) or false
    -- The default Buffs/Debuffs bars are ALL SPECS content: they list in the
    -- All Specs view (editable) and on concrete spec views (specs show
    -- everything the all-buckets apply to them), but NEVER in the other
    -- group views -- groups don't inherit from each other (BM parity;
    -- All-Specs content is already covered by the All Specs bucket).
    local showDefaults = not useBlizz
        and (
            pabSpecSel == "allspecs"
            or (type(pabSpecSel) == "string" and pabSpecSel:match("^spec%d") ~= nil)
        )
    -- A "default" selection re-targets the first custom bar (or nothing)
    -- whenever the default tiles are not listed in this view.
    if not showDefaults and barPick and barPick.id == "default" then
        local first = buffBars[1] or debuffBars[1]
        if first then
            barPick = { kind = buffBars[1] and "buff" or "debuff", id = first.id }
        else
            barPick = nil
        end
    end
    -- Back on a defaults-listing view with nothing selected: re-seed the
    -- default selection so the detail pane never stays blank.
    if showDefaults and not barPick then
        barPick = { kind = "buff", id = "default" }
    end

    -- Page-level "Player Aura Bars" header card removed (by request:
    -- it competed visually with the new per-bar preview box now sitting at the top of
    -- each detail pane). HEADER_H kept at 0 rather than removed outright so `root`'s
    -- offset math below still reads clearly as "below the (now empty) header band".
    local HEADER_H = 0

    local rootFrame = CreateFrame("Frame", nil, outerRoot)
    rootFrame:SetPoint("TOPLEFT", outerRoot, "TOPLEFT", 0, -HEADER_H)
    rootFrame:SetPoint("BOTTOMRIGHT", outerRoot, "BOTTOMRIGHT", 0, 0)
    rootFrame:SetFrameLevel(outerRoot:GetFrameLevel() + 1)
    local visibleH = fullH - HEADER_H

    local sideOuter = CreateFrame("Frame", nil, rootFrame)
    sideOuter:SetSize(sidebarW, visibleH)
    sideOuter:SetPoint("TOPRIGHT", rootFrame, "TOPRIGHT", 0, -1)
    sideOuter:SetFrameLevel(rootFrame:GetFrameLevel() + 1)
    local sbBg = sideOuter:CreateTexture(nil, "BACKGROUND")
    sbBg:SetAllPoints()
    sbBg:SetColorTexture(0, 0, 0, 0.25)
    CludesUI.CardSidebar(sideOuter, sbBg)
    -------------------------------------------------------------------
    --  SECTIONED SIDEBAR (fixed, no outer scroll): top options (Disable
    --  All / Use Blizzard Buffs), Editing Spec, then two independently
    --  scrollable halves (Buff Bars / Debuff Bars).
    -------------------------------------------------------------------
    local pinnedY = -6

    -- The rows' pill and knob, drawn texel to pixel as the settings toggle's
    -- are (CludesUI.MakePixelLayer): a stadium and a circle sized for the
    -- layer's scale, the knob one pad in from the side its state sits on.
    local function OptionPillFit(L, keyName)
        local wid, height = L.parent:GetSize()
        local hp, wp = math.floor(height * keyName + 0.5), math.floor(wid * keyName + 0.5)
        if hp == L.hp and wp == L.wp then
            return
        end
        L.hp, L.wp = hp, wp
        local pad = math.max(1, math.floor(2 * keyName + 0.5))
        local d = math.max(2, hp - 2 * pad)
        -- Square, as the settings toggle is (CludesUI_Widgets.lua PX).
        L.track:SetColorTexture(1, 1, 1, 1)
        L.knob:SetColorTexture(1, 1, 1, 1)
        L.knob:SetSize(d, d)
        L.knob:ClearAllPoints()
        L.knob:SetPoint("TOPLEFT", L._frame, "TOPLEFT", L.on and (wp - pad - d) or pad, -pad)
    end

    -- Toggle row helper (label left, tile-style pill right).
    local function OptionRow(posY, labelText, status, tooltip, onToggle)
        local row = CreateFrame("Frame", nil, sideOuter)
        row:SetSize(sidebarW, 26)
        row:SetPoint("TOPLEFT", sideOuter, "TOPLEFT", 0, posY)
        row:SetFrameLevel(sideOuter:GetFrameLevel() + 1)
        row:EnableMouse(true)
        local labelFS = row:CreateFontString(nil, "OVERLAY")
        labelFS:SetFont(fontFile, 12, "")
        labelFS:SetPoint("LEFT", row, "LEFT", 12, 0)
        labelFS:SetPoint("RIGHT", row, "RIGHT", -52, 0)
        labelFS:SetJustifyH("LEFT")
        labelFS:SetWordWrap(false)
        labelFS:SetText(labelText)
        labelFS:SetTextColor(1, 1, 1)
        local button = CreateFrame("Button", nil, row)
        button:SetSize(32, 16)
        button:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        button:SetFrameLevel(row:GetFrameLevel() + 2)
        local L = CludesUI.MakePixelLayer(button, OptionPillFit)
        local pillBg = L._frame:CreateTexture(nil, "BACKGROUND")
        pillBg:SetAllPoints(L._frame)
        local knob = L._frame:CreateTexture(nil, "ARTWORK")
        L.track, L.knob, L.on = pillBg, knob, status and true or false
        L:Fit()
        if status then
            local acr, acg, acb = 0.30, 0.79, 0.94
            if CludesUI.ResolveActiveAccent then
                acr, acg, acb = CludesUI.ResolveActiveAccent()
            end
            pillBg:SetVertexColor(acr, acg, acb, 1)
            knob:SetVertexColor(1, 1, 1, 1)
        else
            pillBg:SetVertexColor(0.25, 0.25, 0.25, 1)
            knob:SetVertexColor(0.5, 0.5, 0.5, 1)
        end
        button:SetScript("OnClick", function()
            onToggle(not status)
        end)
        if tooltip then
            row:SetScript("OnEnter", function()
                CludesUI.ShowWidgetTooltip(row, tooltip)
            end)
            row:SetScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)
            button:HookScript("OnEnter", function()
                CludesUI.ShowWidgetTooltip(row, tooltip)
            end)
            button:HookScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)
        end
        return posY - 26
    end

    -- Disable All: full shutdown, applied live (bars torn down, movers
    -- dropped, Blizzard's native display handed back); a reload is only
    -- recommended cleanup. The page re-covers with the activation overlay,
    -- whose enable action is the way back.
    pinnedY = OptionRow(
        pinnedY,
        L("Disable All"),
        not (mod.PAB_Enabled and mod.PAB_Enabled()),
        L("Turns off Player Aura Bars completely."),
        function(val)
            if not val then
                return
            end
            if mod.PAB_SetEnabled then
                mod.PAB_SetEnabled(false)
            end
            CludesUI:RefreshPage(true)
            CludesUI:ShowConfirmPopup({
                title = "Reload Recommended",
                message = L(
                    "Player Aura Bars are disabled and Blizzard's default display is back. A UI reload is recommended to finish cleanup."
                ),
                confirmText = "Reload Now",
                cancelText = "Later",
                reload = true,
            })
        end
    )

    -- Use Blizzard Buffs: the built-in Buffs/Debuffs bars stand down and
    -- Blizzard's native display returns, all live; custom bars keep working.
    pinnedY = OptionRow(
        pinnedY,
        L("Use Blizzard Buffs"),
        useBlizz,
        L(
            "Keeps Blizzard's own buff and debuff display and turns off the built-in Buffs and Debuffs bars. Custom bars keep working."
        ),
        function(val)
            if not sPABTop then
                return
            end
            sPABTop.useBlizzardBuffs = val and true or nil
            if mod.PAB_ApplyUseBlizzard then
                mod.PAB_ApplyUseBlizzard()
            end
            CludesUI:RefreshPage(true)
        end
    )
    -- No divider under the toggles (user call): just breathing room before
    -- the Editing Spec block.
    pinnedY = pinnedY - 9

    local function SectionDivider(posY)
        local divider = sideOuter:CreateTexture(nil, "ARTWORK")
        divider:SetHeight(1)
        divider:SetPoint("TOPLEFT", sideOuter, "TOPLEFT", 8, posY - 4)
        divider:SetPoint("TOPRIGHT", sideOuter, "TOPRIGHT", -8, posY - 4)
        divider:SetColorTexture(1, 1, 1, 0.08)
        return posY - 9
    end

    -------------------------------------------------------------------
    --  EDITING SPEC (fixed block): group buckets lead, then every spec
    --  in the game as its own "spec<ID>" bucket. Bars in the selected
    --  bucket render only on matching specs; concrete views list the
    --  group bars as inherited read-only tiles below.
    -------------------------------------------------------------------
    do
        local specLabel = sideOuter:CreateFontString(nil, "OVERLAY")
        specLabel:SetFont(fontFile, 11, "")
        specLabel:SetPoint("TOP", sideOuter, "TOPLEFT", floor(sidebarW / 2), pinnedY - 8)
        specLabel:SetText(L("EDITING SPEC"))
        specLabel:SetTextColor(0.6, 0.6, 0.6)
        pinnedY = pinnedY - 27

        -- Roster shared with the right-click "Add To" menu (the menu
        -- rebuilds it lazily per open). WoW Forever: All Specs, then one
        -- row per class keyed to the bucket that class renders.
        local specDDValues, specDDOrder, specDDIcons = CludesUI.BuildSpecBucketRoster(nil, mod.PAB_ForeverKey)
        specDDValues._menuOpts = {
            maxHeight = 300,
            icon = function(key)
                return specDDIcons[key]
            end,
        }

        local specDD = CludesUI.BuildDropdownControl(
            sideOuter,
            sidebarW - 24,
            sideOuter:GetFrameLevel() + 2,
            specDDValues,
            specDDOrder,
            function()
                return pabSpecSel or "allspecs"
            end,
            function(val)
                pabSpecSel = val
                barPick = { kind = "buff", id = "default" }
                inheritPick = nil
                CludesUI:RefreshPage(true)
            end
        )
        specDD:SetPoint("TOP", sideOuter, "TOPLEFT", floor(sidebarW / 2), pinnedY)
        pinnedY = pinnedY - 36
    end
    pinnedY = SectionDivider(pinnedY)

    -------------------------------------------------------------------
    --  Split halves (Buff Bars / Debuff Bars), each its own scroll; the
    --  sidebar itself no longer scrolls.
    -------------------------------------------------------------------
    local fixedH = math.abs(pinnedY)
    -- Floor keeps the halves from collapsing/overlapping at pathological
    -- window heights (the sidebar also clips its children).
    local half = math.max(60, floor((visibleH - fixedH) / 2))
    sideOuter:SetClipsChildren(true)

    local function MakeSection(posY, height, headerText)
        local heading = sideOuter:CreateFontString(nil, "OVERLAY")
        heading:SetFont(fontFile, 11, "")
        heading:SetPoint("TOP", sideOuter, "TOPLEFT", floor(sidebarW / 2), posY - 13)
        heading:SetText(headerText)
        heading:SetTextColor(0.6, 0.6, 0.6)
        local scroller = CreateFrame("ScrollFrame", nil, sideOuter)
        scroller:SetPoint("TOPLEFT", sideOuter, "TOPLEFT", 0, posY - 32)
        scroller:SetSize(sidebarW, math.max(10, height - 32))
        scroller:SetClipsChildren(true)
        local childFrame = CreateFrame("Frame", nil, scroller)
        childFrame:SetWidth(sidebarW)
        scroller:SetScrollChild(childFrame)
        -- The standard smooth scroll + auto-hiding 4px scrollbar.
        local updateThumb = AttachEditorScroll(scroller, childFrame)
        return {
            child = childFrame,
            scroll = scroller,
            top = posY,
            height = height,
            viewH = math.max(10, height - 32),
            updateThumb = updateThumb,
        }
    end

    -- Finalizes one section: the Add button FLOWS under the tiles while
    -- everything fits, and PINS to the section bottom (always visible) once
    -- the list overflows -- the viewport then ends above the button band and
    -- the scrollbar appears.
    local ADD_AREA = 50 -- AddNewButton's consumed height (pad + button + pad)
    local function FinishSection(sec, tilesY, labelText, onClick)
        local contentH = math.abs(tilesY)
        if contentH + ADD_AREA <= sec.viewH then
            AddNewButton(sec.child, tilesY, sidebarW, labelText, onClick)
            sec.child:SetHeight(math.max(10, contentH + ADD_AREA))
        else
            sec.scroll:SetHeight(math.max(10, sec.viewH - ADD_AREA))
            sec.child:SetHeight(contentH + 6)
            AddNewButton(sideOuter, sec.top - sec.height + ADD_AREA, sidebarW, labelText, onClick)
        end
        -- Prime the scrollbar's visibility (it otherwise first paints on the
        -- first wheel/drag).
        if sec.updateThumb then
            sec.updateThumb()
        end
    end

    local buffSec = MakeSection(pinnedY, half, L("BUFF BARS"))
    local buffChild = buffSec.child
    -- 2% white wash over the whole Buff Bars half (header + list): visual
    -- separation from the debuff half below (user call). BACKGROUND
    -- sublevel 1 sits above the sidebar's own dark bg; tiles render above
    -- both (their frames level higher). Top edge starts at fixedY + 4 --
    -- flush against the divider LINE above (SectionDivider draws it 4px
    -- above the y it returns); bottom edge lands exactly on the
    -- between-halves divider.
    do
        local wash = sideOuter:CreateTexture(nil, "BACKGROUND", nil, 1)
        wash:SetPoint("TOPLEFT", sideOuter, "TOPLEFT", 0, pinnedY + 4)
        wash:SetPoint("TOPRIGHT", sideOuter, "TOPRIGHT", 0, pinnedY + 4)
        wash:SetHeight(half + 4)
        wash:SetColorTexture(1, 1, 1, 0.02)
    end
    local debuffTop = pinnedY - half
    do
        local divider = sideOuter:CreateTexture(nil, "ARTWORK")
        divider:SetHeight(1)
        divider:SetPoint("TOPLEFT", sideOuter, "TOPLEFT", 8, debuffTop)
        divider:SetPoint("TOPRIGHT", sideOuter, "TOPRIGHT", -8, debuffTop)
        divider:SetColorTexture(1, 1, 1, 0.08)
    end
    local debuffSec = MakeSection(debuffTop - 1, visibleH - fixedH - half - 1, L("DEBUFF BARS"))
    local debuffChild = debuffSec.child

    -- Inherited bar tiles for one section (concrete spec views only):
    -- read-only rows -- edit them in their group; the pill toggles ONLY
    -- this spec's enable (ns.PAB_SetInhDisabled). Builds into the given
    -- section child at y; returns the new y cursor.
    local function BuildInheritedBarTiles(sectionChild, tileTop, buffBar)
        if not inhGroups then
            return tileTop
        end
        for gi = 1, #inhGroups do
            local gkey = inhGroups[gi]
            local ginfo = SPEC_GROUP_INFO[gkey]
            local gname = ginfo and L(ginfo.name) or gkey
            local gl = (mod.PAB_BucketBars and mod.PAB_BucketBars(buffBar, gkey)) or {}
            for idx = 1, #gl do
                local barConf = gl[idx]
                local disHere = mod.PAB_InhDisabled and mod.PAB_InhDisabled(pabSpecSel, barConf.id)
                local kindName = buffBar and "buff" or "debuff"
                tileTop = tileTop
                    - BuildTile(sectionChild, tileTop, {
                        width = sidebarW,
                        fontPath = fontFile,
                        title = L(barConf.name or (buffBar and "Buff Bar" or "Debuff Bar")),
                        subtitle = gname,
                        inheritedTooltip = CludesUI.Lf("Inherited from %1$s. Editable only there.", gname),
                        selected = (
                            inheritPick
                            and inheritPick.kind == kindName
                            and inheritPick.group == gkey
                            and inheritPick.id == barConf.id
                        )
                                and true
                            or false,
                        -- Pill = the PER-SPEC enable only; a group-level disable
                        -- dims the tile instead (the pill must never look dead).
                        dimmed = barConf.enabled == false or nil,
                        enabled = (not disHere) and true or false,
                        showToggle = true,
                        onSelect = function()
                            inheritPick = { kind = kindName, group = gkey, id = barConf.id }
                            CludesUI:RefreshPage(true)
                        end,
                        onToggle = function()
                            if not (mod.PAB_SetInhDisabled and mod.PAB_InhDisabled) then
                                return
                            end
                            mod.PAB_SetInhDisabled(
                                pabSpecSel,
                                barConf.id,
                                not mod.PAB_InhDisabled(pabSpecSel, barConf.id)
                            )
                            Apply(buffBar, barConf.id)
                            CludesUI:RefreshPage(true)
                        end,
                    })
            end
        end
        return tileTop
    end

    -- Buff bars section (top half): fixed "Buffs" default bar first (hidden
    -- while Use Blizzard Buffs owns the display), then custom bars.
    do
        local sidebarChild = buffChild -- section-scoped: this half's scroll child
        local tileTop = 0

        -- Name follows the bar's content (see DefaultBuffBarName). Static, not
        -- a refresh client: every toggle that can change it forces a full page
        -- rebuild, which re-runs this.
        local sPAB = sPABTop
        local defBuffCfg = sPAB and mod.PAB_DefaultBuffsCfg and mod.PAB_DefaultBuffsCfg(sPAB) or nil
        if showDefaults then
            tileTop = tileTop
                - BuildTile(sidebarChild, tileTop, {
                    width = sidebarW,
                    fontPath = fontFile,
                    title = DefaultBuffBarName(defBuffCfg),
                    subtitle = L("Default"),
                    selected = (
                        barPick
                        and barPick.kind == "buff"
                        and barPick.id == "default"
                        and not inheritPick
                    )
                            and true
                        or false,
                    -- Enable toggle (cfg.enabled, nil = enabled): disables the bar without
                    -- deleting it, custom-bar parity.
                    enabled = not (defBuffCfg and defBuffCfg.enabled == false),
                    showToggle = defBuffCfg ~= nil,
                    onToggle = function(val)
                        if not defBuffCfg then
                            return
                        end
                        if val then
                            defBuffCfg.enabled = nil
                        else
                            defBuffCfg.enabled = false
                        end
                        if mod.PAB_ApplyLiveConfig then
                            mod.PAB_ApplyLiveConfig(true)
                        end
                        -- Re-register so an open unlock session drops/restores the mover.
                        if mod.PAB_RegisterUnlock then
                            mod.PAB_RegisterUnlock()
                        end
                        CludesUI:RefreshPage(true)
                    end,
                    onSelect = function()
                        barPick = { kind = "buff", id = "default" }
                        inheritPick = nil
                        CludesUI:RefreshPage(true)
                    end,
                })
        end
        tileTop = BuildInheritedBarTiles(sidebarChild, tileTop, true)
        for idx = 1, #buffBars do
            local barConf = buffBars[idx]
            tileTop = tileTop
                - BuildTile(sidebarChild, tileTop, {
                    width = sidebarW,
                    fontPath = fontFile,
                    title = L(barConf.name or "Buff Bar"),
                    subtitleFn = function()
                        return BuildBuffBarSubtitle(barConf)
                    end,
                    selected = (barPick and barPick.kind == "buff" and barPick.id == barConf.id and not inheritPick)
                            and true
                        or false,
                    enabled = barConf.enabled and true or false,
                    showToggle = true,
                    onSelect = function()
                        barPick = { kind = "buff", id = barConf.id }
                        inheritPick = nil
                        CludesUI:RefreshPage(true)
                    end,
                    -- Right-click: copy this bar into another editing-spec
                    -- bucket (full clone, fresh id; the source stays).
                    onContext = function(tileFrame)
                        if not CludesUI.ShowPickMenu then
                            return
                        end
                        CludesUI.ShowPickMenu(tileFrame, {
                            title = L("Add To"),
                            fontPath = fontFile,
                            items = CludesUI.SpecBucketMenuItems(pabSpecSel, nil, mod.PAB_ForeverKey),
                            onPick = function(key)
                                local nb = mod.PAB_CopyCustomBar and mod.PAB_CopyCustomBar(true, barConf, key)
                                if nb then
                                    Apply(true, nb.id)
                                    CludesUI:RefreshPage(true)
                                end
                            end,
                        })
                    end,
                    onToggle = function(val)
                        barConf.enabled = val and true or false
                        Apply(true, barConf.id)
                        CludesUI:RefreshPage(true)
                    end,
                    onEdit = function()
                        CludesUI:ShowInputPopup({
                            title = L("Rename Bar"),
                            placeholder = L(barConf.name or "Buff Bar"),
                            confirmText = L("Rename"),
                            cancelText = L("Cancel"),
                            onConfirm = function(textValue)
                                if textValue and textValue ~= "" then
                                    barConf.name = textValue
                                    -- Re-registers this bar's Unlock Mode label from
                                    -- the new bar.name (RegisterPABCustomUnlock reads
                                    -- it live, but only ever re-runs from here) --
                                    -- without this, Unlock Mode kept showing the old
                                    -- name until the next /reload.
                                    Apply(true, barConf.id)
                                end
                                CludesUI:RefreshPage(true)
                            end,
                        })
                    end,
                    onDelete = function()
                        CludesUI:ShowConfirmPopup({
                            title = L("Delete Bar"),
                            message = L("Delete this buff bar?"),
                            confirmText = L("Delete"),
                            cancelText = L("Cancel"),
                            onConfirm = function()
                                mod.PAB_DeleteCustomBuffBar(barConf.id)
                                if barPick and barPick.kind == "buff" and barPick.id == barConf.id then
                                    barPick = { kind = "buff", id = "default" }
                                end
                                Apply(true, barConf.id)
                                CludesUI:RefreshPage(true)
                            end,
                        })
                    end,
                })
        end
        FinishSection(buffSec, tileTop, L("Add Buff Bar"), function(self)
            ShowAddBarPopup(self, "buff", fontFile)
        end)
    end

    -- Debuff bars section (bottom half): fixed "Debuffs" default bar first
    -- (hidden while Use Blizzard Buffs owns the display), then custom.
    do
        local sidebarChild = debuffChild -- section-scoped: this half's scroll child
        local tileTop = 0

        local sPAB2 = sPABTop
        local defDebuffCfg = sPAB2 and mod.PAB_DefaultDebuffsCfg and mod.PAB_DefaultDebuffsCfg(sPAB2) or nil
        if showDefaults then
            tileTop = tileTop
                - BuildTile(sidebarChild, tileTop, {
                    width = sidebarW,
                    fontPath = fontFile,
                    title = L("Debuffs"),
                    subtitle = L("Default"),
                    selected = (
                        barPick
                        and barPick.kind == "debuff"
                        and barPick.id == "default"
                        and not inheritPick
                    )
                            and true
                        or false,
                    -- Enable toggle (cfg.enabled, nil = enabled): custom-bar parity.
                    enabled = not (defDebuffCfg and defDebuffCfg.enabled == false),
                    showToggle = defDebuffCfg ~= nil,
                    onToggle = function(val)
                        if not defDebuffCfg then
                            return
                        end
                        if val then
                            defDebuffCfg.enabled = nil
                        else
                            defDebuffCfg.enabled = false
                        end
                        if mod.PAB_ApplyLiveConfig then
                            mod.PAB_ApplyLiveConfig(false)
                        end
                        -- Re-register so an open unlock session drops/restores the mover.
                        if mod.PAB_RegisterUnlock then
                            mod.PAB_RegisterUnlock()
                        end
                        CludesUI:RefreshPage(true)
                    end,
                    onSelect = function()
                        barPick = { kind = "debuff", id = "default" }
                        inheritPick = nil
                        CludesUI:RefreshPage(true)
                    end,
                })
        end

        tileTop = BuildInheritedBarTiles(sidebarChild, tileTop, false)
        for idx = 1, #debuffBars do
            local barConf = debuffBars[idx]
            tileTop = tileTop
                - BuildTile(sidebarChild, tileTop, {
                    width = sidebarW,
                    fontPath = fontFile,
                    title = L(barConf.name or "Debuff Bar"),
                    subtitleFn = function()
                        return BuildDebuffBarSubtitle(barConf)
                    end,
                    selected = (barPick and barPick.kind == "debuff" and barPick.id == barConf.id and not inheritPick)
                            and true
                        or false,
                    enabled = barConf.enabled and true or false,
                    showToggle = true,
                    onSelect = function()
                        barPick = { kind = "debuff", id = barConf.id }
                        inheritPick = nil
                        CludesUI:RefreshPage(true)
                    end,
                    -- Right-click: copy this bar into another editing-spec
                    -- bucket (full clone, fresh id; the source stays).
                    onContext = function(tileFrame)
                        if not CludesUI.ShowPickMenu then
                            return
                        end
                        CludesUI.ShowPickMenu(tileFrame, {
                            title = L("Add To"),
                            fontPath = fontFile,
                            items = CludesUI.SpecBucketMenuItems(pabSpecSel, nil, mod.PAB_ForeverKey),
                            onPick = function(key)
                                local nb = mod.PAB_CopyCustomBar and mod.PAB_CopyCustomBar(false, barConf, key)
                                if nb then
                                    Apply(false, nb.id)
                                    CludesUI:RefreshPage(true)
                                end
                            end,
                        })
                    end,
                    onToggle = function(val)
                        barConf.enabled = val and true or false
                        Apply(false, barConf.id)
                        CludesUI:RefreshPage(true)
                    end,
                    onEdit = function()
                        CludesUI:ShowInputPopup({
                            title = L("Rename Bar"),
                            placeholder = L(barConf.name or "Debuff Bar"),
                            confirmText = L("Rename"),
                            cancelText = L("Cancel"),
                            onConfirm = function(textValue)
                                if textValue and textValue ~= "" then
                                    barConf.name = textValue
                                    -- Re-registers this bar's Unlock Mode label from
                                    -- the new bar.name (RegisterPABCustomUnlock reads
                                    -- it live, but only ever re-runs from here) --
                                    -- without this, Unlock Mode kept showing the old
                                    -- name until the next /reload.
                                    Apply(false, barConf.id)
                                end
                                CludesUI:RefreshPage(true)
                            end,
                        })
                    end,
                    onDelete = function()
                        CludesUI:ShowConfirmPopup({
                            title = L("Delete Bar"),
                            message = L("Delete this debuff bar?"),
                            confirmText = L("Delete"),
                            cancelText = L("Cancel"),
                            onConfirm = function()
                                mod.PAB_DeleteCustomDebuffBar(barConf.id)
                                if barPick and barPick.kind == "debuff" and barPick.id == barConf.id then
                                    barPick = { kind = "debuff", id = "default" }
                                end
                                Apply(false, barConf.id)
                                CludesUI:RefreshPage(true)
                            end,
                        })
                    end,
                })
        end
        FinishSection(debuffSec, tileTop, L("Add Debuff Bar"), function(self)
            ShowAddBarPopup(self, "debuff", fontFile)
        end)
    end

    local detail = CreateFrame("Frame", nil, rootFrame)
    detail:SetPoint("TOPLEFT", rootFrame, "TOPLEFT", 0, 0)
    detail:SetSize(leftW, visibleH)
    detail:SetFrameLevel(rootFrame:GetFrameLevel() + 1)

    if inheritPick and pabInhBar then
        -- Read-only pane for an INHERITED group bar: where it lives, a jump
        -- link to the owning group, and a pointer at the tile toggle for the
        -- per-spec enable. No settings render -- edits belong to the group.
        local ginfo = SPEC_GROUP_INFO[inheritPick.group]
        local gname = ginfo and L(ginfo.name) or inheritPick.group
        local title = detail:CreateFontString(nil, "OVERLAY")
        title:SetFont(fontFile, 18, "")
        title:SetPoint("TOPLEFT", detail, "TOPLEFT", 25, -25)
        title:SetTextColor(0.55, 0.72, 1)
        title:SetText(pabInhBar.name or (inheritPick.kind == "buff" and L("Buff Bar") or L("Debuff Bar")))
        local subMenu = detail:CreateFontString(nil, "OVERLAY")
        subMenu:SetFont(fontFile, 13, "")
        subMenu:SetPoint("LEFT", title, "RIGHT", 6, 0)
        subMenu:SetTextColor(0.75, 0.75, 0.75, 0.65)
        subMenu:SetText("(" .. CludesUI.Lf("Inherited from %1$s", gname) .. ")")
        local details = detail:CreateFontString(nil, "OVERLAY")
        details:SetFont(fontFile, 12, "")
        details:SetPoint("TOPLEFT", detail, "TOPLEFT", 25, -58)
        details:SetPoint("RIGHT", detail, "RIGHT", -35, 0)
        details:SetJustifyH("LEFT")
        details:SetWordWrap(true)
        details:SetText(
            CludesUI.Lf(
                "Inherited from %1$s. Edit it there, or use the tile toggle to enable or disable it for this spec.",
                gname
            )
        )
        details:SetTextColor(0.65, 0.65, 0.65)
        local itemLink = CreateFrame("Button", nil, detail)
        itemLink:SetPoint("TOPLEFT", detail, "TOPLEFT", 25, -108)
        itemLink:SetFrameLevel(detail:GetFrameLevel() + 2)
        local linkFS = itemLink:CreateFontString(nil, "OVERLAY")
        linkFS:SetFont(fontFile, 12, "")
        linkFS:SetPoint("TOPLEFT")
        linkFS:SetText(CludesUI.Lf("Edit in %1$s", gname))
        local lac = CludesUI.CLUDES_GREEN
        if lac then
            linkFS:SetTextColor(lac.r, lac.g, lac.b, 0.85)
        else
            linkFS:SetTextColor(0.30, 0.79, 0.94, 0.85)
        end
        itemLink:SetSize(linkFS:GetStringWidth() + 4, 18)
        itemLink:SetScript("OnEnter", function()
            linkFS:SetAlpha(1)
        end)
        itemLink:SetScript("OnLeave", function()
            linkFS:SetAlpha(0.85)
        end)
        local jumpKind, jumpGroup, jumpId = inheritPick.kind, inheritPick.group, inheritPick.id
        itemLink:SetScript("OnClick", function()
            pabSpecSel = jumpGroup
            barPick = { kind = jumpKind, id = jumpId }
            inheritPick = nil
            CludesUI:RefreshPage(true)
        end)
    elseif barPick then
        if barPick.id == "default" then
            BuildDefaultBarDetail(detail, fontFile, barPick.kind == "buff")
        elseif barPick.kind == "buff" then
            local barConf = mod.PAB_GetCustomBuffBar and mod.PAB_GetCustomBuffBar(barPick.id)
            if barConf then
                BuildBuffBarDetail(detail, fontFile, barConf)
            end
        else
            local barConf = mod.PAB_GetCustomDebuffBar and mod.PAB_GetCustomDebuffBar(barPick.id)
            if barConf then
                BuildDebuffBarDetail(detail, fontFile, barConf)
            end
        end
    end

    -- Activation overlay (same chrome as the Debuff Manager page's override/activation
    -- overlay): PAB ships disabled, so the whole page sits under a dark cover with a
    -- single enable action until the user opts in. Built LAST so it covers sidebar +
    -- detail; child of outerRoot so every teardown path destroys it.
    if not (mod.PAB_Enabled and mod.PAB_Enabled()) then
        local _, button = CludesUI.BuildActivationOverlay(outerRoot, {
            fontPath = fontFile,
            width = parentW,
            title = L("Player Aura Bars"),
            text = L("Replaces Blizzard's default buff and debuff display with fully customizable bars."),
            buttonLabel = L("Enable Player Aura Bars"),
        })
        button:SetScript("OnClick", function()
            if mod.PAB_SetEnabled then
                mod.PAB_SetEnabled(true)
            end
            CludesUI:RefreshPage(true)
        end)
    end

    CludesUI._EndRootRender(PAB_RENDER_KEY)
    return 0
end
