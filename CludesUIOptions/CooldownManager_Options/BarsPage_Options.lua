if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CooldownManager_Options\BarsPage_Options.lua
--  Cooldown Manager options: the CDM Bars page (BuildCDMBarsPage). Definitions
--  only; the shared helpers come from ns._CDMO_OptEnv (filled by
--  CUI_CooldownManager_Options.lua), the preview from LivePreview_Options.lua.
-------------------------------------------------------------------------------
local mod = CludesUI._ModuleNS["CludesUICooldownManager"]
if not mod then return end -- module disabled: no options page

-- The options page pool (CludesUI_FramePool.lua): a frame made under a pool
-- host (a reused page or header, a kept menu) is handed out again reset to
-- fresh; anywhere else this is the plain CreateFrame. The bar menu is one kept
-- frame for the session (PoolKept), dressed again on each open; PoolBegin
-- hands its rows out again in place when the open menu draws itself again.
local CreateFrame = CludesUI._Pool.CreateFrame
local PoolKept, PoolBegin = CludesUI._Pool.Kept, CludesUI._Pool.Begin

-- Live preview on mount and dismount (skyriding swaps the icons the preview
-- copies). One event frame for the session, registered only while the CDM
-- Bars page shows (its page frame's OnShow and OnHide), so nothing listens
-- while the page is hidden. Only the preview is drawn again: the rows below
-- it do not change with the mount.
local mountActive = {}
function mountActive.OnEvent()
    local environ = mod._CDMO_OptEnv
    local preview = environ and (environ.optState._cdmPreview or CludesUI._cdmHeaderPreview)
    if preview and preview:IsVisible() then environ.UpdateCDMPreviewAndResize() end
end
function mountActive.Arm() mountActive.frame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED") end
function mountActive.Disarm() mountActive.frame:UnregisterAllEvents() end

local function BuildCDMBarsPage(page, hostFrame, yOffset)
    local environ = mod._CDMO_OptEnv
    local AnyIconAlwaysShowOn, BuildKeybindStyleControls, DB, durationPositionOrder =
        environ.AnyIconAlwaysShowOn,
        environ.BuildKeybindStyleControls,
        environ.DB,
        environ.durationPositionOrder
    local durationPositionValues, FONT_PATH, GetCDMOptOutline, optionState =
        environ.durationPositionValues, environ.FONT_PATH, environ.GetCDMOptOutline, environ.optState
    local Pix, Refresh, SelectedCDMBar, UpdateCDMPreview =
        environ.PP, environ.Refresh, environ.SelectedCDMBar, environ.UpdateCDMPreview
    local UpdateCDMPreviewAndResize = environ.UpdateCDMPreviewAndResize
    local BuildCDMLivePreview = mod.CDMO_BuildCDMLivePreview
    local W = CludesUI.Widgets
    local cursorY = yOffset
    local _, height, heading

    local profile = DB()
    if not profile or not profile.cdmBars then return math.abs(yOffset) end

    local barList = profile.cdmBars.bars
    if not barList or #barList == 0 then return math.abs(yOffset) end

    -- Clamp selection
    if optionState.selectedCDMBarIndex < 1 then optionState.selectedCDMBarIndex = 1 end
    if optionState.selectedCDMBarIndex > #barList then optionState.selectedCDMBarIndex = #barList end

    local barInfo = barList[optionState.selectedCDMBarIndex]
    if not barInfo then return math.abs(yOffset) end

    -- Tag every option registered by this build with the selected bar, so a global-search
    -- jump to a bar-specific setting (e.g. HoverCast/FocusKick-only rows) restores this exact
    -- bar first via CludesUI._setCDMBar -- otherwise the matched row wouldn't exist under whatever bar is selected when the player jumps there.
    CludesUI._buildingSelector = { setter = CludesUI._setCDMBar, key = barInfo.key }

    -- Capture the key so closures always look up the CURRENT bar data from the profile (no
    -- stale references across reorders/rebuilds). Searchable single-select "Sync From"
    -- source-spec dropdown; defaults to the current spec. Reuses one frame on ns so repeated opens don't leak.
    local function ShowRPTSourcePicker(defaultKey, onSelect)
        -- All-classes source list (current class always + other classes that have data), so the source isn't limited to the player's class.
        local details = mod.GetAllCDMSpecInfo and mod.GetAllCDMSpecInfo()
            or (mod.GetCDMSpecInfo and mod.GetCDMSpecInfo())
            or {}
        local DDW = 280
        local ROW_H = 30
        local MAX_VISIBLE = 10 -- rows shown before the list scrolls
        local MAX_LIST_H = MAX_VISIBLE * ROW_H
        local SrcPopup = mod._rptSrcPopup
        if not SrcPopup then
            SrcPopup = { rows = {} }
            mod._rptSrcPopup = SrcPopup
            local scale = (CludesUI.GetPopupScale()) or 1
            local shade = CreateFrame("Frame", nil, UIParent)
            shade:SetFrameStrata("FULLSCREEN_DIALOG")
            shade:SetAllPoints(UIParent)
            shade:EnableMouse(true)
            shade:Hide()
            local dt = shade:CreateTexture(nil, "BACKGROUND")
            dt:SetAllPoints()
            dt:SetColorTexture(0, 0, 0, 0.25)
            local dialog = CreateFrame("Frame", nil, shade)
            dialog:SetScale(scale)
            dialog:SetFrameStrata("FULLSCREEN_DIALOG")
            dialog:SetFrameLevel(shade:GetFrameLevel() + 10)
            Pix.Size(dialog, DDW + 24, 320)
            dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
            dialog:EnableMouse(true)
            local backdrop = dialog:CreateTexture(nil, "BACKGROUND")
            backdrop:SetAllPoints()
            backdrop:SetColorTexture(0.062, 0.070, 0.082, 1)
            SrcPopup.brd = CludesUI.MakeRoundedBorder(dialog, 1, 1, 1, 0.15, backdrop)
            local titleFs = CludesUI.MakeFont(dialog, 15, nil, 1, 1, 1, 1)
            titleFs:SetPoint("TOP", dialog, "TOP", 0, -14)
            titleFs:SetText("Sync From")
            local subFs = CludesUI.MakeFont(dialog, 11, nil, 1, 1, 1, 0.45)
            subFs:SetPoint("TOP", titleFs, "BOTTOM", 0, -4)
            subFs:SetWidth(DDW)
            subFs:SetJustifyH("CENTER")
            subFs:SetText("Choose the spec to copy trinkets, pots, racials & buff presets from")
            local search = CreateFrame("EditBox", nil, dialog)
            Pix.Size(search, DDW, 26)
            search:SetPoint("TOP", subFs, "BOTTOM", 0, -10)
            search:SetFont(FONT_PATH, 12, "")
            search:SetTextColor(1, 1, 1, 0.9)
            search:SetJustifyH("LEFT")
            search:SetAutoFocus(false)
            search:SetMaxLetters(30)
            search:SetTextInsets(6, 6, 0, 0)
            local sbg = search:CreateTexture(nil, "BACKGROUND")
            sbg:SetAllPoints()
            sbg:SetColorTexture(0, 0, 0, 0.4)
            CludesUI.MakeRoundedBorder(search, 1, 1, 1, 0.10, sbg)
            local ph = search:CreateFontString(nil, "OVERLAY")
            ph:SetFont(FONT_PATH, 11, "")
            ph:SetTextColor(0.5, 0.5, 0.5, 0.6)
            ph:SetPoint("LEFT", search, "LEFT", 6, 0)
            ph:SetText("Search...")
            search:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
            -- Scrollable, capped list: a long cross-class spec list scrolls
            -- (mousewheel) inside a fixed max height instead of running off the
            -- screen. A thin thumb on the right shows when there is more to see.
            local scroller = CreateFrame("ScrollFrame", nil, dialog)
            scroller:SetPoint("TOPLEFT", search, "BOTTOMLEFT", 0, -8)
            scroller:SetPoint("RIGHT", dialog, "RIGHT", -12, 0)
            scroller:EnableMouseWheel(true)
            local listF = CreateFrame("Frame", nil, scroller)
            listF:SetWidth(DDW)
            scroller:SetScrollChild(listF)
            local track = scroller:CreateTexture(nil, "ARTWORK")
            track:SetWidth(3)
            track:SetColorTexture(1, 1, 1, 0.06)
            track:SetPoint("TOPRIGHT", scroller, "TOPRIGHT", -1, 0)
            track:SetPoint("BOTTOMRIGHT", scroller, "BOTTOMRIGHT", -1, 0)
            track:Hide()
            local thumb = scroller:CreateTexture(nil, "OVERLAY")
            thumb:SetWidth(3)
            thumb:SetColorTexture(1, 1, 1, 0.25)
            thumb:Hide()
            local function UpdateThumb()
                local visibleH, fullH = scroller:GetHeight(), listF:GetHeight()
                local maxScroll = math.max(0, fullH - visibleH)
                if maxScroll <= 0 then
                    track:Hide()
                    thumb:Hide()
                    return
                end
                track:Show()
                thumb:Show()
                local thumbH = math.max(20, visibleH * visibleH / fullH)
                thumb:SetHeight(thumbH)
                local frac = (scroller:GetVerticalScroll() or 0) / maxScroll
                thumb:ClearAllPoints()
                thumb:SetPoint("TOPRIGHT", track, "TOPRIGHT", 0, -frac * (visibleH - thumbH))
            end
            scroller:SetScript("OnMouseWheel", function(self, delta)
                local maxScroll = math.max(0, listF:GetHeight() - self:GetHeight())
                if maxScroll <= 0 then return end
                local new =
                    math.max(0, math.min(maxScroll, (self:GetVerticalScroll() or 0) - delta * ROW_H * 2))
                self:SetVerticalScroll(new)
                UpdateThumb()
            end)
            shade:SetScript("OnMouseDown", function() shade:Hide() end)
            dialog:SetScript("OnMouseDown", function() end)
            SrcPopup.dimmer, SrcPopup.popup, SrcPopup.search, SrcPopup.ph, SrcPopup.list, SrcPopup.DDW =
                shade, dialog, search, ph, listF, DDW
            SrcPopup.scroll, SrcPopup.updateThumb = scroller, UpdateThumb
        end

        local function Rebuild()
            local filter = (SrcPopup.search:GetText() or ""):lower()
            local isShown = 0
            for _, row in ipairs(SrcPopup.rows) do
                row:Hide()
            end
            for _, s in ipairs(details) do
                local nm = s.name or ""
                if filter == "" or nm:lower():find(filter, 1, true) then
                    isShown = isShown + 1
                    local r = SrcPopup.rows[isShown]
                    if not r then
                        r = CreateFrame("Button", nil, SrcPopup.list)
                        Pix.Size(r, SrcPopup.DDW, ROW_H)
                        r:SetFrameLevel(SrcPopup.list:GetFrameLevel() + 1)
                        local highlight = r:CreateTexture(nil, "ARTWORK")
                        highlight:SetAllPoints()
                        highlight:SetColorTexture(1, 1, 1, 0.06)
                        highlight:Hide()
                        r._hl = highlight
                        local iconTex = r:CreateTexture(nil, "ARTWORK")
                        iconTex:SetSize(20, 20)
                        iconTex:SetPoint("LEFT", r, "LEFT", 8, 0)
                        r._ic = iconTex
                        local tx = CludesUI.MakeFont(r, 13, nil, 1, 1, 1, 0.85)
                        tx:SetPoint("LEFT", iconTex, "RIGHT", 8, 0)
                        r._tx = tx
                        r:SetScript("OnEnter", function(self) self._hl:Show() end)
                        r:SetScript("OnLeave", function(self)
                            if not self._isDefault then self._hl:Hide() end
                        end)
                        SrcPopup.rows[isShown] = r
                    end
                    r:ClearAllPoints()
                    r:SetPoint("TOPLEFT", SrcPopup.list, "TOPLEFT", 0, -((isShown - 1) * ROW_H))
                    if s.icon then
                        r._ic:SetTexture(s.icon)
                        r._ic:Show()
                    else
                        r._ic:Hide()
                    end
                    r._tx:SetText(nm)
                    r._isDefault = (s.key == defaultKey)
                    r._hl:SetShown(r._isDefault)
                    local barKey = s.key
                    r:SetScript("OnClick", function()
                        SrcPopup.dimmer:Hide()
                        if onSelect then onSelect(barKey) end
                    end)
                    r:Show()
                end
            end
            local listH = math.max(ROW_H, isShown * ROW_H)
            SrcPopup.list:SetHeight(listH)
            local visibleH = math.min(listH, MAX_LIST_H)
            SrcPopup.scroll:SetHeight(visibleH)
            SrcPopup.popup:SetHeight(110 + visibleH)
            -- Rebuilt while shown (search typing): refit the outline's bottom edge.
            SrcPopup.brd:Fit()
            SrcPopup.scroll:SetVerticalScroll(0)
            if SrcPopup.updateThumb then SrcPopup.updateThumb() end
        end
        SrcPopup.search:SetScript("OnTextChanged", function(self)
            SrcPopup.ph:SetShown((self:GetText() or "") == "")
            Rebuild()
        end)
        SrcPopup.search:SetText("")
        SrcPopup.ph:Show()
        Rebuild()
        SrcPopup.dimmer:Show()
        C_Timer.After(0.05, function() SrcPopup.search:SetFocus() end)
    end

    -- Sync Generic CDs/Buffs across specs (per profile): trinkets, pots, racials
    -- and buff-bar presets (Bloodlust, etc.). First-time setup picks a SOURCE spec
    -- (searchable dropdown, default current spec), then a spec picker with the
    -- source locked ON (auto-checked, can't be deselected).
    local function DoRPTSyncSetup()
        local curKey = mod.GetActiveSpecKey and mod.GetActiveSpecKey()
        ShowRPTSourcePicker(curKey, function(sourceKey)
            local srcName = sourceKey
            local srcID = tonumber(sourceKey)
            if srcID then
                -- WoW Forever has no by-ID spec global; its spec-ID name
                -- lookups name the source there instead of the raw key.
                local num
                if GetSpecializationInfoByID then
                    num = select(2, GetSpecializationInfoByID(srcID))
                elseif GetSpecializationNameForSpecID then
                    num = GetSpecializationNameForSpecID(srcID)
                elseif GetSpecializationInfoForSpecID then
                    num = select(2, GetSpecializationInfoForSpecID(srcID))
                end
                if num and num ~= "" then srcName = num end
            end
            -- WoW Forever: a key names a whole class there.
            if CludesUI.IS_FOREVER then
                local t = CludesUI.SpecClassOf(tonumber(sourceKey))
                if t then srcName = CludesUI.ForeverClassName(t) end
            end
            local specs = mod.GetCDMSpecInfo and mod.GetCDMSpecInfo() or {}
            for _, spec in ipairs(specs) do
                spec.checked = (spec.key == sourceKey)
            end
            CludesUI:ShowCDMSpecPickerPopup({
                title = "Sync Generic CDs/Buffs",
                -- The grid lists every class (a profile is shared across
                -- characters), so an alt's specs are ticked from here; say
                -- so, or it reads as "this character's specs" only. Keep the
                -- subtitle to one line so it clears Check All / Uncheck All.
                subtitle = CludesUI.Lf(
                    "Choose which specs sync with %1$s, including your alts' specs (the source is always included)",
                    srcName
                ),
                confirmText = "Sync",
                specs = specs,
                lockedSpecs = {
                    [sourceKey] = "This is the spec you're syncing from -- it's always included.",
                },
                foreverActiveKey = curKey,
                onConfirm = function(selectedSpecs)
                    selectedSpecs[sourceKey] = true
                    local cnt = 0
                    for _, value in pairs(selectedSpecs) do
                        if value then cnt = cnt + 1 end
                    end
                    if cnt <= 1 then
                        -- Only the source picked -> nothing to sync; clear any
                        -- existing sync and SAY so (one ticked spec is the
                        -- natural first guess at "sync FROM this spec").
                        if mod.ClearRPTSync then mod.ClearRPTSync() end
                        CludesUI.Print(
                            "|cff4cc9f0CludesUI CDM:|r "
                                .. CludesUI.L(
                                    "Sync cleared -- only one spec was selected. Tick at least two specs (including other characters' specs) to sync between them."
                                )
                        )
                        CludesUI:RefreshPage(true)
                        return
                    end
                    if mod.SetupRPTSync then mod.SetupRPTSync(selectedSpecs, sourceKey) end
                    if mod.FullCDMRebuild then mod.FullCDMRebuild("profile_import") end
                    -- Which bar each entry sits on is synced; its SLOT is not
                    -- (every spec keeps its own ordering) -- easily read as a
                    -- bug, so the print states it explicitly.
                    CludesUI.Print(
                        "|cff4cc9f0CludesUI CDM:|r "
                            .. CludesUI.Lf(
                                "Syncing generic CDs/buffs across %d specs. Icon order is not synced -- each spec keeps its own arrangement.",
                                cnt
                            )
                    )
                    CludesUI:RefreshPage(true)
                end,
            })
        end)
    end

    -- Edit an existing sync: open the spec picker directly (no source step),
    -- with the currently-synced specs pre-checked. Unchecking a spec drops it
    -- from the sync (its trinkets/pots/racials/buff presets are left as-is);
    -- checking a new spec folds it in. Falling to one-or-zero specs clears it.
    local function EditRPTSync()
        -- Pre-check EVERY synced spec, not just the current class's: a sync
        -- can span other classes (one profile across characters), and the
        -- grid shows all classes -- seed from the STORED sync set, not from
        -- GetCDMSpecInfo (which only returns the current class's specs).
        local existing = mod.GetRPTSyncSpecs and mod.GetRPTSyncSpecs()
        local specs = {}
        if existing then
            for barKey in pairs(existing) do
                specs[#specs + 1] = { key = barKey, checked = true }
            end
        end
        CludesUI:ShowCDMSpecPickerPopup({
            title = "Sync Generic CDs/Buffs",
            subtitle = "Uncheck a spec to remove it from the sync. Removed specs keep their current trinkets, pots, racials & buff presets.",
            confirmText = "Save",
            specs = specs,
            foreverActiveKey = CludesUI.IS_FOREVER and mod.GetActiveSpecKey and mod.GetActiveSpecKey() or nil,
            onConfirm = function(selectedSpecs)
                local cnt = 0
                for _, value in pairs(selectedSpecs) do
                    if value then cnt = cnt + 1 end
                end
                if cnt <= 1 then
                    -- One or zero specs left -> nothing to sync; clear it.
                    -- Announced for the same reason as the setup path: the
                    -- sync is discarded here, not merely left unchanged.
                    if mod.ClearRPTSync then mod.ClearRPTSync() end
                    CludesUI.Print(
                        "|cff4cc9f0CludesUI CDM:|r "
                            .. CludesUI.L("Sync cleared -- fewer than two specs remained selected.")
                    )
                    CludesUI:RefreshPage(true)
                    return
                end
                if mod.UpdateRPTSyncSpecs then mod.UpdateRPTSyncSpecs(selectedSpecs) end
                if mod.FullCDMRebuild then mod.FullCDMRebuild("profile_import") end
                CludesUI:RefreshPage(true)
            end,
        })
    end

    -- Route the third action button: edit the live sync, or set up a new one.
    local function DoRPTSync()
        if mod.HasRPTSync and mod.HasRPTSync() then
            EditRPTSync()
        else
            DoRPTSyncSetup()
        end
    end

    -- Action buttons: repopulate + open Blizzard CDM + sync generic CDs/buffs
    -- (trinkets, pots, racials & buff presets across specs).
    -- The third button keeps the same label whether or not a sync exists;
    -- DoRPTSync routes to setup vs edit based on ns.HasRPTSync().
    _, height = W:WideTripleButton(
        hostFrame,
        "Repopulate from Blizzard CDM",
        "Open Blizzard CDM",
        "Sync Generic CDs/Buffs",
        cursorY,
        function()
            CludesUI:ShowConfirmPopup({
                title = "Repopulate Bars",
                message = "This will reset all default bar spell assignments for the current spec to match Blizzard's CDM layout. Spells you added yourself (presets, custom IDs and racials) are kept. Continue?",
                confirmText = "Repopulate",
                cancelText = "Cancel",
                onConfirm = function()
                    if mod.RepopulateFromBlizzard then mod.RepopulateFromBlizzard() end
                    C_Timer.After(0.15, function()
                        if optionState._cdmPreview and optionState._cdmPreview.Update then
                            optionState._cdmPreview:Update()
                        end
                        UpdateCDMPreviewAndResize()
                    end)
                end,
            })
        end,
        function()
            local edge = SelectedCDMBar()
            local barType = edge and (edge.barType or edge.key) or "cooldowns"
            local isBuff = (barType == "buffs")
            if mod.OpenBlizzardCDMTab then mod.OpenBlizzardCDMTab(isBuff) end
        end,
        DoRPTSync,
        225
    )
    cursorY = cursorY - height

    -- A change to a bar's size inputs (rows, icon size, spacing, shape)
    -- drops the matched-axis dimensions the layout pass caches, so they are
    -- worked out again.
    local function ClearMatchDims(bar)
        bar._matchIconPhys = nil
        bar._matchExtraPixels = nil
        bar._matchStride = nil
        bar._matchExtraPixelsH = nil
        bar._matchStrideH = nil
    end

    -- After a change: the bars built again and the live preview redrawn
    -- (resize: the preview's own size may have changed too).
    local function RebuildBars(resize)
        mod.BuildAllCDMBars()
        Refresh()
        if resize then
            UpdateCDMPreviewAndResize()
        else
            UpdateCDMPreview()
        end
    end

    local barId = barInfo.key
    local function BarList()
        local profile = DB()
        if not profile or not profile.cdmBars or not profile.cdmBars.bars then return barInfo end
        for _, bar in ipairs(profile.cdmBars.bars) do
            if bar.key == barId then return bar end
        end
        return barInfo
    end
    -- Row accessors over BD(): a key read (or its default) and written.
    local function BDField(barKey)
        return function(value) BarList()[barKey] = value end
    end
    local function BDFieldOr(barKey, default)
        return function() return BarList()[barKey] or default end
    end
    local function BDFieldIs(barKey)
        return function() return BarList()[barKey] == true end
    end
    local function BDFieldGet(barKey)
        return function() return BarList()[barKey] end
    end
    -- Row accessors over BD(): a key read (or its default) and written.
    local function BDField(barKey)
        return function(value) BarList()[barKey] = value end
    end
    local function BDFieldOr(barKey, default)
        return function() return BarList()[barKey] or default end
    end
    local function BDFieldGet(barKey)
        return function() return BarList()[barKey] end
    end

    local isDefault = (barInfo.key == "cooldowns" or barInfo.key == "utility" or barInfo.key == "buffs")
    local isBuffBar = mod.IsBarBuffFamily(barInfo)
    -- FocusKick is the special nameplate-anchored bar. Most options panel
    -- sections are hidden for it; only Icon Display + a custom Nameplate
    -- Anchor row are shown.
    local focusKickBar = (barInfo.key == "focuskick")

    -------------------------------------------------------------------
    --  CONTENT HEADER  (dropdown + live preview)
    -------------------------------------------------------------------
    CludesUI:ClearContentHeader()
    optionState._cdmPreview = nil

    optionState._cdmHeaderBuilder = function(heading, hdrW)
        local PAD = CludesUI.CONTENT_PAD or 10
        local PV_PAD = 10
        local fy = -20

        -- Bar selector dropdown (custom-built to support delete buttons)
        local DD_H = 34
        local ddW = 350

        local DDS = CludesUI.DD_STYLE
        local mBgR = DDS.BG_R
        local mBgG = DDS.BG_G
        local mBgB = DDS.BG_B
        local mBgA = DDS.BG_A
        local mBgHA = DDS.BG_HA
        local mBrdA = DDS.BRD_A
        local mBrdHA = DDS.BRD_HA or 0.30
        local mTxtA = DDS.TXT_A
        local mTxtHA = DDS.TXT_HA or 1
        local hlA = DDS.ITEM_HL_A
        local selA = DDS.ITEM_SEL_A
        local tDimR = CludesUI.TEXT_DIM_R or 0.7
        local tDimG = CludesUI.TEXT_DIM_G or 0.7
        local tDimB = CludesUI.TEXT_DIM_B or 0.7
        local tDimA = CludesUI.TEXT_DIM_A or 0.85
        local ITEM_H = 26
        local MEDIA = "Interface\\AddOns\\CludesUI\\media\\"
        local ICON_SZ = 14
        -- The bars every profile has; any other (Focus Kick aside) is custom.
        local BUILT_IN = { cooldowns = true, utility = true, buffs = true }

        -- Dropdown button
        local dropdownBtn = CreateFrame("Button", nil, heading)
        Pix.Size(dropdownBtn, ddW, DD_H)
        dropdownBtn:SetFrameLevel(heading:GetFrameLevel() + 5)
        local ddBg = dropdownBtn:CreateTexture(nil, "BACKGROUND")
        ddBg:SetAllPoints()
        ddBg:SetColorTexture(mBgR, mBgG, mBgB, mBgA)
        local ddBrd = CludesUI.MakeRoundedBorder(dropdownBtn, 1, 1, 1, mBrdA, ddBg)
        local dropCaption = dropdownBtn:CreateFontString(nil, "OVERLAY")
        dropCaption:SetFont(FONT_PATH, 13, GetCDMOptOutline())
        dropCaption:SetAlpha(mTxtA)
        dropCaption:SetJustifyH("LEFT")
        dropCaption:SetWordWrap(false)
        dropCaption:SetMaxLines(1)
        dropCaption:SetPoint("LEFT", dropdownBtn, "LEFT", 12, 0)
        -- Arrow (standard CludesUI dropdown arrow)
        local arrow = CludesUI.MakeDropdownArrow(dropdownBtn, 12, CludesUI.PanelPP)
        dropCaption:SetPoint("RIGHT", arrow, "LEFT", -5, 0)

        local function UpdateDDLabel()
            local edge = barList[optionState.selectedCDMBarIndex]
            local labelText = edge and CludesUI.L(edge.name or edge.key) or ""
            dropCaption:SetText(labelText)
        end
        UpdateDDLabel()

        -- Custom-bar display order for THIS dropdown only: a pure VIEW over
        -- p.cdmBars.bars. The bars array is NEVER reordered -- stored
        -- numeric bar paths (unlock/override data) and selectedCDMBarIndex
        -- depend on array positions. Saved key list first (keys whose bar
        -- no longer exists are dropped), then any custom bars not yet
        -- listed, in array order (new bars append). Same self-healing
        -- contract as the RF party Class Order list. Built-ins (cooldowns/
        -- utility/buffs/focuskick) are never part of the order list.
        local function CustomBarDisplayOrder()
            local sequence, seen, byKey = {}, {}, {}
            for _, bar in ipairs(barList) do
                if bar.key and not bar.isGhostBar and not BUILT_IN[bar.key] and bar.key ~= "focuskick" then
                    byKey[bar.key] = bar
                end
            end
            local saved = profile.cdmBars.customBarMenuOrder
            if type(saved) == "table" then
                for _, keyName in ipairs(saved) do
                    if byKey[keyName] and not seen[keyName] then
                        sequence[#sequence + 1] = keyName
                        seen[keyName] = true
                    end
                end
            end
            for _, bar in ipairs(barList) do
                local keyName = bar.key
                if keyName and byKey[keyName] and not seen[keyName] then
                    sequence[#sequence + 1] = keyName
                    seen[keyName] = true
                end
            end
            return sequence, byKey
        end

        -- Custom dropdown menu
        local ddMenu
        local function BuildDDMenu(redraw)
            local dropMenu
            local inPlace = redraw and ddMenu ~= nil
            if inPlace then
                -- Drawn again in place (a reorder drop): the open menu keeps
                -- its frame and hands its rows out again in creation order.
                dropMenu = ddMenu
                PoolBegin(dropMenu)
            else
                if ddMenu then
                    ddMenu:Hide()
                    ddMenu = nil
                end
                -- One menu frame for the session, dressed again on every open.
                dropMenu = PoolKept(optionState, "cdmBarMenu", "Frame", UIParent)
            end
            dropMenu:SetFrameStrata("FULLSCREEN_DIALOG")
            dropMenu:SetFrameLevel(300)
            dropMenu:SetClampedToScreen(true)
            dropMenu:SetPoint("TOPLEFT", dropdownBtn, "BOTTOMLEFT", 0, -2)
            dropMenu:SetPoint("TOPRIGHT", dropdownBtn, "BOTTOMRIGHT", 0, -2)
            local backdrop = dropMenu:CreateTexture(nil, "BACKGROUND")
            backdrop:SetAllPoints()
            backdrop:SetColorTexture(mBgR, mBgG, mBgB, mBgHA)
            CludesUI.MakeRoundedBorder(dropMenu, 1, 1, 1, mBrdA, backdrop, nil, true)

            local menuH = 4
            local customCount = 0
            for _, bar in ipairs(barList) do
                if not BUILT_IN[bar.key] and not bar.isGhostBar then customCount = customCount + 1 end
            end

            -- Display list: array order, except CUSTOM bars render in the saved
            -- dropdown order (CustomBarDisplayOrder). All customs emit as one block
            -- at the first custom bar's array position, so an empty/absent saved
            -- order reproduces the old listing byte-identically. Every entry
            -- carries its REAL array index (realIdx) -- selection and all other
            -- consumers keep using array positions; only this listing is reordered.
            local ordKeys, ordByKey = CustomBarDisplayOrder()
            local reorderable = #ordKeys >= 2
            local displayList, realIdx = {}, {}
            do
                local customsEmitted = false
                for bIdx, bar in ipairs(barList) do
                    realIdx[bar] = bIdx
                    if not bar.isGhostBar then
                        if ordByKey[bar.key] then
                            if not customsEmitted then
                                customsEmitted = true
                                for _, keyName in ipairs(ordKeys) do
                                    displayList[#displayList + 1] = ordByKey[keyName]
                                end
                            end
                        else
                            displayList[#displayList + 1] = bar
                        end
                    end
                end
            end

            -- In-menu drag-to-reorder for the custom-bar band: each custom
            -- row gets a grip ("=") that drags the row; a green insertion
            -- line previews the drop slot; releasing writes ONLY the display
            -- key list (p.cdmBars.customBarMenuOrder) and re-renders the
            -- menu in place. Same drag mechanics as the shared reorder
            -- widget (RF Class Order). Row clicks / delete / rename are
            -- untouched -- only the grip starts a drag.
            local drag = {}
            local customRows = {}
            local hintShown = false
            local insLine
            if reorderable then
                insLine = dropMenu:CreateTexture(nil, "OVERLAY", nil, 7)
                insLine:SetHeight(2)
                local ACC = CludesUI.CLUDES_GREEN or { r = 0.30, g = 0.79, b = 0.94 }
                insLine:SetColorTexture(ACC.r, ACC.g, ACC.b, 0.9)
                insLine:Hide()
            end
            local function ResetDrag()
                drag.row = nil
                drag.startY = nil
                drag.active = false
                drag.slot = nil
            end
            -- The slot (1 .. #customRows + 1) a row dragged to height cY would
            -- drop into: before the first other custom row whose middle lies
            -- below it.
            local function DropSlot(entry, cY, menuTop)
                local slot = #customRows
                for ri, r2 in ipairs(customRows) do
                    if r2.item ~= entry then
                        if cY > menuTop + r2.topY - ITEM_H / 2 then
                            slot = ri
                            break
                        end
                        slot = ri + 1
                    end
                end
                return math.max(1, math.min(slot, #customRows + 1))
            end

            for _, bar in ipairs(displayList) do
                local position = realIdx[bar]
                if bar.isGhostBar then
                    -- skip ghost bar in dropdown
                else
                    -- FocusKick is treated as a built-in: cannot be deleted
                    -- or renamed even though its barType is "cooldowns".
                    local focusKickBar = (bar.key == "focuskick")
                    local isCustom = not BUILT_IN[bar.key] and not focusKickBar

                    -- Hint above the custom-bar band (only when reorderable).
                    if reorderable and not hintShown and ordByKey[bar.key] then
                        hintShown = true
                        local ht = dropMenu:CreateFontString(nil, "OVERLAY")
                        ht:SetFont(FONT_PATH, 10, GetCDMOptOutline())
                        ht:SetPoint("TOPLEFT", dropMenu, "TOPLEFT", 10, -menuH - 4)
                        ht:SetTextColor(1, 1, 1, 0.25)
                        ht:SetText(CludesUI.L("Drag to Reorder Bars"))
                        menuH = menuH + 18
                    end

                    local entry = CreateFrame("Button", nil, dropMenu)
                    entry:SetHeight(ITEM_H)
                    entry:SetPoint("TOPLEFT", dropMenu, "TOPLEFT", 1, -menuH)
                    entry:SetPoint("TOPRIGHT", dropMenu, "TOPRIGHT", -1, -menuH)
                    entry:SetFrameLevel(dropMenu:GetFrameLevel() + 2)
                    if reorderable and ordByKey[bar.key] then
                        customRows[#customRows + 1] = { item = entry, key = bar.key, topY = -menuH }
                    end

                    local itemCaption = entry:CreateFontString(nil, "OVERLAY")
                    itemCaption:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                    itemCaption:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                    itemCaption:SetJustifyH("LEFT")
                    itemCaption:SetWordWrap(false)
                    itemCaption:SetMaxLines(1)
                    itemCaption:SetPoint("LEFT", entry, "LEFT", 10, 0)
                    local displayName = CludesUI.L(bar.name or bar.key)
                    itemCaption:SetText(displayName)

                    local iHl = entry:CreateTexture(nil, "ARTWORK")
                    iHl:SetAllPoints()
                    iHl:SetColorTexture(1, 1, 1, 1)
                    iHl:SetAlpha(position == optionState.selectedCDMBarIndex and selA or 0)

                    -- Delete and Rename on a custom bar's row: small icons at
                    -- its right edge, dimmed until the row is hovered.
                    local delBtn, editBtn
                    -- The row lit (hovered) and at rest (the selected bar's wash).
                    local function Lit()
                        itemCaption:SetTextColor(1, 1, 1, 1)
                        iHl:SetAlpha(hlA)
                    end
                    local function Rest()
                        itemCaption:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                        iHl:SetAlpha(position == optionState.selectedCDMBarIndex and selA or 0)
                        if delBtn then delBtn:SetAlpha(0.75) end
                        if editBtn then editBtn:SetAlpha(0.75) end
                    end
                    if isCustom then
                        -- Hovering an icon lights it, the row and its partner.
                        local function RowIcon(anchor, relPoint, x, file, tip)
                            local button = CreateFrame("Button", nil, entry)
                            button:SetSize(ICON_SZ, ICON_SZ)
                            button:SetPoint("RIGHT", anchor, relPoint, x, 0)
                            button:SetFrameLevel(entry:GetFrameLevel() + 2)
                            local icon = button:CreateTexture(nil, "OVERLAY")
                            icon:SetSize(ICON_SZ, ICON_SZ)
                            icon:SetPoint("CENTER", button, "CENTER", 0, 0)
                            if icon.SetSnapToPixelGrid then
                                icon:SetSnapToPixelGrid(false)
                                icon:SetTexelSnappingBias(0)
                            end
                            icon:SetTexture(MEDIA .. "icons\\" .. file)
                            button:SetAlpha(0.75)
                            button:SetScript("OnEnter", function(self)
                                self:SetAlpha(1)
                                Lit()
                                delBtn:SetAlpha(0.85)
                                editBtn:SetAlpha(0.85)
                                CludesUI.ShowWidgetTooltip(self, tip)
                            end)
                            button:SetScript("OnLeave", function(self)
                                if entry:IsMouseOver() or delBtn:IsMouseOver() or editBtn:IsMouseOver() then
                                    self:SetAlpha(0.85)
                                else
                                    Rest()
                                end
                                CludesUI.HideWidgetTooltip()
                            end)
                            return button
                        end
                        delBtn = RowIcon(entry, "RIGHT", -8, "cui-close.png", "Delete")
                        editBtn = RowIcon(delBtn, "LEFT", -4, "cui-edit.png", "Rename")

                        itemCaption:SetPoint("RIGHT", editBtn, "LEFT", -4, 0)

                        -- Drag grip: the ONLY drag affordance (row click still
                        -- selects, delete/rename untouched). Same grip glyph +
                        -- 3px threshold + insertion-line mechanics as the
                        -- shared reorder widget. Drop writes the display key
                        -- list and re-renders this menu in place.
                        if reorderable and ordByKey[bar.key] then
                            itemCaption:SetPoint("LEFT", entry, "LEFT", 24, 0)
                            local gripButton = CreateFrame("Button", nil, entry)
                            gripButton:SetSize(16, ITEM_H)
                            gripButton:SetPoint("LEFT", entry, "LEFT", 4, 0)
                            gripButton:SetFrameLevel(entry:GetFrameLevel() + 2)
                            local gripTex = gripButton:CreateFontString(nil, "OVERLAY")
                            gripTex:SetFont(FONT_PATH, 10, GetCDMOptOutline())
                            gripTex:SetPoint("CENTER", gripButton, "CENTER", 0, 0)
                            gripTex:SetText("=")
                            gripTex:SetTextColor(1, 1, 1, 0.2)
                            gripButton:SetScript("OnEnter", function() gripTex:SetTextColor(1, 1, 1, 0.6) end)
                            gripButton:SetScript("OnLeave", function()
                                if not (drag.row == entry and drag.active) then
                                    gripTex:SetTextColor(1, 1, 1, 0.2)
                                end
                            end)
                            gripButton:SetScript("OnMouseDown", function(_, mb)
                                if mb ~= "LeftButton" then return end
                                local _, curY = GetCursorPosition()
                                drag.row = entry
                                drag.startY = curY
                                drag.active = false
                                drag.slot = nil
                            end)
                            gripButton:SetScript("OnUpdate", function()
                                if drag.row ~= entry or not drag.startY then return end
                                local _, curY = GetCursorPosition()
                                if not drag.active then
                                    if math.abs(curY - drag.startY) < 3 then return end
                                    drag.active = true
                                    entry:SetFrameLevel(dropMenu:GetFrameLevel() + 10)
                                    entry:SetAlpha(0.8)
                                    gripTex:SetTextColor(1, 1, 1, 0.6)
                                end
                                local cY = curY / dropMenu:GetEffectiveScale()
                                local mT = dropMenu:GetTop() or 0
                                local iI = DropSlot(entry, cY, mT)
                                drag.slot = iI
                                local bandTop = customRows[1] and customRows[1].topY or 0
                                local lnY = (iI <= 1) and (bandTop + 1) or (bandTop - (iI - 1) * ITEM_H + 1)
                                insLine:ClearAllPoints()
                                insLine:SetPoint("TOPLEFT", dropMenu, "TOPLEFT", 8, lnY)
                                insLine:SetPoint("TOPRIGHT", dropMenu, "TOPRIGHT", -8, lnY)
                                insLine:Show()
                                entry:ClearAllPoints()
                                entry:SetPoint("TOPLEFT", dropMenu, "TOPLEFT", 1, cY - mT)
                                entry:SetPoint("TOPRIGHT", dropMenu, "TOPRIGHT", -1, cY - mT)
                            end)
                            gripButton:SetScript("OnMouseUp", function(_, mb)
                                if mb ~= "LeftButton" or drag.row ~= entry then return end
                                local wasActive = drag.active
                                local slot = drag.slot
                                ResetDrag()
                                if insLine then insLine:Hide() end
                                if not wasActive then return end
                                local from
                                local keyList = {}
                                for ri, r2 in ipairs(customRows) do
                                    keyList[ri] = r2.key
                                    if r2.item == entry then from = ri end
                                end
                                local to = slot or from
                                if from and to then
                                    if from < to then to = to - 1 end
                                    to = math.max(1, math.min(to, #keyList))
                                    if from ~= to then
                                        local mv = table.remove(keyList, from)
                                        table.insert(keyList, to, mv)
                                        local profile = DB()
                                        if profile and profile.cdmBars then
                                            profile.cdmBars.customBarMenuOrder = keyList
                                        end
                                    end
                                end
                                -- Re-render in the new order (also re-anchors the
                                -- dragged row); the redrawn menu stays open.
                                BuildDDMenu(true)
                            end)
                        end

                        delBtn:SetScript("OnClick", function()
                            dropMenu:Hide()
                            local delName = bar.name or bar.key
                            local delKey = bar.key
                            CludesUI:ShowConfirmPopup({
                                title = "Delete Bar",
                                message = CludesUI.Lf('Are you sure you want to delete "%1$s"?', delName),
                                confirmText = "Delete",
                                cancelText = "Cancel",
                                onConfirm = function()
                                    mod.RemoveCDMBar(delKey)
                                    -- Select the cooldowns bar after deletion
                                    optionState.selectedCDMBarIndex = 1
                                    for bi, bb in ipairs(barList) do
                                        if bb.key == "cooldowns" then
                                            optionState.selectedCDMBarIndex = bi
                                            break
                                        end
                                    end
                                    Refresh()
                                    -- Other pages' saved headers name the bars (Bar Glows'
                                    -- target): built again on their next visit. This
                                    -- page's header is built by its own rebuild below.
                                    CludesUI:InvalidateContentHeaderCache()
                                    CludesUI:RefreshPage(true)
                                end,
                            })
                        end)
                        editBtn:SetScript("OnClick", function()
                            dropMenu:Hide()
                            local oldName = bar.name or bar.key
                            CludesUI:ShowInputPopup({
                                title = "Rename Bar",
                                message = CludesUI.Lf('Enter a new name for "%1$s":', oldName),
                                placeholder = oldName,
                                confirmText = "Rename",
                                cancelText = "Cancel",
                                onConfirm = function(newName)
                                    newName = newName and strtrim(newName) or ""
                                    if newName == "" or newName == oldName then return end
                                    bar.name = newName
                                    -- Other pages' saved headers name the bars; this
                                    -- page's header is built by its own rebuild below.
                                    CludesUI:InvalidateContentHeaderCache()
                                    CludesUI:RefreshPage(true)
                                    if mod.RegisterCDMUnlockElements then mod.RegisterCDMUnlockElements() end
                                end,
                            })
                        end)
                    end

                    entry:SetScript("OnEnter", function()
                        Lit()
                        if delBtn then
                            delBtn:SetAlpha(1)
                            editBtn:SetAlpha(1)
                        end
                    end)
                    entry:SetScript("OnLeave", function()
                        if delBtn and (delBtn:IsMouseOver() or editBtn:IsMouseOver()) then return end
                        Rest()
                    end)
                    entry:SetScript("OnClick", function()
                        dropMenu:Hide()
                        optionState.selectedCDMBarIndex = position
                        -- The rebuild builds this page's header with the page,
                        -- once (no other page's header shows the selection).
                        CludesUI:RefreshPage(true)
                    end)

                    menuH = menuH + ITEM_H
                end -- else (not ghost bar)
            end -- for displayList

            -- Divider before add-bar options
            local div = dropMenu:CreateTexture(nil, "ARTWORK")
            div:SetHeight(1)
            div:SetColorTexture(1, 1, 1, 0.10)
            div:SetPoint("TOPLEFT", dropMenu, "TOPLEFT", 1, -menuH - 4)
            div:SetPoint("TOPRIGHT", dropMenu, "TOPRIGHT", -1, -menuH - 4)
            menuH = menuH + 9

            -- "Add New ..." items (disabled if at cap)
            local atCap = customCount >= (mod.MAX_CUSTOM_BARS or 6)
            -- Custom Aura ("custom_buff") bars were merged into Buff bars: a
            -- Buff bar now hosts Blizzard-tracked buffs AND injected preset/
            -- custom buffs, so there's no separate Aura bar type to create.
            local addBarTypes = {
                { type = "cooldowns", label = CludesUI.L("+ Add New Cooldowns Bar") },
                { type = "utility", label = CludesUI.L("+ Add New Utility Bar") },
                { type = "buffs", label = CludesUI.L("+ Add New Buff Bar") },
            }
            for _, record in ipairs(addBarTypes) do
                local addEntry = CreateFrame("Button", nil, dropMenu)
                addEntry:SetHeight(ITEM_H)
                addEntry:SetPoint("TOPLEFT", dropMenu, "TOPLEFT", 1, -menuH)
                addEntry:SetPoint("TOPRIGHT", dropMenu, "TOPRIGHT", -1, -menuH)
                addEntry:SetFrameLevel(dropMenu:GetFrameLevel() + 2)
                local addCaption = addEntry:CreateFontString(nil, "OVERLAY")
                addCaption:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                addCaption:SetPoint("LEFT", addEntry, "LEFT", 10, 0)
                addCaption:SetJustifyH("LEFT")
                if atCap then
                    addCaption:SetText(CludesUI.Lf("%1$s (max %2$s)", record.label, mod.MAX_CUSTOM_BARS or 6))
                    addCaption:SetTextColor(tDimR, tDimG, tDimB, tDimA * 0.4)
                else
                    addCaption:SetText(record.label)
                    addCaption:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                    local addHl = addEntry:CreateTexture(nil, "ARTWORK")
                    addHl:SetAllPoints()
                    addHl:SetColorTexture(1, 1, 1, 1)
                    addHl:SetAlpha(0)
                    local bType = record.type
                    addEntry:SetScript("OnEnter", function()
                        addCaption:SetTextColor(1, 1, 1, 1)
                        addHl:SetAlpha(hlA)
                    end)
                    addEntry:SetScript("OnLeave", function()
                        addCaption:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                        addHl:SetAlpha(0)
                    end)
                    addEntry:SetScript("OnClick", function()
                        dropMenu:Hide()
                        mod.AddCDMBar(bType)
                        optionState.selectedCDMBarIndex = #profile.cdmBars.bars
                        Refresh()
                        -- Other pages' saved headers name the bars; this
                        -- page's header is built by its own rebuild below.
                        CludesUI:InvalidateContentHeaderCache()
                        CludesUI:RefreshPage(true)
                    end)
                end
                menuH = menuH + ITEM_H
            end

            dropMenu:SetHeight(menuH + 4)

            -- Close on left-click outside (non-blocking). Never dismiss while a custom-bar row is being dragged -- a fast drag can momentarily leave the menu bounds.
            dropMenu:SetScript("OnUpdate", function(frame)
                if drag.active then return end
                if
                    not frame:IsMouseOver()
                    and not dropdownBtn:IsMouseOver()
                    and IsMouseButtonDown("LeftButton")
                then
                    frame:Hide()
                end
            end)
            -- Hooked once per dress: an in-place redraw keeps the dress's hook.
            if not inPlace then
                dropMenu:HookScript("OnHide", function(m) m:SetScript("OnUpdate", nil) end)
            end

            dropMenu:Show()
            ddMenu = dropMenu
        end

        -- Dropdown button hover/click
        dropdownBtn:SetScript("OnEnter", function()
            dropCaption:SetAlpha(mTxtHA)
            ddBrd:SetColor(1, 1, 1, mBrdHA)
            ddBg:SetColorTexture(mBgR, mBgG, mBgB, mBgHA)
        end)
        dropdownBtn:SetScript("OnLeave", function()
            if ddMenu and ddMenu:IsShown() then return end
            dropCaption:SetAlpha(mTxtA)
            ddBrd:SetColor(1, 1, 1, mBrdA)
            ddBg:SetColorTexture(mBgR, mBgG, mBgB, mBgA)
        end)
        dropdownBtn:SetScript("OnClick", function()
            if ddMenu and ddMenu:IsShown() then
                ddMenu:Hide()
            else
                BuildDDMenu()
            end
        end)
        dropdownBtn:HookScript("OnHide", function()
            if ddMenu then ddMenu:Hide() end
        end)

        Pix.Point(dropdownBtn, "TOP", heading, "TOP", 0, fy)
        fy = fy - DD_H - PV_PAD

        -- Live CDM bar preview
        local previewH = BuildCDMLivePreview(heading, fy)
        fy = fy - previewH - PV_PAD

        optionState._cdmHeaderFixedH = 20 + DD_H + PV_PAD + PV_PAD

        return math.abs(fy)
    end
    CludesUI:SetContentHeader(optionState._cdmHeaderBuilder)

    -- Refresh preview icons on mount/dismount (mountLive above): listening while this page
    -- shows, from now on and whenever it shows again. Skipped during a hidden search
    -- pre-build: nothing to preview while indexing.
    if not CludesUI._prebuilding then
        if not mountActive.frame then
            mountActive.frame = CreateFrame("Frame")
            mountActive.frame:SetScript("OnEvent", mountActive.OnEvent)
        end
        if hostFrame:IsVisible() then mountActive.Arm() end
        hostFrame:HookScript("OnShow", mountActive.Arm)
        hostFrame:HookScript("OnHide", mountActive.Disarm)
    end

    -------------------------------------------------------------------
    --  Scrollable options
    -------------------------------------------------------------------

    -------------------------------------------------------------------
    --  BAR LAYOUT / ICON DISPLAY
    -------------------------------------------------------------------
    hostFrame._showRowDivider = true

    if barInfo.key == "buffs" then
        -- ("Use Blizzard Buff Bar" toggle temporarily removed.)
    end

    -------------------------------------------------------------------
    --  BAR LAYOUT
    -------------------------------------------------------------------
    -- Sync helper: all bars except ghost/focuskick. FocusKick is a nameplate-anchored
    -- identity and never receives global syncs.
    local function ForEachSyncBar(func)
        local profile = DB()
        if not profile or not profile.cdmBars then return end
        for _, bar in ipairs(profile.cdmBars.bars) do
            if not bar.isGhostBar and bar.key ~= "focuskick" then func(bar) end
        end
    end

    if not focusKickBar then
        heading, height = W:SectionHeader(hostFrame, "BAR LAYOUT", cursorY)
        cursorY = cursorY - height
        -- The selected bar's mover (the key is read at the click).
        CludesUI.BuildSectionUnlockJump(heading, {
            key = function() return "CDM_" .. BarList().key end,
        })

        -- Row 1: (Sync) Visibility. Mouseover stays structurally absent for CDM bars
        -- (noMouseover), matching the old VIS_VALUES_CDM list.
        local visRow, visibleH = CludesUI.BuildVisibilityRow(
            W,
            hostFrame,
            cursorY,
            {
                getStore = BarList,
                legacyKey = "barVisibility",
                caps = { partyIncludesRaid = false, noMouseover = true, luaDragonriding = true },
                -- The three built-in bars ship visHideHousing = true in DEFAULTS, so an
                -- explicit uncheck must persist false or DeepMergeDefaults re-fills it to
                -- true on next login. Harmless for other bars: they never go through that
                -- merge, so the checkbox reads store[k] == true either way.
                trueDefaultOpts = { visHideHousing = true },
                onChanged = function() mod.CDMApplyVisibility() end,
                onOptionChanged = function() mod.CDMApplyVisibility() end,
            },
            -- Number of Rows moved up into the slot the Visibility Options dropdown
            -- left behind; its Row Icons cog moved with it.
            {
                type = "slider",
                text = "Number of Rows",
                min = 1,
                max = 6,
                step = 1,
                getValue = BDFieldOr("numRows", 1),
                setValue = function(value)
                    local edge = BarList()
                    edge.numRows = value
                    if value ~= 2 then
                        edge.topRowCount = nil
                        edge.customTopRowEnabled = nil
                        edge.bottomRowCount = nil
                        edge.customBottomRowEnabled = nil
                        edge.topRowSizeOffset = nil
                        edge.customTopRowSizeEnabled = nil
                        edge.bottomRowSizeOffset = nil
                        edge.customBottomRowSizeEnabled = nil
                        if edge.rowGrowDirection then
                            -- The row growth pin rides on the 2-row custom split (the
                            -- only layout whose row count changes at runtime). Clear it
                            -- with the rest of the split settings and re-store the
                            -- position in plain edge format from the bar's current spot.
                            edge.rowGrowDirection = nil
                            if mod.RecaptureBarAnchor then mod.RecaptureBarAnchor(edge.key) end
                        end
                    end
                    -- numRows change invalidates cached match dims (rows is one
                    -- of the inputs to the matched-axis dim calculation).
                    ClearMatchDims(edge)
                    RebuildBars(true)
                    CludesUI:RefreshPage()
                end,
            }
        )
        cursorY = cursorY - visibleH

        -- ONE sync icon now that both halves share a control: VisFullCopy / VisFullEquals
        -- carry the mode selection and every option boolean together.
        if not CludesUI._prebuilding then
            local region = visRow._leftRegion
            CludesUI.BuildSyncIcon({
                region = region,
                tooltip = "Apply Visibility to all Bars",
                isSynced = function()
                    local source = BarList()
                    local inSync = true
                    ForEachSyncBar(function(bar)
                        if not CludesUI.VisFullEquals(source, "barVisibility", bar, "barVisibility") then
                            inSync = false
                        end
                    end)
                    return inSync
                end,
                onClick = function()
                    local source = BarList()
                    ForEachSyncBar(function(bar)
                        if bar ~= source then CludesUI.VisFullCopy(bar, source, "barVisibility") end
                    end)
                    mod.CDMApplyVisibility()
                    CludesUI:RefreshPage()
                end,
            })
        end

        -- Row 2: Anchor to Cursor | Cursor Position (cog: X + Y)
        do
            local _, cursorH = CludesUI.BuildCursorAnchorRow({
                W = W,
                parent = hostFrame,
                y = cursorY,
                getData = BarList,
                onApply = function()
                    mod.BuildAllCDMBars()
                    mod.RegisterCDMUnlockElements()
                    Refresh()
                end,
            })
            cursorY = cursorY - cursorH
        end

        -- Bar Opacity is offered for cooldown/utility/buff bars only (excl. focuskick);
        -- other bar types leave the slot blank, as before.
        local isCDOrUtilityRow3 = (
            barInfo.barType == "cooldowns"
            or barInfo.barType == "utility"
            or barInfo.barType == "buffs"
        ) and not focusKickBar
        local row3Right
        if isCDOrUtilityRow3 then
            row3Right = {
                type = "slider",
                text = "Bar Opacity",
                min = 0,
                max = 100,
                step = 1,
                getValue = function() return math.floor((BarList().barOpacity or 1) * 100 + 0.5) end,
                setValue = function(value)
                    BarList().barOpacity = value / 100
                    if mod.ApplyBarOpacity then mod.ApplyBarOpacity(BarList().key) end
                    UpdateCDMPreview()
                end,
            }
        else
            row3Right = { type = "label", text = "" }
        end
        local opacityRow
        opacityRow, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Bar Background",
            getValue = BDFieldIs("barBgEnabled"),
            setValue = function(value)
                BarList().barBgEnabled = value
                RebuildBars()
                CludesUI:RefreshPage()
            end,
        }, row3Right)
        cursorY = cursorY - height

        -- Inline color swatch on Bar Background (left)
        if not CludesUI._prebuilding then
            local region = opacityRow._leftRegion
            local control = region and region._control
            if control and CludesUI.BuildColorSwatch then
                local bgSwatch, updateBgSwatch = CludesUI.BuildColorSwatch(
                    region,
                    opacityRow:GetFrameLevel() + 3,
                    function()
                        return BarList().barBgR or 0,
                            BarList().barBgG or 0,
                            BarList().barBgB or 0,
                            BarList().barBgA or 0.5
                    end,
                    function(red, green, blue, a)
                        BarList().barBgR = red
                        BarList().barBgG = green
                        BarList().barBgB = blue
                        BarList().barBgA = a
                        RebuildBars()
                    end,
                    true,
                    20
                )
                Pix.Point(bgSwatch, "RIGHT", control, "LEFT", -8, 0)
                local block = CludesUI.NewSwatchBlocker(bgSwatch)
                block:SetScript(
                    "OnEnter",
                    function()
                        CludesUI.ShowWidgetTooltip(bgSwatch, CludesUI.DisabledTooltip("Bar Background"))
                    end
                )
                block:SetScript("OnLeave", function() CludesUI.HideWidgetTooltip() end)
                CludesUI.RegisterWidgetRefresh(function()
                    if updateBgSwatch then updateBgSwatch() end
                    local enabled = BarList().barBgEnabled == true
                    bgSwatch:SetAlpha(enabled and 1 or 0.3)
                    if enabled then
                        block:Hide()
                    else
                        block:Show()
                    end
                end)
                local enabled = BarList().barBgEnabled == true
                bgSwatch:SetAlpha(enabled and 1 or 0.3)
                if enabled then
                    block:Hide()
                else
                    block:Show()
                end
            end
        end

        -- Inline cog on Number of Rows (now in the Visibility row's right slot):
        -- Row Icons settings (only relevant when numRows == 2)
        if not CludesUI._prebuilding then
            local leftRegion = visRow._rightRegion
            local control = leftRegion._control
            local function customTopOff()
                local edge = BarList()
                return not edge or not edge.customTopRowEnabled
            end
            local function rowsNotTwo() return (BarList().numRows or 1) ~= 2 end
            -- Row-size options are locked while the bar is width/height matched,
            -- exactly like Icon Scale (a per-row size offset can't honor a match).
            local rsMatchKey = "CDM_" .. BarList().key
            local rsWDis, rsWTip = CludesUI.MatchGuard(rsMatchKey, "Width")
            local rsHDis, rsHTip = CludesUI.MatchGuard(rsMatchKey, "Height")
            local function rowSizeMatched() return rsWDis() or rsHDis() end
            local function rowSizeMatchTip()
                if rsWDis() then return rsWTip() end
                return rsHTip()
            end
            -- Row Growth dropdown: labels track the bar's orientation (rows
            -- stack vertically on horizontal bars, horizontally on vertical
            -- bars). The page rebuilds on orientation flips and bar switches,
            -- so build-time resolution is safe.
            local rowGrowValues, rowGrowOrder, rowGrowTip
            if BarList().verticalOrientation then
                rowGrowValues = { CENTER = "Grow Centered", RIGHT = "Grow Right", LEFT = "Grow Left" }
                rowGrowOrder = { "CENTER", "RIGHT", "LEFT" }
                rowGrowTip =
                    "How extra columns grow when the second column appears or disappears. Grow Right keeps the left column in place, Grow Left keeps the right column in place, Grow Centered keeps the bar centered."
            else
                rowGrowValues = { CENTER = "Grow Centered", DOWN = "Grow Down", UP = "Grow Up" }
                rowGrowOrder = { "CENTER", "DOWN", "UP" }
                rowGrowTip =
                    "How extra rows grow when the second row appears or disappears. Grow Down keeps the top row in place, Grow Up keeps the bottom row in place, Grow Centered keeps the bar centered."
            end
            CludesUI.BuildInlineCog(leftRegion, {
                anchorTo = control,
                title = "Row Icons",
                rows = {
                    {
                        type = "dropdown",
                        label = "Row Growth",
                        values = rowGrowValues,
                        order = rowGrowOrder,
                        tooltip = rowGrowTip,
                        -- Only meaningful with the 2-row custom split (the only
                        -- layout whose row count changes at runtime). Anchored
                        -- bars are positioned by their anchor system, which
                        -- ignores the pin entirely.
                        disabled = function()
                            if rowsNotTwo() then return true end
                            local barData = BarList()
                            if barData.anchorTo and barData.anchorTo ~= "none" then return true end
                            if
                                CludesUI.IsUnlockAnchored and CludesUI.IsUnlockAnchored("CDM_" .. barData.key)
                            then
                                return true
                            end
                            return false
                        end,
                        disabledTooltip = function()
                            if rowsNotTwo() then return "This option requires exactly 2 rows" end
                            return "Not available while this bar is anchored to another element"
                        end,
                        rawTooltip = true,
                        get = BDFieldOr("rowGrowDirection", "CENTER"),
                        set = function(value)
                            local edge = BarList()
                            edge.rowGrowDirection = (value ~= "CENTER") and value or nil
                            -- Recapture the corner from the bar's current spot BEFORE
                            -- rebuilding, so the new anchor pins where the bar sits now.
                            if mod.RecaptureBarAnchor then mod.RecaptureBarAnchor(edge.key) end
                            RebuildBars(true)
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Custom Base Row Count",
                        -- The base row is the FIRST DATA row: it fills first and it is
                        -- the row Row Growth keeps in place (visual top normally, visual
                        -- bottom/right when reversed). Stored in the legacy topRowCount
                        -- keys; the legacy bottom-count fields are still honored at
                        -- runtime for old profiles but no longer have UI. Enabling this
                        -- clears the legacy bottom flag so the base count takes effect.
                        disabled = rowsNotTwo,
                        disabledTooltip = "This option requires exactly 2 rows",
                        rawTooltip = true,
                        get = BDFieldGet("customTopRowEnabled"),
                        set = function(value)
                            BarList().customTopRowEnabled = value
                            if value then BarList().customBottomRowEnabled = nil end
                            RebuildBars(true)
                        end,
                    },
                    {
                        type = "slider",
                        label = "Base Row Icons",
                        min = 1,
                        max = 15,
                        step = 1,
                        tooltip = "How many icons to show on the base row (the row that fills first and that Row Growth keeps in place). The rest go on the second row.",
                        disabled = function() return rowsNotTwo() or customTopOff() end,
                        disabledTooltip = function()
                            if rowsNotTwo() then return "This option requires exactly 2 rows" end
                            return "Custom Base Row Count"
                        end,
                        get = function()
                            local edge = BarList()
                            if edge.topRowCount and edge.topRowCount > 0 then return edge.topRowCount end
                            local total = 0
                            local sdTR = mod.GetBarSpellData(edge.key)
                            if sdTR and sdTR.assignedSpells then
                                for _, spellRef in ipairs(sdTR.assignedSpells) do
                                    if spellRef and spellRef ~= 0 then total = total + 1 end
                                end
                            end
                            if total == 0 then return 1 end
                            return math.ceil(total / 2)
                        end,
                        set = function(value)
                            if value == 0 then value = nil end
                            BarList().topRowCount = value
                            RebuildBars(true)
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Custom Base Row Size",
                        -- Mutually exclusive with Custom Second Row Size (stored
                        -- in the legacy customBottomRowSize* keys); also locked
                        -- while the bar is width/height matched (same as Icon Scale).
                        disabled = function()
                            return rowsNotTwo()
                                or rowSizeMatched()
                                or BarList().customBottomRowSizeEnabled == true
                        end,
                        disabledTooltip = function()
                            if rowsNotTwo() then return "This option requires exactly 2 rows" end
                            if rowSizeMatched() then return rowSizeMatchTip() end
                            return "Disabled while Custom Second Row Size is enabled"
                        end,
                        rawTooltip = true,
                        get = BDFieldGet("customTopRowSizeEnabled"),
                        set = function(value)
                            BarList().customTopRowSizeEnabled = value
                            if value then BarList().customBottomRowSizeEnabled = nil end
                            RebuildBars(true)
                        end,
                    },
                    {
                        type = "slider",
                        label = "Base Icon Size",
                        min = -20,
                        max = 20,
                        step = 1,
                        tooltip = "Offsets the base row's icon size in pixels from Icon Scale. The second row keeps the base size.",
                        disabled = function()
                            return rowsNotTwo() or rowSizeMatched() or not BarList().customTopRowSizeEnabled
                        end,
                        disabledTooltip = function()
                            if rowsNotTwo() then return "This option requires exactly 2 rows" end
                            if rowSizeMatched() then return rowSizeMatchTip() end
                            return "Custom Base Row Size"
                        end,
                        rawTooltip = function() return rowSizeMatched() end,
                        get = BDFieldOr("topRowSizeOffset", 0),
                        set = function(value)
                            if value == 0 then value = nil end
                            BarList().topRowSizeOffset = value
                            RebuildBars(true)
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Custom Second Row Size",
                        -- Flip of Custom Base Row Size; mutually exclusive with it.
                        disabled = function()
                            return rowsNotTwo()
                                or rowSizeMatched()
                                or BarList().customTopRowSizeEnabled == true
                        end,
                        disabledTooltip = function()
                            if rowsNotTwo() then return "This option requires exactly 2 rows" end
                            if rowSizeMatched() then return rowSizeMatchTip() end
                            return "Disabled while Custom Base Row Size is enabled"
                        end,
                        rawTooltip = true,
                        get = BDFieldGet("customBottomRowSizeEnabled"),
                        set = function(value)
                            BarList().customBottomRowSizeEnabled = value
                            if value then BarList().customTopRowSizeEnabled = nil end
                            RebuildBars(true)
                        end,
                    },
                    {
                        type = "slider",
                        label = "Second Row Icon Size",
                        min = -20,
                        max = 20,
                        step = 1,
                        tooltip = "Offsets the second row's icon size in pixels from Icon Scale. The base row keeps the base size.",
                        disabled = function()
                            return rowsNotTwo()
                                or rowSizeMatched()
                                or not BarList().customBottomRowSizeEnabled
                        end,
                        disabledTooltip = function()
                            if rowsNotTwo() then return "This option requires exactly 2 rows" end
                            if rowSizeMatched() then return rowSizeMatchTip() end
                            return "Custom Second Row Size"
                        end,
                        rawTooltip = function() return rowSizeMatched() end,
                        get = BDFieldOr("bottomRowSizeOffset", 0),
                        set = function(value)
                            if value == 0 then value = nil end
                            BarList().bottomRowSizeOffset = value
                            RebuildBars(true)
                        end,
                    },
                },
            })
            -- Cog stays clickable at any row count; the rows inside gate
            -- themselves on the 2-row requirement individually.
        end

        -- Inline cog on Bar Opacity (now in the Bar Background row): fade the bar to a
        -- chosen alpha while out of combat. Off by default.
        if isCDOrUtilityRow3 then
            local region = opacityRow._rightRegion
            local control = region and region._control
            CludesUI.BuildInlineCog(region, {
                anchorTo = control,
                title = "Out of Combat Alpha",
                rows = {
                    {
                        type = "toggle",
                        label = "Fade Out of Combat",
                        tooltip = "Dims this bar while out of combat.",
                        rawTooltip = true,
                        get = BDFieldIs("oocFadeEnabled"),
                        set = function(value)
                            BarList().oocFadeEnabled = value
                            if mod.CDMApplyVisibility then mod.CDMApplyVisibility() end
                            UpdateCDMPreview()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Out of Combat Alpha",
                        min = 0,
                        max = 100,
                        step = 1,
                        disabled = function() return not BarList().oocFadeEnabled end,
                        disabledTooltip = "Enable Fade Out of Combat first",
                        rawTooltip = true,
                        get = function() return math.floor((BarList().oocFadeAlpha or 0.5) * 100 + 0.5) end,
                        set = function(value)
                            BarList().oocFadeAlpha = value / 100
                            if mod.CDMApplyVisibility then mod.CDMApplyVisibility() end
                            UpdateCDMPreview()
                        end,
                    },
                },
            })
        end

        -- Max Icons + Overflow To: excess icons (beyond Max, the tail of this bar's order)
        -- render on the target bar for the session. Identity, per-spell settings and the options
        -- preview stay on this bar. Legacy profiles carry nil barType on default bars -- resolve the family via the shared helper, never the raw field.
        local ofBarType = mod.GetBarType and mod.GetBarType(barInfo) or barInfo.barType
        local isOverflowBar = (ofBarType == "cooldowns" or ofBarType == "utility")
            and not barInfo.isGhostBar
            and barInfo.key ~= (mod.FOCUSKICK_BAR_KEY or "focuskick")
        if isOverflowBar then
            local function OverflowShiftBlocked()
                return (mod.CdmBarHasShiftCdState and mod.CdmBarHasShiftCdState(BarList().key)) or false
            end
            -- A bar may not BOTH receive overflow and have its own overflow config: incoming
            -- icons ignore the recipient's cap and never chain onward, so a cap on a recipient
            -- would promise behavior that does not exist. Recipient = ANY bar (enabled or not -- re-enabling must not create the forbidden state) with an active cap+target pair pointing here.
            local function BarIsOverflowRecipient(barKey)
                local profile = DB()
                if not (profile and profile.cdmBars) then return false end
                for _, bar in ipairs(profile.cdmBars.bars) do
                    if
                        bar.key ~= barKey
                        and bar.maxIcons
                        and bar.maxIcons > 0
                        and bar.overflowTarget == barKey
                    then
                        return true
                    end
                end
                return false
            end
            local ofVals, ofOrder = { [""] = "None" }, { "" }
            do
                local profile = DB()
                if profile and profile.cdmBars then
                    for _, bar in ipairs(profile.cdmBars.bars) do
                        local bt = mod.GetBarType and mod.GetBarType(bar) or bar.barType
                        -- Bars with their own active overflow config are not offered as targets (the recipient rule, other door).
                        local hasOwnOverflow = bar.maxIcons and bar.maxIcons > 0 and bar.overflowTarget ~= nil
                        if
                            bar.key ~= barInfo.key
                            and not bar.isGhostBar
                            and bar.key ~= (mod.FOCUSKICK_BAR_KEY or "focuskick")
                            and bar.key ~= "buffs"
                            and bt ~= "buffs"
                            and bt ~= "custom_buff"
                            and not hasOwnOverflow
                        then
                            ofVals[bar.key] = CludesUI.L(bar.name or bar.key)
                            ofOrder[#ofOrder + 1] = bar.key
                        end
                    end
                    -- A stored target that the filter (or a bar delete) now excludes still
                    -- displays -- and can be cleared -- rather than masquerading as "None" while active at runtime (pre-rule configs keep working under no-chaining).
                    local current = barInfo.overflowTarget
                    if current and not ofVals[current] then
                        local curName = current
                        for _, bar in ipairs(profile.cdmBars.bars) do
                            if bar.key == current then
                                curName = bar.name or current
                                break
                            end
                        end
                        ofVals[current] = CludesUI.L(curName)
                        ofOrder[#ofOrder + 1] = current
                    end
                end
            end
            _, height = W:DualRow(hostFrame, cursorY, {
                type = "slider",
                text = "Max Icons (0 = Off)",
                min = 0,
                max = 20,
                step = 1,
                -- A blocked bar with a value already set can still lower/clear it -- a disabled control must never trap an existing value on.
                disabled = function()
                    local barData = BarList()
                    return (OverflowShiftBlocked() or BarIsOverflowRecipient(barData.key))
                        and not (barData.maxIcons and barData.maxIcons > 0)
                end,
                disabledTooltip = function()
                    if BarIsOverflowRecipient(BarList().key) then
                        return "Not available while another bar overflows into this bar"
                    end
                    return "Not available while a spell on this bar uses a Cooldown State Shift Icons setting"
                end,
                rawTooltip = true,
                getValue = BDFieldOr("maxIcons", 0),
                setValue = function(value)
                    if value == 0 then value = nil end
                    BarList().maxIcons = value
                    RebuildBars(true)
                    C_Timer.After(0, function() CludesUI:RefreshPage() end)
                end,
            }, {
                type = "dropdown",
                text = "Overflow To",
                values = ofVals,
                order = ofOrder,
                -- Recipient bars cannot pick a fresh target (third door); one with a stale target set stays enabled so it can be cleared back to None.
                disabled = function()
                    local barData = BarList()
                    return OverflowShiftBlocked()
                        or (BarIsOverflowRecipient(barData.key) and not barData.overflowTarget)
                        or not (barData.maxIcons and barData.maxIcons > 0)
                end,
                -- Tooltip priority: recipient block, then the plain Max Icons requirement. The
                -- Shift Icons message only shows when it is the ACTUAL blocker (Max Icons
                -- already above 0 but a spell carries a shift cooldown-state setting) -- most users never touch that setting, so the default tooltip stays basic.
                disabledTooltip = function()
                    local barData = BarList()
                    if BarIsOverflowRecipient(barData.key) then
                        return "Not available while another bar overflows into this bar"
                    end
                    if not (barData.maxIcons and barData.maxIcons > 0) then
                        return "Requires Max Icons to be above 0"
                    end
                    return "Not available while a spell on this bar uses a Cooldown State Shift Icons setting"
                end,
                rawTooltip = true,
                getValue = function()
                    local t = BarList().overflowTarget
                    if t and ofVals[t] then return t end
                    return ""
                end,
                setValue = function(value)
                    if value == "" then value = nil end
                    BarList().overflowTarget = value
                    RebuildBars(true)
                end,
            })
            cursorY = cursorY - height
        end

        -- Vertical Orientation shares a row with Keep Buffs in Same Place on buff bars
        -- (both apply there), and stands alone -- last row of the section -- otherwise.
        -- Moved down here, after Max Icons/Overflow To; shown for every non-focuskick bar
        -- regardless of overflow capability, same as before the move (this section's outer
        -- gate is `not isFocusKick`, not isOverflowBar).
        local vertOrientCfg = {
            type = "toggle",
            text = "Vertical Orientation",
            getValue = BDFieldGet("verticalOrientation"),
            setValue = function(value)
                local edge = BarList()
                edge.verticalOrientation = value
                edge.growDirection = value and "DOWN" or "RIGHT"
                -- Orientation flip invalidates the row growth direction too (UP/DOWN are
                -- horizontal-bar values, LEFT/RIGHT vertical).
                edge.rowGrowDirection = nil
                -- Orientation flip swaps the meaning of width-axis vs height-axis, so width/height match caches no longer apply.
                ClearMatchDims(edge)
                RebuildBars(true)
            end,
        }

        if mod.IsBarBuffFamily(barInfo) then
            local prof = mod.ECME and mod.ECME.db and mod.ECME.db.profile
            -- (Hide Buffs When Inactive toggle removed: always forced ON.)
        end

        -- Keep Buffs in Same Place (native buff bars): reserves every tracked buff's slot so
        -- active buffs never reposition; inactive slots are invisible. Reuses the Always-Show
        -- placeholder path internally (placeholders injected, then rendered alpha 0). Mutually exclusive with Always Show Buffs -- disabled while that is on.
        -- (Minimum Bar Size moved to the Icon Scale inline cog, user-directed.)
        if isBuffBar then
            _, height = W:DualRow(hostFrame, cursorY, {
                type = "toggle",
                text = "Keep Buffs in Same Place",
                disabled = function()
                    local barData = BarList()
                    return barData.showInactiveBuffIcons == true or AnyIconAlwaysShowOn(barData.key)
                end,
                disabledTooltip = "Disabled while Always Show Buffs is enabled (on the bar, or on any individual buff)",
                rawTooltip = true,
                getValue = BDFieldIs("hidePlaceholderIcon"),
                setValue = function(value)
                    BarList().hidePlaceholderIcon = value
                    RebuildBars(true)
                    CludesUI:RefreshPage()
                end,
            }, vertOrientCfg)
            cursorY = cursorY - height
        else
            _, height = W:DualRow(hostFrame, cursorY, vertOrientCfg, { type = "label", text = "" })
            cursorY = cursorY - height
        end
    end -- not isFocusKick (Bar Layout section)

    -------------------------------------------------------------------
    --  FOCUSKICK OPTIONS (FocusKick only)
    -------------------------------------------------------------------
    if focusKickBar then
        _, height = W:SectionHeader(hostFrame, "FocusKick Options", cursorY)
        cursorY = cursorY - height

        local NP_SIDE_VALUES = { LEFT = "Left", RIGHT = "Right", TOP = "Top", BOTTOM = "Bottom" }
        local NP_SIDE_ORDER = { "LEFT", "RIGHT", "TOP", "BOTTOM" }

        local function ApplyAnchor()
            if mod.ApplyFocusKickAnchor then mod.ApplyFocusKickAnchor() end
        end
        local function RefreshReminders()
            if mod.RefreshFocusReminders then mod.RefreshFocusReminders() end
        end
        -- A cog slider over one of this bar's settings: read with its default,
        -- written and then applied by apply().
        local function BarSlider(label, barKey, default, minV, maxV, apply)
            return {
                type = "slider",
                label = label,
                min = minV,
                max = maxV,
                step = 1,
                get = function() return BarList()[barKey] or default end,
                set = function(value)
                    BarList()[barKey] = value
                    apply()
                end,
            }
        end

        -- Row 1: Nameplate Anchor (left) | Focus Text Reminders (right)
        local npRow
        npRow, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Nameplate Anchor",
            values = NP_SIDE_VALUES,
            order = NP_SIDE_ORDER,
            getValue = BDFieldOr("nameplateAnchorSide", "LEFT"),
            setValue = function(value)
                BarList().nameplateAnchorSide = value
                ApplyAnchor()
                CludesUI:RefreshPage()
            end,
        }, {
            type = "toggle",
            text = "Focus Text Reminders",
            tooltip = 'This will display the word "FOCUS" below caster/miniboss mobs in M+ if you have not set your focus. Disabled for specs with no kick.',
            getValue = function()
                local edge = BarList()
                return edge.focusReminderEnabled == true
            end,
            setValue = function(value)
                BarList().focusReminderEnabled = value
                RefreshReminders()
                CludesUI:RefreshPage()
            end,
        })
        cursorY = cursorY - height

        -- Inline cog for Nameplate Offset (left)
        if not CludesUI._prebuilding then
            local region = npRow._leftRegion
            CludesUI.BuildInlineCog(region, {
                anchorTo = region._control,
                title = "Nameplate Offset",
                rows = {
                    BarSlider("X Offset", "nameplateOffsetX", 0, -100, 100, ApplyAnchor),
                    BarSlider("Y Offset", "nameplateOffsetY", 0, -100, 100, ApplyAnchor),
                },
            })
        end

        -- Inline cog + dual swatch for Focus Reminders (right region). Layout right-to-left
        -- along the row's right region: [control] [cog] [accent swatch] [custom swatch].
        -- Accent swatch (next to the cog) is the active mode by default; custom swatch dims and blocks while accent is on.
        if not CludesUI._prebuilding then
            local region = npRow._rightRegion
            local control = region and region._control

            CludesUI.BuildInlineCog(region, {
                title = "Focus Reminder Settings",
                rows = {
                    BarSlider("Text Size", "focusReminderSize", 26, 8, 50, RefreshReminders),
                    BarSlider("X Offset", "focusReminderOffsetX", 0, -100, 100, RefreshReminders),
                    BarSlider("Y Offset", "focusReminderOffsetY", 0, -100, 100, RefreshReminders),
                },
            })

            -- Right (accent) swatch: one-click activation, displays live CLUDES_GREEN
            local accentSwatch, updateAccentSwatch = CludesUI.BuildColorSwatch(
                region,
                npRow:GetFrameLevel() + 3,
                function()
                    local brandGreen = CludesUI.CLUDES_GREEN
                    if brandGreen then return brandGreen.r, brandGreen.g, brandGreen.b end
                    return 0.298, 0.788, 0.941
                end,
                function() end, -- read-only display, no picker
                false,
                20
            )
            Pix.Point(accentSwatch, "RIGHT", region._lastInline or control, "LEFT", -8, 0)
            accentSwatch:SetScript("OnClick", function()
                BarList().focusReminderUseAccent = true
                RefreshReminders()
                CludesUI:RefreshPage()
            end)
            CludesUI.HoverTip(accentSwatch, "Accent Color")

            -- Left (custom) swatch: color picker when accent mode is off
            local customColorSwatch, updateCustomSwatch = CludesUI.BuildColorSwatch(
                region,
                npRow:GetFrameLevel() + 3,
                function()
                    local edge = BarList()
                    return edge.focusReminderR or 1, edge.focusReminderG or 1, edge.focusReminderB or 1
                end,
                function(red, green, blue)
                    BarList().focusReminderR, BarList().focusReminderG, BarList().focusReminderB =
                        red, green, blue
                    BarList().focusReminderUseAccent = false
                    RefreshReminders()
                end,
                false,
                20
            )
            Pix.Point(customColorSwatch, "RIGHT", accentSwatch, "LEFT", -8, 0)
            CludesUI.HoverTip(customColorSwatch, "Custom Color")

            -- Block overlay: while accent mode is active, clicking the custom swatch flips accent mode off instead of opening the color picker.
            local customBlock = CreateFrame("Button", nil, customColorSwatch)
            customBlock:SetAllPoints()
            customBlock:SetFrameLevel(customColorSwatch:GetFrameLevel() + 10)
            customBlock:EnableMouse(true)
            customBlock:SetScript("OnClick", function()
                if BarList().focusReminderUseAccent then
                    BarList().focusReminderUseAccent = false
                    RefreshReminders()
                    CludesUI:RefreshPage()
                end
            end)
            customBlock:SetScript(
                "OnEnter",
                function() CludesUI.ShowWidgetTooltip(customColorSwatch, "Custom Color") end
            )
            customBlock:SetScript("OnLeave", function() CludesUI.HideWidgetTooltip() end)
            region._lastInline = customColorSwatch

            -- Disable both swatches + cog when Focus Text Reminders toggle is off
            local enableBlock = CreateFrame("Frame", nil, customColorSwatch)
            enableBlock:SetAllPoints()
            enableBlock:SetFrameLevel(customColorSwatch:GetFrameLevel() + 20)
            enableBlock:EnableMouse(true)
            enableBlock:SetScript(
                "OnEnter",
                function()
                    CludesUI.ShowWidgetTooltip(
                        customColorSwatch,
                        CludesUI.DisabledTooltip("Focus Text Reminders")
                    )
                end
            )
            enableBlock:SetScript("OnLeave", function() CludesUI.HideWidgetTooltip() end)

            local function UpdateFRSwatchState()
                local edge = BarList()
                local enabled = edge.focusReminderEnabled == true
                if not enabled then
                    accentSwatch:SetAlpha(0.3)
                    customColorSwatch:SetAlpha(0.3)
                    customBlock:Hide()
                    enableBlock:Show()
                else
                    enableBlock:Hide()
                    local useAccent = edge.focusReminderUseAccent
                    if useAccent then
                        accentSwatch:SetAlpha(1)
                        customColorSwatch:SetAlpha(0.3)
                        customBlock:Show()
                    else
                        accentSwatch:SetAlpha(0.3)
                        customColorSwatch:SetAlpha(1)
                        customBlock:Hide()
                    end
                end
            end
            CludesUI.RegisterWidgetRefresh(function()
                updateAccentSwatch()
                updateCustomSwatch()
                UpdateFRSwatchState()
            end)
            UpdateFRSwatchState()
        end

        -- Row 2: Focus Cast Sound (left) | Interrupt Spell picker (right). Sound values come
        -- from the runtime sound table (built-in sounds + LSM appended at init); the spell
        -- picker rebuilds every render so it reflects the bar's current spell list. Shallow-copy the names table to attach per-row menu options (preview icon) without polluting the shared ns.FOCUSKICK_SOUND_NAMES other code reads.
        local soundValues = {}
        if mod.FOCUSKICK_SOUND_NAMES then
            for keyName, value in pairs(mod.FOCUSKICK_SOUND_NAMES) do
                soundValues[keyName] = value
            end
        else
            soundValues.none = "None"
        end
        local soundOrder = mod.FOCUSKICK_SOUND_ORDER or { "none" }
        soundValues._menuOpts = {
            itemHeight = 26,
            maxTextWidthPct = 0.8,
            searchable = true,
            iconAtlas = function(barKey)
                if barKey == "none" then return nil end
                local paths = mod.FOCUSKICK_SOUND_PATHS
                if not paths or not paths[barKey] then return nil end
                return CludesUI.SOUND_ICON_ATLAS
            end,
            iconPressedAtlas = function(barKey)
                if barKey == "none" then return nil end
                return CludesUI.SOUND_ICON_PRESSED_ATLAS
            end,
            iconOnClick = function(barKey)
                local paths = mod.FOCUSKICK_SOUND_PATHS
                local filePath = paths and paths[barKey]
                if filePath then PlaySoundFile(filePath, "Master") end
            end,
            iconTooltip = function() return "Preview Sound" end,
        }

        -- Spell dropdown values/order -- rebuilt live on every dropdown
        -- click (see OnClick hook below) so the list always reflects what
        -- is currently on the focuskick bar, even if the user added or
        -- removed spells via the spell picker without closing options.
        local spellValues = {}
        local orderList = {}
        local function RebuildSpellOptions()
            wipe(spellValues)
            for i = #orderList, 1, -1 do
                orderList[i] = nil
            end
            -- Interrupts only. The list comes from CludesUI.KickData (the suite's
            -- interrupt table, built from game spell data and shared with the Kick
            -- Tracker), filtered to what this character can cast right now. Picking
            -- one keeps the "only when my kick is ready" gate with an EMPTY FocusKick
            -- bar (no nameplate icon, kick stays on the CDM); the engine already
            -- honors an explicit pick without bar content.
            local sd = mod.GetBarSpellData and mod.GetBarSpellData("focuskick")
            local entries = sd and sd.assignedSpells
            local barHasSpell = false
            if entries then
                for _, spellRef in ipairs(entries) do
                    if type(spellRef) == "number" and spellRef > 0 then
                        barHasSpell = true
                        break
                    end
                end
            end
            -- No explicit pick: the engine falls back to the bar's first castable
            -- spell, or stays silent on an empty bar. Name that state honestly.
            spellValues["__none"] = barHasSpell and "Auto (First on Bar)" or "None"
            orderList[#orderList + 1] = "__none"

            local kicks, seenName = {}, {}
            local KD = CludesUI.KickData
            local resolve = mod.ResolveCastableInterrupt
            if KD and KD.INTERRUPTS and resolve then
                for ident, keyName in pairs(KD.INTERRUPTS) do
                    -- True kicks only: `tracked = false` marks spells that merely
                    -- also interrupt (Avenger's Shield), same rule as the Kick Tracker.
                    local castable = keyName.tracked ~= false and resolve(ident)
                    if castable then
                        local details = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(ident)
                        local name = (details and details.name) or ("Spell " .. ident)
                        if not seenName[name] then
                            seenName[name] = true
                            kicks[#kicks + 1] = { key = tostring(ident), name = name }
                        end
                    end
                end
            end
            table.sort(kicks, function(lhs, rhs) return lhs.name < rhs.name end)
            if #kicks > 0 then
                orderList[#orderList + 1] = "---"
                for _, keyName in ipairs(kicks) do
                    spellValues[keyName.key] = keyName.name
                    orderList[#orderList + 1] = keyName.key
                end
            end
            -- Sound-only mode: fire on every cast, no interrupt or cooldown gate.
            orderList[#orderList + 1] = "---"
            spellValues["__any"] = "Any Cast (Sound Only)"
            orderList[#orderList + 1] = "__any"
            -- The stored selection can outlive its spell (removing the kick empties
            -- assignedSpells, focusKickInterruptSpellID keeps pointing at it) and the
            -- dropdown would render the raw spell id. Give it a NAME but do NOT add it
            -- to spellOrder: it must not be selectable on a bar that no longer holds it.
            -- Label it ONLY when this character can cast it: the id is profile-level but
            -- the spellbook is per-spec, so a spec sharing the profile can inherit a pick
            -- it can never use; unlabelled makes getValue below fall back to the bar's
            -- own contents.
            local selSid = BarList and BarList() and BarList().focusKickInterruptSpellID
            if selSid and (not mod.ResolveCastableInterrupt or mod.ResolveCastableInterrupt(selSid)) then
                local selKey = tostring(selSid)
                if not spellValues[selKey] then
                    local selInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(selSid)
                    spellValues[selKey] = (selInfo and selInfo.name) or ("Spell " .. selKey)
                end
            end
        end
        RebuildSpellOptions()

        local focusKickRow
        focusKickRow, height = W:DualRow(hostFrame, cursorY, {
            type = "dropdown",
            text = "Focus Cast Sound",
            values = soundValues,
            order = soundOrder,
            getValue = BDFieldOr("focusCastSoundKey", "none"),
            setValue = function(value)
                BarList().focusCastSoundKey = value
                -- Arm/disarm the cast proxy live (it is demand-gated on the sound).
                if mod.RefreshFocusKickProxies then mod.RefreshFocusKickProxies() end
            end,
        }, {
            type = "dropdown",
            text = "Interrupt Spell",
            tooltip = "Pick your kick to play the sound only while it is off cooldown, or Any Cast (Sound Only) to play it on every enemy cast.\nLeave the bar above empty for a sound with no nameplate icon.",
            values = spellValues,
            order = orderList,
            getValue = function()
                if BarList().focusCastSoundAnyCast == true then return "__any" end
                local spellRef = BarList().focusKickInterruptSpellID
                if not spellRef then return orderList[1] end
                -- No label means RebuildSpellOptions rejected it: either
                -- this character cannot cast it, or it is not on the bar
                -- and not castable. Show what the bar actually holds
                -- rather than a selection the player never made.
                local barKey = tostring(spellRef)
                if not spellValues[barKey] then return orderList[1] end
                return barKey
            end,
            setValue = function(value)
                BarList().focusCastSoundAnyCast = (value == "__any") or nil
                if value == "__none" or value == "__any" then
                    BarList().focusKickInterruptSpellID = nil
                else
                    BarList().focusKickInterruptSpellID = tonumber(value)
                end
                if mod.RefreshFocusKickProxies then mod.RefreshFocusKickProxies() end
            end,
        })
        cursorY = cursorY - height

        -- Live refresh: every click on the Interrupt Spell dropdown
        -- rebuilds the option list from the bar's current spells and
        -- invalidates the cached menu so the new options appear.
        do
            local rightRegion = focusKickRow and focusKickRow._rightRegion
            local dropdownBtn = rightRegion and rightRegion._control
            if dropdownBtn then
                local origOnClick = dropdownBtn:GetScript("OnClick")
                dropdownBtn:SetScript("OnClick", function(self, ...)
                    RebuildSpellOptions()
                    if dropdownBtn._invalidateMenu then dropdownBtn._invalidateMenu() end
                    if origOnClick then origOnClick(self, ...) end
                end)
            end
        end

        -- Row: Show on Target
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Show on Target",
            tooltip = "Show the FocusKick bar on your current target's nameplate instead of your focus target's nameplate.",
            getValue = BDFieldIs("focusKickUseTarget"),
            setValue = function(value)
                BarList().focusKickUseTarget = value
                if mod.ApplyFocusKickAnchor then mod.ApplyFocusKickAnchor() end
                if mod.RefreshFocusCastProxyUnit then mod.RefreshFocusCastProxyUnit() end
                CludesUI:RefreshPage()
            end,
        }, { type = "label", text = "" })
        cursorY = cursorY - height

        _, height = W:Spacer(hostFrame, cursorY, 8)
        cursorY = cursorY - height
    else
        _, height = W:Spacer(hostFrame, cursorY, 8)
        cursorY = cursorY - height
    end

    -------------------------------------------------------------------
    --  ICON DISPLAY
    -------------------------------------------------------------------
    -- (The per-icon hint now lives directly below the preview icons -- see
    -- the reorder hint in BuildCDMLivePreview's pf.Update.)
    _, height = W:SectionHeader(hostFrame, "ICON DISPLAY", cursorY)
    cursorY = cursorY - height
    cursorY = CludesUI.BlizzStyle.Note(hostFrame, cursorY, "cdmicons")

    -- Active State Animation dropdown values
    local ACTIVE_ANIM_VALUES = {
        blizzard = "Blizzard",
        ["1"] = "Pixel Glow",
        ["3"] = "Action Button Glow",
        ["4"] = "Auto-Cast Shine",
        ["5"] = "GCD",
        ["7"] = "Classic WoW Glow",
        hideActive = "Hide Active State",
    }
    local ACTIVE_ANIM_ORDER = { "blizzard", "hideActive", "1", "---", "3", "4", "5", "7" }

    local function CustomShapeOn()
        local s = BarList().iconShape or "none"
        return s ~= "none" and s ~= "cropped"
    end

    -- Adjust Crop cog on Custom Icon Shape (both shape rows below). Writes the per-bar
    -- iconCropPercent that ns.CdmCropFactor / ns.CdmCropTrim read; unset = 10 = the classic
    -- crop. Disabled unless the shape is Cropped. Under a stock style both shape rows are
    -- fully gated, so the row (and this cog with it) is hidden by the widget factory.
    local function AttachCropCog(region)
        CludesUI.BuildInlineCog(region, {
            disabled = function() return (BarList().iconShape or "none") ~= "cropped" end,
            disabledTooltip = "This option requires Custom Icon Shape to be set to Cropped",
            title = "Custom Icon Shape",
            rows = {
                {
                    type = "slider",
                    label = "Adjust Crop",
                    min = 5,
                    max = 25,
                    step = 1,
                    tooltip = "How much is trimmed from the icon's top and bottom, as a percentage per side. 10% is the classic cropped look.",
                    get = function() return mod.CdmCropPercent(BarList()) end,
                    set = function(value)
                        local edge = BarList()
                        edge.iconCropPercent = value
                        -- Icon height changes: drop the same match caches the shape setter drops.
                        ClearMatchDims(edge)
                        RebuildBars(true)
                    end,
                },
            },
        })
    end

    -- Shape dropdown values
    local SHAPE_VALUES = {
        none = "None",
        cropped = "Cropped",
        square = "Square",
        circle = "Circle",
        csquare = "Curved Square",
        diamond = "Diamond",
        hexagon = "Hexagon",
        portrait = "Portrait",
        shield = "Shield",
    }
    local SHAPE_ORDER = {
        "none",
        "cropped",
        "---",
        "square",
        "circle",
        "csquare",
        "diamond",
        "hexagon",
        "portrait",
        "shield",
    }

    -- Border thickness dropdown
    local BORDER_LABELS =
        { none = "None", thin = "Thin", normal = "Normal", heavy = "Heavy", strong = "Strong" }
    local BORDER_ORDER = { "none", "thin", "normal", "heavy", "strong" }
    local BORDER_SIZES = { none = 0, thin = 1, normal = 2, heavy = 3, strong = 4 }

    -- The Icon Shape, Icon Zoom and Border Style sync icons, the same in
    -- the buff-bar layout and the regular one.
    local function IconShapeSync(region)
        if CludesUI._prebuilding then return end
        CludesUI.BuildSyncIcon({
            region = region,
            tooltip = "Apply Icon Shape to all Bars",
            isSynced = function()
                local edge = BarList()
                local value = edge.iconShape or "none"
                local zoom = edge.iconZoom or 0.08
                local crop = mod.CdmCropPercent(edge)
                local inSync = true
                ForEachSyncBar(function(bar)
                    if
                        (bar.iconShape or "none") ~= value
                        or (bar.iconZoom or 0.08) ~= zoom
                        or mod.CdmCropPercent(bar) ~= crop
                    then
                        inSync = false
                    end
                end)
                return inSync
            end,
            onClick = function()
                local edge = BarList()
                local value = edge.iconShape or "none"
                local zoom = edge.iconZoom or 0.08
                local crop = edge.iconCropPercent
                ForEachSyncBar(function(bar)
                    bar.iconShape = value
                    bar.iconZoom = zoom
                    bar.iconCropPercent = crop
                    local isCS = (value ~= "none" and value ~= "cropped")
                    if isCS then
                        bar.borderThickness = "strong"
                        bar.borderSize = BORDER_SIZES["strong"]
                    else
                        bar.borderThickness = "thin"
                        bar.borderSize = BORDER_SIZES["thin"]
                    end
                    ClearMatchDims(bar)
                end)
                RebuildBars(true)
                CludesUI:RefreshPage()
            end,
        })
    end
    local function IconZoomSync(region)
        if CludesUI._prebuilding then return end
        CludesUI.BuildSyncIcon({
            region = region,
            tooltip = "Apply Icon Zoom to all Bars",
            isSynced = function()
                local value = BarList().iconZoom or 0.08
                local inSync = true
                ForEachSyncBar(function(bar)
                    if (bar.iconZoom or 0.08) ~= value then inSync = false end
                end)
                return inSync
            end,
            onClick = function()
                local value = BarList().iconZoom or 0.08
                ForEachSyncBar(function(bar) bar.iconZoom = value end)
                RebuildBars()
                CludesUI:RefreshPage()
            end,
        })
    end
    local function BorderStyleSync(region)
        if CludesUI._prebuilding then return end
        CludesUI.BuildSyncIcon({
            region = region,
            tooltip = "Apply Border Style to all Bars",
            onClick = function()
                local edge = BarList()
                local bt = edge.borderTexture or "solid"
                local ox = edge.borderTextureOffset
                local oy = edge.borderTextureOffsetY
                local sx = edge.borderTextureShiftX
                local sy = edge.borderTextureShiftY
                local th = edge.borderThickness or "thin"
                local sz = edge.borderSize or 1
                local px = edge.borderSizePx
                local bh = edge.borderBehind
                local br, backdrop, bb, ba = edge.borderR, edge.borderG, edge.borderB, edge.borderA
                local classColor = edge.borderClassColor
                ForEachSyncBar(function(bar)
                    bar.borderTexture = bt
                    bar.borderTextureOffset = ox
                    bar.borderTextureOffsetY = oy
                    bar.borderTextureShiftX = sx
                    bar.borderTextureShiftY = sy
                    bar.borderThickness = th
                    bar.borderSize = sz
                    local pxv = px
                    if pxv == nil and bar.borderSizePx ~= nil then pxv = false end
                    bar.borderSizePx = pxv
                    bar.borderBehind = bh
                    bar.borderR = br
                    bar.borderG = backdrop
                    bar.borderB = bb
                    bar.borderA = ba
                    bar.borderClassColor = classColor
                end)
                RebuildBars()
                CludesUI:RefreshPage()
            end,
            isSynced = function()
                local edge = BarList()
                local bt = edge.borderTexture or "solid"
                local ox = edge.borderTextureOffset
                local oy = edge.borderTextureOffsetY
                local sx = edge.borderTextureShiftX
                local sy = edge.borderTextureShiftY
                local bh = edge.borderBehind or false
                local inSync = true
                ForEachSyncBar(function(bar)
                    if (bar.borderTexture or "solid") ~= bt then inSync = false end
                    if bar.borderTextureOffset ~= ox or bar.borderTextureOffsetY ~= oy then inSync = false end
                    if bar.borderTextureShiftX ~= sx or bar.borderTextureShiftY ~= sy then inSync = false end
                    if (bar.borderBehind or false) ~= bh then inSync = false end
                end)
                return inSync
            end,
        })
    end

    local buffGlowBar = isBuffBar or (barInfo.barType == "custom_buff")
    local scaleAnimRow
    if buffGlowBar then
        -- Row 1: Always Show Buffs (native buff bars only) | Icon Scale.
        -- Per-bar now: shows a greyed placeholder icon for each inactive
        -- tracked buff. No edit-mode change, no reload. custom_buff bars
        -- draw their own always-on icons, so the toggle is hidden there.
        local row1Left
        if isBuffBar then
            row1Left = {
                type = "toggle",
                text = "Always Show Buffs",
                -- Mutually exclusive with "Keep Buffs in Same Place" (Bar Layout).
                -- Disabled while that is the active choice. The extra
                -- "and showInactiveBuffIcons ~= true" keeps a legacy both-on profile
                -- unlockable: this toggle stays enabled so it can be turned off.
                disabled = function()
                    local barData = BarList()
                    return barData.hidePlaceholderIcon == true and barData.showInactiveBuffIcons ~= true
                end,
                disabledTooltip = "Disabled while Keep Buffs in Same Place is enabled",
                rawTooltip = true,
                getValue = BDFieldIs("showInactiveBuffIcons"),
                setValue = function(value)
                    BarList().showInactiveBuffIcons = value
                    RebuildBars(true)
                    CludesUI:RefreshPage()
                end,
            }
        else
            row1Left = { type = "label", text = "" }
        end
        local icsWDis, icsWTip, icsWRaw = CludesUI.MatchGuard("CDM_" .. barId, "Width")
        local icsHDis, icsHTip = CludesUI.MatchGuard("CDM_" .. barId, "Height")
        local icsDis = function() return icsWDis() or icsHDis() end
        local icsTip = function()
            if icsWDis() then return icsWTip() end
            if icsHDis() then return icsHTip() end
            return false
        end
        scaleAnimRow, height = W:DualRow(hostFrame, cursorY, row1Left, {
            type = "slider",
            text = "Icon Scale",
            min = 16,
            max = 100,
            step = 1,
            disabled = icsDis,
            disabledTooltip = icsTip,
            rawTooltip = true,
            getValue = BDFieldOr("iconSize", 36),
            setValue = function(value)
                local edge = BarList()
                edge.iconSize = value
                edge._matchPhysWidth = nil
                edge._matchPhysHeight = nil
                ClearMatchDims(edge)
                RebuildBars(true)
            end,
        })
        cursorY = cursorY - height

        -- Inline cog on Always Show Buffs toggle (per-bar; native buff bars)
        if isBuffBar then
            local leftRegion = scaleAnimRow._leftRegion
            CludesUI.BuildInlineCog(leftRegion, {
                anchorTo = leftRegion._control,
                disabled = function() return not BarList().showInactiveBuffIcons end,
                disabledTooltip = "Always Show Buffs",
                title = "Always Show Buffs",
                rows = {
                    {
                        type = "toggle",
                        label = "Desaturate Off CD",
                        get = function() return BarList().desaturateInactiveBuffs ~= false end,
                        set = BDField("desaturateInactiveBuffs"),
                    },
                },
            })
        end

        -- Row 2: Buff Glow + swatches | Icon Spacing. The Glows page's Buff Glow
        -- descriptor over this bar: a custom icon shape locks it (shown as None),
        -- and its Pixel Glow parameters keep their own row below (per-icon Buff
        -- Glows read them too), so this row takes the swatches only.
        local GO = CludesUI.GlowOptions
        local buffGlowDesc = mod._CDM_BuffGlowDesc(BarList, function()
            mod.BuildAllCDMBars()
            Refresh()
        end)
        buffGlowDesc.caps = { mode = true }
        buffGlowDesc.isOff, buffGlowDesc.disabled = CustomShapeOn, CustomShapeOn
        buffGlowDesc.disabledTooltip = "This option requires a non-custom button shape"
        local buffGlowRow
        buffGlowRow, height = W:DualRow(hostFrame, cursorY, GO.DropdownSpec(buffGlowDesc, "Buff Glow"), {
            type = "slider",
            pixel = true,
            text = "Icon Spacing",
            min = -10,
            max = 20,
            step = 1,
            getValue = BDFieldOr("spacing", 2),
            setValue = function(value)
                local edge = BarList()
                edge.spacing = value
                ClearMatchDims(edge)
                RebuildBars(true)
            end,
        })
        cursorY = cursorY - height
        GO.AttachInline(buffGlowRow._leftRegion, buffGlowDesc)

        -- (Pixel Glow Thickness / Lines / Speed moved to a dedicated row at the
        -- bottom of this section -- see "Pixel Glow Thickness (buff bars)" below.
        -- Same buffGlow* variables, so user settings are unchanged.)

        -- Row 3: Custom Icon Shape | Icon Zoom
        local buffShapeZoomRow
        buffShapeZoomRow, height = W:DualRow(
            hostFrame,
            cursorY,
            CludesUI.BlizzStyle.Gate("cdmicons", {
                type = "dropdown",
                text = "Custom Icon Shape",
                values = SHAPE_VALUES,
                order = SHAPE_ORDER,
                itemDisabled = function(value)
                    if
                        value ~= "none"
                        and value ~= "cropped"
                        and (BarList().borderTexture or "solid") ~= "solid"
                    then
                        return true
                    end
                    return false
                end,
                itemDisabledTooltip = function(value)
                    if
                        value ~= "none"
                        and value ~= "cropped"
                        and (BarList().borderTexture or "solid") ~= "solid"
                    then
                        return "This option requires the Border Style to be set to Solid"
                    end
                end,
                getValue = BDFieldOr("iconShape", "none"),
                setValue = function(value)
                    local edge = BarList()
                    edge.iconShape = value
                    edge.iconZoom = mod.CDM_SHAPE_ZOOM_DEFAULTS[value] or 0.08
                    local isCS = (value ~= "none" and value ~= "cropped")
                    if isCS then
                        edge.borderThickness = "strong"
                        edge.borderSize = BORDER_SIZES["strong"]
                        edge.activeStateAnim = "blizzard"
                    else
                        edge.borderThickness = "thin"
                        edge.borderSize = BORDER_SIZES["thin"]
                    end
                    ClearMatchDims(edge)
                    RebuildBars(true)
                    -- The Border Size slot is a different control under a custom shape: rebuild the page.
                    CludesUI:RefreshPage(true)
                end,
            }),
            CludesUI.BlizzStyle.Gate("cdmicons", {
                type = "slider",
                text = "Icon Zoom",
                min = 0,
                max = 0.20,
                step = 0.01,
                getValue = BDFieldOr("iconZoom", 0.08),
                setValue = function(value)
                    BarList().iconZoom = value
                    mod.RefreshCDMIconAppearance(BarList().key)
                    Refresh()
                    UpdateCDMPreview()
                end,
            })
        )
        cursorY = cursorY - height

        AttachCropCog(buffShapeZoomRow._leftRegion)

        -- Sync icon on Custom Icon Shape (left of row 3)
        IconShapeSync(buffShapeZoomRow._leftRegion)
        -- Sync icon on Icon Zoom (right of row 3)
        IconZoomSync(buffShapeZoomRow._rightRegion)

        -- Row 4: Border Size + swatches | Border Style dropdown + offset cog
        do
            local texValues, texOrder = CludesUI.GetBorderTextureDropdown()
            local buffBsRow
            -- Border Size: the exact-size slider, except under a custom shape, whose
            -- ring is on (Strong) or off (None): that keeps the None..Strong dropdown.
            local buffSizeCfg
            if CustomShapeOn() then
                buffSizeCfg = {
                    type = "dropdown",
                    text = "Border Size",
                    values = BORDER_LABELS,
                    order = BORDER_ORDER,
                    itemDisabled = function(value)
                        if CustomShapeOn() and (value == "thin" or value == "normal" or value == "heavy") then
                            return true
                        end
                        return false
                    end,
                    itemDisabledTooltip = function(value)
                        if CustomShapeOn() and (value == "thin" or value == "normal" or value == "heavy") then
                            return "This option requires a non-custom shape to be selected"
                        end
                    end,
                    getValue = BDFieldOr("borderThickness", "thin"),
                    setValue = function(value)
                        BarList().borderThickness = value
                        BarList().borderSize = BORDER_SIZES[value] or 1
                        RebuildBars()
                    end,
                }
            else
                buffSizeCfg = CludesUI.BorderPxSliderCfg({
                    text = "Border Size",
                    getStep = function() return BarList().borderSize or 1 end,
                    setStep = function(step)
                        local edge = BarList()
                        edge.borderThickness = CludesUI.BORDER_LABEL_OF_STEP[step] or "thin"
                        edge.borderSize = step
                    end,
                    getTex = function() return BarList().borderTexture or "solid" end,
                    getPx = function() return BarList().borderSizePx end,
                    setPx = function(value) BarList().borderSizePx = value end,
                    apply = function() RebuildBars() end,
                })
            end
            buffBsRow, height = W:DualRow(
                hostFrame,
                cursorY,
                CludesUI.BlizzStyle.Gate("cdmicons", buffSizeCfg),
                CludesUI.BlizzStyle.Gate("cdmicons", {
                    type = "dropdown",
                    text = "Border Style",
                    disabled = function() return CustomShapeOn() end,
                    disabledTooltip = "This option requires a non-custom button shape",
                    values = texValues,
                    order = texOrder,
                    getValue = BDFieldOr("borderTexture", "solid"),
                    setValue = function(value)
                        local edge = BarList()
                        edge.borderTexture = value
                        edge.borderTextureOffset = nil
                        edge.borderTextureOffsetY = nil
                        edge.borderTextureShiftX = nil
                        edge.borderTextureShiftY = nil
                        local _bcol, _bbehind = CludesUI.GetBorderStyleSelectDefaults(value)
                        edge.borderR = _bcol.r
                        edge.borderG = _bcol.g
                        edge.borderB = _bcol.b
                        edge.borderA = 1
                        edge.borderClassColor = false
                        edge.borderBehind = _bbehind
                        local defTh = CludesUI.GetBorderDefaultSize("cdm", value)
                        -- An unregistered SharedMedia border defaults to the NUMBER 1: store its label.
                        if type(defTh) == "number" then
                            defTh = CludesUI.BORDER_LABEL_OF_STEP[defTh] or "thin"
                        end
                        if defTh then
                            edge.borderThickness = defTh
                            edge.borderSize = BORDER_SIZES[defTh] or 1
                        end
                        if edge.borderSizePx then edge.borderSizePx = false end
                        RebuildBars()
                        CludesUI:RefreshPage(true)
                    end,
                })
            )
            cursorY = cursorY - height
            -- Width Offset | Height Offset: the textured border's outward offsets,
            -- present only while a textured style is selected (built on the
            -- prebuild pass too, so the y advance is identical). Disabled under a
            -- custom shape exactly like the Border Style dropdown it belongs to.
            do
                local tex0 = BarList().borderTexture or "solid"
                if tex0 ~= "" and tex0 ~= "solid" then
                    local ocfgL, ocfgR = CludesUI.BorderOffsetRowCfgs({
                        addonKey = "cdm",
                        disabled = function() return CustomShapeOn() end,
                        disabledTooltip = "This option requires a non-custom button shape",
                        getTex = function() return BarList().borderTexture or "solid" end,
                        getStep = function() return BarList().borderSize or 1 end,
                        getSizeKey = function() return BarList().borderThickness or "thin" end,
                        getPx = function() return BarList().borderSizePx end,
                        getX = function() return BarList().borderTextureOffset end,
                        setX = function(value) BarList().borderTextureOffset = value end,
                        getY = function() return BarList().borderTextureOffsetY end,
                        setY = function(value) BarList().borderTextureOffsetY = value end,
                        apply = function() RebuildBars() end,
                    })
                    _, height = W:DualRow(
                        hostFrame,
                        cursorY,
                        CludesUI.BlizzStyle.Gate("cdmicons", ocfgL),
                        CludesUI.BlizzStyle.Gate("cdmicons", ocfgR)
                    )
                    cursorY = cursorY - height
                end
            end
            -- Inline cog for border offset
            if not CludesUI._prebuilding then
                local region = buffBsRow._rightRegion
                local cogBtn = CludesUI.BuildInlineCog(region, {
                    title = "Border Options",
                    rows = {
                        {
                            type = "slider",
                            label = "Shift X",
                            min = -10,
                            max = 10,
                            step = 1,
                            get = function()
                                local value = BarList().borderTextureShiftX
                                if value then return value end
                                local edge = BarList()
                                local texture = edge.borderTexture or "solid"
                                local th = edge.borderThickness or "thin"
                                local _, _, dsx = CludesUI.GetBorderDefaults("cdm", texture, th)
                                return dsx
                            end,
                            set = function(value)
                                BarList().borderTextureShiftX = value == 0 and nil or value
                                RebuildBars()
                            end,
                        },
                        {
                            type = "slider",
                            label = "Shift Y",
                            min = -10,
                            max = 10,
                            step = 1,
                            get = function()
                                local value = BarList().borderTextureShiftY
                                if value then return value end
                                local edge = BarList()
                                local texture = edge.borderTexture or "solid"
                                local th = edge.borderThickness or "thin"
                                local _, _, _, dsy = CludesUI.GetBorderDefaults("cdm", texture, th)
                                return dsy
                            end,
                            set = function(value)
                                BarList().borderTextureShiftY = value == 0 and nil or value
                                RebuildBars()
                            end,
                        },
                        {
                            type = "toggle",
                            label = "Show Behind",
                            get = BDFieldOr("borderBehind", false),
                            set = function(value)
                                BarList().borderBehind = value == false and nil or value
                                RebuildBars()
                                CludesUI:RefreshPage()
                            end,
                        },
                    },
                })
                local function SyncBorderCog()
                    local texture = BarList().borderTexture or "solid"
                    if texture == "solid" or CludesUI.BlizzStyle.Get("cdmicons") then
                        cogBtn:Hide()
                    else
                        cogBtn:Show()
                    end
                end
                CludesUI.RegisterWidgetRefresh(SyncBorderCog)
                SyncBorderCog()
            end
            -- Inline border color swatches on Border Size (left region of row 4)
            if not CludesUI._prebuilding then
                local leftRegion = buffBsRow._leftRegion
                local control = leftRegion._control

                local classBorderSwatch, updateClassBorderSwatch = CludesUI.BuildColorSwatch(
                    leftRegion,
                    buffBsRow:GetFrameLevel() + 3,
                    function()
                        local _, class = UnitClass("player")
                        local classColor = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
                        if classColor then return classColor.r, classColor.g, classColor.b end
                        return 1, 1, 1
                    end,
                    function() end,
                    false,
                    20
                )
                Pix.Point(classBorderSwatch, "RIGHT", control, "LEFT", -8, 0)
                classBorderSwatch:SetScript("OnClick", function()
                    if CludesUI.BlizzStyle.Get("cdmicons") then return end
                    BarList().borderClassColor = true
                    mod.RefreshCDMIconAppearance(BarList().key)
                    Refresh()
                    UpdateCDMPreview()
                    CludesUI:RefreshPage()
                end)
                CludesUI.HoverTip(classBorderSwatch, "Class Colored")

                local UpdateBorderState
                local colorSwatch, updateSwatch = CludesUI.BuildColorSwatch(
                    leftRegion,
                    buffBsRow:GetFrameLevel() + 3,
                    function() return BarList().borderR or 0, BarList().borderG or 0, BarList().borderB or 0 end,
                    function(red, green, blue)
                        -- Picking a color always switches off class color so the chosen custom color actually applies.
                        BarList().borderClassColor = false
                        BarList().borderR, BarList().borderG, BarList().borderB = red, green, blue
                        mod.RefreshCDMIconAppearance(BarList().key)
                        Refresh()
                        UpdateCDMPreview()
                    end,
                    false,
                    20
                )
                Pix.Point(colorSwatch, "RIGHT", classBorderSwatch, "LEFT", -8, 0)
                CludesUI.HoverTip(colorSwatch, "Custom Colored")

                -- Clicking the custom swatch switches class color off AND opens
                -- the color picker in the same click (a toggle-only first click
                -- leaves the border black and the swatch looking stuck).
                local origClick = colorSwatch:GetScript("OnClick")
                colorSwatch:SetScript("OnClick", function(self, ...)
                    -- No border selected (or Blizzard Style): don't open the color picker
                    if
                        (BarList().borderThickness or "thin") == "none" or CludesUI.BlizzStyle.Get("cdmicons")
                    then
                        return
                    end
                    if BarList().borderClassColor then
                        BarList().borderClassColor = false
                        mod.RefreshCDMIconAppearance(BarList().key)
                        Refresh()
                        UpdateCDMPreview()
                        updateSwatch()
                        UpdateBorderState()
                    end
                    if origClick then origClick(self, ...) end
                end)

                function UpdateBorderState()
                    local isClassColored = BarList().borderClassColor
                    local isNone = (BarList().borderThickness or "thin") == "none"
                        or CludesUI.BlizzStyle.Get("cdmicons")
                    colorSwatch:SetAlpha((isClassColored or isNone) and 0.3 or 1)
                    classBorderSwatch:SetAlpha((isClassColored and not isNone) and 1 or 0.3)
                end
                CludesUI.RegisterWidgetRefresh(function()
                    updateSwatch()
                    updateClassBorderSwatch()
                    UpdateBorderState()
                end)
                UpdateBorderState()
            end
            -- Sync icon: Border Size (left region)
            if not CludesUI._prebuilding then
                CludesUI.BuildSyncIcon({
                    region = buffBsRow._leftRegion,
                    tooltip = "Apply Border Size to all Bars",
                    isSynced = function()
                        local edge = BarList()
                        local value = edge.borderThickness or "thin"
                        local px = edge.borderSizePx or false
                        local classColor = edge.borderClassColor
                        local inSync = true
                        ForEachSyncBar(function(bar)
                            if
                                (bar.borderThickness or "thin") ~= value
                                or (bar.borderSizePx or false) ~= px
                                or bar.borderClassColor ~= classColor
                            then
                                inSync = false
                            end
                        end)
                        return inSync
                    end,
                    onClick = function()
                        local edge = BarList()
                        local value = edge.borderThickness or "thin"
                        local sz = edge.borderSize or 1
                        local px = edge.borderSizePx
                        local classColor = edge.borderClassColor
                        ForEachSyncBar(function(bar)
                            bar.borderThickness = value
                            bar.borderSize = sz
                            local pxv = px
                            if pxv == nil and bar.borderSizePx ~= nil then pxv = false end
                            bar.borderSizePx = pxv
                            bar.borderClassColor = classColor
                        end)
                        RebuildBars()
                        CludesUI:RefreshPage()
                    end,
                })
            end
            -- Sync icon: Border Style (right region)
            BorderStyleSync(buffBsRow._rightRegion)
        end
    else
        local icsWDis2, icsWTip2 = CludesUI.MatchGuard("CDM_" .. barId, "Width")
        local icsHDis2, icsHTip2 = CludesUI.MatchGuard("CDM_" .. barId, "Height")
        local icsDis2 = function() return icsWDis2() or icsHDis2() end
        local icsTip2 = function()
            if icsWDis2() then return icsWTip2() end
            if icsHDis2() then return icsHTip2() end
            return false
        end
        scaleAnimRow, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Icon Scale",
            min = 16,
            max = 100,
            step = 1,
            disabled = icsDis2,
            disabledTooltip = icsTip2,
            rawTooltip = true,
            getValue = BDFieldOr("iconSize", 36),
            setValue = function(value)
                local edge = BarList()
                edge.iconSize = value
                -- Manual iconSize override -- clear ALL match cache so the
                -- new value wins over any stored target width/height.
                edge._matchPhysWidth = nil
                edge._matchPhysHeight = nil
                ClearMatchDims(edge)
                RebuildBars(true)
            end,
        }, {
            type = "slider",
            pixel = true,
            text = "Icon Spacing",
            min = -10,
            max = 20,
            step = 1,
            getValue = BDFieldOr("spacing", 2),
            setValue = function(value)
                local edge = BarList()
                edge.spacing = value
                -- Spacing change invalidates the width/height match cache because the
                -- cached _matchIconPhys was computed against the old spacing -- new
                -- spacing means the icons no longer fit the matched bar dimension.
                ClearMatchDims(edge)
                RebuildBars(true)
            end,
        })
        cursorY = cursorY - height

        -- Sync icon on Icon Spacing (right of row 1)
        if not CludesUI._prebuilding then
            CludesUI.BuildSyncIcon({
                region = scaleAnimRow._rightRegion,
                tooltip = "Apply Icon Spacing to all Bars",
                isSynced = function()
                    local value = BarList().spacing or 2
                    local inSync = true
                    ForEachSyncBar(function(bar)
                        if (bar.spacing or 2) ~= value then inSync = false end
                    end)
                    return inSync
                end,
                onClick = function()
                    local value = BarList().spacing or 2
                    ForEachSyncBar(function(bar)
                        bar.spacing = value
                        -- Spacing change invalidates each bar's match cache.
                        ClearMatchDims(bar)
                    end)
                    RebuildBars(true)
                    CludesUI:RefreshPage()
                end,
            })
        end
    end -- isBuffBar else

    -- Inline cog on Icon Scale: Minimum Bar Size (growth-axis icon-slot
    -- reservation, user-directed to live here, not as a Bar Layout row). Placed
    -- AFTER the isBuffGlowBar branch: each side builds its own scaleAnimRow with
    -- Icon Scale in a different slot (right on buff-family rows, left elsewhere).
    -- The slider stays editable: the runtime skips the reservation while the
    -- growth axis is width/height matched, so no MatchGuard lock is needed.
    -- Orientation resolves at build time; the page rebuilds on flips. FocusKick is
    -- excluded: it is nameplate-anchored, nothing matches or anchors to its edges.
    if not focusKickBar then
        local minVert = BarList().verticalOrientation == true
        local region = buffGlowBar and scaleAnimRow._rightRegion or scaleAnimRow._leftRegion
        CludesUI.BuildInlineCog(region, {
            title = minVert and "Minimum Height" or "Minimum Width",
            rows = {
                {
                    type = "slider",
                    label = minVert and "Icon Slots Tall (0 = Off)" or "Icon Slots Wide (0 = Off)",
                    min = 0,
                    max = 20,
                    step = 1,
                    get = BDFieldOr("minSizeIcons", 0),
                    set = function(value)
                        if value == 0 then value = nil end
                        local edge = BarList()
                        edge.minSizeIcons = value
                        -- Growth-axis extent changed: cached match dims stale.
                        ClearMatchDims(edge)
                        RebuildBars(true)
                    end,
                },
            },
        })
    end

    -- Border Style dropdown (CD/utility and non-buff bars only)
    if not buffGlowBar then
        do
            local texValues, texOrder = CludesUI.GetBorderTextureDropdown()
            local bsRow
            -- Border Size: the exact-size slider, except under a custom shape, whose
            -- ring is on (Strong) or off (None): that keeps the None..Strong dropdown.
            local sizeCfg
            if CustomShapeOn() then
                sizeCfg = {
                    type = "dropdown",
                    text = "Border Size",
                    values = BORDER_LABELS,
                    order = BORDER_ORDER,
                    itemDisabled = function(value)
                        if CustomShapeOn() and (value == "thin" or value == "normal" or value == "heavy") then
                            return true
                        end
                        return false
                    end,
                    itemDisabledTooltip = function(value)
                        if CustomShapeOn() and (value == "thin" or value == "normal" or value == "heavy") then
                            return "This option requires a non-custom shape to be selected"
                        end
                    end,
                    getValue = BDFieldOr("borderThickness", "thin"),
                    setValue = function(value)
                        BarList().borderThickness = value
                        BarList().borderSize = BORDER_SIZES[value] or 1
                        RebuildBars()
                    end,
                }
            else
                sizeCfg = CludesUI.BorderPxSliderCfg({
                    text = "Border Size",
                    getStep = function() return BarList().borderSize or 1 end,
                    setStep = function(step)
                        local edge = BarList()
                        edge.borderThickness = CludesUI.BORDER_LABEL_OF_STEP[step] or "thin"
                        edge.borderSize = step
                    end,
                    getTex = function() return BarList().borderTexture or "solid" end,
                    getPx = function() return BarList().borderSizePx end,
                    setPx = function(value) BarList().borderSizePx = value end,
                    apply = function() RebuildBars() end,
                })
            end
            bsRow, height = W:DualRow(
                hostFrame,
                cursorY,
                CludesUI.BlizzStyle.Gate("cdmicons", {
                    type = "dropdown",
                    text = "Border Style",
                    disabled = function() return CustomShapeOn() end,
                    disabledTooltip = "This option requires a non-custom button shape",
                    values = texValues,
                    order = texOrder,
                    getValue = BDFieldOr("borderTexture", "solid"),
                    setValue = function(value)
                        local edge = BarList()
                        edge.borderTexture = value
                        edge.borderTextureOffset = nil
                        edge.borderTextureOffsetY = nil
                        edge.borderTextureShiftX = nil
                        edge.borderTextureShiftY = nil
                        local _bcol, _bbehind = CludesUI.GetBorderStyleSelectDefaults(value)
                        edge.borderR = _bcol.r
                        edge.borderG = _bcol.g
                        edge.borderB = _bcol.b
                        edge.borderA = 1
                        edge.borderClassColor = false
                        edge.borderBehind = _bbehind
                        local defTh = CludesUI.GetBorderDefaultSize("cdm", value)
                        -- An unregistered SharedMedia border defaults to the NUMBER 1: store its label.
                        if type(defTh) == "number" then
                            defTh = CludesUI.BORDER_LABEL_OF_STEP[defTh] or "thin"
                        end
                        if defTh then
                            edge.borderThickness = defTh
                            edge.borderSize = BORDER_SIZES[defTh] or 1
                        end
                        if edge.borderSizePx then edge.borderSizePx = false end
                        RebuildBars()
                        CludesUI:RefreshPage(true)
                    end,
                }),
                CludesUI.BlizzStyle.Gate("cdmicons", sizeCfg)
            )
            cursorY = cursorY - height
            -- Width Offset | Height Offset: the textured border's outward offsets,
            -- present only while a textured style is selected (built on the
            -- prebuild pass too, so the y advance is identical). Disabled under a
            -- custom shape exactly like the Border Style dropdown it belongs to.
            do
                local tex0 = BarList().borderTexture or "solid"
                if tex0 ~= "" and tex0 ~= "solid" then
                    local ocfgL, ocfgR = CludesUI.BorderOffsetRowCfgs({
                        addonKey = "cdm",
                        disabled = function() return CustomShapeOn() end,
                        disabledTooltip = "This option requires a non-custom button shape",
                        getTex = function() return BarList().borderTexture or "solid" end,
                        getStep = function() return BarList().borderSize or 1 end,
                        getSizeKey = function() return BarList().borderThickness or "thin" end,
                        getPx = function() return BarList().borderSizePx end,
                        getX = function() return BarList().borderTextureOffset end,
                        setX = function(value) BarList().borderTextureOffset = value end,
                        getY = function() return BarList().borderTextureOffsetY end,
                        setY = function(value) BarList().borderTextureOffsetY = value end,
                        apply = function() RebuildBars() end,
                    })
                    _, height = W:DualRow(
                        hostFrame,
                        cursorY,
                        CludesUI.BlizzStyle.Gate("cdmicons", ocfgL),
                        CludesUI.BlizzStyle.Gate("cdmicons", ocfgR)
                    )
                    cursorY = cursorY - height
                end
            end
            -- Inline cog for border offset
            if not CludesUI._prebuilding then
                local region = bsRow._leftRegion
                local cogBtn = CludesUI.BuildInlineCog(region, {
                    title = "Border Options",
                    rows = {
                        {
                            type = "slider",
                            label = "Shift X",
                            min = -10,
                            max = 10,
                            step = 1,
                            get = function()
                                local value = BarList().borderTextureShiftX
                                if value then return value end
                                local edge = BarList()
                                local texture = edge.borderTexture or "solid"
                                local th = edge.borderThickness or "thin"
                                local _, _, dsx = CludesUI.GetBorderDefaults("cdm", texture, th)
                                return dsx
                            end,
                            set = function(value)
                                BarList().borderTextureShiftX = value == 0 and nil or value
                                RebuildBars()
                            end,
                        },
                        {
                            type = "slider",
                            label = "Shift Y",
                            min = -10,
                            max = 10,
                            step = 1,
                            get = function()
                                local value = BarList().borderTextureShiftY
                                if value then return value end
                                local edge = BarList()
                                local texture = edge.borderTexture or "solid"
                                local th = edge.borderThickness or "thin"
                                local _, _, _, dsy = CludesUI.GetBorderDefaults("cdm", texture, th)
                                return dsy
                            end,
                            set = function(value)
                                BarList().borderTextureShiftY = value == 0 and nil or value
                                RebuildBars()
                            end,
                        },
                        {
                            type = "toggle",
                            label = "Show Behind",
                            get = BDFieldOr("borderBehind", false),
                            set = function(value)
                                BarList().borderBehind = value == false and nil or value
                                RebuildBars()
                                CludesUI:RefreshPage()
                            end,
                        },
                    },
                })
                local function SyncBorderCog()
                    local texture = BarList().borderTexture or "solid"
                    if texture == "solid" or CludesUI.BlizzStyle.Get("cdmicons") then
                        cogBtn:Hide()
                    else
                        cogBtn:Show()
                    end
                end
                CludesUI.RegisterWidgetRefresh(SyncBorderCog)
                SyncBorderCog()
            end
            -- Sync icon: Border Style (left region of bsRow)
            BorderStyleSync(bsRow._leftRegion)
            -- Inline color swatches on Border Size (right region)
            if not CludesUI._prebuilding then
                local rightRegion = bsRow._rightRegion
                local control = rightRegion._control

                -- Class color swatch (rightmost)
                local classBorderSwatch, updateClassBorderSwatch = CludesUI.BuildColorSwatch(
                    rightRegion,
                    bsRow:GetFrameLevel() + 3,
                    function()
                        local _, class = UnitClass("player")
                        local classColor = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
                        if classColor then return classColor.r, classColor.g, classColor.b end
                        return 1, 1, 1
                    end,
                    function() end,
                    false,
                    20
                )
                Pix.Point(classBorderSwatch, "RIGHT", control, "LEFT", -8, 0)
                classBorderSwatch:SetScript("OnClick", function()
                    if CludesUI.BlizzStyle.Get("cdmicons") then return end
                    BarList().borderClassColor = true
                    mod.RefreshCDMIconAppearance(BarList().key)
                    Refresh()
                    UpdateCDMPreview()
                    CludesUI:RefreshPage()
                end)
                CludesUI.HoverTip(classBorderSwatch, "Class Colored")

                -- Custom color swatch (left of class swatch)
                local colorSwatch, updateSwatch = CludesUI.BuildColorSwatch(
                    rightRegion,
                    bsRow:GetFrameLevel() + 3,
                    function() return BarList().borderR or 0, BarList().borderG or 0, BarList().borderB or 0 end,
                    function(red, green, blue)
                        BarList().borderR, BarList().borderG, BarList().borderB = red, green, blue
                        mod.RefreshCDMIconAppearance(BarList().key)
                        Refresh()
                        UpdateCDMPreview()
                    end,
                    false,
                    20
                )
                Pix.Point(colorSwatch, "RIGHT", classBorderSwatch, "LEFT", -8, 0)
                CludesUI.HoverTip(colorSwatch, "Custom Color")

                -- Click the dimmed custom swatch to switch back from class color (no block overlay)
                local origClick = colorSwatch:GetScript("OnClick")
                colorSwatch:SetScript("OnClick", function(self, ...)
                    if CludesUI.BlizzStyle.Get("cdmicons") then return end
                    if BarList().borderClassColor then
                        BarList().borderClassColor = false
                        mod.RefreshCDMIconAppearance(BarList().key)
                        Refresh()
                        UpdateCDMPreview()
                        CludesUI:RefreshPage()
                        return
                    end
                    -- No border selected: allow swapping boxes but do not open the color picker
                    if (BarList().borderThickness or "thin") == "none" then return end
                    if origClick then origClick(self, ...) end
                end)

                local function UpdateBorderSwatchState()
                    local isClassColored = BarList().borderClassColor
                    local isNone = (BarList().borderThickness or "thin") == "none"
                        or CludesUI.BlizzStyle.Get("cdmicons")
                    colorSwatch:SetAlpha((isClassColored or isNone) and 0.3 or 1)
                    classBorderSwatch:SetAlpha((isClassColored and not isNone) and 1 or 0.3)
                end
                CludesUI.RegisterWidgetRefresh(function()
                    updateSwatch()
                    updateClassBorderSwatch()
                    UpdateBorderSwatchState()
                end)
                UpdateBorderSwatchState()
            end
            -- Sync icon on Border Size (right region)
            if not CludesUI._prebuilding then
                CludesUI.BuildSyncIcon({
                    region = bsRow._rightRegion,
                    tooltip = "Apply Border Size to all Bars",
                    isSynced = function()
                        local edge = BarList()
                        local value = edge.borderThickness or "thin"
                        local px = edge.borderSizePx or false
                        local classColor = edge.borderClassColor
                        local bt = edge.borderTexture or "solid"
                        local sx = edge.borderTextureShiftX
                        local sy = edge.borderTextureShiftY
                        local br, backdrop, bb, ba =
                            edge.borderR or 0, edge.borderG or 0, edge.borderB or 0, edge.borderA or 1
                        local inSync = true
                        ForEachSyncBar(function(bar)
                            if
                                (bar.borderThickness or "thin") ~= value
                                or (bar.borderSizePx or false) ~= px
                                or bar.borderClassColor ~= classColor
                                or (bar.borderTexture or "solid") ~= bt
                            then
                                inSync = false
                            end
                            if bar.borderTextureShiftX ~= sx or bar.borderTextureShiftY ~= sy then
                                inSync = false
                            end
                            if
                                (bar.borderR or 0) ~= br
                                or (bar.borderG or 0) ~= backdrop
                                or (bar.borderB or 0) ~= bb
                                or (bar.borderA or 1) ~= ba
                            then
                                inSync = false
                            end
                        end)
                        return inSync
                    end,
                    onClick = function()
                        local edge = BarList()
                        local value = edge.borderThickness or "thin"
                        local sz = edge.borderSize or 1
                        local px = edge.borderSizePx
                        local classColor = edge.borderClassColor
                        local bt = edge.borderTexture or "solid"
                        local sx = edge.borderTextureShiftX
                        local sy = edge.borderTextureShiftY
                        local br, backdrop, bb, ba = edge.borderR, edge.borderG, edge.borderB, edge.borderA
                        ForEachSyncBar(function(bar)
                            bar.borderThickness = value
                            bar.borderSize = sz
                            local pxv = px
                            if pxv == nil and bar.borderSizePx ~= nil then pxv = false end
                            bar.borderSizePx = pxv
                            bar.borderClassColor = classColor
                            bar.borderTexture = bt
                            bar.borderTextureShiftX = sx
                            bar.borderTextureShiftY = sy
                            bar.borderR = br
                            bar.borderG = backdrop
                            bar.borderB = bb
                            bar.borderA = ba
                        end)
                        RebuildBars()
                        CludesUI:RefreshPage()
                    end,
                })
            end
        end
    end -- not isBuffGlowBar

    -- (Active Animation UI removed -- active state is now per-icon via spell picker dropdown)

    -- (Sync) Custom Icon Shape | (Sync) Icon Zoom (CD/utility bars only;
    -- buff bars have both in their own Row 3 above)
    if not buffGlowBar then
        local shapeRow
        shapeRow, height = W:DualRow(
            hostFrame,
            cursorY,
            CludesUI.BlizzStyle.Gate("cdmicons", {
                type = "dropdown",
                text = "Custom Icon Shape",
                values = SHAPE_VALUES,
                order = SHAPE_ORDER,
                itemDisabled = function(value)
                    if
                        value ~= "none"
                        and value ~= "cropped"
                        and (BarList().borderTexture or "solid") ~= "solid"
                    then
                        return true
                    end
                    return false
                end,
                itemDisabledTooltip = function(value)
                    if
                        value ~= "none"
                        and value ~= "cropped"
                        and (BarList().borderTexture or "solid") ~= "solid"
                    then
                        return "This option requires the Border Style to be set to Solid"
                    end
                end,
                getValue = BDFieldOr("iconShape", "none"),
                setValue = function(value)
                    local edge = BarList()
                    edge.iconShape = value
                    edge.iconZoom = mod.CDM_SHAPE_ZOOM_DEFAULTS[value] or 0.08
                    local isCS = (value ~= "none" and value ~= "cropped")
                    if isCS then
                        edge.borderThickness = "strong"
                        edge.borderSize = BORDER_SIZES["strong"]
                        edge.activeStateAnim = "blizzard"
                    else
                        edge.borderThickness = "thin"
                        edge.borderSize = BORDER_SIZES["thin"]
                    end
                    ClearMatchDims(edge)
                    RebuildBars(true)
                    -- The Border Size slot is a different control under a custom shape: rebuild the page.
                    CludesUI:RefreshPage(true)
                end,
            }),
            CludesUI.BlizzStyle.Gate("cdmicons", {
                type = "slider",
                text = "Icon Zoom",
                min = 0,
                max = 0.20,
                step = 0.01,
                getValue = BDFieldOr("iconZoom", 0.08),
                setValue = function(value)
                    BarList().iconZoom = value
                    mod.RefreshCDMIconAppearance(BarList().key)
                    Refresh()
                    UpdateCDMPreview()
                end,
            })
        )
        cursorY = cursorY - height

        AttachCropCog(shapeRow._leftRegion)

        IconShapeSync(shapeRow._leftRegion)
        IconZoomSync(shapeRow._rightRegion)
    end -- not isBuffGlowBar

    -- Row 4: Duration Size (cog + swatch) | Stack Size (cog + swatch)
    local durationRow
    durationRow, height = W:DualRow(hostFrame, cursorY, {
        type = "slider",
        text = "Duration Size",
        min = 6,
        max = 30,
        step = 1,
        trackWidth = 120,
        getValue = BDFieldOr("cooldownFontSize", 12),
        setValue = function(value)
            BarList().cooldownFontSize = value
            mod.RefreshCDMIconAppearance(BarList().key)
            Refresh()
            UpdateCDMPreview()
        end,
    }, {
        type = "slider",
        text = "Charge/Stack Size",
        min = 6,
        max = 30,
        step = 1,
        trackWidth = 120,
        getValue = BDFieldOr("stackCountSize", 11),
        setValue = function(value)
            BarList().stackCountSize = value
            mod.RefreshCDMIconAppearance(BarList().key)
            RebuildBars()
        end,
    })
    cursorY = cursorY - height

    -- Duration Size: inline cog + color swatch
    if not CludesUI._prebuilding then
        local leftRegion = durationRow._leftRegion
        local control = leftRegion._control
        CludesUI.BuildInlineCog(leftRegion, {
            title = "Duration Text",
            rows = {
                {
                    type = "toggle",
                    label = "Show Duration",
                    get = function() return BarList().showCooldownText ~= false end,
                    set = function(value)
                        BarList().showCooldownText = value
                        mod.RefreshCDMIconAppearance(BarList().key)
                        Refresh()
                        CludesUI:RefreshPage()
                    end,
                },
                {
                    type = "dropdown",
                    label = "Position",
                    values = durationPositionValues,
                    order = durationPositionOrder,
                    get = BDFieldOr("cooldownTextPosition", "center"),
                    set = function(value)
                        BarList().cooldownTextPosition = value
                        mod.RefreshCDMIconAppearance(BarList().key)
                        Refresh()
                        UpdateCDMPreview()
                    end,
                },
                {
                    type = "slider",
                    label = "X Offset",
                    min = -50,
                    max = 50,
                    step = 1,
                    get = BDFieldOr("cooldownTextX", 0),
                    set = function(value)
                        BarList().cooldownTextX = value
                        mod.RefreshCDMIconAppearance(BarList().key)
                        Refresh()
                    end,
                },
                {
                    type = "slider",
                    label = "Y Offset",
                    min = -50,
                    max = 50,
                    step = 1,
                    get = BDFieldOr("cooldownTextY", 0),
                    set = function(value)
                        BarList().cooldownTextY = value
                        mod.RefreshCDMIconAppearance(BarList().key)
                        Refresh()
                    end,
                },
            },
        })

        local durSwatch, updateDurSwatch = CludesUI.BuildColorSwatch(
            leftRegion,
            durationRow:GetFrameLevel() + 3,
            function()
                return BarList().cooldownTextR or 1,
                    BarList().cooldownTextG or 1,
                    BarList().cooldownTextB or 1
            end,
            function(red, green, blue)
                BarList().cooldownTextR = red
                BarList().cooldownTextG = green
                BarList().cooldownTextB = blue
                mod.RefreshCDMIconAppearance(BarList().key)
                Refresh()
                UpdateCDMPreview()
            end,
            false,
            20
        )
        Pix.Point(durSwatch, "RIGHT", leftRegion._lastInline or control, "LEFT", -8, 0)
        leftRegion._lastInline = durSwatch

        local durBlock = CludesUI.NewSwatchBlocker(durSwatch)
        durBlock:SetScript(
            "OnEnter",
            function() CludesUI.ShowWidgetTooltip(durSwatch, CludesUI.DisabledTooltip("Duration Text")) end
        )
        durBlock:SetScript("OnLeave", function() CludesUI.HideWidgetTooltip() end)
        CludesUI.RegisterWidgetRefresh(function()
            if updateDurSwatch then updateDurSwatch() end
            local enabled = BarList().showCooldownText ~= false
            durSwatch:SetAlpha(enabled and 1 or 0.3)
            if enabled then
                durBlock:Hide()
            else
                durBlock:Show()
            end
        end)
        local enabled = BarList().showCooldownText ~= false
        durSwatch:SetAlpha(enabled and 1 or 0.3)
        if enabled then
            durBlock:Hide()
        else
            durBlock:Show()
        end
    end

    -- Stack Size: inline cog + color swatch
    if not CludesUI._prebuilding then
        local rightRegion = durationRow._rightRegion
        local control = rightRegion._control
        local scPopupSpec = {
            title = "Charges/Stacks",
            rows = {
                -- View over the legacy showItemCount boolean (Never = false,
                -- Always = true/nil) plus the itemCountOOC flag for the new
                -- Out of Combat mode. OOC keeps showItemCount = true so every
                -- legacy reader treats it as "on"; the combat gate lives in
                -- the icon restyle. Zero migration.
                {
                    type = "dropdown",
                    label = "Show Item Count",
                    values = { never = "Never", always = "Always", ooc = "Out of Combat" },
                    order = { "never", "always", "ooc" },
                    get = function()
                        if BarList().itemCountOOC then return "ooc" end
                        return (BarList().showItemCount ~= false) and "always" or "never"
                    end,
                    set = function(value)
                        local edge = BarList()
                        edge.itemCountOOC = (value == "ooc") or nil
                        edge.showItemCount = (value ~= "never")
                        mod.RefreshCDMIconAppearance(edge.key)
                        RebuildBars()
                        CludesUI:RefreshPage()
                    end,
                },
                -- Crafted-rank pip on tracked items (ranks share icon art, so
                -- two ranks are otherwise indistinguishable). Off by default.
                {
                    type = "toggle",
                    label = "Show Item Quality",
                    tooltip = "Show the crafted quality rank on tracked items, matching the rank icon on the action bars. Items with no crafted quality are unaffected.",
                    get = BDFieldIs("showItemQuality"),
                    set = function(value)
                        BarList().showItemQuality = value
                        if mod.FullCDMRebuild then mod.FullCDMRebuild("item_quality_toggle") end
                    end,
                },
                -- Buff-family only (stripped below for cd/utility): those
                -- bars hide counters via the per-spell Hide Charge Text
                -- lane, which owns their counter alpha channel.
                {
                    type = "toggle",
                    label = "Show Charge/Stack Text",
                    tooltip = "Show the charge and stack counters on this bar's icons.",
                    get = function() return BarList().showChargeStackText ~= false end,
                    -- if/else, NOT `v and nil or false`: that expression is
                    -- ALWAYS false (the nil arm falls through the or).
                    set = function(value)
                        if value then
                            BarList().showChargeStackText = nil
                        else
                            BarList().showChargeStackText = false
                        end
                        mod.RefreshCDMIconAppearance(BarList().key)
                        Refresh()
                        UpdateCDMPreview()
                    end,
                },
                {
                    type = "dropdown",
                    label = "Position",
                    values = {
                        bottomright = "Bottom Right",
                        bottom = "Bottom",
                        bottomleft = "Bottom Left",
                        left = "Left",
                        topleft = "Top Left",
                        top = "Top",
                        topright = "Top Right",
                        right = "Right",
                        center = "Center",
                    },
                    order = {
                        "bottomright",
                        "bottom",
                        "bottomleft",
                        "left",
                        "topleft",
                        "top",
                        "topright",
                        "right",
                        "center",
                    },
                    get = BDFieldOr("stackCountPosition", "bottomright"),
                    set = function(value)
                        BarList().stackCountPosition = value
                        mod.RefreshCDMIconAppearance(BarList().key)
                        RebuildBars()
                    end,
                },
                {
                    type = "slider",
                    label = "X Offset",
                    min = -150,
                    max = 150,
                    step = 1,
                    get = BDFieldOr("stackCountX", 0),
                    set = function(value)
                        BarList().stackCountX = value
                        mod.RefreshCDMIconAppearance(BarList().key)
                        RebuildBars()
                    end,
                },
                {
                    type = "slider",
                    label = "Y Offset",
                    min = -150,
                    max = 150,
                    step = 1,
                    get = BDFieldOr("stackCountY", 0),
                    set = function(value)
                        BarList().stackCountY = value
                        mod.RefreshCDMIconAppearance(BarList().key)
                        RebuildBars()
                    end,
                },
            },
        }
        -- Show Charge/Stack Text (row 3) is buff-family only -- see its comment.
        if not buffGlowBar then table.remove(scPopupSpec.rows, 3) end
        CludesUI.BuildInlineCog(rightRegion, scPopupSpec)

        local scSwatch, updateScSwatch = CludesUI.BuildColorSwatch(
            rightRegion,
            durationRow:GetFrameLevel() + 3,
            function()
                return BarList().stackCountR or 1, BarList().stackCountG or 1, BarList().stackCountB or 1
            end,
            function(red, green, blue)
                BarList().stackCountR = red
                BarList().stackCountG = green
                BarList().stackCountB = blue
                mod.RefreshCDMIconAppearance(BarList().key)
                RebuildBars()
            end,
            false,
            20
        )
        Pix.Point(scSwatch, "RIGHT", rightRegion._lastInline or control, "LEFT", -8, 0)
        rightRegion._lastInline = scSwatch

        local scBlock = CludesUI.NewSwatchBlocker(scSwatch)
        scBlock:SetScript(
            "OnEnter",
            function() CludesUI.ShowWidgetTooltip(scSwatch, CludesUI.DisabledTooltip("Item Count")) end
        )
        scBlock:SetScript("OnLeave", function() CludesUI.HideWidgetTooltip() end)
        CludesUI.RegisterWidgetRefresh(function()
            if updateScSwatch then updateScSwatch() end
            local enabled = BarList().showItemCount ~= false
            scSwatch:SetAlpha(enabled and 1 or 0.3)
            if enabled then
                scBlock:Hide()
            else
                scBlock:Show()
            end
        end)
        local enabled = BarList().showItemCount ~= false
        scSwatch:SetAlpha(enabled and 1 or 0.3)
        if enabled then
            scBlock:Hide()
        else
            scBlock:Show()
        end
    end

    -- Suppress GCD (CD/utility bars only) | Pixel Glow Thickness (+ cog: Lines/Speed)
    if not buffGlowBar then
        if mod.CDM_BarHasPixelRow(barInfo) then
            local sgcdRow
            sgcdRow, height = W:DualRow(hostFrame, cursorY, {
                type = "toggle",
                text = "Suppress GCD",
                tooltip = "Hide the brief GCD swipe that flashes when you cast any spell. The actual ability cooldown swipe still shows.",
                getValue = BDFieldIs("suppressGCD"),
                setValue = function(value)
                    BarList().suppressGCD = value and true or false
                    Refresh()
                end,
            }, {
                type = "slider",
                text = "Pixel Glow Thickness",
                min = 1,
                max = 4,
                step = 1,
                trackWidth = 120,
                tooltip = "Thickness of any Pixel Glow assigned to this bar's buttons. Assign glows by right-clicking an icon in the preview.",
                getValue = BDFieldOr("pixelGlowThickness", 2),
                setValue = function(value)
                    BarList().pixelGlowThickness = value
                    mod.BuildAllCDMBars()
                    if mod.RequestBarGlowUpdate then mod.RequestBarGlowUpdate() end
                    Refresh()
                end,
            })
            cursorY = cursorY - height
            -- Inline cog on Pixel Glow Thickness: Lines + Speed
            if not CludesUI._prebuilding then
                local rightRegion = sgcdRow._rightRegion
                CludesUI.BuildInlineCog(rightRegion, {
                    title = "Pixel Glow",
                    rows = {
                        {
                            type = "slider",
                            label = "Lines",
                            min = 2,
                            max = 16,
                            step = 1,
                            get = BDFieldOr("pixelGlowLines", 8),
                            set = function(value)
                                BarList().pixelGlowLines = value
                                mod.BuildAllCDMBars()
                                if mod.RequestBarGlowUpdate then mod.RequestBarGlowUpdate() end
                            end,
                        },
                        {
                            type = "slider",
                            label = "Speed",
                            min = 1,
                            max = 8,
                            step = 1,
                            get = function() return 9 - (BarList().pixelGlowSpeed or 4) end,
                            set = function(value)
                                BarList().pixelGlowSpeed = 9 - value
                                mod.BuildAllCDMBars()
                                if mod.RequestBarGlowUpdate then mod.RequestBarGlowUpdate() end
                            end,
                        },
                        {
                            type = "toggle",
                            label = "Background",
                            get = BDFieldIs("pixelGlowBackground"),
                            set = function(value)
                                BarList().pixelGlowBackground = value and true or nil
                                mod.BuildAllCDMBars()
                                if mod.RequestBarGlowUpdate then mod.RequestBarGlowUpdate() end
                            end,
                        },
                        {
                            type = "colorpicker",
                            label = "Background Color",
                            get = function()
                                return BarList().pixelGlowBackgroundR or 0,
                                    BarList().pixelGlowBackgroundG or 0,
                                    BarList().pixelGlowBackgroundB or 0
                            end,
                            set = function(red, green, blue)
                                BarList().pixelGlowBackgroundR = red
                                BarList().pixelGlowBackgroundG = green
                                BarList().pixelGlowBackgroundB = blue
                                mod.BuildAllCDMBars()
                                if mod.RequestBarGlowUpdate then mod.RequestBarGlowUpdate() end
                            end,
                            disabled = function() return BarList().pixelGlowBackground ~= true end,
                            disabledTooltip = "Pixel Glow Background",
                        },
                    },
                })
            end
        end
    end

    -- Pixel Glow Thickness (buff bars) -- mirrors the CD/utility row above.
    -- Reuses the same buffGlow* variables so user settings are unchanged.
    -- Always enabled (no disabled state).
    if buffGlowBar then
        local pgRow
        pgRow, height = W:DualRow(hostFrame, cursorY, {
            type = "slider",
            text = "Pixel Glow Thickness",
            min = 1,
            max = 4,
            step = 1,
            trackWidth = 120,
            tooltip = "Thickness of the Pixel Glow applied to this bar's buff icons.",
            getValue = BDFieldOr("buffGlowThickness", 2),
            setValue = function(value)
                BarList().buffGlowThickness = value
                mod.BuildAllCDMBars()
                if mod.RefreshBuffGlows then mod.RefreshBuffGlows() end
                Refresh()
            end,
        }, {
            type = "toggle",
            text = "Only Show Numbers",
            tooltip = "Hide this bar's icons and show only the duration text.",
            getValue = BDFieldIs("onlyShowNumbers"),
            setValue = function(value)
                BarList().onlyShowNumbers = value and true or nil
                mod.BuildAllCDMBars()
                Refresh()
            end,
        })
        cursorY = cursorY - height
        -- Inline cog on Pixel Glow Thickness: Lines + Speed (buffGlow* vars)
        if not CludesUI._prebuilding then
            local leftRegion = pgRow._leftRegion
            CludesUI.BuildInlineCog(leftRegion, {
                title = "Pixel Glow",
                rows = {
                    {
                        type = "slider",
                        label = "Lines",
                        min = 2,
                        max = 16,
                        step = 1,
                        get = BDFieldOr("buffGlowLines", 8),
                        set = function(value)
                            BarList().buffGlowLines = value
                            mod.BuildAllCDMBars()
                            if mod.RefreshBuffGlows then mod.RefreshBuffGlows() end
                        end,
                    },
                    {
                        type = "slider",
                        label = "Speed",
                        min = 1,
                        max = 8,
                        step = 1,
                        get = function() return 9 - (BarList().buffGlowSpeed or 4) end,
                        set = function(value)
                            BarList().buffGlowSpeed = 9 - value
                            mod.BuildAllCDMBars()
                            if mod.RefreshBuffGlows then mod.RefreshBuffGlows() end
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Background",
                        get = BDFieldIs("buffGlowBackground"),
                        set = function(value)
                            BarList().buffGlowBackground = value and true or nil
                            mod.BuildAllCDMBars()
                            if mod.RefreshBuffGlows then mod.RefreshBuffGlows() end
                        end,
                    },
                    {
                        type = "colorpicker",
                        label = "Background Color",
                        get = function()
                            return BarList().buffGlowBackgroundR or 0,
                                BarList().buffGlowBackgroundG or 0,
                                BarList().buffGlowBackgroundB or 0
                        end,
                        set = function(red, green, blue)
                            BarList().buffGlowBackgroundR = red
                            BarList().buffGlowBackgroundG = green
                            BarList().buffGlowBackgroundB = blue
                            mod.BuildAllCDMBars()
                            if mod.RefreshBuffGlows then mod.RefreshBuffGlows() end
                        end,
                        disabled = function() return BarList().buffGlowBackground ~= true end,
                        disabledTooltip = "Pixel Glow Background",
                    },
                },
            })
        end
    end

    -- Charges/Stacks Only (cd/utility bars) -- the counterpart to the buff
    -- bars' "Only Show Numbers" above. Strips the icon down to its charge /
    -- stack counter: art, swipe, recharge edge and cooldown text all go.
    if not buffGlowBar and (barInfo.barType == "cooldowns" or barInfo.barType == "utility") then
        _, height = W:DualRow(hostFrame, cursorY, {
            type = "toggle",
            text = "Charges/Stacks Only (No Icon)",
            tooltip = "Hide this bar's icon art, cooldown swipe, recharge edge and cooldown text, leaving only the charge or stack count.",
            getValue = BDFieldIs("chargesOnly"),
            setValue = function(value)
                BarList().chargesOnly = value and true or nil
                mod.BuildAllCDMBars()
                Refresh()
            end,
        }, {
            type = "toggle",
            text = "Hide Charge Count at 0",
            tooltip = "Hide the charge number while a spell has no charges left, instead of showing a 0. The number returns as soon as a charge comes back.",
            getValue = BDFieldIs("hideZeroChargeText"),
            setValue = function(value)
                BarList().hideZeroChargeText = value and true or nil
                mod.BuildAllCDMBars()
                Refresh()
            end,
        })
        cursorY = cursorY - height
    end

    _, height = W:Spacer(hostFrame, cursorY, 8)
    cursorY = cursorY - height

    -------------------------------------------------------------------
    --  EXTRAS (not shown for custom aura bars or FocusKick)
    -------------------------------------------------------------------
    local isCustomBuffBar = (barInfo.barType == "custom_buff")
    local isAnyBuffBar = buffGlowBar -- buffs or custom_buff
    if mod.CDM_BarHasExtras(barInfo) then
        _, height = W:SectionHeader(hostFrame, "EXTRAS", cursorY)
        cursorY = cursorY - height

        -- Hide Items if Missing: one config, hosted in a different row per bar
        -- family. Buff bars carry it in the tooltip row's right slot; CD and
        -- utility bars keep it beside Mirror Key Presses further down.
        local hideMissingCfg = {
            type = "toggle",
            text = "Hide Items if Missing",
            tooltip = "Hide consumable items (potions, healthstone) from the bar when you have none in your bags, instead of showing them dimmed. They reappear automatically once you have the item again.",
            getValue = BDFieldIs("hideItemsIfMissing"),
            setValue = function(value)
                BarList().hideItemsIfMissing = value
                if mod.FullCDMRebuild then mod.FullCDMRebuild("hide_missing_toggle") end
            end,
        }
        -- Buffs get "Show Tooltip on Hover" only (auras aren't cast -> no keybind);
        -- cooldown/utility icon bars get the Tooltip | Keybind pair below.
        if isAnyBuffBar then
            local _, tth = W:DualRow(hostFrame, cursorY, {
                type = "toggle",
                text = "Show Tooltip on Hover",
                getValue = BDFieldIs("showTooltip"),
                setValue = function(value)
                    BarList().showTooltip = value
                    mod.ApplyCDMTooltipState(BarList().key)
                    Refresh()
                end,
            }, hideMissingCfg)
            cursorY = cursorY - tth
        else
            local kbRow
            kbRow, height = W:DualRow(hostFrame, cursorY, {
                type = "toggle",
                text = "Show Tooltip on Hover",
                getValue = BDFieldIs("showTooltip"),
                setValue = function(value)
                    BarList().showTooltip = value
                    mod.ApplyCDMTooltipState(BarList().key)
                    Refresh()
                end,
            }, {
                type = "toggle",
                text = "Show Keybind",
                getValue = BDFieldIs("showKeybind"),
                setValue = function(value)
                    local barData = BarList()
                    barData.showKeybind = value
                    mod.RefreshCDMIconAppearance(barData.key)
                    mod.ApplyCachedKeybinds()
                    UpdateCDMPreview()
                    CludesUI:RefreshPage()
                end,
            })
            cursorY = cursorY - height

            BuildKeybindStyleControls(kbRow, BarList, function()
                mod.RefreshCDMIconAppearance(BarList().key)
                mod.ApplyCachedKeybinds()
                UpdateCDMPreview()
                CludesUI:RefreshPage()
            end)
        end -- if isAnyBuffBar (tooltip only) / else (tooltip + keybind)

        -- Pandemic Glow: the Glows page's descriptor over this bar, with the
        -- preview and the Pixel Glow cog inline and the swatches in the right half.
        -- WoW Forever: the same row is the Anti-Clip Glow (CUI_CDM_ForeverAntiClip.lua).
        do
            local GO = CludesUI.GlowOptions
            local antiClip = mod.CDM_ANTI_CLIP
            local panDesc = mod._CDM_PandemicGlowDesc(BarList, function()
                mod.BuildAllCDMBars()
                Refresh()
            end)
            local panGlowRow
            panGlowRow, height = W:DualRow(
                hostFrame,
                cursorY,
                GO.DropdownSpec(
                    panDesc,
                    antiClip and "Anti-Clip Glow" or "Pandemic Glow",
                    antiClip
                            and "Show a glow on icons when casting the spell next, after your current cast or global cooldown, won't clip it"
                        or "Show a glow on icons when the remaining duration is in the pandemic window (last 30%)"
                ),
                { type = "label", text = antiClip and "Anti-Clip Glow Color" or "Pandemic Glow Color" }
            )
            cursorY = cursorY - height

            if not CludesUI._prebuilding then
                local leftRegion = panGlowRow._leftRegion
                leftRegion._lastInline =
                    GO.BuildPreview(leftRegion, panDesc, { anchor = leftRegion._control, x = -8 })
                GO.AttachInline(leftRegion, panDesc, panGlowRow._rightRegion)

                if CludesUI.BuildSyncIcon and CludesUI.ApplyPandemicGlowToAll then
                    CludesUI.BuildSyncIcon({
                        region = panGlowRow._leftRegion,
                        tooltip = antiClip
                                and "Apply this glow's look to the Nameplates Pandemic Glow, all CDM bars, and tracking bars. A surface that can't show a style uses its closest match."
                            or "Apply this pandemic glow to Nameplates, all CDM bars, and tracking bars. A surface that can't show a style uses its closest match.",
                        isSynced = function()
                            return CludesUI.IsPandemicGlowSyncedToAll(
                                CludesUI.PandemicPayloadFromCdmBar(BarList()),
                                { skipCdmKey = barId }
                            )
                        end,
                        onClick = function()
                            CludesUI.ApplyPandemicGlowToAll(
                                CludesUI.PandemicPayloadFromCdmBar(BarList()),
                                { skipCdmKey = barId }
                            )
                            Refresh()
                        end,
                    })
                end
            end
        end

        -- Show Non-On Use Trinkets | Show Rotation Helper. Forever has no
        -- Assisted Highlight: there the trinket toggle closes the section
        -- instead (beside Show Glows Only in Combat, or as the odd last slot).
        local trinketCfg = {
            type = "toggle",
            text = "Show Non-On Use Trinkets",
            tooltip = "Show equipped trinkets even if they don't have an on-use effect.",
            getValue = BDFieldIs("showPassiveTrinkets"),
            setValue = function(value)
                BarList().showPassiveTrinkets = value
                if mod.FullCDMRebuild then mod.FullCDMRebuild("trinket_toggle") end
            end,
        }
        if not CludesUI.IS_FOREVER then
            _, height = W:DualRow(hostFrame, cursorY, trinketCfg, {
                type = "toggle",
                text = "Show Rotation Helper",
                tooltip = "Highlight Blizzard's next recommended ability on all CDM bars. Requires Assisted Highlight to be enabled in Blizzard's options. Disabling this hides only the CDM highlight.\n\nPress the normal ability's keybind yourself. This does not cast spells or use the Single-Button Assistant, so it does not add that assistant's global cooldown penalty. Only abilities present on your CDM bars can be highlighted.",
                disabled = function() return not mod.RotationAssistAvailable() end,
                disabledTooltip = "This option requires Blizzard's Assisted Highlight to be enabled",
                rawTooltip = true,
                getValue = function()
                    local profile = DB()
                    return profile
                        and profile.cdmBars
                        and not profile.cdmBars.hideRotationHelper
                        and mod.RotationAssistAvailable()
                end,
                setValue = function(value)
                    local profile = DB()
                    if profile and profile.cdmBars then
                        profile.cdmBars.hideRotationHelper = not value
                        if mod.UpdateRotationHighlights then mod.UpdateRotationHighlights() end
                        -- The Style and Thickness rows below exist only while this
                        -- is on (the Glows page rebuilds its listing on every return).
                        CludesUI:RefreshPage(true)
                    end
                end,
            })
            cursorY = cursorY - height
        end -- not IS_FOREVER

        -- Rotation Assist styling is profile-wide (not tied to the selected
        -- bar). Keeping it on this override-eligible page lets the existing
        -- spec/conditional override system capture every scalar below.
        -- Read and write the runtime addon's authoritative profile. The options
        -- DB reference can lag behind a profile/override proxy swap, which made
        -- the swatches display Class while the renderer still read Custom.
        local function RotationBars()
            local runtime = mod.ECME and mod.ECME.db and mod.ECME.db.profile
            local fallback = DB()
            return (runtime and runtime.cdmBars) or (fallback and fallback.cdmBars)
        end
        -- A rotation setting read with its default, and written (when the store
        -- exists) with the highlights redrawn either way.
        local function RotGet(barKey, default)
            local rotBars = RotationBars()
            return (rotBars and rotBars[barKey]) or default
        end
        local function RotRedraw()
            if mod.UpdateRotationHighlights then mod.UpdateRotationHighlights() end
        end
        local function RotSet(barKey, value)
            local rotBars = RotationBars()
            if rotBars then rotBars[barKey] = value end
            RotRedraw()
        end
        local function RotCustomRGB()
            return RotGet("rotationAssistColorR", 1),
                RotGet("rotationAssistColorG", 0),
                RotGet("rotationAssistColorB", 0)
        end
        local function RotSetCustomRGB(red, green, blue)
            local rotBars = RotationBars()
            if rotBars then
                rotBars.rotationAssistColorR = red
                rotBars.rotationAssistColorG = green
                rotBars.rotationAssistColorB = blue
            end
            RotRedraw()
        end
        -- Which of the Thickness / Outset rows the current style reads (the renderer
        -- uses thickness for Solid Border and Pixel Glow, outset for every style but
        -- Blizzard Default): 0 = neither, 1 = outset only, 3 = both. The rows below
        -- exist only for the styles that read them, so the Style dropdown forces a
        -- rebuild when this key flips.
        local function RotRowsKey()
            local rotBars = RotationBars()
            local s = (rotBars and rotBars.rotationAssistStyle) or "blizzard"
            local barKey = 0
            if s ~= "blizzard" then barKey = 1 end
            if s == "solid" or s == "pixel" then barKey = barKey + 2 end
            return barKey
        end

        -- Style | Color and Thickness | Outset: built only while the CDM highlight
        -- can show (Show Rotation Helper on, Blizzard's Assisted Highlight on).
        if not mod._CDM_RotationHelperOff() then
            local ROT_STYLE_ORDER =
                { "blizzard", "solid", "pixel", "shape", "button", "autocast", "gcd", "modern", "classic" }
            local ROT_STYLE_NAMES = {
                blizzard = "Blizzard Default",
                solid = "Solid Border",
                pixel = "Pixel Glow",
                shape = "Shape Glow",
                button = "Action Button Glow",
                autocast = "Auto-Cast Shine",
                gcd = "GCD",
                modern = "Modern WoW Glow",
                classic = "Classic WoW Glow",
            }
            local rotStyleRow
            rotStyleRow, height = W:DualRow(hostFrame, cursorY, {
                type = "dropdown",
                text = "Rotation Assist Style",
                values = ROT_STYLE_NAMES,
                order = ROT_STYLE_ORDER,
                tooltip = "Choose the profile-wide border or glow used for Blizzard's Assisted Combat suggestion.",
                getValue = function() return RotGet("rotationAssistStyle", "blizzard") end,
                setValue = function(value)
                    local rotBars = RotationBars()
                    if rotBars then
                        local before = RotRowsKey()
                        rotBars.rotationAssistStyle = value
                        RotRedraw()
                        -- Full rebuild only when the Thickness / Outset row set changes;
                        -- the in-place refresh otherwise.
                        CludesUI:RefreshPage(RotRowsKey() ~= before)
                    end
                end,
            }, { type = "label", text = "Rotation Assist Color" })
            cursorY = cursorY - height

            do
                local colorRgn = rotStyleRow._rightRegion
                if colorRgn and CludesUI.BuildTrioColorSwatch then
                    -- Same trio as the Pandemic Glow row above. The helper opens the
                    -- picker only while custom mode is already active, so a picker
                    -- cancel can never flip the mode. Dimmed while Blizzard Default
                    -- owns the highlight; clicks are ignored there.
                    local function rotColorOff()
                        local rotBars = RotationBars()
                        return not rotBars or rotBars.rotationAssistStyle == "blizzard"
                    end
                    local colorSwatch, defaultSwatch, classSwatch =
                        CludesUI.BuildTrioColorSwatch(colorRgn, rotStyleRow:GetFrameLevel() + 3, {
                            getMode = function() return RotGet("rotationAssistColorMode", "default") end,
                            setMode = function(mode)
                                local rotBars = RotationBars()
                                if not rotBars or rotBars.rotationAssistStyle == "blizzard" then return end
                                -- Spec Overrides: the slot this write belongs to, read
                                -- before the write (as the widget factory does).
                                local snap = CludesUI._SOAttribution(colorRgn)
                                rotBars.rotationAssistColorMode = mode
                                RotRedraw()
                                CludesUI._NotifySettingWrite(colorRgn, snap)
                            end,
                            getCustomRGB = RotCustomRGB,
                            setCustomRGB = RotSetCustomRGB,
                            hasClassColor = true,
                            onChange = function() CludesUI:RefreshPage() end,
                            disabled = rotColorOff,
                            disabledAlpha = 0.15,
                        })
                    Pix.Point(classSwatch, "RIGHT", colorRgn, "RIGHT", -20, 0)
                    Pix.Point(colorSwatch, "RIGHT", classSwatch, "LEFT", -8, 0)
                    Pix.Point(defaultSwatch, "RIGHT", colorSwatch, "LEFT", -8, 0)

                    local function UpdateRotSwatchMouse()
                        local off = rotColorOff()
                        colorSwatch:EnableMouse(not off)
                        defaultSwatch:EnableMouse(not off)
                        classSwatch:EnableMouse(not off)
                    end
                    CludesUI.RegisterWidgetRefresh(UpdateRotSwatchMouse)
                    UpdateRotSwatchMouse()
                    colorRgn._captureCfg = {
                        type = "multi",
                        text = "Rotation Assist Color",
                        accessors = {
                            {
                                type = "dropdown",
                                text = "Rotation Assist Color Mode",
                                values = { default = "Default", custom = "Custom", class = "Class Color" },
                                order = { "default", "custom", "class" },
                                getValue = function() return RotGet("rotationAssistColorMode", "default") end,
                                setValue = function(mode) RotSet("rotationAssistColorMode", mode) end,
                            },
                            {
                                type = "colorpicker",
                                text = "Rotation Assist Custom Color",
                                getValue = function()
                                    local red, green, b = RotCustomRGB()
                                    return red, green, b, 1
                                end,
                                setValue = RotSetCustomRGB,
                            },
                        },
                    }
                end
            end

            -- Thickness | Outset: built only for the styles that read them (see
            -- RotRowsKey). Outset alone takes the left slot with a blank right slot.
            local rotRows = RotRowsKey()
            if rotRows > 0 then
                local thicknessCfg = {
                    type = "slider",
                    text = "Rotation Assist Thickness",
                    min = 1,
                    max = 8,
                    step = 1,
                    trackWidth = 120,
                    tooltip = "Thickness in physical pixels for Solid Border and Pixel Glow.",
                    getValue = function() return RotGet("rotationAssistThickness", 3) end,
                    setValue = function(value) RotSet("rotationAssistThickness", value) end,
                }
                local outsetCfg = {
                    type = "slider",
                    text = "Rotation Assist Outset",
                    min = 0,
                    max = 12,
                    step = 1,
                    trackWidth = 120,
                    tooltip = "How many pixels the custom effect extends beyond the icon.",
                    getValue = function() return RotGet("rotationAssistOutset", 1) end,
                    setValue = function(value) RotSet("rotationAssistOutset", value) end,
                }
                if rotRows >= 2 then
                    local rotThRow
                    rotThRow, height = W:DualRow(hostFrame, cursorY, thicknessCfg, outsetCfg)
                    cursorY = cursorY - height
                    -- Pixel Glow's remaining parameters (Solid Border reads thickness only).
                    if not CludesUI._prebuilding then
                        local function notPixel()
                            local rotBars = RotationBars()
                            return not rotBars or rotBars.rotationAssistStyle ~= "pixel"
                        end
                        -- The shared Pixel Glow rows over the rotationAssist* keys, minus
                        -- Thickness (it sits on this row itself).
                        local rotCogRows = {}
                        for _, r in ipairs(CludesUI.GlowOptions.CogRows(mod._CDM_RotationGlowDesc())) do
                            if r.label ~= "Thickness" then rotCogRows[#rotCogRows + 1] = r end
                        end
                        CludesUI.BuildInlineCog(rotThRow._leftRegion, {
                            title = "Pixel Glow Settings",
                            captureRegion = rotThRow._leftRegion,
                            disabled = notPixel,
                            disabledTooltip = "This option requires Pixel Glow to be the selected glow type",
                            rows = rotCogRows,
                        })
                    end
                else
                    _, height = W:DualRow(hostFrame, cursorY, outsetCfg, CludesUI.BlankRowCfg())
                    cursorY = cursorY - height
                end
            end
        end -- not RotationHelperOff

        -- Hide Items if Missing | Mirror Key Presses -- CD/utility bars only.
        -- Buff bars host Hide Items if Missing in the tooltip row above (their
        -- copy of this row would be empty), and Mirror Key Presses is not for
        -- buff-family bars (buffs are auto-tracked auras, not keybind-pressed
        -- abilities, so a "pressed" look has no meaning). (Per-spell threshold
        -- decimals/color moved to the per-icon dropdown: Threshold Text.)
        if not isAnyBuffBar then
            _, height = W:DualRow(hostFrame, cursorY, hideMissingCfg, {
                type = "toggle",
                text = "Mirror Key Presses",
                tooltip = "When you press an ability's keybind, show the action button's \"pushed down\" look on its icon on this bar -- even while the ability is on cooldown.",
                getValue = BDFieldIs("pressMirror"),
                setValue = function(value)
                    BarList().pressMirror = value
                    if mod.ClearCdmPressPush then mod.ClearCdmPressPush() end
                end,
            })
            cursorY = cursorY - height
        end

        -- Bar Strata: per-bar screen render layer for the bar container and its
        -- icons (MEDIUM default = the engine's baseline, so unset bars are
        -- unchanged). Cursor-anchored bars keep their deliberate TOOLTIP raise
        -- while riding the cursor; this applies only when not cursor-anchored.
        -- Same values/labels as the Tracking Bars "Bar Strata" dropdown.
        local strataCfg = {
            type = "dropdown",
            text = "Bar Strata",
            tooltip = "Screen layer this bar and its icons render on.",
            values = CludesUI.FRAME_STRATA_LABELS,
            order = CludesUI.FRAME_STRATA_ORDER_FULL,
            getValue = BDFieldOr("barStrata", "MEDIUM"),
            setValue = function(value)
                BarList().barStrata = value
                mod.BuildAllCDMBars()
                Refresh()
            end,
        }
        -- Bar Strata opens the rows below. (Swap Combat Potions When Missing, once
        -- beside it, is a per-icon setting now: each Combat Potion icon's menu,
        -- Combat Potion Icon; an icon that never set its own still reads the old
        -- profile-wide switch.)

        -- Global, not per-bar: one gate for every glow the Cooldown Manager
        -- draws, hence the label. Beside Bar Strata on buff-family bars; on
        -- cooldown/utility bars it leads the row under the cooldown edge row.
        local glowCombatCfg = {
            type = "toggle",
            text = "Show Glows Only in Combat (global)",
            tooltip = "Hide every Cooldown Manager glow out of combat and bring them all back the moment you enter combat.",
            getValue = function()
                local profile = DB()
                return (profile and profile.cdmBars and profile.cdmBars.glowsOnlyInCombat) == true
            end,
            setValue = function(value)
                local profile = DB()
                if not profile or not profile.cdmBars then return end
                profile.cdmBars.glowsOnlyInCombat = value and true or false
                -- Re-read the cached gate, then let the sweep take the running
                -- glows down (or bring the suppressed ones back) right away
                -- instead of waiting for the next combat edge.
                local first = value and mod._cdmGlowGateEverOn ~= true
                if mod.RefreshGlowCombatGate then mod.RefreshGlowCombatGate() end
                if mod.CDMGlowCombatSync then mod.CDMGlowCombatSync() end
                -- First enable of the session: glows lit before this point carry
                -- no record (StartNativeGlow records only once the gate has been
                -- on), so re-issue the bar and buff glows now -- they restart
                -- suppressed. Proc, CD-ready and preset glows already lit follow
                -- on their own next edge; every later login is exact from the start.
                if first then
                    if mod.RequestBarGlowUpdate then mod.RequestBarGlowUpdate() end
                    if mod.RefreshBuffGlows then mod.RefreshBuffGlows() end
                end
                CludesUI:RefreshPage()
            end,
        }

        -- Cooldown/utility bars only: buff bars have no cooldown edge. Bar Strata
        -- takes the first slot here and every later toggle moves up one; WoW
        -- Forever closes with Show Non-On Use Trinkets (retail places it beside
        -- Show Rotation Helper above).
        if barInfo.barType == "cooldowns" or barInfo.barType == "utility" then
            local edgeCfg = {
                type = "toggle",
                text = "Always Show Cooldown Edge",
                tooltip = "Show the rotating cooldown edge on every cooldown in this bar, not just while a charge is recharging. Hide Recharge Edge still overrides this for individual charge spells.",
                getValue = BDFieldIs("showCooldownEdge"),
                setValue = function(value)
                    BarList().showCooldownEdge = value and true or nil
                    mod.BuildAllCDMBars()
                    Refresh()
                end,
            }
            _, height = W:DualRow(hostFrame, cursorY, strataCfg, edgeCfg)
            cursorY = cursorY - height
            if CludesUI.IS_FOREVER then
                _, height = W:DualRow(hostFrame, cursorY, glowCombatCfg, trinketCfg)
                cursorY = cursorY - height
            else
                _, height = W:DualRow(hostFrame, cursorY, glowCombatCfg, CludesUI.BlankRowCfg())
                cursorY = cursorY - height
            end
        else
            _, height = W:DualRow(hostFrame, cursorY, strataCfg, glowCombatCfg)
            cursorY = cursorY - height
            if CludesUI.IS_FOREVER then
                _, height = W:DualRow(hostFrame, cursorY, trinketCfg, CludesUI.BlankRowCfg())
                cursorY = cursorY - height
            end
        end
    end -- custom_buff extras guard

    -----------------------------------------------------------------
    --  ADDITIONAL BAR OFFSET -- render-only X/Y displacement stacked on
    --  top of the bar's normal position (saved, module-anchored, or
    --  unlock-anchored). Unlock mode always shows the BASE position (the
    --  bar's mover gets a distinct tint + tooltip while an offset is set);
    --  the offset re-applies on exit. 0/0 = the feature is fully inert.
    --  FocusKick is nameplate-pinned (no free position, no mover): dead controls there.
    -----------------------------------------------------------------
    if not focusKickBar then
        _, height = W:SectionHeader(hostFrame, "ADDITIONAL BAR OFFSET", cursorY)
        cursorY = cursorY - height
        do
            local function SetAddOffset(axisKey, value)
                local barData = BarList()
                if not barData then return end
                barData[axisKey] = (value ~= 0) and value or nil
                -- The anchor extra-offset registry getter (registered for every eligible bar
                -- by the unlock registration pass below) reads the live value, so no per-edit
                -- set/clear is needed. Re-register unlock elements so the mover's offset
                -- marker (tint + tooltip) reflects the new state at the next unlock entry,
                -- then re-apply positions: the build covers saved and module-anchored
                -- placement, the cascade covers an unlock-anchored bar (the build leaves
                -- those positions to the anchor system).
                if mod.RegisterCDMUnlockElements then mod.RegisterCDMUnlockElements() end
                mod.BuildAllCDMBars()
                if
                    CludesUI.IsUnlockAnchored
                    and CludesUI.IsUnlockAnchored("CDM_" .. barData.key)
                    and CludesUI.PropagateAnchorChain
                then
                    CludesUI.PropagateAnchorChain("CDM_" .. barData.key)
                end
                Refresh()
            end
            _, height = W:DualRow(hostFrame, cursorY, {
                type = "slider",
                pixel = true,
                text = "Offset X",
                min = -500,
                max = 500,
                step = 1,
                trackWidth = 120,
                tooltip = "Extra horizontal shift stacked on top of this bar's normal position. Layout mode shows the base position; the offset re-applies when you exit.",
                getValue = function()
                    local barData = BarList()
                    return (barData and barData.addOffsetX) or 0
                end,
                setValue = function(value) SetAddOffset("addOffsetX", value) end,
            }, {
                type = "slider",
                pixel = true,
                text = "Offset Y",
                min = -500,
                max = 500,
                step = 1,
                trackWidth = 120,
                tooltip = "Extra vertical shift stacked on top of this bar's normal position. Layout mode shows the base position; the offset re-applies when you exit.",
                getValue = function()
                    local barData = BarList()
                    return (barData and barData.addOffsetY) or 0
                end,
                setValue = function(value) SetAddOffset("addOffsetY", value) end,
            })
            cursorY = cursorY - height
        end
    end -- not isFocusKick

    return math.abs(cursorY)
end

-- Used by CUI_CooldownManager_Options.lua
mod.CDMO_BuildCDMBarsPage = BuildCDMBarsPage
