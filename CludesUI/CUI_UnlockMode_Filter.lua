if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_UnlockMode_Filter.lua
--  Unlock Mode top bar layout and element filter. The bar is drawn in code
--  (DrawBanner) as a toolbar across the whole screen width, its controls in
--  one row: the logo and title, the toggles as square chips, the funnel and
--  filter box, then help, Exit, Save & Exit and the - and + scale buttons.
--  It stays on screen with - and + (the box narrows first).
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

-- The drawn bar's height, the row's spacing (outer padding, gap between
-- chips, gap between groups), the chips' size and the brand logo's.
local BAR_H, PAD, GAP, GROUP_GAP = 58, 16, 6, 18
local CHIP, CHIP_ICON, SCALE_CHIP, LOGO_SZ = 28, 18, 22, 26
-- A toggle chip's caption: its size and the room under the face it takes.
-- The face line sits FACE_UP above the bar's centre so face and caption
-- centre on it together; every other control sits on the face line.
local CAPTION_SZ, CAPTION_H, FACE_UP = 9, 13, 6
local LOGO_TEX = "Interface\\AddOns\\CludesUI\\media\\logo-full-thin.png"
local FILTER_ICON = "Interface\\AddOns\\CludesUI\\media\\icons\\filter.png"
-- The bar's own numbers (toggle edges and gaps, the clearance before Exit /
-- Save & Exit, the - and + reach, the scale range) come from CreateHUD
-- (CUI_UnlockMode_Session.lua) as hud._hudLayout.
local ICON_SZ, BOX_GAP = 28, 6
local BOX_MIN, BOX_MAX = 120, 220
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

-- The bar, drawn in code: a dark plate across the whole screen width, a faint
-- sheen, and an accent line along its bottom edge with a soft glow under it.
-- The plate follows the screen, not the bar frame, so it reads as a toolbar
-- whatever the row's width. Spec-override sessions paint it gold
-- (UM.PaintBanner, which also colours the brand logo, made in BuildFilter).
local function DrawBanner(hud)
    local function Span(tex, top, h)
        tex:SetPoint("TOP", hud, "TOP", 0, top)
        tex:SetPoint("LEFT", UIParent, "LEFT")
        tex:SetPoint("RIGHT", UIParent, "RIGHT")
        tex:SetHeight(h)
    end
    local plate = hud:CreateTexture(nil, "BACKGROUND")
    Span(plate, 0, BAR_H)
    plate:SetColorTexture(0.035, 0.043, 0.052, 0.95)
    local sheen = hud:CreateTexture(nil, "BACKGROUND", nil, 1)
    Span(sheen, 0, BAR_H)
    sheen:SetColorTexture(1, 1, 1, 1)
    sheen:SetGradient("VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 0.04))
    local line = hud:CreateTexture(nil, "ARTWORK", nil, 2)
    Span(line, -(BAR_H - 2), 2)
    local glow = hud:CreateTexture(nil, "ARTWORK", nil, 1)
    Span(glow, -BAR_H, 14)
    glow:SetColorTexture(1, 1, 1, 1)

    local function Paint(r, g, b)
        line:SetColorTexture(r, g, b, 0.9)
        glow:SetGradient("VERTICAL", CreateColor(r, g, b, 0), CreateColor(r, g, b, 0.2))
        if hud._badgeLogo then hud._badgeLogo:SetVertexColor(r, g, b, 1) end
        if hud._chipRepaint then hud._chipRepaint() end
    end
    function UM.PaintBanner(special)
        if special then Paint(1, 0.82, 0.30); return end
        local c = CludesUI.CLUDES_GREEN
        Paint(c.r, c.g, c.b)
    end
    CludesUI.RegAccent({ type = "callback", fn = function() UM.PaintBanner(CludesUI._specialUnlockGroup) end })
end

-- The bar's accent colour now: gold in a spec-override session.
local function BarAccent()
    if CludesUI._specialUnlockGroup then return 1, 0.82, 0.30 end
    local c = CludesUI.CLUDES_GREEN
    return c.r, c.g, c.b
end

-- A square chip behind a control: plate, 2px corner outline. Returns the outline.
local function ChipPlate(hud, btn)
    local plate = btn:CreateTexture(nil, "BACKGROUND")
    plate:SetAllPoints()
    plate:SetColorTexture(1, 1, 1, 0.04)
    local brd = CludesUI.MakeRoundedBorder(btn, 1, 1, 1, 0.12, plate, 2)
    hud._outlines[#hud._outlines + 1] = brd
    return brd
end

-- A toggle as a chip: its icon on a square face, a short caption under it
-- naming what it does; the full name and state lead the tooltip
-- (UM.ShowBarTip reads btn._label). The state shows as an accent wash and a
-- bottom cap on the face, and an accent caption: full when on, half for
-- Grid Lines' Dimmed. It reads the state from the icon's alpha, which every
-- toggle already sets (off, dimmed, on); hover (0.9) only brightens it.
-- The button spans face and caption, as wide as the wider of the two.
local chips = {}
local function Chipify(hud, btn, caption)
    btn._label:Hide()
    btn._chip = true
    local text = btn:CreateFontString(nil, "OVERLAY")
    text:SetFont(UM.FONT_PATH, CAPTION_SZ, "OUTLINE, SLUG")
    text:SetText(CludesUI.L(caption))
    btn:SetSize(math.max(CHIP, math.ceil(text:GetStringWidth() or CHIP) + 4), CHIP + CAPTION_H)
    local face = CreateFrame("Frame", nil, btn)
    face:SetSize(CHIP, CHIP)
    face:SetPoint("TOP")
    text:SetPoint("TOP", face, "BOTTOM", 0, -3)
    local tex = btn._tex
    tex:SetParent(face)  -- a child frame draws over its parent's textures
    tex:ClearAllPoints()
    tex:SetPoint("CENTER", face, "CENTER")
    tex:SetSize(CHIP_ICON, CHIP_ICON)
    tex:SetDrawLayer("OVERLAY")
    local brd = ChipPlate(hud, face)
    local wash = face:CreateTexture(nil, "BACKGROUND", nil, 1)
    wash:SetAllPoints()
    local cap = face:CreateTexture(nil, "ARTWORK")
    cap:SetPoint("BOTTOMLEFT", 1, 1)
    cap:SetPoint("BOTTOMRIGHT", -1, 1)
    cap:SetHeight(2)
    local level, hover = 0, false
    local function Paint()
        local r, g, b = BarAccent()
        wash:SetColorTexture(r, g, b, 0.16 * level)
        cap:SetColorTexture(r, g, b, level)
        if hover then
            brd:SetColor(1, 1, 1, 0.35)
            text:SetTextColor(1, 1, 1, 0.95)
        elseif level > 0 then
            brd:SetColor(r, g, b, 0.5)
            text:SetTextColor(r, g, b, 0.95)
        else
            brd:SetColor(1, 1, 1, 0.12)
            text:SetTextColor(1, 1, 1, 0.55)
        end
    end
    hooksecurefunc(tex, "SetAlpha", function(_, a)
        hover = a > 0.85
        if not hover then
            level = (a > ALPHA_OFF + 0.05) and ((a >= ALPHA_ON - 0.01) and 1 or 0.5) or 0
        end
        Paint()
    end)
    tex:SetAlpha(tex:GetAlpha())
    chips[#chips + 1] = Paint
end

-- The row, left to right: brand | toggles | funnel, box ... help, Exit,
-- Save & Exit | - +. Everything hangs off the bar frame's two ends, so the
-- frame's width (Layout) is the whole row; it sits centred on the screen.
local function RowParts(hud, icon, frame)
    return {
        left = { hud._brand, "|", hud._gridBtn, hud._magnetBtn, hud._darkOverlayBtn, hud._flashBtn,
                 hud._coordBtn, hud._hoverBtn, "|", icon, frame },
        right = { hud._plusBtn, hud._minusBtn, "|", hud._saveBtn, hud._exitBtn, hud._infoBtn },
    }
end

-- Sizes the box for a half screen width V (bar units at banner scale 100%,
-- nil = no limit), sets the bar frame's width to the row's and returns half
-- of it: the box gives up its width first when the row does not fit.
local function Layout(hud, frame, V)
    local parts = RowParts(hud, { GetWidth = function() return ICON_SZ end }, frame)
    local function Width(list)
        local w, prev = 0, nil
        for _, p in ipairs(list) do
            if p == "|" then
                w = w + GROUP_GAP
            else
                if prev and prev ~= "|" then w = w + ((p == frame) and BOX_GAP or GAP) end
                w = w + ((p == frame) and 0 or p:GetWidth())
            end
            prev = p
        end
        return w
    end
    -- The funnel stands in at its size; the box is added apart.
    local fixed = 2 * PAD + Width(parts.left) + GROUP_GAP + Width(parts.right)
    local boxW = BOX_MAX
    if V and (fixed + boxW) / 2 > V then boxW = BOX_MIN end
    frame:SetWidth(boxW)
    local w = math.ceil(fixed + boxW)
    hud:SetWidth(w)
    return w / 2
end

-- Keeps the bar and its - and + on screen: a banner scale that no longer
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

-- Called by CreateHUD with the bar and its controls' vertical centre: draws
-- the bar, restyles the controls and lays out the row.
function UM.BuildFilter(hud, centerY)
    local FONT_PATH = UM.FONT_PATH
    local BR, BG, BB = CludesUI.BORDER_R, CludesUI.BORDER_G, CludesUI.BORDER_B
    -- Brand: the logo (the open animation's emblem lands on it) and the title.
    local brand = CreateFrame("Frame", nil, hud)
    brand:SetHeight(CHIP)
    local logo = brand:CreateTexture(nil, "ARTWORK")
    logo:SetSize(LOGO_SZ, LOGO_SZ)
    logo:SetPoint("LEFT")
    logo:SetTexture(LOGO_TEX)
    local title = brand:CreateFontString(nil, "OVERLAY")
    title:SetFont(UM.FONT_PATH, 13, "OUTLINE, SLUG")
    title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
    title:SetTextColor(1, 1, 1, 0.92)
    title:SetText(CludesUI.L("LAYOUT MODE"))
    brand:SetWidth(LOGO_SZ + 8 + math.ceil(title:GetStringWidth() or 90))
    hud._brand, hud._badgeLogo = brand, logo
    DrawBanner(hud)

    -- Toggles become chips; help, and - and +, take the same plate.
    Chipify(hud, hud._gridBtn, "Grid")
    Chipify(hud, hud._magnetBtn, "Snap")
    Chipify(hud, hud._darkOverlayBtn, "Overlays")
    Chipify(hud, hud._flashBtn, "Cursor Light")
    Chipify(hud, hud._coordBtn, "Coordinates")
    Chipify(hud, hud._hoverBtn, "Auto Hide")
    hud._chipRepaint = function() for i = 1, #chips do chips[i]() end end
    hud._infoBtn:SetSize(CHIP, CHIP)
    ChipPlate(hud, hud._infoBtn)
    for _, b in ipairs({ hud._minusBtn, hud._plusBtn }) do
        b:SetSize(SCALE_CHIP, SCALE_CHIP)
        b._shadow:Hide()
        b._label:SetFont(UM.FONT_PATH, 16, "")
        ChipPlate(hud, b)
    end
    UM.PaintBanner(CludesUI._specialUnlockGroup)

    -- Funnel icon: the box's focus button and tooltip anchor.
    local icon = CreateFrame("Button", nil, hud)
    icon:SetSize(ICON_SZ, ICON_SZ)
    icon:SetFrameLevel(hud:GetFrameLevel() + 2)
    local iconTex = icon:CreateTexture(nil, "OVERLAY")
    iconTex:SetAllPoints()
    iconTex:SetTexture(FILTER_ICON)
    iconTex:SetAlpha(ALPHA_OFF)

    -- The box, as tall as the Exit and Save & Exit buttons; Layout sets its width.
    local frame = CreateFrame("Frame", nil, hud)
    frame:SetSize(BOX_MIN, hud._exitBtn:GetHeight())
    frame:SetFrameLevel(hud:GetFrameLevel() + 2)

    -- Place the row: the left group from the bar's left end, the right group
    -- from its right end, each part on the controls' centre line.
    local parts = RowParts(hud, icon, frame)
    -- Each part is placed from the bar's end by the widths before it: a chip
    -- (face and caption) centred on the bar, the rest on its face line.
    local faceY = centerY + FACE_UP
    local function Chain(list, side)
        local x, prev, gap = PAD, nil, 0
        for _, p in ipairs(list) do
            if p == "|" then
                gap = GROUP_GAP
            else
                if prev then x = x + ((gap > 0) and gap or ((p == frame) and BOX_GAP or GAP)) end
                local y = p._chip and (faceY - CAPTION_H / 2) or faceY  -- a chip's face on the face line
                p:ClearAllPoints()
                if side == "LEFT" then
                    p:SetPoint("LEFT", hud, "TOPLEFT", x, y)
                else
                    p:SetPoint("RIGHT", hud, "TOPRIGHT", -x, y)
                end
                x = x + p:GetWidth()
                prev, gap = p, 0
            end
        end
    end
    Chain(parts.left, "LEFT")
    Chain(parts.right, "RIGHT")

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
