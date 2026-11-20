if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_UnlockMode_Movers.lua
--  CreateMover: the draggable mover built for each registered element.
--  Loaded after CUI_UnlockMode.lua; _unlockCoreInit runs it once with UM.
-------------------------------------------------------------------------------
local _, CUI_NS = ...
CUI_NS = CUI_NS.__cuiCoreNS or CUI_NS -- standalone builds: the core's own table (CludesUI.lua)
CUI_NS.unlockParts = CUI_NS.unlockParts or {}
CUI_NS.unlockParts.Movers = function(LM)
    local mod, ABAR, floor, abs = CUI_NS, LM.EAB, LM.floor, LM.abs
    local min, max, round, DeferMoverSync = LM.min, LM.max, LM.round, LM.DeferMoverSync
    local FONT_PATH, MOVER_ALPHA, MOVER_HOVER, MOVER_DRAG =
        LM.FONT_PATH, LM.MOVER_ALPHA, LM.MOVER_HOVER, LM.MOVER_DRAG
    local BAR_LOOKUP, ALL_BAR_ORDER, GetVisibilityOnly, registeredElements =
        LM.BAR_LOOKUP, LM.ALL_BAR_ORDER, LM.GetVisibilityOnly, LM.registeredElements
    local registeredOrder, RebuildRegisteredOrder, handles, pendingPositions =
        LM.registeredOrder, LM.RebuildRegisteredOrder, LM.movers, LM.pendingPositions
    local GetBarGrowDir, GetAnchorDB, GetAnchorInfo, SetAnchorInfo =
        LM.GetBarGrowDir, LM.GetAnchorDB, LM.GetAnchorInfo, LM.SetAnchorInfo
    local ClearAnchorInfo, IsAnchored, MatchH, FadeOverlayForSelectElement =
        LM.ClearAnchorInfo, LM.IsAnchored, LM.MatchH, LM.FadeOverlayForSelectElement
    local CancelPickMode, FlashRedBorder, RejectH, ReapplyAllAnchors =
        LM.CancelPickMode, LM.FlashRedBorder, LM.RejectH, LM.ReapplyAllAnchors
    local LoadBarPosition, GetAccent, ClearSnapHighlight, ShowSnapHighlight =
        LM.LoadBarPosition, LM.GetAccent, LM.ClearSnapHighlight, LM.ShowSnapHighlight
    local HideAllGuidesAndHighlight, ShowAlignmentGuides, SnapPosition, SelectMover =
        LM.HideAllGuidesAndHighlight, LM.ShowAlignmentGuides, LM.SnapPosition, LM.SelectMover
    local DeselectMover, GetActionBarVisualSize, SortMoverFrameLevels =
        LM.DeselectMover, LM.GetActionBarVisualSize, LM.SortMoverFrameLevels

    local _mouseHeld = false -- true while left mouse button is held down anywhere

    local function OverlapUsesScroll(snapMethod)
        return snapMethod == "scroll"
            or snapMethod == "shiftscroll"
            or snapMethod == "controlscroll"
            or snapMethod == "altscroll"
    end

    local function OverlapModifierDown(snapMethod)
        if snapMethod == "scroll" then
            return true
        end
        if snapMethod == "shiftscroll" then
            return IsShiftKeyDown()
        end
        if snapMethod == "controlscroll" then
            return IsControlKeyDown()
        end
        if snapMethod == "altscroll" then
            return IsAltKeyDown()
        end
        return false
    end

    local function OverlapScrollDown()
        local snapMethod = CludesUI.GetUnlockOverlapMethod()
        return OverlapUsesScroll(snapMethod) and OverlapModifierDown(snapMethod)
    end

    function LM.UpdateMoverMouseWheel()
        local snapMethod = CludesUI.GetUnlockOverlapMethod()
        local active = LM.isUnlocked
            and LM.arrowKeyFrame
            and LM.arrowKeyFrame:IsShown()
            and OverlapUsesScroll(snapMethod)
        if LM.arrowKeyFrame then
            if active and snapMethod ~= "scroll" then
                LM.arrowKeyFrame:RegisterEvent("MODIFIER_STATE_CHANGED")
            else
                LM.arrowKeyFrame:UnregisterEvent("MODIFIER_STATE_CHANGED")
            end
        end
        local enabled = active and OverlapModifierDown(snapMethod) or false
        for _, m in pairs(handles) do
            m:EnableMouseWheel(enabled)
            if m._linkBtns then
                for _, button in ipairs(m._linkBtns) do
                    button:EnableMouseWheel(enabled)
                end
            end
            if m._cogBtn then
                m._cogBtn:EnableMouseWheel(enabled)
            end
        end
    end
    CludesUI.RefreshUnlockOverlapMethod = LM.UpdateMoverMouseWheel

    -- Rotate only the overlay levels; the real elements and saved layout stay put.
    local function CycleOverlappingMovers(current, delta)
        if not LM.isUnlocked or InCombatLockdown() or _mouseHeld or delta == 0 or not OverlapScrollDown() then
            return
        end
        local hits = {}
        for _, m in pairs(handles) do
            if m._dragging then
                return
            end
            if m:IsShown() and m:IsMouseOver() then
                hits[#hits + 1] = { mover = m, base = m._baseLevel, raised = m._raisedLevel }
            end
        end
        if #hits < 2 then
            return
        end
        table.sort(hits, function(lhs, rhs)
            if lhs.base == rhs.base then
                return lhs.mover._barKey < rhs.mover._barKey
            end
            return lhs.base > rhs.base
        end)
        local index
        for idx, hit in ipairs(hits) do
            if hit.mover == current then
                index = idx
                break
            end
        end
        if not index then
            return
        end
        index = (index - 1 + (delta > 0 and -1 or 1)) % #hits + 1
        local goal = hits[index].mover
        for idx = 1, #hits do
            local m = hits[(index + idx - 2) % #hits + 1].mover
            m._baseLevel = hits[idx].base
            m._raisedLevel = hits[idx].raised
            m._cycleLowered = m ~= goal
            m._hoverPending = false
        end
        -- Raise first so none of the lowered overlays can take mouse focus midway.
        goal:SetFrameLevel(goal._raisedLevel + 100)
        local accR, accG, accB = GetAccent()
        CludesUI.HideWidgetTooltip()
        for _, hit in ipairs(hits) do
            local m = hit.mover
            if m ~= goal then
                if m._forceCollapse then
                    m._forceCollapse()
                end
                m:SetFrameLevel(m._baseLevel)
                if m._cogBtn then
                    m._cogBtn:SetFrameLevel(m._baseLevel + 10)
                end
                if not m._selected then
                    if not LM.darkOverlaysEnabled then
                        m:SetAlpha(MOVER_ALPHA)
                    end
                    m._brd:SetColor(accR, accG, accB, 0.6)
                end
            end
        end
        goal:GetScript("OnEnter")(goal)
    end

    -- True while any part of a frame's rect reads secret: all of it when the frame
    -- rides an engine aura container, its size alone when only one edge does (a
    -- Blizzard Style unit frame's box around its aura stack). Nothing measures it then.
    local function RectSecret(f)
        return issecretvalue
                and (issecretvalue(f:GetLeft()) or issecretvalue(f:GetTop()) or issecretvalue(f:GetWidth()) or issecretvalue(
                    f:GetHeight()
                ))
            or false
    end

    -------------------------------------------------------------------------------
    --  Menu pools. A menu keeps the rows, edit-box rows, titles and dividers it has
    --  built and hands them out again on every open, so a reopened menu builds
    --  nothing new. Begin resets the counters, each Item / Field / Title / Div call
    --  returns the next entry (built on first use, its per-use state reset) and End
    --  hides what the open did not use. `shadowed` picks the label style (drop
    --  shadow, else outline); `fineDivs` makes the dividers unsnapped so a height of
    --  one physical pixel stays exact. Every frame here is one this file creates.
    -------------------------------------------------------------------------------
    local MenuPool = {}

    -- Background and border, built once when the menu frame is created.
    function MenuPool.Chrome(dropMenu)
        local backdrop = dropMenu:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(0.088, 0.098, 0.111, 0.95)
        CludesUI.MakeBorder(dropMenu, 1, 1, 1, 0.20)
        CludesUI.AccentCap(dropMenu)
    end

    function MenuPool.Begin(dropMenu, shadowed, fineDivs)
        local p = dropMenu._pool
        if not p then
            p = { shadowed = shadowed, fineDivs = fineDivs, items = {}, fields = {}, titles = {}, divs = {} }
            dropMenu._pool = p
        end
        p.nItems, p.nFields, p.nTitles, p.nDivs = 0, 0, 0, 0
    end

    function MenuPool.End(dropMenu)
        local p = dropMenu._pool
        for idx = p.nItems + 1, #p.items do
            local entry = p.items[idx]
            entry:Hide()
            if entry._sub then
                entry._sub:Hide()
            end
        end
        for idx = p.nFields + 1, #p.fields do
            local row = p.fields[idx]
            row:Hide()
            -- A hidden edit box keeps the keyboard: release it with the row.
            local checkBox = row._box
            if checkBox and checkBox:HasFocus() then
                checkBox:ClearFocus()
            end
        end
        for idx = p.nTitles + 1, #p.titles do
            p.titles[idx]:Hide()
        end
        for idx = p.nDivs + 1, #p.divs do
            p.divs[idx]:Hide()
        end
    end

    function MenuPool.Font(p, fontStr, size)
        if p.shadowed then
            CludesUI.PrimeFontShadow(fontStr, true)
            fontStr:SetFont(FONT_PATH, size, "")
        else
            fontStr:SetFont(FONT_PATH, size, "OUTLINE, SLUG")
        end
    end

    -- Clickable row: a highlight texture and a left label. Comes back with no
    -- scripts, the highlight clear, the label idle grey, anchored on its left only
    -- and wrapping, and the arrow, check box and flyout of an earlier use hidden.
    function MenuPool.Item(dropMenu, posY, hgt)
        local p = dropMenu._pool
        local num = p.nItems + 1
        p.nItems = num
        local entry = p.items[num]
        if not entry then
            entry = CreateFrame("Button", nil, dropMenu)
            entry:RegisterForClicks("AnyUp")
            local highlight = entry:CreateTexture(nil, "ARTWORK")
            highlight:SetAllPoints()
            entry._hl = highlight
            local labelFS = entry:CreateFontString(nil, "OVERLAY")
            MenuPool.Font(p, labelFS, 11)
            labelFS:SetJustifyH("LEFT")
            entry._lbl = labelFS
            p.items[num] = entry
        end
        entry:SetHeight(hgt)
        entry:ClearAllPoints()
        entry:SetPoint("TOPLEFT", dropMenu, "TOPLEFT", 1, posY)
        entry:SetPoint("TOPRIGHT", dropMenu, "TOPRIGHT", -1, posY)
        entry:SetFrameLevel(dropMenu:GetFrameLevel() + 2)
        entry:SetScript("OnEnter", nil)
        entry:SetScript("OnLeave", nil)
        entry:SetScript("OnClick", nil)
        local highlight, labelFS = entry._hl, entry._lbl
        highlight:SetColorTexture(1, 1, 1, 0)
        labelFS:ClearAllPoints()
        labelFS:SetPoint("LEFT", entry, "LEFT", 10, 0)
        labelFS:SetWordWrap(true)
        labelFS:SetTextColor(0.75, 0.75, 0.75, 0.9)
        if entry._arrow then
            entry._arrow:Hide()
        end
        if entry._check then
            entry._check:Hide()
        end
        if entry._sub then
            entry._sub:Hide()
        end
        entry:Show()
        return entry, highlight, labelFS
    end

    -- Check box on a pooled row's left (the suite's checkbox look, filled in the
    -- menu's linked orange while checked); the label moves to its right. dim
    -- greys the box on a row that cannot be picked.
    function MenuPool.Check(entry, checked, dim)
        local checkBox = entry._check
        if not checkBox then
            checkBox = CreateFrame("Frame", nil, entry)
            checkBox:SetSize(12, 12)
            checkBox:SetPoint("LEFT", entry, "LEFT", 10, 0)
            local backdrop = checkBox:CreateTexture(nil, "BACKGROUND")
            backdrop:SetAllPoints()
            backdrop:SetColorTexture(0.114, 0.106, 0.099, 1)
            checkBox._brd = CludesUI.MakeBorder(checkBox, 0.4, 0.4, 0.4, 0.6)
            local fill = checkBox:CreateTexture(nil, "ARTWORK")
            CludesUI.PP.SetInside(fill, checkBox, 2, 2)
            fill:SetColorTexture(1, 0.7, 0.3, 1)
            checkBox._fill = fill
            entry._check = checkBox
        end
        checkBox._fill:SetShown(checked and true or false)
        if checked then
            checkBox._brd:SetColor(1, 0.7, 0.3, 0.8)
        else
            checkBox._brd:SetColor(0.4, 0.4, 0.4, 0.6)
        end
        checkBox:SetAlpha(dim and 0.3 or 1)
        checkBox:Show()
        local labelFS = entry._lbl
        labelFS:ClearAllPoints()
        labelFS:SetPoint("LEFT", checkBox, "RIGHT", 6, 0)
        return checkBox
    end

    -- Right-pointing arrow on a pooled row (a row that opens a flyout).
    function MenuPool.Arrow(entry, texture, alpha)
        local a = entry._arrow
        if not a then
            a = entry:CreateTexture(nil, "ARTWORK")
            a:SetSize(10, 10)
            a:SetPoint("RIGHT", entry, "RIGHT", -8, 0)
            entry._arrow = a
        end
        a:SetTexture(texture)
        a:SetAlpha(alpha)
        a:Show()
        return a
    end

    -- Label row with an optional edit box on its right. The label comes back idle
    -- grey and wrapping; the box enabled, white, unfocused and without hover
    -- scripts. The caller sets the box's numeric mode, letter cap, value and keys.
    function MenuPool.Field(dropMenu, posY, hgt, withBox)
        local p = dropMenu._pool
        local num = p.nFields + 1
        p.nFields = num
        local row = p.fields[num]
        if not row then
            row = CreateFrame("Frame", nil, dropMenu)
            local labelFS = row:CreateFontString(nil, "OVERLAY")
            MenuPool.Font(p, labelFS, 11)
            labelFS:SetJustifyH("LEFT")
            labelFS:SetPoint("LEFT", row, "LEFT", 10, 0)
            row._lbl = labelFS
            p.fields[num] = row
        end
        row:SetHeight(hgt)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", dropMenu, "TOPLEFT", 1, posY)
        row:SetPoint("TOPRIGHT", dropMenu, "TOPRIGHT", -1, posY)
        row:SetFrameLevel(dropMenu:GetFrameLevel() + 2)
        local labelFS = row._lbl
        labelFS:SetWordWrap(true)
        labelFS:SetTextColor(0.75, 0.75, 0.75, 0.9)
        local checkBox = row._box
        -- A hidden edit box keeps the keyboard, so a reused or retired box lets go.
        if checkBox and checkBox:HasFocus() then
            checkBox:ClearFocus()
        end
        if withBox then
            if not checkBox then
                checkBox = CreateFrame("EditBox", nil, row)
                checkBox:SetSize(50, 18)
                checkBox:SetPoint("RIGHT", row, "RIGHT", -8, 0)
                checkBox:SetFont(FONT_PATH, 10, "")
                checkBox:SetJustifyH("CENTER")
                local boxBg = checkBox:CreateTexture(nil, "BACKGROUND")
                boxBg:SetAllPoints()
                boxBg:SetColorTexture(0, 0, 0, 0.4)
                checkBox:SetAutoFocus(false)
                row._box = checkBox
            end
            checkBox:SetFrameLevel(dropMenu:GetFrameLevel() + 3)
            checkBox:Enable()
            checkBox:SetTextColor(1, 1, 1, 0.9)
            checkBox:SetScript("OnEnter", nil)
            checkBox:SetScript("OnLeave", nil)
            checkBox:Show()
        elseif checkBox then
            checkBox:Hide()
        end
        row:Show()
        return row, labelFS, checkBox
    end

    -- Dimmed size-10 section title; the caller anchors it and sets its text.
    function MenuPool.Title(dropMenu)
        local p = dropMenu._pool
        local num = p.nTitles + 1
        p.nTitles = num
        local fontStr = p.titles[num]
        if not fontStr then
            fontStr = dropMenu:CreateFontString(nil, "OVERLAY")
            MenuPool.Font(p, fontStr, 10)
            fontStr:SetTextColor(1, 1, 1, 0.40)
            fontStr:SetJustifyH("LEFT")
            p.titles[num] = fontStr
        end
        fontStr:ClearAllPoints()
        fontStr:Show()
        return fontStr
    end

    -- Faint divider line across the menu at y, h tall.
    function MenuPool.Div(dropMenu, posY, hgt)
        local p = dropMenu._pool
        local num = p.nDivs + 1
        p.nDivs = num
        local d = p.divs[num]
        if not d then
            d = dropMenu:CreateTexture(nil, "ARTWORK")
            if p.fineDivs and d.SetSnapToPixelGrid then
                d:SetSnapToPixelGrid(false)
                d:SetTexelSnappingBias(0)
            end
            d:SetColorTexture(1, 1, 1, 0.10)
            p.divs[num] = d
        end
        d:SetHeight(hgt)
        d:ClearAllPoints()
        d:SetPoint("TOPLEFT", dropMenu, "TOPLEFT", 1, posY)
        d:SetPoint("TOPRIGHT", dropMenu, "TOPRIGHT", -1, posY)
        d:Show()
        return d
    end

    local function CreateMover(barId)
        local element = registeredElements[barId]
        local existing = handles[barId]

        -- Skip elements that are intentionally hidden or currently anchored
        -- (keepMoverWhenAnchored elements keep a position-locked mover instead).
        if
            element
            and (
                (element.isHidden and element.isHidden())
                or (element.isAnchored and element.isAnchored() and not element.keepMoverWhenAnchored)
            )
        then
            if existing then
                existing:Hide()
            end
            return nil
        end

        if existing then
            return existing
        end

        local barFrame = LM.GetBarFrame(barId)
        if not barFrame then
            return nil
        end

        local accR, accG, accB = GetAccent()
        local labelText = LM.GetBarLabel(barId)
        local gearButton -- forward declaration; assigned later in CreateMover

        local handle = CreateFrame("Button", nil, LM.unlockFrame)
        -- Party Frames always render above Raid Frames in unlock mode
        local MOVER_LEVEL_BUMP = (barId == "RF_PartyFrames") and 10 or 0
        local MOVER_BASE_LEVEL = LM.unlockFrame:GetFrameLevel() + 20 + MOVER_LEVEL_BUMP
        local MOVER_RAISED_LEVEL = MOVER_BASE_LEVEL + 5
        handle:SetFrameLevel(MOVER_BASE_LEVEL)
        handle._baseLevel = MOVER_BASE_LEVEL
        handle._raisedLevel = MOVER_RAISED_LEVEL
        handle:SetClampedToScreen(true)
        handle:SetMovable(true)
        handle:RegisterForDrag("LeftButton")
        handle:EnableMouse(true)
        local function OnMoverWheel(_, delta)
            CycleOverlappingMovers(handle, delta)
        end
        handle:EnableMouseWheel(OverlapScrollDown())
        handle:SetScript("OnMouseWheel", OnMoverWheel)
        handle:SetScript("OnMouseDown", function(self, btnFrame)
            if btnFrame == "LeftButton" then
                _mouseHeld = true
            end
        end)
        -- OnMouseUp is set later (after link buttons are created) to also handle link drag forwarding

        -- Background (matches cogwheel dark color at 75% opacity). Elements may
        -- override the base color via their moverBg definition field; the base is
        -- stored on the mover so snap-highlight and dark-overlay repaints keep it.
        local regElem = registeredElements[barId]
        local bgTint = regElem and regElem.moverBg
        handle._bgR = bgTint and bgTint.r or 0.075
        handle._bgG = bgTint and bgTint.g or 0.113
        handle._bgB = bgTint and bgTint.b or 0.141
        local backdrop = handle:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        if LM.darkOverlaysEnabled then
            backdrop:SetColorTexture(handle._bgR, handle._bgG, handle._bgB, 0.95)
        else
            backdrop:SetColorTexture(0, 0, 0, 0)
        end
        handle._bg = backdrop

        -- Pixel-perfect border (accent colored, uses shared MakeBorder)
        local brd = CludesUI.MakeBorder(handle, accR, accG, accB, 0.6)
        handle._brd = brd

        -- Label -- on a higher-level frame so it renders above the border
        local nameTag = CreateFrame("Frame", nil, handle)
        nameTag:SetAllPoints()
        nameTag:SetClipsChildren(true)
        nameTag:SetFrameLevel(handle:GetFrameLevel() + 3)
        local nameText = nameTag:CreateFontString(nil, "OVERLAY")
        CludesUI.PrimeFontShadow(nameText, true)
        nameText:SetFont(FONT_PATH, 10 + (UIParent:GetEffectiveScale() < 0.6 and 1 or 0), "")
        nameText:SetText(CludesUI.L(labelText))
        nameText:SetTextColor(1, 1, 1, 0.75)
        nameText:SetWordWrap(false)
        nameText:SetNonSpaceWrap(false)
        nameText:SetPoint("CENTER", handle, "CENTER")
        handle._label = nameText
        if not LM.darkOverlaysEnabled then
            nameText:Hide()
        end

        -- Optional dimmed subtitle under the label (element definition field)
        if regElem and regElem.subtitle then
            local subFS = nameTag:CreateFontString(nil, "OVERLAY")
            CludesUI.PrimeFontShadow(subFS, true)
            subFS:SetFont(FONT_PATH, 8 + (UIParent:GetEffectiveScale() < 0.6 and 1 or 0), "")
            subFS:SetText(CludesUI.L(regElem.subtitle))
            subFS:SetTextColor(1, 1, 1, 0.40)
            subFS:SetJustifyH("CENTER")
            subFS:SetWordWrap(true)
            subFS:SetNonSpaceWrap(false)
            subFS:SetPoint("TOP", nameText, "BOTTOM", 0, -3)
            subFS:SetPoint("LEFT", nameTag, "LEFT", 8, 0)
            subFS:SetPoint("RIGHT", nameTag, "RIGHT", -8, 0)
            handle._subtitle = subFS
            if not LM.darkOverlaysEnabled then
                subFS:Hide()
            end
        end

        -- Coordinate readout (shows during drag and selection, top-left of mover)
        local coordFS = nameTag:CreateFontString(nil, "OVERLAY")
        CludesUI.PrimeFontShadow(coordFS, true)
        coordFS:SetFont(FONT_PATH, 9 + (UIParent:GetEffectiveScale() < 0.6 and 1 or 0), "")
        coordFS:SetTextColor(1, 1, 1, 0.7)
        coordFS:SetPoint("TOPLEFT", handle, "TOPLEFT", 3, -2)
        coordFS:Hide()
        handle._coordFS = coordFS

        ---------------------------------------------------------------------------
        --  W Match | H Match | Anchor | Grow  (centered below the name)
        --  Also: "Anchored" text and pick-mode instruction text
        ---------------------------------------------------------------------------
        -- Action link text labels
        local WM_TEXT = "W Match"
        local HM_TEXT = "H Match"
        local AT_TEXT = "Anchor"
        local GD_TEXT = "Grow"

        -- Clickable buttons for each action (parented to labelFrame for correct level)
        local wmBtn = CreateFrame("Button", nil, nameTag)
        wmBtn:SetFrameLevel(nameTag:GetFrameLevel() + 2)
        wmBtn:RegisterForClicks("LeftButtonUp")
        wmBtn:EnableMouse(true)
        wmBtn:Hide()

        local hmBtn = CreateFrame("Button", nil, nameTag)
        hmBtn:SetFrameLevel(nameTag:GetFrameLevel() + 2)
        hmBtn:RegisterForClicks("LeftButtonUp")
        hmBtn:EnableMouse(true)
        hmBtn:Hide()

        local atBtn = CreateFrame("Button", nil, nameTag)
        atBtn:SetFrameLevel(nameTag:GetFrameLevel() + 2)
        atBtn:RegisterForClicks("LeftButtonUp")
        atBtn:EnableMouse(true)
        atBtn:Hide()

        local gdBtn = CreateFrame("Button", nil, nameTag)
        gdBtn:SetFrameLevel(nameTag:GetFrameLevel() + 2)
        gdBtn:RegisterForClicks("LeftButtonUp")
        gdBtn:EnableMouse(true)
        gdBtn:Hide()

        -- Store link buttons on mover so OnLeave can check if any are hovered
        handle._linkBtns = { wmBtn, hmBtn, atBtn, gdBtn }
        for _, button in ipairs(handle._linkBtns) do
            button:EnableMouseWheel(OverlapScrollDown())
            button:SetScript("OnMouseWheel", OnMoverWheel)
        end

        -- Font strings inside each button (accent colored, drop shadow)
        local widthMatchText = wmBtn:CreateFontString(nil, "OVERLAY")
        CludesUI.PrimeFontShadow(widthMatchText, true)
        widthMatchText:SetFont(FONT_PATH, 9, "")
        widthMatchText:SetTextColor(accR, accG, accB, 0.85)
        widthMatchText:SetText(CludesUI.L(WM_TEXT))
        widthMatchText:SetPoint("CENTER")

        local heightMatchText = hmBtn:CreateFontString(nil, "OVERLAY")
        CludesUI.PrimeFontShadow(heightMatchText, true)
        heightMatchText:SetFont(FONT_PATH, 9, "")
        heightMatchText:SetTextColor(accR, accG, accB, 0.85)
        heightMatchText:SetText(CludesUI.L(HM_TEXT))
        heightMatchText:SetPoint("CENTER")

        local anchorText = atBtn:CreateFontString(nil, "OVERLAY")
        CludesUI.PrimeFontShadow(anchorText, true)
        anchorText:SetFont(FONT_PATH, 9, "")
        anchorText:SetTextColor(accR, accG, accB, 0.85)
        anchorText:SetText(CludesUI.L(AT_TEXT))
        anchorText:SetPoint("CENTER")

        local gdFS = gdBtn:CreateFontString(nil, "OVERLAY")
        CludesUI.PrimeFontShadow(gdFS, true)
        gdFS:SetFont(FONT_PATH, 9, "")
        gdFS:SetTextColor(accR, accG, accB, 0.85)
        gdFS:SetText(CludesUI.L(GD_TEXT))
        gdFS:SetPoint("CENTER")

        -- 1px pixel-perfect divider lines between action links
        local Pix = CludesUI and CludesUI.PP
        local divPx = Pix and Pix.mult or 1

        local div1 = nameTag:CreateTexture(nil, "OVERLAY")
        div1:SetColorTexture(1, 1, 1, 0.25)
        div1:SetWidth(divPx)
        div1:SetHeight(10)
        if div1.SetSnapToPixelGrid then
            div1:SetSnapToPixelGrid(false)
            div1:SetTexelSnappingBias(0)
        end
        div1:Hide()

        local div2 = nameTag:CreateTexture(nil, "OVERLAY")
        div2:SetColorTexture(1, 1, 1, 0.25)
        div2:SetWidth(divPx)
        div2:SetHeight(10)
        if div2.SetSnapToPixelGrid then
            div2:SetSnapToPixelGrid(false)
            div2:SetTexelSnappingBias(0)
        end
        div2:Hide()

        local div3 = nameTag:CreateTexture(nil, "OVERLAY")
        div3:SetColorTexture(1, 1, 1, 0.25)
        div3:SetWidth(divPx)
        div3:SetHeight(10)
        if div3.SetSnapToPixelGrid then
            div3:SetSnapToPixelGrid(false)
            div3:SetTexelSnappingBias(0)
        end
        div3:Hide()

        -- Determine if this element supports resizing
        local canResize = not (element and element.noResize)
        -- Determine if this element can be anchored to other elements (an element
        -- that places itself, ownsPosition, takes no link either)
        local canAnchorTo = not (element and (element.noAnchorTo or element.ownsPosition))

        -- Grow direction: action bars 1-8 and CDM bars (both horizontal and vertical)
        local _GROW_KEYS = {
            MainBar = true,
            Bar2 = true,
            Bar3 = true,
            Bar4 = true,
            Bar5 = true,
            Bar6 = true,
            Bar7 = true,
            Bar8 = true,
            StanceBar = true,
            PetBar = true,
            ERB_TotemBar = true, -- totem bar: align active icons left/right/center
            EABR_Reminders = true, -- aura buff reminders: align icons left/right/center
        }
        local canGrow = _GROW_KEYS[barId] or barId:sub(1, 4) == "CDM_" or barId:sub(1, 4) == "PAB_"

        -- Match-source capability: width/height MATCH buttons may appear even when
        -- drag/manual resize is disabled (noResize), if the element opts in via
        -- allowMatchSource (e.g. tracking bars sized via their own sliders can still size-MATCH another element).
        local canMatchSource = canResize or (element and element.allowMatchSource) or false

        -- Single source of truth for which action-row link buttons are active, in
        -- left-to-right order. The layout, the hover show/hide, and the hover-box
        -- width calc all read this so they never drift apart. `fb` = fallback width.
        local function ActiveLinks()
            local t = {}
            -- A match resizes this element through its own setter, so each match
            -- button shows only when that setter exists.
            if canMatchSource then
                if not element or element.setWidth then
                    t[#t + 1] = { btn = wmBtn, fs = widthMatchText, fb = 50 }
                end
                if not element or element.setHeight then
                    t[#t + 1] = { btn = hmBtn, fs = heightMatchText, fb = 55 }
                end
            end
            if canAnchorTo and not mod.IsMoverPosLocked(barId) then
                t[#t + 1] = { btn = atBtn, fs = anchorText, fb = 45 }
            end
            if canGrow then
                t[#t + 1] = { btn = gdBtn, fs = gdFS, fb = 30 }
            end
            return t
        end

        -- Layout: position action link buttons + dividers centered below name.
        -- Unified dynamic layout: lay out exactly the buttons ActiveLinks() reports,
        -- with one divider between each adjacent pair. This renders the existing
        -- cases pixel-identically and naturally handles match-buttons-without-resize.
        local function LayoutActionRow()
            local gap = 8
            local itemList = ActiveLinks()
            if #itemList == 0 then
                return
            end
            local divs = { div1, div2, div3 }
            local totalW = 0
            for idx, entry in ipairs(itemList) do
                entry.w = entry.fs:GetStringWidth() or entry.fb
                totalW = totalW + entry.w
                if idx < #itemList then
                    totalW = totalW + gap + 1 + gap
                end
            end
            local posX = -totalW / 2
            for idx, entry in ipairs(itemList) do
                entry.btn:SetSize(entry.w + 4, 14)
                entry.btn:ClearAllPoints()
                entry.btn:SetPoint("TOP", nameText, "BOTTOM", posX + entry.w / 2, -4)
                posX = posX + entry.w
                if idx < #itemList and divs[idx] then
                    divs[idx]:ClearAllPoints()
                    divs[idx]:SetPoint("TOP", nameText, "BOTTOM", posX + gap + 0.5, -6)
                    posX = posX + gap + 1 + gap
                end
            end
        end
        -- For MatchH.CommitMatchExtra (file scope): the matched label changes width.
        handle._layoutActionRow = LayoutActionRow

        -- Anchored indicator: name label turns orange when anchored
        -- No separate font string needed
        local anchoredFS = nil
        handle._anchoredFS = nil

        -- Pick mode instruction text (shown when in pick mode, replaces all other text)
        local pickText = nameTag:CreateFontString(nil, "OVERLAY")
        CludesUI.PrimeFontShadow(pickText, true)
        pickText:SetFont(FONT_PATH, 10 + (UIParent:GetEffectiveScale() < 0.6 and 1 or 0), "")
        pickText:SetTextColor(1, 1, 1, 0.85)
        pickText:SetPoint("CENTER", handle, "CENTER")
        pickText:SetJustifyH("CENTER")
        pickText:SetWordWrap(true)
        pickText:Hide()
        handle._pickFS = pickText

        ---------------------------------------------------------------------------
        --  Hover animation state
        --  0 = idle (name centered, action row hidden)
        --  1 = hovered (name shifted up, action row visible + faded in)
        ---------------------------------------------------------------------------
        local LABEL_Y_NORMAL = 0
        local LABEL_Y_SHIFTED = 7
        local ANIM_DUR = 0.15
        local hoverState = 0
        local hoverTarget = 0
        local isAnchored = false
        local realW, realH = 0, 0 -- real element size (set by Sync)
        local moverCX, moverCY = 0, 0 -- stored center in UIParent-TOPLEFT coords (set by Sync)
        handle._setCenterXY = function(cx, cy)
            moverCX = cx
            moverCY = cy
        end
        handle._getCenterXY = function()
            return moverCX, moverCY
        end

        -- Re-anchor the mover directly to the bar frame so both share the exact same
        -- screen position with zero coordinate math (pixel-perfect). The bar's CENTER
        -- anchor is already applied synchronously by RecenterBarAnchor before this
        -- fires, so just update mover size and re-attach to bar TOPLEFT. Deferred one frame so the bar's layout has flushed after a move/resize.
        function handle:ReanchorToBar()
            local barKey = self._barKey
            local self2 = self
            C_Timer.After(0, function()
                if self2._dragging then
                    return
                end
                local b = LM.GetBarFrame(barKey)
                if not b then
                    return
                end
                -- A bar riding an engine aura container reports a secret rect
                -- outside unlock mode (the follow provider is inert inside it, so
                -- the bar rests plain there): nothing to attach to yet.
                if RectSecret(b) then
                    return
                end
                local s = b:GetEffectiveScale()
                local uiZoom = UIParent:GetEffectiveScale()
                local elemScale = s / uiZoom
                -- Update size from bar (+ any below-frame extra, e.g. boss castbar).
                local element = registeredElements[barKey]
                local extra = (element and element.getBottomExtra and (element.getBottomExtra(barKey) or 0) or 0)
                    * elemScale
                -- Visual insets (optional, e.g. a Blizzard Style unit frame whose stock
                -- box carries transparent padding round its art): the mover outlines
                -- the rect inside them. Left, right, top, bottom in the bar's units.
                local il, ir, entry, ib = 0, 0, 0, 0
                if element and element.getInsets then
                    local l, r, t, bt = element.getInsets(barKey)
                    if l then
                        il, ir, entry, ib =
                            l * elemScale, (r or 0) * elemScale, (t or 0) * elemScale, (bt or 0) * elemScale
                    end
                end
                local wid = (b:GetWidth() or 50) * elemScale - il - ir
                local hgt = (b:GetHeight() or 50) * elemScale + extra - entry - ib
                if wid > 10 then
                    realW = wid
                end
                if hgt > 10 then
                    realH = hgt
                end
                self2:SetSize(realW, realH)
                -- Recompute moverCX/moverCY from bar's current center. Shift the
                -- stored center DOWN by half the extra so the box stays top-pinned
                -- to the frame and grows downward over the extra region; insets
                -- shift it by half their difference.
                local bcx, bcy = b:GetCenter()
                if bcx and bcy then
                    moverCX = bcx * elemScale + (il - ir) * 0.5
                    moverCY = bcy * elemScale - UIParent:GetHeight() - extra * 0.5 + (ib - entry) * 0.5
                end
                -- Anchor mover to bar TOPLEFT for pixel-perfect overlay
                CludesUI._unlockAttachMover(self2, b, barKey, il, entry)
                LM.PointPicker.Refresh(self2)
            end)
        end

        -- Refresh link button text/color based on active matches
        local function RefreshLinkStates()
            local wm = MatchH.GetWidthMatchInfo(barId)
            local hm = MatchH.GetHeightMatchInfo(barId)
            local anchorInfo = GetAnchorInfo(barId)
            -- For linkedDimensions elements, one active match blocks the other
            local wmBlocked = element and element.linkedDimensions and hm ~= nil
            local hmBlocked = element and element.linkedDimensions and wm ~= nil
            if wm then
                widthMatchText:SetText(CludesUI.L("W Matched"))
                widthMatchText:SetTextColor(1, 0.7, 0.3, 0.85)
                -- A match's Extra Width rides the label: "W Matched +5".
                local wx = CludesUI.GetMatchExtra("w", barId)
                if wx then
                    widthMatchText:SetText(CludesUI.L("W Matched") .. (wx > 0 and " +" or " ") .. wx)
                end
            elseif wmBlocked then
                widthMatchText:SetText(CludesUI.L("W Match"))
                widthMatchText:SetTextColor(accR, accG, accB, 0.35)
            else
                widthMatchText:SetText(CludesUI.L("W Match"))
                widthMatchText:SetTextColor(accR, accG, accB, 0.85)
            end
            if hm then
                heightMatchText:SetText(CludesUI.L("H Matched"))
                heightMatchText:SetTextColor(1, 0.7, 0.3, 0.85)
                local hx = CludesUI.GetMatchExtra("h", barId)
                if hx then
                    heightMatchText:SetText(CludesUI.L("H Matched") .. (hx > 0 and " +" or " ") .. hx)
                end
            elseif hmBlocked then
                heightMatchText:SetText(CludesUI.L("H Match"))
                heightMatchText:SetTextColor(accR, accG, accB, 0.35)
            else
                heightMatchText:SetText(CludesUI.L("H Match"))
                heightMatchText:SetTextColor(accR, accG, accB, 0.85)
            end
            if anchorInfo then
                anchorText:SetText(CludesUI.L("Anchored"))
                anchorText:SetTextColor(1, 0.7, 0.3, 0.85)
            else
                anchorText:SetText(CludesUI.L("Anchor"))
                anchorText:SetTextColor(accR, accG, accB, 0.85)
            end
            gdFS:SetText(CludesUI.L("Grow"))
            gdFS:SetTextColor(1, 0.7, 0.3, 0.85)
        end

        -- Update the name label color based on anchor state
        local function RefreshAnchoredIdle()
            -- A link on an element that places itself (ownsPosition) is inert.
            local anchorInfo = not (element and element.ownsPosition) and GetAnchorInfo(barId) or nil
            isAnchored = anchorInfo ~= nil or mod.IsMoverPosLocked(barId)
            nameText:SetText(CludesUI.L(labelText))
            if isAnchored then
                nameText:SetTextColor(1, 0.7, 0.3, 0.85)
            else
                nameText:SetTextColor(1, 1, 1, 0.75)
            end
        end

        local animFrame = CreateFrame("Frame", nil, nameTag)

        local function ApplyHoverState(s)
            -- Name shifts up on hover to make room for action links below
            local labelShift = LABEL_Y_NORMAL + s * (LABEL_Y_SHIFTED - LABEL_Y_NORMAL)
            labelShift = labelShift + 2 - s
            -- Update the existing anchor offset instead of ClearAllPoints to avoid
            -- layout thrash that causes the label to jitter during animation.
            nameText:SetPoint("CENTER", handle, "CENTER", 0, labelShift)
            -- Smoothly interpolate text width from constrained to unconstrained
            -- to avoid a hard snap when the animation starts.
            if realW > 0 then
                local constrainedW = realW
                local targetW = handle._cachedNameStrW or constrainedW
                local curTextW = constrainedW + (targetW - constrainedW) * s
                nameText:SetWidth(curTextW)
            end

            -- Action links: show on hover. Visibility is built from the same
            -- ActiveLinks() list as the layout, so match buttons appear for
            -- allowMatchSource elements and the dividers always match the buttons.
            local links = ActiveLinks()
            local activeBtn = {}
            for _, entry in ipairs(links) do
                activeBtn[entry.btn] = true
            end
            local function _linkVis(button)
                if activeBtn[button] then
                    button:SetAlpha(s)
                    if s > 0.01 then
                        button:Show()
                    else
                        button:Hide()
                    end
                else
                    button:Hide()
                end
            end
            _linkVis(wmBtn)
            _linkVis(hmBtn)
            _linkVis(atBtn)
            _linkVis(gdBtn)
            local nDivs = #links > 0 and (#links - 1) or 0
            local divsV = { div1, div2, div3 }
            for idx = 1, 3 do
                if idx <= nDivs then
                    divsV[idx]:SetAlpha(s)
                    if s > 0.01 then
                        divsV[idx]:Show()
                    else
                        divsV[idx]:Hide()
                    end
                else
                    divsV[idx]:Hide()
                end
            end

            -- Cog: same show/hide as links
            if gearButton then
                gearButton:SetAlpha(s)
                if s > 0.01 then
                    gearButton:Show()
                else
                    gearButton:Hide()
                end
            end

            -- Animate-expand the mover only on hover (idle = raw element size)
            if realW > 0 and realH > 0 then
                local PAD = 5
                -- Use cached hover dimensions (computed once in ShowOverlayText)
                -- to avoid calling GetStringWidth every frame during animation.
                local hoverW = handle._cachedHoverW or realW
                local hoverH = handle._cachedHoverH or realH
                local curW = realW + (hoverW - realW) * s
                local curH = realH + (hoverH - realH) * s
                -- Expand symmetrically from the mover's stored center (set by Sync).
                -- This avoids reading GetLeft/GetTop from the bar frame, which can
                -- shift after a resize and cause the mover to teleport.
                local hasCenterXY = (moverCX ~= 0 or moverCY ~= 0)
                if hasCenterXY then
                    local tx = moverCX - curW * 0.5
                    local ty = moverCY + curH * 0.5
                    handle:ClearAllPoints()
                    handle:SetPoint("TOPLEFT", UIParent, "TOPLEFT", tx, ty)
                else
                    -- Fallback: Sync hasn't run yet, read from bar frame
                    local bk2 = handle._barKey
                    local b2 = LM.GetBarFrame(bk2)
                    if b2 then
                        local s2 = b2:GetEffectiveScale()
                        local uiS2 = UIParent:GetEffectiveScale()
                        local bL2 = b2:GetLeft()
                        local bT2 = b2:GetTop()
                        if bL2 and bT2 then
                            local tx = bL2 * s2 / uiS2 - (curW - realW) * 0.5
                            local ty = bT2 * s2 / uiS2 - UIParent:GetHeight() + (curH - realH) * 0.5
                            handle:ClearAllPoints()
                            handle:SetPoint("TOPLEFT", UIParent, "TOPLEFT", tx, ty)
                        end
                    end
                end
                handle:SetSize(curW, curH)
            end
        end

        local function AnimateHoverTo(goal)
            if
                goal == hoverTarget
                and not animFrame:GetScript("OnUpdate")
                and math.abs(hoverState - goal) < 0.01
            then
                return
            end
            hoverTarget = goal
            animFrame:SetScript("OnUpdate", function(self, elapsed)
                local dir = hoverTarget > hoverState and 1 or -1
                hoverState = hoverState + dir * (elapsed / ANIM_DUR)
                if (dir == 1 and hoverState >= hoverTarget) or (dir == -1 and hoverState <= hoverTarget) then
                    hoverState = hoverTarget
                    self:SetScript("OnUpdate", nil)
                    -- Snap back to bar anchor when fully collapsed
                    if hoverState == 0 and handle.ReanchorToBar then
                        handle:ReanchorToBar()
                    end
                    -- Show coordinates when fully expanded
                    if hoverState == 1 and handle._coordFS then
                        if handle.UpdateCoordText then
                            handle:UpdateCoordText()
                        end
                    end
                end
                ApplyHoverState(hoverState)
            end)
        end

        -- Show/hide overlay text helpers
        local function ShowOverlayText()
            handle._hoverConfirmed = true
            if LM.darkOverlaysEnabled then
                nameText:SetAlpha(1)
                nameText:Show()
            end
            RefreshAnchoredIdle()
            -- Cache hover dimensions once so ApplyHoverState avoids per-frame GetStringWidth
            if realW > 0 and realH > 0 then
                local PAD = 5
                local nameW = nameText:GetStringWidth() or 0
                local nameH = nameText:GetStringHeight() or 10
                local rowW = 0
                do
                    local links = ActiveLinks()
                    local gap = 8
                    for idx, entry in ipairs(links) do
                        rowW = rowW + (entry.fs:GetStringWidth() or entry.fb)
                        if idx < #links then
                            rowW = rowW + gap + 1 + gap
                        end
                    end
                end
                local contentW = math.max(nameW, rowW)
                local contentH = nameH + 4 + 14
                handle._cachedHoverW = math.max(realW, contentW + PAD * 2 + 6)
                handle._cachedHoverH = math.max(realH, contentH + PAD * 2 + 2)
            end
            -- Cache unconstrained name width for smooth text width interpolation
            local nsw = nameText:GetStringWidth() or realW
            handle._cachedNameStrW = math.max(nsw + 4, realW)
            -- Skip RefreshLinkStates if a link button is currently hovered (would reset its white color)
            local linkHovered = false
            if handle._linkBtns then
                for _, btn in ipairs(handle._linkBtns) do
                    if btn:IsMouseOver() then
                        linkHovered = true
                        break
                    end
                end
            end
            if not linkHovered then
                RefreshLinkStates()
            end
            LayoutActionRow()
            AnimateHoverTo(1)
            pickText:Hide()
        end

        local function HideOverlayText()
            handle._hoverConfirmed = false
            -- Hide coordinates when collapsing (unless coords-always-on)
            if handle._coordFS and not LM.coordsEnabled then
                handle._coordFS:Hide()
            end
            AnimateHoverTo(0)
        end

        local function ShowPickText(textValue)
            wmBtn:Hide()
            hmBtn:Hide()
            atBtn:Hide()
            gdBtn:Hide()
            div1:Hide()
            div2:Hide()
            div3:Hide()
            hoverState = 0
            hoverTarget = 0
            animFrame:SetScript("OnUpdate", nil)
            nameText:ClearAllPoints()
            nameText:SetPoint("CENTER", handle, "CENTER", 0, LABEL_Y_NORMAL)
            nameText:SetAlpha(0)
            pickText:SetText(CludesUI.L(textValue))
            pickText:Show()
        end

        local function HidePickText()
            pickText:Hide()
            if LM.darkOverlaysEnabled then
                nameText:SetAlpha(1)
            end
        end

        handle._showOverlayText = ShowOverlayText
        handle._hideOverlayText = HideOverlayText
        handle._showPickText = ShowPickText
        handle._hidePickText = HidePickText

        -- Snap-collapse: instantly reset hover state without animation.
        -- Used by DoClose to guarantee no mover is stuck expanded on re-enter.
        handle._forceCollapse = function()
            hoverState = 0
            hoverTarget = 0
            handle._hoverConfirmed = false
            if handle._coordFS and not LM.coordsEnabled then
                handle._coordFS:Hide()
            end
            animFrame:SetScript("OnUpdate", nil)
            ApplyHoverState(0)
            if handle.ReanchorToBar then
                handle:ReanchorToBar()
            end
        end

        -- Refresh the anchored text (called after anchor changes)
        function handle:RefreshAnchoredText()
            RefreshAnchoredIdle()
            RefreshLinkStates()
            -- If not hovered, apply idle state to show/hide anchored text
            if not self:IsMouseOver() then
                ApplyHoverState(hoverState)
            end
        end

        -- Hover effects for action buttons (brighten to white on hover, keep mover highlighted)
        local function BtnEnter(button, fontStr, matchType)
            CludesUI.HideWidgetTooltip()
            -- Check if this button is blocked by linkedDimensions
            local isBlocked = false
            if element and element.linkedDimensions then
                if
                    matchType == "width"
                    and MatchH.GetHeightMatchInfo(barId) ~= nil
                    and MatchH.GetWidthMatchInfo(barId) == nil
                then
                    isBlocked = true
                elseif
                    matchType == "height"
                    and MatchH.GetWidthMatchInfo(barId) ~= nil
                    and MatchH.GetHeightMatchInfo(barId) == nil
                then
                    isBlocked = true
                end
            end
            if isBlocked then
                CludesUI.ShowWidgetTooltip(button, "This element doesn't support both Height and Width matching")
                return
            end
            fontStr:SetTextColor(1, 1, 1, 1)
            handle:SetFrameLevel(handle._raisedLevel + 100)
            handle._brd:SetColor(1, 1, 1, 0.9)
            -- Show tooltip for active matches
            local tipText
            if matchType == "width" then
                local goal = MatchH.GetWidthMatchInfo(barId)
                if goal then
                    tipText = LM.GetBarLabel(goal) or goal
                end
            elseif matchType == "height" then
                local goal = MatchH.GetHeightMatchInfo(barId)
                if goal then
                    tipText = LM.GetBarLabel(goal) or goal
                end
            elseif matchType == "anchor" then
                local details = GetAnchorInfo(barId)
                if details then
                    tipText = LM.GetBarLabel(details.target) or details.target
                end
            elseif matchType == "grow" then
                local gd = GetBarGrowDir(barId)
                if gd then
                    tipText = "Grow " .. gd:sub(1, 1) .. gd:sub(2):lower()
                end
            end
            if tipText then
                CludesUI.ShowWidgetTooltip(button, tipText)
            end
        end
        local function BtnLeave(button, fontStr, matchType)
            CludesUI.HideWidgetTooltip()
            -- Restore correct color based on active/blocked state
            local isActive = false
            local isBlocked = false
            if matchType == "width" then
                isActive = MatchH.GetWidthMatchInfo(barId) ~= nil
                isBlocked = element
                    and element.linkedDimensions
                    and not isActive
                    and MatchH.GetHeightMatchInfo(barId) ~= nil
            elseif matchType == "height" then
                isActive = MatchH.GetHeightMatchInfo(barId) ~= nil
                isBlocked = element
                    and element.linkedDimensions
                    and not isActive
                    and MatchH.GetWidthMatchInfo(barId) ~= nil
            elseif matchType == "anchor" then
                isActive = GetAnchorInfo(barId) ~= nil
            elseif matchType == "grow" then
                isActive = true
            end
            if isActive then
                fontStr:SetTextColor(1, 0.7, 0.3, 0.85)
            elseif isBlocked then
                fontStr:SetTextColor(accR, accG, accB, 0.35)
            else
                fontStr:SetTextColor(accR, accG, accB, 0.85)
            end
            -- Restore frame level/border only -- mover OnLeave owns the collapse
            C_Timer.After(0.05, function()
                if not handle:IsMouseOver() then
                    local overChild = handle._cogBtn and handle._cogBtn:IsMouseOver()
                    if not overChild and handle._linkBtns then
                        for _, btn in ipairs(handle._linkBtns) do
                            if btn:IsMouseOver() then
                                overChild = true
                                break
                            end
                        end
                    end
                    if not overChild then
                        handle:SetFrameLevel(handle._baseLevel)
                        if handle._cogBtn then
                            handle._cogBtn:SetFrameLevel(handle._baseLevel + 10)
                        end
                        handle._brd:SetColor(accR, accG, accB, 0.6)
                    end
                end
            end)
        end
        wmBtn:SetScript("OnEnter", function(self)
            BtnEnter(self, widthMatchText, "width")
        end)
        wmBtn:SetScript("OnLeave", function(self)
            BtnLeave(self, widthMatchText, "width")
        end)
        hmBtn:SetScript("OnEnter", function(self)
            BtnEnter(self, heightMatchText, "height")
        end)
        hmBtn:SetScript("OnLeave", function(self)
            BtnLeave(self, heightMatchText, "height")
        end)
        atBtn:SetScript("OnEnter", function(self)
            BtnEnter(self, anchorText, "anchor")
        end)
        atBtn:SetScript("OnLeave", function(self)
            BtnLeave(self, anchorText, "anchor")
        end)

        -- Forward drag from link buttons to the mover using OnMouseDown/Up instead of
        -- WoW's drag system: RegisterForDrag fires OnDragStop as soon as the button
        -- moves (happens when the hover row collapses on drag start), breaking the drag
        -- immediately; OnMouseDown/Up bypass that. To avoid collapsing the action row on a plain click, defer drag start until the cursor moves 3px.
        local linkDragPending = false
        local linkDragStartX, linkDragStartY = 0, 0

        local function LinkMouseDown(button, btnFrame)
            if btnFrame ~= "LeftButton" then
                return
            end
            local uiScale = UIParent:GetEffectiveScale()
            linkDragStartX, linkDragStartY = GetCursorPosition()
            linkDragStartX = linkDragStartX / uiScale
            linkDragStartY = linkDragStartY / uiScale
            linkDragPending = true
            -- Poll for movement threshold before committing to drag
            handle:SetScript("OnUpdate", function(s)
                if not linkDragPending then
                    return
                end
                local sc2 = UIParent:GetEffectiveScale()
                local curX, curY = GetCursorPosition()
                curX = curX / sc2
                curY = curY / sc2
                if abs(curX - linkDragStartX) > 1 or abs(curY - linkDragStartY) > 1 then
                    linkDragPending = false
                    -- Now fire the real drag start
                    local script = handle:GetScript("OnDragStart")
                    if script then
                        script(handle)
                    end
                end
            end)
        end
        local function LinkMouseUp(button, btnFrame)
            if btnFrame ~= "LeftButton" then
                return
            end
            linkDragPending = false
            if handle._dragging then
                local script = handle:GetScript("OnDragStop")
                if script then
                    script(handle)
                end
            else
                -- No drag committed -- clear the pending OnUpdate
                handle:SetScript("OnUpdate", nil)
            end
        end
        wmBtn:SetScript("OnMouseDown", LinkMouseDown)
        wmBtn:SetScript("OnMouseUp", LinkMouseUp)
        hmBtn:SetScript("OnMouseDown", LinkMouseDown)
        hmBtn:SetScript("OnMouseUp", LinkMouseUp)
        atBtn:SetScript("OnMouseDown", LinkMouseDown)
        atBtn:SetScript("OnMouseUp", LinkMouseUp)
        -- Also catch mouse release on the mover itself during a link-initiated drag.
        -- When the user drags far from the link button, the release happens over the
        -- mover (or nowhere), so the link button's OnMouseUp never fires.
        handle:SetScript("OnMouseUp", function(self, btnFrame)
            if btnFrame == "LeftButton" then
                _mouseHeld = false
                if linkDragPending or self._dragging then
                    LinkMouseUp(self, btnFrame)
                end
            end
        end)

        -- Click handlers for Width Match / Height Match / Anchor To
        -- Toggle: if already matched, clear it; otherwise enter pick mode
        wmBtn:SetScript("OnClick", function()
            CludesUI.HideWidgetTooltip()
            -- Block if linkedDimensions and height match is already active
            if
                element
                and element.linkedDimensions
                and MatchH.GetHeightMatchInfo(barId) ~= nil
                and MatchH.GetWidthMatchInfo(barId) == nil
            then
                return
            end
            if MatchH.GetWidthMatchInfo(barId) then
                MatchH.ClearWidthMatch(barId)
                LM.hasChanges = true
                RefreshLinkStates()
                LayoutActionRow()
                return
            end
            -- Element-declared dynamic block on NEW matches (clearing above stays
            -- allowed): e.g. action bars in Blizzard Style, where CUI doesn't
            -- size the bars and a match would only write junk settings.
            if element and element.matchUnavailable then
                local why = element.matchUnavailable(barId)
                if why then
                    CludesUI.ShowWidgetTooltip(wmBtn, why)
                    return
                end
            end
            CancelPickMode()
            LM.pickMode = "widthMatch"
            LM.pickModeMover = handle
            ShowPickText("Click any element\nto match its width")
            FadeOverlayForSelectElement(true)
        end)

        hmBtn:SetScript("OnClick", function()
            CludesUI.HideWidgetTooltip()
            -- Block if linkedDimensions and width match is already active
            if
                element
                and element.linkedDimensions
                and MatchH.GetWidthMatchInfo(barId) ~= nil
                and MatchH.GetHeightMatchInfo(barId) == nil
            then
                return
            end
            if MatchH.GetHeightMatchInfo(barId) then
                MatchH.ClearHeightMatch(barId)
                LM.hasChanges = true
                RefreshLinkStates()
                LayoutActionRow()
                return
            end
            -- Element-declared dynamic block on NEW matches (see wmBtn above).
            if element and element.matchUnavailable then
                local why = element.matchUnavailable(barId)
                if why then
                    CludesUI.ShowWidgetTooltip(hmBtn, why)
                    return
                end
            end
            CancelPickMode()
            LM.pickMode = "heightMatch"
            LM.pickModeMover = handle
            ShowPickText("Click any element\nto match its height")
            FadeOverlayForSelectElement(true)
        end)

        atBtn:SetScript("OnClick", function()
            CludesUI.HideWidgetTooltip()
            if mod.IsMoverPosLocked(barId) then
                return
            end
            if GetAnchorInfo(barId) then
                ClearAnchorInfo(barId)
                -- Capture current screen position so Save & Exit persists it.
                -- Without this, the old cdmBarPositions (from when anchored)
                -- would be used on /reload, snapping the bar to the wrong spot.
                local barFrame = LM.GetBarFrame(barId)
                if barFrame then
                    local pt, _, rpt, bx, by = barFrame:GetPoint(1)
                    if pt then
                        pendingPositions[barId] = {
                            point = pt,
                            relPoint = rpt,
                            x = bx,
                            y = by,
                        }
                    end
                end
                LM.hasChanges = true
                RefreshAnchoredIdle()
                RefreshLinkStates()
                LayoutActionRow()
                if handles[barId] and handles[barId].RefreshAnchoredText then
                    handles[barId]:RefreshAnchoredText()
                end
                return
            end
            CancelPickMode()
            LM.pickMode = "anchorTo"
            LM.pickModeMover = handle
            ShowPickText("Click any element\nto anchor to it")
            FadeOverlayForSelectElement(true)
            LM.PointPicker.Begin(handle)
        end)

        gdBtn:SetScript("OnClick", function()
            CludesUI.HideWidgetTooltip()
            -- Build and show the grow direction dropdown
            if not LM.growDropdownFrame then
                LM.growDropdownFrame = CreateFrame("Frame", nil, LM.unlockFrame)
                LM.growDropdownFrame:SetFrameStrata("FULLSCREEN_DIALOG")
                LM.SetMoverOverlayLevel(LM.growDropdownFrame, 10)
                LM.growDropdownFrame:SetClampedToScreen(true)
                LM.growDropdownFrame:EnableMouse(true)
                -- Built once: background, border, the title and the divider under it.
                MenuPool.Chrome(LM.growDropdownFrame)
                local titleFS = LM.growDropdownFrame:CreateFontString(nil, "OVERLAY")
                CludesUI.PrimeFontShadow(titleFS, true)
                titleFS:SetFont(FONT_PATH, 10, "")
                titleFS:SetTextColor(1, 1, 1, 0.40)
                titleFS:SetJustifyH("LEFT")
                titleFS:SetPoint("TOPLEFT", LM.growDropdownFrame, "TOPLEFT", 10, -8)
                LM.growDropdownFrame._titleFS = titleFS
                local titleDiv = LM.growDropdownFrame:CreateTexture(nil, "ARTWORK")
                titleDiv:SetHeight(1)
                titleDiv:SetColorTexture(1, 1, 1, 0.10)
                titleDiv:SetPoint("TOPLEFT", LM.growDropdownFrame, "TOPLEFT", 1, -24)
                titleDiv:SetPoint("TOPRIGHT", LM.growDropdownFrame, "TOPRIGHT", -1, -24)
            end
            if not LM.growDropdownCatcher then
                LM.growDropdownCatcher = CreateFrame("Button", nil, LM.unlockFrame)
                LM.growDropdownCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
                LM.SetMoverOverlayLevel(LM.growDropdownCatcher, 9)
                LM.growDropdownCatcher:SetAllPoints(UIParent)
                LM.growDropdownCatcher._umCatcher = true -- not an element for the hover bar
                LM.growDropdownCatcher:RegisterForClicks("AnyUp")
                LM.growDropdownCatcher:SetScript("OnClick", function()
                    LM.growDropdownFrame:Hide()
                    LM.growDropdownCatcher:Hide()
                end)
            end

            local DD_ITEM_H = 24
            local DD_WIDTH = 160
            LM.growDropdownFrame:SetSize(DD_WIDTH, 10)
            LM.growDropdownFrame:ClearAllPoints()
            local scale = UIParent:GetEffectiveScale()
            local nowX, nowY = GetCursorPosition()
            nowX = nowX / scale
            nowY = nowY / scale - UIParent:GetHeight()
            LM.growDropdownFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", nowX, nowY)

            LM.growDropdownFrame._titleFS:SetText(CludesUI.L("Grow Direction"))
            local menuY = -27 -- first row, below the title and its divider

            -- Read orientation dynamically (not from closure) so the dropdown
            -- shows the correct options if orientation changed after mover creation.
            local vertical = false
            if barId:sub(1, 4) == "CDM_" then
                local cdm3 = CludesUI.Lite.GetAddon("CludesUICooldownManager", true)
                local cb3 = cdm3 and cdm3.db and cdm3.db.profile and cdm3.db.profile.cdmBars
                if cb3 and cb3.bars then
                    for _, b3 in ipairs(cb3.bars) do
                        if b3.key == barId:sub(5) then
                            vertical = b3.verticalOrientation == true
                            break
                        end
                    end
                end
            elseif barId == "ERB_TotemBar" then
                if CludesUI.GetTotemGrowDir then
                    local _, v3 = CludesUI.GetTotemGrowDir()
                    vertical = v3
                end
            elseif barId == "EABR_Reminders" then
                vertical = false -- the reminder row is horizontal only
            elseif barId:sub(1, 4) == "PAB_" then
                -- Player Aura Bars support vertical growth too -- read the bar's
                -- own current growDirection (same bridge the currentVal lookup below uses)
                -- to decide which pair of grow options this popup offers.
                local euf3 = CludesUI.Lite.GetAddon("CludesUIUnitFrames", true)
                local pabDir = (euf3 and euf3.GetGrowDirectionForBar and euf3:GetGrowDirectionForBar(barId))
                    or "LEFT"
                vertical = (pabDir == "UP" or pabDir == "DOWN" or pabDir == "CENTER_VERTICAL")
            else
                local eab3 = CludesUI.Lite.GetAddon("CludesUIActionBars", true)
                local s3 = eab3
                    and eab3.db
                    and eab3.db.profile
                    and eab3.db.profile.bars
                    and eab3.db.profile.bars[barId]
                if s3 then
                    vertical = (s3.orientation == "vertical")
                end
            end
            local growOptions = {}
            if barId:sub(1, 4) == "PAB_" then
                growOptions[#growOptions + 1] = { label = "Grow Centered Horizontal", val = "CENTER_HORIZONTAL" }
                growOptions[#growOptions + 1] = { label = "Grow Centered Vertical", val = "CENTER_VERTICAL" }
            else
                growOptions[#growOptions + 1] = { label = "Grow Centered", val = "CENTER" }
            end
            if vertical then
                growOptions[#growOptions + 1] = { label = "Grow Up", val = "UP" }
                growOptions[#growOptions + 1] = { label = "Grow Down", val = "DOWN" }
            else
                growOptions[#growOptions + 1] = { label = "Grow Left", val = "LEFT" }
                growOptions[#growOptions + 1] = { label = "Grow Right", val = "RIGHT" }
            end
            -- Read actual grow direction directly (GetBarGrowDir filters defaults)
            local currentVal = "CENTER"
            if barId:sub(1, 4) == "CDM_" then
                local cdm4 = CludesUI.Lite.GetAddon("CludesUICooldownManager", true)
                local cb4 = cdm4 and cdm4.db and cdm4.db.profile and cdm4.db.profile.cdmBars
                if cb4 and cb4.bars then
                    for _, b4 in ipairs(cb4.bars) do
                        if b4.key == barId:sub(5) then
                            currentVal = b4.growDirection or "CENTER"
                            break
                        end
                    end
                end
            elseif barId == "ERB_TotemBar" then
                -- Clamped read: a direction left over from the other orientation is
                -- never stored back, so the menu must resolve it the same way the
                -- layout does or it would highlight an option that is not offered.
                currentVal = CludesUI.GetTotemGrowDir and CludesUI.GetTotemGrowDir()
                    or (vertical and "DOWN" or "RIGHT")
            elseif barId == "EABR_Reminders" then
                if CludesUI.GetAuraBuffGrowDir then
                    currentVal = CludesUI.GetAuraBuffGrowDir()
                end
            elseif barId:sub(1, 4) == "PAB_" then
                local euf4 = CludesUI.Lite.GetAddon("CludesUIUnitFrames", true)
                currentVal = (euf4 and euf4.GetGrowDirectionForBar and euf4:GetGrowDirectionForBar(barId))
                    or "LEFT"
            else
                local eab4 = CludesUI.Lite.GetAddon("CludesUIActionBars", true)
                local s4 = eab4
                    and eab4.db
                    and eab4.db.profile
                    and eab4.db.profile.bars
                    and eab4.db.profile.bars[barId]
                if s4 then
                    currentVal = (s4.growDirection or "up"):upper()
                end
            end

            MenuPool.Begin(LM.growDropdownFrame, true)
            for _, record in ipairs(growOptions) do
                local isDisabled = false
                local isCurrent = (record.val == currentVal)

                local menuItem, highlight, labelFS = MenuPool.Item(LM.growDropdownFrame, menuY, DD_ITEM_H)
                labelFS:SetText(CludesUI.L(record.label))
                if isDisabled then
                    labelFS:SetTextColor(0.4, 0.4, 0.4, 0.5)
                    local tipText = "Deselect a grow direction to return to centered"
                    menuItem:SetScript("OnEnter", function()
                        CludesUI.ShowWidgetTooltip(menuItem, tipText)
                    end)
                    menuItem:SetScript("OnLeave", function()
                        CludesUI.HideWidgetTooltip()
                    end)
                else
                    local baseR, baseG, baseB, baseA =
                        isCurrent and 1 or 0.75,
                        isCurrent and 0.7 or 0.75,
                        isCurrent and 0.3 or 0.75,
                        isCurrent and 0.9 or 0.9
                    labelFS:SetTextColor(baseR, baseG, baseB, baseA)
                    menuItem:SetScript("OnEnter", function()
                        highlight:SetColorTexture(1, 1, 1, 0.08)
                        labelFS:SetTextColor(1, 1, 1, 1)
                    end)
                    menuItem:SetScript("OnLeave", function()
                        highlight:SetColorTexture(1, 1, 1, 0)
                        labelFS:SetTextColor(baseR, baseG, baseB, baseA)
                    end)
                    local sideVal = record.val
                    menuItem:SetScript("OnClick", function()
                        LM.growDropdownFrame:Hide()
                        LM.growDropdownCatcher:Hide()

                        -- If already on this direction, just close the popup
                        if sideVal == currentVal then
                            return
                        end

                        CludesUI._unlockSetGrowDirection(barId, sideVal)
                        RefreshLinkStates()
                    end)
                end
                menuY = menuY - DD_ITEM_H
            end
            MenuPool.End(LM.growDropdownFrame)

            LM.growDropdownFrame:SetHeight(-menuY + 4)
            LM.growDropdownFrame:Show()
            LM.growDropdownCatcher:Show()
        end)
        gdBtn:SetScript("OnEnter", function(self)
            BtnEnter(self, gdFS, "grow")
        end)
        gdBtn:SetScript("OnLeave", function(self)
            BtnLeave(self, gdFS, "grow")
        end)

        -- Helper: update coordinate readout from mover's current position
        function handle:UpdateCoordText()
            local fontStr = self._coordFS
            if not fontStr then
                return
            end
            local barKey = self._barKey
            local PPi = CludesUI and CludesUI.PP
            local toPx = (PPi and PPi.ToPixels) or round
            -- STORED value first for unanchored CENTER/CENTER elements when not
            -- mid-drag: an odd-pixel-dimension frame's physical center legitimately
            -- sits on a half pixel (whole-pixel edges force it), so a live-derived
            -- readout can never echo the user's own typed value back (-368 reads as
            -- -367/-369 depending on rounding). The stored value is what the appliers
            -- round-trip, so it's the truth to display. Live geometry is only authoritative while dragging (store not yet updated).
            if not self._dragging then
                local anchorInfo = GetAnchorInfo(barKey)
                if not (anchorInfo and anchorInfo.target) then
                    local place = pendingPositions[barKey]
                    if type(place) ~= "table" or place._anchored or not place.point then
                        local element = registeredElements[barKey]
                        place = element and element.loadPosition and element.loadPosition(barKey) or nil
                        if not place then
                            place = LoadBarPosition(barKey)
                        end
                    end
                    if
                        type(place) == "table"
                        and place.point == "CENTER"
                        and (place.relPoint or "CENTER") == "CENTER"
                        and place.x
                        and place.y
                    then
                        -- Parity-aware like the live branch below (odd dims store a half-pixel center).
                        local scrollBar = LM.GetBarFrame(barKey)
                        local c2pS = PPi and PPi.CenterToPixels
                        local px, py
                        if c2pS and scrollBar then
                            px = c2pS(place.x, scrollBar:GetWidth(), scrollBar:GetEffectiveScale())
                            py = c2pS(place.y, scrollBar:GetHeight(), scrollBar:GetEffectiveScale())
                        else
                            px, py = toPx(place.x), toPx(place.y)
                        end
                        fontStr:SetText(format("%.0f, %.0f", px, py))
                        fontStr:Show()
                        return
                    end
                end
            end
            -- Derive from the bar's LIVE geometry using the exact same formula and
            -- physical-pixel units as the cog X/Y boxes, so the overlay always agrees
            -- with the cog and updates immediately (no waiting for a commit).
            -- Parity-aware (CenterToPixels): odd-pixel dims center on a half pixel,
            -- which plain ToPixels reads back one high on this live path.
            local b = LM.GetBarFrame(barKey)
            if b then
                local boxLeft, bR = b:GetLeft(), b:GetRight()
                local bT, bB = b:GetTop(), b:GetBottom()
                if boxLeft and bR and bT and bB then
                    local scaleRatio = b:GetEffectiveScale() / UIParent:GetEffectiveScale()
                    local sw = UIParent:GetWidth()
                    local sh = UIParent:GetHeight()
                    local liveCX = ((boxLeft + bR) * 0.5 * scaleRatio) - sw * 0.5
                    local liveCY = ((bT + bB) * 0.5 * scaleRatio) - sh * 0.5
                    local c2p = PPi and PPi.CenterToPixels
                    fontStr:SetText(
                        format(
                            "%.0f, %.0f",
                            c2p and c2p(liveCX, b:GetWidth(), b:GetEffectiveScale()) or toPx(liveCX),
                            c2p and c2p(liveCY, b:GetHeight(), b:GetEffectiveScale()) or toPx(liveCY)
                        )
                    )
                    fontStr:Show()
                    return
                end
            end
            -- Fallback (frameless elements): saved CENTER position, same pixel units.
            local element = registeredElements[barKey]
            local place = element and element.loadPosition and element.loadPosition(barKey)
            if not place then
                place = LoadBarPosition(barKey)
            end
            if place and place.x and place.y then
                fontStr:SetText(format("%.0f, %.0f", toPx(place.x), toPx(place.y)))
                fontStr:Show()
                return
            end
            -- Last resort: derive from mover bounds.
            local l, r, t, b2 = self:GetLeft(), self:GetRight(), self:GetTop(), self:GetBottom()
            if not l or not t then
                fontStr:Hide()
                return
            end
            local screenW = UIParent:GetWidth()
            local screenH = UIParent:GetHeight()
            fontStr:SetText(
                format(
                    "%.0f, %.0f",
                    toPx(((l + r) * 0.5) - screenW * 0.5),
                    toPx(((t + b2) * 0.5) - screenH * 0.5)
                )
            )
            fontStr:Show()
        end

        handle._barKey = barId
        handle:SetAlpha(LM.darkOverlaysEnabled and 1 or MOVER_ALPHA)

        -- Initialize anchored text and link states, then apply idle state
        RefreshAnchoredIdle()
        RefreshLinkStates()
        ApplyHoverState(0)

        -- Sync size/position to the real bar (or registered element)
        function handle:Sync()
            -- Temporarily hidden for this unlock session (Shift+Right Click). Stay
            -- hidden until unlock mode is re-entered, which clears the flag. Every
            -- re-sync path (retry ticker, combat resume, open fade-in loops) must
            -- honor this and keep the overlay hidden.
            if self._tempHidden then
                self:Hide()
                return
            end
            local barKey = self._barKey
            local b = LM.GetBarFrame(barKey)
            local element = registeredElements[barKey]

            -- Re-read the element's moverBg tint: movers persist for the session
            -- while elements re-register with STATE-DEPENDENT tints (CDM's
            -- Additional Bar Offset marker), so a stale CreateMover-time color
            -- would stick until /reload. Change-guarded repaint.
            do
                local bgTint = element and element.moverBg
                local nr = bgTint and bgTint.r or 0.075
                local ng = bgTint and bgTint.g or 0.113
                local nb = bgTint and bgTint.b or 0.141
                if self._bgR ~= nr or self._bgG ~= ng or self._bgB ~= nb then
                    self._bgR, self._bgG, self._bgB = nr, ng, nb
                    if self._bg and LM.darkOverlaysEnabled then
                        self._bg:SetColorTexture(nr, ng, nb, 0.95)
                    end
                end
            end

            -- Stale/intentionally-hidden registrations (e.g. a deleted CDM tracking bar
            -- whose TBB_<idx> element is never unregistered, or a grouped non-anchor
            -- bar) must NOT be shown. Mirrors the CreateMover guard so blanket
            -- `for _, m in pairs(movers) do m:Sync() end` loops can't re-show a mover
            -- CreateMover intentionally hid. Action bars resolve elem == nil (no-op); isHidden is read live, so an un-hidden element still syncs.
            if
                element
                and (
                    (element.isHidden and element.isHidden())
                    or (element.isAnchored and element.isAnchored() and not element.keepMoverWhenAnchored)
                )
            then
                self:Hide()
                return
            end

            -- For registered elements without a live frame, use getSize + loadPosition
            if not b and element then
                local wid, hgt = 100, 30
                local centerYOff = 0
                if element.getSize then
                    local gw, gh, gyOff = element.getSize(barKey)
                    wid, hgt = gw, gh
                    centerYOff = gyOff or 0
                end
                if wid < 10 then
                    wid = 100
                end
                if hgt < 10 then
                    hgt = 30
                end
                realW, realH = wid, hgt
                self:SetSize(wid, hgt)
                if self._label then
                    self._label:SetWidth(wid * 0.95)
                end
                local place = element.loadPosition and element.loadPosition(barKey)
                if place then
                    self:ClearAllPoints()
                    self:SetPoint(
                        place.point,
                        UIParent,
                        place.relPoint or place.point,
                        place.x,
                        (place.y or 0) + centerYOff
                    )
                else
                    self:ClearAllPoints()
                    self:SetPoint("CENTER", UIParent, "CENTER", 0, centerYOff)
                end
                self:Show()
                ApplyHoverState(hoverState)
                return
            end

            if not b then
                self:Hide()
                return
            end
            -- Show mover even for hidden bars (mouseover/alwaysHidden) so user can reposition
            -- Only skip if the bar frame truly doesn't exist.
            -- A bar still on a follow anchor from before the session (a Blizzard
            -- Style cast bar under its frame's aura stack) reports a secret rect:
            -- re-apply its anchor now -- the follow provider is inert in unlock
            -- mode, so that places it absolutely -- and sync from the plain rect.
            -- If the rect has not resolved yet, sync again next frame.
            if RectSecret(b) then
                if CludesUI.ReapplyOwnAnchor then
                    CludesUI.ReapplyOwnAnchor(barKey)
                end
                if RectSecret(b) then
                    self:Hide()
                    local num = self._secretResync or 0
                    if num < 2 then
                        self._secretResync = num + 1
                        C_Timer.After(0, function()
                            self:Sync()
                        end)
                    end
                    return
                end
            end
            self._secretResync = nil
            local s = b:GetEffectiveScale()
            local uiZoom = UIParent:GetEffectiveScale()
            local wid, hgt
            local elemScale = s / uiZoom
            -- Visual insets (optional, e.g. a Blizzard Style unit frame whose stock
            -- box carries transparent padding round its art): the mover outlines
            -- the rect inside them. UIParent units.
            local il, ir, entry, ib = 0, 0, 0, 0
            if element and element.getInsets then
                local l, r, t, bt = element.getInsets(barKey)
                if l then
                    il, ir, entry, ib =
                        l * elemScale, (r or 0) * elemScale, (t or 0) * elemScale, (bt or 0) * elemScale
                end
            end
            -- Read size directly from the bar frame. Since the mover is anchored
            -- to the bar, we need the size in the mover's coordinate space.
            -- elemScale converts from bar space to UIParent (mover parent) space.
            wid = (b:GetWidth() or 50) * elemScale - il - ir
            hgt = (b:GetHeight() or 50) * elemScale - entry - ib
            -- For action bars, compute visual size from button grid (accounts for
            -- shape overrides, padding, and per-button scale)
            -- Only use this as a fallback when the frame has no size yet (first load).
            if wid < 10 or hgt < 10 then
                local abW, abH = GetActionBarVisualSize(barKey)
                if abW and abH then
                    wid, hgt = abW, abH
                end
            end
            local isTinyAnchor = (wid < 10)
            local centerYOff = 0
            if isTinyAnchor then
                -- Frame exists but has no size yet -- use getSize fallback
                if element and element.getSize then
                    local gw, gh, gyOff = element.getSize(barKey)
                    wid, hgt = gw, gh
                    centerYOff = gyOff or 0
                end
            end
            -- Extend the overlay downward to wrap an element's below-frame extra
            -- (e.g. the boss castbar). Inflating h here flows into SetSize and the
            -- center math below, keeping the top pinned and growing the box down.
            if element and element.getBottomExtra then
                hgt = hgt + (element.getBottomExtra(barKey) or 0) * elemScale
            end
            realW, realH = wid, hgt
            self:SetSize(wid, hgt)
            if self._label then
                self._label:SetWidth(wid * 0.95)
            end

            -- Position: convert bar's screen position to UIParent-relative
            -- Center the mover on the bar's visual center for pixel-perfect alignment.
            local boxLeft = b:GetLeft()
            local bT = b:GetTop()
            if boxLeft and bT then
                local Pix = CludesUI and CludesUI.PP
                if isTinyAnchor and element then
                    -- Dynamic bar (1x1 when empty): anchor is CENTER-positioned.
                    -- Compute TOPLEFT from GetCenter() to avoid layout-flush timing
                    -- issues where GetLeft()/GetTop() still reflect the old 1x1 size.
                    local cx, cy
                    local bCX, bCY = b:GetCenter()
                    if bCX and bCY then
                        cx = bCX * s / uiZoom + (il - ir) * 0.5 - wid * 0.5
                        cy = bCY * s / uiZoom + (ib - entry) * 0.5 - UIParent:GetHeight() + hgt * 0.5 + centerYOff
                    elseif boxLeft and bT then
                        cx = boxLeft * s / uiZoom
                        cy = bT * s / uiZoom - UIParent:GetHeight()
                    else
                        -- No screen position yet -- fall back to saved pos
                        local place = element.loadPosition and element.loadPosition(barKey)
                        if place and place.point == "CENTER" then
                            local uiW = UIParent:GetWidth()
                            local uiH = UIParent:GetHeight()
                            cx = uiW * 0.5 + (place.x or 0) - wid * 0.5
                            cy = -(uiH * 0.5) + (place.y or 0) + hgt * 0.5
                        else
                            cx = 0
                            cy = -UIParent:GetHeight() * 0.5
                        end
                    end
                    if Pix then
                        cx = Pix.Scale(cx)
                        cy = Pix.Scale(cy)
                    end
                    self:ClearAllPoints()
                    self:SetPoint("TOPLEFT", UIParent, "TOPLEFT", cx, cy)
                    moverCX, moverCY = cx + wid * 0.5, cy - hgt * 0.5
                else
                    -- Anchor mover directly to the bar frame so both share the
                    -- exact same screen position with zero coordinate math.
                    CludesUI._unlockAttachMover(self, b, barKey, il, entry)
                    -- Compute moverCX/moverCY for snap/drag logic
                    local cx = boxLeft * elemScale + il
                    local cy = bT * elemScale - UIParent:GetHeight() - entry
                    moverCX, moverCY = cx + wid * 0.5, cy - hgt * 0.5
                end
            else
                -- Bar has no position yet (not shown), place at center
                self:ClearAllPoints()
                self:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
                moverCX, moverCY = 0, -UIParent:GetHeight() * 0.5
            end
            self:Show()
            -- Re-apply hover state so mover size reflects current animation state
            ApplyHoverState(hoverState)
        end

        -- Lightweight size-only sync: updates baseW/baseH and re-applies hover state
        -- without repositioning the mover. Used after width/height match changes.
        function handle:SyncSize()
            local barKey = self._barKey
            local element = registeredElements[barKey]
            if element and element.getSize then
                local gw, gh = element.getSize(barKey)
                -- Use the raw value from getSize without rounding: the layout function
                -- (LayoutCDMBar, LayoutBar, etc.) already snapped dimensions to the
                -- physical pixel grid. Re-rounding to the nearest integer shifts values
                -- off the pixel grid when PP.mult != 1.0 (e.g. 214.4 -> 214 instead of staying 214.4, exactly 402 physical pixels at mult=0.533).
                if gw and gw > 0 then
                    realW = gw
                end
                if gh and gh > 0 then
                    realH = gh
                end
            else
                local b = LM.GetBarFrame(barKey)
                if b then
                    local s = b:GetEffectiveScale()
                    local uiZoom = UIParent:GetEffectiveScale()
                    realW = (b:GetWidth() or realW) * s / uiZoom
                    realH = (b:GetHeight() or realH) * s / uiZoom
                end
            end
            -- moverCX/moverCY are already updated by RecenterBarAnchor (called before
            -- SyncSize). Do NOT recompute from GetLeft/GetTop here -- the mover may
            -- still be anchored to the bar's old TOPLEFT position at this point, which
            -- would produce a wrong center and cause a one-frame visual jump.
            ApplyHoverState(hoverState)
            -- Re-anchor to bar for pixel-perfect alignment after size change
            self:ReanchorToBar()
        end

        -- Drag handlers: manual cursor-based positioning for live snap + live bar movement
        handle:SetScript("OnDragStart", function(self)
            if InCombatLockdown() then
                return
            end
            if LM.pickMode == "pointAnchor" then
                return
            end
            if LM.PointPicker.Active() then
                CancelPickMode()
            end
            -- Position-locked: the module's anchor option owns this bar's position
            if mod.IsMoverPosLocked(self._barKey) then
                SelectMover(self)
                return
            end
            -- Anchored bars can be dragged -- the offset from parent is updated on drop
            SelectMover(self)
            self:SetAlpha(LM.darkOverlaysEnabled and 1 or MOVER_DRAG)
            self._dragging = true
            self._hoverPending = false -- cancel pending expand animation
            self._shiftAxis = nil -- nil = not locked, "X" or "Y" once determined
            -- Cache centerYOff for tiny-anchor elements (used in OnUpdate and OnDragStop)
            local element = registeredElements[self._barKey]
            if element and element.getSize then
                local _, _, gyOff = element.getSize(self._barKey)
                self._dragCenterYOff = gyOff or 0
            else
                self._dragCenterYOff = 0
            end
            -- Visual insets (see Sync): the bar's box sits outside the mover by
            -- these, UIParent units. The bar is placed from the mover's rect plus
            -- them, and the mover re-attaches inside them.
            self._dragIL, self._dragIR, self._dragIT, self._dragIB = 0, 0, 0, 0
            if element and element.getInsets then
                local bIn = LM.GetBarFrame(self._barKey)
                local l, r, t, bt = element.getInsets(self._barKey)
                if l and bIn then
                    local es = bIn:GetEffectiveScale() / UIParent:GetEffectiveScale()
                    self._dragIL, self._dragIR = l * es, (r or 0) * es
                    self._dragIT, self._dragIB = (t or 0) * es, (bt or 0) * es
                end
            end
            -- Snap links away instantly during drag (no animation -- it fights with drag positioning)
            hoverState = 0
            hoverTarget = 0
            animFrame:SetScript("OnUpdate", nil)
            ApplyHoverState(0)

            -- Record offset from cursor to mover center at drag start
            -- Use stored moverCX/moverCY (base-size center) so expanding/collapsing
            -- hover state does not corrupt the offset when dragging from a link button
            local scale = UIParent:GetEffectiveScale()
            local nowX, nowY = GetCursorPosition()
            nowX = nowX / scale
            nowY = nowY / scale
            local cx = (moverCX ~= 0 or moverCY ~= 0) and moverCX or (self:GetLeft() + self:GetRight()) / 2
            local cy = (moverCX ~= 0 or moverCY ~= 0) and moverCY
                or (self:GetTop() + self:GetBottom()) / 2 - UIParent:GetHeight()
            cy = cy + UIParent:GetHeight() -- convert back to screen-space Y for drag math
            self._dragOffX = cx - nowX
            self._dragOffY = cy - nowY
            self._dragStartCX = cx
            self._dragStartCY = cy

            -- Snap mover to cursor immediately so there's no one-frame lag
            local halfW0 = self:GetWidth() / 2
            local halfH0 = self:GetHeight() / 2
            self._dragHalfW = halfW0
            self._dragHalfH = halfH0
            local snap0X, snap0Y = SnapPosition(self._barKey, cx, cy, halfW0, halfH0)
            local bar0 = LM.GetBarFrame(self._barKey)
            if bar0 and not InCombatLockdown() then
                local uiS0 = UIParent:GetEffectiveScale()
                local bS0 = bar0:GetEffectiveScale()
                local ratio0 = uiS0 / bS0
                local barHW0 = (bar0:GetWidth() or 0) * 0.5
                local barHH0 = (bar0:GetHeight() or 0) * 0.5
                local barX0 = (snap0X + (self._dragIR - self._dragIL) * 0.5) * ratio0 - barHW0
                local barY0 = (
                    snap0Y
                    + (self._dragIT - self._dragIB) * 0.5
                    - UIParent:GetHeight()
                    - (self._dragCenterYOff or 0)
                )
                        * ratio0
                    + barHH0
                local PPd = CludesUI and CludesUI.PP
                if PPd and PPd.SnapForES then
                    local lockX, lockY = CludesUI._snapAxisLocked()
                    if not lockX then
                        barX0 = PPd.SnapForES(barX0, bS0)
                    end
                    if not lockY then
                        barY0 = PPd.SnapForES(barY0, bS0)
                    end
                end
                pcall(function()
                    CludesUI.ClearFramePoints(bar0)
                    CludesUI.SetFramePoint(bar0, "TOPLEFT", UIParent, "TOPLEFT", barX0, barY0)
                end)
                -- Element follow-up to the one-point placement above (an element
                -- whose rect needs a second anchor -- main chat's size corner --
                -- restores it here), before the collapsed rect ever renders.
                if element and element.onLiveMove then
                    pcall(element.onLiveMove, self._barKey)
                end
                self:ClearAllPoints()
                if element and element.detachedMover then
                    -- The bar refuses dependents (see AttachMoverToBar): same spot, absolute.
                    self:SetPoint(
                        "TOPLEFT",
                        UIParent,
                        "TOPLEFT",
                        snap0X - halfW0,
                        snap0Y + halfH0 - UIParent:GetHeight()
                    )
                else
                    self:SetPoint("TOPLEFT", bar0, "TOPLEFT", self._dragIL, -self._dragIT)
                end
            else
                local f0X = snap0X - halfW0
                local f0Y = snap0Y + halfH0 - UIParent:GetHeight()
                self:ClearAllPoints()
                self:SetPoint("TOPLEFT", UIParent, "TOPLEFT", f0X, f0Y)
            end

            -- OnUpdate: move mover + real bar to cursor position with snap
            self:SetScript("OnUpdate", function(s)
                local uiScale = UIParent:GetEffectiveScale()
                local curX, curY = GetCursorPosition()
                curX = curX / uiScale
                curY = curY / uiScale

                -- Raw center = cursor + offset
                local rawCX = curX + s._dragOffX
                local rawCY = curY + s._dragOffY

                -- Shift-axis-lock: constrain to one axis based on initial drag direction
                if IsShiftKeyDown() then
                    if not s._shiftAxis then
                        local adx = abs(rawCX - s._dragStartCX)
                        local ady = abs(rawCY - s._dragStartCY)
                        -- Determine axis once movement exceeds 3px threshold
                        if adx > 3 or ady > 3 then
                            s._shiftAxis = (adx >= ady) and "X" or "Y"
                        end
                    end
                    if s._shiftAxis == "X" then
                        rawCY = s._dragStartCY
                    elseif s._shiftAxis == "Y" then
                        rawCX = s._dragStartCX
                    end
                else
                    s._shiftAxis = nil -- release shift = unlock axis
                end

                local halfW = s._dragHalfW
                local halfH = s._dragHalfH

                -- Apply snap
                local snapCX, snapCY = SnapPosition(s._barKey, rawCX, rawCY, halfW, halfH)

                -- Clamp to screen edges
                local screenW = UIParent:GetWidth()
                local screenH = UIParent:GetHeight()
                snapCX = max(halfW, min(screenW - halfW, snapCX))
                snapCY = max(halfH, min(screenH - halfH, snapCY))

                -- Move the real bar live first, then anchor the mover to it so
                -- the overlay stays pixel-perfect regardless of scale differences.
                local barFrame = LM.GetBarFrame(s._barKey)
                if barFrame and not InCombatLockdown() then
                    local uiZoom = UIParent:GetEffectiveScale()
                    local bS = barFrame:GetEffectiveScale()
                    local scaleRatio = uiZoom / bS
                    -- bar:GetWidth/Height are in the bar's local (unscaled) space.
                    -- Convert snapCX/snapCY (UIParent screen coords) into the bar's
                    -- local space first, then subtract the unscaled half-size to get TOPLEFT.
                    local barHW = (barFrame:GetWidth() or 0) * 0.5
                    local barHH = (barFrame:GetHeight() or 0) * 0.5
                    local barX = (snapCX + (s._dragIR - s._dragIL) * 0.5) * scaleRatio - barHW
                    local barY = (
                        snapCY
                        + (s._dragIT - s._dragIB) * 0.5
                        - UIParent:GetHeight()
                        - (s._dragCenterYOff or 0)
                    )
                            * scaleRatio
                        + barHH
                    local PPd = CludesUI and CludesUI.PP
                    if PPd and PPd.SnapForES then
                        -- When an edge snap is active, skip SnapForES on that axis.
                        -- The unsnapped barX/barY already matches the target's edge
                        -- exactly. Re-snapping would shift it to a different pixel.
                        local lockX, lockY = CludesUI._snapAxisLocked()
                        if not lockX then
                            barX = PPd.SnapForES(barX, bS)
                        end
                        if not lockY then
                            barY = PPd.SnapForES(barY, bS)
                        end
                    end
                    pcall(function()
                        CludesUI.ClearFramePoints(barFrame)
                        CludesUI.SetFramePoint(barFrame, "TOPLEFT", UIParent, "TOPLEFT", barX, barY)
                    end)
                    -- Anchor mover directly to bar TOPLEFT for pixel-perfect overlay
                    s:ClearAllPoints()
                    local dElem = registeredElements[s._barKey]
                    if dElem and dElem.detachedMover then
                        -- The bar refuses dependents (see AttachMoverToBar): same spot, absolute.
                        s:SetPoint(
                            "TOPLEFT",
                            UIParent,
                            "TOPLEFT",
                            snapCX - halfW,
                            snapCY + halfH - UIParent:GetHeight()
                        )
                    else
                        s:SetPoint("TOPLEFT", barFrame, "TOPLEFT", s._dragIL, -s._dragIT)
                    end
                else
                    -- No live bar -- position mover in UIParent space
                    local finalX = snapCX - halfW
                    local finalY = snapCY + halfH - UIParent:GetHeight()
                    s:ClearAllPoints()
                    s:SetPoint("TOPLEFT", UIParent, "TOPLEFT", finalX, finalY)
                end

                -- Element follow-up to the placement above, BEFORE the anchor chain
                -- reads this frame's rect: an element whose rect needs a second
                -- anchor (main chat's size corner) restores it here, so dependents
                -- anchor against the true rect on the same tick.
                local element = registeredElements[s._barKey]
                if element and element.onLiveMove then
                    pcall(element.onLiveMove, s._barKey)
                end

                -- Show live coordinates during drag (only on elements >= 20px tall).
                -- Physical-pixel counts, matching the cog X/Y boxes and the overlay.
                if s._coordFS and s:GetHeight() >= 12 then
                    local PPc = CludesUI and CludesUI.PP
                    local toPx = (PPc and PPc.ToPixels) or round
                    s._coordFS:SetText(
                        format("%.0f, %.0f", toPx(snapCX - screenW * 0.5), toPx(snapCY - screenH * 0.5))
                    )
                    s._coordFS:Show()
                end

                -- Anchor chain: propagate recursively down the chain
                local anchorDB = GetAnchorDB()
                if anchorDB then
                    LM.PropagateAnchorChain(s._barKey)
                end

                ShowAlignmentGuides(s._barKey)

                -- Safety net: if mouse button was released outside any button frame
                -- (e.g. during a link-initiated drag), stop the drag now.
                if not IsMouseButtonDown("LeftButton") then
                    local stopScript = s:GetScript("OnDragStop")
                    if stopScript then
                        stopScript(s)
                    end
                end
            end)
        end)

        handle:SetScript("OnDragStop", function(self)
            self:SetScript("OnUpdate", nil)
            self._dragging = false
            _mouseHeld = false
            self:SetAlpha(LM.darkOverlaysEnabled and 1 or MOVER_HOVER)
            -- Convert back to CENTER anchor so hover-expand stays symmetric
            local mL, mR = self:GetLeft(), self:GetRight()
            local mT, mB = self:GetTop(), self:GetBottom()
            if mL and mR and mT and mB then
                local cx = (mL + mR) * 0.5
                local cy = (mT + mB) * 0.5 - UIParent:GetHeight()
                self:ClearAllPoints()
                self:SetPoint("CENTER", UIParent, "TOPLEFT", cx, cy)
                moverCX, moverCY = cx, cy
            end
            -- Update coords to final position (stays visible if selected or coords-always-on)
            if self._selected and self.UpdateCoordText then
                self:UpdateCoordText()
            elseif LM.coordsEnabled and self.UpdateCoordText then
                self:UpdateCoordText()
            else
                self._coordFS:Hide()
            end
            HideAllGuidesAndHighlight()
            -- Re-show links after drag if still hovered
            if self:IsMouseOver() then
                if self._showOverlayText then
                    self._showOverlayText()
                end
            end
            -- Re-anchor toolbar in case mover moved near/away from screen top
            if self._anchorToolbar then
                self._anchorToolbar()
            end

            -- Check if the mover actually moved (avoids false dirty flag from
            -- click-and-hold without movement)
            local cxL, cxR = self:GetLeft(), self:GetRight()
            local cyT, cyB = self:GetTop(), self:GetBottom()
            if not cxL or not cxR or not cyT or not cyB then
                return
            end
            local cx = (cxL + cxR) / 2
            local cy = (cyT + cyB) / 2
            local startCX = self._dragStartCX or cx
            local startCY = self._dragStartCY or cy
            local moved = (abs(cx - startCX) > 0.5) or (abs(cy - startCY) > 0.5)
            if not moved then
                return
            end

            -- Store position in pending table (NOT saved until user clicks Save & Exit)

            local barFrame = LM.GetBarFrame(self._barKey)
            if not InCombatLockdown() then
                local uiZoom = UIParent:GetEffectiveScale()

                -- If this bar is anchored, the offset was already updated live during drag.
                -- No need to recompute here -- using mover screen coords would introduce
                -- sub-pixel drift vs the cursor-based offset set in OnUpdate.

                local dragCYOff = self._dragCenterYOff or 0
                if barFrame then
                    -- Read the bar's actual TOPLEFT from its current SetPoint rather
                    -- than recomputing from the mover center. The OnUpdate already
                    -- positioned the bar with exact edge alignment (no SnapForES drift).
                    local _, _, _, barX, barY = barFrame:GetPoint(1)
                    if not barX or not barY then
                        local bS = barFrame:GetEffectiveScale()
                        local scaleRatio = uiZoom / bS
                        local barHW = (barFrame:GetWidth() or 0) * 0.5
                        local barHH = (barFrame:GetHeight() or 0) * 0.5
                        barX = cx * scaleRatio - barHW
                        barY = (cy - UIParent:GetHeight() - dragCYOff) * scaleRatio + barHH
                        local PPd = CludesUI and CludesUI.PP
                        if PPd and PPd.SnapForES then
                            barX = PPd.SnapForES(barX, bS)
                            barY = PPd.SnapForES(barY, bS)
                        end
                    end
                    pendingPositions[self._barKey] = {
                        point = "TOPLEFT",
                        relPoint = "TOPLEFT",
                        x = barX,
                        y = barY,
                    }
                else
                    -- No live frame (e.g. unit frame not spawned) -- store in UIParent coords
                    local halfW = (realW > 0 and realW or self:GetWidth()) / 2
                    local halfH = (realH > 0 and realH or self:GetHeight()) / 2
                    pendingPositions[self._barKey] = {
                        point = "TOPLEFT",
                        relPoint = "TOPLEFT",
                        x = cx - halfW,
                        y = cy + halfH - UIParent:GetHeight() - dragCYOff,
                    }
                end
                LM.hasChanges = true
            end

            -- If anchored to a parent, update the stored offset so the parent's future
            -- moves don't snap this child back. Read actual child edges directly
            -- instead of computing from center+half to avoid float dust from (top+bottom)/2 - height/2 != bottom.
            local anchorInfo = GetAnchorInfo(self._barKey)
            if anchorInfo and anchorInfo.mode == "POINT" then
                local ox, oy = mod.PointAnchors.Capture(self._barKey, anchorInfo)
                if ox then
                    anchorInfo.offsetX, anchorInfo.offsetY = ox, oy
                    LM.ApplyAnchorPosition(self._barKey, anchorInfo.target, nil, true)
                end
            elseif anchorInfo then
                local targetBar = LM.GetBarFrame(anchorInfo.target)
                if targetBar then
                    local tS = targetBar:GetEffectiveScale()
                    local uiZoom = UIParent:GetEffectiveScale()
                    local tL = targetBar:GetLeft()
                    local tR = targetBar:GetRight()
                    local tT = targetBar:GetTop()
                    local tB = targetBar:GetBottom()
                    if tL and tR and tT and tB then
                        tL = tL * tS / uiZoom
                        tR = tR * tS / uiZoom
                        tT = tT * tS / uiZoom
                        tB = tB * tS / uiZoom
                        local tCX = (tL + tR) / 2
                        local tCY = (tT + tB) / 2
                        -- Growth-edge extent and followed edges: the same edges the
                        -- apply measures from. A follow frame's live bottom is plain
                        -- here (unlock mode never runs under aura restriction).
                        if CludesUI._GetAnchorTargetExtent then
                            local ext = CludesUI._GetAnchorTargetExtent(anchorInfo.target, anchorInfo.side)
                            if ext then
                                if anchorInfo.side == "TOP" then
                                    tT = ext
                                elseif anchorInfo.side == "BOTTOM" then
                                    tB = ext
                                elseif anchorInfo.side == "LEFT" then
                                    tL = ext
                                elseif anchorInfo.side == "RIGHT" then
                                    tR = ext
                                end
                            end
                        end
                        if anchorInfo.side == "BOTTOM" and CludesUI._GetAnchorFollowFrame then
                            local fol = CludesUI._GetAnchorFollowFrame(self._barKey, anchorInfo.target, anchorInfo.side)
                            local fB = fol and fol:GetBottom()
                            if not (issecretvalue and issecretvalue(fB)) and fB then
                                tB = fB * fol:GetEffectiveScale() / uiZoom
                            end
                        end
                        -- Read child edges from the actual bar frame for accuracy
                        local childBar = LM.GetBarFrame(self._barKey)
                        local cL, cR, cT, cB
                        local cRatio = 1 -- mover coords are already UIParent units
                        if childBar and childBar:GetLeft() then
                            local cS = childBar:GetEffectiveScale()
                            cRatio = cS / uiZoom
                            cL = childBar:GetLeft() * cS / uiZoom
                            cR = childBar:GetRight() * cS / uiZoom
                            cT = childBar:GetTop() * cS / uiZoom
                            cB = childBar:GetBottom() * cS / uiZoom
                        else
                            local halfW = realW > 0 and realW / 2 or (self:GetWidth() / 2)
                            local halfH = realH > 0 and realH / 2 or (self:GetHeight() / 2)
                            cL = cx - halfW
                            cR = cx + halfW
                            cT = cy + halfH
                            cB = cy - halfH
                        end
                        -- The live rect carries the element's own extra offset (the raid
                        -- container's per-tier offset), which every anchored apply folds in
                        -- again: rebase to the base rect before storing the offsets, like
                        -- the cog's screen-edge link does. The getter is in frame units.
                        local exX, exY = CludesUI._ExtraAnchorOffset(self._barKey)
                        exX, exY = exX * cRatio, exY * cRatio
                        cL, cR = cL - exX, cR - exX
                        cT, cB = cT - exY, cB - exY
                        local cCX = (cL + cR) / 2
                        local cCY = (cT + cB) / 2
                        local sd = anchorInfo.side
                        if sd == "LEFT" then
                            anchorInfo.offsetX = cR - tL
                            anchorInfo.offsetY = cCY - tCY
                        elseif sd == "RIGHT" then
                            anchorInfo.offsetX = cL - tR
                            anchorInfo.offsetY = cCY - tCY
                        elseif sd == "TOP" then
                            anchorInfo.offsetX = cCX - tCX
                            anchorInfo.offsetY = cB - tT
                        elseif sd == "BOTTOM" then
                            anchorInfo.offsetX = cCX - tCX
                            anchorInfo.offsetY = cT - tB
                        else
                            anchorInfo.offsetX = cCX - tCX
                            anchorInfo.offsetY = cCY - tCY
                        end
                    end
                end
                -- The cross-axis screen edge rides the same recapture, else the next
                -- apply pulls that axis back to where the edge offset still points.
                if anchorInfo.edge and anchorInfo.edge.key then
                    local eo = CludesUI._CaptureScreenEdgeOffset(self._barKey, anchorInfo.edge.key, anchorInfo.edge.side)
                    if eo then
                        anchorInfo.edge.offset = eo
                    end
                end
                -- Growth bars: recapture the growth-edge pin from the dropped
                -- position (the user may have carried the bar to the other
                -- corner, which can change the reference edge).
                if CludesUI._unlockCaptureGrowPin then
                    CludesUI._unlockCaptureGrowPin(self._barKey, anchorInfo, anchorInfo.side)
                end
            end

            -- Anchor chain: propagate recursively down the chain
            LM.PropagateAnchorChain(self._barKey)

            local element = registeredElements[self._barKey]
            if element and element.onLiveMove then
                pcall(element.onLiveMove, self._barKey)
            end

            -- Keep the mover selected after drag so arrow keys can nudge it.
            -- Drop frame level back to normal so it doesn't block other movers.
            if self._selected then
                self:SetFrameLevel(self._baseLevel or self:GetFrameLevel())
            end

            -- Re-anchor mover to bar for pixel-perfect alignment
            self:ReanchorToBar()
        end)

        -- Hover effects
        handle:SetScript("OnEnter", function(self)
            if not self._dragging then
                if _mouseHeld and not self._dragging then
                    return
                end
                self._cycleLowered = nil
                -- Collapse any other expanded mover before expanding this one
                if LM.hoveredMover and LM.hoveredMover ~= self and not LM.hoveredMover._dragging then
                    if LM.hoveredMover._hideOverlayText then
                        LM.hoveredMover._hideOverlayText()
                    end
                    LM.hoveredMover = nil
                end
                -- Collapse selected mover's overlay if hovering a different one
                if LM.selectedMover and LM.selectedMover ~= self and not LM.selectedMover._dragging then
                    if LM.selectedMover._hideOverlayText then
                        LM.selectedMover._hideOverlayText()
                    end
                end
                LM.hoveredMover = self
                -- Raise above all other movers
                self:SetFrameLevel(self._raisedLevel + 100)
                if self._cogBtn then
                    self._cogBtn:SetFrameLevel(self:GetFrameLevel() + 10)
                end
                LM.PointPicker.Enter(self)
                -- Select Element mode: white border highlight on hover targets
                if LM.selectElementPicker and LM.selectElementPicker ~= self then
                    self._brd:SetColor(1, 1, 1, 0.9)
                    if not LM.darkOverlaysEnabled then
                        self:SetAlpha(MOVER_HOVER)
                    end
                    return
                end
                -- Pick mode (width/height match, anchor to): white border on hover targets
                if LM.pickModeMover and LM.pickModeMover ~= self and LM.pickMode then
                    self._brd:SetColor(1, 1, 1, 0.9)
                    if not LM.darkOverlaysEnabled then
                        self:SetAlpha(MOVER_HOVER)
                    end
                    return
                end
                if not LM.darkOverlaysEnabled then
                    self:SetAlpha(MOVER_HOVER)
                end
                self._brd:SetColor(1, 1, 1, 0.9)
                -- Don't show links if this mover is the pick mode source
                if LM.pickModeMover == self and LM.pickMode then
                -- Already showing pick text, don't override
                else
                    -- Wait the intent delay, then expand if still hovered and cursor has settled.
                    -- If cursor is still fast at fire time, allow one retry after a short pause.
                    self._hoverPending = true
                    local m = self
                    C_Timer.After(CludesUI._unlockHoverIntentDelay, function()
                        if not m._hoverPending then
                            return
                        end
                        if not m:IsMouseOver() and not (m._cogBtn and m._cogBtn:IsMouseOver()) then
                            local overLink = false
                            if m._linkBtns then
                                for _, btn in ipairs(m._linkBtns) do
                                    if btn:IsMouseOver() then
                                        overLink = true
                                        break
                                    end
                                end
                            end
                            if not overLink then
                                m._hoverPending = false
                                return
                            end
                        end
                        local function DoExpand()
                            if not m._hoverPending then
                                return
                            end
                            m._hoverPending = false
                            local stillOver = m:IsMouseOver() or (m._cogBtn and m._cogBtn:IsMouseOver())
                            if not stillOver and m._linkBtns then
                                for _, btn in ipairs(m._linkBtns) do
                                    if btn:IsMouseOver() then
                                        stillOver = true
                                        break
                                    end
                                end
                            end
                            if stillOver and m._showOverlayText then
                                -- Collapse any other mover still animating open
                                if
                                    LM.hoveredMover
                                    and LM.hoveredMover ~= m
                                    and not LM.hoveredMover._dragging
                                then
                                    if LM.hoveredMover._hideOverlayText then
                                        LM.hoveredMover._hideOverlayText()
                                    end
                                    LM.hoveredMover = nil
                                end
                                LM.hoveredMover = m
                                m._showOverlayText()
                            end
                        end
                        if CludesUI._unlockCursorSpeed > CludesUI._unlockHoverSpeedThresh then
                            C_Timer.After(0.08, DoExpand)
                        else
                            DoExpand()
                        end
                    end)
                end
            end
        end)
        handle:SetScript("OnLeave", function(self)
            LM.PointPicker.Leave(self)
            if not self._dragging then
                -- Delay so hovering child buttons (cog, link buttons) doesn't flicker
                C_Timer.After(0.12, function()
                    if self._dragging or self._cycleLowered then
                        return
                    end
                    if self:IsMouseOver() or self._pointHandleHovered then
                        self:SetFrameLevel(self._raisedLevel + 100)
                        self._brd:SetColor(1, 1, 1, 0.9)
                        if not LM.darkOverlaysEnabled then
                            self:SetAlpha(MOVER_HOVER)
                        end
                        return
                    end
                    if self._cogBtn and self._cogBtn:IsMouseOver() then
                        self:SetFrameLevel(self._raisedLevel + 100)
                        self._brd:SetColor(1, 1, 1, 0.9)
                        if not LM.darkOverlaysEnabled then
                            self:SetAlpha(MOVER_HOVER)
                        end
                        return
                    end
                    if self._linkBtns then
                        for _, button in ipairs(self._linkBtns) do
                            if button:IsMouseOver() then
                                self:SetFrameLevel(self._raisedLevel + 100)
                                self._brd:SetColor(1, 1, 1, 0.9)
                                if not LM.darkOverlaysEnabled then
                                    self:SetAlpha(MOVER_HOVER)
                                end
                                return
                            end
                        end
                    end
                    -- Truly left the element -- cancel any pending expand and collapse
                    self._hoverPending = false
                    if self._hideOverlayText then
                        self._hideOverlayText()
                    end
                    if LM.hoveredMover == self then
                        LM.hoveredMover = nil
                    end
                    -- Keep highlight border and raised level if selected (arrow keys)
                    if not self._selected then
                        self:SetFrameLevel(self._baseLevel)
                        if not LM.darkOverlaysEnabled then
                            self:SetAlpha(MOVER_ALPHA)
                        end
                        self._brd:SetColor(accR, accG, accB, 0.6)
                    end
                end)
            end
        end)

        -- Left-click to select
        handle:SetScript("OnClick", function(self, btnFrame)
            if LM.PointPicker.BodyClick(self, btnFrame) then
                return
            end
            if btnFrame == "LeftButton" then
                -- Width Match / Height Match / Anchor To pick mode handling
                -- Clicking the source mover itself cancels the pick mode
                if LM.pickModeMover and LM.pickModeMover == self and LM.pickMode then
                    CancelPickMode()
                    return
                end
                if LM.pickModeMover and LM.pickModeMover ~= self and LM.pickMode then
                    local sourceMover = LM.pickModeMover
                    local sourceKey = sourceMover._barKey
                    local targetBar = self._barKey

                    if LM.pickMode == "widthMatch" then
                        local tEl = registeredElements[targetBar]
                        if tEl and tEl.noSizeMatchTarget then
                            CancelPickMode()
                            FlashRedBorder(self)
                            local tLabel = LM.GetBarLabel(targetBar) or targetBar
                            RejectH.ShowTooltip(
                                CludesUI.Lf("Elements cannot size match to\n%1$s", CludesUI.L(tLabel))
                            )
                            return
                        end
                        if RejectH.IsActionBar(sourceKey) and not RejectH.IsActionBar(targetBar) then
                            CancelPickMode()
                            FlashRedBorder(self)
                            RejectH.ShowTooltip("Action Bars can only width match\nto other Action Bars")
                            return
                        end
                        local wdb = MatchH.GetWidthMatchDB()
                        if wdb and MatchH.WouldCreateCycle(wdb, sourceKey, targetBar) then
                            CancelPickMode()
                            FlashRedBorder(self)
                            RejectH.ShowTooltip("This would create a circular width match")
                            return
                        end
                        MatchH.SetWidthMatch(sourceKey, targetBar)
                        MatchH.ApplyWidthMatch(sourceKey, targetBar)
                        LM.hasChanges = true
                        CancelPickMode()
                        local sm = handles[sourceKey]
                        if sm then
                            sm:SyncSize()
                            if sm.RefreshAnchoredText then
                                sm:RefreshAnchoredText()
                            end
                        end
                        local anchorInfo = GetAnchorInfo(sourceKey)
                        if anchorInfo then
                            LM.ApplyAnchorPosition(sourceKey, anchorInfo.target, anchorInfo.side, true)
                        end
                        CludesUI.PropagateWidthMatch(sourceKey)
                        LM.PropagateAnchorChain(sourceKey)
                        return
                    elseif LM.pickMode == "heightMatch" then
                        local tEl = registeredElements[targetBar]
                        if tEl and tEl.noSizeMatchTarget then
                            CancelPickMode()
                            FlashRedBorder(self)
                            local tLabel = LM.GetBarLabel(targetBar) or targetBar
                            RejectH.ShowTooltip(
                                CludesUI.Lf("Elements cannot size match to\n%1$s", CludesUI.L(tLabel))
                            )
                            return
                        end
                        local hdb = MatchH.GetHeightMatchDB()
                        if hdb and MatchH.WouldCreateCycle(hdb, sourceKey, targetBar) then
                            CancelPickMode()
                            FlashRedBorder(self)
                            RejectH.ShowTooltip("This would create a circular height match")
                            return
                        end
                        MatchH.SetHeightMatch(sourceKey, targetBar)
                        MatchH.ApplyHeightMatch(sourceKey, targetBar)
                        LM.hasChanges = true
                        CancelPickMode()
                        local sm = handles[sourceKey]
                        if sm then
                            sm:SyncSize()
                            if sm.RefreshAnchoredText then
                                sm:RefreshAnchoredText()
                            end
                        end
                        local anchorInfo = GetAnchorInfo(sourceKey)
                        if anchorInfo then
                            LM.ApplyAnchorPosition(sourceKey, anchorInfo.target, anchorInfo.side, true)
                        end
                        CludesUI.PropagateHeightMatch(sourceKey)
                        LM.PropagateAnchorChain(sourceKey)
                        return
                    elseif
                        LM.pickMode == "anchorTo"
                        or LM.pickMode == "fallbackAnchor"
                        or LM.pickMode == "overrideAnchor"
                    then
                        -- Show anchor direction dropdown near the clicked target.
                        -- fallbackAnchor mode stores a fallback link on the
                        -- element's EXISTING anchor instead of re-anchoring it;
                        -- overrideAnchor mode stores a per-override-group link.
                        local fbPick = (LM.pickMode == "fallbackAnchor")
                        local ovPick = (LM.pickMode == "overrideAnchor")
                        local ovGid = ovPick and CludesUI._OverridePickGid and CludesUI._OverridePickGid()
                            or nil
                        local pm = LM.pickModeMover
                        local menuBarKey = pm._barKey

                        -- Reject elements marked as non-anchorable (e.g. buff bars
                        -- whose icon count changes dynamically with auras).
                        local targetEl = registeredElements[targetBar]
                        if targetEl and targetEl.noAnchorTarget then
                            CancelPickMode()
                            FlashRedBorder(self)
                            local targetLabel = LM.GetBarLabel(targetBar) or targetBar
                            RejectH.ShowTooltip(
                                CludesUI.Lf("Elements cannot be anchored to\n%1$s", CludesUI.L(targetLabel))
                            )
                            return
                        end

                        if fbPick then
                            local curInfo = GetAnchorInfo(menuBarKey)
                            if not curInfo or not curInfo.target then
                                CancelPickMode()
                                FlashRedBorder(self)
                                RejectH.ShowTooltip("Anchor this element first")
                                return
                            end
                            if targetBar == curInfo.target then
                                CancelPickMode()
                                FlashRedBorder(self)
                                RejectH.ShowTooltip("The fallback must differ from\nthe main anchor target")
                                return
                            end
                        end

                        if ovPick then
                            if not ovGid then
                                CancelPickMode()
                                return
                            end
                            if targetBar == menuBarKey then
                                CancelPickMode()
                                FlashRedBorder(self)
                                RejectH.ShowTooltip("An element cannot anchor to itself")
                                return
                            end
                            -- Walk primary + fallback + override edges from the
                            -- target: reaching this element means an engaged loop
                            -- could chase itself across cascades forever.
                            local circular = false
                            local seen = {}
                            local stack = { targetBar }
                            while #stack > 0 do
                                local k = table.remove(stack)
                                if k == menuBarKey then
                                    circular = true
                                    break
                                end
                                if not seen[k] then
                                    seen[k] = true
                                    local details = GetAnchorInfo(k)
                                    if details and details.target then
                                        stack[#stack + 1] = details.target
                                    end
                                    if details and details.fallback and details.fallback.target then
                                        stack[#stack + 1] = details.fallback.target
                                    end
                                    local ovT = CludesUI._OverrideAnchorTargets
                                        and CludesUI._OverrideAnchorTargets(k)
                                    if ovT then
                                        for idx = 1, #ovT do
                                            stack[#stack + 1] = ovT[idx]
                                        end
                                    end
                                end
                            end
                            if circular then
                                CancelPickMode()
                                FlashRedBorder(self)
                                RejectH.ShowTooltip("This would create a circular anchor")
                                return
                            end
                        end

                        -- Circular / ancestor checks guard PRIMARY anchor links;
                        -- a fallback/override is a one-level positional read, so
                        -- they use their own checks above instead.
                        if not fbPick and not ovPick then
                            local circular = false
                            local visited = { [menuBarKey] = true }
                            local walk = targetBar
                            while walk do
                                if visited[walk] then
                                    circular = true
                                    break
                                end
                                visited[walk] = true
                                local details = GetAnchorInfo(walk)
                                walk = details and details.target or nil
                            end
                            if circular then
                                CancelPickMode()
                                FlashRedBorder(self)
                                RejectH.ShowTooltip("This would create a circular anchor")
                                return
                            end

                            -- Ancestor depth check: prevent anchoring to a grandparent
                            -- or higher. Only direct parent (depth 1) or unrelated
                            -- elements are valid targets.
                            local ancestorDepth = 0
                            local aWalk = menuBarKey
                            while aWalk do
                                local aInfo = GetAnchorInfo(aWalk)
                                if not aInfo or not aInfo.target then
                                    break
                                end
                                ancestorDepth = ancestorDepth + 1
                                if aInfo.target == targetBar and ancestorDepth >= 2 then
                                    CancelPickMode()
                                    FlashRedBorder(self)
                                    RejectH.ShowTooltip("This would create a circular anchor")
                                    return
                                end
                                aWalk = aInfo.target
                            end
                        end

                        CancelPickMode()
                        -- Build and show the anchor direction dropdown
                        local DD_ITEM_H = 24
                        local DD_WIDTH = 160
                        if not LM.anchorDropdownFrame then
                            LM.anchorDropdownFrame = CreateFrame("Frame", nil, LM.unlockFrame)
                            LM.anchorDropdownFrame:SetFrameStrata("FULLSCREEN_DIALOG")
                            LM.SetMoverOverlayLevel(LM.anchorDropdownFrame, 10)
                            LM.anchorDropdownFrame:SetClampedToScreen(true)
                            LM.anchorDropdownFrame:EnableMouse(true)
                            -- Built once: background, border and both title styles (the
                            -- short dimmed label and the wrapped usage hint).
                            MenuPool.Chrome(LM.anchorDropdownFrame)
                            local shortFS = LM.anchorDropdownFrame:CreateFontString(nil, "OVERLAY")
                            shortFS:SetFont(FONT_PATH, 10, "OUTLINE, SLUG")
                            shortFS:SetJustifyH("LEFT")
                            shortFS:SetPoint("TOPLEFT", LM.anchorDropdownFrame, "TOPLEFT", 10, -8)
                            shortFS:SetTextColor(1, 1, 1, 0.40)
                            LM.anchorDropdownFrame._titleShort = shortFS
                            local hintText = LM.anchorDropdownFrame:CreateFontString(nil, "OVERLAY")
                            hintText:SetFont(FONT_PATH, 10, "OUTLINE, SLUG")
                            hintText:SetJustifyH("LEFT")
                            hintText:SetPoint("TOPLEFT", LM.anchorDropdownFrame, "TOPLEFT", 10, -8)
                            hintText:SetTextColor(0.75, 0.75, 0.75, 0.9)
                            hintText:SetWidth(DD_WIDTH - 20)
                            hintText:SetWordWrap(true)
                            LM.anchorDropdownFrame._titleHint = hintText
                        end
                        -- Click catcher behind dropdown
                        if not LM.anchorDropdownCatcher then
                            LM.anchorDropdownCatcher = CreateFrame("Button", nil, LM.unlockFrame)
                            LM.anchorDropdownCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
                            LM.SetMoverOverlayLevel(LM.anchorDropdownCatcher, 9)
                            LM.anchorDropdownCatcher:SetAllPoints(UIParent)
                            LM.anchorDropdownCatcher._umCatcher = true -- not an element for the hover bar
                            LM.anchorDropdownCatcher:RegisterForClicks("AnyUp")
                            LM.anchorDropdownCatcher:SetScript("OnClick", function()
                                LM.anchorDropdownFrame:Hide()
                                LM.anchorDropdownCatcher:Hide()
                            end)
                        end

                        LM.anchorDropdownFrame:SetSize(DD_WIDTH, 10)
                        LM.anchorDropdownFrame:ClearAllPoints()
                        local scale = UIParent:GetEffectiveScale()
                        local nowX, nowY = GetCursorPosition()
                        nowX = nowX / scale
                        nowY = nowY / scale - UIParent:GetHeight()
                        LM.anchorDropdownFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", nowX, nowY)

                        local menuY = -4
                        -- Growth bars (CDM and action bars) get the corner rows below on a
                        -- primary anchor pick; the hint speaks to those rows when they exist.
                        local isGrowBar = not fbPick
                            and not ovPick
                            and (
                                menuBarKey:sub(1, 4) == "CDM_"
                                or (CludesUI._abBarKeys and CludesUI._abBarKeys[menuBarKey])
                                or false
                            )
                        -- Title: the fallback picker keeps its short dimmed label;
                        -- the anchor picker shows a wrapped usage hint in the same
                        -- color as the option rows below.
                        local titleShort = LM.anchorDropdownFrame._titleShort
                        local titleHint = LM.anchorDropdownFrame._titleHint
                        if fbPick or ovPick then
                            titleHint:Hide()
                            titleShort:Show()
                            if fbPick then
                                titleShort:SetText(CludesUI.L("Fallback Direction"))
                            else
                                titleShort:SetText(CludesUI.L("Override Anchor Direction"))
                            end
                            menuY = menuY - 18
                        else
                            titleShort:Hide()
                            titleHint:Show()
                            if isGrowBar then
                                titleHint:SetText(
                                    CludesUI.L(
                                        "Corner options place the bar flush with that corner of the target and set its grow direction to keep it there as bars change size."
                                    )
                                )
                            else
                                titleHint:SetText(
                                    CludesUI.L(
                                        "After anchoring, drag to an edge and choose a grow direction to maintain its corner spot as bars change size."
                                    )
                                )
                            end
                            menuY = menuY - (titleHint:GetStringHeight() + 8)
                        end
                        MenuPool.Begin(LM.anchorDropdownFrame, false)
                        MenuPool.Div(LM.anchorDropdownFrame, menuY - 2, 1)
                        menuY = menuY - 5

                        local sides = { "Left", "Right", "Top", "Bottom" }
                        for _, sideName in ipairs(sides) do
                            local sideVal = string.upper(sideName)
                            local menuItem, highlight, labelFS =
                                MenuPool.Item(LM.anchorDropdownFrame, menuY, DD_ITEM_H)
                            labelFS:SetText(
                                CludesUI.Lf(
                                    fbPick and "Fallback to %1$s" or "Anchor to %1$s",
                                    CludesUI.L(sideName)
                                )
                            )
                            menuItem:SetScript("OnEnter", function()
                                highlight:SetColorTexture(1, 1, 1, 0.08)
                                labelFS:SetTextColor(1, 1, 1, 1)
                            end)
                            menuItem:SetScript("OnLeave", function()
                                highlight:SetColorTexture(1, 1, 1, 0)
                                labelFS:SetTextColor(0.75, 0.75, 0.75, 0.9)
                            end)
                            menuItem:SetScript("OnClick", function()
                                LM.anchorDropdownFrame:Hide()
                                LM.anchorDropdownCatcher:Hide()
                                if ovPick then
                                    -- Store the override link; the element only
                                    -- moves while that group's override is active.
                                    if CludesUI._SetOverrideAnchor then
                                        CludesUI._SetOverrideAnchor(menuBarKey, ovGid, targetBar, sideVal)
                                    end
                                    LM.hasChanges = true
                                    return
                                end
                                if fbPick then
                                    -- Store the fallback link; the element only
                                    -- moves when the main target is absent.
                                    if CludesUI.SetAnchorFallback then
                                        CludesUI.SetAnchorFallback(menuBarKey, targetBar, sideVal)
                                    end
                                    LM.hasChanges = true
                                    return
                                end
                                -- Default grow direction to match the anchor side
                                -- (orientation-aware: cross-axis sides map to CENTER)
                                local vertical = false
                                if menuBarKey:sub(1, 4) == "CDM_" then
                                    local rawCdmKey = menuBarKey:sub(5)
                                    local cdmAddon = CludesUI.Lite.GetAddon("CludesUICooldownManager", true)
                                    local cdmBars = cdmAddon
                                        and cdmAddon.db
                                        and cdmAddon.db.profile
                                        and cdmAddon.db.profile.cdmBars
                                    if cdmBars and cdmBars.bars then
                                        for _, barFrame in ipairs(cdmBars.bars) do
                                            if barFrame.key == rawCdmKey then
                                                vertical = barFrame.verticalOrientation == true
                                                local map = vertical
                                                        and {
                                                            TOP = "UP",
                                                            BOTTOM = "DOWN",
                                                            LEFT = "CENTER",
                                                            RIGHT = "CENTER",
                                                        }
                                                    or {
                                                        LEFT = "LEFT",
                                                        RIGHT = "RIGHT",
                                                        TOP = "CENTER",
                                                        BOTTOM = "CENTER",
                                                    }
                                                barFrame.growDirection = map[sideVal] or "CENTER"
                                                break
                                            end
                                        end
                                    end
                                else
                                    local eab = CludesUI.Lite.GetAddon("CludesUIActionBars", true)
                                    local abBars = eab and eab.db and eab.db.profile and eab.db.profile.bars
                                    local abCfg = abBars and abBars[menuBarKey]
                                    if abCfg then
                                        vertical = (abCfg.orientation == "vertical")
                                        local map = vertical
                                                and {
                                                    TOP = "up",
                                                    BOTTOM = "down",
                                                    LEFT = "center",
                                                    RIGHT = "center",
                                                }
                                            or {
                                                LEFT = "left",
                                                RIGHT = "right",
                                                TOP = "center",
                                                BOTTOM = "center",
                                            }
                                        abCfg.growDirection = map[sideVal] or "center"
                                    end
                                end
                                -- Set anchor relationship
                                SetAnchorInfo(menuBarKey, targetBar, sideVal)
                                -- Apply the anchor position
                                LM.ApplyAnchorPosition(menuBarKey, targetBar, sideVal)
                                -- Propagate to children after layout flushes so
                                -- they read the correct bounds from the newly-anchored parent
                                C_Timer.After(0, function()
                                    LM.PropagateAnchorChain(menuBarKey)
                                end)
                                LM.hasChanges = true
                                -- Refresh the anchored mover's text
                                if handles[menuBarKey] and handles[menuBarKey].RefreshAnchoredText then
                                    handles[menuBarKey]:RefreshAnchoredText()
                                end
                                -- Sync mover position to follow the element after anchor placement
                                DeferMoverSync(handles[menuBarKey], function(m)
                                    m:Sync()
                                end, LM.GetBarFrame(menuBarKey))
                            end)
                            menuY = menuY - DD_ITEM_H
                        end

                        -- Corner rows (growth bars, primary anchor only): the bar sits flush
                        -- with that corner of the target and grows away from it. Nothing new
                        -- in the record -- it is the side pick above, the flush drag and the
                        -- cog's Grow row in one click. A corner reads by the bar's
                        -- orientation: a horizontal bar sits above or below the target
                        -- (Top/Bottom) with the named edges flush and grows away from them; a
                        -- vertical bar sits beside it (Left/Right) the same way. So the four
                        -- rows cover exactly the sides the picks above leave centered.
                        if isGrowBar then
                            MenuPool.Div(LM.anchorDropdownFrame, menuY - 4, 1)
                            menuY = menuY - 9
                            local corners = {
                                { label = CludesUI.L("Top Left"), v = "TOP", h = "LEFT" },
                                { label = CludesUI.L("Top Right"), v = "TOP", h = "RIGHT" },
                                { label = CludesUI.L("Bottom Left"), v = "BOTTOM", h = "LEFT" },
                                { label = CludesUI.L("Bottom Right"), v = "BOTTOM", h = "RIGHT" },
                            }
                            for _, corner in ipairs(corners) do
                                local menuItem, highlight, labelFS =
                                    MenuPool.Item(LM.anchorDropdownFrame, menuY, DD_ITEM_H)
                                labelFS:SetText(CludesUI.Lf("Anchor to %1$s", corner.label))
                                menuItem:SetScript("OnEnter", function()
                                    highlight:SetColorTexture(1, 1, 1, 0.08)
                                    labelFS:SetTextColor(1, 1, 1, 1)
                                end)
                                menuItem:SetScript("OnLeave", function()
                                    highlight:SetColorTexture(1, 1, 1, 0)
                                    labelFS:SetTextColor(0.75, 0.75, 0.75, 0.9)
                                end)
                                menuItem:SetScript("OnClick", function()
                                    LM.anchorDropdownFrame:Hide()
                                    LM.anchorDropdownCatcher:Hide()
                                    -- Orientation, the same lookups as the side pick. The bar is
                                    -- placed on centered growth first (the side pick's own default
                                    -- for this side): a held growth edge would otherwise pin the
                                    -- bar to where it stood before the anchor moved it.
                                    local vertical = false
                                    if menuBarKey:sub(1, 4) == "CDM_" then
                                        local rawCdmKey = menuBarKey:sub(5)
                                        local cdmAddon =
                                            CludesUI.Lite.GetAddon("CludesUICooldownManager", true)
                                        local cdmBars = cdmAddon
                                            and cdmAddon.db
                                            and cdmAddon.db.profile
                                            and cdmAddon.db.profile.cdmBars
                                        if cdmBars and cdmBars.bars then
                                            for _, barFrame in ipairs(cdmBars.bars) do
                                                if barFrame.key == rawCdmKey then
                                                    vertical = barFrame.verticalOrientation == true
                                                    barFrame.growDirection = "CENTER"
                                                    break
                                                end
                                            end
                                        end
                                    else
                                        local eab = CludesUI.Lite.GetAddon("CludesUIActionBars", true)
                                        local abBars = eab
                                            and eab.db
                                            and eab.db.profile
                                            and eab.db.profile.bars
                                        local abCfg = abBars and abBars[menuBarKey]
                                        if abCfg then
                                            vertical = (abCfg.orientation == "vertical")
                                            abCfg.growDirection = "center"
                                        end
                                    end
                                    -- The side the corner means, the edge held flush along it and
                                    -- the direction that grows away from that edge.
                                    local sideVal = vertical and corner.h or corner.v
                                    local flush = vertical and corner.v or corner.h
                                    local growVal
                                    if vertical then
                                        growVal = (flush == "TOP") and "DOWN" or "UP"
                                    else
                                        growVal = (flush == "RIGHT") and "LEFT" or "RIGHT"
                                    end
                                    -- Flush edges: the side pick centers the bar along the side, so
                                    -- the shift is half the size difference (UIParent units,
                                    -- pixel-snapped like the side pick's own offsets). Sizes, not
                                    -- rects: the target's bounds are read before anything moves.
                                    local offX, offY = 0, 0
                                    local childF, targetF = LM.GetBarFrame(menuBarKey), LM.GetBarFrame(targetBar)
                                    if childF and targetF then
                                        local uiZoom = UIParent:GetEffectiveScale()
                                        local cS, tS =
                                            childF:GetEffectiveScale() / uiZoom,
                                            targetF:GetEffectiveScale() / uiZoom
                                        local snap = (CludesUI.PP and CludesUI.PP.Snap)
                                            or function(v)
                                                return math.floor(v + 0.5)
                                            end
                                        if vertical then
                                            local half = (
                                                (targetF:GetHeight() or 0) * tS
                                                - (childF:GetHeight() or 0) * cS
                                            ) / 2
                                            offY = snap((flush == "TOP") and half or -half)
                                        else
                                            local half = (
                                                (targetF:GetWidth() or 0) * tS
                                                - (childF:GetWidth() or 0) * cS
                                            ) / 2
                                            offX = snap((flush == "RIGHT") and half or -half)
                                        end
                                    end
                                    -- Set anchor relationship, flush offsets included (the record a
                                    -- side pick plus a drag to the edge leaves behind)
                                    SetAnchorInfo(menuBarKey, targetBar, sideVal, offX, offY)
                                    -- A screen edge the element holds on the flush axis would win
                                    -- that axis on every apply and undo the alignment just asked
                                    -- for: release it, the Relative-to-Screen clear path's way.
                                    local aiC = GetAnchorInfo(menuBarKey)
                                    if
                                        aiC
                                        and aiC.edge
                                        and aiC.edge.key
                                        and CludesUI._ScreenEdgeAxis
                                        and CludesUI._ScreenEdgeAxis(aiC.edge.key)
                                            == (vertical and "Y" or "X")
                                    then
                                        aiC.edge = nil
                                        CludesUI._anchorLinksStamp = (CludesUI._anchorLinksStamp or 0) + 1
                                    end
                                    -- Apply the anchor position
                                    LM.ApplyAnchorPosition(menuBarKey, targetBar, sideVal)
                                    -- Grow away from the flush edge, after the placement: the
                                    -- growth-edge hold captures from where the bar now sits.
                                    CludesUI._unlockSetGrowDirection(menuBarKey, growVal)
                                    -- Propagate to children after layout flushes so
                                    -- they read the correct bounds from the newly-anchored parent
                                    C_Timer.After(0, function()
                                        LM.PropagateAnchorChain(menuBarKey)
                                    end)
                                    LM.hasChanges = true
                                    -- Refresh the anchored mover's text
                                    if handles[menuBarKey] and handles[menuBarKey].RefreshAnchoredText then
                                        handles[menuBarKey]:RefreshAnchoredText()
                                    end
                                    -- Sync mover position to follow the element after anchor placement
                                    DeferMoverSync(handles[menuBarKey], function(m)
                                        m:Sync()
                                    end, LM.GetBarFrame(menuBarKey))
                                end)
                                menuY = menuY - DD_ITEM_H
                            end
                        end

                        -- "Remove Anchor" option if already anchored
                        if not fbPick and IsAnchored(menuBarKey) then
                            MenuPool.Div(LM.anchorDropdownFrame, menuY - 4, 1)
                            menuY = menuY - 9

                            local removeItem, rHl, rLbl =
                                MenuPool.Item(LM.anchorDropdownFrame, menuY, DD_ITEM_H)
                            rLbl:SetTextColor(0.9, 0.3, 0.3, 0.9)
                            rLbl:SetText(CludesUI.L("Remove Anchor"))
                            removeItem:SetScript("OnEnter", function()
                                rHl:SetColorTexture(1, 1, 1, 0.08)
                                rLbl:SetTextColor(1, 0.4, 0.4, 1)
                            end)
                            removeItem:SetScript("OnLeave", function()
                                rHl:SetColorTexture(1, 1, 1, 0)
                                rLbl:SetTextColor(0.9, 0.3, 0.3, 0.9)
                            end)
                            removeItem:SetScript("OnClick", function()
                                LM.anchorDropdownFrame:Hide()
                                LM.anchorDropdownCatcher:Hide()
                                ClearAnchorInfo(menuBarKey)
                                LM.hasChanges = true
                                if handles[menuBarKey] and handles[menuBarKey].RefreshAnchoredText then
                                    handles[menuBarKey]:RefreshAnchoredText()
                                end
                            end)
                            menuY = menuY - DD_ITEM_H
                        end
                        MenuPool.End(LM.anchorDropdownFrame)

                        LM.anchorDropdownFrame:SetHeight(-menuY + 4)
                        LM.anchorDropdownFrame:Show()
                        LM.anchorDropdownCatcher:Show()
                        return
                    end
                end

                -- Select Element pick mode: clicking a different mover sets it as snap target
                if LM.selectElementPicker and LM.selectElementPicker ~= self then
                    local picker = LM.selectElementPicker
                    picker._snapTarget = self._barKey
                    picker._preSelectTarget = nil
                    LM.selectElementPicker = nil
                    FadeOverlayForSelectElement(false)
                    -- Restore this mover's normal colors
                    self._brd:SetColor(accR, accG, accB, 0.6)
                    if not LM.darkOverlaysEnabled then
                        self:SetAlpha(MOVER_ALPHA)
                    end
                    -- Update the picker's dropdown label
                    if picker._updateSnapLabel then
                        picker._updateSnapLabel()
                    end
                    return
                end
                -- Toggle: clicking the already-selected mover deselects it
                if LM.selectedMover == self then
                    DeselectMover()
                else
                    SelectMover(self)
                end
            elseif btnFrame == "RightButton" then
                if LM.selectElementPicker then
                    return
                end
                -- Shift+Right Click temporarily hides this element's overlay for the
                -- current unlock session. The _tempHidden flag is cleared when unlock
                -- mode is next entered, so the overlay reappears then. Purely a visual
                -- toggle on the overlay -- it never touches the underlying element.
                if IsShiftKeyDown() then
                    if LM.pickModeMover == self and LM.PointPicker.Active() then
                        CancelPickMode()
                    end
                    self._tempHidden = true
                    self._hoverPending = false
                    if LM.selectedMover == self then
                        DeselectMover()
                    end
                    if LM.hoveredMover == self then
                        LM.hoveredMover = nil
                    end
                    if self._hideOverlayText then
                        self._hideOverlayText()
                    end
                    -- Hide the cog too; its OnHide closes any open cog menu.
                    if self._cogBtn then
                        self._cogBtn:Hide()
                    end
                    self:Hide()
                    return
                end
                SelectMover(self)
                if self._openCogMenu then
                    self._openCogMenu()
                end
            end
        end)
        handle:RegisterForClicks("LeftButtonUp", "RightButtonUp")

        ---------------------------------------------------------------------------
        --  Action toolbar: cog settings button only
        --  Cog is flush with mover's top-right corner.
        ---------------------------------------------------------------------------
        local ICON_PATH = "Interface\\AddOns\\CludesUI\\media\\icons\\"
        local ARROW_ICON = ICON_PATH .. "cui-arrow.png"
        local ARROW_RIGHT_ICON = ICON_PATH .. "right-arrow.png"
        -- The cogwheel art (CludesUI.COGS_ICON is the settings panel's cog).
        local COGS_ICON = ICON_PATH .. "cogs-3.png"
        local ACT_SZ = 22 -- cog button size
        local ACT_PAD = 3 -- gap between cog and dropdown
        local DD_W = 150 -- dropdown width

        -- Cog settings button (opens a dropdown with Reset / Center / Orientation)
        gearButton = CreateFrame("Button", nil, LM.unlockFrame)
        gearButton:SetFrameLevel(handle:GetFrameLevel() + 10)
        gearButton:RegisterForClicks("AnyUp")
        gearButton:EnableMouse(true)
        gearButton:EnableMouseWheel(OverlapScrollDown())
        gearButton:SetScript("OnMouseWheel", OnMoverWheel)
        gearButton:SetSize(ACT_SZ, ACT_SZ)
        do
            local backdrop = gearButton:CreateTexture(nil, "BACKGROUND")
            backdrop:SetAllPoints()
            backdrop:SetColorTexture(0.088, 0.098, 0.111, 0.9)
            gearButton._bg = backdrop
            local brd = CludesUI.MakeBorder(gearButton, 1, 1, 1, 0.20)
            gearButton._brd = brd
            local icon = gearButton:CreateTexture(nil, "ARTWORK")
            icon:SetSize(18, 18)
            icon:SetPoint("CENTER")
            icon:SetTexture(COGS_ICON)
            icon:SetAlpha(0.7)
            gearButton._icon = icon
            gearButton:SetScript("OnEnter", function(self)
                self._bg:SetColorTexture(0.088, 0.098, 0.111, 0.98)
                self._brd:SetColor(1, 1, 1, 0.30)
                self._icon:SetAlpha(1)
                handle:SetFrameLevel(handle._raisedLevel + 100)
                handle._brd:SetColor(1, 1, 1, 0.9)
                if not LM.darkOverlaysEnabled then
                    handle:SetAlpha(MOVER_HOVER)
                end
            end)
            gearButton:SetScript("OnLeave", function(self)
                self._bg:SetColorTexture(0.088, 0.098, 0.111, 0.9)
                self._brd:SetColor(1, 1, 1, 0.20)
                self._icon:SetAlpha(0.7)
            end)
        end
        gearButton:Hide()

        -- Cog visibility is now tied to the hover animation.
        -- Show/hide helpers are simple wrappers.
        local function ShowCogForHover() end
        local function HideCogAfterDelay() end
        local function HideCogImmediate() end

        handle._showCogForHover = ShowCogForHover
        handle._hideCogAfterDelay = HideCogAfterDelay
        handle._hideCogImmediate = HideCogImmediate

        -- Re-set cogBtn hover scripts now that fade helpers are in scope
        gearButton:SetScript("OnEnter", function(self)
            self._bg:SetColorTexture(0.088, 0.098, 0.111, 0.98)
            self._brd:SetColor(1, 1, 1, 0.30)
            self._icon:SetAlpha(1)
            -- Restore mover highlight immediately (mover:OnLeave resets it when mouse moves to cog)
            handle:SetFrameLevel(handle._raisedLevel + 100)
            handle._brd:SetColor(1, 1, 1, 0.9)
            if not LM.darkOverlaysEnabled then
                handle:SetAlpha(MOVER_HOVER)
            end
        end)
        gearButton:SetScript("OnLeave", function(self)
            self._bg:SetColorTexture(0.088, 0.098, 0.111, 0.9)
            self._brd:SetColor(1, 1, 1, 0.20)
            self._icon:SetAlpha(0.7)
        end)

        ---------------------------------------------------------------------------
        --  Snap-to dropdown (custom styled, per-mover memory)
        ---------------------------------------------------------------------------
        local snapDropdown = CreateFrame("Button", nil, LM.unlockFrame)
        snapDropdown:SetFrameLevel(handle:GetFrameLevel() + 10)
        snapDropdown:RegisterForClicks("AnyUp")
        snapDropdown:EnableMouse(true)
        snapDropdown:SetSize(DD_W, 30)
        local snapDDBg = snapDropdown:CreateTexture(nil, "BACKGROUND")
        snapDDBg:SetAllPoints()
        snapDDBg:SetColorTexture(0.088, 0.098, 0.111, 0.9)
        snapDropdown._bg = snapDDBg
        local snapDDBrd = CludesUI.MakeBorder(snapDropdown, 1, 1, 1, 0.20)
        snapDropdown._brd = snapDDBrd
        local snapDropdownText = snapDropdown:CreateFontString(nil, "OVERLAY")
        snapDropdownText:SetFont(FONT_PATH, 12, "OUTLINE, SLUG")
        snapDropdownText:SetTextColor(1, 1, 1, 0.50)
        snapDropdownText:SetJustifyH("LEFT")
        snapDropdownText:SetWordWrap(false)
        snapDropdownText:SetMaxLines(1)
        snapDropdownText:SetPoint("LEFT", snapDropdown, "LEFT", 8, 0)
        snapDropdownText:SetText(CludesUI.L("Snap to: Auto"))
        local snapDDArrow = CludesUI.MakeDropdownArrow(snapDropdown, 12)
        snapDropdownText:SetPoint("RIGHT", snapDDArrow, "LEFT", -5, 0)
        snapDropdown:SetScript("OnEnter", function(self)
            if not LM.snapEnabled then
                -- Grayed out: show tooltip explaining why
                CludesUI.ShowWidgetTooltip(self, "This feature requires Snap Elements to be enabled")
                return
            end
            self._bg:SetColorTexture(0.088, 0.098, 0.111, 0.98)
            self._brd:SetColor(1, 1, 1, 0.30)
            snapDropdownText:SetTextColor(1, 1, 1, 0.60)
        end)
        snapDropdown:SetScript("OnLeave", function(self)
            CludesUI.HideWidgetTooltip()
            if not LM.snapEnabled then
                return
            end
            self._bg:SetColorTexture(0.088, 0.098, 0.111, 0.9)
            self._brd:SetColor(1, 1, 1, 0.20)
            snapDropdownText:SetTextColor(1, 1, 1, 0.50)
        end)
        snapDropdown:Hide()

        -- Helper: apply grayed-out or normal visual state to the dropdown
        local function RefreshSnapDDState()
            if not LM.snapEnabled then
                snapDDBg:SetColorTexture(0.088, 0.098, 0.111, 0.50)
                snapDDBrd:SetColor(1, 1, 1, 0.07)
                snapDropdownText:SetTextColor(1, 1, 1, 0.20)
                snapDDArrow:SetAlpha(0.10)
            else
                snapDDBg:SetColorTexture(0.088, 0.098, 0.111, 0.9)
                snapDDBrd:SetColor(1, 1, 1, 0.20)
                snapDropdownText:SetTextColor(1, 1, 1, 0.50)
                snapDDArrow:SetAlpha(1)
            end
        end
        handle._refreshSnapDD = RefreshSnapDDState

        -- Snap dropdown menu frame (lazy-created, shared across this mover)
        local snapList
        local regSubMenus = {}

        local function CloseSnapMenu()
            if snapList then
                snapList:Hide()
            end
            for _, rs in pairs(regSubMenus) do
                if rs and rs.Hide then
                    rs:Hide()
                end
            end
        end

        local function UpdateSnapLabel()
            local tgt = handle._snapTarget
            if tgt == "_disable_" then
                snapDropdownText:SetText(CludesUI.L("Snap to: None"))
            elseif tgt == "_select_" then
                snapDropdownText:SetText(CludesUI.L("Snap to: Select Element"))
            elseif tgt then
                local labelFS = LM.GetBarLabel(tgt)
                snapDropdownText:SetText(CludesUI.Lf("Snap to: %1$s", labelFS or tgt))
            else
                snapDropdownText:SetText(CludesUI.L("Snap to: All Elements"))
            end
            -- Update snap highlight to match new target
            if handle._selected then
                if tgt and tgt ~= "_disable_" and tgt ~= "_select_" and handles[tgt] then
                    ShowSnapHighlight(tgt)
                else
                    ClearSnapHighlight()
                end
            end
        end

        local function BuildSnapMenu()
            if snapList then
                -- Rebuild items
                for _, childFrame in ipairs({ snapList:GetChildren() }) do
                    childFrame:Hide()
                    childFrame:SetParent(nil)
                end
                for _, tex in ipairs({ snapList:GetRegions() }) do
                    if tex.Hide then
                        tex:Hide()
                    end
                end
            end
            snapList = snapList or CreateFrame("Frame", nil, LM.unlockFrame)
            snapList:SetFrameStrata("FULLSCREEN_DIALOG")
            LM.SetMoverOverlayLevel(snapList)
            snapList:SetClampedToScreen(true)
            snapList:SetSize(DD_W, 10)
            snapList:SetPoint("TOPLEFT", handle, "TOPRIGHT", 4, 0)

            -- Background + border
            local menuBg = snapList:CreateTexture(nil, "BACKGROUND")
            menuBg:SetAllPoints()
            menuBg:SetColorTexture(0.088, 0.098, 0.111, 0.95)
            CludesUI.MakeBorder(snapList, 1, 1, 1, 0.20)
            CludesUI.AccentCap(snapList)

            local ITEM_H = 24
            local rowOffset = -4
            local itemList = {}

            -- Title: "Snap Target"
            local titleLbl = snapList:CreateFontString(nil, "OVERLAY")
            titleLbl:SetFont(FONT_PATH, 10, "OUTLINE, SLUG")
            titleLbl:SetTextColor(1, 1, 1, 0.40)
            titleLbl:SetJustifyH("LEFT")
            titleLbl:SetPoint("TOPLEFT", snapList, "TOPLEFT", 10, rowOffset - 4)
            titleLbl:SetText(CludesUI.L("Snap Target"))
            rowOffset = rowOffset - 18

            -- Title divider
            local titleDiv = snapList:CreateTexture(nil, "ARTWORK")
            titleDiv:SetHeight(1)
            titleDiv:SetColorTexture(1, 1, 1, 0.10)
            titleDiv:SetPoint("TOPLEFT", snapList, "TOPLEFT", 1, rowOffset - 2)
            titleDiv:SetPoint("TOPRIGHT", snapList, "TOPRIGHT", -1, rowOffset - 2)
            rowOffset = rowOffset - 5

            local function MakeItem(hostFrame, textValue, onClick, isSelected)
                local menuItem = CreateFrame("Button", nil, hostFrame)
                menuItem:SetHeight(ITEM_H)
                menuItem:SetPoint("TOPLEFT", hostFrame, "TOPLEFT", 1, rowOffset)
                menuItem:SetPoint("TOPRIGHT", hostFrame, "TOPRIGHT", -1, rowOffset)
                menuItem:SetFrameLevel(hostFrame:GetFrameLevel() + 2)
                menuItem:RegisterForClicks("AnyUp")
                local highlight = menuItem:CreateTexture(nil, "ARTWORK")
                highlight:SetAllPoints()
                highlight:SetColorTexture(1, 1, 1, 0)
                local labelFS = menuItem:CreateFontString(nil, "OVERLAY")
                labelFS:SetFont(FONT_PATH, 11, "OUTLINE, SLUG")
                labelFS:SetTextColor(0.75, 0.75, 0.75, 0.9)
                labelFS:SetJustifyH("LEFT")
                labelFS:SetPoint("LEFT", menuItem, "LEFT", 10, 0)
                labelFS:SetText(CludesUI.L(textValue))
                if isSelected then
                    highlight:SetColorTexture(1, 1, 1, 0.04)
                    labelFS:SetTextColor(1, 1, 1, 1)
                end
                menuItem:SetScript("OnEnter", function()
                    highlight:SetColorTexture(1, 1, 1, 0.08)
                    labelFS:SetTextColor(1, 1, 1, 1)
                end)
                menuItem:SetScript("OnLeave", function()
                    if isSelected then
                        highlight:SetColorTexture(1, 1, 1, 0.04)
                    else
                        highlight:SetColorTexture(1, 1, 1, 0)
                    end
                    labelFS:SetTextColor(0.75, 0.75, 0.75, 0.9)
                end)
                menuItem:SetScript("OnClick", function()
                    onClick()
                    CloseSnapMenu()
                    UpdateSnapLabel()
                end)
                itemList[#itemList + 1] = menuItem
                rowOffset = rowOffset - ITEM_H
                return menuItem
            end

            local curTarget = handle._snapTarget

            MakeItem(snapList, "All Elements", function()
                handle._snapTarget = nil
            end, not curTarget)

            -- None (per-mover snap disable)
            MakeItem(snapList, "None", function()
                handle._snapTarget = "_disable_"
            end, curTarget == "_disable_")

            -- Divider before element groups
            local div = snapList:CreateTexture(nil, "ARTWORK")
            div:SetHeight(1)
            div:SetColorTexture(1, 1, 1, 0.10)
            div:SetPoint("TOPLEFT", snapList, "TOPLEFT", 1, rowOffset - 4)
            div:SetPoint("TOPRIGHT", snapList, "TOPRIGHT", -1, rowOffset - 4)
            rowOffset = rowOffset - 9

            -- Registered element groups (Unit Frames, Action Bars, Resource Bars, etc.)
            RebuildRegisteredOrder()
            local regGroups = {} -- { groupName = { {key,label}, ... } }
            local regGroupOrder = {} -- preserve first-seen order
            for _, rk in ipairs(registeredOrder) do
                if rk ~= barId and handles[rk] and handles[rk]:IsShown() then
                    local element = registeredElements[rk]
                    local gName = element.group or "Other"
                    if not regGroups[gName] then
                        regGroups[gName] = {}
                        regGroupOrder[#regGroupOrder + 1] = gName
                    end
                    regGroups[gName][#regGroups[gName] + 1] = { key = rk, label = element.label or rk }
                end
            end
            -- Add visibility-only bars (MicroBar, BagBar) to "Other" group
            for _, barKey in ipairs(ALL_BAR_ORDER) do
                if GetVisibilityOnly()[barKey] and barKey ~= barId and handles[barKey] and handles[barKey]:IsShown() then
                    if not regGroups["Other"] then
                        regGroups["Other"] = {}
                        regGroupOrder[#regGroupOrder + 1] = "Other"
                    end
                    regGroups["Other"][#regGroups["Other"] + 1] = { key = barKey, label = LM.GetBarLabel(barKey) }
                end
            end
            wipe(regSubMenus)
            for _, gName in ipairs(regGroupOrder) do
                local gElems = regGroups[gName]
                local regionItem = CreateFrame("Button", nil, snapList)
                regionItem:SetHeight(ITEM_H)
                regionItem:SetPoint("TOPLEFT", snapList, "TOPLEFT", 1, rowOffset)
                regionItem:SetPoint("TOPRIGHT", snapList, "TOPRIGHT", -1, rowOffset)
                regionItem:SetFrameLevel(snapList:GetFrameLevel() + 2)
                regionItem:RegisterForClicks("AnyUp")
                local rgHl = regionItem:CreateTexture(nil, "ARTWORK")
                rgHl:SetAllPoints()
                rgHl:SetColorTexture(1, 1, 1, 0)
                local rgLbl = regionItem:CreateFontString(nil, "OVERLAY")
                rgLbl:SetFont(FONT_PATH, 11, "OUTLINE, SLUG")
                rgLbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
                rgLbl:SetJustifyH("LEFT")
                rgLbl:SetPoint("LEFT", regionItem, "LEFT", 10, 0)
                rgLbl:SetText(CludesUI.L(gName))
                local rgArrow = regionItem:CreateTexture(nil, "ARTWORK")
                rgArrow:SetSize(10, 10)
                rgArrow:SetPoint("RIGHT", regionItem, "RIGHT", -8, 0)
                rgArrow:SetTexture(ARROW_RIGHT_ICON)
                rgArrow:SetAlpha(0.7)
                rowOffset = rowOffset - ITEM_H

                local regionFlyout
                local function ShowRegSub()
                    -- Close any other open leaf sub-menus first
                    for otherName, rs in pairs(regSubMenus) do
                        if otherName ~= gName and rs and rs:IsShown() then
                            rs:Hide()
                        end
                    end
                    if regionFlyout then
                        for _, childFrame in ipairs({ regionFlyout:GetChildren() }) do
                            childFrame:Hide()
                            childFrame:SetParent(nil)
                        end
                        for _, tex in ipairs({ regionFlyout:GetRegions() }) do
                            if tex.Hide then
                                tex:Hide()
                            end
                        end
                    end
                    regionFlyout = regionFlyout or CreateFrame("Frame", nil, LM.unlockFrame)
                    regionFlyout:SetFrameStrata("FULLSCREEN_DIALOG")
                    LM.SetMoverOverlayLevel(regionFlyout, 10)
                    regionFlyout:SetClampedToScreen(true)
                    regionFlyout:SetSize(DD_W, 10)
                    regionFlyout:SetPoint("TOPLEFT", regionItem, "TOPRIGHT", 2, 0)
                    local rsBg = regionFlyout:CreateTexture(nil, "BACKGROUND")
                    rsBg:SetAllPoints()
                    rsBg:SetColorTexture(0.088, 0.098, 0.111, 0.95)
                    CludesUI.MakeBorder(regionFlyout, 1, 1, 1, 0.20)
                    CludesUI.AccentCap(regionFlyout)
                    local rsYOff = -4
                    for _, eInfo in ipairs(gElems) do
                        local ek, eLbl = eInfo.key, eInfo.label
                        local isSel = (curTarget == ek)
                        local subItem = CreateFrame("Button", nil, regionFlyout)
                        subItem:SetHeight(ITEM_H)
                        subItem:SetPoint("TOPLEFT", regionFlyout, "TOPLEFT", 1, rsYOff)
                        subItem:SetPoint("TOPRIGHT", regionFlyout, "TOPRIGHT", -1, rsYOff)
                        subItem:SetFrameLevel(regionFlyout:GetFrameLevel() + 2)
                        subItem:RegisterForClicks("AnyUp")
                        local subHighlight = subItem:CreateTexture(nil, "ARTWORK")
                        subHighlight:SetAllPoints()
                        subHighlight:SetColorTexture(1, 1, 1, isSel and 0.04 or 0)
                        local subLabel = subItem:CreateFontString(nil, "OVERLAY")
                        subLabel:SetFont(FONT_PATH, 11, "OUTLINE, SLUG")
                        subLabel:SetTextColor(0.75, 0.75, 0.75, 0.9)
                        subLabel:SetJustifyH("LEFT")
                        subLabel:SetPoint("LEFT", subItem, "LEFT", 10, 0)
                        subLabel:SetText(CludesUI.L(eLbl))
                        if isSel then
                            subLabel:SetTextColor(1, 1, 1, 1)
                        end
                        subItem:SetScript("OnEnter", function()
                            subHighlight:SetColorTexture(1, 1, 1, 0.08)
                            subLabel:SetTextColor(1, 1, 1, 1)
                        end)
                        subItem:SetScript("OnLeave", function()
                            subHighlight:SetColorTexture(1, 1, 1, isSel and 0.04 or 0)
                            subLabel:SetTextColor(0.75, 0.75, 0.75, 0.9)
                        end)
                        subItem:SetScript("OnClick", function()
                            handle._snapTarget = ek
                            CloseSnapMenu()
                            UpdateSnapLabel()
                        end)
                        rsYOff = rsYOff - ITEM_H
                    end
                    regionFlyout:SetHeight(-rsYOff + 4)
                    -- Width: fit the widest label + left padding (10) + right spacing (10) + border (2)
                    local rsMaxW = DD_W
                    for _, eInfo in ipairs(gElems) do
                        local tw = (CludesUI.MeasureText and CludesUI.MeasureText(eInfo.label, FONT_PATH, 11))
                            or 0
                        local needed = 10 + tw + 10 + 2
                        if needed > rsMaxW then
                            rsMaxW = needed
                        end
                    end
                    regionFlyout:SetWidth(rsMaxW)
                    regionFlyout:EnableMouse(true)
                    regionFlyout:SetScript("OnLeave", function(self)
                        C_Timer.After(0.05, function()
                            if self:IsShown() and not self:IsMouseOver() and not regionItem:IsMouseOver() then
                                self:Hide()
                            end
                        end)
                    end)
                    regionFlyout:Show()
                    regSubMenus[gName] = regionFlyout
                end

                regionItem:SetScript("OnEnter", function()
                    rgHl:SetColorTexture(1, 1, 1, 0.08)
                    rgLbl:SetTextColor(1, 1, 1, 1)
                    rgArrow:SetAlpha(0.9)
                    ShowRegSub()
                end)
                regionItem:SetScript("OnLeave", function()
                    rgHl:SetColorTexture(1, 1, 1, 0)
                    rgLbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
                    rgArrow:SetAlpha(0.5)
                    C_Timer.After(0.05, function()
                        local rs = regSubMenus[gName]
                        if rs and rs:IsShown() and not rs:IsMouseOver() and not regionItem:IsMouseOver() then
                            rs:Hide()
                        end
                    end)
                end)
            end

            snapList:SetHeight(-rowOffset + 4)
            snapList:Show()
        end

        -- Click-catcher: full-screen invisible frame that closes the menu when clicking elsewhere
        local snapClickCatcher
        local function ShowClickCatcher()
            if not snapClickCatcher then
                snapClickCatcher = CreateFrame("Button", nil, LM.unlockFrame)
                snapClickCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
                LM.SetMoverOverlayLevel(snapClickCatcher, -1)
                snapClickCatcher:SetAllPoints(UIParent)
                snapClickCatcher._umCatcher = true -- not an element for the hover bar
                snapClickCatcher:RegisterForClicks("AnyUp")
                snapClickCatcher:SetScript("OnClick", function()
                    CloseSnapMenu()
                end)
            end
            snapClickCatcher:Show()
        end
        local function HideClickCatcher()
            if snapClickCatcher then
                snapClickCatcher:Hide()
            end
        end

        local origCloseSnapMenu = CloseSnapMenu
        CloseSnapMenu = function()
            origCloseSnapMenu()
            HideClickCatcher()
            handle._menuOpen = false
        end

        snapDropdown:SetScript("OnClick", function()
            -- Block opening when global snap is disabled
            if not LM.snapEnabled then
                return
            end
            if snapList and snapList:IsShown() then
                CloseSnapMenu()
            else
                handle._menuOpen = true
                BuildSnapMenu()
                ShowClickCatcher()
            end
        end)

        -- Also close menu when dropdown hides (e.g. mover deselected)
        snapDropdown:SetScript("OnHide", CloseSnapMenu)

        ---------------------------------------------------------------------------
        --  Layout: cog flush with mover top-right (flips below if near screen top)
        ---------------------------------------------------------------------------
        local TOOLBAR_FLIP_THRESHOLD = 50 -- px from screen top to flip toolbar below

        local function IsNearScreenTop()
            local mTop = handle:GetTop()
            if not mTop then
                return false
            end
            local uiZoom = UIParent:GetEffectiveScale()
            local mS = handle:GetEffectiveScale()
            local screenTop = UIParent:GetHeight()
            local moverTopUI = mTop * mS / uiZoom
            return (screenTop - moverTopUI) < TOOLBAR_FLIP_THRESHOLD
        end
        handle._isNearScreenTop = IsNearScreenTop

        local function AnchorToolbarToMover()
            gearButton:ClearAllPoints()
            gearButton:SetPoint("TOPRIGHT", handle, "TOPRIGHT", -1, -1)
        end
        handle._anchorToolbar = AnchorToolbarToMover
        AnchorToolbarToMover()

        -- Hide orientation button for visibility-only bars or bars without layout support
        local isVisOnly = GetVisibilityOnly()[barId] or not (BAR_LOOKUP and BAR_LOOKUP[barId])

        handle._cogBtn = gearButton
        handle._actionBtns = { gearButton }

        -- Open snap menu helper (called from right-click handler)
        handle._openSnapMenu = function()
            handle._menuOpen = true
            BuildSnapMenu()
            ShowClickCatcher()
        end
        handle._isVisOnly = isVisOnly
        handle._snapTarget = nil -- per-mover snap target (nil = auto)
        handle._updateSnapLabel = UpdateSnapLabel
        RefreshSnapDDState() -- apply initial grayed-out state if snap is disabled

        ---------------------------------------------------------------------------
        --  Cog settings menu (Reset / Center / Orientation)
        ---------------------------------------------------------------------------
        local gearMenu
        local cogClickCatcher

        local function CloseCogMenu()
            if gearMenu then
                gearMenu:Hide()
            end
            if handle._cogEdgeSub then
                handle._cogEdgeSub:Hide()
            end
            if cogClickCatcher then
                cogClickCatcher:Hide()
            end
            handle._menuOpen = false
            handle._syncCogPos = nil
            handle._syncCogSize = nil
        end

        local function BuildCogMenu()
            if handle._cogEdgeSub then
                handle._cogEdgeSub:Hide()
            end
            -- A fresh build shows the links as they stand (see CloseEdgeSub).
            handle._cogEdgeDirty = nil
            -- Cleared up front: the rows below point these at this open's boxes, and
            -- a box from an earlier open may now serve another row.
            handle._syncCogPos = nil
            handle._syncCogSize = nil
            if not gearMenu then
                gearMenu = CreateFrame("Frame", nil, LM.unlockFrame)
                gearMenu:SetFrameStrata("FULLSCREEN_DIALOG")
                LM.SetMoverOverlayLevel(gearMenu)
                -- Built once: background, border and the arrow-key hint at the top.
                MenuPool.Chrome(gearMenu)
                local hintText = gearMenu:CreateFontString(nil, "OVERLAY")
                CludesUI.PrimeFontShadow(hintText, true)
                hintText:SetFont(FONT_PATH, 10, "")
                hintText:SetTextColor(0.7, 0.7, 0.7, 0.85)
                hintText:SetJustifyH("CENTER")
                hintText:SetWordWrap(true)
                hintText:SetPoint("TOPLEFT", gearMenu, "TOPLEFT", 8, -8)
                hintText:SetPoint("TOPRIGHT", gearMenu, "TOPRIGHT", -8, -8)
                gearMenu._hintFS = hintText
            end
            gearMenu:SetFrameStrata("FULLSCREEN_DIALOG")
            LM.SetMoverOverlayLevel(gearMenu)
            gearMenu:SetClampedToScreen(true)
            gearMenu:SetSize(DD_W + 60, 10)
            gearMenu:SetPoint("TOPLEFT", gearButton, "BOTTOMLEFT", 0, -2)
            gearMenu:EnableMouse(true)
            MenuPool.Begin(gearMenu, true, true)

            local ITEM_H = 24
            local rowOffset = -4

            -- Arrow-key hint at the very top (centered). Shown for every element since
            -- arrow keys nudge the selected element 1px in any direction.
            do
                local hintText = gearMenu._hintFS
                hintText:SetText(
                    CludesUI.L("Use arrow keys to move selected element 1px any direction")
                        .. ". "
                        .. CludesUI.L("Shift+Right Click to temporarily hide overlay")
                )
                local hintH = hintText:GetStringHeight()
                if not hintH or hintH < 1 then
                    hintH = 28
                end
                rowOffset = rowOffset - (hintH + 10)

                -- Divider below the hint
                MenuPool.Div(gearMenu, rowOffset - 4, Pix and Pix.mult or 1)
                rowOffset = rowOffset - 9
            end

            -- "Element Options" -- navigate to this element's settings page (top of menu)
            local settingsMap = CludesUI._ELEMENT_SETTINGS_MAP[barId]
            -- Cooldown Manager bars use dynamic per-bar keys ("CDM_<key>" / "TBB_<idx>"),
            -- so they miss the exact lookup; resolve them to their shared tab entry by prefix.
            if not settingsMap then
                if barId:sub(1, 4) == "CDM_" then
                    settingsMap = CludesUI._ELEMENT_SETTINGS_MAP["CDM_"]
                elseif barId:sub(1, 4) == "TBB_" or barId:sub(1, 5) == "TBBG_" then
                    settingsMap = CludesUI._ELEMENT_SETTINGS_MAP["TBB_"]
                elseif barId:sub(1, 7) == "EDM_Win" then
                    settingsMap = CludesUI._ELEMENT_SETTINGS_MAP["EDM_Win"]
                end
            end
            -- Queue Status is a Blizzard-owned element with no CUI settings page; its
            -- "Element Options" opens Blizzard Edit Mode instead of navigating to a tab
            -- (the same action as clicking a Blizzard Edit Mode overlay in unlock mode).
            local opensEditMode = (barId == "QueueStatus")
            if settingsMap or opensEditMode then
                local optItem, optHl, optLbl = MenuPool.Item(gearMenu, rowOffset, ITEM_H)
                optLbl:SetText(CludesUI.L("Element Options"))
                optItem:SetScript("OnEnter", function()
                    optHl:SetColorTexture(1, 1, 1, 0.08)
                    optLbl:SetTextColor(1, 1, 1, 1)
                end)
                optItem:SetScript("OnLeave", function()
                    optHl:SetColorTexture(1, 1, 1, 0)
                    optLbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
                end)
                optItem:SetScript("OnClick", function()
                    CloseCogMenu()
                    if opensEditMode then
                        -- Open Blizzard Edit Mode, exactly as the Blizz-owned overlays do.
                        if InCombatLockdown() then
                            return
                        end
                        if EditModeManagerFrame then
                            mod.RequestClose(false, function()
                                ShowUIPanel(EditModeManagerFrame)
                            end)
                        end
                    else
                        mod.RequestClose(true, function()
                            CludesUI:NavigateToElementSettings(
                                settingsMap.module,
                                settingsMap.page,
                                settingsMap.sectionName,
                                settingsMap.preSelectFn,
                                settingsMap.highlightText
                            )
                        end)
                    end
                end)
                rowOffset = rowOffset - ITEM_H

                -- Divider after Element Options
                MenuPool.Div(gearMenu, rowOffset - 4, Pix and Pix.mult or 1)
                rowOffset = rowOffset - 9
            end

            -- Width / Height input fields (only for resizable elements)
            -- CDM bars skip width/height here; size is driven by icon count/size in the options panel
            local isCDMBar = barId:sub(1, 4) == "CDM_"
            if canResize and element then
                local ROW_H = 22
                local curW, curH = 0, 0
                if element.getSize then
                    curW, curH = element.getSize(barId)
                end

                -- Create both boxes upfront so each OnEnterPressed can update the other
                local wBox, hBox

                local function MakeSizeRow(dim, initVal)
                    local _, labelFS, checkBox = MenuPool.Field(gearMenu, rowOffset, ROW_H, true)
                    labelFS:SetText((CludesUI.L(dim)) or dim)

                    checkBox:SetNumeric(true)
                    checkBox:SetMaxLetters(5)
                    -- Display the element's native size (UI coords), matching getSize/setWidth
                    -- and the options sliders -- physical pixels (ToPixels) diverge from the actual setting at non-1.0 UI scales.
                    checkBox:SetNumber(floor((initVal or 0) + 0.5))

                    -- Disable if this element is width/height matched
                    local isWidth = (dim == "Width")
                    local matchTarget = isWidth and CludesUI.GetWidthMatchTarget(barId)
                        or (not isWidth and CludesUI.GetHeightMatchTarget(barId))
                    if matchTarget then
                        checkBox:Disable()
                        checkBox:SetTextColor(0.4, 0.4, 0.4, 0.7)
                        local targetName = LM.GetBarLabel(matchTarget) or matchTarget
                        checkBox:SetScript("OnEnter", function()
                            CludesUI.ShowWidgetTooltip(
                                checkBox,
                                isWidth
                                        and CludesUI.Lf(
                                            "Width matched to %1$s. Unmatch to edit.",
                                            CludesUI.L(targetName)
                                        )
                                    or CludesUI.Lf(
                                        "Height matched to %1$s. Unmatch to edit.",
                                        CludesUI.L(targetName)
                                    )
                            )
                        end)
                        checkBox:SetScript("OnLeave", function()
                            CludesUI.HideWidgetTooltip()
                        end)
                    end

                    checkBox:SetScript("OnEnterPressed", function(self)
                        -- Value is in the element's native UI coords (no physical-pixel conversion)
                        local value = math.max(1, math.floor(self:GetNumber() + 0.5))
                        local scrollBar = LM.GetBarFrame(barId)
                        local savedAlpha = scrollBar and CludesUI._GetFFD(scrollBar).restoreAlpha
                        if scrollBar and not savedAlpha then
                            CludesUI._UnlockSetBarAlpha(scrollBar, 0)
                        end
                        if dim == "Width" then
                            if element.setWidth then
                                element.setWidth(barId, value)
                            end
                            for childKey, targetBar in pairs(MatchH.GetWidthMatchDB() or {}) do
                                if targetBar == barId then
                                    MatchH.ApplyWidthMatch(childKey, barId)
                                end
                            end
                        else
                            if element.setHeight then
                                element.setHeight(barId, value)
                            end
                            for childKey, targetBar in pairs(MatchH.GetHeightMatchDB() or {}) do
                                if targetBar == barId then
                                    MatchH.ApplyHeightMatch(childKey, barId)
                                end
                            end
                        end
                        LM.hasChanges = true
                        self:ClearFocus()
                        CludesUI.RecenterBarAnchor(barId)
                        if scrollBar and not savedAlpha then
                            C_Timer.After(0, function()
                                CludesUI._UnlockSetBarAlpha(scrollBar, 1)
                            end)
                        end
                        local bm = handles[barId]
                        if bm then
                            bm:SyncSize()
                        end
                        for childKey, _ in pairs(handles) do
                            if handles[childKey] and handles[childKey].SyncSize then
                                local wm = MatchH.GetWidthMatchInfo(childKey)
                                local hm = MatchH.GetHeightMatchInfo(childKey)
                                if wm == barId or hm == barId then
                                    handles[childKey]:SyncSize()
                                end
                            end
                        end
                        -- Refresh both input boxes to reflect actual post-resize dimensions
                        if element.getSize then
                            local nw, nh = element.getSize(barId)
                            if wBox then
                                wBox:SetNumber(floor((nw or 0) + 0.5))
                            end
                            if hBox then
                                hBox:SetNumber(floor((nh or 0) + 0.5))
                            end
                        end
                        LM.PropagateAnchorChain(barId)
                    end)
                    checkBox:SetScript("OnEscapePressed", function(self)
                        self:ClearFocus()
                        if element.getSize then
                            local w2, h2 = element.getSize(barId)
                            self:SetNumber(floor((dim == "Width" and (w2 or 0) or (h2 or 0)) + 0.5))
                        end
                    end)
                    rowOffset = rowOffset - ROW_H
                    return checkBox
                end

                -- Special override sessions never offer the direct size inputs: element
                -- size is not an override aspect (only the wm/hm size companions are),
                -- so a resize here would write the SHARED module setting mid-session
                -- while looking like a per-group edit. Users resize from the options panel instead.
                if not isCDMBar and not CludesUI._specialUnlockGroup then
                    -- A size row shows only when the element has its setter.
                    wBox = element.setWidth and MakeSizeRow("Width", curW) or nil
                    hBox = element.setHeight and MakeSizeRow("Height", curH) or nil
                    -- Re-read both boxes after an Extra Width / Height commit.
                    handle._syncCogSize = function()
                        if not element.getSize then
                            return
                        end
                        local nw, nh = element.getSize(barId)
                        if wBox then
                            wBox:SetNumber(floor((nw or 0) + 0.5))
                        end
                        if hBox then
                            hBox:SetNumber(floor((nh or 0) + 0.5))
                        end
                    end
                end

                -- X Position / Y Position rows (screen coords from center)
                do
                    local sw = UIParent:GetWidth()
                    local sh = UIParent:GetHeight()
                    -- Current value of an axis as a physical-pixel COUNT, read from the
                    -- bar's LIVE geometry. Displaying pixel counts (not raw UIParent
                    -- units) makes +1 in the box equal exactly one physical pixel, i.e.
                    -- one arrow-key nudge; PP.mult is only 1 at pixel-perfect UI scale.
                    local function AxisToPx(ax)
                        local PPi = CludesUI and CludesUI.PP
                        if not PPi or not PPi.ToPixels then
                            return nil
                        end
                        -- STORED value first for unanchored CENTER/CENTER elements (same
                        -- reasoning as UpdateCoordText): the box must echo the user's own
                        -- typed value back; a live-derived center is off by half a pixel for odd-pixel-dimension frames.
                        local aiX = GetAnchorInfo(barId)
                        if not (aiX and aiX.target) then
                            local place = pendingPositions[barId]
                            if type(place) ~= "table" or place._anchored or not place.point then
                                local elemX = registeredElements[barId]
                                place = elemX and elemX.loadPosition and elemX.loadPosition(barId) or nil
                                if not place then
                                    place = LoadBarPosition(barId)
                                end
                            end
                            if
                                type(place) == "table"
                                and place.point == "CENTER"
                                and (place.relPoint or "CENTER") == "CENTER"
                                and place.x
                                and place.y
                            then
                                -- Parity-aware like the live conversion below (odd dims store a half-pixel center).
                                local scrollBar = LM.GetBarFrame(barId)
                                local c2pS = PPi.CenterToPixels
                                if ax == "X" then
                                    if c2pS and scrollBar then
                                        return c2pS(
                                            place.x,
                                            scrollBar:GetWidth(),
                                            scrollBar:GetEffectiveScale()
                                        )
                                    end
                                    return PPi.ToPixels(place.x)
                                end
                                if c2pS and scrollBar then
                                    return c2pS(place.y, scrollBar:GetHeight(), scrollBar:GetEffectiveScale())
                                end
                                return PPi.ToPixels(place.y)
                            end
                        end
                        local b = LM.GetBarFrame(barId)
                        if not b then
                            return nil
                        end
                        local boxLeft, bR = b:GetLeft(), b:GetRight()
                        local bT, bB = b:GetTop(), b:GetBottom()
                        if not (boxLeft and bR and bT and bB) then
                            return nil
                        end
                        local scaleRatio = b:GetEffectiveScale() / UIParent:GetEffectiveScale()
                        -- Parity-aware live conversion: odd-pixel dims rest their
                        -- center on a half pixel; plain ToPixels reads that back
                        -- one high, so deltas computed from it move the frame to
                        -- the -0.5 side (1px off the stored-value convention).
                        local c2p = PPi.CenterToPixels
                        if ax == "X" then
                            local liveCX = ((boxLeft + bR) * 0.5 * scaleRatio) - sw * 0.5
                            if c2p then
                                return c2p(liveCX, b:GetWidth(), b:GetEffectiveScale())
                            end
                            return PPi.ToPixels(liveCX)
                        end
                        local liveCY = ((bT + bB) * 0.5 * scaleRatio) - sh * 0.5
                        if c2p then
                            return c2p(liveCY, b:GetHeight(), b:GetEffectiveScale())
                        end
                        return PPi.ToPixels(liveCY)
                    end

                    local function MakePosRow(dim, initVal)
                        local _, labelFS, checkBox = MenuPool.Field(gearMenu, rowOffset, ROW_H, true)
                        labelFS:SetText(dim == "X" and CludesUI.L("X Position") or CludesUI.L("Y Position"))

                        checkBox:SetNumeric(false)
                        checkBox:SetMaxLetters(6)
                        checkBox:SetText(tostring(initVal))

                        checkBox:SetScript("OnEnterPressed", function(self)
                            local value = tonumber(self:GetText())
                            self:ClearFocus()
                            if not value then
                                return
                            end
                            local PPi = CludesUI and CludesUI.PP
                            if InCombatLockdown() or not PPi then
                                return
                            end
                            -- Current value from LIVE geometry (never the stale moverCX).
                            local curPx = AxisToPx(dim)
                            if not curPx then
                                return
                            end
                            local deltaPx = value - curPx
                            if deltaPx ~= 0 then
                                -- One physical pixel == PP.mult UIParent units. Apply an
                                -- exact integer-pixel delta through the SAME primitive the
                                -- arrow keys use, so anchored/unanchored handling, the
                                -- pending-save capture, and the mover-center re-sync all
                                -- match the proven path: no second snap, no lost move.
                                local stepUnits = PPi.FromPixels(deltaPx)
                                if dim == "X" then
                                    CludesUI._unlockNudge(stepUnits, 0, handle, true)
                                else
                                    CludesUI._unlockNudge(0, stepUnits, handle, true)
                                end
                            end
                            if handle.ReanchorToBar then
                                handle:ReanchorToBar()
                            end
                            -- Re-sync the text to where the bar ACTUALLY landed so it can
                            -- never snap back to the old number.
                            local landed = AxisToPx(dim)
                            if landed then
                                self:SetText(tostring(landed))
                            end
                        end)
                        checkBox:SetScript("OnEscapePressed", function(self)
                            self:ClearFocus()
                            -- Discard typed text; show the bar's actual current value.
                            local cur = AxisToPx(dim)
                            self:SetText(tostring(cur or initVal))
                        end)
                        rowOffset = rowOffset - ROW_H
                        return checkBox
                    end

                    local xBox = MakePosRow("X", AxisToPx("X") or 0)
                    local yBox = MakePosRow("Y", AxisToPx("Y") or 0)
                    -- Let arrow-key nudges (while the cog is open) refresh these boxes
                    -- so they stay in lockstep with the element and the floating overlay.
                    handle._syncCogPos = function()
                        if xBox then
                            local px = AxisToPx("X")
                            if px then
                                xBox:SetText(tostring(px))
                            end
                        end
                        if yBox then
                            local py = AxisToPx("Y")
                            if py then
                                yBox:SetText(tostring(py))
                            end
                        end
                    end
                end

                -- Divider after size/position inputs
                MenuPool.Div(gearMenu, rowOffset - 4, Pix and Pix.mult or 1)
                rowOffset = rowOffset - 9
            end

            -- Extra Width / Extra Height (matched elements only): whole physical pixels
            -- added to the size the match gives, typed like the Offset X/Y rows below
            -- (Enter applies, Escape reverts). Not gated on canResize: CDM bars and
            -- tracking bars are sized by their matches too. Hidden while the look
            -- fixes the size or the element refuses matches right now.
            do
                local wT = MatchH.GetWidthMatchInfo(barId)
                local hT = MatchH.GetHeightMatchInfo(barId)
                if
                    (wT or hT)
                    and not InCombatLockdown()
                    and not (element and element.sizeFixedByLook)
                    and not (element and element.matchUnavailable and element.matchUnavailable(barId))
                then
                    local XROW_H = 22
                    local function ExtraText(dim)
                        return tostring(CludesUI.GetMatchExtra(dim, barId) or 0)
                    end
                    local function MakeExtraRow(textValue, dim)
                        local _, labelFS, checkBox = MenuPool.Field(gearMenu, rowOffset, XROW_H, true)
                        labelFS:SetWordWrap(false)
                        labelFS:SetText(textValue)
                        checkBox:SetNumeric(false)
                        checkBox:SetMaxLetters(4)
                        checkBox:SetText(ExtraText(dim))
                        -- Enter applies (clamped to -100..100 in the commit), Escape
                        -- reverts; the box then re-reads the store, so it only ever
                        -- shows a value that landed.
                        checkBox:SetScript("OnEnterPressed", function(self)
                            self:ClearFocus()
                            local value = tonumber(self:GetText())
                            if value and not InCombatLockdown() then
                                MatchH.CommitMatchExtra(dim, barId, value)
                                -- An anchored element may have moved with its new size.
                                if handle._syncCogPos then
                                    handle._syncCogPos()
                                end
                                if handle._syncCogSize then
                                    handle._syncCogSize()
                                end
                            end
                            self:SetText(ExtraText(dim))
                        end)
                        checkBox:SetScript("OnEscapePressed", function(self)
                            self:SetText(ExtraText(dim))
                            self:ClearFocus()
                        end)
                        rowOffset = rowOffset - XROW_H
                    end
                    if wT then
                        MakeExtraRow(CludesUI.L("Extra Width"), "w")
                    end
                    if hT then
                        MakeExtraRow(CludesUI.L("Extra Height"), "h")
                    end
                    MenuPool.Div(gearMenu, rowOffset - 4, Pix and Pix.mult or 1)
                    rowOffset = rowOffset - 9
                end
            end

            -- Anchor rows (anchored elements only): the target this element is linked
            -- to, and the offset a drag or a nudge left between the two, typed in
            -- place. Nothing here positions an element differently from a drag: a
            -- typed offset is a nudge by the difference. Rows share the size/position
            -- rows' shape above.
            do
                local aiM = GetAnchorInfo(barId)
                if aiM and aiM.target and not InCombatLockdown() then
                    local AROW_H = 22
                    local tgtName = LM.GetBarLabel(aiM.target) or aiM.target
                    local function MakeAnchorRow(textValue, withBox)
                        local rowFrame, labelFS, checkBox = MenuPool.Field(gearMenu, rowOffset, AROW_H, withBox)
                        labelFS:SetWordWrap(false)
                        labelFS:SetText(textValue)
                        rowOffset = rowOffset - AROW_H
                        return rowFrame, labelFS, checkBox
                    end
                    do
                        local _, labelFS = MakeAnchorRow(CludesUI.Lf("Anchored to: %1$s", tgtName))
                        labelFS:SetTextColor(0.55, 0.55, 0.55, 0.9)
                    end
                    if aiM.mode == "POINT" then
                        local _, labelFS = MakeAnchorRow(mod.PointAnchors.Description(aiM))
                        labelFS:SetTextColor(1, 0.35, 0.35, 0.9)
                    end
                    -- Offset X / Offset Y: typed values, Enter applies, Escape reverts.
                    -- Physical pixels in the box, units in the record, like the X/Y
                    -- Position boxes (AxisToPx): +1 here is one pixel, one nudge. A typed
                    -- value drives the SAME pixel-exact nudge the arrow keys and the X/Y
                    -- boxes use, by the difference from the record, so the anchored move,
                    -- the pending-save capture and the mover re-sync all follow the proven
                    -- path (a position-locked mover refuses it there too); the box then
                    -- re-reads the record, so it can never show a number that did not land.
                    local PPo = CludesUI and CludesUI.PP
                    local function OffsetPx(key)
                        local a = GetAnchorInfo(barId)
                        local v = a and a[key] or 0
                        if PPo and PPo.ToPixels then
                            v = PPo.ToPixels(v)
                        end
                        return math.floor(v + 0.5)
                    end
                    local function OffsetText(key)
                        return tostring(OffsetPx(key))
                    end
                    local function MakeOffsetRow(textValue, key)
                        local _, _, checkBox = MakeAnchorRow(textValue, true)
                        checkBox:SetNumeric(false)
                        checkBox:SetMaxLetters(6)
                        checkBox:SetText(OffsetText(key))
                        local function Commit(self)
                            local value = tonumber(self:GetText())
                            if value and not InCombatLockdown() and PPo and PPo.FromPixels then
                                local deltaPx = math.floor(value + 0.5) - OffsetPx(key)
                                if deltaPx ~= 0 then
                                    local stepUnits = PPo.FromPixels(deltaPx)
                                    if key == "offsetX" then
                                        CludesUI._unlockNudge(stepUnits, 0, handle, true)
                                    else
                                        CludesUI._unlockNudge(0, stepUnits, handle, true)
                                    end
                                    -- The bar just moved: the X/Y Position boxes follow right away.
                                    if handle._syncCogPos then
                                        handle._syncCogPos()
                                    end
                                end
                            end
                            self:SetText(OffsetText(key))
                        end
                        -- Enter applies, Escape reverts; losing focus does neither, like
                        -- the X/Y Position boxes above.
                        checkBox:SetScript("OnEnterPressed", function(self)
                            self:ClearFocus()
                            Commit(self)
                        end)
                        checkBox:SetScript("OnEscapePressed", function(self)
                            self:SetText(OffsetText(key))
                            self:ClearFocus()
                        end)
                        return checkBox
                    end
                    local oxBox = MakeOffsetRow(CludesUI.L("Offset X"), "offsetX")
                    local oyBox = MakeOffsetRow(CludesUI.L("Offset Y"), "offsetY")
                    -- Arrow-key nudges move the offsets underneath: keep these boxes in
                    -- lockstep, the same way the X/Y boxes are.
                    local prevSync = handle._syncCogPos
                    handle._syncCogPos = function()
                        if prevSync then
                            prevSync()
                        end
                        if not oxBox:HasFocus() then
                            oxBox:SetText(OffsetText("offsetX"))
                        end
                        if not oyBox:HasFocus() then
                            oyBox:SetText(OffsetText("offsetY"))
                        end
                    end
                    MenuPool.Div(gearMenu, rowOffset - 4, Pix and Pix.mult or 1)
                    rowOffset = rowOffset - 9
                end
            end
            -- Snap Target: enter pick mode or clear existing target
            local selElemItem, selElemHl, selElemLbl = MenuPool.Item(gearMenu, rowOffset, ITEM_H)
            local curTgt = handle._snapTarget
            local hasTarget = curTgt and curTgt ~= "_disable_" and curTgt ~= "_select_"
            if hasTarget then
                local tgtName = LM.GetBarLabel(curTgt) or curTgt
                selElemLbl:SetText(CludesUI.Lf("Snap Target: %1$s", "|cFF4CC9F0" .. tgtName .. "|r"))
                selElemLbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
            else
                selElemLbl:SetText(CludesUI.L("Select Snap Target"))
                selElemLbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
            end
            selElemItem:SetScript("OnEnter", function()
                selElemHl:SetColorTexture(1, 1, 1, 0.08)
                selElemLbl:SetTextColor(1, 1, 1, 1)
            end)
            selElemItem:SetScript("OnLeave", function()
                selElemHl:SetColorTexture(1, 1, 1, 0)
                selElemLbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
            end)
            selElemItem:SetScript("OnClick", function()
                if hasTarget then
                    handle._snapTarget = nil
                    UpdateSnapLabel()
                    CloseCogMenu()
                else
                    handle._preSelectTarget = handle._snapTarget
                    handle._snapTarget = "_select_"
                    LM.selectElementPicker = handle
                    FadeOverlayForSelectElement(true)
                    UpdateSnapLabel()
                    CloseCogMenu()
                end
            end)
            rowOffset = rowOffset - ITEM_H

            -- Helper: menu action item
            local function MakeActionItem(textValue, onClick, hoverFullText)
                local menuItem, highlight, labelFS = MenuPool.Item(gearMenu, rowOffset, ITEM_H)
                -- Cap the label at the row width, ending 5px before the row edge,
                -- so long dynamic labels truncate instead of spilling past the menu.
                labelFS:SetPoint("RIGHT", menuItem, "RIGHT", -5, 0)
                labelFS:SetWordWrap(false)
                labelFS:SetText(CludesUI.L(textValue))
                menuItem:SetScript("OnEnter", function()
                    highlight:SetColorTexture(1, 1, 1, 0.08)
                    labelFS:SetTextColor(1, 1, 1, 1)
                    -- Rows that opted in surface their full text while truncated.
                    if
                        hoverFullText
                        and CludesUI.ShowWidgetTooltip
                        and labelFS:GetStringWidth() > labelFS:GetWidth() + 0.5
                    then
                        CludesUI.ShowWidgetTooltip(menuItem, hoverFullText)
                    end
                end)
                menuItem:SetScript("OnLeave", function()
                    highlight:SetColorTexture(1, 1, 1, 0)
                    labelFS:SetTextColor(0.75, 0.75, 0.75, 0.9)
                    if hoverFullText and CludesUI.HideWidgetTooltip then
                        CludesUI.HideWidgetTooltip()
                    end
                end)
                menuItem:SetScript("OnClick", function()
                    if hoverFullText and CludesUI.HideWidgetTooltip then
                        CludesUI.HideWidgetTooltip()
                    end
                    CloseCogMenu()
                    onClick()
                end)
                rowOffset = rowOffset - ITEM_H
                return menuItem, labelFS, highlight
            end

            MakeActionItem("Center on Screen", function()
                if InCombatLockdown() then
                    return
                end
                local barKey = handle._barKey
                local PPc = CludesUI and CludesUI.PP
                local b = LM.GetBarFrame(barKey)
                if not b or not PPc or not PPc.ToPixels or not PPc.FromPixels then
                    return
                end
                -- Drive the move through the SAME stored-first delta path the cog X box
                -- uses when the user types 0: read current X from the pending/stored
                -- logical value for unanchored CENTER/CENTER elements (a live-derived
                -- center is off by half a pixel for odd-pixel-width frames), then
                -- NudgeMover accumulates prev + exact delta -- the stored X lands at
                -- exactly 0 and the readout echoes it (rewriting pendingPositions to a
                -- snapped TOPLEFT would bake the half pixel into the save).
                local curPx
                local aiC = GetAnchorInfo(barKey)
                if not (aiC and aiC.target) then
                    local place = pendingPositions[barKey]
                    if type(place) ~= "table" or place._anchored or not place.point then
                        local elemC = registeredElements[barKey]
                        place = elemC and elemC.loadPosition and elemC.loadPosition(barKey) or nil
                        if not place then
                            place = LoadBarPosition(barKey)
                        end
                    end
                    if
                        type(place) == "table"
                        and place.point == "CENTER"
                        and (place.relPoint or "CENTER") == "CENTER"
                        and place.x
                        and place.y
                    then
                        -- Parity-aware like the cog X box and readout (odd dims store a half-pixel center).
                        local c2pC = PPc.CenterToPixels
                        curPx = (c2pC and c2pC(place.x, b:GetWidth(), b:GetEffectiveScale()))
                            or PPc.ToPixels(place.x)
                    end
                end
                if curPx == nil then
                    -- Anchored/edge-stored/legacy formats: live-derived center, matching
                    -- the coordinate readout. Parity-aware conversion (CenterToPixels):
                    -- an odd-pixel-width frame's live center legitimately sits on a half
                    -- pixel, and plain ToPixels' tie-up round overshoots it by one --
                    -- the centering delta then lands the frame a full pixel left of an
                    -- identical element centered from its stored value ("dragged first, then centered" 1px mismatch).
                    local boxLeft, bR = b:GetLeft(), b:GetRight()
                    if not (boxLeft and bR) then
                        return
                    end
                    local scaleRatio = b:GetEffectiveScale() / UIParent:GetEffectiveScale()
                    local liveCX = ((boxLeft + bR) * 0.5 * scaleRatio) - UIParent:GetWidth() * 0.5
                    if PPc.CenterToPixels then
                        curPx = PPc.CenterToPixels(liveCX, b:GetWidth(), b:GetEffectiveScale())
                    else
                        curPx = PPc.ToPixels(liveCX)
                    end
                end
                if curPx and curPx ~= 0 then
                    CludesUI._unlockNudge(PPc.FromPixels(-curPx), 0, handle, true)
                end
                if handle.ReanchorToBar then
                    handle:ReanchorToBar()
                end
                -- Collapse the mover if the mouse moved away during centering
                C_Timer.After(0.15, function()
                    if not handle:IsMouseOver() and not (handle._cogBtn and handle._cogBtn:IsMouseOver()) then
                        if handle._hideOverlayText then
                            handle._hideOverlayText()
                        end
                        if LM.hoveredMover == handle then
                            LM.hoveredMover = nil
                        end
                        handle._hoverPending = false
                        if not handle._selected then
                            handle:SetFrameLevel(handle._baseLevel)
                        end
                    end
                end)
            end)

            -- Screen-edge links: the element stays put and keeps its distance to that
            -- edge on any screen size. The grow direction is left alone.
            --
            -- Not gated on noAnchorTo, unlike the link button: that flag means "must not
            -- become a child of another element", which a screen edge never makes it.
            -- The minimap and kin carry it while CludesUI owns their position. Only a
            -- Blizzard-owned position must stay out, or the two fight over the frame.
            local NO_SCREEN_ANCHOR = { QueueStatus = true } -- Blizzard Edit Mode owns it
            -- An element that places itself (ownsPosition: main chat) takes no
            -- screen-edge link either; one that keeps its own screen relation
            -- (getScreenPoint / setScreenPoint) gets the same menu through those.
            local seElem = registeredElements[barId]
            local ownScreen = seElem
                    and seElem.ownsPosition
                    and seElem.getScreenPoint
                    and seElem.setScreenPoint
                    and seElem
                or nil
            if
                not NO_SCREEN_ANCHOR[barId]
                and not mod.IsMoverPosLocked(barId)
                and (ownScreen or not (seElem and seElem.ownsPosition))
            then
                -- Primary link to a screen edge. The capture comes first: on an
                -- offset-less link ApplyAnchorPosition's side-snap branch stores the FLUSH
                -- offsets (0/0) before its no-move capture runs, and the next apply would
                -- snap the element onto the edge.
                local function LinkToScreenEdge(edgeKey, side)
                    if InCombatLockdown() then
                        return
                    end
                    local offX, offY = CludesUI._CaptureAnchorOffsets(barId, edgeKey, side)
                    if offX == nil then
                        return
                    end
                    SetAnchorInfo(barId, edgeKey, side, offX, offY)
                    LM.ApplyAnchorPosition(barId, edgeKey, side, nil, true)
                    if handle.RefreshAnchoredText then
                        handle:RefreshAnchoredText()
                    end
                end

                -- Which slot a picked edge lands in: with nothing anchored it becomes the
                -- primary; a primary screen edge on the SAME axis is replaced; when a
                -- cross-axis edge already holds the other axis the pick takes the primary
                -- slot (a plain element link there would govern nothing any more, and
                -- SetAnchorInfo keeps the other edge); otherwise it becomes the cross-axis
                -- edge and the primary keeps its own axis.
                local function SetScreenAnchor(edgeKey, side)
                    if InCombatLockdown() then
                        return
                    end
                    local anchorInfo = GetAnchorInfo(barId)
                    local dim = CludesUI._ScreenEdgeAxis(edgeKey)
                    local hasCrossEdge = anchorInfo
                        and anchorInfo.edge
                        and anchorInfo.edge.key
                        and CludesUI._ScreenEdgeAxis(anchorInfo.edge.key) ~= dim
                    if
                        not (anchorInfo and anchorInfo.target)
                        or CludesUI._ScreenEdgeAxis(anchorInfo.target) == dim
                        or hasCrossEdge
                    then
                        LinkToScreenEdge(edgeKey, side)
                        return
                    end
                    local off = CludesUI._CaptureScreenEdgeOffset(barId, edgeKey, side)
                    if off == nil then
                        return
                    end
                    -- A link that never got offsets (module default, imported layout) would
                    -- take the side-snap branch below and bank FLUSH offsets for the axis
                    -- the primary keeps. Fill them from the live rect first.
                    if anchorInfo.offsetX == nil or anchorInfo.offsetY == nil then
                        local pX, pY = CludesUI._CaptureAnchorOffsets(barId, anchorInfo.target, anchorInfo.side)
                        if pX == nil then
                            return
                        end
                        anchorInfo.offsetX, anchorInfo.offsetY = pX, pY
                    end
                    anchorInfo.edge = { key = edgeKey, side = side, offset = off }
                    CludesUI._anchorLinksStamp = (CludesUI._anchorLinksStamp or 0) + 1
                    LM.ApplyAnchorPosition(barId, anchorInfo.target, anchorInfo.side, nil, true)
                    LM.hasChanges = true
                    if handle.RefreshAnchoredText then
                        handle:RefreshAnchoredText()
                    end
                end
                -- The side says where the element sits relative to the strip, so it is
                -- the opposite of the edge it hugs; opp is the edge across the screen,
                -- which a checked edge greys out. The last row carries no key: it
                -- clears the links, which is what centered means here -- the element
                -- follows the screen center again, like every unanchored element.
                local EDGE_ITEMS = {
                    { key = "SCREEN_LEFT", side = "RIGHT", opp = "SCREEN_RIGHT", text = "Left" },
                    { key = "SCREEN_RIGHT", side = "LEFT", opp = "SCREEN_LEFT", text = "Right" },
                    { key = "SCREEN_TOP", side = "BOTTOM", opp = "SCREEN_BOTTOM", text = "Top" },
                    { key = "SCREEN_BOTTOM", side = "TOP", opp = "SCREEN_TOP", text = "Bottom" },
                    { text = "Center" },
                }

                -- The point an element with its own screen relation is left with when
                -- an edge is checked (on) or unchecked: Left and Right set or clear its
                -- horizontal half, Top and Bottom its vertical one. No edge is Center.
                local function ScreenPointWith(cur, edgeKey, on)
                    if not edgeKey then
                        return "CENTER"
                    end
                    cur = cur or "CENTER"
                    local v = cur:match("TOP") or cur:match("BOTTOM") or ""
                    local hgt = cur:match("LEFT") or cur:match("RIGHT") or ""
                    if edgeKey == "SCREEN_LEFT" then
                        hgt = on and "LEFT" or ""
                    elseif edgeKey == "SCREEN_RIGHT" then
                        hgt = on and "RIGHT" or ""
                    elseif edgeKey == "SCREEN_TOP" then
                        v = on and "TOP" or ""
                    else
                        v = on and "BOTTOM" or ""
                    end
                    local p = v .. hgt
                    return p ~= "" and p or "CENTER"
                end

                -- The cross-axis edge goes and the primary link takes its axis back.
                -- Rebase the link's offsets from the live rect first, or the element
                -- jumps to wherever that axis pointed before the edge took over.
                local function DropCrossEdge(anchorInfo)
                    anchorInfo.edge = nil
                    CludesUI._anchorLinksStamp = (CludesUI._anchorLinksStamp or 0) + 1
                    local offX, offY = CludesUI._CaptureAnchorOffsets(barId, anchorInfo.target, anchorInfo.side)
                    if offX ~= nil then
                        anchorInfo.offsetX, anchorInfo.offsetY = offX, offY
                    end
                    -- Growth bars: the pin outranks the offsets on its axis, so recapture
                    -- it from the current position too, the way the drag-stop path does.
                    if CludesUI._unlockCaptureGrowPin then
                        CludesUI._unlockCaptureGrowPin(barId, anchorInfo, anchorInfo.side)
                    end
                    LM.ApplyAnchorPosition(barId, anchorInfo.target, anchorInfo.side, nil, true)
                end

                -- Center: drop the SCREEN anchors only. A link to another element stays,
                -- that one belongs to the link button.
                local function ClearScreenAnchor()
                    if InCombatLockdown() then
                        return
                    end
                    local anchorInfo = GetAnchorInfo(barId)
                    if not anchorInfo then
                        return
                    end
                    local primaryIsEdge = anchorInfo.target and CludesUI.IsScreenEdgeKey(anchorInfo.target)
                    if not primaryIsEdge and not anchorInfo.edge then
                        return
                    end
                    if primaryIsEdge then
                        -- Nothing holds the element afterwards: clear the record and
                        -- capture the live position so Save & Exit persists it, the same
                        -- way the link button unlink path does.
                        ClearAnchorInfo(barId)
                        local barFrame = LM.GetBarFrame(barId)
                        if barFrame then
                            local pt, _, rpt, bx, by = barFrame:GetPoint(1)
                            if pt then
                                pendingPositions[barId] = { point = pt, relPoint = rpt, x = bx, y = by }
                            end
                        end
                    else
                        DropCrossEdge(anchorInfo)
                    end
                    LM.hasChanges = true
                    if handle.RefreshAnchoredText then
                        handle:RefreshAnchoredText()
                    end
                end

                -- Unchecking an edge drops that edge alone. A primary edge hands its
                -- slot to the cross-axis edge when there is one (the link a pick of
                -- that edge makes); a lone primary edge goes the way Center takes it.
                local function DropScreenEdge(edgeKey)
                    if InCombatLockdown() then
                        return
                    end
                    local anchorInfo = GetAnchorInfo(barId)
                    if not anchorInfo then
                        return
                    end
                    local cross = anchorInfo.edge
                    if cross and cross.key == edgeKey then
                        DropCrossEdge(anchorInfo)
                        LM.hasChanges = true
                        if handle.RefreshAnchoredText then
                            handle:RefreshAnchoredText()
                        end
                    elseif anchorInfo.target == edgeKey then
                        if cross and cross.key then
                            LinkToScreenEdge(cross.key, cross.side)
                        else
                            ClearScreenAnchor()
                        end
                    end
                end

                -- Divider: the screen anchor is a state, not another one-shot action.
                MenuPool.Div(gearMenu, rowOffset - 4, Pix and Pix.mult or 1)
                rowOffset = rowOffset - 9

                local seItem, seLbl, seHl = MakeActionItem("Relative to Screen", function() end)
                local seArrow = MenuPool.Arrow(seItem, ARROW_RIGHT_ICON, 0.7)
                -- Linked to an edge: the row wears the same orange as an anchored mover.
                local function SERestColor()
                    local linked
                    if ownScreen then
                        linked = ownScreen.getScreenPoint(barId) ~= "CENTER"
                    else
                        local anchorInfo = GetAnchorInfo(barId)
                        linked = anchorInfo
                            and (
                                (anchorInfo.target and CludesUI.IsScreenEdgeKey(anchorInfo.target))
                                or (anchorInfo.edge and anchorInfo.edge.key ~= nil)
                            )
                    end
                    if linked then
                        seLbl:SetTextColor(1, 0.7, 0.3, 1)
                    else
                        seLbl:SetTextColor(0.75, 0.75, 0.75, 0.9)
                    end
                end
                SERestColor()

                -- Leaving the flyout closes it. A check made in it changed the links
                -- the cog menu's anchor rows show, so the menu is built again then:
                -- built under the cursor, it would push the flyout away mid-pick.
                local function CloseEdgeSub(flyout)
                    flyout:Hide()
                    if handle._cogEdgeDirty and gearMenu and gearMenu:IsShown() then
                        BuildCogMenu()
                    end
                end

                local function ShowEdgeSub()
                    -- Built once per mover and kept on it, parented to unlockFrame;
                    -- CloseCogMenu and every BuildCogMenu hide it.
                    local edgeFlyout = handle._cogEdgeSub
                    if not edgeFlyout then
                        edgeFlyout = CreateFrame("Frame", nil, LM.unlockFrame)
                        handle._cogEdgeSub = edgeFlyout
                        edgeFlyout:SetFrameStrata("FULLSCREEN_DIALOG")
                        LM.SetMoverOverlayLevel(edgeFlyout, 4)
                        MenuPool.Chrome(edgeFlyout)
                    end
                    edgeFlyout:SetFrameStrata("FULLSCREEN_DIALOG")
                    LM.SetMoverOverlayLevel(edgeFlyout, 4)
                    edgeFlyout:SetClampedToScreen(true)
                    edgeFlyout:ClearAllPoints()
                    edgeFlyout:SetPoint("TOPLEFT", seItem, "TOPRIGHT", 2, 0)
                    MenuPool.Begin(edgeFlyout, false)
                    -- Two rows can be checked at once: a primary edge plus the cross-axis
                    -- one. Center is checked exactly while neither exists.
                    local curAi = GetAnchorInfo(barId)
                    local nowT = curAi and curAi.target
                    nowT = (nowT and CludesUI.IsScreenEdgeKey(nowT)) and nowT or nil
                    local curEdge = curAi and curAi.edge and curAi.edge.key or nil
                    local centered = curAi == nil
                    if ownScreen then
                        -- Its point gives both rows: the horizontal half and the
                        -- vertical one.
                        local p = ownScreen.getScreenPoint(barId) or "CENTER"
                        nowT = (p:find("LEFT", 1, true) and "SCREEN_LEFT")
                            or (p:find("RIGHT", 1, true) and "SCREEN_RIGHT")
                            or nil
                        curEdge = (p:find("TOP", 1, true) and "SCREEN_TOP")
                            or (p:find("BOTTOM", 1, true) and "SCREEN_BOTTOM")
                            or nil
                        centered = p == "CENTER"
                    end
                    -- A check box per row, and the flyout stays open: a click checks or
                    -- unchecks a row and the rows are drawn again in place.
                    local foci = GetMouseFoci()
                    local seY = -4
                    for idx = 1, #EDGE_ITEMS do
                        local e = EDGE_ITEMS[idx]
                        local checked = (e.key ~= nil and (e.key == nowT or e.key == curEdge))
                            or (e.key == nil and centered)
                        -- An edge cannot join the one across the screen from it, and
                        -- Center has nothing to clear while no screen edge is checked
                        -- (an element linked to another element only).
                        local disabled
                        if e.key then
                            disabled = e.opp == nowT or e.opp == curEdge
                        else
                            disabled = not centered and nowT == nil and curEdge == nil
                        end
                        local red, green, blue, a = 0.75, 0.75, 0.75, 0.9
                        if checked then
                            red, green, blue, a = 1, 0.7, 0.3, 1
                        end
                        if disabled then
                            a = 0.3
                        end
                        local subItem, subHighlight, subLabel = MenuPool.Item(edgeFlyout, seY, ITEM_H)
                        MenuPool.Check(subItem, checked, disabled)
                        subHighlight:SetColorTexture(1, 1, 1, checked and 0.04 or 0)
                        subLabel:SetTextColor(red, green, blue, a)
                        subLabel:SetPoint("RIGHT", subItem, "RIGHT", -8, 0)
                        subLabel:SetWordWrap(false)
                        subLabel:SetText(CludesUI.L(e.text))
                        if not disabled then
                            local function OnEnter()
                                subHighlight:SetColorTexture(1, 1, 1, 0.08)
                                if checked then
                                    subLabel:SetTextColor(1, 0.8, 0.5, 1)
                                else
                                    subLabel:SetTextColor(1, 1, 1, 1)
                                end
                                -- Preview: show the line the element would hold on to.
                                if e.key then
                                    CludesUI._ShowScreenEdgeMarker(e.key)
                                end
                            end
                            subItem:SetScript("OnEnter", OnEnter)
                            subItem:SetScript("OnLeave", function()
                                subHighlight:SetColorTexture(1, 1, 1, checked and 0.04 or 0)
                                subLabel:SetTextColor(red, green, blue, a)
                                if e.key then
                                    CludesUI._HideScreenEdgeMarker(e.key)
                                end
                            end)
                            subItem:SetScript("OnClick", function()
                                if InCombatLockdown() or (checked and not e.key) then
                                    return
                                end
                                if ownScreen then
                                    ownScreen.setScreenPoint(
                                        barId,
                                        ScreenPointWith(ownScreen.getScreenPoint(barId), e.key, not checked)
                                    )
                                elseif not e.key then
                                    ClearScreenAnchor()
                                elseif checked then
                                    DropScreenEdge(e.key)
                                else
                                    SetScreenAnchor(e.key, e.side)
                                end
                                handle._cogEdgeDirty = true
                                -- The anchor rows' offset boxes read the links live.
                                if handle._syncCogPos then
                                    handle._syncCogPos()
                                end
                                SERestColor()
                                ShowEdgeSub()
                            end)
                            -- The row just clicked is still under the cursor.
                            if foci and foci[1] == subItem then
                                OnEnter()
                            end
                        end
                        seY = seY - ITEM_H
                    end
                    MenuPool.End(edgeFlyout)
                    -- Fixed width: CludesUI.MeasureText does not exist (the other two
                    -- call sites in this file are dead code for the same reason), so a
                    -- measuring loop would always keep its minimum. The labels truncate
                    -- instead, so a long translation cannot spill past the background.
                    edgeFlyout:SetSize(DD_W, -seY + 4)
                    edgeFlyout:EnableMouse(true)
                    edgeFlyout:SetScript("OnLeave", function(self)
                        C_Timer.After(0.05, function()
                            if self:IsShown() and not self:IsMouseOver() and not seItem:IsMouseOver() then
                                CloseEdgeSub(self)
                            end
                        end)
                    end)
                    edgeFlyout:Show()
                end

                -- The row is a pooled one, so its hover handlers are set whole (the
                -- action row's highlight plus the arrow and the flyout), never hooked.
                seItem:SetScript("OnClick", ShowEdgeSub)
                seItem:SetScript("OnEnter", function()
                    seHl:SetColorTexture(1, 1, 1, 0.08)
                    seLbl:SetTextColor(1, 1, 1, 1)
                    seArrow:SetAlpha(0.9)
                    ShowEdgeSub()
                end)
                seItem:SetScript("OnLeave", function()
                    seHl:SetColorTexture(1, 1, 1, 0)
                    seArrow:SetAlpha(0.7)
                    SERestColor()
                    C_Timer.After(0.05, function()
                        local flyout = handle._cogEdgeSub
                        if flyout and flyout:IsShown() and not flyout:IsMouseOver() and not seItem:IsMouseOver() then
                            CloseEdgeSub(flyout)
                        end
                    end)
                end)
            end

            -- Toggle Orientation (hidden for vis-only bars)
            if not isVisOnly then
                MakeActionItem("Toggle Orientation", function()
                    if InCombatLockdown() then
                        return
                    end
                    if not ABAR then
                        return
                    end
                    ABAR:ToggleOrientationForBar(handle._barKey)
                    LM.hasChanges = true
                    DeferMoverSync(handles[handle._barKey], function(m)
                        m:Sync()
                    end, LM.GetBarFrame(handle._barKey))
                end)
            end

            -- Fallback Anchor: only for elements anchored to a target that can
            -- be absent (tracking bars / global groups per spec, pet frame with
            -- no pet). Captures the element's CURRENT position as the spot it
            -- falls back to whenever that target is missing.
            do
                local aiF = GetAnchorInfo(barId)
                local fbEligible = aiF
                    and aiF.target
                    and CludesUI.EligibleFallbackTarget
                    and CludesUI.EligibleFallbackTarget(aiF.target)
                if fbEligible then
                    MenuPool.Div(gearMenu, rowOffset - 4, Pix and Pix.mult or 1)
                    rowOffset = rowOffset - 9
                    -- fallback records need a target (a legacy record without
                    -- one, from the retired position-capture flow, reads as unset)
                    local hasFb = aiF.fallback ~= nil and aiF.fallback.target ~= nil
                    MakeActionItem(
                        hasFb and "Fallback Anchor: Change" or "Fallback Anchor: Select",
                        function()
                            if CludesUI._BeginFallbackAnchorPick then
                                CludesUI._BeginFallbackAnchorPick(handle)
                            end
                        end
                    )
                    if hasFb then
                        MakeActionItem("Fallback Anchor: Clear", function()
                            if CludesUI.ClearAnchorFallback then
                                CludesUI.ClearAnchorFallback(barId)
                            end
                        end)
                    end
                end
            end

            -- Override Anchor (Resource Bars): a per-spec-override-group alternate
            -- anchor, edited via a draggable gold ghost. Only offered for groups
            -- WITHOUT a custom unlock layout (a fork owns every position already).
            -- ONE "Override Anchor" row hover-opens an upward-building subnav of
            -- groups to add (the snap menu's regSub pattern); each existing entry
            -- gets an "Edit Override" row whose subnav offers Edit/Delete -- the
            -- menu stays a single line until overrides actually exist.
            do
                local ovGroups = CludesUI._OverrideAnchorEligible
                        and CludesUI._OverrideAnchorEligible(barId)
                        and CludesUI._OverrideAnchorGroups
                        and CludesUI._OverrideAnchorGroups()
                    or nil
                if ovGroups then
                    local OV_ARROW = "Interface\\AddOns\\CludesUI\\media\\icons\\right-arrow.png"
                    local ovOpenSub -- only one override subnav open at a time

                    local function OvSubRow(flyout, rsY, textValue, onClick)
                        local subItem, subHighlight, subLabel = MenuPool.Item(flyout, rsY, ITEM_H)
                        subLabel:SetText(textValue)
                        subItem:SetScript("OnEnter", function()
                            subHighlight:SetColorTexture(1, 1, 1, 0.08)
                            subLabel:SetTextColor(1, 1, 1, 1)
                        end)
                        subItem:SetScript("OnLeave", function()
                            subHighlight:SetColorTexture(1, 1, 1, 0)
                            subLabel:SetTextColor(0.75, 0.75, 0.75, 0.9)
                        end)
                        subItem:SetScript("OnClick", function()
                            CloseCogMenu()
                            onClick()
                        end)
                        return rsY - ITEM_H
                    end

                    -- Parent row with a right arrow; entries rebuilt on every
                    -- hover ({ text, fn } rows, { text, title = true } headers).
                    local function OvSubnavItem(textValue, buildEntries)
                        local menuItem, highlight, labelFS = MenuPool.Item(gearMenu, rowOffset, ITEM_H)
                        labelFS:SetPoint("RIGHT", menuItem, "RIGHT", -20, 0)
                        labelFS:SetWordWrap(false)
                        labelFS:SetText(CludesUI.L(textValue))
                        local arrow = MenuPool.Arrow(menuItem, OV_ARROW, 0.5)
                        local function ShowSub()
                            local flyout = menuItem._sub
                            if ovOpenSub and ovOpenSub ~= flyout and ovOpenSub:IsShown() then
                                ovOpenSub:Hide()
                            end
                            -- Kept on the pooled row and parented to the cog menu, so
                            -- closing the menu hides the subnav with it.
                            if not flyout then
                                flyout = CreateFrame("Frame", nil, gearMenu)
                                menuItem._sub = flyout
                                flyout:SetFrameStrata("FULLSCREEN_DIALOG")
                                LM.SetMoverOverlayLevel(flyout, 4)
                                MenuPool.Chrome(flyout)
                            end
                            flyout:SetFrameStrata("FULLSCREEN_DIALOG")
                            LM.SetMoverOverlayLevel(flyout, 4)
                            flyout:SetClampedToScreen(true)
                            -- Build UPWARD: the subnav's bottom is pinned level
                            -- with the row, so added rows extend toward the top.
                            flyout:ClearAllPoints()
                            flyout:SetPoint("BOTTOMLEFT", menuItem, "BOTTOMRIGHT", 2, 0)
                            MenuPool.Begin(flyout, false)
                            local entries = buildEntries()
                            local rsY = -4
                            local maxW = 140
                            for _, entry in ipairs(entries) do
                                if entry.title then
                                    local t = MenuPool.Title(flyout)
                                    t:SetPoint("TOPLEFT", flyout, "TOPLEFT", 10, rsY - 4)
                                    t:SetText(entry.text)
                                    rsY = rsY - 18
                                    MenuPool.Div(flyout, rsY - 2, 1)
                                    rsY = rsY - 5
                                else
                                    rsY = OvSubRow(flyout, rsY, entry.text, entry.fn)
                                end
                                local tw = (
                                    CludesUI.MeasureText
                                    and CludesUI.MeasureText(entry.text, FONT_PATH, entry.title and 10 or 11)
                                ) or 0
                                local needed = 10 + tw + 10 + 2
                                if needed > maxW then
                                    maxW = needed
                                end
                            end
                            MenuPool.End(flyout)
                            flyout:SetSize(maxW, -rsY + 4)
                            flyout:EnableMouse(true)
                            flyout:SetScript("OnLeave", function(self)
                                C_Timer.After(0.05, function()
                                    if
                                        self:IsShown()
                                        and not self:IsMouseOver()
                                        and not menuItem:IsMouseOver()
                                    then
                                        self:Hide()
                                    end
                                end)
                            end)
                            flyout:Show()
                            ovOpenSub = flyout
                        end
                        menuItem:SetScript("OnEnter", function()
                            highlight:SetColorTexture(1, 1, 1, 0.08)
                            labelFS:SetTextColor(1, 1, 1, 1)
                            arrow:SetAlpha(0.9)
                            ShowSub()
                        end)
                        menuItem:SetScript("OnLeave", function()
                            highlight:SetColorTexture(1, 1, 1, 0)
                            labelFS:SetTextColor(0.75, 0.75, 0.75, 0.9)
                            arrow:SetAlpha(0.5)
                            C_Timer.After(0.05, function()
                                local flyout = menuItem._sub
                                if
                                    flyout
                                    and flyout:IsShown()
                                    and not flyout:IsMouseOver()
                                    and not menuItem:IsMouseOver()
                                then
                                    flyout:Hide()
                                end
                            end)
                        end)
                        rowOffset = rowOffset - ITEM_H
                        return menuItem
                    end

                    MenuPool.Div(gearMenu, rowOffset - 4, Pix and Pix.mult or 1)
                    rowOffset = rowOffset - 9

                    local addable = {}
                    for _, og in ipairs(ovGroups) do
                        if
                            not (CludesUI._HasOverrideAnchor and CludesUI._HasOverrideAnchor(barId, og.id))
                        then
                            addable[#addable + 1] = og
                        end
                    end
                    if #addable > 0 then
                        OvSubnavItem("Override Anchor", function()
                            local entries = {}
                            for _, og in ipairs(addable) do
                                local groupId = og.id
                                entries[#entries + 1] = {
                                    text = og.name or ("Group " .. tostring(groupId)),
                                    fn = function()
                                        if CludesUI._BeginOverrideAnchorPick then
                                            CludesUI._BeginOverrideAnchorPick(handle, groupId)
                                        end
                                    end,
                                }
                            end
                            return entries
                        end)
                    end
                    for _, og in ipairs(ovGroups) do
                        if CludesUI._HasOverrideAnchor and CludesUI._HasOverrideAnchor(barId, og.id) then
                            local groupId = og.id
                            local gname = og.name or ("Group " .. tostring(groupId))
                            OvSubnavItem(CludesUI.Lf("Edit Override: %1$s", gname), function()
                                return {
                                    { text = gname, title = true },
                                    {
                                        text = CludesUI.L("Edit Anchor"),
                                        fn = function()
                                            if CludesUI._BeginOverrideAnchorPick then
                                                CludesUI._BeginOverrideAnchorPick(handle, groupId)
                                            end
                                        end,
                                    },
                                    {
                                        text = CludesUI.L("Delete Override Anchor"),
                                        fn = function()
                                            if CludesUI._ClearOverrideAnchor then
                                                CludesUI._ClearOverrideAnchor(barId, groupId)
                                            end
                                        end,
                                    },
                                }
                            end)
                        end
                    end
                end
            end
            MenuPool.End(gearMenu)

            gearMenu:SetHeight(-rowOffset + 4)
            gearMenu:Show()
        end

        -- Click-catcher for cog menu
        local function ShowCogClickCatcher()
            if not cogClickCatcher then
                cogClickCatcher = CreateFrame("Button", nil, LM.unlockFrame)
                cogClickCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
                LM.SetMoverOverlayLevel(cogClickCatcher, -1)
                cogClickCatcher:SetAllPoints(UIParent)
                cogClickCatcher._umCatcher = true -- not an element for the hover bar
                cogClickCatcher:RegisterForClicks("AnyUp")
                cogClickCatcher:SetScript("OnClick", function()
                    CloseCogMenu()
                end)
            end
            cogClickCatcher:Show()
        end

        gearButton:SetScript("OnClick", function()
            if gearMenu and gearMenu:IsShown() then
                CloseCogMenu()
            else
                SelectMover(handle)
                handle._menuOpen = true
                BuildCogMenu()
                ShowCogClickCatcher()
            end
        end)
        gearButton:SetScript("OnHide", CloseCogMenu)

        -- Expose cog menu opener on the mover (used by right-click handler)
        handle._openCogMenu = function()
            if gearMenu and gearMenu:IsShown() then
                CloseCogMenu()
            else
                SelectMover(handle)
                handle._menuOpen = true
                BuildCogMenu()
                ShowCogClickCatcher()
            end
        end

        -- Re-read this mover's name from its registered element. `label` above is
        -- a plain local captured once at CreateMover time -- RefreshAnchoredIdle
        -- (fired on every hover and anchor-state change, see ShowOverlayText /
        -- RefreshAnchoredText) closes over that SAME local and keeps re-painting it
        -- verbatim, so a caller that only did nameFS:SetText(...) directly would see
        -- the very next hover silently revert the text. Reassigning the local here
        -- (a plain Lua upvalue write, legal from any function sharing this closure)
        -- is what makes the change stick.
        function handle:UpdateLabel()
            labelText = LM.GetBarLabel(barId)
            RefreshAnchoredIdle()
        end

        -- Opt-in hover tooltip (element definition field `moverTooltip`, string or
        -- function): additive-only -- absent = the handlers no-op. Installed
        -- UNCONDITIONALLY and resolved LIVE from registeredElements, because movers
        -- persist for the whole session while elements re-register with
        -- state-dependent tooltips (CDM's Additional Bar Offset marker). Placed
        -- after every SetScript above so the HookScripts can never be replaced.
        -- Suppressed while dragging and in the pick/select modes (the base OnEnter
        -- early-returns there and a tooltip over the pickers would mislead).
        handle:HookScript("OnEnter", function()
            local el = registeredElements[barId]
            local tip = el and el.moverTooltip
            if not tip then
                return
            end
            if _mouseHeld or LM.pickMode or LM.selectElementPicker then
                return
            end
            if type(tip) == "function" then
                tip = tip(barId)
            end
            if tip and CludesUI.ShowWidgetTooltip then
                CludesUI.ShowWidgetTooltip(handle, tip)
            end
        end)
        handle:HookScript("OnLeave", function()
            CludesUI.HideWidgetTooltip()
        end)
        handle:HookScript("OnDragStart", function()
            CludesUI.HideWidgetTooltip()
        end)
        -- Element filter (CUI_UnlockMode_Filter.lua): a new or re-shown mover stays hidden while filtered.
        if LM.FilterOnShow then
            handle:HookScript("OnShow", LM.FilterOnShow)
            LM.FilterOnShow(handle)
        end

        handles[barId] = handle
        return handle
    end

    -- Override RegisterUnlockElements so that late-registering addons (e.g. CDM
    -- registering after a 0.5s timer) get movers spawned immediately if unlock
    -- mode is already open when they call in.
    do
        local _origRegister = CludesUI.RegisterUnlockElements
        function CludesUI:RegisterUnlockElements(elements, folder)
            _origRegister(self, elements, folder)
            if not LM.isUnlocked then
                return
            end
            -- Unlock mode is open -- spawn movers for any newly registered keys,
            -- and hide existing movers whose element is now intentionally hidden.
            local spawned = false
            for _, element in ipairs(elements) do
                local key = element.key
                if handles[key] then
                    -- Re-registration: hide mover if element is now hidden, and
                    -- RE-SHOW one whose element came back (e.g. a PAB bar
                    -- re-enabled mid-session -- the drop half always worked, the
                    -- restore half never did). Session temp-hides
                    -- (Shift+Right-Click) stay respected.
                    if element.isHidden and element.isHidden() then
                        handles[key]:Hide()
                    elseif not handles[key]:IsShown() and not handles[key]._tempHidden then
                        handles[key]:Sync()
                        handles[key]:SetAlpha(LM.darkOverlaysEnabled and 1 or MOVER_ALPHA)
                        handles[key]:Show()
                        spawned = true
                    end
                else
                    local m = CreateMover(key)
                    if m then
                        m:Sync()
                        m:SetAlpha(LM.darkOverlaysEnabled and 1 or MOVER_ALPHA)
                        m:Show()
                        spawned = true
                    end
                end
            end
            if spawned then
                SortMoverFrameLevels()
                ReapplyAllAnchors()
            end
        end
    end

    LM.CreateMover = CreateMover
end
