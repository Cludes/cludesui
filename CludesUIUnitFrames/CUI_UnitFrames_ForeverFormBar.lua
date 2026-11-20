if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_UnitFrames_ForeverFormBar.lua  (WoW Forever only, druids only)
--
--  Power Type "Mana + Form Power" on the player frame: the power bar stays on
--  mana and a second bar shows the form's own power (Cat Form energy, Bear
--  Form rage) while the form runs on it. It is a child of the unit frame,
--  anchored to the power bar: an attached power bar sits in the frame's bar
--  clip (clipped to the frame box), which would cut off a bar outside it. It
--  hides and fades with the frame. The CludesUI look sets it against
--  the power bar on the side away from the health bar, sharing the border
--  line; a stock look (Blizzard, Classic, WoW Forever) sets it under the frame
--  art, lined up with the power bar. Texture, background, opacity and fill
--  direction follow the power bar; the fill is the form power's colour. Its
--  text follows the power bar's text settings (Power Text, Text Position and
--  its cog, Text Color) with the form's power; Smart shows the value.
--
--  The main file calls ns.UF_ForeverFormBar where the player power bar is
--  built and restyled; on every other client and class it stays nil.
--  Bottom-anchored player auras keep clear of the bar while it shows under
--  the frame (ns.UF_ForeverFormBarShown, read by the aura containers' bottom
--  reserve): each time it shows, hides or is laid out again, the bar asks
--  for one re-anchor on the next frame.
--  Cost: off = no frames, no events. On: UNIT_DISPLAYPOWER only, plus the
--  form power's events while the bar shows.
-------------------------------------------------------------------------------
local _, mod = ...
local CUI = _G.CludesUI
if not (CUI and CUI.IS_FOREVER) then
    return
end
local _, playerClass = UnitClass("player")
if playerClass ~= "DRUID" then
    return
end

local MANA = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
local WHITE = "Interface\\Buttons\\WHITE8X8"
local UnitPower, UnitPowerMax, UnitPowerType = UnitPower, UnitPowerMax, UnitPowerType

-- Event host at file scope, so its work bills Unit Frames.
local evf = CreateFrame("Frame")
-- bar (the StatusBar), settings (player settings as last applied), on (the
-- option is on and the power bar draws), live (form power events registered),
-- shown (the bar shows, as the aura reserve last heard),
-- pt / token (the form's power type as last read), text ("cur" / "pct" /
-- "both" while the text shows, else nil) with its format strings fmtPct and
-- fmtBoth (built per apply, so a paint builds no string).
local S = { on = false, live = false, shown = false }

local Secret = CUI.IsSecret

-- The bar while it shows, else nil: the bottom-anchored player auras reserve
-- the space it takes under the frame (CUI_UnitFrames_AuraContainers.lua).
function mod.UF_ForeverFormBarShown()
    if S.shown then
        return S.bar
    end
end

-- One re-anchor of the player auras on the next frame (a no-op unless they
-- are bottom-anchored).
local function Reanchor()
    if CUI.UF_RequestResourceReanchor then
        CUI.UF_RequestResourceReanchor()
    end
end

-- The form text's own setting; unset follows the power bar's.
local function FormVal(cfg, key, base, def)
    local val = cfg[key]
    if val == nil then
        val = cfg[base]
    end
    if val == nil then
        val = def
    end
    return val
end

local function Paint()
    local barFrame, pt = S.bar, S.pt
    if not (barFrame and pt) then
        return
    end
    barFrame:SetMinMaxValues(0, UnitPowerMax("player", pt))
    barFrame:SetValue(UnitPower("player", pt))
    local mode = S.text
    if mode == "cur" then
        barFrame.text:SetFormattedText("%d", UnitPower("player", pt))
    elseif mode == "pct" then
        barFrame.text:SetFormattedText(S.fmtPct, UnitPowerPercent("player", pt, true, CurveConstants.ScaleTo100))
    elseif mode == "curmax" then
        barFrame.text:SetFormattedText("%d / %d", UnitPower("player", pt), UnitPowerMax("player", pt))
    elseif mode == "both" then
        barFrame.text:SetFormattedText(
            S.fmtBoth,
            UnitPower("player", pt),
            UnitPowerPercent("player", pt, true, CurveConstants.ScaleTo100)
        )
    end
end

-- The form power's colour at Power Bar Opacity, and the power bar's background.
local function Color()
    local s, barFrame = S.settings, S.bar
    local details = S.token and CUI.GetPowerColor(S.token)
    local red, green, blue = 1, 1, 1
    if details then
        red, green, blue = details.r, details.g, details.b
    end
    local op = s.powerBarOpacity or 100
    if op <= 1.0 then
        op = op * 100
    end
    barFrame:SetStatusBarColor(red, green, blue, op / 100)
    -- Form Text Color: power-coloured takes the form's colour, else custom or
    -- white. Neither set follows the power bar's Text Color.
    local pc, tc = s.foreverFormTextPowerColor, s.foreverFormTextColor
    if pc == nil and tc == nil then
        pc, tc = s.powerPercentTextPowerColor, s.powerTextColor
    end
    if pc then
        barFrame.text:SetTextColor(red, green, blue)
    elseif tc then
        barFrame.text:SetTextColor(tc.r, tc.g, tc.b, tc.a or 1)
    else
        barFrame.text:SetTextColor(1, 1, 1)
    end
    if s.powerBgPowerColored then
        local frame = CUI.GetPowerBgDarkenFactor()
        barFrame.bg:SetColorTexture(red * frame, green * frame, blue * frame, 1)
    else
        local color = s.customPowerBgColor
        if color then
            barFrame.bg:SetColorTexture(color.r, color.g, color.b, 1)
        else
            barFrame.bg:SetColorTexture(17 / 255, 17 / 255, 17 / 255, 1)
        end
    end
end

local function SetLive(enabled)
    if S.live == enabled then
        return
    end
    S.live = enabled
    if enabled then
        evf:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
        evf:RegisterUnitEvent("UNIT_MAXPOWER", "player")
    else
        evf:UnregisterEvent("UNIT_POWER_FREQUENT")
        evf:UnregisterEvent("UNIT_MAXPOWER")
    end
end

-- Shows the bar while the form runs on a power other than mana. A secret
-- read keeps the last verdict. laidOut: the bar was just laid out, so a
-- shown bar may have moved.
local function Sync(laidOut)
    local barFrame = S.bar
    if not barFrame then
        return
    end
    local pt, token = UnitPowerType("player")
    if Secret(pt) or Secret(token) then
        if laidOut and S.shown then
            Reanchor()
        end
        return
    end
    local show = S.on and pt ~= MANA
    if show then
        S.pt, S.token = pt, token
        Color()
        Paint()
    end
    SetLive(show)
    barFrame:SetShown(show)
    if show ~= S.shown or (show and laidOut) then
        S.shown = show
        Reanchor()
    end
end

evf:SetScript("OnEvent", function(_, evt, _, token)
    if evt == "UNIT_DISPLAYPOWER" then
        Sync()
    elseif evt == "UNIT_MAXPOWER" or Secret(token) or token == S.token then
        Paint()
    end
end)

local function Build(widget)
    local barFrame = CreateFrame("StatusBar", nil, widget)
    barFrame:SetStatusBarTexture(WHITE)
    local backdrop = barFrame:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    barFrame.bg = backdrop
    -- Border on its own child frame (the canonical pattern).
    local bdr = CreateFrame("Frame", nil, barFrame)
    bdr:SetAllPoints(barFrame)
    CUI.PP.CreateBorder(bdr, 0, 0, 0, 1, 1)
    barFrame.border = bdr
    -- Text on a frame over the border.
    local tf = CreateFrame("Frame", nil, barFrame)
    tf:SetAllPoints(barFrame)
    barFrame.textFrame = tf
    barFrame.text = tf:CreateFontString(nil, "OVERLAY")
    barFrame.text:SetWordWrap(false)
    barFrame:Hide()
    S.bar = barFrame
end

-- The Form Power Text settings (format, position, size, offsets, percent
-- sign); each unset one follows the power bar's. Smart shows the value (form
-- power is never mana).
local function StyleText(s)
    local fontStr = S.bar.text
    local place = FormVal(s, "foreverFormTextPos", "powerPercentText", "none")
    local fmt = FormVal(s, "foreverFormTextFormat", "powerTextFormat", "perpp")
    if place == "none" or fmt == "none" then
        S.text = nil
        fontStr:Hide()
        return
    end
    S.text = (fmt == "curpp" or fmt == "smart") and "cur"
        or (fmt == "curmaxpp" and "curmax")
        or (fmt == "both" and "both")
        or "pct"
    local sign = (FormVal(s, "foreverFormShowPercent", "powerShowPercent", true) ~= false) and "%%" or ""
    S.fmtPct, S.fmtBoth = "%d" .. sign, "%d | %d" .. sign
    CUI.ApplyModuleFont(
        fontStr,
        nil,
        FormVal(s, "foreverFormTextSize", "powerPercentSize", 9),
        "unitFrames"
    )
    local ox = FormVal(s, "foreverFormTextX", "powerPercentX", 0)
    local oy = FormVal(s, "foreverFormTextY", "powerPercentY", 0)
    fontStr:ClearAllPoints()
    if place == "left" then
        fontStr:SetJustifyH("LEFT")
        fontStr:SetPoint("LEFT", S.bar, "LEFT", 2 + ox, oy)
    elseif place == "right" then
        fontStr:SetJustifyH("RIGHT")
        fontStr:SetPoint("RIGHT", S.bar, "RIGHT", -2 + ox, oy)
    else
        fontStr:SetJustifyH("CENTER")
        fontStr:SetPoint("CENTER", S.bar, "CENTER", ox, oy)
    end
    fontStr:Show()
end

-- Under the bars, every stock art ends at the power track's edge (vis.b is
-- the level badge's or portrait ring's, far lower). WoW Forever's track
-- has a rim below it, so the bar drops past that.
local FOREVER_RIM_DROP = 3

local function Layout(widget, power, cfg)
    local barFrame, Pix = S.bar, CUI.PP
    local place = mod.UF_PowerPos(cfg)
    local detached = (place == "detached_top" or place == "detached_bottom")
    -- A stock look draws an attached power bar inside its frame art.
    local G = (not detached) and mod.UF_Blizz() and mod.UF_BlizzGeom(widget)
    local bs, c, hgt
    -- Form Bar X / Y Offset (Power Type cog).
    local ox, oy = cfg.foreverFormBarX or 0, cfg.foreverFormBarY or 0
    barFrame:ClearAllPoints()
    if G and G.power and G.vis and G.h then
        -- Just under the art, lined up with the power bar.
        bs, hgt = 1, G.power.h
        local drop = mod.UF_Forever() and FOREVER_RIM_DROP or 0
        barFrame:SetPoint("TOPLEFT", power, "BOTTOMLEFT", ox, oy - drop)
        barFrame:SetPoint("TOPRIGHT", power, "BOTTOMRIGHT", ox, oy - drop)
    else
        -- Against the power bar, overlapping by the border so the two share
        -- one line: the frame's border on an attached bar, its own when detached.
        if detached then
            bs, c = cfg.powerBorderSize or 0, cfg.powerBorderColor
        else
            bs, c = cfg.borderSize or 1, cfg.borderColor
        end
        hgt = power:GetHeight()
        local overlap = bs * Pix.mult
        if place == "above" or place == "detached_top" then
            barFrame:SetPoint("BOTTOMLEFT", power, "TOPLEFT", ox, oy - overlap)
            barFrame:SetPoint("BOTTOMRIGHT", power, "TOPRIGHT", ox, oy - overlap)
        else
            barFrame:SetPoint("TOPLEFT", power, "BOTTOMLEFT", ox, oy + overlap)
            barFrame:SetPoint("TOPRIGHT", power, "BOTTOMRIGHT", ox, oy + overlap)
        end
    end
    barFrame:SetHeight(math.max(1, hgt or 1))
    local fillTex = power:GetStatusBarTexture()
    barFrame:SetStatusBarTexture((fillTex and fillTex:GetTexture()) or WHITE)
    -- Textured Background: as the power bar's (Color() paints it next).
    mod.UF_TexBgTint(barFrame.bg, power.bg and power.bg._cuiTexPath)
    barFrame:SetReverseFill(cfg.powerReverseFill and true or false)
    if bs > 0 then
        Pix.UpdateBorder(barFrame.border, bs, c and c.r or 0, c and c.g or 0, c and c.b or 0, 1)
        barFrame.border:Show()
    else
        barFrame.border:Hide()
    end
end

-- frame: the player frame; power: its power bar; s: the player settings.
function mod.UF_ForeverFormBar(widget, power, cfg)
    local shade = cfg and cfg.powerTypeOverride
    S.on = (power and shade and shade.foreverDruid and cfg.foreverFormBar and mod.UF_PowerBarDraws(cfg)) and true
        or false
    if not S.on then
        evf:UnregisterAllEvents()
        S.live = false
        if S.bar then
            S.bar:Hide()
        end
        if S.shown then
            S.shown = false
            Reanchor()
        end
        return
    end
    if not S.bar then
        Build(widget)
    end
    local barFrame = S.bar
    if barFrame:GetParent() ~= widget then
        barFrame:SetParent(widget)
    end
    -- The power bar's strata (a detached one can sit higher) and a level over it.
    barFrame:SetFrameStrata(power:GetFrameStrata())
    barFrame:SetFrameLevel(power:GetFrameLevel() + 1)
    barFrame.border:SetFrameLevel(barFrame:GetFrameLevel() + 5)
    barFrame.textFrame:SetFrameLevel(barFrame:GetFrameLevel() + 6)
    S.settings, S.frame, S.power = cfg, widget, power
    Layout(widget, power, cfg)
    StyleText(cfg)
    evf:RegisterUnitEvent("UNIT_DISPLAYPOWER", "player")
    Sync(true)
end

-- The form bar's own options re-apply only this bar: a full frame reload per
-- slider step visibly rebuilds the player frame.
function mod.UF_ForeverFormBarRelayout()
    if not (S.on and S.bar) then
        return
    end
    Layout(S.frame, S.power, S.settings)
    StyleText(S.settings)
    Sync(true)
end
