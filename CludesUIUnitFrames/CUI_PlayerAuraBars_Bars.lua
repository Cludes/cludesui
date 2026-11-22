if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CUI_PlayerAuraBars_Bars.lua
--
--  The default Buffs and Debuffs bars: their state, the restricted-apply
--  deferral, growth and position, CreateBars, the unlock registration,
--  RestyleBars and ApplyLiveConfig.
--  Reads the earlier Player Aura Bars files through ns and ns._pabInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._pabInternals
-- CludesUIUnitFrames_PlayerAuraBars.lua or an earlier Player Aura Bars
-- file failed to load.
if not Inner or Inner.broken then return end
Inner.broken = true

local BuffBarChain, PAB, PabSnap = Inner.BuffBarChain, Inner.PAB, Inner.PabSnap
local BuffCandidateExtras, BuildStyle = Inner.BuffCandidateExtras, Inner.BuildStyle
local DebuffCandidateExtras = Inner.DebuffCandidateExtras
local ResolveSortDirection, ResolveSortMethod = Inner.ResolveSortDirection, Inner.ResolveSortMethod
local STYLE_BUFFS, STYLE_DEBUFFS = Inner.STYLE_BUFFS, Inner.STYLE_DEBUFFS
local ApplyGroupConfig, BuildGroupLayout = Inner.ApplyGroupConfig, Inner.BuildGroupLayout
local DebuffChainFor, MergeCandidateFilters = Inner.DebuffChainFor, Inner.MergeCandidateFilters
local RetireContainer, ComputeGrid = Inner.RetireContainer, Inner.ComputeGrid
local DefaultBuffsCfg, DefaultDebuffsCfg = Inner.DefaultBuffsCfg, Inner.DefaultDebuffsCfg
local EnsureBarEnable, EnsureDebuffFilterV2 = Inner.EnsureBarEnable, Inner.EnsureDebuffFilterV2
local EnsureExtDefCustomBar, EnsureFilterLanes = Inner.EnsureExtDefCustomBar, Inner.EnsureFilterLanes
local SeedDefaultBuffsDebuffsFromLegacySources = Inner.SeedDefaultBuffsDebuffsFromLegacySources
local SetAK, SetBuffsParent, SetDebuffsParent = Inner.SetAK, Inner.SetBuffsParent, Inner.SetDebuffsParent
local SetBuffsSlotSig, SetBuffsContainer = Inner.SetBuffsSlotSig, Inner.SetBuffsContainer
local SetDebuffsContainer = Inner.SetDebuffsContainer

local AK -- CludesUI.AuraKit, resolved at first use (see SetAK)
Inner.AKSetters[#Inner.AKSetters + 1] = function(val) AK = val end

local buffsContainer, debuffsContainer
Inner.buffsContainerSetters[#Inner.buffsContainerSetters + 1] = function(val) buffsContainer = val end
Inner.debuffsContainerSetters[#Inner.debuffsContainerSetters + 1] = function(val) debuffsContainer = val end
local buffHost, debuffHost
Inner.buffsParentSetters[#Inner.buffsParentSetters + 1] = function(val) buffHost = val end
Inner.debuffsParentSetters[#Inner.debuffsParentSetters + 1] = function(val) debuffHost = val end
-- Per-container, per-polarity registry of every group key ever declared (see
-- ApplyGroupConfig): reset only when a container is (re-)created, never on a live
-- settings change.
local declaredSet = { buffs = {}, debuffs = {} } -- buffs: only the "Show All Buffs" catch-all key ("all"); debuffs: every class-token chain key
local lastSize = { buffs = nil, debuffs = nil } -- {w=,h=} last-applied grid size, for fixed-edge compensation (see ApplyLiveConfig)
local buffsSlotSig -- signature of the default Buffs bar's last-applied resolved spell list (ns.PAB_ResolveSpells), mirrors customBuffSig[barId] for the per-bar slots model
Inner.buffsSlotSigSetters[#Inner.buffsSlotSigSetters + 1] = function(val) buffsSlotSig = val end
local RegisterPABUnlock -- forward-declared; defined after CreateBars, called from it
local SyncCancelCVar -- forward-declared; defined after RestyleBars, called from CreateBars/RestyleBars/ReloadCustomBuffBarImpl
local pabSuppressed = false -- vehicle ride OR degraded-filter window: SetParentShownSafe dims the parents instead of hiding them (see ApplyVehicleHidden)
Inner.pabSuppressedSetters[#Inner.pabSuppressedSetters + 1] = function(val) pabSuppressed = val end
-- Last label the Buffs mover was registered under, so ApplyLiveConfig can
-- re-register on a name change without doing it on every slider drag.
local lastUnlockBuffLabel
local ReloadAllCustomBars -- forward-declared; assigned by CUI_PlayerAuraBars_CustomBars.lua (SetReloadAllCustomBars), called from CreateBars
Inner.reloadAllSetters[#Inner.reloadAllSetters + 1] = function(val) ReloadAllCustomBars = val end
local PAB_MaybeRefreshPreview -- forward-declared; assigned by CUI_PlayerAuraBars_Preview.lua (SetMaybeRefreshPreview), called from every live-apply function so an open bar-detail preview box tracks slider drags without those functions knowing it exists
Inner.previewRefreshSetters[#Inner.previewRefreshSetters + 1] = function(val) PAB_MaybeRefreshPreview = val end

-- Last-applied growDirection per live container (weak keys); written by
-- ApplyContainerAnchorAndGrowth, read by the restricted-apply gate below.
local containerDirections = setmetatable({}, { __mode = "k" })

local restrictedApplies = {}
local restrictionHooked = false
-- Defers ONLY the direction-change reconfigure (Hide/SetUnit/UpdateAllAuras +
-- resize) to the restriction lift. Ordinary container-level re-drives are
-- restriction-legal (they ran mid-combat for weeks pre-centered-growth), and
-- the cinematic/faction/vehicle recovery lane DEPENDS on them running inside
-- instanced combat -- a blanket defer would leave restored bars showing
-- degraded content until the combat edge.
local function DeferRestrictedApply(gridKey, func, boxHolder, direction)
    local applied = boxHolder and containerDirections[boxHolder]
    if not (applied and applied ~= (direction or "LEFT")) then return false end
    if not AK then SetAK(CUI and CUI.AuraKit) end
    if not (AK and AK.AurasRestricted and AK.AurasRestricted()) then return false end
    restrictedApplies[gridKey] = func
    if not restrictionHooked then
        restrictionHooked = true
        AK.OnRestrictionLift(function()
            if not next(restrictedApplies) then return end
            local pending = restrictedApplies
            restrictedApplies = {}
            for _, apply in pairs(pending) do
                apply()
            end
        end)
    end
    return true
end

-- One-shot OOC reconciler for parent-geometry passes skipped inside lockdown. Every
-- bar parent has the engine aura container ANCHORED to it, which makes the PARENT's
-- own SetSize/ClearAllPoints/SetPoint ADDON_ACTION_BLOCKED in combat (a protected
-- anchor-dependent poisons its anchor ancestor's geometry) -- while the cinematic/
-- faction/vehicle recovery lane legitimately re-drives config mid-combat. Keyed and
-- coalesced through the addon's shared ns.CombatQueue.
local function QueuePABRegenApply(gridKey, func) mod.CombatQueue.Defer("PAB:" .. gridKey, func) end

-- Combat-safe Show/Hide for a bar PARENT. The engine aura container is a
-- CHILD of the parent, so the parent's own Show/Hide is ADDON_ACTION_BLOCKED
-- in lockdown exactly like its SetSize/SetPoint (field report: the
-- cinematic/faction recovery lane re-asserting the default bars mid-combat).
-- No call at all when the state already matches; in combat the visual verdict
-- lands through alpha (never protected) and the real Show/Hide is replayed at
-- regen via `recompute`, which re-derives the verdict at that time.
-- Suppression (pabSuppressed) rides on alpha OUT of combat too, never on the
-- shown state: it lifts on transitions that routinely land mid-combat, and a
-- real Hide taken while suppressed cannot be undone until the next regen edge.
-- Field report (Kings' Rest, Entomb): the tomb is a vehicle and being inside it
-- drops the player's combat, so the ride's hide replayed for real at that regen
-- and the exit's show was blocked -- the bars stayed gone for the whole boss
-- pulled afterwards.
local function SetParentShownSafe(gridKey, hostFrame, wanted, recompute)
    wanted = wanted and true or false
    local locked = InCombatLockdown()
    local isShown = hostFrame:IsShown()
    if issecretvalue and issecretvalue(isShown) then isShown = nil end
    local alpha = (pabSuppressed or (locked and not wanted)) and 0 or 1
    if hostFrame:GetAlpha() ~= alpha then hostFrame:SetAlpha(alpha) end
    if isShown == wanted then return end
    if locked then
        QueuePABRegenApply("shown:" .. gridKey, recompute)
        return
    end
    hostFrame:SetShown(wanted)
end

-- Default-bar enable toggle (cfg.enabled, nil = enabled): the parent hides
-- exactly like a disabled custom bar's. Vehicle suppression still wins while
-- active -- SetParentShownSafe keeps it on alpha, so this pass carries the
-- enable verdict without un-suppressing anything (a bar built mid-ride used to
-- come up at full alpha here).
local function ApplyDefaultBarShown(buffSide)
    local pabCfg = PAB()
    if not pabCfg then return end
    local hostFrame
    if buffSide then
        hostFrame = buffHost
    else
        hostFrame = debuffHost
    end
    if not hostFrame then return end
    local conf = buffSide and DefaultBuffsCfg(pabCfg) or DefaultDebuffsCfg(pabCfg)
    -- Master enable + Use Blizzard Buffs both stand the defaults down (the
    -- recovery lane can reach this while disabled-awaiting-reload).
    SetParentShownSafe(
        buffSide and "default-buffs" or "default-debuffs",
        hostFrame,
        pabCfg.enabled == true and conf.enabled ~= false and pabCfg.useBlizzardBuffs ~= true,
        function() ApplyDefaultBarShown(buffSide) end
    )
end

-- Grow direction. AK.ApplyContainerLayout only applies growth when BOTH growthH and
-- growthV are set. Values are AnchorUtil.FlowDirection members, NOT strings
-- (Blizzard_SharedXMLBase/AnchorUtil.lua: Left=-1, Right=1, Up=1, Down=-1); our
-- settings store uppercase direction strings, matching CUI_UnlockMode.lua's dropdown
-- `val` convention.
--
-- CRITICAL: AnchorUtil.ApplyFlowLayout positions every element via
-- `layout:GetAnchorPoint()` (layout.anchorPoint, a THIRD independent field defaulting
-- to "TOPLEFT"), NOT our outer spec.point. Elements are placed relative to that
-- internal anchor with offsets increasing in the growthH direction, so leaving
-- anchorPoint at default while growthH changes puts the first icon on the wrong side
-- and lets icons drift outside the mover box. Derive ONE corner from the direction and
-- use it for BOTH the outer frame anchor and the internal flow anchorPoint, so the
-- fixed corner and the flow's start corner are the same physical point:
--   growDirection RIGHT -> fixed/start corner TOPLEFT (icons extend right)
--   growDirection LEFT  -> fixed/start corner TOPRIGHT (icons extend left)
--
-- Vertical growth (Up/Down): the flow's PRIMARY axis becomes vertical (icons fill
-- up/down first) and growthH instead carries the CROSS axis -- which side additional
-- columns wrap to, from cfg.iconWrapDirection ("LEFT"/"RIGHT", default LEFT). Mirrors
-- CUI_RaidFrames_AuraContainers.lua's AnchorDebuffContainer (grow==UP/DOWN: gH = wrap,
-- gV = grow), except PAB has no separate wrap dropdown. Horizontal growth keeps
-- growthH as the primary axis and growthV hardcoded Down (rows wrap downward).
local function ToGrowthH(growText, wrapText)
    local FlowDir = AnchorUtil and AnchorUtil.FlowDirection
    if not FlowDir then return nil end
    if growText == "CENTER_VERTICAL" then return FlowDir.Right end
    if growText == "UP" or growText == "DOWN" then
        return wrapText == "RIGHT" and FlowDir.Right or FlowDir.Left
    end
    return (growText == "RIGHT" or growText == "CENTER_HORIZONTAL") and FlowDir.Right or FlowDir.Left
end
-- Gated on the GROWTH direction, never on the wrap value itself (same shape as
-- ToGrowthH above). iconWrapDirection is one shared field whose Up/Down values are
-- only offered for LEFT/RIGHT growth, so a value left behind by a growth-direction
-- change must stay inert everywhere else: reading it unconditionally flipped
-- CENTER_VERTICAL's columns to grow Up out of its fixed "TOP" anchor, and stacked
-- CENTER_HORIZONTAL's rows upward, from a setting whose cog those modes never show.
local function ToGrowthV(growText, wrapText)
    local FlowDir = AnchorUtil and AnchorUtil.FlowDirection
    if not FlowDir then return nil end
    if growText == "UP" then return FlowDir.Up end
    if growText == "DOWN" then return FlowDir.Down end
    if growText == "LEFT" or growText == "RIGHT" then
        return wrapText == "UP" and FlowDir.Up or FlowDir.Down
    end
    return FlowDir.Down -- centered growth: rows always wrap downward
end
-- Corner = the flow's fixed start point = (opposite of growthV side) + (opposite of
-- growthH side), same rule horizontal or vertical (LEFT/RIGHT: growthV is always Down
-- -> TOP component; growthH Right/Left -> LEFT/RIGHT component).
local function CornerFor(growText, wrapText)
    if growText == "CENTER_VERTICAL" then return "TOP" end
    if growText == "UP" or growText == "DOWN" then
        local vSide = (growText == "UP") and "BOTTOM" or "TOP"
        local hSide = (wrapText == "RIGHT") and "LEFT" or "RIGHT"
        return vSide .. hSide
    end
    if growText == "LEFT" or growText == "RIGHT" then
        local vSide = (wrapText == "UP") and "BOTTOM" or "TOP"
        local hSide = (growText == "RIGHT") and "LEFT" or "RIGHT"
        return vSide .. hSide
    end
    return (growText == "CENTER_HORIZONTAL") and "TOPLEFT" or "TOPRIGHT"
end

-- Shared by every container, default and custom alike: builds the AK.RequestContainer
-- spec's point+layout from a bar cfg's growDirection and a precomputed grid
-- (ComputeGrid), so default and custom bars can never drift in how they read
-- growDirection/rowWidth. Also returns the corner (callers need it for the
-- container's own SetPoint against its parent) and `vertical` (AK.SetContainerAxis is
-- a separate call from AK.ApplyContainerLayout -- axis is not part of the layout table).
local function BuildContainerSpec(hostFrame, conf, gridFrame)
    local direction = conf.growDirection or "LEFT"
    local wrap = conf.iconWrapDirection or "LEFT"
    local vertical = (direction == "UP" or direction == "DOWN" or direction == "CENTER_VERTICAL")
    local layoutAnchor = direction == "CENTER_HORIZONTAL" and "LEFT" or CornerFor(direction, wrap)
    local containerAnchor = (direction == "CENTER_HORIZONTAL" or direction == "CENTER_VERTICAL") and "CENTER"
        or layoutAnchor
    return containerAnchor,
        {
            point = { containerAnchor, hostFrame, containerAnchor, 0, 0 },
            layout = {
                anchorPoint = layoutAnchor,
                padding = { 0, 0, 0, 0 },
                rowWidth = gridFrame.rowWidth,
                growthH = ToGrowthH(direction, wrap),
                growthV = ToGrowthV(direction, wrap),
            },
        },
        vertical
end

-- Re-applies container anchor/axis/growth/padding/rowWidth for an already-created
-- container against `parent`'s current grid. Shared by ApplyLiveConfig and the
-- existing-container branches of ReloadCustomBuffBarImpl/ReloadCustomDebuffBarImpl so
-- the three cannot drift. The outer frame anchor is a plain SetPoint (not AK-managed),
-- so it is live-settable like any other frame anchor.
local function ApplyContainerAnchorAndGrowth(boxHolder, hostFrame, conf, gridFrame)
    local containerAnchor, specInfo, vertical = BuildContainerSpec(hostFrame, conf, gridFrame)
    local direction = conf.growDirection or "LEFT"
    local directionChanged = containerDirections[boxHolder] and containerDirections[boxHolder] ~= direction
    containerDirections[boxHolder] = direction
    if directionChanged then boxHolder:Hide() end

    local size = PabSnap(conf.iconSize or 32)
    local height = conf.iconShape == "cropped" and PabSnap(mod.PAB_CroppedHeight(conf.iconSize or 32, conf))
        or size
    boxHolder:ClearAllPoints()
    boxHolder:SetSize(size, height)
    boxHolder:SetPoint(containerAnchor, hostFrame, containerAnchor, 0, 0)
    AK.SetContainerAnchor(boxHolder, specInfo.layout.anchorPoint)
    AK.SetContainerAxis(boxHolder, vertical)
    if specInfo.layout.growthH then
        AK.SetContainerGrowth(boxHolder, specInfo.layout.growthH, specInfo.layout.growthV)
    end
    AK.SetContainerPadding(boxHolder, 0, 0, 0, 0)
    AK.SetContainerRowWidth(boxHolder, gridFrame.rowWidth)

    if directionChanged then
        boxHolder:SetUnit("player")
        boxHolder:UpdateAllAuras()
        boxHolder:Show()
    end
end

-- Default anchor when no saved position exists yet. Independent per bar (bars must be
-- individually movable): the two just get separate default offsets so they don't
-- overlap before either has been dragged.
local DEFAULT_POS = {
    buffs = { point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -300, y = -200 },
    debuffs = { point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -300, y = -260 },
}

local function BarPositionKey(buffSide) return buffSide and "buffsPos" or "debuffsPos" end

-- Snaps a saved (x, y) to the physical pixel grid before SetPoint, matching
-- CUI_UnitFrames_Layout.lua's ApplyFramePosition. An unsnapped coordinate is only
-- wrong at a non-pixel-perfect UIParent scale (1 coord unit == 1 physical pixel at
-- PP.PixelBestSize()). CENTER/CENTER anchors need SnapCenterForDim -- its odd-
-- dimension handling keeps both edges on whole pixels, while plain SnapForES would
-- round the center itself and push edges onto half pixels; every other anchor point
-- uses SnapForES.
local function SnapBarPos(widget, anchorPt, relPoint, posX, posY, wid, hgt)
    if not (posX and posY) then return posX, posY end
    local Pix = CUI.PP
    local es = widget:GetEffectiveScale()
    local isCenterAnchor = (anchorPt == "CENTER" or anchorPt == nil)
        and (relPoint == "CENTER" or relPoint == nil)
    -- w/h replace the frame's own size when given (legacy positions, BarAnchorOffset).
    if isCenterAnchor then
        return Pix.SnapCenterForDim(posX, wid or widget:GetWidth() or 0, es),
            Pix.SnapCenterForDim(posY, hgt or widget:GetHeight() or 0, es)
    end
    return Pix.SnapForES(posX, es), Pix.SnapForES(posY, es)
end

-- Pixel-rounding compensation. A stored position places a reference frame (see
-- BarAnchorOffset); the live frame is the snapped grid, slightly larger or smaller.
-- Returns the SetPoint offset that keeps the growth origin (the parent corner the
-- container is pinned to, the center for centered growth) where the reference frame
-- puts it, for a frame anchored at `point`. dw/dh are (reference - snapped) at apply
-- time; ApplyLiveConfig also passes a reference size change to move a stored center
-- with its origin.
local OriginShift
do
    local FRAC_X = {
        TOPLEFT = 0,
        LEFT = 0,
        BOTTOMLEFT = 0,
        TOP = 0.5,
        CENTER = 0.5,
        BOTTOM = 0.5,
        TOPRIGHT = 1,
        RIGHT = 1,
        BOTTOMRIGHT = 1,
    }
    local FRAC_Y = {
        BOTTOMLEFT = 0,
        BOTTOM = 0,
        BOTTOMRIGHT = 0,
        LEFT = 0.5,
        CENTER = 0.5,
        RIGHT = 0.5,
        TOPLEFT = 1,
        TOP = 1,
        TOPRIGHT = 1,
    }
    function OriginShift(conf, anchorPt, dw, dh)
        local direction = conf.growDirection or "LEFT"
        local origin = (direction == "CENTER_HORIZONTAL" or direction == "CENTER_VERTICAL") and "CENTER"
            or CornerFor(direction, conf.iconWrapDirection or "LEFT")
        anchorPt = anchorPt or "CENTER"
        return (FRAC_X[origin] - (FRAC_X[anchorPt] or 0.5)) * dw,
            (FRAC_Y[origin] - (FRAC_Y[anchorPt] or 0.5)) * dh
    end
end

-- Pre-snap SetPoint offsets for a stored bar position. A position saved by an
-- unlock-mode move since the rounding fix (pos.design) refers to the design frame.
-- Any other position, defaults included, keeps the placement it had before the fix:
-- its growth origin stays where the truncated legacy frame, snapped as before, put
-- it at this resolution, until the bar is moved.
local function BarAnchorOffset(widget, conf, gridFrame, place)
    local posX, posY = place.x, place.y
    if not (posX and posY) then return posX, posY end
    local rw, rh = gridFrame.designWidth, gridFrame.designHeight
    if not place.design then
        rw, rh = gridFrame.legacyWidth, gridFrame.legacyHeight
        posX, posY =
            SnapBarPos(widget or UIParent, place.point, place.relPoint or place.point, posX, posY, rw, rh)
    end
    local dx, dy = OriginShift(conf, place.point, rw - gridFrame.width, rh - gridFrame.height)
    return posX + dx, posY + dy
end

-- Unlock-mode savePos: x/y is the VISUAL position the mover hands over, `cur` the
-- stored one. An unchanged position (a discard or an untouched commit writes back
-- what loadPos returned) keeps `cur` as it is, so a legacy position only converts
-- on a real move. Anything else is stored as a design position.
local function MoverStorePos(widget, conf, gridFrame, current, anchorPt, relPoint, posX, posY)
    relPoint = relPoint or anchorPt
    if not (posX and posY) then return { point = anchorPt, relPoint = relPoint, x = posX, y = posY } end
    if current and current.point == anchorPt and (current.relPoint or current.point) == relPoint then
        local cx, cy = BarAnchorOffset(widget, conf, gridFrame, current)
        if cx and cy and math.abs(posX - cx) < 0.001 and math.abs(posY - cy) < 0.001 then return current end
    end
    local dx, dy = OriginShift(
        conf,
        anchorPt,
        gridFrame.designWidth - gridFrame.width,
        gridFrame.designHeight - gridFrame.height
    )
    return { point = anchorPt, relPoint = relPoint, x = posX - dx, y = posY - dy, design = true }
end

-- Centered growth needs a position whose meaning does not change with the mover's
-- configured grid size. Rebase any edge-anchored saved position to CENTER/CENTER at
-- the frame's current visual center before resizing it.
local function RebaseBarPositionToCenter(widget, place)
    if place and place.point == "CENTER" and (place.relPoint or place.point) == "CENTER" then return place end
    local cx, cy = widget:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not (cx and cy and ux and uy) then return place end
    local posX, posY = cx - ux, cy - uy
    local sx, sy = SnapBarPos(widget, "CENTER", "CENTER", posX, posY)
    widget:ClearAllPoints()
    widget:SetPoint("CENTER", UIParent, "CENTER", sx, sy)
    -- design: centered growth has no rounding shift at CENTER, so the measured
    -- center already is the design center (BarAnchorOffset).
    return { point = "CENTER", relPoint = "CENTER", x = posX, y = posY, design = true }
end

-- Applies the saved position (if any) or the default to the given parent frame.
-- Shared between initial creation and the unlock-mode applyPos callback so the two
-- never drift into different SetPoint logic. `grid` is optional (computed when nil).
-- An unlock-anchored bar belongs to the anchor: the stored position is only a
-- snapshot of where the anchor put it at the last Save & Exit, stale once the
-- target moves (a player frame riding a CDM whose width varies per spec or
-- character), and nothing re-anchors a fixed-size bar afterwards. The stored
-- position still seeds a parent with no point yet; the anchor then places it.
local function ApplyBarPosition(hostFrame, buffSide, gridFrame)
    local unlockKey = buffSide and "PAB_Buffs" or "PAB_Debuffs"
    local anchored = CUI.IsUnlockAnchored and CUI.IsUnlockAnchored(unlockKey)
    if anchored and hostFrame:GetNumPoints() > 0 and CUI.ReapplyOwnAnchor then
        CUI.ReapplyOwnAnchor(unlockKey)
        return
    end
    local pabCfg = PAB()
    local posKey = BarPositionKey(buffSide)
    local place = pabCfg and pabCfg[posKey]
    local def = buffSide and DEFAULT_POS.buffs or DEFAULT_POS.debuffs
    local conf = pabCfg and (buffSide and DefaultBuffsCfg(pabCfg) or DefaultDebuffsCfg(pabCfg))
    local p = (place and place.point) and place or def
    local posX, posY = p.x, p.y
    if conf then
        posX, posY = BarAnchorOffset(hostFrame, conf, gridFrame or ComputeGrid(buffSide, conf), p)
    end
    hostFrame:ClearAllPoints()
    posX, posY = SnapBarPos(hostFrame, p.point, p.relPoint or p.point, posX, posY)
    hostFrame:SetPoint(p.point, UIParent, p.relPoint or p.point, posX, posY)
    if conf and (conf.growDirection == "CENTER_HORIZONTAL" or conf.growDirection == "CENTER_VERTICAL") then
        pabCfg[posKey] = RebaseBarPositionToCenter(hostFrame, place)
    end
    if anchored and CUI.ReapplyOwnAnchor then CUI.ReapplyOwnAnchor(unlockKey) end
end

-- Blizzard's player BuffFrame/DebuffFrame are superseded by this module: hide them so
-- auras aren't shown twice. House pattern for "Blizzard keeps re-showing this": Hide()
-- once, then hooksecurefunc(Show) to immediately re-hide whenever Blizzard's code calls
-- Show() again. hooksecurefunc runs AFTER Blizzard's secure call completes, not from
-- inside it, so nothing is tainted. Neither frame is protected/secure, so plain Hide()
-- is safe with no lockdown concern.
local blizzardAurasHidden = false
-- True while PAB owns the buff/debuff display (the natives must stay
-- hidden): master-enabled and not in Use Blizzard Buffs mode. The re-hide
-- hooks below read this LIVE, so Disable All and Use Blizzard Buffs can
-- hand the display back without a reload.
local function OwnsNativeAuras()
    local pabCfg = PAB()
    return (pabCfg and pabCfg.enabled == true and pabCfg.useBlizzardBuffs ~= true) and true or false
end

local function HideStockAuras()
    if blizzardAurasHidden then return end
    blizzardAurasHidden = true
    if BuffFrame then
        BuffFrame:Hide()
        hooksecurefunc(BuffFrame, "Show", function()
            if OwnsNativeAuras() then BuffFrame:Hide() end
        end)
    end
    if DebuffFrame then
        DebuffFrame:Hide()
        hooksecurefunc(DebuffFrame, "Show", function()
            if OwnsNativeAuras() then DebuffFrame:Hide() end
        end)
    end
end

-- Hands the native display back mid-session (Disable All / Use Blizzard
-- Buffs ON): the hooks above release once PabOwnsNativeAuras() is false, so
-- an explicit Show restores Blizzard's frames without a reload. No-op if
-- the natives were never hidden this session.
local function ShowBlizzardPlayerAuras()
    if not blizzardAurasHidden then return end
    if OwnsNativeAuras() then return end
    if BuffFrame then BuffFrame:Show() end
    if DebuffFrame then DebuffFrame:Show() end
end

-- Re-asserts native visibility for the CURRENT profile/mode (profile swaps
-- cross enable/useBlizzard modes in both directions): hide when PAB owns
-- the display -- the first hide installs the hooks, later ones re-assert
-- past the latch -- show when it does not.
local function SyncNativeAuras()
    if OwnsNativeAuras() then
        if blizzardAurasHidden then
            if BuffFrame then BuffFrame:Hide() end
            if DebuffFrame then DebuffFrame:Hide() end
        else
            HideStockAuras()
        end
    else
        ShowBlizzardPlayerAuras()
    end
end

-- Weapon enchants are not auras, so only the engine's own item-enchantment
-- source renders them (see AK.AddItemEnchantmentsToContainer): a LEADING
-- layout group on the Buffs container, flowed ahead of the aura run in every
-- grow direction and in combat. They ride the bar's broad-content modes
-- (ns.PAB_EnchantsOn: All Buffs or Has Duration on the default Buffs bar),
-- with no opt-in of their own.
local function BuildEnchantSpec(conf, pad, rowGap, maxSlots)
    local layout = BuildGroupLayout(conf, pad, rowGap)
    local placement = CustomAuraContainerItemEnchantmentPlacement
    if placement then layout.placement = placement.BeforeAuraGroups end
    local sortMethods = AuraContainerItemEnchantmentSortMethod
    local sortDirs = AuraContainerSortDirection
    return {
        style = STYLE_BUFFS,
        -- Marks the cell as a weapon enchant for the style pass (Blizzard
        -- Style draws the stock temp-enchant ring on those only).
        extraInit = AK.EnchantCellInit,
        layout = layout,
        hidePermanent = true,
        maxSlots = maxSlots,
        -- REVERSE keeps MAIN HAND adjacent to the aura run: the engine puts
        -- the group's first element at the leading edge, and Slot order is
        -- main hand, off hand, ranged.
        sortMethod = sortMethods and sortMethods.Slot,
        sortDirection = sortDirs and sortDirs.Reverse,
    }
end

-- Declares them on `container` (idempotent) and re-applies their layout, so
-- a live padding/icon-size change follows. Turning the row OFF is served by
-- the content signature below instead: the engine has no addon-facing
-- unregister, so the container has to be rebuilt for that.
-- Wrapped in do...end so only the two helpers used below stay chunk-level
-- locals.
local BuffAuraMax, SyncEnchantEvents
do
    -- Inventory slots behind AuraContainerItemEnchantmentSlot, in the same order.
    local ENCH_INV_SLOTS = { INVSLOT_MAINHAND or 16, INVSLOT_OFFHAND or 17, INVSLOT_RANGED or 18 }

    -- Weapon enchants showing right now. Only duration-bearing ones render
    -- (hidePermanent in BuildEnchantSpec), so an empty or permanently enchanted
    -- slot costs nothing. Equipment state, not aura data: these returns carry no
    -- secret flags, in restricted combat either.
    local function ActiveEnchantCount(slots)
        local api = C_PaperDollInfo and C_PaperDollInfo.GetTemporaryEnchantmentInfo
        if not api then return 0 end
        local num = 0
        for index = 1, math.min(slots or 0, #ENCH_INV_SLOTS) do
            local details = api(ENCH_INV_SLOTS[index])
            if details and details.hasExpirationTime then num = num + 1 end
        end
        return num
    end
    -- Unit Frames widens the player buff row by the same cells.
    mod.PAB_ActiveEnchantCount = ActiveEnchantCount

    -- Aura cap for the Buffs bar: "Max Icons" is the whole bar's budget, so the
    -- cells actually showing come off it and the rendered total stays at the
    -- configured number. Nothing is reserved for a slot that is not enchanted.
    function BuffAuraMax(gridFrame)
        local slots = gridFrame.enchSlots or 0
        if slots <= 0 then return gridFrame.effectiveMax end
        local num = ActiveEnchantCount(slots)
        -- WoW Forever: its imbue cells come off the budget too (nil elsewhere).
        if mod.PAB_FvImbueCount then num = num + mod.PAB_FvImbueCount() end
        return math.max(0, gridFrame.effectiveMax - num)
    end

    -- The budget moves with the enchants, so an applied or expired oil re-applies
    -- it. Registered ONLY while the row is on, and the count is change-guarded:
    -- WEAPON_ENCHANT_CHANGED also fires for charge ticks, which leave the cell
    -- count alone.
    local enchantWatcher, lastEnchCount
    function SyncEnchantEvents(wanted)
        if wanted then
            if not enchantWatcher then
                enchantWatcher = CreateFrame("Frame")
                enchantWatcher:SetScript("OnEvent", function()
                    local num = ActiveEnchantCount(#ENCH_INV_SLOTS)
                    if num == lastEnchCount then return end
                    lastEnchCount = num
                    if mod.PAB_ApplyLiveConfig then mod.PAB_ApplyLiveConfig(true) end
                end)
            end
            lastEnchCount = ActiveEnchantCount(#ENCH_INV_SLOTS)
            enchantWatcher:RegisterEvent("WEAPON_ENCHANT_CHANGED")
            enchantWatcher:RegisterEvent("WEAPON_SLOT_CHANGED")
        elseif enchantWatcher then
            enchantWatcher:UnregisterAllEvents()
            lastEnchCount = nil
        end
        -- WoW Forever: its imbue cells follow the row on and off (nil elsewhere).
        if mod.PAB_FvImbueSync then mod.PAB_FvImbueSync(wanted) end
    end
end

local function ApplyEnchants(boxHolder, conf, pad, gridFrame)
    local on = mod.PAB_EnchantsOn(conf)
    SyncEnchantEvents(on)
    if not (on and boxHolder and gridFrame) then return end
    if (gridFrame.enchSlots or 0) <= 0 then return end
    AK.AddItemEnchantmentsToContainer(
        boxHolder,
        BuildEnchantSpec(conf, pad, gridFrame.rowGap, gridFrame.enchSlots)
    )
    -- WoW Forever: imbues are an enchant type the engine cells never see there,
    -- drawn by CUI_UnitFrames_ForeverImbues.lua (nil on every other client).
    if mod.PAB_FvImbueLayout then
        mod.PAB_FvImbueLayout(
            boxHolder,
            buffHost,
            conf,
            gridFrame,
            BuildGroupLayout(conf, pad, gridFrame.rowGap),
            (BuildContainerSpec(buffHost, conf, gridFrame))
        )
    end
end

-- Buffs content signature: the resolved spell set PLUS the number of declared
-- weapon-enchant slots. A group's candidateFilters are fixed at declaration
-- and an item enchantment cannot be undeclared at all, so a change in either
-- releases the container and builds a fresh one -- including a grid shrunk
-- below three cells, which declares fewer slots than before.
local function BuffsContentSig(conf, spells, enchSlots)
    enchSlots = mod.PAB_EnchantsOn(conf) and (enchSlots or 0) or 0
    return table.concat(spells, ",") .. (enchSlots > 0 and ("|e" .. enchSlots) or "")
end

local function BuildBars()
    if not AK then SetAK(CUI and CUI.AuraKit) end
    if not AK then return end -- 12.1 gated at file top; defensive only

    local pabCfg = PAB()
    if not pabCfg then return end -- ns.db not ready yet; SetupOptionsPanel calls back once it is

    -- Master enable, default OFF: nothing below runs while disabled -- Blizzard's
    -- BuffFrame/DebuffFrame stay untouched, no containers, no unlock elements, options
    -- page shows an activation overlay. One-shot seed: the retired Styled Player Auras
    -- module's enable toggle carries over, so its users come up enabled.
    if not pabCfg.pabEnableSeeded then
        pabCfg.pabEnableSeeded = true
        if pabCfg.enabled == nil then
            local old = mod.db and mod.db.profile and mod.db.profile.playerAuras
            if old and old.enabled == true then pabCfg.enabled = true end
        end
    end
    if pabCfg.enabled ~= true then return end

    -- Enablement is confirmed from here down: arm the cinematic/faction/
    -- vehicle recovery lane (CUI_PlayerAuraBars_Lifecycle.lua; every file has
    -- loaded by the time anything calls CreateBars). Idempotent.
    mod.PAB_ArmRecovery()

    -- Must run before DefaultBuffsCfg/DefaultDebuffsCfg are first called, so seeded
    -- values are what their first lazy-create populates. One-time-ever seed, not a
    -- re-appliable migration (see SeedDefaultBuffsDebuffsFromLegacySources).
    SeedDefaultBuffsDebuffsFromLegacySources(pabCfg)
    EnsureDebuffFilterV2(pabCfg)
    EnsureFilterLanes(pabCfg)
    EnsureBarEnable(pabCfg)

    -- Must run before buffCfg/custom-bar spell resolution below: the curated presets
    -- are otherwise only imported when the options page opens, so a bar referencing a
    -- not-yet-imported preset filter would resolve an incomplete spell set at login,
    -- cache it as its signature, and never re-resolve until something else forces a
    -- signature change.
    if mod.PAB_ImportBM2Filters then mod.PAB_ImportBM2Filters() end

    -- After the import: the External Defensives seed references the imported
    -- "Externals" preset filter by id.
    EnsureExtDefCustomBar(pabCfg)

    -- Use Blizzard Buffs: PAB stands down for the DEFAULT bars only --
    -- Blizzard's native BuffFrame/DebuffFrame stay untouched and the default
    -- bars never build; custom bars (editing-spec buckets included) still
    -- run in full. Default-bar unlock elements drop via their isHidden.
    if pabCfg.useBlizzardBuffs == true then
        RegisterPABUnlock()
        ReloadAllCustomBars()
        SyncCancelCVar()
        return
    end

    HideStockAuras()

    local buffConf, debuffConf = DefaultBuffsCfg(pabCfg), DefaultDebuffsCfg(pabCfg)

    AK.styles[STYLE_BUFFS] = BuildStyle(true, buffConf)
    AK.styles[STYLE_DEBUFFS] = BuildStyle(false, debuffConf)

    local buffGridFrame = ComputeGrid(true, buffConf)
    local debuffGridFrame = ComputeGrid(false, debuffConf)

    if not buffHost then SetBuffsParent(CreateFrame("Frame", "CludesUIPlayerAuraBars_Buffs", UIParent)) end
    buffHost:SetSize(buffGridFrame.width, buffGridFrame.height)
    ApplyBarPosition(buffHost, true, buffGridFrame)
    lastSize.buffs = {
        w = buffGridFrame.width,
        h = buffGridFrame.height,
        dw = buffGridFrame.designWidth,
        dh = buffGridFrame.designHeight,
        lw = buffGridFrame.legacyWidth,
        lh = buffGridFrame.legacyHeight,
        gd = buffConf.growDirection,
        wd = buffConf.iconWrapDirection,
    }

    if not debuffHost then
        SetDebuffsParent(CreateFrame("Frame", "CludesUIPlayerAuraBars_Debuffs", UIParent))
    end
    debuffHost:SetSize(debuffGridFrame.width, debuffGridFrame.height)
    ApplyBarPosition(debuffHost, false, debuffGridFrame)
    lastSize.debuffs = {
        w = debuffGridFrame.width,
        h = debuffGridFrame.height,
        dw = debuffGridFrame.designWidth,
        dh = debuffGridFrame.designHeight,
        lw = debuffGridFrame.legacyWidth,
        lh = debuffGridFrame.legacyHeight,
        gd = debuffConf.growDirection,
        wd = debuffConf.iconWrapDirection,
    }

    -- Enable toggles (cfg.enabled, nil = enabled): containers and groups still
    -- build below so a live re-enable needs no reload; a disabled bar just
    -- hides its parent (custom-bar pattern).
    ApplyDefaultBarShown(true)
    ApplyDefaultBarShown(false)

    local debuffChain = DebuffChainFor(debuffConf)

    -- Single scalar padding, feeding ONLY ApplyGroupConfig's per-group
    -- elementSpacing/lineSpacing/groupSpacing/groupLineSpacing (gap BETWEEN icons).
    -- Must NOT also feed the container's outer edge inset (spec.layout.padding /
    -- AK.SetContainerPadding) -- a DIFFERENT concept (container frame edge to first
    -- icon); tying them pushes the whole grid away from its fixed corner as padding
    -- grows. Outer inset is fixed at 0.
    local buffPad = buffConf.padding or 5
    local debuffPad = debuffConf.padding or 5

    local _, buffSpec = BuildContainerSpec(buffHost, buffConf, buffGridFrame)
    local _, debuffSpec = BuildContainerSpec(debuffHost, debuffConf, debuffGridFrame)

    -- Groups are declared additively right after creation (not via spec.groups) so
    -- the same ApplyGroupConfig path handles both initial creation and every later
    -- live settings change.
    --
    -- Buffs: the Filters/Extra-Spells selection and the "Show All Buffs" catch-all
    -- coexist additively on the same container -- both are independent GROUPS,
    -- nothing in AK's model makes them mutually exclusive. The catch-all uses the same
    -- zero-classes-enabled chain as Debuffs' "all" group (just { base }); buffs have no
    -- per-class filtering UI, so it's all-or-nothing, gated only by showAllBuffs.
    -- Defaults ON, else an unconfigured bar shows nothing; ON matches Blizzard's
    -- player BuffFrame (HELPFUL, no category restriction).
    --
    -- The spell selection must be ONE GROUP whose candidateFilters.includeSpellIDs is
    -- the resolved spell-ID set (map shape {[id]=true}, every includeSpellIDs consumer
    -- in the codebase uses a map, never an array). NOT one AK.AddAuraSlot per spellID:
    -- AK's flow layout only positions GROUP content, never slot content -- slots must
    -- self-anchor via extraInit (both other AddAuraSlot consumers,
    -- CUI_RaidFrames_AuraContainers.lua and CUI_ResourceBars_EbonMight121.lua, manually
    -- SetPoint their button). With slots, buttons report shown=true at the right size
    -- but GetPoint(1) returns nil and nothing renders. PAB needs a flowing multi-icon
    -- grid of a DYNAMIC spell set, which slots can't do without reimplementing flow
    -- placement by hand. A group's candidateFilters is fixed at declaration, so a
    -- spell-list change still requires releasing and recreating the container -- hence
    -- the sig-diffing.
    local buffAllChain = BuffBarChain(buffConf)
    local buffSpells = mod.PAB_ResolveSpells(buffConf)
    SetBuffsSlotSig(BuffsContentSig(buffConf, buffSpells, buffGridFrame.enchSlots))
    -- This runs more than once per session (master re-enable, Use Blizzard
    -- Buffs off, a profile swap whose content signature moved), and a container
    -- can never be destroyed: retire the previous pair first or the orphans stay
    -- shown on the same parent and every aura -- and every enchant cell -- renders
    -- twice.
    RetireContainer(buffsContainer, declaredSet.buffs)
    RetireContainer(debuffsContainer, declaredSet.debuffs)
    AK.RequestContainer(buffHost, "player", buffSpec, function(boxHolder)
        SetBuffsContainer(boxHolder)
        ApplyContainerAnchorAndGrowth(boxHolder, buffHost, buffConf, buffGridFrame)
        ApplyEnchants(boxHolder, buffConf, buffPad, buffGridFrame)
        declaredSet.buffs = {}
        ApplyGroupConfig(
            boxHolder,
            buffAllChain,
            declaredSet.buffs,
            STYLE_BUFFS,
            BuffAuraMax(buffGridFrame),
            buffPad,
            buffGridFrame.rowGap,
            buffConf,
            BuffCandidateExtras(buffConf)
        )
        if #buffSpells > 0 then
            local includeMap = {}
            for index = 1, #buffSpells do
                includeMap[buffSpells[index]] = true
            end
            AK.AddGroupToContainer(boxHolder, {
                key = "spells",
                filter = { "HELPFUL" },
                style = STYLE_BUFFS,
                maxFrameCount = BuffAuraMax(buffGridFrame),
                candidateFilters = MergeCandidateFilters(
                    { includeSpellIDs = includeMap },
                    BuffCandidateExtras(buffConf)
                ),
                sortMethod = ResolveSortMethod(buffConf),
                sortDirection = ResolveSortDirection(buffConf),
                layout = BuildGroupLayout(buffConf, buffPad, buffGridFrame.rowGap),
            })
            declaredSet.buffs.spells = true
        end
    end)
    AK.RequestContainer(debuffHost, "player", debuffSpec, function(boxHolder)
        SetDebuffsContainer(boxHolder)
        ApplyContainerAnchorAndGrowth(boxHolder, debuffHost, debuffConf, debuffGridFrame)
        declaredSet.debuffs = {}
        ApplyGroupConfig(
            boxHolder,
            debuffChain,
            declaredSet.debuffs,
            STYLE_DEBUFFS,
            debuffGridFrame.effectiveMax,
            debuffPad,
            debuffGridFrame.rowGap,
            debuffConf,
            DebuffCandidateExtras(debuffConf)
        )
    end)
    RegisterPABUnlock()
    ReloadAllCustomBars()
    SyncCancelCVar()
end

-- Unlock mode's cog menu only offers "Element Options" for keys in
-- CludesUI._ELEMENT_SETTINGS_MAP; a module adds its own dynamic keys there the
-- way CludesUIDataBars.lua does, so CUI_UnlockMode.lua's static map needs no
-- PAB branch. barId nil = one of the two built-in bars.
--
-- No sectionName/highlightText: NavigateToElementSettings scans the page
-- wrapper's DIRECT children for section headers, and PABMP_BuildPage builds past
-- `parent` into its own root on the shared scroll frame, so nothing is scannable.
local function MapElementSettings(gridKey, kind, barId)
    if not CUI then return end
    CUI._ELEMENT_SETTINGS_MAP = CUI._ELEMENT_SETTINGS_MAP or {}
    CUI._ELEMENT_SETTINGS_MAP[gridKey] = {
        module = "CludesUIUnitFrames",
        page = "Player Aura Bars",
        preSelectFn = function()
            if not CUI._setPABSelection then return end
            if not barId then
                CUI._setPABSelection(kind, "default")
                return
            end
            -- Owning bucket resolved at click time, not baked in at registration:
            -- the tile's "Add To" menu can move a bar to another editing-spec
            -- bucket long after its key was mapped.
            local barFrame, bucket
            if kind == "buff" then
                barFrame, bucket = mod.PAB_GetCustomBuffBar(barId)
            else
                barFrame, bucket = mod.PAB_GetCustomDebuffBar(barId)
            end
            if barFrame then CUI._setPABSelection(kind, barId, bucket) end
        end,
    }
end

-- Unlock-mode registration, patterned on Damage Meters' ns.RegisterDMUnlock
-- (CUI_DamageMeters_State.lua) and MakeSATimerUnlockElement (CUI_DamageMeters_Timer.lua)
-- (observed CUI.MakeUnlockElement field
-- usage, not a verified schema). Both bars use noResize (AuraKit sizes the container
-- from the active aura count, nothing to drag-resize) and noAnchorTarget (a
-- dynamically-resizing frame is a bad anchor target for other elements).
function RegisterPABUnlock()
    if not (CUI and CUI.RegisterUnlockElements and CUI.MakeUnlockElement) then return end
    local MK = CUI.MakeUnlockElement

    local function MakeBarElement(gridKey, labelText, sequence, buffSide, getParent)
        return MK({
            key = gridKey,
            label = labelText,
            group = "Player Aura Bars",
            order = sequence,
            noResize = true,
            noAnchorTarget = true,
            -- Enable toggle: a disabled default bar keeps no mover (custom-bar
            -- parity). Master-disabled and Use Blizzard Buffs stand the
            -- defaults down entirely, mover included.
            isHidden = function()
                local pabCfg = PAB()
                if not pabCfg or pabCfg.enabled ~= true or pabCfg.useBlizzardBuffs == true then
                    return true
                end
                local conf = buffSide and DefaultBuffsCfg(pabCfg) or DefaultDebuffsCfg(pabCfg)
                return conf.enabled == false
            end,
            getFrame = function() return getParent() end,
            -- Deliberately NOT container:GetWidth()/GetHeight(): AuraContainer geometry
            -- is a Secret Value while tainted (throws in CUI_UnlockMode.lua comparing a
            -- secret baseW). noResize is set anyway, so only a public number for the
            -- mover's label is needed.
            getSize = function()
                local pabCfg = PAB()
                if not pabCfg then return 32, 32 end
                local gridFrame =
                    ComputeGrid(buffSide, buffSide and DefaultBuffsCfg(pabCfg) or DefaultDebuffsCfg(pabCfg))
                return gridFrame.width, gridFrame.height
            end,
            -- The mover works in VISUAL positions (the snapped live frame): loadPos
            -- converts the stored one (BarAnchorOffset), savePos goes back through
            -- MoverStorePos, which leaves an unchanged position untouched.
            savePos = function(_, anchorPt, relPoint, posX, posY)
                local pabCfg = PAB()
                if not pabCfg then return end
                local posKey = BarPositionKey(buffSide)
                local conf = buffSide and DefaultBuffsCfg(pabCfg) or DefaultDebuffsCfg(pabCfg)
                pabCfg[posKey] = MoverStorePos(
                    getParent(),
                    conf,
                    ComputeGrid(buffSide, conf),
                    pabCfg[posKey],
                    anchorPt,
                    relPoint,
                    posX,
                    posY
                )
            end,
            loadPos = function()
                local pabCfg = PAB()
                local place = pabCfg and pabCfg[BarPositionKey(buffSide)]
                if not place then return nil end
                local conf = buffSide and DefaultBuffsCfg(pabCfg) or DefaultDebuffsCfg(pabCfg)
                local posX, posY = BarAnchorOffset(getParent(), conf, ComputeGrid(buffSide, conf), place)
                return { point = place.point, relPoint = place.relPoint, x = posX, y = posY }
            end,
            -- Spec-override unlock layers bank and restore the STORED table through
            -- these, not the visual position loadPos returns: a layer harvested at
            -- one resolution stays valid at another and keeps the design flag.
            loadRawPosition = function()
                local pabCfg = PAB()
                local place = pabCfg and pabCfg[BarPositionKey(buffSide)]
                if not place then return nil end
                return {
                    point = place.point,
                    relPoint = place.relPoint,
                    x = place.x,
                    y = place.y,
                    design = place.design,
                }
            end,
            saveRawPosition = function(_, profile)
                local pabCfg = PAB()
                if not (pabCfg and profile and profile.point) then return end
                pabCfg[BarPositionKey(buffSide)] = {
                    point = profile.point,
                    relPoint = profile.relPoint or profile.point,
                    x = profile.x,
                    y = profile.y,
                    design = profile.design,
                }
            end,
            clearPos = function()
                local pabCfg = PAB()
                if pabCfg then pabCfg[BarPositionKey(buffSide)] = nil end
            end,
            applyPos = function()
                local hostFrame = getParent()
                if hostFrame then ApplyBarPosition(hostFrame, buffSide) end
            end,
        })
    end

    -- Buffs mover carries the bar's display name (see ns.PAB_DefaultBuffsName).
    -- Baked in at registration -- CUI_UnlockMode.lua's GetBarLabel returns the
    -- stored string -- which is why ApplyLiveConfig re-registers when the name
    -- changes.
    local pabCfg = PAB()
    local buffLabel = mod.PAB_DefaultBuffsName(pabCfg and DefaultBuffsCfg(pabCfg) or nil)
    lastUnlockBuffLabel = buffLabel

    local elements = {
        MakeBarElement("PAB_Buffs", buffLabel, 700, true, function() return buffHost end),
        MakeBarElement("PAB_Debuffs", "Debuffs", 701, false, function() return debuffHost end),
    }
    MapElementSettings("PAB_Buffs", "buff")
    MapElementSettings("PAB_Debuffs", "debuff")
    CUI:RegisterUnlockElements(elements, "CludesUIUnitFrames")
    -- Registration alone only updates the element table; a mover already built
    -- this session keeps the label CreateMover baked into its FontString. No-op
    -- before the first unlock session, so it is safe on the CreateBars path too.
    if CUI.RefreshUnlockElementLabel then CUI.RefreshUnlockElementLabel("PAB_Buffs") end
end
-- Exported for the default-bar enable toggles: re-registering re-runs unlock
-- mode's Sync, which re-reads isHidden and drops a disabled bar's mover
-- mid-session instead of waiting for the next natural Sync.
mod.PAB_RegisterUnlock = function() RegisterPABUnlock() end

-- Public hook for the Options UI: rebuild both style tables and re-decorate every
-- existing button. Purely a re-skin -- does NOT touch groups, filters, container
-- layout, or parent frame size. Call for style-only fields (colors, fonts, border,
-- dispel colors, cooldown/stack text, icon zoom). iconSize also needs ApplyLiveConfig
-- for both polarities, since it affects grid geometry.
local function StyleAllBars()
    local pabCfg = PAB()
    if not (AK and pabCfg) then return end
    AK.styles[STYLE_BUFFS] = BuildStyle(true, DefaultBuffsCfg(pabCfg))
    AK.styles[STYLE_DEBUFFS] = BuildStyle(false, DefaultDebuffsCfg(pabCfg))
    AK.RestyleSoon(STYLE_BUFFS)
    AK.RestyleSoon(STYLE_DEBUFFS)
    SyncCancelCVar()
end
mod.PAB_Restyle = StyleAllBars

-- CursorFreelookStartDelta is the fraction of the screen the cursor must move before a
-- held mouse button counts as camera freelook instead of a click; Blizzard's own
-- shipped default is 0.001 (verified against the client's cvar list, not assumed). At
-- 0 -- the most aggressive setting, zero movement required -- ANY right-click on an
-- aura icon is claimed for freelook before the release reaches our button, silently
-- eating the "Right-Click to Cancel" click (field-reported 2026-08-12, twice
-- independently). Players land on 0 via third-party "camera feel" addons/macros (a
-- dedicated community addon, CursorDeltaFix, does exactly this:
-- SetCVar("CursorFreelookStartDelta", 0)) or a manual /console tweak, not from
-- anything CludesUI does.
--
-- Repair only, never a nudge above Blizzard's default: we only ever touch this CVar
-- when it is caught sitting at the pathological 0, restoring it to Blizzard's own
-- 0.001 -- never raised past that, and never touched at all if it's anywhere else
-- (including a deliberately-tuned non-zero, non-default value). Conditional on some
-- right-click-cancelable buff surface actually being live, so a player who never uses
-- the feature never has this CVar touched by CludesUI at all.
local CANCEL_CVAR = "CursorFreelookStartDelta"
local CANCEL_CVAR_BROKEN = 0
local CANCEL_CVAR_DEFAULT = "0.001"

--- True while some right-click-cancelable player buff display is live: the default
--- Buffs bar (rightClickCancel defaults ON), any enabled custom buff bar with its own
--- toggle ON, or the classic Unit Frames player-buffs display (CUI_UnitFrames_
--- AuraContainers.lua's cancelButtons is unconditional whenever unit=="player" and
--- isBuff, gated only on the element being shown at all).
local function AnyRightClickCancelActive(cfg)
    -- Use Blizzard Buffs: the NATIVE BuffFrame owns the display and its
    -- right-click cancel breaks on the same CVar -- always repair.
    if cfg.useBlizzardBuffs == true then return true end
    local dbc = DefaultBuffsCfg(cfg)
    if dbc.enabled ~= false and dbc.rightClickCancel ~= false then return true end
    local customBuffBars = cfg.customBuffBars
    if customBuffBars then
        for index = 1, #customBuffBars do
            local barFrame = customBuffBars[index]
            if barFrame.enabled ~= false and barFrame.rightClickCancel ~= false then return true end
        end
    end
    -- Editing-spec bucket buff bars count too (enable-toggle test only,
    -- matching the legacy loop: the CVar repair may run while the spec is
    -- mid-change, so err on the permissive side).
    if cfg.pabSpecBars then
        for _, bar in pairs(cfg.pabSpecBars) do
            local bl = bar.buffBars
            if bl then
                for index = 1, #bl do
                    local barFrame = bl[index]
                    if barFrame.enabled ~= false and barFrame.rightClickCancel ~= false then return true end
                end
            end
        end
    end
    local saved = mod.db
    local playerCfg = saved and saved.profile and saved.profile.player
    if playerCfg and playerCfg.showBuffs ~= false then return true end
    return false
end

function SyncCancelCVar()
    local pabCfg = PAB()
    if not pabCfg or pabCfg.enabled ~= true then return end
    if not AnyRightClickCancelActive(pabCfg) then return end
    if InCombatLockdown() then return end
    if tonumber(GetCVar(CANCEL_CVAR)) == CANCEL_CVAR_BROKEN then
        -- A repair to Blizzard's default, which Uninstall CUI must not undo:
        -- plain SetCVar, not CludesUI.SetCVar.
        SetCVar(CANCEL_CVAR, CANCEL_CVAR_DEFAULT)
    end
end

-- Public hook for the Options UI: live counterpart to RestyleBars for everything
-- spec-level (class toggles, grid: iconsPerRow/maxRows/padding/maxBuffs-or-Debuffs,
-- grow direction). Applies to ONE polarity's container; callers touching a shared
-- field (iconSize) call it for both. No-op before the container exists
-- (SetupOptionsPanel calls CreateBars() once ns.db is ready).
local function ApplyLiveCfg(buffSide)
    local pabCfg = PAB()
    if not (AK and pabCfg) then return end
    if
        DeferRestrictedApply(
            buffSide and "default-buffs" or "default-debuffs",
            function() ApplyLiveCfg(buffSide) end,
            buffSide and buffsContainer or debuffsContainer,
            (buffSide and DefaultBuffsCfg(pabCfg) or DefaultDebuffsCfg(pabCfg)).growDirection
        )
    then
        return
    end
    local boxHolder = buffSide and buffsContainer or debuffsContainer
    local hostFrame = buffSide and buffHost or debuffHost
    if not boxHolder or not hostFrame then return end

    local conf = buffSide and DefaultBuffsCfg(pabCfg) or DefaultDebuffsCfg(pabCfg)
    -- Enable toggle: a disabled bar hides its parent and skips every live
    -- apply below (geometry, enchant layout, group work) -- re-enabling runs
    -- the full pass. Same shape as the custom bars' early return. Use
    -- Blizzard Buffs and the MASTER disable stand the default bars down the
    -- same way. Weapon enchants ride the container, so they stand down with
    -- the bar's parent -- nothing extra to tear down here.
    ApplyDefaultBarShown(buffSide)
    if pabCfg.enabled ~= true or conf.enabled == false or pabCfg.useBlizzardBuffs == true then
        if buffSide then SyncEnchantEvents(false) end
        return
    end
    local gridFrame = ComputeGrid(buffSide, conf)
    local sizeKey = buffSide and "buffs" or "debuffs"
    local previous = lastSize[sizeKey]

    -- Edge-growing containers use a fixed parent corner, so move a CENTER-saved parent
    -- by half the size delta to keep that corner fixed. Centered growth deliberately
    -- skips this: the parent center is its fixed anchor. Uses lastSize rather than live
    -- geometry so rapid slider updates cannot read a stale prior size.
    local posKey = BarPositionKey(buffSide)
    local place = pabCfg[posKey]
    local centered = conf.growDirection == "CENTER_HORIZONTAL" or conf.growDirection == "CENTER_VERTICAL"
    -- The engine aura container anchored to `parent` makes the PARENT's own geometry
    -- protected in combat (anchor-ancestor rule): the SetSize/ClearAllPoints/SetPoint
    -- below are ADDON_ACTION_BLOCKED inside lockdown -- and the cinematic/faction/
    -- vehicle recovery lane runs this function in instanced combat BY DESIGN (see
    -- DeferRestrictedApply). A recovery re-drive carries an UNCHANGED grid, so
    -- skipping the geometry cluster drops nothing there; a genuinely changed grid
    -- (options edited mid-combat) or a still-pending centered rebase reconciles once
    -- at the regen edge. lastSize stays untouched on the skip so the deferred pass
    -- still sees the real last-applied size (the fixed-corner compensation needs it),
    -- and the stored pos is not mutated for a resize that never landed.
    if InCombatLockdown() then
        local sizeChanged = not (
            previous
            and previous.w == gridFrame.width
            and previous.h == gridFrame.height
            and previous.dw == gridFrame.designWidth
            and previous.dh == gridFrame.designHeight
            and previous.gd == conf.growDirection
            and previous.wd == conf.iconWrapDirection
        )
        local rebasePending = centered
            and not (place and place.point == "CENTER" and (place.relPoint or place.point) == "CENTER")
        if sizeChanged or rebasePending then
            QueuePABRegenApply(sizeKey, function() ApplyLiveCfg(buffSide) end)
        end
    else
        if centered then
            place = RebaseBarPositionToCenter(hostFrame, place)
            pabCfg[posKey] = place
        end
        local resized = not centered
            and previous
            and (
                previous.w ~= gridFrame.width
                or previous.h ~= gridFrame.height
                or previous.dw ~= gridFrame.designWidth
                or previous.dh ~= gridFrame.designHeight
            )
        if resized and place and place.point == "CENTER" then
            -- The stored center belongs to its reference frame (design or legacy, see
            -- BarAnchorOffset), so it moves by that frame's delta, toward whichever
            -- side the growth origin is on.
            local dx, dy
            if place.design then
                dx, dy = OriginShift(
                    conf,
                    place.point,
                    previous.dw - gridFrame.designWidth,
                    previous.dh - gridFrame.designHeight
                )
            else
                dx, dy = OriginShift(
                    conf,
                    place.point,
                    previous.lw - gridFrame.legacyWidth,
                    previous.lh - gridFrame.legacyHeight
                )
            end
            place.x = place.x + dx
            place.y = place.y + dy
        end
        local turned = previous
            and (previous.gd ~= conf.growDirection or previous.wd ~= conf.iconWrapDirection)
        lastSize[sizeKey] = {
            w = gridFrame.width,
            h = gridFrame.height,
            dw = gridFrame.designWidth,
            dh = gridFrame.designHeight,
            lw = gridFrame.legacyWidth,
            lh = gridFrame.legacyHeight,
            gd = conf.growDirection,
            wd = conf.iconWrapDirection,
        }
        hostFrame:SetSize(gridFrame.width, gridFrame.height)
        -- Re-seated AFTER SetSize so SnapBarPos snaps against the new size and the
        -- rounding shift follows the new grid, or the new origin after a grow/wrap
        -- direction change. The STORED pos keeps the raw accumulation. Never for an
        -- unlock-anchored bar: the anchor owns its placement and re-applies itself on
        -- a size change.
        local anchored = CUI.IsUnlockAnchored
            and CUI.IsUnlockAnchored(buffSide and "PAB_Buffs" or "PAB_Debuffs")
        if (resized or turned) and not anchored then ApplyBarPosition(hostFrame, buffSide, gridFrame) end
    end

    local pad = conf.padding or 5
    ApplyContainerAnchorAndGrowth(boxHolder, hostFrame, conf, gridFrame)

    if buffSide then
        -- Unlock mode bakes the mover's label at registration, so a Filters
        -- change would leave the old name on it until the next CreateBars.
        -- Re-register only when the name actually changed -- this function runs
        -- on every slider drag.
        local labelText = mod.PAB_DefaultBuffsName(conf)
        if labelText ~= lastUnlockBuffLabel and RegisterPABUnlock then RegisterPABUnlock() end
    end

    if buffSide then
        local spells = mod.PAB_ResolveSpells(conf)
        local sig = BuffsContentSig(conf, spells, gridFrame.enchSlots)
        local allChain = BuffBarChain(conf)
        if sig ~= buffsSlotSig then
            -- Safe to fully release+rebuild: the default Buffs container holds only the
            -- catch-all group + the spells group, nothing else shares it. The new
            -- container's anchor/growth/rowWidth come from `spec` below -- the live
            -- SetContainerAnchor/etc calls above ran against the OLD container and are
            -- harmless overhead. A group's candidateFilters is fixed at declaration, so a
            -- spell-list change requires this release+rebuild -- and so does the
            -- weapon-enchant row, which the engine cannot undeclare at all.
            RetireContainer(boxHolder, declaredSet.buffs)
            local _, specInfo = BuildContainerSpec(hostFrame, conf, gridFrame)
            AK.RequestContainer(hostFrame, "player", specInfo, function(newContainer)
                SetBuffsContainer(newContainer)
                ApplyContainerAnchorAndGrowth(newContainer, hostFrame, conf, gridFrame)
                ApplyEnchants(newContainer, conf, pad, gridFrame)
                declaredSet.buffs = {}
                ApplyGroupConfig(
                    newContainer,
                    allChain,
                    declaredSet.buffs,
                    STYLE_BUFFS,
                    BuffAuraMax(gridFrame),
                    pad,
                    gridFrame.rowGap,
                    conf,
                    BuffCandidateExtras(conf)
                )
                if #spells > 0 then
                    local includeMap = {}
                    for index = 1, #spells do
                        includeMap[spells[index]] = true
                    end
                    AK.AddGroupToContainer(newContainer, {
                        key = "spells",
                        filter = { "HELPFUL" },
                        style = STYLE_BUFFS,
                        maxFrameCount = BuffAuraMax(gridFrame),
                        candidateFilters = MergeCandidateFilters(
                            { includeSpellIDs = includeMap },
                            BuffCandidateExtras(conf)
                        ),
                        sortMethod = ResolveSortMethod(conf),
                        sortDirection = ResolveSortDirection(conf),
                        layout = BuildGroupLayout(conf, pad, gridFrame.rowGap),
                    })
                    declaredSet.buffs.spells = true
                end
            end)
            SetBuffsSlotSig(sig)
        else
            -- Spell list unchanged: only Show All Buffs and/or grid (icon size,
            -- padding, ...) may have changed. ApplyGroupConfig is idempotent and self-
            -- zeroes the catch-all when `allChain` is empty, so one call covers on and
            -- off. The spells group isn't part of that chain path, so its
            -- maxFrameCount/layout/sort are refreshed here directly.
            --
            -- The enchant layout rides this branch (not the pass above): on the
            -- rebuild path the container here is the one about to be retired,
            -- and declaring three engine frames on it would leak them.
            ApplyEnchants(boxHolder, conf, pad, gridFrame)
            ApplyGroupConfig(
                boxHolder,
                allChain,
                declaredSet.buffs,
                STYLE_BUFFS,
                BuffAuraMax(gridFrame),
                pad,
                gridFrame.rowGap,
                conf,
                BuffCandidateExtras(conf)
            )
            if declaredSet.buffs.spells then
                CUI.AuraKit.SetGroupCap(boxHolder, "spells", BuffAuraMax(gridFrame))
                boxHolder:SetAuraGroupLayout("spells", BuildGroupLayout(conf, pad, gridFrame.rowGap))
                local liveIncludeMap = {}
                for index = 1, #spells do
                    liveIncludeMap[spells[index]] = true
                end
                boxHolder:SetAuraGroupCandidateFilters(
                    "spells",
                    MergeCandidateFilters({ includeSpellIDs = liveIncludeMap }, BuffCandidateExtras(conf))
                )
                local sortMethod, sortDirection = ResolveSortMethod(conf), ResolveSortDirection(conf)
                if sortMethod ~= nil and sortDirection ~= nil then
                    boxHolder:SetAuraGroupSortMethod("spells", sortMethod, sortDirection)
                end
            end
        end
    else
        local chain = DebuffChainFor(conf)
        ApplyGroupConfig(
            boxHolder,
            chain,
            declaredSet.debuffs,
            STYLE_DEBUFFS,
            gridFrame.effectiveMax,
            pad,
            gridFrame.rowGap,
            conf,
            DebuffCandidateExtras(conf)
        )
    end

    if PAB_MaybeRefreshPreview then PAB_MaybeRefreshPreview(buffSide and "buff" or "debuff", "default") end
end
mod.PAB_ApplyLiveConfig = ApplyLiveCfg
-- Bridge for CludesUF:GetGrowDirectionForBar/SetGrowDirectionForBar, kept here
-- rather than in CUI_UnitFrames_Lifecycle.lua so the settings-field names stay defined
-- in one place.
--
-- Also handles custom-bar keys ("PAB_CustomBuff_<id>"/"PAB_CustomDebuff_<id>", the
-- unlock-mode keys RegisterPABCustomUnlock registers in CUI_PlayerAuraBars_CustomBars.lua): CUI_UnlockMode.lua's Grow
-- dropdown dispatches here for ANY barKey prefixed "PAB_", so without these branches it
-- silently no-ops on custom bars. Calls ns.PAB_ReloadCustomBuffBar/DebuffBar rather than
-- BuildContainerSpec/SetContainerGrowth directly, since the spell/class signature is
-- unchanged and those already re-apply corner + growth cheaply.
function mod.PAB_GetGrowDirection(barId)
    local pabCfg = PAB()
    if not pabCfg then return "LEFT" end
    if barId == "PAB_Buffs" then return DefaultBuffsCfg(pabCfg).growDirection or "LEFT" end
    if barId == "PAB_Debuffs" then return DefaultDebuffsCfg(pabCfg).growDirection or "LEFT" end
    local buffId = barId:match("^PAB_CustomBuff_(%d+)$")
    if buffId then
        local barFrame = mod.PAB_GetCustomBuffBar(tonumber(buffId))
        return barFrame and (barFrame.growDirection or "LEFT") or "LEFT"
    end
    local debuffId = barId:match("^PAB_CustomDebuff_(%d+)$")
    if debuffId then
        local barFrame = mod.PAB_GetCustomDebuffBar(tonumber(debuffId))
        return barFrame and (barFrame.growDirection or "LEFT") or "LEFT"
    end
    return "LEFT"
end

function mod.PAB_SetGrowDirection(barId, direction)
    local pabCfg = PAB()
    if not pabCfg then return end
    if barId == "PAB_Buffs" then
        DefaultBuffsCfg(pabCfg).growDirection = direction
        StyleAllBars()
        ApplyLiveCfg(true)
        return
    elseif barId == "PAB_Debuffs" then
        DefaultDebuffsCfg(pabCfg).growDirection = direction
        StyleAllBars()
        ApplyLiveCfg(false)
        return
    end
    local buffId = barId:match("^PAB_CustomBuff_(%d+)$")
    if buffId then
        local barFrame = mod.PAB_GetCustomBuffBar(tonumber(buffId))
        if barFrame then
            barFrame.growDirection = direction
            mod.PAB_ReloadCustomBuffBar(barFrame.id)
        end
        return
    end
    local debuffId = barId:match("^PAB_CustomDebuff_(%d+)$")
    if debuffId then
        local barFrame = mod.PAB_GetCustomDebuffBar(tonumber(debuffId))
        if barFrame then
            barFrame.growDirection = direction
            mod.PAB_ReloadCustomDebuffBar(barFrame.id)
        end
        return
    end
end

Inner.ApplyContainerAnchorAndGrowth = ApplyContainerAnchorAndGrowth
Inner.ApplyDefaultBarShown, Inner.ApplyLiveConfig = ApplyDefaultBarShown, ApplyLiveCfg
Inner.BarAnchorOffset, Inner.BuffsContentSig = BarAnchorOffset, BuffsContentSig
Inner.BuildContainerSpec, Inner.CornerFor, Inner.CreateBars = BuildContainerSpec, CornerFor, BuildBars
Inner.DeferRestrictedApply, Inner.MapElementSettings = DeferRestrictedApply, MapElementSettings
Inner.MoverStorePos, Inner.QueuePABRegenApply = MoverStorePos, QueuePABRegenApply
Inner.RebaseBarPositionToCenter, Inner.RegisterPABUnlock = RebaseBarPositionToCenter, RegisterPABUnlock
Inner.SetParentShownSafe, Inner.ShowBlizzardPlayerAuras = SetParentShownSafe, ShowBlizzardPlayerAuras
Inner.SnapBarPos, Inner.SyncCancelCVar = SnapBarPos, SyncCancelCVar
Inner.SyncEnchantEvents, Inner.SyncNativeAuras = SyncEnchantEvents, SyncNativeAuras
Inner.broken = false
