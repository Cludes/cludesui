if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  ActionBars_Options\LivePreview_Options.lua
--  Action Bars options: the live preview in the Bar Display content header
--  (BuildLivePreview). Definitions only; the shared helpers come from
--  ns._ABO_OptEnv (filled by CUI_ActionBars_Options.lua).
-------------------------------------------------------------------------------
local mod = CludesUI._ModuleNS["CludesUIActionBars"]
if not mod then return end -- module disabled: no options page
-- Options page pool (CludesUI_FramePool.lua, first in this addon): the
-- preview is built on the header's kept root, so its frames are reset and
-- dressed again by the next build instead of made anew; on any other parent
-- this is CreateFrame.
local CreateFrame = CludesUI._Pool.CreateFrame

--- Build (or rebuild for a different bar) the live preview frame. Shows only
--- Edit-Mode-enabled buttons (numButtonsShowable) at the first real button's
--- GetWidth/GetHeight so icon size matches Blizzard's.
--- @param parent  Frame   scrollChild content parent
--- @param yOff    number  current y offset in the page layout
--- @return number height consumed by the preview
local function BuildLivePreview(hostFrame, yOff)
    local environ = mod._ABO_OptEnv
    local BAR_LOOKUP, ABAR, FirstBarButton, floor =
        environ.BAR_LOOKUP, environ.EAB, environ.FirstBarButton, environ.floor
    local optionState, pcall, Pix, RANGE_INDICATOR =
        environ.optState, environ.pcall, environ.PP, environ.RANGE_INDICATOR
    local SB, SelectedKey = environ.SB, environ.SelectedKey
    local barId = SelectedKey()
    local barInfo = BAR_LOOKUP[barId]
    -- Skip visibility-only / data bars (no count). Guard on count, not buttonPrefix:
    -- custom bars (Bar9/Bar10) lack a prefix but render from EABButtons like any bar.
    if not barInfo or not barInfo.count then
        optionState.activePreview = nil
        return 0
    end

    local PAD = CludesUI.CONTENT_PAD
    local maxBtns = barInfo.count -- always 12, used for pre-allocation

    -- Our custom bar frame (may be nil during first build before bars are created)
    local barFrame = _G["EABBar_" .. barId]

    -- Real button size from the first button, rounded to kill float noise.
    local btn1 = FirstBarButton(barId)
    local realBtnW = math.floor((btn1 and btn1:GetWidth() or 0) + 0.5)
    local realBtnH = math.floor((btn1 and btn1:GetHeight() or 0) + 0.5)
    if realBtnW < 1 then realBtnW = 36 end
    if realBtnH < 1 then realBtnH = 36 end

    -- No Blizzard Edit Mode scale: our bar scale applies directly to the frame.
    local blizzEditScale = 1

    local baseBtnW = realBtnW
    local baseBtnH = realBtnH

    -- Initial height estimate (will be recalculated in Update)
    local initH = baseBtnH + 20

    local popFrame = CreateFrame("Frame", nil, hostFrame)
    -- Scale the preview so it matches real action bar size on screen.
    local previewScale = UIParent:GetEffectiveScale() / hostFrame:GetEffectiveScale()
    popFrame:SetScale(previewScale)
    local localParentW = (hostFrame:GetWidth() - PAD * 2) / previewScale
    Pix.Size(popFrame, localParentW, initH)

    -- Max visible height for the preview area (in parent-space pixels)
    local PREVIEW_MAX_H = 200

    -- Wrapper frame at parent scale; holds the scroll frame and scrollbar
    local wrapper = CreateFrame("Frame", nil, hostFrame)
    wrapper:SetPoint("TOPLEFT", hostFrame, "TOPLEFT", PAD, yOff)
    wrapper:SetSize(hostFrame:GetWidth() - PAD * 2, PREVIEW_MAX_H)
    wrapper:SetClipsChildren(true)

    local scrollFrame = CreateFrame("ScrollFrame", nil, wrapper)
    scrollFrame:SetAllPoints()
    scrollFrame:SetScrollChild(popFrame)
    scrollFrame:EnableMouseWheel(true)

    local UpdatePVThumb = CludesUI.AttachSmoothScrollbar(scrollFrame, {
        step = 40,
        thumbMin = 20,
        trackParent = wrapper,
        topInset = 2,
        level = 5,
        panelWheel = true,
    })

    -- Store refs for height management after Update()
    popFrame._wrapper = wrapper
    popFrame._scrollFrame = scrollFrame
    popFrame._previewScale = previewScale
    popFrame._PREVIEW_MAX_H = PREVIEW_MAX_H
    popFrame._updatePVThumb = UpdatePVThumb

    local function Snap(val) return CludesUI.PP.SnapForES(val, popFrame:GetEffectiveScale()) end

    -- Snap to whole physical pixels at the preview's effective scale (same
    -- approach as the border system).
    local function SnapS(val)
        local es = popFrame:GetEffectiveScale()
        return CludesUI.PP.SnapForES(val, es)
    end

    -- Disable WoW's automatic pixel snapping on a texture
    local UnsnapTex = CludesUI.PP.DisablePixelSnap

    -- Pre-create all 12 per-button sub-frames/textures; show/hide by
    -- numButtonsShowable --------------------------------------------------
    local buttons = {}
    local DEFAULT_FONT = (CludesUI.GetFontPath("actionBars"))
        or "Interface\\AddOns\\CludesUI\\media\\fonts\\Expressway.TTF"

    for i = 1, maxBtns do
        local bf = CreateFrame("Frame", nil, popFrame)
        bf:SetSize(baseBtnW, baseBtnH)
        bf:Hide()

        local icon = bf:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetColorTexture(0.062, 0.070, 0.082, 1)

        local bT = bf:CreateTexture(nil, "OVERLAY")
        local bB = bf:CreateTexture(nil, "OVERLAY")
        local bL = bf:CreateTexture(nil, "OVERLAY")
        local bR = bf:CreateTexture(nil, "OVERLAY")
        UnsnapTex(bT)
        UnsnapTex(bB)
        UnsnapTex(bL)
        UnsnapTex(bR)
        bT:Hide()
        bB:Hide()
        bL:Hide()
        bR:Hide()

        -- Keybind text (top-right, mirrors real button HotKey position)
        local keybindFS = bf:CreateFontString(nil, "OVERLAY")
        CludesUI.ApplyIconTextFont(keybindFS, DEFAULT_FONT, 12, "actionBars")
        keybindFS:SetTextColor(1, 1, 1)
        keybindFS:SetPoint("TOPRIGHT", bf, "TOPRIGHT", -1, -3)
        keybindFS:SetPoint("TOPLEFT", bf, "TOPLEFT", 4, -3)
        keybindFS:SetJustifyH("RIGHT")
        keybindFS:SetWordWrap(false)
        keybindFS:SetText("")

        -- Count / charges text (bottom-right, mirrors real button Count position)
        local countFS = bf:CreateFontString(nil, "OVERLAY")
        CludesUI.ApplyIconTextFont(countFS, DEFAULT_FONT, 12, "actionBars")
        countFS:SetTextColor(1, 1, 1)
        countFS:SetPoint("BOTTOMRIGHT", bf, "BOTTOMRIGHT", -1, 4)
        countFS:SetText("")

        -- Macro name text (bottom-center, mirrors real button Name position)
        local macroFS = bf:CreateFontString(nil, "OVERLAY")
        CludesUI.PrimeFontShadow(macroFS, false)
        macroFS:SetFont(DEFAULT_FONT, 12, (CludesUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG")
        macroFS:SetTextColor(1, 1, 1)
        macroFS:SetPoint("BOTTOMLEFT", bf, "BOTTOMLEFT", 1, 4)
        macroFS:SetPoint("BOTTOMRIGHT", bf, "BOTTOMRIGHT", -1, 4)
        macroFS:SetJustifyH("CENTER")
        macroFS:SetWordWrap(false)
        macroFS:SetText("")

        buttons[i] = {
            frame = bf,
            icon = icon,
            borders = { bT, bB, bL, bR },
            keybind = keybindFS,
            count = countFS,
            macro = macroFS,
        }
    end

    -- Stock styles: the stock button art on a preview button, laid out as
    -- the live buttons lay it (they keep Blizzard's own textures, scaled
    -- with the button). Blizzard Style: the rounded icon-frame mask centred
    -- on the icon and the icon-frame ring at its stock 46x45-on-45 ratio.
    -- Classic WoW UI: the vanilla slot ring at 66/36 of the button
    -- (CENTER 0,-1/36), the empty-slot art on an empty slot, no mask. No
    -- CUI border, shape or backdrop either way. Built once per button,
    -- re-sized per pass; the kit not in use steps aside.
    local blizzMaskInfo
    local function ApplyBlizzPreviewButton(record, bf, icon, classic, filled)
        local bT, bB, bL, bR = record.borders[1], record.borders[2], record.borders[3], record.borders[4]
        bT:Hide()
        bB:Hide()
        bL:Hide()
        bR:Hide()
        if record._bdPreview then record._bdPreview:Hide() end
        if record.shapeBorderTex then record.shapeBorderTex:Hide() end
        if record.shapeMask and record._prevMasked then
            pcall(icon.RemoveMaskTexture, icon, record.shapeMask)
            record.shapeMask:Hide()
            record._prevMasked = false
        end
        icon:ClearAllPoints()
        icon:SetAllPoints(bf)
        local wid, height = bf:GetSize()
        if classic then
            if record.blizzMask then record.blizzMask:Hide() end
            if record.blizzRing then record.blizzRing:Hide() end
            local cring = record.classicRing
            if not cring then
                cring = bf:CreateTexture(nil, "ARTWORK", nil, 2)
                UnsnapTex(cring)
                record.classicRing = cring
            end
            local art = mod.AB_CLASSIC
            cring:SetTexture(filled and art.slot or art.empty)
            cring:SetTexCoord(0, 1, 0, 1)
            cring:ClearAllPoints()
            cring:SetPoint("CENTER", bf, "CENTER", 0, -height / 36)
            cring:SetSize(66 * wid / 36, 66 * height / 36)
            cring:Show()
            return
        end
        if record.classicRing then record.classicRing:Hide() end
        local mask = record.blizzMask
        if not mask then
            mask = bf:CreateMaskTexture()
            mask:SetAtlas("UI-HUD-ActionBar-IconFrame-Mask")
            icon:AddMaskTexture(mask)
            record.blizzMask = mask
            -- Above the icon, below the OVERLAY texts (a NormalTexture on
            -- the live button sits under its font strings the same way).
            local ring = bf:CreateTexture(nil, "ARTWORK", nil, 2)
            mod.AB_StockAtlas(ring, "UI-HUD-ActionBar-IconFrame")
            UnsnapTex(ring)
            record.blizzRing = ring
        end
        if blizzMaskInfo == nil then
            blizzMaskInfo = C_Texture.GetAtlasInfo("UI-HUD-ActionBar-IconFrame-Mask") or false
        end
        local sx, sy = wid / 45, height / 45
        mask:ClearAllPoints()
        mask:SetPoint("CENTER", icon, "CENTER", 0, 0)
        if blizzMaskInfo then
            mask:SetSize(blizzMaskInfo.width * sx, blizzMaskInfo.height * sy)
        else
            mask:SetSize(wid, height)
        end
        mask:Show()
        local ring = record.blizzRing
        ring:ClearAllPoints()
        ring:SetPoint("TOPLEFT", bf, "TOPLEFT", 0, 0)
        ring:SetSize(46 * sx, 45 * sy)
        ring:Show()
    end

    -- Preview background texture (behind all buttons)
    local previewBG = popFrame:CreateTexture(nil, "BACKGROUND", nil, -1)
    local previewBGBorder = CreateFrame("Frame", nil, popFrame, "BackdropTemplate")
    previewBGBorder:EnableMouse(false)
    previewBG:Hide()

    -- Store barFrame ref and base size for Update
    popFrame._barFrame = barFrame
    popFrame._baseBtnW = baseBtnW
    popFrame._baseBtnH = baseBtnH
    popFrame._barInfo = barInfo
    popFrame._blizzEditScale = blizzEditScale
    popFrame._buttons = buttons
    popFrame._previewBG = previewBG

    -- The Update method reads current DB + Blizzard state, applies it --
    popFrame.Update = function(self)
        local prefs = SB()
        if not prefs then return end

        local details = self._barInfo
        local bar = self._barFrame
        local btnW = self._baseBtnW
        local btnH = self._baseBtnH

        -- Override with user-set button size from DB
        if prefs.buttonWidth and prefs.buttonWidth > 0 then btnW = prefs.buttonWidth end
        if prefs.buttonHeight and prefs.buttonHeight > 0 then btnH = prefs.buttonHeight end

        -- How many buttons are visible (from our DB settings)
        local numVisible = prefs.overrideNumIcons or prefs.numIcons or details.count
        if numVisible < 1 then numVisible = details.count end

        -- Stance bar: ignore icon count setting, use actual shapeshift form count
        if details.isStance then
            numVisible = GetNumShapeshiftForms() or details.count
            if numVisible < 1 then numVisible = details.count end
        end

        -- Multi-row layout: show all rows matching the real bar
        local numRows = prefs.numRows or 1
        local ovRows = prefs.overrideNumRows
        if ovRows and ovRows > 0 then numRows = ovRows end
        local stride = math.ceil(numVisible / numRows)
        numRows = math.ceil(numVisible / stride)
        local previewCount = numVisible
        -- Preview always shows all slots regardless of alwaysShowButtons setting
        local showEmpty = true

        local leftmost = 1
        local spacing = prefs.buttonPadding or 2
        local resolvedBrdSize, resolvedBrdPx = mod.ResolveBorderThickness(prefs)
        local brdOn = resolvedBrdSize > 0
        local brdSize = resolvedBrdSize
        local brdPx = resolvedBrdPx -- the exact size the live buttons resolve (nil = legacy)
        local brdColor = prefs.borderColor or { r = 0, g = 0, b = 0, a = 1 }
        local brdClassColor = prefs.borderClassColor
        local zoom = (prefs.iconZoom or ABAR.db.profile.iconZoom or 5.5) / 100
        local square = ABAR.db.profile.squareIcons
        -- Stock styles: stock button art (see ApplyBlizzPreviewButton);
        -- shapes, zoom and CUI borders do not apply, as on the live bars.
        local abStyle = CludesUI.BlizzStyle.Active("actionbars")
        local blizzAB = abStyle ~= "cui"
        local classicAB = abStyle == "classic"
        local hideKB = prefs.hideKeybind

        -- Font path (global setting)
        local fontFile = (CludesUI.GetFontPath("actionBars")) or DEFAULT_FONT

        local kbSize = prefs.keybindFontSize or 12
        local kbColor = prefs.keybindFontColor or { r = 1, g = 1, b = 1 }
        local ctSize = prefs.countFontSize or 12
        local ctColor = prefs.countFontColor or { r = 1, g = 1, b = 1 }
        local hideMacro = prefs.hideMacroText
        local mcSize = prefs.macroFontSize or 12
        local mcColor = prefs.macroFontColor or { r = 1, g = 1, b = 1 }

        -- Shape settings: derive from unified border system
        local btnShape = prefs.buttonShape or "none"
        local shapeBrdOn = resolvedBrdSize > 0
        local shapeBrdColor = prefs.shapeBorderColor or prefs.borderColor or { r = 0, g = 0, b = 0, a = 1 }
        local shapeBrdSize = resolvedBrdSize
        local shapeBrdOpacity = (prefs.shapeBorderOpacity or 100) / 100
        local shapeBrdR, shapeBrdG, shapeBrdB, shapeBrdA =
            shapeBrdColor.r, shapeBrdColor.g, shapeBrdColor.b, (shapeBrdColor.a or 1) * shapeBrdOpacity
        -- Unified class color
        local useClassColor = brdClassColor
        if useClassColor == nil then useClassColor = prefs.shapeBorderClassColor end
        if useClassColor then
            local _, classTok = UnitClass("player")
            if classTok then
                local classColor = RAID_CLASS_COLORS[classTok]
                if classColor then
                    shapeBrdR, shapeBrdG, shapeBrdB = classColor.r, classColor.g, classColor.b
                end
            end
        end

        local scaledBtnW = SnapS(btnW * (self._blizzEditScale or 1))
        local scaledBtnH = SnapS(btnH * (self._blizzEditScale or 1))
        -- Expand button size for custom shapes (mirrors SHAPE_BTN_EXPAND in main file)
        if not blizzAB and btnShape ~= "none" and btnShape ~= "cropped" then
            local shapeExp = SnapS(mod.SHAPE_BTN_EXPAND * (self._blizzEditScale or 1))
            scaledBtnW = scaledBtnW + shapeExp
            scaledBtnH = scaledBtnH + shapeExp
        end
        -- Shrink button height for "cropped" mode (10% top + 10% bottom)
        if not blizzAB and btnShape == "cropped" then scaledBtnH = SnapS(scaledBtnH * 0.80) end

        local scaledPad = SnapS(spacing * (self._blizzEditScale or 1))

        local isVertical = (prefs.orientation or "horizontal") == "vertical"

        local totalScale = (self._blizzEditScale or 1)
        local scaledKBSize = math.max(6, floor(kbSize * totalScale + 0.5))
        local scaledCTSize = math.max(6, floor(ctSize * totalScale + 0.5))
        local scaledMCSize = math.max(6, floor(mcSize * totalScale + 0.5))

        -- Multi-row grid: vertical swaps cols/rows, uses actual column count (numRows may not fully fill).
        local gridCols, gridRows
        if isVertical then
            gridCols = math.ceil(numVisible / stride)
            gridRows = stride
        else
            gridCols = stride
            gridRows = numRows
        end
        local gridW = gridCols * scaledBtnW + (gridCols - 1) * scaledPad
        local gridH = gridRows * scaledBtnH + (gridRows - 1) * scaledPad
        -- Paging Arrows (Action Bar 1), sized as the live ones
        -- (ns.AB_PagingArrowMetrics): beside a horizontal bar (grid and arrows
        -- centred as one), above or below a vertical one.
        local pgArrow, pgText, pgGap, pgOff, pgRight
        if details.key == "MainBar" and prefs.showPagingArrows then
            pgArrow, pgText, pgGap, pgOff = mod.AB_PagingArrowMetrics(btnH)
            pgRight = prefs.pagingArrowsRight and true or false
        end
        local pgSide = (pgArrow and not isVertical) and (pgArrow + pgOff) or 0
        local gridStartX =
            Snap(math.max(0, (self:GetWidth() - gridW - pgSide) / 2) + (pgRight and 0 or pgSide))

        -- Inset for background growth above/below the grid (ScrollFrame clips its child; without it the top border is lost).
        local bgTopInset, bgBottomInset = 0, 0
        if prefs.bgEnabled then
            local rawBgPadding = prefs.bgPadding
            local bgSpacing = Snap((rawBgPadding ~= nil and rawBgPadding or (prefs.bgPadY or 0)) * totalScale)
            local bgMultiplierY = math.max(1, math.min(4, math.floor((prefs.bgMultiplierY or 1) + 0.5)))
            local bgIconPadding = Snap((prefs.buttonPadding or 0) * totalScale)
            local bgGrowY = (bgMultiplierY - 1) * (gridH + bgIconPadding)
            if (prefs.bgExpandDirectionY or "up") == "down" then
                bgBottomInset = bgSpacing + bgGrowY
            else
                bgTopInset = bgSpacing + bgGrowY
            end
        end
        -- The bar's chrome (painted after the buttons): WoW Forever's
        -- frame and dividers and the bar's end caps (horizontal only),
        -- with room above and below the grid for them.
        local fvPrev = mod.AB_ForeverBg(details.key)
        local capsPrev, capsL, capsR
        if not isVertical then
            capsPrev, capsL, capsR = mod.AB_CapsLook(details.key)
        end
        if fvPrev or capsPrev then
            local reachT, reachB =
                mod.AB_ChromeReach(scaledBtnW, gridH, fvPrev, capsPrev, gridRows > 1, totalScale, details.key)
            bgTopInset = math.max(bgTopInset, Snap(reachT - 10))
            bgBottomInset = math.max(bgBottomInset, Snap(reachB - 10))
        end
        -- Room for the paging arrows past the grid's 10px margins.
        if pgArrow then
            if isVertical then
                local need = Snap(pgArrow + pgOff - 10)
                if pgRight then
                    bgBottomInset = math.max(bgBottomInset, need)
                else
                    bgTopInset = math.max(bgTopInset, need)
                end
            else
                local need = Snap((pgArrow * 2 + pgText + pgGap * 2 - gridH) / 2 - 10)
                bgTopInset = math.max(bgTopInset, need)
                bgBottomInset = math.max(bgBottomInset, need)
            end
        end

        local frameH = Snap(gridH + 20 + bgTopInset + bgBottomInset)
        self:SetHeight(frameH)

        -- Resize wrapper to min(content, max) and toggle scrollbar
        local parentH = frameH * self._previewScale
        local maxH = self._PREVIEW_MAX_H
        if parentH > maxH then
            -- Bottom padding so the last row is fully visible when scrolled down
            local paddedH = Snap(gridH + 20 + bgTopInset + bgBottomInset + scaledBtnH)
            self:SetHeight(paddedH)
            -- Snap the viewport to a whole number of rows so the cap never slices
            -- a row in half; topInset is the space above row 1 (matches gridStartY).
            local topInset = Snap(10) + bgTopInset
            local rowStep = scaledBtnH + scaledPad
            local visibleRows =
                math.max(1, math.floor((maxH / self._previewScale - topInset + scaledPad) / rowStep + 0.001))
            visibleRows = math.min(visibleRows, gridRows)
            local cappedLocalH = Snap(topInset + visibleRows * scaledBtnH + (visibleRows - 1) * scaledPad)
            self._wrapper:SetHeight(math.min(maxH, cappedLocalH * self._previewScale))
        else
            self._wrapper:SetHeight(parentH)
            -- Reset scroll when content fits without scrolling
            if self._scrollFrame then self._scrollFrame:SetVerticalScroll(0) end
        end
        if self._updatePVThumb then self._updatePVThumb() end

        -- Store grid bounds for background anchoring
        self._gridStartX = gridStartX
        self._gridStartY = -Snap(10) - bgTopInset
        self._gridW = gridW
        self._gridH = gridH

        local startY = self._gridStartY
        -- growUp covers "up" OR "center": horizontal bars only store left/right/center, so a plain == "up" check never fires.
        local _gd = prefs.growDirection or "up"
        local growUp = (_gd == "up" or _gd == "center")
        local colFlip, rowFlip, cornerFill = mod.GetOrderFlips(prefs, isVertical, growUp)
        for i = 1, maxBtns do
            local record = buttons[i]
            local bf = record.frame
            local icon = record.icon

            if i >= leftmost and i <= previewCount then
                local position = i - leftmost -- 0-based index
                local col, row
                if isVertical then
                    if cornerFill then
                        -- Corner modes fill across columns (gridCols) first, then wrap down.
                        col = position % gridCols
                        row = math.floor(position / gridCols)
                    else
                        col = math.floor(position / stride)
                        row = position % stride
                    end
                else
                    col = position % stride
                    row = math.floor(position / stride)
                end
                -- dispCol/dispRow = visual position after order flips; col stays the content
                -- column so vertical-centering math below still measures the right buttons.
                local dispCol, dispRow = col, row
                if isVertical then
                    if colFlip then dispCol = gridCols - 1 - dispCol end
                    if rowFlip then dispRow = stride - 1 - dispRow end
                else
                    if colFlip then dispCol = stride - 1 - dispCol end
                    if rowFlip then dispRow = numRows - 1 - dispRow end
                end

                local xOff, yOff
                if isVertical then
                    -- Vertical: center each column vertically when last column is shorter
                    local countInCol
                    if cornerFill then
                        -- Row-major fill: column c holds every gridCols-th button.
                        countInCol = math.floor((previewCount - 1 - col) / gridCols) + 1
                    else
                        local colStart = col * stride + 1
                        local colEnd = math.min(colStart + stride - 1, previewCount)
                        countInCol = colEnd - colStart + 1
                    end
                    local colH = countInCol * scaledBtnH + (countInCol - 1) * scaledPad
                    local colOffY = Snap((gridH - colH) / 2)
                    xOff = Snap(gridStartX + dispCol * (scaledBtnW + scaledPad))
                    yOff = startY - colOffY - Snap(dispRow * (scaledBtnH + scaledPad))
                else
                    -- Horizontal: left-align rows to match actual bar layout
                    xOff = Snap(gridStartX + dispCol * (scaledBtnW + scaledPad))
                    local displayRow = growUp and ((numRows - 1) - dispRow) or dispRow
                    yOff = startY - Snap(displayRow * (scaledBtnH + scaledPad))
                end
                bf:SetSize(scaledBtnW, scaledBtnH)
                bf:ClearAllPoints()
                bf:SetPoint("TOPLEFT", self, "TOPLEFT", xOff, yOff)
                bf:Show()

                -- Icon texture from our EABButton (not the hidden Blizzard button)
                local eabBtns = mod.barButtons and mod.barButtons[details.key]
                local realBtn = (eabBtns and eabBtns[i])
                    or (details.buttonPrefix and _G[details.buttonPrefix .. i])
                local hasAction = realBtn and mod.ButtonHasAction(realBtn, details.buttonPrefix)
                local iconTex = hasAction and realBtn.icon and realBtn.icon:GetTexture()

                -- Always Show Buttons: when off, hide empty slots entirely
                if not hasAction and not showEmpty then
                    bf:Hide()
                else
                    if not iconTex then
                        icon:SetColorTexture(0, 0, 0, 0.5)
                        UnsnapTex(icon)
                        icon:SetTexCoord(0, 1, 0, 1)
                    else
                        icon:SetTexture(iconTex)
                        if not blizzAB and (square or zoom > 0 or btnShape == "cropped") then
                            local z = zoom
                            if btnShape == "cropped" then
                                -- Preserve aspect ratio: trim top/bottom by 10%
                                icon:SetTexCoord(z, 1 - z, z + 0.10, 1 - z - 0.10)
                            else
                                icon:SetTexCoord(z, 1 - z, z, 1 - z)
                            end
                        else
                            icon:SetTexCoord(0, 1, 0, 1)
                        end
                    end

                    if blizzAB then
                        ApplyBlizzPreviewButton(record, bf, icon, classicAB, iconTex and true or false)
                    else
                        -- The styles' rings and mask step aside on the CUI look (the
                        -- flag is a live read: a profile switch can flip it mid-page).
                        if record.blizzRing then record.blizzRing:Hide() end
                        if record.blizzMask then record.blizzMask:Hide() end
                        if record.classicRing then record.classicRing:Hide() end
                        local bT, bB, bL, bR =
                            record.borders[1], record.borders[2], record.borders[3], record.borders[4]
                        local brdTexKey = prefs.borderTexture or "solid"
                        local brdIsSolid = (brdTexKey == "solid")

                        if brdOn and brdIsSolid then
                            -- Solid: 4 texture strips
                            local cr, cg, checkBtn, ca = brdColor.r, brdColor.g, brdColor.b, brdColor.a
                            if useClassColor then
                                local _, ct2 = UnitClass("player")
                                if ct2 then
                                    local cc2 = RAID_CLASS_COLORS[ct2]
                                    if cc2 then
                                        cr, cg, checkBtn = cc2.r, cc2.g, cc2.b
                                    end
                                end
                            end
                            -- The pixels the live strips draw (SnapBorderTextures): the exact size
                            -- when set, else the step, as whole pixels at this button's scale.
                            local onePx = CludesUI.PP.perfect / bf:GetEffectiveScale()
                            local sz = math.max(onePx, math.floor((brdPx or brdSize) + 0.5) * onePx)

                            bT:SetColorTexture(cr, cg, checkBtn, ca)
                            UnsnapTex(bT)
                            bT:SetHeight(sz)
                            bT:ClearAllPoints()
                            Pix.Point(bT, "TOPLEFT", bf, "TOPLEFT", 0, 0)
                            Pix.Point(bT, "TOPRIGHT", bf, "TOPRIGHT", 0, 0)
                            bT:Show()

                            bB:SetColorTexture(cr, cg, checkBtn, ca)
                            UnsnapTex(bB)
                            bB:SetHeight(sz)
                            bB:ClearAllPoints()
                            Pix.Point(bB, "BOTTOMLEFT", bf, "BOTTOMLEFT", 0, 0)
                            Pix.Point(bB, "BOTTOMRIGHT", bf, "BOTTOMRIGHT", 0, 0)
                            bB:Show()

                            bL:SetColorTexture(cr, cg, checkBtn, ca)
                            UnsnapTex(bL)
                            bL:SetWidth(sz)
                            bL:ClearAllPoints()
                            Pix.Point(bL, "TOPLEFT", bT, "BOTTOMLEFT", 0, 0)
                            Pix.Point(bL, "BOTTOMLEFT", bB, "TOPLEFT", 0, 0)
                            bL:Show()

                            bR:SetColorTexture(cr, cg, checkBtn, ca)
                            UnsnapTex(bR)
                            bR:SetWidth(sz)
                            bR:ClearAllPoints()
                            Pix.Point(bR, "TOPRIGHT", bT, "BOTTOMRIGHT", 0, 0)
                            Pix.Point(bR, "BOTTOMRIGHT", bB, "TOPRIGHT", 0, 0)
                            bR:Show()

                            if record._bdPreview then record._bdPreview:Hide() end
                        elseif brdOn and not brdIsSolid then
                            -- Textured: BackdropTemplate on preview button
                            bT:Hide()
                            bB:Hide()
                            bL:Hide()
                            bR:Hide()
                            if not record._bdPreview then
                                record._bdPreview = CreateFrame("Frame", nil, bf, "BackdropTemplate")
                                record._bdPreview:EnableMouse(false)
                            end
                            local bdPv = record._bdPreview
                            -- The live edge (ApplyBorderStyle) in this frame's units: the exact
                            -- size as whole pixels at UIParent scale, else the step's edge. ratio
                            -- cancels any scale between the preview button and UIParent so the
                            -- edge is the game's size (1 today: the preview runs at UIParent scale).
                            local gamePP = CludesUI.PP
                            local EDGE_MAP = CludesUI.BORDER_EDGE_MAP
                            local uiES = UIParent:GetEffectiveScale()
                            local pvES = bf:GetEffectiveScale()
                            local ratio = (pvES > 0.01 and uiES > 0) and (uiES / pvES) or 1
                            local edgeSize
                            if brdPx then
                                edgeSize = math.max(1, math.floor(brdPx + 0.5)) * gamePP.mult * ratio
                            else
                                edgeSize = (EDGE_MAP[brdSize] or EDGE_MAP[1]) * ratio
                            end
                            local thKey = prefs.borderThickness or "thin"
                            local dox, doy, dsx, dsy =
                                CludesUI.GetBorderDefaults("actionbars", brdTexKey, thKey)
                            if brdPx then
                                -- The step's defaults follow the exact edge (the user's own offsets stay).
                                local f = (brdPx * gamePP.mult) / (EDGE_MAP[brdSize] or EDGE_MAP[1])
                                dox, doy, dsx, dsy =
                                    gamePP.Snap(dox * f),
                                    gamePP.Snap(doy * f),
                                    gamePP.Snap(dsx * f),
                                    gamePP.Snap(dsy * f)
                            end
                            local adjX = (prefs.borderTextureOffset or dox) * ratio
                            local adjY = (prefs.borderTextureOffsetY or doy) * ratio
                            -- Whole pixels at the preview's own scale, as ApplyBorderStyle snaps the live anchors.
                            local snapES = (pvES > 0.01) and pvES or uiES
                            local offX, offY
                            if CludesUI.BorderTextureUsesScaleOffset(brdTexKey) then
                                local half = CludesUI.BorderHalfEdge(brdTexKey, edgeSize, snapES)
                                offX = half + adjX
                                offY = half + adjY
                            else
                                offX = adjX
                                offY = adjY
                            end
                            local sx = (prefs.borderTextureShiftX or dsx) * ratio
                            local sy = (prefs.borderTextureShiftY or dsy) * ratio
                            offX, offY = gamePP.SnapForES(offX, snapES), gamePP.SnapForES(offY, snapES)
                            sx, sy = gamePP.SnapForES(sx, snapES), gamePP.SnapForES(sy, snapES)
                            bdPv:ClearAllPoints()
                            bdPv:SetPoint("TOPLEFT", bf, "TOPLEFT", -offX + sx, offY + sy)
                            bdPv:SetPoint("BOTTOMRIGHT", bf, "BOTTOMRIGHT", offX + sx, -offY + sy)
                            if prefs.borderBehind then
                                bdPv:SetFrameLevel(math.max(0, bf:GetFrameLevel() - 1))
                            else
                                bdPv:SetFrameLevel(bf:GetFrameLevel() + 2)
                            end
                            local texPath = CludesUI.ResolveBorderTexture(brdTexKey)
                            if texPath then
                                bdPv:SetBackdrop({
                                    edgeFile = texPath,
                                    edgeSize = edgeSize,
                                    insets = { left = 0, right = 0, top = 0, bottom = 0 },
                                })
                                local cr, cg, checkBtn, ca =
                                    brdColor.r, brdColor.g, brdColor.b, brdColor.a or 1
                                if useClassColor then
                                    local _, ct2 = UnitClass("player")
                                    if ct2 then
                                        local cc2 = RAID_CLASS_COLORS[ct2]
                                        if cc2 then
                                            cr, cg, checkBtn = cc2.r, cc2.g, cc2.b
                                        end
                                    end
                                end
                                bdPv:SetBackdropBorderColor(cr, cg, checkBtn, ca)
                                bdPv:Show()
                            end
                        else
                            bT:Hide()
                            bB:Hide()
                            bL:Hide()
                            bR:Hide()
                            if record._bdPreview then record._bdPreview:Hide() end
                        end

                        -- Button Shape mask + border
                        local SHAPE_MASKS = mod.SHAPE_MASKS
                        local SHAPE_BORDERS = mod.SHAPE_BORDERS
                        if
                            btnShape ~= "none"
                            and btnShape ~= "cropped"
                            and SHAPE_MASKS
                            and SHAPE_MASKS[btnShape]
                        then
                            if not record.shapeMask then
                                record.shapeMask = bf:CreateMaskTexture()
                                record.shapeMask:SetAllPoints(bf)
                            end
                            record.shapeMask:SetTexture(
                                SHAPE_MASKS[btnShape],
                                "CLAMPTOBLACKADDITIVE",
                                "CLAMPTOBLACKADDITIVE"
                            )
                            record.shapeMask:Show()
                            if record._prevMasked then
                                pcall(icon.RemoveMaskTexture, icon, record.shapeMask)
                            end
                            icon:AddMaskTexture(record.shapeMask)
                            record._prevMasked = true
                            -- Expand icon beyond bf for SHAPE_ICON_EXPAND (icon only, NOT mask)
                            local SHAPE_ICON_EXPAND_OFFSETS = {
                                circle = 2,
                                csquare = 4,
                                diamond = 2,
                                hexagon = 4,
                                portrait = 2,
                                shield = 2,
                                square = 4,
                            }
                            local shapeOffset = SHAPE_ICON_EXPAND_OFFSETS[btnShape] or 0
                            local shapeDefault = (
                                mod.SHAPE_ZOOM_DEFAULTS and mod.SHAPE_ZOOM_DEFAULTS[btnShape] or 6.0
                            ) / 100
                            local iconExp = mod.SHAPE_ICON_EXPAND + shapeOffset + (zoom - shapeDefault) * 200
                            if iconExp < 0 then iconExp = 0 end
                            local halfIE = iconExp / 2
                            icon:ClearAllPoints()
                            Pix.Point(icon, "TOPLEFT", bf, "TOPLEFT", -halfIE, halfIE)
                            Pix.Point(icon, "BOTTOMRIGHT", bf, "BOTTOMRIGHT", halfIE, -halfIE)
                            -- Mask: inset 1px when border is on (matches unit frames)
                            record.shapeMask:ClearAllPoints()
                            if shapeBrdSize >= 1 then
                                Pix.Point(record.shapeMask, "TOPLEFT", bf, "TOPLEFT", 1, -1)
                                Pix.Point(record.shapeMask, "BOTTOMRIGHT", bf, "BOTTOMRIGHT", -1, 1)
                            else
                                record.shapeMask:SetAllPoints(bf)
                            end
                            -- Expand texcoords to fill mask opening
                            local SHAPE_INSETS = CludesUI.SHAPE_INSETS
                            local insetPx = SHAPE_INSETS[btnShape] or 17
                            local visRatio = (128 - 2 * insetPx) / 128
                            local expand = ((1 / visRatio) - 1) * 0.5
                            icon:SetTexCoord(-expand, 1 + expand, -expand, 1 + expand)
                            bT:Hide()
                            bB:Hide()
                            bL:Hide()
                            bR:Hide()
                            if not record.shapeBorderTex then
                                record.shapeBorderTex = bf:CreateTexture(nil, "OVERLAY", nil, 6)
                            end
                            -- No mask on border: render at button frame size
                            pcall(
                                record.shapeBorderTex.RemoveMaskTexture,
                                record.shapeBorderTex,
                                record.shapeMask
                            )
                            record.shapeBorderTex:ClearAllPoints()
                            record.shapeBorderTex:SetAllPoints(bf)
                            if shapeBrdOn and SHAPE_BORDERS[btnShape] then
                                record.shapeBorderTex:SetTexture(SHAPE_BORDERS[btnShape])
                                record.shapeBorderTex:SetVertexColor(
                                    shapeBrdR,
                                    shapeBrdG,
                                    shapeBrdB,
                                    shapeBrdA
                                )
                                record.shapeBorderTex:Show()
                            else
                                record.shapeBorderTex:Hide()
                            end
                        else
                            -- None/Cropped: remove mask if previously applied
                            if record.shapeMask and record._prevMasked then
                                pcall(icon.RemoveMaskTexture, icon, record.shapeMask)
                                record.shapeMask:Hide()
                                record._prevMasked = false
                            end
                            if record.shapeBorderTex then record.shapeBorderTex:Hide() end
                            icon:ClearAllPoints()
                            icon:SetAllPoints(bf)
                            -- Texcoords: cropped trims top/bottom, none uses zoom only
                            if icon.SetTexCoord then
                                local z = zoom
                                if btnShape == "cropped" then
                                    icon:SetTexCoord(z, 1 - z, z + 0.10, 1 - z - 0.10)
                                else
                                    if z > 0 or square then
                                        icon:SetTexCoord(z, 1 - z, z, 1 - z)
                                    else
                                        icon:SetTexCoord(0, 1, 0, 1)
                                    end
                                end
                            end
                        end
                    end -- close Blizzard Style / CUI look split
                    local keybindFS = record.keybind
                    if hideKB then
                        keybindFS:SetText("")
                    else
                        local hkText = ""
                        if realBtn and realBtn.HotKey then
                            hkText = realBtn.HotKey:GetText() or ""
                            if hkText == RANGE_INDICATOR or hkText == "\226\128\162" then hkText = "" end
                        end
                        keybindFS:SetText(hkText)
                    end
                    CludesUI.ApplyIconTextFont(keybindFS, fontFile, scaledKBSize, "actionBars")
                    keybindFS:SetTextColor(kbColor.r, kbColor.g, kbColor.b)
                    local kbOX = (prefs.keybindOffsetX or 0) * totalScale
                    local kbOY = (prefs.keybindOffsetY or 0) * totalScale
                    if
                        not (
                            prefs.keybindAnchor
                            and ABAR.PlaceButtonText(keybindFS, bf, prefs.keybindAnchor, kbOX, kbOY)
                        )
                    then
                        keybindFS:ClearAllPoints()
                        keybindFS:SetPoint("TOPRIGHT", bf, "TOPRIGHT", -1 + kbOX, -3 + kbOY)
                        keybindFS:SetPoint("TOPLEFT", bf, "TOPLEFT", 4 + kbOX, -3 + kbOY)
                        keybindFS:SetJustifyH("RIGHT")
                    end

                    local countFS = record.count
                    do
                        local ctText = ""
                        if realBtn and realBtn.Count then ctText = realBtn.Count:GetText() or "" end
                        countFS:SetText(ctText)
                        -- Charge Numbers: while the bar hides a kind of count, the
                        -- sample takes the live count's alpha, which the runtime
                        -- sets by the count's kind (passed through as it reads,
                        -- never compared); otherwise it shows in full.
                        if
                            realBtn
                            and realBtn.Count
                            and (prefs.hideChargeCount or prefs.hideStackCount or prefs.hideItemCount)
                        then
                            countFS:SetAlpha(realBtn.Count:GetAlpha())
                        else
                            countFS:SetAlpha(1)
                        end
                    end
                    CludesUI.ApplyIconTextFont(countFS, fontFile, scaledCTSize, "actionBars")
                    countFS:SetTextColor(ctColor.r, ctColor.g, ctColor.b)
                    local ctOX = (prefs.countOffsetX or 0) * totalScale
                    local ctOY = (prefs.countOffsetY or 0) * totalScale
                    if
                        not (
                            prefs.countAnchor
                            and ABAR.PlaceButtonText(countFS, bf, prefs.countAnchor, ctOX, ctOY)
                        )
                    then
                        countFS:ClearAllPoints()
                        countFS:SetPoint("BOTTOMRIGHT", bf, "BOTTOMRIGHT", -1 + ctOX, 4 + ctOY)
                        countFS:SetJustifyH("RIGHT")
                    end

                    local macroFS = record.macro
                    if macroFS then
                        if hideMacro then
                            macroFS:SetText("")
                        else
                            local mcText = ""
                            if realBtn and realBtn.Name then mcText = realBtn.Name:GetText() or "" end
                            macroFS:SetText(mcText)
                        end
                        CludesUI.PrimeFontShadow(macroFS, false)
                        macroFS:SetFont(
                            fontFile,
                            scaledMCSize,
                            (CludesUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG"
                        )
                        macroFS:SetTextColor(mcColor.r, mcColor.g, mcColor.b)
                        local mcOX = (prefs.macroOffsetX or 0) * totalScale
                        local mcOY = (prefs.macroOffsetY or 0) * totalScale
                        if
                            not (
                                prefs.macroAnchor
                                and ABAR.PlaceButtonText(macroFS, bf, prefs.macroAnchor, mcOX, mcOY)
                            )
                        then
                            macroFS:ClearAllPoints()
                            macroFS:SetPoint("BOTTOMLEFT", bf, "BOTTOMLEFT", 1 + mcOX, 4 + mcOY)
                            macroFS:SetPoint("BOTTOMRIGHT", bf, "BOTTOMRIGHT", -1 + mcOX, 4 + mcOY)
                            macroFS:SetJustifyH("CENTER")
                        end
                    end
                end -- close alwaysShowButtons else
            else
                bf:Hide()
            end
        end

        if fvPrev or capsPrev or self._abChrome then
            local abc = self._abChrome
            if not abc then
                abc = {}
                self._abChrome = abc
            end
            local oneLine = (isVertical and gridCols or gridRows) == 1 and spacing <= 2
            mod.AB_PaintBarChrome(
                abc,
                self,
                gridStartX,
                self._gridStartY,
                gridW,
                gridH,
                scaledBtnW,
                fvPrev,
                capsPrev,
                gridRows > 1,
                isVertical,
                oneLine and (isVertical and gridRows or gridCols) or 0,
                (isVertical and scaledBtnH or scaledBtnW) + scaledPad,
                0,
                0,
                totalScale,
                details.key,
                capsL,
                capsR
            )
        end

        -- The paging arrows' stand-in (built on first use): the live arrow art
        -- and page number, over the bar's chrome.
        local pg = self._pagingPreview
        if pgArrow then
            if not pg then
                pg = CreateFrame("Frame", nil, self)
                pg.up = pg:CreateTexture(nil, "ARTWORK")
                pg.up:SetAtlas("UI-HUD-ActionBar-PageUpArrow-Up")
                pg.down = pg:CreateTexture(nil, "ARTWORK")
                pg.down:SetAtlas("UI-HUD-ActionBar-PageDownArrow-Up")
                pg.text = pg:CreateFontString(nil, "OVERLAY")
                pg.text:SetTextColor(1, 1, 1, 0.9)
                self._pagingPreview = pg
            end
            pg:SetFrameLevel(self:GetFrameLevel() + 20)
            pg.text:SetFont(
                STANDARD_TEXT_FONT,
                pgText,
                (CludesUI.SlugFlag("OUTLINE, SLUG")) or "OUTLINE, SLUG"
            )
            pg.text:SetText(tostring(mod.EAB_VTABLE.GetActionBarPage() or 1))
            pg.up:SetSize(pgArrow, pgArrow)
            pg.down:SetSize(pgArrow, pgArrow)
            pg:ClearAllPoints()
            pg.up:ClearAllPoints()
            pg.down:ClearAllPoints()
            pg.text:ClearAllPoints()
            pg.text:SetPoint("CENTER", pg, "CENTER", 0, 0)
            if isVertical then
                pg:SetSize(pgArrow * 2 + pgText * 2 + pgGap * 2, pgArrow)
                local cx = Snap(gridStartX + gridW / 2)
                if pgRight then
                    pg:SetPoint("TOP", self, "TOPLEFT", cx, self._gridStartY - gridH - pgOff)
                else
                    pg:SetPoint("BOTTOM", self, "TOPLEFT", cx, self._gridStartY + pgOff)
                end
                pg.down:SetPoint("LEFT", pg, "LEFT", 0, 0)
                pg.up:SetPoint("RIGHT", pg, "RIGHT", 0, 0)
            else
                pg:SetSize(pgArrow, pgArrow * 2 + pgText + pgGap * 2)
                local cy = Snap(self._gridStartY - gridH / 2)
                if pgRight then
                    pg:SetPoint("LEFT", self, "TOPLEFT", gridStartX + gridW + pgOff, cy)
                else
                    pg:SetPoint("RIGHT", self, "TOPLEFT", gridStartX - pgOff, cy)
                end
                pg.up:SetPoint("TOP", pg, "TOP", 0, 0)
                pg.down:SetPoint("BOTTOM", pg, "BOTTOM", 0, 0)
            end
            pg:Show()
        elseif pg then
            pg:Hide()
        end

        if prefs.bgEnabled then
            local bgC = prefs.bgColor or { r = 0, g = 0, b = 0, a = 0.5 }
            local bgAlpha = prefs.bgOpacity ~= nil and prefs.bgOpacity / 100 or bgC.a
            previewBG:SetColorTexture(bgC.r, bgC.g, bgC.b, bgAlpha)
            local rawPadding = prefs.bgPadding
            local extraX = Snap((rawPadding ~= nil and rawPadding or (prefs.bgPadX or 0)) * totalScale)
            local extraY = Snap((rawPadding ~= nil and rawPadding or (prefs.bgPadY or 0)) * totalScale)
            -- Anchor to full grid bounds (not buttons) so multi-row backgrounds still cover a shorter last row.
            local gx = self._gridStartX or 0
            local gw = self._gridW or 0
            local gh = self._gridH or 0
            local gy = self._gridStartY or -Snap(10)
            previewBG:ClearAllPoints()
            local leftX, right = gx - extraX, gx + gw + extraX
            local topY, bottom = gy + extraY, gy - gh - extraY
            local multiplierX = math.max(1, math.min(4, math.floor((prefs.bgMultiplierX or 1) + 0.5)))
            local multiplierY = math.max(1, math.min(4, math.floor((prefs.bgMultiplierY or 1) + 0.5)))
            local directionX = prefs.bgExpandDirectionX or "right"
            local directionY = prefs.bgExpandDirectionY or "up"
            local iconPadding = Snap((prefs.buttonPadding or 0) * totalScale)
            local growX = (multiplierX - 1) * (gw + iconPadding)
            local growY = (multiplierY - 1) * (gh + iconPadding)
            if directionX == "left" then
                leftX = leftX - growX
            else
                right = right + growX
            end
            if directionY == "down" then
                bottom = bottom - growY
            else
                topY = topY + growY
            end
            previewBG:SetPoint("TOPLEFT", self, "TOPLEFT", leftX, topY)
            previewBG:SetPoint("BOTTOMRIGHT", self, "TOPLEFT", right, bottom)
            previewBG:Show()
            previewBGBorder:SetFrameLevel(
                prefs.bgBorderBehind and math.max(0, self:GetFrameLevel() - 1) or self:GetFrameLevel()
            )
            previewBGBorder:ClearAllPoints()
            previewBGBorder:SetAllPoints(previewBG)
            if CludesUI.ApplyBorderStyle then
                local bc = prefs.bgBorderColor or { r = 0, g = 0, b = 0, a = 1 }
                local thicknessKey = prefs.bgBorderThickness or "none"
                local thickness = mod.BORDER_THICKNESS and mod.BORDER_THICKNESS[thicknessKey]
                local borderSize = thickness and thickness.regular or 0
                local bgPx = CludesUI.BorderPx(prefs.bgBorderThicknessPx, borderSize, prefs.bgBorderTexture)
                CludesUI.ApplyBorderStyle(
                    previewBGBorder,
                    borderSize,
                    bc.r,
                    bc.g,
                    bc.b,
                    bc.a or 1,
                    prefs.bgBorderTexture or "solid",
                    prefs.bgBorderOffsetX,
                    prefs.bgBorderOffsetY,
                    prefs.bgBorderShiftX,
                    prefs.bgBorderShiftY,
                    "actionbars",
                    thicknessKey,
                    nil,
                    bgPx
                )
            end
        else
            previewBG:Hide()
            if CludesUI.ApplyBorderStyle then
                CludesUI.ApplyBorderStyle(previewBGBorder, 0, 0, 0, 0, prefs.bgBorderTexture or "solid")
            else
                previewBGBorder:Hide()
            end
        end

        -- Mouseover fade shows the real bar at full alpha on hover, so preview uses full alpha too, not the fade-out alpha.
        local barAlpha = prefs.mouseoverEnabled and 1 or (prefs.mouseoverAlpha or 1)
        self:SetAlpha(barAlpha)

        -- Refresh text overlay sizes (font/text may have changed)
        if self._textOverlays then
            for _, shade in ipairs(self._textOverlays) do
                if shade._resizeToText then shade._resizeToText() end
            end
        end
    end

    popFrame:Update()

    -- Return the actual computed height (converted to parent-space)
    optionState.activePreview = popFrame
    -- This module's own header preview slot: other modules' header previews
    -- stay alive beside it and never answer for it.
    CludesUI._abHeaderPreview = popFrame
    return popFrame._wrapper:GetHeight()
end

-- Used by CUI_ActionBars_Options.lua
mod.ABO_BuildLivePreview = BuildLivePreview
