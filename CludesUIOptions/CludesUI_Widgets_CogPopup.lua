if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUI_Widgets_CogPopup.lua
--  BuildCogPopup, the shared cog settings popup. Reads BuildColorSwatch, so
--  it loads after CludesUI_Widgets_Color.lua.
--  DEFERRED: body runs on first CludesUI:EnsureLoaded() call, not at load.
-------------------------------------------------------------------------------
local CUI = _G.CludesUI
CUI._deferredInits[#CUI._deferredInits + 1] = function()
    -- Options page pool (CludesUI_FramePool.lua): frames made here on a pool
    -- host (a kept popup and every frame it hands out) are reset and dressed again
    -- by the next build instead of made anew; elsewhere this is CreateFrame.
    local CreateFrame = CUI._Pool.CreateFrame
    local PoolKept, PoolOwned = CUI._Pool.Kept, CUI._Pool.Owned
    -- Deferred work on a pooled frame stops once the frame was reset (dressed
    -- again for another use): its generation moved on, or it waits idle.
    local PoolGen, PoolIsIdle = CUI._Pool.Gen, CUI._Pool.IsIdle
    local Pix = CUI.PanelPP
    local SolidTex = CUI.SolidTex
    local MakeFont = CUI.MakeFont
    local MakeDropdownArrow = CUI.MakeDropdownArrow
    local EXPRESSWAY = CUI.EXPRESSWAY
    local CLUDES_GREEN = CUI.CLUDES_GREEN
    local BORDER_COLOR = CUI.BORDER_COLOR
    local WI = CUI._widgetInternals
    local PixelizeSliderCfg = WI.PixelizeSliderCfg
    local ResolveDisabledTip = CUI.ResolveDisabledTip
    local DDText = CUI.DDText
    local BuildSliderCore = CUI.BuildSliderCore
    local BuildDropdownControl = CUI.BuildDropdownControl
    local BuildToggleControl = CUI.BuildToggleControl
    local BuildColorSwatch = CUI.BuildColorSwatch

    -- One hidden font string measures the labels of every popup (made on the first).
    local measureFS
    -- Every popup made while the settings panel exists closes when the panel hides:
    -- ONE OnHide hook on the panel (installed with the first popup) over a weak set
    -- of the popups, hidden in the order they were made.
    local panelPopups = setmetatable({}, { __mode = "k" }) -- popup -> order made
    local panelPopupN, panelHooked = 0, false
    local hideList = {}
    local function PopupOrder(a, b) return panelPopups[a] < panelPopups[b] end
    local function HidePanelPopups()
        local num = 0
        for popFrame in pairs(panelPopups) do
            if popFrame:IsShown() then
                num = num + 1
                hideList[num] = popFrame
            end
        end
        if num > 1 then table.sort(hideList, PopupOrder) end
        for idx = 1, num do
            local popFrame = hideList[idx]
            hideList[idx] = nil
            if popFrame:IsShown() then popFrame:Hide() end
        end
    end

    -------------------------------------------------------------------------------
    --  BuildCogPopup -- reusable cog settings popup with consistent layout
    --  opts = { title = "Popup Title", rows = {
    --      { type="slider", label="Distance", min=-50, max=50, step=1, get=fn, set=fn },
    --      { type="toggle", label="Show Health Percent", get=fn, set=fn }, } }
    --  Returns: popupFrame, showFn(anchorBtn)
    --  The popup frame is kept per anchor button and set of shown rows (the options
    --  page pool), not per call: one anchor button opens one live popup. Two popups
    --  built from separate calls and opened from the same button would share the
    --  frame, the later open dressing it for its own rows.
    --
    --  Sections, in place of opts.rows:
    --  opts.sections = { { title = "Slot", rows = { ... }, hidden = fn, stackLast = true }, ... }
    --  opts.columnsFrom (2): from this many shown sections on, each shown section
    --      takes a column of its own, its title (accent) on top, side by side with
    --      a 1px divider between columns, opts.maxColumns (4) per band and further
    --      sections in a band below. Each column measures its own labels and sizes
    --      its sliders as a one-column popup does (opts.minWidth applies per column).
    --  Below columnsFrom the shown sections' rows stack in one column with no
    --      titles, stackLast sections after the others: the popup an opts.rows
    --      popup with those rows would be.
    --  A section shows while its hidden (if any) returns false and one of its rows
    --  shows. Rows take every field they take in opts.rows. The popup is clamped to
    --  the screen.
    -------------------------------------------------------------------------------
    local function BuildCogPopup(options)
        -- Every row the popup can show: opts.rows, or the rows of every section in order.
        local allRows = options.rows
        if options.sections then
            allRows = {}
            for _, sec in ipairs(options.sections) do
                for _, row in ipairs(sec.rows) do
                    allRows[#allRows + 1] = row
                end
            end
        end
        -- Spec Overrides capture: a cog's settings belong to its hosting slot -- ONE setting, captured whole. When the call site passes captureRegion (the DualRow half-region the cog sits in), every row with get/set joins that slot's capture group.
        -- row.noCapture opts a single row out (same flag DualRow honors): a popup can mix capturing rows with rows that must not capture (settings stored per palette rather than under a flat key).
        if options.captureRegion and CUI.AddCaptureAccessor and allRows then
            for _, row in ipairs(allRows) do
                if
                    row.get
                    and row.set
                    and not row.noCapture
                    and row.type ~= "button"
                    and row.type ~= "reorder"
                    and row.type ~= "reordercheck"
                then
                    CUI.AddCaptureAccessor(options.captureRegion, {
                        type = row.type,
                        text = row.label,
                        getValue = row.get,
                        setValue = row.set,
                        min = row.min,
                        max = row.max,
                        step = row.step,
                        values = row.values,
                        order = row.order,
                        -- Grouping kept so the Spec Overrides page mirrors the slot 1:1 with a real inline cog.
                        fromCog = true,
                        cogTitle = options.title,
                    })
                end
            end
        end

        local SIDE_PAD = 14
        local TOP_PAD = 14
        local TITLE_H = 11
        local TITLE_GAP = 10
        local GAP = 10
        local ROW_HEIGHT = 24
        local DROPDOWN_ROW_H = 30
        local TOGGLE_ROW_H = 28
        local INPUT_W = 34
        local SLIDER_INPUT_GAP = 8
        local LABEL_SLIDER_GAP = 12
        local MIN_POPUP_W = 180
        local POPUP_INPUT_A = 0.55

        local TG_W = 32
        local TG_H = 16
        local KNOB_SZ = 12
        local KNOB_PAD = 2

        local popupFrame, popupOwner
        -- row.hidden (a function): the row is left out while it returns true. A
        -- popup with such rows builds one frame per set of shown rows (cached, so
        -- a flip back reuses it) and swaps to the matching one when a change made
        -- inside it flips a row; a popup without them builds once, as always.
        -- A section's hidden takes part the same way.
        local dynamic = false
        if allRows then
            for _, row in ipairs(allRows) do
                if row.hidden then
                    dynamic = true
                    break
                end
            end
        end
        if options.sections and not dynamic then
            for _, sec in ipairs(options.sections) do
                if sec.hidden then
                    dynamic = true
                    break
                end
            end
        end
        local variants = dynamic and {} or nil
        local function HiddenSig()
            if not dynamic then return "" end
            local sig = ""
            if options.sections then
                for si, sec in ipairs(options.sections) do
                    if sec.hidden and sec.hidden() then
                        sig = sig .. "s" .. si .. ","
                    else
                        for ri, row in ipairs(sec.rows) do
                            if row.hidden and row.hidden() then sig = sig .. si .. "." .. ri .. "," end
                        end
                    end
                end
                return sig
            end
            for idx, row in ipairs(options.rows) do
                if row.hidden and row.hidden() then sig = sig .. idx .. "," end
            end
            return sig
        end
        local SwapVariant -- set below showFn; the refresh pass calls it

        -- Spec Overrides auto-capture: cog row writes attribute to the cog's anchor button, which sits inside the host slot's region.
        -- The slot is read before the setter runs: a setter that rebuilds the page may dress that button again for another slot.
        -- The notifying setter is this popup's own, on a row of its own over the caller's (popupRows): a row table a
        -- caller keeps across builds is never wrapped again, so no earlier build's setter runs, notifies or stays alive.
        -- Made by the first CreatePopup (most cogs a page builds are never opened).
        local popupRows, popupRowsMade
        local function PopupRows()
            if popupRowsMade then return popupRows end
            popupRowsMade = true
            if not allRows then return nil end
            for _, row in ipairs(allRows) do
                if row.set then
                    local _s = row.set
                    local function NotifyingSet(...)
                        local f = popupOwner or options.captureRegion
                        local snap = CUI._SOAttribution(f)
                        _s(...)
                        CUI._NotifySettingWrite(f, snap)
                    end
                    popupRows = popupRows or {}
                    popupRows[row] = setmetatable({ set = NotifyingSet }, { __index = row })
                end
            end
            return popupRows
        end

        -- anchorBtn: the button the popup opens from. The popup is kept per anchor
        -- button and set of shown rows (sig): opened again after the page rebuilt,
        -- the same frame is reset and dressed again here instead of made anew.
        -- (CreatePopup sits near Lua 5.1's 60-upvalue limit: new popup state goes
        -- into a table, not into more upvalues.)
        local function CreatePopup(sig, anchorBtn)
            local rowWidgets = {} -- per-row refresh info
            -- The rows this frame shows (all of them without row.hidden), each with
            -- this popup's notifying setter (popupRows), and the columns they fill:
            -- col = { measure = the rows its width is measured from, title,
            -- first, last = its rows' range in rows }; colStart[i] = the column
            -- rows[i] starts. A rows popup is one column with no title.
            local rowList, cols, colStart = {}, {}, {}
            local notifying = PopupRows()
            local multi = false -- one column per shown section
            if not options.sections then
                for _, row in ipairs(options.rows) do
                    if not (dynamic and row.hidden and row.hidden()) then
                        rowList[#rowList + 1] = (notifying and notifying[row]) or row
                    end
                end
                cols[1] = { measure = options.rows }
            else
                local isShown = {}
                for _, sec in ipairs(options.sections) do
                    if not (sec.hidden and sec.hidden()) then
                        for _, row in ipairs(sec.rows) do
                            if not (row.hidden and row.hidden()) then
                                isShown[#isShown + 1] = sec
                                break
                            end
                        end
                    end
                end
                multi = #isShown > 0 and #isShown >= (options.columnsFrom or 2)
                if not multi then
                    -- One column: stackLast sections after the others.
                    local sequence = {}
                    for _, sec in ipairs(isShown) do
                        if not sec.stackLast then sequence[#sequence + 1] = sec end
                    end
                    for _, sec in ipairs(isShown) do
                        if sec.stackLast then sequence[#sequence + 1] = sec end
                    end
                    isShown = sequence
                    cols[1] = { measure = {} }
                end
                for _, sec in ipairs(isShown) do
                    local col = cols[1]
                    if multi then
                        col = { measure = sec.rows, title = sec.title, first = #rowList + 1 }
                        cols[#cols + 1] = col
                        colStart[#rowList + 1] = col
                    else
                        for _, row in ipairs(sec.rows) do
                            col.measure[#col.measure + 1] = row
                        end
                    end
                    for _, row in ipairs(sec.rows) do
                        if not (row.hidden and row.hidden()) then
                            rowList[#rowList + 1] = (notifying and notifying[row]) or row
                        end
                    end
                    col.last = #rowList
                end
            end
            if not multi then
                colStart[1] = cols[1]
                cols[1].first, cols[1].last = 1, #rowList
            end
            -- Measure slider labels to find maxLblW: per column, each sizing its
            -- sliders and its width as a one-column popup does
            local tmpFS = measureFS
            if not tmpFS then
                tmpFS = UIParent:CreateFontString(nil, "OVERLAY")
                measureFS = tmpFS
            end
            tmpFS:SetFont(EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 11, "")
            tmpFS:Show()
            local COG_DD_W = 130
            for _, col in ipairs(cols) do
                local maxLblW = 0
                -- Widest label + dropdown pair (a dropdown or checkbox-list row may ask
                -- for a wider control with row.ddWidth; every other row uses COG_DD_W).
                local maxDDNeed = COG_DD_W
                for _, row in ipairs(col.measure) do
                    if row.type == "slider" or row.type == "input" then
                        tmpFS:SetText(CUI.L(row.label))
                        local wid = tmpFS:GetStringWidth()
                        if wid > maxLblW then maxLblW = wid end
                    elseif
                        row.type == "dropdown"
                        or row.type == "segmented"
                        or row.type == "reordercheck"
                    then
                        tmpFS:SetText(CUI.L(row.label))
                        local wid = tmpFS:GetStringWidth()
                            + (
                                ((row.type == "dropdown" or row.type == "reordercheck") and row.ddWidth)
                                or COG_DD_W
                            )
                        if wid > maxDDNeed then maxDDNeed = wid end
                    elseif
                        row.type == "toggle"
                        or row.type == "colorpicker"
                        or row.type == "multiswatch"
                        or row.type == "button"
                    then
                        -- A long label must not run under the right-aligned switch or swatches, or past a button's edges.
                        tmpFS:SetText(CUI.L(row.label))
                        local control = TG_W
                        if row.type == "colorpicker" then
                            control = 20
                        elseif row.type == "multiswatch" then
                            control = #(row.swatches or {}) * 28
                        elseif row.type == "button" then
                            control = 16
                        end
                        local wid = tmpFS:GetStringWidth() + control
                        if wid > maxDDNeed then maxDDNeed = wid end
                    end
                end
                if maxLblW < 10 then maxLblW = 60 end

                local SLIDER_LEFT = SIDE_PAD + maxLblW + LABEL_SLIDER_GAP
                local TARGET_W = options.minWidth or 260
                local SLIDER_W = math.max(80, TARGET_W - SLIDER_LEFT - SLIDER_INPUT_GAP - INPUT_W - SIDE_PAD)
                local POPUP_W = math.max(
                    options.minWidth or MIN_POPUP_W,
                    SLIDER_LEFT + SLIDER_W + SLIDER_INPUT_GAP + INPUT_W + SIDE_PAD
                )
                -- Widen for dropdown rows (label + gap + dropdown + padding)
                local ddNeeded = SIDE_PAD + maxDDNeed + LABEL_SLIDER_GAP + SIDE_PAD
                if ddNeeded > POPUP_W then POPUP_W = ddNeeded end
                if options.minWidth and options.minWidth > POPUP_W then POPUP_W = options.minWidth end
                -- Stretch the track to fill a widened popup so no gap opens between the slider and its value box. Gated on minWidth so un-widened cog popups keep their original slider width.
                if options.minWidth then
                    SLIDER_W =
                        math.max(SLIDER_W, POPUP_W - SLIDER_LEFT - SLIDER_INPUT_GAP - INPUT_W - SIDE_PAD)
                end
                -- A column also fits its title, in whole units (its divider sits on them).
                if multi then
                    if col.title then
                        tmpFS:SetText(CUI.L(col.title))
                        local tw = SIDE_PAD + tmpFS:GetStringWidth() + SIDE_PAD
                        if tw > POPUP_W then POPUP_W = tw end
                    end
                    POPUP_W = math.ceil(POPUP_W)
                end
                col.sliderLeft, col.sliderW, col.w = SLIDER_LEFT, SLIDER_W, POPUP_W
            end
            tmpFS:Hide()
            local SLIDER_LEFT, SLIDER_W, POPUP_W = cols[1].sliderLeft, cols[1].sliderW, cols[1].w

            local function RowH(row)
                if row.type == "toggle" or row.type == "segmented" then
                    return TOGGLE_ROW_H
                elseif row.type == "dropdown" or row.type == "reorder" or row.type == "reordercheck" then
                    return DROPDOWN_ROW_H
                elseif row.type == "button" then
                    return ROW_HEIGHT + 4
                end
                return ROW_HEIGHT
            end
            -- Column titles: their height and the gap under them; the gap between bands.
            local HDR_H, HDR_GAP, BAND_GAP = 12, 6, GAP * 2
            local totalH = TOP_PAD + TITLE_H + TITLE_GAP
            local contentBottom -- columns: the last band's bottom
            if not multi then
                cols[1].y = -totalH
                for idx, row in ipairs(rowList) do
                    if idx > 1 then totalH = totalH + GAP end
                    totalH = totalH + RowH(row)
                end
            else
                -- Bands of up to opts.maxColumns columns side by side, a 1px divider
                -- between columns: a band is as tall as its tallest column, the
                -- popup as wide as its widest band.
                local perBand = math.max(1, options.maxColumns or 4)
                local posX, band = 0, nil
                POPUP_W = 0
                for ci, col in ipairs(cols) do
                    local height = col.title and (HDR_H + HDR_GAP) or 0
                    for idx = col.first, col.last do
                        if idx > col.first then height = height + GAP end
                        height = height + RowH(rowList[idx])
                    end
                    if (ci - 1) % perBand == 0 then
                        if band then totalH = totalH + band.h + BAND_GAP end
                        band = { y = -totalH, h = 0 }
                        posX = 0
                    else
                        posX = posX + 1 -- the divider
                    end
                    col.x, col.y, col.band = posX, band.y, band
                    posX = posX + col.w
                    if posX > POPUP_W then POPUP_W = posX end
                    if height > band.h then band.h = height end
                end
                totalH = totalH + band.h
                contentBottom = -totalH
            end
            totalH = totalH + TOP_PAD

            -- Footer (optional unlock mode link)
            local FOOTER_H = 0
            if options.footer and options.footer.unlockKey then
                FOOTER_H = 42 -- 2 lines of small text + padding
                totalH = totalH + FOOTER_H
            end

            local popFrame, isNew = PoolKept(anchorBtn, "cog:" .. (sig or ""), "Frame", CUI.OverlayParent())
            popFrame:SetSize(POPUP_W, totalH)
            popFrame:SetFrameStrata(options.frameStrata or "DIALOG")
            popFrame:SetFrameLevel(options.frameLevel or 200)
            popFrame:EnableMouse(true)
            popFrame:Hide()
            -- Spec Overrides auto-capture: edits inside this popup attribute to the slot whose cog opened it.
            popFrame._cuiOptionsPopup = true
            -- Controller cursor: the popup blocks what is under it but is not a stop itself.
            CUI.PadHint(popFrame, "nodepass")

            -- Match panel scale so the popup matches scrollable-area widgets
            local ppScale = CUI.GetPopupScale() or 1
            popFrame:SetScale(ppScale)
            if isNew and CUI._popupFrames then
                CUI._popupFrames[#CUI._popupFrames + 1] = { popup = popFrame }
            end

            local backdrop = SolidTex(popFrame, "BACKGROUND", 0.062, 0.070, 0.082, options.bgAlpha or 0.95)
            backdrop:SetAllPoints()
            CUI.MakeRoundedBorder(popFrame, BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.15, backdrop)

            -- House look: an accent cap along the top, the title on the left in capitals.
            local cap =
                SolidTex(popFrame, "ARTWORK", CUI.CLUDES_GREEN.r, CUI.CLUDES_GREEN.g, CUI.CLUDES_GREEN.b, 0.9)
            cap:SetPoint("TOPLEFT")
            cap:SetPoint("TOPRIGHT")
            cap:SetHeight(2)
            local titleFS = MakeFont(popFrame, TITLE_H, "", 1, 1, 1)
            titleFS:SetAlpha(0.9)
            titleFS:SetPoint("TOPLEFT", popFrame, "TOPLEFT", 14, -TOP_PAD)
            titleFS:SetText(CUI.L(options.title or ""):upper())

            -- A sections popup can be wide: it stays on screen.
            if options.sections then popFrame:SetClampedToScreen(true) end
            -- The frame each column's rows anchor to: the popup itself for one
            -- column; per column, a frame whose top-left sits at the column's
            -- origin on the popup's top edge, with the dividers between columns
            -- (and across the popup between bands).
            if multi then
                local prevBand
                for _, col in ipairs(cols) do
                    local a = CreateFrame("Frame", nil, popFrame)
                    a:SetPoint("TOPLEFT", popFrame, "TOPLEFT", col.x, 0)
                    a:SetSize(col.w, totalH)
                    col.anchor = a
                    if prevBand then
                        local div =
                            SolidTex(popFrame, "BORDER", BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, 0.15)
                        Pix.DisablePixelSnap(div)
                        if col.band == prevBand then
                            Pix.Point(div, "TOPLEFT", popFrame, "TOPLEFT", col.x - 1, col.y)
                            Pix.Size(div, 1, col.band.h)
                        else
                            Pix.Point(div, "TOPLEFT", popFrame, "TOPLEFT", 1, col.y + BAND_GAP / 2)
                            Pix.Size(div, POPUP_W - 2, 1)
                        end
                    end
                    prevBand = col.band
                end
            else
                cols[1].anchor = popFrame
            end

            local curY = -(TOP_PAD + TITLE_H + TITLE_GAP)
            -- The column the rows below are built in: its frame and width.
            local ca, COL_W = popFrame, POPUP_W
            -- A dropdown-height row's disabled overlay (row.disabled set): dims the row,
            -- blocks it and explains the lock; the refresh shows it while disabled.
            local function RowDisabledOverlay(row, cursorY)
                if not row.disabled then return nil end
                local dis = CreateFrame("Frame", nil, popFrame)
                dis:SetPoint("TOPLEFT", ca, "TOPLEFT", 1, cursorY)
                dis:SetPoint("TOPRIGHT", ca, "TOPRIGHT", -1, cursorY)
                dis:SetHeight(DROPDOWN_ROW_H)
                dis:SetFrameLevel(popFrame:GetFrameLevel() + 10)
                dis:EnableMouse(true)
                local disTex = SolidTex(dis, "OVERLAY", 0.062, 0.070, 0.082, 0.70)
                disTex:SetAllPoints()
                dis:SetScript("OnEnter", function(self)
                    local tipText = ResolveDisabledTip(row)
                    if tipText and CUI.ShowWidgetTooltip then CUI.ShowWidgetTooltip(self, tipText) end
                end)
                dis:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
                return dis
            end
            -- A row's dimmed caption, centred in a row rowH tall at the current
            -- height, with a hover tooltip over it when the row has one.
            local function RowLabel(row, rowH)
                local caption = MakeFont(popFrame, 11, nil, 1, 1, 1)
                caption:SetAlpha(0.6)
                caption:SetText(CUI.L(row.label))
                caption:SetPoint("LEFT", ca, "TOPLEFT", SIDE_PAD, curY - rowH / 2 - 1)
                if row.tooltip then
                    local hit = CreateFrame("Frame", nil, popFrame)
                    hit:SetPoint("TOPLEFT", caption, "TOPLEFT", -2, 2)
                    hit:SetPoint("BOTTOMRIGHT", caption, "BOTTOMRIGHT", 2, -2)
                    hit:SetFrameLevel(popFrame:GetFrameLevel() + 3)
                    hit:EnableMouse(true)
                    hit:SetScript("OnEnter", function() CUI.ShowWidgetTooltip(caption, row.tooltip) end)
                    hit:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
                end
                return caption
            end
            for idx, row in ipairs(rowList) do
                local col = colStart[idx]
                if col then
                    -- A column's first row: the column's frame, widths, top and title.
                    ca, COL_W, SLIDER_LEFT, SLIDER_W, curY =
                        col.anchor, col.w, col.sliderLeft, col.sliderW, col.y
                    if col.title then
                        local heading =
                            MakeFont(popFrame, 11, nil, CLUDES_GREEN.r, CLUDES_GREEN.g, CLUDES_GREEN.b)
                        heading:SetText(CUI.L(col.title))
                        heading:SetPoint("TOPLEFT", ca, "TOPLEFT", SIDE_PAD, curY)
                        CUI.RegAccent({
                            type = "callback",
                            obj = heading,
                            fn = function(red, green, blue) heading:SetTextColor(red, green, blue) end,
                        })
                        curY = curY - HDR_H - HDR_GAP
                    end
                elseif idx > 1 then
                    curY = curY - GAP
                end

                if row.type == "slider" then
                    local srow = PixelizeSliderCfg(row)
                    local labelFS = RowLabel(row, ROW_HEIGHT)

                    local track, valBox, updateVisual = BuildSliderCore(
                        popFrame,
                        SLIDER_W,
                        4,
                        12,
                        INPUT_W,
                        ROW_HEIGHT,
                        11,
                        POPUP_INPUT_A,
                        srow.min,
                        srow.max,
                        srow.step,
                        srow.get,
                        srow.set,
                        true
                    )
                    track:SetPoint("LEFT", ca, "TOPLEFT", SLIDER_LEFT, curY - ROW_HEIGHT / 2)
                    valBox:ClearAllPoints()
                    valBox:SetPoint("RIGHT", ca, "TOPRIGHT", -SIDE_PAD, curY - ROW_HEIGHT / 2)

                    local sliderDis
                    if row.disabled then
                        sliderDis = CreateFrame("Frame", nil, popFrame)
                        sliderDis:SetPoint("TOPLEFT", ca, "TOPLEFT", 1, curY)
                        sliderDis:SetPoint("TOPRIGHT", ca, "TOPRIGHT", -1, curY)
                        sliderDis:SetHeight(ROW_HEIGHT)
                        sliderDis:SetFrameLevel(popFrame:GetFrameLevel() + 10)
                        sliderDis:EnableMouse(true)
                        local disTex = SolidTex(sliderDis, "OVERLAY", 0.062, 0.070, 0.082, 0.70)
                        disTex:SetAllPoints()
                        sliderDis:SetScript("OnEnter", function(self)
                            local tipText = ResolveDisabledTip(row)
                            if tipText and CUI.ShowWidgetTooltip then CUI.ShowWidgetTooltip(self, tipText) end
                        end)
                        sliderDis:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
                    end

                    rowWidgets[#rowWidgets + 1] = {
                        type = "slider",
                        updateVisual = updateVisual,
                        get = srow.get,
                        disOverlay = sliderDis,
                        disCheck = row.disabled,
                    }
                    curY = curY - ROW_HEIGHT
                elseif row.type == "toggle" then
                    local labelFS = RowLabel(row, TOGGLE_ROW_H)

                    local cogToggle, _, cogSnap = BuildToggleControl(
                        popFrame,
                        popFrame:GetFrameLevel() + 2,
                        row.get,
                        function(val) row.set(val) end,
                        { sizeRatio = 0.8, noAnim = true }
                    )
                    cogToggle:SetPoint("RIGHT", ca, "TOPRIGHT", -SIDE_PAD, curY - TOGGLE_ROW_H / 2)

                    local function UpdateToggleVisual() cogSnap() end
                    UpdateToggleVisual()
                    cogToggle:SetScript("OnClick", function()
                        local current = row.get()
                        row.set(not current)
                        UpdateToggleVisual()
                        if popFrame._refresh then popFrame._refresh() end
                    end)

                    local toggleDis
                    if row.disabled then
                        toggleDis = CreateFrame("Frame", nil, popFrame)
                        toggleDis:SetPoint("TOPLEFT", ca, "TOPLEFT", 1, curY)
                        toggleDis:SetPoint("TOPRIGHT", ca, "TOPRIGHT", -1, curY)
                        toggleDis:SetHeight(TOGGLE_ROW_H)
                        toggleDis:SetFrameLevel(popFrame:GetFrameLevel() + 10)
                        toggleDis:EnableMouse(true)
                        local disTex = SolidTex(toggleDis, "OVERLAY", 0.062, 0.070, 0.082, 0.70)
                        disTex:SetAllPoints()
                        toggleDis:SetScript("OnEnter", function(self)
                            local tipText = ResolveDisabledTip(row)
                            if tipText and CUI.ShowWidgetTooltip then CUI.ShowWidgetTooltip(self, tipText) end
                        end)
                        toggleDis:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
                    end

                    rowWidgets[#rowWidgets + 1] = {
                        type = "toggle",
                        updateVisual = UpdateToggleVisual,
                        disOverlay = toggleDis,
                        disCheck = row.disabled,
                    }
                    curY = curY - TOGGLE_ROW_H
                elseif row.type == "dropdown" then
                    local labelFS = MakeFont(popFrame, 11, nil, 1, 1, 1)
                    labelFS:SetAlpha(0.6)
                    labelFS:SetText(CUI.L(row.label))
                    labelFS:SetPoint("LEFT", ca, "TOPLEFT", SIDE_PAD, curY - DROPDOWN_ROW_H / 2 - 1)

                    -- Cog-popup dropdowns render 10% smaller than the panel dropdowns.
                    local DD_SCALE = 0.9
                    local dropdownBtn, dropCaption = BuildDropdownControl(
                        popFrame,
                        row.ddWidth or COG_DD_W,
                        popFrame:GetFrameLevel() + 2,
                        row.values,
                        row.order,
                        row.get,
                        function(val)
                            row.set(val)
                            if popFrame._refresh then popFrame._refresh() end
                        end,
                        row.itemDisabled
                    )
                    dropdownBtn:SetScale(DD_SCALE)
                    dropdownBtn:ClearAllPoints()
                    -- Offsets divided by DD_SCALE so the scaled control still lands flush-right and vertically centered: SetScale multiplies a frame's own anchor offsets by its scale.
                    dropdownBtn:SetPoint(
                        "RIGHT",
                        ca,
                        "TOPRIGHT",
                        -SIDE_PAD / DD_SCALE,
                        (curY - DROPDOWN_ROW_H / 2) / DD_SCALE
                    )
                    if row.tooltip then
                        dropdownBtn._ttText = row.tooltip
                        dropdownBtn._ttOpts = row.tooltipOpts
                    end
                    -- Propagate popup scale and the 10% reduction to the lazily-built menu so the open list matches the shrunk control.
                    dropdownBtn:HookScript("OnClick", function(self)
                        if self._ddMenu then
                            if not self._ddMenu._cogScaled then
                                self._ddMenu:SetScale(ppScale * DD_SCALE)
                                self._ddMenu._cogScaled = true
                            end
                            -- Keep the menu above the cog popup: BuildDropdownMenu creates it at FULLSCREEN_DIALOG 200, which sits BEHIND a popup that is itself FULLSCREEN_DIALOG.
                            self._ddMenu:SetFrameStrata(popFrame:GetFrameStrata())
                            self._ddMenu:SetFrameLevel(popFrame:GetFrameLevel() + 30)
                        end
                    end)

                    -- Disabled overlay, mirroring slider/input handling
                    local ddDis = RowDisabledOverlay(row, curY)

                    rowWidgets[#rowWidgets + 1] = {
                        type = "dropdown",
                        btn = dropdownBtn,
                        lbl = dropCaption,
                        get = row.get,
                        values = row.values,
                        refresh = dropdownBtn._ddRefresh,
                        disOverlay = ddDis,
                        disCheck = row.disabled,
                    }
                    curY = curY - DROPDOWN_ROW_H
                elseif row.type == "reordercheck" then
                    local labelFS = MakeFont(popFrame, 11, nil, 1, 1, 1)
                    labelFS:SetAlpha(0.6)
                    labelFS:SetText(CUI.L(row.label))
                    labelFS:SetPoint("LEFT", ca, "TOPLEFT", SIDE_PAD, curY - DROPDOWN_ROW_H / 2 - 1)

                    local itemList = type(row.items) == "function" and row.items() or row.items or {}
                    local dropdownBtn, refresh
                    dropdownBtn, refresh = CUI.BuildReorderCBDropdown(
                        popFrame,
                        row.ddWidth or COG_DD_W,
                        popFrame:GetFrameLevel() + 2,
                        itemList,
                        row.get,
                        function(keyName, val, sequence)
                            row.set(keyName, val, sequence)
                            if popFrame._refresh then popFrame._refresh() end
                        end,
                        {
                            hint = row.hint,
                            hint2 = row.hint2,
                            grip = row.grip,
                            openOrder = row.openOrder,
                            tail = row.tail,
                            onTail = function(keyName)
                                if row.onTail then row.onTail(keyName, dropdownBtn) end
                            end,
                            tailSelected = row.tailSelected,
                            setOrder = function(keyList)
                                if row.setOrder then row.setOrder(keyList) end
                            end,
                        }
                    )
                    local DD_SCALE = 0.9
                    dropdownBtn:SetScale(DD_SCALE)
                    dropdownBtn:ClearAllPoints()
                    dropdownBtn:SetPoint(
                        "RIGHT",
                        ca,
                        "TOPRIGHT",
                        -SIDE_PAD / DD_SCALE,
                        (curY - DROPDOWN_ROW_H / 2) / DD_SCALE
                    )
                    dropdownBtn:HookScript("OnClick", function(self)
                        if self._ddMenu then
                            self._ddMenu:SetFrameStrata(popFrame:GetFrameStrata())
                            self._ddMenu:SetFrameLevel(popFrame:GetFrameLevel() + 30)
                        end
                    end)
                    local rcDis = RowDisabledOverlay(row, curY)

                    rowWidgets[#rowWidgets + 1] = {
                        type = "reordercheck",
                        btn = dropdownBtn,
                        refresh = refresh,
                        disOverlay = rcDis,
                        disCheck = row.disabled,
                    }
                    curY = curY - DROPDOWN_ROW_H
                elseif row.type == "segmented" then
                    local labelFS = MakeFont(popFrame, 11, nil, 1, 1, 1)
                    labelFS:SetAlpha(0.6)
                    labelFS:SetText(CUI.L(row.label))
                    labelFS:SetPoint("LEFT", ca, "TOPLEFT", SIDE_PAD, curY - TOGGLE_ROW_H / 2 - 1)

                    local seg, _seg2, segRefresh = CUI.BuildSegmentedControl({
                        parent = popFrame,
                        keys = row.keys,
                        labels = row.labels,
                        autoWidth = true,
                        square = true,
                        height = 22,
                        getChecked = function(key) return row.get() == key end,
                        onToggle = function(key)
                            row.set(key)
                            if popFrame._refresh then popFrame._refresh() end
                        end,
                    })
                    seg:ClearAllPoints()
                    seg:SetPoint("RIGHT", ca, "TOPRIGHT", -SIDE_PAD, curY - TOGGLE_ROW_H / 2)

                    local segDis
                    if row.disabled then
                        segDis = CreateFrame("Frame", nil, popFrame)
                        segDis:SetPoint("TOPLEFT", ca, "TOPLEFT", 1, curY)
                        segDis:SetPoint("TOPRIGHT", ca, "TOPRIGHT", -1, curY)
                        segDis:SetHeight(TOGGLE_ROW_H)
                        segDis:SetFrameLevel(popFrame:GetFrameLevel() + 10)
                        segDis:EnableMouse(true)
                        local disTex = SolidTex(segDis, "OVERLAY", 0.062, 0.070, 0.082, 0.70)
                        disTex:SetAllPoints()
                        segDis:SetScript("OnEnter", function(self)
                            local tipText = ResolveDisabledTip(row)
                            if tipText and CUI.ShowWidgetTooltip then CUI.ShowWidgetTooltip(self, tipText) end
                        end)
                        segDis:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
                    end

                    rowWidgets[#rowWidgets + 1] = {
                        type = "segmented",
                        seg = seg,
                        refresh = segRefresh,
                        disOverlay = segDis,
                        disCheck = row.disabled,
                    }
                    curY = curY - TOGGLE_ROW_H
                elseif row.type == "colorpicker" then
                    local labelFS = RowLabel(row, ROW_HEIGHT)

                    local cpSwatch, cpUpdate = BuildColorSwatch(
                        popFrame,
                        popFrame:GetFrameLevel() + 2,
                        function() return row.get() end,
                        function(red, green, blue, a)
                            row.set(red, green, blue, a)
                            if popFrame._refresh then popFrame._refresh() end
                        end,
                        row.hasAlpha,
                        20
                    )
                    cpSwatch:ClearAllPoints()
                    cpSwatch:SetPoint("RIGHT", ca, "TOPRIGHT", -SIDE_PAD, curY - ROW_HEIGHT / 2)

                    -- Disabled: blocking overlays on label + swatch (inline swatch pattern)
                    local cpSwBlock, cpLblBlock
                    if row.disabled then
                        cpSwBlock = CreateFrame("Frame", nil, cpSwatch)
                        cpSwBlock:SetAllPoints()
                        cpSwBlock:SetFrameLevel(cpSwatch:GetFrameLevel() + 10)
                        cpSwBlock:EnableMouse(true)
                        cpSwBlock:SetScript("OnEnter", function()
                            local tipText = ResolveDisabledTip(row)
                            if tipText and CUI.ShowWidgetTooltip then
                                CUI.ShowWidgetTooltip(cpSwatch, tipText)
                            end
                        end)
                        cpSwBlock:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)

                        cpLblBlock = CreateFrame("Frame", nil, popFrame)
                        cpLblBlock:SetPoint("TOPLEFT", labelFS, "TOPLEFT", -2, 2)
                        cpLblBlock:SetPoint("BOTTOMRIGHT", labelFS, "BOTTOMRIGHT", 2, -2)
                        cpLblBlock:SetFrameLevel(popFrame:GetFrameLevel() + 10)
                        cpLblBlock:EnableMouse(true)
                        cpLblBlock:SetScript("OnEnter", function()
                            local tipText = ResolveDisabledTip(row)
                            if tipText and CUI.ShowWidgetTooltip then
                                CUI.ShowWidgetTooltip(labelFS, tipText)
                            end
                        end)
                        cpLblBlock:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
                    end

                    rowWidgets[#rowWidgets + 1] = {
                        type = "colorpicker",
                        updateSwatch = cpUpdate,
                        swatch = cpSwatch,
                        lbl = labelFS,
                        swBlock = cpSwBlock,
                        lblBlock = cpLblBlock,
                        disCheck = row.disabled,
                    }

                    if row.disabled then
                        local initDis = type(row.disabled) == "function" and row.disabled() or row.disabled
                        cpSwatch:SetAlpha(initDis and 0.3 or 1)
                        -- Label dims by alpha rather than the dark row overlay the other
                        -- types use: that overlay would tint the swatch's own color.
                        labelFS:SetAlpha(initDis and 0.2 or 0.6)
                        if cpSwBlock then
                            if initDis then
                                cpSwBlock:Show()
                            else
                                cpSwBlock:Hide()
                            end
                        end
                        if cpLblBlock then
                            if initDis then
                                cpLblBlock:Show()
                            else
                                cpLblBlock:Hide()
                            end
                        end
                    end

                    curY = curY - ROW_HEIGHT
                elseif row.type == "multiswatch" then
                    -- Cog-row form of the main-page multiSwatch slot: label + N swatches right-to-left from the right edge; click one or the other, the inactive one dims. Same swatch spec: getValue/setValue/hasAlpha/tooltip/onClick (original picker click stashed on _eabOrigClick)/refreshAlpha.
                    local labelFS = MakeFont(popFrame, 11, nil, 1, 1, 1)
                    labelFS:SetAlpha(0.6)
                    labelFS:SetText(CUI.L(row.label))
                    labelFS:SetPoint("LEFT", ca, "TOPLEFT", SIDE_PAD, curY - ROW_HEIGHT / 2 - 1)

                    local MSW_GAP = 8
                    local mswX = -SIDE_PAD
                    local mswUpdates, mswAlphas = {}, {}
                    local mswSwatches = row.swatches or {}
                    for idx = #mswSwatches, 1, -1 do
                        local sc = mswSwatches[idx]
                        local colorSwatch, updateSwatch = BuildColorSwatch(
                            popFrame,
                            popFrame:GetFrameLevel() + 2,
                            sc.getValue,
                            function(red, green, blue, a)
                                local f = popupOwner or options.captureRegion
                                local snap = CUI._SOAttribution(f)
                                if sc.setValue then sc.setValue(red, green, blue, a) end
                                CUI._NotifySettingWrite(f, snap)
                                if popFrame._refresh then popFrame._refresh() end
                            end,
                            sc.hasAlpha,
                            20
                        )
                        colorSwatch:ClearAllPoints()
                        colorSwatch:SetPoint("RIGHT", ca, "TOPRIGHT", mswX, curY - ROW_HEIGHT / 2)
                        mswX = mswX - 20 - MSW_GAP
                        if sc.onClick then
                            colorSwatch._eabOrigClick = colorSwatch:GetScript("OnClick")
                            colorSwatch:SetScript("OnClick", function(self, ...)
                                local f = popupOwner or options.captureRegion
                                local snap = CUI._SOAttribution(f)
                                sc.onClick(self, ...)
                                CUI._NotifySettingWrite(f, snap)
                                if popFrame._refresh then popFrame._refresh() end
                            end)
                        end
                        if sc.tooltip then
                            colorSwatch:HookScript(
                                "OnEnter",
                                function() CUI.ShowWidgetTooltip(colorSwatch, sc.tooltip) end
                            )
                            colorSwatch:HookScript("OnLeave", function() CUI.HideWidgetTooltip() end)
                        end
                        mswUpdates[#mswUpdates + 1] = updateSwatch
                        if sc.refreshAlpha then
                            mswAlphas[#mswAlphas + 1] = { sw = colorSwatch, fn = sc.refreshAlpha }
                            colorSwatch:SetAlpha(sc.refreshAlpha())
                        end
                    end

                    -- Row-level disabled overlay, as on the slider/input rows
                    local mswDis
                    if row.disabled then
                        mswDis = CreateFrame("Frame", nil, popFrame)
                        mswDis:SetPoint("TOPLEFT", ca, "TOPLEFT", 1, curY)
                        mswDis:SetPoint("TOPRIGHT", ca, "TOPRIGHT", -1, curY)
                        mswDis:SetHeight(ROW_HEIGHT)
                        mswDis:SetFrameLevel(popFrame:GetFrameLevel() + 10)
                        mswDis:EnableMouse(true)
                        local disTex = SolidTex(mswDis, "OVERLAY", 0.062, 0.070, 0.082, 0.70)
                        disTex:SetAllPoints()
                        mswDis:SetScript("OnEnter", function(self)
                            local tipText = ResolveDisabledTip(row)
                            if tipText and CUI.ShowWidgetTooltip then CUI.ShowWidgetTooltip(self, tipText) end
                        end)
                        mswDis:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
                        local initDis = type(row.disabled) == "function" and row.disabled() or row.disabled
                        if initDis then
                            mswDis:Show()
                        else
                            mswDis:Hide()
                        end
                    end

                    rowWidgets[#rowWidgets + 1] = {
                        type = "multiswatch",
                        updates = mswUpdates,
                        alphaFns = mswAlphas,
                        disOverlay = mswDis,
                        disCheck = row.disabled,
                    }
                    curY = curY - ROW_HEIGHT
                elseif row.type == "input" then
                    local labelFS = RowLabel(row, ROW_HEIGHT)

                    local inputW = row.inputWidth or 80
                    local SAVE_W = 34
                    local SAVE_GAP = 4

                    -- commitOnBlur: no Save button, commit on Enter and focus loss (matches the threshold EditBoxes). Otherwise an explicit Save button sits right of the input.
                    local commitOnBlur = row.commitOnBlur
                    local ACC = CLUDES_GREEN
                    local saveBtn, saveBg, saveLbl
                    if not commitOnBlur then
                        saveBtn = CreateFrame("Button", nil, popFrame)
                        saveBtn:SetSize(SAVE_W, ROW_HEIGHT - 4)
                        saveBtn:SetPoint("RIGHT", ca, "TOPRIGHT", -SIDE_PAD, curY - ROW_HEIGHT / 2)
                        saveBtn:SetFrameLevel(popFrame:GetFrameLevel() + 3)
                        saveBg = SolidTex(saveBtn, "BACKGROUND", ACC.r, ACC.g, ACC.b, 0.85)
                        saveBg:SetAllPoints()
                        CUI.RoundBody(saveBtn, saveBg)
                        saveLbl = MakeFont(saveBtn, 10, nil, 1, 1, 1)
                        saveLbl:SetAlpha(0.9)
                        saveLbl:SetText(CUI.L("Save"))
                        saveLbl:SetPoint("CENTER")
                        saveBtn:SetScript("OnEnter", function()
                            saveBg:SetColorTexture(
                                ACC.r + (1 - ACC.r) * 0.25,
                                ACC.g + (1 - ACC.g) * 0.25,
                                ACC.b + (1 - ACC.b) * 0.25,
                                0.95
                            )
                            saveLbl:SetAlpha(1)
                        end)
                        saveBtn:SetScript("OnLeave", function()
                            saveBg:SetColorTexture(ACC.r, ACC.g, ACC.b, 0.85)
                            saveLbl:SetAlpha(0.9)
                        end)
                    end

                    local boxFrame = CreateFrame("EditBox", nil, popFrame)
                    boxFrame:SetSize(inputW, ROW_HEIGHT - 4)
                    if commitOnBlur then
                        boxFrame:SetPoint("RIGHT", ca, "TOPRIGHT", -SIDE_PAD, curY - ROW_HEIGHT / 2)
                    else
                        boxFrame:SetPoint("RIGHT", saveBtn, "LEFT", -SAVE_GAP, 0)
                    end
                    boxFrame:SetAutoFocus(false)
                    boxFrame:SetFont(EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 11, "")
                    boxFrame:SetTextColor(1, 1, 1, POPUP_INPUT_A)
                    boxFrame:SetJustifyH(row.inputJustify or "CENTER")
                    if row.inputJustify == "LEFT" then boxFrame:SetTextInsets(6, 6, 0, 0) end
                    local boxBg = SolidTex(boxFrame, "BACKGROUND", 0.12, 0.12, 0.12, 0.8)
                    boxBg:SetAllPoints()
                    CUI.RoundBody(boxFrame, boxBg)
                    boxFrame:SetText(row.get and row.get() or "")
                    -- Left-aligned text that overflows shows its start, not its end.
                    if row.inputJustify == "LEFT" then boxFrame:SetCursorPosition(0) end

                    local _committing = false -- guard ClearFocus -> OnEditFocusLost reentry
                    local function ApplyInput()
                        if _committing then return end
                        _committing = true
                        boxFrame:ClearFocus()
                        if row.set then row.set(boxFrame:GetText()) end
                        if popFrame._refresh then popFrame._refresh() end
                        -- Brief white flash on the save button as confirmation
                        if saveBg then
                            saveBg:SetColorTexture(1, 1, 1, 0.9)
                            saveLbl:SetText(CUI.L("Saved"))
                            local g = PoolGen(saveBg)
                            C_Timer.After(0.4, function()
                                if PoolGen(saveBg) ~= g or PoolIsIdle(saveBg) then return end
                                saveBg:SetColorTexture(ACC.r, ACC.g, ACC.b, 0.85)
                                saveLbl:SetText(CUI.L("Save"))
                            end)
                        end
                        _committing = false
                    end

                    boxFrame:SetScript("OnEnterPressed", function(self) ApplyInput() end)
                    boxFrame:SetScript("OnEscapePressed", function(self)
                        -- Cancel: guard + restore BEFORE ClearFocus -- in commitOnBlur mode ClearFocus fires OnEditFocusLost, which would otherwise SAVE the discarded text.
                        _committing = true
                        self:SetText(row.get and row.get() or "")
                        if row.inputJustify == "LEFT" then self:SetCursorPosition(0) end
                        self:ClearFocus()
                        _committing = false
                    end)
                    if commitOnBlur then
                        boxFrame:SetScript("OnEditFocusLost", function() ApplyInput() end)
                    else
                        saveBtn:SetScript("OnClick", function() ApplyInput() end)
                    end

                    local inputDis
                    if row.disabled then
                        inputDis = CreateFrame("Frame", nil, popFrame)
                        inputDis:SetPoint("TOPLEFT", ca, "TOPLEFT", 1, curY)
                        inputDis:SetPoint("TOPRIGHT", ca, "TOPRIGHT", -1, curY)
                        inputDis:SetHeight(ROW_HEIGHT)
                        inputDis:SetFrameLevel(popFrame:GetFrameLevel() + 10)
                        inputDis:EnableMouse(true)
                        local disTex = SolidTex(inputDis, "OVERLAY", 0.062, 0.070, 0.082, 0.70)
                        disTex:SetAllPoints()
                        inputDis:SetScript("OnEnter", function(self)
                            local tipText = ResolveDisabledTip(row)
                            if tipText and CUI.ShowWidgetTooltip then CUI.ShowWidgetTooltip(self, tipText) end
                        end)
                        inputDis:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
                    end

                    rowWidgets[#rowWidgets + 1] = {
                        type = "input",
                        box = boxFrame,
                        get = row.get,
                        disOverlay = inputDis,
                        disCheck = row.disabled,
                        saveBg = saveBg,
                        leftJustify = row.inputJustify == "LEFT",
                    }
                    curY = curY - ROW_HEIGHT
                elseif row.type == "button" then
                    local BTN_ROW_H = ROW_HEIGHT + 4
                    local button = CreateFrame("Button", nil, popFrame)
                    Pix.Size(button, COL_W - SIDE_PAD * 2, BTN_ROW_H)
                    Pix.Point(button, "TOP", ca, "TOPLEFT", COL_W / 2, curY)
                    button:SetFrameLevel(popFrame:GetFrameLevel() + 2)
                    local btnBg = SolidTex(button, "BACKGROUND", 0.18, 0.18, 0.18, 0.85)
                    btnBg:SetAllPoints()
                    local btnLbl = MakeFont(button, 11, nil, 1, 1, 1)
                    btnLbl:SetAlpha(0.7)
                    btnLbl:SetPoint("CENTER")
                    btnLbl:SetText(CUI.L(row.label))
                    button:SetScript("OnEnter", function()
                        btnBg:SetColorTexture(0.25, 0.25, 0.25, 0.85)
                        btnLbl:SetAlpha(1)
                    end)
                    button:SetScript("OnLeave", function()
                        btnBg:SetColorTexture(0.18, 0.18, 0.18, 0.85)
                        btnLbl:SetAlpha(0.7)
                    end)
                    button:SetScript("OnClick", function()
                        if row.action then row.action() end
                        if popFrame._refresh then popFrame._refresh() end
                    end)
                    rowWidgets[#rowWidgets + 1] = { type = "button" }
                    curY = curY - BTN_ROW_H
                elseif row.type == "reorder" then
                    -- Full-width dropdown button opening a drag-to-reorder menu (hint label + draggable rows), matching the raid/party "Sort By" reorder section.
                    local RR_W = COL_W - SIDE_PAD * 2
                    local dropdownBtn = CreateFrame("Button", nil, popFrame)
                    dropdownBtn:SetSize(RR_W, DROPDOWN_ROW_H - 2)
                    dropdownBtn:SetPoint("TOP", ca, "TOPLEFT", COL_W / 2, curY - 1)
                    dropdownBtn:SetFrameLevel(popFrame:GetFrameLevel() + 2)
                    local rBg = SolidTex(
                        dropdownBtn,
                        "BACKGROUND",
                        CUI.DD_BG_R,
                        CUI.DD_BG_G,
                        CUI.DD_BG_B,
                        CUI.DD_BG_A
                    )
                    rBg:SetAllPoints()
                    local rBrd = CUI.MakeRoundedBorder(dropdownBtn, 1, 1, 1, CUI.DD_BRD_A, rBg)
                    local rLbl = MakeFont(dropdownBtn, 12, nil, 1, 1, 1)
                    rLbl:SetAlpha(CUI.DD_TXT_A)
                    rLbl:SetJustifyH("LEFT")
                    rLbl:SetWordWrap(false)
                    rLbl:SetMaxLines(1)
                    rLbl:SetPoint("LEFT", dropdownBtn, "LEFT", 8, 0)
                    rLbl:SetText(CUI.L(row.label))
                    local rArrow = MakeDropdownArrow(dropdownBtn, 12, Pix)
                    rLbl:SetPoint("RIGHT", rArrow, "LEFT", -5, 0)
                    dropdownBtn:SetScript("OnEnter", function()
                        rBg:SetColorTexture(CUI.DD_BG_R, CUI.DD_BG_G, CUI.DD_BG_B, CUI.DD_BG_HA)
                        rBrd:SetColor(1, 1, 1, CUI.DD_BRD_HA)
                        rLbl:SetAlpha(CUI.DD_TXT_HA)
                    end)
                    dropdownBtn:SetScript("OnLeave", function()
                        rBg:SetColorTexture(CUI.DD_BG_R, CUI.DD_BG_G, CUI.DD_BG_B, CUI.DD_BG_A)
                        rBrd:SetColor(1, 1, 1, CUI.DD_BRD_A)
                        rLbl:SetAlpha(CUI.DD_TXT_A)
                    end)

                    -- Menu is FULLSCREEN_DIALOG so it floats above the popup; it
                    -- belongs to the popup (hidden with it, dressed again with it).
                    local MH = 26
                    local FONT = (CUI.GetFontPath()) or "Fonts\\FRIZQT__.TTF"
                    local dropMenu = PoolOwned(popFrame, "reorder", "Frame", CUI.OverlayParent())
                    dropMenu:SetFrameStrata("FULLSCREEN_DIALOG")
                    dropMenu:SetFrameLevel(220)
                    dropMenu:SetClampedToScreen(true)
                    dropMenu:SetWidth(RR_W)
                    dropMenu:Hide()
                    -- Controller cursor: Cancel clicks the button (it toggles the list closed).
                    if CUI.PadCP() then dropMenu.CloseButton = dropdownBtn end
                    local mBg2 = SolidTex(dropMenu, "BACKGROUND", CUI.DD_BG_R, CUI.DD_BG_G, CUI.DD_BG_B, 0.98)
                    mBg2:SetAllPoints()
                    CUI.MakeRoundedBorder(dropMenu, 1, 1, 1, CUI.DD_BRD_A, mBg2, nil, true)
                    dropMenu:SetPoint("TOPLEFT", dropdownBtn, "BOTTOMLEFT", 0, -2)
                    dropdownBtn._ddMenu = dropMenu -- popup click-outside ignores menu interaction

                    -- Declared before OnShow so its OnUpdate can suppress the click-away dismiss while a row is being dragged.
                    local dragRow, dsY, isDragging = nil, nil, false

                    dropMenu:SetScript("OnShow", function(self)
                        self:SetScale(dropdownBtn:GetEffectiveScale() / UIParent:GetEffectiveScale())
                        self:SetScript("OnUpdate", function(frame)
                            if isDragging then return end -- never dismiss mid-drag
                            if not dropdownBtn:IsMouseOver() and not frame:IsMouseOver() then
                                if IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton") then
                                    frame:Hide()
                                end
                            end
                        end)
                    end)
                    dropMenu:SetScript("OnHide", function(self)
                        self:SetScript("OnUpdate", nil)
                        -- Controller cursor: back onto the button (a no-op once the popup hid it too).
                        if CUI.PadCursorShown() then CUI.PadFocus(dropdownBtn) end
                    end)

                    local mY = -2
                    local ht = dropMenu:CreateFontString(nil, "OVERLAY")
                    ht:SetFont(FONT, 10, "")
                    ht:SetPoint("TOPLEFT", dropMenu, "TOPLEFT", 10, mY - 4)
                    ht:SetTextColor(1, 1, 1, 0.25)
                    ht:SetText(CUI.L(row.hint or "Drag to Reorder"))
                    mY = mY - 18

                    -- Height cap: rows live on a scroll child. Menus longer than
                    -- row.maxVisible rows clamp to that many and mousewheel-scroll;
                    -- the drag math below is scroll-child-relative, so reordering
                    -- keeps working while scrolled. No maxVisible = full height,
                    -- scrolling never engages (exact legacy behavior).
                    local scroller = CreateFrame("ScrollFrame", nil, dropMenu)
                    scroller:SetPoint("TOPLEFT", dropMenu, "TOPLEFT", 0, mY)
                    scroller:SetPoint("TOPRIGHT", dropMenu, "TOPRIGHT", 0, mY)
                    scroller:SetFrameLevel(dropMenu:GetFrameLevel() + 1)
                    local sChild = CreateFrame("Frame", nil, scroller)
                    scroller:SetScrollChild(sChild)
                    local maxScroll = 0
                    dropMenu:EnableMouseWheel(true)
                    dropMenu:SetScript("OnMouseWheel", function(_, delta)
                        if maxScroll <= 0 then return end
                        local nv = (scroller:GetVerticalScroll() or 0) - delta * MH * 2
                        if nv < 0 then
                            nv = 0
                        elseif nv > maxScroll then
                            nv = maxScroll
                        end
                        scroller:SetVerticalScroll(nv)
                    end)

                    local cbBaseY = 0
                    local rowFrames, rowPool = {}, {}
                    local insLine = sChild:CreateTexture(nil, "OVERLAY", nil, 7)
                    insLine:SetHeight(2)
                    local EG2 = CUI.CLUDES_GREEN or { r = 0.30, g = 0.79, b = 0.94 }
                    insLine:SetColorTexture(EG2.r, EG2.g, EG2.b, 0.9)
                    insLine:Hide()

                    local function PersistOrder()
                        local keyList = {}
                        for _, rf in ipairs(rowFrames) do
                            keyList[#keyList + 1] = rf._key
                        end
                        if row.set then row.set(keyList) end
                    end

                    -- Runs on the pressed row only, from mouse down to mouse up.
                    local function DragUpdate(self)
                        if not dsY then return end
                        local _, curY = GetCursorPosition()
                        if not isDragging then
                            if math.abs(curY - dsY) < 3 then return end
                            isDragging = true
                            self:SetFrameLevel(dropMenu:GetFrameLevel() + 10)
                            self:SetAlpha(0.8)
                            for _, r2 in ipairs(rowFrames) do
                                if r2._lbl then r2._lbl:SetTextColor(0.75, 0.75, 0.75, 1) end
                            end
                        end
                        local sc = dropMenu:GetEffectiveScale()
                        local cY = curY / sc
                        local mT = sChild:GetTop() or 0
                        local iI = #rowFrames
                        for ri, r2 in ipairs(rowFrames) do
                            if r2 ~= self and r2._baseY then
                                local rm = mT + r2._baseY - MH / 2
                                if cY > rm then
                                    iI = ri
                                    break
                                end
                                iI = ri + 1
                            end
                        end
                        iI = math.max(1, math.min(iI, #rowFrames + 1))
                        local lnY = (iI <= 1) and (cbBaseY + 1) or (cbBaseY - (iI - 1) * MH + 1)
                        insLine:ClearAllPoints()
                        insLine:SetPoint("TOPLEFT", sChild, "TOPLEFT", 8, lnY)
                        insLine:SetPoint("TOPRIGHT", sChild, "TOPRIGHT", -8, lnY)
                        insLine:Show()
                        self:ClearAllPoints()
                        self:SetPoint("TOPLEFT", sChild, "TOPLEFT", 1, cY - mT)
                        self:SetPoint("TOPRIGHT", sChild, "TOPRIGHT", -1, cY - mT)
                    end

                    local function MakeRow()
                        local rf = CreateFrame("Button", nil, sChild)
                        rf:SetHeight(MH)
                        rf:SetFrameLevel(dropMenu:GetFrameLevel() + 2)

                        local rl = rf:CreateFontString(nil, "OVERLAY")
                        rl:SetFont(FONT, 13, "")
                        rl:SetPoint("LEFT", rf, "LEFT", 20, 0)
                        rl:SetJustifyH("LEFT")
                        rl:SetTextColor(0.75, 0.75, 0.75, 1)
                        rf._lbl = rl

                        local grip = rf:CreateFontString(nil, "OVERLAY")
                        grip:SetFont(FONT, 10, "")
                        grip:SetPoint("LEFT", rf, "LEFT", 8, 0)
                        grip:SetText("=")
                        grip:SetTextColor(1, 1, 1, 0.2)

                        local rHL = rf:CreateTexture(nil, "ARTWORK")
                        rHL:SetAllPoints()
                        rHL:SetColorTexture(1, 1, 1, 0)

                        rf:SetScript("OnEnter", function()
                            if isDragging then return end
                            rl:SetTextColor(1, 1, 1, 1)
                            rHL:SetColorTexture(1, 1, 1, 0.04)
                        end)
                        rf:SetScript("OnLeave", function()
                            if isDragging then return end
                            rl:SetTextColor(0.75, 0.75, 0.75, 1)
                            rHL:SetColorTexture(1, 1, 1, 0)
                        end)

                        rf:SetScript("OnMouseDown", function(self, b)
                            if b ~= "LeftButton" then return end
                            local _, curY = GetCursorPosition()
                            dsY = curY
                            dragRow = self
                            self:SetScript("OnUpdate", DragUpdate)
                        end)

                        rf:SetScript("OnMouseUp", function(self, b)
                            if b ~= "LeftButton" or dragRow ~= self then return end
                            self:SetScript("OnUpdate", nil)
                            dsY = nil
                            dragRow = nil
                            if not isDragging then return end
                            isDragging = false
                            insLine:Hide()
                            self:SetFrameLevel(dropMenu:GetFrameLevel() + 2)
                            self:SetAlpha(1)
                            local _, curY = GetCursorPosition()
                            local sc = dropMenu:GetEffectiveScale()
                            curY = curY / sc
                            local mT = sChild:GetTop() or 0
                            local from = self._cbIndex
                            local iI = #rowFrames
                            for ri, r2 in ipairs(rowFrames) do
                                if r2 ~= self and r2._baseY then
                                    local rm = mT + r2._baseY - MH / 2
                                    if curY > rm then
                                        iI = ri
                                        break
                                    end
                                    iI = ri + 1
                                end
                            end
                            iI = math.max(1, math.min(iI, #rowFrames + 1))
                            if from < iI then iI = iI - 1 end
                            local to = math.max(1, math.min(iI, #rowFrames))
                            if from ~= to then
                                local mv = table.remove(rowFrames, from)
                                table.insert(rowFrames, to, mv)
                                PersistOrder()
                            end
                            for ri = 1, #rowFrames do
                                local r2 = rowFrames[ri]
                                r2._cbIndex = ri
                                local ry = cbBaseY - (ri - 1) * MH
                                r2._baseY = ry
                                r2:ClearAllPoints()
                                r2:SetPoint("TOPLEFT", sChild, "TOPLEFT", 1, ry)
                                r2:SetPoint("TOPRIGHT", sChild, "TOPRIGHT", -1, ry)
                            end
                        end)
                        return rf
                    end

                    -- row.items() is read again on every open: a cached popup must
                    -- not keep a list that changed since (the stats shown right
                    -- now, a tracked spell list). An unchanged list keeps its rows.
                    local itemSig
                    local function Populate()
                        local itemList = (row.items and row.items()) or {}
                        local sig = ""
                        for _, it in ipairs(itemList) do
                            sig = sig .. tostring(it.key) .. "\n" .. tostring(it.label) .. "\n"
                        end
                        if sig == itemSig then return end
                        itemSig = sig
                        wipe(rowFrames)
                        for ci, it in ipairs(itemList) do
                            local rf = rowPool[ci] or MakeRow()
                            rowPool[ci] = rf
                            local ry = cbBaseY - (ci - 1) * MH
                            rf._baseY, rf._cbIndex, rf._key = ry, ci, it.key
                            rf._lbl:SetText(it.label)
                            rf:ClearAllPoints()
                            rf:SetPoint("TOPLEFT", sChild, "TOPLEFT", 1, ry)
                            rf:SetPoint("TOPRIGHT", sChild, "TOPRIGHT", -1, ry)
                            rf:Show()
                            rowFrames[ci] = rf
                        end
                        for idx = #itemList + 1, #rowPool do
                            rowPool[idx]:Hide()
                        end
                        local visN = #itemList
                        if row.maxVisible and row.maxVisible > 0 and visN > row.maxVisible then
                            visN = row.maxVisible
                        end
                        local listH, visH = #itemList * MH, visN * MH
                        scroller:SetHeight(math.max(visH, 1))
                        sChild:SetSize(RR_W, math.max(listH, 1))
                        scroller:SetVerticalScroll(0)
                        maxScroll = math.max(0, listH - visH)
                        dropMenu:SetHeight(20 + visH + 4)
                    end
                    Populate()
                    CUI.TrackOverlay(dropMenu)

                    dropdownBtn:SetScript("OnClick", function()
                        if dropMenu:IsShown() then
                            dropMenu:Hide()
                        else
                            Populate()
                            dropMenu:Show()
                        end
                        -- Controller cursor: into the opened list.
                        if CUI.PadCursorShown() and dropMenu:IsShown() then CUI.PadFocus(dropMenu) end
                    end)

                    -- Disabled overlay: dim + block + hide menu
                    local reorderDis
                    if row.disabled then
                        reorderDis = CreateFrame("Frame", nil, popFrame)
                        reorderDis:SetPoint("TOPLEFT", ca, "TOPLEFT", 1, curY)
                        reorderDis:SetPoint("TOPRIGHT", ca, "TOPRIGHT", -1, curY)
                        reorderDis:SetHeight(DROPDOWN_ROW_H)
                        reorderDis:SetFrameLevel(popFrame:GetFrameLevel() + 12)
                        reorderDis:EnableMouse(true)
                        local disTex = SolidTex(reorderDis, "OVERLAY", 0.062, 0.070, 0.082, 0.70)
                        disTex:SetAllPoints()
                        reorderDis:SetScript("OnEnter", function(self)
                            local tipText = ResolveDisabledTip(row)
                            if tipText and CUI.ShowWidgetTooltip then CUI.ShowWidgetTooltip(self, tipText) end
                        end)
                        reorderDis:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
                        local initDis = type(row.disabled) == "function" and row.disabled() or row.disabled
                        if initDis then
                            reorderDis:Show()
                        else
                            reorderDis:Hide()
                        end
                    end

                    rowWidgets[#rowWidgets + 1] = {
                        type = "reorder",
                        btn = dropdownBtn,
                        menu = dropMenu,
                        disOverlay = reorderDis,
                        disCheck = row.disabled,
                    }
                    curY = curY - DROPDOWN_ROW_H
                end
            end
            -- Columns: the footer goes under the last band.
            if multi then curY = contentBottom end

            if options.footer and options.footer.unlockKey then
                local footerY = curY - 10
                local line1 = MakeFont(popFrame, 12, nil, 0x78 / 255, 0x7b / 255, 0x81 / 255)
                line1:SetText(CUI.L("Reposition freely with"))
                line1:SetPoint("TOP", popFrame, "TOPLEFT", POPUP_W / 2, footerY)

                local unlockBtn = CreateFrame("Button", nil, popFrame)
                unlockBtn:SetSize(80, 14)
                unlockBtn:SetPoint("TOP", line1, "BOTTOM", 0, -5)
                local _ugr, _ugg, _ugb = CLUDES_GREEN.r, CLUDES_GREEN.g, CLUDES_GREEN.b
                local _uhr = _ugr + (1 - _ugr) * 0.25
                local _uhg = _ugg + (1 - _ugg) * 0.25
                local _uhb = _ugb + (1 - _ugb) * 0.25
                local unlockFS = MakeFont(unlockBtn, 13, nil, _ugr, _ugg, _ugb)
                unlockFS:SetAlpha(0.9)
                unlockFS:SetText(CUI.L("Layout Mode"))
                unlockFS:SetPoint("CENTER")
                unlockBtn:SetScript("OnClick", function()
                    popFrame:Hide()
                    CUI.OpenUnlockModeAt(options.footer.unlockKey)
                end)
                unlockBtn:SetScript("OnEnter", function(self)
                    unlockFS:SetTextColor(_uhr, _uhg, _uhb)
                    unlockFS:SetAlpha(1)
                end)
                unlockBtn:SetScript("OnLeave", function(self)
                    unlockFS:SetTextColor(_ugr, _ugg, _ugb)
                    unlockFS:SetAlpha(0.9)
                end)
            end
            -- Re-read every get function and update visuals
            popFrame._refresh = function()
                for _, rw in ipairs(rowWidgets) do
                    if rw.type == "slider" then
                        if rw.disOverlay and rw.disCheck then
                            local dis
                            if type(rw.disCheck) == "function" then
                                dis = rw.disCheck()
                            else
                                dis = rw.disCheck
                            end
                            if dis then
                                rw.disOverlay:Show()
                            else
                                rw.disOverlay:Hide()
                            end
                        end
                        if rw.updateVisual and rw.get then rw.updateVisual(rw.get()) end
                    elseif rw.type == "toggle" then
                        if rw.disOverlay and rw.disCheck then
                            local dis
                            if type(rw.disCheck) == "function" then
                                dis = rw.disCheck()
                            else
                                dis = rw.disCheck
                            end
                            if dis then
                                rw.disOverlay:Show()
                            else
                                rw.disOverlay:Hide()
                            end
                        end
                        if rw.updateVisual then rw.updateVisual() end
                    elseif rw.type == "colorpicker" then
                        if rw.disCheck then
                            local dis
                            if type(rw.disCheck) == "function" then
                                dis = rw.disCheck()
                            else
                                dis = rw.disCheck
                            end
                            if rw.swatch then rw.swatch:SetAlpha(dis and 0.3 or 1) end
                            if rw.lbl then rw.lbl:SetAlpha(dis and 0.2 or 0.6) end
                            if rw.swBlock then
                                if dis then
                                    rw.swBlock:Show()
                                else
                                    rw.swBlock:Hide()
                                end
                            end
                            if rw.lblBlock then
                                if dis then
                                    rw.lblBlock:Show()
                                else
                                    rw.lblBlock:Hide()
                                end
                            end
                        end
                        if rw.updateSwatch then rw.updateSwatch() end
                    elseif rw.type == "dropdown" then
                        if rw.disOverlay and rw.disCheck then
                            local dis
                            if type(rw.disCheck) == "function" then
                                dis = rw.disCheck()
                            else
                                dis = rw.disCheck
                            end
                            if dis then
                                rw.disOverlay:Show()
                            else
                                rw.disOverlay:Hide()
                            end
                        end
                        if rw.lbl and rw.get and rw.values then
                            rw.lbl:SetText(CUI.L(DDText(rw.values[rw.get()]) or tostring(rw.get())))
                            if rw.refresh then rw.refresh() end
                        end
                    elseif rw.type == "input" then
                        if rw.disOverlay and rw.disCheck then
                            local dis
                            if type(rw.disCheck) == "function" then
                                dis = rw.disCheck()
                            else
                                dis = rw.disCheck
                            end
                            if dis then
                                rw.disOverlay:Show()
                            else
                                rw.disOverlay:Hide()
                            end
                        end
                        if rw.box and rw.get and not rw.box:HasFocus() then
                            rw.box:SetText(rw.get())
                            if rw.leftJustify then rw.box:SetCursorPosition(0) end
                        end
                        -- Re-apply save button colour for the current theme
                        if rw.saveBg then
                            rw.saveBg:SetColorTexture(CLUDES_GREEN.r, CLUDES_GREEN.g, CLUDES_GREEN.b, 0.85)
                        end
                    elseif rw.type == "segmented" then
                        if rw.disOverlay and rw.disCheck then
                            local dis
                            if type(rw.disCheck) == "function" then
                                dis = rw.disCheck()
                            else
                                dis = rw.disCheck
                            end
                            if dis then
                                rw.disOverlay:Show()
                            else
                                rw.disOverlay:Hide()
                            end
                        end
                        if rw.refresh then rw.refresh() end
                    elseif rw.type == "multiswatch" then
                        if rw.disOverlay and rw.disCheck then
                            local dis
                            if type(rw.disCheck) == "function" then
                                dis = rw.disCheck()
                            else
                                dis = rw.disCheck
                            end
                            if dis then
                                rw.disOverlay:Show()
                            else
                                rw.disOverlay:Hide()
                            end
                        end
                        if rw.updates then
                            for idx = 1, #rw.updates do
                                rw.updates[idx]()
                            end
                        end
                        if rw.alphaFns then
                            for idx = 1, #rw.alphaFns do
                                local a = rw.alphaFns[idx]
                                a.sw:SetAlpha(a.fn())
                            end
                        end
                    elseif rw.type == "reorder" then
                        if rw.disOverlay and rw.disCheck then
                            local dis
                            if type(rw.disCheck) == "function" then
                                dis = rw.disCheck()
                            else
                                dis = rw.disCheck
                            end
                            if dis then
                                rw.disOverlay:Show()
                                if rw.menu then rw.menu:Hide() end
                            else
                                rw.disOverlay:Hide()
                            end
                        end
                    elseif rw.type == "reordercheck" then
                        if rw.disOverlay then
                            local dis = rw.disCheck
                            if type(dis) == "function" then dis = dis() end
                            rw.disOverlay:SetShown(dis and true or false)
                            if dis and rw.btn._ddMenu then rw.btn._ddMenu:Hide() end
                        end
                        if rw.refresh then rw.refresh() end
                    end
                end
                -- A change made inside flipped a row.hidden: the matching frame takes over.
                if dynamic and popFrame:IsShown() and HiddenSig() ~= popFrame._sig then SwapVariant() end
            end

            -- True while a dropdown menu opened from inside this popup is shown and moused over. Exposed so external close-logic (e.g. a parent menu driving this popup as a flyout with its own _clickOutside disabled) stays open when a clicked dropdown list extends below the popup's own rect.
            popFrame._anyDropdownHovered = function()
                for _, rw in ipairs(rowWidgets) do
                    if
                        (rw.type == "dropdown" or rw.type == "reorder" or rw.type == "reordercheck")
                        and rw.btn
                        and rw.btn._ddMenu
                        and rw.btn._ddMenu:IsShown()
                        and rw.btn._ddMenu:IsMouseOver()
                    then
                        return true
                    end
                    -- A cog popup a dropdown row opened beside this one (btn._sidePopup).
                    local sp = rw.btn and rw.btn._sidePopup
                    if sp and sp:IsShown() and (sp:IsMouseOver() or sp._anyDropdownHovered()) then
                        return true
                    end
                end
                return false
            end

            -- Click-outside-to-close; also closes when scrolled out of view
            local wasDown = false
            popFrame._clickOutside = function(self)
                local down = IsMouseButtonDown("LeftButton")
                if down and not wasDown then
                    if
                        not self:IsMouseOver()
                        and not (popupOwner and popupOwner:IsMouseOver())
                        and not popFrame._anyDropdownHovered()
                    then
                        self:Hide()
                    end
                end
                wasDown = down

                -- Close when the anchor button scrolls out of the visible area
                if popupOwner then
                    local scrollFrame = CUI._scrollFrame
                    if scrollFrame then
                        if popupOwner._inScrollChild == nil then
                            local scrollChild = scrollFrame.GetScrollChild and scrollFrame:GetScrollChild()
                            local found = false
                            if scrollChild then
                                local p = popupOwner:GetParent()
                                while p do
                                    if p == scrollChild then
                                        found = true
                                        break
                                    end
                                    p = p:GetParent()
                                end
                            end
                            popupOwner._inScrollChild = found
                        end
                        if popupOwner._inScrollChild then
                            local sfTop = scrollFrame:GetTop()
                            local sfBot = scrollFrame:GetBottom()
                            local btnBot = popupOwner:GetBottom()
                            if sfTop and sfBot and btnBot then
                                if btnBot < sfBot or btnBot > sfTop then self:Hide() end
                            end
                        end
                    end
                end
            end

            popFrame:SetScript("OnHide", function(self)
                self:SetScript("OnUpdate", nil)
                local ownerFrame = popupOwner
                popupOwner = nil
                popFrame._owner = nil
                -- Dim the anchor back to cog idle alpha; skipped via noOwnerDim when the anchor isn't a cog (e.g. a preview icon) and must not fade.
                -- A hand-built glyph button goes back to its idle alpha through SetGlyphAlpha.
                if ownerFrame and ownerFrame._cuiCogState then
                    ownerFrame._cuiCogState()
                elseif ownerFrame and not options.noOwnerDim then
                    if ownerFrame._glyphA then
                        CUI.SetGlyphAlpha(ownerFrame, 0.4)
                    else
                        ownerFrame:SetAlpha(0.4)
                    end
                end
                -- Controller cursor: back onto the cog (not for the hover-opened popups,
                -- where it stays free; a no-op once the cog is hidden).
                if ownerFrame and not options.noOwnerDim and CUI.PadCursorShown() then
                    CUI.PadFocus(ownerFrame)
                end
            end)

            -- Close when the main CludesUI frame hides (HidePanelPopups)
            if CUI._mainFrame and not panelPopups[popFrame] then
                panelPopupN = panelPopupN + 1
                panelPopups[popFrame] = panelPopupN
                if not panelHooked then
                    panelHooked = true
                    CUI._mainFrame:HookScript("OnHide", HidePanelPopups)
                end
            end

            -- Every dress (a no-op once tracked): a popup first made before the
            -- controller overlay layer existed is tracked once it sits on it.
            CUI.TrackOverlay(popFrame)
            popupFrame = popFrame
            popFrame._sig = sig
            if variants then variants[sig] = popFrame end
            return popFrame
        end

        -- showFn: toggle popup anchored to a button. Wrapped in a callable table so callers can access showFn._popupFrame.
        local showFn = setmetatable({}, {
            __call = function(self, anchorBtn)
                if dynamic then
                    -- The frame for the rows shown right now (built on first need).
                    local current = popupFrame
                    local wanted = variants[HiddenSig()] or CreatePopup(HiddenSig(), anchorBtn)
                    popupFrame = current
                    if popupFrame ~= wanted then
                        if popupFrame and popupFrame:IsShown() then popupFrame:Hide() end
                        popupFrame = wanted
                    end
                    self._popupFrame = popupFrame
                elseif not popupFrame then
                    CreatePopup(nil, anchorBtn)
                    self._popupFrame = popupFrame
                end

                -- Toggle off if same anchor clicked while visible
                if popupOwner == anchorBtn and popupFrame:IsShown() then
                    popupFrame:Hide()
                    return
                end
                local prevOwner = popupOwner
                popupOwner = anchorBtn
                popupFrame._owner = anchorBtn
                if prevOwner and prevOwner ~= anchorBtn and prevOwner._cuiCogState then
                    prevOwner._cuiCogState()
                end

                -- Refresh all widget visuals from get functions
                popupFrame._refresh()

                -- Anchor below the cog icon and animate downward
                popupFrame:ClearAllPoints()
                popupFrame:SetPoint("TOP", anchorBtn, "BOTTOM", 0, -5)
                popupFrame:SetAlpha(0)
                popupFrame:Show()
                local elapsed = 0
                local anchorGen = PoolGen(anchorBtn)
                popupFrame:SetScript("OnUpdate", function(self, dt)
                    -- The anchor was dressed again mid-slide (page reuse): the popup
                    -- stays where it is, fully shown.
                    if PoolGen(anchorBtn) ~= anchorGen or PoolIsIdle(anchorBtn) then
                        self:SetAlpha(1)
                        self:SetScript("OnUpdate", self._clickOutside)
                        return
                    end
                    elapsed = elapsed + dt
                    local t = math.min(elapsed / 0.15, 1)
                    self:SetAlpha(t)
                    self:ClearAllPoints()
                    self:SetPoint("TOP", anchorBtn, "BOTTOM", 0, -5 + (8 * (1 - t)))
                    if t >= 1 then self:SetScript("OnUpdate", self._clickOutside) end
                end)
                if anchorBtn._cuiCogState then anchorBtn._cuiCogState() end
                -- Controller cursor: Cancel clicks the anchor again (a second click on the same
                -- anchor closes the popup), and the cursor moves into the popup. Not for the
                -- hover-opened popups (noOwnerDim: the anchor is a menu row, not a cog), where
                -- the cursor must stay free to walk past the row.
                if CUI.PadCP() and not options.noOwnerDim then
                    popupFrame.CloseButton = anchorBtn.Click and anchorBtn or nil
                    if CUI.PadCursorShown() then CUI.PadFocus(popupFrame) end
                end
            end,
        })

        -- Open, a change made inside flipped a row.hidden: the frame for the new
        -- set of rows takes the same anchor, without the open animation.
        SwapVariant = function()
            local ownerFrame = popupOwner
            if not (dynamic and ownerFrame) then return end
            local old = popupFrame
            local wanted = variants[HiddenSig()] or CreatePopup(HiddenSig(), ownerFrame)
            popupFrame = old
            if wanted == old then return end
            if old then old:Hide() end -- its OnHide lets go of the owner
            popupFrame = wanted
            showFn._popupFrame = wanted
            popupOwner = ownerFrame
            wanted._owner = ownerFrame
            wanted._refresh()
            wanted:ClearAllPoints()
            wanted:SetPoint("TOP", ownerFrame, "BOTTOM", 0, -5)
            wanted:SetAlpha(1)
            wanted:Show()
            wanted:SetScript("OnUpdate", wanted._clickOutside)
            if ownerFrame._cuiCogState then ownerFrame._cuiCogState() end
            if CUI.PadCP() and not options.noOwnerDim then
                wanted.CloseButton = ownerFrame.Click and ownerFrame or nil
                if CUI.PadCursorShown() then CUI.PadFocus(wanted) end
            end
        end

        return popupFrame, showFn
    end

    CUI.BuildCogPopup = BuildCogPopup
end -- end deferred init
