if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUI_Popups.lua
--  Popup scale helper, announcement shell and buttons, reload helpers, and
--  the confirm / info / input popups. Loads right after CludesUI.lua.
-------------------------------------------------------------------------------
local CludesUI = _G.CludesUI

local PanelPP = CludesUI.PanelPP
local MakeFont = CludesUI.MakeFont
local MakeBorder = CludesUI.MakeBorder
local SolidTex = CludesUI.SolidTex
local lerp = CludesUI.lerp
local CLUDES_GREEN = CludesUI.CLUDES_GREEN
local BORDER_COLOR = CludesUI.BORDER_COLOR
local TEXT_DIM = CludesUI.TEXT_DIM

-------------------------------------------------------------------------------
--  Popup Scale Helper -- pixel-perfect base scale * user panel scale, so popups grow/shrink with the main panel when the scale slider moves.
-------------------------------------------------------------------------------
local _popupFrames = {} -- { popup, dimmer } pairs to update on scale change
CludesUI._popupFrames = _popupFrames

local function GetPopupScale()
    local physW = (GetPhysicalScreenSize())
    local baseScale = GetScreenWidth() / physW
    local userScale = (CludesUIDB and CludesUIDB.panelScale) or 1.0
    return baseScale * userScale
end
CludesUI.GetPopupScale = GetPopupScale

-- Reference density for dialog popups: 1440p at 0.64 UI scale (the suite's design reference),
-- where popups render at 768/(1440*0.64) = 0.8333 physical px/unit. Applied as a CONSTANT it
-- pins that size on every display, fixing both defects of the old squared scale: size no longer
-- moves INVERSELY with UI scale, nor grows QUADRATICALLY with the Window Scale slider; px/unit
-- is 0.8333 * panelScale. THE INVARIANT: every popup occupies the same screen fraction it does
-- at 1440p/0.64 -- screen-height fraction = (units * POPUP_REF_DENSITY * panelScale) / physH,
-- which holds exactly when panelScale == physH/1440 (what the Startup seed and the
-- panel_scale_highdpi_reset_v3 migration set it to). Do NOT "fix" this constant to 1.0: that
-- normalizes every display to 1 px/unit, 20% larger than the reference. Deliberate deviation:
-- the seed is FLOORED at 1, so below 1440p the fraction runs larger than reference (1080p by
-- 33%); enforcing it there would seed 0.75 and shrink the options panel a quarter for the
-- largest resolution segment (accepted trade). On the namespace, not a file local: 200-local cap.
CludesUI.POPUP_REF_DENSITY = 768 / (1440 * 0.64)

-- Scale a dialog sets on ITSELF, atop the dimmer that already carries GetPopupScale(). mult =
-- the dialog's own relative bump (1, or 1.15 for intro popups); ALWAYS route through this so the reference density lives in exactly one place.
function CludesUI.PopupBump(mult)
    return (mult or 1) * CludesUI.POPUP_REF_DENSITY
end

-- Dialog popups sit on a dimmer GetPopupScale has ALREADY scaled, so a dialog that also
-- SetScale(ppScale)s itself renders at ppScale SQUARED (baseScale = 768/(physH*uiScale) means
-- panelScale^2 * baseScale px/unit): oversizing popups everywhere, and (uiScale in the
-- denominator) BIGGER as UI scale drops. Dialogs take their scale ONCE from the dimmer and set
-- only their own relative bump, so px/unit == panelScale, exactly matching the options panel.
-- Units are easy to get wrong: GetEffectiveScale() is NOT physical px/unit. WoW maps the UI
-- through a 768-tall virtual space, so px/unit = GetEffectiveScale() * physH/768; baseScale is
-- then exactly 1 at the pixel-perfect uiScale (768/physH) on every resolution, which collapses
-- the corrected formula to panelScale.
-- _popupFrames entries come in TWO shapes, and the shape decides where the scale belongs (see
-- RefreshPopupScales): { popup = p } -- unscaled parent, popup carries the scale; { popup = p,
-- dimmer = d } -- scaled dimmer, popup carries only its bump. The raid-frame manager popups and
-- the nameplate filter panel are the former and were never doubled, why GetPopupScale itself is unchanged.

-- Hard ceiling for modal setup popups: they sit on a full-screen dimmer that eats every click
-- behind it, so one overflowing the display puts its buttons off-screen with no way back to the
-- game menu. Measured, not derived: GetEffectiveScale reports what the frame really renders at,
-- including every stacked parent scale, so this holds whatever the upstream scale math does (only ever shrinks).
function CludesUI.ClampPopupToScreen(dialog, w, h)
    if not dialog or not w or not h or w <= 0 or h <= 0 then
        return
    end
    local es = dialog:GetEffectiveScale()
    if type(es) ~= "number" or es <= 0 then
        return
    end
    local pw, ph = GetPhysicalScreenSize()
    if type(pw) ~= "number" or type(ph) ~= "number" or pw <= 0 or ph <= 0 then
        return
    end
    local fit = math.min((pw * 0.92) / (w * es), (ph * 0.92) / (h * es))
    if fit >= 1 then
        return
    end
    dialog:SetScale(dialog:GetScale() * fit)
end

-- Announcement popup shell: full-screen dimmer (name.."Dimmer") and a centred panel
-- (name.."Popup") with a rounded 1 px outline (popup._brd) and Escape handling. opts: w, h;
-- bump (PopupBump mult; nil = caller scales both frames later); strata; dimAlpha; bg {r,g,b};
-- edge {r,g,b,a}; clamp (ClampPopupToScreen); onEscape (nil = Escape is only swallowed);
-- onDimmerDown. Other keys propagate. Returns dimmer, popup.
function CludesUI.BuildPopupShell(name, options)
    local strata = options.strata or "FULLSCREEN_DIALOG"
    local shade = CreateFrame("Frame", name .. "Dimmer", UIParent)
    shade:SetFrameStrata(strata)
    shade:SetAllPoints(UIParent)
    shade:EnableMouse(true)
    shade:EnableMouseWheel(true)
    shade:SetScript("OnMouseWheel", function() end)
    if options.onDimmerDown then
        shade:SetScript("OnMouseDown", options.onDimmerDown)
    end
    if options.bump then
        shade:SetScale(GetPopupScale())
    end
    local dimTex = shade:CreateTexture(nil, "BACKGROUND")
    dimTex:SetAllPoints()
    dimTex:SetColorTexture(0, 0, 0, options.dimAlpha or 0.35)

    local dialog = CreateFrame("Frame", name .. "Popup", shade)
    if options.bump then
        dialog:SetScale(CludesUI.PopupBump(options.bump))
    end
    dialog:SetFrameStrata(strata)
    dialog:SetFrameLevel(shade:GetFrameLevel() + 10)
    PanelPP.Size(dialog, options.w, options.h)
    if options.clamp then
        CludesUI.ClampPopupToScreen(dialog, options.w, options.h)
    end
    dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    dialog:EnableMouse(true)

    local c = options.bg or { 0.062, 0.070, 0.082 }
    local bg = dialog:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(c[1], c[2], c[3], 1)

    -- The outline sits on a pixel layer: whole physical pixels at every later scale.
    local e = options.edge or { 1, 1, 1, 0.15 }
    dialog._brd = CludesUI.MakeRoundedBorder(dialog, e[1], e[2], e[3], e[4], bg)

    local onEscape = options.onEscape
    -- EnableKeyboard and SetPropagateKeyboardInput are protected in combat:
    -- a shell built there never takes the keyboard, and in combat a shown one
    -- stands aside (keys reach the game, its buttons still answer).
    if not InCombatLockdown() then
        dialog:EnableKeyboard(true)
        dialog:SetPropagateKeyboardInput(true)
    end
    dialog:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then
            return
        end
        self:SetPropagateKeyboardInput(key ~= "ESCAPE")
        if key == "ESCAPE" and onEscape then
            onEscape()
        end
    end)
    -- Controller Back takes the Escape route (swallowed when there is none). It
    -- counts only when a controller is in use at the show, so the keyboard path
    -- never changes. The dimmer is born shown: with a controller it is hidden
    -- first so the caller's Show() is a real show edge.
    if CludesUI.RegisterEscapeClose then
        if CludesUI.PadInUse() then
            shade:Hide()
        end
        CludesUI.RegisterEscapeClose(shade, {
            padOnly = true,
            modal = not onEscape,
            onEscape = onEscape and function()
                onEscape()
            end or nil,
        })
    end
    -- Controller cursor: the panel is a blocker, not a stop.
    CludesUI.PadHint(dialog, "nodepass")
    return shade, dialog
end

-- Announcement action button, 38 tall: primary is bright, secondary dim. opts: w;
-- secondary; hoverA (secondary border alpha on hover); hoverRGB {r,g,b} (secondary
-- hovers to that colour instead, border alpha 0.95); square (the square outline,
-- for a window that is square by design). The caller anchors it.
function CludesUI.MakeActionButton(parent, font, text, red, green, blue, options)
    local secondary, hoverRGB = options.secondary, options.hoverRGB
    local button = CreateFrame("Button", nil, parent)
    button:SetFrameLevel(parent:GetFrameLevel() + 2)
    PanelPP.Size(button, options.w, 38)
    local bbg = button:CreateTexture(nil, "BACKGROUND")
    bbg:SetAllPoints()
    bbg:SetColorTexture(0.062, 0.070, 0.082, 0.92)
    local brd
    if options.square then
        brd = MakeBorder(button, red, green, blue, secondary and 0.35 or 0.9, PanelPP)
    else
        brd = CludesUI.MakeRoundedBorder(button, red, green, blue, secondary and 0.35 or 0.9, bbg)
    end
    local caption = button:CreateFontString(nil, "OVERLAY")
    caption:SetFont(font, 15, "")
    PanelPP.Point(caption, "CENTER", button, "CENTER", 0, 0)
    caption:SetTextColor(red, green, blue, secondary and 0.55 or 0.9)
    caption:SetText(text)
    button:SetScript("OnEnter", function()
        if secondary and hoverRGB then
            caption:SetTextColor(hoverRGB[1], hoverRGB[2], hoverRGB[3], 1)
            brd:SetColor(hoverRGB[1], hoverRGB[2], hoverRGB[3], 0.95)
        else
            caption:SetTextColor(red, green, blue, 1)
            brd:SetColor(red, green, blue, secondary and options.hoverA or 1)
        end
    end)
    button:SetScript("OnLeave", function()
        caption:SetTextColor(red, green, blue, secondary and 0.55 or 0.9)
        brd:SetColor(red, green, blue, secondary and 0.35 or 0.9)
    end)
    -- The label, for a popup that changes its font later (the Talent Conditions
    -- picker takes its opener's module font).
    button._label = caption
    return button
end

-- Dialog button (confirm and input dialogs, and a few windows that match
-- them): 125 x 27, a label and an outline that ease from their resting
-- colours to their hover colours in 0.1 s, over a faint wash of the outline's
-- colour that brightens with them. Colours are given as four RGBA groups:
-- label, label on hover, outline, outline on hover. square (optional): a
-- square outline, for a window that is square by design.
-- Exposes btn._lbl, btn._resetAnim() (snap back to resting) and
-- btn._setColors(...) (new colours, same order; repaints where it is).
local POPUP_BTN_W, POPUP_BTN_H, POPUP_BTN_FADE = 125, 27, 0.1

function CludesUI.MakePopupButton(parent, point, relTo, relPoint, x, y, ...)
    local square = select(17, ...)
    local col = {} -- [1..4] label, [5..8] label hover, [9..12] outline, [13..16] outline hover
    local function SetColors(...)
        for i = 1, 16 do
            col[i] = select(i, ...)
        end
    end
    SetColors(...)

    local button = CreateFrame("Button", nil, parent)
    button:SetSize(POPUP_BTN_W, POPUP_BTN_H)
    button:SetPoint(point, relTo, relPoint, x, y)
    button:SetFrameLevel(parent:GetFrameLevel() + 2)
    local wash = SolidTex(button, "BACKGROUND", 0, 0, 0, 0.5)
    wash:SetAllPoints()
    local outline = square and MakeBorder(button, col[9], col[10], col[11], col[12])
        or CludesUI.MakeRoundedBorder(button, col[9], col[10], col[11], col[12], wash)
    local label = MakeFont(button, 12, nil, col[1], col[2], col[3])
    label:SetPoint("CENTER")

    -- t: 0 resting, 1 hovered.
    local t, goal = 0, 0
    local function Paint()
        local function Mix(i)
            return lerp(col[i], col[i + 4], t)
        end
        label:SetTextColor(Mix(1), Mix(2), Mix(3), Mix(4))
        outline:SetColor(
            lerp(col[9], col[13], t),
            lerp(col[10], col[14], t),
            lerp(col[11], col[15], t),
            lerp(col[12], col[16], t)
        )
        -- A dark base with the outline's colour coming through as it lights up.
        wash:SetColorTexture(
            lerp(0, col[13], 0.08 * t),
            lerp(0, col[14], 0.08 * t),
            lerp(0, col[15], 0.08 * t),
            0.5 + 0.1 * t
        )
    end
    local function Step(self, elapsed)
        t = goal == 1 and math.min(1, t + elapsed / POPUP_BTN_FADE)
            or math.max(0, t - elapsed / POPUP_BTN_FADE)
        if t == goal then
            self:SetScript("OnUpdate", nil)
        end
        Paint()
    end
    button:SetScript("OnEnter", function(self)
        goal = 1
        self:SetScript("OnUpdate", Step)
    end)
    button:SetScript("OnLeave", function(self)
        goal = 0
        self:SetScript("OnUpdate", Step)
    end)

    button._lbl = label
    function button._resetAnim()
        t, goal = 0, 0
        button:SetScript("OnUpdate", nil)
        Paint()
    end
    function button._setColors(...)
        SetColors(...)
        Paint()
    end
    Paint()
    return button
end

-- Re-apply the scale to the frame that OWNS it. A popup registered with a dimmer takes its
-- scale from that dimmer and carries only its bump, so writing GetPopupScale() onto the popup
-- here would restore the squared double-scale on the first slider change; scaling the dimmer also keeps it from holding its creation-time scale forever while the popup rescales underneath it.
local function RefreshPopupScales()
    local s = GetPopupScale()
    for _, entry in ipairs(_popupFrames) do
        if entry.dimmer then
            entry.dimmer:SetScale(s)
        elseif entry.popup then
            entry.popup:SetScale(s)
        end
    end
end

-- Register so popups rescale when the user adjusts the panel scale slider
if not CludesUI._onScaleChanged then
    CludesUI._onScaleChanged = {}
end
CludesUI._onScaleChanged[#CludesUI._onScaleChanged + 1] = RefreshPopupScales

-------------------------------------------------------------------------------
--  Custom Confirmation Popup  (matches CludesUI aesthetic)
--  Usage:  CludesUI:ShowConfirmPopup({ title, message, confirmText, cancelText, onConfirm, onCancel })
-------------------------------------------------------------------------------
local confirmPopup

-- Helper: wire Escape key to dismiss a popup via its dimmer
-- Keyboard for a popup of ours: `frame` takes the keys, `host` (its dimmer,
-- when it has one) shows and hides it. EnableKeyboard and
-- SetPropagateKeyboardInput are protected in combat, so the frame takes the
-- keyboard now and each time the host shows, only out of combat, passing keys
-- on by default; its OnKeyDown returns first in combat (keys reach the game,
-- Escape stands aside, the buttons still answer). It lets go when the host
-- hides out of combat, so a popup shown again in combat holds no keyboard
-- (an Escape that closed it left propagation off).
function CludesUI.PopupTakeKeys(frame, host)
    local function Take()
        if InCombatLockdown() then
            return
        end
        frame:EnableKeyboard(true)
        frame:SetPropagateKeyboardInput(true)
    end
    if host then
        host:HookScript("OnShow", Take)
        host:HookScript("OnHide", function()
            if not InCombatLockdown() then
                frame:EnableKeyboard(false)
            end
        end)
    end
    Take()
end

local function WirePopupEscape(dialog, shade)
    -- EnableKeyboard and SetPropagateKeyboardInput are protected in combat:
    -- the popup takes the keyboard only while shown out of combat, passing
    -- keys on by default, and in combat it stands aside (keys reach the
    -- game, Escape does not close it, its buttons still answer).
    local function TakeKeys(on)
        if InCombatLockdown() then
            return
        end
        dialog:EnableKeyboard(on)
        if on then
            dialog:SetPropagateKeyboardInput(true)
        end
    end
    dialog:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then
            return
        end
        if key == "ESCAPE" then
            if dialog._modal then
                -- Modal popups swallow Escape: the user must click a button.
                self:SetPropagateKeyboardInput(false)
                return
            end
            self:SetPropagateKeyboardInput(false)
            shade:Hide()
            if dialog._onCancel then
                dialog._onCancel()
            end
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
    -- Release keyboard capture when the popup is dismissed
    shade:HookScript("OnHide", function()
        TakeKeys(false)
    end)
    shade:HookScript("OnShow", function()
        TakeKeys(true)
    end)
    if shade:IsShown() then
        TakeKeys(true)
    end
    -- Controller Back takes the same route as Escape (modal popups swallow it).
    -- It counts only when a controller is in use at the show, so the keyboard
    -- path never changes.
    if CludesUI.RegisterEscapeClose then
        CludesUI.RegisterEscapeClose(shade, {
            padOnly = true,
            modal = function()
                return dialog._modal
            end,
            onEscape = function()
                shade:Hide()
                if dialog._onCancel then
                    dialog._onCancel()
                end
            end,
        })
    end
    -- Controller cursor: the panel is a blocker, not a stop.
    CludesUI.PadHint(dialog, "nodepass")
end

-- Checkbox row of the confirm and input popups (opts.checkbox): a box with an
-- accent tick and a label, hidden until a show asks for it. A click flips
-- popup._cbChecked.
local function MakePopupCheckbox(dialog, width)
    local EG = CLUDES_GREEN
    local cbRow = CreateFrame("Button", nil, dialog)
    cbRow:SetSize(width, 18)
    cbRow:SetFrameLevel(dialog:GetFrameLevel() + 2)

    local cbBox = CreateFrame("Frame", nil, cbRow)
    cbBox:SetSize(14, 14)
    cbBox:SetPoint("LEFT", cbRow, "LEFT", 0, 0)
    cbBox:SetFrameLevel(cbRow:GetFrameLevel() + 1)
    local cbBoxBg = SolidTex(cbBox, "BACKGROUND", 0.088, 0.098, 0.111, 1)
    cbBoxBg:SetAllPoints()
    CludesUI.MakeRoundedBorder(cbBox, BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.25, cbBoxBg)
    local cbCheck = SolidTex(cbBox, "ARTWORK", EG.r, EG.g, EG.b, 1)
    cbCheck:SetPoint("TOPLEFT", 3, -3)
    cbCheck:SetPoint("BOTTOMRIGHT", -3, 3)
    CludesUI.RoundBody(cbBox, cbCheck, 1)
    cbCheck:Hide()

    local cbLabel = MakeFont(cbRow, 11, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
    cbLabel:SetPoint("LEFT", cbBox, "RIGHT", 6, 0)

    dialog._cbChecked = false
    cbRow:SetScript("OnClick", function()
        dialog._cbChecked = not dialog._cbChecked
        if dialog._cbChecked then
            cbCheck:Show()
        else
            cbCheck:Hide()
        end
    end)
    cbRow:Hide()
    dialog._cbRow = cbRow
    dialog._cbCheck = cbCheck
    dialog._cbLabel = cbLabel
end

-- Shows the checkbox row unchecked with its label, its centre y above the
-- popup's bottom edge (the confirm dialog's layout then places it again).
local function ShowPopupCheckbox(dialog, label, y)
    local EG = CLUDES_GREEN
    dialog._cbChecked = false
    dialog._cbCheck:SetColorTexture(EG.r, EG.g, EG.b, 1)
    dialog._cbCheck:Hide()
    dialog._cbLabel:SetText(CludesUI.L(label))
    dialog._cbRow:SetWidth(14 + 6 + dialog._cbLabel:GetStringWidth())
    dialog._cbRow:ClearAllPoints()
    dialog._cbRow:SetPoint("BOTTOM", dialog, "BOTTOM", 0, y)
    dialog._cbRow:Show()
end

-- The house dialog look: an accent cap along the top, a header band behind
-- the title (DIALOG_HEAD tall) and a footer band behind the buttons
-- (DIALOG_FOOT tall), each with a hairline divider. Titles sit left in the
-- header band, buttons right in the footer.
local DIALOG_HEAD, DIALOG_FOOT, DIALOG_PAD = 40, 46, 18
local CONFIRM_MIN_H = 150 -- the confirm dialog's least height: a header, two lines, the footer
local function DressDialog(dialog)
    local function Tex(layer, sub, a)
        local tx = dialog:CreateTexture(nil, layer, nil, sub)
        tx:SetColorTexture(1, 1, 1, a)
        return tx
    end
    local head = Tex("BACKGROUND", 2, 0.035)
    head:SetPoint("TOPLEFT")
    head:SetPoint("TOPRIGHT")
    head:SetHeight(DIALOG_HEAD)
    local hl = Tex("ARTWORK", 0, 0.08)
    hl:SetPoint("TOPLEFT", head, "BOTTOMLEFT")
    hl:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT")
    hl:SetHeight(1)
    local foot = Tex("BACKGROUND", 2, 0.025)
    foot:SetPoint("BOTTOMLEFT")
    foot:SetPoint("BOTTOMRIGHT")
    foot:SetHeight(DIALOG_FOOT)
    local fl = Tex("ARTWORK", 0, 0.08)
    fl:SetPoint("BOTTOMLEFT", foot, "TOPLEFT")
    fl:SetPoint("BOTTOMRIGHT", foot, "TOPRIGHT")
    fl:SetHeight(1)
    local cap = dialog:CreateTexture(nil, "ARTWORK", nil, 1)
    cap:SetPoint("TOPLEFT")
    cap:SetPoint("TOPRIGHT")
    cap:SetHeight(2)
    local function Paint()
        local color = CLUDES_GREEN
        cap:SetColorTexture(color.r, color.g, color.b, 0.9)
    end
    Paint()
    dialog:HookScript("OnShow", Paint)
end

-- A dialog title, left in the header band.
local function PlaceDialogTitle(dialog, title, w)
    title:ClearAllPoints()
    title:SetPoint("LEFT", dialog, "TOPLEFT", DIALOG_PAD, -DIALOG_HEAD / 2)
    title:SetWidth(w - 2 * DIALOG_PAD)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
end

local function CreateConfirmPopup()
    if confirmPopup then
        return confirmPopup
    end

    local POPUP_W, POPUP_H = 400, CONFIRM_MIN_H

    -- Full-screen dimming overlay
    local shade = CreateFrame("Frame", "CUIConfirmDimmer", UIParent)
    shade:SetFrameStrata("FULLSCREEN_DIALOG")
    shade:SetFrameLevel(100) -- above unlock mode movers (level ~21)
    shade:SetAllPoints(UIParent)
    shade:EnableMouse(true)
    shade:EnableMouseWheel(true)
    shade:SetScript("OnMouseWheel", function() end)
    shade:Hide()

    local dimTex = SolidTex(shade, "BACKGROUND", 0, 0, 0, 0.25)
    dimTex:SetAllPoints()

    -- Popup frame
    local dialog = CreateFrame("Frame", "CUIConfirmPopup", shade)
    dialog:SetSize(POPUP_W, POPUP_H)
    dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    dialog:SetFrameStrata("FULLSCREEN_DIALOG")
    dialog:SetFrameLevel(shade:GetFrameLevel() + 10)

    -- Popups render at default UI scale (dimmer stays at 1 to cover the full screen).

    -- Background: flat dark default, optional stone atlas for modern style
    local popBgFlat = SolidTex(dialog, "BACKGROUND", 0.062, 0.070, 0.082, 1)
    popBgFlat:SetAllPoints()
    local dialogArt = dialog:CreateTexture(nil, "BACKGROUND")
    dialogArt:SetTexture("Interface\\AddOns\\CludesUI\\media\\modern_blizz.png")
    dialogArt:SetTexCoord(0.25, 1, 0, 0.75)
    dialogArt:SetAllPoints()
    dialogArt:Hide()
    local dialogTint = dialog:CreateTexture(nil, "BACKGROUND", nil, 1)
    dialogTint:SetColorTexture(0, 0, 0, 0.6)
    dialogTint:SetAllPoints()
    dialogTint:Hide()
    dialog._popBgFlat = popBgFlat
    dialog._popBgAtlas = dialogArt
    dialog._popBgOverlay = dialogTint

    dialog._brd =
        CludesUI.MakeRoundedBorder(dialog, BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.15, popBgFlat)
    CludesUI.RoundBody(dialog, dialogArt)
    CludesUI.RoundBody(dialog, dialogTint)
    DressDialog(dialog)

    -- Title, left in the header band
    local title = MakeFont(dialog, 15, "", 1, 1, 1)
    PlaceDialogTitle(dialog, title, POPUP_W)
    dialog._title = title

    -- Message, left-aligned under the header
    local messageText = MakeFont(dialog, 12, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
    messageText:SetPoint("TOPLEFT", dialog, "TOPLEFT", DIALOG_PAD, -(DIALOG_HEAD + 14))
    messageText:SetWidth(POPUP_W - 2 * DIALOG_PAD)
    messageText:SetJustifyH("LEFT")
    messageText:SetWordWrap(true)
    messageText:SetSpacing(4)
    dialog._msg = messageText

    -- Disclaimer (smaller, italic, below message)
    local disc = dialog:CreateFontString(nil, "OVERLAY")
    disc:SetFont(CludesUI.EXPRESSWAY, 11, "")
    disc:SetTextColor(TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a * 0.7)
    disc:SetPoint("TOPLEFT", messageText, "BOTTOMLEFT", 0, -8)
    disc:SetWidth(POPUP_W - 2 * DIALOG_PAD)
    disc:SetJustifyH("LEFT")
    disc:SetWordWrap(true)
    disc:Hide()
    dialog._disclaimer = disc

    -- Scale/resolution mismatch warning (red, below disclaimer)
    local scaleWarn = MakeFont(dialog, 10, nil, 1, 0.2, 0.2, 1)
    scaleWarn:SetWidth(POPUP_W - 2 * DIALOG_PAD)
    scaleWarn:SetJustifyH("LEFT")
    scaleWarn:SetWordWrap(true)
    scaleWarn:SetSpacing(2)
    scaleWarn:Hide()
    dialog._scaleWarnLabel = scaleWarn
    dialog._baseH = POPUP_H

    -- Buttons, right in the footer band: Confirm at the corner, Cancel left of it
    local BTN_GAP = 8
    local BTN_Y = 10
    local BTN_W = 125

    -- Cancel button -- dim white style
    local EG = CLUDES_GREEN
    local cancelBtn = CludesUI.MakePopupButton(
        dialog,
        "BOTTOMRIGHT",
        dialog,
        "BOTTOMRIGHT",
        -(14 + BTN_W + BTN_GAP),
        BTN_Y,
        1,
        1,
        1,
        0.7, -- default text
        1,
        1,
        1,
        0.9, -- hovered text
        1,
        1,
        1,
        0.5, -- default border
        1,
        1,
        1,
        0.6 -- hovered border
    )

    -- Confirm button -- accent style
    local confirmBtn = CludesUI.MakePopupButton(
        dialog,
        "BOTTOMRIGHT",
        dialog,
        "BOTTOMRIGHT",
        -14,
        BTN_Y,
        EG.r,
        EG.g,
        EG.b,
        0.9, -- default text
        EG.r,
        EG.g,
        EG.b,
        1, -- hovered text
        EG.r,
        EG.g,
        EG.b,
        0.9, -- default border
        EG.r,
        EG.g,
        EG.b,
        1 -- hovered border
    )

    dialog._cancelBtn = cancelBtn
    dialog._confirmBtn = confirmBtn

    -- Optional checkbox (above buttons, centered)
    MakePopupCheckbox(dialog, POPUP_W - 60)

    -- Close on dimmer click outside the popup; modal popups ignore dimmer clicks.
    dialog:EnableMouse(true)
    shade:SetScript("OnMouseDown", function()
        if dialog._modal then
            return
        end
        if not dialog:IsMouseOver() then
            shade:Hide()
            if dialog._onCancel then
                dialog._onCancel()
            end
        end
    end)

    -- Close on Escape
    WirePopupEscape(dialog, shade)

    dialog._dimmer = shade
    confirmPopup = dialog
    return dialog
end

-- Repaints the cached popup's accent parts (the confirm button and the checkbox
-- tick) with the current accent; the popup itself is built once and reused.
local function InvalidateConfirmPopup()
    local dialog = confirmPopup
    if not dialog then
        return
    end
    local EG = CLUDES_GREEN
    dialog._confirmBtn._setColors(
        EG.r,
        EG.g,
        EG.b,
        0.9,
        EG.r,
        EG.g,
        EG.b,
        1,
        EG.r,
        EG.g,
        EG.b,
        0.9,
        EG.r,
        EG.g,
        EG.b,
        1
    )
    dialog._cbCheck:SetColorTexture(EG.r, EG.g, EG.b, 1)
end
CludesUI._InvalidateConfirmPopup = InvalidateConfirmPopup

-- Reload the UI from our own code: the reload is asked for at once, then the
-- caller's optional pre-reload `work` runs. WoW Forever lets addon code reload
-- only inside a click or keypress (in or out of combat), never from an event
-- or a timer, so every caller runs from one: a button, a confirm popup or a
-- slash command. It also refused a reload asked for late in the click, after
-- the confirm popup had closed and the caller's work had run (build 70425),
-- so the reload comes before anything else the click does. The client
-- reloads only once the click's code has finished, so `work` still runs and
-- is saved. Code that may run from an event asks with a confirm popup
-- (reload = true), whose click reloads. `title` and `message` name the reload
-- for its callers; nothing shows them.
function CludesUI.RequestReload(title, message, work)
    ReloadUI()
    if work then
        work()
    end
end

function CludesUI:ShowConfirmPopup(options)
    -- reload = true: confirming reloads the UI from the click (RequestReload),
    -- the caller's own onConfirm, if it has one, running after the reload is
    -- asked for as its pre-reload work. The caller's table is left as is.
    if options.reload then
        local swatchOpts = {}
        for key, val in pairs(options) do
            swatchOpts[key] = val
        end
        swatchOpts.reload = nil
        local work = options.onConfirm
        swatchOpts.onConfirm = function(checked)
            CludesUI.RequestReload(nil, nil, work and function()
                work(checked)
            end)
        end
        options = swatchOpts
    end
    -- Force-close any widget tooltip so it doesn't linger behind the popup
    if CludesUI.HideWidgetTooltip then
        CludesUI.HideWidgetTooltip()
    end
    local dialog = CreateConfirmPopup()
    dialog._dimmer:SetFrameLevel(options.frameLevel or 100)

    -- Background style: flat (default) or modern Blizzard stone
    local modern = options.modernBlizz
    dialog._popBgFlat:SetShown(not modern)
    dialog._popBgAtlas:SetShown(modern == true)
    dialog._popBgOverlay:SetShown(modern == true)

    dialog._title:SetText(CludesUI.L(options.title or "Confirm"))
    dialog._msg:SetText(CludesUI.L(options.message or "Are you sure?"))
    if options.disclaimer then
        dialog._disclaimer:SetText(CludesUI.L(options.disclaimer))
        dialog._disclaimer:Show()
    else
        dialog._disclaimer:SetText("")
        dialog._disclaimer:Hide()
    end

    -- Scale/resolution mismatch warning (red)
    if options.scaleWarning and options.scaleWarning ~= "" then
        dialog._scaleWarnLabel:SetText(CludesUI.L(options.scaleWarning))
        dialog._scaleWarnLabel:Show()
    else
        dialog._scaleWarnLabel:SetText("")
        dialog._scaleWarnLabel:Hide()
    end
    -- Optional checkbox (placed by the layout below)
    if options.checkbox then
        ShowPopupCheckbox(dialog, options.checkbox, 0)
    else
        dialog._cbRow:Hide()
    end

    -- Optional type-to-confirm gate (lazy, like the macro overlay): the user must type the given
    -- word (case-insensitive) before confirm accepts clicks. NOT supported with confirmMacro (secure overlay clicks cannot be gated).
    dialog._typeGateOn = nil
    dialog._padGate = nil
    -- Controller: the word cannot be typed, so the gate becomes a second press of confirm.
    local padGate = options.typeToConfirm and CludesUI.PadInUse()
    if options.typeToConfirm and not padGate then
        if not dialog._typeRow then
            local line = CreateFrame("Frame", nil, dialog)
            line:SetSize(220, 26)
            line:SetFrameLevel(dialog:GetFrameLevel() + 2)
            local tLbl = MakeFont(line, 12, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
            tLbl:SetPoint("LEFT", line, "LEFT", 0, 0)
            local inputBox = CreateFrame("EditBox", nil, line)
            inputBox:SetSize(110, 26)
            inputBox:SetPoint("RIGHT", line, "RIGHT", 0, 0)
            inputBox:SetAutoFocus(false)
            inputBox:SetFont(CludesUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 13, "")
            inputBox:SetTextColor(1, 1, 1, 1)
            inputBox:SetTextInsets(8, 8, 0, 0)
            inputBox:SetMaxLetters(24)
            SolidTex(inputBox, "BACKGROUND", 0.10, 0.10, 0.11, 0.9)
            CludesUI.MakeRoundedBorder(inputBox, 1, 1, 1, 0.12)
            inputBox:SetScript("OnEscapePressed", function(self)
                self:ClearFocus()
            end)
            inputBox:SetScript("OnTextChanged", function(self)
                if not dialog._typeGateOn then
                    return
                end
                local ok = strlower(strtrim(self:GetText() or "")) == dialog._typeWant
                dialog._typeGateOk = ok
                dialog._confirmBtn:SetAlpha(ok and 1 or 0.3)
            end)
            inputBox:SetScript("OnEnterPressed", function(self)
                -- The confirm runs first in the keypress, as a click on it
                -- would (a reload it asks for comes first), then the focus clears.
                if dialog._typeGateOk then
                    local click = dialog._confirmBtn:GetScript("OnClick")
                    if click then
                        click(dialog._confirmBtn)
                    end
                end
                self:ClearFocus()
            end)
            line._label = tLbl
            line._box = inputBox
            dialog._typeRow = line
        end
        local line = dialog._typeRow
        dialog._typeGateOn = true
        dialog._typeGateOk = false
        dialog._typeWant = strlower(strtrim(tostring(options.typeToConfirm)))
        line._label:SetText(string.format(CludesUI.L('Type "%s" to enable:'), tostring(options.typeToConfirm)))
        line._box:SetText("")
        line:SetWidth(line._label:GetStringWidth() + 10 + 110)
        line:Show()
    elseif dialog._typeRow then
        dialog._typeRow._box:ClearFocus()
        dialog._typeRow:Hide()
    end
    if padGate then
        local caption = dialog._padGateLbl
        if not caption then
            caption = MakeFont(dialog, 12, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
            caption:SetWidth(dialog:GetWidth() - 2 * DIALOG_PAD)
            caption:SetJustifyH("LEFT")
            dialog._padGateLbl = caption
        end
        dialog._typeGateOn = true
        dialog._typeGateOk = false
        dialog._padGate = true
        caption:SetText(CludesUI.Lf('Press "%1$s" twice to continue.', CludesUI.L(options.confirmText or "Confirm")))
        caption:Show()
    elseif dialog._padGateLbl then
        dialog._padGateLbl:Hide()
    end

    -- Layout: what sits between the header and the footer stacks from the top
    -- in reading order (message, disclaimer, warning, type-to-confirm or the
    -- controller's note, checkbox), each at its measured height, and the
    -- dialog takes exactly that much room. A height the client keeps secret
    -- (a restricted moment) counts as a few lines.
    do
        local function Measure(fs, fallback)
            local h = fs:GetStringHeight() or fallback
            if issecretvalue and issecretvalue(h) then
                h = fallback
            end
            return math.ceil(h)
        end
        local y = DIALOG_HEAD + 14
        local function Stack(region, h, gap)
            region:ClearAllPoints()
            region:SetPoint("TOPLEFT", dialog, "TOPLEFT", DIALOG_PAD, -(y + gap))
            y = y + gap + h
        end
        Stack(dialog._msg, Measure(dialog._msg, 48), 0)
        if dialog._disclaimer:IsShown() then
            Stack(dialog._disclaimer, Measure(dialog._disclaimer, 28), 8)
        end
        if dialog._scaleWarnLabel:IsShown() then
            Stack(dialog._scaleWarnLabel, Measure(dialog._scaleWarnLabel, 24), 10)
        end
        if dialog._typeRow and dialog._typeRow:IsShown() then
            Stack(dialog._typeRow, 26, 14)
        end
        if dialog._padGateLbl and dialog._padGateLbl:IsShown() then
            Stack(dialog._padGateLbl, Measure(dialog._padGateLbl, 14), 14)
        end
        if dialog._cbRow:IsShown() then
            Stack(dialog._cbRow, 18, 12)
        end
        dialog:SetHeight(math.max(CONFIRM_MIN_H, y + 16 + DIALOG_FOOT))
    end
    -- A popup shown again keeps its layer seat: refit for the new height.
    dialog._brd:Fit()
    dialog._cancelBtn._lbl:SetText(CludesUI.L(options.cancelText or "Cancel"))
    dialog._confirmBtn._lbl:SetText(CludesUI.L(options.confirmText or "Confirm"))
    -- onDismiss: called on escape/click-outside. Falls back to onCancel if not provided.
    dialog._onCancel = options.onDismiss or options.onCancel or nil
    dialog._modal = options.modal and true or false
    -- This show's handle (returned below, for CloseConfirmPopup).
    local handle = {}
    dialog._handle = handle

    -- Single-button mode: hide cancel, center confirm
    if options.hideCancel then
        dialog._cancelBtn:Hide()
        dialog._confirmBtn:ClearAllPoints()
        dialog._confirmBtn:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -14, 10)
    else
        dialog._cancelBtn:Show()
        dialog._confirmBtn:ClearAllPoints()
        dialog._confirmBtn:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -14, 10)
    end
    -- Controller cursor: its cancel press backs out through the visible Cancel,
    -- which is also its first stop, only when Cancel is what Escape does (not
    -- for a modal popup, which needs an answer, nor when onDismiss differs).
    if CludesUI.PadCP() then
        local backIsCancel = not (options.hideCancel or options.modal or options.onDismiss)
        dialog.CloseButton = backIsCancel and dialog._cancelBtn or nil
        CludesUI.PadHint(dialog._cancelBtn, "nodepriority", backIsCancel and 1 or false)
    end

    -- Reset hover states
    dialog._cancelBtn._resetAnim()
    dialog._confirmBtn._resetAnim()
    -- confirmDisabled: the confirm stays visible but dark and inert (the
    -- popup is pooled, so both states are re-asserted on every show).
    local confirmOff = options.confirmDisabled and true or false
    dialog._confirmBtn:SetAlpha((dialog._typeGateOn or confirmOff) and 0.3 or 1)
    dialog._confirmBtn:EnableMouse(not confirmOff)

    dialog._cancelBtn:SetScript("OnClick", function()
        dialog._dimmer:Hide()
        if options.onCancel then
            options.onCancel()
        end
    end)

    -- Macro overlay: a protected action (/logout) needs a hardware event routed
    -- through InsecureActionButtonTemplate.
    if options.confirmMacro then
        if not dialog._macroOverlay then
            local ov = CreateFrame(
                "Button",
                "CUIConfirmMacroOverlay",
                dialog._confirmBtn,
                "InsecureActionButtonTemplate"
            )
            ov:SetAllPoints(dialog._confirmBtn)
            ov:SetFrameLevel(dialog._confirmBtn:GetFrameLevel() + 5)
            -- Mouse-up clicks only, and the attribute says so: left unset, the
            -- secure click handler follows the key-down CVar (on by default)
            -- and acts on the press, which an up-only button never delivers.
            ov:RegisterForClicks("AnyUp")
            ov:SetAttribute("useOnKeyDown", false)
            -- Forward hover visuals to the real button underneath
            ov:SetScript("OnEnter", function()
                dialog._confirmBtn:GetScript("OnEnter")(dialog._confirmBtn)
            end)
            ov:SetScript("OnLeave", function()
                dialog._confirmBtn:GetScript("OnLeave")(dialog._confirmBtn)
            end)
            -- Stored callback, not a new hook per ShowConfirmPopup call (they accumulate).
            ov:HookScript("OnClick", function()
                dialog._dimmer:Hide()
                if ov._postAction then
                    ov._postAction()
                end
            end)
            dialog._macroOverlay = ov
        end
        local ov = dialog._macroOverlay
        ov:SetAttribute("type", "macro")
        ov:SetAttribute("macrotext", options.confirmMacro)
        ov._postAction = options.onConfirm
        ov:Show()
        -- Hide the normal confirm click so it doesn't double-fire
        dialog._confirmBtn:SetScript("OnClick", nil)
    else
        if dialog._macroOverlay then
            dialog._macroOverlay:Hide()
        end
        dialog._confirmBtn:SetScript("OnClick", function()
            if options.confirmDisabled then
                return
            end
            if dialog._typeGateOn and not dialog._typeGateOk then
                -- Controller gate: the first press arms, the second confirms.
                if dialog._padGate then
                    dialog._typeGateOk = true
                    dialog._padArmT = GetTime()
                    dialog._confirmBtn:SetAlpha(1)
                    dialog._padGateLbl:SetText(CludesUI.L("Press again to confirm."))
                end
                return
            end
            -- Controller gate: a double tap or a bounced press is not a second press.
            if dialog._padGate and GetTime() - (dialog._padArmT or 0) < 0.5 then
                return
            end
            -- The callback runs before the popup closes, as Blizzard's own
            -- popups do, so a reload it asks for comes first in the click
            -- (RequestReload). The popup then closes only while it still
            -- shows this request: the callback may have opened the next one.
            if options.onConfirm then
                options.onConfirm(dialog._cbChecked)
            end
            if dialog._handle == handle then
                dialog._dimmer:Hide()
            end
        end)
    end

    -- Counter-scale the popup to the options panel (same formula as its root frame, which may not exist yet); the dimmer stays at 1 so it still covers the full screen.
    dialog:SetScale(GetPopupScale())

    dialog._dimmer:Show()
    -- Controller cursor: move it into the popup (the safe button is its first stop).
    CludesUI.PadFocus(dialog)
    return handle
end

-- Closes the confirm popup only while it still shows the request whose handle
-- ShowConfirmPopup returned (the popup is shared, so never another caller's
-- dialog), without running any of its callbacks.
function CludesUI:CloseConfirmPopup(handle)
    local dialog = confirmPopup
    if handle and dialog and dialog._handle == handle then
        dialog._dimmer:Hide()
    end
end

-- There is no beta-reset welcome popup or wipe gate (CludesUI:ShowWelcomePopup does not exist); manual reset lives in Global Settings > Reset.

-------------------------------------------------------------------------------
--  Info dialog: a title, a message and Close.
--  Usage:  CludesUI:ShowInfoPopup({ title, content, width, height })
--  The dialog fits its message: a short note gets a short dialog, a long one
--  grows to `height` (default 420) and scrolls past that. `width` defaults to
--  400. Escape, a click outside it and a controller's back press close it.
-------------------------------------------------------------------------------
local info -- the dialog, built on first use: { dimmer, frame, title, text, scroll, child, ScrollTo, UpdateBar }

local INFO = { W = 400, MAX_H = 420, MIN_TEXT = 36, TEXT_PAD = 12 }

local function BuildInfoDialog()
    local shade = CreateFrame("Frame", "CUIInfoDimmer", UIParent)
    shade:SetFrameStrata("FULLSCREEN_DIALOG")
    shade:SetAllPoints(UIParent)
    shade:EnableMouse(true)
    shade:EnableMouseWheel(true)
    shade:SetScript("OnMouseWheel", function() end) -- the world under it does not zoom
    shade:Hide()
    SolidTex(shade, "BACKGROUND", 0, 0, 0, 0.25):SetAllPoints()

    local frame = CreateFrame("Frame", "CUIInfoPopup", shade)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(shade:GetFrameLevel() + 10)
    frame:EnableMouse(true)
    local bg = SolidTex(frame, "BACKGROUND", 0.062, 0.070, 0.082, 1)
    bg:SetAllPoints()
    -- Radius 4 as the other dialogs: the size is not known yet, so the automatic
    -- choice (by size) would take a control's 2.
    CludesUI.MakeRoundedBorder(frame, BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.15, bg, 4)
    DressDialog(frame)

    local title = MakeFont(frame, 15, "", 1, 1, 1)

    local scroll = CreateFrame("ScrollFrame", nil, frame)
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", DIALOG_PAD, -(DIALOG_HEAD + INFO.TEXT_PAD))
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -DIALOG_PAD, DIALOG_FOOT + INFO.TEXT_PAD)
    scroll:SetFrameLevel(frame:GetFrameLevel() + 1)
    scroll:EnableMouseWheel(true)
    local child = CreateFrame("Frame", nil, scroll)
    scroll:SetScrollChild(child)
    local text = child:CreateFontString(nil, "OVERLAY")
    text:SetFont(CludesUI.EXPRESSWAY, 12, "")
    text:SetTextColor(TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, 0.85)
    text:SetPoint("TOPLEFT")
    text:SetJustifyH("LEFT")
    text:SetWordWrap(true)
    text:SetSpacing(3)
    local UpdateBar, ScrollTo = CludesUI.AttachSmoothScrollbar(scroll, { child = child })

    local close = CreateFrame("Button", nil, frame)
    close:SetSize(100, 26)
    close:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, 10)
    close:SetFrameLevel(frame:GetFrameLevel() + 2)
    CludesUI.MakeStyledButton(close, "Close", 11, CludesUI.RB_COLOURS, function()
        shade:Hide()
    end)
    if CludesUI.PadCP() then
        frame.CloseButton = close -- a controller's back press closes through it
    end

    shade:SetScript("OnMouseDown", function()
        if not frame:IsMouseOver() then
            shade:Hide()
        end
    end)
    WirePopupEscape(frame, shade)
    shade:HookScript("OnHide", function()
        ScrollTo(0) -- the next message starts at its top
    end)

    frame._dimmer = shade -- the shared popup helpers read the dimmer from here
    info = {
        dimmer = shade,
        frame = frame,
        title = title,
        text = text,
        scroll = scroll,
        child = child,
        ScrollTo = ScrollTo,
        UpdateBar = UpdateBar,
    }
    return info
end

-- Sizes the dialog to its message: width w, height up to maxH.
local function FitInfoDialog(infoDialog, w, maxH)
    local textW = w - 2 * DIALOG_PAD - 10 -- room for the scroll bar
    infoDialog.frame:SetWidth(w)
    PlaceDialogTitle(infoDialog.frame, infoDialog.title, w)
    infoDialog.child:SetWidth(textW)
    infoDialog.text:SetWidth(textW)
    local textH = infoDialog.text:GetStringHeight() or 0
    if issecretvalue and issecretvalue(textH) then
        textH = maxH -- unreadable in a restricted moment: take the full size and scroll
    end
    textH = math.max(INFO.MIN_TEXT, math.ceil(textH))
    -- Exactly the text's height: the visible area is textH tall when it fits,
    -- so anything taller would show a scroll bar for a short message.
    infoDialog.child:SetHeight(textH)
    local chrome = DIALOG_HEAD + DIALOG_FOOT + 2 * INFO.TEXT_PAD
    -- One pixel of slack, so rounding at the UI scale can never leave a sliver to scroll.
    infoDialog.frame:SetHeight(math.min(maxH, chrome + textH + 1))
    infoDialog.UpdateBar()
end

function CludesUI:ShowInfoPopup(options)
    options = options or {}
    if CludesUI.HideWidgetTooltip then
        CludesUI.HideWidgetTooltip()
    end
    local infoDialog = info or BuildInfoDialog()
    infoDialog.title:SetText(CludesUI.L(options.title or "Information"))
    infoDialog.text:SetText(options.content and CludesUI.L(options.content) or "")
    FitInfoDialog(infoDialog, options.width or INFO.W, options.height or INFO.MAX_H)
    infoDialog.ScrollTo(0)
    infoDialog.dimmer:Show()
    CludesUI.PadFocus(infoDialog.frame) -- a controller's cursor moves into the dialog
end

-------------------------------------------------------------------------------
--  Custom Input Popup  (matches CludesUI aesthetic, with EditBox)
--  Usage:  CludesUI:ShowInputPopup({ title, message, placeholder, confirmText, cancelText, onConfirm, onCancel })
--          onConfirm receives the entered text as its first argument. A copy box for
--          a link: initialText + selectText (starts selected) + hideCancel (one button).
--          infoTooltip (string or function) adds a hover info badge left of the input;
--          infoTooltipOpts go to ShowWidgetTooltip, anchored to the popup frame.
--          preview(text) returns a preview line (under the input, below previewLabel,
--          in previewColor) and a hint line. complete(text, cursor) returns
--          items { text, label, desc, detail }, from, to: a suggestion list under the input
--          (Up/Down select, Tab inserts, Esc closes it). messageSize sets the message size,
--          messageColor { r, g, b[, a] } its colour (a red note). warning adds an
--          orange line under the input, redWarning a red one below it. numeric takes digits
--          only. validate(text) runs on a confirm: a message it returns shows in red under
--          the input and keeps the popup open. checkbox (a label) adds a box above the
--          buttons, unchecked on each show; onConfirm then receives its state second.
--          money swaps the text box for gold/silver/copper boxes, onConfirm
--          then gets the total in copper.
-------------------------------------------------------------------------------
local MONEY_ICONS = {
    "Interface\\MoneyFrame\\UI-GoldIcon",
    "Interface\\MoneyFrame\\UI-SilverIcon",
    "Interface\\MoneyFrame\\UI-CopperIcon",
}

-- opts.money: three number boxes with coin icons in the input frame (built on
-- first use). tab / shift-tab jumps between them.
local function BuildMoneyRow(dialog)
    if dialog._moneyRow then
        return
    end
    local line = CreateFrame("Frame", nil, dialog._inputFrame)
    line:SetAllPoints()
    line:SetFrameLevel(dialog._inputFrame:GetFrameLevel() + 1)
    local boxes, widths = {}, { 100, 36, 36 }
    local x = 12
    for i = 1, 3 do
        local entry = CreateFrame("EditBox", nil, line)
        entry:SetPoint("TOPLEFT", line, "TOPLEFT", x, -1)
        entry:SetPoint("BOTTOMLEFT", line, "BOTTOMLEFT", x, 1)
        entry:SetWidth(widths[i])
        entry:SetFont(CludesUI.EXPRESSWAY, 11, "")
        entry:SetTextColor(1, 1, 1, 0.9)
        entry:SetJustifyH("RIGHT")
        entry:SetAutoFocus(false)
        entry:SetNumeric(true)
        entry:SetMaxLetters(i == 1 and 7 or 2)
        local zero = entry:CreateFontString(nil, "ARTWORK")
        zero:SetFont(CludesUI.EXPRESSWAY, 11, "")
        zero:SetTextColor(TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a * 0.5)
        zero:SetPoint("RIGHT")
        zero:SetText("0")
        entry:SetScript("OnTextChanged", function(self)
            zero:SetShown((self:GetText() or "") == "")
        end)
        entry:SetScript("OnEnterPressed", function()
            dialog._tryConfirm()
        end)
        entry:SetScript("OnEscapePressed", function()
            dialog._dimmer:Hide()
            if dialog._onCancel then
                dialog._onCancel()
            end
        end)
        entry:SetScript("OnTabPressed", function()
            boxes[(i - 1 + (IsShiftKeyDown() and 2 or 1)) % 3 + 1]:SetFocus()
        end)
        local coin = line:CreateTexture(nil, "ARTWORK")
        coin:SetSize(13, 13)
        coin:SetPoint("LEFT", entry, "RIGHT", 4, 0)
        coin:SetTexture(MONEY_ICONS[i])
        boxes[i] = entry
        x = x + widths[i] + 4 + 13 + 14
    end
    dialog._moneyRow, dialog._moneyBoxes = line, boxes
    -- silver and copper past 99 count as 99
    dialog._moneyValue = function()
        local function N(entry)
            return tonumber(entry:GetText()) or 0
        end
        return N(boxes[1]) * 10000 + math.min(N(boxes[2]), 99) * 100 + math.min(N(boxes[3]), 99)
    end
end

function CludesUI:ShowInputPopup(options)
    if not self._inputPopup then
        local POPUP_W, POPUP_H = 390, 194

        local shade = CreateFrame("Frame", "CUIInputDimmer", UIParent)
        shade:SetFrameStrata("FULLSCREEN_DIALOG")
        shade:SetAllPoints(UIParent)
        shade:EnableMouse(true)
        shade:EnableMouseWheel(true)
        shade:SetScript("OnMouseWheel", function() end)
        shade:Hide()

        local dimTex = SolidTex(shade, "BACKGROUND", 0, 0, 0, 0.25)
        dimTex:SetAllPoints()

        local dialog = CreateFrame("Frame", "CUIInputPopup", shade)
        dialog:SetSize(POPUP_W, POPUP_H)
        dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:SetFrameLevel(shade:GetFrameLevel() + 10)

        local popBgFlat = SolidTex(dialog, "BACKGROUND", 0.062, 0.070, 0.082, 1)
        popBgFlat:SetAllPoints()
        local dialogArt = dialog:CreateTexture(nil, "BACKGROUND")
        dialogArt:SetTexture("Interface\\AddOns\\CludesUI\\media\\modern_blizz.png")
        dialogArt:SetTexCoord(0.25, 1, 0, 0.75)
        dialogArt:SetAllPoints()
        dialogArt:Hide()
        local dialogTint = dialog:CreateTexture(nil, "BACKGROUND", nil, 1)
        dialogTint:SetColorTexture(0, 0, 0, 0.6)
        dialogTint:SetAllPoints()
        dialogTint:Hide()
        dialog._popBgFlat = popBgFlat
        dialog._popBgAtlas = dialogArt
        dialog._popBgOverlay = dialogTint

        dialog._brd =
            CludesUI.MakeRoundedBorder(dialog, BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.15, popBgFlat)
        CludesUI.RoundBody(dialog, dialogArt)
        CludesUI.RoundBody(dialog, dialogTint)
        DressDialog(dialog)

        local title = MakeFont(dialog, 15, "", 1, 1, 1)
        PlaceDialogTitle(dialog, title, POPUP_W)
        dialog._title = title

        -- Optional info badge left of the input (opts.infoTooltip): hover text only.
        local info = CreateFrame("Frame", nil, dialog)
        PanelPP.Size(info, 14, 14)
        info:SetFrameLevel(dialog:GetFrameLevel() + 3)
        info:EnableMouse(true)
        local infoIco = info:CreateTexture(nil, "OVERLAY")
        infoIco:SetAllPoints()
        infoIco:SetTexture("Interface\\AddOns\\CludesUI\\media\\icons\\cui-info.png")
        infoIco:SetVertexColor(1, 1, 1, 0.6)
        info:SetScript("OnEnter", function(self)
            infoIco:SetVertexColor(1, 1, 1, 1)
            if self._tip then
                self._tipShown = true
                CludesUI.ShowWidgetTooltip(self._tipOpts and dialog or self, self._tip, self._tipOpts)
            end
        end)
        local function InfoLeave(self)
            infoIco:SetVertexColor(1, 1, 1, 0.6)
            if self._tipShown then
                self._tipShown = nil
                CludesUI.HideWidgetTooltip()
            end
        end
        info:SetScript("OnLeave", InfoLeave)
        -- Closing the popup under the cursor: drop the tooltip without relying on OnLeave.
        info:SetScript("OnHide", InfoLeave)
        info:Hide()
        dialog._info = info

        local messageText = MakeFont(dialog, 12, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
        messageText:SetPoint("TOP", dialog, "TOP", 0, -(DIALOG_HEAD + 12))
        messageText:SetWidth(POPUP_W - 60)
        messageText:SetJustifyH("CENTER")
        messageText:SetWordWrap(true)
        messageText:SetSpacing(4)
        dialog._msg = messageText

        local INPUT_W, INPUT_H = 270, 28
        local inputFrame = CreateFrame("Frame", nil, dialog)
        inputFrame:SetSize(INPUT_W, INPUT_H)
        inputFrame:SetPoint("TOP", messageText, "BOTTOM", 0, -12)
        inputFrame:SetFrameLevel(dialog:GetFrameLevel() + 2)

        local iBg = SolidTex(inputFrame, "BACKGROUND", 0, 0, 0, 0.5)
        iBg:SetAllPoints()
        local iBrd = CludesUI.MakeRoundedBorder(inputFrame, 1, 1, 1, 0.2, iBg)

        -- Red flash animation for empty-input validation
        local FLASH_DUR = 0.7
        local flashElapsed = 0
        local flashing = false
        local flashFrame = CreateFrame("Frame", nil, inputFrame)
        flashFrame:Hide()
        flashFrame:SetScript("OnUpdate", function(self, elapsed)
            flashElapsed = flashElapsed + elapsed
            if flashElapsed >= FLASH_DUR then
                flashing = false
                self:Hide()
                iBrd:SetColor(1, 1, 1, 0.2)
                return
            end
            local t = flashElapsed / FLASH_DUR
            local r = lerp(0.9, 1, t)
            local g = lerp(0.15, 1, t)
            local b = lerp(0.15, 1, t)
            local a = lerp(0.7, 0.2, t)
            iBrd:SetColor(r, g, b, a)
        end)

        dialog._flashEmpty = function()
            flashElapsed = 0
            flashing = true
            iBrd:SetColor(0.9, 0.15, 0.15, 0.7)
            flashFrame:Show()
            dialog._focusInput()
        end

        local textInput = CreateFrame("EditBox", nil, inputFrame)
        textInput:SetPoint("TOPLEFT", 12, -1)
        textInput:SetPoint("BOTTOMRIGHT", -12, 1)
        textInput:SetFont(CludesUI.EXPRESSWAY, 11, "")
        textInput:SetTextColor(1, 1, 1, 0.9)
        textInput:SetAutoFocus(false)
        textInput:SetMaxLetters(30)

        local placeholder = textInput:CreateFontString(nil, "ARTWORK")
        placeholder:SetFont(CludesUI.EXPRESSWAY, 11, "")
        placeholder:SetTextColor(TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a * 0.5)
        placeholder:SetPoint("LEFT", textInput, "LEFT", 0, 0)
        dialog._placeholder = placeholder

        textInput:SetScript("OnTextChanged", function(self)
            local text = self:GetText() or ""
            if text == "" then
                placeholder:Show()
            else
                placeholder:Hide()
            end
            if dialog._statusShown then
                dialog._statusShown = nil
                dialog._statusLabel:SetText("")
            end
            if dialog._maxCount then
                local count = strlenutf8 and strlenutf8(text) or #text
                dialog._countLabel:SetText(count .. "/" .. dialog._maxCount)
            end
            if dialog._preview then
                dialog._updatePreview(text)
            end
            if dialog._complete then
                dialog._updateSuggest(text)
            end
        end)
        -- Suggestion list keys (opts.complete): Up/Down move the selection, Tab
        -- inserts it. Same arrow handling as the panel's global search box.
        textInput:SetScript("OnTabPressed", function()
            if dialog._suggest then
                dialog._acceptSuggest()
            end
        end)
        textInput:SetScript("OnArrowPressed", function(_, key)
            if not dialog._suggest then
                return
            end
            if key == "UP" then
                dialog._stepSuggest(-1)
            elseif key == "DOWN" then
                dialog._stepSuggest(1)
            end
        end)
        dialog._editBox = textInput

        -- Optional warning text (shown below the input field)
        local warnLabel = MakeFont(dialog, 10, nil, 1, 0.65, 0.2, 0.85)
        warnLabel:SetPoint("TOP", inputFrame, "BOTTOM", 0, -8)
        warnLabel:SetWidth(POPUP_W - 40)
        warnLabel:SetJustifyH("CENTER")
        warnLabel:SetWordWrap(true)
        warnLabel:SetSpacing(2)
        warnLabel:Hide()
        dialog._warnLabel = warnLabel
        dialog._inputFrame = inputFrame -- store so reuse block can anchor against it
        PanelPP.Point(info, "RIGHT", inputFrame, "LEFT", -8, 0)

        -- A message from opts.validate, right under the input (each show anchors
        -- it); it clears when the text changes.
        local statusLabel = MakeFont(dialog, 11, nil, 1, 0.3, 0.3, 1)
        statusLabel:SetWidth(POPUP_W - 40)
        statusLabel:SetJustifyH("CENTER")
        statusLabel:SetWordWrap(false)
        dialog._statusLabel = statusLabel

        -- Optional checkbox (above the buttons, centred)
        MakePopupCheckbox(dialog, POPUP_W - 60)

        -- Optional scale/resolution mismatch warning (red, shown below the orange warning)
        local scaleWarnLabel = MakeFont(dialog, 10, nil, 1, 0.2, 0.2, 1)
        scaleWarnLabel:SetWidth(POPUP_W - 40)
        scaleWarnLabel:SetJustifyH("CENTER")
        scaleWarnLabel:SetWordWrap(true)
        scaleWarnLabel:SetSpacing(2)
        scaleWarnLabel:Hide()
        dialog._scaleWarnLabel = scaleWarnLabel

        -- Optional extra button (shown above the input field, e.g. "Add Current Zone")
        local EXTRA_BTN_W, EXTRA_BTN_H = 160, 28
        local extraBtn = CreateFrame("Button", nil, dialog)
        extraBtn:SetSize(EXTRA_BTN_W, EXTRA_BTN_H)
        extraBtn:SetPoint("TOP", inputFrame, "BOTTOM", 0, -6)
        extraBtn:SetFrameLevel(dialog:GetFrameLevel() + 2)
        local extraBg = SolidTex(extraBtn, "BACKGROUND", 0, 0, 0, 0.5)
        extraBg:SetAllPoints()
        CludesUI.MakeRoundedBorder(extraBtn, 1, 1, 1, 0.25, extraBg)
        local extraLbl = MakeFont(extraBtn, 12, nil, 1, 1, 1)
        extraLbl:SetAlpha(0.6)
        extraLbl:SetPoint("CENTER")
        do
            local FADE_DUR = 0.1
            local progress, target = 0, 0
            local function Apply(t)
                extraLbl:SetTextColor(1, 1, 1, lerp(0.6, 0.9, t))
            end
            local function OnUpdate(self, elapsed)
                local dir = (target == 1) and 1 or -1
                progress = progress + dir * (elapsed / FADE_DUR)
                if (dir == 1 and progress >= 1) or (dir == -1 and progress <= 0) then
                    progress = target
                    self:SetScript("OnUpdate", nil)
                end
                Apply(progress)
            end
            extraBtn:SetScript("OnEnter", function(self)
                target = 1
                self:SetScript("OnUpdate", OnUpdate)
            end)
            extraBtn:SetScript("OnLeave", function(self)
                target = 0
                self:SetScript("OnUpdate", OnUpdate)
            end)
            extraBtn._resetAnim = function()
                progress = 0
                target = 0
                Apply(0)
                extraBtn:SetScript("OnUpdate", nil)
            end
        end
        extraBtn:Hide()
        dialog._extraBtn = extraBtn
        dialog._extraLbl = extraLbl

        local BTN_GAP = 8
        local BTN_Y = 10

        local EG = CLUDES_GREEN
        local cancelBtn = CludesUI.MakePopupButton(
            dialog,
            "BOTTOMRIGHT",
            dialog,
            "BOTTOMRIGHT",
            -(14 + 125 + BTN_GAP),
            BTN_Y,
            1,
            1,
            1,
            0.7,
            1,
            1,
            1,
            0.9,
            1,
            1,
            1,
            0.5,
            1,
            1,
            1,
            0.6
        )
        local confirmBtn = CludesUI.MakePopupButton(
            dialog,
            "BOTTOMRIGHT",
            dialog,
            "BOTTOMRIGHT",
            -14,
            BTN_Y,
            EG.r,
            EG.g,
            EG.b,
            0.9,
            EG.r,
            EG.g,
            EG.b,
            1,
            EG.r,
            EG.g,
            EG.b,
            0.9,
            EG.r,
            EG.g,
            EG.b,
            1
        )

        dialog._cancelBtn = cancelBtn
        dialog._confirmBtn = confirmBtn
        dialog._btnGap, dialog._btnY = BTN_GAP, BTN_Y

        dialog:EnableMouse(true)
        shade:SetScript("OnMouseDown", function()
            if not dialog:IsMouseOver() then
                shade:Hide()
                if dialog._onCancel then
                    dialog._onCancel()
                end
            end
        end)

        WirePopupEscape(dialog, shade)

        -- The one confirm path (the confirm button and Enter). A message from
        -- opts.validate keeps the popup open. The callback runs before the
        -- popup closes, so a reload it asks for comes first in the click or
        -- keypress (RequestReload); the popup closes only while it still shows
        -- the same request (the callback may have opened the next one).
        dialog._tryConfirm = function()
            -- money boxes: total in copper, has to be more than zero
            if dialog._money then
                local copper = dialog._moneyValue()
                if copper <= 0 then
                    dialog._flashEmpty()
                    return
                end
                local shown, cb = dialog._handle, dialog._onConfirmCb
                if cb then
                    cb(copper)
                end
                if dialog._handle == shown then
                    shade:Hide()
                end
                return
            end
            local txt = textInput:GetText()
            if not txt or (txt == "" and not dialog._allowEmpty) then
                dialog._flashEmpty()
                return
            end
            local err = dialog._validate and dialog._validate(txt)
            if err then
                dialog._statusLabel:SetText(CludesUI.L(err))
                dialog._statusShown = true
                dialog._flashEmpty()
                return
            end
            if dialog._closePicker then
                dialog._closePicker()
            end
            local shown, cb = dialog._handle, dialog._onConfirmCb
            if cb then
                if dialog._cbRow:IsShown() then
                    cb(txt, dialog._cbChecked)
                else
                    cb(txt)
                end
            end
            if dialog._handle == shown then
                shade:Hide()
            end
        end
        confirmBtn:SetScript("OnClick", dialog._tryConfirm)

        textInput:SetScript("OnEnterPressed", function()
            if dialog._multiline then
                return
            end
            -- An open suggestion list takes Enter like Tab.
            if dialog._suggest then
                dialog._acceptSuggest()
                return
            end
            dialog._tryConfirm()
        end)
        textInput:SetScript("OnEscapePressed", function()
            -- An open suggestion list closes first.
            if dialog._suggest then
                dialog._closeSuggest()
                return
            end
            shade:Hide()
            if dialog._onCancel then
                dialog._onCancel()
            end
        end)

        dialog._focusInput = function()
            local inputBox = dialog._money and dialog._moneyBoxes[1] or dialog._editBox
            inputBox:SetFocus()
            return inputBox
        end

        dialog._dimmer = shade
        self._inputPopup = dialog
    end

    local dialog = self._inputPopup

    -- Create-once singleton: its creation-time frame level loses to any FULLSCREEN_DIALOG
    -- frame born later (popup dimmers ~1-11, dropdown menus at 200), which then draws OVER
    -- this modal; re-raise on every show (descendants shift with the parent, keeping relative offsets).
    dialog._dimmer:SetFrameLevel(300)

    -- Background style: flat (default) or modern Blizzard stone
    local modern = options.modernBlizz
    dialog._popBgFlat:SetShown(not modern)
    dialog._popBgAtlas:SetShown(modern == true)
    dialog._popBgOverlay:SetShown(modern == true)

    dialog._title:SetText(CludesUI.L(options.title or "Enter Name"))
    dialog._info._tip = options.infoTooltip
    dialog._info._tipOpts = options.infoTooltipOpts
    dialog._info:SetShown(options.infoTooltip ~= nil)
    -- Optional colour swatch left of the input (opts.swatch = { get, onClick,
    -- tooltip }), built on its first use. It is painted from get() -> r, g, b
    -- as the popup shows and each time the caller's onClick(swatch, repaint)
    -- calls repaint(). The caller opens the colour picker, and an open one
    -- closes with the popup: before a confirm runs its callback, and when the
    -- popup is dismissed (so the picker's own cancel comes first).
    local sw = options.swatch
    if sw and not dialog._swatch then
        local swatch = CreateFrame("Button", nil, dialog)
        PanelPP.Size(swatch, 20, 20)
        PanelPP.Point(swatch, "RIGHT", dialog._inputFrame, "LEFT", -8, 0)
        swatch:SetFrameLevel(dialog:GetFrameLevel() + 3)
        local fill = SolidTex(swatch, "ARTWORK", 1, 1, 1, 1)
        fill:SetAllPoints()
        CludesUI.MakeRoundedBorder(swatch, 1, 1, 1, 0.9, fill)
        dialog._paintSwatch = function()
            local swatchOpts = dialog._swatchOpts
            if not swatchOpts then
                return
            end
            local red, green, blue = swatchOpts.get()
            fill:SetColorTexture(red or 1, green or 1, blue or 1, 1)
        end
        dialog._closePicker = function()
            local picker = dialog._swatchOpts and CludesUI._colorPickerPopup
            if picker and picker:IsShown() then
                picker:Hide()
            end
        end
        swatch:SetScript("OnClick", function(self)
            local swatchOpts = dialog._swatchOpts
            if swatchOpts and swatchOpts.onClick then
                swatchOpts.onClick(self, dialog._paintSwatch)
            end
        end)
        swatch:SetScript("OnEnter", function(self)
            local swatchOpts = dialog._swatchOpts
            if swatchOpts and swatchOpts.tooltip then
                self._tipShown = true
                CludesUI.ShowWidgetTooltip(self, CludesUI.L(swatchOpts.tooltip))
            end
        end)
        local function SwatchLeave(self)
            if self._tipShown then
                self._tipShown = nil
                CludesUI.HideWidgetTooltip()
            end
        end
        swatch:SetScript("OnLeave", SwatchLeave)
        swatch:SetScript("OnHide", SwatchLeave)
        dialog._dimmer:HookScript("OnHide", dialog._closePicker)
        dialog._swatch = swatch
    end
    dialog._swatchOpts = sw
    if dialog._swatch then
        dialog._swatch:SetShown(sw ~= nil)
        if sw then
            dialog._paintSwatch()
        end
        -- The info badge steps left of a shown swatch
        dialog._info:ClearAllPoints()
        PanelPP.Point(dialog._info, "RIGHT", sw and dialog._swatch or dialog._inputFrame, "LEFT", -8, 0)
    end
    dialog._msg:SetText(CludesUI.L(options.message or ""))
    dialog._placeholder:SetText(CludesUI.L(options.placeholder or "Enter name..."))
    dialog._cancelBtn._lbl:SetText(CludesUI.L(options.cancelText or "Cancel"))
    dialog._confirmBtn._lbl:SetText(CludesUI.L(options.confirmText or "Save"))
    -- Single-button mode (a copy box): hide Cancel, centre the confirm button.
    dialog._cancelBtn:SetShown(not options.hideCancel)
    dialog._confirmBtn:ClearAllPoints()
    if options.hideCancel then
        dialog._confirmBtn:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -14, dialog._btnY)
    else
        dialog._confirmBtn:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -14, dialog._btnY)
    end
    dialog._selectText = options.selectText == true
    dialog._onCancel = options.onDismiss or options.onCancel or nil
    dialog._onConfirmCb = options.onConfirm or nil
    -- This show's request: a confirm closes the popup only while it still shows it.
    dialog._handle = {}
    dialog._allowEmpty = options.allowEmpty == true
    dialog._multiline = options.multiline == true
    dialog._validate = options.validate
    dialog._money = options.money == true
    if dialog._money then
        BuildMoneyRow(dialog)
        for _, entry in ipairs(dialog._moneyBoxes) do
            entry:SetText("")
        end
    end
    if dialog._moneyRow then
        dialog._moneyRow:SetShown(dialog._money)
    end
    dialog._editBox:SetShown(not dialog._money)
    dialog._statusShown = nil
    dialog._statusLabel:SetText("")

    dialog._editBox:SetNumeric(options.numeric == true)
    dialog._editBox:SetMaxLetters(options.maxLetters or 30)
    dialog._editBox:SetMultiLine(dialog._multiline)
    dialog._editBox:SetJustifyV(dialog._multiline and "TOP" or "MIDDLE")
    dialog._inputFrame:SetHeight(options.inputHeight or 28)
    dialog._editBox:ClearAllPoints()
    dialog._editBox:SetPoint("TOPLEFT", dialog._inputFrame, "TOPLEFT", 12, dialog._multiline and -8 or -1)
    -- A multi-line box keeps the letter count inside its bottom-right corner,
    -- under the text; a single-line box has no room under its text, so its
    -- count sits beside its right edge and the box keeps its full height.
    local countInside = options.showCount and dialog._multiline
    dialog._editBox:SetPoint("BOTTOMRIGHT", dialog._inputFrame, "BOTTOMRIGHT", -12, countInside and 18 or 1)
    dialog._placeholder:ClearAllPoints()
    if dialog._multiline then
        dialog._placeholder:SetPoint("TOPLEFT", dialog._editBox, "TOPLEFT", 0, -1)
    else
        dialog._placeholder:SetPoint("LEFT", dialog._editBox, "LEFT", 0, 0)
    end
    if options.showCount and not dialog._countLabel then
        dialog._countLabel =
            MakeFont(dialog._inputFrame, 9, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
    end
    dialog._maxCount = options.showCount and (options.maxLetters or 0) or nil
    if dialog._countLabel then
        dialog._countLabel:SetShown(dialog._maxCount and dialog._maxCount > 0)
        dialog._countLabel:ClearAllPoints()
        if countInside then
            dialog._countLabel:SetPoint("BOTTOMRIGHT", dialog._inputFrame, "BOTTOMRIGHT", -8, 5)
        else
            dialog._countLabel:SetPoint("LEFT", dialog._inputFrame, "RIGHT", 8, 0)
        end
    end
    dialog._msg:SetFont(CludesUI.EXPRESSWAY, options.messageSize or 12, "")
    local mc = options.messageColor or TEXT_DIM
    dialog._msg:SetTextColor(mc.r, mc.g, mc.b, mc.a or 1)
    -- Optional preview block under the input (opts.preview), centred, one line
    -- each at a fixed height so typing never re-lays out the popup; the
    -- suggestion list (opts.complete) floats over it.
    local belowH = 0
    dialog._preview, dialog._complete = options.preview, options.complete
    if (options.preview or options.complete) and not dialog._previewValue then
        local inputW = dialog._inputFrame:GetWidth()
        local div = SolidTex(dialog, "ARTWORK", 1, 1, 1, 0.1)
        PanelPP.Size(div, inputW, 1)
        PanelPP.Point(div, "TOP", dialog._inputFrame, "BOTTOM", 0, -10)
        local label = MakeFont(dialog, 10, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
        label:SetPoint("TOP", div, "BOTTOM", 0, -6)
        local value = MakeFont(dialog, 12, nil, 1, 1, 1, 1)
        value:SetPoint("TOP", label, "BOTTOM", 0, -3)
        value:SetWidth(dialog:GetWidth() - 40)
        value:SetJustifyH("CENTER")
        value:SetWordWrap(false)
        local hint = MakeFont(dialog, 10, nil, 1, 0.65, 0.2, 0.85)
        hint:SetPoint("TOP", value, "BOTTOM", 0, -4)
        hint:SetWidth(dialog:GetWidth() - 40)
        hint:SetJustifyH("CENTER")
        hint:SetWordWrap(false)
        dialog._previewDiv, dialog._previewLabelFS, dialog._previewValue, dialog._hintLabel =
            div, label, value, hint
        dialog._updatePreview = function(text)
            local line, note = dialog._preview(text)
            value:SetText(line or "")
            hint:SetText(note or "")
        end

        -- Suggestion list: up to ROWS entries (the window follows the
        -- selection or the mouse wheel), each with its description and the
        -- sample on the right, a scrollbar when more entries exist, and a key
        -- legend.
        local ROWS, ROW_H = 6, 16
        local dropList = CreateFrame("Frame", nil, dialog)
        dropList:SetFrameLevel(dialog:GetFrameLevel() + 20)
        dropList:SetPoint("TOPLEFT", dialog._inputFrame, "BOTTOMLEFT", 0, -2)
        dropList:SetWidth(inputW)
        -- Full height up front: the outline's body mask (shared by the rows) is
        -- shaped once here and keeps that radius for every later row count.
        dropList:SetHeight(ROWS * ROW_H + 21)
        dropList:EnableMouse(true)
        local ddBg = SolidTex(dropList, "BACKGROUND", 0.04, 0.035, 0.03, 0.97)
        ddBg:SetAllPoints()
        dropList._brd = CludesUI.MakeRoundedBorder(dropList, 1, 1, 1, 0.2, ddBg)
        local rows = {}
        for i = 1, ROWS do
            local line = CreateFrame("Button", nil, dropList)
            line:SetHeight(ROW_H)
            line:SetPoint("TOPLEFT", dropList, "TOPLEFT", 1, -1 - (i - 1) * ROW_H)
            line:SetPoint("TOPRIGHT", dropList, "TOPRIGHT", -1, -1 - (i - 1) * ROW_H)
            line._sel = SolidTex(line, "BACKGROUND", 1, 1, 1, 0.18)
            line._sel:SetAllPoints()
            -- The list's shape: the first row keeps its round corners.
            line._sel:AddMaskTexture(dropList._brd.bodyMask)
            line._bar = SolidTex(line, "ARTWORK", 1, 1, 1, 1)
            line._bar:AddMaskTexture(dropList._brd.bodyMask)
            line._bar:SetPoint("TOPLEFT")
            line._bar:SetPoint("BOTTOMLEFT")
            PanelPP.Width(line._bar, 2)
            line._key = MakeFont(line, 11, nil, 1, 1, 1, 0.9)
            line._key:SetPoint("LEFT", line, "LEFT", 8, 0)
            line._detail = MakeFont(line, 10, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
            line._detail:SetPoint("RIGHT", line, "RIGHT", -8, 0)
            line._desc = MakeFont(line, 10, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
            line._desc:SetPoint("LEFT", line, "LEFT", 104, 0)
            line._desc:SetPoint("RIGHT", line._detail, "LEFT", -8, 0)
            line._desc:SetJustifyH("LEFT")
            line._desc:SetWordWrap(false)
            line:SetScript("OnClick", function(self)
                local suggest = dialog._suggest
                if suggest then
                    suggest.sel = suggest.offset + self._index
                    dialog._acceptSuggest()
                end
            end)
            rows[i] = line
        end
        -- Scrollbar in the house look (AttachSmoothScrollbar's alphas), sized
        -- to the row window, on its own frame so it draws above the rows.
        local bar = CreateFrame("Frame", nil, dropList)
        bar:SetFrameLevel(dropList:GetFrameLevel() + 5)
        bar:SetPoint("TOPRIGHT", dropList, "TOPRIGHT", -2, -2)
        PanelPP.Size(bar, 3, ROWS * ROW_H - 2)
        local track = SolidTex(bar, "ARTWORK", 1, 1, 1, 0.02)
        track:SetAllPoints()
        local thumb = SolidTex(bar, "OVERLAY", 1, 1, 1, 0.27)
        PanelPP.Width(thumb, 3)
        local legend = MakeFont(dropList, 10, nil, TEXT_DIM.r, TEXT_DIM.g, TEXT_DIM.b, TEXT_DIM.a)
        legend:SetText(CludesUI.L("Up/Down: select   Tab/Enter: insert   Esc: close"))
        local legendDiv = SolidTex(dropList, "ARTWORK", 1, 1, 1, 0.1)
        legendDiv:SetHeight(1)
        dropList:Hide()
        dialog._suggestDD = dropList

        local function Render()
            local suggest, EGC = dialog._suggest, CludesUI.CLUDES_GREEN
            local n = math.min(#suggest.items, ROWS)
            for i = 1, ROWS do
                local line, item = rows[i], suggest.items[suggest.offset + i]
                if i <= n and item then
                    line._index = i
                    line._key:SetText(item.label)
                    line._desc:SetText(item.desc or "")
                    line._detail:SetText(item.detail or "")
                    local on = suggest.offset + i == suggest.sel
                    if on then
                        line._sel:SetColorTexture(EGC.r, EGC.g, EGC.b, 0.18)
                        line._bar:SetColorTexture(EGC.r, EGC.g, EGC.b, 1)
                    end
                    line._sel:SetShown(on)
                    line._bar:SetShown(on)
                    line:Show()
                else
                    line:Hide()
                end
            end
            local total = #suggest.items
            local more = total > ROWS
            track:SetShown(more)
            thumb:SetShown(more)
            if more then
                local trackH = ROWS * ROW_H - 2
                local thumbH = math.max(12, trackH * ROWS / total)
                thumb:SetHeight(thumbH)
                thumb:ClearAllPoints()
                thumb:SetPoint(
                    "TOPRIGHT",
                    track,
                    "TOPRIGHT",
                    0,
                    -math.floor((trackH - thumbH) * suggest.offset / (total - ROWS) + 0.5)
                )
            end
            legendDiv:ClearAllPoints()
            legendDiv:SetPoint("TOPLEFT", dropList, "TOPLEFT", 1, -1 - n * ROW_H)
            legendDiv:SetPoint("TOPRIGHT", dropList, "TOPRIGHT", -1, -1 - n * ROW_H)
            legend:ClearAllPoints()
            legend:SetPoint("TOPLEFT", legendDiv, "BOTTOMLEFT", 7, -4)
            dropList:SetHeight(n * ROW_H + 21)
            dropList._brd:Fit()
            dropList:Show()
        end
        -- A click outside the list closes it (the panel search's pattern):
        -- listened to only while the list is shown.
        local clickOff = CreateFrame("Frame")
        clickOff:SetScript("OnEvent", function()
            if not dropList:IsMouseOver() and not dialog._editBox:IsMouseOver() then
                dialog._closeSuggest()
            end
        end)
        dropList:SetScript("OnShow", function()
            clickOff:RegisterEvent("GLOBAL_MOUSE_DOWN")
        end)
        dropList:SetScript("OnHide", function()
            clickOff:UnregisterEvent("GLOBAL_MOUSE_DOWN")
        end)
        -- The wheel moves the window only; the selection stays and the arrow
        -- keys bring it back into view.
        dropList:EnableMouseWheel(true)
        dropList:SetScript("OnMouseWheel", function(_, delta)
            local suggest = dialog._suggest
            if not suggest then
                return
            end
            local off = math.max(0, math.min(#suggest.items - ROWS, suggest.offset - delta))
            if off ~= suggest.offset then
                suggest.offset = off
                Render()
            end
        end)

        dialog._closeSuggest = function()
            dialog._suggest = nil
            dropList:Hide()
        end
        dialog._stepSuggest = function(infoDialog)
            local suggest = dialog._suggest
            local n = #suggest.items
            suggest.sel = (suggest.sel - 1 + infoDialog) % n + 1
            if suggest.sel <= suggest.offset then
                suggest.offset = suggest.sel - 1
            elseif suggest.sel > suggest.offset + ROWS then
                suggest.offset = suggest.sel - ROWS
            end
            Render()
        end
        dialog._acceptSuggest = function()
            local suggest, entry = dialog._suggest, dialog._editBox
            local item = suggest.items[suggest.sel]
            local text = entry:GetText() or ""
            local new = text:sub(1, suggest.from - 1) .. item.text .. text:sub(suggest.to + 1)
            dialog._closeSuggest()
            entry:SetText(new)
            entry:SetFocus()
            entry:SetCursorPosition(suggest.from - 1 + #item.text)
            dialog._updateSuggest(new)
        end
        dialog._updateSuggest = function(text)
            local items, from, to = dialog._complete(text, dialog._editBox:GetCursorPosition())
            if not items then
                dialog._closeSuggest()
                return
            end
            dialog._suggest = { items = items, from = from, to = to, sel = 1, offset = 0 }
            Render()
        end
    end
    if dialog._previewValue then
        local pv = options.preview ~= nil
        dialog._previewDiv:SetShown(pv)
        dialog._previewLabelFS:SetShown(pv)
        dialog._previewValue:SetShown(pv)
        dialog._hintLabel:SetShown(pv)
        dialog._closeSuggest()
        if pv then
            dialog._previewLabelFS:SetText(options.previewLabel or "")
            local color = options.previewColor
            dialog._previewValue:SetTextColor(color and color.r or 1, color and color.g or 1, color and color.b or 1, 1)
            belowH = 32
        end
    end
    local initText = options.initialText or ""
    dialog._editBox:SetText(initText)
    if options.preview then
        dialog._updatePreview(initText)
    end
    if dialog._maxCount then
        local count = strlenutf8 and strlenutf8(initText) or #initText
        dialog._countLabel:SetText(count .. "/" .. dialog._maxCount)
    end
    if initText == "" then
        dialog._placeholder:Show()
    else
        dialog._placeholder:Hide()
    end

    dialog._cancelBtn._resetAnim()
    dialog._confirmBtn._resetAnim()

    -- The validate status line sits under the input (and a preview block); the
    -- blocks below it move down by its height.
    local statusH = options.validate and 16 or 0
    dialog._statusLabel:ClearAllPoints()
    dialog._statusLabel:SetPoint("TOP", dialog._inputFrame, "BOTTOM", 0, -6 - belowH)
    belowH = belowH + statusH

    -- Extra button (e.g. "Add Current Zone")
    local extraH = 0
    if options.extraButton then
        dialog._extraLbl:SetText(options.extraButton.text or "Extra")
        dialog._extraBtn._resetAnim()
        dialog._extraBtn:SetScript("OnClick", function()
            if options.extraButton.onClick then
                options.extraButton.onClick(dialog._editBox)
            end
        end)
        -- Below the preview block when there is one.
        dialog._extraBtn:ClearAllPoints()
        dialog._extraBtn:SetPoint("TOP", dialog._inputFrame, "BOTTOM", 0, -6 - belowH)
        dialog._extraBtn:Show()
        -- What follows (the warnings) goes below the button, not under it.
        belowH = belowH + 32
    else
        dialog._extraBtn:Hide()
    end

    -- Optional checkbox above the buttons
    local cbH = 0
    if options.checkbox then
        ShowPopupCheckbox(dialog, options.checkbox, dialog._btnY + 27 + 10)
        cbH = 28
    else
        dialog._cbRow:Hide()
    end

    -- A label's height as shown (a secret height in a restricted moment counts as one line).
    local function TextH(fs)
        local h = fs:GetStringHeight() or 12
        if issecretvalue and issecretvalue(h) then
            h = 12
        end
        return math.ceil(h)
    end

    -- Optional warning text below the input field
    local warnH = 0
    if options.warning and options.warning ~= "" then
        dialog._warnLabel:ClearAllPoints()
        dialog._warnLabel:SetPoint("TOP", dialog._inputFrame, "BOTTOM", 0, -18 - belowH)
        dialog._warnLabel:SetText(options.warning)
        dialog._warnLabel:Show()
        warnH = math.max(24, TextH(dialog._warnLabel) + 12)
    else
        dialog._warnLabel:SetText("")
        dialog._warnLabel:Hide()
    end

    -- Optional red warning (redWarning; scaleWarning, its first use, a
    -- scale/resolution mismatch), below the orange one
    local scaleWarnH = 0
    local redWarning = options.redWarning or options.scaleWarning
    if redWarning and redWarning ~= "" then
        dialog._scaleWarnLabel:ClearAllPoints()
        if options.warning and options.warning ~= "" then
            dialog._scaleWarnLabel:SetPoint("TOP", dialog._warnLabel, "BOTTOM", 0, -14)
        else
            dialog._scaleWarnLabel:SetPoint("TOP", dialog._inputFrame, "BOTTOM", 0, -18 - belowH)
        end
        dialog._scaleWarnLabel:SetText(CludesUI.L(redWarning))
        dialog._scaleWarnLabel:Show()
        scaleWarnH = math.max(30, TextH(dialog._scaleWarnLabel) + 18)
    else
        dialog._scaleWarnLabel:SetText("")
        dialog._scaleWarnLabel:Hide()
    end

    -- The base height leaves room for about three lines of message; a longer
    -- one grows the dialog instead of pushing the input towards the buttons.
    local msgExtra = math.max(0, TextH(dialog._msg) - 40)
    dialog:SetHeight(
        194
            + msgExtra
            + math.max(0, (options.inputHeight or 28) - 28)
            + extraH
            + warnH
            + scaleWarnH
            + belowH
            + cbH
    )
    dialog._brd:Fit()

    dialog._cancelBtn:SetScript("OnClick", function()
        dialog._dimmer:Hide()
        if options.onCancel then
            options.onCancel()
        end
    end)
    -- Controller cursor: its cancel press backs out through Cancel only when
    -- Cancel shows and is what Escape does (onDismiss differs from it).
    if CludesUI.PadCP() then
        dialog.CloseButton = (not (options.onDismiss or options.hideCancel)) and dialog._cancelBtn or nil
    end

    dialog._dimmer:Show()
    C_Timer.After(0.05, function()
        local inputBox = dialog._focusInput()
        if dialog._selectText then
            inputBox:HighlightText()
        end
    end)
end

-------------------------------------------------------------------------------
--  Quantity window (the Bags stack splitter, Blizzard Skins+' Merchant Bulk
--  Buy): a small window over a button with a title, a close button,
--  - [amount] + and "/ max", an optional text line and a row of action
--  buttons. Amounts are whole steps from one step up to the max (0 while not
--  even one step fits); Shift on -/+ moves by the range's shiftStep when set.
--  Built once per caller, dressed by opts.skin, refilled on every use:
--    d:SetRange(step, max[, shiftStep]), d:SetValue(n), d:Current(),
--    d:Open(owner), d:FocusInput(); d._eb, d._extra, d._buttons[key].
--  opts: name, width, height, title, editWidth, maxLetters, extraLine,
--    buttons = { { key, label, width, height, point ("BOTTOMLEFT", "BOTTOM" or
--    "BOTTOMRIGHT"), onClick, tooltip (text, or a function read on every
--    hover), tooltipOpts (ShowWidgetTooltip's opts), primary } }, onEnter, onChange(n),
--    onShow, onHide, skin = { frame(d), font(fs, size), button(parent, w, h,
--    label) -> button, editBox(eb), close(btn) }.
-------------------------------------------------------------------------------
function CludesUI.CreateQuantityDialog(options)
    local skin = options.skin
    local infoDialog = CreateFrame("Frame", options.name, UIParent)
    infoDialog:SetFrameStrata("DIALOG")
    infoDialog:SetSize(options.width, options.height)
    infoDialog:SetClampedToScreen(true)
    infoDialog:EnableMouse(true)
    infoDialog:EnableMouseWheel(true)
    infoDialog:Hide()
    infoDialog._step, infoDialog._max = 1, 1
    skin.frame(infoDialog)

    local title = infoDialog:CreateFontString(nil, "OVERLAY")
    skin.font(title, 13)
    title:SetPoint("TOPLEFT", infoDialog, "TOPLEFT", 10, -9)
    title:SetTextColor(1, 1, 1, 0.9)
    title:SetText(options.title)

    local close = CreateFrame("Button", nil, infoDialog)
    skin.close(close)
    close:SetScript("OnClick", function()
        infoDialog:Hide()
    end)
    -- Controller cursor: Cancel finds the window's close button.
    if CludesUI.PadCP() then
        infoDialog.CloseButton = close
    end

    local entry = CreateFrame("EditBox", nil, infoDialog)
    local function Clamped(n)
        if infoDialog._max < infoDialog._step then
            return 0
        end
        return Clamp(math.floor(n / infoDialog._step) * infoDialog._step, infoDialog._step, infoDialog._max)
    end
    function infoDialog:Current()
        return Clamped(entry:GetNumber() or 0)
    end
    function infoDialog:SetValue(n)
        n = Clamped(n)
        entry:SetText(tostring(n))
        entry:SetCursorPosition(#entry:GetText())
        if options.onChange then
            options.onChange(n)
        end
    end
    function infoDialog:SetRange(step, top, shiftStep)
        infoDialog._step, infoDialog._max, infoDialog._shiftStep = math.max(step or 1, 1), top, shiftStep
        infoDialog._maxLbl:SetText("/ " .. top)
    end
    local function Nudge(dir)
        infoDialog:SetValue(infoDialog:Current() + dir * ((IsShiftKeyDown() and infoDialog._shiftStep) or infoDialog._step))
    end

    local minus = skin.button(infoDialog, 22, 22, "-")
    minus:SetPoint("TOPLEFT", infoDialog, "TOPLEFT", 10, -30)
    minus:SetScript("OnClick", function()
        Nudge(-1)
    end)

    entry:SetSize(options.editWidth or 56, 22)
    entry:SetPoint("LEFT", minus, "RIGHT", 4, 0)
    entry:SetAutoFocus(false)
    entry:SetNumeric(true)
    entry:SetMaxLetters(options.maxLetters or 5)
    entry:SetTextColor(1, 1, 1, 1)
    entry:SetJustifyH("CENTER")
    entry:SetTextInsets(4, 4, 0, 0)
    skin.editBox(entry)
    entry:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then
            return
        end
        if self:GetNumber() > infoDialog._max then
            infoDialog:SetValue(infoDialog._max)
        elseif options.onChange then
            options.onChange(infoDialog:Current())
        end
    end)
    entry:SetScript("OnEditFocusLost", function()
        if infoDialog:IsShown() then
            infoDialog:SetValue(infoDialog:Current())
        end
    end)
    entry:SetScript("OnEnterPressed", function()
        if options.onEnter then
            options.onEnter()
        end
    end)
    entry:SetScript("OnEscapePressed", function()
        infoDialog:Hide()
    end)
    -- Controller cursor: the -/+ buttons cover the amount, so no on-screen
    -- keyboard for this box.
    CludesUI.PadHint(entry, "hidekeyboard")
    infoDialog._eb = entry

    local plus = skin.button(infoDialog, 22, 22, "+")
    plus:SetPoint("LEFT", entry, "RIGHT", 4, 0)
    plus:SetScript("OnClick", function()
        Nudge(1)
    end)

    local maxLbl = infoDialog:CreateFontString(nil, "OVERLAY")
    skin.font(maxLbl, 12)
    maxLbl:SetPoint("LEFT", plus, "RIGHT", 8, 0)
    maxLbl:SetTextColor(0.7, 0.7, 0.7, 1)
    infoDialog._maxLbl = maxLbl

    if options.extraLine then
        local line = infoDialog:CreateFontString(nil, "OVERLAY")
        skin.font(line, 12)
        line:SetPoint("TOPLEFT", minus, "BOTTOMLEFT", 0, -9)
        line:SetPoint("RIGHT", infoDialog, "RIGHT", -10, 0)
        line:SetJustifyH("LEFT")
        line:SetWordWrap(false)
        line:SetTextColor(1, 1, 1, 0.9)
        infoDialog._extra = line
    end

    infoDialog._buttons = {}
    for _, spec in ipairs(options.buttons) do
        local widget = skin.button(infoDialog, spec.width, spec.height, spec.label)
        local p = spec.point
        widget:SetPoint(p, infoDialog, p, (p == "BOTTOMLEFT" and 10) or (p == "BOTTOMRIGHT" and -10) or 0, 10)
        widget:SetScript("OnClick", spec.onClick)
        if spec.tooltip then
            widget:HookScript("OnEnter", function()
                CludesUI.ShowWidgetTooltip(widget, spec.tooltip, spec.tooltipOpts)
            end)
            widget:HookScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)
        end
        infoDialog._buttons[spec.key] = widget
        if spec.primary then
            infoDialog._primary = widget
        end
    end

    infoDialog:SetScript("OnMouseWheel", function(_, delta)
        Nudge(delta > 0 and 1 or -1)
    end)
    infoDialog:SetScript("OnShow", function()
        if options.onShow then
            options.onShow()
        end
    end)
    infoDialog:SetScript("OnHide", function()
        entry:ClearFocus()
        if options.onHide then
            options.onHide()
        end
    end)
    CludesUI.RegisterEscapeClose(infoDialog)

    function infoDialog:Open(owner)
        infoDialog:ClearAllPoints()
        infoDialog:SetPoint("BOTTOMLEFT", owner, "TOPLEFT", -4, 6)
        infoDialog:Show()
    end
    -- Keyboard on the amount, or, with a controller cursor on screen, the
    -- cursor on the primary button (focus would raise the on-screen keyboard).
    function infoDialog:FocusInput()
        if CludesUI.PadCursorShown() then
            CludesUI.PadFocus(infoDialog._primary)
        else
            entry:SetFocus()
            entry:HighlightText()
        end
    end
    return infoDialog
end

-- Blizzard's StackSplitFrame when it is open on owner and ours to take over:
-- returns its max. Not when a key is still held in it (its OnHide replays key
-- releases through RunBinding, which must not run from our code), nor under
-- WoW Forever's Gamepad interface style (the popup is part of the controller
-- navigation).
function CludesUI.StackSplitFor(owner)
    local ssf = StackSplitFrame
    if not ssf or not ssf:IsShown() or ssf.owner ~= owner then
        return nil
    end
    if ssf.down and next(ssf.down) then
        return nil
    end
    if CludesUI.PadGamepadUI() then
        return nil
    end
    return ssf.maxStack or 0
end

-- Takes Blizzard's StackSplitFrame away once StackSplitFor said yes: Hide
-- only, no field writes on Blizzard's popup. Its OnHide runs under this call
-- and writes owner.hasStackSplit = 0 onto the button it was open on.
function CludesUI.TakeStackSplit()
    StackSplitFrame:Hide()
end
