if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_UnlockMode_Bar.lua
--  Layout Mode's toolbar, CludesUI's own: a strip across the top of the
--  screen holding, left to right, the logo and title, the toggles (square
--  chips with a caption under each), the element filter, then help, Exit,
--  Save & Exit and the two size buttons.
--
--  Everything on it is described by a table (TOGGLES, the row lists) and
--  built by a handful of small makers, so adding a control is one entry.
--  The bar fades out while Shift is held, and, with Auto Hide on, whenever
--  the cursor is not at the top of the screen over it.
--
--  Loaded after CUI_UnlockMode_Filter.lua; _unlockCoreInit runs it once with
--  UM. It provides UM.CreateBar (the session calls it on open), UM.hudFrame,
--  UM.PaintBanner and CludesUI:GetUnlockModeTopBarAnchor.
-------------------------------------------------------------------------------
local _, CUI_NS = ...
CUI_NS = CUI_NS.__cuiCoreNS or CUI_NS -- standalone builds: the core's own table (CludesUI.lua)
CUI_NS.unlockParts = CUI_NS.unlockParts or {}

-- Sizes, in bar units (one unit is one screen pixel at bar size 100%).
local BAR_H = 58 -- the strip's height
local FACE_Y = -22 -- the controls' centre line, from the top
local PAD, GAP, GROUP_GAP = 16, 6, 18 -- outer padding, gap in a group, gap between groups
local CHIP, CHIP_ICON = 28, 18 -- a toggle's face and the icon on it
local CAPTION_SZ, CAPTION_H = 9, 13 -- a toggle's caption: font size, room under the face
local BTN_H, SIZE_CHIP, LOGO_SZ = 26, 22, 26
local BOX_GAP, BOX_MIN, BOX_MAX = 6, 120, 220
local DROP_H = 130 -- how far above the screen the bar waits before it drops in
local SIZE_MIN, SIZE_MAX, SIZE_STEP = 1.0, 1.5, 0.1
local HOVER_FADE, SHIFT_FADE = 0.5, 0.15 -- seconds to fade for Auto Hide / while Shift is held
local ICONS = "Interface\\AddOns\\CludesUI\\media\\icons\\"
local LOGO = "Interface\\AddOns\\CludesUI\\media\\logo-full-thin.png"

CUI_NS.unlockParts.Bar = function(LM)
    local mod = CUI_NS
    local L = CludesUI.L
    local movers = LM.movers
    local FONT = LM.FONT_PATH

    local autoHide = false -- the Auto Hide toggle: not saved, off at every login

    -- The bar's accent: gold while a spec-override layout is being edited.
    local function Accent()
        if CludesUI._specialUnlockGroup then
            return 1, 0.82, 0.30
        end
        local c = CludesUI.CLUDES_GREEN
        return c.r, c.g, c.b
    end

    -------------------------------------------------------------------------------
    --  The toggles. level(): 0 off, 0.5 half, 1 on. state(): the word the tooltip
    --  shows beside the name. click(): flips the setting and applies it.
    -------------------------------------------------------------------------------
    local function OnOff(get)
        return function()
            return get() and 1 or 0
        end, function()
            return get() and "Enabled" or "Disabled"
        end
    end

    local TOGGLES = {}
    do
        local function Add(t)
            TOGGLES[#TOGGLES + 1] = t
        end

        Add({
            icon = "grid.png",
            caption = "Grid",
            name = "Grid Lines",
            tip = "Shows a grid to line elements up. Click to switch between dimmed, bright and off.",
            level = function()
                return LM.gridMode == "bright" and 1 or (LM.gridMode == "dimmed" and 0.5 or 0)
            end,
            state = function()
                return LM.gridMode == "bright" and "Bright"
                    or (LM.gridMode == "dimmed" and "Dimmed" or "Disabled")
            end,
            click = function()
                LM.CycleGridMode()
                if CludesUIDB then
                    CludesUIDB.unlockGridMode = LM.gridMode
                end
                local grid = LM.gridFrame
                if not grid then
                    return
                end
                if LM.gridMode == "disabled" then
                    grid:Hide()
                else
                    grid:Rebuild()
                    grid:Show()
                end
            end,
        })

        local level, status = OnOff(function()
            return LM.snapEnabled
        end)
        Add({
            icon = "magnet.png",
            caption = "Snap",
            name = "Snap Elements",
            level = level,
            state = status,
            tip = "Dragged elements snap to the edges and centers of the closest element.",
            click = function()
                LM.snapEnabled = not LM.snapEnabled
                if CludesUIDB then
                    CludesUIDB.unlockSnapEnabled = LM.snapEnabled
                end
                for _, m in pairs(movers) do
                    if m._refreshSnapDD then
                        m._refreshSnapDD()
                    end
                end
            end,
        })

        level, status = OnOff(function()
            return LM.darkOverlaysEnabled
        end)
        Add({
            icon = "dark-overlay.png",
            caption = "Overlays",
            name = "Dark Overlays",
            level = level,
            state = status,
            tip = "Gives every element a dark background with its name. Turn it off to see the real elements underneath.",
            click = function()
                LM.darkOverlaysEnabled = not LM.darkOverlaysEnabled
                LM.ApplyDarkOverlays()
            end,
        })

        level, status = OnOff(function()
            return LM.flashlightEnabled
        end)
        Add({
            icon = "flashlight.png",
            caption = "Cursor Light",
            name = "Cursor Light",
            level = level,
            state = status,
            tip = "Lights up the grid lines around the cursor. Needs the grid lines to be on.",
            click = function()
                LM.flashlightEnabled = not LM.flashlightEnabled
            end,
        })

        level, status = OnOff(function()
            return LM.coordsEnabled
        end)
        Add({
            icon = "coordinates.png",
            caption = "Coordinates",
            name = "Coordinates",
            level = level,
            state = status,
            tip = "Always shows every element's position, not only while it is hovered, dragged or selected.",
            click = function()
                LM.coordsEnabled = not LM.coordsEnabled
                for _, m in pairs(movers) do
                    if m._coordFS then
                        if LM.coordsEnabled then
                            if m.UpdateCoordText then
                                m:UpdateCoordText()
                            end
                        elseif not m._selected then
                            m._coordFS:Hide() -- the selected element keeps its own
                        end
                    end
                end
            end,
        })

        level, status = OnOff(function()
            return autoHide
        end)
        Add({
            icon = "hover.png",
            caption = "Auto Hide",
            name = "Auto Hide",
            level = level,
            state = status,
            tip = "Hides this bar until the cursor reaches it at the top of the screen, except over an element. Hold Shift to hide it any time.",
            click = function()
                autoHide = not autoHide
            end,
        })
    end

    -- The controls the help chip lists, keys in the accent colour.
    local function HelpText()
        local hex = CludesUI.HexColor(Accent())
        local function Line(key, what)
            return hex .. L(key) .. "|r: " .. L(what)
        end
        local lines = {
            Line("Shift + Drag", "Move it on one axis only."),
            Line("Arrow Keys", "Move the selected element 1px."),
            Line("Shift + Arrow Keys", "Move it 100px."),
            Line("Right Click", "Open the element's settings."),
            Line("Shift + Right Click", "Hide the element's overlay temporarily."),
            Line("Hold Shift", "Hide this bar."),
        }
        -- The Overlap Cycling key, by the setting's own label; none while it is disabled.
        local method = CludesUI.GetUnlockOverlapMethod()
        local overlap = method ~= "disabled" and CludesUI.UNLOCK_OVERLAP_LABELS[method]
        if overlap then
            lines[#lines + 1] = Line(overlap, "Cycle through overlapping elements.")
        end
        return table.concat(lines, "\n")
    end

    -------------------------------------------------------------------------------
    --  UM.CreateBar(parent): builds the bar once and returns it (hidden, waiting
    --  above the screen for the open animation to drop it in).
    -------------------------------------------------------------------------------
    function LM.CreateBar(hostFrame)
        if LM.hudFrame then
            return LM.hudFrame
        end

        -- Saved choices. Grid defaults to dimmed, snapping to on.
        local saved = CludesUIDB
        LM.gridMode = saved and saved.unlockGridMode or "dimmed"
        LM.snapEnabled = not (saved and saved.unlockSnapEnabled == false)

        -- One bar unit is one physical pixel at size 100%; a very low UI scale gets a little more.
        local base = GetScreenWidth() / (GetPhysicalScreenSize())
        if UIParent:GetEffectiveScale() < 0.6 then
            base = base * 1.08
        end
        local size = math.max(SIZE_MIN, math.min(SIZE_MAX, saved and saved.unlockBannerScale or SIZE_MIN))

        local bar = CreateFrame("Frame", nil, hostFrame)
        LM.hudFrame = bar
        bar:SetFrameStrata("TOOLTIP")
        bar:SetFrameLevel(900)
        bar:SetSize(400, BAR_H)
        bar:SetScale(base * size)
        bar:EnableMouse(false) -- only its controls take the mouse
        bar:SetPoint("TOP", UIParent, "TOP", 0, DROP_H * base)
        bar._dropH = DROP_H

        local outlines = {} -- pixel-seated outlines, re-seated when the bar lands or changes size
        function bar._refitOutlines()
            if not bar:IsVisible() then
                return
            end
            for idx = 1, #outlines do
                outlines[idx]:Fit()
            end
        end
        local controls = {} -- everything that takes the mouse (cut while the bar is faded out)
        local repaint = {} -- accent-coloured pieces, repainted when the accent changes

        -- A control's tooltip: under the bar, starting at the control's left edge
        -- unless that would run off the right of the screen. Not while the
        -- first-open tip covers that spot.
        local function Tip(ownerFrame, textValue, justify)
            if LM.unlockTipFrame and LM.unlockTipFrame:IsShown() then
                return
            end
            local toUI = ownerFrame:GetEffectiveScale() / UIParent:GetEffectiveScale()
            local side = (ownerFrame:GetLeft() * toUI + 250 > UIParent:GetRight()) and "RIGHT" or "LEFT"
            CludesUI.ShowWidgetTooltip(ownerFrame, textValue, {
                anchorPoint = "TOP" .. side,
                anchorTo = "BOTTOM" .. side,
                justify = justify,
                -- Its top sits just under the strip, whatever the control's height.
                anchorY = -(
                        BAR_H
                        + 1
                        + (ownerFrame._tall and (FACE_Y - CAPTION_H / 2) or FACE_Y)
                        - ownerFrame:GetHeight() / 2
                    ) * bar:GetScale(),
            })
        end
        LM.ShowBarTip = Tip

        ---------------------------------------------------------------------------
        --  The strip: a dark plate across the whole screen, an accent line along
        --  its bottom edge and a soft glow under that.
        ---------------------------------------------------------------------------
        local function Span(texture, topY, height)
            texture:SetPoint("TOP", bar, "TOP", 0, topY)
            texture:SetPoint("LEFT", UIParent, "LEFT")
            texture:SetPoint("RIGHT", UIParent, "RIGHT")
            texture:SetHeight(height)
        end
        local backing = bar:CreateTexture(nil, "BACKGROUND")
        Span(backing, 0, BAR_H)
        backing:SetColorTexture(0.035, 0.043, 0.052, 0.95)
        local sheen = bar:CreateTexture(nil, "BACKGROUND", nil, 1)
        Span(sheen, 0, BAR_H)
        sheen:SetColorTexture(1, 1, 1, 1)
        sheen:SetGradient("VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 0.04))
        local line = bar:CreateTexture(nil, "ARTWORK", nil, 2)
        Span(line, -(BAR_H - 2), 2)
        local glow = bar:CreateTexture(nil, "ARTWORK", nil, 1)
        Span(glow, -BAR_H, 14)
        glow:SetColorTexture(1, 1, 1, 1)
        repaint[#repaint + 1] = function(r, g, b)
            line:SetColorTexture(r, g, b, 0.9)
            glow:SetGradient("VERTICAL", CreateColor(r, g, b, 0), CreateColor(r, g, b, 0.2))
        end

        ---------------------------------------------------------------------------
        --  Makers
        ---------------------------------------------------------------------------
        -- A square plate with a 2px-corner outline on host; returns the outline.
        local function Plate(host)
            local backdrop = host:CreateTexture(nil, "BACKGROUND")
            backdrop:SetAllPoints()
            backdrop:SetColorTexture(1, 1, 1, 0.04)
            local brd = CludesUI.MakeRoundedBorder(host, 1, 1, 1, 0.12, backdrop, 2)
            outlines[#outlines + 1] = brd
            return brd
        end

        local function Control(kind, wid, hgt)
            local c = CreateFrame(kind, nil, bar)
            c:SetSize(wid, hgt)
            c:SetFrameLevel(bar:GetFrameLevel() + 2)
            controls[#controls + 1] = c
            return c
        end

        -- A toggle: icon on a square face, caption under it. The face fills and
        -- gains a bottom cap in the accent colour by the toggle's level.
        local function MakeToggle(def)
            local caption = bar:CreateFontString(nil, "OVERLAY")
            caption:SetFont(FONT, CAPTION_SZ, "OUTLINE, SLUG")
            caption:SetText(L(def.caption))
            local button = Control(
                "Button",
                math.max(CHIP, math.ceil(caption:GetStringWidth() or CHIP) + 4),
                CHIP + CAPTION_H
            )
            button._tall = true
            caption:SetParent(button)
            local face = CreateFrame("Frame", nil, button)
            face:SetSize(CHIP, CHIP)
            face:SetPoint("TOP")
            caption:SetPoint("TOP", face, "BOTTOM", 0, -3)
            local brd = Plate(face)
            local wash = face:CreateTexture(nil, "BACKGROUND", nil, 1)
            wash:SetAllPoints()
            local cap = face:CreateTexture(nil, "ARTWORK")
            cap:SetPoint("BOTTOMLEFT", 1, 1)
            cap:SetPoint("BOTTOMRIGHT", -1, 1)
            cap:SetHeight(2)
            local icon = face:CreateTexture(nil, "OVERLAY")
            icon:SetSize(CHIP_ICON, CHIP_ICON)
            icon:SetPoint("CENTER")
            icon:SetTexture(ICONS .. def.icon)

            local hover = false
            local function Paint()
                local r, g, b = Accent()
                local lv = def.level()
                wash:SetColorTexture(r, g, b, 0.16 * lv)
                cap:SetColorTexture(r, g, b, lv)
                if lv > 0 then
                    icon:SetVertexColor(r, g, b)
                else
                    icon:SetVertexColor(1, 1, 1)
                end
                icon:SetAlpha(hover and 1 or (lv > 0 and 0.9 or 0.45))
                if hover then
                    brd:SetColor(1, 1, 1, 0.35)
                    caption:SetTextColor(1, 1, 1, 0.95)
                elseif lv > 0 then
                    brd:SetColor(r, g, b, 0.5)
                    caption:SetTextColor(r, g, b, 0.95)
                else
                    brd:SetColor(1, 1, 1, 0.12)
                    caption:SetTextColor(1, 1, 1, 0.55)
                end
            end
            local function ShowTip()
                Tip(
                    button,
                    CludesUI.HexColor(Accent())
                        .. L(def.name)
                        .. "|r  "
                        .. L(def.state())
                        .. "\n"
                        .. L(def.tip)
                )
            end
            button:SetScript("OnEnter", function()
                hover = true
                Paint()
                ShowTip()
            end)
            button:SetScript("OnLeave", function()
                hover = false
                Paint()
                CludesUI.HideWidgetTooltip()
            end)
            button:SetScript("OnClick", function()
                def.click()
                Paint()
                if hover then
                    ShowTip()
                end -- the state word changed
            end)
            repaint[#repaint + 1] = Paint
            return button
        end

        -- A small square button showing an icon or a character.
        local function MakeChip(wid, hgt, iconFile, char)
            local button = Control("Button", wid, hgt)
            local brd = Plate(button)
            local mark
            if iconFile then
                mark = button:CreateTexture(nil, "OVERLAY")
                mark:SetSize(CHIP_ICON, CHIP_ICON)
                mark:SetPoint("CENTER")
                mark:SetTexture(ICONS .. iconFile)
            else
                mark = button:CreateFontString(nil, "OVERLAY")
                mark:SetFont(FONT, 16, "")
                mark:SetPoint("CENTER")
                mark:SetText(char)
            end
            button._off = false
            function button.Paint(hover)
                local a = button._off and 0.2 or (hover and 0.95 or 0.6)
                if iconFile then
                    mark:SetAlpha(a)
                else
                    mark:SetTextColor(1, 1, 1, a)
                end
                brd:SetColor(1, 1, 1, (hover and not button._off) and 0.35 or 0.12)
            end
            button:SetScript("OnEnter", function()
                button.Paint(true)
            end)
            button:SetScript("OnLeave", function()
                button.Paint(false)
            end)
            button.Paint(false)
            return button
        end

        -- A text button: grey outline, or the accent colour for the primary one.
        local function MakeTextButton(textValue, wid, primary, onClick)
            local button = Control("Button", wid, BTN_H)
            local backdrop = button:CreateTexture(nil, "BACKGROUND")
            backdrop:SetAllPoints()
            local brd = CludesUI.MakeRoundedBorder(button, 1, 1, 1, 0.3, backdrop, 2)
            outlines[#outlines + 1] = brd
            local labelText = button:CreateFontString(nil, "OVERLAY")
            labelText:SetFont(FONT, 10, "OUTLINE, SLUG")
            labelText:SetPoint("CENTER")
            labelText:SetText(L(textValue))
            local hover = false
            local function Paint()
                local r, g, b = 1, 1, 1
                if primary then
                    r, g, b = Accent()
                end
                backdrop:SetColorTexture(r, g, b, hover and 0.14 or 0.06)
                brd:SetColor(r, g, b, hover and (primary and 1 or 0.5) or (primary and 0.7 or 0.3))
                labelText:SetTextColor(r, g, b, hover and 1 or (primary and 0.9 or 0.7))
            end
            button:SetScript("OnEnter", function()
                hover = true
                Paint()
            end)
            button:SetScript("OnLeave", function()
                hover = false
                Paint()
            end)
            button:SetScript("OnClick", onClick)
            repaint[#repaint + 1] = Paint
            return button
        end

        ---------------------------------------------------------------------------
        --  The controls
        ---------------------------------------------------------------------------
        -- Brand: the logo (the open animation's emblem flies onto it) and the title.
        local brand = CreateFrame("Frame", nil, bar)
        local logo = brand:CreateTexture(nil, "ARTWORK")
        logo:SetSize(LOGO_SZ, LOGO_SZ)
        logo:SetPoint("LEFT")
        logo:SetTexture(LOGO)
        local title = brand:CreateFontString(nil, "OVERLAY")
        title:SetFont(FONT, 13, "OUTLINE, SLUG")
        title:SetPoint("LEFT", logo, "RIGHT", 8, 0)
        title:SetTextColor(1, 1, 1, 0.92)
        title:SetText(L("LAYOUT MODE"))
        brand:SetSize(LOGO_SZ + 8 + math.ceil(title:GetStringWidth() or 90), CHIP)
        bar._badgeLogo = logo
        repaint[#repaint + 1] = function(r, g, b)
            logo:SetVertexColor(r, g, b, 1)
        end

        local leftX = { brand, "|" }
        for idx = 1, #TOGGLES do
            leftX[#leftX + 1] = MakeToggle(TOGGLES[idx])
        end

        -- Element filter: a funnel that focuses the box, the box, and its clear button.
        local funnel = MakeChip(CHIP, CHIP, "filter.png")
        local box = Control("Frame", BOX_MIN, BTN_H)
        local boxBg = box:CreateTexture(nil, "BACKGROUND")
        boxBg:SetAllPoints()
        boxBg:SetColorTexture(CludesUI.SL_INPUT_R, CludesUI.SL_INPUT_G, CludesUI.SL_INPUT_B, 0.9)
        local boxBrd = CludesUI.MakeRoundedBorder(box, 1, 1, 1, 0.2, boxBg, 2)
        outlines[#outlines + 1] = boxBrd
        local edit = CreateFrame("EditBox", nil, box)
        edit:SetAllPoints()
        edit:SetAutoFocus(false)
        edit:SetFont(FONT, 11, "")
        edit:SetTextColor(1, 1, 1, 0.9)
        edit:SetTextInsets(6, 18, 0, 0)
        edit:SetMaxLetters(40)
        controls[#controls + 1] = edit
        local hint = box:CreateFontString(nil, "OVERLAY")
        hint:SetFont(FONT, 10, "")
        hint:SetPoint("LEFT", box, "LEFT", 6, 0)
        hint:SetTextColor(1, 1, 1, 0.35)
        hint:SetText(L("Filter elements..."))
        local clear = CreateFrame("Button", nil, box)
        clear:SetSize(16, 16)
        clear:SetPoint("RIGHT", box, "RIGHT", -2, 0)
        clear:SetFrameLevel(edit:GetFrameLevel() + 2)
        clear:Hide()
        controls[#controls + 1] = clear
        local cross = clear:CreateFontString(nil, "OVERLAY")
        cross:SetFont(FONT, 12, "")
        cross:SetPoint("CENTER")
        cross:SetText("x")
        cross:SetTextColor(1, 1, 1, 0.45)
        clear:SetScript("OnEnter", function()
            cross:SetTextColor(1, 1, 1, 1)
        end)
        clear:SetScript("OnLeave", function()
            cross:SetTextColor(1, 1, 1, 0.45)
        end)
        clear:SetScript("OnClick", function()
            edit:SetText("")
            edit:ClearFocus()
        end)

        local filtering = false
        local function PaintFilter()
            local focus = edit:HasFocus()
            boxBrd:SetColor(1, 1, 1, (focus or edit:IsMouseOver()) and 0.4 or 0.2)
            funnel._off = false
            funnel.Paint(focus or funnel:IsMouseOver() or filtering)
        end
        local FILTER_TIP =
            "Show only the elements whose name contains every word typed here. Escape clears it."
        edit:SetScript("OnEnter", function(self)
            PaintFilter()
            Tip(self, L(FILTER_TIP))
        end)
        edit:SetScript("OnLeave", function()
            PaintFilter()
            CludesUI.HideWidgetTooltip()
        end)
        funnel:SetScript("OnEnter", function(self)
            PaintFilter()
            Tip(self, L(FILTER_TIP))
        end)
        funnel:SetScript("OnLeave", function()
            PaintFilter()
            CludesUI.HideWidgetTooltip()
        end)
        funnel:SetScript("OnClick", function()
            edit:SetFocus()
        end)
        edit:SetScript("OnEscapePressed", function(self)
            self:SetText("")
            self:ClearFocus()
        end)
        edit:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
        end)
        -- A click anywhere else gives the keyboard back (the arrow keys nudge again).
        edit:SetScript("OnEditFocusGained", function(self)
            self:RegisterEvent("GLOBAL_MOUSE_DOWN")
            PaintFilter()
        end)
        edit:SetScript("OnEditFocusLost", function(self)
            self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
            PaintFilter()
        end)
        edit:SetScript("OnEvent", function(self)
            if not (self:IsMouseOver() or clear:IsMouseOver() or funnel:IsMouseOver()) then
                self:ClearFocus()
            end
        end)
        edit:SetScript("OnTextChanged", function(self)
            local textValue = self:GetText() or ""
            hint:SetShown(textValue == "")
            clear:SetShown(textValue ~= "")
            filtering = LM.FilterSet(textValue)
            PaintFilter()
        end)
        leftX[#leftX + 1] = "|"
        leftX[#leftX + 1] = funnel
        leftX[#leftX + 1] = box

        local help = MakeChip(CHIP, CHIP, "cui-info.png")
        help:SetScript("OnEnter", function(self)
            self.Paint(true)
            Tip(self, HelpText(), "LEFT")
        end)
        help:SetScript("OnLeave", function(self)
            self.Paint(false)
            CludesUI.HideWidgetTooltip()
        end)
        local exit = MakeTextButton("Exit", 60, false, function()
            mod.RequestClose(false)
        end)
        local save = MakeTextButton("Save & Exit", 92, true, function()
            mod.RequestClose(true)
        end)
        local smaller = MakeChip(SIZE_CHIP, SIZE_CHIP, nil, "-")
        local bigger = MakeChip(SIZE_CHIP, SIZE_CHIP, nil, "+")
        -- Right group, listed from the bar's right end inward.
        local right = { bigger, smaller, "|", save, exit, help }

        ---------------------------------------------------------------------------
        --  Layout: each list hangs off one end of the bar frame, so the frame's
        --  width is the whole row and it sits centred on the screen. The filter
        --  box gives up its width first when the row does not fit (limit: the
        --  widest the row may be, in bar units; nil = no limit).
        ---------------------------------------------------------------------------
        local function Place(entries, side)
            local posX, first, groupGap = PAD, true, false
            for _, c in ipairs(entries) do
                if c == "|" then
                    groupGap = true
                else
                    if not first then
                        posX = posX + (groupGap and GROUP_GAP or (c == box and BOX_GAP or GAP))
                    end
                    first, groupGap = false, false
                    -- A toggle is taller by its caption: its face sits on the centre line.
                    local posY = c._tall and (FACE_Y - CAPTION_H / 2) or FACE_Y
                    c:ClearAllPoints()
                    if side == "LEFT" then
                        c:SetPoint("LEFT", bar, "TOPLEFT", posX, posY)
                    else
                        c:SetPoint("RIGHT", bar, "TOPRIGHT", -posX, posY)
                    end
                    posX = posX + c:GetWidth()
                end
            end
            return posX
        end
        local function Layout(limit)
            box:SetWidth(BOX_MAX)
            local need = Place(leftX, "LEFT") + GROUP_GAP + Place(right, "RIGHT")
            if limit and need > limit then
                box:SetWidth(BOX_MIN)
                need = Place(leftX, "LEFT") + GROUP_GAP + Place(right, "RIGHT")
            end
            bar:SetWidth(math.ceil(need))
            return need
        end

        ---------------------------------------------------------------------------
        --  Size: 100% to 150% in 10% steps, saved. A size the screen cannot fit
        --  shows at the largest step that does (without saving it) and greys "+".
        ---------------------------------------------------------------------------
        local fitMax = SIZE_MAX
        local zone -- the hover zone, made below
        local function Shown()
            return math.min(size, math.max(SIZE_MIN, math.floor(fitMax / SIZE_STEP + 0.001) * SIZE_STEP))
        end
        local function ApplySize()
            local s = Shown()
            bar:SetScale(base * s)
            bar:ClearAllPoints()
            bar:SetPoint("TOP", UIParent, "TOP", 0, 0)
            if zone then
                zone:SetHeight((BAR_H + 2) * base * s)
            end
            smaller._off = s <= SIZE_MIN + 0.001
            bigger._off = s >= SIZE_MAX - 0.001 or s + SIZE_STEP > fitMax + 0.001
            smaller.Paint(false)
            bigger.Paint(false)
            bar._refitOutlines()
        end
        local function Step(dir)
            local s = math.max(SIZE_MIN, math.min(SIZE_MAX, Shown() + dir * SIZE_STEP))
            size = s
            if CludesUIDB then
                CludesUIDB.unlockBannerScale = s
            end
            ApplySize()
        end
        smaller:SetScript("OnClick", function(self)
            if not self._off then
                Step(-1)
            end
        end)
        bigger:SetScript("OnClick", function(self)
            if not self._off then
                Step(1)
            end
        end)
        -- The fit only changes with the screen, so it runs each time the bar shows.
        local function Fit()
            local limit = GetScreenWidth() / base
            fitMax = limit / Layout(limit)
            bar:SetScale(base * Shown())
            smaller._off = Shown() <= SIZE_MIN + 0.001
            bigger._off = Shown() >= SIZE_MAX - 0.001 or Shown() + SIZE_STEP > fitMax + 0.001
            smaller.Paint(false)
            bigger.Paint(false)
        end
        bar._applySize = ApplySize

        ---------------------------------------------------------------------------
        --  Colour
        ---------------------------------------------------------------------------
        function LM.PaintBanner()
            local r, g, b = Accent()
            for idx = 1, #repaint do
                repaint[idx](r, g, b)
            end
        end
        CludesUI.RegAccent({
            type = "callback",
            fn = function()
                LM.PaintBanner()
            end,
        })
        LM.PaintBanner()

        ---------------------------------------------------------------------------
        --  Fading. Holding Shift fades the bar out so what is under it can be
        --  reached; Auto Hide keeps it out unless the cursor is at the top of the
        --  screen within the bar's width and not on an element. While faded out,
        --  its controls let the mouse through.
        ---------------------------------------------------------------------------
        zone = CreateFrame("Frame", nil, hostFrame) -- other addons stack under this (GetUnlockModeTopBarAnchor)
        zone:SetFrameStrata("FULLSCREEN_DIALOG")
        zone:SetFrameLevel(hostFrame:GetFrameLevel() + 56)
        zone:SetPoint("TOPLEFT", UIParent, "TOPLEFT")
        zone:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT")
        zone:SetHeight((BAR_H + 2) * base * Shown())
        zone:EnableMouse(false)
        zone:Hide()
        bar._hoverZone = zone

        local alpha, cut = 1, false
        local function CutMouse(enabled)
            if enabled == cut then
                return
            end
            cut = enabled
            for idx = 1, #controls do
                local c = controls[idx]
                if enabled then
                    -- Disabling the mouse fires no OnLeave: clear the hover look by hand.
                    local leave = c:GetScript("OnLeave")
                    if leave then
                        leave(c)
                    end
                end
                c:EnableMouse(not enabled)
            end
        end

        -- Is the cursor on a Layout Mode element (not the bar, not a menu's click catcher)?
        -- Read again only when the cursor moved or the mouse cut changed.
        local seenX, seenY, seenCut, seenHit
        local function OverElement(posX, posY)
            if posX == seenX and posY == seenY and cut == seenCut then
                return seenHit
            end
            seenX, seenY, seenCut, seenHit = posX, posY, cut, false
            local f = GetMouseFoci()[1]
            while f do
                if f.IsForbidden and f:IsForbidden() then
                    return false
                end
                local up = f:GetParent()
                if up == LM.unlockFrame then
                    seenHit = f ~= bar and not f._umCatcher
                    return seenHit
                end
                f = up
            end
            return false
        end

        bar:SetScript("OnUpdate", function(self, dt)
            local typing = edit:HasFocus()
            local shift = IsShiftKeyDown() and not typing -- capitals in the filter are not a hide
            CutMouse(shift or (autoHide and alpha == 0))
            if shift then
                -- Always written: opening Layout Mode sets the frame's alpha to 1 behind our back.
                alpha = math.max(0, alpha - dt / SHIFT_FADE)
                self:SetAlpha(alpha)
                if not autoHide then
                    zone:Hide()
                end
                return
            end
            if not autoHide then
                if alpha < 1 then
                    alpha = 1
                    self:SetAlpha(1)
                end
                zone:Hide()
                return
            end
            zone:Show()
            local posX, posY = GetCursorPosition()
            local ui = UIParent:GetEffectiveScale()
            local wanted = typing
            if not wanted and posY / ui >= UIParent:GetHeight() - zone:GetHeight() then
                local s, l, r = self:GetEffectiveScale(), self:GetLeft(), self:GetRight()
                local drag = LM.selectedMover and LM.selectedMover._dragging
                wanted = l ~= nil
                    and posX >= l * s
                    and posX <= r * s
                    and not drag
                    and not OverElement(posX, posY)
            end
            alpha = math.max(0, math.min(1, alpha + (wanted and dt or -dt) / HOVER_FADE))
            self:SetAlpha(alpha)
        end)

        bar:SetScript("OnShow", function()
            Fit()
            LM.PaintBanner()
        end)
        -- Closing Layout Mode (or a combat pause) hides the bar: start clean next time,
        -- and drop a tooltip one of its controls left showing.
        bar:SetScript("OnHide", function()
            edit:ClearFocus()
            edit:SetText("")
            LM.FilterReset()
            filtering = false
            local ownerFrame = CludesUI._WidgetTooltipOwner()
            for idx = 1, #controls do
                if controls[idx] == ownerFrame then
                    CludesUI.HideWidgetTooltip(true)
                    break
                end
            end
        end)

        Fit()
        bar:Hide()
        return bar
    end

    -- Stable anchor for other addons that stack controls under the bar.
    function CludesUI:GetUnlockModeTopBarAnchor()
        return LM.hudFrame and LM.hudFrame._hoverZone
    end
end
