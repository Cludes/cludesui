if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_ResourceBars_Anchors.lua
--
--  The player resource stack rects, the Unlock Mode registration and the
--  anchor system: anchor frames, bar anchoring and free positions.
--  Reads the earlier Resource Bars files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._internals
-- CludesUIResourceBars.lua or an earlier Resource Bars file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local Pix = CludesUI.PP
local floor = math.floor

local ERB, SnapXY, IsPowerBarHidden = Inner.ERB, Inner.SnapXY, Inner.IsPowerBarHidden
local IsSpecDisabled, IsVerticalOrientation = Inner.IsSpecDisabled, Inner.IsVerticalOrientation
local OrientedSize = Inner.OrientedSize

local mainFrame
Inner.mainFrameSetters[#Inner.mainFrameSetters + 1] = function(val)
    mainFrame = val
end
local health
Inner.healthBarSetters[#Inner.healthBarSetters + 1] = function(val)
    health = val
end
local primaryBar
Inner.primaryBarSetters[#Inner.primaryBarSetters + 1] = function(val)
    primaryBar = val
end
local secondaryFrame
Inner.secondaryFrameSetters[#Inner.secondaryFrameSetters + 1] = function(val)
    secondaryFrame = val
end
local secondaryBar
Inner.secondaryBarSetters[#Inner.secondaryBarSetters + 1] = function(val)
    secondaryBar = val
end
local castBarFrame
Inner.castBarFrameSetters[#Inner.castBarFrameSetters + 1] = function(val)
    castBarFrame = val
end
local gcdBarFrame
Inner.gcdBarFrameSetters[#Inner.gcdBarFrameSetters + 1] = function(val)
    gcdBarFrame = val
end
local totemBarFrame
Inner.totemBarFrameSetters[#Inner.totemBarFrameSetters + 1] = function(val)
    totemBarFrame = val
end
local cachedSecondary
Inner.cachedSecondarySetters[#Inner.cachedSecondarySetters + 1] = function(val)
    cachedSecondary = val
end

local RefreshAnchoredBarsForUnlockTarget

-- Per-bar rects of the player's resource stack for the current spec and form, in
-- physical pixels: one { l, r, t, b } entry per bar in the layout, or nil when there
-- is none. A bar counts by its layout predicate (Power: not IsPowerBarHidden; Class
-- Resource: the structural part of UpdateVisibility, without the transient
-- ShouldShowBar; the Forever shapeshift mana bar: ns._FDMStackBottomFrame, its host
-- only while shown for the form) and by not being hidden, never by its alpha: the
-- combat/target/group visibility modes only fade a bar that keeps its place, so the
-- footprint holds still through them. The unused class resource container is hidden
-- and keeps its old rect, so it never counts. The unit frame auras walk the chain of
-- these bars docked under the player frame (CUI_UnitFrames_AuraContainers.lua,
-- ResourceStackBelowFrame), so a bar placed elsewhere is never reserved.
function CludesUI.ERB_PlayerStackBars()
    local p = ERB and ERB.db and ERB.db.profile
    if not p then
        return nil
    end
    local barList, num = nil, 0
    local function add(f)
        if not (f and f:IsShown()) then
            return
        end
        local fb, ft = f:GetBottom(), f:GetTop()
        if not (fb and ft) then
            return
        end
        local s = f:GetEffectiveScale() or 1
        barList = barList or {}
        num = num + 1
        barList[num] = { l = (f:GetLeft() or 0) * s, r = (f:GetRight() or 0) * s, t = ft * s, b = fb * s }
    end
    if not IsPowerBarHidden() then
        add(primaryBar)
    end
    local sp = p.secondary
    if
        sp
        and sp.enabled ~= false
        and not IsSpecDisabled(sp)
        and not _G._CURB_BarHiddenByForm(sp)
        and cachedSecondary
    then
        add(secondaryFrame)
        add(secondaryBar)
    end
    if mod._FDMStackBottomFrame then
        add(mod._FDMStackBottomFrame())
    end
    return barList
end

-- Unlock mode: register with shared CludesUI unlock system
local function RegisterUnlockElements()
    if not CludesUI or not CludesUI.RegisterUnlockElements then
        return
    end
    local MK = CludesUI.MakeUnlockElement

    -- Shared helper: save position to a settings sub-table and apply to frame
    -- centerShiftY: extra Y on a stored CENTER, as the bar's own build adds it.
    local function MakePosHelpers(getSettings, frame_fn, defaultOffX, defaultOffY, centerShiftY)
        local function savePos(key, anchorPoint, relPoint, posX, posY)
            if not anchorPoint then
                return
            end
            local s = getSettings()
            s.unlockPos = { point = anchorPoint, relPoint = relPoint or anchorPoint, x = posX, y = posY }
            if not CludesUI._unlockActive then
                local f = frame_fn()
                if f then
                    f:ClearAllPoints()
                    f:SetPoint(anchorPoint, UIParent, relPoint or anchorPoint, posX, posY)
                end
            end
            mod.ERB_GroupDirty()
        end
        local function loadPos()
            local place = getSettings().unlockPos
            if not place then
                return nil
            end
            local pt = place.point
            -- The resize re-apply reads this, not applyPos (0 while expand is suppressed).
            local posY = place.y
            if centerShiftY and pt == "CENTER" and posY then
                posY = posY + centerShiftY()
            end
            return { point = pt, relPoint = place.relPoint or pt, x = place.x, y = posY }
        end
        local function clearPos()
            local s = getSettings()
            s.unlockPos = nil
            if defaultOffX then
                s.offsetX = defaultOffX
            end
            if defaultOffY then
                s.offsetY = defaultOffY
            end
        end
        local function applyPos()
            mod.ERB_GroupDirty()
            local s = getSettings()
            if s.anchorTo and s.anchorTo ~= "none" then
                return
            end
            local place = s.unlockPos
            if not place then
                return
            end
            local f = frame_fn()
            if f then
                local pt = place.point
                local px, py = place.x, place.y
                if centerShiftY and pt == "CENTER" and py then
                    py = py + centerShiftY()
                end
                local PPa = CludesUI and CludesUI.PP
                if PPa and px and py then
                    local es = f:GetEffectiveScale()
                    -- CENTER anchor with stored CENTER offsets: SnapCenterForDim with
                    -- the frame's actual size gives odd-pixel-dim frames the +0.5
                    -- center offset that lands edges on whole pixels. Plain SnapForES
                    -- forces edges to half pixels, drifting 1px on save/exit or spec swap.
                    local isCenterAnchor = (pt == "CENTER")
                        and (place.relPoint == "CENTER" or place.relPoint == nil)
                    if isCenterAnchor and PPa.SnapCenterForDim then
                        px = PPa.SnapCenterForDim(px, f:GetWidth() or 0, es)
                        py = PPa.SnapCenterForDim(py, f:GetHeight() or 0, es)
                    elseif PPa.SnapForES then
                        px = PPa.SnapForES(px, es)
                        py = PPa.SnapForES(py, es)
                    end
                end
                f:ClearAllPoints()
                f:SetPoint(pt, UIParent, place.relPoint or pt, px, py)
            end
        end
        return savePos, loadPos, clearPos, applyPos
    end

    local function Rebuild()
        ERB:ApplyAll()
    end
    -- A size from a width/height match or the mover: the unlock system's settle
    -- pass hands every matched bar its size again after each resize burst (CDM
    -- bars resize all through combat), and a rebuild is a full ApplyAll, so an
    -- unchanged size rebuilds nothing.
    local function SetDim(t, key, val)
        if t[key] == val then
            return
        end
        t[key] = val
        Rebuild()
    end
    local function LiveMove(key)
        if RefreshAnchoredBarsForUnlockTarget then
            RefreshAnchoredBarsForUnlockTarget(key)
        end
        -- A bar moved on its own: the "Border Around All" group re-judges.
        mod.ERB_GroupDirty()
    end

    local elements = {}

    -- Health Bar
    do
        local function S()
            return ERB.db.profile.health
        end
        -- Size callbacks use the spec-resolved config so matching lands where the
        -- bar renders; position always stays on S() (global).
        local function SS()
            return _G._CURB_ResolveHealthCfg() or S()
        end
        local save, load, clear, apply = MakePosHelpers(S, function()
            return health
        end, 0, -65)
        elements[#elements + 1] = MK({
            key = "ERB_Health",
            label = "Health Bar",
            group = "Resource Bars",
            order = 500,
            getFrame = function()
                return health
            end,
            isHidden = function()
                local s = S()
                return not s.enabled or IsSpecDisabled(s)
            end,
            -- Reported through the ON-SCREEN axes, not the stored ones: a vertical
            -- bar renders through OrientedSize, so stored width is what the player
            -- sees as height; handing the mover the raw stored pair would make it
            -- act on a bar that is still horizontal.
            getSize = function()
                local s, g = SS(), ERB.db.profile.general
                return OrientedSize(s.width, s.height, s.orientation or (g and g.orientation) or "HORIZONTAL")
            end,
            -- Stock styles: the frame drawn outside the fill (Classic WoW UI's
            -- vanilla frame, Blizzard Style's panel rim), so size matches line
            -- up with the frame on screen. Under the CludesUI look: a textured
            -- border's reach outside the bar (ns.ERB_EuiBorderPad), else nil.
            getMatchPad = function()
                local style = mod.ERB_BarsStyle()
                if style == "cui" then
                    local pw, ph = mod.ERB_EuiBorderPad(SS())
                    if pw then
                        return pw, ph
                    end
                end
                if style == "cui" then
                    return nil
                end
                local s, g = SS(), ERB.db.profile.general
                local ori = s.orientation or (g and g.orientation) or "HORIZONTAL"
                if style == "blizzard" then
                    return mod.ERB_BlizzMatchPad(IsVerticalOrientation(ori))
                end
                local wid, hgt = OrientedSize(s.width, s.height, ori)
                return mod.ERB_ClassicMatchPad(wid, hgt, IsVerticalOrientation(ori), mod.ERB_BarFrameK(s))
            end,
            setWidth = function(_, wid)
                local s, g = SS(), ERB.db.profile.general
                if IsVerticalOrientation(s.orientation or (g and g.orientation)) then
                    SetDim(s, "height", Pix.Snap(wid))
                else
                    SetDim(s, "width", Pix.Snap(wid))
                end
            end,
            setHeight = function(_, hgt)
                local s, g = SS(), ERB.db.profile.general
                if IsVerticalOrientation(s.orientation or (g and g.orientation)) then
                    SetDim(s, "width", Pix.Snap(hgt))
                else
                    SetDim(s, "height", Pix.Snap(hgt))
                end
            end,
            isAnchored = function()
                local s = S()
                return s.anchorTo and s.anchorTo ~= "none"
            end,
            keepMoverWhenAnchored = true,
            onLiveMove = LiveMove,
            savePos = save,
            loadPos = load,
            clearPos = clear,
            applyPos = apply,
        })
    end

    -- Power Bar
    do
        local function S()
            return ERB.db.profile.primary
        end
        local function SS()
            return _G._CURB_ResolvePowerCfg() or S()
        end
        -- Expand Power Bar if No Resource grows it toward the class resource slot.
        local save, load, clear, apply = MakePosHelpers(
            S,
            function()
                return primaryBar
            end,
            0,
            -74,
            function()
                return mod.ERB_PowerExpandShiftY or 0
            end
        )
        elements[#elements + 1] = MK({
            key = "ERB_Power",
            label = "Power Bar",
            group = "Resource Bars",
            order = 501,
            getFrame = function()
                return primaryBar
            end,
            isHidden = function()
                local s = S()
                return s.enabled == false or IsSpecDisabled(s)
            end,
            -- On-screen axes, as with the health bar above.
            getSize = function()
                local s, g = SS(), ERB.db.profile.general
                return OrientedSize(
                    s.width or 214,
                    s.height or 14,
                    s.orientation or (g and g.orientation) or "HORIZONTAL"
                )
            end,
            -- Stock styles: the frame outside the fill (see the health bar).
            getMatchPad = function()
                local style = mod.ERB_BarsStyle()
                if style == "cui" then
                    local pw, ph = mod.ERB_EuiBorderPad(SS())
                    if pw then
                        return pw, ph
                    end
                end
                if style == "cui" then
                    return nil
                end
                local s, g = SS(), ERB.db.profile.general
                local ori = s.orientation or (g and g.orientation) or "HORIZONTAL"
                if style == "blizzard" then
                    return mod.ERB_BlizzMatchPad(IsVerticalOrientation(ori))
                end
                local wid, hgt = OrientedSize(s.width or 214, s.height or 14, ori)
                return mod.ERB_ClassicMatchPad(wid, hgt, IsVerticalOrientation(ori), mod.ERB_BarFrameK(s))
            end,
            -- WoW Forever druid: the mover wraps the Mana Bar while Shapeshifted
            -- shown below the bar (CUI_ResourceBars_ForeverDruidMana.lua); nil
            -- on every other client and class.
            getBottomExtra = mod.FDM_BottomExtra,
            setWidth = function(_, wid)
                local s, g = SS(), ERB.db.profile.general
                if IsVerticalOrientation(s.orientation or (g and g.orientation)) then
                    SetDim(s, "height", Pix.Snap(wid))
                else
                    SetDim(s, "width", Pix.Snap(wid))
                end
            end,
            setHeight = function(_, hgt)
                local s, g = SS(), ERB.db.profile.general
                if IsVerticalOrientation(s.orientation or (g and g.orientation)) then
                    SetDim(s, "width", Pix.Snap(hgt))
                else
                    SetDim(s, "height", Pix.Snap(hgt))
                end
            end,
            isAnchored = function()
                local s = S()
                return s.anchorTo and s.anchorTo ~= "none"
            end,
            keepMoverWhenAnchored = true,
            onLiveMove = LiveMove,
            savePos = save,
            loadPos = load,
            clearPos = clear,
            applyPos = apply,
            -- Spec and Conditional Overrides layout layers bank and restore the
            -- STORED position through these: loadPos reports the expanded CENTER
            -- while Expand Power Bar if No Resource grows the bar, and a layer
            -- banking that would save the shift into the stored position.
            loadRawPos = function()
                local place = S().unlockPos
                if not (place and place.point) then
                    return nil
                end
                return {
                    point = place.point,
                    relPoint = place.relPoint or place.point,
                    x = place.x,
                    y = place.y,
                }
            end,
            saveRawPos = function(_, p)
                if not (p and p.point) then
                    return
                end
                S().unlockPos = { point = p.point, relPoint = p.relPoint or p.point, x = p.x, y = p.y }
                mod.ERB_GroupDirty()
            end,
        })
    end

    -- Class Resource (pips/runes)
    do
        local function S()
            return ERB.db.profile.secondary
        end
        local function SS()
            return _G._CURB_ResolveSecondaryCfg() or S()
        end
        local save, load, clear, apply = MakePosHelpers(S, function()
            return secondaryFrame
        end, 0, -38)
        elements[#elements + 1] = MK({
            key = "ERB_ClassResource",
            label = "Class Resource",
            group = "Resource Bars",
            order = 502,
            getFrame = function()
                return secondaryFrame
            end,
            -- On-screen axes. This bar's OWN orientation key (pipOrientation, no
            -- fallback to general) treats anything not HORIZONTAL as vertical in
            -- its renderer -- mirrored here so the mover and W/H match what is drawn.
            getSize = function()
                local s = SS()
                return OrientedSize(
                    s.pipWidth,
                    s.pipHeight,
                    (s.pipOrientation or "HORIZONTAL") ~= "HORIZONTAL" and "VERTICAL_UP" or "HORIZONTAL"
                )
            end,
            -- Stock styles: the frame outside the row (see the health bar).
            getMatchPad = function()
                local style = mod.ERB_BarsStyle()
                if style == "cui" then
                    local pw, ph = mod.ERB_EuiBorderPad(SS())
                    if pw then
                        return pw, ph
                    end
                end
                if style == "cui" then
                    return nil
                end
                local s = SS()
                local vertical = (s.pipOrientation or "HORIZONTAL") ~= "HORIZONTAL"
                if style == "blizzard" then
                    return mod.ERB_BlizzMatchPad(vertical)
                end
                local wid, hgt =
                    OrientedSize(s.pipWidth, s.pipHeight, vertical and "VERTICAL_UP" or "HORIZONTAL")
                return mod.ERB_ClassicMatchPad(wid, hgt, vertical, mod.ERB_BarFrameK(s))
            end,
            setWidth = function(_, wid)
                local s = SS()
                if (s.pipOrientation or "HORIZONTAL") ~= "HORIZONTAL" then
                    SetDim(s, "pipHeight", Pix.Snap(wid))
                else
                    SetDim(s, "pipWidth", Pix.Snap(wid))
                end
            end,
            setHeight = function(_, hgt)
                local s = SS()
                if (s.pipOrientation or "HORIZONTAL") ~= "HORIZONTAL" then
                    SetDim(s, "pipWidth", Pix.Snap(hgt))
                else
                    SetDim(s, "pipHeight", Pix.Snap(hgt))
                end
            end,
            isHidden = function()
                local s = S()
                return s.enabled == false or IsSpecDisabled(s)
            end,
            isAnchored = function()
                local s = S()
                return s.anchorTo and s.anchorTo ~= "none"
            end,
            keepMoverWhenAnchored = true,
            onLiveMove = LiveMove,
            savePos = save,
            loadPos = load,
            clearPos = clear,
            applyPos = apply,
        })
    end

    -- Cast Bar
    do
        local function S()
            return ERB.db.profile.castBar
        end
        local function castSave(key, anchorPoint, relPoint, posX, posY)
            if not anchorPoint then
                return
            end
            local cb = S()
            cb.unlockPos = { point = anchorPoint, relPoint = relPoint or anchorPoint, x = posX, y = posY }
            if not CludesUI._unlockActive and castBarFrame then
                castBarFrame:ClearAllPoints()
                castBarFrame:SetPoint(anchorPoint, UIParent, relPoint or anchorPoint, posX, posY)
            end
        end
        local function castLoad()
            local place = S().unlockPos
            if not place then
                return nil
            end
            local pt = place.point
            return { point = pt, relPoint = place.relPoint or pt, x = place.x, y = place.y }
        end
        local function castClear()
            local cb = S()
            cb.unlockPos = nil
            cb.anchorX = 0
            cb.anchorY = -54
        end
        local function castApply()
            local place = S().unlockPos
            if not place then
                return
            end
            if castBarFrame then
                local pt = place.point
                local sx, sy = SnapXY(place.x, place.y, castBarFrame, place)
                castBarFrame:ClearAllPoints()
                castBarFrame:SetPoint(pt, UIParent, place.relPoint or pt, sx, sy)
            end
        end
        elements[#elements + 1] = MK({
            key = "ERB_CastBar",
            label = "Cast Bar",
            group = "Resource Bars",
            order = 504,
            noAnchorTarget = true,
            getFrame = function()
                return castBarFrame
            end,
            getSize = function()
                local cb = S()
                return cb.width + mod.ERB_CastIconW(cb), cb.height
            end,
            -- Stock styles: the frame outside the bar. Classic WoW UI: the
            -- vanilla frame, icon included (it wraps bar and icon together).
            -- Blizzard Style: the stock frame 2px round the fill (on the
            -- icon's side it lands on the icon); the text box below is a
            -- label, not the frame (the mover wraps it through getBottomExtra).
            -- CludesUI look: the textured border round bar and icon.
            getMatchPad = function()
                local cs = mod.ERB_CastStyle()
                if cs == "classic" then
                    return mod.ERB_ClassicMatchPad(0, 0, false, mod.ERB_ClassicFrameK(S()))
                end
                if cs == "blizzard" and mod.ERB_BlizzAtlas("frame") then
                    return (mod.ERB_CastIconW(S()) > 0) and 2 or 4, 4
                end
                if cs == "cui" then
                    return mod.ERB_EuiBorderPad(S())
                end
                return nil
            end,
            -- Blizzard Style: the stock text box (and the icon spanning it)
            -- hang 13px below the bar; the mover wraps them. Classic WoW UI
            -- has no text box.
            getBottomExtra = function()
                local cb = S()
                if
                    mod.ERB_CastStyle() == "blizzard"
                    and cb.showSpellText
                    and mod.ERB_BlizzAtlas("textbox")
                then
                    return 13
                end
                return 0
            end,
            setWidth = function(_, wid)
                local cb = S()
                SetDim(cb, "width", Pix.Snap(math.max(wid - mod.ERB_CastIconW(cb), 10)))
            end,
            setHeight = function(_, hgt)
                SetDim(S(), "height", Pix.Snap(hgt))
            end,
            savePos = castSave,
            loadPos = castLoad,
            clearPos = castClear,
            applyPos = castApply,
        })
    end

    -- GCD Bar
    do
        local function S()
            return ERB.db.profile.gcdBar
        end
        local function gcdSave(key, anchorPoint, relPoint, posX, posY)
            if not anchorPoint then
                return
            end
            local g = S()
            g.unlockPos = { point = anchorPoint, relPoint = relPoint or anchorPoint, x = posX, y = posY }
            if not CludesUI._unlockActive and gcdBarFrame then
                gcdBarFrame:ClearAllPoints()
                gcdBarFrame:SetPoint(anchorPoint, UIParent, relPoint or anchorPoint, posX, posY)
            end
        end
        local function gcdLoad()
            local place = S().unlockPos
            if not place then
                return nil
            end
            local pt = place.point
            return { point = pt, relPoint = place.relPoint or pt, x = place.x, y = place.y }
        end
        local function gcdClear()
            local g = S()
            g.unlockPos = nil
            g.anchorX = 0
            g.anchorY = -78
        end
        local function gcdApply()
            local place = S().unlockPos
            if not place then
                return
            end
            if gcdBarFrame then
                local pt = place.point
                local sx, sy = SnapXY(place.x, place.y, gcdBarFrame, place)
                gcdBarFrame:ClearAllPoints()
                gcdBarFrame:SetPoint(pt, UIParent, place.relPoint or pt, sx, sy)
            end
        end
        elements[#elements + 1] = MK({
            key = "ERB_GCDBar",
            label = "GCD Bar",
            group = "Resource Bars",
            order = 506,
            noAnchorTarget = true,
            getFrame = function()
                return gcdBarFrame
            end,
            getSize = function()
                local g = S()
                return OrientedSize(g.width, g.height, g.orientation or "HORIZONTAL")
            end,
            -- The textured border's reach outside the bar (every look draws it).
            getMatchPad = function()
                return mod.ERB_EuiBorderPad(S())
            end,
            setWidth = function(_, wid)
                local g = S()
                if IsVerticalOrientation(g.orientation) then
                    SetDim(g, "height", Pix.Snap(math.max(wid, 4)))
                else
                    SetDim(g, "width", Pix.Snap(math.max(wid, 10)))
                end
            end,
            setHeight = function(_, hgt)
                local g = S()
                if IsVerticalOrientation(g.orientation) then
                    SetDim(g, "width", Pix.Snap(math.max(hgt, 10)))
                else
                    SetDim(g, "height", Pix.Snap(math.max(hgt, 4)))
                end
            end,
            savePos = gcdSave,
            loadPos = gcdLoad,
            clearPos = gcdClear,
            applyPos = gcdApply,
        })
    end

    -- Totem Bar
    do
        local function S()
            return ERB.db.profile.totemBar
        end
        local function totemSave(key, anchorPoint, relPoint, posX, posY)
            if not anchorPoint then
                return
            end
            local tb = S()
            tb.unlockPos = { point = anchorPoint, relPoint = relPoint or anchorPoint, x = posX, y = posY }
            if not CludesUI._unlockActive and totemBarFrame then
                totemBarFrame:ClearAllPoints()
                totemBarFrame:SetPoint(anchorPoint, UIParent, relPoint or anchorPoint, posX, posY)
            end
        end
        local function totemLoad()
            local place = S().unlockPos
            if not place then
                return nil
            end
            local pt = place.point
            return { point = pt, relPoint = place.relPoint or pt, x = place.x, y = place.y }
        end
        local function totemClear()
            S().unlockPos = nil
        end
        local function totemApply()
            local place = S().unlockPos
            if not place then
                return
            end
            if totemBarFrame then
                local pt = place.point
                local sx, sy = SnapXY(place.x, place.y, totemBarFrame, place)
                totemBarFrame:ClearAllPoints()
                totemBarFrame:SetPoint(pt, UIParent, place.relPoint or pt, sx, sy)
            end
        end
        elements[#elements + 1] = MK({
            key = "ERB_TotemBar",
            label = "Totem Bar",
            group = "Resource Bars",
            order = 505,
            noResize = true,
            noAnchorTarget = true,
            getFrame = function()
                return totemBarFrame
            end,
            getSize = function()
                local tb = S()
                local iconSz = tb.iconSize or 30
                local spacing = tb.spacing or 2
                -- Estimate extent based on max 5 totems; swap W/H when vertical
                local maxDim = iconSz * 5 + spacing * 4
                if tb.orientation == "VERTICAL" then
                    return iconSz, maxDim
                end
                return maxDim, iconSz
            end,
            savePos = totemSave,
            loadPos = totemLoad,
            clearPos = totemClear,
            applyPos = totemApply,
        })
    end

    -- Arcane Soul (Sunfury Arcane Mage): returns nil for every other class, so
    -- the mover only exists where the feature can.
    if mod.AS_MakeUnlockElement then
        elements[#elements + 1] = mod.AS_MakeUnlockElement(MK)
    end
    -- Swing Timer (WoW Forever): returns nil on clients without C_SwingTimer.
    if mod.ST_MakeUnlockElement then
        elements[#elements + 1] = mod.ST_MakeUnlockElement(MK, Rebuild)
    end
    -- Call Totem Bar (WoW Forever): nil elsewhere.
    if mod.CT_MakeUnlockElement then
        elements[#elements + 1] = mod.CT_MakeUnlockElement(MK)
    end

    CludesUI:RegisterUnlockElements(elements, "CludesUIResourceBars")
end

_G._CURB_RegisterUnlock = RegisterUnlockElements

-- Anchor resolution helper: returns the target frame for an anchorTo key, or nil.
local ERB_ANCHOR_FRAMES = {
    erb_classresource = function()
        return secondaryFrame
    end,
    erb_powerbar = function()
        return primaryBar
    end,
    erb_health = function()
        return health
    end,
    erb_castbar = function()
        return castBarFrame
    end,
    erb_gcdbar = function()
        return gcdBarFrame
    end,
    erb_cdm = function()
        return _G._CUCME_GetBarFrame and _G._CUCME_GetBarFrame("cooldowns")
    end,
    mouse = nil, -- handled separately
    partyframe = nil, -- handled separately
    playerframe = nil, -- handled separately
}

local ERB_VALID_ANCHORS = CludesUI.RESOURCE_BAR_ANCHOR_KEYS

local function ResolveAnchorFrame(anchorKey)
    local func = ERB_ANCHOR_FRAMES[anchorKey]
    if func then
        return func()
    end
    return nil
end

local function NormalizeAnchorKey(anchorKey)
    if anchorKey and ERB_VALID_ANCHORS[anchorKey] then
        return anchorKey
    end
    return "none"
end

-- Vertical "effective Y" of a bar from STORED config (screen up = +y). Needed
-- because a spec with no class resource never lays that frame out, so live
-- bounds (GetTop/GetCenter) are unavailable. Dragged bars store unlockPos as
-- CENTER/CENTER; free bars use offsetY relative to the centered mainFrame --
-- both CENTER-relative, so comparable.
local function BarEffectiveY(conf)
    if conf and conf.unlockPos and conf.unlockPos.point and conf.unlockPos.y then
        return conf.unlockPos.y
    end
    return (conf and conf.offsetY) or 0
end

-- "Expand Power Bar if No Resource" direction: the power bar fills the area the
-- absent class resource would occupy, growing TOWARD it. +1 = class resource
-- ABOVE -> grow up; -1 = below -> grow down. Pure read of stored config (no
-- writes, no live bounds), resolved even when the class resource is disabled so
-- expanding into a toggled-off/spec-disabled one grows the right way. Falls back
-- to +1 (default layout has it above) with no config or when co-located.
local function ResolveExpandDirSign(pp, sp)
    if not sp then
        return 1
    end
    -- Anchored: class resource pinned relative to the power bar.
    if NormalizeAnchorKey(sp.anchorTo) == "erb_powerbar" then
        if sp.anchorPosition == "bottom" then
            return -1
        end
        if sp.anchorPosition == "top" then
            return 1
        end
    end
    -- Anchored the other way: power bar pinned relative to the class resource.
    if NormalizeAnchorKey(pp.anchorTo) == "erb_classresource" then
        if pp.anchorPosition == "top" then
            return -1
        end -- power above CR -> CR below -> grow down
        if pp.anchorPosition == "bottom" then
            return 1
        end -- power below CR -> CR above -> grow up
    end
    -- Free / dragged: compare stored vertical positions.
    local sy, py = BarEffectiveY(sp), BarEffectiveY(pp)
    if sy > py then
        return 1
    elseif sy < py then
        return -1
    end
    return 1
end

-- ApplyBarAnchor args: frame to position; anchorKey = anchorTo value; anchorPos
-- "left"/"right"/"top"/"bottom"; offsetX/offsetY extra offsets; growthDir
-- "UP"/"DOWN"/"LEFT"/"RIGHT" from the anchor edge; growCentered true = centered
-- on the anchor edge midpoint, false = corner there.
-- SetFrameClickThrough recursively sets mouse passthrough on a frame and its
-- children, storing original state on first call so it can be restored.
local function SetFrameClickThrough(widget, clickThrough)
    if not widget then
        return
    end
    if clickThrough then
        -- Store original state if not already stored
        if widget._erbMouseWas == nil then
            widget._erbMouseWas = widget:IsMouseEnabled()
        end
        widget:EnableMouse(false)
        if widget.EnableMouseClicks then
            widget:EnableMouseClicks(false)
        end
        if widget.EnableMouseMotion then
            widget:EnableMouseMotion(false)
        end
    else
        -- Restore original state
        if widget._erbMouseWas ~= nil then
            widget:EnableMouse(widget._erbMouseWas)
            widget._erbMouseWas = nil
        end
    end
    for _, childFrame in ipairs({ widget:GetChildren() }) do
        SetFrameClickThrough(childFrame, clickThrough)
    end
end

local function ApplyBarAnchor(widget, anchorKey, anchorPos, offsetX, offsetY, growthDir, growCentered)
    -- Always clear any previous mouse-tracking OnUpdate
    if widget._erbMouseTrack then
        widget:SetScript("OnUpdate", nil)
        if widget._erbMouseShell then
            widget._erbMouseShell:SetScript("OnUpdate", nil)
            widget._erbMouseShell:Hide()
        end
        widget._erbMouseTrack = nil
        local g = ERB.db and ERB.db.profile and ERB.db.profile.general
        widget:SetFrameStrata(g and g.frameStrata or "MEDIUM")
        widget:SetFrameLevel(5)
        -- Restore mouse on frame and all children
        SetFrameClickThrough(widget, false)
        if widget.EnableMouseMotion then
            widget:EnableMouseMotion(true)
        end
    end

    if not anchorKey or anchorKey == "none" then
        return false
    end
    offsetX = offsetX or 0
    offsetY = offsetY or 0
    -- Snap offsets to physical pixel grid
    local PPa = CludesUI and CludesUI.PP
    if PPa and PPa.SnapForES then
        local es = widget:GetEffectiveScale()
        offsetX = PPa.SnapForES(offsetX, es)
        offsetY = PPa.SnapForES(offsetY, es)
    end
    anchorPos = anchorPos or "left"
    growthDir = growthDir or "UP"
    local centered = (growCentered ~= false)

    local function GetAnchorPoints()
        if anchorPos == "left" then
            return "RIGHT", "LEFT"
        elseif anchorPos == "right" then
            return "LEFT", "RIGHT"
        elseif anchorPos == "top" then
            return "BOTTOM", "TOP"
        elseif anchorPos == "bottom" then
            return "TOP", "BOTTOM"
        end
        return "LEFT", "RIGHT"
    end

    if anchorKey == "mouse" then
        -- Determine SetPoint anchor and directional nudge based on anchorPos
        local pointFrom, baseOX, baseOY
        if anchorPos == "left" then
            pointFrom = "RIGHT"
            baseOX = -15 + offsetX
            baseOY = offsetY
        elseif anchorPos == "right" then
            pointFrom = "LEFT"
            baseOX = 15 + offsetX
            baseOY = offsetY
        elseif anchorPos == "top" then
            pointFrom = "BOTTOM"
            baseOX = offsetX
            baseOY = 15 + offsetY
        elseif anchorPos == "bottom" then
            pointFrom = "TOP"
            baseOX = offsetX
            baseOY = -15 + offsetY
        else
            pointFrom = "LEFT"
            baseOX = 15 + offsetX
            baseOY = offsetY
        end
        widget:SetFrameStrata("TOOLTIP")
        widget:SetFrameLevel(9980)
        widget:ClearAllPoints()
        widget:SetPoint(pointFrom, UIParent, "BOTTOMLEFT", 0, 0)
        widget._erbMouseTrack = true
        -- Make frame and all children fully click-through while following cursor
        SetFrameClickThrough(widget, true)
        local lastMX, lastMY
        -- Cursor-follow runs per RENDER FRAME on a pool shell (bills ResourceBars via
        -- frame-birth attribution): a 60Hz anim ticker visibly steps against a gliding
        -- cursor since position has no engine easing. Kept cheap: raw-pixel early-out
        -- on unmoved frames, in-place SetPoint on moves.
        if not widget._erbMouseShell then
            widget._erbMouseShell = mod.TakeShell()
        end
        widget._erbMouseShell:Show()
        widget._erbMouseShell:SetScript("OnUpdate", function()
            local cx, cy = GetCursorPosition()
            if cx ~= lastMX or cy ~= lastMY then
                local firstMove = lastMX == nil
                lastMX, lastMY = cx, cy
                local s = UIParent:GetEffectiveScale()
                if firstMove then
                    widget:ClearAllPoints()
                end
                widget:SetPoint(
                    pointFrom,
                    UIParent,
                    "BOTTOMLEFT",
                    floor(cx / s + 0.5) + baseOX,
                    floor(cy / s + 0.5) + baseOY
                )
            end
        end)
        return true
    elseif anchorKey == "partyframe" then
        local partyFrame = CludesUI.FindPlayerPartyFrame()
        if not partyFrame then
            return false
        end
        local framePoint, targetPoint = GetAnchorPoints()
        widget:ClearAllPoints()
        widget:SetPoint(framePoint, partyFrame, targetPoint, offsetX, offsetY)
        return true
    elseif anchorKey == "playerframe" then
        local playerFrame = CludesUI.FindPlayerUnitFrame()
        if not playerFrame then
            return false
        end
        local framePoint, targetPoint = GetAnchorPoints()
        widget:ClearAllPoints()
        widget:SetPoint(framePoint, playerFrame, targetPoint, offsetX, offsetY)
        return true
    end

    local targetFrame = ResolveAnchorFrame(anchorKey)
    if not targetFrame or not targetFrame:IsShown() then
        return false
    end

    widget:ClearAllPoints()
    local framePoint, targetPoint = GetAnchorPoints()
    local success
    success = pcall(widget.SetPoint, widget, framePoint, targetFrame, targetPoint, offsetX, offsetY)
    return success or false
end

local UNLOCK_TARGET_TO_ERB_ANCHOR = {
    ERB_Health = "erb_health",
    ERB_Power = "erb_powerbar",
    ERB_ClassResource = "erb_classresource",
    ERB_CastBar = "erb_castbar",
    ERB_GCDBar = "erb_gcdbar",
}

local function GetAnchorOffsets(prefs)
    if not prefs then
        return 0, 0
    end
    local offsetX = prefs.anchorOffsetX
    if offsetX == nil then
        offsetX = prefs.anchorX
    end
    local offsetY = prefs.anchorOffsetY
    if offsetY == nil then
        offsetY = prefs.anchorY
    end
    return offsetX or 0, offsetY or 0
end

local function ApplyFreeBarPosition(widget, prefs, defaultX, defaultY, width, height)
    if not widget then
        return
    end

    local place = prefs and prefs.unlockPos
    widget:SetSize(width, height)
    widget:ClearAllPoints()

    if place and place.point then
        local sx, sy = SnapXY(place.x, place.y, widget, place)
        widget:SetPoint(place.point, UIParent, place.relPoint or place.point, sx, sy)
        return
    end

    widget:SetPoint(
        "CENTER",
        mainFrame,
        "CENTER",
        prefs.offsetX or defaultX or 0,
        prefs.offsetY or defaultY or 0
    )
end

local function ReapplyInternalBarAnchors()
    if not (ERB and ERB.db and ERB.db.profile) then
        return
    end

    local p = ERB.db.profile
    local anchoredBars = {
        { frame = health, settings = p.health },
        { frame = primaryBar, settings = p.primary },
        { frame = secondaryFrame, settings = p.secondary },
    }

    for _ = 1, 2 do
        for _, details in ipairs(anchoredBars) do
            local widget = details.frame
            local prefs = details.settings
            local anchorKey = prefs and prefs.anchorTo
            if
                widget
                and prefs
                and widget:IsShown()
                and anchorKey
                and anchorKey ~= "none"
                and ERB_ANCHOR_FRAMES[anchorKey]
            then
                local offsetX, offsetY = GetAnchorOffsets(prefs)
                ApplyBarAnchor(
                    widget,
                    anchorKey,
                    prefs.anchorPosition,
                    offsetX,
                    offsetY,
                    prefs.growthDirection,
                    prefs.growCentered
                )
            end
        end
    end
end

RefreshAnchoredBarsForUnlockTarget = function(unlockKey)
    local targetAnchor = UNLOCK_TARGET_TO_ERB_ANCHOR[unlockKey]
    if not (targetAnchor and ERB and ERB.db and ERB.db.profile) then
        return
    end

    local p = ERB.db.profile
    local barList = {
        { frame = health, settings = p.health },
        { frame = primaryBar, settings = p.primary },
        { frame = secondaryFrame, settings = p.secondary },
    }

    for _ = 1, 2 do
        for _, details in ipairs(barList) do
            local widget = details.frame
            local prefs = details.settings
            if widget and prefs and widget:IsShown() and prefs.anchorTo == targetAnchor then
                local offsetX, offsetY = GetAnchorOffsets(prefs)
                ApplyBarAnchor(
                    widget,
                    prefs.anchorTo,
                    prefs.anchorPosition,
                    offsetX,
                    offsetY,
                    prefs.growthDirection,
                    prefs.growCentered
                )
            end
        end
    end
end

Inner.ApplyBarAnchor, Inner.ApplyFreeBarPosition = ApplyBarAnchor, ApplyFreeBarPosition
Inner.GetAnchorOffsets, Inner.NormalizeAnchorKey = GetAnchorOffsets, NormalizeAnchorKey
Inner.ReapplyInternalBarAnchors = ReapplyInternalBarAnchors
Inner.RegisterUnlockElements, Inner.ResolveExpandDirSign = RegisterUnlockElements, ResolveExpandDirSign
Inner.broken = false
