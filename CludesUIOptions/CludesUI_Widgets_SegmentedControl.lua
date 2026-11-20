if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUI_Widgets_SegmentedControl.lua
--  BuildSegmentedControl, the pill-shaped tab bar of the multi-edit headers.
--  DEFERRED: body runs on first CludesUI:EnsureLoaded() call, not at load.
-------------------------------------------------------------------------------
local CUI = _G.CludesUI
CUI._deferredInits[#CUI._deferredInits + 1] = function()
    -- Page reuse: the frames this file builds go through the options frame pool
    -- (CludesUI_FramePool.lua), which hands a kept page or popup its previous
    -- build's frames back reset to new; on any other parent it creates as before.
    local CreateFrame = CUI._Pool.CreateFrame
    local Pix = CUI.PanelPP
    local CLUDES_GREEN = CUI.CLUDES_GREEN
    local MEDIA_PATH = CUI.MEDIA_PATH
    local ShowWidgetTooltip = CUI.ShowWidgetTooltip
    local HideWidgetTooltip = CUI.HideWidgetTooltip

    -------------------------------------------------------------------------------
    --  Segmented Control  (pill-shaped tab bar for multi-edit headers)
    --  cfg = {
    --      parent       = Frame,          -- parent frame to attach to
    --      width        = number,         -- total width (used as fallback)
    --      autoWidth    = bool,           -- auto-size to fit label content
    --      keys         = { "k1", ... },  -- ordered keys
    --      labels       = { k1="Lbl" },   -- display labels per key
    --      getChecked   = function(key) -> bool,
    --      getEyeball   = function() -> key  (optional, the "primary" selected key)
    --      onToggle     = function(key),  -- called when a segment is clicked
    --      isDisabled   = function(key) -> bool  (optional, grays out segment)
    --      disabledTip  = function(key) -> string (optional, tooltip for disabled)
    --  }
    --  Returns: frame, height, refreshFn, buttons (key -> segment button)
    -------------------------------------------------------------------------------
    -- The one hidden font string every control measures its labels with (made on
    -- the first build, shown only while it measures, as a new one was).
    local measureFS

    local function BuildSegmentedControl(rowConf)
        local ACCENT = CLUDES_GREEN
        local SEG_H = rowConf.height or 28
        local FONT_SZ = 13
        local SEG_PAD = 22
        local PILL_BG = { 0.125, 0.125, 0.137 } -- #202023
        local PILL_BGA = 0.95
        local INACTIVE_R, INACTIVE_G, INACTIVE_B = 0.467, 0.471, 0.482 -- #77787b
        local INACTIVE_A = 0.5
        local ACTIVE_R, ACTIVE_G, ACTIVE_B = ACCENT.r, ACCENT.g, ACCENT.b
        local BG_HOVER_BOOST = 0.04 -- 4% brightness on hover for background

        local numKeys = #rowConf.keys

        local tmpFS = measureFS
        if tmpFS then
            tmpFS:Show()
        else
            tmpFS = UIParent:CreateFontString(nil, "OVERLAY")
            measureFS = tmpFS
        end
        tmpFS:SetFont(CUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF", FONT_SZ, "")
        local segWidths, textW = {}, {}
        local pillW = 0
        for _, key in ipairs(rowConf.keys) do
            tmpFS:SetText(CUI.L(rowConf.labels[key] or key))
            textW[key] = math.ceil(tmpFS:GetStringWidth())
            local wid = textW[key] + SEG_PAD * 2
            segWidths[key] = wid
            pillW = pillW + wid
        end
        tmpFS:Hide()

        -- Square mode: a box with rounded corners. Its segments sit BOX_PAD inside
        -- one outline, BOX_GAP apart; the checked one carries a rounded marker.
        local SQUARE = rowConf.square and true or false
        local BOX_PAD, BOX_GAP = 2, 2
        local boxExtra = SQUARE and (BOX_PAD * 2 + BOX_GAP * (numKeys - 1)) or 0

        if not rowConf.autoWidth then
            pillW = rowConf.width - boxExtra
            local baseW = math.floor(pillW / numKeys)
            local remainder = pillW - baseW * numKeys
            for position, key in ipairs(rowConf.keys) do
                segWidths[key] = baseW + (position <= remainder and 1 or 0)
                -- A long translated label widens its segment instead of overflowing it.
                segWidths[key] = math.max(segWidths[key], textW[key] + 16)
            end
        end

        local capW = SQUARE and 0 or SEG_H
        if not SQUARE then
            segWidths[rowConf.keys[1]] = math.floor(segWidths[rowConf.keys[1]] - capW)
            segWidths[rowConf.keys[numKeys]] = math.floor(segWidths[rowConf.keys[numKeys]] - capW)
        end
        pillW = 0
        for _, key in ipairs(rowConf.keys) do
            pillW = pillW + segWidths[key]
        end
        -- Account for 1px overlap between adjacent segments
        local overlapTotal = SQUARE and 0 or (numKeys - 1) * 1
        local totalW = pillW + capW * 2 - overlapTotal + boxExtra

        local widget = CreateFrame("Frame", nil, rowConf.parent)
        widget:SetSize(totalW, SEG_H)

        local pillBody = CreateFrame("Frame", nil, widget)
        pillBody:SetSize(pillW - overlapTotal + boxExtra, SEG_H)
        Pix.Point(pillBody, "TOP", widget, "TOP", 0, 0)
        pillBody:SetFrameLevel(widget:GetFrameLevel() + 1)

        local backdrop = pillBody:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(0, 0, 0, 0) -- transparent; per-segment segBg handles background
        local boxBdr = SQUARE
            and CUI.MakeRoundedBorder(
                pillBody,
                INACTIVE_R,
                INACTIVE_G,
                INACTIVE_B,
                INACTIVE_A,
                backdrop,
                2
            )

        -------------------------------------------------------------------
        -- Pill caps
        -------------------------------------------------------------------
        local CAP_FILL_L_TEX = MEDIA_PATH .. "pill-fill-l.png"
        local CAP_FILL_R_TEX = MEDIA_PATH .. "pill-fill-r.png"
        local CAP_BORDER_L_TEX = MEDIA_PATH .. "pill-border-l.png"
        local CAP_BORDER_R_TEX = MEDIA_PATH .. "pill-border-r.png"

        local capLeftFill = pillBody:CreateTexture(nil, "BACKGROUND", nil, 1)
        capLeftFill:SetSize(capW, SEG_H)
        capLeftFill:SetTexture(CAP_FILL_L_TEX)
        capLeftFill:SetVertexColor(PILL_BG[1], PILL_BG[2], PILL_BG[3], PILL_BGA)

        local capLeftBdr = pillBody:CreateTexture(nil, "BACKGROUND", nil, 2)
        capLeftBdr:SetSize(capW, SEG_H)
        capLeftBdr:SetTexture(CAP_BORDER_L_TEX)

        local capRightFill = pillBody:CreateTexture(nil, "BACKGROUND", nil, 1)
        capRightFill:SetSize(capW, SEG_H)
        capRightFill:SetTexture(CAP_FILL_R_TEX)
        capRightFill:SetVertexColor(PILL_BG[1], PILL_BG[2], PILL_BG[3], PILL_BGA)

        local capRightBdr = pillBody:CreateTexture(nil, "BACKGROUND", nil, 2)
        capRightBdr:SetSize(capW, SEG_H)
        capRightBdr:SetTexture(CAP_BORDER_R_TEX)

        -- Cap accent overlays (5% accent tint when checked, using same pill cap PNGs)
        local capLeftAccent = pillBody:CreateTexture(nil, "BACKGROUND", nil, 3)
        capLeftAccent:SetSize(capW, SEG_H)
        capLeftAccent:SetTexture(CAP_FILL_L_TEX)
        capLeftAccent:SetVertexColor(ACCENT.r, ACCENT.g, ACCENT.b, 0.05)
        capLeftAccent:Hide()

        local capRightAccent = pillBody:CreateTexture(nil, "BACKGROUND", nil, 3)
        capRightAccent:SetSize(capW, SEG_H)
        capRightAccent:SetTexture(CAP_FILL_R_TEX)
        capRightAccent:SetVertexColor(ACCENT.r, ACCENT.g, ACCENT.b, 0.05)
        capRightAccent:Hide()

        -- Cap click zones anchored to pillBody for now, re-anchored after segments
        local capLeftBtn = CreateFrame("Button", nil, widget)
        capLeftBtn:SetSize(capW, SEG_H)
        Pix.Point(capLeftBtn, "RIGHT", pillBody, "LEFT", 0, 0)
        capLeftBtn:SetFrameLevel(pillBody:GetFrameLevel() + 4)
        capLeftBtn:SetScript("OnClick", function()
            local key = rowConf.keys[1]
            if rowConf.isDisabled and rowConf.isDisabled(key) then
                return
            end
            if rowConf.onToggle then
                rowConf.onToggle(key)
            end
        end)
        capLeftBtn:SetScript("OnEnter", function()
            local key = rowConf.keys[1]
            if rowConf.isDisabled and rowConf.isDisabled(key) then
                if rowConf.disabledTip then
                    local tipText = rowConf.disabledTip(key)
                    if tipText then
                        ShowWidgetTooltip(capLeftBtn, tipText)
                    end
                end
                return
            end
            widget._hoverIdx = 1
            if widget._refreshAll then
                widget._refreshAll()
            end
        end)
        capLeftBtn:SetScript("OnLeave", function()
            HideWidgetTooltip()
            widget._hoverIdx = nil
            if widget._refreshAll then
                widget._refreshAll()
            end
        end)

        local capRightBtn = CreateFrame("Button", nil, widget)
        capRightBtn:SetSize(capW, SEG_H)
        Pix.Point(capRightBtn, "LEFT", pillBody, "RIGHT", 0, 0)
        capRightBtn:SetFrameLevel(pillBody:GetFrameLevel() + 4)
        capRightBtn:SetScript("OnClick", function()
            local key = rowConf.keys[numKeys]
            if rowConf.isDisabled and rowConf.isDisabled(key) then
                return
            end
            if rowConf.onToggle then
                rowConf.onToggle(key)
            end
        end)
        capRightBtn:SetScript("OnEnter", function()
            local key = rowConf.keys[numKeys]
            if rowConf.isDisabled and rowConf.isDisabled(key) then
                if rowConf.disabledTip then
                    local tipText = rowConf.disabledTip(key)
                    if tipText then
                        ShowWidgetTooltip(capRightBtn, tipText)
                    end
                end
                return
            end
            widget._hoverIdx = numKeys
            if widget._refreshAll then
                widget._refreshAll()
            end
        end)
        capRightBtn:SetScript("OnLeave", function()
            HideWidgetTooltip()
            widget._hoverIdx = nil
            if widget._refreshAll then
                widget._refreshAll()
            end
        end)

        -------------------------------------------------------------------
        -- Segments each has full 1px border; adjacent segments overlap by 1px
        -------------------------------------------------------------------
        local segments = {}
        local btnByKey = {}
        local BASE_LEVEL = pillBody:GetFrameLevel() + 3
        local CHECKED_LEVEL = BASE_LEVEL + 1 -- checked segments draw on top

        for i, key in ipairs(rowConf.keys) do
            local thisW = segWidths[key]

            local button = CreateFrame("Button", nil, pillBody)
            if SQUARE then
                Pix.Size(button, thisW, SEG_H - BOX_PAD * 2)
                if i == 1 then
                    Pix.Point(button, "TOPLEFT", pillBody, "TOPLEFT", BOX_PAD, -BOX_PAD)
                else
                    Pix.Point(button, "TOPLEFT", segments[i - 1].btn, "TOPRIGHT", BOX_GAP, 0)
                end
            else
                Pix.Size(button, thisW, SEG_H)
                if i == 1 then
                    Pix.Point(button, "TOPLEFT", pillBody, "TOPLEFT", 0, 0)
                else
                    -- Anchor to previous segment's right edge, shifted 1px left for overlap
                    Pix.Point(button, "TOPLEFT", segments[i - 1].btn, "TOPRIGHT", -1, 0)
                end
            end
            button:SetFrameLevel(BASE_LEVEL)

            -- Per-segment hover background overlay
            local segBg = button:CreateTexture(nil, "BACKGROUND", nil, 1)
            segBg:SetAllPoints()
            segBg:SetColorTexture(PILL_BG[1], PILL_BG[2], PILL_BG[3], PILL_BGA)

            -- Accent tint overlay for checked/active segments (5% opacity)
            local accentBg = button:CreateTexture(nil, "BACKGROUND", nil, 2)
            accentBg:SetAllPoints()
            accentBg:SetColorTexture(ACCENT.r, ACCENT.g, ACCENT.b, 0.05)
            accentBg:Hide()

            -- Square mode: the marker, a rounded outline with segBg as its body.
            local segTop, segBot, segLeft, segRight, marker
            if SQUARE then
                marker = CUI.MakeRoundedBorder(button, ACTIVE_R, ACTIVE_G, ACTIVE_B, 0, segBg, 1)
            else
                -- Full 1px border on all 4 sides matches MakeBorder's pixel-perfect technique: vertical edges inset by 1px to avoid overlapping corners.
                segTop = button:CreateTexture(nil, "ARTWORK", nil, 7)
                segTop:SetColorTexture(INACTIVE_R, INACTIVE_G, INACTIVE_B, INACTIVE_A)
                segTop:SetHeight(1)
                Pix.Point(segTop, "TOPLEFT", button, "TOPLEFT", 0, 0)
                Pix.Point(segTop, "TOPRIGHT", button, "TOPRIGHT", 0, 0)

                segBot = button:CreateTexture(nil, "ARTWORK", nil, 7)
                segBot:SetColorTexture(INACTIVE_R, INACTIVE_G, INACTIVE_B, INACTIVE_A)
                segBot:SetHeight(1)
                Pix.Point(segBot, "BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
                Pix.Point(segBot, "BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)

                -- Vertical edges anchored to horizontal edges (inset 1px) to avoid bright corners
                segLeft = button:CreateTexture(nil, "ARTWORK", nil, 7)
                segLeft:SetColorTexture(INACTIVE_R, INACTIVE_G, INACTIVE_B, INACTIVE_A)
                segLeft:SetWidth(1)
                Pix.Point(segLeft, "TOPLEFT", segTop, "BOTTOMLEFT", 0, 0)
                Pix.Point(segLeft, "BOTTOMLEFT", segBot, "TOPLEFT", 0, 0)

                segRight = button:CreateTexture(nil, "ARTWORK", nil, 7)
                segRight:SetColorTexture(INACTIVE_R, INACTIVE_G, INACTIVE_B, INACTIVE_A)
                segRight:SetWidth(1)
                Pix.Point(segRight, "TOPRIGHT", segTop, "BOTTOMRIGHT", 0, 0)
                Pix.Point(segRight, "BOTTOMRIGHT", segBot, "TOPRIGHT", 0, 0)
            end

            local labelFS = button:CreateFontString(nil, "OVERLAY")
            labelFS:SetFont(CUI.EXPRESSWAY, FONT_SZ, "")
            local lblOfsX = 0
            if i == 1 then
                lblOfsX = -capW / 2
            end
            if i == numKeys then
                lblOfsX = capW / 2
            end
            labelFS:SetPoint("CENTER", lblOfsX, 0)
            labelFS:SetText(CUI.L(rowConf.labels[key] or key))

            segments[i] = {
                key = key,
                btn = button,
                lbl = labelFS,
                w = thisW,
                segBg = segBg,
                accentBg = accentBg,
                segTop = segTop,
                segBot = segBot,
                segLeft = segLeft,
                segRight = segRight,
                marker = marker,
            }
            btnByKey[key] = button

            button:SetScript("OnClick", function()
                if rowConf.isDisabled and rowConf.isDisabled(key) then
                    return
                end
                if rowConf.onToggle then
                    rowConf.onToggle(key)
                end
            end)

            button:SetScript("OnEnter", function()
                if rowConf.isDisabled and rowConf.isDisabled(key) then
                    if rowConf.disabledTip then
                        local tipText = rowConf.disabledTip(key)
                        if tipText then
                            ShowWidgetTooltip(button, tipText)
                        end
                    end
                    return
                end
                widget._hoverIdx = i
                if widget._refreshAll then
                    widget._refreshAll()
                end
            end)

            button:SetScript("OnLeave", function()
                HideWidgetTooltip()
                widget._hoverIdx = nil
                if widget._refreshAll then
                    widget._refreshAll()
                end
            end)
        end

        -------------------------------------------------------------------
        -- Anchor caps to segment buttons. Raw SetPoint (not PixelUtil) for cap textures to avoid asymmetric pixel rounding that squishes one side.
        -------------------------------------------------------------------
        local firstBtn = segments[1].btn
        local lastBtn = segments[#segments].btn

        capLeftFill:SetPoint("RIGHT", firstBtn, "LEFT", 0, 0)
        capLeftBdr:SetPoint("RIGHT", firstBtn, "LEFT", 0, 0)
        capLeftAccent:SetPoint("RIGHT", firstBtn, "LEFT", 0, 0)
        capRightFill:SetPoint("LEFT", lastBtn, "RIGHT", 0, 0)
        capRightBdr:SetPoint("LEFT", lastBtn, "RIGHT", 0, 0)
        capRightAccent:SetPoint("LEFT", lastBtn, "RIGHT", 0, 0)
        capLeftBtn:ClearAllPoints()
        capLeftBtn:SetPoint("RIGHT", firstBtn, "LEFT", 0, 0)
        capRightBtn:ClearAllPoints()
        capRightBtn:SetPoint("LEFT", lastBtn, "RIGHT", 0, 0)

        if SQUARE then
            -- No rounded caps: hide the textures and their click zones outright.
            capLeftFill:Hide()
            capLeftBdr:Hide()
            capLeftAccent:Hide()
            capRightFill:Hide()
            capRightBdr:Hide()
            capRightAccent:Hide()
            capLeftBtn:Hide()
            capRightBtn:Hide()
        end

        -------------------------------------------------------------------
        -- RefreshAll
        -------------------------------------------------------------------
        local function RefreshAll()
            local eyeKey = rowConf.getEyeball and rowConf.getEyeball()
            local hoverIdx = widget._hoverIdx

            for position, seg in ipairs(segments) do
                local disabled = rowConf.isDisabled and rowConf.isDisabled(seg.key)
                local checked = rowConf.getChecked(seg.key)
                local isHover = (hoverIdx == position)

                -- Label color
                if disabled then
                    seg.lbl:SetTextColor(1, 1, 1, 0.20)
                elseif checked then
                    seg.lbl:SetTextColor(ACTIVE_R, ACTIVE_G, ACTIVE_B, 1.0)
                else
                    seg.lbl:SetTextColor(1, 1, 1, 0.60)
                end

                -- Checked segments get higher frame level so their border draws on top of the adjacent unchecked segment's border.
                if checked and not disabled then
                    seg.btn:SetFrameLevel(CHECKED_LEVEL)
                else
                    seg.btn:SetFrameLevel(BASE_LEVEL)
                end

                -- Border color: checked = accent, unchecked = inactive gray, disabled = 25% opacity
                local br, bg2, bb, ba
                if disabled then
                    br, bg2, bb, ba = INACTIVE_R, INACTIVE_G, INACTIVE_B, 0.10
                elseif checked then
                    br, bg2, bb, ba = ACTIVE_R, ACTIVE_G, ACTIVE_B, 1.0
                else
                    br, bg2, bb, ba = INACTIVE_R, INACTIVE_G, INACTIVE_B, INACTIVE_A
                end

                seg.segTop:SetColorTexture(br, bg2, bb, ba)
                seg.segBot:SetColorTexture(br, bg2, bb, ba)
                seg.segLeft:SetColorTexture(br, bg2, bb, ba)
                seg.segRight:SetColorTexture(br, bg2, bb, ba)

                -- All 4 borders visible, except: first segment hides its left, last hides its right -- the rounded caps draw those edges. (Square mode refreshes in RefreshBox.)
                seg.segTop:Show()
                seg.segBot:Show()
                local isFirst = (position == 1)
                local isLast = (position == #segments)
                if isFirst then
                    seg.segLeft:Hide()
                else
                    seg.segLeft:Show()
                end
                if isLast then
                    seg.segRight:Hide()
                else
                    seg.segRight:Show()
                end

                -- Background: disabled = 50% opacity, hover = lighten by 4%, normal = PILL_BGA
                if disabled then
                    seg.segBg:SetColorTexture(PILL_BG[1], PILL_BG[2], PILL_BG[3], 0.50)
                    seg.accentBg:Hide()
                elseif isHover then
                    local hr, hg, hb =
                        PILL_BG[1] + BG_HOVER_BOOST, PILL_BG[2] + BG_HOVER_BOOST, PILL_BG[3] + BG_HOVER_BOOST
                    seg.segBg:SetColorTexture(hr, hg, hb, PILL_BGA)
                    if checked then
                        seg.accentBg:SetColorTexture(ACCENT.r, ACCENT.g, ACCENT.b, 0.05)
                        seg.accentBg:Show()
                    else
                        seg.accentBg:Hide()
                    end
                else
                    seg.segBg:SetColorTexture(PILL_BG[1], PILL_BG[2], PILL_BG[3], PILL_BGA)
                    if checked then
                        seg.accentBg:SetColorTexture(ACCENT.r, ACCENT.g, ACCENT.b, 0.05)
                        seg.accentBg:Show()
                    else
                        seg.accentBg:Hide()
                    end
                end
            end

            -- Cap borders & fills: match adjacent segment's state (checked/disabled/hover)
            local firstKey = rowConf.keys[1]
            local lastKey = rowConf.keys[numKeys]
            local firstDisabled = rowConf.isDisabled and rowConf.isDisabled(firstKey)
            local lastDisabled = rowConf.isDisabled and rowConf.isDisabled(lastKey)
            local firstChecked = rowConf.getChecked(firstKey) and not firstDisabled
            local lastChecked = rowConf.getChecked(lastKey) and not lastDisabled
            local firstHover = (hoverIdx == 1) and not firstDisabled
            local lastHover = (hoverIdx == numKeys) and not lastDisabled

            local lbr, lbg2, lbb, lba = INACTIVE_R, INACTIVE_G, INACTIVE_B, INACTIVE_A
            if firstDisabled then
                lba = 0.10
            elseif firstChecked then
                lbr, lbg2, lbb, lba = ACTIVE_R, ACTIVE_G, ACTIVE_B, 1.0
            end
            capLeftBdr:SetVertexColor(lbr, lbg2, lbb, lba)

            local rbr, rbg2, rbb, rba = INACTIVE_R, INACTIVE_G, INACTIVE_B, INACTIVE_A
            if lastDisabled then
                rba = 0.10
            elseif lastChecked then
                rbr, rbg2, rbb, rba = ACTIVE_R, ACTIVE_G, ACTIVE_B, 1.0
            end
            capRightBdr:SetVertexColor(rbr, rbg2, rbb, rba)

            -- Cap fills: disabled = 50% opacity, hover = lighten by 4%, normal = PILL_BGA
            local lfr, lfg, lfb, lfa = PILL_BG[1], PILL_BG[2], PILL_BG[3], PILL_BGA
            if firstDisabled then
                lfa = 0.50
            elseif firstHover then
                lfr, lfg, lfb = lfr + BG_HOVER_BOOST, lfg + BG_HOVER_BOOST, lfb + BG_HOVER_BOOST
            end
            capLeftFill:SetVertexColor(lfr, lfg, lfb, lfa)

            local rfr, rfg, rfb, rfa = PILL_BG[1], PILL_BG[2], PILL_BG[3], PILL_BGA
            if lastDisabled then
                rfa = 0.50
            elseif lastHover then
                rfr, rfg, rfb = rfr + BG_HOVER_BOOST, rfg + BG_HOVER_BOOST, rfb + BG_HOVER_BOOST
            end
            capRightFill:SetVertexColor(rfr, rfg, rfb, rfa)

            -- Cap accent overlays: show 5% accent tint when checked (matches segment accentBg)
            if firstChecked then
                capLeftAccent:SetVertexColor(ACCENT.r, ACCENT.g, ACCENT.b, 0.05)
                capLeftAccent:Show()
            else
                capLeftAccent:Hide()
            end
            if lastChecked then
                capRightAccent:SetVertexColor(ACCENT.r, ACCENT.g, ACCENT.b, 0.05)
                capRightAccent:Show()
            else
                capRightAccent:Hide()
            end
        end

        -- Square mode: the box outline and fill dim only when every segment is
        -- disabled; the checked segment shows its marker and a 5% accent tint,
        -- a hovered one lightens by 4%, both as rounded fills inside the box.
        local function RefreshBox()
            local hoverIdx = widget._hoverIdx
            local allDisabled = true
            for position, seg in ipairs(segments) do
                local disabled = rowConf.isDisabled and rowConf.isDisabled(seg.key)
                local checked = rowConf.getChecked(seg.key)
                local boost = (hoverIdx == position) and BG_HOVER_BOOST or 0
                if disabled then
                    seg.lbl:SetTextColor(1, 1, 1, 0.20)
                elseif checked then
                    seg.lbl:SetTextColor(ACTIVE_R, ACTIVE_G, ACTIVE_B, 1.0)
                else
                    seg.lbl:SetTextColor(1, 1, 1, 0.60)
                end
                if disabled then
                    seg.marker:SetColor(ACTIVE_R, ACTIVE_G, ACTIVE_B, 0)
                    seg.segBg:SetColorTexture(0, 0, 0, 0)
                elseif checked then
                    allDisabled = false
                    seg.marker:SetColor(ACTIVE_R, ACTIVE_G, ACTIVE_B, 1.0)
                    seg.segBg:SetColorTexture(
                        PILL_BG[1] * 0.95 + ACTIVE_R * 0.05 + boost,
                        PILL_BG[2] * 0.95 + ACTIVE_G * 0.05 + boost,
                        PILL_BG[3] * 0.95 + ACTIVE_B * 0.05 + boost,
                        PILL_BGA
                    )
                else
                    allDisabled = false
                    seg.marker:SetColor(ACTIVE_R, ACTIVE_G, ACTIVE_B, 0)
                    seg.segBg:SetColorTexture(
                        PILL_BG[1] + boost,
                        PILL_BG[2] + boost,
                        PILL_BG[3] + boost,
                        boost > 0 and PILL_BGA or 0
                    )
                end
            end
            boxBdr:SetColor(INACTIVE_R, INACTIVE_G, INACTIVE_B, allDisabled and 0.10 or INACTIVE_A)
            backdrop:SetColorTexture(PILL_BG[1], PILL_BG[2], PILL_BG[3], allDisabled and 0.50 or PILL_BGA)
        end
        if SQUARE then
            RefreshAll = RefreshBox
        end

        widget._refreshAll = RefreshAll
        RefreshAll()

        -- Pill sits at 90% opacity permanently
        widget:SetAlpha(0.9)
        return widget, SEG_H, RefreshAll, btnByKey
    end

    CUI.BuildSegmentedControl = BuildSegmentedControl
end -- end deferred init
