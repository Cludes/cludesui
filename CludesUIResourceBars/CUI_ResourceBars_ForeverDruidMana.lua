if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-- CUI_ResourceBars_ForeverDruidMana.lua
-- WoW FOREVER ONLY, DRUID ONLY: Mana Bar while Shapeshifted.
--
-- A thin mana bar attached to the Power Bar while the druid's form runs on
-- another power (Cat = energy, Bear = rage), so the mana pool stays in view.
-- It is a child of the Power Bar frame: it moves, fades, hides and
-- mouseover-reveals with it, and it is not an unlock element, an anchor target
-- or part of size matching. Below / Above sit it outside the bar's frame (a
-- vertical bar: right / left side), and elements linked to that side of the
-- Power Bar measure from this bar's far edge instead (anchor extent below);
-- Inside lays it over the bar's bottom edge (a vertical bar: its right edge),
-- above the fill and under the bar's text.
-- The look follows the Power Bar (texture, background, border, fill opacity,
-- orientation); the fill is the mana power colour.
--
-- Settings: profile.primary.foreverDruidMana, a table that exists only on
-- Forever (DEFAULTS in the main file). The main file calls ns.FDM_Apply at the
-- end of every BuildBars (settings applies, form changes, login) and
-- ns.FDM_Visibility from UpdateVisibility; on every other client and class
-- this file returns right below and both stay nil.
--
-- Cost: off = no frames, no events. On: UNIT_DISPLAYPOWER (form edges) only;
-- the mana events are registered only while this bar is shown and the Power
-- Bar can show, and a paint with unchanged mana and max does nothing. The
-- Power Bar's anchor links re-cascade only when this bar's edge changes.

local _, mod = ...
local CUI = _G.CludesUI

if not CUI.IS_FOREVER then return end
local _, playerClass = UnitClass("player")
if playerClass ~= "DRUID" then return end

local MANA = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
local WHITE = "Interface\\Buttons\\WHITE8x8"
local EMPTY = {}
local format, max = string.format, math.max
local UnitPower, UnitPowerMax = UnitPower, UnitPowerMax

-- Event host at FILE SCOPE (attribution rule, see _erbEventFrame in the main
-- file): its OnEvent work bills ResourceBars. The bar frames stay lazy.
local evf = CreateFrame("Frame")

-- pb (the Power Bar frame), host (outer frame: border + text), sb (inner
-- StatusBar), bg, border, textFrame, text; enabled (feature on, form event
-- registered), shown (the form wants this bar), pbVis (the Power Bar's
-- visibility pass lets it show), live (shown and pbVis: mana events
-- registered), cur / mx (last painted values), texPath (fill file last set),
-- textOn / fmt / suffix (text settings as last applied), extSide / extSig
-- (the Power Bar side this bar extends and its layout, nil for Inside),
-- extLast (the extent last cascaded); Powershifting: cost (the current form's
-- mana cost, nil = none or unreadable), cfg (the settings last applied), ori
-- (the bar's orientation), shiftTex / missTex / shifts (the cost mark, the
-- missing-mana mark and the shifts-left text).
local DruidMana = { enabled = false, shown = false, live = false, pbVis = true, parked = false }

-- Let the unit frame aura reserve see this bar when it floats below the stack
-- (CludesUI.ERB_PlayerStackBars consumes it; see CUI_UnitFrames_AuraContainers.lua).
-- Returns the host ONLY while it is shown for the current form, so the reserved
-- footprint tracks the form (not transient paint state) and is nil on every other
-- client/class and in the carve/inside modes that add no height below the frame.
mod._FDMStackBottomFrame = function()
    if DruidMana.shown and not DruidMana.parked and DruidMana.host then return DruidMana.host end
end

-------------------------------------------------------------------------------
--  Helpers
-------------------------------------------------------------------------------

-- Secret values throw on comparison and on truth tests: every API read passes
-- here before it is looked at.
local function Plain(val) return not (issecretvalue and issecretvalue(val)) end

-- The form's power is not mana. Asks the Power Bar's own resolver, so Power
-- Type "Mana" (the bar itself stays on mana) reads as mana here too. A
-- restricted answer keeps the last verdict.
local function FormWantsBar()
    local pt = _G._CURB_GetPrimaryPowerType()
    if not Plain(pt) then return DruidMana.shown end
    return type(pt) == "number" and pt ~= MANA
end

-- The mana colour from the Power Bar's palette (dark mode, overrides and
-- fallbacks included). Read per apply: the palette memo is wiped on edits.
local function ManaColor()
    local pc = _G._CURB_PowerColors[MANA]
    if pc then return pc[1], pc[2], pc[3] end
    return 1, 1, 1
end

-- Powershifting: the mana the current form's spell costs (shifting back into
-- it), nil out of a form or while the cost cannot be read.
local function ShiftCost()
    local index = GetShapeshiftForm()
    if not (Plain(index) and type(index) == "number" and index > 0) then return nil end
    local _, _, _, spellID = GetShapeshiftFormInfo(index)
    if not (Plain(spellID) and spellID and C_Spell and C_Spell.GetSpellPowerCost) then return nil end
    local costs = C_Spell.GetSpellPowerCost(spellID)
    if not Plain(costs) or type(costs) ~= "table" or (issecrettable and issecrettable(costs)) then return nil end
    for i = 1, #costs do
        local kind, amount = costs[i].type, costs[i].cost
        if not (Plain(kind) and Plain(amount)) then return nil end
        if kind == MANA and type(amount) == "number" and amount > 0 then return amount end
    end
    return nil
end

-- A mark over the bar from fraction `from` to `to` of its length, along the
-- fill's direction (a vertical bar grows up, or down when reversed).
local function PlaceMark(tex, from, to)
    local scrollBar = DruidMana.sb
    local ori = DruidMana.ori
    local vertical = ori == "VERTICAL_UP" or ori == "VERTICAL_DOWN"
    local len = vertical and scrollBar:GetHeight() or scrollBar:GetWidth()
    local size = len * (to - from)
    if not (len and len > 0) or size < 1 then
        tex:Hide()
        return
    end
    tex:ClearAllPoints()
    if not vertical then
        tex:SetPoint("TOPLEFT", scrollBar, "TOPLEFT", len * from, 0)
        tex:SetPoint("BOTTOMLEFT", scrollBar, "BOTTOMLEFT", len * from, 0)
        tex:SetWidth(size)
    elseif ori == "VERTICAL_DOWN" then
        tex:SetPoint("TOPLEFT", scrollBar, "TOPLEFT", 0, -len * from)
        tex:SetPoint("TOPRIGHT", scrollBar, "TOPRIGHT", 0, -len * from)
        tex:SetHeight(size)
    else
        tex:SetPoint("BOTTOMLEFT", scrollBar, "BOTTOMLEFT", 0, len * from)
        tex:SetPoint("BOTTOMRIGHT", scrollBar, "BOTTOMRIGHT", 0, len * from)
        tex:SetHeight(size)
    end
    tex:Show()
end

-- Powershifting paint, from plain mana (nil = unreadable: everything hides).
-- With a shift's worth or more, Shift Cost marks the end of the fill a shift
-- would spend; below it, Missing Mana marks what is still needed up to one
-- shift. Shifts Left counts the shifts the mana covers.
local function DrawShift(current, mx)
    local cfg, cost = DruidMana.cfg, DruidMana.cost
    local on = cfg and cfg.powershift ~= false and cost and current and mx and mx > 0
    local enough = on and current >= cost
    if enough and cfg.shiftMark ~= false then
        PlaceMark(DruidMana.shiftTex, math.max(current - cost, 0) / mx, current / mx)
    else
        DruidMana.shiftTex:Hide()
    end
    if on and not enough and cfg.warnLow ~= false then
        PlaceMark(DruidMana.missTex, current / mx, math.min(cost / mx, 1))
    else
        DruidMana.missTex:Hide()
    end
    if on and cfg.shiftsLeft ~= false then
        local n = math.floor(current / cost)
        DruidMana.shifts:SetText(n == 1 and CUI.L("1 shift") or CUI.Lf("%1$d shifts", n))
        DruidMana.shifts:Show()
    else
        DruidMana.shifts:Hide()
    end
end

-- BorderReach for a bar wearing the Power Bar's border settings: l, r, t, b
-- (nil for a border drawn inside the bar).
local function ReachOf(pp, es)
    local bs = pp.borderSize or 0
    local texture = pp.borderTexture or "solid"
    return CUI.BorderReach(
        bs,
        texture,
        pp.borderTextureOffset,
        pp.borderTextureOffsetY,
        pp.borderTextureShiftX,
        pp.borderTextureShiftY,
        "resourcebars",
        bs,
        CUI.BorderPx(pp.borderSizePx, bs, texture),
        nil,
        pp.borderA,
        es
    )
end

-- One side ("l" / "r" / "t" / "b") of a reach, 0 when drawn inside.
local function Side(side, left, right, top, bottom)
    if not left then return 0 end
    local val
    if side == "l" then
        val = left
    elseif side == "r" then
        val = right
    elseif side == "t" then
        val = top
    else
        val = bottom
    end
    return (val > 0) and val or 0
end

-- How far the Power Bar's frame reaches past the side this bar faces.
local function PowerBarReach(pp, place, pbSide, vertical, es)
    local style = mod.ERB_BarsStyle()
    if style == "blizzard" then
        -- The panel's opaque rim (ns.ERB_BlizzMatchPad): 2 above, 1 below,
        -- turned with a vertical bar to 2 left, 1 right. The panel's shadow
        -- draws under this bar.
        if not mod.ERB_BlizzMatchPad(vertical) then return 0 end
        return (place == "above") and 2 or 1
    elseif style == "classic" then
        -- The vanilla frame's whole reach, so its art never covers this bar;
        -- turned with a vertical bar like the art (top rim on the left).
        local CF = CUI.ClassicFrame
        return ((place == "above") and CF.OVER_T or CF.OVER_B) * mod.ERB_BarFrameK(pp)
    end
    local topY, bottom, leftX, right = mod.ERB_BorderExtents(pp)
    return Side(pbSide, ReachOf(pp, es)) + Side(pbSide, leftX, right, topY, bottom)
end

-- Inside: the Power Bar's hash-line inset (an exact solid border size, else
-- the step). The stock styles draw their frame outside the fill: none.
local function InsideInset(pp)
    if mod.ERB_BarsBlizz() then return 0 end
    local bs = pp.borderSize or 0
    local texture = pp.borderTexture
    if not texture or texture == "" or texture == "solid" then
        bs = CUI.BorderPx(pp.borderSizePx, bs, texture) or bs
    end
    return bs * CUI.PP.mult
end

-------------------------------------------------------------------------------
--  Paint
-------------------------------------------------------------------------------

-- Fill and text from live mana, in the Power Bar's text formats. force = the
-- look or the visibility just changed: repaint and snap (no ease). A
-- restricted read skips the clamp and the stamps and always rewrites.
local function DrawMana(force)
    local scrollBar = DruidMana.sb
    local current = UnitPower("player", MANA)
    local mx = UnitPowerMax("player", MANA)
    local curPlain, mxPlain = Plain(current), Plain(mx)
    if mxPlain and (type(mx) ~= "number" or mx <= 0) then return end
    if curPlain then
        if type(current) ~= "number" then return end
        if current < 0 then current = 0 end
    end
    if curPlain and mxPlain then
        if not force and current == DruidMana.cur and mx == DruidMana.mx then return end
        if force or mx ~= DruidMana.mx then scrollBar:SetMinMaxValues(0, mx) end
        DruidMana.cur, DruidMana.mx = current, mx
    else
        DruidMana.cur, DruidMana.mx = nil, nil
        scrollBar:SetMinMaxValues(0, mx)
    end
    -- Eases only while the Power Bar's Smooth Bars item is on (its _smoothing)
    local interp = curPlain and not force and DruidMana.pb and DruidMana.pb._smoothing
    if interp then
        scrollBar:SetValue(current, interp)
    else
        scrollBar:SetValue(current)
    end
    if curPlain and mxPlain then
        DrawShift(current, mx)
    else
        DrawShift(nil, nil)
    end

    if not DruidMana.textOn then return end
    local fmt = DruidMana.fmt
    -- A "smart" here reads as the value: WoW Forever has no Smart Text.
    local wantPct = fmt == "perpp" or fmt == "both"
    local txt
    if wantPct then
        -- Built only for a format that shows it.
        local pctRaw = UnitPowerPercent
                and UnitPowerPercent("player", MANA, true, CurveConstants and CurveConstants.ScaleTo100)
            or 0
        local percentText = format("%d", pctRaw) .. DruidMana.suffix
        txt = (fmt == "both") and (mod.AbbreviateNumbers(current) .. " | " .. percentText) or percentText
    elseif fmt == "curmaxpp" then
        txt = mod.AbbreviateNumbers(current) .. " / " .. mod.AbbreviateNumbers(UnitPowerMax("player", MANA))
    else
        txt = mod.AbbreviateNumbers(current)
    end
    DruidMana.text:SetText(txt)
end

-- Mana events only while this bar is shown and the Power Bar can show; the
-- edge into live repaints at once (mana moved while unregistered).
local function UpdateLive()
    local live = (DruidMana.shown and DruidMana.pbVis) and true or false
    if live == DruidMana.live then return end
    DruidMana.live = live
    if live then
        evf:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
        evf:RegisterUnitEvent("UNIT_MAXPOWER", "player")
        DrawMana(true)
    else
        evf:UnregisterEvent("UNIT_POWER_FREQUENT")
        evf:UnregisterEvent("UNIT_MAXPOWER")
    end
end

-- Elements linked to the Power Bar re-cascade only when the edge this bar
-- lends them changes (shown / hidden, side, size, gap, offsets): a rebuild
-- that leaves it in place schedules no anchor work. Unlock mode re-applies
-- every link on exit, so a change there only records.
local cascadeQueued = false
local function CascadeSettled()
    cascadeQueued = false
    if not CUI._unlockActive then CUI.PropagateAnchorChain("ERB_Power") end
end
local function ReportExtent()
    local sig = (DruidMana.shown and not DruidMana.parked and DruidMana.extSide) and DruidMana.extSig or nil
    if sig == DruidMana.extLast then return end
    DruidMana.extLast = sig
    if not CUI._unlockActive and CUI.PropagateAnchorChain then
        CUI.PropagateAnchorChain("ERB_Power")
        -- A form change cascades mid-rebuild, on the bars' old edges: once more settled.
        if not cascadeQueued then
            cascadeQueued = true
            C_Timer.After(0, CascadeSettled)
        end
    end
end

-- Form edge: show or hide for the form's power, then the event set.
local function Refresh()
    local isShown = DruidMana.enabled and FormWantsBar() or false
    if isShown ~= DruidMana.shown then
        DruidMana.shown = isShown
        DruidMana.host:SetShown(isShown)
    end
    -- A new form costs its own shift (Cat and Bear differ): repaint when live.
    local cost = isShown and ShiftCost() or nil
    local costChanged = cost ~= DruidMana.cost
    DruidMana.cost = cost
    local wasLive = DruidMana.live
    UpdateLive()
    if costChanged and wasLive and DruidMana.live then DrawMana(true) end
    ReportExtent()
end

evf:SetScript("OnEvent", function(_, evt, _, powerType)
    if evt == "UNIT_DISPLAYPOWER" then
        Refresh()
    elseif DruidMana.live then
        -- Energy and rage ticks share these events: mana only.
        if Plain(powerType) and powerType and powerType ~= "MANA" then return end
        DrawMana(false)
    end
end)

-------------------------------------------------------------------------------
--  Build / look
-------------------------------------------------------------------------------

-- The Power Bar's frame shape: outer frame (border + text, never clipped),
-- inner StatusBar inset a quarter pixel so the fill never bleeds past the
-- border, bg inside it. host._sb / host._bg are what ns.ApplyFillOpacity reads.
local function EnsureBuilt(pb)
    local owner = DruidMana.host
    if owner then
        if owner:GetParent() ~= pb then owner:SetParent(pb) end
        return
    end
    owner = CreateFrame("Frame", nil, pb)
    owner:Hide()
    local scrollBar = CreateFrame("StatusBar", nil, owner)
    local q = CUI.PP.mult * 0.25
    scrollBar:SetPoint("TOPLEFT", owner, "TOPLEFT", q, -q)
    scrollBar:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", -q, q)
    scrollBar:SetStatusBarTexture(WHITE)
    scrollBar:SetMinMaxValues(0, 1)
    scrollBar:SetValue(0)
    local backdrop = scrollBar:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    local border = CreateFrame("Frame", nil, owner)
    border:SetAllPoints(owner)
    local textFrame = CreateFrame("Frame", nil, owner)
    textFrame:SetAllPoints(owner)
    -- Font before any SetText ("Font not set" on the Forever client).
    local textValue = textFrame:CreateFontString(nil, "OVERLAY")
    mod.SetRBFont(textValue, mod.GetRBFont(), 8)
    textValue:SetWordWrap(false)
    -- Powershifting: the two marks over the fill, the shifts-left count at
    -- the bar's far end.
    local shiftTex = scrollBar:CreateTexture(nil, "ARTWORK", nil, 2)
    shiftTex:Hide()
    local missTex = scrollBar:CreateTexture(nil, "ARTWORK", nil, 2)
    missTex:Hide()
    local shifts = textFrame:CreateFontString(nil, "OVERLAY")
    mod.SetRBFont(shifts, mod.GetRBFont(), 8)
    shifts:SetWordWrap(false)
    shifts:SetPoint("RIGHT", owner, "RIGHT", -2, 0)
    shifts:Hide()
    DruidMana.shiftTex, DruidMana.missTex, DruidMana.shifts = shiftTex, missTex, shifts
    owner._sb, owner._bg = scrollBar, backdrop
    DruidMana.host, DruidMana.sb, DruidMana.bg, DruidMana.border, DruidMana.textFrame, DruidMana.text =
        owner, scrollBar, backdrop, border, textFrame, textValue
end

-- Levels, then position and size (sized before the border is styled: a
-- textured border set up on a 0x0 frame never paints). One level above the
-- Power Bar's fill: Inside draws over the fill, under the Power Bar's text
-- (25), the classic frame and a lifted border; Below / Above clear every
-- frame the Power Bar draws (reach below). Returns orientation, inside.
local function Layout(pb, pp, g, cfg)
    local Pix = CUI.PP
    local owner, bdr = DruidMana.host, DruidMana.border
    local base = pb._sb:GetFrameLevel() + 1
    owner:SetFrameLevel(base)
    DruidMana.sb:SetFrameLevel(base + 1)
    bdr:SetFrameLevel(pp.borderBehind and max(0, base - 1) or (base + 1))
    DruidMana.textFrame:SetFrameLevel(24)

    local es = pb:GetEffectiveScale()
    local ori = pp.orientation or g.orientation or "HORIZONTAL"
    local vertical = mod.IsVerticalOrientation(ori)
    local place = cfg.position
    if place ~= "above" and place ~= "inside" then place = "below" end
    local thick = Pix.SnapForES(max(cfg.height or 6, 1), es)
    local ox = Pix.SnapForES(cfg.offsetX or 0, es)
    local oy = Pix.SnapForES(cfg.offsetY or 0, es)

    owner:ClearAllPoints()
    if place == "inside" then
        local index = Pix.SnapForES(InsideInset(pp), es)
        -- Never thicker than the Power Bar's fill.
        local room = (vertical and pb:GetWidth() or pb:GetHeight()) - 2 * index
        if room > 0 and thick > room then thick = room end
        if vertical then
            owner:SetPoint("TOPRIGHT", pb, "TOPRIGHT", ox - index, oy - index)
            owner:SetPoint("BOTTOMRIGHT", pb, "BOTTOMRIGHT", ox - index, oy + index)
            owner:SetWidth(thick)
        else
            owner:SetPoint("BOTTOMLEFT", pb, "BOTTOMLEFT", ox + index, oy + index)
            owner:SetPoint("BOTTOMRIGHT", pb, "BOTTOMRIGHT", ox - index, oy + index)
            owner:SetHeight(thick)
        end
        DruidMana.extSide, DruidMana.extSig = nil, nil
        return ori, true
    end

    -- Gap = the space between the two bars' visible edges: the Power Bar's
    -- reach on the facing side and this bar's own border reach toward it are
    -- added to it. A vertical bar: Below = right side, Above = left side.
    local above = place == "above"
    local pbSide, ownSide
    if vertical then
        pbSide, ownSide = above and "l" or "r", above and "r" or "l"
    else
        pbSide, ownSide = above and "t" or "b", above and "b" or "t"
    end
    local skinData = Pix.SnapForES(
        max(cfg.gap or 2, 0) + PowerBarReach(pp, place, pbSide, vertical, es) + Side(ownSide, ReachOf(pp, es)),
        es
    )
    if vertical then
        if above then
            owner:SetPoint("TOPRIGHT", pb, "TOPLEFT", ox - skinData, oy)
            owner:SetPoint("BOTTOMRIGHT", pb, "BOTTOMLEFT", ox - skinData, oy)
        else
            owner:SetPoint("TOPLEFT", pb, "TOPRIGHT", ox + skinData, oy)
            owner:SetPoint("BOTTOMLEFT", pb, "BOTTOMRIGHT", ox + skinData, oy)
        end
        owner:SetWidth(thick)
    else
        if above then
            owner:SetPoint("BOTTOMLEFT", pb, "TOPLEFT", ox, oy + skinData)
            owner:SetPoint("BOTTOMRIGHT", pb, "TOPRIGHT", ox, oy + skinData)
        else
            owner:SetPoint("TOPLEFT", pb, "BOTTOMLEFT", ox, oy - skinData)
            owner:SetPoint("TOPRIGHT", pb, "BOTTOMRIGHT", ox, oy - skinData)
        end
        owner:SetHeight(thick)
    end
    -- The anchor side this bar extends past (NotifyExtent compares extSig).
    if vertical then
        DruidMana.extSide = above and "LEFT" or "RIGHT"
    else
        DruidMana.extSide = above and "TOP" or "BOTTOM"
    end
    DruidMana.extSig = format("%s:%s:%s:%s:%s", DruidMana.extSide, thick, skinData, ox, oy)
    return ori, false
end

-- The Power Bar's border settings in every style (a stock style's frame art
-- has no plain form, so this bar keeps the CludesUI border). Inside sits
-- within the Power Bar's own border and wears none.
local function ApplyBorder(pp, inside)
    local bdr = DruidMana.border
    -- Lost-rect recovery, see the cast bar border in the main file.
    if not bdr:GetLeft() then bdr:SetAllPoints(DruidMana.host) end
    if inside then
        CUI.ApplyBorderStyle(bdr, 0, 0, 0, 0, 0, "solid")
        return
    end
    local bs = pp.borderSize or 0
    local texture = pp.borderTexture or "solid"
    CUI.ApplyBorderStyle(
        bdr,
        bs,
        pp.borderR or 0,
        pp.borderG or 0,
        pp.borderB or 0,
        pp.borderA or 1,
        texture,
        pp.borderTextureOffset,
        pp.borderTextureOffsetY,
        pp.borderTextureShiftX,
        pp.borderTextureShiftY,
        "resourcebars",
        bs,
        nil,
        CUI.BorderPx(pp.borderSizePx, bs, texture)
    )
    -- The strip container was levelled off the border frame when it was made.
    local edges = CUI.PP.GetBorders(bdr)
    if edges then edges:SetFrameLevel(bdr:GetFrameLevel() + 1) end
end

-- Orientation, the Power Bar's fill texture (the plain user texture under
-- every style), the mana fill, the Power Bar's background and fill opacity.
-- Returns the mana colour for the text.
local function ApplyLook(pp, g, profile, ori)
    local scrollBar = DruidMana.sb
    if ori == "VERTICAL_UP" or ori == "VERTICAL_DOWN" then
        scrollBar:SetOrientation("VERTICAL")
        scrollBar:SetRotatesTexture(true)
        scrollBar:SetReverseFill(ori == "VERTICAL_DOWN")
    else
        scrollBar:SetOrientation("HORIZONTAL")
        scrollBar:SetRotatesTexture(false)
        scrollBar:SetReverseFill(false)
    end
    local filePath = CUI.ResolveTexturePath(
        _G._CURB_BarTextures,
        (profile.splitTex == true and pp.barTexture) or g.barTexture or "none",
        WHITE
    )
    if filePath ~= DruidMana.texPath then
        DruidMana.texPath = filePath
        scrollBar:SetStatusBarTexture(filePath)
        -- A new file resets the vertex colour: drop the fill memo so the
        -- paint below lands.
        local ft = scrollBar:GetStatusBarTexture()
        if ft then
            ft._lfOn, ft._lgOn = nil, nil
        end
    end
    local red, green, blue = ManaColor()
    mod.ApplyBarFlat(scrollBar:GetStatusBarTexture(), red, green, blue, 1)
    DruidMana.bg:SetColorTexture(pp.bgR or 0, pp.bgG or 0, pp.bgB or 0, pp.bgA or 0.75)
    -- Textured Background, as the Power Bar's: flat while Fill Color is below 100.
    if g.barTextureBg or DruidMana.bg._erbBgTex then
        mod.ERB_BgTexture(
            DruidMana.bg,
            g.barTextureBg and (pp.fillOpacity or 100) >= 100 and filePath,
            pp.bgR or 0,
            pp.bgG or 0,
            pp.bgB or 0,
            pp.bgA or 0.75
        )
    end
    mod.ApplyFillOpacity(DruidMana.host, ori, pp.fillOpacity)
    return red, green, blue
end

-- Text style, same keys and colour rule as the Power Bar's text (custom, or
-- the power colour: here mana's).
local function ApplyText(cfg, red, green, blue)
    local fontStr = DruidMana.text
    mod.SetRBFont(fontStr, mod.GetRBFont(), cfg.textSize or 8)
    fontStr:ClearAllPoints()
    local a = cfg.textAnchor or "CENTER"
    fontStr:SetPoint(a, DruidMana.host, a, cfg.textXOffset or 0, cfg.textYOffset or 0)
    if cfg.textCustomColored == false then
        fontStr:SetTextColor(red, green, blue, 1)
    else
        fontStr:SetTextColor(cfg.textFillR or 1, cfg.textFillG or 1, cfg.textFillB or 1, cfg.textFillA or 1)
    end
    local fmt = cfg.textFormat or "none"
    DruidMana.fmt = fmt
    DruidMana.suffix = (cfg.showPercent == false) and "" or "%"
    DruidMana.textOn = fmt ~= "none"
    fontStr:SetShown(DruidMana.textOn)
end

-- Off: every event dropped, the bar hidden and its anchor extent handed back.
local function Teardown()
    if not DruidMana.enabled then return end
    DruidMana.enabled, DruidMana.shown, DruidMana.live = false, false, false
    DruidMana.cur, DruidMana.mx, DruidMana.cost = nil, nil, nil
    evf:UnregisterAllEvents()
    DruidMana.host:Hide()
    ReportExtent()
end

-------------------------------------------------------------------------------
--  Entry points (main file)
-------------------------------------------------------------------------------

-- End of every BuildBars: full restyle from settings, then show / hide for
-- the form. pb / pp / g = the Power Bar frame, its resolved settings and the
-- general settings; each falls back to a lookup when omitted.
function mod.FDM_Apply(pb, pp, g)
    local ERB = mod.ERB
    local profile = ERB.db and ERB.db.profile
    if not profile then return end
    pb = pb or DruidMana.pb or _G.ERB_PrimaryBar
    pp = pp or _G._CURB_ResolvePowerCfg(profile)
    local c = pp and pp.foreverDruidMana
    -- Power Type "Mana" keeps the Power Bar itself on mana: nothing to add.
    local shade = profile.primary and profile.primary.powerTypeOverride
    if not (pb and c and c.enabled and pp.enabled ~= false) or (shade and shade.foreverDruid) then
        Teardown()
        return
    end
    DruidMana.pb = pb
    EnsureBuilt(pb)
    if not DruidMana.enabled then
        DruidMana.enabled = true
        evf:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
    end
    g = g or profile.general or EMPTY
    local ori, inside = Layout(pb, pp, g, c)
    ApplyBorder(pp, inside)
    local red, green, blue = ApplyLook(pp, g, profile, ori)
    ApplyText(c, red, green, blue)
    -- Powershifting look: its two mark colours and the count in the text's size.
    DruidMana.cfg, DruidMana.ori = c, ori
    DruidMana.shiftTex:SetColorTexture(c.shiftR or 0.94, c.shiftG or 0.54, c.shiftB or 0.14, 1)
    DruidMana.missTex:SetColorTexture(c.missR or 0.9, c.missG or 0.15, c.missB or 0.15, 1)
    mod.SetRBFont(DruidMana.shifts, mod.GetRBFont(), c.textSize or 8)
    local wasLive = DruidMana.live
    Refresh()
    -- Already live: the new look and text settings paint now (an edge into
    -- live painted in UpdateLive).
    if wasLive and DruidMana.live then DrawMana(true) end
end

-- The Power Bar's visibility pass (vis = true / "mouseover" / false / nil).
-- Tracked while off too, so an enable knows the current state. Alpha and
-- fades need nothing here: this bar is the Power Bar's child.
function mod.FDM_Visibility(vis)
    local on = (vis == true or vis == "mouseover")
    if on == DruidMana.pbVis then return end
    DruidMana.pbVis = on
    if DruidMana.enabled then UpdateLive() end
end

-- The bar frame while it is shown for the current form (Show When Missing).
function mod.FDM_Host() return DruidMana.shown and DruidMana.host or nil end

-- Show When Energy Missing parks this bar out of sight while the Power Bar is
-- revealed (main file, ns.ERB_MissingHost): its edge goes back to the elements
-- below for that time.
function mod.FDM_Parked(parked)
    parked = parked and true or false
    if parked == DruidMana.parked then return end
    DruidMana.parked = parked
    ReportExtent()
end

-- Anchor-target edge for the unlock anchor system: while this bar shows
-- Below / Above the Power Bar, an element linked to that side of "ERB_Power"
-- measures from this bar's far edge, so a form change moves it clear of the
-- mana bar instead of leaving it overlapped. The Power Bar keeps its own
-- edges everywhere else. Live in unlock mode too, so a linked element's mover
-- stays clear of the bar and a drag measures from the same edge (Below: the
-- Power Bar's mover wraps this bar, ns.FDM_BottomExtra). Chained in front of
-- any provider installed before this file loaded.
local prevExtent = CUI._GetAnchorTargetExtent
CUI._GetAnchorTargetExtent = function(targetKey, side)
    if
        targetKey == "ERB_Power"
        and DruidMana.shown
        and not DruidMana.parked
        and side == DruidMana.extSide
    then
        local owner, pb = DruidMana.host, DruidMana.pb
        local val, pv
        if side == "BOTTOM" then
            val, pv = owner:GetBottom(), pb:GetBottom()
        elseif side == "TOP" then
            val, pv = owner:GetTop(), pb:GetTop()
        elseif side == "LEFT" then
            val, pv = owner:GetLeft(), pb:GetLeft()
        else
            val, pv = owner:GetRight(), pb:GetRight()
        end
        if val and pv then
            -- Only ever outward: an offset that tucks it back toward the
            -- Power Bar leaves the Power Bar's edge in charge.
            if side == "BOTTOM" or side == "LEFT" then
                if pv < val then val = pv end
            elseif pv > val then
                val = pv
            end
            return val * owner:GetEffectiveScale() / UIParent:GetEffectiveScale()
        end
    end
    if prevExtent then return prevExtent(targetKey, side) end
    return nil
end

-- Unlock mode: the Power Bar's getBottomExtra (main file). While this bar
-- shows Below a horizontal Power Bar, the mover grows down to wrap it, to
-- the same edge linked elements measure from; 0 otherwise. Power Bar units
-- (this bar is its child: one scale).
function mod.FDM_BottomExtra()
    if not (DruidMana.shown and not DruidMana.parked and DruidMana.extSide == "BOTTOM") then return 0 end
    local hb, pb = DruidMana.host:GetBottom(), DruidMana.pb:GetBottom()
    if not (hb and pb) or hb >= pb then return 0 end
    return pb - hb
end
