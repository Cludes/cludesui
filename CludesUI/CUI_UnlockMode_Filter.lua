if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_UnlockMode_Filter.lua
--  Unlock Mode element filter: a funnel icon and a box right of the top
--  banner's logo, Snap Elements moved to its left; the banner grows on both
--  sides to make room (its art is drawn in slices that stretch only the
--  plain bar, the logo stays whole) and stays on screen with - and +.
--  Typing hides every overlay whose name lacks one of the typed words; the
--  real frames are never touched. Not saved: hiding the banner clears it.
--  Loaded after CUI_UnlockMode_Session.lua; _unlockCoreInit runs it once with UM.
-------------------------------------------------------------------------------
local _, CUI_NS = ...
CUI_NS = CUI_NS.__cuiCoreNS or CUI_NS  -- standalone builds: the core's own table (CludesUI.lua)
CUI_NS.unlockParts = CUI_NS.unlockParts or {}

-- Filter text -> lower-case words, nil when there are none.
local function ParseFilter(text)
    if type(text) ~= "string" then return nil end
    local words
    for w in text:lower():gmatch("%S+") do
        words = words or {}
        words[#words + 1] = w
    end
    return words
end

local function HasAllWords(words, name)
    if type(name) ~= "string" or name == "" then return false end
    name = name:lower()
    for i = 1, #words do
        if not name:find(words[i], 1, true) then return false end
    end
    return true
end

-- True when the filter keeps an element: no words, or every word (a plain
-- substring, any case) in its label or in the label as shown (translated).
local function FilterKeeps(words, label)
    if not words then return true end
    if HasAllWords(words, label) then return true end
    local shown = CludesUI.L(label)
    return shown ~= label and HasAllWords(words, shown) or false
end

-- The bar's base width (CreateHUD's frame, before Layout widens it) and the
-- drawn bar's parts (DrawBanner): its height, and the logo badge hung from
-- its centre, which the open animation's logo flies into (its centre BADGE_Y
-- below the top of the bar, its logo BADGE_LOGO wide).
local BANNER_W = 1144
local BAR_H, BADGE, BADGE_TOP, BADGE_LOGO = 58, 56, 8, 38
local LOGO_TEX = "Interface\\AddOns\\CludesUI\\media\\logo-full-thin.png"
local FILTER_ICON = "Interface\\AddOns\\CludesUI\\media\\icons\\filter.png"
-- The bar's own numbers (toggle edges and gaps, the clearance before Exit /
-- Save & Exit, the - and + reach, the scale range) come from CreateHUD
-- (CUI_UnlockMode_Session.lua) as hud._hudLayout.
local ICON_SZ, BOX_GAP = 28, 6
local BOX_MIN, BOX_MAX = 100, 200
local ALPHA_OFF, ALPHA_ON, ALPHA_HOVER = 0.30, 0.60, 0.9  -- as the bar's toggles

CUI_NS.unlockParts.Filter = function(UM)
local movers, blizzOverlays = UM.movers, UM._blizzOwnedOverlays

local words, lastKey = nil, ""

local function Hides(key)
    return words ~= nil and not FilterKeeps(words, UM.GetBarLabel(key))
end
UM.FilterHides = Hides  -- ghost sync (CUI_UnlockMode_Positions.lua)

-- Mover OnShow hook (CreateMover): every show path ends here.
function UM.FilterOnShow(m)
    if words and Hides(m._barKey) then m:Hide() end
end

-- As the Shift+Right Click hide, without its session flag.
local function HideMover(m)
    m._hoverPending = false
    if UM.selectedMover == m then UM.DeselectMover() end
    if UM.hoveredMover == m then UM.hoveredMover = nil end
    if m._hideOverlayText then m._hideOverlayText() end
    if m._cogBtn then m._cogBtn:Hide() end
    m:Hide()
end

local function Apply()
    if not UM.isUnlocked then return end
    -- A pick mode survives the filter (it helps find the target) unless its own mover hides.
    if UM.pickModeMover and UM.pickMode and Hides(UM.pickModeMover._barKey) then UM.CancelPickMode() end
    if UM.selectElementPicker and Hides(UM.selectElementPicker._barKey) then UM.CancelPickMode() end
    local alpha = UM.darkOverlaysEnabled and 1 or UM.MOVER_ALPHA
    for _, m in pairs(movers) do
        if Hides(m._barKey) then
            if m:IsShown() then HideMover(m) end
        elseif not m:IsShown() and not m._tempHidden then
            m:Sync()
            if m:IsShown() then m:SetAlpha(alpha) end
        end
    end
    for label, ov in pairs(blizzOverlays) do
        if words and not FilterKeeps(words, label) then
            if ov:IsShown() then
                ov._forceCollapse()
                ov:Hide()
                ov._filterHidden = true
            end
        elseif ov._filterHidden then
            ov._filterHidden = nil
            if not ov._tempHidden then ov:SetAlpha(1); ov:Show() end
        end
    end
    -- Ghosts hide themselves in their sync; a refresh brings the kept ones back.
    if CludesUI._RefreshFallbackGhosts then CludesUI._RefreshFallbackGhosts() end
    if CludesUI._RefreshOverrideGhosts then CludesUI._RefreshOverrideGhosts() end
    -- Resting alpha: one hidden during the open fade-in missed its ramp (a running fade resets it).
    if CludesUI._SetFallbackGhostsAlpha then CludesUI._SetFallbackGhostsAlpha(1) end
    if CludesUI._SetOverrideGhostsAlpha then CludesUI._SetOverrideGhostsAlpha(1) end
end

-- The bar, drawn in code: a dark plate the bar's width with square ends, an
-- accent line along its bottom edge with a soft glow under it, and the
-- CludesUI logo on a square badge that hangs over that line at the centre.
-- Every part is anchored to the bar's edges, so it follows Layout's width.
-- Spec-override sessions paint it gold (UM.PaintBanner).
local function DrawBanner(hud)
    local plate = hud:CreateTexture(nil, "BACKGROUND")
    plate:SetPoint("TOPLEFT")
    plate:SetPoint("TOPRIGHT")
    plate:SetHeight(BAR_H)
    plate:SetColorTexture(0.035, 0.043, 0.052, 0.94)
    local sheen = hud:CreateTexture(nil, "BACKGROUND", nil, 1)
    sheen:SetAllPoints(plate)
    sheen:SetColorTexture(1, 1, 1, 1)
    sheen:SetGradient("VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 0.04))
    local line = hud:CreateTexture(nil, "ARTWORK", nil, 2)
    line:SetPoint("TOPLEFT", 0, -(BAR_H - 2))
    line:SetPoint("TOPRIGHT", 0, -(BAR_H - 2))
    line:SetHeight(2)
    local glow = hud:CreateTexture(nil, "ARTWORK", nil, 1)
    glow:SetPoint("TOPLEFT", 0, -BAR_H)
    glow:SetPoint("TOPRIGHT", 0, -BAR_H)
    glow:SetHeight(14)
    glow:SetColorTexture(1, 1, 1, 1)
    local lEdge = hud:CreateTexture(nil, "ARTWORK", nil, 2)
    lEdge:SetPoint("TOPLEFT")
    lEdge:SetSize(2, BAR_H)
    local rEdge = hud:CreateTexture(nil, "ARTWORK", nil, 2)
    rEdge:SetPoint("TOPRIGHT")
    rEdge:SetSize(2, BAR_H)

    local badge = CreateFrame("Frame", nil, hud)
    badge:SetSize(BADGE, BADGE)
    badge:SetPoint("TOP", hud, "TOP", 0, -BADGE_TOP)
    badge:SetFrameLevel(hud:GetFrameLevel() + 1)
    local bbg = badge:CreateTexture(nil, "BACKGROUND")
    bbg:SetAllPoints()
    bbg:SetColorTexture(0.05, 0.062, 0.075, 1)
    local bbrd = CludesUI.MakeRoundedBorder(badge, 1, 1, 1, 1, bbg, 2)
    hud._outlines[#hud._outlines + 1] = bbrd
    local logo = badge:CreateTexture(nil, "ARTWORK")
    logo:SetSize(BADGE_LOGO, BADGE_LOGO)
    logo:SetPoint("CENTER")
    logo:SetTexture(LOGO_TEX)
    hud._badgeLogo = logo
    hud._badgeY, hud._badgeLogoSz = BADGE_TOP + BADGE / 2, BADGE_LOGO

    local function Paint(r, g, b)
        line:SetColorTexture(r, g, b, 0.9)
        glow:SetGradient("VERTICAL", CreateColor(r, g, b, 0), CreateColor(r, g, b, 0.22))
        lEdge:SetColorTexture(r, g, b, 0.5)
        rEdge:SetColorTexture(r, g, b, 0.5)
        bbrd:SetColor(r, g, b, 0.85)
        logo:SetVertexColor(r, g, b, 1)
    end
    function UM.PaintBanner(special)
        if special then Paint(1, 0.82, 0.30); return end
        local c = CludesUI.CLUDES_GREEN
        Paint(c.r, c.g, c.b)
    end
    UM.PaintBanner(CludesUI._specialUnlockGroup)
    CludesUI.RegAccent({ type = "callback", fn = function() UM.PaintBanner(CludesUI._specialUnlockGroup) end })
end

-- Sizes the box and the banner for a half screen width V (banner units at
-- banner scale 100%, nil = no limit) and returns the half width the banner
-- then needs: its own width or its - and + buttons, whichever
-- reaches farther. Exit and Save & Exit sit at the default inset (BuildFilter);
-- the box evens out the two halves, those buttons included, so both keep the
-- toggles' own gap to the chains, and the banner grows until they do.
-- When that does not fit: the box shrinks to BOX_MIN, then the gap to the
-- minimum clearance.
local function Layout(hud, frame, V)
    local L = hud._hudLayout
    local half = BANNER_W / 2
    local wS, wC, wH = hud._magnetBtn:GetWidth(), hud._coordBtn:GetWidth(), hud._hoverBtn:GetWidth()
    local left = -L.upLeft + wS + hud._gridBtn:GetWidth() + hud._darkOverlayBtn:GetWidth()
        + hud._flashBtn:GetWidth() + 3 * L.gapL
    local fixed = L.upRight + ICON_SZ + BOX_GAP + L.gapL + wC + L.gapL + wH + L.gapL + hud._infoBtn:GetWidth()
    local exitW, saveW, edgeIn = hud._exitBtn:GetWidth(), hud._saveBtn:GetWidth(), L.edgeIn
    local function Outer(e) return math.max(half + e, half + e - edgeIn + L.scaleBtnReach) end
    local function Need(boxW, gap)
        return math.max(0, left + gap + exitW + edgeIn - half, fixed + boxW + gap + saveW + edgeIn - half)
    end
    local boxW = math.max(BOX_MIN, math.min(BOX_MAX, math.floor(left + exitW - saveW - fixed + 0.5)))
    local e = Need(boxW, L.gapL)
    if V and Outer(math.ceil(e)) > V then
        boxW = BOX_MIN
        e = Need(boxW, L.gapL)
        if Outer(math.ceil(e)) > V then e = Need(boxW, L.clear) end
    end
    e = math.ceil(e)
    hud:SetWidth(BANNER_W + 2 * e)
    frame:SetWidth(boxW)
    return Outer(e)
end

-- Keeps the banner and its - and + on screen: a banner scale that no longer
-- fits (a smaller screen) shows at the largest step that does, without saving
-- it, and CreateHUD greys + where the next step would not fit (its scale cap).
local function MakeFit(hud, frame)
    local L = hud._hudLayout
    local s0 = CludesUIDB and CludesUIDB.unlockBannerScale or L.scaleMin
    local base = hud:GetScale() / math.max(L.scaleMin, math.min(L.scaleMax, s0))  -- scale at 100%
    return function()
        local V = GetScreenWidth() / (2 * base)
        local fitMax = V / Layout(hud, frame, V)
        local s = hud:GetScale() / base
        local target = s
        if s > math.max(L.scaleMin, fitMax) + 0.001 then
            target = math.max(L.scaleMin, math.floor(fitMax / L.scaleStep + 0.001) * L.scaleStep)
        end
        hud._setScaleCap(fitMax)
        if target ~= s then hud._applyBannerScale(target, true) end
    end
end

-- Called by CreateHUD with the banner and the toggles' vertical center.
-- Left of the logo: Exit, Cursor Light, Dark Overlays, Grid Lines and Snap
-- Elements (moved over); right of it: the funnel, the box, Coordinates,
-- Hover Top Bar and Save & Exit.
function UM.BuildFilter(hud, centerY)
    DrawBanner(hud)
    local L = hud._hudLayout
    local FONT_PATH = UM.FONT_PATH
    local BR, BG, BB = CludesUI.BORDER_R, CludesUI.BORDER_G, CludesUI.BORDER_B

    -- Snap Elements next to the logo's left side, its label outside like the other left toggles.
    local snap = hud._magnetBtn
    snap:ClearAllPoints()
    snap:SetPoint("RIGHT", hud, "TOP", L.upLeft, centerY)
    snap._tex:ClearAllPoints()
    snap._tex:SetPoint("RIGHT", snap, "RIGHT", 0, 0)
    snap._label:ClearAllPoints()
    snap._label:SetPoint("RIGHT", snap._tex, "LEFT", -5, 0)
    snap._label:SetJustifyH("RIGHT")
    -- Grid, then Dark Overlays and Cursor Light hung off it, left of Snap Elements.
    hud._gridBtn:ClearAllPoints()
    hud._gridBtn:SetPoint("RIGHT", snap, "LEFT", -L.gapL, 0)

    -- Funnel icon next to the logo's right side: the box's focus button and tooltip anchor.
    local icon = CreateFrame("Button", nil, hud)
    icon:SetSize(ICON_SZ, ICON_SZ)
    icon:SetPoint("LEFT", hud, "TOP", L.upRight, centerY)
    icon:SetFrameLevel(hud:GetFrameLevel() + 2)
    local iconTex = icon:CreateTexture(nil, "OVERLAY")
    iconTex:SetAllPoints()
    iconTex:SetTexture(FILTER_ICON)
    iconTex:SetAlpha(ALPHA_OFF)

    -- The box, as tall as the Exit and Save & Exit buttons; Layout sets its width.
    local frame = CreateFrame("Frame", nil, hud)
    frame:SetSize(BOX_MIN, hud._exitBtn:GetHeight())
    frame:SetPoint("LEFT", icon, "RIGHT", BOX_GAP, 0)
    frame:SetFrameLevel(hud:GetFrameLevel() + 2)
    -- Coordinates and Hover Top Bar right of the box, spaced as the left toggles.
    hud._coordBtn:ClearAllPoints()
    hud._coordBtn:SetPoint("LEFT", frame, "RIGHT", L.gapL, 0)
    hud._hoverBtn:ClearAllPoints()
    hud._hoverBtn:SetPoint("LEFT", hud._coordBtn, "RIGHT", L.gapL, 0)
    hud._infoBtn:ClearAllPoints()
    hud._infoBtn:SetPoint("LEFT", hud._hoverBtn, "RIGHT", L.gapL, 0)
    -- Exit and Save & Exit at the default inset: Layout grows the banner around the
    -- chains instead, so - and + keep clear of the bar's ends on both sides.
    local exit, save = hud._exitBtn, hud._saveBtn
    local _, _, _, _, exitY = exit:GetPoint(1)
    local _, _, _, _, saveY = save:GetPoint(1)
    exit:ClearAllPoints()
    exit:SetPoint("LEFT", hud, "TOPLEFT", L.edgeIn, exitY)
    save:ClearAllPoints()
    save:SetPoint("RIGHT", hud, "TOPRIGHT", -L.edgeIn, saveY)

    -- The fit only changes with the screen, so it runs as the bar shows.
    local Fit = MakeFit(hud, frame)
    Fit()
    hud:HookScript("OnShow", Fit)
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(CludesUI.SL_INPUT_R, CludesUI.SL_INPUT_G, CludesUI.SL_INPUT_B, 0.9)
    local brd = CludesUI.MakeRoundedBorder(frame, BR, BG, BB, 0.20, bg)
    hud._outlines[#hud._outlines + 1] = brd

    local box = CreateFrame("EditBox", nil, frame)
    box:SetAllPoints()
    box:SetAutoFocus(false)
    box:EnableMouse(true)
    box:SetFont(FONT_PATH, 11, "")
    box:SetTextColor(1, 1, 1, 0.9)
    box:SetTextInsets(6, 18, 0, 0)
    box:SetMaxLetters(40)

    local hint = frame:CreateFontString(nil, "OVERLAY")
    hint:SetFont(FONT_PATH, 10, "")
    hint:SetPoint("LEFT", frame, "LEFT", 6, 0)
    hint:SetTextColor(1, 1, 1, 0.35)
    hint:SetText(CludesUI.L("Filter elements..."))

    local clear = CreateFrame("Button", nil, frame)
    clear:SetSize(16, 16)
    clear:SetPoint("RIGHT", frame, "RIGHT", -2, 0)
    clear:SetFrameLevel(box:GetFrameLevel() + 2)
    clear:Hide()
    local x = clear:CreateFontString(nil, "OVERLAY")
    x:SetFont(FONT_PATH, 12, "")
    x:SetPoint("CENTER")
    x:SetTextColor(1, 1, 1, 0.45)
    x:SetText("x")
    clear:SetScript("OnEnter", function() x:SetTextColor(1, 1, 1, 1) end)
    clear:SetScript("OnLeave", function() x:SetTextColor(1, 1, 1, 0.45) end)
    clear:SetScript("OnClick", function() box:SetText(""); box:ClearFocus() end)

    -- Box border and icon follow hover and focus; the icon also shows whether a filter is set.
    local iconHover = false
    local function Border()
        brd:SetColor(BR, BG, BB, (box:HasFocus() or box:IsMouseOver()) and 0.40 or 0.20)
        iconTex:SetAlpha((iconHover or box:HasFocus()) and ALPHA_HOVER or (words and ALPHA_ON or ALPHA_OFF))
    end
    local function ShowTip(owner)
        -- Below the bar: above it is off screen, and on the bar the banner (level 900) covers it.
        UM.ShowBarTip(owner, CludesUI.L("Show only the elements whose name contains every word typed here. Escape clears it."))
    end
    box:SetScript("OnEnter", function(self)
        Border()
        ShowTip(self)
    end)
    box:SetScript("OnLeave", function()
        Border()
        CludesUI.HideWidgetTooltip()
    end)
    icon:SetScript("OnEnter", function(self)
        iconHover = true
        Border()
        ShowTip(self)
    end)
    icon:SetScript("OnLeave", function()
        iconHover = false
        Border()
        CludesUI.HideWidgetTooltip()
    end)
    icon:SetScript("OnClick", function() box:SetFocus() end)
    box:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    -- A click anywhere else gives the keyboard back (arrow keys nudge again).
    box:SetScript("OnEditFocusGained", function(self)
        self:RegisterEvent("GLOBAL_MOUSE_DOWN")
        Border()
    end)
    box:SetScript("OnEditFocusLost", function(self)
        self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
        Border()
    end)
    box:SetScript("OnEvent", function(self)
        if not self:IsMouseOver() and not clear:IsMouseOver() and not icon:IsMouseOver() then self:ClearFocus() end
    end)
    box:SetScript("OnTextChanged", function(self)
        local text = self:GetText() or ""
        if text == "" then hint:Show(); clear:Hide() else hint:Hide(); clear:Show() end
        local w = ParseFilter(text)
        local key = w and table.concat(w, " ") or ""
        if key == lastKey then return end
        words, lastKey = w, key
        Apply()
        Border()
    end)
    -- Closing Unlock Mode (or a combat suspend) hides the banner: start clean.
    hud:HookScript("OnHide", function()
        words, lastKey = nil, ""
        for _, ov in pairs(blizzOverlays) do ov._filterHidden = nil end
        box:ClearFocus()
        box:SetText("")
        iconHover = false
        Border()
    end)

    hud._filterBox, hud._filterIcon, hud._filterClear = box, icon, clear
end
end
