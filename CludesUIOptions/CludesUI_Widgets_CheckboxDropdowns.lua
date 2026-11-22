if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUI_Widgets_CheckboxDropdowns.lua
--  Checkbox dropdowns shared by the options pages: the empty-filter
--  warning, BuildVisOptsCBDropdown and its drag-reorder variant, and the
--  slider dropdown (BuildSliderDropdown). Loads right after
--  CludesUI_Widgets.lua.
-------------------------------------------------------------------------------
local CUI = _G.CludesUI

-- The options page pool (CludesUI_FramePool.lua, the options addon's first
-- file): a frame made below on a pool host is handed out again, reset to new,
-- when that host is built again, and each lazy menu is kept per dropdown
-- button. Captured once here, never read through the public slot later.
local Pool = CUI._Pool
local CreateFrame, PoolKept, PoolGen = Pool.CreateFrame, Pool.Kept, Pool.Gen

-- Global search prebuild: the stand-in a builder below returns in place of a
-- control on an absorber row (PrebuildStandIn, CludesUI_Widgets.lua). Nil
-- outside the pass and for a real parent.
local function StandIn(hostFrame)
    if not CUI._prebuilding then return nil end
    return CUI._widgetInternals.PrebuildStandIn(hostFrame)
end

-- Empty-selection warning for a filter dropdown whose selection is allowed
-- to reach "shows nothing" (PAB buff/debuff Filters, RF Debuff Manager base
-- Filters): while hasContentFn() is false, the dropdown carries a red border
-- and a persistent bubble above it (warnText), and the returned closure --
-- meant as the dropdown's onMenuClosed -- pulses the control red twice when
-- the menu closes on an empty selection. hasContentFn must be the surface's
-- REAL render predicate (broad mode / Show lane / extra spells / enchants /
-- fx-forced or claimed categories): anything that still renders must count,
-- so a surface that displays something never warns. Update registers as a
-- widget refresh, so every lane click that triggers a non-force RefreshPage
-- re-evaluates live. A long warnText wraps at WARN_WRAP px. opts.onDismiss:
-- advice the reader may wave off for good (the Kick Tracker's marker
-- warning): a button in the bubble's own dress sits beside it, the
-- pair centred over the control, and a click runs it and re-reads; the
-- caller's hasContentFn honours the flag it keeps.
local WARN_WRAP = 300 -- px of text a warning bubble holds on one line
local WARN_GAP = 4 -- px between the bubble and its dismiss button
local DISMISS_MAX = 22 -- px the dismiss button grows to beside a wrapped bubble

local function WarnDress(widget)
    local backdrop = widget:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    backdrop:SetColorTexture(0.12, 0.03, 0.03, 0.95)
    CUI.MakeRoundedBorder(widget, 0.85, 0.2, 0.2, 1, backdrop)
end

function CUI.AttachEmptyFilterWarn(region, checkDrop, warnText, hasContentFn, options)
    -- Search prebuild on an absorber row: the warning indexes nothing, so none is built.
    local standIn = StandIn(region) or StandIn(checkDrop)
    if standIn then return standIn end
    local Pix = CUI.PanelPP
    local onDismiss = options and options.onDismiss
    local Update

    local bubble = CreateFrame("Frame", nil, region)
    bubble:SetFrameLevel(checkDrop:GetFrameLevel() + 10)
    local fontStr = CUI.MakeFont(bubble, 12, nil, 1, 0.4, 0.4)
    fontStr:SetText(warnText)
    fontStr:SetPoint("CENTER")
    local tw = math.ceil(fontStr:GetStringWidth())
    if tw > WARN_WRAP then
        tw = WARN_WRAP
        fontStr:SetWidth(tw)
        fontStr:SetWordWrap(true)
        fontStr:SetJustifyH("CENTER")
    end
    local bw, bh = tw + 16, math.ceil(fontStr:GetStringHeight()) + 10
    Pix.Size(bubble, bw, bh)
    WarnDress(bubble)
    if onDismiss then
        local sz = math.min(bh, DISMISS_MAX)
        local cross = CreateFrame("Button", nil, bubble)
        Pix.Size(cross, sz, sz)
        cross:SetPoint("LEFT", bubble, "RIGHT", WARN_GAP, 0)
        cross:SetFrameLevel(bubble:GetFrameLevel())
        WarnDress(cross)
        local highlight = cross:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(0.85, 0.2, 0.2, 0.25)
        CUI.RoundBody(cross, highlight)
        local xfs = CUI.MakeFont(cross, 12, nil, 1, 0.4, 0.4)
        xfs:SetPoint("CENTER", cross, "CENTER", 0, 1)
        xfs:SetText("x")
        cross:SetScript("OnEnter", function()
            xfs:SetTextColor(1, 0.75, 0.75)
            CUI.ShowWidgetTooltip(cross, CUI.L("Dismiss this warning"))
        end)
        cross:SetScript("OnLeave", function()
            xfs:SetTextColor(1, 0.4, 0.4)
            CUI.HideWidgetTooltip()
        end)
        cross:SetScript("OnClick", function()
            onDismiss()
            Update()
        end)
        bubble:SetPoint("BOTTOM", checkDrop, "TOP", -(sz + WARN_GAP) / 2, 5)
    else
        bubble:SetPoint("BOTTOM", checkDrop, "TOP", 0, 5)
    end
    bubble:Hide()

    local warnBorder = CreateFrame("Frame", nil, checkDrop)
    warnBorder:SetAllPoints(checkDrop)
    CUI.MakeRoundedBorder(warnBorder, 0.85, 0.2, 0.2, 1)
    warnBorder:Hide()

    local flash = checkDrop:CreateTexture(nil, "OVERLAY", nil, 7)
    flash:SetAllPoints()
    flash:SetColorTexture(0.9, 0.15, 0.15, 0.45)
    CUI.RoundBody(checkDrop, flash)
    flash:SetAlpha(0)
    local anim = flash:CreateAnimationGroup()
    local a1 = anim:CreateAnimation("Alpha")
    a1:SetFromAlpha(0)
    a1:SetToAlpha(1)
    a1:SetDuration(0.10)
    a1:SetOrder(1)
    local a2 = anim:CreateAnimation("Alpha")
    a2:SetFromAlpha(1)
    a2:SetToAlpha(0)
    a2:SetDuration(0.45)
    a2:SetOrder(2)
    -- Two pulses read as a deliberate alert; one reads as a rendering glitch.
    anim:SetLooping("REPEAT")
    local loops = 0
    anim:SetScript("OnPlay", function() loops = 0 end)
    anim:SetScript("OnLoop", function(self)
        loops = loops + 1
        if loops >= 2 then self:Stop() end
    end)

    Update = function()
        local empty = not hasContentFn()
        bubble:SetShown(empty)
        warnBorder:SetShown(empty)
        if not empty and anim:IsPlaying() then anim:Stop() end
    end
    Update()
    CUI.RegisterWidgetRefresh(Update)
    return function()
        Update()
        if not hasContentFn() then anim:Restart() end
    end
end

-------------------------------------------------------------------------------
--  Shared Visibility Options Checkbox Dropdown
--  Reusable across CDM, Action Bars, Resource Bars, Unit Frames.
--  items = CludesUI.VIS_OPT_ITEMS (or a subset)
--  getFn(key) -> bool, setFn(key, bool)
--  onMenuClosed (optional) fires once each time the open menu hides --
--  callers that defer page rebuilds while the menu is open flush there.
--  opts.dimLocked: locked rows dim their checkbox too, not only the label.
--  opts.noAllLabel: the summary names every checked row even when all are
--  checked (a selection, not a filter: never "All").
--  opts.countLabel: a partly checked list reads "3 of 5" instead of naming its
--  checked rows (a long list of names, such as characters); "All" and the
--  empty label stay.
--  opts.disabled (fn) + disabledTooltip/rawTooltip/requireState (as
--  ResolveDisabledTip): greyed and click-blocked while it answers true, the
--  reason on hover, re-checked with the page's widgets.
--  Returns: ddBtn, refreshFn. refreshFn(true) also reads a dynamic items list
--  again while the menu is closed, for a change made outside the menu.
-------------------------------------------------------------------------------
function CUI.BuildVisOptsCBDropdown(
    parentFrame,
    ddW,
    fLevel,
    itemList,
    getFn,
    setFn,
    onChanged,
    maxVisibleItems,
    searchable,
    closeButton,
    onMenuClosed,
    options
)
    -- Search prebuild on an absorber row: the dropdown indexes nothing, so none is built.
    local standIn = StandIn(parentFrame)
    if standIn then return standIn, standIn end
    local Pix = CUI.PanelPP
    options = options or {}
    -- Opt-in dynamic items: pass a FUNCTION returning the items array and it re-evaluates on every menu OPEN (the menu rebuilds), so lists that depend on other settings never go stale. A table stays static.
    local itemsFn
    if type(itemList) == "function" then
        itemsFn = itemList
        itemList = itemsFn() or {}
    end
    local dropdownBtn = CreateFrame("Button", nil, parentFrame)
    -- This build's dress of the button: once a page pass hands the button out
    -- again (the options page pool), the new build owns it and this build's
    -- painters leave it alone (a setter's own rebuild, a kept refresher).
    local dressGen = PoolGen(dropdownBtn)
    Pix.Size(dropdownBtn, ddW, 30)
    dropdownBtn:SetFrameLevel(fLevel)
    local ddBg = dropdownBtn:CreateTexture(nil, "BACKGROUND")
    ddBg:SetAllPoints()
    ddBg:SetColorTexture(CUI.DD_BG_R, CUI.DD_BG_G, CUI.DD_BG_B, CUI.DD_BG_A)
    local ddBrd = CUI.MakeRoundedBorder(dropdownBtn, 1, 1, 1, CUI.DD_BRD_A, ddBg)
    local dropCaption = dropdownBtn:CreateFontString(nil, "OVERLAY")
    -- Options panel is Expressway-locked by design (locale-aware: CJK/Cyrillic get the system glyph font). The user's global font intentionally does not restyle the settings UI.
    local fontFile = CUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF"
    dropCaption:SetFont(fontFile, 13, "")
    dropCaption:SetTextColor(1, 1, 1, CUI.DD_TXT_A)
    dropCaption:SetJustifyH("LEFT")
    dropCaption:SetWordWrap(false)
    dropCaption:SetMaxLines(1)
    dropCaption:SetPoint("LEFT", dropdownBtn, "LEFT", 12, 0)
    local arrow = CUI.MakeDropdownArrow(dropdownBtn, 12, Pix)
    dropCaption:SetPoint("RIGHT", arrow, "LEFT", -5, 0)

    local dropMenu
    local function SummaryLabel()
        local nameList = {}
        local sum = 0
        local hiddenCount = 0
        -- A LIVE override replaces the whole setting, whether it is being edited or just
        -- applied, so the summary is what it holds and nothing else. Mixing it with the
        -- rows below reads as one selection that exists nowhere ("Always or Solo"), and
        -- it is also the only place that still tells the truth while the rows underneath
        -- show the shared value they edit.
        local held = options.ovHeldFn and options.ovHeldFn()
        if held then
            for _, entry in ipairs(itemList) do
                if entry.key == held then return CUI.L(entry.label) end
            end
        end
        for _, entry in ipairs(itemList) do
            -- isModifier rows (the Visibility match toggle) are not conditions: excluded
            -- from the summary and from the "All" shortcut. item.excludeFromSummaryFn
            -- opts a row out the same way (e.g. locked behind an unlearned talent).
            if
                not entry.isHeader
                and not entry.isTopAction
                and not entry.isModifier
                and not (entry.excludeFromSummaryFn and entry.excludeFromSummaryFn())
            then
                sum = sum + 1
                if getFn(entry.key) then nameList[#nameList + 1] = CUI.L(entry.label) end
                -- Dual-lane rows: the hide lane reads through getFn(key, true).
                if entry.dual and getFn(entry.key, true) then hiddenCount = hiddenCount + 1 end
            end
        end
        local base
        -- opts.emptyLabel: the unified Visibility row reads "Always" with no show lane
        -- checked (an unconstrained element still shows), never "None".
        -- opts.separatorFn lets a modifier row rename the join, so the summary reads
        -- the way the conditions actually combine.
        local sep = options.separatorFn and options.separatorFn() or ", "
        if #nameList == 0 then
            base = options.emptyLabel and CUI.L(options.emptyLabel) or CUI.L("None")
        elseif #nameList == sum and not options.noAllLabel then
            base = CUI.L("All")
        elseif options.countLabel then
            base = CUI.Lf("%1$d of %2$d", #nameList, sum)
        else
            base = table.concat(nameList, sep)
        end
        if hiddenCount > 0 then base = base .. " (-" .. hiddenCount .. ")" end
        return base
    end
    local function SyncCaption()
        if PoolGen(dropdownBtn) ~= dressGen then return end
        dropCaption:SetText(SummaryLabel())
    end
    SyncCaption()

    -- The menu and its fixed parts are built on the first open. A dynamic list
    -- (itemsFn) marks it stale on every open, and EnsureMenu then lays the same
    -- menu out again for the new items: rows come from per-kind pools (AcquireRow),
    -- and the ones a layout leaves unused are hidden.
    local menuStale
    local ITEM_HEIGHT = 28
    local HDR_H = 22
    -- _allRows: { frame, isHeader, label(string), height } per laid-out row.
    -- Top-action locked tints refresh in the same sweeps as _allRows. They can't JOIN _allRows: the search relayout repositions every frame in that list, and top actions live above the search box.
    local _allRows, _taTints = {}, {}
    local sf, childFrame, searchEdit, searchPlaceholder, taDivider, closeBtn, seal
    local UpdateCBThumb
    local rowPools = {}
    local function AcquireRow(kind, make, arg)
        local pool = rowPools[kind]
        if not pool then
            pool = { used = 0 }
            rowPools[kind] = pool
        end
        pool.used = pool.used + 1
        local row = pool[pool.used]
        if not row then
            row = make(arg)
            pool[pool.used] = row
        end
        row:Show()
        return row
    end
    -- Label row: a top action (parent: the menu) or an action item (the scroll child).
    local function MakeTextRow(hostFrame)
        local row = CreateFrame("Button", nil, hostFrame)
        row:SetHeight(ITEM_HEIGHT)
        local labelFS = row:CreateFontString(nil, "OVERLAY")
        labelFS:SetFont(fontFile, 13, "")
        labelFS:SetPoint("LEFT", row, "LEFT", 10, 0)
        labelFS:SetPoint("RIGHT", row, "RIGHT", -10, 0)
        labelFS:SetJustifyH("LEFT")
        labelFS:SetWordWrap(false)
        labelFS:SetMaxLines(1)
        local highlight = row:CreateTexture(nil, "ARTWORK")
        highlight:SetAllPoints()
        row._lbl, row._hl = labelFS, highlight
        return row
    end
    local function MakeHeaderRow()
        local heading = CreateFrame("Frame", nil, childFrame)
        heading:SetHeight(HDR_H)
        local hdrLbl = heading:CreateFontString(nil, "OVERLAY")
        hdrLbl:SetFont(fontFile, 10, "")
        hdrLbl:SetTextColor(0.5, 0.5, 0.5, 1)
        hdrLbl:SetPoint("LEFT", heading, "LEFT", 10, 0)
        hdrLbl:SetJustifyH("LEFT")
        local hdrLine = heading:CreateTexture(nil, "ARTWORK")
        hdrLine:SetHeight(1)
        hdrLine:SetPoint("LEFT", hdrLbl, "RIGHT", 6, 0)
        hdrLine:SetColorTexture(0.3, 0.3, 0.3, 0.5)
        heading._lbl, heading._line = hdrLbl, hdrLine
        return heading
    end
    -- Checkbox row with the parts its item's shape needs (check box, icon, hide
    -- lane, swatch); the pool key carries that shape, so a reused row has them.
    local function MakeCheckRow(entry)
        local row = CreateFrame("Button", nil, childFrame)
        row:SetHeight(ITEM_HEIGHT)
        row:SetFrameLevel(dropMenu:GetFrameLevel() + 2)
        if not entry.noCheck then
            local boxFrame = CreateFrame("Frame", nil, row)
            boxFrame:SetSize(16, 16)
            boxFrame:SetPoint("LEFT", row, "LEFT", 10, 0)
            local boxBg = boxFrame:CreateTexture(nil, "BACKGROUND")
            boxBg:SetAllPoints()
            boxBg:SetColorTexture(0.114, 0.106, 0.099, 1)
            row._boxBrd = CUI.MakeRoundedBorder(boxFrame, 0.4, 0.4, 0.4, 0.6, boxBg)
            local chk = boxFrame:CreateTexture(nil, "ARTWORK")
            Pix.SetInside(chk, boxFrame, 2, 2)
            chk:SetSnapToPixelGrid(false)
            CUI.RoundBody(boxFrame, chk, 2)
            row._box, row._chk = boxFrame, chk
        end
        -- Optional icon (spell icon etc.) between checkbox and label
        local lblAnchor = row._box
        if entry.icon then
            local ico = row:CreateTexture(nil, "ARTWORK")
            if row._box then
                ico:SetPoint("LEFT", row._box, "RIGHT", 6, 0)
            else
                ico:SetPoint("LEFT", row, "LEFT", 10, 0)
            end
            ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            row._ico = ico
            lblAnchor = ico
        end
        local labelFS = row:CreateFontString(nil, "OVERLAY")
        labelFS:SetFont(fontFile, 13, "")
        if lblAnchor then
            labelFS:SetPoint("LEFT", lblAnchor, "RIGHT", entry.icon and 6 or 8, 0)
        else
            labelFS:SetPoint("LEFT", row, "LEFT", 10, 0)
        end
        labelFS:SetPoint("RIGHT", row, "RIGHT", (entry.dual and not entry.noCheck) and -32 or -10, 0)
        labelFS:SetJustifyH("LEFT")
        labelFS:SetWordWrap(false)
        labelFS:SetMaxLines(1)
        local highlight = row:CreateTexture(nil, "ARTWORK")
        highlight:SetAllPoints()
        row._lbl, row._hl = labelFS, highlight
        if entry.dual and not entry.noCheck then
            local negBox = CreateFrame("Button", nil, row)
            negBox:SetSize(16, 16)
            negBox:SetPoint("RIGHT", row, "RIGHT", -10, 0)
            negBox:SetFrameLevel(row:GetFrameLevel() + 1)
            local negBg = negBox:CreateTexture(nil, "BACKGROUND")
            negBg:SetAllPoints()
            negBg:SetColorTexture(0.114, 0.106, 0.099, 1)
            row._negBrd = CUI.MakeRoundedBorder(negBox, 0.4, 0.4, 0.4, 0.6, negBg)
            local negChk = negBox:CreateTexture(nil, "ARTWORK")
            Pix.SetInside(negChk, negBox, 2, 2)
            negChk:SetColorTexture(0.85, 0.3, 0.3, 1)
            negChk:SetSnapToPixelGrid(false)
            CUI.RoundBody(negBox, negChk, 2)
            row._negBox, row._negChk = negBox, negChk
        end
        if entry.swatch then
            -- The swatch reads and writes the swatch spec of the item the row shows (row._swSpec).
            row._swSpec = entry.swatch
            local sw, swUpdate = CUI.BuildColorSwatch(
                row,
                row:GetFrameLevel() + 1,
                function() return row._swSpec.get() end,
                function(...) row._swSpec.set(...) end,
                entry.swatch.hasAlpha,
                16
            )
            sw:ClearAllPoints()
            sw:SetPoint("RIGHT", row, "RIGHT", row._negBox and -32 or -10, 0)
            labelFS:SetPoint("RIGHT", sw, "LEFT", -6, 0)
            local swBlock = CreateFrame("Frame", nil, sw)
            swBlock:SetAllPoints()
            swBlock:SetFrameLevel(sw:GetFrameLevel() + 10)
            swBlock:EnableMouse(true)
            swBlock:SetScript("OnEnter", function()
                local tipText = CUI.ResolveDisabledTip(row._swSpec)
                if tipText then CUI.ShowWidgetTooltip(sw, tipText) end
            end)
            swBlock:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
            swBlock:Hide()
            row._sw, row._swUpdate, row._swBlock = sw, swUpdate, swBlock
        end
        return row
    end

    local function BuildMenuOnce()
        if dropMenu and not menuStale then return end
        menuStale = nil
        local firstBuild = not dropMenu
        -- Opt-in top-action rows (item.isTopAction with label + onClick): accent clickable entries pinned ABOVE the search box with a divider under the group -- the "Custom Spell ID at the top" pattern from the CDM spell pickers. Excluded from the scroll list, the checkable count, and the summary label.
        local topActions = {}
        wipe(_taTints)
        for _, entry in ipairs(itemList) do
            if entry.isTopAction then topActions[#topActions + 1] = entry end
        end
        local TOP_H = (#topActions > 0) and (#topActions * ITEM_HEIGHT + 7) or 0
        local checkableCount = 0
        local contentH = 8
        for _, entry in ipairs(itemList) do
            if entry.isTopAction then -- rendered above the search box
            elseif entry.isHeader then
                contentH = contentH + HDR_H
            else
                contentH = contentH + ITEM_HEIGHT
                checkableCount = checkableCount + 1
            end
        end
        local SEARCH_H = searchable and 26 or 0
        -- The box plus its 4-unit gap: the menu reserves exactly what the scroll area skips.
        local SEARCH_PAD = searchable and (SEARCH_H + 4) or 0
        local CLOSE_BTN_H = closeButton and (6 + 26 + 6) or 0
        contentH = contentH + CLOSE_BTN_H
        local needsScroll = maxVisibleItems and checkableCount > maxVisibleItems
        -- +2 accounts for scroll frame 1px top + 1px bottom insets so non-scrolling menus don't scroll
        local menuH = (
            needsScroll and (4 + maxVisibleItems * ITEM_HEIGHT + 4 + CLOSE_BTN_H) or (contentH + 4)
        )
            + SEARCH_PAD
            + TOP_H
        if firstBuild then
            -- One menu per dropdown button for the session: a build that dresses
            -- the button again gets this frame back here, reset to new.
            dropMenu = PoolKept(dropdownBtn, "cbMenu", "Frame", CUI.OverlayParent())
        end
        dropMenu:SetFrameStrata("FULLSCREEN_DIALOG")
        dropMenu:SetFrameLevel(200)
        dropMenu:SetClampedToScreen(true)
        dropMenu:EnableMouse(true)
        dropMenu:SetSize(ddW, menuH)
        dropMenu:ClearAllPoints()
        dropMenu:SetPoint("TOPLEFT", dropdownBtn, "BOTTOMLEFT", 0, -2)
        dropMenu:Hide()
        if firstBuild then
            -- Controller cursor: the list blocks what is under it but is not a stop itself;
            -- Cancel clicks the dropdown button (it toggles the list closed).
            if CUI.PadCP() then
                CUI.PadHint(dropMenu, "nodepass")
                dropMenu.CloseButton = dropdownBtn
            end
            local mBg = dropMenu:CreateTexture(nil, "BACKGROUND")
            mBg:SetAllPoints()
            mBg:SetColorTexture(CUI.DD_BG_R, CUI.DD_BG_G, CUI.DD_BG_B, CUI.DD_BG_HA)
            CUI.MakeRoundedBorder(dropMenu, 1, 1, 1, CUI.DD_BRD_A, mBg, nil, true)
        end
        local ppScale = CUI.GetPopupScale() or 1
        dropMenu:SetScale(ppScale)
        for _, pool in pairs(rowPools) do
            pool.used = 0
        end

        -- Top-action rows above the search box, divider under the group.
        if #topActions > 0 then
            local ay = -4
            for idx = 1, #topActions do
                local entry = topActions[idx]
                local row = AcquireRow("ta", MakeTextRow, dropMenu)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", dropMenu, "TOPLEFT", 1, ay)
                row:SetPoint("TOPRIGHT", dropMenu, "TOPRIGHT", -1, ay)
                row:SetFrameLevel(dropMenu:GetFrameLevel() + 2)
                local labelFS, highlight = row._lbl, row._hl
                labelFS:SetTextColor(CUI.CLUDES_GREEN.r, CUI.CLUDES_GREEN.g, CUI.CLUDES_GREEN.b, 0.8)
                labelFS:SetText(CUI.L(entry.label))
                highlight:SetColorTexture(1, 1, 1, 0)
                -- Opt-in locked state (item.lockedFn + item.lockedTooltip): evaluated LIVE on hover/click (checkbox toggles can flip it while the menu is open), plus once at build for the initial tint.
                local function TALocked() return entry.lockedFn and entry.lockedFn() or false end
                local function PaintApplyAll()
                    if TALocked() then
                        labelFS:SetTextColor(1, 1, 1, 0.3)
                    else
                        labelFS:SetTextColor(CUI.CLUDES_GREEN.r, CUI.CLUDES_GREEN.g, CUI.CLUDES_GREEN.b, 0.8)
                    end
                end
                PaintApplyAll()
                _taTints[#_taTints + 1] = PaintApplyAll
                row:SetScript("OnEnter", function()
                    PaintApplyAll()
                    if TALocked() then
                        local tipText = entry.lockedTooltip
                        if tipText and CUI.ShowWidgetTooltip then
                            CUI.ShowWidgetTooltip(row, type(tipText) == "function" and tipText() or tipText)
                        end
                        return
                    end
                    highlight:SetColorTexture(1, 1, 1, 0.06)
                end)
                row:SetScript("OnLeave", function()
                    highlight:SetColorTexture(1, 1, 1, 0)
                    CUI.HideWidgetTooltip()
                    PaintApplyAll()
                end)
                row:SetScript("OnClick", function()
                    if TALocked() then return end
                    dropMenu:Hide()
                    if entry.onClick then entry.onClick() end
                end)
                ay = ay - ITEM_HEIGHT
            end
            if not taDivider then
                taDivider = dropMenu:CreateTexture(nil, "ARTWORK")
                taDivider:SetHeight(1)
                taDivider:SetColorTexture(0.3, 0.3, 0.3, 0.5)
            end
            taDivider:ClearAllPoints()
            taDivider:SetPoint("TOPLEFT", dropMenu, "TOPLEFT", 10, ay - 3)
            taDivider:SetPoint("TOPRIGHT", dropMenu, "TOPRIGHT", -10, ay - 3)
            taDivider:Show()
        elseif taDivider then
            taDivider:Hide()
        end

        -- Search box (optional)
        if searchable then
            if not searchEdit then
                searchEdit = CreateFrame("EditBox", nil, dropMenu)
                searchEdit:SetFont(fontFile, 11, "")
                searchEdit:SetTextColor(1, 1, 1, 0.9)
                searchEdit:SetJustifyH("LEFT")
                searchEdit:SetAutoFocus(false)
                searchEdit:SetMaxLetters(30)
                -- Text at the check boxes' x (the scroll area sits 1 unit in, boxes 10 into a row).
                searchEdit:SetTextInsets(10, 10, 0, 0)
                local sDiv = searchEdit:CreateTexture(nil, "ARTWORK")
                sDiv:SetHeight(1)
                -- This list's own divider style (the top actions' divider above).
                sDiv:SetPoint("BOTTOMLEFT", searchEdit, "BOTTOMLEFT", 9, 0)
                sDiv:SetPoint("BOTTOMRIGHT", searchEdit, "BOTTOMRIGHT", -9, 0)
                sDiv:SetColorTexture(0.3, 0.3, 0.3, 0.5)
                searchPlaceholder = searchEdit:CreateFontString(nil, "OVERLAY")
                searchPlaceholder:SetFont(fontFile, 11, "")
                searchPlaceholder:SetTextColor(0.5, 0.5, 0.5, 0.6)
                searchPlaceholder:SetPoint("LEFT", searchEdit, "LEFT", 10, 0)
                searchPlaceholder:SetText(CUI.L("Search..."))
                searchEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
            end
            -- The list's flush first row: inside the border (below the top
            -- actions), its last unit the divider, the scroll area right below.
            searchEdit:ClearAllPoints()
            searchEdit:SetPoint("TOPLEFT", dropMenu, "TOPLEFT", 1, -1 - TOP_H)
            searchEdit:SetPoint("TOPRIGHT", dropMenu, "TOPRIGHT", -1, -1 - TOP_H)
            searchEdit:SetHeight(SEARCH_PAD - 1)
            searchEdit:SetFrameLevel(dropMenu:GetFrameLevel() + 3)
        end

        -- Scroll frame for items
        if not sf then
            sf = CreateFrame("ScrollFrame", nil, dropMenu)
            sf:EnableMouseWheel(true)
            childFrame = CreateFrame("Frame", nil, sf)
            childFrame:SetWidth(ddW - 2)
            sf:SetScrollChild(childFrame)
            -- Thin scrollbar track (4px, right side, matching standard dropdown)
            local cbTrack = CreateFrame("Frame", nil, sf)
            cbTrack:SetWidth(4)
            cbTrack:SetPoint("TOPRIGHT", sf, "TOPRIGHT", -4, -4)
            cbTrack:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", -4, 4)
            cbTrack:SetFrameLevel(sf:GetFrameLevel() + 2)
            local cbTrackBg = cbTrack:CreateTexture(nil, "BACKGROUND")
            cbTrackBg:SetAllPoints()
            cbTrackBg:SetColorTexture(1, 1, 1, 0.02)

            local cbThumb = CreateFrame("Button", nil, cbTrack)
            cbThumb:SetWidth(4)
            cbThumb:SetFrameLevel(cbTrack:GetFrameLevel() + 1)
            cbThumb:EnableMouse(true)
            cbThumb:RegisterForDrag("LeftButton")
            local cbThumbBg = cbThumb:CreateTexture(nil, "ARTWORK")
            cbThumbBg:SetAllPoints()
            cbThumbBg:SetColorTexture(1, 1, 1, 0.27)
            -- Controller cursor: it scrolls the list to the row itself; the pointer-drag thumb is no stop.
            CUI.PadHint(cbThumb, "nodeignore")

            local function SafeMaxScroll() return math.max(0, childFrame:GetHeight() - sf:GetHeight()) end

            UpdateCBThumb = function()
                local maxScroll = SafeMaxScroll()
                if maxScroll <= 0 then
                    cbTrack:Hide()
                    return
                end
                cbTrack:Show()
                local trackH = cbTrack:GetHeight()
                local visH = sf:GetHeight()
                local ratio = visH / (visH + maxScroll)
                local thumbH = math.max(20, trackH * ratio)
                cbThumb:SetHeight(thumbH)
                local scrollRatio = (tonumber(sf:GetVerticalScroll()) or 0) / maxScroll
                local maxTravel = trackH - thumbH
                cbThumb:ClearAllPoints()
                cbThumb:SetPoint("TOP", cbTrack, "TOP", 0, -(scrollRatio * maxTravel))
            end

            -- Thumb drag
            cbThumb:SetScript("OnMouseDown", function(self, btnFrame)
                if btnFrame ~= "LeftButton" then return end
                local _, cursorY = GetCursorPosition()
                local dragStartY = cursorY / self:GetEffectiveScale()
                local dragStartScroll = sf:GetVerticalScroll()
                self:SetScript("OnUpdate", function(self2)
                    if not IsMouseButtonDown("LeftButton") then
                        self2:SetScript("OnUpdate", nil)
                        return
                    end
                    local _, curY = GetCursorPosition()
                    curY = curY / self2:GetEffectiveScale()
                    local deltaY = dragStartY - curY
                    local trackH = cbTrack:GetHeight()
                    local maxTravel = trackH - self2:GetHeight()
                    if maxTravel <= 0 then return end
                    local maxScroll = SafeMaxScroll()
                    local newScroll =
                        math.max(0, math.min(maxScroll, dragStartScroll + (deltaY / maxTravel) * maxScroll))
                    sf:SetVerticalScroll(newScroll)
                    UpdateCBThumb()
                end)
            end)
            cbThumb:SetScript("OnMouseUp", function(self, btnFrame)
                if btnFrame ~= "LeftButton" then return end
                self:SetScript("OnUpdate", nil)
            end)

            sf:SetScript("OnMouseWheel", function(self, delta)
                local maxScroll = SafeMaxScroll()
                if maxScroll <= 0 then return end
                local current = self:GetVerticalScroll()
                self:SetVerticalScroll(math.max(0, math.min(maxScroll, current - delta * ITEM_HEIGHT)))
                UpdateCBThumb()
            end)
        end
        local sfTop = -((SEARCH_PAD > 0 and SEARCH_PAD or 1) + TOP_H)
        sf:ClearAllPoints()
        sf:SetPoint("TOPLEFT", 1, sfTop)
        sf:SetPoint("BOTTOMRIGHT", -1, 1)
        childFrame:SetHeight(contentH)
        sf:SetVerticalScroll(0)

        local yOff = -4
        wipe(_allRows)
        -- Published for the refreshers below: the rows are parented to the SCROLL CHILD,
        -- so a menu:GetChildren() walk never reaches them.
        dropMenu._rows = _allRows
        for _, entry in ipairs(itemList) do
            -- Top-action items render above the search box, never here.
            if entry.isTopAction then -- luacheck: ignore (intentional empty)
            -- Header/divider items: non-interactive label
            elseif entry.isHeader then
                local hdrH = HDR_H
                local heading = AcquireRow("hdr", MakeHeaderRow)
                heading:ClearAllPoints()
                heading:SetPoint("TOPLEFT", childFrame, "TOPLEFT", 1, yOff)
                heading:SetPoint("TOPRIGHT", childFrame, "TOPRIGHT", -1, yOff)
                heading:SetFrameLevel(dropMenu:GetFrameLevel() + 2)
                local hdrLine = heading._line
                heading._lbl:SetText(CUI.L(entry.label))
                -- Opt-in right caption (item.rightLabel): labels the hide-lane column on dual menus.
                if entry.rightLabel then
                    local hdrR = heading._right
                    if not hdrR then
                        hdrR = heading:CreateFontString(nil, "OVERLAY")
                        hdrR:SetFont(fontFile, 10, "")
                        hdrR:SetTextColor(0.5, 0.5, 0.5, 1)
                        hdrR:SetPoint("RIGHT", heading, "RIGHT", -10, 0)
                        hdrR:SetJustifyH("RIGHT")
                        heading._right = hdrR
                    end
                    hdrR:SetText(CUI.L(entry.rightLabel))
                    hdrR:Show()
                    hdrLine:SetPoint("RIGHT", hdrR, "LEFT", -6, 0)
                else
                    if heading._right then heading._right:Hide() end
                    hdrLine:SetPoint("RIGHT", heading, "RIGHT", -10, 0)
                end
                if entry.tooltip then
                    heading:EnableMouse(true)
                    heading:SetScript("OnEnter", function() CUI.ShowWidgetTooltip(heading, entry.tooltip) end)
                    heading:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
                else
                    heading:SetScript("OnEnter", nil)
                    heading:SetScript("OnLeave", nil)
                    heading:EnableMouse(false)
                end
                _allRows[#_allRows + 1] =
                    { frame = heading, isHeader = true, label = entry.label, height = hdrH }
                yOff = yOff - hdrH
            elseif entry.isAction then
                -- Action item: clickable text, no checkbox (for "All Specs", "All Healers", etc.)
                local row = AcquireRow("act", MakeTextRow, childFrame)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", childFrame, "TOPLEFT", 1, yOff)
                row:SetPoint("TOPRIGHT", childFrame, "TOPRIGHT", -1, yOff)
                row:SetFrameLevel(dropMenu:GetFrameLevel() + 2)
                local labelFS, highlight = row._lbl, row._hl
                labelFS:SetTextColor(CUI.CLUDES_GREEN.r, CUI.CLUDES_GREEN.g, CUI.CLUDES_GREEN.b, 0.8)
                labelFS:SetText(CUI.L(entry.labelFn and entry.labelFn() or entry.label))
                local function UpdateActionLabel()
                    if entry.labelFn then labelFS:SetText(CUI.L(entry.labelFn())) end
                end
                row._updateActionLabel = UpdateActionLabel
                highlight:SetColorTexture(1, 1, 1, 0)
                local EG_r, EG_g, EG_b = CUI.CLUDES_GREEN.r, CUI.CLUDES_GREEN.g, CUI.CLUDES_GREEN.b
                local function SyncActionLocked()
                    local isLocked = entry.lockedFn and entry.lockedFn()
                    if isLocked then
                        labelFS:SetTextColor(0.4, 0.4, 0.4, 0.4)
                        row:EnableMouse(false)
                    else
                        labelFS:SetTextColor(EG_r, EG_g, EG_b, 0.8)
                        row:EnableMouse(true)
                    end
                end
                row._updateLocked = SyncActionLocked
                SyncActionLocked()
                row:SetScript("OnEnter", function()
                    labelFS:SetTextColor(1, 1, 1, 1)
                    highlight:SetColorTexture(1, 1, 1, 0.04)
                end)
                row:SetScript("OnLeave", function()
                    SyncActionLocked()
                    highlight:SetColorTexture(1, 1, 1, 0)
                end)
                row:SetScript("OnClick", function()
                    if entry.lockedFn and entry.lockedFn() then return end
                    setFn(entry.key, true)
                    -- Refresh all checkbox visuals + dynamic action labels
                    for _, r in ipairs(_allRows) do
                        if r.frame._updateCheck then r.frame._updateCheck() end
                        if r.frame._updateActionLabel then r.frame._updateActionLabel() end
                        if r.frame._updateLocked then r.frame._updateLocked() end
                    end
                    for idx = 1, #_taTints do
                        _taTints[idx]()
                    end
                    SyncCaption()
                end)
                _allRows[#_allRows + 1] = {
                    frame = row,
                    isHeader = false,
                    isAction = true,
                    label = entry.label,
                    height = ITEM_HEIGHT,
                }
                yOff = yOff - ITEM_HEIGHT
            else
                -- Opt-in plain rows (item.noCheck): the identical row minus the checkbox -- the regular-dropdown look for select-style pickers. Click still routes setFn(key, not getFn(key)), so a picker whose getFn is constant-false always selects with true.
                local shape = (entry.noCheck and "n" or "c")
                    .. (entry.icon and "i" or "")
                    .. ((entry.dual and not entry.noCheck) and "d" or "")
                    .. (entry.swatch and (entry.swatch.hasAlpha and "A" or "s") or "")
                local row = AcquireRow("chk" .. shape, MakeCheckRow, entry)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", childFrame, "TOPLEFT", 1, yOff)
                row:SetPoint("TOPRIGHT", childFrame, "TOPRIGHT", -1, yOff)
                row:SetFrameLevel(dropMenu:GetFrameLevel() + 2)
                row._isLocked = nil
                local boxFrame, boxBrd, chk = row._box, row._boxBrd, row._chk
                if chk then
                    chk:SetColorTexture(CUI.CLUDES_GREEN.r, CUI.CLUDES_GREEN.g, CUI.CLUDES_GREEN.b, 1)
                    boxFrame:SetScript("OnEnter", nil)
                    boxFrame:SetScript("OnLeave", nil)
                    boxFrame:EnableMouse(false)
                    boxFrame:SetAlpha(1)
                end
                -- Optional icon (spell icon etc.) between checkbox and label
                if row._ico then
                    local icoSz = entry.iconSize or (ITEM_HEIGHT - 6)
                    row._ico:SetSize(icoSz, icoSz)
                    row._ico:SetTexture(entry.icon)
                end
                -- Opt-in dimmed rows (item.dimFn): a pick that has no effect here right now
                -- (it shows somewhere else) rests dimmed but stays clickable, and hovering it
                -- shows item.dimTooltip (string or function) in place of item.tooltip.
                local function Dimmed() return (entry.dimFn and entry.dimFn()) and true or false end
                -- Modifier rows rest in the accent only while active; read live, since a
                -- sibling's click flips the checked state (UpdateCheck runs on every row).
                local function RestColor()
                    if entry.isModifier and getFn(entry.key) then
                        return CUI.CLUDES_GREEN.r, CUI.CLUDES_GREEN.g, CUI.CLUDES_GREEN.b
                    end
                    if Dimmed() then return 0.5, 0.5, 0.5 end
                    return 0.75, 0.75, 0.75
                end
                local labelFS, highlight = row._lbl, row._hl
                labelFS:SetTextColor(RestColor())
                labelFS:SetText(CUI.L(entry.label))
                highlight:SetColorTexture(1, 1, 1, 0)
                -- Opt-in dual-lane rows (item.dual): a second right-aligned box is the HIDE lane.
                -- Lane state reads getFn(key, true) and writes setFn(key, v, true); the show lane
                -- keeps the plain getFn(key)/setFn(key, v) contract, so single-lane callers are
                -- untouched. item.showLockedFn dims the show lane; while it is locked, row clicks
                -- fall through to the hide lane (broad "All" modes already show everything).
                local negBox, negBrd, negChk = row._negBox, row._negBrd, row._negChk
                -- Opt-in colour swatch (item.swatch = { get = fn -> r, g, b, a, set = fn(r, g, b, a),
                -- hasAlpha, disabled = fn, disabledTooltip (+ rawTooltip / requireState, as
                -- ResolveDisabledTip) }): its own button at the row's right edge, so a click
                -- opens the colour picker and never toggles the row. While disabled it dims
                -- and a blocker takes its clicks and explains the requirement.
                local sw, swUpdate, swBlock = row._sw, row._swUpdate, row._swBlock
                if sw then row._swSpec = entry.swatch end
                local function ShowLaneLocked() return entry.showLockedFn and entry.showLockedFn() or false end
                -- item.ovLockedFn is the override-session lock: it blocks the click like any
                -- other lock, but is painted and explained differently, because the row is not
                -- merely unavailable here -- it cannot be captured into an override at all.
                local function OvLocked() return (entry.ovLockedFn and entry.ovLockedFn()) and true or false end
                local function IsRowLocked()
                    if OvLocked() or entry.locked then return true end
                    return (entry.lockedFn and entry.lockedFn()) and true or false
                end
                local function LockedTip()
                    local lt = (OvLocked() and entry.ovLockedTooltip) or entry.lockedTooltip
                    if type(lt) == "function" then lt = lt() end
                    return lt
                end
                local function SyncCheck()
                    if chk then
                        if getFn(entry.key) then
                            chk:Show()
                            boxBrd:SetColor(CUI.CLUDES_GREEN.r, CUI.CLUDES_GREEN.g, CUI.CLUDES_GREEN.b, 0.8)
                        else
                            chk:Hide()
                            boxBrd:SetColor(0.4, 0.4, 0.4, 0.6)
                        end
                        if boxFrame and entry.dual then
                            local laneLocked = ShowLaneLocked()
                            boxFrame:SetAlpha(laneLocked and 0.3 or 1)
                            -- Mouse only while locked AND the item explains the
                            -- dim (item.showLockedTooltip): the disabled box then
                            -- swallows its own hover for the tooltip, and clicks,
                            -- like any disabled control. Unlocked, the box goes
                            -- mouse-inert again so the ROW keeps every click.
                            boxFrame:EnableMouse((laneLocked and entry.showLockedTooltip) and true or false)
                        end
                    end
                    if negChk then
                        if getFn(entry.key, true) then
                            negChk:Show()
                            negBrd:SetColor(0.85, 0.3, 0.3, 0.8)
                        else
                            negChk:Hide()
                            negBrd:SetColor(0.4, 0.4, 0.4, 0.6)
                        end
                    end
                    if sw then
                        swUpdate()
                        local off = entry.swatch.disabled and entry.swatch.disabled() or false
                        sw:SetAlpha(off and 0.3 or 1)
                        swBlock:SetShown(off and true or false)
                    end
                    -- Radio partners refresh each other, so this also runs on the hovered row;
                    -- repainting that one would drop its hover white until the mouse re-enters.
                    if entry.isModifier and not row._isLocked and not row:IsMouseOver() then
                        labelFS:SetTextColor(RestColor())
                    end
                end
                SyncCheck()
                row._updateCheck = SyncCheck
                row:SetScript("OnEnter", function()
                    if row._isLocked then
                        -- Locked rows keep the gray look (no highlight); if the item explains its lock, show that instead of the normal tooltip.
                        local lt = LockedTip()
                        if lt then CUI.ShowWidgetTooltip(row, lt) end
                        return
                    end
                    labelFS:SetTextColor(1, 1, 1, 1)
                    highlight:SetColorTexture(1, 1, 1, 0.04)
                    local tipText = entry.tooltip
                    if entry.dimTooltip and Dimmed() then tipText = entry.dimTooltip end
                    if type(tipText) == "function" then tipText = tipText() end
                    if tipText then CUI.ShowWidgetTooltip(row, tipText) end
                end)
                row:SetScript("OnLeave", function()
                    if row._isLocked then
                        if entry.lockedTooltip or entry.ovLockedTooltip then CUI.HideWidgetTooltip() end
                        return
                    end
                    labelFS:SetTextColor(RestColor())
                    highlight:SetColorTexture(1, 1, 1, 0)
                    if entry.tooltip or entry.dimTooltip then CUI.HideWidgetTooltip() end
                end)
                local function UpdateLocked()
                    local isLocked = IsRowLocked()
                    -- Mouse stays enabled so locked rows can explain themselves on hover; clicks are guarded independently in OnClick.
                    row._isLocked = isLocked and true or false
                    if isLocked then
                        labelFS:SetTextColor(0.4, 0.4, 0.4, 0.5)
                    else
                        labelFS:SetTextColor(RestColor())
                    end
                    -- opts.dimLocked: a locked row's checkbox dims with its label, so a
                    -- checked one reads as fixed rather than clickable (dual rows keep
                    -- their own lane dimming).
                    if options.dimLocked and boxFrame and not entry.dual then
                        boxFrame:SetAlpha(isLocked and 0.4 or 1)
                    end
                end
                row._updateLocked = UpdateLocked
                UpdateLocked()
                -- snap: the slot snapshot the click took before its setter ran
                -- (CludesUI._SOAttribution), or nil.
                local function AfterToggle(snap)
                    -- opts.notifyWrites: join the primary capture path every other widget's
                    -- setter uses. Without it a checklist has only the polling fallback,
                    -- whose mouse attribution is CLEARED while the menu (a UIParent child
                    -- with no popup marker) holds focus, so an override session never sees
                    -- the write when it happens. ddBtn's parent carries the row's
                    -- _captureCfg, so the slot is attributed exactly. Opt-in: every other
                    -- checklist keeps the behaviour it has always had.
                    if options.notifyWrites then CUI._NotifySettingWrite(dropdownBtn, snap) end
                    SyncCaption()
                    -- Refresh checkbox visuals + dynamic action labels, so items whose checked state depends on others (e.g. "Always" in crosshair) update live. Locked visuals refresh too, so rows whose lockedFn depends on the current selection never show a stale gray/active state.
                    for _, r in ipairs(_allRows) do
                        if r.frame._updateCheck then r.frame._updateCheck() end
                        if r.frame._updateActionLabel then r.frame._updateActionLabel() end
                        if r.frame._updateLocked then r.frame._updateLocked() end
                    end
                    for idx = 1, #_taTints do
                        _taTints[idx]()
                    end
                    if onChanged then
                        -- Anchor menu to absolute screen position BEFORE callback so a page rebuild (which destroys
                        -- ddBtn) can't shift us. GetCenter and SetPoint offsets are both in the menu's own coordinate
                        -- space, so the values pass through unscaled -- scaling them by effective-scale ratios made
                        -- the menu creep toward the bottom-left on every click when the options panel scale differs from UIParent's.
                        local cx, cy = dropMenu:GetCenter()
                        dropMenu:ClearAllPoints()
                        dropMenu:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy)
                        onChanged()
                    end
                end
                row:SetScript("OnClick", function()
                    if IsRowLocked() then return end
                    -- The slot the write belongs to, taken before the setter runs: a
                    -- setter that rebuilds the page can dress ddBtn for another slot.
                    local snap = options.notifyWrites and CUI._SOAttribution(dropdownBtn) or nil
                    -- The slot's Apply to link stays a few seconds after the pick.
                    CUI._SyncPickNotice(dropdownBtn)
                    if negBox and ShowLaneLocked() then
                        setFn(entry.key, not getFn(entry.key, true), true)
                    else
                        setFn(entry.key, not getFn(entry.key))
                    end
                    AfterToggle(snap)
                end)
                if negBox then
                    negBox:SetScript("OnClick", function()
                        if IsRowLocked() then return end
                        local snap = options.notifyWrites and CUI._SOAttribution(dropdownBtn) or nil
                        CUI._SyncPickNotice(dropdownBtn)
                        setFn(entry.key, not getFn(entry.key, true), true)
                        AfterToggle(snap)
                    end)
                    negBox:SetScript("OnEnter", function()
                        if row._isLocked then
                            local lt = LockedTip()
                            if lt then CUI.ShowWidgetTooltip(negBox, lt) end
                            return
                        end
                        labelFS:SetTextColor(1, 1, 1, 1)
                        highlight:SetColorTexture(1, 1, 1, 0.04)
                        local hlt = options.hideLaneTooltip
                        if type(hlt) == "function" then hlt = hlt(entry.key) end
                        CUI.ShowWidgetTooltip(
                            negBox,
                            hlt and CUI.L(hlt) or CUI.L("Hide these instead of showing them")
                        )
                    end)
                    negBox:SetScript("OnLeave", function()
                        if not row._isLocked then labelFS:SetTextColor(RestColor()) end
                        highlight:SetColorTexture(1, 1, 1, 0)
                        CUI.HideWidgetTooltip()
                    end)
                    -- The SHOW box mirrors the hide box's self-explanation, but
                    -- only while a broad mode locks the lane: UpdateCheck enables
                    -- its mouse exactly then, so these scripts never fire for an
                    -- active lane and row clicks stay untouched.
                    if boxFrame then
                        boxFrame:SetScript("OnEnter", function()
                            labelFS:SetTextColor(1, 1, 1, 1)
                            highlight:SetColorTexture(1, 1, 1, 0.04)
                            local tt = entry.showLockedTooltip
                            if type(tt) == "function" then tt = tt() end
                            if tt then CUI.ShowWidgetTooltip(boxFrame, tt) end
                        end)
                        boxFrame:SetScript("OnLeave", function()
                            if not row._isLocked then labelFS:SetTextColor(RestColor()) end
                            highlight:SetColorTexture(1, 1, 1, 0)
                            CUI.HideWidgetTooltip()
                        end)
                    end
                end
                -- Marks the contiguous run the override overlay below seals off.
                row._ovBlock = entry.ovLockedFn and true or nil
                _allRows[#_allRows + 1] =
                    { frame = row, isHeader = false, label = entry.label, height = ITEM_HEIGHT }
                yOff = yOff - ITEM_HEIGHT
            end -- isHeader else
        end

        -- Override session: the excluded rows are sealed off as ONE block rather than
        -- marked one by one -- 1px red border, a 5% red wash, a lock glyph with a caption
        -- and a click blocker holding the explanation, the same treatment SetSlotMark
        -- gives an override-red slot in the panel.
        -- Parented to the scroll child so it travels with the rows.
        if options.ovLockedFn then
            local first, last
            for idx = 1, #_allRows do
                if _allRows[idx].frame._ovBlock then
                    -- A header sitting directly on top of the run introduces it.
                    if not first then
                        first = (idx > 1 and _allRows[idx - 1].isHeader) and (idx - 1) or idx
                    end
                    last = idx
                end
            end
            if first and last then
                if not seal then
                    seal = CreateFrame("Button", nil, childFrame)
                    seal:SetFrameLevel(dropMenu:GetFrameLevel() + 8)
                    local wash = seal:CreateTexture(nil, "BACKGROUND")
                    wash:SetAllPoints()
                    wash:SetColorTexture(0.9, 0.2, 0.2, 0.05)
                    if Pix and Pix.CreateBorder then
                        Pix.CreateBorder(seal, 0.9, 0.2, 0.2, 0.9, 1, "OVERLAY", 7)
                    end
                    -- Caption on the block's top edge rather than across its middle: the wash
                    -- is deliberately faint, so a centred label would land on readable rows.
                    local sealLbl = seal:CreateFontString(nil, "OVERLAY", nil, 7)
                    sealLbl:SetFont(fontFile, 11, "")
                    sealLbl:SetTextColor(1, 0.35, 0.35, 1)
                    sealLbl:SetPoint("TOPRIGHT", seal, "TOPRIGHT", -6, -5)
                    sealLbl:SetText(CUI.L("Not overridable"))
                    -- The section header's divider line runs straight THROUGH the caption at
                    -- this height. A plate in the menu's own background colour cuts the line
                    -- for the width of the text: the seal sits at a higher frame level than
                    -- the header, so anything it draws covers that line.
                    local backing = seal:CreateTexture(nil, "ARTWORK", nil, 6)
                    backing:SetColorTexture(CUI.DD_BG_R, CUI.DD_BG_G, CUI.DD_BG_B, 1)
                    backing:SetPoint("TOPLEFT", sealLbl, "TOPLEFT", -5, 2)
                    backing:SetPoint("BOTTOMRIGHT", sealLbl, "BOTTOMRIGHT", 5, -2)
                    seal:EnableMouse(true)
                    seal:SetScript("OnEnter", function(self)
                        if options.ovLockedTooltip then
                            CUI.ShowWidgetTooltip(self, options.ovLockedTooltip)
                        end
                    end)
                    seal:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
                end
                seal:ClearAllPoints()
                seal:SetPoint("TOPLEFT", _allRows[first].frame, "TOPLEFT", 1, 0)
                -- The 4px scrollbar track sits 4px off the right edge, ON the scroll
                -- frame rather than in here, so the seal stops short of it instead of
                -- running underneath and having the bar cut through its border.
                seal:SetPoint("BOTTOMRIGHT", _allRows[last].frame, "BOTTOMRIGHT", -9, 0)
                seal:SetFrameLevel(dropMenu:GetFrameLevel() + 8)
                dropMenu._ovSeal = seal
                seal:SetShown(options.ovLockedFn())
            else
                dropMenu._ovSeal = nil
                if seal then seal:Hide() end
            end
        end

        -- Close button at bottom of dropdown (optional)
        if closeButton then
            local CLOSE_H = 26
            local closePad = 6
            yOff = yOff - closePad
            local ACC = CUI.CLUDES_GREEN or { r = 0.30, g = 0.79, b = 0.94 }
            if not closeBtn then
                closeBtn = CreateFrame("Button", nil, childFrame)
                closeBtn:SetHeight(CLOSE_H)
                local closeBtnW = math.floor((ddW - 2) * 0.75)
                closeBtn:SetWidth(closeBtnW)
                closeBtn:SetFrameLevel(dropMenu:GetFrameLevel() + 3)
                local closeBg = closeBtn:CreateTexture(nil, "BACKGROUND")
                closeBg:SetAllPoints()
                closeBtn._bg = closeBg
                local closeLbl = closeBtn:CreateFontString(nil, "OVERLAY")
                closeLbl:SetFont(fontFile, 12, "")
                closeLbl:SetPoint("CENTER")
                closeLbl:SetText(CUI.L(type(closeButton) == "string" and closeButton or "Okay"))
                closeLbl:SetTextColor(1, 1, 1, 1)
                closeBtn:SetScript("OnClick", function() dropMenu:Hide() end)
                closeBtn:SetScript("OnEnter", function() closeBg:SetColorTexture(ACC.r, ACC.g, ACC.b, 1) end)
                closeBtn:SetScript(
                    "OnLeave",
                    function() closeBg:SetColorTexture(ACC.r, ACC.g, ACC.b, 0.85) end
                )
            end
            closeBtn._bg:SetColorTexture(ACC.r, ACC.g, ACC.b, 0.85)
            closeBtn:ClearAllPoints()
            closeBtn:SetPoint("TOP", childFrame, "TOPLEFT", (ddW - 2) / 2, yOff)
            closeBtn:SetFrameLevel(dropMenu:GetFrameLevel() + 3)
            yOff = yOff - CLOSE_H - closePad
        end

        childFrame:SetHeight(math.max(1, math.abs(yOff)))

        -- Rows a dynamic list no longer uses stay pooled, hidden and inert.
        for _, pool in pairs(rowPools) do
            for idx = pool.used + 1, #pool do
                local r = pool[idx]
                r:Hide()
                r._updateCheck, r._updateLocked, r._updateActionLabel = nil, nil, nil
            end
        end
        if not firstBuild then return end

        -- Wire search filtering
        if searchEdit then
            searchEdit:SetScript("OnTextChanged", function(self)
                local t = strlower(strtrim(self:GetText()))
                searchPlaceholder:SetShown(t == "")
                local visY = -4
                local lastHdr = nil
                local lastHdrY = 0
                local hdrHasVisible = false
                for _, r in ipairs(_allRows) do
                    if r.isHeader then
                        -- Defer header: show only if a child is visible
                        if lastHdr and not hdrHasVisible then lastHdr:Hide() end
                        lastHdr = r.frame
                        lastHdrY = visY
                        hdrHasVisible = false
                        if t == "" then
                            lastHdr:Show()
                            lastHdr:ClearAllPoints()
                            lastHdr:SetPoint("TOPLEFT", childFrame, "TOPLEFT", 1, visY)
                            lastHdr:SetPoint("TOPRIGHT", childFrame, "TOPRIGHT", -1, visY)
                            visY = visY - r.height
                            hdrHasVisible = true
                        end
                    else
                        if t == "" or strfind(strlower(r.label), t, 1, true) then
                            -- Show header if this is the first visible child
                            if lastHdr and not hdrHasVisible then
                                lastHdr:Show()
                                lastHdr:ClearAllPoints()
                                lastHdr:SetPoint("TOPLEFT", childFrame, "TOPLEFT", 1, lastHdrY)
                                lastHdr:SetPoint("TOPRIGHT", childFrame, "TOPRIGHT", -1, lastHdrY)
                                visY = lastHdrY - HDR_H
                                hdrHasVisible = true
                            end
                            r.frame:Show()
                            r.frame:ClearAllPoints()
                            r.frame:SetPoint("TOPLEFT", childFrame, "TOPLEFT", 1, visY)
                            r.frame:SetPoint("TOPRIGHT", childFrame, "TOPRIGHT", -1, visY)
                            visY = visY - r.height
                        else
                            r.frame:Hide()
                        end
                    end
                end
                -- Hide trailing header with no visible children
                if lastHdr and not hdrHasVisible then lastHdr:Hide() end
                -- The override seal is anchored to the FIRST and LAST row of its run,
                -- which this filter hides and repositions without touching the seal. Drop
                -- it while a filter is active rather than re-deriving the run: with rows
                -- missing there is no contiguous block left to mark, and a stale seal is a
                -- mouse-enabled frame parked over whatever rows did survive.
                if dropMenu._ovSeal then
                    dropMenu._ovSeal:SetShown(
                        t == "" and options.ovLockedFn and options.ovLockedFn() or false
                    )
                end
                childFrame:SetHeight(math.max(1, math.abs(visY)))
                sf:SetVerticalScroll(0)
                UpdateCBThumb()
            end)
            dropMenu:HookScript("OnShow", function()
                searchEdit:SetText("")
                -- Not under the controller cursor: focus would pop its on-screen keyboard over the list.
                if not CUI.PadCursorShown() then searchEdit:SetFocus() end
                UpdateCBThumb()
            end)
        end

        dropMenu:HookScript("OnShow", UpdateCBThumb)

        -- Refresh all checkbox + locked visuals on show
        dropMenu:HookScript("OnShow", function()
            for _, rowInfo in ipairs(_allRows) do
                if rowInfo.frame._updateCheck then rowInfo.frame._updateCheck() end
                if rowInfo.frame._updateLocked then rowInfo.frame._updateLocked() end
            end
            for idx = 1, #_taTints do
                _taTints[idx]()
            end
        end)

        if CUI.PadCP() then
            -- Controller cursor (ShowMenu calls this only while it is shown): list back
            -- to the top, cursor onto the first row.
            dropMenu._padFocus = function()
                sf:SetVerticalScroll(0)
                UpdateCBThumb()
                local first
                for idx = 1, #_allRows do
                    local r = _allRows[idx]
                    if not r.isHeader and r.frame:IsShown() then
                        first = r.frame
                        break
                    end
                end
                CUI.PadFocus(first or dropMenu)
            end
            CUI.TrackOverlay(dropMenu)
        end
        dropdownBtn._ddMenu = dropMenu
    end

    local function PaintDropNormal()
        if PoolGen(dropdownBtn) ~= dressGen then return end
        dropCaption:SetTextColor(1, 1, 1, CUI.DD_TXT_A)
        ddBrd:SetColor(1, 1, 1, CUI.DD_BRD_A)
        ddBg:SetColorTexture(CUI.DD_BG_R, CUI.DD_BG_G, CUI.DD_BG_B, CUI.DD_BG_A)
    end
    local function PaintDropHover()
        if PoolGen(dropdownBtn) ~= dressGen then return end
        dropCaption:SetTextColor(1, 1, 1, CUI.DD_TXT_HA)
        ddBrd:SetColor(1, 1, 1, CUI.DD_BRD_HA)
        ddBg:SetColorTexture(CUI.DD_BG_R, CUI.DD_BG_G, CUI.DD_BG_B, CUI.DD_BG_HA)
    end
    dropdownBtn:SetScript("OnEnter", function() PaintDropHover() end)
    dropdownBtn:SetScript("OnLeave", function()
        if not (dropMenu and dropMenu:IsShown()) then PaintDropNormal() end
    end)

    local function ShowMenu()
        -- Dynamic items: re-evaluate and lay the menu out again on every open (only when about to show -- a toggle-close never rebuilds).
        if itemsFn and not (dropMenu and dropMenu:IsShown()) then
            itemList = itemsFn() or {}
            if dropMenu then
                dropMenu:Hide()
                menuStale = true
            end
            SyncCaption()
        end
        BuildMenuOnce()
        if dropMenu:IsShown() then
            dropMenu:Hide()
            return
        end
        -- A static menu is built once and reused, so anything that changed while it was
        -- closed would show stale: refresh checked state AND locks on every open. The
        -- case that matters is an override session starting between two opens.
        for _, r in ipairs(dropMenu._rows or {}) do
            if r.frame._updateCheck then r.frame._updateCheck() end
            if r.frame._updateLocked then r.frame._updateLocked() end
        end
        if dropMenu._ovSeal then dropMenu._ovSeal:SetShown(options.ovLockedFn()) end
        -- Match the panel's effective scale since menu lives on UIParent
        local btnScale = dropdownBtn:GetEffectiveScale()
        local uiScale = UIParent:GetEffectiveScale()
        dropMenu:SetScale(btnScale / uiScale)
        CUI.SeatDropdownMenu(dropMenu)
        PaintDropHover()
        dropMenu:Show()
        -- Track the open menu globally so popup outside-click watchers don't treat clicks on rows that extend below the popup as a dismissing outside click.
        CUI._openDropdownMenu = dropMenu
        dropMenu:SetScript("OnUpdate", function(self)
            -- Close when left-clicking outside the menu and button. The shared colour
            -- picker is a separate popup a row swatch opens: working in it keeps the menu.
            local cp = CUI._colorPickerPopup
            if
                not self:IsMouseOver()
                and not dropdownBtn:IsMouseOver()
                and IsMouseButtonDown("LeftButton")
                and not (cp and cp:IsShown())
            then
                self:Hide()
                return
            end
            -- Close when the dropdown button scrolls out of the visible area
            local scrollFrame = CUI._scrollFrame
            if scrollFrame then
                if dropdownBtn._inScrollChild == nil then
                    local scrollChild = scrollFrame.GetScrollChild and scrollFrame:GetScrollChild()
                    local found = false
                    if scrollChild then
                        local p = dropdownBtn:GetParent()
                        while p do
                            if p == scrollChild then
                                found = true
                                break
                            end
                            p = p:GetParent()
                        end
                    end
                    dropdownBtn._inScrollChild = found
                end
                if dropdownBtn._inScrollChild then
                    local sfTop = scrollFrame:GetTop()
                    local sfBot = scrollFrame:GetBottom()
                    local btnBot = dropdownBtn:GetBottom()
                    if sfTop and sfBot and btnBot then
                        if btnBot < sfBot or btnBot > sfTop then self:Hide() end
                    end
                end
            end
        end)
        dropMenu:SetScript("OnHide", function(self)
            self:SetScript("OnUpdate", nil)
            if CUI._openDropdownMenu == self then CUI._openDropdownMenu = nil end
            if dropdownBtn:IsMouseOver() then
                PaintDropHover()
            else
                PaintDropNormal()
            end
            if onMenuClosed then onMenuClosed() end
            -- Controller cursor: back onto the dropdown button (a no-op once that is hidden too).
            if CUI.PadCursorShown() then CUI.PadFocus(dropdownBtn) end
        end)
        if dropMenu._padFocus and CUI.PadCursorShown() then dropMenu._padFocus() end
    end

    dropdownBtn:SetScript("OnClick", function() ShowMenu() end)
    dropdownBtn:HookScript("OnHide", function()
        if dropMenu then dropMenu:Hide() end
    end)

    -- RefreshAll(true), opt-in: a dynamic list is read again first, so the summary
    -- names a change made outside the menu while it is closed (an entry typed into
    -- a popup). A page refresh calls it with no argument and reads nothing again.
    local function RefreshAll(reread)
        -- A caller may keep this past a page pass that dressed ddBtn (and with it
        -- the kept menu) for another build.
        if PoolGen(dropdownBtn) ~= dressGen then return end
        if reread == true and itemsFn and not (dropMenu and dropMenu:IsShown()) then
            itemList = itemsFn() or {}
        end
        SyncCaption()
        if dropMenu then
            for _, r in ipairs(dropMenu._rows or {}) do
                if r.frame._updateCheck then r.frame._updateCheck() end
                if r.frame._updateLocked then r.frame._updateLocked() end
            end
            if dropMenu._ovSeal then dropMenu._ovSeal:SetShown(options.ovLockedFn()) end
        end
    end

    if options.disabled then
        local block = CreateFrame("Frame", nil, dropdownBtn)
        block:SetAllPoints()
        block:SetFrameLevel(dropdownBtn:GetFrameLevel() + 20)
        block:EnableMouse(true)
        block:SetScript("OnEnter", function()
            local tipText = CUI.ResolveDisabledTip(options)
            if tipText then CUI.ShowWidgetTooltip(dropdownBtn, tipText) end
        end)
        block:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
        local function DisabledState()
            local off = options.disabled() and true or false
            dropdownBtn:SetAlpha(off and 0.4 or 1)
            block:SetShown(off)
            if off and dropMenu then dropMenu:Hide() end
        end
        DisabledState()
        CUI.RegisterWidgetRefresh(DisabledState)
    end
    return dropdownBtn, RefreshAll
end

-------------------------------------------------------------------------------
--  Spec picker items for BuildVisOptsCBDropdown (the "Select a Spec" lists):
--  "All Specs" first (key CludesUI.SPEC_PICK_ALL, an action row), then on
--  retail every class's specs under its class header, classes in alphabetical
--  order, with opts.roles adding the All Healers / All Tanks / All DPS action
--  rows (keys SPEC_PICK_HEALERS / _TANKS / _DPS) after it. WoW Forever lists
--  one row per class instead, keyed by its class token and standing for every
--  retail spec of the class (CludesUI.ForeverClassSpecIDs; the caller's
--  getter and setter expand it), and no role rows. opts.allLockedFn locks the
--  action rows; opts.lockedFn(specID) locks a spec row, and a Forever class row
--  while any spec of its class is locked. Returns the items and the role table
--  ({ [SPEC_PICK_HEALERS] = spec IDs, ... }, empty on Forever).
-------------------------------------------------------------------------------
CUI.SPEC_PICK_ALL, CUI.SPEC_PICK_HEALERS = 0, -1
CUI.SPEC_PICK_TANKS, CUI.SPEC_PICK_DPS = -2, -3
function CUI.SpecPickItems(options)
    options = options or {}
    local lockedFn, allLockedFn = options.lockedFn, options.allLockedFn
    local itemList, roles = {}, {}
    itemList[1] = { key = CUI.SPEC_PICK_ALL, label = "All Specs", isAction = true, lockedFn = allLockedFn }
    if CUI.IS_FOREVER then
        local classes = CUI.ForeverClasses()
        for num = 1, #classes do
            local token = classes[num]
            local ids = CUI.ForeverClassSpecIDs(token)
            itemList[#itemList + 1] = {
                key = token,
                label = CUI.ForeverClassName(token),
                lockedFn = lockedFn and function()
                    for idx = 1, #ids do
                        if lockedFn(ids[idx]) then return true end
                    end
                    return false
                end or nil,
            }
        end
        return itemList, roles
    end
    if options.roles then
        itemList[#itemList + 1] = {
            key = CUI.SPEC_PICK_HEALERS,
            label = "All Healers",
            isAction = true,
            lockedFn = allLockedFn,
        }
        itemList[#itemList + 1] =
            { key = CUI.SPEC_PICK_TANKS, label = "All Tanks", isAction = true, lockedFn = allLockedFn }
        itemList[#itemList + 1] =
            { key = CUI.SPEC_PICK_DPS, label = "All DPS", isAction = true, lockedFn = allLockedFn }
    end
    local classList = {}
    for classID = 1, (GetNumClasses and GetNumClasses() or 13) do
        local className = GetClassInfo(classID)
        if className then classList[#classList + 1] = { classID = classID, className = className } end
    end
    table.sort(classList, function(lhs, rhs) return lhs.className < rhs.className end)
    local healers, tanks, dps = {}, {}, {}
    for _, cls in ipairs(classList) do
        itemList[#itemList + 1] = { isHeader = true, label = cls.className }
        for specIndex = 1, (C_SpecializationInfo.GetNumSpecializationsForClassID(cls.classID) or 0) do
            local specID, specName, _, _, role = GetSpecializationInfoForClassID(cls.classID, specIndex)
            if specID and specName then
                local spellRef = specID
                itemList[#itemList + 1] = {
                    key = specID,
                    label = specName,
                    lockedFn = lockedFn and function() return lockedFn(spellRef) end or nil,
                }
                if role == "HEALER" then
                    healers[#healers + 1] = specID
                elseif role == "TANK" then
                    tanks[#tanks + 1] = specID
                else
                    dps[#dps + 1] = specID
                end
            end
        end
    end
    roles[CUI.SPEC_PICK_HEALERS] = healers
    roles[CUI.SPEC_PICK_TANKS] = tanks
    roles[CUI.SPEC_PICK_DPS] = dps
    return itemList, roles
end

-------------------------------------------------------------------------------
--  AttachRowReorder
--  Drag-to-reorder for a column of rows at fixed slots in a host frame (the
--  reorder dropdown's movable rows, the Cooldown Manager's Combat Potion
--  priority rows): a 3px drag threshold, the dragged row floating with the
--  cursor, an insertion line at the gap it points at, and a drop that shuffles
--  the ITEMS (spec.items, in place) while the row frames keep their slots.
--  spec = {
--      rows    = { row, ... },       -- row._item (its item), row._slotY (its slot's y)
--      items   = { item, ... },      -- in row order; item.key; mutated on a drop
--      itemH   = number,             -- the row height
--      slotY   = function(i),        -- y of slot i from the host's top (slot 1 highest)
--      insLine = texture,            -- the insertion line, on the host, hidden
--      state   = { dragging = false },  -- read by the rows' own hover/click scripts
--      refresh = function(),         -- repaint every row from spec.items
--      onDrop  = function(keys),     -- after a drop that changed the order
--      canReorder  = function() -> boolean,  -- optional drag guard
--      onDragStart = function(row),  -- optional, as the drag begins
--  }
--  Rows anchor TOPLEFT (1, slotY) / TOPRIGHT (-1, slotY) to the host at the
--  host's level + 2 and float at + 10. Every row gets row:_cancelDrag().
-------------------------------------------------------------------------------
function CUI.AttachRowReorder(host, specInfo)
    local rowList, movable, ITEM_HEIGHT, SlotY = specInfo.rows, specInfo.items, specInfo.itemH, specInfo.slotY
    local insLine, status = specInfo.insLine, specInfo.state
    -- Read live: a host raised after this call (a cog popup lifts its open
    -- dropdown menu) would otherwise park dropped rows behind its background.
    local function BaseLevel() return host:GetFrameLevel() + 2 end
    local function Park(row)
        row:SetFrameLevel(BaseLevel())
        row:SetAlpha(1)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", host, "TOPLEFT", 1, row._slotY)
        row:SetPoint("TOPRIGHT", host, "TOPRIGHT", -1, row._slotY)
    end
    -- Gap index (1..#items+1) the cursor points at: walk the slot midpoints, skipping the dragged row's own slot -- the same logic as the raid frames Sort By reorder menu, so the insertion line and the drop target always agree.
    local function TargetGap(cursorY, fromIdx)
        local mT = host:GetTop() or 0
        local iI = #movable
        for idx = 1, #movable do
            if idx ~= fromIdx then
                local mid = mT + SlotY(idx) - ITEM_HEIGHT / 2
                if cursorY > mid then
                    iI = idx
                    break
                end
                iI = idx + 1
            end
        end
        return math.max(1, math.min(iI, #movable + 1))
    end
    for idx = 1, #rowList do
        local row = rowList[idx]
        local dsY, dgO, dgFrom
        local DragUpdate
        row:SetScript("OnMouseDown", function(self, b)
            if b ~= "LeftButton" then return end
            row._suppressClick = nil
            if specInfo.canReorder and not specInfo.canReorder() then return end
            local _, curY = GetCursorPosition()
            dsY = curY
            self:SetScript("OnUpdate", DragUpdate)
        end)
        row:SetScript("OnMouseUp", function(self, b)
            if b ~= "LeftButton" then return end
            dsY = nil
            self:SetScript("OnUpdate", nil)
            if not status.dragging then return end
            self._suppressClick = true
            status.dragging = false
            insLine:Hide()
            -- Snap the floated row back to its slot
            Park(self)
            if specInfo.canReorder and not specInfo.canReorder() then
                specInfo.refresh()
                return
            end
            local _, curY = GetCursorPosition()
            curY = curY / host:GetEffectiveScale()
            local from
            for mi = 1, #movable do
                if movable[mi] == self._item then
                    from = mi
                    break
                end
            end
            -- Gap -> insertion index: removing the row first shifts everything after it up one, so downward moves adjust by -1 (same as the raid frames Sort By drop).
            local iI = TargetGap(curY, from)
            if from and from < iI then iI = iI - 1 end
            local to = math.max(1, math.min(iI, #movable))
            if from and from ~= to then
                local mv = table.remove(movable, from)
                table.insert(movable, to, mv)
                if specInfo.onDrop then
                    local keyList = {}
                    for mi = 1, #movable do
                        keyList[mi] = movable[mi].key
                    end
                    specInfo.onDrop(keyList)
                end
            end
            specInfo.refresh()
        end)
        DragUpdate = function(self)
            if not dsY then return end
            local _, curY = GetCursorPosition()
            if not status.dragging then
                if math.abs(curY - dsY) < 3 then return end
                status.dragging = true
                local sc = host:GetEffectiveScale()
                dgO = (curY / sc) - (self:GetTop() or 0)
                dgFrom = nil
                for mi = 1, #movable do
                    if movable[mi] == self._item then
                        dgFrom = mi
                        break
                    end
                end
                self:SetFrameLevel(BaseLevel() + 8)
                self:SetAlpha(0.8)
                if specInfo.onDragStart then specInfo.onDragStart(self) end
            end
            local sc = host:GetEffectiveScale()
            local cY = curY / sc
            local mT = host:GetTop() or 0
            local lY = cY - (dgO or 0) - mT
            lY = math.max(SlotY(#movable), math.min(lY, SlotY(1)))
            self:ClearAllPoints()
            self:SetPoint("TOPLEFT", host, "TOPLEFT", 1, lY)
            self:SetPoint("TOPRIGHT", host, "TOPRIGHT", -1, lY)
            local lnY = SlotY(TargetGap(cY, dgFrom)) + 1
            insLine:ClearAllPoints()
            insLine:SetPoint("TOPLEFT", host, "TOPLEFT", 8, lnY)
            insLine:SetPoint("TOPRIGHT", host, "TOPRIGHT", -8, lnY)
            insLine:Show()
        end
        row._cancelDrag = function(self)
            if not dsY then return end
            dsY = nil
            self:SetScript("OnUpdate", nil)
            Park(self)
        end
    end
end

-------------------------------------------------------------------------------
--  BuildReorderCBDropdown
--  Checkbox dropdown whose rows can also be drag-reordered vertically. Row visuals match BuildVisOptsCBDropdown;
--  the drag behavior matches the Macro Factory per-macro menus (3px threshold, floating row, insertion line, contents shuffle on drop).
--  items: array in initial display order:
--      { key = "...", label = "...", fixed = true|nil, tooltip = "..."|nil }
--  fixed rows are checkbox-only and pinned below the movable rows; a row's
--  tooltip shows while the cursor is on it.
--  getFn(key) -> checked; setFn(key, checked, orderedMovableKeys) fires on row click.
--  opts = {
--      setOrder = function(orderedMovableKeys),  -- fired on every drop
--      onClose  = function(orderChanged),        -- fired once per menu close
--      hint     = "Drag to Reorder",             -- text above the rows
--      grip     = true,                          -- a three-dash drag handle on each movable row
--      hint2    = "...",                         -- optional second hint line
--      canReorder = function() -> boolean,       -- optional drag guard
--      summaryLabel = function(movable, fixed, getFn) -> string,
--      head     = { { key, label }, ... },       -- plain rows (no box) at the top, a divider under them
--      onHead   = function(key),
--      tail     = { { key, label }, ... },       -- plain rows at the bottom, a divider above them
--      onTail   = function(key),
--      tailSelected = function(key) -> boolean,  -- shows a tail row as the current choice
--      openOrder = function() -> keys | nil,     -- on every open: these movable rows first, in this
--  }                                             -- order, the rest in their first order
--  A plain row calls its callback, then closes the menu (onClose sees the pick).
--  Returns ddBtn, RefreshAll (same contract as BuildVisOptsCBDropdown).
-------------------------------------------------------------------------------
function CUI.BuildReorderCBDropdown(parentFrame, ddW, fLevel, itemList, getFn, setFn, options)
    -- Search prebuild on an absorber row: the dropdown indexes nothing, so none is built.
    local standIn = StandIn(parentFrame)
    if standIn then return standIn, standIn end
    options = options or {}
    local Pix = CUI.PanelPP
    local ACC = CUI.CLUDES_GREEN or { r = 0.30, g = 0.79, b = 0.94 }
    -- Options panel is Expressway-locked by design (locale-aware: CJK/Cyrillic get the system glyph font). The user's global font intentionally does not restyle the settings UI.
    local fontFile = CUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF"

    -- Split movable / fixed, preserving the given order
    local movable, fixedItems = {}, {}
    for _, it in ipairs(itemList) do
        if it.fixed then
            fixedItems[#fixedItems + 1] = it
        else
            movable[#movable + 1] = it
        end
    end
    local head, tail = options.head or {}, options.tail or {}
    -- The movable rows' first order (opts.openOrder sorts from it).
    local baseMovable = {}
    for idx = 1, #movable do
        baseMovable[idx] = movable[idx]
    end
    local function MovableKeys()
        local keyList = {}
        for idx = 1, #movable do
            keyList[idx] = movable[idx].key
        end
        return keyList
    end
    local plainPaints = {}
    local function PaintRows()
        for idx = 1, #plainPaints do
            plainPaints[idx]()
        end
    end

    local dropdownBtn = CreateFrame("Button", nil, parentFrame)
    -- This build's dress of the button (see BuildVisOptsCBDropdown).
    local dressGen = PoolGen(dropdownBtn)
    Pix.Size(dropdownBtn, ddW, 30)
    dropdownBtn:SetFrameLevel(fLevel)
    local ddBg = dropdownBtn:CreateTexture(nil, "BACKGROUND")
    ddBg:SetAllPoints()
    ddBg:SetColorTexture(CUI.DD_BG_R, CUI.DD_BG_G, CUI.DD_BG_B, CUI.DD_BG_A)
    local ddBrd = CUI.MakeRoundedBorder(dropdownBtn, 1, 1, 1, CUI.DD_BRD_A, ddBg)
    local dropCaption = dropdownBtn:CreateFontString(nil, "OVERLAY")
    dropCaption:SetFont(fontFile, 13, "")
    dropCaption:SetTextColor(1, 1, 1, CUI.DD_TXT_A)
    dropCaption:SetJustifyH("LEFT")
    dropCaption:SetWordWrap(false)
    dropCaption:SetMaxLines(1)
    dropCaption:SetPoint("LEFT", dropdownBtn, "LEFT", 12, 0)
    local arrow = CUI.MakeDropdownArrow(dropdownBtn, 12, Pix)
    dropCaption:SetPoint("RIGHT", arrow, "LEFT", -5, 0)

    local function SummaryLabel()
        if options.summaryLabel then return options.summaryLabel(movable, fixedItems, getFn) end
        local nameList = {}
        local sum = 0
        local function collect(entries)
            for _, entry in ipairs(entries) do
                sum = sum + 1
                if getFn(entry.key) then nameList[#nameList + 1] = CUI.L(entry.label) end
            end
        end
        collect(movable)
        collect(fixedItems)
        if #nameList == 0 then return CUI.L("None") end
        if #nameList == sum then return CUI.L("All") end
        return table.concat(nameList, ", ")
    end
    local function SyncCaption()
        if PoolGen(dropdownBtn) ~= dressGen then return end
        dropCaption:SetText(SummaryLabel())
    end
    SyncCaption()

    local dropMenu
    local orderChanged = false
    local allRows = {}

    local ITEM_HEIGHT = 28
    local HINT_H = options.hint2 and 32 or 18
    local DIV_H = 7

    local function BuildMenuOnce()
        if dropMenu then return end
        local HEAD_H = (#head > 0) and (#head * ITEM_HEIGHT + DIV_H) or 0
        local TAIL_H = (#tail > 0) and (DIV_H + #tail * ITEM_HEIGHT) or 0
        local ROWS_BASE_Y = -4 - HEAD_H - HINT_H
        local menuH = 4
            + HEAD_H
            + HINT_H
            + #movable * ITEM_HEIGHT
            + ((#fixedItems > 0) and (DIV_H + #fixedItems * ITEM_HEIGHT) or 0)
            + TAIL_H
            + 4
        -- One menu per dropdown button for the session: a build that dresses the
        -- button again gets this frame back here, reset to new.
        dropMenu = PoolKept(dropdownBtn, "reorderMenu", "Frame", CUI.OverlayParent())
        dropMenu:SetFrameStrata("FULLSCREEN_DIALOG")
        dropMenu:SetFrameLevel(200)
        dropMenu:SetClampedToScreen(true)
        dropMenu:EnableMouse(true)
        dropMenu:SetSize(ddW, menuH)
        dropMenu:SetPoint("TOPLEFT", dropdownBtn, "BOTTOMLEFT", 0, -2)
        dropMenu:Hide()
        local mBg = dropMenu:CreateTexture(nil, "BACKGROUND")
        mBg:SetAllPoints()
        mBg:SetColorTexture(CUI.DD_BG_R, CUI.DD_BG_G, CUI.DD_BG_B, CUI.DD_BG_HA)
        CUI.MakeRoundedBorder(dropMenu, 1, 1, 1, CUI.DD_BRD_A, mBg, nil, true)
        -- Controller cursor: the list blocks what is under it but is not a stop itself;
        -- Cancel clicks the dropdown button (it toggles the list closed).
        if CUI.PadCP() then
            CUI.PadHint(dropMenu, "nodepass")
            dropMenu.CloseButton = dropdownBtn
        end

        -- Hint line(s) above the rows
        local hint = dropMenu:CreateFontString(nil, "OVERLAY")
        hint:SetFont(fontFile, 10, "")
        hint:SetTextColor(1, 1, 1, 0.25)
        if options.hint2 then
            hint:SetPoint("TOP", dropMenu, "TOP", 0, -6 - HEAD_H)
            local hint2 = dropMenu:CreateFontString(nil, "OVERLAY")
            hint2:SetFont(fontFile, 9, "")
            hint2:SetTextColor(1, 1, 1, 0.25)
            hint2:SetPoint("TOP", hint, "BOTTOM", 0, -3)
            hint2:SetText(CUI.L(options.hint2))
        else
            hint:SetPoint("TOP", dropMenu, "TOP", 0, -4 - HEAD_H - (HINT_H - 10) / 2)
        end
        hint:SetText(CUI.L(options.hint or "Drag to Reorder"))

        -- A plain row (head or tail): its label alone; its callback runs before
        -- the menu closes, so onClose sees the pick. A tail row shows the
        -- current choice.
        local function BuildPlainRow(entry, slotY, onPick, selFn)
            local row = CreateFrame("Button", nil, dropMenu)
            row:SetHeight(ITEM_HEIGHT)
            row:SetPoint("TOPLEFT", dropMenu, "TOPLEFT", 1, slotY)
            row:SetPoint("TOPRIGHT", dropMenu, "TOPRIGHT", -1, slotY)
            row:SetFrameLevel(dropMenu:GetFrameLevel() + 2)
            local labelFS = row:CreateFontString(nil, "OVERLAY")
            labelFS:SetFont(fontFile, 13, "")
            labelFS:SetPoint("LEFT", row, "LEFT", 10, 0)
            labelFS:SetPoint("RIGHT", row, "RIGHT", -10, 0)
            labelFS:SetJustifyH("LEFT")
            labelFS:SetWordWrap(false)
            labelFS:SetMaxLines(1)
            labelFS:SetText(CUI.L(entry.label))
            local highlight = row:CreateTexture(nil, "ARTWORK")
            highlight:SetAllPoints()
            local hover = false
            local function PaintEntry()
                local lit = hover or (selFn and selFn(entry.key))
                labelFS:SetTextColor(lit and 1 or 0.75, lit and 1 or 0.75, lit and 1 or 0.75, 1)
                highlight:SetColorTexture(1, 1, 1, lit and 0.04 or 0)
            end
            PaintEntry()
            plainPaints[#plainPaints + 1] = PaintEntry
            row:SetScript("OnEnter", function()
                hover = true
                PaintEntry()
            end)
            row:SetScript("OnLeave", function()
                hover = false
                PaintEntry()
            end)
            row:SetScript("OnClick", function()
                hover = false
                if onPick then onPick(entry.key) end
                dropMenu:Hide()
                SyncCaption()
            end)
        end
        for idx = 1, #head do
            BuildPlainRow(head[idx], -4 - (idx - 1) * ITEM_HEIGHT, options.onHead)
        end
        if #head > 0 then
            local hd = dropMenu:CreateTexture(nil, "ARTWORK")
            hd:SetHeight(1)
            hd:SetPoint("TOPLEFT", dropMenu, "TOPLEFT", 10, -4 - #head * ITEM_HEIGHT - 3)
            hd:SetPoint("TOPRIGHT", dropMenu, "TOPRIGHT", -10, -4 - #head * ITEM_HEIGHT - 3)
            hd:SetColorTexture(1, 1, 1, 0.08)
        end

        -- Shared with the row reorder (AttachRowReorder below): the rows' own
        -- scripts stand down while a drag runs.
        local dragState = { dragging = false }
        local insLine = dropMenu:CreateTexture(nil, "OVERLAY", nil, 7)
        insLine:SetHeight(2)
        insLine:SetColorTexture(ACC.r, ACC.g, ACC.b, 0.9)
        insLine:Hide()

        local function SlotY(idx) return ROWS_BASE_Y - (idx - 1) * ITEM_HEIGHT end

        local function BuildRow(entry, slotY, draggable)
            local row = CreateFrame("Button", nil, dropMenu)
            row:SetHeight(ITEM_HEIGHT)
            row:SetPoint("TOPLEFT", dropMenu, "TOPLEFT", 1, slotY)
            row:SetPoint("TOPRIGHT", dropMenu, "TOPRIGHT", -1, slotY)
            row:SetFrameLevel(dropMenu:GetFrameLevel() + 2)
            row._item = entry
            row._slotY = slotY
            local boxFrame = CreateFrame("Frame", nil, row)
            boxFrame:SetSize(16, 16)
            boxFrame:SetPoint("LEFT", row, "LEFT", 10, 0)
            local boxBg = boxFrame:CreateTexture(nil, "BACKGROUND")
            boxBg:SetAllPoints()
            boxBg:SetColorTexture(0.114, 0.106, 0.099, 1)
            local boxBrd = CUI.MakeRoundedBorder(boxFrame, 0.4, 0.4, 0.4, 0.6, boxBg)
            local chk = boxFrame:CreateTexture(nil, "ARTWORK")
            Pix.SetInside(chk, boxFrame, 2, 2)
            chk:SetColorTexture(ACC.r, ACC.g, ACC.b, 1)
            chk:SetSnapToPixelGrid(false)
            CUI.RoundBody(boxFrame, chk, 2)
            local labelFS = row:CreateFontString(nil, "OVERLAY")
            labelFS:SetFont(fontFile, 13, "")
            labelFS:SetTextColor(0.75, 0.75, 0.75, 1)
            labelFS:SetPoint("LEFT", boxFrame, "RIGHT", 8, 0)
            labelFS:SetPoint("RIGHT", row, "RIGHT", (draggable and options.grip) and -30 or -10, 0)
            labelFS:SetJustifyH("LEFT")
            labelFS:SetWordWrap(false)
            labelFS:SetMaxLines(1)
            labelFS:SetText(CUI.L(entry.label))
            local highlight = row:CreateTexture(nil, "ARTWORK")
            highlight:SetAllPoints()
            highlight:SetColorTexture(1, 1, 1, 0)
            -- opts.grip: a three-dash handle on the right of each movable row.
            if draggable and options.grip then
                for g = 1, 3 do
                    local bar = row:CreateTexture(nil, "ARTWORK")
                    bar:SetSize(10, 1)
                    bar:SetPoint("RIGHT", row, "RIGHT", -10, (2 - g) * 3)
                    bar:SetColorTexture(1, 1, 1, 0.35)
                end
            end
            local function SyncCheck()
                if getFn(row._item.key) then
                    chk:Show()
                    boxBrd:SetColor(ACC.r, ACC.g, ACC.b, 0.8)
                else
                    chk:Hide()
                    boxBrd:SetColor(0.4, 0.4, 0.4, 0.6)
                end
            end
            SyncCheck()
            row._updateCheck = SyncCheck
            row._lbl = labelFS
            row:SetScript("OnEnter", function()
                if dragState.dragging then return end
                labelFS:SetTextColor(1, 1, 1, 1)
                highlight:SetColorTexture(1, 1, 1, 0.04)
                -- The row's current item (drops shuffle row contents).
                local tipText = row._item.tooltip
                if tipText then CUI.ShowWidgetTooltip(row, tipText) end
            end)
            row:SetScript("OnLeave", function()
                if dragState.dragging then return end
                labelFS:SetTextColor(0.75, 0.75, 0.75, 1)
                highlight:SetColorTexture(1, 1, 1, 0)
                if row._item.tooltip then CUI.HideWidgetTooltip() end
            end)
            row:SetScript("OnClick", function()
                if row._suppressClick then
                    row._suppressClick = nil
                    return
                end
                if dragState.dragging then return end
                setFn(row._item.key, not getFn(row._item.key), MovableKeys())
                SyncCaption()
                for _, r in ipairs(allRows) do
                    if r._updateCheck then r._updateCheck() end
                end
                PaintRows()
            end)
            allRows[#allRows + 1] = row
            return row
        end

        -- Movable rows sit at fixed slots; drops shuffle row CONTENTS, not frames, so slot geometry stays constant for the drag math.
        local movableRows = {}
        local function RefreshMovableRows()
            for idx = 1, #movableRows do
                local rf = movableRows[idx]
                rf._item = movable[idx]
                rf._lbl:SetText(CUI.L(movable[idx].label))
                rf._updateCheck()
            end
        end

        for idx = 1, #movable do
            movableRows[idx] = BuildRow(movable[idx], SlotY(idx), true)
        end
        -- The drag itself (threshold, floating row, insertion line, drop) is the
        -- shared row reorder; a drop shuffles `movable` and repaints the rows.
        CUI.AttachRowReorder(dropMenu, {
            rows = movableRows,
            items = movable,
            itemH = ITEM_HEIGHT,
            slotY = SlotY,
            insLine = insLine,
            state = dragState,
            canReorder = options.canReorder,
            refresh = RefreshMovableRows,
            onDragStart = function()
                for _, rf in ipairs(movableRows) do
                    if rf._lbl then rf._lbl:SetTextColor(0.75, 0.75, 0.75, 1) end
                end
            end,
            onDrop = function(keyList)
                orderChanged = true
                if options.setOrder then options.setOrder(keyList) end
                SyncCaption()
            end,
        })

        -- Divider + fixed (non-draggable) rows below the movable group
        if #fixedItems > 0 then
            local divY = ROWS_BASE_Y - #movable * ITEM_HEIGHT - 3
            local dl = dropMenu:CreateTexture(nil, "ARTWORK")
            dl:SetHeight(1)
            dl:SetPoint("TOPLEFT", dropMenu, "TOPLEFT", 10, divY)
            dl:SetPoint("TOPRIGHT", dropMenu, "TOPRIGHT", -10, divY)
            dl:SetColorTexture(1, 1, 1, 0.08)
            for idx = 1, #fixedItems do
                BuildRow(
                    fixedItems[idx],
                    ROWS_BASE_Y - #movable * ITEM_HEIGHT - DIV_H - (idx - 1) * ITEM_HEIGHT,
                    false
                )
            end
        end

        -- Divider + plain tail rows at the bottom
        if #tail > 0 then
            local tailTop = ROWS_BASE_Y
                - #movable * ITEM_HEIGHT
                - ((#fixedItems > 0) and (DIV_H + #fixedItems * ITEM_HEIGHT) or 0)
            local td = dropMenu:CreateTexture(nil, "ARTWORK")
            td:SetHeight(1)
            td:SetPoint("TOPLEFT", dropMenu, "TOPLEFT", 10, tailTop - 3)
            td:SetPoint("TOPRIGHT", dropMenu, "TOPRIGHT", -10, tailTop - 3)
            td:SetColorTexture(1, 1, 1, 0.08)
            for idx = 1, #tail do
                BuildPlainRow(
                    tail[idx],
                    tailTop - DIV_H - (idx - 1) * ITEM_HEIGHT,
                    options.onTail,
                    options.tailSelected
                )
            end
        end

        -- Every open: the caller's row order (opts.openOrder), then the check
        -- and choice visuals.
        dropMenu:HookScript("OnShow", function()
            if options.openOrder then
                local keyList = options.openOrder()
                local byKey, used, num = {}, {}, 0
                for _, it in ipairs(baseMovable) do
                    byKey[it.key] = it
                end
                if keyList then
                    for _, keyName in ipairs(keyList) do
                        local it = byKey[keyName]
                        if it and not used[keyName] then
                            num = num + 1
                            movable[num] = it
                            used[keyName] = true
                        end
                    end
                end
                for _, it in ipairs(baseMovable) do
                    if not used[it.key] then
                        num = num + 1
                        movable[num] = it
                    end
                end
                RefreshMovableRows()
            end
            for _, r in ipairs(allRows) do
                if r._updateCheck then r._updateCheck() end
            end
            PaintRows()
        end)

        -- One close notification per open/close cycle (reload prompts hook this)
        dropMenu:HookScript("OnHide", function()
            for _, row in ipairs(movableRows) do
                row:_cancelDrag()
            end
            dragState.dragging = false
            insLine:Hide()
            -- Controller cursor: back onto the dropdown button before onClose, so a
            -- prompt it opens can still take the cursor (a no-op once the button is hidden).
            if CUI.PadCursorShown() then CUI.PadFocus(dropdownBtn) end
            local changed = orderChanged
            orderChanged = false
            if options.onClose then options.onClose(changed) end
        end)

        CUI.TrackOverlay(dropMenu)
        dropdownBtn._ddMenu = dropMenu
    end

    local function PaintDropNormal()
        if PoolGen(dropdownBtn) ~= dressGen then return end
        dropCaption:SetTextColor(1, 1, 1, CUI.DD_TXT_A)
        ddBrd:SetColor(1, 1, 1, CUI.DD_BRD_A)
        ddBg:SetColorTexture(CUI.DD_BG_R, CUI.DD_BG_G, CUI.DD_BG_B, CUI.DD_BG_A)
    end
    local function PaintDropHover()
        if PoolGen(dropdownBtn) ~= dressGen then return end
        dropCaption:SetTextColor(1, 1, 1, CUI.DD_TXT_HA)
        ddBrd:SetColor(1, 1, 1, CUI.DD_BRD_HA)
        ddBg:SetColorTexture(CUI.DD_BG_R, CUI.DD_BG_G, CUI.DD_BG_B, CUI.DD_BG_HA)
    end
    dropdownBtn:SetScript("OnEnter", PaintDropHover)
    dropdownBtn:SetScript("OnLeave", function()
        if not (dropMenu and dropMenu:IsShown()) then PaintDropNormal() end
    end)

    local function ShowMenu()
        BuildMenuOnce()
        if dropMenu:IsShown() then
            dropMenu:Hide()
            return
        end
        local btnScale = dropdownBtn:GetEffectiveScale()
        local uiScale = UIParent:GetEffectiveScale()
        dropMenu:SetScale(btnScale / uiScale)
        CUI.SeatDropdownMenu(dropMenu)
        PaintDropHover()
        dropMenu:Show()
        dropMenu:SetScript("OnUpdate", function(self)
            if
                not self:IsMouseOver()
                and not dropdownBtn:IsMouseOver()
                and IsMouseButtonDown("LeftButton")
            then
                self:Hide()
            end
        end)
        -- Controller cursor: into the opened list.
        if CUI.PadCursorShown() then CUI.PadFocus(dropMenu) end
    end
    dropdownBtn:SetScript("OnClick", ShowMenu)
    dropdownBtn:HookScript("OnHide", function()
        if dropMenu then dropMenu:Hide() end
    end)

    local function RefreshAll()
        -- A caller may keep this past a page pass that dressed ddBtn (and with it
        -- the kept menu's rows) for another build.
        if PoolGen(dropdownBtn) ~= dressGen then return end
        SyncCaption()
        for _, r in ipairs(allRows) do
            if r._updateCheck then r._updateCheck() end
        end
        PaintRows()
    end
    return dropdownBtn, RefreshAll
end

-------------------------------------------------------------------------------
--  Slider dropdown: a dropdown button whose menu is a short stack of sliders
--  (label, track and value box per row), several related amounts behind one
--  control. items[i] = { label, tooltip, min, max, step, get = fn -> number,
--  set = fn(v) }; tooltip shows over the row's label. The button reads the
--  labels of the rows away from their minimum ("None" when none, "All" when
--  every one). opts.menuW = the menu width (default 320); the menu opens
--  right-aligned under the button, stays open while a slider is dragged past
--  its edge and runs nothing while closed.
--  Returns: ddBtn, refreshFn
-------------------------------------------------------------------------------
function CUI.BuildSliderDropdown(parentFrame, ddW, fLevel, itemList, options)
    -- Search prebuild on an absorber row: the dropdown indexes nothing, so none is built.
    local standIn = StandIn(parentFrame)
    if standIn then return standIn, standIn end
    local Pix = CUI.PanelPP
    options = options or {}
    local fontFile = CUI.EXPRESSWAY
    local dropdownBtn = CreateFrame("Button", nil, parentFrame)
    -- This build's dress of the button (see BuildVisOptsCBDropdown).
    local dressGen = PoolGen(dropdownBtn)
    Pix.Size(dropdownBtn, ddW, 30)
    dropdownBtn:SetFrameLevel(fLevel)
    local ddBg = dropdownBtn:CreateTexture(nil, "BACKGROUND")
    ddBg:SetAllPoints()
    local ddBrd = CUI.MakeRoundedBorder(dropdownBtn, 1, 1, 1, CUI.DD_BRD_A, ddBg)
    local dropCaption = dropdownBtn:CreateFontString(nil, "OVERLAY")
    dropCaption:SetFont(fontFile, 13, "")
    dropCaption:SetJustifyH("LEFT")
    dropCaption:SetWordWrap(false)
    dropCaption:SetMaxLines(1)
    dropCaption:SetPoint("LEFT", dropdownBtn, "LEFT", 12, 0)
    local arrow = CUI.MakeDropdownArrow(dropdownBtn, 12, Pix)
    dropCaption:SetPoint("RIGHT", arrow, "LEFT", -5, 0)

    local function PaintEntry(hover)
        if PoolGen(dropdownBtn) ~= dressGen then return end
        dropCaption:SetTextColor(1, 1, 1, hover and CUI.DD_TXT_HA or CUI.DD_TXT_A)
        ddBrd:SetColor(1, 1, 1, hover and CUI.DD_BRD_HA or CUI.DD_BRD_A)
        ddBg:SetColorTexture(CUI.DD_BG_R, CUI.DD_BG_G, CUI.DD_BG_B, hover and CUI.DD_BG_HA or CUI.DD_BG_A)
    end
    PaintEntry(false)

    local function SyncCaption()
        if PoolGen(dropdownBtn) ~= dressGen then return end
        local nameList = {}
        for _, entry in ipairs(itemList) do
            local val = entry.get()
            if val and val ~= (entry.min or 0) then nameList[#nameList + 1] = CUI.L(entry.label) end
        end
        if #nameList == 0 then
            dropCaption:SetText(CUI.L("None"))
        elseif #nameList == #itemList then
            dropCaption:SetText(CUI.L("All"))
        else
            dropCaption:SetText(table.concat(nameList, ", "))
        end
    end
    SyncCaption()

    local dropMenu, refreshers
    local ROW_H, PAD, TRACK_W = 34, 6, 140
    local function BuildMenuOnce()
        if dropMenu then return end
        -- One menu per dropdown button for the session: a build that dresses the
        -- button again gets this frame back here, reset to new.
        dropMenu = PoolKept(dropdownBtn, "sliderMenu", "Frame", CUI.OverlayParent())
        dropMenu:SetFrameStrata("FULLSCREEN_DIALOG")
        dropMenu:SetFrameLevel(200)
        dropMenu:SetClampedToScreen(true)
        dropMenu:EnableMouse(true)
        -- The page under the menu must not scroll away from it.
        dropMenu:EnableMouseWheel(true)
        dropMenu:SetScript("OnMouseWheel", function() end)
        dropMenu:SetSize(options.menuW or 320, PAD * 2 + #itemList * ROW_H)
        dropMenu:SetPoint("TOPRIGHT", dropdownBtn, "BOTTOMRIGHT", 0, -2)
        dropMenu:Hide()
        -- Controller cursor: the menu blocks what is under it but is not a stop
        -- itself; Cancel clicks the button (it toggles the menu closed).
        if CUI.PadCP() then
            CUI.PadHint(dropMenu, "nodepass")
            dropMenu.CloseButton = dropdownBtn
        end
        local mBg = dropMenu:CreateTexture(nil, "BACKGROUND")
        mBg:SetAllPoints()
        mBg:SetColorTexture(CUI.DD_BG_R, CUI.DD_BG_G, CUI.DD_BG_B, CUI.DD_BG_HA)
        CUI.MakeRoundedBorder(dropMenu, 1, 1, 1, CUI.DD_BRD_A, mBg, nil, true)

        refreshers = {}
        for idx, entry in ipairs(itemList) do
            local cursorY = -(PAD + (idx - 1) * ROW_H)
            local row = CreateFrame("Frame", nil, dropMenu)
            row:SetHeight(ROW_H)
            row:SetPoint("TOPLEFT", dropMenu, "TOPLEFT", 1, cursorY)
            row:SetPoint("TOPRIGHT", dropMenu, "TOPRIGHT", -1, cursorY)
            row:SetFrameLevel(dropMenu:GetFrameLevel() + 2)
            local track, valBox, refresh = CUI.BuildSliderCore(
                row,
                TRACK_W,
                4,
                14,
                40,
                24,
                12,
                CUI.SL_INPUT_A,
                entry.min or 0,
                entry.max or 100,
                entry.step or 1,
                entry.get,
                function(val)
                    -- Attributed to the button: its row carries the override
                    -- capture config, the menu sits on the overlay parent. The
                    -- slot is taken before the setter runs: one that rebuilds
                    -- the page can dress ddBtn for another slot.
                    local snap = CUI._SOAttribution(dropdownBtn)
                    entry.set(val)
                    SyncCaption()
                    CUI._NotifySettingWrite(dropdownBtn, snap)
                end,
                true
            )
            Pix.Point(valBox, "RIGHT", row, "RIGHT", -12, 0)
            Pix.Point(track, "RIGHT", valBox, "LEFT", -12, 0)
            refreshers[idx] = refresh
            local labelFS = row:CreateFontString(nil, "OVERLAY")
            labelFS:SetFont(fontFile, 13, "")
            labelFS:SetTextColor(1, 1, 1, 0.85)
            labelFS:SetJustifyH("LEFT")
            labelFS:SetWordWrap(false)
            labelFS:SetPoint("LEFT", row, "LEFT", 14, 0)
            labelFS:SetPoint("RIGHT", track, "LEFT", -12, 0)
            labelFS:SetText(CUI.L(entry.label))
            if entry.tooltip then
                row:EnableMouse(true)
                row:SetScript("OnEnter", function() CUI.ShowWidgetTooltip(labelFS, entry.tooltip) end)
                row:SetScript("OnLeave", function() CUI.HideWidgetTooltip() end)
            end
            if idx < #itemList then
                local div = row:CreateTexture(nil, "ARTWORK")
                div:SetColorTexture(1, 1, 1, 0.06)
                div:SetHeight(1)
                div:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 10, 0)
                div:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -10, 0)
            end
        end

        dropMenu:SetScript("OnHide", function(self)
            self:SetScript("OnUpdate", nil)
            if CUI._openDropdownMenu == self then CUI._openDropdownMenu = nil end
            PaintEntry(dropdownBtn:IsMouseOver())
            -- Controller cursor: back onto the button (a no-op once that is hidden too).
            if CUI.PadCursorShown() then CUI.PadFocus(dropdownBtn) end
        end)
        if CUI.PadCP() then CUI.TrackOverlay(dropMenu) end
    end

    -- Whether the button scrolls with the page (decided on the first open).
    local inScroll
    local function ShowMenu()
        BuildMenuOnce()
        if dropMenu:IsShown() then
            dropMenu:Hide()
            return
        end
        for idx = 1, #refreshers do
            refreshers[idx]()
        end
        -- The menu lives on the overlay parent: match the panel's scale.
        dropMenu:SetScale(dropdownBtn:GetEffectiveScale() / UIParent:GetEffectiveScale())
        CUI.SeatDropdownMenu(dropMenu)
        PaintEntry(true)
        dropMenu:Show()
        CUI._openDropdownMenu = dropMenu
        local sf = CUI._scrollFrame
        if inScroll == nil then
            inScroll = false
            local childFrame = sf and sf.GetScrollChild and sf:GetScrollChild()
            local p = dropdownBtn:GetParent()
            while childFrame and p do
                if p == childFrame then
                    inScroll = true
                    break
                end
                p = p:GetParent()
            end
        end
        dropMenu:SetScript("OnUpdate", function(self)
            -- A left click outside the menu and its button closes it; never
            -- mid-drag, so a slider dragged past the menu's edge keeps it.
            if
                not CUI._sliderDragging
                and IsMouseButtonDown("LeftButton")
                and not self:IsMouseOver()
                and not dropdownBtn:IsMouseOver()
            then
                self:Hide()
                return
            end
            -- The button scrolled out of the page's visible area.
            if inScroll then
                local topY, bot, b = sf:GetTop(), sf:GetBottom(), dropdownBtn:GetBottom()
                if topY and bot and b and (b < bot or b > topY) then self:Hide() end
            end
        end)
        if CUI.PadCursorShown() then CUI.PadFocus(dropMenu) end
    end
    dropdownBtn:SetScript("OnEnter", function() PaintEntry(true) end)
    dropdownBtn:SetScript("OnLeave", function()
        if not (dropMenu and dropMenu:IsShown()) then PaintEntry(false) end
    end)
    dropdownBtn:SetScript("OnClick", ShowMenu)
    dropdownBtn:HookScript("OnHide", function()
        if dropMenu then dropMenu:Hide() end
    end)

    local function RefreshAll()
        -- A caller may keep this past a page pass that dressed ddBtn (and with it
        -- the kept menu's sliders) for another build.
        if PoolGen(dropdownBtn) ~= dressGen then return end
        SyncCaption()
        if dropMenu and dropMenu:IsShown() then
            for idx = 1, #refreshers do
                refreshers[idx]()
            end
        end
    end
    return dropdownBtn, RefreshAll
end
