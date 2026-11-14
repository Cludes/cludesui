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
local pabSel = { kind = "buff", id = "default" }
-- Editing-spec bucket: "allspecs" (the legacy bar arrays), a group bucket
-- key, or a concrete "spec<ID>". Session-sticky like pabSel.
local pabSpecSel = "allspecs"
-- Inherited-bar selection ({kind, group, id}); wins over pabSel while set.
local pabInhSel = nil

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
CludesUI._setPABSelection = function(kind, ident, bucket)
    pabSel = { kind = kind, id = ident or "default" }
    pabInhSel = nil
    if bucket then
        pabSpecSel = bucket
    elseif
        pabSel.id == "default"
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
            local bar = buffBars[idx]
            entries[#entries + 1] = {
                key = "custombuff_" .. bar.id,
                label = bar.name or "Buff Bar",
                isBuff = true,
                cfg = bar,
            }
        end
    end
    local debuffBars = mod.PAB_CustomDebuffBars and mod.PAB_CustomDebuffBars()
    if debuffBars then
        for idx = 1, #debuffBars do
            local bar = debuffBars[idx]
            entries[#entries + 1] = {
                key = "customdebuff_" .. bar.id,
                label = bar.name or "Debuff Bar",
                isBuff = false,
                cfg = bar,
            }
        end
    end
    return entries
end

-- Which PabAllBarEntries() row a given (cfg, isBuff) pair is.
local function PabBarKeyOf(conf, isBuff)
    local s = mod.db and mod.db.profile and mod.db.profile.playerAuraBars
    if s then
        if conf == mod.PAB_DefaultBuffsCfg(s) then
            return "buffs"
        end
        if conf == mod.PAB_DefaultDebuffsCfg(s) then
            return "debuffs"
        end
    end
    if conf.id then
        return (isBuff and "custombuff_" or "customdebuff_") .. conf.id
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
    local seenNames, result = {}, {}
    for idx = 1, #universe do
        local ident = universe[idx]
        local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(ident)
        local dedupKey = name or ("id:" .. ident)
        if not seenNames[dedupKey] then
            seenNames[dedupKey] = true
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
    table.sort(result, function(a, b)
        return (rank[a.name] or (1000 + place[a])) < (rank[b.name] or (1000 + place[b]))
    end)
    return result
end

local function DedupedFilterItems()
    local filters = (mod.PAB_Filters and mod.PAB_Filters()) or {}
    local seenNames, result = {}, {}
    for idx = 1, #filters do
        local f = filters[idx]
        if not seenNames[f.name] then
            seenNames[f.name] = true
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
local function DefaultBuffBarName(conf)
    return L(mod.PAB_DefaultBuffsName and mod.PAB_DefaultBuffsName(conf) or "Buffs")
end

local function BuildBuffBarSubtitle(bar)
    local extraCount = bar.spells and #bar.spells or 0
    local nHidden = 0
    -- Presets only the other client offers are not listed here, so they do not count.
    if bar.negFilters then
        for fid in pairs(bar.negFilters) do
            if not mod.PAB_HiddenPresetFilter(fid) then
                nHidden = nHidden + 1
            end
        end
    end

    if bar.showAllBuffs ~= false or bar.hasDuration == true then
        local txt = (bar.showAllBuffs ~= false) and L("All Buffs") or L("Has Duration")
        if extraCount > 0 then
            txt = txt .. " + " .. extraCount .. " " .. L("spells")
        end
        if nHidden > 0 then
            txt = txt .. ", " .. nHidden .. " " .. L("hidden")
        end
        return txt
    end

    local nameList, totalSelected = {}, 0
    if bar.filters then
        local allFilters = mod.PAB_Filters and mod.PAB_Filters()
        if allFilters then
            for idx = 1, #allFilters do
                local f = allFilters[idx]
                if bar.filters[f.id] then
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
    if nHidden > 0 then
        labelText = labelText .. ", " .. nHidden .. " " .. L("hidden")
    end
    return labelText
end

-- Custom debuff bar sidebar tile subtitle -- same "reflect the actual
-- ASSIGNED DEBUFFS config" fix as BuildBuffBarSubtitle above, just for the
-- debuff shape (bar.showAllDebuffs + bar.classFilters, no filters/extra
-- spells concept on the debuff side -- custom debuff bars are pure
-- class-token selection, see ns.PAB_AddCustomDebuffBar).
local function BuildDebuffBarSubtitle(bar)
    local nc = 0
    if bar.classFilters then
        for _ in pairs(bar.classFilters) do
            nc = nc + 1
        end
    end
    local nHidden = 0
    if bar.negClassFilters then
        for _ in pairs(bar.negClassFilters) do
            nHidden = nHidden + 1
        end
    end
    if bar.showAllDebuffs ~= false then
        if nHidden > 0 then
            return L("All Debuffs") .. ", " .. nHidden .. " " .. L("hidden")
        end
        return L("All Debuffs")
    end
    local txt = tostring(nc) .. " " .. (nc == 1 and L("class") or L("classes"))
    if nHidden > 0 then
        txt = txt .. ", " .. nHidden .. " " .. L("hidden")
    end
    return txt
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
local function BuildAssignedBuffsFields(widget, fontFile, sy, conf, apply, isDefault)
    local W = CludesUI.Widgets
    local Pix = CludesUI.PanelPP
    local _, hh = 0, 0
    local heading

    heading, hh = W:SectionHeader(widget, "ASSIGNED BUFFS", sy)
    sy = sy - hh
    -- The Move in Unlock Mode button on the bar's first section: the key reads
    -- the sidebar selection at the click, so it highlights the selected bar.
    CludesUI.BuildSectionUnlockJump(heading, {
        key = function()
            if pabSel.id == "default" then
                return "PAB_Buffs"
            end
            return "PAB_CustomBuff_" .. pabSel.id
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
    ffRow, hh = W:DualRow(widget, sy, {
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
    sy = sy - hh

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
        if not mod.PAB_BuffBarHasContent(conf, isDefault) then
            return false
        end
        -- WoW Forever: visibleOnly counts only the Show-lane filters this client
        -- lists, so a bar whose sole content is a hidden retail preset warns.
        local visibleOnly = CludesUI.IS_FOREVER
            and conf.filters
            and conf.showAllBuffs == false
            and conf.hasDuration ~= true
            and not (conf.spells and #conf.spells > 0)
        if not visibleOnly then
            return true
        end
        for fid in pairs(conf.filters) do
            if not mod.PAB_HiddenPresetFilter(fid) then
                return true
            end
        end
        return false
    end

    -- LEFT: Filters checkbox dropdown, "Edit Filters" pinned top action.
    do
        local rgn = ffRow._leftRegion
        if rgn._control then
            rgn._control:Hide()
        end
        local function AllBuffsOn()
            return conf.showAllBuffs ~= false
        end
        local function BroadOn()
            return conf.showAllBuffs ~= false or conf.hasDuration == true
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
                        return conf.showAllBuffs == false and conf.hasDuration ~= true
                    end,
                    lockedTooltip = function()
                        return CludesUI.DisabledTooltip("All Buffs or Has Duration", "enabled")
                    end,
                    onClick = function()
                        CludesUI.ShowSpellBlacklistPopup({
                            title = "Buff Blacklist",
                            get = function()
                                return conf.blacklist
                            end,
                            add = function(ident)
                                conf.blacklist = conf.blacklist or {}
                                conf.blacklist[ident] = true
                            end,
                            remove = function(ident)
                                if conf.blacklist then
                                    conf.blacklist[ident] = nil
                                    if not next(conf.blacklist) then
                                        conf.blacklist = nil
                                    end
                                end
                            end,
                            onChanged = function()
                                apply()
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
        local cbDD, cbRefresh = CludesUI.BuildVisOptsCBDropdown(
            rgn,
            190,
            rgn:GetFrameLevel() + 2,
            FilterItems,
            function(k, neg)
                if k == PAB_ALL_BUFFS_KEY then
                    return AllBuffsOn()
                end
                if k == PAB_HAS_DURATION_KEY then
                    return conf.hasDuration == true
                end
                if neg then
                    local nf = conf.negFilters
                    return nf and nf[k] == true
                end
                local f = conf.filters
                return f and f[k] == true
            end,
            function(k, val, neg)
                if k == PAB_ALL_BUFFS_KEY then
                    conf.showAllBuffs = val
                    -- Mutually exclusive with Has Duration -- both are broad-content
                    -- modes. The show/hide lanes PERSIST across mode flips (the hide
                    -- lane subtracts in both modes; the show lane simply goes dormant
                    -- while broad content is on). Extra Spells stay untouched.
                    conf.hasDuration = nil
                    apply()
                    -- Non-force, same as every other row: the open menu
                    -- refreshes its own checks/locks in place, so a mode
                    -- flip must not tear the page down under it.
                    CludesUI:RefreshPage()
                    return
                end
                if k == PAB_HAS_DURATION_KEY then
                    conf.hasDuration = val or nil
                    -- Mutually exclusive with All Buffs (a broad-content mode of its
                    -- own); lanes persist, same as All Buffs.
                    if val then
                        conf.showAllBuffs = false
                    end
                    apply()
                    CludesUI:RefreshPage()
                    return
                end
                -- Two-lane real-filter write: checking one lane clears the other;
                -- emptied lane tables drop to nil (saved-variable hygiene).
                if neg then
                    conf.negFilters = conf.negFilters or {}
                    conf.negFilters[k] = val or nil
                    if not next(conf.negFilters) then
                        conf.negFilters = nil
                    end
                    if val and conf.filters then
                        conf.filters[k] = nil
                    end
                else
                    conf.filters = conf.filters or {}
                    conf.filters[k] = val or nil
                    if val and conf.negFilters then
                        conf.negFilters[k] = nil
                        if not next(conf.negFilters) then
                            conf.negFilters = nil
                        end
                    end
                end
                if conf.filters and not next(conf.filters) then
                    conf.filters = nil
                end
                apply()
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
        Pix.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
        rgn._control = cbDD
        rgn._lastInline = nil
        CludesUI.RegisterWidgetRefresh(cbRefresh)
        warnClosed = CludesUI.AttachEmptyFilterWarn(
            rgn,
            cbDD,
            L("You are displaying NO buffs at all."),
            BuffBarHasContent
        )
    end

    -- RIGHT: Extra Spells checkbox dropdown (direct cfg.spells only, see
    -- doc comment above for why there is no "Presets" group here). Shares
    -- ffRow with Filters (redesign) instead of its own row.
    do
        local rgn = ffRow._rightRegion
        if rgn._control then
            rgn._control:Hide()
        end
        local function HasDirect(ident)
            local sp = conf.spells
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
                        conf.spells = conf.spells or {}
                        conf.spells[#conf.spells + 1] = ident
                        apply()
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
            if conf.filters then
                for fid in pairs(conf.filters) do
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
            local sp = conf.spells or {}
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
        local cbDD, cbRefresh = CludesUI.BuildVisOptsCBDropdown(
            rgn,
            190,
            rgn:GetFrameLevel() + 2,
            ExtraItems,
            HasDirect,
            function(k, val)
                conf.spells = conf.spells or {}
                if val then
                    if not HasDirect(k) then
                        conf.spells[#conf.spells + 1] = k
                    end
                else
                    -- Unchecking drops the whole curated family, not just this id:
                    -- PAB_ResolveSpells expands a family from any member, so a
                    -- differently-named sibling left in the list would keep the buff
                    -- tracked behind an unchecked box. Same family = same table.
                    local fam = mod.PAB_SPELL_FAMILY and mod.PAB_SPELL_FAMILY[k]
                    for idx = #conf.spells, 1, -1 do
                        local ident = conf.spells[idx]
                        if ident == k or (fam and mod.PAB_SPELL_FAMILY[ident] == fam) then
                            table.remove(conf.spells, idx)
                        end
                    end
                end
                apply()
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
        Pix.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
        rgn._control = cbDD
        rgn._lastInline = nil
        CludesUI.RegisterWidgetRefresh(cbRefresh)
    end

    return sy
end

-- "Assigned Debuffs": unified Filters dropdown (same model as Raid Frames' Debuff
-- Manager base grid): pinned "All Debuffs" row above a Show/Hide caption row, then
-- TWO-LANE class rows -- ONE control, live in both modes. The left checkbox SHOWS a
-- class (cfg.classFilters, add mode; dimmed while All Debuffs is on), the right red
-- box HIDES it (cfg.negClassFilters -- hidden chain links / inverted candidates in
-- both modes, see DebuffSubtractFn/BuildChain). Lanes are mutually exclusive per
-- class and persist across mode flips. Used by BOTH the default Debuffs bar and
-- every custom debuff bar.
local function BuildAssignedDebuffsFields(widget, fontFile, sy, conf, apply)
    local W = CludesUI.Widgets
    local Pix = CludesUI.PanelPP
    local _, hh = 0, 0
    local heading

    heading, hh = W:SectionHeader(widget, "ASSIGNED DEBUFFS", sy)
    sy = sy - hh
    -- The Move in Unlock Mode button on the bar's first section: the key reads
    -- the sidebar selection at the click, so it highlights the selected bar.
    CludesUI.BuildSectionUnlockJump(heading, {
        key = function()
            if pabSel.id == "default" then
                return "PAB_Debuffs"
            end
            return "PAB_CustomDebuff_" .. pabSel.id
        end,
    })

    local safRow
    safRow, hh = W:DualRow(
        widget,
        sy,
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
            return conf.maxDurSec
        end, function(val)
            conf.maxDurSec = val
        end, apply)
    )
    sy = sy - hh
    do
        local rgn = safRow._leftRegion
        if rgn._control then
            rgn._control:Hide()
        end
        local PAB_ALL_DEBUFFS_KEY = "__allDebuffs"
        local PAB_DEBUFF_HAS_DUR_KEY = "__debuffHasDuration"
        local PAB_HIDE_EXH_KEY = "__hideExhaustion"
        local PAB_MATCH_ANY_KEY = "__matchAny"
        local PAB_MATCH_ALL_KEY = "__matchAll"
        local function AllOn()
            return conf.showAllDebuffs ~= false
        end
        local function MatchAll()
            return conf.debuffMatch == "all"
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
        local function ClearExclusive(k)
            local other = mod.PAB_ExclusiveSkey and mod.PAB_ExclusiveSkey[k]
            if not other then
                return
            end
            if conf.classFilters then
                conf.classFilters[other] = nil
                if not next(conf.classFilters) then
                    conf.classFilters = nil
                end
            end
            if conf.negClassFilters then
                conf.negClassFilters[other] = nil
                if not next(conf.negClassFilters) then
                    conf.negClassFilters = nil
                end
            end
        end
        local warnClosed
        local cbDD, cbRefresh = CludesUI.BuildVisOptsCBDropdown(
            rgn,
            190,
            rgn:GetFrameLevel() + 2,
            FilterItems,
            function(k, neg)
                if k == PAB_ALL_DEBUFFS_KEY then
                    return AllOn()
                end
                if k == PAB_DEBUFF_HAS_DUR_KEY then
                    return conf.hasDuration == true
                end
                if k == PAB_HIDE_EXH_KEY then
                    return conf.hideExhaustion == true
                end
                if k == PAB_MATCH_ANY_KEY or k == PAB_MATCH_ALL_KEY then
                    return (k == PAB_MATCH_ALL_KEY) == MatchAll()
                end
                if neg then
                    local nf = conf.negClassFilters
                    return nf and nf[k] == true
                end
                local f = conf.classFilters
                return f and f[k] == true
            end,
            function(k, val, neg)
                if k == PAB_ALL_DEBUFFS_KEY then
                    -- Stores the raw boolean directly (nil must mean "on",
                    -- same convention as showAllBuffs). Lanes persist across
                    -- mode flips (the hide lane subtracts in both modes).
                    conf.showAllDebuffs = val
                    apply()
                    CludesUI:RefreshPage()
                    return
                end
                if k == PAB_DEBUFF_HAS_DUR_KEY then
                    -- AND-modifier (native maxDuration on every debuff group;
                    -- permanents excluded): combines with All Debuffs or any
                    -- class-filter selection; alone it acts as the timed
                    -- catch-all (DebuffCatchAllOn).
                    conf.hasDuration = val or nil
                    apply()
                    CludesUI:RefreshPage()
                    return
                end
                if k == PAB_HIDE_EXH_KEY then
                    conf.hideExhaustion = val or nil
                    apply()
                    CludesUI:RefreshPage()
                    return
                end
                if k == PAB_MATCH_ANY_KEY or k == PAB_MATCH_ALL_KEY then
                    -- Radio pair: the clicked row always wins (the toggled value
                    -- is ignored), so clicking the active row keeps it. nil =
                    -- Match Any keeps untouched bars byte-identical.
                    local wanted = (k == PAB_MATCH_ALL_KEY) and "all" or nil
                    if conf.debuffMatch == wanted then
                        return
                    end
                    conf.debuffMatch = wanted
                    apply()
                    CludesUI:RefreshPage()
                    return
                end
                -- Two-lane class write: checking one lane clears the other;
                -- emptied lane tables drop to nil (saved-variable hygiene).
                if val then
                    ClearExclusive(k)
                end
                if neg then
                    conf.negClassFilters = conf.negClassFilters or {}
                    conf.negClassFilters[k] = val or nil
                    if not next(conf.negClassFilters) then
                        conf.negClassFilters = nil
                    end
                    if val and conf.classFilters then
                        conf.classFilters[k] = nil
                    end
                else
                    conf.classFilters = conf.classFilters or {}
                    conf.classFilters[k] = val or nil
                    if val and conf.negClassFilters then
                        conf.negClassFilters[k] = nil
                        if not next(conf.negClassFilters) then
                            conf.negClassFilters = nil
                        end
                    end
                end
                if conf.classFilters and not next(conf.classFilters) then
                    conf.classFilters = nil
                end
                apply()
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
        Pix.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
        rgn._control = cbDD
        rgn._lastInline = nil
        CludesUI.RegisterWidgetRefresh(cbRefresh)
        warnClosed = CludesUI.AttachEmptyFilterWarn(
            rgn,
            cbDD,
            L("You are displaying NO debuffs at all."),
            function()
                if not mod.PAB_DebuffBarHasContent then
                    return true
                end
                -- Match All picks that can never match together build nothing.
                if mod.PAB_DebuffMatchEmpty and mod.PAB_DebuffMatchEmpty(conf) then
                    return false
                end
                return mod.PAB_DebuffBarHasContent(conf) and true or false
            end
        )
    end

    return sy
end

-- "Core": Icon Size (+Icon Zoom cog) | Growth Direction;
--         Sort Method | Sort Direction;
--         Duration [+expand][swatch][toggle] | Stacks [+expand][swatch][toggle].
-- Shared by every bar (default + custom, buff + debuff) -- growDirection is generic
-- (BuildContainerSpec doesn't care about slots vs. groups). isBuff is currently unused
-- here (Sort Method's option set is now shared between buffs/debuffs, see
-- SORT_METHOD_VALUES' doc comment) but kept for callers/future per-polarity fields.
local function BuildCoreFields(widget, fontFile, sy, conf, apply, isBuff)
    local W = CludesUI.Widgets
    local Pix = CludesUI.PanelPP
    local _, hh = 0, 0

    _, hh = W:SectionHeader(widget, "CORE", sy)
    sy = sy - hh

    local sizeRow
    sizeRow, hh = W:DualRow(widget, sy, {
        type = "slider",
        text = "Icon Size",
        min = 16,
        max = 400,
        step = 1,
        trackWidth = 120,
        getValue = function()
            return conf.iconSize or 32
        end,
        setValue = function(val)
            conf.iconSize = val
            apply()
        end,
    }, {
        type = "dropdown",
        text = "Growth Direction",
        values = GROW_DIR_VALUES,
        order = GROW_DIR_ORDER,
        getValue = function()
            return conf.growDirection or "LEFT"
        end,
        setValue = function(val)
            -- Change the wrap direction to be a valid value from the new growth direction
            if val == "UP" or val == "DOWN" then
                if conf.iconWrapDirection ~= "LEFT" and conf.iconWrapDirection ~= "RIGHT" then
                    conf.iconWrapDirection = "LEFT"
                end
            elseif val == "LEFT" or val == "RIGHT" then
                if conf.iconWrapDirection ~= "UP" and conf.iconWrapDirection ~= "DOWN" then
                    conf.iconWrapDirection = "DOWN"
                end
            end

            conf.growDirection = val
            apply()
        end,
    })
    sy = sy - hh

    _, hh = W:DualRow(widget, sy, {
        type = "dropdown",
        text = "Sort Method",
        values = SORT_METHOD_VALUES,
        order = SORT_METHOD_ORDER,
        getValue = function()
            return conf.sortMethod or "Default"
        end,
        setValue = function(val)
            conf.sortMethod = val
            apply()
        end,
    }, {
        type = "dropdown",
        text = "Sort Direction",
        values = SORT_DIR_VALUES,
        order = SORT_DIR_ORDER,
        getValue = function()
            return conf.sortDirection or "Normal"
        end,
        setValue = function(val)
            conf.sortDirection = val
            apply()
        end,
    })
    sy = sy - hh
    do
        local rgn = sizeRow._leftRegion
        CludesUI.BuildInlineCog(rgn, {
            title = "Icon Size",
            rows = {
                {
                    type = "slider",
                    label = "Icon Zoom",
                    min = 0,
                    max = 0.20,
                    step = 0.01,
                    get = function()
                        return conf.iconZoom or 0.055
                    end,
                    set = function(val)
                        conf.iconZoom = val
                        apply()
                    end,
                },
            },
        })
    end
    do
        -- Icon Wrap: only meaningful for vertical growth (Up/Down) and horizontal growth (Left/Right) -- decides which
        -- side additional columns stack toward when Icons Per Row/Column > 1. Cog-only,
        -- no separate dropdown row, and only shown while Growth Direction is Up/Down or Left/Right.
        local rgn = sizeRow._rightRegion
        local cogBtn = CludesUI.BuildInlineCog(rgn, {
            title = "Growth",
            rows = {
                {
                    type = "dropdown",
                    label = "Icon Wrap",
                    values = ICON_WRAP_VALUES,
                    order = ICON_WRAP_ORDER,
                    get = function()
                        return conf.iconWrapDirection or "LEFT"
                    end,
                    set = function(val)
                        conf.iconWrapDirection = val
                        apply()
                    end,
                    itemDisabled = function(val)
                        if conf.growDirection == "LEFT" or conf.growDirection == "RIGHT" then
                            return val == "LEFT" or val == "RIGHT"
                        elseif conf.growDirection == "UP" or conf.growDirection == "DOWN" then
                            return val == "UP" or val == "DOWN"
                        end
                        return false
                    end,
                },
            },
        })
        local function UpdateWrapCogVisibility()
            local dir = conf.growDirection or "LEFT"
            if cogBtn then
                cogBtn:SetShown(dir == "UP" or dir == "DOWN" or dir == "LEFT" or dir == "RIGHT")
            end
        end
        CludesUI.RegisterWidgetRefresh(UpdateWrapCogVisibility)
        UpdateWrapCogVisibility()
    end

    local dsRow
    dsRow, hh = W:DualRow(widget, sy, {
        type = "toggle",
        text = "Duration",
        getValue = function()
            return conf.durationShow ~= false
        end,
        setValue = function(val)
            conf.durationShow = val
            apply()
        end,
    }, {
        type = "toggle",
        text = "Stacks",
        getValue = function()
            return conf.stackShow ~= false
        end,
        setValue = function(val)
            conf.stackShow = val
            apply()
        end,
    })
    sy = sy - hh
    do
        local rgn = dsRow._leftRegion
        CludesUI.BuildInlineCog(rgn, {
            title = "Duration Text",
            rows = {
                {
                    type = "slider",
                    label = "Text Size",
                    min = 6,
                    max = 60,
                    step = 1,
                    get = function()
                        return conf.durationTextSize or 11
                    end,
                    set = function(val)
                        conf.durationTextSize = val
                        apply()
                    end,
                },
                {
                    type = "slider",
                    label = "Offset X",
                    min = -50,
                    max = 50,
                    step = 1,
                    get = function()
                        return conf.durationOffsetX or 0
                    end,
                    set = function(val)
                        conf.durationOffsetX = val
                        apply()
                    end,
                },
                {
                    type = "slider",
                    label = "Offset Y",
                    min = -50,
                    max = 50,
                    step = 1,
                    get = function()
                        return conf.durationOffsetY or 0
                    end,
                    set = function(val)
                        conf.durationOffsetY = val
                        apply()
                    end,
                },
                {
                    type = "dropdown",
                    label = "Position",
                    values = AURA_POINT_VALUES,
                    order = AURA_POINT_ORDER,
                    get = function()
                        return conf.durationPosition or "CENTER"
                    end,
                    set = function(val)
                        conf.durationPosition = val
                        apply()
                    end,
                },
                {
                    type = "toggle",
                    label = "Show S for Seconds",
                    get = function()
                        return conf.durationShowSeconds == true
                    end,
                    set = function(val)
                        conf.durationShowSeconds = val and true or nil
                        apply()
                    end,
                },
                {
                    type = "slider",
                    label = "Precise Below (minutes, 0 = off)",
                    min = 0,
                    max = 90,
                    step = 1,
                    get = function()
                        return conf.durationPrecisionThreshold and conf.durationPrecisionThreshold / 60 or 0
                    end,
                    set = function(val)
                        conf.durationPrecisionThreshold = val > 0 and math.floor(val * 60 + 0.5) or nil
                        apply()
                    end,
                },
            },
        })
        local colorSwatch, updateSwatch = CludesUI.BuildColorSwatch(rgn, dsRow:GetFrameLevel() + 3, function()
            return (conf.durationColorR or 1), (conf.durationColorG or 1), (conf.durationColorB or 1), 1
        end, function(r, g, b)
            conf.durationColorR, conf.durationColorG, conf.durationColorB = r, g, b
            apply()
        end, false, 20)
        colorSwatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = colorSwatch
        CludesUI.RegisterWidgetRefresh(updateSwatch)
    end
    do
        local rgn = dsRow._rightRegion
        CludesUI.BuildInlineCog(rgn, {
            title = "Stacks Text",
            rows = {
                {
                    type = "slider",
                    label = "Text Size",
                    min = 6,
                    max = 60,
                    step = 1,
                    get = function()
                        return conf.stackTextSize or 11
                    end,
                    set = function(val)
                        conf.stackTextSize = val
                        apply()
                    end,
                },
                {
                    type = "slider",
                    label = "Offset X",
                    min = -50,
                    max = 50,
                    step = 1,
                    get = function()
                        return conf.stackOffsetX or 0
                    end,
                    set = function(val)
                        conf.stackOffsetX = val
                        apply()
                    end,
                },
                {
                    type = "slider",
                    label = "Offset Y",
                    min = -50,
                    max = 50,
                    step = 1,
                    get = function()
                        return conf.stackOffsetY or 0
                    end,
                    set = function(val)
                        conf.stackOffsetY = val
                        apply()
                    end,
                },
                {
                    type = "dropdown",
                    label = "Position",
                    values = AURA_POINT_VALUES,
                    order = AURA_POINT_ORDER,
                    get = function()
                        return conf.stackPosition or "BOTTOMRIGHT"
                    end,
                    set = function(val)
                        conf.stackPosition = val
                        apply()
                    end,
                },
            },
        })
        local colorSwatch, updateSwatch = CludesUI.BuildColorSwatch(rgn, dsRow:GetFrameLevel() + 3, function()
            return (conf.stackColorR or 1), (conf.stackColorG or 1), (conf.stackColorB or 1), 1
        end, function(r, g, b)
            conf.stackColorR, conf.stackColorG, conf.stackColorB = r, g, b
            apply()
        end, false, 20)
        colorSwatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = colorSwatch
        CludesUI.RegisterWidgetRefresh(updateSwatch)
    end

    return sy
end

local function FontOutlineField(conf, apply)
    return {
        type = "dropdown",
        text = "Font Outline",
        values = FONT_OUTLINE_VALUES,
        order = FONT_OUTLINE_ORDER,
        getValue = function()
            return conf.fontOutline or "default"
        end,
        setValue = function(val)
            conf.fontOutline = val
            apply()
        end,
    }
end

-- "Display": Border Style (+shift/behind cog) | Border Size [swatch]; Width
-- Offset | Height Offset (textured style only); Icons Per Row (+grid cog) |
-- Spacing (+row-spacing cog); Icon Shape | Icon Zoom; remaining toggles are
-- packed by polarity without placeholder slots.
local function BuildDisplayFields(widget, fontFile, sy, conf, apply, isBuff)
    local W = CludesUI.Widgets
    local Pix = CludesUI.PanelPP
    local _, hh = 0, 0

    _, hh = W:SectionHeader(widget, "DISPLAY", sy)
    sy = sy - hh
    sy = CludesUI.BlizzStyle.Note(widget, sy, "playerauras")

    local textureValues, textureOrder = CludesUI.GetBorderTextureDropdown()
    -- Border Size: the pixel slider over cfg.borderSize and its borderSizePx
    -- companion (CludesUI.BorderPxSliderCfg). A custom Icon Shape keeps the
    -- None..Strong dropdown instead: its ring is on/off (PabShapeBorderSize), so a
    -- pixel count means nothing there. The Icon Shape setter rebuilds the page when
    -- the shape crosses none/custom, which swaps the control in this slot.
    local sizeCfg
    if IsMaskShape(conf.iconShape) then
        sizeCfg = {
            type = "dropdown",
            text = "Border Size",
            values = BORDER_SIZE_VALUES,
            order = BORDER_SIZE_LEVELS,
            itemDisabled = function(val)
                return IsMaskShape(conf.iconShape) and BORDER_SIZE_SHAPE_DISABLED[val] or false
            end,
            itemDisabledTooltip = function()
                return "This option requires a non-custom shape to be selected"
            end,
            getValue = function()
                return BORDER_SIZE_KEY[conf.borderSize or 1] or "thin"
            end,
            setValue = function(val)
                conf.borderSize = BORDER_SIZE_NUM[val] or 1
                apply()
            end,
        }
    else
        sizeCfg = CludesUI.BorderPxSliderCfg({
            text = "Border Size",
            trackWidth = 120,
            -- The step BuildStyle renders with (cfg.borderSize or 1), as a number.
            getStep = function()
                return conf.borderSize or 1
            end,
            setStep = function(step)
                conf.borderSize = step
            end,
            getTex = function()
                return conf.borderTexture or "solid"
            end,
            getPx = function()
                return conf.borderSizePx
            end,
            setPx = function(val)
                conf.borderSizePx = val
            end,
            apply = apply,
        })
    end
    local styleRow
    styleRow, hh = W:DualRow(
        widget,
        sy,
        CludesUI.BlizzStyle.Gate("playerauras", {
            type = "dropdown",
            text = "Border Style",
            disabled = function()
                return IsMaskShape(conf.iconShape)
            end,
            disabledTooltip = "This option requires a non-custom shape to be selected",
            rawTooltip = true,
            values = textureValues,
            order = textureOrder,
            getValue = function()
                return conf.borderTexture or "solid"
            end,
            setValue = function(val)
                conf.borderTexture = val
                conf.borderTextureOffset = nil
                conf.borderTextureOffsetY = nil
                conf.borderTextureShiftX = nil
                conf.borderTextureShiftY = nil
                local color, behind = CludesUI.GetBorderStyleSelectDefaults(val)
                conf.borderR, conf.borderG, conf.borderB, conf.borderA = color.r, color.g, color.b, 1
                conf.borderBehind = behind
                local defaultSize = CludesUI.GetBorderDefaultSize("unitframes", val)
                if defaultSize then
                    conf.borderSize = defaultSize
                end
                -- A style pick resets the size: the exact size paired with the old
                -- step and texture goes with it (false, never nil, once it was set).
                if conf.borderSizePx then
                    conf.borderSizePx = false
                end
                apply()
                -- The Width Offset | Height Offset row below exists only for a
                -- textured style: a Solid/textured crossing rebuilds the page.
                CludesUI:RefreshPage(true)
            end,
        }),
        CludesUI.BlizzStyle.Gate("playerauras", sizeCfg)
    )
    sy = sy - hh
    do
        local rgn = styleRow._leftRegion
        local borderCogRows = {
            {
                type = "slider",
                label = "Shift X",
                min = -10,
                max = 10,
                step = 1,
                get = function()
                    if conf.borderTextureShiftX ~= nil then
                        return conf.borderTextureShiftX
                    end
                    local _, _, posX = CludesUI.GetBorderDefaults(
                        "unitframes",
                        conf.borderTexture or "solid",
                        conf.borderSize or 1
                    )
                    return posX
                end,
                set = function(val)
                    if val == 0 then
                        val = nil
                    end
                    conf.borderTextureShiftX = val
                    apply()
                end,
            },
            {
                type = "slider",
                label = "Shift Y",
                min = -10,
                max = 10,
                step = 1,
                get = function()
                    if conf.borderTextureShiftY ~= nil then
                        return conf.borderTextureShiftY
                    end
                    local _, _, _, posY = CludesUI.GetBorderDefaults(
                        "unitframes",
                        conf.borderTexture or "solid",
                        conf.borderSize or 1
                    )
                    return posY
                end,
                set = function(val)
                    if val == 0 then
                        val = nil
                    end
                    conf.borderTextureShiftY = val
                    apply()
                end,
            },
            {
                type = "toggle",
                label = "Show Behind",
                get = function()
                    return conf.borderBehind == true
                end,
                set = function(val)
                    conf.borderBehind = val
                    apply()
                end,
            },
        }
        -- Debuff bars only: their engine dispel ring can take this border's art.
        if not isBuff then
            borderCogRows[#borderCogRows + 1] = {
                type = "toggle",
                label = "Textured Dispel Ring",
                tooltip = "Draws the dispel-colored ring in this border style's shape instead of flat lines.",
                get = function()
                    return conf.borderDispelTextured == true
                end,
                set = function(val)
                    conf.borderDispelTextured = val and true or false
                    apply()
                end,
            }
        end
        local cogBtn = CludesUI.BuildInlineCog(rgn, {
            title = "Border Options",
            rows = borderCogRows,
        })
        local function UpdateBorderCogVisibility()
            if cogBtn then
                cogBtn:SetShown(
                    (conf.borderTexture or "solid") ~= "solid"
                        and not IsMaskShape(conf.iconShape)
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
            target.borderTexture = conf.borderTexture
            target.borderTextureOffset = conf.borderTextureOffset
            target.borderTextureOffsetY = conf.borderTextureOffsetY
            target.borderTextureShiftX = conf.borderTextureShiftX
            target.borderTextureShiftY = conf.borderTextureShiftY
            target.borderBehind = conf.borderBehind
            -- Textured Dispel Ring is a debuff-bar setting: it travels only from
            -- a debuff bar to debuff bars.
            if not isBuff and not record.isBuff then
                target.borderDispelTextured = conf.borderDispelTextured
            end
            target.borderR, target.borderG, target.borderB, target.borderA =
                conf.borderR, conf.borderG, conf.borderB, conf.borderA
            -- Border textures and custom shape masks are mutually exclusive in
            -- the editor. A bulk style sync follows the same "last choice wins"
            -- rule as a direct selection so it cannot create a locked combination.
            if (conf.borderTexture or "solid") ~= "solid" then
                target.iconShape = "none"
            end
            PabApplyBarEntry(record)
        end
        CludesUI.BuildSyncIcon({
            region = rgn,
            tooltip = "Apply Border Style to all Bars",
            onClick = function()
                for _, record in ipairs(PabAllBarEntries()) do
                    if record.cfg ~= conf then
                        CopyBorderStyleTo(record)
                    end
                end
                CludesUI:RefreshPage()
            end,
            isSynced = function()
                local texture = conf.borderTexture or "solid"
                for _, record in ipairs(PabAllBarEntries()) do
                    local c = record.cfg
                    if
                        (c.borderTexture or "solid") ~= texture
                        or c.borderTextureOffset ~= conf.borderTextureOffset
                        or c.borderTextureOffsetY ~= conf.borderTextureOffsetY
                        or c.borderTextureShiftX ~= conf.borderTextureShiftX
                        or c.borderTextureShiftY ~= conf.borderTextureShiftY
                        or (c.borderBehind == true) ~= (conf.borderBehind == true)
                        or (
                            not isBuff
                            and not record.isBuff
                            and (c.borderDispelTextured == true) ~= (conf.borderDispelTextured == true)
                        )
                    then
                        return false
                    end
                end
                return true
            end,
            flashTargets = function()
                return { rgn }
            end,
            multiApply = {
                elementKeys = keyList,
                elementLabels = labels,
                getCurrentKey = function()
                    return PabBarKeyOf(conf, isBuff)
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
        local tex = conf.borderTexture
        if tex and tex ~= "" and tex ~= "solid" then
            local ocfgL, ocfgR = CludesUI.BorderOffsetRowCfgs({
                addonKey = "unitframes",
                trackWidth = 120,
                getTex = function()
                    return conf.borderTexture or "solid"
                end,
                getStep = function()
                    return conf.borderSize or 1
                end,
                getSizeKey = function()
                    return conf.borderSize or 1
                end,
                getPx = function()
                    return conf.borderSizePx
                end,
                getX = function()
                    return conf.borderTextureOffset
                end,
                setX = function(val)
                    conf.borderTextureOffset = val
                end,
                getY = function()
                    return conf.borderTextureOffsetY
                end,
                setY = function(val)
                    conf.borderTextureOffsetY = val
                end,
                apply = apply,
            })
            _, hh = W:DualRow(
                widget,
                sy,
                CludesUI.BlizzStyle.Gate("playerauras", ocfgL),
                CludesUI.BlizzStyle.Gate("playerauras", ocfgR)
            )
            sy = sy - hh
        end
    end

    local rowRow
    rowRow, hh = W:DualRow(widget, sy, {
        type = "slider",
        text = "Icons Per Row",
        min = 1,
        max = 20,
        step = 1,
        trackWidth = 120,
        getValue = function()
            return conf.iconsPerRow or (isBuff and 11 or 8)
        end,
        setValue = function(val)
            conf.iconsPerRow = val
            apply()
        end,
    }, {
        type = "slider",
        text = "Spacing",
        min = -5,
        max = 20,
        step = 1,
        trackWidth = 120,
        getValue = function()
            return conf.padding or 5
        end,
        setValue = function(val)
            conf.padding = val
            apply()
        end,
    })
    sy = sy - hh
    do
        local rgn = styleRow._rightRegion
        local colorSwatch, updateSwatch = CludesUI.BuildColorSwatch(
            rgn,
            styleRow:GetFrameLevel() + 3,
            function()
                return (conf.borderR or 0), (conf.borderG or 0), (conf.borderB or 0), (conf.borderA or 1)
            end,
            function(r, g, b, a)
                conf.borderR, conf.borderG, conf.borderB, conf.borderA = r, g, b, a
                apply()
            end,
            true,
            20
        )
        colorSwatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
        rgn._lastInline = colorSwatch
        CludesUI.RegisterWidgetRefresh(updateSwatch)
    end
    do
        local rgn = styleRow._rightRegion
        local keyList, labels = {}, {}
        for _, record in ipairs(PabAllBarEntries()) do
            keyList[#keyList + 1] = record.key
            labels[record.key] = record.label
        end
        local function CopyBorderTo(record)
            record.cfg.borderSize = conf.borderSize
            -- The exact size travels with its step, verbatim (string/false/nil);
            -- a target whose value was set is cleared with false, never nil.
            local px = conf.borderSizePx
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
                conf.borderR, conf.borderG, conf.borderB, conf.borderA
            PabApplyBarEntry(record)
        end
        CludesUI.BuildSyncIcon({
            region = rgn,
            tooltip = "Apply Border Size and Color to all Bars",
            onClick = function()
                for _, record in ipairs(PabAllBarEntries()) do
                    if record.cfg ~= conf then
                        CopyBorderTo(record)
                    end
                end
                CludesUI:RefreshPage()
            end,
            isSynced = function()
                local size = conf.borderSize or 1
                local r, g, b, a = conf.borderR or 0, conf.borderG or 0, conf.borderB or 0, conf.borderA or 1
                for _, record in ipairs(PabAllBarEntries()) do
                    local c = record.cfg
                    if
                        (c.borderSize or 1) ~= size
                        or (c.borderR or 0) ~= r
                        or (c.borderG or 0) ~= g
                        or (c.borderB or 0) ~= b
                        or (c.borderA or 1) ~= a
                        or (c.borderSizePx or false) ~= (conf.borderSizePx or false)
                    then
                        return false
                    end
                end
                return true
            end,
            flashTargets = function()
                return { rgn }
            end,
            multiApply = {
                elementKeys = keyList,
                elementLabels = labels,
                getCurrentKey = function()
                    return PabBarKeyOf(conf, isBuff)
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
        local rgn = rowRow._rightRegion
        CludesUI.BuildInlineCog(rgn, {
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
                    get = function()
                        return conf.rowSpacing or 12
                    end,
                    set = function(val)
                        conf.rowSpacing = val
                        apply()
                    end,
                },
            },
        })
    end

    do
        -- Verified against CUI_RaidFrames_BuffManager.lua's "legacy layout"
        -- branch: perRowCfg paired with a blank spacer, cog on
        -- gridRow._leftRegion -- i.e. directly on Icons Per Row's own
        -- region. Same trackWidth=120 slider + cog combo used there.
        local rgn = rowRow._leftRegion
        CludesUI.BuildInlineCog(rgn, {
            title = "Icons Per Row",
            rows = {
                {
                    type = "slider",
                    label = "Max Rows",
                    min = 1,
                    max = 10,
                    step = 1,
                    get = function()
                        return conf.maxRows or (isBuff and 3 or 2)
                    end,
                    set = function(val)
                        conf.maxRows = val
                        apply()
                    end,
                },
                {
                    type = "slider",
                    label = "Max Total",
                    min = 1,
                    max = 40,
                    step = 1,
                    get = function()
                        return conf.maxTotal or (isBuff and 32 or 16)
                    end,
                    set = function(val)
                        conf.maxTotal = val
                        apply()
                    end,
                },
            },
        })
    end

    -- Icon Shape reuses the base Border Size/Color above -- no separate shape fields.
    local shapeRow
    shapeRow, hh = W:DualRow(
        widget,
        sy,
        {
            type = "dropdown",
            text = "Icon Shape",
            values = SHAPE_VALUES,
            order = SHAPE_ORDER,
            itemDisabled = function(val)
                return IsMaskShape(val) and (conf.borderTexture or "solid") ~= "solid"
            end,
            itemDisabledTooltip = function(val)
                if IsMaskShape(val) and (conf.borderTexture or "solid") ~= "solid" then
                    return "This option requires the Border Style to be set to Solid"
                end
            end,
            getValue = function()
                return conf.iconShape or "none"
            end,
            setValue = function(val)
                local wasShaped = IsMaskShape(conf.iconShape)
                conf.iconShape = val
                -- Entering shape mode with a now-disabled Border Size level selected:
                -- snap to the shape default, same as Action Bars' own shape dropdown
                -- resetting border thickness on every shape change.
                local curKey = BORDER_SIZE_KEY[conf.borderSize or 1] or "thin"
                if IsMaskShape(val) and BORDER_SIZE_SHAPE_DISABLED[curKey] then
                    conf.borderSize = BORDER_SIZE_NUM[BORDER_SIZE_DEFAULT_SHAPE]
                end
                apply()
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
                return (conf.iconZoom or 0.055) * 100
            end,
            setValue = function(val)
                conf.iconZoom = val / 100
                apply()
            end,
        })
    )
    sy = sy - hh
    do
        local rgn = shapeRow._leftRegion
        CludesUI.BuildInlineCog(rgn, {
            title = "Icon Shape",
            disabled = function()
                return conf.iconShape ~= "cropped"
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
                        return mod.PAB_CropPercent(conf)
                    end,
                    set = function(val)
                        conf.iconCropPercent = val
                        apply()
                    end,
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
            local shape = conf.iconShape
            record.cfg.iconShape = shape
            if shape == "cropped" then
                record.cfg.iconCropPercent = mod.PAB_CropPercent(conf)
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
            region = rgn,
            tooltip = "Apply Icon Shape to all Bars",
            onClick = function()
                for _, record in ipairs(PabAllBarEntries()) do
                    if record.cfg ~= conf then
                        CopyShapeTo(record)
                    end
                end
                CludesUI:RefreshPage()
            end,
            isSynced = function()
                local shape = conf.iconShape or "none"
                for _, record in ipairs(PabAllBarEntries()) do
                    if (record.cfg.iconShape or "none") ~= shape then
                        return false
                    end
                    if
                        shape == "cropped"
                        and mod.PAB_CropPercent(record.cfg) ~= mod.PAB_CropPercent(conf)
                    then
                        return false
                    end
                end
                return true
            end,
            flashTargets = function()
                return { rgn }
            end,
            multiApply = {
                elementKeys = keyList,
                elementLabels = labels,
                getCurrentKey = function()
                    return PabBarKeyOf(conf, isBuff)
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
    swipeRow, hh = W:DualRow(widget, sy, {
        type = "toggle",
        text = "Show Duration Swipe",
        getValue = function()
            return conf.showSwipe ~= false
        end,
        setValue = function(val)
            conf.showSwipe = val
            apply()
        end,
    }, {
        type = "toggle",
        text = "Show Tooltips",
        tooltip = "Show aura tooltips when hovering this bar's icons.",
        getValue = function()
            return conf.showTooltips ~= false
        end,
        setValue = function(val)
            conf.showTooltips = val
            apply()
        end,
    })
    sy = sy - hh
    do
        local rgn = swipeRow._leftRegion
        CludesUI.BuildInlineCog(rgn, {
            title = "Duration Swipe",
            rows = {
                -- Default on = the swipe UNCOVERS the icon as time runs out
                -- (the module's shipped look); off = Blizzard's standard
                -- direction, darkness growing over the icon instead.
                {
                    type = "toggle",
                    label = "Reverse Swipe",
                    get = function()
                        return conf.reverseSwipe ~= false
                    end,
                    set = function(val)
                        conf.reverseSwipe = val
                        apply()
                    end,
                },
            },
        })
    end

    -- Buff bars only: debuffs are never player-cancelable, so the row would
    -- be a dead switch there.
    if isBuff then
        _, hh = W:DualRow(widget, sy, FontOutlineField(conf, apply), {
            type = "toggle",
            text = "Right-Click to Cancel",
            tooltip = "Right-clicking a buff icon cancels the buff. Turning this off makes the bar's icons click-through; tooltips still follow the Show Tooltips setting.",
            getValue = function()
                return conf.rightClickCancel ~= false
            end,
            setValue = function(val)
                conf.rightClickCancel = val
                apply()
            end,
        })
        sy = sy - hh
    end

    return sy
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

local function BuildDispelColorFields(widget, fontFile, sy, conf, apply)
    local W = CludesUI.Widgets
    local Pix = CludesUI.PanelPP
    local _, hh = 0, 0

    -- Dispel-type indicator icon on each debuff bar (engine-driven, mirrors
    -- Raid Frames' "Type Icon Position"). "none" (default) = feature off.
    _, hh = W:SectionHeader(widget, "DEBUFF DISPLAY", sy)
    sy = sy - hh
    do
        local function IconOn()
            return (conf.dispelIconPosition or "none") ~= "none"
        end
        local row
        row, hh = W:DualRow(widget, sy, {
            type = "dropdown",
            text = "Type Icon Position",
            tooltip = "Shows the debuff's dispel type icon (Magic, Curse, Disease, Poison, Bleed) on the bar.",
            values = DISPEL_ICON_POS_VALUES,
            order = DISPEL_ICON_POS_ORDER,
            getValue = function()
                return conf.dispelIconPosition or "none"
            end,
            setValue = function(val)
                conf.dispelIconPosition = val
                apply()
                CludesUI:RefreshPage()
            end,
        }, FontOutlineField(conf, apply))
        sy = sy - hh
        local rgn = row._leftRegion
        CludesUI.BuildInlineCog(rgn, {
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
                    get = function()
                        return conf.dispelIconSize or 16
                    end,
                    set = function(val)
                        conf.dispelIconSize = val
                        apply()
                    end,
                },
                {
                    type = "slider",
                    label = "Offset X",
                    min = -50,
                    max = 50,
                    step = 1,
                    get = function()
                        return conf.dispelIconOffsetX or 0
                    end,
                    set = function(val)
                        conf.dispelIconOffsetX = val
                        apply()
                    end,
                },
                {
                    type = "slider",
                    label = "Offset Y",
                    min = -50,
                    max = 50,
                    step = 1,
                    get = function()
                        return conf.dispelIconOffsetY or 0
                    end,
                    set = function(val)
                        conf.dispelIconOffsetY = val
                        apply()
                    end,
                },
            },
        })
    end

    -- Blizzard Style paints the stock per-type border art, so the palette has
    -- nothing to colour: the whole section stays out (fully gated rows hide).
    if CludesUI.BlizzStyle.Get("playerauras") then
        return sy
    end

    _, hh = W:SectionHeader(widget, "DISPEL COLORS", sy)
    sy = sy - hh

    local function AddDispelSwatch(rgn, record)
        local colorSwatch, updateSwatch = CludesUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 3, function()
            local c = conf[record.key]
            if c then
                return c.r or 1, c.g or 1, c.b or 1, 1
            end
            return record.fallback[1], record.fallback[2], record.fallback[3], 1
        end, function(r, g, b)
            conf[record.key] = { r = r, g = g, b = b }
            apply()
        end, false, 18)
        Pix.Point(colorSwatch, "RIGHT", rgn, "RIGHT", -20, 0)
        CludesUI.RegisterWidgetRefresh(updateSwatch)
    end
    for idx = 1, #DISPEL_COLOR_ROWS, 2 do
        local leftX, right = DISPEL_COLOR_ROWS[idx], DISPEL_COLOR_ROWS[idx + 1]
        local row
        row, hh = W:DualRow(
            widget,
            sy,
            { type = "label", text = leftX.label },
            right and { type = "label", text = right.label } or { type = "label", text = "" }
        )
        sy = sy - hh
        AddDispelSwatch(row._leftRegion, leftX)
        if right then
            AddDispelSwatch(row._rightRegion, right)
        end
    end

    return sy
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

local function BuildFxEffects(widget, sy, conf, apply)
    local W = CludesUI.Widgets
    local Pix = CludesUI.PanelPP
    if not (W and Pix) then
        return sy
    end
    local hh
    local MEDIA_MP = "Interface\\AddOns\\CludesUI\\media\\icons\\"

    local entries = conf.fxList or {}

    -- Real AuraButtons forbid driver-ticked glows (Blizzard_AuraButton.xml:
    -- ForbiddenAspects baked into the template), so the icon glow is an engine
    -- host: the shared controls offer only what renders there.
    local GO = CludesUI.GlowOptions

    -- One "ICON EFFECTS" section block per list entry.
    for bi = 1, #entries do
        local e = entries[bi]
        if not e.filters then
            e.filters = {}
        end

        local hdrRgn
        hdrRgn, hh = W:SectionHeader(widget, "ICON EFFECTS", sy)
        sy = sy - hh
        -- Remove X right after the section title text
        if hdrRgn then
            local del = CreateFrame("Button", nil, hdrRgn)
            del:SetSize(14, 14)
            if hdrRgn._label then
                del:SetPoint("LEFT", hdrRgn._label, "RIGHT", 8, 0)
            else
                del:SetPoint("BOTTOMRIGHT", hdrRgn, "BOTTOMRIGHT", 0, 6)
            end
            del:SetFrameLevel(hdrRgn:GetFrameLevel() + 2)
            del:SetAlpha(0.5)
            local dx = del:CreateTexture(nil, "OVERLAY")
            dx:SetAllPoints()
            if dx.SetSnapToPixelGrid then
                dx:SetSnapToPixelGrid(false)
                dx:SetTexelSnappingBias(0)
            end
            dx:SetTexture(MEDIA_MP .. "cui-close.png")
            del:SetScript("OnEnter", function(self)
                self:SetAlpha(0.9)
                CludesUI.ShowWidgetTooltip(self, CludesUI.L("Delete"))
            end)
            del:SetScript("OnLeave", function(self)
                self:SetAlpha(0.5)
                CludesUI.HideWidgetTooltip()
            end)
            local blockIdx = bi
            del:SetScript("OnClick", function()
                table.remove(entries, blockIdx)
                apply()
                CludesUI:RefreshPage(true)
            end)
        end

        -- Row 1: Filters | Icon Glow (shared glow controls)
        local glowDesc = GO.PrefixSite(function()
            return e
        end, "glow", "engine", apply)
        -- The half next to Filters is too narrow for the color swatches.
        glowDesc.colorInCog = true
        local row
        row, hh = W:DualRow(widget, sy, {
            type = "dropdown",
            text = "Filters",
            values = { __placeholder = "..." },
            order = { "__placeholder" },
            getValue = function()
                return "__placeholder"
            end,
            setValue = function() end,
        }, GO.DropdownSpec(glowDesc, "Icon Glow"))
        sy = sy - hh
        do
            local rgn = row._leftRegion
            if rgn._control then
                rgn._control:Hide()
            end
            local itemList = mod.PAB_FxClassItems and mod.PAB_FxClassItems() or {}
            local cbDD, cbRefresh = CludesUI.BuildVisOptsCBDropdown(
                rgn,
                190,
                rgn:GetFrameLevel() + 2,
                itemList,
                function(k)
                    return e.filters[k] == true
                end,
                function(k, val)
                    e.filters[k] = val or nil
                    apply()
                    CludesUI:RefreshPage()
                end
            )
            Pix.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
            rgn._control = cbDD
            rgn._lastInline = nil
            if cbRefresh then
                CludesUI.RegisterWidgetRefresh(cbRefresh)
            end
        end
        GO.AttachInline(row._rightRegion, glowDesc)

        -- Row 2: Border (+ swatch) | Size (icon size for the matched
        -- filters; 0 = the bar's own icon size).
        -- Border: solid px only (no Border Style here), so a plain 0-4 slider view
        -- over e.borderSize, the same number the dropdown wrote. A custom Icon
        -- Shape keeps the None..Strong dropdown (the shape ring is on/off); the
        -- Icon Shape setter rebuilds the page on a none/custom crossing.
        local fxBorderCfg
        if IsMaskShape(conf.iconShape) then
            fxBorderCfg = {
                type = "dropdown",
                text = "Border",
                values = BORDER_SIZE_VALUES,
                order = BORDER_SIZE_LEVELS,
                itemDisabled = function(val)
                    return IsMaskShape(conf.iconShape) and BORDER_SIZE_SHAPE_DISABLED[val] or false
                end,
                itemDisabledTooltip = function()
                    return "This option requires a non-custom shape to be selected"
                end,
                getValue = function()
                    return BORDER_SIZE_KEY[e.borderSize or 0] or "none"
                end,
                setValue = function(val)
                    e.borderSize = BORDER_SIZE_NUM[val] or 0
                    apply()
                end,
            }
        else
            fxBorderCfg = {
                type = "slider",
                text = "Border",
                min = 0,
                max = 4,
                step = 1,
                trackWidth = 120,
                getValue = function()
                    return e.borderSize or 0
                end,
                setValue = function(val)
                    e.borderSize = val
                    apply()
                end,
            }
        end
        local bRow
        bRow, hh = W:DualRow(widget, sy, fxBorderCfg, {
            type = "slider",
            text = "Size",
            min = 0,
            max = 400,
            step = 1,
            trackWidth = 120,
            getValue = function()
                return e.size or 0
            end,
            setValue = function(val)
                e.size = (val and val > 0) and val or nil
                apply()
            end,
        })
        sy = sy - hh
        do
            local rgn = bRow._leftRegion
            local colorSwatch = CludesUI.BuildColorSwatch(rgn, bRow:GetFrameLevel() + 3, function()
                local c = e.borderColor or { r = 0, g = 0, b = 0 }
                return c.r or 0, c.g or 0, c.b or 0, 1
            end, function(r, g, b)
                e.borderColor = { r = r, g = g, b = b }
                apply()
            end, false, 20)
            colorSwatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -8, 0)
            rgn._lastInline = colorSwatch
        end
    end

    -- "Add Icon Effects Per-Filter" accent text link (centered)
    do
        local ar, ag, ab = 1, 0.82, 0.30
        if CludesUI.GetAccentColor then
            ar, ag, ab = CludesUI.GetAccentColor()
        end
        local addBtn = CreateFrame("Button", nil, widget)
        addBtn:SetHeight(22)
        addBtn:SetPoint("TOP", widget, "TOP", 0, sy - 17)
        addBtn:SetFrameLevel(widget:GetFrameLevel() + 2)
        local labelFS = addBtn:CreateFontString(nil, "OVERLAY")
        local fp = (CludesUI.GetFontPath("unitFrames")) or "Fonts\\FRIZQT__.TTF"
        labelFS:SetFont(fp, 16, "")
        labelFS:SetPoint("CENTER", addBtn, "CENTER", 0, 0)
        labelFS:SetText(CludesUI.L("Add Icon Effects Per-Filter"))
        labelFS:SetTextColor(ar, ag, ab)
        labelFS:SetAlpha(0.9)
        addBtn:SetWidth(labelFS:GetStringWidth() + 8)
        addBtn:SetScript("OnEnter", function()
            labelFS:SetAlpha(1)
        end)
        addBtn:SetScript("OnLeave", function()
            labelFS:SetAlpha(0.9)
        end)
        addBtn:SetScript("OnClick", function()
            conf.fxList = conf.fxList or {}
            conf.fxList[#conf.fxList + 1] = { filters = {} }
            CludesUI:RefreshPage(true)
        end)
        sy = sy - 17 - 22 - 8
    end
    return sy
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
local function WrapCompensatedBody(parentFrame, topOffset)
    local contentPad = CludesUI.CONTENT_PAD or 45
    local PAD = 20 -- matches PABMP_BuildPage's own detail-pane inset
    local padDiff = contentPad - PAD
    local visibleW = parentFrame:GetWidth()

    local scroll = CreateFrame("ScrollFrame", nil, parentFrame)
    scroll:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", -padDiff, topOffset or 0)
    scroll:SetPoint("BOTTOMRIGHT", parentFrame, "BOTTOMRIGHT", padDiff, 0)
    scroll:SetFrameLevel(parentFrame:GetFrameLevel() + 1)
    scroll:SetClipsChildren(true)

    local body = CreateFrame("Frame", nil, scroll)
    body:SetSize(visibleW + padDiff * 2, 10) -- finalized by FinalizeCompensatedBody
    body._showRowDivider = true
    scroll:SetScrollChild(body)
    body._pabUpdateThumb = AttachEditorScroll(scroll, body, nil, padDiff + 2, true)

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
            scroll:ClearAllPoints()
            scroll:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", -padDiff, newTopOffset)
            scroll:SetPoint("BOTTOMRIGHT", parentFrame, "BOTTOMRIGHT", padDiff, 0)
            if body._pabUpdateThumb then
                body._pabUpdateThumb()
            end
        end)
    end

    return body
end

-- Sizes the scroll child to its real content height and refreshes the scrollbar's
-- thumb/track visibility. Call once, after all of a detail pane's fields have been
-- built into `body` and the final sy/by accumulator value is known.
local function FinalizeCompensatedBody(body, sy)
    body:SetHeight(max(10, math.abs(sy) + 20))
    if body._pabUpdateThumb then
        body._pabUpdateThumb()
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
    local sub = widget:CreateFontString(nil, "OVERLAY")
    sub:SetFont(fontFile, 13, "")
    sub:SetPoint("LEFT", title, "RIGHT", 4, 0)
    sub:SetPoint("RIGHT", widget, "RIGHT", -pad, 0)
    sub:SetJustifyH("LEFT")
    sub:SetWordWrap(false)
    sub:SetTextColor(0.75, 0.75, 0.75, 0.65)
    sub:SetText("(" .. (subtitle or "") .. ")")
    return posY - 11 - 18 - 5
end

local function BuildDefaultBarDetail(widget, fontFile, isBuff)
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
    local conf = isBuff and mod.PAB_DefaultBuffsCfg(s) or mod.PAB_DefaultDebuffsCfg(s)

    local function ApplyBar()
        if mod.PAB_Restyle then
            mod.PAB_Restyle()
        end
        if mod.PAB_ApplyLiveConfig then
            mod.PAB_ApplyLiveConfig(isBuff)
        end
    end

    local scrollTop = 0
    if mod.PAB_BuildPreviewBox then
        scrollTop =
            mod.PAB_BuildPreviewBox(widget, fontFile, 0, isBuff and "buff" or "debuff", "default", conf)
    end
    local body = WrapCompensatedBody(widget, scrollTop)
    local sy = 0
    sy = BuildBarTitle(
        body,
        fontFile,
        isBuff and DefaultBuffBarName(conf) or L("Debuffs"),
        L("Built-in bar. Cannot be deleted"),
        sy
    )

    if isBuff then
        sy = BuildAssignedBuffsFields(body, fontFile, sy, conf, ApplyBar, true)
    else
        sy = BuildAssignedDebuffsFields(body, fontFile, sy, conf, ApplyBar)
    end
    sy = BuildCoreFields(body, fontFile, sy, conf, ApplyBar, isBuff)
    sy = BuildDisplayFields(body, fontFile, sy, conf, ApplyBar, isBuff)
    if not isBuff then
        sy = BuildDispelColorFields(body, fontFile, sy, conf, ApplyBar)
        sy = BuildFxEffects(body, sy, conf, ApplyBar)
    end
    FinalizeCompensatedBody(body, sy)
end
-- Sidebar tile: the shared manager tile at this page's 58px height, with a
-- 14px pencil and a narrower text inset when there is no pill.
local function BuildTile(parentFrame, posY, options)
    options.height, options.textRight = TILE_H, options.showToggle and -52 or -16
    options.editSize, options.editSnap = 14, true
    return CludesUI.BuildManagerTile(parentFrame, posY, options)
end

-- Sidebar "Add New" button (Raid Frames Buff Manager parity: solid green
-- accent button, 60% of the sidebar width, centered; background brightens
-- from 0.8 to full alpha on hover).
local function AddNewButton(parentFrame, posY, width, labelText, onClick)
    local btnW = floor(width * 0.6)
    local addBtn = CreateFrame("Button", nil, parentFrame)
    addBtn:SetSize(btnW, 30)
    addBtn:SetPoint("TOP", parentFrame, "TOPLEFT", floor(width / 2), posY - 10)
    addBtn:SetFrameLevel(parentFrame:GetFrameLevel() + 1)
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

local function Apply(isBuff, barId)
    if isBuff then
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
local function BuildBuffBarDetail(widget, fontFile, bar)
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
        Apply(true, bar.id)
    end

    local scrollTop = 0
    if mod.PAB_BuildPreviewBox then
        scrollTop = mod.PAB_BuildPreviewBox(widget, fontFile, 0, "buff", bar.id, bar)
    end
    local body = WrapCompensatedBody(widget, scrollTop)
    local by = 0
    by = BuildBarTitle(body, fontFile, L(bar.name or "Buff Bar"), L("Custom buff bar"), by)
    by = BuildAssignedBuffsFields(body, fontFile, by, bar, ApplyBar)
    by = BuildCoreFields(body, fontFile, by, bar, ApplyBar, true)
    by = BuildDisplayFields(body, fontFile, by, bar, ApplyBar, true)
    FinalizeCompensatedBody(body, by)
end

-------------------------------------------------------------------------------
--  Custom Debuff Bar detail pane -- category/class-token based, no SpellID
-- popup (by design: debuffs stay category-based, same as
--  RaidFrames).
-------------------------------------------------------------------------------

local function BuildDebuffBarDetail(widget, fontFile, bar)
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
        Apply(false, bar.id)
    end

    local scrollTop = 0
    if mod.PAB_BuildPreviewBox then
        scrollTop = mod.PAB_BuildPreviewBox(widget, fontFile, 0, "debuff", bar.id, bar)
    end
    local body = WrapCompensatedBody(widget, scrollTop)
    local by = 0
    by = BuildBarTitle(body, fontFile, L(bar.name or "Debuff Bar"), L("Custom debuff bar"), by)
    by = BuildAssignedDebuffsFields(body, fontFile, by, bar, ApplyBar)
    by = BuildCoreFields(body, fontFile, by, bar, ApplyBar, false)
    by = BuildDisplayFields(body, fontFile, by, bar, ApplyBar, false)
    by = BuildDispelColorFields(body, fontFile, by, bar, ApplyBar)
    by = BuildFxEffects(body, by, bar, ApplyBar)
    FinalizeCompensatedBody(body, by)
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
AttachEditorScroll = function(scroll, childFrame, onScroll, rightInset, panelWheel)
    return CludesUI.AttachSmoothScrollbar(scroll, {
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
    local eg = CludesUI.CLUDES_GREEN or { r = 0.30, g = 0.79, b = 0.94 }
    local MEDIA_FE = "Interface\\AddOns\\CludesUI\\media\\icons\\"

    local POPUP_W, POPUP_H, SIDE_W = 620, 520, 180

    -- One editor for the session: every open and every Rebuild() dresses the
    -- same dimmer again, and the frames below it come back from the pool.
    local dimmer = PoolKept(mod, "pabFilterEditor", "Frame", UIParent)
    dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
    dimmer:SetAllPoints(UIParent)
    dimmer:EnableMouse(true)
    dimmer:EnableMouseWheel(true)
    dimmer:SetScript("OnMouseWheel", function() end)
    dimmer:SetScript("OnMouseDown", function()
        dimmer:Hide()
        mod._pabFilterEditor = nil
    end)
    local dimTex = CludesUI.SolidTex(dimmer, "BACKGROUND", 0, 0, 0, 0.25)
    dimTex:SetAllPoints()
    mod._pabFilterEditor = dimmer

    local dialog = CreateFrame("Frame", nil, dimmer)
    dialog:SetSize(POPUP_W, POPUP_H)
    dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    dialog:SetFrameStrata("FULLSCREEN_DIALOG")
    dialog:SetFrameLevel(dimmer:GetFrameLevel() + 10)
    dialog:EnableMouse(true)
    local popBg = CludesUI.SolidTex(dialog, "BACKGROUND", 0.062, 0.070, 0.082, 1)
    popBg:SetAllPoints()
    CludesUI.MakeRoundedBorder(dialog, 1, 1, 1, 0.15, popBg)
    if CludesUI.GetPopupScale then
        dialog:SetScale(CludesUI.GetPopupScale())
    end

    local title = CludesUI.MakeFont(dialog, 16, "", 1, 1, 1)
    title:SetPoint("TOP", dialog, "TOP", 0, -18)
    title:SetText(L("Edit Filters"))

    do
        local close = CreateFrame("Button", nil, dialog)
        close:SetSize(19, 19)
        close:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -13, -8)
        close:SetFrameLevel(dialog:GetFrameLevel() + 5)
        local closeIcon = close:CreateTexture(nil, "ARTWORK")
        closeIcon:SetAllPoints()
        closeIcon:SetTexture(MEDIA_FE .. "cui-close.png")
        closeIcon:SetAlpha(0.40)
        closeIcon:SetSnapToPixelGrid(false)
        closeIcon:SetTexelSnappingBias(0)
        close:SetScript("OnEnter", function()
            closeIcon:SetAlpha(0.50)
        end)
        close:SetScript("OnLeave", function()
            closeIcon:SetAlpha(0.40)
        end)
        close:SetScript("OnClick", function()
            dimmer:Hide()
            mod._pabFilterEditor = nil
        end)
    end

    -- Escape closes the editor alone: the key is swallowed here, so it never
    -- reaches the Escape proxy that would close the options window too.
    -- SetPropagateKeyboardInput is protected in combat, so the editor takes
    -- the keyboard only when built out of combat and stands aside in it. The
    -- capture is a frame of its own, owned by the popup outside its child
    -- list: a dress in combat cannot clear keyboard flags, so it leaves only
    -- that frame for the next dress out of combat, never the popup.
    if not InCombatLockdown() then
        local keyList = PoolOwned(dialog, "keys", "Frame", dialog)
        keyList:SetAllPoints(dialog)
        keyList:EnableKeyboard(true)
        keyList:SetPropagateKeyboardInput(true)
        keyList:SetScript("OnKeyDown", function(self, key)
            if InCombatLockdown() then
                return
            end
            self:SetPropagateKeyboardInput(key ~= "ESCAPE")
            if key == "ESCAPE" then
                dimmer:Hide()
                mod._pabFilterEditor = nil
            end
        end)
    end

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

    local sideScroll = CreateFrame("ScrollFrame", nil, side)
    sideScroll:SetPoint("TOPLEFT", side, "TOPLEFT", 1, -1)
    sideScroll:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", -1, 1)
    sideScroll:SetFrameLevel(side:GetFrameLevel() + 1)
    local sideChild = CreateFrame("Frame", nil, sideScroll)
    sideChild:SetWidth(SIDE_W - 2)
    sideScroll:SetScrollChild(sideChild)

    local fy = -4
    for idx = 1, #filters do
        local f = filters[idx]
        local isSel = (pabFilterSel == f.id)
        local frow = CreateFrame("Button", nil, sideChild)
        frow:SetHeight(26)
        frow:SetPoint("TOPLEFT", sideChild, "TOPLEFT", 0, fy)
        frow:SetPoint("TOPRIGHT", sideChild, "TOPRIGHT", 0, fy)
        frow:SetFrameLevel(sideChild:GetFrameLevel() + 1)
        local rbg = frow:CreateTexture(nil, "BACKGROUND")
        rbg:SetAllPoints()
        rbg:SetColorTexture(1, 1, 1, isSel and 0.07 or 0)
        local rl = CludesUI.MakeFont(frow, 12, nil, 1, 1, 1)
        rl:SetAlpha(isSel and 0.95 or 0.6)
        rl:SetPoint("LEFT", frow, "LEFT", 10, 0)
        rl:SetPoint("RIGHT", frow, "RIGHT", f.preset and -8 or -42, 0)
        rl:SetJustifyH("LEFT")
        rl:SetWordWrap(false)
        rl:SetText(L(f.name))
        if isSel then
            local accent = frow:CreateTexture(nil, "ARTWORK", nil, 2)
            accent:SetSize(2, 26)
            accent:SetPoint("TOPLEFT", frow, "TOPLEFT", 0, 0)
            accent:SetColorTexture(eg.r, eg.g, eg.b, 0.9)
        end
        frow:SetScript("OnEnter", function()
            if not isSel then
                rbg:SetColorTexture(1, 1, 1, 0.04)
            end
        end)
        frow:SetScript("OnLeave", function()
            rbg:SetColorTexture(1, 1, 1, isSel and 0.07 or 0)
        end)
        frow:SetScript("OnClick", function()
            pabFilterSel = f.id
            pabFilterScrollPos = 0
            Rebuild()
        end)

        -- Imported Buff Manager presets (f.preset = true) are protected --
        -- not renameable/deletable, matching BM2's own `if not f.preset`
        -- guard exactly. User-created filters keep both icons.
        if not f.preset then
            local del = CreateFrame("Button", nil, frow)
            del:SetSize(14, 14)
            del:SetPoint("RIGHT", frow, "RIGHT", -6, 0)
            del:SetFrameLevel(frow:GetFrameLevel() + 1)
            del:SetAlpha(0.5)
            local dx = del:CreateTexture(nil, "OVERLAY")
            dx:SetAllPoints()
            if dx.SetSnapToPixelGrid then
                dx:SetSnapToPixelGrid(false)
                dx:SetTexelSnappingBias(0)
            end
            dx:SetTexture(MEDIA_FE .. "cui-close.png")
            del:SetScript("OnEnter", function(self)
                self:SetAlpha(0.9)
                CludesUI.ShowWidgetTooltip(self, L("Delete"))
            end)
            del:SetScript("OnLeave", function(self)
                self:SetAlpha(0.5)
                CludesUI.HideWidgetTooltip()
            end)
            del:SetScript("OnClick", function()
                CludesUI:ShowConfirmPopup({
                    title = L("Delete Filter"),
                    message = L("Delete this filter? It is removed from every bar using it."),
                    confirmText = L("Delete"),
                    cancelText = L("Cancel"),
                    onConfirm = function()
                        mod.PAB_DeleteFilter(f.id)
                        ApplyAll()
                        Rebuild()
                    end,
                })
            end)

            local edit = CreateFrame("Button", nil, frow)
            edit:SetSize(14, 14)
            edit:SetPoint("RIGHT", del, "LEFT", -4, 0)
            edit:SetFrameLevel(frow:GetFrameLevel() + 1)
            edit:SetAlpha(0.5)
            local ex = edit:CreateTexture(nil, "OVERLAY")
            ex:SetAllPoints()
            if ex.SetSnapToPixelGrid then
                ex:SetSnapToPixelGrid(false)
                ex:SetTexelSnappingBias(0)
            end
            ex:SetTexture(MEDIA_FE .. "cui-edit.png")
            edit:SetScript("OnEnter", function(self)
                self:SetAlpha(0.9)
                CludesUI.ShowWidgetTooltip(self, L("Edit"))
            end)
            edit:SetScript("OnLeave", function(self)
                self:SetAlpha(0.5)
                CludesUI.HideWidgetTooltip()
            end)
            edit:SetScript("OnClick", function()
                EditorInput({
                    title = L("Rename Filter"),
                    placeholder = L(f.name),
                    confirmText = L("Rename"),
                    cancelText = L("Cancel"),
                    onConfirm = function(textValue)
                        mod.PAB_RenameFilter(f.id, textValue)
                        Rebuild()
                    end,
                })
            end)
        end
        fy = fy - 27
    end
    local addFilterBtn = CludesUI.BuildPopupButton(sideChild, SIDE_W - 16, 26, "Add Filter", function()
        EditorInput({
            title = L("Add Filter"),
            message = L("Name the new filter."),
            confirmText = L("Add"),
            cancelText = L("Cancel"),
            onConfirm = function(textValue)
                local f = mod.PAB_AddFilter((textValue and textValue ~= "" and textValue) or L("New Filter"))
                if f then
                    pabFilterSel = f.id
                end
                Rebuild()
            end,
        })
    end)
    addFilterBtn:SetPoint("TOPLEFT", sideChild, "TOPLEFT", 8, fy - 8)
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

    local leftX = CreateFrame("Frame", nil, dialog)
    leftX:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -44)
    leftX:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -(SIDE_W + 12), 12)
    leftX:SetFrameLevel(dialog:GetFrameLevel() + 1)

    local nm = CludesUI.MakeFont(leftX, 13, nil, 1, 1, 1)
    nm:SetAlpha(0.9)
    nm:SetPoint("TOPLEFT", leftX, "TOPLEFT", 2, -2)
    nm:SetText(L(sel.name))
    if not sel.preset then
        local ren = CreateFrame("Button", nil, leftX)
        ren:SetSize(54, 16)
        ren:SetPoint("LEFT", nm, "RIGHT", 10, 0)
        ren:SetFrameLevel(leftX:GetFrameLevel() + 2)
        local rl = CludesUI.MakeFont(ren, 11, nil, ar, ag, ab)
        rl:SetAlpha(0.9)
        rl:SetPoint("LEFT")
        rl:SetText(L("Rename"))
        ren:SetScript("OnEnter", function()
            rl:SetAlpha(1)
        end)
        ren:SetScript("OnLeave", function()
            rl:SetAlpha(0.9)
        end)
        ren:SetScript("OnClick", function()
            EditorInput({
                title = L("Rename Filter"),
                placeholder = L(sel.name),
                confirmText = L("Rename"),
                cancelText = L("Cancel"),
                onConfirm = function(textValue)
                    mod.PAB_RenameFilter(sel.id, textValue)
                    Rebuild()
                end,
            })
        end)
    end

    -- Search Spells: same curated (deduped) universe as the Extra Spells
    -- dropdown, matching BM2's own search exactly (BM2's comment:
    -- "identical list to the Extra Spells dropdown").
    local searchDD = CludesUI.BuildVisOptsCBDropdown(leftX, 170, leftX:GetFrameLevel() + 5, function()
        local universe = DedupedPresetSpellUniverse()
        local result = {}
        for idx = 1, #universe do
            local ident = universe[idx]
            -- An id kept only for the other client is not on the filter here.
            if sel.spells[ident] == nil or mod.PAB_OtherClientSpell(sel, ident) then
                local nm2 = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(ident)
                result[#result + 1] = {
                    key = ident,
                    label = nm2 or tostring(ident),
                    noCheck = true,
                    icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(ident),
                }
            end
        end
        table.sort(result, function(a, b)
            return tostring(a.label or a.key) < tostring(b.label or b.key)
        end)
        return result
    end, function()
        return false
    end, function(k, val)
        if val and mod.PAB_AddSpellToFilter and mod.PAB_AddSpellToFilter(sel.id, k) then
            ApplyAll()
            Rebuild()
        end
    end, nil, 10, true)
    searchDD:ClearAllPoints()
    searchDD:SetPoint("TOPLEFT", leftX, "TOPLEFT", 2, -23)
    for _, r in ipairs({ searchDD:GetRegions() }) do
        if r.SetText and r.GetText then
            r:SetText(L("Search Spells"))
            break
        end
    end

    local addSpellBtn = CludesUI.BuildPopupButton(leftX, 110, 24, "Add Spell ID", function()
        EditorInput({
            title = L("Add Spell ID"),
            message = L("Enter the spell ID to add to this filter."),
            confirmText = L("Add"),
            cancelText = L("Cancel"),
            onConfirm = function(textValue)
                local ident = tonumber(textValue or "")
                if ident and mod.PAB_AddSpellToFilter(sel.id, ident) then
                    ApplyAll()
                    Rebuild()
                end
            end,
        })
    end)
    addSpellBtn:SetPoint("LEFT", searchDD, "RIGHT", 8, 0)

    -- Spell checkbox list: mirrors the checkbox-dropdown widget's visuals exactly (16px
    -- box, accent fill inset 2, hover wash), grouped by class (via
    -- PAB_SPELL_CLASS_HINTS) with a Custom group for anything without a hint.
    local scroll = CreateFrame("ScrollFrame", nil, leftX)
    scroll:SetPoint("TOPLEFT", leftX, "TOPLEFT", 0, -58)
    scroll:SetPoint("BOTTOMRIGHT", leftX, "BOTTOMRIGHT", 0, 0)
    local childFrame = CreateFrame("Frame", nil, scroll)
    childFrame:SetWidth(POPUP_W - SIDE_W - 40)
    scroll:SetScrollChild(childFrame)
    local _updSpellThumb, setSpellScroll = AttachEditorScroll(scroll, childFrame, function(val)
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
    local seenNames = {}
    for idx = 1, #allIds do
        local ident = allIds[idx]
        local dedupKey = NameOf(ident)
        if not seenNames[dedupKey] then
            seenNames[dedupKey] = true
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

    local cy = 0
    local function SpellRow(ident, classColor)
        local srow = CreateFrame("Button", nil, childFrame)
        srow:SetHeight(24)
        srow:SetPoint("TOPLEFT", childFrame, "TOPLEFT", 2, cy)
        srow:SetPoint("TOPRIGHT", childFrame, "TOPRIGHT", -2, cy)
        srow:SetFrameLevel(childFrame:GetFrameLevel() + 1)
        local highlight = srow:CreateTexture(nil, "ARTWORK")
        highlight:SetAllPoints()
        highlight:SetColorTexture(1, 1, 1, 0)
        local box = CreateFrame("Frame", nil, srow)
        box:SetSize(16, 16)
        box:SetPoint("LEFT", srow, "LEFT", 6, 0)
        local boxBg = box:CreateTexture(nil, "BACKGROUND")
        boxBg:SetAllPoints()
        boxBg:SetColorTexture(0.114, 0.106, 0.099, 1)
        local boxBrd = CludesUI.MakeRoundedBorder(box, 0.4, 0.4, 0.4, 0.6, boxBg)
        local chk = box:CreateTexture(nil, "ARTWORK")
        chk:SetPoint("TOPLEFT", box, "TOPLEFT", 2, -2)
        chk:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -2, 2)
        chk:SetColorTexture(eg.r, eg.g, eg.b, 1)
        CludesUI.RoundBody(box, chk, 2)
        local on = sel.spells[ident] and true or false
        local ico = srow:CreateTexture(nil, "ARTWORK")
        ico:SetSize(22, 22)
        ico:SetPoint("LEFT", box, "RIGHT", 6, 0)
        local tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(ident)
        if tex then
            ico:SetTexture(tex)
        end
        ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(ident)
        local lr, lg2, lb2 = 1, 1, 1
        if classColor then
            lr, lg2, lb2 = classColor.r, classColor.g, classColor.b
        end
        local labelFS = CludesUI.MakeFont(srow, 13, nil, lr, lg2, lb2)
        labelFS:SetPoint("LEFT", ico, "RIGHT", 6, 0)
        labelFS:SetPoint("RIGHT", srow, "RIGHT", -24, 0) -- every PAB row is deletable, always reserve the X's space
        labelFS:SetJustifyH("LEFT")
        labelFS:SetWordWrap(false)
        labelFS:SetText(name or ("Spell " .. tostring(ident)))
        local function UpdateRow()
            on = sel.spells[ident] and true or false
            if on then
                chk:Show()
                if boxBrd and boxBrd.SetColor then
                    boxBrd:SetColor(eg.r, eg.g, eg.b, 0.8)
                end
            else
                chk:Hide()
                if boxBrd and boxBrd.SetColor then
                    boxBrd:SetColor(0.4, 0.4, 0.4, 0.6)
                end
            end
            labelFS:SetAlpha(on and 0.9 or 0.45)
            ico:SetAlpha(on and 1 or 0.45)
            ico:SetDesaturated(not on)
        end
        UpdateRow()
        srow:SetScript("OnEnter", function()
            highlight:SetColorTexture(1, 1, 1, 0.04)
        end)
        srow:SetScript("OnLeave", function()
            highlight:SetColorTexture(1, 1, 1, 0)
        end)
        srow:SetScript("OnClick", function()
            mod.PAB_SetSpellState(sel.id, ident, not on)
            ApplyAll()
            UpdateRow()
        end)
        local del = CreateFrame("Button", nil, srow)
        del:SetSize(14, 14)
        del:SetPoint("RIGHT", srow, "RIGHT", -6, 0)
        del:SetFrameLevel(srow:GetFrameLevel() + 1)
        del:SetAlpha(0.5)
        local dx = del:CreateTexture(nil, "OVERLAY")
        dx:SetAllPoints()
        if dx.SetSnapToPixelGrid then
            dx:SetSnapToPixelGrid(false)
            dx:SetTexelSnappingBias(0)
        end
        dx:SetTexture(MEDIA_FE .. "cui-close.png")
        del:SetScript("OnEnter", function(self)
            self:SetAlpha(0.9)
        end)
        del:SetScript("OnLeave", function(self)
            self:SetAlpha(0.5)
        end)
        del:SetScript("OnClick", function()
            mod.PAB_SetSpellState(sel.id, ident, nil)
            ApplyAll()
            Rebuild()
        end)
        cy = cy - 29
    end
    local function GroupHeader(textValue)
        local heading = CludesUI.MakeFont(childFrame, 14, nil, 0.5, 0.5, 0.5)
        heading:SetPoint("TOPLEFT", childFrame, "TOPLEFT", 2, cy - 10)
        heading:SetText(textValue)
        local line = childFrame:CreateTexture(nil, "ARTWORK")
        line:SetHeight(1)
        line:SetPoint("LEFT", heading, "RIGHT", 6, 0)
        line:SetPoint("RIGHT", childFrame, "RIGHT", -10, 0)
        line:SetColorTexture(0.3, 0.3, 0.3, 0.5)
        cy = cy - 30
    end
    if #customList > 0 then
        GroupHeader(L("Custom"))
        for idx = 1, #customList do
            SpellRow(customList[idx])
        end
    end
    for c = 1, #CLASS_ORDER do
        local cls = CLASS_ORDER[c]
        local entries = byClass[cls]
        if entries and #entries > 0 then
            local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[cls]
            local cname = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cls] or cls
            GroupHeader(cc and ("|c" .. cc.colorStr .. cname .. "|r") or cname)
            for idx = 1, #entries do
                SpellRow(entries[idx], cc)
            end
        end
    end
    if cy == 0 then
        local empty = CludesUI.MakeFont(childFrame, 12, nil, 1, 1, 1)
        empty:SetAlpha(0.4)
        empty:SetPoint("TOPLEFT", childFrame, "TOPLEFT", 4, -6)
        empty:SetText(L("No spells yet. Add spell IDs above."))
        cy = -30
    end
    childFrame:SetHeight(math.abs(cy) + 10)

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

local function ShowAddBarPopup(anchorBtn, kind, fontFile)
    if pabAddPopup and pabAddPopup:IsShown() and pabAddPopup._kind == kind then
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
            p2:SetScript("OnUpdate", function(m)
                if not (m._anchorBtn and m._anchorBtn:IsMouseOver()) and not m:IsMouseOver() then
                    if IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton") then
                        m:Hide()
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
    dialog._kind = kind
    dialog._anchorBtn = anchorBtn
    dialog._nameBox:SetText("")
    dialog._createBtn:SetScript("OnClick", function()
        local textValue = dialog._nameBox:GetText()
        local name = (textValue and textValue ~= "") and textValue or nil
        local bar
        -- New bars land in the EDITED editing-spec bucket ("allspecs" =
        -- the legacy arrays, today's behavior).
        if kind == "buff" then
            bar = mod.PAB_AddCustomBuffBar and mod.PAB_AddCustomBuffBar(name, pabSpecSel)
        else
            bar = mod.PAB_AddCustomDebuffBar and mod.PAB_AddCustomDebuffBar(name, pabSpecSel)
        end
        dialog:Hide()
        if bar then
            pabSel = { kind = kind, id = bar.id }
            pabInhSel = nil
            Apply(kind == "buff", bar.id)
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
    local root = mod._pabRoot
    if not root then
        return
    end
    mod._pabRoot = nil
    root:Hide()
    if not pabRootPark then
        pabRootPark = CreateFrame("Frame", nil, UIParent)
        pabRootPark:Hide()
    end
    root:SetParent(pabRootPark)
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
    if pabInhSel and inhGroups then
        for gi = 1, #inhGroups do
            if inhGroups[gi] == pabInhSel.group then
                local gl = mod.PAB_BucketBars
                    and mod.PAB_BucketBars(pabInhSel.kind == "buff", pabInhSel.group)
                for idx = 1, #(gl or {}) do
                    if gl[idx].id == pabInhSel.id then
                        pabInhBar = gl[idx]
                        break
                    end
                end
                break
            end
        end
    end
    if not pabInhBar then
        pabInhSel = nil
    end

    -- Validate selection against current data (bar may have been deleted
    -- elsewhere, e.g. profile switch). "default" is always valid (the two
    -- fixed built-in bars, not custom-bar list entries).
    if pabSel and pabSel.id ~= "default" then
        local success = false
        local entries = (pabSel.kind == "buff") and buffBars or debuffBars
        for idx = 1, #entries do
            if entries[idx].id == pabSel.id then
                success = true
            end
        end
        if not success then
            pabSel = { kind = "buff", id = "default" }
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
    if not showDefaults and pabSel and pabSel.id == "default" then
        local first = buffBars[1] or debuffBars[1]
        if first then
            pabSel = { kind = buffBars[1] and "buff" or "debuff", id = first.id }
        else
            pabSel = nil
        end
    end
    -- Back on a defaults-listing view with nothing selected: re-seed the
    -- default selection so the detail pane never stays blank.
    if showDefaults and not pabSel then
        pabSel = { kind = "buff", id = "default" }
    end

    -- Page-level "Player Aura Bars" header card removed (by request:
    -- it competed visually with the new per-bar preview box now sitting at the top of
    -- each detail pane). HEADER_H kept at 0 rather than removed outright so `root`'s
    -- offset math below still reads clearly as "below the (now empty) header band".
    local HEADER_H = 0

    local root = CreateFrame("Frame", nil, outerRoot)
    root:SetPoint("TOPLEFT", outerRoot, "TOPLEFT", 0, -HEADER_H)
    root:SetPoint("BOTTOMRIGHT", outerRoot, "BOTTOMRIGHT", 0, 0)
    root:SetFrameLevel(outerRoot:GetFrameLevel() + 1)
    local visibleH = fullH - HEADER_H

    local sidebarOuter = CreateFrame("Frame", nil, root)
    sidebarOuter:SetSize(sidebarW, visibleH)
    sidebarOuter:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, -1)
    sidebarOuter:SetFrameLevel(root:GetFrameLevel() + 1)
    local sbBg = sidebarOuter:CreateTexture(nil, "BACKGROUND")
    sbBg:SetAllPoints()
    sbBg:SetColorTexture(0, 0, 0, 0.25)
    CludesUI.CardSidebar(sidebarOuter, sbBg)
    -------------------------------------------------------------------
    --  SECTIONED SIDEBAR (fixed, no outer scroll): top options (Disable
    --  All / Use Blizzard Buffs), Editing Spec, then two independently
    --  scrollable halves (Buff Bars / Debuff Bars).
    -------------------------------------------------------------------
    local fixedY = -6

    -- The rows' pill and knob, drawn texel to pixel as the settings toggle's
    -- are (CludesUI.MakePixelLayer): a stadium and a circle sized for the
    -- layer's scale, the knob one pad in from the side its state sits on.
    local function OptionPillFit(L, k)
        local wid, hgt = L.parent:GetSize()
        local hp, wp = math.floor(hgt * k + 0.5), math.floor(wid * k + 0.5)
        if hp == L.hp and wp == L.wp then
            return
        end
        L.hp, L.wp = hp, wp
        local pad = math.max(1, math.floor(2 * k + 0.5))
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
        local row = CreateFrame("Frame", nil, sidebarOuter)
        row:SetSize(sidebarW, 26)
        row:SetPoint("TOPLEFT", sidebarOuter, "TOPLEFT", 0, posY)
        row:SetFrameLevel(sidebarOuter:GetFrameLevel() + 1)
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
    fixedY = OptionRow(
        fixedY,
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
    fixedY = OptionRow(
        fixedY,
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
    fixedY = fixedY - 9

    local function SectionDivider(posY)
        local div = sidebarOuter:CreateTexture(nil, "ARTWORK")
        div:SetHeight(1)
        div:SetPoint("TOPLEFT", sidebarOuter, "TOPLEFT", 8, posY - 4)
        div:SetPoint("TOPRIGHT", sidebarOuter, "TOPRIGHT", -8, posY - 4)
        div:SetColorTexture(1, 1, 1, 0.08)
        return posY - 9
    end

    -------------------------------------------------------------------
    --  EDITING SPEC (fixed block): group buckets lead, then every spec
    --  in the game as its own "spec<ID>" bucket. Bars in the selected
    --  bucket render only on matching specs; concrete views list the
    --  group bars as inherited read-only tiles below.
    -------------------------------------------------------------------
    do
        local specLabel = sidebarOuter:CreateFontString(nil, "OVERLAY")
        specLabel:SetFont(fontFile, 11, "")
        specLabel:SetPoint("TOP", sidebarOuter, "TOPLEFT", floor(sidebarW / 2), fixedY - 8)
        specLabel:SetText(L("EDITING SPEC"))
        specLabel:SetTextColor(0.6, 0.6, 0.6)
        fixedY = fixedY - 27

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
            sidebarOuter,
            sidebarW - 24,
            sidebarOuter:GetFrameLevel() + 2,
            specDDValues,
            specDDOrder,
            function()
                return pabSpecSel or "allspecs"
            end,
            function(val)
                pabSpecSel = val
                pabSel = { kind = "buff", id = "default" }
                pabInhSel = nil
                CludesUI:RefreshPage(true)
            end
        )
        specDD:SetPoint("TOP", sidebarOuter, "TOPLEFT", floor(sidebarW / 2), fixedY)
        fixedY = fixedY - 36
    end
    fixedY = SectionDivider(fixedY)

    -------------------------------------------------------------------
    --  Split halves (Buff Bars / Debuff Bars), each its own scroll; the
    --  sidebar itself no longer scrolls.
    -------------------------------------------------------------------
    local fixedH = math.abs(fixedY)
    -- Floor keeps the halves from collapsing/overlapping at pathological
    -- window heights (the sidebar also clips its children).
    local half = math.max(60, floor((visibleH - fixedH) / 2))
    sidebarOuter:SetClipsChildren(true)

    local function MakeSection(posY, height, headerText)
        local heading = sidebarOuter:CreateFontString(nil, "OVERLAY")
        heading:SetFont(fontFile, 11, "")
        heading:SetPoint("TOP", sidebarOuter, "TOPLEFT", floor(sidebarW / 2), posY - 13)
        heading:SetText(headerText)
        heading:SetTextColor(0.6, 0.6, 0.6)
        local scroll = CreateFrame("ScrollFrame", nil, sidebarOuter)
        scroll:SetPoint("TOPLEFT", sidebarOuter, "TOPLEFT", 0, posY - 32)
        scroll:SetSize(sidebarW, math.max(10, height - 32))
        scroll:SetClipsChildren(true)
        local childFrame = CreateFrame("Frame", nil, scroll)
        childFrame:SetWidth(sidebarW)
        scroll:SetScrollChild(childFrame)
        -- The standard smooth scroll + auto-hiding 4px scrollbar.
        local updateThumb = AttachEditorScroll(scroll, childFrame)
        return {
            child = childFrame,
            scroll = scroll,
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
            AddNewButton(sidebarOuter, sec.top - sec.height + ADD_AREA, sidebarW, labelText, onClick)
        end
        -- Prime the scrollbar's visibility (it otherwise first paints on the
        -- first wheel/drag).
        if sec.updateThumb then
            sec.updateThumb()
        end
    end

    local buffSec = MakeSection(fixedY, half, L("BUFF BARS"))
    local buffChild = buffSec.child
    -- 2% white wash over the whole Buff Bars half (header + list): visual
    -- separation from the debuff half below (user call). BACKGROUND
    -- sublevel 1 sits above the sidebar's own dark bg; tiles render above
    -- both (their frames level higher). Top edge starts at fixedY + 4 --
    -- flush against the divider LINE above (SectionDivider draws it 4px
    -- above the y it returns); bottom edge lands exactly on the
    -- between-halves divider.
    do
        local wash = sidebarOuter:CreateTexture(nil, "BACKGROUND", nil, 1)
        wash:SetPoint("TOPLEFT", sidebarOuter, "TOPLEFT", 0, fixedY + 4)
        wash:SetPoint("TOPRIGHT", sidebarOuter, "TOPRIGHT", 0, fixedY + 4)
        wash:SetHeight(half + 4)
        wash:SetColorTexture(1, 1, 1, 0.02)
    end
    local debuffTop = fixedY - half
    do
        local div = sidebarOuter:CreateTexture(nil, "ARTWORK")
        div:SetHeight(1)
        div:SetPoint("TOPLEFT", sidebarOuter, "TOPLEFT", 8, debuffTop)
        div:SetPoint("TOPRIGHT", sidebarOuter, "TOPRIGHT", -8, debuffTop)
        div:SetColorTexture(1, 1, 1, 0.08)
    end
    local debuffSec = MakeSection(debuffTop - 1, visibleH - fixedH - half - 1, L("DEBUFF BARS"))
    local debuffChild = debuffSec.child

    -- Inherited bar tiles for one section (concrete spec views only):
    -- read-only rows -- edit them in their group; the pill toggles ONLY
    -- this spec's enable (ns.PAB_SetInhDisabled). Builds into the given
    -- section child at y; returns the new y cursor.
    local function BuildInheritedBarTiles(sectionChild, tileY, isBuff)
        if not inhGroups then
            return tileY
        end
        for gi = 1, #inhGroups do
            local gkey = inhGroups[gi]
            local ginfo = SPEC_GROUP_INFO[gkey]
            local gname = ginfo and L(ginfo.name) or gkey
            local gl = (mod.PAB_BucketBars and mod.PAB_BucketBars(isBuff, gkey)) or {}
            for idx = 1, #gl do
                local bar = gl[idx]
                local disHere = mod.PAB_InhDisabled and mod.PAB_InhDisabled(pabSpecSel, bar.id)
                local kind = isBuff and "buff" or "debuff"
                tileY = tileY
                    - BuildTile(sectionChild, tileY, {
                        width = sidebarW,
                        fontPath = fontFile,
                        title = L(bar.name or (isBuff and "Buff Bar" or "Debuff Bar")),
                        subtitle = gname,
                        inheritedTooltip = CludesUI.Lf("Inherited from %1$s. Editable only there.", gname),
                        selected = (
                            pabInhSel
                            and pabInhSel.kind == kind
                            and pabInhSel.group == gkey
                            and pabInhSel.id == bar.id
                        )
                                and true
                            or false,
                        -- Pill = the PER-SPEC enable only; a group-level disable
                        -- dims the tile instead (the pill must never look dead).
                        dimmed = bar.enabled == false or nil,
                        enabled = (not disHere) and true or false,
                        showToggle = true,
                        onSelect = function()
                            pabInhSel = { kind = kind, group = gkey, id = bar.id }
                            CludesUI:RefreshPage(true)
                        end,
                        onToggle = function()
                            if not (mod.PAB_SetInhDisabled and mod.PAB_InhDisabled) then
                                return
                            end
                            mod.PAB_SetInhDisabled(
                                pabSpecSel,
                                bar.id,
                                not mod.PAB_InhDisabled(pabSpecSel, bar.id)
                            )
                            Apply(isBuff, bar.id)
                            CludesUI:RefreshPage(true)
                        end,
                    })
            end
        end
        return tileY
    end

    -- Buff bars section (top half): fixed "Buffs" default bar first (hidden
    -- while Use Blizzard Buffs owns the display), then custom bars.
    do
        local sidebarChild = buffChild -- section-scoped: this half's scroll child
        local tileY = 0

        -- Name follows the bar's content (see DefaultBuffBarName). Static, not
        -- a refresh client: every toggle that can change it forces a full page
        -- rebuild, which re-runs this.
        local sPAB = sPABTop
        local defBuffCfg = sPAB and mod.PAB_DefaultBuffsCfg and mod.PAB_DefaultBuffsCfg(sPAB) or nil
        if showDefaults then
            tileY = tileY
                - BuildTile(sidebarChild, tileY, {
                    width = sidebarW,
                    fontPath = fontFile,
                    title = DefaultBuffBarName(defBuffCfg),
                    subtitle = L("Default"),
                    selected = (
                        pabSel
                        and pabSel.kind == "buff"
                        and pabSel.id == "default"
                        and not pabInhSel
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
                        pabSel = { kind = "buff", id = "default" }
                        pabInhSel = nil
                        CludesUI:RefreshPage(true)
                    end,
                })
        end
        tileY = BuildInheritedBarTiles(sidebarChild, tileY, true)
        for idx = 1, #buffBars do
            local bar = buffBars[idx]
            tileY = tileY
                - BuildTile(sidebarChild, tileY, {
                    width = sidebarW,
                    fontPath = fontFile,
                    title = L(bar.name or "Buff Bar"),
                    subtitleFn = function()
                        return BuildBuffBarSubtitle(bar)
                    end,
                    selected = (pabSel and pabSel.kind == "buff" and pabSel.id == bar.id and not pabInhSel)
                            and true
                        or false,
                    enabled = bar.enabled and true or false,
                    showToggle = true,
                    onSelect = function()
                        pabSel = { kind = "buff", id = bar.id }
                        pabInhSel = nil
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
                                local nb = mod.PAB_CopyCustomBar and mod.PAB_CopyCustomBar(true, bar, key)
                                if nb then
                                    Apply(true, nb.id)
                                    CludesUI:RefreshPage(true)
                                end
                            end,
                        })
                    end,
                    onToggle = function(val)
                        bar.enabled = val and true or false
                        Apply(true, bar.id)
                        CludesUI:RefreshPage(true)
                    end,
                    onEdit = function()
                        CludesUI:ShowInputPopup({
                            title = L("Rename Bar"),
                            placeholder = L(bar.name or "Buff Bar"),
                            confirmText = L("Rename"),
                            cancelText = L("Cancel"),
                            onConfirm = function(textValue)
                                if textValue and textValue ~= "" then
                                    bar.name = textValue
                                    -- Re-registers this bar's Unlock Mode label from
                                    -- the new bar.name (RegisterPABCustomUnlock reads
                                    -- it live, but only ever re-runs from here) --
                                    -- without this, Unlock Mode kept showing the old
                                    -- name until the next /reload.
                                    Apply(true, bar.id)
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
                                mod.PAB_DeleteCustomBuffBar(bar.id)
                                if pabSel and pabSel.kind == "buff" and pabSel.id == bar.id then
                                    pabSel = { kind = "buff", id = "default" }
                                end
                                Apply(true, bar.id)
                                CludesUI:RefreshPage(true)
                            end,
                        })
                    end,
                })
        end
        FinishSection(buffSec, tileY, L("Add Buff Bar"), function(self)
            ShowAddBarPopup(self, "buff", fontFile)
        end)
    end

    -- Debuff bars section (bottom half): fixed "Debuffs" default bar first
    -- (hidden while Use Blizzard Buffs owns the display), then custom.
    do
        local sidebarChild = debuffChild -- section-scoped: this half's scroll child
        local tileY = 0

        local sPAB2 = sPABTop
        local defDebuffCfg = sPAB2 and mod.PAB_DefaultDebuffsCfg and mod.PAB_DefaultDebuffsCfg(sPAB2) or nil
        if showDefaults then
            tileY = tileY
                - BuildTile(sidebarChild, tileY, {
                    width = sidebarW,
                    fontPath = fontFile,
                    title = L("Debuffs"),
                    subtitle = L("Default"),
                    selected = (
                        pabSel
                        and pabSel.kind == "debuff"
                        and pabSel.id == "default"
                        and not pabInhSel
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
                        pabSel = { kind = "debuff", id = "default" }
                        pabInhSel = nil
                        CludesUI:RefreshPage(true)
                    end,
                })
        end

        tileY = BuildInheritedBarTiles(sidebarChild, tileY, false)
        for idx = 1, #debuffBars do
            local bar = debuffBars[idx]
            tileY = tileY
                - BuildTile(sidebarChild, tileY, {
                    width = sidebarW,
                    fontPath = fontFile,
                    title = L(bar.name or "Debuff Bar"),
                    subtitleFn = function()
                        return BuildDebuffBarSubtitle(bar)
                    end,
                    selected = (pabSel and pabSel.kind == "debuff" and pabSel.id == bar.id and not pabInhSel)
                            and true
                        or false,
                    enabled = bar.enabled and true or false,
                    showToggle = true,
                    onSelect = function()
                        pabSel = { kind = "debuff", id = bar.id }
                        pabInhSel = nil
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
                                local nb = mod.PAB_CopyCustomBar and mod.PAB_CopyCustomBar(false, bar, key)
                                if nb then
                                    Apply(false, nb.id)
                                    CludesUI:RefreshPage(true)
                                end
                            end,
                        })
                    end,
                    onToggle = function(val)
                        bar.enabled = val and true or false
                        Apply(false, bar.id)
                        CludesUI:RefreshPage(true)
                    end,
                    onEdit = function()
                        CludesUI:ShowInputPopup({
                            title = L("Rename Bar"),
                            placeholder = L(bar.name or "Debuff Bar"),
                            confirmText = L("Rename"),
                            cancelText = L("Cancel"),
                            onConfirm = function(textValue)
                                if textValue and textValue ~= "" then
                                    bar.name = textValue
                                    -- Re-registers this bar's Unlock Mode label from
                                    -- the new bar.name (RegisterPABCustomUnlock reads
                                    -- it live, but only ever re-runs from here) --
                                    -- without this, Unlock Mode kept showing the old
                                    -- name until the next /reload.
                                    Apply(false, bar.id)
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
                                mod.PAB_DeleteCustomDebuffBar(bar.id)
                                if pabSel and pabSel.kind == "debuff" and pabSel.id == bar.id then
                                    pabSel = { kind = "debuff", id = "default" }
                                end
                                Apply(false, bar.id)
                                CludesUI:RefreshPage(true)
                            end,
                        })
                    end,
                })
        end
        FinishSection(debuffSec, tileY, L("Add Debuff Bar"), function(self)
            ShowAddBarPopup(self, "debuff", fontFile)
        end)
    end

    local detail = CreateFrame("Frame", nil, root)
    detail:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
    detail:SetSize(leftW, visibleH)
    detail:SetFrameLevel(root:GetFrameLevel() + 1)

    if pabInhSel and pabInhBar then
        -- Read-only pane for an INHERITED group bar: where it lives, a jump
        -- link to the owning group, and a pointer at the tile toggle for the
        -- per-spec enable. No settings render -- edits belong to the group.
        local ginfo = SPEC_GROUP_INFO[pabInhSel.group]
        local gname = ginfo and L(ginfo.name) or pabInhSel.group
        local title = detail:CreateFontString(nil, "OVERLAY")
        title:SetFont(fontFile, 18, "")
        title:SetPoint("TOPLEFT", detail, "TOPLEFT", 25, -25)
        title:SetTextColor(0.55, 0.72, 1)
        title:SetText(pabInhBar.name or (pabInhSel.kind == "buff" and L("Buff Bar") or L("Debuff Bar")))
        local sub = detail:CreateFontString(nil, "OVERLAY")
        sub:SetFont(fontFile, 13, "")
        sub:SetPoint("LEFT", title, "RIGHT", 6, 0)
        sub:SetTextColor(0.75, 0.75, 0.75, 0.65)
        sub:SetText("(" .. CludesUI.Lf("Inherited from %1$s", gname) .. ")")
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
        local jumpKind, jumpGroup, jumpId = pabInhSel.kind, pabInhSel.group, pabInhSel.id
        itemLink:SetScript("OnClick", function()
            pabSpecSel = jumpGroup
            pabSel = { kind = jumpKind, id = jumpId }
            pabInhSel = nil
            CludesUI:RefreshPage(true)
        end)
    elseif pabSel then
        if pabSel.id == "default" then
            BuildDefaultBarDetail(detail, fontFile, pabSel.kind == "buff")
        elseif pabSel.kind == "buff" then
            local bar = mod.PAB_GetCustomBuffBar and mod.PAB_GetCustomBuffBar(pabSel.id)
            if bar then
                BuildBuffBarDetail(detail, fontFile, bar)
            end
        else
            local bar = mod.PAB_GetCustomDebuffBar and mod.PAB_GetCustomDebuffBar(pabSel.id)
            if bar then
                BuildDebuffBarDetail(detail, fontFile, bar)
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
