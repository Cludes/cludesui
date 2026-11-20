if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_PlayerAuraBars_Config.lua
--
--  Grid sizing, the default bar configs, seeding and migration from the
--  legacy sources and the per-bar enable state.
--  Reads the earlier Player Aura Bars files through ns and ns._pabInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._pabInternals
-- CludesUIUnitFrames_PlayerAuraBars.lua or an earlier Player Aura Bars
-- file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local PAB, PAB_FxListView, PAB_FxSafeToForce = Inner.PAB, Inner.PAB_FxListView, Inner.PAB_FxSafeToForce
local PAB_FxWantsCategory, PabShapedSize = Inner.PAB_FxWantsCategory, Inner.PabShapedSize
local PabSnap, VisibleCandidateClasses = Inner.PabSnap, Inner.VisibleCandidateClasses
local VisibleTokenClasses = Inner.VisibleTokenClasses

-- Grid sizing. AK's flow layout only exposes a row WIDTH (pixels) to wrap on, no
-- native "max lines" cap, so a row cap is enforced indirectly by capping
-- maxFrameCount to rows*cols; the anchor frame's footprint is our own bounding-box
-- estimate from the same three numbers, not something AK reports back.
--
-- Settings: maxTotal (overall cap), iconsPerRow (columns), maxRows. Effective cap =
-- min(maxTotal, maxRows * iconsPerRow) -- e.g. maxTotal=10 on a 5x5 grid still shows
-- at most 10, using 2 rows. iconsPerRow/maxRows/maxTotal fallbacks are
-- isBuff-conditional (11x3=32 buffs, 8x2=16 debuffs), reached only when a bar doesn't
-- set these itself (the two default bars); every custom bar sets all three explicitly
-- (PAB_AddCustomBuffBar/DebuffBar, 8x1=8 for both).
--
-- width/height: N icons need (N-1) gaps, not N -- `cols * (iconSize + pad)` bakes in
-- one extra trailing pad, making the box a few px bigger than its icons. This sizes
-- the LIVE bar's parent frame and the preview box (RenderPreviewIcons/
-- PAB_BuildPreviewBox); the CENTER-anchor recompensation math assumes it's accurate.
-- Because an Icon Effects Size override renders one category's icons bigger via a
-- separate sized style variant (EnsurePabSizedStyle) without growing the frame, the
-- box is sized for the LARGEST icon that could ever appear. An exact footprint is
-- impossible ahead of time -- a FLOW layout mixing per-group icon sizes is
-- data-dependent -- so this follows the same static worst-case capacity reservation
-- spirit maxTotal/rows*cols already use.
local function MaxIconSizeFor(isBuff, conf)
    local size = conf.iconSize or 32
    if not isBuff and conf.fxList then
        local entries = PAB_FxListView(conf.fxList)
        if entries then
            for index = 1, #entries do
                local sz = tonumber(entries[index].size)
                if sz and sz > size then
                    size = sz
                end
            end
        end
    end
    -- Snap to the physical pixel grid (same reasoning as ApplyGroupConfig's gap/rowGap
    -- snap): a raw iconSize also feeds the container's cross-axis extent math
    -- (ComputeGrid) at a non-pixel-perfect UIParent scale. Shape-expand applied last so
    -- the bar frame's footprint (ComputeGrid) always matches the buttons' real size.
    -- Second value: the unsnapped size, for ComputeGrid's design extent.
    local shaped = PabShapedSize(size, conf.iconShape)
    return PabSnap(shaped), shaped
end

-- Engine-declared weapon-enchant slots (AuraContainerItemEnchantmentSlot:
-- main hand, off hand, ranged). Only the first two are reachable in current
-- retail content, but the engine declares all three, so anything reserving
-- space for them must tolerate three.
local ENCH_SLOT_COUNT = 3

local function ComputeGrid(isBuff, conf)
    local iconSize, rawIconSize = MaxIconSizeFor(isBuff, conf)
    local rawIconHeight = conf.iconShape == "cropped" and mod.PAB_CroppedHeight(rawIconSize, conf)
        or rawIconSize
    local iconHeight = conf.iconShape == "cropped" and PabSnap(rawIconHeight) or iconSize
    local pad = conf.padding or 5
    local rowGap = conf.rowSpacing or 12
    local layoutPad = PabSnap(pad)
    local layoutRowGap = PabSnap(rowGap)
    local cols = math.max(1, conf.iconsPerRow or (isBuff and 11 or 8))
    local rowList = math.max(1, conf.maxRows or (isBuff and 3 or 2))
    local configuredMax = conf.maxTotal or (isBuff and 32 or 16)
    local effectiveMax = math.min(configuredMax, rowList * cols)
    -- Actual rows needed for the effective cap, never more than the row limit
    local usedRows = math.min(rowList, math.max(1, math.ceil(effectiveMax / cols)))
    -- How many weapon-enchant slots may be DECLARED on this bar. A grid under
    -- three cells declares only what it can hold (main hand first), so the
    -- cells can never spill out of it. This is not a budget: an inactive slot
    -- reserves nothing, only a cell that actually shows costs one (BuffAuraMax).
    local enchSlots = 0
    if isBuff and mod.PAB_EnchantsOn(conf) then
        enchSlots = math.min(ENCH_SLOT_COUNT, effectiveMax)
    end
    -- `lineExtent` is the icons' own extent on the line axis (iconsPerRow
    -- icons of iconSize + gaps); `crossExtent` is the other axis (lines actually used).
    -- Horizontal growth: a "line" is a row, so lineExtent -> width. Vertical growth
    -- modes: a "line" is a column, so lineExtent -> height -- see
    -- CornerFor/BuildContainerSpec for the matching growthH/growthV swap.
    local vertical = (
        conf.growDirection == "UP"
        or conf.growDirection == "DOWN"
        or conf.growDirection == "CENTER_VERTICAL"
    )
    local primarySize = vertical and iconHeight or iconSize
    local crossSize = vertical and iconSize or iconHeight
    local lineExtent = cols * primarySize + (cols - 1) * layoutPad
    -- Wrap budget handed to the engine. At POSITIVE spacing the engine reserves a
    -- TRAILING elementSpacing after every element (not only between), so a full
    -- line needs cols * (icon + spacing) or the last icon of every row wraps --
    -- field-confirmed twice, most recently 2026-08-14 (11-per-row wrapped at 10
    -- without the trailing pad). At NEGATIVE spacing that same trailing reserve
    -- makes the final icon wrap EARLY, so the budget adds nothing there.
    -- lineExtent still sizes the bar's own frame either way, so the drag box
    -- measures the icons, not the phantom trailing gap.
    local rowWidth = math.max(primarySize, lineExtent) + math.max(0, layoutPad)
    local crossExtent = usedRows * crossSize + (usedRows - 1) * layoutRowGap
    local width = vertical and crossExtent or lineExtent
    local height = vertical and lineExtent or crossExtent
    -- Reference boxes for stored positions (see BarAnchorOffset): the design extent
    -- from the raw config numbers, identical at every resolution, and the legacy
    -- extent the pre-fix PP.Scale truncation produced at this resolution.
    local Pix = CludesUI.PP
    local legacyIcon, legacyPad, legacyRowGap = Pix.Scale(rawIconSize), Pix.Scale(pad), Pix.Scale(rowGap)
    local legacyHeight = conf.iconShape == "cropped" and Pix.Scale(rawIconHeight) or legacyIcon
    local designLine = cols * (vertical and rawIconHeight or rawIconSize) + (cols - 1) * pad
    local designCross = usedRows * (vertical and rawIconSize or rawIconHeight) + (usedRows - 1) * rowGap
    local legacyLine = cols * (vertical and legacyHeight or legacyIcon) + (cols - 1) * legacyPad
    local legacyCross = usedRows * (vertical and legacyIcon or legacyHeight) + (usedRows - 1) * legacyRowGap
    return {
        -- The bar's WHOLE icon budget (Max Icons), weapon-enchant cells
        -- included -- BuffAuraMax takes the showing ones off it.
        effectiveMax = effectiveMax,
        enchSlots = enchSlots,
        rowWidth = rowWidth,
        width = width,
        height = height,
        designWidth = vertical and designCross or designLine,
        designHeight = vertical and designLine or designCross,
        legacyWidth = vertical and legacyCross or legacyLine,
        legacyHeight = vertical and legacyLine or legacyCross,
        rowGap = rowGap,
    }
end

-- Lazily creates and returns the default bars' per-polarity cfg sub-tables: same
-- shape as a custom bar object's shared+category fields, so
-- BuildStyle/ComputeGrid/ClassEnabled cannot tell the two apart.
local function DefaultBuffsCfg(cfg)
    cfg.defaultBuffs = cfg.defaultBuffs or {}
    return cfg.defaultBuffs
end
local function DefaultDebuffsCfg(cfg)
    cfg.defaultDebuffs = cfg.defaultDebuffs or {}
    return cfg.defaultDebuffs
end
mod.PAB_DefaultBuffsCfg = DefaultBuffsCfg
mod.PAB_DefaultDebuffsCfg = DefaultDebuffsCfg

-- Weapon enchants ride the default Buffs bar whenever one of its broad-content
-- modes (All Buffs or Has Duration) is on: oils and imbues are not auras, so
-- the catch-all group cannot admit them and the engine's item-enchantment
-- source stands in for it. No opt-in of their own -- the old "Weapon
-- Enchants" Filters row only existed while they had to be drawn by hand --
-- and custom buff bars never carry them.
function mod.PAB_EnchantsOn(conf)
    if not conf or (conf.showAllBuffs == false and conf.hasDuration ~= true) then
        return false
    end
    local pabCfg = PAB()
    return pabCfg ~= nil and pabCfg.defaultBuffs == conf
end

-- Default Buffs bar display name. Returns the RAW English key: unlock mode
-- stores element labels untranslated (CUI_UnlockMode.lua's GetBarLabel hands
-- back elem.label verbatim), and the options page wraps the result in L()
-- itself. One definition for both callers.
function mod.PAB_DefaultBuffsName(conf)
    return "Buffs"
end

-- One-time seed of the default Buffs/Debuffs bars' position/size/grid from Blizzard's
-- EditMode Buff/Debuff frame setup, so a first-time PAB user doesn't lose an
-- already-customized Blizzard layout. Guarded by s.pabEditModeSeeded, deliberately NOT
-- a nil-check on s.buffsPos/s.defaultBuffs: Buffs/Debuffs bars already exist for every
-- current user, so a nil-check would treat "never manually moved" as "brand new
-- profile" and silently reposition/resize existing bars.
--
-- Reads live BuffFrame/DebuffFrame state rather than C_EditMode.GetLayouts(): that
-- table is not reliably indexable by `activeLayout` (the pairs-key holding the active
-- layout's data did not match activeLayout's number, no other field to match on).
-- Blizzard has already resolved and applied the active layout onto these two frames by
-- the time addons run, so reading their live AuraContainer fields sidesteps the lookup.
--
-- Field mapping: AuraContainer.iconPadding -> padding (direct pixels).
-- AuraContainer.iconScale (observed 0.5-2.0, Blizzard's 50%-200% slider) -> iconSize =
-- round(32 * scale); assumes Blizzard's 100% matches PAB's 32px default (an
-- approximation, low risk, user can readjust). AuraContainer.iconStride -> iconsPerRow
-- (NOT maxTotal: "stride" = icons per row before wrapping, exact-matched against
-- Blizzard's IconLimitBuffFrame/DebuffFrame setting; no Blizzard equivalent for a true
-- total cap exists, so maxTotal stays unmigrated at PAB's own default).
-- AuraContainer.isHorizontal + .addIconsToRight/.addIconsToTop -> growDirection +
-- iconWrapDirection (the vertical-orientation branch is inferred from PAB's own
-- cross-axis convention, ToGrowthH/CornerFor above, NOT tested -- verification only
-- covered a horizontal Blizzard layout). frame:GetLeft()/GetTop() minus UIParent's own
-- -> buffsPos/debuffsPos, stored as a TOPLEFT-relative-to-UIParent offset --
-- deliberately NOT GetPoint()'s raw relativeTo, since PAB always anchors to UIParent
-- (ApplyBarPosition) while Blizzard's anchor can chain to an arbitrary frame (observed:
-- Buffs relativeTo="DebuffFrame"); absolute screen coordinates sidestep that chain.
local function SeedBarFromEditMode(widget, conf, posKey, cfg, isBuff)
    if not (widget and widget.AuraContainer) then
        return
    end
    local ac = widget.AuraContainer

    local uiLeft, uiTop = UIParent:GetLeft(), UIParent:GetTop()
    local leftX, topY = widget:GetLeft(), widget:GetTop()
    if uiLeft and uiTop and leftX and topY then
        cfg[posKey] = { point = "TOPLEFT", relPoint = "TOPLEFT", x = leftX - uiLeft, y = topY - uiTop }
    end

    if ac.iconPadding then
        conf.padding = ac.iconPadding
    end
    if ac.iconScale then
        conf.iconSize = math.floor(32 * ac.iconScale + 0.5)
    end
    if ac.iconStride then
        conf.iconsPerRow = ac.iconStride
        -- Keep the full icon cap reachable when the migrated row width is narrower
        -- than PAB's default (Blizzard stride=7 vs fallback iconsPerRow=11):
        -- ComputeGrid caps at min(maxTotal, maxRows*iconsPerRow) and maxTotal is NOT
        -- migrated, so maxRows must grow or a narrower stride silently shows fewer
        -- icons than the un-migrated default did. cap matches ComputeGrid's own
        -- isBuff-conditional maxTotal fallback (32/16) exactly.
        local cap = isBuff and 32 or 16
        conf.maxRows = math.max(1, math.ceil(cap / ac.iconStride))
    end

    if ac.isHorizontal ~= nil then
        if ac.isHorizontal then
            conf.growDirection = ac.addIconsToRight and "RIGHT" or "LEFT"
        else
            conf.growDirection = ac.addIconsToTop and "UP" or "DOWN"
            conf.iconWrapDirection = ac.addIconsToRight and "RIGHT" or "LEFT"
        end
    end
end

-- Migrates the retired Styled Player Auras module (db.profile.playerAuras). That
-- module never controlled position/size/grid (Blizzard drove layout via Edit Mode),
-- so nothing here duplicates SeedBarFromEditMode above; it DID apply border/font
-- styling as ONE shared flat cfg table, not split per polarity. Gated on the old
-- module's own `enabled` flag: only migrate if it was actually on. Field mapping:
-- borderSize/borderR/G/B/A -> same field name on BOTH buffCfg and debuffCfg (one
-- shared old value, not two). showText -> durationShow, both bars (same nil/true =
-- shown). textSize -> BOTH durationTextSize AND stackTextSize on both bars: the old
-- SkinAuraButton sized duration AND stack-count font strings from cfg.textSize, NOT
-- the duration-only/stack-only split the old External Defensives module uses.
-- noBorderDebuffs -> debuffCfg.borderSize = 0 (debuffs-only override, applied after
-- the shared borderSize above). Border texture/offset/layer fields now map directly;
-- durationFormat remains unsupported. Old buffIconZoom/debuffIconZoom are skipped --
-- PAB has its own per-bar iconZoom.
local function MigratePlayerAuraStyle(buffCfg, debuffCfg)
    local old = mod.db and mod.db.profile and mod.db.profile.playerAuras
    if not (old and old.enabled) then
        return
    end

    for _, conf in ipairs({ buffCfg, debuffCfg }) do
        if old.borderSize then
            conf.borderSize = old.borderSize
        end
        if old.borderR then
            conf.borderR = old.borderR
        end
        if old.borderG then
            conf.borderG = old.borderG
        end
        if old.borderB then
            conf.borderB = old.borderB
        end
        if old.borderA then
            conf.borderA = old.borderA
        end
        if old.borderTexture then
            conf.borderTexture = old.borderTexture
        end
        if old.borderTextureOffset ~= nil then
            conf.borderTextureOffset = old.borderTextureOffset
        end
        if old.borderTextureOffsetY ~= nil then
            conf.borderTextureOffsetY = old.borderTextureOffsetY
        end
        if old.borderTextureShiftX ~= nil then
            conf.borderTextureShiftX = old.borderTextureShiftX
        end
        if old.borderTextureShiftY ~= nil then
            conf.borderTextureShiftY = old.borderTextureShiftY
        end
        if old.borderBehind ~= nil then
            conf.borderBehind = old.borderBehind
        end
        if old.showText ~= nil then
            conf.durationShow = old.showText
        end
        if old.textSize then
            conf.durationTextSize = old.textSize
            conf.stackTextSize = old.textSize
        end
    end

    if old.noBorderDebuffs then
        debuffCfg.borderSize = 0
    end
end

-- One-shot filter-model upgrade (v2, per profile): debuff bars moved to the unified
-- All Debuffs + filters dropdown, where checked classes SUBTRACT while Show All is on.
-- Stale add-mode selections that Show All used to bypass would suddenly subtract
-- content -- clear them once on every Show All debuff bar; add-mode bars keep theirs.
local function EnsureDebuffFilterV2(s)
    if s.pabDebuffFiltersV2 then
        return
    end
    s.pabDebuffFiltersV2 = true
    local skinData = s.defaultDebuffs
    if skinData and skinData.showAllDebuffs ~= false then
        skinData.classFilters = nil
    end
    if s.customDebuffBars then
        for index = 1, #s.customDebuffBars do
            local barFrame = s.customDebuffBars[index]
            if barFrame.showAllDebuffs ~= false then
                barFrame.classFilters = nil
            end
        end
    end
end

-- One-shot lane split (per profile): the filter dropdowns became two-lane (show/hide),
-- so the single mode-dependent selection splits into cfg.filters/classFilters (SHOW)
-- and cfg.negFilters/negClassFilters (HIDE). A broad-mode bar's checked entries were
-- subtracting -- move them to the hide lane so rendering is bit-identical; add-mode
-- selections already mean SHOW and stay put. Runs after EnsureDebuffFilterV2.
local function EnsureFilterLanes(s)
    if s.pabFilterLanesV1 then
        return
    end
    s.pabFilterLanesV1 = true
    local function SplitBuff(barFrame)
        if not barFrame then
            return
        end
        if (barFrame.showAllBuffs ~= false or barFrame.hasDuration == true) and barFrame.filters and next(barFrame.filters) then
            barFrame.negFilters = barFrame.filters
            barFrame.filters = nil
        end
    end
    local function SplitDebuff(barFrame)
        if not barFrame then
            return
        end
        if barFrame.showAllDebuffs ~= false and barFrame.classFilters and next(barFrame.classFilters) then
            barFrame.negClassFilters = barFrame.classFilters
            barFrame.classFilters = nil
        end
    end
    SplitBuff(s.defaultBuffs)
    if s.customBuffBars then
        for index = 1, #s.customBuffBars do
            SplitBuff(s.customBuffBars[index])
        end
    end
    SplitDebuff(s.defaultDebuffs)
    if s.customDebuffBars then
        for index = 1, #s.customDebuffBars do
            SplitDebuff(s.customDebuffBars[index])
        end
    end
end
mod.PAB_EnsureFilterLanes = EnsureFilterLanes

-- Content-source tests for the no-empty-selection rule: a bar always keeps at
-- least one content source (a broad mode, a Show-lane filter, an Extra
-- Spell). The hide lane is not a content source, and weapon enchants ride the
-- broad modes (ns.PAB_EnchantsOn) rather than counting as one. Shared by the
-- enable migration below and the options dropdowns' guards.
local function BuffBarHasContent(barFrame, isDefault)
    if barFrame.showAllBuffs ~= false or barFrame.hasDuration == true then
        return true
    end
    if barFrame.filters and next(barFrame.filters) then
        return true
    end
    if barFrame.spells and #barFrame.spells > 0 then
        return true
    end
    return false
end
-- Debuff content besides the All Debuffs mode: Show-lane classes, or an Icon
-- Effects block forcing a safe class on ("as if that Base Filter were on" --
-- the chain builders' fx wrapper renders those categories even in add mode, so
-- an fx-only bar is NOT empty).
local function DebuffBarOtherContent(barFrame)
    if barFrame.classFilters and next(barFrame.classFilters) then
        return true
    end
    if barFrame.fxList then
        local function AnyForced(entries)
            if not entries then
                return false
            end
            for index = 1, #entries do
                local class = entries[index]
                if PAB_FxSafeToForce(class) and PAB_FxWantsCategory(barFrame.fxList, class.key) then
                    return true
                end
            end
            return false
        end
        if AnyForced(VisibleTokenClasses()) or AnyForced(VisibleCandidateClasses()) then
            return true
        end
    end
    return false
end
local function DebuffBarHasContent(barFrame)
    if barFrame.showAllDebuffs ~= false or barFrame.hasDuration == true then
        return true
    end
    return DebuffBarOtherContent(barFrame)
end
mod.PAB_BuffBarHasContent = BuffBarHasContent
mod.PAB_DebuffBarOtherContent = DebuffBarOtherContent
mod.PAB_DebuffBarHasContent = DebuffBarHasContent

-- One-shot (per profile), HISTORICAL: written when the phase-2 no-empty rule
-- held (dropdown guards kept one content source alive). Those guards are gone
-- (2026-08-15): empty selections are legal again and the options page warns
-- loudly instead (red dropdown + bubble, AttachEmptyFilterWarn). The mapping
-- below still runs once for pre-phase-2 profiles: a LEGACY bar with no
-- content source rendered nothing, so it becomes All + disabled -- the same
-- nothing on screen, with sensible content on re-enable. Post-stamp empties
-- created through the dropdown are left exactly as the user set them. Runs
-- after EnsureFilterLanes (lanes must be split before emptiness is judged;
-- a broad-mode bar is never empty either way).
local function EnsureBarEnable(s)
    EnsureFilterLanes(s)
    -- One-shot: the "Weapon Enchants" opt-in is gone (the cells follow the
    -- broad-content modes, ns.PAB_EnchantsOn). An enchants-only bar had its
    -- grid pinned to 3x1x3 with the user's own grid stashed: put that back
    -- and turn All Buffs on, so the enchants it showed keep showing.
    if not s.pabEnchantsAutoV1 then
        s.pabEnchantsAutoV1 = true
        local skinData = s.defaultBuffs
        if skinData then
            local saved = skinData.enchGridSaved
            if saved then
                skinData.iconsPerRow, skinData.maxRows, skinData.maxTotal = saved.iconsPerRow, saved.maxRows, saved.maxTotal
                skinData.enchGridSaved = nil
                skinData.showAllBuffs = nil
            end
            skinData.showWeaponEnchants = nil
        end
    end
    if s.pabBarEnableV1 then
        return
    end
    s.pabBarEnableV1 = true
    local function MapBuff(barFrame, isDefault)
        if not barFrame then
            return
        end
        if barFrame.enabled ~= false and not BuffBarHasContent(barFrame, isDefault) then
            barFrame.showAllBuffs = nil -- All Buffs back on (nil = on)
            barFrame.enabled = false
        end
    end
    local function MapDebuff(barFrame)
        if not barFrame then
            return
        end
        if barFrame.enabled ~= false and not DebuffBarHasContent(barFrame) then
            barFrame.showAllDebuffs = nil
            barFrame.enabled = false
        end
    end
    MapBuff(s.defaultBuffs, true)
    if s.customBuffBars then
        for index = 1, #s.customBuffBars do
            MapBuff(s.customBuffBars[index], false)
        end
    end
    MapDebuff(s.defaultDebuffs)
    if s.customDebuffBars then
        for index = 1, #s.customDebuffBars do
            MapDebuff(s.customDebuffBars[index])
        end
    end
end
mod.PAB_EnsureBarEnable = EnsureBarEnable

local function SeedDefaultBuffsDebuffsFromLegacySources(cfg)
    if cfg.pabEditModeSeeded then
        return
    end
    cfg.pabEditModeSeeded = true -- set first: never retry even if a read below errors/fails partway
    local buffCfg, debuffCfg = DefaultBuffsCfg(cfg), DefaultDebuffsCfg(cfg)
    SeedBarFromEditMode(BuffFrame, buffCfg, "buffsPos", cfg, true)
    SeedBarFromEditMode(DebuffFrame, debuffCfg, "debuffsPos", cfg, false)
    MigratePlayerAuraStyle(buffCfg, debuffCfg)
end

-- One-shot: the External Defensives bar is a normal custom buff bar carrying the
-- imported "Externals" preset filter (curated external-defensive spell list;
-- PAB_ImportBM2Filters must have run already -- see CreateBars' call order), so it
-- needs zero bespoke machinery. Seeded once per profile, disabled by default like the
-- built-in it replaced. Sources, newest first: the retired built-in bar's saved cfg
-- (s.defaultExternalDefensives), else the pre-PAB standalone module's table
-- (growDirection was lowercase there; showText -> durationShow; textSize styled the
-- stack/application-count text -> stackTextSize), else plain disabled defaults. The
-- retired position slots (s.extDefPos / the legacy module's unlockPos) become the
-- bar's own pos.
local function EnsureExtDefCustomBar(s)
    if s.pabExtDefSeeded == 2 then
        return
    end
    local extId
    do
        local entries = mod.PAB_Filters and mod.PAB_Filters()
        if entries then
            for index = 1, #entries do
                if entries[index].preset and entries[index].name == "Externals" then
                    extId = entries[index].id
                    break
                end
            end
        end
    end
    -- v1 of this seed gave the bar a bespoke extDefFilter pseudo-filter (since
    -- removed); convert those bars in place to the preset filter.
    if s.pabExtDefSeeded then
        s.pabExtDefSeeded = 2
        local barList = s.customBuffBars
        if barList and extId then
            for index = 1, #barList do
                local b = barList[index]
                if b.extDefFilter then
                    b.extDefFilter = nil
                    b.showAllBuffs = false
                    b.filters = { [extId] = true }
                end
            end
        end
        return
    end
    s.pabExtDefSeeded = 2
    local source = s.defaultExternalDefensives
    local legacy = mod.db and mod.db.profile and mod.db.profile.externalDefensives
    local from = source or legacy
    s.nextBarId = (s.nextBarId or 1)
    local barFrame = {
        id = s.nextBarId,
        name = "External Defensives",
        enabled = false,
        showAllBuffs = false,
        filters = extId and { [extId] = true } or {},
        spells = {},
        ownOnlySpells = {},
        growDirection = "LEFT",
        iconsPerRow = 4,
        maxRows = 1,
        maxTotal = 4,
        durationPosition = "CENTER",
    }
    s.nextBarId = s.nextBarId + 1
    if from then
        if from.enabled ~= nil then
            barFrame.enabled = from.enabled == true
        end
        if from.iconSize then
            barFrame.iconSize = from.iconSize
        end
        if from.growDirection then
            barFrame.growDirection = string.upper(from.growDirection)
        end
        if from.durationShow ~= nil then
            barFrame.durationShow = from.durationShow
        elseif from.showText ~= nil then
            barFrame.durationShow = from.showText
        end
        if from.stackTextSize then
            barFrame.stackTextSize = from.stackTextSize
        elseif from.textSize then
            barFrame.stackTextSize = from.textSize
        end
        if from.durationPosition then
            barFrame.durationPosition = from.durationPosition
        end
        if from.durationTextSize then
            barFrame.durationTextSize = from.durationTextSize
        end
        if from.durationOffsetX then
            barFrame.durationOffsetX = from.durationOffsetX
        end
        if from.durationOffsetY then
            barFrame.durationOffsetY = from.durationOffsetY
        end
        if from.durationColorR then
            barFrame.durationColorR, barFrame.durationColorG, barFrame.durationColorB =
                from.durationColorR, from.durationColorG, from.durationColorB
        end
        if from.stackShow ~= nil then
            barFrame.stackShow = from.stackShow
        end
        if from.stackPosition then
            barFrame.stackPosition = from.stackPosition
        end
        if from.stackOffsetX then
            barFrame.stackOffsetX = from.stackOffsetX
        end
        if from.stackOffsetY then
            barFrame.stackOffsetY = from.stackOffsetY
        end
        if from.stackColorR then
            barFrame.stackColorR, barFrame.stackColorG, barFrame.stackColorB =
                from.stackColorR, from.stackColorG, from.stackColorB
        end
        if from.iconsPerRow then
            barFrame.iconsPerRow = from.iconsPerRow
        end
        if from.maxRows then
            barFrame.maxRows = from.maxRows
        end
        if from.maxTotal then
            barFrame.maxTotal = from.maxTotal
        end
        if from.padding then
            barFrame.padding = from.padding
        end
        if from.rowSpacing then
            barFrame.rowSpacing = from.rowSpacing
        end
        if from.iconZoom then
            barFrame.iconZoom = from.iconZoom
        end
        if from.showSwipe ~= nil then
            barFrame.showSwipe = from.showSwipe
        end
        if from.reverseSwipe ~= nil then
            barFrame.reverseSwipe = from.reverseSwipe
        end
        if from.fontOutline then
            barFrame.fontOutline = from.fontOutline
        end
        if from.sortMethod then
            barFrame.sortMethod = from.sortMethod
        end
        if from.sortDirection then
            barFrame.sortDirection = from.sortDirection
        end
        if from.borderSize then
            barFrame.borderSize = from.borderSize
        end
        if from.borderR then
            barFrame.borderR, barFrame.borderG, barFrame.borderB, barFrame.borderA =
                from.borderR, from.borderG, from.borderB, from.borderA
        end
        if from.borderTexture then
            barFrame.borderTexture = from.borderTexture
        end
        if from.borderTextureOffset ~= nil then
            barFrame.borderTextureOffset = from.borderTextureOffset
        end
        if from.borderTextureOffsetY ~= nil then
            barFrame.borderTextureOffsetY = from.borderTextureOffsetY
        end
        if from.borderTextureShiftX ~= nil then
            barFrame.borderTextureShiftX = from.borderTextureShiftX
        end
        if from.borderTextureShiftY ~= nil then
            barFrame.borderTextureShiftY = from.borderTextureShiftY
        end
        if from.borderBehind ~= nil then
            barFrame.borderBehind = from.borderBehind
        end
    end
    local place = s.extDefPos or (legacy and legacy.unlockPos)
    if place and place.point then
        barFrame.pos = { point = place.point, relPoint = place.relPoint or place.point, x = place.x, y = place.y }
    end
    s.customBuffBars = s.customBuffBars or {}
    s.customBuffBars[#s.customBuffBars + 1] = barFrame
    -- Retire the built-in bar's storage for good.
    s.defaultExternalDefensives = nil
    s.extDefPos = nil
end

Inner.BuffBarHasContent, Inner.ComputeGrid = BuffBarHasContent, ComputeGrid
Inner.DefaultBuffsCfg, Inner.DefaultDebuffsCfg = DefaultBuffsCfg, DefaultDebuffsCfg
Inner.EnsureBarEnable, Inner.EnsureDebuffFilterV2 = EnsureBarEnable, EnsureDebuffFilterV2
Inner.EnsureExtDefCustomBar, Inner.EnsureFilterLanes = EnsureExtDefCustomBar, EnsureFilterLanes
Inner.SeedDefaultBuffsDebuffsFromLegacySources = SeedDefaultBuffsDebuffsFromLegacySources
Inner.broken = false
