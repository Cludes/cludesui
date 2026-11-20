if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUI_Widgets_Color.lua
--  Color widgets: HSV helpers, the color picker popup, the color swatches
--  and the factory's color rows. Loads right after CludesUI_Widgets.lua.
--  DEFERRED: body runs on first CludesUI:EnsureLoaded() call, not at load.
-------------------------------------------------------------------------------
local CludesUI = _G.CludesUI
CludesUI._deferredInits[#CludesUI._deferredInits + 1] = function()
    -- Page reuse: the frames this file builds go through the options frame pool
    -- (CludesUI_FramePool.lua), which hands a kept page its previous build's
    -- frames back reset to new; on any other parent it creates as before. A
    -- swatch's dress count (PoolGen) and idle flag (PoolIsIdle) tell its color
    -- picker callbacks that the page was rebuilt while the picker was open.
    local CreateFrame = CludesUI._Pool.CreateFrame
    local PoolGen = CludesUI._Pool.Gen
    local PoolIsIdle = CludesUI._Pool.IsIdle
    local Pix = CludesUI.PanelPP
    local MakeFont = CludesUI.MakeFont
    local RowBg = CludesUI.RowBg
    local RegisterWidgetRefresh = CludesUI.RegisterWidgetRefresh
    local EXPRESSWAY = CludesUI.EXPRESSWAY
    local CONTENT_PAD = CludesUI.CONTENT_PAD
    local TEXT_WHITE = CludesUI.TEXT_WHITE
    local MEDIA_PATH = CludesUI.MEDIA_PATH
    local TEXT_DIM_R = CludesUI.TEXT_DIM_R
    local TEXT_DIM_G = CludesUI.TEXT_DIM_G
    local TEXT_DIM_B = CludesUI.TEXT_DIM_B
    local TEXT_DIM_A = CludesUI.TEXT_DIM_A
    local BORDER_R = CludesUI.BORDER_R
    local BORDER_G = CludesUI.BORDER_G
    local BORDER_B = CludesUI.BORDER_B
    local MakeStyledButton = CludesUI.MakeStyledButton
    local RB_COLOURS = CludesUI.RB_COLOURS
    local ShowWidgetTooltip = CludesUI.ShowWidgetTooltip
    local HideWidgetTooltip = CludesUI.HideWidgetTooltip
    local WI = CludesUI._widgetInternals
    local TagOptionRow = WI.TagOptionRow
    local PrebuildStandIn = WI.PrebuildStandIn
    local WidgetFactory = CludesUI.Widgets

    -------------------------------------------------------------------------------
    --  HSV RGB Conversion Helpers
    -------------------------------------------------------------------------------
    local function HSVtoRGB(height, s, val)
        local c = val * s
        local posX = c * (1 - math.abs((height / 60) % 2 - 1))
        local m = val - c
        local red, green, blue
        if height < 60 then
            red, green, blue = c, posX, 0
        elseif height < 120 then
            red, green, blue = posX, c, 0
        elseif height < 180 then
            red, green, blue = 0, c, posX
        elseif height < 240 then
            red, green, blue = 0, posX, c
        elseif height < 300 then
            red, green, blue = posX, 0, c
        else
            red, green, blue = c, 0, posX
        end
        return red + m, green + m, blue + m
    end

    local function RGBtoHSV(red, green, blue)
        local mx = math.max(red, green, blue)
        local mn = math.min(red, green, blue)
        local d = mx - mn
        local height, s, val
        val = mx
        s = (mx == 0) and 0 or (d / mx)
        if d == 0 then
            height = 0
        elseif mx == red then
            height = 60 * (((green - blue) / d) % 6)
        elseif mx == green then
            height = 60 * (((blue - red) / d) + 2)
        else
            height = 60 * (((red - green) / d) + 4)
        end
        return height, s, val
    end

    -------------------------------------------------------------------------------
    --  Color Picker recent-colors & favorites (file-scope, shared per session)
    -------------------------------------------------------------------------------
    local PICKER_MAX_SWATCHES = 10

    local function GetPickerDB()
        if not CludesUIDB then
            return {}
        end
        if not CludesUIDB.colorPicker then
            CludesUIDB.colorPicker = {}
        end
        return CludesUIDB.colorPicker
    end
    local function GetRecentColorsDB()
        local saved = GetPickerDB()
        if not saved.recentColors then
            saved.recentColors = {}
        end
        return saved.recentColors
    end
    local function GetFavoritesDB()
        local saved = GetPickerDB()
        if not saved.favorites then
            saved.favorites = {}
        end
        return saved.favorites
    end
    local function ColorKey(red, green, blue)
        return string.format(
            "%d-%d-%d",
            math.floor(red * 255 + 0.5),
            math.floor(green * 255 + 0.5),
            math.floor(blue * 255 + 0.5)
        )
    end
    local function RecordRecentColor(red, green, blue)
        local saved = GetRecentColorsDB()
        local key = ColorKey(red, green, blue)
        for idx = #saved, 1, -1 do
            if ColorKey(saved[idx][1], saved[idx][2], saved[idx][3]) == key then
                table.remove(saved, idx)
            end
        end
        table.insert(saved, 1, { red, green, blue })
        while #saved > PICKER_MAX_SWATCHES do
            table.remove(saved)
        end
    end
    local function IsFavorite(red, green, blue)
        local key = ColorKey(red, green, blue)
        for _, c in ipairs(GetFavoritesDB()) do
            if ColorKey(c[1], c[2], c[3]) == key then
                return true
            end
        end
        return false
    end
    local function ToggleFavorite(red, green, blue)
        local saved = GetFavoritesDB()
        local key = ColorKey(red, green, blue)
        for idx = #saved, 1, -1 do
            if ColorKey(saved[idx][1], saved[idx][2], saved[idx][3]) == key then
                table.remove(saved, idx)
                return false
            end
        end
        table.insert(saved, 1, { red, green, blue })
        while #saved > PICKER_MAX_SWATCHES do
            table.remove(saved)
        end
        return true
    end

    -------------------------------------------------------------------------------
    --  Custom Color Picker Popup (singleton, replaces Blizzard ColorPickerFrame)
    -------------------------------------------------------------------------------
    local function BuildColorPickerPopup()
        local PAD = 31
        local PAD_TOP = 21
        local SV_SIZE = 200
        local BAR_W = 20
        local BAR_GAP = 10
        local RIGHT_W = 70
        local RIGHT_GAP = 19
        local PAD_RIGHT = 26
        local POPUP_H = PAD_TOP + 28 + SV_SIZE + 80 + PAD
        local BASE_W = PAD + SV_SIZE + BAR_GAP + BAR_W + BAR_GAP + BAR_W + RIGHT_GAP + RIGHT_W + PAD_RIGHT
        local BASE_W_NO_ALPHA = PAD + SV_SIZE + BAR_GAP + BAR_W + RIGHT_GAP + RIGHT_W + PAD_RIGHT
        -- Extra RIGHT COLUMN height when the picker has an alpha slider, so OK/Cancel clear the Opacity input inserted below Hex#. Popup height and the left-side favorites/recent rows are NOT affected.
        local OPACITY_BLOCK_H = 50

        local currentH, currentS, currentV, currentA = 0, 1, 1, 1
        local prevR, prevG, prevB, prevA = 1, 1, 1, 1
        local swatchFunc, opacityFunc, cancelFunc
        local hasOpacity = false
        local updating = false

        local dialog = CreateFrame("Frame", "CludesUIColorPicker", UIParent)
        dialog:SetSize(BASE_W, POPUP_H)
        dialog:SetPoint("CENTER")
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:SetFrameLevel(400)
        dialog:SetClampedToScreen(true)
        dialog:SetMovable(true)
        dialog:EnableMouse(true)
        dialog:Hide()

        -- Click-off close via GLOBAL_MOUSE_DOWN (non-blocking: preserves hover/click on every other frame)
        local clickOffFrame = CreateFrame("Frame")
        clickOffFrame:Hide()
        clickOffFrame:SetScript("OnEvent", function(_, evt)
            if evt == "GLOBAL_MOUSE_DOWN" then
                if dialog:IsShown() and not dialog:IsMouseOver() then
                    if cancelFunc then
                        cancelFunc()
                    end
                    dialog:Hide()
                end
            end
        end)
        dialog:HookScript("OnShow", function()
            -- Defer registration one frame so the mouse-down that opened the popup doesn't immediately trigger click-outside-to-close.
            C_Timer.After(0, function()
                if dialog:IsShown() then
                    clickOffFrame:RegisterEvent("GLOBAL_MOUSE_DOWN")
                    clickOffFrame:Show()
                end
            end)
        end)
        dialog:HookScript("OnHide", function()
            clickOffFrame:UnregisterEvent("GLOBAL_MOUSE_DOWN")
            clickOffFrame:Hide()
        end)

        local backdrop = dialog:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(0.062, 0.070, 0.082, 1)

        CludesUI.MakeRoundedBorder(dialog, BORDER_R, BORDER_G, BORDER_B, 0.15, backdrop)

        -- Title bar (draggable)
        local titleBar = CreateFrame("Frame", nil, dialog)
        titleBar:SetHeight(28)
        titleBar:SetPoint("TOPLEFT")
        titleBar:SetPoint("TOPRIGHT")
        titleBar:EnableMouse(true)
        titleBar:RegisterForDrag("LeftButton")
        titleBar:SetScript("OnDragStart", function()
            dialog:StartMoving()
        end)
        titleBar:SetScript("OnDragStop", function()
            dialog:StopMovingOrSizing()
        end)
        -- House look: an accent cap, a header band (to just above the colour
        -- field) with a hairline under it, and the title on its left.
        local band = dialog:CreateTexture(nil, "BACKGROUND", nil, 2)
        band:SetColorTexture(1, 1, 1, 0.035)
        band:SetPoint("TOPLEFT")
        band:SetPoint("TOPRIGHT")
        band:SetHeight(44)
        local bandLine = dialog:CreateTexture(nil, "ARTWORK")
        bandLine:SetColorTexture(1, 1, 1, 0.08)
        bandLine:SetPoint("TOPLEFT", band, "BOTTOMLEFT")
        bandLine:SetPoint("TOPRIGHT", band, "BOTTOMRIGHT")
        bandLine:SetHeight(1)
        local cap = dialog:CreateTexture(nil, "ARTWORK", nil, 1)
        cap:SetPoint("TOPLEFT")
        cap:SetPoint("TOPRIGHT")
        cap:SetHeight(2)
        dialog:HookScript("OnShow", function()
            local color = CludesUI.CLUDES_GREEN
            cap:SetColorTexture(color.r, color.g, color.b, 0.9)
        end)
        local titleLbl = MakeFont(titleBar, 13, nil, 1, 1, 1)
        titleLbl:SetPoint("LEFT", dialog, "TOPLEFT", PAD, -24)
        titleLbl:SetText(CludesUI.L("Color Picker"):upper())

        local closeBtn = CreateFrame("Button", nil, dialog)
        closeBtn:SetSize(25, 25)
        closeBtn:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -13, -12)
        closeBtn:SetFrameLevel(dialog:GetFrameLevel() + 5)
        -- The rounded outline around the plain X (the old art had a square box drawn in).
        local closeBrd = CludesUI.MakeRoundedBorder(closeBtn, 1, 1, 1, 0.40)
        local closeIcon = closeBtn:CreateTexture(nil, "ARTWORK")
        closeIcon:SetPoint("TOPLEFT", 7, -7)
        closeIcon:SetPoint("BOTTOMRIGHT", -7, 7)
        closeIcon:SetTexture(MEDIA_PATH .. "icons/cui-close.png")
        closeIcon:SetAlpha(0.40)
        closeIcon:SetSnapToPixelGrid(false)
        closeIcon:SetTexelSnappingBias(0)
        closeBtn:SetScript("OnEnter", function()
            closeIcon:SetAlpha(0.50)
            closeBrd:SetColor(1, 1, 1, 0.50)
        end)
        closeBtn:SetScript("OnLeave", function()
            closeIcon:SetAlpha(0.40)
            closeBrd:SetColor(1, 1, 1, 0.40)
        end)
        closeBtn:SetScript("OnClick", function()
            if cancelFunc then
                cancelFunc()
            end
            dialog:Hide()
        end)

        -- Getters kept Blizzard-API-compatible
        local outR, outG, outB, outA = 1, 1, 1, 1
        function dialog:GetColorRGB()
            return outR, outG, outB
        end
        function dialog:GetColorAlpha()
            return outA
        end

        -- Forward declarations
        local UpdateSVPadHue, UpdateSVCrosshair, UpdateHueIndicator
        local UpdateAlphaBar, UpdateHexInput, UpdateOpacityInput
        local newPreviewTex, prevPreviewTex

        local function FireCallbacks()
            if swatchFunc then
                swatchFunc()
            end
            if hasOpacity and opacityFunc then
                opacityFunc()
            end
        end

        local function UpdateAllControls()
            if updating then
                return
            end
            updating = true
            local red, green, blue = HSVtoRGB(currentH, currentS, currentV)
            outR, outG, outB, outA = red, green, blue, currentA
            if UpdateSVPadHue then
                UpdateSVPadHue(currentH)
            end
            if UpdateSVCrosshair then
                UpdateSVCrosshair(currentS, currentV)
            end
            if UpdateHueIndicator then
                UpdateHueIndicator(currentH)
            end
            if UpdateAlphaBar then
                UpdateAlphaBar(red, green, blue, currentA)
            end
            if UpdateHexInput then
                UpdateHexInput(red, green, blue)
            end
            if UpdateOpacityInput then
                UpdateOpacityInput(currentA)
            end
            if newPreviewTex then
                newPreviewTex:SetColorTexture(red, green, blue, currentA)
            end
            updating = false
        end

        local svPad = CreateFrame("Frame", nil, dialog)
        svPad:SetSize(SV_SIZE, SV_SIZE)
        svPad:SetPoint("TOPLEFT", dialog, "TOPLEFT", PAD, -(PAD_TOP + 28))
        svPad:EnableMouse(true)

        local svHue = svPad:CreateTexture(nil, "BACKGROUND")
        svHue:SetAllPoints()
        svHue:SetColorTexture(1, 0, 0, 1)

        local svWhite = svPad:CreateTexture(nil, "BORDER")
        svWhite:SetAllPoints()
        svWhite:SetColorTexture(1, 1, 1, 1)
        svWhite:SetGradient("HORIZONTAL", CreateColor(1, 1, 1, 1), CreateColor(1, 1, 1, 0))

        local svBlack = svPad:CreateTexture(nil, "ARTWORK")
        svBlack:SetAllPoints()
        svBlack:SetColorTexture(0, 0, 0, 1)
        svBlack:SetGradient("VERTICAL", CreateColor(0, 0, 0, 1), CreateColor(0, 0, 0, 0))

        -- Opaque: white at 6% over the popup's background, so it reads as before.
        local EDGE_R, EDGE_G, EDGE_B = 0.077 * 0.94 + 0.06, 0.068 * 0.94 + 0.06, 0.058 * 0.94 + 0.06
        -- The three layers stay square: a mask on each let the hue show through
        -- the partly drawn gradients at the edge (a red rim). The cover in the
        -- popup's colour rounds them, and they fill the outline's whole-pixel
        -- seat, so no part of an edge pixel lies outside it.
        local svEdge = CludesUI.MakeRoundedBorder(svPad, EDGE_R, EDGE_G, EDGE_B, 1)
        svEdge:SetCover(0.062, 0.070, 0.082)
        svHue:SetAllPoints(svEdge._frame)
        svWhite:SetAllPoints(svEdge._frame)
        svBlack:SetAllPoints(svEdge._frame)

        local ARM = 6
        local chT = svPad:CreateTexture(nil, "OVERLAY", nil, 7)
        chT:SetSize(1, ARM)
        chT:SetColorTexture(1, 1, 1, 0.9)
        local chB = svPad:CreateTexture(nil, "OVERLAY", nil, 7)
        chB:SetSize(1, ARM)
        chB:SetColorTexture(1, 1, 1, 0.9)
        local chL = svPad:CreateTexture(nil, "OVERLAY", nil, 7)
        chL:SetSize(ARM, 1)
        chL:SetColorTexture(1, 1, 1, 0.9)
        local chR = svPad:CreateTexture(nil, "OVERLAY", nil, 7)
        chR:SetSize(ARM, 1)
        chR:SetColorTexture(1, 1, 1, 0.9)

        UpdateSVPadHue = function(height)
            local red, green, blue = HSVtoRGB(height, 1, 1)
            svHue:SetColorTexture(red, green, blue, 1)
        end
        UpdateSVCrosshair = function(s, val)
            local posX = s * SV_SIZE
            local cursorY = -(1 - val) * SV_SIZE
            chT:ClearAllPoints()
            chT:SetPoint("BOTTOM", svPad, "TOPLEFT", posX, cursorY + 2)
            chB:ClearAllPoints()
            chB:SetPoint("TOP", svPad, "TOPLEFT", posX, cursorY - 2)
            chL:ClearAllPoints()
            chL:SetPoint("RIGHT", svPad, "TOPLEFT", posX - 2, cursorY)
            chR:ClearAllPoints()
            chR:SetPoint("LEFT", svPad, "TOPLEFT", posX + 2, cursorY)
        end

        local svDragging = false
        local function SVFromCursor()
            local curX, curY = GetCursorPosition()
            local scale = svPad:GetEffectiveScale()
            curX, curY = curX / scale, curY / scale
            local leftX, bottom = svPad:GetLeft(), svPad:GetBottom()
            local s = math.max(0, math.min(1, (curX - leftX) / SV_SIZE))
            local val = math.max(0, math.min(1, (curY - bottom) / SV_SIZE))
            return s, val
        end
        svPad:SetScript("OnMouseDown", function(self, button)
            if button == "LeftButton" then
                svDragging = true
                currentS, currentV = SVFromCursor()
                UpdateAllControls()
                FireCallbacks()
                self:SetScript("OnUpdate", function()
                    if not IsMouseButtonDown("LeftButton") then
                        svDragging = false
                        self:SetScript("OnUpdate", nil)
                        return
                    end
                    currentS, currentV = SVFromCursor()
                    UpdateAllControls()
                    FireCallbacks()
                end)
            end
        end)
        svPad:SetScript("OnMouseUp", function(self)
            svDragging = false
            self:SetScript("OnUpdate", nil)
        end)

        local hueBar = CreateFrame("Frame", nil, dialog)
        hueBar:SetSize(BAR_W, SV_SIZE)
        hueBar:SetPoint("TOPLEFT", svPad, "TOPRIGHT", BAR_GAP, 0)
        hueBar:EnableMouse(true)

        local HUE_COLORS = {
            { 1, 0, 0 },
            { 1, 1, 0 },
            { 0, 1, 0 },
            { 0, 1, 1 },
            { 0, 0, 1 },
            { 1, 0, 1 },
            { 1, 0, 0 },
        }
        local segH = SV_SIZE / 6
        local hueMask
        for idx = 1, 6 do
            local seg = hueBar:CreateTexture(nil, "BACKGROUND")
            seg:SetSize(BAR_W, segH)
            seg:SetPoint("TOPLEFT", hueBar, "TOPLEFT", 0, -(idx - 1) * segH)
            seg:SetColorTexture(1, 1, 1, 1)
            local topY, bot = HUE_COLORS[idx], HUE_COLORS[idx + 1]
            seg:SetGradient(
                "VERTICAL",
                CreateColor(bot[1], bot[2], bot[3], 1),
                CreateColor(topY[1], topY[2], topY[3], 1)
            )
            -- One rounded mask over the whole bar for all six segments.
            if hueMask then
                seg:AddMaskTexture(hueMask)
            else
                hueMask = CludesUI.RoundBody(hueBar, seg)
                if hueMask then
                    hueMask:ClearAllPoints()
                    hueMask:SetAllPoints(hueBar)
                end
            end
        end
        CludesUI.MakeRoundedBorder(hueBar, EDGE_R, EDGE_G, EDGE_B, 1)

        local hueInd = hueBar:CreateTexture(nil, "OVERLAY", nil, 7)
        hueInd:SetSize(BAR_W + 4, 2)
        hueInd:SetColorTexture(1, 1, 1, 1)

        UpdateHueIndicator = function(height)
            hueInd:ClearAllPoints()
            hueInd:SetPoint("CENTER", hueBar, "TOPLEFT", BAR_W / 2, -(height / 360) * SV_SIZE)
        end

        local hueDragging = false
        local function HueFromCursor()
            local _, curY = GetCursorPosition()
            curY = curY / hueBar:GetEffectiveScale()
            return math.max(0, math.min(1, (hueBar:GetTop() - curY) / SV_SIZE)) * 360
        end
        hueBar:SetScript("OnMouseDown", function(self, button)
            if button == "LeftButton" then
                hueDragging = true
                currentH = HueFromCursor()
                UpdateAllControls()
                FireCallbacks()
                self:SetScript("OnUpdate", function()
                    if not IsMouseButtonDown("LeftButton") then
                        hueDragging = false
                        self:SetScript("OnUpdate", nil)
                        return
                    end
                    currentH = HueFromCursor()
                    UpdateAllControls()
                    FireCallbacks()
                end)
            end
        end)
        hueBar:SetScript("OnMouseUp", function(self)
            hueDragging = false
            self:SetScript("OnUpdate", nil)
        end)

        local alphaBar = CreateFrame("Frame", nil, dialog)
        alphaBar:SetSize(BAR_W, SV_SIZE)
        alphaBar:SetPoint("TOPLEFT", hueBar, "TOPRIGHT", BAR_GAP, 0)
        alphaBar:EnableMouse(true)

        local alphaGrad = alphaBar:CreateTexture(nil, "ARTWORK")
        alphaGrad:SetAllPoints()
        alphaGrad:SetColorTexture(1, 0, 0, 1)
        -- The gradient's rounded mask covers the whole bar; the checkerboard shares it.
        local alphaMask = CludesUI.RoundBody(alphaBar, alphaGrad)

        local CK = 10 -- coarse checkerboard cell: 2 cols x 20 rows = 40 textures
        local ckCols = math.ceil(BAR_W / CK)
        local ckRows = math.ceil(SV_SIZE / CK)
        for row = 0, ckRows - 1 do
            for col = 0, ckCols - 1 do
                local c = ((row + col) % 2 == 0) and 0.3 or 0.15
                local ck = alphaBar:CreateTexture(nil, "BACKGROUND")
                ck:SetSize(CK, CK)
                ck:SetPoint("TOPLEFT", alphaBar, "TOPLEFT", col * CK, -row * CK)
                ck:SetColorTexture(c, c, c, 1)
                if alphaMask then
                    ck:AddMaskTexture(alphaMask)
                end
            end
        end

        local alphaInd = alphaBar:CreateTexture(nil, "OVERLAY", nil, 7)
        alphaInd:SetSize(BAR_W + 4, 2)
        alphaInd:SetColorTexture(1, 1, 1, 1)
        CludesUI.MakeRoundedBorder(alphaBar, EDGE_R, EDGE_G, EDGE_B, 1)

        -- Reused CreateColor objects: no per-frame allocation during drag
        local alphaColorBot = CreateColor(0, 0, 0, 0)
        local alphaColorTop = CreateColor(0, 0, 0, 1)

        UpdateAlphaBar = function(red, green, blue, a)
            alphaColorBot.r, alphaColorBot.g, alphaColorBot.b, alphaColorBot.a = red, green, blue, 0
            alphaColorTop.r, alphaColorTop.g, alphaColorTop.b, alphaColorTop.a = red, green, blue, 1
            alphaGrad:SetGradient("VERTICAL", alphaColorBot, alphaColorTop)
            alphaInd:ClearAllPoints()
            alphaInd:SetPoint("CENTER", alphaBar, "TOPLEFT", BAR_W / 2, -(1 - a) * SV_SIZE)
        end

        local alphaDragging = false
        local function AlphaFromCursor()
            local _, curY = GetCursorPosition()
            curY = curY / alphaBar:GetEffectiveScale()
            return 1 - math.max(0, math.min(1, (alphaBar:GetTop() - curY) / SV_SIZE))
        end
        alphaBar:SetScript("OnMouseDown", function(self, button)
            if button == "LeftButton" then
                alphaDragging = true
                currentA = AlphaFromCursor()
                UpdateAllControls()
                FireCallbacks()
                self:SetScript("OnUpdate", function()
                    if not IsMouseButtonDown("LeftButton") then
                        alphaDragging = false
                        self:SetScript("OnUpdate", nil)
                        return
                    end
                    currentA = AlphaFromCursor()
                    UpdateAllControls()
                    FireCallbacks()
                end)
            end
        end)
        alphaBar:SetScript("OnMouseUp", function(self)
            alphaDragging = false
            self:SetScript("OnUpdate", nil)
        end)

        -- Controller cursor: the three pads read the pointer position, which its presses
        -- do not move, so they are skipped (Hex#, Opacity and the swatches set colours);
        -- the drag bar is no stop, and Cancel clicks the close button.
        if CludesUI.PadCP() then
            CludesUI.PadHint(svPad, "nodeignore")
            CludesUI.PadHint(hueBar, "nodeignore")
            CludesUI.PadHint(alphaBar, "nodeignore")
            CludesUI.PadHint(titleBar, "nodepass")
            dialog.CloseButton = closeBtn
        end

        ---------------------------------------------------------------------------
        --  Right column: New, Prev, Hex#, OK
        ---------------------------------------------------------------------------
        local rightCol = CreateFrame("Frame", nil, dialog)
        rightCol:SetSize(RIGHT_W, SV_SIZE)
        rightCol:SetPoint("TOPLEFT", alphaBar, "TOPRIGHT", RIGHT_GAP, 0)

        local nl = MakeFont(rightCol, 10, nil, 1, 1, 1)
        nl:SetAlpha(TEXT_DIM_A)
        nl:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, 0)
        nl:SetText(CludesUI.L("New"))

        newPreviewTex = rightCol:CreateTexture(nil, "ARTWORK")
        newPreviewTex:SetSize(RIGHT_W, 26)
        newPreviewTex:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, -14)
        newPreviewTex:SetColorTexture(1, 1, 1, 1)
        CludesUI.RoundBody(rightCol, newPreviewTex)

        -- Prev preview sits directly below New
        local prevPrev = rightCol:CreateTexture(nil, "ARTWORK")
        prevPrev:SetSize(RIGHT_W, 26)
        prevPrev:SetPoint("TOPLEFT", newPreviewTex, "BOTTOMLEFT", 0, -4)
        prevPrev:SetColorTexture(1, 1, 1, 1)
        CludesUI.RoundBody(rightCol, prevPrev)
        prevPreviewTex = prevPrev

        -- Clicking the prev swatch restores the previous color
        local prevBtn = CreateFrame("Button", nil, rightCol)
        prevBtn:SetAllPoints(prevPrev)
        prevBtn:SetFrameLevel(rightCol:GetFrameLevel() + 5)
        prevBtn:SetScript("OnClick", function()
            currentH, currentS, currentV = RGBtoHSV(prevR, prevG, prevB)
            currentA = hasOpacity and prevA or 1
            UpdateAllControls()
            FireCallbacks()
        end)

        local pl = MakeFont(rightCol, 10, nil, 1, 1, 1)
        pl:SetAlpha(TEXT_DIM_A)
        pl:SetPoint("TOPLEFT", prevPrev, "BOTTOMLEFT", 0, -6)
        pl:SetText(CludesUI.L("Prev"))

        local hexLbl = MakeFont(rightCol, 10, nil, 1, 1, 1)
        hexLbl:SetAlpha(TEXT_DIM_A)
        hexLbl:SetPoint("TOPLEFT", pl, "BOTTOMLEFT", 0, -21)
        hexLbl:SetText(CludesUI.L("Hex#"))

        local hexBox = CreateFrame("EditBox", nil, rightCol)
        hexBox:SetSize(RIGHT_W, 24)
        hexBox:SetPoint("TOPLEFT", hexLbl, "BOTTOMLEFT", 0, -4)
        hexBox:SetFont(EXPRESSWAY, 10, "")
        hexBox:SetTextColor(TEXT_DIM_R, TEXT_DIM_G, TEXT_DIM_B, TEXT_DIM_A)
        hexBox:SetMaxLetters(7) -- six digits and an optional leading #, as colours are usually written
        hexBox:SetAutoFocus(false)
        hexBox:EnableMouse(true)
        hexBox:SetJustifyH("CENTER")
        local hbg = hexBox:CreateTexture(nil, "BACKGROUND")
        hbg:SetAllPoints()
        hbg:SetColorTexture(0.213, 0.204, 0.196, 0.5)
        CludesUI.MakeRoundedBorder(hexBox, 1, 1, 1, 0.04, hbg)

        local lastValidHex = "FFFFFF"
        local lastHexR, lastHexG, lastHexB = -1, -1, -1
        UpdateHexInput = function(red, green, blue)
            if hexBox:HasFocus() then
                return
            end
            local ri, gi, bi = math.floor(red * 255 + 0.5), math.floor(green * 255 + 0.5), math.floor(blue * 255 + 0.5)
            if ri == lastHexR and gi == lastHexG and bi == lastHexB then
                return
            end
            lastHexR, lastHexG, lastHexB = ri, gi, bi
            local hex = string.format("%02X%02X%02X", ri, gi, bi)
            lastValidHex = hex
            hexBox:SetText(hex)
        end
        -- The six hex digits in text ("#4cc9f0", "4CC9F0"), or nil. short: also
        -- take three digits as shorthand ("FFF" is "FFFFFF"), for a finished
        -- entry only, as three digits are also the first half of six.
        local function ParseHex(text, short)
            local digits = (text or ""):upper():gsub("[^%dA-F]", "")
            if short and #digits == 3 then
                digits = digits:gsub("(.)", "%1%1")
            end
            if #digits == 6 then
                return digits
            end
        end
        local function ApplyHex(digits)
            local ri, gi, bi =
                tonumber(digits:sub(1, 2), 16) / 255,
                tonumber(digits:sub(3, 4), 16) / 255,
                tonumber(digits:sub(5, 6), 16) / 255
            currentH, currentS, currentV = RGBtoHSV(ri, gi, bi)
            lastValidHex = digits
            UpdateAllControls()
            FireCallbacks()
        end
        local function CommitHex()
            local digits = ParseHex(hexBox:GetText(), true)
            if digits then
                ApplyHex(digits)
                hexBox:SetText(digits)
            else
                hexBox:SetText(lastValidHex)
            end
        end
        local hexEscaping = false
        hexBox:SetScript("OnEnterPressed", function()
            CommitHex()
            hexBox:ClearFocus()
        end)
        hexBox:SetScript("OnEscapePressed", function()
            hexEscaping = true
            hexBox:SetText(lastValidHex)
            hexBox:ClearFocus()
            hexEscaping = false
            if cancelFunc then
                cancelFunc()
            end
            dialog:Hide()
        end)
        hexBox:SetScript("OnEditFocusLost", function()
            if not hexEscaping then
                CommitHex()
            end
        end)
        hexBox:SetScript("OnEditFocusGained", function()
            hexBox:HighlightText()
        end)
        hexBox:SetScript("OnTextChanged", function(self, userInput)
            if not self:HasFocus() then
                return
            end
            -- A whole colour typed or pasted shows at once.
            local digits = ParseHex(self:GetText())
            if digits and digits ~= lastValidHex then
                ApplyHex(digits)
            end
        end)

        -- Opacity input: shown only with an alpha slider, below Hex# and styled identically. Integer percentage, 0-100.
        local opacityLbl = MakeFont(rightCol, 10, nil, 1, 1, 1)
        opacityLbl:SetAlpha(TEXT_DIM_A)
        opacityLbl:SetPoint("TOPLEFT", hexBox, "BOTTOMLEFT", 0, -10)
        opacityLbl:SetText(CludesUI.L("Opacity"))

        local opacityBox = CreateFrame("EditBox", nil, rightCol)
        opacityBox:SetSize(RIGHT_W, 24)
        opacityBox:SetPoint("TOPLEFT", opacityLbl, "BOTTOMLEFT", 0, -4)
        opacityBox:SetFont(EXPRESSWAY, 10, "")
        opacityBox:SetTextColor(TEXT_DIM_R, TEXT_DIM_G, TEXT_DIM_B, TEXT_DIM_A)
        opacityBox:SetMaxLetters(3)
        opacityBox:SetAutoFocus(false)
        opacityBox:EnableMouse(true)
        opacityBox:SetNumeric(true)
        opacityBox:SetJustifyH("CENTER")
        local obg = opacityBox:CreateTexture(nil, "BACKGROUND")
        obg:SetAllPoints()
        obg:SetColorTexture(0.213, 0.204, 0.196, 0.5)
        CludesUI.MakeRoundedBorder(opacityBox, 1, 1, 1, 0.04, obg)

        local lastOpacityPct = -1
        UpdateOpacityInput = function(a)
            if opacityBox:HasFocus() then
                return
            end
            local pct = math.floor((a or 1) * 100 + 0.5)
            if pct == lastOpacityPct then
                return
            end
            lastOpacityPct = pct
            opacityBox:SetText(tostring(pct))
        end
        -- Parse the box and apply as alpha. commit=true snaps back to the live value when unparseable (Enter/focus loss).
        local function ApplyOpacityText(commit)
            local num = tonumber(opacityBox:GetText())
            if num then
                num = math.max(0, math.min(100, math.floor(num + 0.5)))
                currentA = num / 100
                lastOpacityPct = num
                UpdateAllControls()
                FireCallbacks()
                return true
            elseif commit then
                opacityBox:SetText(tostring(math.floor(currentA * 100 + 0.5)))
            end
            return false
        end
        local opacityEscaping = false
        opacityBox:SetScript("OnEnterPressed", function()
            ApplyOpacityText(true)
            opacityBox:ClearFocus()
        end)
        opacityBox:SetScript("OnEscapePressed", function()
            opacityEscaping = true
            opacityBox:SetText(tostring(math.floor(currentA * 100 + 0.5)))
            opacityBox:ClearFocus()
            opacityEscaping = false
            if cancelFunc then
                cancelFunc()
            end
            dialog:Hide()
        end)
        opacityBox:SetScript("OnEditFocusLost", function()
            if not opacityEscaping then
                ApplyOpacityText(true)
            end
        end)
        opacityBox:SetScript("OnEditFocusGained", function()
            opacityBox:HighlightText()
        end)
        opacityBox:SetScript("OnTextChanged", function(self, userInput)
            if not self:HasFocus() then
                return
            end
            ApplyOpacityText(false)
        end)
        opacityLbl:Hide()
        opacityBox:Hide()

        -- OK button, bottom of the right column (reset/reload button style)
        local okBtn = CreateFrame("Button", nil, rightCol)
        okBtn:SetSize(RIGHT_W, 21)
        okBtn:SetPoint("BOTTOMLEFT", rightCol, "BOTTOMLEFT", 0, 0)
        okBtn:SetFrameLevel(dialog:GetFrameLevel() + 2)
        local _confirmed = false
        MakeStyledButton(okBtn, "OK", 10, RB_COLOURS, function()
            RecordRecentColor(HSVtoRGB(currentH, currentS, currentV))
            -- Fire on OK even when nothing changed, to confirm the selection
            FireCallbacks()
            _confirmed = true
            dialog:Hide()
        end)

        -- Cancel text above OK button
        local cancelBtn = CreateFrame("Button", nil, rightCol)
        cancelBtn:SetSize(RIGHT_W, 14)
        cancelBtn:SetPoint("BOTTOM", okBtn, "TOP", 0, 5)
        cancelBtn:SetFrameLevel(dialog:GetFrameLevel() + 2)
        local cancelText = cancelBtn:CreateFontString(nil, "OVERLAY")
        cancelText:SetFont(EXPRESSWAY, 10, "")
        cancelText:SetPoint("CENTER")
        cancelText:SetText(CludesUI.L("cancel"))
        cancelText:SetTextColor(1, 1, 1, 0.4)
        cancelBtn:SetScript("OnEnter", function()
            cancelText:SetTextColor(1, 1, 1, 0.7)
        end)
        cancelBtn:SetScript("OnLeave", function()
            cancelText:SetTextColor(1, 1, 1, 0.4)
        end)
        cancelBtn:SetScript("OnClick", function()
            _confirmed = false
            dialog:Hide()
        end)

        ---------------------------------------------------------------------------
        --  Favorites & Recent Colors (below HSV picker)
        ---------------------------------------------------------------------------
        local RefreshSwatchRows
        local SWATCH_SZ = 19
        local SWATCH_SPACING = 4

        local function MakeSwatchBtn(hostFrame, isFavorites)
            local button = CreateFrame("Button", nil, hostFrame)
            button:SetSize(SWATCH_SZ, SWATCH_SZ)
            button:SetFrameLevel(hostFrame:GetFrameLevel() + 2)
            local texture = button:CreateTexture(nil, "ARTWORK")
            texture:SetAllPoints()
            button._tex = texture
            CludesUI.RoundBody(button, texture)
            button:SetScript("OnEnter", function(self)
                local color = self._color
                if not color then
                    return
                end
                local hex = string.format(
                    "%02X%02X%02X",
                    math.floor(color[1] * 255 + 0.5),
                    math.floor(color[2] * 255 + 0.5),
                    math.floor(color[3] * 255 + 0.5)
                )
                local hint = isFavorites and CludesUI.L("Right-click: remove favorite")
                    or CludesUI.L("Right-click: favorite")
                -- Anchor on the hovered swatch so the tooltip sits directly above it (default placement is BOTTOM -> anchor TOP).
                ShowWidgetTooltip(self, "|cff" .. hex .. "#|r" .. hex .. "\n" .. hint)
            end)
            button:SetScript("OnLeave", function()
                HideWidgetTooltip()
            end)
            button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            button:SetScript("OnClick", function(self, mouseButton)
                local color = self._color
                if not color then
                    return
                end
                if mouseButton == "RightButton" then
                    if isFavorites or not IsFavorite(color[1], color[2], color[3]) then
                        ToggleFavorite(color[1], color[2], color[3])
                    end
                    RefreshSwatchRows()
                else
                    currentH, currentS, currentV = RGBtoHSV(color[1], color[2], color[3])
                    UpdateAllControls()
                    FireCallbacks()
                end
            end)
            button:Hide()
            return button
        end

        local favLbl = MakeFont(dialog, 10, nil, 1, 1, 1)
        favLbl:SetAlpha(TEXT_DIM_A)
        favLbl:SetPoint("TOPLEFT", svPad, "BOTTOMLEFT", 0, -10)
        favLbl:SetText(CludesUI.L("Favorites"))

        local favRow = CreateFrame("Frame", nil, dialog)
        favRow:SetSize(BASE_W - PAD - PAD_RIGHT, SWATCH_SZ)
        favRow:SetPoint("TOPLEFT", favLbl, "BOTTOMLEFT", 0, -3)
        favRow._label = favLbl
        favRow._isFavorites = true

        local rcLbl = MakeFont(dialog, 10, nil, 1, 1, 1)
        rcLbl:SetAlpha(TEXT_DIM_A)
        rcLbl:SetPoint("TOPLEFT", favRow, "BOTTOMLEFT", 0, -8)
        rcLbl:SetText(CludesUI.L("Recent Colors"))

        local rcRow = CreateFrame("Frame", nil, dialog)
        rcRow:SetSize(BASE_W - PAD - PAD_RIGHT, SWATCH_SZ)
        rcRow:SetPoint("TOPLEFT", rcLbl, "BOTTOMLEFT", 0, -3)
        rcRow._label = rcLbl
        rcRow._isFavorites = false

        local favSwatches, rcSwatches = {}, {}

        local function PopulateSwatchRow(swatchPool, row, payload)
            local total = math.min(#payload, PICKER_MAX_SWATCHES)
            for idx = 1, math.max(total, #swatchPool) do
                local button = swatchPool[idx]
                if not button then
                    button = MakeSwatchBtn(row, row._isFavorites)
                    swatchPool[idx] = button
                end
                if idx <= total then
                    button._color = payload[idx]
                    button._tex:SetColorTexture(payload[idx][1], payload[idx][2], payload[idx][3], 1)
                    button:Show()
                    button:ClearAllPoints()
                    if idx == 1 then
                        button:SetPoint("LEFT", row, "LEFT", 0, 0)
                    else
                        button:SetPoint("LEFT", swatchPool[idx - 1], "RIGHT", SWATCH_SPACING, 0)
                    end
                else
                    button:Hide()
                end
            end
        end

        RefreshSwatchRows = function()
            PopulateSwatchRow(favSwatches, favRow, GetFavoritesDB())
            PopulateSwatchRow(rcSwatches, rcRow, GetRecentColorsDB())
        end

        -- Controller cursor: the swatch that opened the picker (set only when it opened under that cursor).
        local padOpener
        dialog:SetScript("OnHide", function()
            CludesUI._colorPickerOpen = false
            if not _confirmed and cancelFunc then
                cancelFunc()
            end
            _confirmed = false
            svDragging = false
            hueDragging = false
            alphaDragging = false
            svPad:SetScript("OnUpdate", nil)
            hueBar:SetScript("OnUpdate", nil)
            alphaBar:SetScript("OnUpdate", nil)
            local checks = CludesUI._deferredDriftChecks
            CludesUI._deferredDriftChecks = nil
            if checks then
                for func in pairs(checks) do
                    func()
                end
            end
            -- Re-evaluate widget state (sync icons, disabled overlays) now the picked color is committed. Fast path: no rebuild.
            CludesUI:RefreshPage()
            -- Controller cursor: back onto that swatch (a no-op once it is hidden).
            if padOpener then
                local opener = padOpener
                padOpener = nil
                if CludesUI.PadCursorShown() then
                    CludesUI.PadFocus(opener)
                end
            end
        end)
        CludesUI.RegisterEscapeClose(dialog)

        function dialog:Open(details, anchor)
            if dialog:IsShown() and cancelFunc then
                cancelFunc()
            end
            swatchFunc = details.swatchFunc
            opacityFunc = details.opacityFunc
            cancelFunc = details.cancelFunc
            hasOpacity = details.hasOpacity or false
            local red, green, blue = details.r or 0, details.g or 0, details.b or 0
            local a = details.opacity or 1
            prevR, prevG, prevB, prevA = red, green, blue, a
            currentH, currentS, currentV = RGBtoHSV(red, green, blue)
            currentA = hasOpacity and a or 1
            prevPreviewTex:SetColorTexture(red, green, blue, hasOpacity and a or 1)
            -- Reposition the right column by alpha-bar visibility. With an alpha slider ONLY the right column grows taller, so OK/Cancel clear the Opacity input below Hex#. Favorites/recent rows sit on the LEFT, clear of that column, so they and the popup height stay put.
            rightCol:ClearAllPoints()
            if hasOpacity then
                alphaBar:Show()
                dialog:SetWidth(BASE_W)
                rightCol:SetPoint("TOPLEFT", alphaBar, "TOPRIGHT", RIGHT_GAP, 0)
                rightCol:SetHeight(SV_SIZE + OPACITY_BLOCK_H)
                opacityLbl:Show()
                opacityBox:Show()
            else
                alphaBar:Hide()
                dialog:SetWidth(BASE_W_NO_ALPHA)
                rightCol:SetPoint("TOPLEFT", hueBar, "TOPRIGHT", RIGHT_GAP, 0)
                rightCol:SetHeight(SV_SIZE)
                opacityLbl:Hide()
                opacityBox:Hide()
            end
            dialog:ClearAllPoints()
            -- Horizontally centered on the cursor; vertical placement flips if needed
            local curX, curY = GetCursorPosition()
            local scale = dialog:GetEffectiveScale()
            curX, curY = curX / scale, curY / scale
            -- Controller cursor: the hidden pointer is nowhere near the swatch it pressed.
            if anchor and CludesUI.PadCursorShown() then
                padOpener = anchor
                local ax, ay = anchor:GetCenter()
                if ax and ay then
                    local ratio = anchor:GetEffectiveScale() / scale
                    curX, curY = ax * ratio, ay * ratio
                end
            end
            local pw = dialog:GetWidth()
            local ph = dialog:GetHeight()
            local posX = curX - pw * 0.5
            local cursorY = curY - 30 -- popup top 30px below the cursor
            -- Flip above the cursor if that would drop below the options window
            local mainFrame = CludesUI._mainFrame
            if mainFrame and mainFrame:IsShown() then
                local mBot = mainFrame:GetBottom()
                if mBot and (cursorY - ph) < mBot then
                    cursorY = curY + 30 + ph -- popup bottom 30px above the cursor
                end
            end
            dialog:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", posX, cursorY)
            CludesUI._colorPickerOpen = true
            RefreshSwatchRows()
            dialog:Show()
            UpdateAllControls()
            -- Controller cursor: into the picker, on OK (its first stop would be the close box).
            if CludesUI.PadCursorShown() then
                CludesUI.PadFocus(okBtn)
            end
        end

        -- Spec Overrides auto-capture: color picker edits attribute to the slot whose swatch opened it.
        dialog._cuiOptionsPopup = true
        CludesUI._colorPickerPopup = dialog
        return dialog
    end

    function CludesUI:ShowColorPicker(details, anchor)
        local dialog = self._colorPickerPopup or BuildColorPickerPopup()
        dialog:Open(details, anchor)
    end

    -- Shared color swatch: border + fill + UpdateSwatch + OnClick. Returns swatch (Button), UpdateSwatch (function), caller positions it. Border textures are deferred until first show to keep page builds light.
    local function BuildColorSwatch(parentFrame, baseLevel, getValue, setValue, hasAlpha, overrideSize)
        -- Search prebuild on an absorber row: the swatch indexes nothing, so none is built.
        local standIn = PrebuildStandIn(parentFrame)
        if standIn then
            return standIn, standIn
        end
        -- Spec Overrides auto-capture (see BuildToggleControl): fires for direct swatch writes and every color-picker change routed through it. The slot is read before the setter runs: a setter that rebuilds the page may dress the frames again for another slot.
        local userSet = setValue -- the caller's own setter, for picker writes made after a rebuild (OnClick)
        do
            local _s = setValue
            setValue = function(...)
                local snap = CludesUI._SOAttribution(parentFrame)
                _s(...)
                CludesUI._NotifySettingWrite(parentFrame, snap)
            end
        end
        do
            local _r = setValue
            setValue = function(...)
                _r(...)
                CludesUI._settingsChanged = true
            end
        end
        local SWATCH_SZ = overrideSize or 24
        local colorSwatch = CreateFrame("Button", nil, parentFrame)
        Pix.Size(colorSwatch, SWATCH_SZ, SWATCH_SZ)
        colorSwatch:SetFrameLevel(baseLevel)

        -- Color fill: 1 texture, always created immediately
        local sFill = colorSwatch:CreateTexture(nil, "ARTWORK")
        sFill:SetAllPoints()

        local borderBuilt = false

        local function BuildBorder()
            if borderBuilt then
                return
            end
            borderBuilt = true
            -- The rounded outline sits on a pixel layer (1 px at every Window
            -- Scale) on the swatch's edge; the fill takes the same shape.
            CludesUI.MakeRoundedBorder(colorSwatch, 1, 1, 1, 1, sFill)
        end

        local function UpdateSwatch()
            local red, green, blue, a = getValue()
            sFill:SetColorTexture(red or 0, green or 0, blue or 0, a or 1)
        end

        -- Initial fill color (no border needed yet)
        do
            local red, green, blue, a = getValue()
            sFill:SetColorTexture(red or 0, green or 0, blue or 0, a or 1)
        end

        -- Border builds lazily on first show, or now if already visible
        colorSwatch:HookScript("OnShow", function()
            if not borderBuilt then
                BuildBorder()
            end
        end)
        if colorSwatch:IsVisible() then
            BuildBorder()
        end

        colorSwatch:SetScript("OnClick", function()
            local red, green, blue, a = getValue()
            red, green, blue, a = red or 0, green or 0, blue or 0, a or 1
            local snapR, snapG, snapB, snapA = red, green, blue, a
            -- The dress the picker opens on. A page rebuild while the picker is
            -- open (page reuse) can dress this swatch again for another use, or
            -- leave it idle; what shows then is that rebuild's own paint.
            local openGen = PoolGen(colorSwatch)
            local function SameDress()
                return PoolGen(colorSwatch) == openGen and not PoolIsIdle(colorSwatch)
            end
            -- The slot the picker writes for, taken as it opens (Spec Overrides):
            -- every write names it, whatever a rebuild has made of the swatch
            -- since (dressed again for another slot, or left on a parked row).
            local openSlot = CludesUI._SOAttribution(parentFrame, {})
            -- Writes the setting the picker was opened for, naming that slot, and
            -- returns true while the swatch is still that dress (the caller then
            -- paints it); once it is not, nothing is painted and the frame is not
            -- named (it may hold another slot now).
            local function Write(cr, cg, checkBtn, ca)
                local same = SameDress()
                userSet(cr, cg, checkBtn, ca)
                CludesUI._NotifySettingWrite(same and parentFrame or nil, openSlot)
                CludesUI._settingsChanged = true
                return same and SameDress()
            end
            local function OnColorChanged()
                local dialog = CludesUI._colorPickerPopup
                if not dialog then
                    return
                end
                local cr, cg, checkBtn = dialog:GetColorRGB()
                local ca = hasAlpha and dialog:GetColorAlpha() or 1
                if SameDress() then
                    sFill:SetColorTexture(cr, cg, checkBtn, ca)
                end
                if Write(cr, cg, checkBtn, ca) then
                    UpdateSwatch()
                end
            end
            local details = {
                swatchFunc = function()
                    OnColorChanged()
                end,
                hasOpacity = hasAlpha,
                opacityFunc = function()
                    OnColorChanged()
                end,
                opacity = a,
                cancelFunc = function()
                    if Write(snapR, snapG, snapB, snapA) then
                        UpdateSwatch()
                    end
                end,
                r = red,
                g = green,
                b = blue,
            }
            CludesUI:ShowColorPicker(details, colorSwatch)
        end)

        -- Spec Overrides capture: an inline swatch belongs to its hosting slot (options files pass the DualRow half-region as parent), so it joins that slot's capture group. AddCaptureAccessor dedupes by getValue identity, so factory-built swatches whose accessors are stashed separately never double.
        if CludesUI.AddCaptureAccessor and not parentFrame._noCapture then
            CludesUI.AddCaptureAccessor(parentFrame, {
                type = "colorpicker",
                hasAlpha = hasAlpha,
                getValue = getValue,
                setValue = setValue,
            })
        end

        return colorSwatch, UpdateSwatch
    end

    -- default/custom/class color swatch trio; callers track a mode string. opts:
    --   getMode()           -> "default" | "custom" | "class"
    --   setMode(mode)       -> store the new mode
    --   getCustomRGB()      -> r, g, b of the custom color
    --   setCustomRGB(r,g,b) -> store the picked color
    --   onChange()          -> optional, called after any swatch click
    --   disabled()          -> optional, true to disable all swatches
    --   disabledAlpha       -> optional alpha while disabled (default 0.3)
    --   hasAlpha, overrideSize -> forwarded to BuildColorSwatch
    -- Returns customSwatch, defaultSwatch, classSwatch, Update.
    local DEFAULT_UNTINTED_R, DEFAULT_UNTINTED_G, DEFAULT_UNTINTED_B = 1.0, 0.788, 0.137
    local function BuildTrioColorSwatch(parentFrame, baseLevel, options)
        local customSwatch, updateCustom = BuildColorSwatch(parentFrame, baseLevel, function()
            local red, green, blue = options.getCustomRGB()
            return red, green, blue, 1
        end, function(red, green, blue)
            options.setCustomRGB(red, green, blue)
            options.setMode("custom")
            if options.onChange then
                options.onChange()
            end
        end, options.hasAlpha, options.overrideSize)
        customSwatch:HookScript("OnEnter", function()
            ShowWidgetTooltip(customSwatch, "Custom Color")
        end)
        customSwatch:HookScript("OnLeave", function()
            HideWidgetTooltip()
        end)
        -- Suite-wide multiSwatch convention: clicking an INACTIVE custom swatch only selects custom mode; the picker opens on a second click while custom is already active.
        customSwatch._eabOrigClick = customSwatch:GetScript("OnClick")
        customSwatch:SetScript("OnClick", function(self)
            if options.getMode() ~= "custom" then
                options.setMode("custom")
                if options.onChange then
                    options.onChange()
                end
                return
            end
            if self._eabOrigClick then
                self._eabOrigClick(self)
            end
        end)

        local defaultSwatch = BuildColorSwatch(parentFrame, baseLevel, function()
            return DEFAULT_UNTINTED_R, DEFAULT_UNTINTED_G, DEFAULT_UNTINTED_B, 1
        end, function() end, options.hasAlpha, options.overrideSize)
        defaultSwatch:SetScript("OnClick", function()
            options.setMode("default")
            if options.onChange then
                options.onChange()
            end
        end)
        defaultSwatch:SetScript("OnEnter", function()
            ShowWidgetTooltip(defaultSwatch, "Default")
        end)
        defaultSwatch:SetScript("OnLeave", function()
            HideWidgetTooltip()
        end)

        local classSwatch
        if options.hasClassColor then
            classSwatch = BuildColorSwatch(parentFrame, baseLevel, function()
                local classColor = CludesUI.GetClassColor(CludesUI._playerClass)
                return classColor.r, classColor.g, classColor.b, 1
            end, function() end, options.hasAlpha, options.overrideSize)
            classSwatch:SetScript("OnClick", function()
                options.setMode("class")
                if options.onChange then
                    options.onChange()
                end
            end)
            classSwatch:SetScript("OnEnter", function()
                ShowWidgetTooltip(classSwatch, "Class Colored")
            end)
            classSwatch:SetScript("OnLeave", function()
                HideWidgetTooltip()
            end)
        end

        local function Update()
            local disabled = options.disabled and options.disabled()
            local mode = options.getMode()
            if disabled then
                local a = options.disabledAlpha or 0.3
                customSwatch:SetAlpha(a)
                defaultSwatch:SetAlpha(a)
                if classSwatch then
                    classSwatch:SetAlpha(a)
                end
            else
                customSwatch:SetAlpha(mode == "custom" and 1 or 0.3)
                defaultSwatch:SetAlpha(mode == "default" and 1 or 0.3)
                if classSwatch then
                    classSwatch:SetAlpha(mode == "class" and 1 or 0.3)
                end
            end
            updateCustom()
        end
        Update()
        RegisterWidgetRefresh(Update)

        return customSwatch, defaultSwatch, classSwatch, Update
    end

    -- Color Picker row (swatch that opens the CludesUI picker popup)
    function WidgetFactory:ColorPicker(hostFrame, textValue, yOffset, getValue, setValue, hasAlpha)
        local ROW_H = 50
        local widget = CreateFrame("Frame", nil, hostFrame)
        Pix.Size(widget, hostFrame:GetWidth() - CONTENT_PAD * 2, ROW_H)
        Pix.Point(widget, "TOPLEFT", hostFrame, "TOPLEFT", CONTENT_PAD, yOffset)

        RowBg(widget, hostFrame)
        TagOptionRow(widget, hostFrame, textValue)

        local labelText = MakeFont(widget, 14, nil, TEXT_WHITE.r, TEXT_WHITE.g, TEXT_WHITE.b)
        Pix.Point(labelText, "LEFT", widget, "LEFT", 20, 0)
        labelText:SetText(CludesUI.L(textValue))

        local colorSwatch, UpdateSwatch =
            BuildColorSwatch(widget, widget:GetFrameLevel() + 1, getValue, setValue, hasAlpha)
        Pix.Point(colorSwatch, "RIGHT", widget, "RIGHT", -20, 0)

        -- Public refresh so external code can update the swatch after bar changes
        widget.RefreshSwatch = UpdateSwatch
        RegisterWidgetRefresh(function()
            UpdateSwatch()
        end)

        return widget, ROW_H
    end

    CludesUI.BuildColorSwatch = BuildColorSwatch
    CludesUI.BuildTrioColorSwatch = BuildTrioColorSwatch
end -- end deferred init
