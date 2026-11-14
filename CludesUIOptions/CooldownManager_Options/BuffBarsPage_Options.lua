if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CooldownManager_Options\BuffBarsPage_Options.lua
--  Cooldown Manager options: the Tracking Bars page with its state, preview
--  popout, placeholders, pickers and stack threshold editor. One init
--  function, called by CUI_CooldownManager_Options.lua where this code used to
--  run, so its hooks and frames are created at the same point and in the same
--  order as before.
-------------------------------------------------------------------------------
local mod = CludesUI._ModuleNS["CludesUICooldownManager"]
if not mod then
    return
end -- module disabled: no options page

-- The options page pool (CludesUI_FramePool.lua): a frame made under a pool
-- host (a reused page, a kept menu) is handed out again reset to fresh;
-- anywhere else this is the plain CreateFrame. A menu made per open (or per
-- page build) is one kept frame for the session (PoolKept), dressed again.
local CreateFrame = CludesUI._Pool.CreateFrame
local PoolKept, PoolGen = CludesUI._Pool.Kept, CludesUI._Pool.Gen

local function InitBuffBarsPage(
    Pix,
    DB,
    Refresh,
    FONT_PATH,
    GetCDMOptOutline,
    GateBlizzardOnly,
    PAGE_BUFF_BARS
)
    ---------------------------------------------------------------------------
    --  Buff Bars page: per-bar tracked buff bars with individual settings
    ---------------------------------------------------------------------------
    local _tbbSelectedBar = 1
    local _tbbSelectedGroup -- nil = editing a bar; gid = editing that group
    -- Deep-link helper (Global Settings > Glows): select a tracking bar by index.
    function mod._TBBSelectBar(idx)
        _tbbSelectedBar = idx
        _tbbSelectedGroup = nil
    end
    local _tbbDDBtn -- live management-dropdown button (picker anchor)
    local _tbbNavigateFn -- set per page build: click-to-scroll handler

    ---------------------------------------------------------------------------
    --  Popout preview docked to the options panel's left edge (raid-frame overlay
    --  preview pattern). Bars are built/skinned by the SAME runtime functions as live
    --  bars (CreateTBBBarFrame/ApplyTBBBarSettings), then dressed with sample fill/timer/
    --  stacks. Bar mode: selected bar with click-to-scroll overlays. Group mode: every
    --  bar of the group chained with its grow/spacing, each clickable to edit.
    ---------------------------------------------------------------------------
    local _tbbPopout
    local _tbbPopoutBars = {} -- pooled preview wraps (runtime-built)

    local function GetTBBPopout()
        if _tbbPopout then
            return _tbbPopout
        end
        local oc = CreateFrame("Frame", nil, UIParent)
        oc:SetFrameStrata("FULLSCREEN_DIALOG")
        oc:SetFrameLevel(10)
        oc:SetClampedToScreen(true)
        oc:Hide()
        local backdrop = oc:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(0, 0, 0, 0.9)
        local title = oc:CreateFontString(nil, "OVERLAY")
        title:SetFont(FONT_PATH, 13, GetCDMOptOutline())
        title:SetPoint("TOP", oc, "TOP", 0, -7)
        title:SetTextColor(1, 1, 1, 0.9)
        oc._title = title
        local hint = oc:CreateFontString(nil, "OVERLAY")
        hint:SetFont(FONT_PATH, 10, GetCDMOptOutline())
        hint:SetPoint("BOTTOM", oc, "BOTTOM", 0, 7)
        hint:SetTextColor(1, 1, 1, 0.4)
        oc._hint = hint
        _tbbPopout = oc
        return oc
    end

    local function HideTBBPopout()
        if _tbbPopout then
            _tbbPopout:Hide()
        end
    end

    -- Pooled hover/click overlay on a preview element (green border, like unit frame
    -- preview overlays); retargeted every refresh.
    local function TBBPvNavButton(wrap, key)
        wrap._pvNav = wrap._pvNav or {}
        local button = wrap._pvNav[key]
        if not button then
            button = CreateFrame("Button", nil, wrap)
            local c = CludesUI.CLUDES_GREEN
            button._brd = Pix.CreateBorder(button, c.r, c.g, c.b, 1, 2, "OVERLAY", 7)
            button._brd:Hide()
            button:SetScript("OnEnter", function(self)
                self._brd:Show()
                if self._tip then
                    CludesUI.ShowWidgetTooltip(self, self._tip)
                end
            end)
            button:SetScript("OnLeave", function(self)
                self._brd:Hide()
                CludesUI.HideWidgetTooltip()
            end)
            button:SetScript("OnMouseDown", function(self)
                if self._onNav then
                    self._onNav()
                end
            end)
            wrap._pvNav[key] = button
        end
        return button
    end

    local function HideTBBPvNav(wrap)
        if not wrap._pvNav then
            return
        end
        for _, b in pairs(wrap._pvNav) do
            b:Hide()
        end
    end

    -- Attach nav overlays for one preview bar. Bar mode: element overlays scroll to and
    -- flash their option rows; group mode: one whole-bar overlay selects the bar for editing.
    local function UpdateTBBPvNav(wrap, mode, barIdx)
        HideTBBPvNav(wrap)
        if mode == "group" then
            local button = TBBPvNavButton(wrap, "select")
            button:ClearAllPoints()
            button:SetAllPoints(wrap)
            button:SetFrameLevel(wrap:GetFrameLevel() + 30)
            button._tip = CludesUI.L("Click to edit this bar")
            button._onNav = function()
                _tbbSelectedBar = barIdx
                _tbbSelectedGroup = nil
                CludesUI:RefreshPage(true)
            end
            button:Show()
            return
        end
        local scrollBar = wrap._bar
        local function ElemBtn(key, elem, isText)
            if not elem or not elem.IsShown or not elem:IsShown() then
                return
            end
            if isText and (elem:GetText() or "") == "" then
                return
            end
            local button = TBBPvNavButton(wrap, key)
            button:ClearAllPoints()
            if isText then
                local tw = (elem:GetStringWidth() or 0) + 6
                local th = (elem:GetStringHeight() or 0) + 6
                if tw < 14 then
                    tw = 14
                end
                if th < 14 then
                    th = 14
                end
                button:SetSize(tw, th)
                -- Anchor by justification: FontString width > string width, so CENTER isn't where glyphs render.
                local justify = elem.GetJustifyH and elem:GetJustifyH() or "LEFT"
                if justify == "RIGHT" then
                    button:SetPoint("RIGHT", elem, "RIGHT", 2, 0)
                elseif justify == "CENTER" then
                    button:SetPoint("CENTER", elem, "CENTER", 0, 0)
                else
                    button:SetPoint("LEFT", elem, "LEFT", -2, 0)
                end
            else
                button:SetAllPoints(elem)
            end
            button:SetFrameLevel(wrap:GetFrameLevel() + (isText and 32 or 30))
            button._tip = nil
            button._onNav = function()
                if _tbbNavigateFn then
                    _tbbNavigateFn(key)
                end
            end
            button:Show()
        end
        ElemBtn("barFill", scrollBar, false)
        ElemBtn("icon", wrap._icon, false)
        ElemBtn("nameText", wrap._nameText, true)
        ElemBtn("timerText", wrap._timerText, true)
        ElemBtn("stacksText", wrap._stacksText, true)
    end

    -- Preview-only dressing over live skinning: sample fill, sample timer/stacks text,
    -- resolved name/icon, and the unassigned overlay.
    local function DressTBBPopoutBar(wrap, conf)
        local scrollBar = wrap._bar
        scrollBar:SetMinMaxValues(0, 1)
        scrollBar:SetValue(0.65)
        if wrap._timerText and wrap._timerText:IsShown() then
            wrap._timerText:SetText("3.2")
        end
        -- Stacks visibility is tick-driven on live bars; drive it from cfg here
        if wrap._stacksText then
            if (conf.stacksPosition or "center") ~= "none" then
                wrap._stacksText:SetText("3")
                wrap._stacksText:Show()
            else
                wrap._stacksText:Hide()
            end
        end
        local unassigned = (not conf.spellID or conf.spellID == 0) and not conf.glowBased
        -- Name (same resolution as the live build)
        if wrap._nameText and wrap._nameText:IsShown() then
            local displayName = conf.name
            if
                (not displayName or displayName == "" or displayName == "New Bar")
                and conf.spellID
                and conf.spellID > 0
            then
                local details = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(conf.spellID)
                displayName = (details and details.name) or displayName
            end
            if unassigned then
                displayName = ""
            end
            -- A custom name is the player's own text: shown as typed, never translated.
            wrap._nameText:SetText(mod.TBBCustomName(conf) or CludesUI.L(displayName or ""))
        end
        -- Icon texture (same resolution as the live build; question mark when no buff assigned yet)
        if wrap._icon and wrap._icon:IsShown() and wrap._icon._tex then
            local iconID
            if conf.popularKey and mod.TBB_POPULAR_BUFFS then
                for _, pe in ipairs(mod.TBB_POPULAR_BUFFS) do
                    if pe.key == conf.popularKey then
                        iconID = pe.icon
                        break
                    end
                end
            end
            if not iconID and conf.spellID and conf.spellID > 0 then
                local spInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(conf.spellID)
                iconID = spInfo and spInfo.iconID
            end
            wrap._icon._tex:SetTexture(iconID or 134400)
        end
        -- Unassigned: dim ALL bar content (fill/texts/icon/border) under a black overlay
        -- frame with a centered hint, above the bar's own layers so it draws over the fill/gradient stack.
        if not wrap._pvDarkFrame then
            local df = CreateFrame("Frame", nil, wrap)
            df:SetAllPoints(wrap)
            local tex = df:CreateTexture(nil, "ARTWORK")
            tex:SetAllPoints()
            tex:SetColorTexture(0, 0, 0, 0.6)
            local hintFS = df:CreateFontString(nil, "OVERLAY")
            hintFS:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            hintFS:SetTextColor(1, 1, 1, 1)
            hintFS:SetJustifyH("CENTER")
            hintFS:SetText(CludesUI.L("Choose a buff from the bar menu"))
            wrap._pvDarkFrame = df
            wrap._pvHint = hintFS
        end
        -- Frame level: above text overlay (+6) and border (+5), below click overlays (+30).
        wrap._pvDarkFrame:SetFrameLevel(wrap:GetFrameLevel() + 20)
        wrap._pvHint:ClearAllPoints()
        wrap._pvHint:SetPoint("CENTER", scrollBar, "CENTER", 0, 0)
        wrap._pvDarkFrame:SetShown(unassigned)
    end

    -- Vertical headroom for texts anchored above/below the bar (outside its bounds).
    local function TBBPvTextPad(conf, side)
        local tp = conf.timerPosition or (conf.showTimer and "right" or "none")
        local sp = conf.stacksPosition or "center"
        local np = conf.verticalOrientation and "none"
            or (conf.namePosition or ((conf.showName ~= false) and "left" or "none"))
        local p = 0
        if tp == side then
            p = math.max(p, conf.timerSize or 11)
        end
        if sp == side then
            p = math.max(p, conf.stacksSize or 11)
        end
        if np == side then
            p = math.max(p, conf.nameSize or 11)
        end
        return p > 0 and (p + 8) or 0
    end

    -- HARD gate for BOTH Tracking Bars preview systems (popout + unlock-style
    -- placeholders): never visible unless the panel is actually OPEN on the Tracking
    -- Bars page. activeModule/activePage alone is NOT enough -- both persist after close,
    -- and event-driven refreshes (saved positions, spec/instance events) rebuild this page with the panel hidden. Every show path funnels through this check.
    local function TBBPreviewAllowed()
        -- Folded to the mini window counts as closed (the page is off screen).
        if not (CludesUI:IsShown()) or CludesUI._panelCollapsed then
            return false
        end
        -- nil = mid-build (page state not stamped); builders only run for the page shown, so only a definite mismatch blocks.
        local am = CludesUI:GetActiveModule()
        local ap = CludesUI:GetActivePage()
        if am and ap and (am ~= "CludesUICooldownManager" or ap ~= PAGE_BUFF_BARS) then
            return false
        end
        return true
    end

    local function RefreshTBBPopout()
        if not TBBPreviewAllowed() then
            HideTBBPopout()
            return
        end
        local t = mod.GetTrackedBuffBars()
        local barList = t and t.bars or {}

        -- Configs to render: the selected group's members, or the selected bar
        local entries = {}
        local mode = "bar"
        if _tbbSelectedGroup then
            mode = "group"
            for i, c in ipairs(barList) do
                if mod.TBBBarGroupID(c) == _tbbSelectedGroup then
                    entries[#entries + 1] = { idx = i, cfg = c }
                end
            end
        else
            local c = barList[_tbbSelectedBar]
            if c then
                entries[1] = { idx = _tbbSelectedBar, cfg = c }
            end
        end
        if #entries == 0 then
            HideTBBPopout()
            return
        end

        local oc = GetTBBPopout()

        -- Build/refresh each preview bar with the LIVE bar code
        for num, e in ipairs(entries) do
            local wrap = _tbbPopoutBars[num]
            if not wrap then
                wrap = mod.CreateTBBBarFrame(oc, "Pv" .. num)
                _tbbPopoutBars[num] = wrap
                -- Width-gated geometry (charge hash lines, threshold ticks) silently skips
                -- while a fresh pool bar's fill size is 0; live bars re-drive from the timer
                -- tick, previews have none, so re-drive when size resolves.
                if wrap._bar then
                    wrap._bar:SetScript("OnSizeChanged", function(sbSelf)
                        local conf = wrap._pvCfg
                        if not conf then
                            return
                        end
                        if mod.ApplyTBBChargeHashLines then
                            local mc = mod.GetTBBMaxCharges and mod.GetTBBMaxCharges(conf)
                            mod.ApplyTBBChargeHashLines(wrap, conf, mc)
                        end
                        if mod.ApplyTBBTickMarks then
                            mod.ApplyTBBTickMarks(
                                sbSelf,
                                conf,
                                wrap._threshTicks,
                                conf.verticalOrientation,
                                wrap._tickOverlay
                            )
                            wrap._ticksDirty = nil
                        end
                    end)
                end
            end
            wrap._pvCfg = e.cfg
            mod.ApplyTBBBarSettings(wrap, e.cfg)
            -- The apply path pins the wrap to the bar's own strata (cfg.strata,
            -- MEDIUM default); lift into the popout's strata AFTER each apply
            -- and re-assert the constructor's child levels (a parent strata
            -- change resets child frame levels). Guarded so refreshes that
            -- didn't touch strata skip the re-stack; level checked too, else a
            -- bar whose OWN strata is the popout's would dodge the lift.
            local base = oc:GetFrameLevel() + 20
            if wrap:GetFrameStrata() ~= "FULLSCREEN_DIALOG" or wrap:GetFrameLevel() ~= base then
                wrap:SetFrameStrata("FULLSCREEN_DIALOG")
                wrap:SetFrameLevel(base)
                local scrollBar = wrap._bar
                if scrollBar then
                    scrollBar:SetFrameLevel(base + 1)
                end
                if wrap._gradClip and scrollBar then
                    wrap._gradClip:SetFrameLevel(scrollBar:GetFrameLevel() + 1)
                end
                if wrap._chargeHashFillClip and scrollBar then
                    wrap._chargeHashFillClip:SetFrameLevel(scrollBar:GetFrameLevel() + 1)
                end
                if wrap._threshOverlays and scrollBar then
                    for i = 1, #wrap._threshOverlays do
                        local shade = wrap._threshOverlays[i]
                        if shade then
                            shade:SetFrameLevel(scrollBar:GetFrameLevel() + 2)
                        end
                    end
                end
                if wrap._sparkOverlay and scrollBar then
                    wrap._sparkOverlay:SetFrameLevel(scrollBar:GetFrameLevel() + 3)
                end
                -- Tick overlay reassert; matches the live-bar block.
                if wrap._tickOverlay and scrollBar then
                    wrap._tickOverlay:SetFrameLevel(scrollBar:GetFrameLevel() + 4)
                end
                if wrap._chargeHashOverlay and scrollBar then
                    wrap._chargeHashOverlay:SetFrameLevel(scrollBar:GetFrameLevel() + 5)
                end
                -- base+6 matches the live-bar reassert: keeps the border above
                -- the tick overlay (sb+4 = base+5), which wins ties via lazy
                -- creation.
                if wrap._barBorder then
                    wrap._barBorder:SetFrameLevel(base + 6)
                end
                if wrap._pandemicGlowOverlay then
                    wrap._pandemicGlowOverlay:SetFrameLevel(base + 7)
                end
                if wrap._textOverlay and scrollBar then
                    wrap._textOverlay:SetFrameLevel(scrollBar:GetFrameLevel() + 7)
                end
            end
            DressTBBPopoutBar(wrap, e.cfg)
            -- Reused pool bars already have a resolved size, so OnSizeChanged may never
            -- fire here: consume the deferred tick-mark pass (apply path drew hash lines itself when sized).
            local psb = wrap._bar
            if wrap._ticksDirty and psb and psb:GetWidth() > 0 and mod.ApplyTBBTickMarks then
                mod.ApplyTBBTickMarks(
                    psb,
                    e.cfg,
                    wrap._threshTicks,
                    e.cfg.verticalOrientation,
                    wrap._tickOverlay
                )
                wrap._ticksDirty = nil
            end
            wrap:Show()
        end
        for num = #entries + 1, #_tbbPopoutBars do
            if _tbbPopoutBars[num] then
                HideTBBPvNav(_tbbPopoutBars[num])
                _tbbPopoutBars[num]:Hide()
            end
        end

        -- Chain layout: single bar centered; group members chained with the
        -- group's grow/spacing, exactly like the live BuildTrackedBuffBars
        local PAD_IN, TITLE_H = 20, 25
        local growDir, spacing = "DOWN", 2
        if mode == "group" then
            growDir = (mod.TBBGroupGrow(_tbbSelectedGroup) or "DOWN"):upper()
            spacing = mod.TBBGroupSpacing(_tbbSelectedGroup) or 2
        end
        local horizontalChain = mode == "group" and (growDir == "LEFT" or growDir == "RIGHT")

        local totalW, totalH = 0, 0
        for num = 1, #entries do
            local wrap = _tbbPopoutBars[num]
            local w2, h2 = wrap:GetWidth(), wrap:GetHeight()
            if mode ~= "group" then
                totalW, totalH = w2, h2
            elseif horizontalChain then
                totalW = totalW + w2 + (num > 1 and spacing or 0)
                if h2 > totalH then
                    totalH = h2
                end
            else
                totalH = totalH + h2 + (num > 1 and spacing or 0)
                if w2 > totalW then
                    totalW = w2
                end
            end
        end
        local topPad, botPad = 0, 0
        for _, e in ipairs(entries) do
            topPad = math.max(topPad, TBBPvTextPad(e.cfg, "top"))
            botPad = math.max(botPad, TBBPvTextPad(e.cfg, "bottom"))
        end

        -- Footer hint
        local hintH = 0
        if mode == "bar" then
            if not (CludesUIDB and CludesUIDB.previewHintDismissed) then
                oc._hint:SetText(CludesUI.L("Click elements to scroll to and highlight their options"))
                oc._hint:Show()
                hintH = 18
            else
                oc._hint:Hide()
            end
        else
            oc._hint:SetText(CludesUI.L("Click a bar to edit it"))
            oc._hint:Show()
            hintH = 18
        end

        -- Whole physical pixels throughout (the bars render at UIParent scale
        -- beside a panel of its own scale): a box or bar edge on a half pixel
        -- draws a doubled line along it.
        local es = oc:GetEffectiveScale()
        local function Px(v)
            return CludesUI.PP.SnapForES(v, es)
        end
        local ocW = Px(math.max(totalW + PAD_IN * 2, 240))
        oc:SetSize(ocW, Px(totalH + topPad + botPad + PAD_IN * 2 + TITLE_H + hintH))

        local firstY = -Px(PAD_IN + TITLE_H + topPad)
        local prev
        for num = 1, #entries do
            local wrap = _tbbPopoutBars[num]
            wrap:ClearAllPoints()
            if num == 1 then
                -- Centred bars sit on a whole-pixel left edge too.
                local cx = Px((ocW - wrap:GetWidth()) / 2)
                if mode == "group" and growDir == "UP" then
                    wrap:SetPoint("BOTTOMLEFT", oc, "BOTTOMLEFT", cx, Px(PAD_IN + botPad + hintH))
                elseif mode == "group" and growDir == "RIGHT" then
                    wrap:SetPoint("TOPLEFT", oc, "TOPLEFT", Px(PAD_IN), firstY)
                elseif mode == "group" and growDir == "LEFT" then
                    wrap:SetPoint("TOPRIGHT", oc, "TOPRIGHT", -Px(PAD_IN), firstY)
                else
                    wrap:SetPoint("TOPLEFT", oc, "TOPLEFT", cx, firstY)
                end
            else
                -- Same relative chain the live bars use
                if growDir == "UP" then
                    wrap:SetPoint("BOTTOM", prev, "TOP", 0, spacing)
                elseif growDir == "RIGHT" then
                    wrap:SetPoint("LEFT", prev, "RIGHT", spacing, 0)
                elseif growDir == "LEFT" then
                    wrap:SetPoint("RIGHT", prev, "LEFT", -spacing, 0)
                else
                    wrap:SetPoint("TOP", prev, "BOTTOM", 0, -spacing)
                end
            end
            prev = wrap
            UpdateTBBPvNav(wrap, mode, entries[num].idx)
        end

        if mode == "group" then
            local gname = (mod.TBBGroupName and mod.TBBGroupName(_tbbSelectedGroup))
                or (CludesUI.L("Group") .. " " .. _tbbSelectedGroup)
            oc._title:SetText(gname .. " " .. CludesUI.L("Preview"))
        else
            oc._title:SetText(CludesUI.L("Preview"))
        end

        -- Dock to the left edge of the options panel, vertically centered, its
        -- corner nudged onto a whole pixel (the panel may sit anywhere).
        oc:ClearAllPoints()
        oc:Show()
        local scrollFrame = CludesUI._scrollFrame
        if scrollFrame then
            local dy = oc:GetHeight() / 2
            oc:SetPoint("TOPRIGHT", scrollFrame, "LEFT", 0, dy)
            local right, topY = oc:GetRight(), oc:GetTop()
            if right and topY then
                oc:SetPoint("TOPRIGHT", scrollFrame, "LEFT", Px(right) - right, dy + Px(topY) - topY)
            end
        else
            oc:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
    end

    -- Pool of unlock placeholders, one per bar (module-scope for cross-page access)
    local _tbbPlaceholders = {}
    local function UpdateTBBPlaceholder()
        -- Same hard gate as the popout: never show (or set placeholder mode) with the
        -- panel closed or another page in front. HideTBBPlaceholder is declared below.
        if not TBBPreviewAllowed() then
            mod._tbbPlaceholderMode = false
            for _, ph in ipairs(_tbbPlaceholders) do
                if ph then
                    ph:Hide()
                end
            end
            HideTBBPopout()
            return
        end
        mod._tbbPlaceholderMode = true
        -- The TBB tick may be idle-asleep; placeholders render from the tick.
        if mod.WakeTBBTick then
            mod.WakeTBBTick()
        end
        local tbb = mod.GetTrackedBuffBars()
        local barList = tbb and tbb.bars
        if not barList then
            return
        end
        for i, _ in ipairs(barList) do
            local liveBar = mod.GetTBBFrame and mod.GetTBBFrame(i)
            if liveBar then
                if not _tbbPlaceholders[i] then
                    _tbbPlaceholders[i] = CludesUI.BuildUnlockPlaceholder({
                        parent = liveBar,
                        -- The bar's own mover (a grouped bar has none under
                        -- this key, so nothing is selected there).
                        onClick = function()
                            CludesUI.OpenUnlockModeAt(mod._tbbUKey[i])
                        end,
                    })
                else
                    local ph = _tbbPlaceholders[i]
                    ph:SetParent(liveBar)
                    ph:SetAllPoints(liveBar)
                    ph:SetFrameLevel(liveBar:GetFrameLevel() + 10)
                end
                _tbbPlaceholders[i]:Show()
                liveBar:Show()
            end
        end
        -- Hide any leftover placeholders from deleted bars
        for i = (#barList + 1), #_tbbPlaceholders do
            if _tbbPlaceholders[i] then
                _tbbPlaceholders[i]:Hide()
            end
        end
    end
    local function HideTBBPlaceholder()
        mod._tbbPlaceholderMode = false
        for _, ph in ipairs(_tbbPlaceholders) do
            if ph then
                ph:Hide()
            end
        end
        -- The popout preview lives and dies with the page, same as placeholders
        -- (runs on every page-leave/panel-close path).
        HideTBBPopout()
    end
    mod.HideTBBPlaceholders = HideTBBPlaceholder
    mod.ShowTBBPlaceholders = UpdateTBBPlaceholder
    CludesUI:RegisterOnHide(HideTBBPlaceholder)
    -- Re-show placeholders when the panel re-opens on Tracking Bars. Exiting unlock mode
    -- to the SAME page skips SelectPage (currentPage == restorePage), so the page-restore
    -- hook that calls ShowTBBPlaceholders never fires; this OnShow re-asserts them.
    local function ReassertTBBPreviews()
        local am = CludesUI:GetActiveModule()
        local ap = CludesUI:GetActivePage()
        if am == "CludesUICooldownManager" and ap == PAGE_BUFF_BARS then
            UpdateTBBPlaceholder()
            RefreshTBBPopout()
        end
    end
    CludesUI:RegisterOnShow(ReassertTBBPreviews)
    -- The popout sits on UIParent beside the panel: it folds away with the panel
    -- and comes back with it (the live-bar placeholders stay up as the preview).
    CludesUI:RegisterOnCollapse(function(on)
        if on then
            HideTBBPopout()
        else
            ReassertTBBPreviews()
        end
    end)

    -- Every CDM page + its selected-bar index are per-spec, but the options panel caches
    -- built pages, so after a swap the cache holds the PREVIOUS spec's wrappers. A shared-
    -- profile spec swap never runs RefreshAllAddons (the cache clear), so without explicit
    -- invalidation reopening serves stale content: drop the CDM page cache, RefreshPage in place if open.
    local _tbbRefreshFn
    local function HandleTBBSpecChange()
        _tbbSelectedBar = 1
        _tbbSelectedGroup = nil
        CludesUI:InvalidateModulePageCache("CludesUICooldownManager")
        if
            CludesUI:IsShown()
            and CludesUI:GetActiveModule() == "CludesUICooldownManager"
            and CludesUI.RefreshPage
        then
            -- Panel open on a CDM page: rebuild now (content-header dropdown + body).
            CludesUI:RefreshPage(true)
        else
            -- Panel closed (or another module): reopening takes the fast RefreshPage path
            -- (dropdown not rebuilt) and SelectPage early-returns on the same page, so the
            -- dropdown would keep the previous spec's bar. Flag a cold rebuild for next show.
            mod._cdmColdRebuildOnShow = true
        end
    end

    -- Authoritative trigger: CDM's ProcessSpecChange calls this AFTER swapping the
    -- spec-key cache (_cachedSpecKey), so the rebuild reads the NEW spec. The
    -- PLAYER_SPECIALIZATION_CHANGED watcher below is a backup (covers panel-closed cache
    -- drop too); it can fire early and read the old spec, but ProcessSpecChange corrects it after.
    mod.OnTBBSpecChanged = HandleTBBSpecChange

    local _tbbSpecWatcher = CreateFrame("Frame")
    _tbbSpecWatcher:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    _tbbSpecWatcher:SetScript("OnEvent", HandleTBBSpecChange)

    -- Bars auto-added while the panel sits on Tracking Bars (e.g. user drags a new spell
    -- into Blizzard's Tracked Bars and returns): rebuild the open page immediately.
    mod.OnTBBBarsAutoAdded = function()
        if
            CludesUI:IsShown()
            and CludesUI:GetActiveModule() == "CludesUICooldownManager"
            and CludesUI:GetActivePage() == PAGE_BUFF_BARS
            and CludesUI.RefreshPage
        then
            CludesUI:RefreshPage(true)
        end
    end

    -- A spec swap while the panel is CLOSED can't rebuild (nothing shown); honor the
    -- pending cold rebuild here so reopening directly onto a CDM page rebuilds fresh.
    CludesUI:RegisterOnShow(function()
        if not mod._cdmColdRebuildOnShow then
            return
        end
        if CludesUI:GetActiveModule() == "CludesUICooldownManager" and CludesUI.RefreshPage then
            mod._cdmColdRebuildOnShow = false
            CludesUI:RefreshPage(true)
        end
    end)

    -- Buff spell picker for tracked buff bars (reuses CDM buff spell list)
    local _tbbSpellPickerMenu

    CludesUI:RegisterOnHide(function()
        if _tbbSpellPickerMenu then
            _tbbSpellPickerMenu:Hide()
        end
    end)

    -- Show the "Custom Buff ID" popup with Spell ID + Duration fields
    local function ShowCustomBuffIDPopup(anchor, barCfg, onChanged)
        local popupName = "CUI_TBB_CustomBuffPopup"
        local dialog = _G[popupName]
        if not dialog then
            local POPUP_W, POPUP_H = 320, 210
            local dimmer = CreateFrame("Frame", popupName .. "Dimmer", UIParent)
            dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
            dimmer:SetAllPoints(UIParent)
            dimmer:EnableMouse(true)
            dimmer:Hide()
            local dimTex = dimmer:CreateTexture(nil, "BACKGROUND")
            dimTex:SetAllPoints()
            dimTex:SetColorTexture(0, 0, 0, 0.25)

            dialog = CreateFrame("Frame", popupName, dimmer)
            dialog:SetSize(POPUP_W, POPUP_H)
            dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
            dialog:SetFrameStrata("FULLSCREEN_DIALOG")
            dialog:SetFrameLevel(dimmer:GetFrameLevel() + 10)
            dialog:EnableMouse(true)
            local popBg = dialog:CreateTexture(nil, "BACKGROUND")
            popBg:SetAllPoints()
            popBg:SetColorTexture(0.062, 0.070, 0.082, 1)
            CludesUI.MakeRoundedBorder(dialog, 1, 1, 1, 0.15, popBg)

            local title = dialog:CreateFontString(nil, "OVERLAY")
            title:SetFont(FONT_PATH, 14, GetCDMOptOutline())
            title:SetPoint("TOP", dialog, "TOP", 0, -18)
            title:SetTextColor(1, 1, 1, 1)
            title:SetText(CludesUI.L("Custom Buff ID"))

            local sidLbl = dialog:CreateFontString(nil, "OVERLAY")
            sidLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            sidLbl:SetPoint("TOPLEFT", dialog, "TOPLEFT", 24, -52)
            sidLbl:SetTextColor(0.7, 0.7, 0.7, 1)
            sidLbl:SetText(CludesUI.L("Spell ID"))

            local sidBox = CreateFrame("EditBox", nil, dialog)
            sidBox:SetSize(180, 28)
            sidBox:SetPoint("TOPLEFT", sidLbl, "BOTTOMLEFT", 0, -4)
            sidBox:SetAutoFocus(false)
            sidBox:SetNumeric(true)
            sidBox:SetMaxLetters(7)
            sidBox:SetFont(FONT_PATH, 13, GetCDMOptOutline())
            sidBox:SetTextColor(1, 1, 1, 0.9)
            sidBox:SetJustifyH("LEFT")
            local sidBg = sidBox:CreateTexture(nil, "BACKGROUND")
            sidBg:SetAllPoints()
            sidBg:SetColorTexture(0.060, 0.049, 0.037, 1)
            CludesUI.MakeRoundedBorder(sidBox, 1, 1, 1, 0.12, sidBg)
            local sidPh = sidBox:CreateFontString(nil, "ARTWORK")
            sidPh:SetFont(FONT_PATH, 12, GetCDMOptOutline())
            sidPh:SetPoint("LEFT", sidBox, "LEFT", 4, 0)
            sidPh:SetTextColor(0.5, 0.5, 0.5, 0.5)
            sidPh:SetText(CludesUI.L("e.g. 12345"))
            sidBox:SetScript("OnTextChanged", function(self)
                if self:GetText() == "" then
                    sidPh:Show()
                else
                    sidPh:Hide()
                end
            end)
            dialog._sidBox = sidBox

            local durLbl = dialog:CreateFontString(nil, "OVERLAY")
            durLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            durLbl:SetPoint("TOPLEFT", sidBox, "BOTTOMLEFT", 0, -12)
            durLbl:SetTextColor(0.7, 0.7, 0.7, 1)
            durLbl:SetText(CludesUI.L("Duration (seconds)"))

            local durBox = CreateFrame("EditBox", nil, dialog)
            durBox:SetSize(180, 28)
            durBox:SetPoint("TOPLEFT", durLbl, "BOTTOMLEFT", 0, -4)
            durBox:SetAutoFocus(false)
            durBox:SetNumeric(true)
            durBox:SetMaxLetters(5)
            durBox:SetFont(FONT_PATH, 13, GetCDMOptOutline())
            durBox:SetTextColor(1, 1, 1, 0.9)
            durBox:SetJustifyH("LEFT")
            local durBg = durBox:CreateTexture(nil, "BACKGROUND")
            durBg:SetAllPoints()
            durBg:SetColorTexture(0.060, 0.049, 0.037, 1)
            CludesUI.MakeRoundedBorder(durBox, 1, 1, 1, 0.12, durBg)
            local durPh = durBox:CreateFontString(nil, "ARTWORK")
            durPh:SetFont(FONT_PATH, 12, GetCDMOptOutline())
            durPh:SetPoint("LEFT", durBox, "LEFT", 4, 0)
            durPh:SetTextColor(0.5, 0.5, 0.5, 0.5)
            durPh:SetText(CludesUI.L("e.g. 30"))
            durBox:SetScript("OnTextChanged", function(self)
                if self:GetText() == "" then
                    durPh:Show()
                else
                    durPh:Hide()
                end
            end)
            dialog._durBox = durBox

            local status = dialog:CreateFontString(nil, "OVERLAY")
            status:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            status:SetPoint("TOP", durBox, "BOTTOM", 0, -6)
            status:SetTextColor(1, 0.3, 0.3, 1)
            status:SetText("")
            dialog._status = status
            dialog._statusTimer = nil

            local ar, ag, ab = CludesUI.GetAccentColor()
            local addBtn = CreateFrame("Button", nil, dialog)
            addBtn:SetSize(80, 28)
            addBtn:SetPoint("BOTTOMRIGHT", dialog, "BOTTOM", -4, 16)
            local addBg = addBtn:CreateTexture(nil, "BACKGROUND")
            addBg:SetAllPoints()
            addBg:SetColorTexture(ar, ag, ab, 0.15)
            CludesUI.MakeRoundedBorder(addBtn, ar, ag, ab, 0.3, addBg)
            local addLbl = addBtn:CreateFontString(nil, "OVERLAY")
            addLbl:SetFont(FONT_PATH, 12, GetCDMOptOutline())
            addLbl:SetPoint("CENTER")
            addLbl:SetText(CludesUI.L("Add"))
            addLbl:SetTextColor(ar, ag, ab, 0.9)
            addBtn:SetScript("OnEnter", function()
                addLbl:SetTextColor(1, 1, 1, 1)
            end)
            addBtn:SetScript("OnLeave", function()
                addLbl:SetTextColor(ar, ag, ab, 0.9)
            end)
            dialog._addBtn = addBtn

            local cancelBtn = CreateFrame("Button", nil, dialog)
            cancelBtn:SetSize(80, 28)
            cancelBtn:SetPoint("BOTTOMLEFT", dialog, "BOTTOM", 4, 16)
            local cBg = cancelBtn:CreateTexture(nil, "BACKGROUND")
            cBg:SetAllPoints()
            cBg:SetColorTexture(0.12, 0.12, 0.12, 0.5)
            CludesUI.MakeRoundedBorder(cancelBtn, 1, 1, 1, 0.10, cBg)
            local cLbl = cancelBtn:CreateFontString(nil, "OVERLAY")
            cLbl:SetFont(FONT_PATH, 12, GetCDMOptOutline())
            cLbl:SetPoint("CENTER")
            cLbl:SetText(CludesUI.L("Cancel"))
            cLbl:SetTextColor(0.7, 0.7, 0.7, 0.8)
            cancelBtn:SetScript("OnEnter", function()
                cLbl:SetTextColor(1, 1, 1, 1)
            end)
            cancelBtn:SetScript("OnLeave", function()
                cLbl:SetTextColor(0.7, 0.7, 0.7, 0.8)
            end)
            cancelBtn:SetScript("OnClick", function()
                dimmer:Hide()
            end)
            dialog._cancelBtn = cancelBtn

            sidBox:SetScript("OnEscapePressed", function()
                dimmer:Hide()
            end)
            durBox:SetScript("OnEscapePressed", function()
                dimmer:Hide()
            end)

            dialog._dimmer = dimmer
            _G[popupName] = dialog
        end

        local curSID = (barCfg.spellID and barCfg.spellID > 0 and not barCfg.popularKey) and barCfg.spellID
            or nil
        local curDur = barCfg.customDuration or nil
        dialog._sidBox:SetText(curSID and tostring(curSID) or "")
        dialog._durBox:SetText(curDur and tostring(curDur) or "")
        dialog._status:SetText("")

        local function SetStatus(textValue, r, g, b)
            dialog._status:SetText(CludesUI.L(textValue))
            dialog._status:SetTextColor(r or 1, g or 0.3, b or 0.3, 1)
            if dialog._statusTimer then
                dialog._statusTimer:Cancel()
            end
            if textValue ~= "" then
                dialog._statusTimer = C_Timer.NewTimer(2.5, function()
                    dialog._status:SetText("")
                end)
            end
        end

        dialog._addBtn:SetScript("OnClick", function()
            local spellRef = tonumber(dialog._sidBox:GetText())
            local dur = tonumber(dialog._durBox:GetText())
            if not spellRef or spellRef <= 0 then
                SetStatus("Enter a valid spell ID")
                return
            end
            spellRef = math.floor(spellRef)
            if not C_Spell.GetSpellName(spellRef) then
                SetStatus("Unknown spell ID")
                return
            end
            if not dur or dur <= 0 then
                SetStatus("Enter a duration in seconds")
                return
            end
            dur = math.floor(dur)
            dialog._dimmer:Hide()
            barCfg.spellID = spellRef
            barCfg.spellIDs = nil
            barCfg.popularKey = nil
            barCfg.glowBased = nil
            barCfg.trackType = nil
            barCfg.customDuration = dur
            -- Manually-entered id has no live frame to read the base from: clear stale
            -- base; MatchFrameToConfig self-heals it once talented.
            barCfg.baseSpellID = nil
            barCfg.name = C_Spell.GetSpellName(spellRef)
            barCfg.customName = nil
            Refresh()
            mod.BuildTrackedBuffBars()
            if onChanged then
                onChanged()
            end
        end)

        mod.PadPopupOpen(dialog._dimmer, dialog, dialog._cancelBtn) -- controller cursor
        dialog._dimmer:Show()
        dialog._sidBox:SetFocus()
    end

    local function ShowTBBSpellPicker(anchor, barCfg, onChanged)
        if _tbbSpellPickerMenu then
            _tbbSpellPickerMenu:Hide()
        end

        local trackedBars = mod.GetTrackedBarSpells and mod.GetTrackedBarSpells(true) or {}
        local popular = mod.TBB_POPULAR_BUFFS or {}

        -- No early bail on empty trackedBars -- the picker still shows popular presets and the custom spell ID input.

        local mBgR = CludesUI.DD_BG_R or 0.075
        local mBgG = CludesUI.DD_BG_G or 0.113
        local mBgB = CludesUI.DD_BG_B or 0.141
        local mBgA = CludesUI.DD_BG_HA or 0.98
        local mBrdA = CludesUI.DD_BRD_A or 0.20
        local hlA = CludesUI.DD_ITEM_HL_A or 0.08
        local tDimR = CludesUI.TEXT_DIM_R or 0.7
        local tDimG = CludesUI.TEXT_DIM_G or 0.7
        local tDimB = CludesUI.TEXT_DIM_B or 0.7
        local tDimA = CludesUI.TEXT_DIM_A or 0.85
        local ACCENT = CludesUI.CLUDES_GREEN or { r = 0.30, g = 0.79, b = 0.94 }

        local menuW = 240
        local ITEM_H = 26
        local MAX_H = 340

        -- One picker frame for the session, dressed again on every open.
        local dropMenu = PoolKept(mod, "tbbSpellPicker", "Frame", UIParent)
        dropMenu:SetFrameStrata("FULLSCREEN_DIALOG")
        dropMenu:SetFrameLevel(300)
        dropMenu:SetClampedToScreen(true)
        dropMenu:SetSize(menuW, 10)

        local mbg = dropMenu:CreateTexture(nil, "BACKGROUND")
        mbg:SetAllPoints()
        mbg:SetColorTexture(mBgR, mBgG, mBgB, mBgA)
        CludesUI.MakeRoundedBorder(dropMenu, 1, 1, 1, mBrdA, mbg, nil, true)

        local inner = CreateFrame("Frame", nil, dropMenu)
        inner:SetWidth(menuW)
        inner:SetPoint("TOPLEFT")

        local mH = 4

        -- "Custom Buff ID" entry at the top
        local isCustomSelected = barCfg.spellID
            and barCfg.spellID > 0
            and not barCfg.popularKey
            and not barCfg.spellIDs
            and barCfg.trackType ~= "cooldown"
        local csItem = CreateFrame("Button", nil, inner)
        csItem:SetHeight(ITEM_H)
        csItem:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
        csItem:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
        csItem:SetFrameLevel(dropMenu:GetFrameLevel() + 2)
        local csHl = csItem:CreateTexture(nil, "ARTWORK", nil, -1)
        csHl:SetAllPoints()
        csHl:SetColorTexture(1, 1, 1, 0)
        local csLbl = csItem:CreateFontString(nil, "OVERLAY")
        csLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
        csLbl:SetPoint("LEFT", 10, 0)
        csLbl:SetJustifyH("LEFT")
        csLbl:SetText(CludesUI.L("Custom Buff ID"))
        csLbl:SetTextColor(
            isCustomSelected and 1 or tDimR,
            isCustomSelected and 1 or tDimG,
            isCustomSelected and 1 or tDimB,
            isCustomSelected and 1 or tDimA
        )
        csItem:SetScript("OnEnter", function()
            csLbl:SetTextColor(1, 1, 1, 1)
            csHl:SetColorTexture(1, 1, 1, hlA)
        end)
        csItem:SetScript("OnLeave", function()
            csLbl:SetTextColor(
                isCustomSelected and 1 or tDimR,
                isCustomSelected and 1 or tDimG,
                isCustomSelected and 1 or tDimB,
                isCustomSelected and 1 or tDimA
            )
            csHl:SetColorTexture(1, 1, 1, 0)
        end)
        csItem:SetScript("OnClick", function()
            dropMenu:Hide()
            ShowCustomBuffIDPopup(anchor, barCfg, onChanged)
        end)
        mH = mH + ITEM_H

        local div1 = inner:CreateTexture(nil, "ARTWORK")
        div1:SetHeight(1)
        div1:SetColorTexture(1, 1, 1, 0.10)
        div1:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH - 4)
        div1:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH - 4)
        mH = mH + 9

        -- Popular buff entries
        local function MakePopularItem(record)
            local isSelected = barCfg.popularKey == record.key
            local item = CreateFrame("Button", nil, inner)
            item:SetHeight(ITEM_H)
            item:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
            item:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
            item:SetFrameLevel(dropMenu:GetFrameLevel() + 2)

            local ico = item:CreateTexture(nil, "ARTWORK")
            local icoSz = ITEM_H - 4
            ico:SetSize(icoSz, icoSz)
            ico:SetPoint("RIGHT", item, "RIGHT", -6, 0)
            ico:SetTexture(record.icon)
            ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            local baseR = isSelected and 1 or tDimR
            local baseG = isSelected and 1 or tDimG
            local baseB = isSelected and 1 or tDimB
            local baseA = isSelected and 1 or tDimA

            local labelFS = item:CreateFontString(nil, "OVERLAY")
            labelFS:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            labelFS:SetPoint("LEFT", 8, 0)
            labelFS:SetPoint("RIGHT", ico, "LEFT", -4, 0)
            labelFS:SetJustifyH("LEFT")
            labelFS:SetWordWrap(false)
            labelFS:SetMaxLines(1)
            labelFS:SetText(CludesUI.L(record.name))
            labelFS:SetTextColor(baseR, baseG, baseB, baseA)

            local highlight = item:CreateTexture(nil, "ARTWORK", nil, -1)
            highlight:SetAllPoints()
            highlight:SetColorTexture(1, 1, 1, isSelected and 0.12 or 0)

            item:SetScript("OnEnter", function()
                labelFS:SetTextColor(1, 1, 1, 1)
                highlight:SetColorTexture(1, 1, 1, hlA)
            end)
            item:SetScript("OnLeave", function()
                labelFS:SetTextColor(baseR, baseG, baseB, baseA)
                highlight:SetColorTexture(1, 1, 1, isSelected and 0.12 or 0)
            end)
            item:SetScript("OnClick", function()
                dropMenu:Hide()
                barCfg.popularKey = record.key
                barCfg.spellIDs = record.spellIDs
                barCfg.glowBased = record.glowBased or nil
                barCfg.customDuration = record.customDuration
                barCfg.spellID = record.spellIDs and record.spellIDs[1] or 0
                barCfg.baseSpellID = nil
                barCfg.trackType = nil
                barCfg.name = record.name
                barCfg.customName = nil
                Refresh()
                mod.BuildTrackedBuffBars()
                if onChanged then
                    onChanged()
                end
            end)
            mH = mH + ITEM_H
        end

        local _, _tbbPClass = UnitClass("player")
        local nPopular = 0
        for _, record in ipairs(popular) do
            -- tbbOnly presets (e.g. debuff-driven Bloodlust) carry a sentinel class to hide
            -- from the cooldown/utility item picker; the TBB picker overrides that and always shows them.
            if record.tbbOnly or not record.class or record.class == _tbbPClass then
                MakePopularItem(record)
                nPopular = nPopular + 1
            end
        end

        -- "Buffs" section always renders (even with no tracked bars) so the Missing Spells prompt below stays visible.
        -- Its divider closes the preset rows, so it is skipped when none were built
        -- (WoW Forever has no presets): the one above already separates Custom Buff ID.
        do
            if nPopular > 0 then
                local div2 = inner:CreateTexture(nil, "ARTWORK")
                div2:SetHeight(1)
                div2:SetColorTexture(1, 1, 1, 0.10)
                div2:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH - 4)
                div2:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH - 4)
                mH = mH + 9
            end

            local buffHdr = inner:CreateFontString(nil, "OVERLAY")
            buffHdr:SetFont(FONT_PATH, 10, GetCDMOptOutline())
            buffHdr:SetTextColor(1, 1, 1, 0.5)
            buffHdr:SetPoint("TOPLEFT", inner, "TOPLEFT", 10, -mH - 5)
            buffHdr:SetText(CludesUI.L("Buffs"))
            mH = mH + 20
        end

        local function MakeSpellItem(sp)
            -- Every spell here came from BuffBarCooldownViewer enumeration, so it's by definition tracked -- no popup needed.
            local usedOnBar = mod.SpellUsedOnAnyOtherTBB and mod.SpellUsedOnAnyOtherTBB(sp.spellID, nil)
            -- A family bar (Roll the Bones) is selected by its base id OR any member,
            -- since the row resolves to the active outcome while one is up.
            local isSelected = not barCfg.popularKey
                and barCfg.trackType ~= "cooldown"
                and barCfg.spellID
                and barCfg.spellID > 0
                and barCfg.spellID == sp.spellID
            if
                not isSelected
                and barCfg.spellIDs
                and not barCfg.popularKey
                and barCfg.trackType ~= "cooldown"
            then
                for _, spellRef in ipairs(barCfg.spellIDs) do
                    if spellRef == sp.spellID then
                        isSelected = true
                        break
                    end
                end
            end
            local item = CreateFrame("Button", nil, inner)
            item:SetHeight(ITEM_H)
            item:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
            item:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
            item:SetFrameLevel(dropMenu:GetFrameLevel() + 2)

            local ico = item:CreateTexture(nil, "ARTWORK")
            local icoSz = ITEM_H - 4
            ico:SetSize(icoSz, icoSz)
            ico:SetPoint("RIGHT", item, "RIGHT", -6, 0)
            if sp.icon then
                ico:SetTexture(sp.icon)
            end
            ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            local baseR = isSelected and 1 or tDimR
            local baseG = isSelected and 1 or tDimG
            local baseB = isSelected and 1 or tDimB
            local baseA = isSelected and 1 or tDimA

            local labelFS = item:CreateFontString(nil, "OVERLAY")
            labelFS:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            labelFS:SetPoint("LEFT", 8, 0)
            labelFS:SetPoint("RIGHT", ico, "LEFT", -4, 0)
            labelFS:SetJustifyH("LEFT")
            labelFS:SetWordWrap(false)
            labelFS:SetMaxLines(1)
            labelFS:SetText(CludesUI.L(sp.name))
            labelFS:SetTextColor(baseR, baseG, baseB, baseA)

            local highlight = item:CreateTexture(nil, "ARTWORK", nil, -1)
            highlight:SetAllPoints()
            highlight:SetColorTexture(1, 1, 1, isSelected and 0.12 or 0)

            -- Gray out if already used on another bar
            if usedOnBar and not isSelected then
                labelFS:SetTextColor(tDimR, tDimG, tDimB, tDimA * 0.4)
                ico:SetDesaturated(true)
                ico:SetAlpha(0.4)
                item:SetScript("OnEnter", function()
                    CludesUI.ShowWidgetTooltip(
                        item,
                        CludesUI.Lf("Already assigned to %s", CludesUI.L(usedOnBar))
                    )
                    highlight:SetColorTexture(1, 1, 1, hlA * 0.3)
                    highlight:SetAlpha(1)
                end)
                item:SetScript("OnLeave", function()
                    CludesUI.HideWidgetTooltip()
                    highlight:SetAlpha(0)
                end)
                mH = mH + ITEM_H
                return
            end

            -- Tracked-but-untalented bar spells (no live BuffBar frame) stay clickable but
            -- render desaturated with a hint (matches CD/utility pickers), so bars can be set without swapping talents.
            local notLearned = (sp.isKnown == false)
            if notLearned then
                ico:SetDesaturated(true)
                ico:SetAlpha(0.5)
            end
            item:SetScript("OnEnter", function()
                labelFS:SetTextColor(1, 1, 1, 1)
                highlight:SetColorTexture(1, 1, 1, hlA)
                if notLearned then
                    CludesUI.ShowWidgetTooltip(item, CludesUI.L("Not currently talented"))
                end
            end)
            item:SetScript("OnLeave", function()
                labelFS:SetTextColor(baseR, baseG, baseB, baseA)
                highlight:SetColorTexture(1, 1, 1, isSelected and 0.12 or 0)
                if notLearned then
                    CludesUI.HideWidgetTooltip()
                end
            end)
            item:SetScript("OnClick", function()
                if notLearned then
                    CludesUI.HideWidgetTooltip()
                end
                dropMenu:Hide()
                barCfg.spellID = sp.spellID
                barCfg.spellIDs = nil
                barCfg.popularKey = nil
                barCfg.glowBased = nil
                barCfg.customDuration = nil
                barCfg.trackType = nil
                barCfg.name = sp.name
                barCfg.customName = nil
                -- Capture the BASE spell id for hero-talent override spells so the bar keeps
                -- tracking after the talent is removed (active override's cooldownInfo
                -- reports base in info.spellID); store only when it differs from the picked id.
                barCfg.baseSpellID = nil
                if sp.cdID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
                    local details = C_CooldownViewer.GetCooldownViewerCooldownInfo(sp.cdID)
                    local RTB_BASE_SPELL_ID = 1214909
                    local isSec = issecretvalue
                    local baseSID = details and details.spellID
                    if baseSID and (isSec and isSec(baseSID)) then
                        baseSID = nil
                    end
                    if baseSID and baseSID > 0 and baseSID ~= sp.spellID then
                        barCfg.baseSpellID = baseSID
                    end
                    -- Roll the Bones: ONE tracked-bar slot cycles through mutually
                    -- exclusive outcome buffs, listed only in the raw linkedSpellIDs.
                    -- The row resolves to whichever outcome is up at pick time, so a
                    -- single id matches nothing else after a re-roll: store the whole
                    -- family as the want-set and key the config on the stable base.
                    if baseSID == RTB_BASE_SPELL_ID and type(details.linkedSpellIDs) == "table" then
                        local ids = {}
                        for i = 1, #details.linkedSpellIDs do
                            local lid = details.linkedSpellIDs[i]
                            if type(lid) == "number" and not (isSec and isSec(lid)) and lid > 0 then
                                ids[#ids + 1] = lid
                            end
                        end
                        if #ids >= 2 then
                            barCfg.spellIDs = ids
                            barCfg.spellID = baseSID
                            barCfg.baseSpellID = nil
                            local nm = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(baseSID)
                            if nm and nm ~= "" then
                                barCfg.name = nm
                            end
                        end
                    end
                end
                Refresh()
                mod.BuildTrackedBuffBars()
                if onChanged then
                    onChanged()
                end
            end)
            mH = mH + ITEM_H
        end

        for _, sp in ipairs(trackedBars) do
            MakeSpellItem(sp)
        end

        -- "Missing Spells?" prompt (centered, accent-colored) closes CUI options and opens
        -- Blizzard's CDM; sits at the end of Buffs so it reads as the way to add more.
        do
            local FOOTER_H = 38
            local mbItem = CreateFrame("Button", nil, inner)
            mbItem:SetHeight(FOOTER_H)
            mbItem:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
            mbItem:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
            mbItem:SetFrameLevel(dropMenu:GetFrameLevel() + 2)

            local mbFS = mbItem:CreateFontString(nil, "OVERLAY")
            mbFS:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            mbFS:SetAllPoints()
            mbFS:SetJustifyH("CENTER")
            mbFS:SetJustifyV("MIDDLE")
            local ar, ag, ab = CludesUI.GetAccentColor()
            mbFS:SetTextColor(ar, ag, ab, 1)
            mbFS:SetText(
                CludesUI.L("Missing Spells? Add as") .. "\n" .. CludesUI.L("Tracking Bar in Blizz CDM")
            )

            mbItem:SetScript("OnEnter", function()
                mbFS:SetTextColor(1, 1, 1, 1)
            end)
            mbItem:SetScript("OnLeave", function()
                local r, g, b = CludesUI.GetAccentColor()
                mbFS:SetTextColor(r, g, b, 1)
            end)
            mbItem:SetScript("OnClick", function()
                dropMenu:Hide()
                if mod.OpenBlizzardCDMTab then
                    mod.OpenBlizzardCDMTab(true)
                end
            end)
            mH = mH + FOOTER_H
        end

        -- "Cooldowns" section: pick a spell COOLDOWN to track instead of a buff
        -- (cfg.trackType="cooldown"), sourced from Essential+Utility pools + settings catalog; skipped when empty.
        local cdSpells = mod.GetCDMSpellsForBar and mod.GetCDMSpellsForBar("cooldowns") or {}
        if #cdSpells > 0 then
            local cdDiv = inner:CreateTexture(nil, "ARTWORK")
            cdDiv:SetHeight(1)
            cdDiv:SetColorTexture(1, 1, 1, 0.10)
            cdDiv:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH - 4)
            cdDiv:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH - 4)
            mH = mH + 9

            local cdHdr = inner:CreateFontString(nil, "OVERLAY")
            cdHdr:SetFont(FONT_PATH, 10, GetCDMOptOutline())
            cdHdr:SetTextColor(1, 1, 1, 0.5)
            cdHdr:SetPoint("TOPLEFT", inner, "TOPLEFT", 10, -mH - 5)
            cdHdr:SetText(CludesUI.L("Cooldowns"))
            mH = mH + 20

            local function MakeCooldownItem(sp)
                -- Gray-out check is scoped to OTHER cooldown-tracking bars -- a buff bar for the same spell never blocks this pick.
                local usedOnBar = mod.SpellUsedOnAnyOtherTBB
                    and mod.SpellUsedOnAnyOtherTBB(sp.spellID, nil, "cooldown")
                local isSelected = barCfg.trackType == "cooldown"
                    and not barCfg.popularKey
                    and not barCfg.spellIDs
                    and barCfg.spellID
                    and barCfg.spellID > 0
                    and barCfg.spellID == sp.spellID
                local item = CreateFrame("Button", nil, inner)
                item:SetHeight(ITEM_H)
                item:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
                item:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
                item:SetFrameLevel(dropMenu:GetFrameLevel() + 2)

                local ico = item:CreateTexture(nil, "ARTWORK")
                local icoSz = ITEM_H - 4
                ico:SetSize(icoSz, icoSz)
                ico:SetPoint("RIGHT", item, "RIGHT", -6, 0)
                if sp.icon then
                    ico:SetTexture(sp.icon)
                end
                ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)

                local baseR = isSelected and 1 or tDimR
                local baseG = isSelected and 1 or tDimG
                local baseB = isSelected and 1 or tDimB
                local baseA = isSelected and 1 or tDimA

                local labelFS = item:CreateFontString(nil, "OVERLAY")
                labelFS:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                labelFS:SetPoint("LEFT", 8, 0)
                labelFS:SetPoint("RIGHT", ico, "LEFT", -4, 0)
                labelFS:SetJustifyH("LEFT")
                labelFS:SetWordWrap(false)
                labelFS:SetMaxLines(1)
                labelFS:SetText(CludesUI.L(sp.name))
                labelFS:SetTextColor(baseR, baseG, baseB, baseA)

                local highlight = item:CreateTexture(nil, "ARTWORK", nil, -1)
                highlight:SetAllPoints()
                highlight:SetColorTexture(1, 1, 1, isSelected and 0.12 or 0)

                -- Gray out if already used on another cooldown-tracking bar
                if usedOnBar and not isSelected then
                    labelFS:SetTextColor(tDimR, tDimG, tDimB, tDimA * 0.4)
                    ico:SetDesaturated(true)
                    ico:SetAlpha(0.4)
                    item:SetScript("OnEnter", function()
                        CludesUI.ShowWidgetTooltip(
                            item,
                            CludesUI.Lf("Already assigned to %s", CludesUI.L(usedOnBar))
                        )
                        highlight:SetColorTexture(1, 1, 1, hlA * 0.3)
                        highlight:SetAlpha(1)
                    end)
                    item:SetScript("OnLeave", function()
                        CludesUI.HideWidgetTooltip()
                        highlight:SetAlpha(0)
                    end)
                    mH = mH + ITEM_H
                    return
                end

                -- Untalented catalog spells stay clickable but render desaturated with a hint, matching the buff rows above.
                local notLearned = (sp.isKnown == false)
                if notLearned then
                    ico:SetDesaturated(true)
                    ico:SetAlpha(0.5)
                end
                item:SetScript("OnEnter", function()
                    labelFS:SetTextColor(1, 1, 1, 1)
                    highlight:SetColorTexture(1, 1, 1, hlA)
                    if notLearned then
                        CludesUI.ShowWidgetTooltip(item, CludesUI.L("Not currently talented"))
                    end
                end)
                item:SetScript("OnLeave", function()
                    labelFS:SetTextColor(baseR, baseG, baseB, baseA)
                    highlight:SetColorTexture(1, 1, 1, isSelected and 0.12 or 0)
                    if notLearned then
                        CludesUI.HideWidgetTooltip()
                    end
                end)
                item:SetScript("OnClick", function()
                    if notLearned then
                        CludesUI.HideWidgetTooltip()
                    end
                    dropMenu:Hide()
                    barCfg.spellID = sp.spellID
                    barCfg.spellIDs = nil
                    barCfg.popularKey = nil
                    barCfg.glowBased = nil
                    barCfg.customDuration = nil
                    barCfg.trackType = "cooldown"
                    barCfg.name = sp.name
                    barCfg.customName = nil
                    -- Capture the BASE spell id for hero-talent override spells so the bar keeps tracking after the talent is removed.
                    barCfg.baseSpellID = nil
                    if sp.cdID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo then
                        local details = C_CooldownViewer.GetCooldownViewerCooldownInfo(sp.cdID)
                        if
                            details
                            and details.spellID
                            and details.spellID > 0
                            and details.spellID ~= sp.spellID
                        then
                            barCfg.baseSpellID = details.spellID
                        end
                    end
                    Refresh()
                    mod.BuildTrackedBuffBars()
                    if onChanged then
                        onChanged()
                    end
                end)
                mH = mH + ITEM_H
            end

            for _, sp in ipairs(cdSpells) do
                MakeCooldownItem(sp)
            end
        end

        local totalH = mH + 4
        inner:SetHeight(totalH)
        if totalH > MAX_H then
            dropMenu:SetHeight(MAX_H)
            local scrollFrame = CreateFrame("ScrollFrame", nil, dropMenu)
            scrollFrame:SetPoint("TOPLEFT", 0, -1)
            scrollFrame:SetPoint("BOTTOMRIGHT", 0, 1)
            scrollFrame:SetFrameLevel(dropMenu:GetFrameLevel() + 1)
            scrollFrame:EnableMouseWheel(true)
            scrollFrame:SetScrollChild(inner)
            inner:SetWidth(menuW)
            local scrollPos = 0
            local maxScroll = totalH - MAX_H
            scrollFrame:SetScript("OnMouseWheel", function(_, delta)
                scrollPos = math.max(0, math.min(maxScroll, scrollPos - delta * 30))
                scrollFrame:SetVerticalScroll(scrollPos)
            end)
        else
            dropMenu:SetHeight(totalH)
            inner:SetParent(dropMenu)
            inner:SetPoint("TOPLEFT")
        end

        dropMenu:ClearAllPoints()
        dropMenu:SetPoint("TOP", anchor, "BOTTOM", 0, -2)
        dropMenu:SetScript("OnUpdate", function(m)
            if not m:IsMouseOver() and not anchor:IsMouseOver() and IsMouseButtonDown("LeftButton") then
                m:Hide()
            end
        end)
        dropMenu:HookScript("OnHide", function(m)
            m:SetScript("OnUpdate", nil)
        end)
        dropMenu:Show()
        _tbbSpellPickerMenu = dropMenu
    end

    -- Select a bar and open its buff picker anchored to the management dropdown (used by
    -- the dropdown's bar rows); page refresh runs first so the picker anchors to the fresh button.
    local function OpenBuffPickerForBar(idx)
        _tbbSelectedBar = idx
        _tbbSelectedGroup = nil
        CludesUI:RefreshPage(true)
        C_Timer.After(0, function()
            local t = mod.GetTrackedBuffBars()
            local conf = t.bars and t.bars[idx]
            if conf and _tbbDDBtn and _tbbDDBtn:IsShown() then
                ShowTBBSpellPicker(_tbbDDBtn, conf, function()
                    CludesUI:RefreshPage(true)
                end)
            end
        end)
    end

    -- Smallest unused "Preset N" default name for the save popup.
    local function UniqueTBBPresetName()
        local presets = mod.GetTBBStylePresets and mod.GetTBBStylePresets() or {}
        local function taken(nm)
            for _, pr in ipairs(presets) do
                if pr.name == nm then
                    return true
                end
            end
            return false
        end
        local num = 1
        while taken("Preset " .. num) do
            num = num + 1
        end
        return "Preset " .. num
    end

    ---------------------------------------------------------------------------
    --  Stack threshold editor (opt-in) popup, opened from the cog on "Enable Stack
    --  Threshold"; edits cfg.stackThresholds -- an ordered list of {value=<stack count>,
    --  r,g,b,a} color stops capped at STACK_THRESH_MAX. Only drives rendering while
    --  cfg.stackThresholdMulti is on (else legacy single-threshold keys own the bar).
    --  ShowStackThreshEditor() rebinds per calling bar.
    ---------------------------------------------------------------------------
    local STACK_THRESH_MAX = 5
    local _stCloseIcon = "Interface\\AddOns\\CludesUI\\media\\icons\\cui-close.png"
    local stPopup
    local _stRows = {}
    local _stGetCfg, _stRefreshFn
    local _stMultiRow, _stMultiSnap, _stAddBtn, _stAddLbl
    local ST_POPUP_W = 260
    local ST_ROW_H = 26
    local ST_PAD = 14
    local ST_GAP = 10
    local ST_DEF_R, ST_DEF_G, ST_DEF_B, ST_DEF_A = 0.8, 0.1, 0.1, 1
    local RefreshStackThreshEditor -- forward decl

    -- Shared explainers; literals live inside the L() calls so extract-locale-keys.sh can
    -- see them (it only reads string literals passed directly to L/Lf, never variables).
    local function StackThreshHelpTip()
        return CludesUI.L(
            "Color the bar differently at several stack counts. The highest count you have reached wins."
        )
    end
    local function StackThreshReplacesTip()
        return CludesUI.L("The single stack threshold is off while Multiple Thresholds is on.")
    end
    local function StackThreshAtCapTip()
        return CludesUI.L("Maximum of 5 thresholds.")
    end

    local function CurrentStackThreshCfg()
        if not _stGetCfg then
            return nil
        end
        return _stGetCfg()
    end

    local function SortStackThresholds(entries)
        table.sort(entries, function(a, b)
            return (a.value or 0) < (b.value or 0)
        end)
    end

    local function BuildStackThreshPopup()
        stPopup = CreateFrame("Frame", nil, UIParent)
        stPopup:SetFrameStrata("FULLSCREEN_DIALOG")
        stPopup:SetFrameLevel(260)
        stPopup:SetClampedToScreen(true)
        stPopup:EnableMouse(true)
        stPopup:SetScale(0.9)
        stPopup:Hide()
        Pix.Size(stPopup, ST_POPUP_W, 200)

        local backdrop = stPopup:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(0.062, 0.070, 0.082, 0.97)
        stPopup._brd = CludesUI.MakeRoundedBorder(stPopup, 1, 1, 1, 0.18, backdrop)

        local clickCatcher = CreateFrame("Button", nil, stPopup)
        clickCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
        clickCatcher:SetFrameLevel(stPopup:GetFrameLevel() - 1)
        clickCatcher:SetAllPoints((CludesUI:GetMainFrame()) or UIParent)
        clickCatcher:SetScript("OnClick", function()
            stPopup:Hide()
        end)
        clickCatcher:Hide()
        -- Close on entering combat
        stPopup:SetScript("OnEvent", function(self, evt)
            if evt == "PLAYER_REGEN_DISABLED" then
                self:Hide()
            end
        end)
        stPopup:SetScript("OnShow", function(self)
            clickCatcher:Show()
            self:RegisterEvent("PLAYER_REGEN_DISABLED")
            self:SetScript("OnUpdate", function(p)
                if IsMouseButtonDown("LeftButton") then
                    local mf = CludesUI._mainFrame
                    local dm = CludesUI._openDropdownMenu
                    if
                        not p:IsMouseOver()
                        and not (mf and mf:IsMouseOver())
                        and not (dm and dm:IsShown() and dm:IsMouseOver())
                    then
                        p:Hide()
                    end
                end
            end)
        end)
        stPopup:SetScript("OnHide", function(self)
            clickCatcher:Hide()
            self:UnregisterEvent("PLAYER_REGEN_DISABLED")
            self:SetScript("OnUpdate", nil)
        end)

        local titleFS = CludesUI.MakeFont(stPopup, 13, nil, 1, 1, 1)
        titleFS:SetAlpha(0.6)
        titleFS:SetPoint("TOP", stPopup, "TOP", 0, -ST_PAD)
        titleFS:SetText(CludesUI.L("Stack Thresholds"))

        -- Row: multi opt-in (label left, toggle right) -- matches the band editor.
        _stMultiRow = CreateFrame("Frame", nil, stPopup)
        _stMultiRow:SetFrameLevel(stPopup:GetFrameLevel() + 3)
        Pix.Height(_stMultiRow, ST_ROW_H)
        local mlbl = CludesUI.MakeFont(_stMultiRow, 12, nil, 1, 1, 1)
        mlbl:SetAlpha(0.6)
        mlbl:SetPoint("LEFT", _stMultiRow, "LEFT", 0, 0)
        mlbl:SetText(CludesUI.L("Use Multiple Thresholds"))
        local multiToggle, _
        multiToggle, _, _stMultiSnap = CludesUI.BuildToggleControl(
            _stMultiRow,
            _stMultiRow:GetFrameLevel() + 3,
            function()
                local conf = CurrentStackThreshCfg()
                return conf and conf.stackThresholdMulti
            end,
            function(v)
                local conf = CurrentStackThreshCfg()
                if not conf then
                    return
                end
                conf.stackThresholdMulti = v and true or false
                if _stRefreshFn then
                    _stRefreshFn()
                end
                RefreshStackThreshEditor()
                CludesUI:RefreshPage()
            end,
            { sizeRatio = 0.95 }
        )
        multiToggle:SetPoint("RIGHT", _stMultiRow, "RIGHT", 0, 0)
        local multiHit = CreateFrame("Frame", nil, _stMultiRow)
        multiHit:SetAllPoints(mlbl)
        multiHit:EnableMouse(true)
        multiHit:SetScript("OnEnter", function(self)
            CludesUI.ShowWidgetTooltip(self, StackThreshHelpTip())
        end)
        multiHit:SetScript("OnLeave", function()
            CludesUI.HideWidgetTooltip()
        end)

        -- Add Threshold button
        _stAddBtn = CreateFrame("Button", nil, stPopup)
        Pix.Size(_stAddBtn, ST_POPUP_W - ST_PAD * 2, 26)
        _stAddBtn:SetFrameLevel(stPopup:GetFrameLevel() + 3)
        local abg = CludesUI.SolidTex(_stAddBtn, "BACKGROUND", 0.050, 0.058, 0.068, 0.92)
        abg:SetAllPoints()
        _stAddBtn._border = CludesUI.MakeRoundedBorder(_stAddBtn, 1, 1, 1, 0.4, abg)
        _stAddLbl = CludesUI.MakeFont(_stAddBtn, 12, nil, 1, 1, 1)
        _stAddLbl:SetAlpha(0.5)
        _stAddLbl:SetPoint("CENTER")
        _stAddLbl:SetText(CludesUI.L("+ Add Threshold"))
        _stAddBtn:SetScript("OnEnter", function(self)
            local conf = CurrentStackThreshCfg()
            local entries = conf and conf.stackThresholds
            if entries and #entries >= STACK_THRESH_MAX then
                CludesUI.ShowWidgetTooltip(self, StackThreshAtCapTip())
                return
            end
            _stAddLbl:SetAlpha(0.7)
            if self._border and self._border.SetColor then
                self._border:SetColor(1, 1, 1, 0.6)
            end
        end)
        _stAddBtn:SetScript("OnLeave", function(self)
            CludesUI.HideWidgetTooltip()
            _stAddLbl:SetAlpha(0.5)
            if self._border and self._border.SetColor then
                self._border:SetColor(1, 1, 1, 0.4)
            end
        end)
        _stAddBtn:SetScript("OnClick", function()
            local conf = CurrentStackThreshCfg()
            if not conf then
                return
            end
            if not conf.stackThresholds then
                conf.stackThresholds = {}
            end
            local entries = conf.stackThresholds
            if #entries >= STACK_THRESH_MAX then
                return
            end
            local last = entries[#entries]
            local nextVal = last and math.min(100, (last.value or 0) + 1) or 5
            entries[#entries + 1] =
                { value = nextVal, r = ST_DEF_R, g = ST_DEF_G, b = ST_DEF_B, a = ST_DEF_A }
            SortStackThresholds(entries)
            if _stRefreshFn then
                _stRefreshFn()
            end
            RefreshStackThreshEditor()
        end)
    end

    -- Lazily create the widgets for threshold row k; returns the row table.
    local function EnsureStackThreshRow(k)
        local row = _stRows[k]
        if row then
            return row
        end
        row = {}
        local rf = CreateFrame("Frame", nil, stPopup)
        rf:SetSize(ST_POPUP_W - ST_PAD * 2, ST_ROW_H)
        rf:SetFrameLevel(stPopup:GetFrameLevel() + 2)
        row.frame = rf

        local labelFS = CludesUI.MakeFont(rf, 12, nil, 1, 1, 1)
        labelFS:SetAlpha(0.6)
        labelFS:SetPoint("LEFT", rf, "LEFT", 2, 0)
        labelFS:SetText(CludesUI.L("At"))
        row.lbl = labelFS

        local input = CreateFrame("EditBox", nil, rf)
        input:SetSize(54, 22)
        input:SetPoint("LEFT", labelFS, "RIGHT", 6, 0)
        input:SetFrameLevel(rf:GetFrameLevel() + 2)
        input:SetAutoFocus(false)
        input:SetFontObject(GameFontHighlightSmall)
        local inFont = CludesUI.GetFontPath("main") or "Fonts\\FRIZQT__.TTF"
        input:SetFont(inFont, 12, "")
        input:SetTextColor(1, 1, 1, 0.75)
        input:SetJustifyH("CENTER")
        input:SetNumeric(true)
        local inBg = input:CreateTexture(nil, "BACKGROUND")
        inBg:SetAllPoints()
        inBg:SetColorTexture(0.12, 0.12, 0.12, 0.8)
        CludesUI.MakeRoundedBorder(input, 1, 1, 1, 0.08, inBg)
        row.input = input

        -- Commit on focus loss (Enter clears focus -> triggers this; Escape sets
        -- _cancelCommit to discard the typed text).
        local function CommitInput(self)
            if self._cancelCommit then
                self._cancelCommit = nil
                return
            end
            local conf = CurrentStackThreshCfg()
            local entries = conf and conf.stackThresholds
            local ent = entries and entries[row._idx]
            if not ent then
                return
            end
            local val = tonumber(self:GetText())
            if val then
                -- Same range as the single-threshold slider on the Extras row.
                ent.value = math.max(0, math.min(100, math.floor(val + 0.5)))
                SortStackThresholds(entries)
                if _stRefreshFn then
                    _stRefreshFn()
                end
            end
            RefreshStackThreshEditor()
        end
        input:SetScript("OnEditFocusLost", CommitInput)
        input:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
        end)
        input:SetScript("OnEscapePressed", function(self)
            self._cancelCommit = true
            self:ClearFocus()
            RefreshStackThreshEditor()
        end)

        local colorSwatch, swatchSnap = CludesUI.BuildColorSwatch(rf, rf:GetFrameLevel() + 3, function()
            local conf = CurrentStackThreshCfg()
            local entries = conf and conf.stackThresholds
            local ent = entries and entries[row._idx]
            if not ent then
                return ST_DEF_R, ST_DEF_G, ST_DEF_B, ST_DEF_A
            end
            return ent.r or ST_DEF_R, ent.g or ST_DEF_G, ent.b or ST_DEF_B, ent.a or ST_DEF_A
        end, function(r, g, b, a)
            local conf = CurrentStackThreshCfg()
            local entries = conf and conf.stackThresholds
            local ent = entries and entries[row._idx]
            if ent then
                ent.r, ent.g, ent.b, ent.a = r, g, b, a
                if _stRefreshFn then
                    _stRefreshFn()
                end
            end
        end, true, 19)
        colorSwatch:SetPoint("LEFT", input, "RIGHT", 10, 0)
        row.swatch = colorSwatch
        row.swatchSnap = swatchSnap

        local delBtn = CreateFrame("Button", nil, rf)
        delBtn:SetSize(14, 14)
        delBtn:SetPoint("RIGHT", rf, "RIGHT", -2, 0)
        delBtn:SetFrameLevel(rf:GetFrameLevel() + 3)
        local delIcon = delBtn:CreateTexture(nil, "OVERLAY")
        delIcon:SetAllPoints()
        delIcon:SetTexture(_stCloseIcon)
        delIcon:SetAlpha(0.4)
        delBtn:SetScript("OnEnter", function()
            delIcon:SetAlpha(0.9)
        end)
        delBtn:SetScript("OnLeave", function()
            delIcon:SetAlpha(0.4)
        end)
        delBtn:SetScript("OnClick", function()
            local conf = CurrentStackThreshCfg()
            local entries = conf and conf.stackThresholds
            if entries and entries[row._idx] then
                table.remove(entries, row._idx)
                -- An empty list would silently fall back to the single threshold while the
                -- toggle still reads "on"; turn it off so the popup matches the bar.
                if #entries == 0 and conf.stackThresholdMulti then
                    conf.stackThresholdMulti = false
                    CludesUI:RefreshPage()
                end
                if _stRefreshFn then
                    _stRefreshFn()
                end
                RefreshStackThreshEditor()
            end
        end)
        row.delBtn = delBtn

        _stRows[k] = row
        return row
    end

    RefreshStackThreshEditor = function()
        if not stPopup then
            return
        end
        local conf = CurrentStackThreshCfg()
        if not conf then
            stPopup:Hide()
            return
        end
        if not conf.stackThresholds then
            conf.stackThresholds = {}
        end
        local entries = conf.stackThresholds

        local curY = -(ST_PAD + 24) -- below the title

        _stMultiRow:ClearAllPoints()
        Pix.Point(_stMultiRow, "TOPLEFT", stPopup, "TOPLEFT", ST_PAD, curY)
        Pix.Point(_stMultiRow, "TOPRIGHT", stPopup, "TOPRIGHT", -ST_PAD, curY)
        _stMultiRow:Show()
        if _stMultiSnap then
            _stMultiSnap()
        end
        curY = curY - ST_ROW_H - ST_GAP

        local num = #entries
        for k = 1, num do
            local row = EnsureStackThreshRow(k)
            row._idx = k
            row.frame:ClearAllPoints()
            Pix.Point(row.frame, "TOPLEFT", stPopup, "TOPLEFT", ST_PAD, curY)
            row.input:SetText(tostring(entries[k].value or 5))
            if row.swatchSnap then
                row.swatchSnap()
            end
            row.frame:Show()
            curY = curY - ST_ROW_H - 4
        end
        for k = num + 1, #_stRows do
            if _stRows[k] then
                _stRows[k].frame:Hide()
            end
        end

        curY = curY - 4
        _stAddBtn:ClearAllPoints()
        Pix.Point(_stAddBtn, "TOPLEFT", stPopup, "TOPLEFT", ST_PAD, curY)
        local atCap = (num >= STACK_THRESH_MAX)
        _stAddBtn:SetEnabled(not atCap)
        _stAddBtn:SetAlpha(atCap and 0.35 or 1)
        curY = curY - 26

        local totalH = math.abs(curY) + ST_PAD
        Pix.Size(stPopup, ST_POPUP_W, totalH)
        stPopup._brd:Fit()
    end

    -- params = { getCfg, refreshFn, anchor }
    local function ShowStackThreshEditor(params)
        if not stPopup then
            BuildStackThreshPopup()
        end
        _stGetCfg = params.getCfg
        _stRefreshFn = params.refreshFn
        local conf = CurrentStackThreshCfg()
        if conf then
            if not conf.stackThresholds then
                conf.stackThresholds = {}
            end
            -- Seed the first entry from the single threshold the first time; inert until
            -- stackThresholdMulti is on, so opening/closing this popup changes nothing on the bar.
            if #conf.stackThresholds == 0 then
                conf.stackThresholds[1] = {
                    value = conf.stackThreshold or 5,
                    r = conf.stackThresholdR or ST_DEF_R,
                    g = conf.stackThresholdG or ST_DEF_G,
                    b = conf.stackThresholdB or ST_DEF_B,
                    a = conf.stackThresholdA or ST_DEF_A,
                }
            end
        end
        RefreshStackThreshEditor()
        stPopup:ClearAllPoints()
        stPopup:SetPoint("TOP", params.anchor, "BOTTOM", 0, -4)
        stPopup:Show()
    end

    local function BuildBuffBarsPage(page, hostFrame, yOffset)
        local W = CludesUI.Widgets
        local posY = yOffset
        local _, hgt, heading

        -- If user chose Blizzard bars, show re-enable button and bail
        local usingBlizz = DB() and DB().cdmBars and DB().cdmBars.useBlizzardBuffBars
        if usingBlizz then
            _, hgt = W:WideDualButton(hostFrame, "Enable Tracking Bars", "Open Blizzard CDM", posY, function()
                local p = DB()
                if p and p.cdmBars then
                    p.cdmBars.useBlizzardBuffBars = false
                end
                CludesUI:ShowConfirmPopup({
                    title = "Reload Required",
                    message = "Switching to CludesUI Tracking Bars requires a reload.",
                    confirmText = "Reload Now",
                    cancelText = "Later",
                    reload = true,
                })
            end, function()
                if mod.OpenBlizzardCDMTab then
                    mod.OpenBlizzardCDMTab(true)
                end
            end, 310)
            posY = posY - hgt
            return math.abs(posY)
        end

        -- Pre-populate bars for spells newly added to Blizzard's Tracked Bars before
        -- reading the bar list, so the page always shows them.
        if mod.EnsureTBBAutoBars and mod.EnsureTBBAutoBars() > 0 then
            mod.BuildTrackedBuffBars()
        end

        local tbb = mod.GetTrackedBuffBars()
        -- Hold the per-group orientation invariant before any widget reads the configs
        -- (the page-tail rebuild runs after).
        if mod.EnforceTBBGroupOrientation then
            mod.EnforceTBBGroupOrientation(tbb)
        end
        local barList = tbb.bars
        if _tbbSelectedBar > #barList then
            _tbbSelectedBar = math.max(1, #barList)
        end

        local function SelectedTBB()
            local t = mod.GetTrackedBuffBars()
            if _tbbSelectedBar < 1 or _tbbSelectedBar > #t.bars then
                return nil
            end
            return t.bars[_tbbSelectedBar]
        end

        local function SelectedTBBSupportsChargeHash()
            local bd = SelectedTBB()
            return bd and mod.GetTBBMaxCharges and mod.GetTBBMaxCharges(bd) ~= nil
        end

        -- Validate the group selection against the live group list (groups dissolve when
        -- their last bar is deleted). Bar-less GLOBAL groups are legal selections: the
        -- Currently Editing menu lists them on every spec precisely so their shared
        -- settings stay editable, and their local gid persists through its globalKey
        -- link with no member bars (every GROUP MODE section is group-keyed and the
        -- previews hide/guard on an empty member list).
        if _tbbSelectedGroup then
            local success = false
            for _, g in ipairs(mod.TBBGroupIDsInUse()) do
                if g == _tbbSelectedGroup then
                    success = true
                    break
                end
            end
            if not success and mod.TBBGroupGlobalKey and mod.TBBGroupGlobalKey(_tbbSelectedGroup) then
                success = true
            end
            if not success then
                _tbbSelectedGroup = nil
            end
        end

        -- The preview mirrors whatever is being edited: the selected bar, or the selected
        -- group's style source (its anchor bar).
        local function PreviewCfg()
            if _tbbSelectedGroup then
                return mod.TBBGroupStyleSource(_tbbSelectedGroup)
            end
            return SelectedTBB()
        end

        local function GroupLabel(groupId)
            return (mod.TBBGroupName and mod.TBBGroupName(groupId)) or (CludesUI.L("Group") .. " " .. groupId)
        end

        -------------------------------------------------------------------
        --  CLICK NAVIGATION (preview elements -> option rows). Map lives on
        --  parent._tbbClickTargets (populated by the bar-mode section build below);
        --  overlays resolve it at click time so a header rebuild never holds stale refs.
        -------------------------------------------------------------------
        local PlaySettingGlow = CludesUI.MakeSettingGlow({ color = CludesUI.CLUDES_GREEN })

        local function NavigateToSetting(key)
            local targets = hostFrame._tbbClickTargets
            if not targets then
                return
            end
            local m = targets[key]
            if not m or not m.section or not m.target then
                return
            end
            CludesUIDB = CludesUIDB or {}
            CludesUIDB.previewHintDismissed = true
            if _tbbPopout and _tbbPopout._hint then
                _tbbPopout._hint:Hide()
            end
            local _, _, _, _, headerY = m.section:GetPoint(1)
            if not headerY then
                return
            end
            CludesUI.SmoothScrollTo(math.max(0, math.abs(headerY) - 40))
            local glowTarget = m.target
            if m.slotSide then
                local regionFrame = (m.slotSide == "left") and m.target._leftRegion or m.target._rightRegion
                if regionFrame then
                    glowTarget = regionFrame
                end
            end
            -- Not on a row a rebuild has meanwhile dressed again for another setting.
            local targetGen = PoolGen(glowTarget)
            C_Timer.After(0.15, function()
                if PoolGen(glowTarget) == targetGen then
                    PlaySettingGlow(glowTarget)
                end
            end)
        end

        local _tbbRefreshTimer

        local function RefreshTBB()
            if _tbbRefreshTimer then
                _tbbRefreshTimer:Cancel()
            end
            _tbbRefreshTimer = C_Timer.NewTimer(0.05, function()
                _tbbRefreshTimer = nil
                Refresh()
                mod.BuildTrackedBuffBars()
                RefreshTBBPopout()
                UpdateTBBPlaceholder()
            end)
        end
        -- Expose this build's RefreshTBB to the outer spec-change watcher so a spec swap
        -- while this page is open rebuilds the dropdown/preview.
        _tbbRefreshFn = RefreshTBB

        -- Drag-and-drop move: put a bar into another group (or make it independent).
        -- Joining a group adopts its current look, same as a freshly added bar; selects the moved bar.
        local function MoveBarToGroup(idx, groupId)
            local t = mod.GetTrackedBuffBars()
            local conf = t.bars and t.bars[idx]
            if not conf then
                return
            end
            if mod.TBBBarGroupID(conf) == groupId then
                return
            end
            mod.TBBSetBarGroup(conf, groupId)
            if groupId ~= 0 then
                local source = mod.TBBGroupStyleSource(groupId)
                if source and source ~= conf then
                    mod.CopyTBBStyle(source, conf)
                end
            end
            _tbbSelectedBar = idx
            _tbbSelectedGroup = nil
            mod.BuildTrackedBuffBars()
            CludesUI:RefreshPage(true)
        end

        -- Drag-and-drop reorder inside the bar's own group: no style copy, the
        -- editing context stays (a selected bar follows its config to its new
        -- index) and the menu opens again on the fresh button for the next move.
        local function ReorderBarInGroup(idx, place)
            local t = mod.GetTrackedBuffBars()
            local sel = not _tbbSelectedGroup and t.bars[_tbbSelectedBar] or nil
            mod.MoveTrackedBuffBarInGroup(idx, place)
            for jdx, c in ipairs(t.bars) do
                if c == sel then
                    _tbbSelectedBar = jdx
                    break
                end
            end
            CludesUI:RefreshPage(true)
            C_Timer.After(0, function()
                if _tbbDDBtn and _tbbDDBtn:IsShown() then
                    _tbbDDBtn:Click()
                end
            end)
        end

        -------------------------------------------------------------------
        --  MANAGEMENT DROPDOWN builder ("Currently Editing:"). Creates the bar/group
        --  selector inside `parentFrame` (Preset Style panel), returns the dropdown
        --  button; caller positions it.
        -------------------------------------------------------------------
        local function BuildManagementDropdown(parentFrame)
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

            local ddBtn = CreateFrame("Button", nil, parentFrame)
            Pix.Size(ddBtn, ddW, DD_H)
            ddBtn:SetFrameLevel(parentFrame:GetFrameLevel() + 5)
            local ddBg = ddBtn:CreateTexture(nil, "BACKGROUND")
            ddBg:SetAllPoints()
            ddBg:SetColorTexture(mBgR, mBgG, mBgB, mBgA)
            local ddBrd = CludesUI.MakeRoundedBorder(ddBtn, 1, 1, 1, mBrdA, ddBg)
            local ddLbl = ddBtn:CreateFontString(nil, "OVERLAY")
            ddLbl:SetFont(FONT_PATH, 13, GetCDMOptOutline())
            ddLbl:SetAlpha(mTxtA)
            ddLbl:SetJustifyH("LEFT")
            ddLbl:SetWordWrap(false)
            ddLbl:SetMaxLines(1)
            ddLbl:SetPoint("LEFT", ddBtn, "LEFT", 12, 0)
            local arrow = CludesUI.MakeDropdownArrow(ddBtn, 12, CludesUI.PanelPP)
            ddLbl:SetPoint("RIGHT", arrow, "LEFT", -5, 0)

            local function UpdateDDLabel()
                if _tbbSelectedGroup then
                    local num = mod.TBBGroupedCount(_tbbSelectedGroup)
                    ddLbl:SetText(
                        GroupLabel(_tbbSelectedGroup)
                            .. "  -  "
                            .. num
                            .. " "
                            .. CludesUI.L(num == 1 and "Bar" or "Bars")
                    )
                    return
                end
                local bd = SelectedTBB()
                if bd then
                    local label = (bd.name and CludesUI.L(bd.name)) or "Bar"
                    if not bd.popularKey and bd.spellID and bd.spellID > 0 then
                        local details = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(bd.spellID)
                        if details and details.name then
                            label = details.name
                        end
                    end
                    local groupId = mod.TBBBarGroupID and mod.TBBBarGroupID(bd) or 0
                    if groupId ~= 0 then
                        label = label .. "  (" .. GroupLabel(groupId) .. ")"
                    end
                    ddLbl:SetText(label)
                else
                    -- Re-fetch the live (per-spec) bar count instead of the build-time `bars`
                    -- upvalue: this header builder is reused across SetContentHeader refreshes
                    -- (e.g. spec change) without a page rebuild, so captured `bars` can be stale.
                    local liveBars = mod.GetTrackedBuffBars().bars
                    if not liveBars or #liveBars == 0 then
                        ddLbl:SetText(CludesUI.L("No Bars - Click to Add"))
                    else
                        ddLbl:SetText(CludesUI.L("Select a bar"))
                    end
                end
            end
            UpdateDDLabel()

            -- Can this bar play Audio on Buff Gain / Loss? The one check behind the
            -- row right-click, the speaker mark and the menu hint. A sound follows a
            -- buff edge: the bar needs a buff assigned and tracked as a buff (never a
            -- cooldown-tracking bar), and the runtime needs an edge source for it (a
            -- Blizzard buff viewer frame, or a self-timed preset).
            local function BarTakesSound(b)
                if not b or b.trackType == "cooldown" then
                    return false
                end
                if not ((b.spellID and b.spellID > 0) or b.glowBased) then
                    return false
                end
                return mod.TBB_BarCanCue(b) and true or false
            end

            -- Right-click a bar row: Audio on Buff Gain / Loss for that bar, the
            -- tracking-bar twin of the CDM icon menu's two audio rows. Opens beside the
            -- clicked row; each row flies out the shared sound list (search, scroll,
            -- preview speaker) from BuildSoundDropdownValues. Same keys and sound
            -- catalogue as the icon menu; playback lives in CUI_CDM_BuffBarAssign.lua.
            local function OpenBarSoundMenu(idx, anchorRow)
                local t = mod.GetTrackedBuffBars()
                local conf = t.bars and t.bars[idx]
                if not conf then
                    return
                end
                if ddBtn._tbbSndMenu then
                    ddBtn._tbbSndMenu:Hide()
                end
                local W = 240
                -- One sound menu frame for the session, dressed again on every open.
                local sm = PoolKept(mod, "tbbSoundMenu", "Frame", UIParent)
                sm:SetFrameStrata("FULLSCREEN_DIALOG")
                -- Above the bar menu it opens from (300), which stays open underneath.
                sm:SetFrameLevel(320)
                sm:SetClampedToScreen(true)
                sm:EnableMouse(true)
                sm:SetSize(W, 8 + ITEM_H * 2)
                local smBg = sm:CreateTexture(nil, "BACKGROUND")
                smBg:SetAllPoints()
                smBg:SetColorTexture(mBgR, mBgG, mBgB, mBgHA)
                CludesUI.MakeRoundedBorder(sm, 1, 1, 1, mBrdA, smBg, nil, true)
                -- A fixed spot, as the CDM icon menu sits under its icon: beside the clicked
                -- row, just outside the bar menu, so it covers no other bar.
                sm:SetPoint("TOPLEFT", anchorRow, "TOPRIGHT", 4, 0)
                local ar, ag, ab = CludesUI.GetAccentColor()
                local nameList = mod.FOCUSKICK_SOUND_NAMES or {}
                local flyouts = {}

                local function MakeSoundRow(i, label, field)
                    local row = CreateFrame("Button", nil, sm)
                    row:SetHeight(ITEM_H)
                    row:SetPoint("TOPLEFT", sm, "TOPLEFT", 1, -4 - (i - 1) * ITEM_H)
                    row:SetPoint("TOPRIGHT", sm, "TOPRIGHT", -1, -4 - (i - 1) * ITEM_H)
                    row:SetFrameLevel(sm:GetFrameLevel() + 2)
                    local labelFS = row:CreateFontString(nil, "OVERLAY")
                    labelFS:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                    labelFS:SetPoint("LEFT", row, "LEFT", 10, 0)
                    labelFS:SetText(CludesUI.L(label))
                    local arrow = row:CreateTexture(nil, "ARTWORK")
                    arrow:SetSize(10, 10)
                    arrow:SetPoint("RIGHT", row, "RIGHT", -8, 0)
                    arrow:SetTexture(MEDIA .. "icons\\right-arrow.png")
                    arrow:SetAlpha(0.7)
                    local val = row:CreateFontString(nil, "OVERLAY")
                    val:SetFont(FONT_PATH, 10, GetCDMOptOutline())
                    val:SetPoint("LEFT", labelFS, "RIGHT", 8, 0)
                    val:SetPoint("RIGHT", arrow, "LEFT", -6, 0)
                    val:SetJustifyH("RIGHT")
                    val:SetWordWrap(false)
                    val:SetMaxLines(1)
                    val:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                    local highlight = row:CreateTexture(nil, "ARTWORK")
                    highlight:SetAllPoints()
                    highlight:SetColorTexture(1, 1, 1, 1)
                    highlight:SetAlpha(0)

                    local function Get()
                        return conf[field] or "none"
                    end
                    -- Accent label while a sound is chosen, like the icon menu's rows.
                    local function Paint()
                        local k = conf[field]
                        if k and k ~= "none" then
                            labelFS:SetTextColor(ar, ag, ab, 1)
                        else
                            labelFS:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                        end
                        val:SetText(nameList[Get()] or Get())
                    end
                    Paint()
                    local function Set(v)
                        conf[field] = (v ~= "none" and v) or nil
                        if conf[field] then
                            -- Flip the 0-cost gate live and hook the bar frames already
                            -- out of the pool, so the next edge plays without a reload.
                            mod._cdmAnyBuffSound = true
                            if mod.EnsureTBBSoundHooks then
                                mod.EnsureTBBSoundHooks()
                            end
                        end
                        Paint()
                        -- The bar row's speaker button follows (dimmed with no sound).
                        if anchorRow._sndPaint then
                            anchorRow._sndPaint()
                        end
                    end
                    local function ShowFlyout()
                        highlight:SetAlpha(hlA)
                        for f, fly in pairs(flyouts) do
                            if f ~= field then
                                fly:Hide()
                            end
                        end
                        local fly = flyouts[field]
                        if not fly then
                            local values, sequence = CludesUI.BuildSoundDropdownValues(
                                mod.FOCUSKICK_SOUND_PATHS,
                                nameList,
                                mod.FOCUSKICK_SOUND_ORDER
                            )
                            values._menuOpts.anchor = "RIGHT"
                            -- Match the CDM icon menu's flyouts: the CDM options font at 11 and
                            -- the speaker atlas in its own colour.
                            values._menuOpts.labelFont = { FONT_PATH, 11, GetCDMOptOutline() }
                            values._menuOpts.iconNativeColor = true
                            local refresh
                            fly, _, refresh = CludesUI.BuildDropdownMenu(
                                row,
                                200,
                                sequence,
                                values,
                                Get,
                                Set,
                                val,
                                "regular"
                            )
                            -- BuildDropdownMenu creates it at FULLSCREEN_DIALOG 200, under both menus.
                            fly:SetFrameStrata(sm:GetFrameStrata())
                            fly:SetFrameLevel(sm:GetFrameLevel() + 30)
                            fly._refresh = refresh
                            flyouts[field] = fly
                        end
                        if not fly:IsShown() then
                            if fly._refresh then
                                fly._refresh()
                            end
                            fly:Show()
                        end
                    end
                    row:SetScript("OnEnter", ShowFlyout)
                    row:SetScript("OnClick", ShowFlyout)
                    row:SetScript("OnLeave", function()
                        highlight:SetAlpha(0)
                    end)
                end
                MakeSoundRow(1, "Audio on Buff Gain", "buffActiveSoundKey")
                MakeSoundRow(2, "Audio on Buff Loss", "buffLostSoundKey")

                local function OverAny()
                    if sm:IsMouseOver() then
                        return true
                    end
                    for _, fly in pairs(flyouts) do
                        if fly:IsShown() and fly:IsMouseOver() then
                            return true
                        end
                    end
                    return false
                end
                sm:SetScript("OnUpdate", function(m)
                    if
                        (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton"))
                        and not OverAny()
                    then
                        m:Hide()
                    end
                end)
                sm:HookScript("OnHide", function(m)
                    m:SetScript("OnUpdate", nil)
                    for _, fly in pairs(flyouts) do
                        fly:Hide()
                    end
                end)
                -- The bar menu underneath asks this before dismissing itself on a click.
                sm._overAny = OverAny
                ddBtn._tbbSndMenu = sm
                sm:Show()
            end

            -- Custom dropdown menu: bars organized by group with quick-add actions inside
            -- each, an independent section, and new-group/independent-bar creation at the bottom.
            local ddMenu
            local function BuildDDMenu()
                if ddMenu then
                    ddMenu:Hide()
                    ddMenu = nil
                end
                local t = mod.GetTrackedBuffBars()
                -- Screen-level overlay: hidden while it is dressed, tracked once its
                -- scripts are set. One menu frame for the session, dressed again on
                -- every open.
                local dropMenu = PoolKept(mod, "tbbBarMenu", "Frame", CludesUI.OverlayParent())
                dropMenu:Hide()
                dropMenu:SetFrameStrata("FULLSCREEN_DIALOG")
                dropMenu:SetFrameLevel(300)
                dropMenu:SetClampedToScreen(true)
                dropMenu:SetPoint("TOPLEFT", ddBtn, "BOTTOMLEFT", 0, -2)
                dropMenu:SetPoint("TOPRIGHT", ddBtn, "BOTTOMRIGHT", 0, -2)
                local backdrop = dropMenu:CreateTexture(nil, "BACKGROUND")
                backdrop:SetAllPoints()
                backdrop:SetColorTexture(mBgR, mBgG, mBgB, mBgHA)
                CludesUI.MakeRoundedBorder(dropMenu, 1, 1, 1, mBrdA, backdrop, nil, true)

                -- Rows build on an inner frame so tall menus can scroll.
                local inner = CreateFrame("Frame", nil, dropMenu)
                -- The options panel can run at a different effective scale than this
                -- screen-level menu; normalize button width into menu space so rows end exactly at the menu's edges.
                inner:SetWidth(ddBtn:GetWidth() * ddBtn:GetEffectiveScale() / dropMenu:GetEffectiveScale())
                inner:SetPoint("TOPLEFT")
                local MENU_MAX_H = 420
                local ar, ag, ab = CludesUI.GetAccentColor()

                local mH = 4

                -- Drag-and-drop: bar rows can be dragged onto another group's section (or
                -- independent) to move them; zones collect every row of a group so the whole
                -- section is a drop target. Inside the bar's own group the drop reorders
                -- instead, at the gap a green insertion line marks. Drag flag declared
                -- before any OnUpdate reads it.
                local dropZones = {} -- { gid, label, frames = {rows...}, rows = {{frame, idx}...}, head, tail }
                local dragState = { idx = nil, name = nil }
                dropMenu._dragActive = false

                local function HoveredZone()
                    for _, z in ipairs(dropZones) do
                        for _, f in ipairs(z.frames) do
                            if f and f:IsMouseOver() then
                                return z, f
                            end
                        end
                    end
                    return nil
                end

                -- Over a row of the dragged bar's own group: the bar's new place among
                -- the members and the gap to mark (header = before the first bar, add
                -- row = after the last, a bar row = the half the cursor is in). nil when
                -- the drop would leave the order as it is.
                local function ReorderTarget(z, f)
                    local rowList = z and z.rows
                    if not (rowList and f and dragState.idx) then
                        return nil
                    end
                    local from, gap
                    for k, r in ipairs(rowList) do
                        if r.idx == dragState.idx then
                            from = k
                        end
                        if r.frame == f then
                            local _, cy = GetCursorPosition()
                            local mid = (f:GetTop() + f:GetBottom()) / 2
                            gap = (cy / f:GetEffectiveScale() > mid) and k or k + 1
                        end
                    end
                    if f == z.head then
                        gap = 1
                    elseif f == z.tail then
                        gap = #rowList + 1
                    end
                    if not (from and gap) or gap == from or gap == from + 1 then
                        return nil
                    end
                    return (gap > from) and gap - 1 or gap, gap
                end

                local insLine = inner:CreateTexture(nil, "OVERLAY", nil, 7)
                insLine:SetHeight(2)
                local ACC = CludesUI.CLUDES_GREEN
                insLine:SetColorTexture(ACC.r, ACC.g, ACC.b, 0.9)
                insLine:Hide()
                local function ShowInsLine(rowList, gap)
                    local r = rowList[gap] or rowList[#rowList]
                    local edge = rowList[gap] and "TOP" or "BOTTOM"
                    insLine:ClearAllPoints()
                    insLine:SetPoint("LEFT", r.frame, edge .. "LEFT", 18, 0)
                    insLine:SetPoint("RIGHT", r.frame, edge .. "RIGHT", -8, 0)
                    insLine:Show()
                end

                local dragGhost
                local function GhostUpdate()
                    local cx, cy = GetCursorPosition()
                    local sc = UIParent:GetEffectiveScale()
                    dragGhost:ClearAllPoints()
                    dragGhost:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", cx / sc + 14, cy / sc - 22)
                    local z, f = HoveredZone()
                    local place, gap = ReorderTarget(z, f)
                    if place then
                        ShowInsLine(z.rows, gap)
                        dragGhost._lbl:SetText(dragState.name or "")
                        dragGhost._lbl:SetTextColor(ar, ag, ab, 1)
                        return
                    end
                    insLine:Hide()
                    if z and dragState.idx then
                        local t2 = mod.GetTrackedBuffBars()
                        local c2 = t2.bars and t2.bars[dragState.idx]
                        if c2 and mod.TBBBarGroupID(c2) ~= z.gid then
                            dragGhost._lbl:SetText(dragState.name .. "  >  " .. z.label)
                            dragGhost._lbl:SetTextColor(ar, ag, ab, 1)
                            return
                        end
                    end
                    dragGhost._lbl:SetText(dragState.name or "")
                    dragGhost._lbl:SetTextColor(1, 1, 1, 0.8)
                end
                local function EnsureGhost()
                    if dragGhost then
                        return dragGhost
                    end
                    -- One ghost frame for the session, dressed again by the first
                    -- drag of each menu open.
                    dragGhost = PoolKept(mod, "tbbDragGhost", "Frame", UIParent)
                    dragGhost:SetFrameStrata("TOOLTIP")
                    dragGhost:SetFrameLevel(500)
                    dragGhost:SetSize(10, 20)
                    local gl = dragGhost:CreateFontString(nil, "OVERLAY")
                    gl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                    gl:SetPoint("BOTTOMLEFT", dragGhost, "BOTTOMLEFT", 0, 0)
                    dragGhost._lbl = gl
                    dragGhost:Hide()
                    return dragGhost
                end
                local function StopDrag()
                    dropMenu._dragActive = false
                    dragState.idx = nil
                    insLine:Hide()
                    if dragGhost then
                        dragGhost:Hide()
                        dragGhost:SetScript("OnUpdate", nil)
                    end
                end
                dropMenu:HookScript("OnHide", StopDrag)

                local function BarIconID(b)
                    if b.popularKey and mod.TBB_POPULAR_BUFFS then
                        for _, pe in ipairs(mod.TBB_POPULAR_BUFFS) do
                            if pe.key == b.popularKey then
                                return pe.icon
                            end
                        end
                    end
                    if b.spellID and b.spellID > 0 then
                        local tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(b.spellID)
                        if tex then
                            return tex
                        end
                    end
                    return 134400
                end

                local function AddHeaderRow(textValue)
                    if mH > 4 then
                        mH = mH + 4
                    end
                    local hLbl = inner:CreateFontString(nil, "OVERLAY")
                    hLbl:SetFont(FONT_PATH, 10, GetCDMOptOutline())
                    hLbl:SetTextColor(1, 1, 1, 0.9)
                    hLbl:SetPoint("TOPLEFT", inner, "TOPLEFT", 10, -mH - 5)
                    hLbl:SetText(textValue)
                    mH = mH + 20
                end

                -- Group header: clickable, selects the GROUP as editing context (group
                -- settings replace per-bar sections). gkey (optional) = group's globalKey,
                -- adds the GLOBAL tag + a delete button that removes it for every spec (with confirmation).
                local function AddGroupHeaderRow(groupId, gkey)
                    if mH > 4 then
                        mH = mH + 4
                    end
                    local item = CreateFrame("Button", nil, inner)
                    item:SetHeight(22)
                    item:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
                    item:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
                    item:SetFrameLevel(dropMenu:GetFrameLevel() + 2)
                    local hLbl = item:CreateFontString(nil, "OVERLAY")
                    hLbl:SetFont(FONT_PATH, 10, GetCDMOptOutline())
                    hLbl:SetTextColor(1, 1, 1, 0.9)
                    hLbl:SetPoint("LEFT", item, "LEFT", 10, 0)
                    local groupDisplayName = (mod.TBBGroupName and mod.TBBGroupName(groupId))
                        or (CludesUI.L("GROUP") .. " " .. groupId)
                    hLbl:SetText(groupDisplayName)
                    if gkey then
                        local gTag = item:CreateFontString(nil, "OVERLAY")
                        gTag:SetFont(FONT_PATH, 9, GetCDMOptOutline())
                        gTag:SetTextColor(ar, ag, ab, 0.9)
                        gTag:SetPoint("LEFT", hLbl, "RIGHT", 6, 0)
                        gTag:SetText(CludesUI.L("GLOBAL"))
                    end
                    local eLbl = item:CreateFontString(nil, "OVERLAY")
                    eLbl:SetFont(FONT_PATH, 10, GetCDMOptOutline())
                    eLbl:SetTextColor(ar, ag, ab, 0.85)
                    eLbl:SetText(CludesUI.L("Edit Group"))
                    local delBtn
                    if gkey then
                        delBtn = CreateFrame("Button", nil, item)
                        delBtn:SetSize(ICON_SZ, ICON_SZ)
                        delBtn:SetPoint("RIGHT", item, "RIGHT", -8, 0)
                        delBtn:SetFrameLevel(item:GetFrameLevel() + 2)
                        local delIcon = delBtn:CreateTexture(nil, "OVERLAY")
                        delIcon:SetSize(ICON_SZ, ICON_SZ)
                        delIcon:SetPoint("CENTER")
                        if delIcon.SetSnapToPixelGrid then
                            delIcon:SetSnapToPixelGrid(false)
                            delIcon:SetTexelSnappingBias(0)
                        end
                        delIcon:SetTexture(MEDIA .. "icons\\cui-close.png")
                        delBtn:SetAlpha(0.6)
                        delBtn:SetScript("OnEnter", function()
                            delBtn:SetAlpha(1)
                            CludesUI.ShowWidgetTooltip(
                                delBtn,
                                CludesUI.L("Delete this global group for all specs")
                            )
                        end)
                        delBtn:SetScript("OnLeave", function()
                            delBtn:SetAlpha(0.6)
                            CludesUI.HideWidgetTooltip()
                        end)
                        delBtn:SetScript("OnClick", function()
                            dropMenu:Hide()
                            CludesUI:ShowConfirmPopup({
                                title = "Delete Global Group",
                                message = CludesUI.Lf(
                                    'Delete "%1$s" for ALL specs? Bars keep their current positions.',
                                    groupDisplayName
                                ),
                                confirmText = "Delete",
                                cancelText = "Cancel",
                                onConfirm = function()
                                    if mod.TBBDeleteGlobalGroup then
                                        mod.TBBDeleteGlobalGroup(gkey)
                                    end
                                    if _tbbSelectedGroup == groupId then
                                        _tbbSelectedGroup = nil
                                    end
                                    mod.BuildTrackedBuffBars()
                                    CludesUI:RefreshPage(true)
                                end,
                            })
                        end)
                        eLbl:SetPoint("RIGHT", delBtn, "LEFT", -8, 0)
                    else
                        eLbl:SetPoint("RIGHT", item, "RIGHT", -10, 0)
                    end
                    local highlight = item:CreateTexture(nil, "ARTWORK")
                    highlight:SetAllPoints()
                    highlight:SetColorTexture(1, 1, 1, 1)
                    local isSel = _tbbSelectedGroup == groupId
                    highlight:SetAlpha(isSel and selA or 0)
                    item:SetScript("OnEnter", function()
                        hLbl:SetTextColor(1, 1, 1, 1)
                        eLbl:SetTextColor(1, 1, 1, 0.9)
                        highlight:SetAlpha(hlA)
                    end)
                    item:SetScript("OnLeave", function()
                        hLbl:SetTextColor(1, 1, 1, 0.9)
                        eLbl:SetTextColor(ar, ag, ab, 0.85)
                        highlight:SetAlpha(isSel and selA or 0)
                    end)
                    item:SetScript("OnClick", function()
                        dropMenu:Hide()
                        _tbbSelectedGroup = groupId
                        CludesUI:RefreshPage(true)
                    end)
                    mH = mH + 22
                    return item
                end

                local function AddBarItem(idx, b, indent)
                    local item = CreateFrame("Button", nil, inner)
                    item:SetHeight(ITEM_H)
                    item:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
                    item:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
                    item:SetFrameLevel(dropMenu:GetFrameLevel() + 2)

                    local spIco = item:CreateTexture(nil, "OVERLAY")
                    spIco:SetSize(ITEM_H - 8, ITEM_H - 8)
                    spIco:SetPoint("LEFT", item, "LEFT", 10 + (indent or 0), 0)
                    spIco:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    local unassigned = (not b.spellID or b.spellID == 0) and not b.glowBased
                    spIco:SetTexture(BarIconID(b))
                    if unassigned then
                        spIco:SetDesaturated(true)
                        spIco:SetAlpha(0.35)
                    end

                    -- Icon = change this bar's buff (green border affordance)
                    local icoBtn = CreateFrame("Button", nil, item)
                    icoBtn:SetAllPoints(spIco)
                    icoBtn:SetFrameLevel(item:GetFrameLevel() + 3)
                    local egc = CludesUI.CLUDES_GREEN
                    local icoBrd = Pix.CreateBorder(icoBtn, egc.r, egc.g, egc.b, 1, 1, "OVERLAY", 7)
                    if icoBrd then
                        icoBrd:Hide()
                    end
                    icoBtn:SetScript("OnEnter", function()
                        if icoBrd then
                            icoBrd:Show()
                        end
                        CludesUI.ShowWidgetTooltip(icoBtn, CludesUI.L("Change buff"))
                    end)
                    icoBtn:SetScript("OnLeave", function()
                        if icoBrd then
                            icoBrd:Hide()
                        end
                        CludesUI.HideWidgetTooltip()
                    end)
                    icoBtn:SetScript("OnClick", function()
                        dropMenu:Hide()
                        OpenBuffPickerForBar(idx)
                    end)

                    local iLbl = item:CreateFontString(nil, "OVERLAY")
                    iLbl:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                    iLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                    iLbl:SetJustifyH("LEFT")
                    iLbl:SetWordWrap(false)
                    iLbl:SetMaxLines(1)
                    iLbl:SetPoint("LEFT", spIco, "RIGHT", 6, 0)
                    local displayName = (b.name and CludesUI.L(b.name)) or CludesUI.Lf("Bar %d", idx)
                    if not b.popularKey and b.spellID and b.spellID > 0 then
                        local details = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(b.spellID)
                        if details and details.name then
                            displayName = details.name
                        end
                    end
                    if unassigned then
                        displayName = displayName .. "  (" .. CludesUI.L("no buff assigned") .. ")"
                    end
                    iLbl:SetText(displayName)

                    local iHl = item:CreateTexture(nil, "ARTWORK")
                    iHl:SetAllPoints()
                    iHl:SetColorTexture(1, 1, 1, 1)
                    iHl:SetAlpha(idx == _tbbSelectedBar and selA or 0)

                    local delBtn = CreateFrame("Button", nil, item)
                    delBtn:SetSize(ICON_SZ, ICON_SZ)
                    delBtn:SetPoint("RIGHT", item, "RIGHT", -8, 0)
                    delBtn:SetFrameLevel(item:GetFrameLevel() + 2)
                    local delIcon = delBtn:CreateTexture(nil, "OVERLAY")
                    delIcon:SetSize(ICON_SZ, ICON_SZ)
                    delIcon:SetPoint("CENTER")
                    if delIcon.SetSnapToPixelGrid then
                        delIcon:SetSnapToPixelGrid(false)
                        delIcon:SetTexelSnappingBias(0)
                    end
                    delIcon:SetTexture(MEDIA .. "icons\\cui-close.png")
                    delBtn:SetAlpha(0.75)
                    iLbl:SetPoint("RIGHT", delBtn, "LEFT", -4, 0)

                    -- Only a bar that can cue gets the sound menu: on a row right-click and
                    -- on the speaker button, dimmed ("Add Audio Effect") while the bar has
                    -- no Audio on Buff Gain/Loss sound and full ("Edit Audio Effect") once
                    -- it has one. The sound menu repaints it through item._sndPaint.
                    local soundable = BarTakesSound(b)
                    if soundable then
                        local sndBtn = CreateFrame("Button", nil, item)
                        sndBtn:SetSize(ICON_SZ, ICON_SZ)
                        sndBtn:SetPoint("RIGHT", delBtn, "LEFT", -6, 0)
                        sndBtn:SetFrameLevel(item:GetFrameLevel() + 2)
                        local sndIcon = sndBtn:CreateTexture(nil, "OVERLAY")
                        sndIcon:SetAllPoints()
                        sndIcon:SetAtlas(CludesUI.SOUND_ICON_ATLAS)
                        local function HasSound()
                            local g, l = b.buffActiveSoundKey, b.buffLostSoundKey
                            return (g and g ~= "none") or (l and l ~= "none")
                        end
                        local function RestAlpha()
                            return HasSound() and 0.8 or 0.3
                        end
                        item._sndPaint = function()
                            if not sndBtn:IsMouseOver() then
                                sndBtn:SetAlpha(RestAlpha())
                            end
                        end
                        sndBtn:SetAlpha(RestAlpha())
                        sndBtn:SetScript("OnEnter", function(self)
                            self:SetAlpha(1)
                            iLbl:SetTextColor(1, 1, 1, 1)
                            iHl:SetAlpha(hlA)
                            CludesUI.ShowWidgetTooltip(
                                self,
                                HasSound() and CludesUI.L("Edit Audio Effect")
                                    or CludesUI.L("Add Audio Effect")
                            )
                        end)
                        sndBtn:SetScript("OnLeave", function(self)
                            CludesUI.HideWidgetTooltip()
                            self:SetAlpha(RestAlpha())
                            if item:IsMouseOver() then
                                return
                            end
                            iLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                            iHl:SetAlpha(idx == _tbbSelectedBar and selA or 0)
                        end)
                        -- The bar menu stays open underneath, as with the row right-click.
                        sndBtn:SetScript("OnClick", function()
                            OpenBarSoundMenu(idx, item)
                        end)
                        iLbl:SetPoint("RIGHT", sndBtn, "LEFT", -4, 0)
                    end

                    delBtn:SetScript("OnEnter", function()
                        delBtn:SetAlpha(1)
                        iLbl:SetTextColor(1, 1, 1, 1)
                        iHl:SetAlpha(hlA)
                    end)
                    delBtn:SetScript("OnLeave", function()
                        if item:IsMouseOver() then
                            return
                        end
                        delBtn:SetAlpha(0.75)
                        iLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                        iHl:SetAlpha(idx == _tbbSelectedBar and selA or 0)
                    end)
                    delBtn:SetScript("OnClick", function()
                        dropMenu:Hide()
                        CludesUI:ShowConfirmPopup({
                            title = "Delete Bar",
                            message = CludesUI.Lf('Delete "%1$s"?', displayName),
                            confirmText = "Delete",
                            cancelText = "Cancel",
                            onConfirm = function()
                                mod.RemoveTrackedBuffBar(idx)
                                CludesUI:RefreshPage(true)
                            end,
                        })
                    end)

                    item:SetScript("OnEnter", function()
                        iLbl:SetTextColor(1, 1, 1, 1)
                        iHl:SetAlpha(hlA)
                        delBtn:SetAlpha(1)
                    end)
                    item:SetScript("OnLeave", function()
                        iLbl:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                        iHl:SetAlpha(idx == _tbbSelectedBar and selA or 0)
                        delBtn:SetAlpha(0.75)
                    end)
                    item:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                    item:SetScript("OnClick", function(_, mouseButton)
                        if mouseButton == "RightButton" then
                            if not soundable then
                                return
                            end
                            -- The bar menu stays open underneath, like the CDM icon menu.
                            OpenBarSoundMenu(idx, item)
                            return
                        end
                        dropMenu:Hide()
                        if unassigned then
                            -- No buff yet: go straight to the buff picker.
                            OpenBuffPickerForBar(idx)
                        else
                            _tbbSelectedBar = idx
                            _tbbSelectedGroup = nil
                            CludesUI:RefreshPage(true)
                        end
                    end)

                    -- Drag to move between groups or reorder within one (drop handled by zone under the cursor at release).
                    item:RegisterForDrag("LeftButton")
                    item:SetScript("OnDragStart", function()
                        dropMenu._dragActive = true
                        dragState.idx = idx
                        dragState.name = displayName
                        local g = EnsureGhost()
                        g._lbl:SetText(displayName)
                        g._lbl:SetTextColor(1, 1, 1, 0.8)
                        g:Show()
                        g:SetScript("OnUpdate", GhostUpdate)
                    end)
                    item:SetScript("OnDragStop", function()
                        local moveIdx = dragState.idx
                        local z, f = HoveredZone()
                        local place = ReorderTarget(z, f)
                        StopDrag()
                        if moveIdx and place then
                            dropMenu:Hide()
                            ReorderBarInGroup(moveIdx, place)
                        elseif moveIdx and z then
                            MoveBarToGroup(moveIdx, z.gid)
                        end
                    end)
                    mH = mH + ITEM_H
                    return item
                end

                local function AddActionItem(textValue, indent, onClick)
                    local item = CreateFrame("Button", nil, inner)
                    item:SetHeight(ITEM_H)
                    item:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
                    item:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
                    item:SetFrameLevel(dropMenu:GetFrameLevel() + 2)
                    local labelFS = item:CreateFontString(nil, "OVERLAY")
                    labelFS:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                    labelFS:SetPoint("LEFT", item, "LEFT", 10 + (indent or 0), 0)
                    labelFS:SetJustifyH("LEFT")
                    labelFS:SetText(textValue)
                    labelFS:SetTextColor(ar, ag, ab, 0.85)
                    local highlight = item:CreateTexture(nil, "ARTWORK")
                    highlight:SetAllPoints()
                    highlight:SetColorTexture(1, 1, 1, 1)
                    highlight:SetAlpha(0)
                    item:SetScript("OnEnter", function()
                        labelFS:SetTextColor(1, 1, 1, 1)
                        highlight:SetAlpha(hlA)
                    end)
                    item:SetScript("OnLeave", function()
                        labelFS:SetTextColor(ar, ag, ab, 0.85)
                        highlight:SetAlpha(0)
                    end)
                    item:SetScript("OnClick", onClick)
                    mH = mH + ITEM_H
                    return item
                end

                -- A freshly created bar has no buff yet: select it and open the buff picker right away so add-and-assign is one flow.
                local function SelectNewBar(newIdx)
                    dropMenu:Hide()
                    OpenBuffPickerForBar(newIdx)
                end

                -- Grouped bars, one section per group (each section doubles as a drop zone for bar drags).
                local gids = mod.TBBGroupIDsInUse and mod.TBBGroupIDsInUse() or {}
                local renderedGlobal = {}
                for _, groupId in ipairs(gids) do
                    local gkey = mod.TBBGroupGlobalKey and mod.TBBGroupGlobalKey(groupId) or nil
                    if gkey then
                        renderedGlobal[gkey] = true
                    end
                    local zone = {
                        gid = groupId,
                        label = (mod.TBBGroupName and mod.TBBGroupName(groupId))
                            or (CludesUI.L("Group") .. " " .. groupId),
                        frames = {},
                        rows = {},
                    }
                    dropZones[#dropZones + 1] = zone
                    zone.head = AddGroupHeaderRow(groupId, gkey)
                    zone.frames[#zone.frames + 1] = zone.head
                    for idx, b in ipairs(t.bars) do
                        if mod.TBBBarGroupID(b) == groupId then
                            local row = AddBarItem(idx, b, 8)
                            zone.frames[#zone.frames + 1] = row
                            zone.rows[#zone.rows + 1] = { frame = row, idx = idx }
                        end
                    end
                    zone.tail = AddActionItem(CludesUI.L("+ Add Bar to Group"), 8, function()
                        SelectNewBar(mod.AddTrackedBuffBar(groupId))
                    end)
                    zone.frames[#zone.frames + 1] = zone.tail
                end

                -- Global groups with no bars on this spec are always listed so any spec can
                -- assign/drag bars into them; selecting one edits its shared settings (a normal drop zone).
                if mod.TBBGlobalGroupKeys then
                    for _, gkey in ipairs(mod.TBBGlobalGroupKeys()) do
                        if not renderedGlobal[gkey] then
                            local lgid = mod.TBBEnsureLocalGroupForGlobal(gkey)
                            if lgid then
                                local zone = {
                                    gid = lgid,
                                    label = (mod.TBBGroupName and mod.TBBGroupName(lgid))
                                        or (CludesUI.L("Group") .. " " .. lgid),
                                    frames = {},
                                }
                                dropZones[#dropZones + 1] = zone
                                zone.frames[#zone.frames + 1] = AddGroupHeaderRow(lgid, gkey)
                                zone.frames[#zone.frames + 1] = AddActionItem(
                                    CludesUI.L("+ Add Bar to Group"),
                                    8,
                                    function()
                                        SelectNewBar(mod.AddTrackedBuffBar(lgid))
                                    end
                                )
                            end
                        end
                    end
                end

                -- Independent bars (the section is the "make independent" zone)
                local indepZone = { gid = 0, label = CludesUI.L("Independent"), frames = {} }
                dropZones[#dropZones + 1] = indepZone
                local anyIndependent = false
                for _, b in ipairs(t.bars) do
                    if mod.TBBBarGroupID(b) == 0 then
                        anyIndependent = true
                        break
                    end
                end
                if anyIndependent then
                    AddHeaderRow(CludesUI.L("INDEPENDENT BARS"))
                    for idx, b in ipairs(t.bars) do
                        if mod.TBBBarGroupID(b) == 0 then
                            indepZone.frames[#indepZone.frames + 1] = AddBarItem(idx, b, 8)
                        end
                    end
                end

                -- Divider + creation actions
                local div = inner:CreateTexture(nil, "ARTWORK")
                div:SetHeight(1)
                div:SetColorTexture(1, 1, 1, 0.10)
                div:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH - 4)
                div:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH - 4)
                mH = mH + 9

                AddActionItem(CludesUI.L("+ Add New Group"), 0, function()
                    local groupId = mod.TBBNextGroupID()
                    if mod.TBBResetGroupSettings then
                        mod.TBBResetGroupSettings(groupId)
                    end
                    SelectNewBar(mod.AddTrackedBuffBar(groupId))
                end)
                indepZone.frames[#indepZone.frames + 1] = AddActionItem(
                    CludesUI.L("+ Add Independent Bar"),
                    0,
                    function()
                        SelectNewBar(mod.AddTrackedBuffBar(0))
                    end
                )

                if #t.bars > 1 then
                    local dragHint = inner:CreateFontString(nil, "OVERLAY")
                    dragHint:SetFont(FONT_PATH, 10, GetCDMOptOutline())
                    dragHint:SetTextColor(1, 1, 1, 0.35)
                    dragHint:SetPoint("TOP", inner, "TOP", 0, -mH - 4)
                    dragHint:SetText(CludesUI.L("Drag a bar to reorder it or move it into another group"))
                    mH = mH + 20
                end
                -- Discoverability for the row right-click (Audio on Buff Gain/Loss): shown
                -- while any bar can take a sound.
                local anySoundable = false
                for _, b in ipairs(t.bars) do
                    if BarTakesSound(b) then
                        anySoundable = true
                        break
                    end
                end
                if anySoundable then
                    local soundHint = inner:CreateFontString(nil, "OVERLAY")
                    soundHint:SetFont(FONT_PATH, 10, GetCDMOptOutline())
                    soundHint:SetTextColor(1, 1, 1, 0.35)
                    soundHint:SetPoint("TOP", inner, "TOP", 0, -mH - 4)
                    soundHint:SetText(CludesUI.L("Right-click a bar to set its sounds"))
                    mH = mH + 20
                end

                local totalH = mH + 4
                inner:SetHeight(totalH)
                if totalH > MENU_MAX_H then
                    dropMenu:SetHeight(MENU_MAX_H)
                    local scrollFrame = CreateFrame("ScrollFrame", nil, dropMenu)
                    scrollFrame:SetPoint("TOPLEFT", 0, -1)
                    scrollFrame:SetPoint("BOTTOMRIGHT", 0, 1)
                    scrollFrame:SetFrameLevel(dropMenu:GetFrameLevel() + 1)
                    scrollFrame:EnableMouseWheel(true)
                    scrollFrame:SetScrollChild(inner)
                    local scrollPos = 0
                    local maxScroll = totalH - MENU_MAX_H
                    scrollFrame:SetScript("OnMouseWheel", function(_, delta)
                        scrollPos = math.max(0, math.min(maxScroll, scrollPos - delta * 30))
                        scrollFrame:SetVerticalScroll(scrollPos)
                    end)
                else
                    dropMenu:SetHeight(totalH)
                end
                dropMenu:SetScript("OnUpdate", function(m)
                    -- Never dismiss mid-drag: dragging naturally leaves the menu bounds with the button held down.
                    if m._dragActive then
                        return
                    end
                    -- A click in the row's sound menu or its flyouts is not a click outside.
                    local snd = ddBtn._tbbSndMenu
                    if snd and snd:IsShown() and snd._overAny and snd._overAny() then
                        return
                    end
                    if
                        not m:IsMouseOver()
                        and not ddBtn:IsMouseOver()
                        and IsMouseButtonDown("LeftButton")
                    then
                        m:Hide()
                    end
                end)
                dropMenu:HookScript("OnHide", function(m)
                    m:SetScript("OnUpdate", nil)
                    if ddBtn._tbbSndMenu then
                        ddBtn._tbbSndMenu:Hide()
                    end
                end)
                -- A no-op unless the menu sits on the controller-cursor overlay layer.
                CludesUI.TrackOverlay(dropMenu)
                dropMenu:Show()
                ddMenu = dropMenu
            end

            ddBtn:SetScript("OnEnter", function()
                ddLbl:SetAlpha(mTxtHA)
                ddBrd:SetColor(1, 1, 1, mBrdHA)
                ddBg:SetColorTexture(mBgR, mBgG, mBgB, mBgHA)
            end)
            ddBtn:SetScript("OnLeave", function()
                if ddMenu and ddMenu:IsShown() then
                    return
                end
                ddLbl:SetAlpha(mTxtA)
                ddBrd:SetColor(1, 1, 1, mBrdA)
                ddBg:SetColorTexture(mBgR, mBgG, mBgB, mBgA)
            end)
            ddBtn:SetScript("OnClick", function()
                -- An open buff picker (e.g. from "+ Add Bar to Group") yields to the management menu.
                if _tbbSpellPickerMenu and _tbbSpellPickerMenu:IsShown() then
                    _tbbSpellPickerMenu:Hide()
                end
                if ddMenu and ddMenu:IsShown() then
                    ddMenu:Hide()
                else
                    BuildDDMenu()
                end
            end)
            ddBtn:HookScript("OnHide", function()
                if ddMenu then
                    ddMenu:Hide()
                end
                if ddBtn._tbbSndMenu then
                    ddBtn._tbbSndMenu:Hide()
                end
            end)

            -- Keep the label current when settings refresh in place (e.g. a group rename commits without a full page rebuild).
            CludesUI.RegisterWidgetRefresh(UpdateDDLabel)

            _tbbDDBtn = ddBtn
            return ddBtn
        end

        -- No content header: preview lives in the popout panel docked to the left of the
        -- options window (RefreshTBBPopout); wire its click-to-scroll overlays to this build's rows.
        CludesUI:ClearContentHeader()
        _tbbNavigateFn = NavigateToSetting

        -------------------------------------------------------------------
        --  ACTION CARDS + PRESET STYLE (top of scrollable settings; shown in both bar and group mode)
        -------------------------------------------------------------------
        do
            -- The third card broadcasts the selected bar to every other spec, then flips to
            -- "Remove Bar from All Specs" (the inverse); dimmed unless a preset/custom-buff bar is selected.
            local _selForBroadcast = (not _tbbSelectedGroup) and SelectedTBB() or nil
            local _canBroadcast = mod.IsTrackedBuffBarBroadcastable
                    and mod.IsTrackedBuffBarBroadcastable(_selForBroadcast)
                or false
            -- WoW Forever: the class runs on one spec, so there is nowhere to copy to.
            if CludesUI.IS_FOREVER then
                _canBroadcast = false
            end
            local _isBroadcast = _canBroadcast
                    and mod.IsTrackedBuffBarBroadcast
                    and mod.IsTrackedBuffBarBroadcast(_selForBroadcast)
                or false
            local _broadcastLabel = _isBroadcast and "Remove Bar from All Specs" or "Add Bar to All Specs"
            local EGc = CludesUI.CLUDES_GREEN
            local PADc = CludesUI.CONTENT_PAD or 10
            local CARD_H, CARD_GAP, CARD_ICON = 60, 12, 24
            local cardTotalW = hostFrame:GetWidth() - PADc * 2
            local CARD_W = math.floor((cardTotalW - CARD_GAP * 2) / 3)
            posY = posY - 10
            local cardRow = CreateFrame("Frame", nil, hostFrame)
            Pix.Size(cardRow, cardTotalW, CARD_H)
            Pix.Point(cardRow, "TOPLEFT", hostFrame, "TOPLEFT", PADc, posY)

            local function MakeActionCard(xOff, iconPath, cardTitle, cardDesc, onClick, disabledTip)
                local cardFrame = CreateFrame("Button", nil, cardRow)
                Pix.Size(cardFrame, CARD_W, CARD_H)
                Pix.Point(cardFrame, "TOPLEFT", cardRow, "TOPLEFT", xOff, 0)
                cardFrame:SetFrameLevel(cardRow:GetFrameLevel() + 2)

                local cbrd = CludesUI.MakeRoundedCard(cardFrame, 0.12, 0.50, 2)
                local cbg, accentLine = cbrd.bg, cbrd.accent

                -- Accent top edge
                accentLine:SetColorTexture(EGc.r, EGc.g, EGc.b, 0.6)

                local cIcon = cardFrame:CreateTexture(nil, "ARTWORK")
                cIcon:SetSize(CARD_ICON, CARD_ICON)
                Pix.Point(cIcon, "LEFT", cardFrame, "LEFT", 18, 0)
                cIcon:SetTexture(iconPath)
                cIcon:SetVertexColor(EGc.r, EGc.g, EGc.b)
                cIcon:SetAlpha(0.6)
                if cIcon.SetSnapToPixelGrid then
                    cIcon:SetSnapToPixelGrid(false)
                    cIcon:SetTexelSnappingBias(0)
                end

                local titleFs = CludesUI.MakeFont(cardFrame, 12, nil, 1, 1, 1, 0.9)
                Pix.Point(titleFs, "TOPLEFT", cIcon, "TOPRIGHT", 14, 1)
                Pix.Point(titleFs, "RIGHT", cardFrame, "RIGHT", -10, 0)
                titleFs:SetJustifyH("LEFT")
                titleFs:SetWordWrap(false)
                titleFs:SetText(CludesUI.L(cardTitle))

                local descFs = CludesUI.MakeFont(cardFrame, 10, nil, 1, 1, 1, 0.35)
                Pix.Point(descFs, "TOPLEFT", titleFs, "BOTTOMLEFT", 0, -4)
                Pix.Point(descFs, "RIGHT", cardFrame, "RIGHT", -10, 0)
                descFs:SetJustifyH("LEFT")
                descFs:SetWordWrap(false)
                descFs:SetText(CludesUI.L(cardDesc))

                if disabledTip then
                    cardFrame:SetAlpha(0.45)
                    cardFrame:SetScript("OnEnter", function()
                        CludesUI.ShowWidgetTooltip(cardFrame, disabledTip)
                    end)
                    cardFrame:SetScript("OnLeave", function()
                        CludesUI.HideWidgetTooltip()
                    end)
                else
                    cardFrame:SetScript("OnEnter", function()
                        cbg:SetColorTexture(0.100, 0.110, 0.124, 0.50)
                        cbrd:SetColor(1, 1, 1, 0.22)
                        titleFs:SetAlpha(1)
                        cIcon:SetAlpha(0.85)
                    end)
                    cardFrame:SetScript("OnLeave", function()
                        cbg:SetColorTexture(0.062, 0.070, 0.082, 0.50)
                        cbrd:SetColor(1, 1, 1, 0.12)
                        titleFs:SetAlpha(0.9)
                        cIcon:SetAlpha(0.6)
                    end)
                    cardFrame:SetScript("OnClick", onClick)
                end
                return cardFrame
            end

            local MEDIA_ICONS = "Interface\\AddOns\\CludesUI\\media\\icons\\"
            MakeActionCard(
                0,
                MEDIA_ICONS .. "power.png",
                "Use Blizzard CDM Bars",
                "Switch back to Blizzard's bars.",
                function()
                    CludesUI:ShowConfirmPopup({
                        title = "Use Blizzard Bars",
                        message = "This will disable CludesUI Tracking Bars and show Blizzard's default Tracked Bars display instead.",
                        confirmText = "Switch & Reload",
                        cancelText = "Cancel",
                        reload = true,
                        onConfirm = function()
                            local p = DB()
                            if p and p.cdmBars then
                                p.cdmBars.useBlizzardBuffBars = true
                            end
                        end,
                    })
                end
            )
            MakeActionCard(
                CARD_W + CARD_GAP,
                MEDIA_ICONS .. "cui-open.png",
                "Open Blizzard CDM",
                "Manage your tracked bars.",
                function()
                    if mod.OpenBlizzardCDMTab then
                        mod.OpenBlizzardCDMTab(true)
                    end
                end
            )
            MakeActionCard(
                (CARD_W + CARD_GAP) * 2,
                MEDIA_ICONS .. "sync.png",
                _broadcastLabel,
                "Copy this bar to every spec.",
                function()
                    local sel = SelectedTBB()
                    if _tbbSelectedGroup or not mod.IsTrackedBuffBarBroadcastable(sel) then
                        return
                    end
                    local nm = sel.name or "Bar"
                    if (not sel.popularKey or sel.popularKey == "") and sel.spellID and sel.spellID > 0 then
                        local details = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(sel.spellID)
                        if details and details.name then
                            nm = details.name
                        end
                    end
                    if mod.IsTrackedBuffBarBroadcast and mod.IsTrackedBuffBarBroadcast(sel) then
                        CludesUI:ShowConfirmPopup({
                            title = "Remove Bar from All Specs",
                            message = CludesUI.Lf(
                                'Remove "%1$s" from every other spec? The bar in this spec is kept.',
                                nm
                            ),
                            confirmText = "Remove from All",
                            cancelText = "Cancel",
                            onConfirm = function()
                                if mod.RemoveBarFromAllSpecs then
                                    mod.RemoveBarFromAllSpecs(_tbbSelectedBar)
                                end
                                CludesUI:RefreshPage(true)
                            end,
                        })
                    else
                        CludesUI:ShowConfirmPopup({
                            title = "Add Bar to All Specs",
                            message = CludesUI.Lf(
                                'Add "%1$s" to every spec? It will be copied to each of your specs that doesn\'t already have it.',
                                nm
                            ),
                            confirmText = "Add to All Specs",
                            cancelText = "Cancel",
                            onConfirm = function()
                                if mod.AddBarToAllSpecs then
                                    mod.AddBarToAllSpecs(_tbbSelectedBar)
                                end
                                CludesUI:RefreshPage(true)
                            end,
                        })
                    end
                end,
                not _canBroadcast
                        and ((CludesUI.IS_FOREVER and "WoW Forever has no other specs to copy this bar to") or (_tbbSelectedGroup and "Select a bar to broadcast it to other specs" or "Only preset or custom buff bars can be added to all specs"))
                    or nil
            )
            posY = posY - CARD_H - 12

            -- Preset Style panel (styled like Profiles & Presets "Active Profile"): pick a
            -- saved style preset and apply it to the selected bar/group, or save the current
            -- style as one. Presets are profile-wide; new bars resolve one by association at creation.
            local _wc = CludesUI.WB_COLOURS
            local PROF_BTN_COLOURS = {
                _wc[1],
                _wc[2],
                _wc[3],
                _wc[4],
                _wc[5],
                _wc[6],
                _wc[7],
                _wc[8],
                1,
                1,
                1,
                CludesUI.DD_BRD_A,
                1,
                1,
                1,
                CludesUI.DD_BRD_HA or 0.30,
                _wc[17],
                _wc[18],
                _wc[19],
                _wc[20],
                _wc[21],
                _wc[22],
                _wc[23],
                _wc[24],
            }
            local LABEL_H = 16
            local CTRL_H = 30
            local PAD_X = 24
            local PAD_Y = 20
            local GAP_DD = 30
            local GAP_BTN = 14
            local PR_ROW_H = PAD_Y + LABEL_H + 4 + CTRL_H + PAD_Y

            local innerW = cardTotalW - PAD_X * 2
            local DD_W = math.floor(innerW * 0.30)
            local BTN_W = math.floor((innerW - DD_W - GAP_DD - GAP_BTN * 2) / 3)

            local prRow = CreateFrame("Frame", nil, hostFrame)
            Pix.Size(prRow, cardTotalW, PR_ROW_H)
            Pix.Point(prRow, "TOPLEFT", hostFrame, "TOPLEFT", PADc, posY)

            local prBg = CludesUI.MakeRoundedCard(prRow, 0.10, 0.50).bg

            -- "Preset Style" label (accent, matching "Active Profile")
            local prLbl = CludesUI.MakeFont(prRow, 12, nil, EGc.r, EGc.g, EGc.b, 0.7)
            Pix.Point(prLbl, "TOPLEFT", prRow, "TOPLEFT", PAD_X, -PAD_Y)
            prLbl:SetText(CludesUI.L("Preset Style"))
            prLbl:SetJustifyH("LEFT")

            -- Live reads: label/menu/apply buttons all pull from the current preset list so saves/renames/deletes never go stale.
            local function SelectedPresetName()
                local p = DB()
                local sel = p and p.tbbSelectedStylePreset
                if sel and mod.FindTBBStylePreset and mod.FindTBBStylePreset(sel) then
                    return sel
                end
                local presets = mod.GetTBBStylePresets and mod.GetTBBStylePresets()
                return presets and presets[1] and presets[1].name or nil
            end
            local function SelectedPreset()
                local nm = SelectedPresetName()
                if not nm then
                    return nil
                end
                return mod.FindTBBStylePreset and mod.FindTBBStylePreset(nm)
            end

            -- Preset dropdown: bespoke button + menu (same look as the standard control) so
            -- each row carries inline rename/delete buttons, matching the "Active Profile" dropdown.
            local aS = CludesUI.RD_DD_COLOURS
            local prDD = CreateFrame("Button", nil, prRow)
            Pix.Size(prDD, DD_W, CTRL_H)
            prDD:SetFrameLevel(prRow:GetFrameLevel() + 2)
            local prDDBg = prDD:CreateTexture(nil, "BACKGROUND")
            prDDBg:SetAllPoints()
            prDDBg:SetColorTexture(CludesUI.DD_BG_R, CludesUI.DD_BG_G, CludesUI.DD_BG_B, CludesUI.DD_BG_A)
            local prDDBrd = CludesUI.MakeRoundedBorder(prDD, 1, 1, 1, CludesUI.DD_BRD_A, prDDBg)
            -- Resting alpha on the text colour, the channel PrApplyNormal /
            -- PrApplyHover write, so a hover and leave land back on it.
            local prDDLbl = CludesUI.MakeFont(prDD, 13, nil, 1, 1, 1, CludesUI.DD_TXT_A)
            prDDLbl:SetJustifyH("LEFT")
            prDDLbl:SetWordWrap(false)
            prDDLbl:SetMaxLines(1)
            prDDLbl:SetPoint("LEFT", prDD, "LEFT", 12, 0)
            local prArrow = CludesUI.MakeDropdownArrow(prDD, 12, Pix)
            prDDLbl:SetPoint("RIGHT", prArrow, "LEFT", -5, 0)
            Pix.Point(prDD, "TOPLEFT", prLbl, "BOTTOMLEFT", 0, -6)
            local function UpdatePrDDLabel()
                prDDLbl:SetText(SelectedPresetName() or CludesUI.L("No Saved Presets"))
            end
            UpdatePrDDLabel()

            -- One preset menu frame for the session, dressed again by every
            -- page build (its rows are pooled under it).
            local prMenu = PoolKept(mod, "tbbPresetMenu", "Frame", UIParent)
            prMenu:SetFrameStrata("FULLSCREEN_DIALOG")
            prMenu:SetFrameLevel(200)
            prMenu:SetClampedToScreen(true)
            prMenu:SetSize(DD_W, 4)
            prMenu:SetPoint("TOPLEFT", prDD, "BOTTOMLEFT", 0, -2)
            prMenu:Hide()
            local prMenuBg = prMenu:CreateTexture(nil, "BACKGROUND")
            prMenuBg:SetAllPoints()
            prMenuBg:SetColorTexture(CludesUI.DD_BG_R, CludesUI.DD_BG_G, CludesUI.DD_BG_B, 0.98)
            CludesUI.MakeRoundedBorder(prMenu, 1, 1, 1, CludesUI.DD_BRD_A, prMenuBg, nil, true)
            prMenu:SetScript("OnShow", function(self)
                local sc = prDD:GetEffectiveScale() / UIParent:GetEffectiveScale()
                self:SetScale(sc)
                self:SetScript("OnUpdate", function(m)
                    if not prDD:IsMouseOver() and not m:IsMouseOver() then
                        if IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton") then
                            m:Hide()
                        end
                    end
                end)
            end)

            local X_SZ = 14
            local MEDIA_PR = "Interface\\AddOns\\CludesUI\\media\\icons\\"
            local prItems = {}

            local function RebuildPresetMenu()
                for _, itm in ipairs(prItems) do
                    itm:Hide()
                end
                local presets = (mod.GetTBBStylePresets and mod.GetTBBStylePresets()) or {}
                local selName = SelectedPresetName()
                local mH = 4
                for i = 1, math.max(#presets, 1) do
                    local itm = prItems[i]
                    if not itm then
                        itm = CreateFrame("Button", nil, prMenu)
                        itm:SetHeight(26)
                        itm:SetFrameLevel(prMenu:GetFrameLevel() + 1)

                        local labelFS = itm:CreateFontString(nil, "OVERLAY")
                        labelFS:SetFont(FONT_PATH, 13, GetCDMOptOutline())
                        labelFS:SetPoint("LEFT", itm, "LEFT", 10, 0)
                        labelFS:SetPoint("RIGHT", itm, "RIGHT", -(X_SZ * 2 + 26), 0)
                        labelFS:SetJustifyH("LEFT")
                        labelFS:SetWordWrap(false)
                        labelFS:SetMaxLines(1)
                        labelFS:SetTextColor(1, 1, 1, CludesUI.TEXT_DIM_A)
                        itm._lbl = labelFS

                        local highlight = itm:CreateTexture(nil, "ARTWORK")
                        highlight:SetAllPoints()
                        highlight:SetColorTexture(1, 1, 1, 1)
                        highlight:SetAlpha(0)
                        itm._hl = highlight

                        local xBtn = CreateFrame("Button", nil, itm)
                        xBtn:SetSize(X_SZ, X_SZ)
                        xBtn:SetPoint("RIGHT", itm, "RIGHT", -8, 0)
                        xBtn:SetFrameLevel(itm:GetFrameLevel() + 2)
                        local xIcon = xBtn:CreateTexture(nil, "OVERLAY")
                        xIcon:SetAllPoints()
                        if xIcon.SetSnapToPixelGrid then
                            xIcon:SetSnapToPixelGrid(false)
                            xIcon:SetTexelSnappingBias(0)
                        end
                        xIcon:SetTexture(MEDIA_PR .. "cui-close.png")
                        xBtn:SetAlpha(0.4)
                        itm._xBtn = xBtn

                        local editBtn = CreateFrame("Button", nil, itm)
                        editBtn:SetSize(X_SZ, X_SZ)
                        editBtn:SetPoint("RIGHT", xBtn, "LEFT", -4, 0)
                        editBtn:SetFrameLevel(itm:GetFrameLevel() + 2)
                        local editIcon = editBtn:CreateTexture(nil, "OVERLAY")
                        editIcon:SetAllPoints()
                        if editIcon.SetSnapToPixelGrid then
                            editIcon:SetSnapToPixelGrid(false)
                            editIcon:SetTexelSnappingBias(0)
                        end
                        editIcon:SetTexture(MEDIA_PR .. "cui-edit.png")
                        editBtn:SetAlpha(0.4)
                        itm._editBtn = editBtn

                        local function IsOverInlineBtn()
                            return xBtn:IsMouseOver() or editBtn:IsMouseOver()
                        end
                        local function SetAllInlineAlpha(a)
                            xBtn:SetAlpha(a)
                            editBtn:SetAlpha(a)
                        end

                        itm:SetScript("OnEnter", function()
                            if itm._isEmpty then
                                return
                            end
                            labelFS:SetTextColor(1, 1, 1, 1)
                            highlight:SetAlpha(CludesUI.DD_ITEM_HL_A)
                            SetAllInlineAlpha(0.8)
                        end)
                        itm:SetScript("OnLeave", function()
                            if itm._isEmpty then
                                return
                            end
                            if IsOverInlineBtn() then
                                return
                            end
                            labelFS:SetTextColor(1, 1, 1, CludesUI.TEXT_DIM_A)
                            highlight:SetAlpha(itm._isSel and CludesUI.DD_ITEM_SEL_A or 0)
                            SetAllInlineAlpha(0.4)
                        end)

                        local function InlineBtnEnter(self)
                            labelFS:SetTextColor(1, 1, 1, 1)
                            highlight:SetAlpha(CludesUI.DD_ITEM_HL_A)
                            SetAllInlineAlpha(0.8)
                            self:SetAlpha(1)
                        end
                        local function InlineBtnLeave(hoveredSelf)
                            if itm:IsMouseOver() or IsOverInlineBtn() then
                                hoveredSelf:SetAlpha(0.8)
                                return
                            end
                            labelFS:SetTextColor(1, 1, 1, CludesUI.TEXT_DIM_A)
                            highlight:SetAlpha(itm._isSel and CludesUI.DD_ITEM_SEL_A or 0)
                            SetAllInlineAlpha(0.4)
                        end

                        xBtn:SetScript("OnEnter", function(self)
                            InlineBtnEnter(self)
                            CludesUI.ShowWidgetTooltip(self, CludesUI.L("Delete"))
                        end)
                        xBtn:SetScript("OnLeave", function(self)
                            InlineBtnLeave(self)
                            CludesUI.HideWidgetTooltip()
                        end)
                        editBtn:SetScript("OnEnter", function(self)
                            InlineBtnEnter(self)
                            CludesUI.ShowWidgetTooltip(self, CludesUI.L("Rename"))
                        end)
                        editBtn:SetScript("OnLeave", function(self)
                            InlineBtnLeave(self)
                            CludesUI.HideWidgetTooltip()
                        end)
                        prItems[i] = itm
                    end

                    itm:SetPoint("TOPLEFT", prMenu, "TOPLEFT", 1, -mH)
                    itm:SetPoint("TOPRIGHT", prMenu, "TOPRIGHT", -1, -mH)

                    local pr = presets[i]
                    if not pr then
                        -- Empty state: a single dim, non-interactive row
                        itm._isEmpty = true
                        itm._isSel = false
                        itm._lbl:SetText(CludesUI.L("No Saved Presets"))
                        itm._lbl:SetTextColor(1, 1, 1, 0.35)
                        itm._hl:SetAlpha(0)
                        itm._xBtn:Hide()
                        itm._editBtn:Hide()
                        itm:SetScript("OnClick", function()
                            prMenu:Hide()
                        end)
                    else
                        local capName = pr.name
                        itm._isEmpty = false
                        itm._lbl:SetText(capName)
                        itm._lbl:SetTextColor(1, 1, 1, CludesUI.TEXT_DIM_A)
                        itm._isSel = (capName == selName)
                        itm._hl:SetAlpha(itm._isSel and CludesUI.DD_ITEM_SEL_A or 0)
                        itm._xBtn:Show()
                        itm._xBtn:SetAlpha(0.4)
                        itm._editBtn:Show()
                        itm._editBtn:SetAlpha(0.4)
                        itm:SetScript("OnClick", function()
                            prMenu:Hide()
                            local p = DB()
                            if p then
                                p.tbbSelectedStylePreset = capName
                            end
                            UpdatePrDDLabel()
                        end)
                        itm._xBtn:SetScript("OnClick", function()
                            prMenu:Hide()
                            CludesUI:ShowConfirmPopup({
                                title = CludesUI.L("Delete Preset"),
                                message = CludesUI.Lf('Delete "%1$s"?', capName),
                                confirmText = CludesUI.L("Delete"),
                                cancelText = CludesUI.L("Cancel"),
                                onConfirm = function()
                                    if mod.DeleteTBBStylePreset then
                                        mod.DeleteTBBStylePreset(capName)
                                    end
                                    CludesUI:RefreshPage(true)
                                end,
                            })
                        end)
                        itm._editBtn:SetScript("OnClick", function()
                            prMenu:Hide()
                            CludesUI:ShowInputPopup({
                                title = CludesUI.L("Rename Preset"),
                                message = CludesUI.Lf('Enter a new name for "%1$s":', capName),
                                placeholder = capName,
                                confirmText = CludesUI.L("Rename"),
                                cancelText = CludesUI.L("Cancel"),
                                onConfirm = function(newName)
                                    newName = newName and strtrim(newName) or ""
                                    if newName == "" or newName == capName then
                                        return
                                    end
                                    if mod.FindTBBStylePreset and mod.FindTBBStylePreset(newName) then
                                        CludesUI.PrintError(
                                            CludesUI.Lf('A preset named "%1$s" already exists.', newName)
                                        )
                                        return
                                    end
                                    if mod.RenameTBBStylePreset then
                                        mod.RenameTBBStylePreset(capName, newName)
                                    end
                                    CludesUI:RefreshPage(true)
                                end,
                            })
                        end)
                    end

                    itm:Show()
                    mH = mH + 26
                end
                prMenu:SetHeight(mH + 4)
            end

            local function PrApplyNormal()
                prDDLbl:SetTextColor(aS[17], aS[18], aS[19], aS[20])
                prDDBrd:SetColor(aS[9], aS[10], aS[11], aS[12])
                prDDBg:SetColorTexture(aS[1], aS[2], aS[3], aS[4])
            end
            local function PrApplyHover()
                prDDLbl:SetTextColor(aS[21], aS[22], aS[23], aS[24])
                prDDBrd:SetColor(aS[13], aS[14], aS[15], aS[16])
                prDDBg:SetColorTexture(aS[5], aS[6], aS[7], aS[8])
            end
            prDD:SetScript("OnClick", function()
                if prMenu:IsShown() then
                    prMenu:Hide()
                else
                    RebuildPresetMenu()
                    prMenu:Show()
                end
            end)
            prDD:SetScript("OnEnter", function()
                PrApplyHover()
            end)
            prDD:SetScript("OnLeave", function()
                if not prMenu:IsShown() then
                    PrApplyNormal()
                end
            end)
            prDD:HookScript("OnHide", function()
                prMenu:Hide()
            end)
            prMenu:HookScript("OnShow", function()
                PrApplyHover()
            end)
            prMenu:SetScript("OnHide", function(self)
                self:SetScript("OnUpdate", nil)
                if prDD:IsMouseOver() then
                    PrApplyHover()
                else
                    PrApplyNormal()
                end
            end)

            -- Buttons with dim labels above, matching the profile row's "Assign to Spec" / "New Profile" columns.
            local function PresetBtn(labelText, btnText, xOff, tooltip, onClick)
                local lab = CludesUI.MakeFont(prRow, 12, nil, 1, 1, 1, 0.45)
                Pix.Point(lab, "LEFT", prLbl, "LEFT", xOff, 0)
                lab:SetText(CludesUI.L(labelText))
                lab:SetJustifyH("LEFT")
                local b = CreateFrame("Button", nil, prRow)
                Pix.Size(b, BTN_W, CTRL_H)
                Pix.Point(b, "TOPLEFT", lab, "BOTTOMLEFT", 0, -6)
                b:SetFrameLevel(prRow:GetFrameLevel() + 2)
                CludesUI.MakeStyledButton(b, btnText, 11, PROF_BTN_COLOURS, onClick)
                b:HookScript("OnEnter", function()
                    CludesUI.ShowWidgetTooltip(b, tooltip)
                end)
                b:HookScript("OnLeave", function()
                    CludesUI.HideWidgetTooltip()
                end)
                return b
            end
            local bx = DD_W + GAP_DD
            PresetBtn(
                "Apply to Bar",
                "Apply to Bar",
                bx,
                "Apply the selected preset's style to this bar.",
                function()
                    local pr = SelectedPreset()
                    if not pr then
                        return
                    end
                    local sel = (not _tbbSelectedGroup) and SelectedTBB() or nil
                    if not sel then
                        return
                    end
                    mod.ApplyTBBStylePresetToCfg(pr, sel)
                    RefreshTBB()
                    CludesUI:RefreshPage()
                end
            )
            PresetBtn(
                "Apply to Group",
                "Apply to Group",
                bx + BTN_W + GAP_BTN,
                "Apply the selected preset's style to every bar in this group.",
                function()
                    local pr = SelectedPreset()
                    if not pr then
                        return
                    end
                    local groupId = _tbbSelectedGroup
                    if not groupId then
                        local sel = SelectedTBB()
                        groupId = sel and mod.TBBBarGroupID(sel) or 0
                    end
                    if not groupId or groupId == 0 then
                        return
                    end
                    local t = mod.GetTrackedBuffBars()
                    for _, c in ipairs(t.bars or {}) do
                        if mod.TBBBarGroupID(c) == groupId then
                            mod.ApplyTBBStylePresetToCfg(pr, c)
                        end
                    end
                    RefreshTBB()
                    CludesUI:RefreshPage()
                end
            )
            PresetBtn(
                "New Preset",
                "Save New Preset",
                bx + (BTN_W + GAP_BTN) * 2,
                "Save this bar's current style as a new preset.",
                function()
                    local source = PreviewCfg()
                    if not source then
                        return
                    end
                    CludesUI:ShowInputPopup({
                        title = CludesUI.L("Save Style Preset"),
                        message = CludesUI.L("Enter a name for the new preset:"),
                        placeholder = UniqueTBBPresetName(),
                        confirmText = CludesUI.L("Save"),
                        cancelText = CludesUI.L("Cancel"),
                        onConfirm = function(nm)
                            if not nm or nm == "" then
                                nm = UniqueTBBPresetName()
                            end
                            if mod.SaveTBBStylePreset and mod.SaveTBBStylePreset(nm, source) then
                                local p = DB()
                                if p then
                                    p.tbbSelectedStylePreset = nm
                                end
                            end
                            CludesUI:RefreshPage(true)
                        end,
                    })
                end
            )

            posY = posY - PR_ROW_H - 14

            -- Currently Editing: centered label + the bar/group management dropdown, between the preset panel and the settings sections.
            local ceLbl = CludesUI.MakeFont(hostFrame, 12, nil, 1, 1, 1, 0.85)
            Pix.Point(ceLbl, "TOP", hostFrame, "TOP", 0, posY)
            ceLbl:SetText(CludesUI.L("Currently Editing:"))
            ceLbl:SetJustifyH("CENTER")
            posY = posY - 16 - 6

            local mgmtDD = BuildManagementDropdown(hostFrame)
            Pix.Point(mgmtDD, "TOP", hostFrame, "TOP", 0, posY)
            posY = posY - 34 - 14
        end

        -------------------------------------------------------------------
        --  GROUP MODE: only this group's settings, no per-bar sections
        -------------------------------------------------------------------
        if _tbbSelectedGroup then
            local groupId = _tbbSelectedGroup
            hostFrame._showRowDivider = true
            hostFrame._tbbClickTargets = nil

            heading, hgt = W:SectionHeader(hostFrame, "GROUP SETTINGS", posY)
            posY = posY - hgt
            -- The group's mover: a global group's TBBG_ element, else its anchor
            -- bar's (nil while no member is enabled: the click then does nothing).
            CludesUI.BuildSectionUnlockJump(heading, {
                key = function()
                    local gk = mod.TBBGroupGlobalKey and mod.TBBGroupGlobalKey(groupId)
                    if gk then
                        return "TBBG_" .. gk
                    end
                    local ai = mod.TBBGroupAnchorIndex(groupId)
                    return ai and ("TBB_" .. ai) or nil
                end,
            })

            -- Grow Direction | Bar Spacing
            _, hgt = W:DualRow(hostFrame, posY, {
                type = "dropdown",
                text = "Grow Direction",
                values = { DOWN = "Down", UP = "Up", LEFT = "Left", RIGHT = "Right" },
                order = { "DOWN", "UP", "LEFT", "RIGHT" },
                getValue = function()
                    return mod.TBBGroupGrow(groupId)
                end,
                setValue = function(v)
                    mod.TBBSetGroupGrow(groupId, v)
                    mod.BuildTrackedBuffBars()
                    -- Preview popout: RefreshPage() takes the fast path, repaint it here.
                    RefreshTBBPopout()
                    CludesUI:RefreshPage()
                end,
            }, {
                type = "slider",
                pixel = true,
                text = "Bar Spacing",
                min = -2,
                max = 20,
                step = 1,
                getValue = function()
                    return mod.TBBGroupSpacing(groupId)
                end,
                setValue = function(v)
                    mod.TBBSetGroupSpacing(groupId, v)
                    mod.BuildTrackedBuffBars()
                    -- Preview popout: RefreshPage() takes the fast path, repaint it here.
                    RefreshTBBPopout()
                    CludesUI:RefreshPage()
                end,
            })
            posY = posY - hgt

            -- Group Name (blank = the default "Group N" label) | Auto-Add
            _, hgt = W:DualRow(hostFrame, posY, {
                type = "input",
                text = "Group Name",
                inputWidth = 160,
                inputStyle = "popup",
                placeholder = CludesUI.L("Group") .. " " .. groupId,
                tooltip = "Rename this group; leave blank for the default name.",
                getValue = function()
                    return (mod.TBBGroupName and mod.TBBGroupName(groupId)) or ""
                end,
                setValue = function(textValue)
                    if mod.TBBSetGroupName then
                        mod.TBBSetGroupName(groupId, textValue)
                    end
                    RefreshTBB()
                    -- Soft refresh so the "Currently Editing:" dropdown label picks up the new name right away.
                    CludesUI:RefreshPage()
                end,
            }, {
                type = "toggle",
                text = "Auto-Add New to This Group",
                tooltip = "Automatically add a bar to this group for every spell in Blizzard's Tracked Bars section, now and whenever a new one appears.",
                getValue = function()
                    return mod.TBBGroupAutoAdd and mod.TBBGroupAutoAdd(groupId) or false
                end,
                setValue = function(v)
                    if not mod.TBBSetGroupAutoAdd then
                        return
                    end
                    mod.TBBSetGroupAutoAdd(groupId, v)
                    if v and mod.PopulateTBBAutoAddGroup then
                        mod.PopulateTBBAutoAddGroup(groupId)
                    end
                    mod.BuildTrackedBuffBars()
                    CludesUI:RefreshPage(true)
                end,
            })
            posY = posY - hgt

            -- Global Group | Shift Elements If No Bars
            local function GlobalEntry()
                local gk = mod.TBBGroupGlobalKey and mod.TBBGroupGlobalKey(groupId)
                return gk and mod.TBBGlobalGroup and mod.TBBGlobalGroup(gk) or nil
            end
            local shiftRow
            shiftRow, hgt = W:DualRow(hostFrame, posY, {
                type = "toggle",
                text = "Global Group",
                tooltip = "Share this group's name, layout, and position across all specs.",
                getValue = function()
                    return (mod.TBBGroupGlobalKey and mod.TBBGroupGlobalKey(groupId) ~= nil) or false
                end,
                setValue = function(v)
                    if not mod.TBBSetGroupGlobal then
                        return
                    end
                    mod.TBBSetGroupGlobal(groupId, v)
                    mod.BuildTrackedBuffBars()
                    CludesUI:RefreshPage(true)
                end,
            }, {
                type = "segmented",
                text = "Shift Elements If No Bars",
                tooltip = "When the current spec has no bars in this group, keeps elements anchored to the group in place and shifts them up or down by one bar height (tune with the cog's Extra Y Offset) to cover its empty slot.",
                disabled = function()
                    return GlobalEntry() == nil
                end,
                disabledTooltip = "Global Group",
                values = { None = "None", Up = "Up", Down = "Down" },
                order = { "None", "Up", "Down" },
                getValue = function()
                    local e = GlobalEntry()
                    return (e and e.shiftNoBar) or "None"
                end,
                setValue = function(v)
                    local e = GlobalEntry()
                    if not e then
                        return
                    end
                    if v == "Up" or v == "Down" then
                        e.shiftNoBar = v
                    else
                        e.shiftNoBar = nil
                    end
                    mod.BuildTrackedBuffBars()
                    CludesUI:RefreshPage()
                end,
            })
            posY = posY - hgt
            -- Inline reposition cog on the shift dropdown: Extra Y Offset
            -- (ResourceBars "Shift Elements if No Resource" parity).
            if not CludesUI._prebuilding then
                local rgn = shiftRow._rightRegion
                CludesUI.BuildInlineCog(rgn, {
                    title = "Shift Offset",
                    rows = {
                        {
                            type = "slider",
                            pixel = true,
                            label = "Extra Y Offset",
                            min = -50,
                            max = 50,
                            step = 1,
                            get = function()
                                local e = GlobalEntry()
                                return (e and e.shiftNoBarExtraY) or 0
                            end,
                            set = function(v)
                                local e = GlobalEntry()
                                if not e then
                                    return
                                end
                                e.shiftNoBarExtraY = (v ~= 0) and v or nil
                                mod.BuildTrackedBuffBars()
                                -- The build tail's cascade is EDGE-gated on the
                                -- shift direction, which a magnitude edit never
                                -- flips -- re-cascade explicitly so the slider
                                -- applies live (deferred batch coalesces drags).
                                local gk = mod.TBBGroupGlobalKey and mod.TBBGroupGlobalKey(groupId)
                                if gk and CludesUI.PropagateAnchorChain then
                                    CludesUI.PropagateAnchorChain("TBBG_" .. gk)
                                end
                            end,
                        },
                    },
                })
            end

            -- Ensure bar frames exist before showing placeholders
            mod.BuildTrackedBuffBars()
            UpdateTBBPlaceholder()
            RefreshTBBPopout()
            return math.abs(posY)
        end

        -------------------------------------------------------------------
        --  Scrollable settings (bar mode)
        -------------------------------------------------------------------
        if not SelectedTBB() then
            HideTBBPlaceholder()
            return math.abs(posY)
        end

        -- Append SharedMedia textures to runtime ns tables (for bar rendering)
        CludesUI.AppendSharedMediaTextures(
            mod.TBB_TEXTURE_NAMES or {},
            mod.TBB_TEXTURE_ORDER or {},
            nil,
            mod.TBB_TEXTURES
        )

        -- Texture dropdown values (built from ns tables, now including SM entries)
        local texValues = {}
        local texOrder = {}
        do
            local nameList = mod.TBB_TEXTURE_NAMES or {}
            local sequence = mod.TBB_TEXTURE_ORDER or {}
            local lookup = mod.TBB_TEXTURES or {}
            for _, key in ipairs(sequence) do
                if key ~= "---" then
                    texValues[key] = nameList[key] or key
                end
                texOrder[#texOrder + 1] = key
            end
            texValues._menuOpts = {
                itemHeight = 28,
                background = function(key)
                    return lookup[key]
                end,
            }
        end

        hostFrame._showRowDivider = true

        -------------------------------------------------------------------
        --  BAR LAYOUT
        -------------------------------------------------------------------
        local layoutHeader
        layoutHeader, hgt = W:SectionHeader(hostFrame, "BAR LAYOUT", posY)
        posY = posY - hgt
        -- The selected bar's mover; a grouped bar's is its group's (a global
        -- group's TBBG_ element, else the group anchor's), since only the anchor
        -- keeps a mover.
        CludesUI.BuildSectionUnlockJump(layoutHeader, {
            key = function()
                local bd = SelectedTBB()
                local groupId = bd and mod.TBBBarGroupID(bd) or 0
                if groupId ~= 0 then
                    local gk = mod.TBBGroupGlobalKey and mod.TBBGroupGlobalKey(groupId)
                    if gk then
                        return "TBBG_" .. gk
                    end
                    local ai = mod.TBBGroupAnchorIndex(groupId)
                    if ai then
                        return "TBB_" .. ai
                    end
                end
                return "TBB_" .. _tbbSelectedBar
            end,
        })

        -- Height | Width. The whole group shares one width/height, so a grouped member
        -- inherits the group ANCHOR's match-lock: if size-matched, every member's slider
        -- is disabled (match wins) instead of silently fighting it.
        local tbbKey = "TBB_" .. _tbbSelectedBar
        do
            local selBd = SelectedTBB()
            local selGid = selBd and mod.TBBBarGroupID(selBd) or 0
            if selGid ~= 0 then
                local ai = mod.TBBGroupAnchorIndex(selGid)
                if ai then
                    tbbKey = "TBB_" .. ai
                end
            end
        end
        local thDis, thTip, thRaw = CludesUI.MatchGuard(tbbKey, "Height")
        local twDis, twTip, twRaw = CludesUI.MatchGuard(tbbKey, "Width")
        -- Width is the THICKNESS of a vertical bar (toggle swaps stored dimensions), so its
        -- floor drops to 1 there -- a 50px floor would clamp a slim vertical bar the moment the slider is touched.
        local selIsVert
        do
            local sb0 = SelectedTBB()
            selIsVert = sb0 and sb0.verticalOrientation and true or false
        end
        local hwRow
        hwRow, hgt = W:DualRow(hostFrame, posY, {
            type = "slider",
            text = "Height",
            min = 1,
            max = 800,
            step = 1,
            disabled = thDis,
            disabledTooltip = thTip,
            rawTooltip = thRaw,
            getValue = function()
                local bd = SelectedTBB()
                return bd and bd.height or 24
            end,
            setValue = function(v)
                local bd = SelectedTBB()
                if not bd then
                    return
                end
                bd.height = v
                -- Grouped bars share height: write the rest of the group too.
                local groupId = mod.TBBBarGroupID(bd)
                if groupId ~= 0 then
                    local t = mod.GetTrackedBuffBars()
                    for _, b in ipairs(t.bars or {}) do
                        if b ~= bd and mod.TBBBarGroupID(b) == groupId then
                            b.height = v
                        end
                    end
                end
                mod.BuildTrackedBuffBars()
                -- BuildTrackedBuffBars() only rebuilds the LIVE bar pool; the
                -- preview wraps in the popout are separate frames. RefreshPage()
                -- takes the fast widget-refresh path here, so the page builder
                -- tail that repaints the popout never re-runs. Repaint it
                -- directly or the preview keeps the old geometry.
                RefreshTBBPopout()
                CludesUI:RefreshPage()
            end,
        }, {
            type = "slider",
            text = "Width",
            min = 1,
            max = 800,
            step = 1,
            disabled = twDis,
            disabledTooltip = twTip,
            rawTooltip = twRaw,
            getValue = function()
                local bd = SelectedTBB()
                return bd and bd.width or 270
            end,
            setValue = function(v)
                local bd = SelectedTBB()
                if not bd then
                    return
                end
                bd.width = v
                -- Grouped bars share width: write the rest of the group too.
                local groupId = mod.TBBBarGroupID(bd)
                if groupId ~= 0 then
                    local t = mod.GetTrackedBuffBars()
                    for _, b in ipairs(t.bars or {}) do
                        if b ~= bd and mod.TBBBarGroupID(b) == groupId then
                            b.width = v
                        end
                    end
                end
                mod.BuildTrackedBuffBars()
                -- Preview popout: RefreshPage() takes the fast path, repaint it here.
                RefreshTBBPopout()
                CludesUI:RefreshPage()
            end,
        })
        posY = posY - hgt

        -- Sync icons: Apply Height/Width to all bars of the SAME orientation -- "height" is
        -- the short side of a horizontal bar but the LONG side of a vertical one, so cross-orientation copies would be nonsense.
        if CludesUI.BuildSyncIcon then
            local function SameOrientation(a, b)
                return (a.verticalOrientation and true or false) == (b.verticalOrientation and true or false)
            end
            local orientWord = selIsVert and "Vertical" or "Horizontal"
            CludesUI.BuildSyncIcon({
                region = hwRow._leftRegion,
                tooltip = "Apply Height to all " .. orientWord .. " Bars",
                isSynced = function()
                    local bd = SelectedTBB()
                    if not bd then
                        return false
                    end
                    local val = bd.height or 24
                    local t = mod.GetTrackedBuffBars()
                    for _, b in ipairs(t.bars or {}) do
                        if SameOrientation(bd, b) and (b.height or 24) ~= val then
                            return false
                        end
                    end
                    return true
                end,
                onClick = function()
                    local bd = SelectedTBB()
                    if not bd then
                        return
                    end
                    local val = bd.height or 24
                    local t = mod.GetTrackedBuffBars()
                    for _, b in ipairs(t.bars or {}) do
                        if SameOrientation(bd, b) then
                            b.height = val
                        end
                    end
                    RefreshTBB()
                    CludesUI:RefreshPage()
                end,
            })
            CludesUI.BuildSyncIcon({
                region = hwRow._rightRegion,
                tooltip = "Apply Width to all " .. orientWord .. " Bars",
                isSynced = function()
                    local bd = SelectedTBB()
                    if not bd then
                        return false
                    end
                    local val = bd.width or 270
                    local t = mod.GetTrackedBuffBars()
                    for _, b in ipairs(t.bars or {}) do
                        if SameOrientation(bd, b) and (b.width or 270) ~= val then
                            return false
                        end
                    end
                    return true
                end,
                onClick = function()
                    local bd = SelectedTBB()
                    if not bd then
                        return
                    end
                    local val = bd.width or 270
                    local t = mod.GetTrackedBuffBars()
                    for _, b in ipairs(t.bars or {}) do
                        if SameOrientation(bd, b) then
                            b.width = val
                        end
                    end
                    RefreshTBB()
                    CludesUI:RefreshPage()
                end,
            })
        end

        -- Vertical Orientation | Bar Texture
        _, hgt = W:DualRow(
            hostFrame,
            posY,
            {
                type = "toggle",
                text = "Vertical Orientation",
                tooltip = "Vertical bars fill upward; flipping a grouped bar flips its whole group.",
                getValue = function()
                    local bd = SelectedTBB()
                    return bd and bd.verticalOrientation
                end,
                setValue = function(v)
                    local bd = SelectedTBB()
                    if not bd then
                        return
                    end
                    -- Swap width/height so visual dimensions stay correct
                    local function flip(c)
                        c.width, c.height = (c.height or 24), (c.width or 270)
                        c.verticalOrientation = v
                    end
                    flip(bd)
                    -- Groups stay orientation-uniform: shared width/height only makes sense
                    -- when every member reads dimensions the same way, so the whole group flips together.
                    local groupId = mod.TBBBarGroupID(bd)
                    if groupId ~= 0 then
                        local t = mod.GetTrackedBuffBars()
                        for _, b in ipairs(t.bars or {}) do
                            if
                                b ~= bd
                                and mod.TBBBarGroupID(b) == groupId
                                and (b.verticalOrientation and true or false) ~= (v and true or false)
                            then
                                flip(b)
                            end
                        end
                        -- Rotate the grow direction so side-by-side stays side-by-side across the flip (DOWN<->RIGHT, UP<->LEFT).
                        local rot = v and { DOWN = "RIGHT", UP = "LEFT" } or { RIGHT = "DOWN", LEFT = "UP" }
                        local grow = mod.TBBGroupGrow(groupId)
                        if rot[grow] then
                            mod.TBBSetGroupGrow(groupId, rot[grow])
                        end
                    end
                    RefreshTBB()
                    -- Full rebuild: the Width slider's floor and sync tooltips are orientation-dependent.
                    CludesUI:RefreshPage(true)
                end,
            },
            GateBlizzardOnly("cdmbars", {
                type = "dropdown",
                text = "Bar Texture",
                values = texValues,
                order = texOrder,
                getValue = function()
                    local bd = SelectedTBB()
                    return bd and bd.texture or "none"
                end,
                setValue = function(v)
                    local bd = SelectedTBB()
                    if not bd then
                        return
                    end
                    bd.texture = v
                    RefreshTBB()
                end,
            })
        )
        posY = posY - hgt

        -- Name Text (dropdown + cog) | Duration Text (dropdown + cog)
        local TBB_POS_VALUES = {
            none = "None",
            center = "Center",
            top = "Top",
            bottom = "Bottom",
            left = "Left",
            right = "Right",
        }
        local TBB_POS_ORDER = { "none", "center", "top", "bottom", "left", "right" }

        -- When a text element claims a position, evict any other text already there so
        -- labels never overlap. Compares EFFECTIVE (rendered) positions: name text never
        -- renders on vertical bars, so its stored slot must not evict anything there.
        local function EvictTBBTextConflicts(bd, changedKey, newPos)
            if newPos == "none" then
                return
            end
            local function resolvePos(key)
                if key == "namePosition" and bd.verticalOrientation then
                    return "none"
                end
                local v = bd[key]
                if v then
                    return v
                end
                if key == "namePosition" then
                    return (bd.showName ~= false) and "left" or "none"
                end
                if key == "timerPosition" then
                    return bd.showTimer and "right" or "none"
                end
                if key == "stacksPosition" then
                    return "center"
                end
                return "none"
            end
            local TEXT_KEYS = { "namePosition", "timerPosition", "stacksPosition" }
            for _, k in ipairs(TEXT_KEYS) do
                if k ~= changedKey and resolvePos(k) == newPos then
                    bd[k] = "none"
                    if k == "namePosition" then
                        bd.showName = false
                    elseif k == "timerPosition" then
                        bd.showTimer = false
                    end
                end
            end
        end

        local function AddTBBTextSwatch(row, regionFrame, prefixText)
            local ctrl = regionFrame._control
            local function GetColor()
                local bd = SelectedTBB()
                if not bd then
                    return 1, 1, 1, 0.9
                end
                local r = bd[prefixText .. "TextR"]
                local g = bd[prefixText .. "TextG"]
                local b = bd[prefixText .. "TextB"]
                local a = bd[prefixText .. "TextA"]
                if r == nil then
                    r = 1
                end
                if g == nil then
                    g = 1
                end
                if b == nil then
                    b = 1
                end
                if a == nil then
                    a = 0.9
                end
                return r, g, b, a
            end
            local colorSwatch, updateSwatch = CludesUI.BuildColorSwatch(
                regionFrame,
                row:GetFrameLevel() + 3,
                GetColor,
                function(r, g, b, a)
                    local bd = SelectedTBB()
                    if not bd then
                        return
                    end
                    bd[prefixText .. "TextR"] = r
                    bd[prefixText .. "TextG"] = g
                    bd[prefixText .. "TextB"] = b
                    bd[prefixText .. "TextA"] = a
                    RefreshTBB()
                end,
                true,
                20
            )
            Pix.Point(colorSwatch, "RIGHT", regionFrame._lastInline or ctrl, "LEFT", -8, 0)
            regionFrame._lastInline = colorSwatch

            local block = CreateFrame("Frame", nil, colorSwatch)
            block:SetAllPoints()
            block:SetFrameLevel(colorSwatch:GetFrameLevel() + 10)
            block:EnableMouse(true)
            block:SetScript("OnEnter", function()
                local bd = SelectedTBB()
                local tipText
                if prefixText == "name" and bd and bd.verticalOrientation then
                    tipText = "Horizontal Orientation (name text is not shown on vertical bars)"
                else
                    local label = prefixText == "timer" and "Duration Text"
                        or (prefixText == "stacks" and "Stacks Text" or "Name Text")
                    tipText = "This option requires a " .. label .. " position other than None"
                end
                CludesUI.ShowWidgetTooltip(colorSwatch, CludesUI.DisabledTooltip(tipText))
            end)
            block:SetScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)

            local function UpdateSwatchState()
                local bd = SelectedTBB()
                local position
                if bd then
                    position = bd[prefixText .. "Position"]
                    if not position then
                        if prefixText == "name" then
                            position = (bd.showName ~= false) and "left" or "none"
                        elseif prefixText == "timer" then
                            position = bd.showTimer and "right" or "none"
                        else
                            position = "center"
                        end
                    end
                end
                local enabled = position ~= nil and position ~= "none"
                if prefixText == "name" and bd and bd.verticalOrientation then
                    enabled = false
                end
                colorSwatch:SetAlpha(enabled and 1 or 0.3)
                if enabled then
                    block:Hide()
                else
                    block:Show()
                end
            end

            CludesUI.RegisterWidgetRefresh(function()
                updateSwatch()
                UpdateSwatchState()
            end)
            UpdateSwatchState()
        end

        local nameRow
        nameRow, hgt = W:DualRow(hostFrame, posY, {
            type = "dropdown",
            text = "Name Text",
            values = TBB_POS_VALUES,
            order = TBB_POS_ORDER,
            disabled = function()
                local bd = SelectedTBB()
                return bd and bd.verticalOrientation and true or false
            end,
            disabledTooltip = "Horizontal Orientation (name text is not shown on vertical bars)",
            getValue = function()
                local bd = SelectedTBB()
                if not bd then
                    return "left"
                end
                if bd.namePosition then
                    return bd.namePosition
                end
                return (bd.showName ~= false) and "left" or "none"
            end,
            setValue = function(v)
                local bd = SelectedTBB()
                if not bd then
                    return
                end
                EvictTBBTextConflicts(bd, "namePosition", v)
                bd.namePosition = v
                bd.showName = (v ~= "none")
                RefreshTBB()
                CludesUI:RefreshPage()
            end,
        }, {
            type = "dropdown",
            text = "Duration Text",
            values = TBB_POS_VALUES,
            order = TBB_POS_ORDER,
            getValue = function()
                local bd = SelectedTBB()
                if not bd then
                    return "right"
                end
                if bd.timerPosition then
                    return bd.timerPosition
                end
                return bd.showTimer and "right" or "none"
            end,
            setValue = function(v)
                local bd = SelectedTBB()
                if not bd then
                    return
                end
                EvictTBBTextConflicts(bd, "timerPosition", v)
                bd.timerPosition = v
                bd.showTimer = (v ~= "none")
                RefreshTBB()
                CludesUI:RefreshPage()
            end,
        })
        posY = posY - hgt
        -- Cog on Name Text: custom name, text size, wrap + x/y
        do
            local rgn = nameRow._leftRegion
            CludesUI.BuildInlineCog(rgn, {
                title = "Name Text Settings",
                disabled = function()
                    local bd = SelectedTBB()
                    if bd and bd.verticalOrientation then
                        return true
                    end
                    local place = bd and bd.namePosition
                    if not place then
                        place = (bd and bd.showName ~= false) and "left" or "none"
                    end
                    return place == "none"
                end,
                disabledTooltip = function()
                    local bd = SelectedTBB()
                    if bd and bd.verticalOrientation then
                        return "Horizontal Orientation (name text is not shown on vertical bars)"
                    end
                    return "This option requires a Name Text position other than None"
                end,
                rows = {
                    {
                        type = "input",
                        label = "Custom Name",
                        inputWidth = 120,
                        commitOnBlur = true,
                        tooltip = "Leave empty to show the spell's name.",
                        get = function()
                            local bd = SelectedTBB()
                            return bd and bd.customName or ""
                        end,
                        set = function(textValue)
                            local bd = SelectedTBB()
                            if not bd then
                                return
                            end
                            textValue = strtrim(textValue or "")
                            bd.customName = textValue ~= "" and textValue or nil
                            RefreshTBB()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Text Size",
                        min = 8,
                        max = 24,
                        step = 1,
                        get = function()
                            local bd = SelectedTBB()
                            return bd and bd.nameSize or 11
                        end,
                        set = function(v)
                            local bd = SelectedTBB()
                            if not bd then
                                return
                            end
                            bd.nameSize = v
                            RefreshTBB()
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Text Wrap",
                        get = function()
                            local bd = SelectedTBB()
                            return bd and bd.nameWrap == true
                        end,
                        set = function(v)
                            local bd = SelectedTBB()
                            if not bd then
                                return
                            end
                            bd.nameWrap = v or nil
                            RefreshTBB()
                        end,
                    },
                    {
                        type = "slider",
                        label = "X Offset",
                        min = -100,
                        max = 100,
                        step = 1,
                        get = function()
                            local bd = SelectedTBB()
                            return bd and bd.nameX or 0
                        end,
                        set = function(v)
                            local bd = SelectedTBB()
                            if not bd then
                                return
                            end
                            bd.nameX = v
                            RefreshTBB()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Y Offset",
                        min = -100,
                        max = 100,
                        step = 1,
                        get = function()
                            local bd = SelectedTBB()
                            return bd and bd.nameY or 0
                        end,
                        set = function(v)
                            local bd = SelectedTBB()
                            if not bd then
                                return
                            end
                            bd.nameY = v
                            RefreshTBB()
                        end,
                    },
                },
            })
        end
        AddTBBTextSwatch(nameRow, nameRow._leftRegion, "name")
        -- Sync icon on Name Text
        do
            local rgn = nameRow._leftRegion
            CludesUI.BuildSyncIcon({
                region = rgn,
                tooltip = "Apply Name Text to all Bars",
                isSynced = function()
                    local bd = SelectedTBB()
                    if not bd then
                        return false
                    end
                    local place = bd.namePosition or ((bd.showName ~= false) and "left" or "none")
                    local tbb = mod.GetTrackedBuffBars()
                    for _, b in ipairs(tbb.bars or {}) do
                        local bp = b.namePosition or ((b.showName ~= false) and "left" or "none")
                        if bp ~= place then
                            return false
                        end
                    end
                    return true
                end,
                onClick = function()
                    local bd = SelectedTBB()
                    if not bd then
                        return
                    end
                    local place = bd.namePosition or ((bd.showName ~= false) and "left" or "none")
                    local tbb = mod.GetTrackedBuffBars()
                    for _, b in ipairs(tbb.bars or {}) do
                        b.namePosition = place
                        b.showName = (place ~= "none")
                    end
                    RefreshTBB()
                    CludesUI:RefreshPage()
                end,
            })
        end
        -- Cog on Duration Text: timer size + x/y
        do
            local rgn = nameRow._rightRegion
            local durationRows = {
                {
                    type = "slider",
                    label = "Timer Size",
                    min = 8,
                    max = 24,
                    step = 1,
                    get = function()
                        local bd = SelectedTBB()
                        return bd and bd.timerSize or 11
                    end,
                    set = function(v)
                        local bd = SelectedTBB()
                        if not bd then
                            return
                        end
                        bd.timerSize = v
                        RefreshTBB()
                    end,
                },
                {
                    type = "slider",
                    label = "X Offset",
                    min = -100,
                    max = 100,
                    step = 1,
                    get = function()
                        local bd = SelectedTBB()
                        return bd and bd.timerX or 0
                    end,
                    set = function(v)
                        local bd = SelectedTBB()
                        if not bd then
                            return
                        end
                        bd.timerX = v
                        RefreshTBB()
                    end,
                },
                {
                    type = "slider",
                    label = "Y Offset",
                    min = -100,
                    max = 100,
                    step = 1,
                    get = function()
                        local bd = SelectedTBB()
                        return bd and bd.timerY or 0
                    end,
                    set = function(v)
                        local bd = SelectedTBB()
                        if not bd then
                            return
                        end
                        bd.timerY = v
                        RefreshTBB()
                    end,
                },
            }
            -- Engine-rendered tenths below the threshold (see CludesUICdmTbbDecimals.lua).
            table.insert(durationRows, 2, {
                type = "toggle",
                label = "Decimals",
                tooltip = "Cannot work for pet/totem summon bars (Call Dreadstalkers, etc.) -- they expose no readable timer.",
                get = function()
                    local bd = SelectedTBB()
                    return bd and bd.timerDecimals == true
                end,
                set = function(v)
                    local bd = SelectedTBB()
                    if not bd then
                        return
                    end
                    bd.timerDecimals = v or nil
                    RefreshTBB()
                end,
            })
            table.insert(durationRows, 3, {
                type = "slider",
                label = "Decimal Threshold",
                min = 1,
                max = 120,
                step = 1,
                disabled = function()
                    local bd = SelectedTBB()
                    return not (bd and bd.timerDecimals)
                end,
                disabledTooltip = "Decimals enabled",
                get = function()
                    local bd = SelectedTBB()
                    return bd and bd.timerDecimalThreshold or 5
                end,
                set = function(v)
                    local bd = SelectedTBB()
                    if not bd then
                        return
                    end
                    bd.timerDecimalThreshold = v
                    RefreshTBB()
                end,
            })
            CludesUI.BuildInlineCog(rgn, {
                title = "Duration Text Settings",
                rows = durationRows,
                disabled = function()
                    local bd = SelectedTBB()
                    local place = bd and bd.timerPosition
                    if not place then
                        place = (bd and bd.showTimer) and "right" or "none"
                    end
                    return place == "none"
                end,
                disabledTooltip = "This option requires a Duration Text position other than None",
            })
        end
        AddTBBTextSwatch(nameRow, nameRow._rightRegion, "timer")
        -- Sync icon on Duration Text
        do
            local rgn = nameRow._rightRegion
            CludesUI.BuildSyncIcon({
                region = rgn,
                tooltip = "Apply Duration Text to all Bars",
                isSynced = function()
                    local bd = SelectedTBB()
                    if not bd then
                        return false
                    end
                    local place = bd.timerPosition or (bd.showTimer and "right" or "none")
                    local tbb = mod.GetTrackedBuffBars()
                    for _, b in ipairs(tbb.bars or {}) do
                        local bp = b.timerPosition or (b.showTimer and "right" or "none")
                        if bp ~= place then
                            return false
                        end
                    end
                    return true
                end,
                onClick = function()
                    local bd = SelectedTBB()
                    if not bd then
                        return
                    end
                    local place = bd.timerPosition or (bd.showTimer and "right" or "none")
                    local tbb = mod.GetTrackedBuffBars()
                    for _, b in ipairs(tbb.bars or {}) do
                        b.timerPosition = place
                        b.showTimer = (place ~= "none")
                    end
                    RefreshTBB()
                    CludesUI:RefreshPage()
                end,
            })
        end

        -- Stacks Text (dropdown + resize cog: size, x, y) | Bar Strata
        local stacksRow
        stacksRow, hgt = W:DualRow(hostFrame, posY, {
            type = "dropdown",
            text = "Stacks Text",
            values = TBB_POS_VALUES,
            order = TBB_POS_ORDER,
            getValue = function()
                local bd = SelectedTBB()
                return bd and bd.stacksPosition or "center"
            end,
            setValue = function(v)
                local bd = SelectedTBB()
                if not bd then
                    return
                end
                EvictTBBTextConflicts(bd, "stacksPosition", v)
                bd.stacksPosition = v
                RefreshTBB()
                CludesUI:RefreshPage()
            end,
        }, {
            type = "dropdown",
            text = "Bar Strata",
            tooltip = "Screen layer the bar renders on; changing a grouped bar changes its whole group.",
            values = CludesUI.FRAME_STRATA_LABELS,
            order = CludesUI.FRAME_STRATA_ORDER_FULL,
            getValue = function()
                local bd = SelectedTBB()
                return bd and bd.strata or "MEDIUM"
            end,
            setValue = function(v)
                local bd = SelectedTBB()
                if not bd then
                    return
                end
                bd.strata = v
                -- Grouped bars share one strata: write the rest of the group too.
                local groupId = mod.TBBBarGroupID(bd)
                if groupId ~= 0 then
                    local t = mod.GetTrackedBuffBars()
                    for _, b in ipairs(t.bars or {}) do
                        if b ~= bd and mod.TBBBarGroupID(b) == groupId then
                            b.strata = v
                        end
                    end
                end
                RefreshTBB()
            end,
        })
        posY = posY - hgt
        do
            local rgn = stacksRow._leftRegion
            CludesUI.BuildInlineCog(rgn, {
                title = "Stacks Text Settings",
                disabled = function()
                    local bd = SelectedTBB()
                    return bd and (bd.stacksPosition or "center") == "none"
                end,
                disabledTooltip = "This option requires a Stacks Text position other than None",
                rows = {
                    {
                        type = "slider",
                        label = "Size",
                        min = 6,
                        max = 24,
                        step = 1,
                        get = function()
                            local bd = SelectedTBB()
                            return bd and bd.stacksSize or 11
                        end,
                        set = function(v)
                            local bd = SelectedTBB()
                            if not bd then
                                return
                            end
                            bd.stacksSize = v
                            RefreshTBB()
                        end,
                    },
                    {
                        type = "slider",
                        label = "X Offset",
                        min = -250,
                        max = 250,
                        step = 1,
                        get = function()
                            local bd = SelectedTBB()
                            return bd and bd.stacksX or 0
                        end,
                        set = function(v)
                            local bd = SelectedTBB()
                            if not bd then
                                return
                            end
                            bd.stacksX = v
                            RefreshTBB()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Y Offset",
                        min = -250,
                        max = 250,
                        step = 1,
                        get = function()
                            local bd = SelectedTBB()
                            return bd and bd.stacksY or 0
                        end,
                        set = function(v)
                            local bd = SelectedTBB()
                            if not bd then
                                return
                            end
                            bd.stacksY = v
                            RefreshTBB()
                        end,
                    },
                },
            })
        end
        AddTBBTextSwatch(stacksRow, stacksRow._leftRegion, "stacks")
        -- Sync icon on Stacks Text
        do
            local rgn = stacksRow._leftRegion
            CludesUI.BuildSyncIcon({
                region = rgn,
                tooltip = "Apply Stacks Text to all Bars",
                isSynced = function()
                    local bd = SelectedTBB()
                    if not bd then
                        return false
                    end
                    local place = bd.stacksPosition or "center"
                    local tbb = mod.GetTrackedBuffBars()
                    for _, b in ipairs(tbb.bars or {}) do
                        if (b.stacksPosition or "center") ~= place then
                            return false
                        end
                    end
                    return true
                end,
                onClick = function()
                    local bd = SelectedTBB()
                    if not bd then
                        return
                    end
                    local place = bd.stacksPosition or "center"
                    local tbb = mod.GetTrackedBuffBars()
                    for _, b in ipairs(tbb.bars or {}) do
                        b.stacksPosition = place
                    end
                    RefreshTBB()
                    CludesUI:RefreshPage()
                end,
            })
        end

        -- Reverse Fill | Fill Up. Deliberately paired on one row: they are the
        -- two options a user reaches for when the bar is not moving the way
        -- they expect, and they do different things. Reverse Fill mirrors the
        -- geometry, Fill Up flips the direction the value travels. Splitting
        -- them across the page is what makes people try the wrong one.
        -- Named distinctly: `fillRow` is already taken further down by the
        -- Fill Color row, which preview click-nav targets by reference.
        local fillDirRow
        fillDirRow, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Reverse Fill",
            tooltip = "Mirrors which end of the bar the fill is anchored to. It does not change the direction the bar travels: use Fill Up for that.",
            getValue = function()
                local bd = SelectedTBB()
                return bd and bd.reverseFill
            end,
            setValue = function(v)
                local bd = SelectedTBB()
                if not bd then
                    return
                end
                bd.reverseFill = v
                RefreshTBB()
            end,
        }, {
            type = "toggle",
            text = "Fill Up",
            tooltip = "Fills the bar as the cooldown recovers instead of draining it as the cooldown runs down.",
            disabled = function()
                local bd = SelectedTBB()
                -- Charge Hash Lines drives its own recovery bar, which
                -- already fills upward, so fillUp cannot do anything there.
                -- Leaving the toggle live would promise behaviour it has no
                -- way to deliver. Test the same way the Charge Hash Lines
                -- toggle does: the stored flag alone is not enough, because
                -- chargeHashLines rides in TBB_STYLE_KEYS and a style copy
                -- or preset can set it on a single-charge spell, where the
                -- hash fill never actually runs.
                return not bd
                    or bd.trackType ~= "cooldown"
                    or (bd.chargeHashLines == true and SelectedTBBSupportsChargeHash())
            end,
            -- rawTooltip: these are whole sentences. Without it they get
            -- wrapped into "This option requires <text> to be enabled".
            rawTooltip = true,
            disabledTooltip = function()
                local bd = SelectedTBB()
                if not bd or bd.trackType ~= "cooldown" then
                    return "This option requires a cooldown-tracking bar"
                end
                return "Charge Hash Lines already fills as charges recover"
            end,
            getValue = function()
                local bd = SelectedTBB()
                return bd and bd.fillUp == true
            end,
            setValue = function(v)
                local bd = SelectedTBB()
                if not bd then
                    return
                end
                bd.fillUp = v and true or nil
                RefreshTBB()
            end,
        })
        posY = posY - hgt

        -- Charge Hash Lines | Smooth Bars. Hash separator count/orientation resolve
        -- automatically from the spell's max charges; Smooth Bars is profile-wide, not per bar/spec.
        local SMOOTH_ITEMS = {
            { key = "buffs", label = "Buffs" },
            { key = "cooldowns", label = "Cooldowns" },
        }
        local SMOOTH_DEFAULT = { buffs = true, cooldowns = false }
        local chargeHashRow
        chargeHashRow, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Charge Hash Lines",
            tooltip = "Divides a cooldown-tracking bar into one recovery section per ability charge. The timer shows the next charge's cooldown.",
            disabled = function()
                local bd = SelectedTBB()
                return not bd or bd.trackType ~= "cooldown" or not SelectedTBBSupportsChargeHash()
            end,
            disabledTooltip = function()
                local bd = SelectedTBB()
                if not bd or bd.trackType ~= "cooldown" then
                    return "This option requires a cooldown-tracking bar"
                end
                return "This option is only available for abilities with multiple charges"
            end,
            getValue = function()
                local bd = SelectedTBB()
                return bd and bd.chargeHashLines == true and SelectedTBBSupportsChargeHash()
            end,
            setValue = function(v)
                local bd = SelectedTBB()
                if not bd then
                    return
                end
                if v and not SelectedTBBSupportsChargeHash() then
                    return
                end
                bd.chargeHashLines = v and true or nil
                RefreshTBB()
                CludesUI:RefreshPage()
            end,
        }, {
            type = "dropdown",
            text = "Smooth Bars",
            tooltip = "Eases bar movement instead of snapping. Affects all Tracking Bars of that type, in every spec of this profile.",
            values = { __placeholder = "..." },
            order = { "__placeholder" },
            getValue = function()
                return "__placeholder"
            end,
            setValue = function() end,
        })
        posY = posY - hgt
        do
            local rgn = chargeHashRow._leftRegion
            CludesUI.BuildInlineCog(rgn, {
                title = "Charge Hash Line Settings",
                disabled = function()
                    local bd = SelectedTBB()
                    return not bd
                        or bd.trackType ~= "cooldown"
                        or not SelectedTBBSupportsChargeHash()
                        or bd.chargeHashLines ~= true
                end,
                disabledTooltip = function()
                    local bd = SelectedTBB()
                    if not bd or bd.trackType ~= "cooldown" then
                        return "This option requires a cooldown-tracking bar"
                    end
                    if not SelectedTBBSupportsChargeHash() then
                        return "This option is only available for abilities with multiple charges"
                    end
                    return "Enable Charge Hash Lines first"
                end,
                rawTooltip = true,
                rows = {
                    {
                        type = "slider",
                        label = "Line Width",
                        min = 1,
                        max = 10,
                        step = 1,
                        get = function()
                            local bd = SelectedTBB()
                            return bd and bd.chargeHashLineWidth or 2
                        end,
                        set = function(v)
                            local bd = SelectedTBB()
                            if not bd then
                                return
                            end
                            bd.chargeHashLineWidth = v
                            RefreshTBB()
                        end,
                    },
                    {
                        type = "colorpicker",
                        label = "Line Color",
                        hasAlpha = true,
                        get = function()
                            local bd = SelectedTBB()
                            if not bd then
                                return 0, 0, 0, 1
                            end
                            local a = bd.chargeHashLineA
                            if a == nil then
                                a = 1
                            end
                            return bd.chargeHashLineR or 0,
                                bd.chargeHashLineG or 0,
                                bd.chargeHashLineB or 0,
                                a
                        end,
                        set = function(r, g, b, a)
                            local bd = SelectedTBB()
                            if not bd then
                                return
                            end
                            bd.chargeHashLineR, bd.chargeHashLineG = r, g
                            bd.chargeHashLineB, bd.chargeHashLineA = b, a
                            RefreshTBB()
                        end,
                    },
                    {
                        type = "toggle",
                        label = "Partial Charge Shade",
                        tooltip = "Darkens the section of the bar that is still recharging the next charge.",
                        get = function()
                            local bd = SelectedTBB()
                            return bd and bd.chargeHashShade == true
                        end,
                        set = function(v)
                            local bd = SelectedTBB()
                            if not bd then
                                return
                            end
                            bd.chargeHashShade = v and true or nil
                            RefreshTBB()
                        end,
                    },
                    {
                        type = "slider",
                        label = "Shade Darkness",
                        min = 5,
                        max = 95,
                        step = 5,
                        disabled = function()
                            local bd = SelectedTBB()
                            return not bd or bd.chargeHashShade ~= true
                        end,
                        get = function()
                            local bd = SelectedTBB()
                            return bd and math.floor(((bd.chargeHashShadeAlpha or 0.5) * 100) + 0.5) or 50
                        end,
                        set = function(v)
                            local bd = SelectedTBB()
                            if not bd then
                                return
                            end
                            bd.chargeHashShadeAlpha = (v or 50) / 100
                            RefreshTBB()
                        end,
                    },
                },
            })
        end

        do
            local rgn = chargeHashRow._rightRegion
            if rgn._control then
                rgn._control:Hide()
            end
            local cbDD, cbDDRefresh = CludesUI.BuildVisOptsCBDropdown(
                rgn,
                210,
                rgn:GetFrameLevel() + 2,
                SMOOTH_ITEMS,
                function(k)
                    local s = mod.GetTBBSmoothSettings and mod.GetTBBSmoothSettings()
                    if not s or s[k] == nil then
                        return SMOOTH_DEFAULT[k]
                    end
                    return s[k] == true
                end,
                function(k, v)
                    local s = mod.GetTBBSmoothSettings and mod.GetTBBSmoothSettings()
                    if s then
                        s[k] = v and true or false
                    end
                end
            )
            Pix.Point(cbDD, "RIGHT", rgn, "RIGHT", -20, 0)
            rgn._control = cbDD
            rgn._lastInline = nil
            CludesUI.RegisterWidgetRefresh(cbDDRefresh)
        end

        -------------------------------------------------------------------
        --  DISPLAY
        -------------------------------------------------------------------
        local displayHeader
        displayHeader, hgt = W:SectionHeader(hostFrame, "DISPLAY", posY)
        posY = posY - hgt
        posY = CludesUI.BlizzStyle.Note(hostFrame, posY, "cdmbars")

        -- Visibility: one control, the shared axis list plus the TBB-only Hide When
        -- Inactive row (single-lane, so it rides in as an extraItem). No mouseover for
        -- CDM-family bars; "Only In Combat" is the In Combat axis.
        local _, tbbVisH = CludesUI.BuildVisibilityRow(
            W,
            hostFrame,
            posY,
            {
                getStore = SelectedTBB,
                legacyKey = "barVisibility",
                caps = { partyIncludesRaid = false, noMouseover = true, luaDragonriding = true },
                onChanged = function()
                    RefreshTBB()
                end,
                onOptionChanged = function()
                    RefreshTBB()
                end,
                extraItems = {
                    {
                        key = "hideWhenInactive",
                        label = "Hide When Inactive",
                        tooltip = "Only show this bar while the tracked buff/cooldown is active. Unchecked keeps an empty bar on screen at all times.",
                        -- nil means ON everywhere this is read, so it cannot go through a
                        -- plain truthiness path.
                        get = function()
                            local bd = SelectedTBB()
                            return bd and bd.hideWhenInactive ~= false
                        end,
                        -- No refresh here: the row fires onOptionChanged after every write.
                        set = function(v)
                            local bd = SelectedTBB()
                            if not bd then
                                return
                            end
                            bd.hideWhenInactive = v
                        end,
                    },
                },
            },
            -- Show Icon moved up into the slot the Visibility Options dropdown left behind.
            {
                type = "dropdown",
                text = "Show Icon",
                values = { none = "None", left = "Left (Top)", right = "Right (Bottom)" },
                order = { "none", "left", "right" },
                getValue = function()
                    local bd = SelectedTBB()
                    return bd and bd.iconDisplay or "none"
                end,
                setValue = function(v)
                    local bd = SelectedTBB()
                    if not bd then
                        return
                    end
                    bd.iconDisplay = v
                    RefreshTBB()
                end,
            }
        )
        posY = posY - tbbVisH

        -- Opacity | Background Color (moved up from its old trailing half-row below)
        local iconRow
        iconRow, hgt = W:DualRow(hostFrame, posY, {
            type = "slider",
            text = "Opacity",
            min = 0,
            max = 100,
            step = 1,
            getValue = function()
                local bd = SelectedTBB()
                return bd and math.floor((bd.opacity or 1.0) * 100 + 0.5) or 100
            end,
            setValue = function(v)
                local bd = SelectedTBB()
                if not bd then
                    return
                end
                bd.opacity = v / 100
                RefreshTBB()
            end,
        }, {
            type = "multiSwatch",
            text = "Background Color",
            swatches = {
                GateBlizzardOnly("cdmbars", {
                    tooltip = "Background Color",
                    hasAlpha = true,
                    getValue = function()
                        local bd = SelectedTBB()
                        return (bd and bd.bgR or 0),
                            (bd and bd.bgG or 0),
                            (bd and bd.bgB or 0),
                            (bd and bd.bgA or 0.4)
                    end,
                    setValue = function(r, g, b, a)
                        local bd = SelectedTBB()
                        if not bd then
                            return
                        end
                        bd.bgR, bd.bgG, bd.bgB, bd.bgA = r, g, b, a
                        RefreshTBB()
                    end,
                }),
            },
        })
        posY = posY - hgt

        -- Fill Color (dropdown: auto/custom + gradient mode + 2 inline swatches) | Show Spark
        local fillRow
        fillRow, hgt = W:DualRow(
            hostFrame,
            posY,
            CludesUI.BlizzStyle.Gate("cdmbars", {
                type = "dropdown",
                text = "Fill Color",
                values = {
                    none = "Custom Color",
                    VERTICAL = "Vertical Gradient",
                    HORIZONTAL = "Horizontal Gradient",
                },
                order = { "none", "HORIZONTAL", "VERTICAL" },
                getValue = function()
                    local bd = SelectedTBB()
                    if not bd then
                        return "none"
                    end
                    -- Treat legacy "auto" as "custom" (no migration needed)
                    if not bd.gradientEnabled then
                        return "none"
                    end
                    return bd.gradientDir or "HORIZONTAL"
                end,
                setValue = function(v)
                    local bd = SelectedTBB()
                    if not bd then
                        return
                    end
                    bd.fillColorMode = "custom"
                    if v == "none" then
                        bd.gradientEnabled = false
                    else
                        bd.gradientEnabled = true
                        bd.gradientDir = v
                    end
                    RefreshTBB()
                    CludesUI:RefreshPage()
                end,
            }),
            {
                type = "toggle",
                text = "Show Spark",
                getValue = function()
                    local bd = SelectedTBB()
                    return bd and bd.showSpark
                end,
                setValue = function(v)
                    local bd = SelectedTBB()
                    if not bd then
                        return
                    end
                    bd.showSpark = v
                    RefreshTBB()
                end,
            }
        )
        posY = posY - hgt
        -- Inline swatches on Fill Color dropdown: fill color + gradient end color
        do
            local rgn = fillRow._leftRegion
            local ctrl = rgn._control

            -- Swatch 1 (rightmost, closer to dropdown): Fill Color
            local fillSwatch, updateFillSwatch = CludesUI.BuildColorSwatch(
                rgn,
                fillRow:GetFrameLevel() + 3,
                function()
                    local bd = SelectedTBB()
                    if not bd then
                        local _, castFrame = UnitClass("player")
                        local cc = RAID_CLASS_COLORS[castFrame]
                        return cc and cc.r or 1, cc and cc.g or 0.70, cc and cc.b or 0, 1
                    end
                    return bd.fillR, bd.fillG, bd.fillB, bd.fillA
                end,
                function(r, g, b, a)
                    local bd = SelectedTBB()
                    if not bd then
                        return
                    end
                    bd.fillColorMode = "custom"
                    bd.fillR, bd.fillG, bd.fillB, bd.fillA = r, g, b, a
                    RefreshTBB()
                end,
                true,
                20
            )
            Pix.Point(fillSwatch, "RIGHT", ctrl, "LEFT", -8, 0)

            -- Swatch 2 (left of swatch 1): Gradient End Color
            local gradSwatch, updateGradSwatch = CludesUI.BuildColorSwatch(
                rgn,
                fillRow:GetFrameLevel() + 3,
                function()
                    local bd = SelectedTBB()
                    if not bd then
                        return 0.20, 0.20, 0.80, 1
                    end
                    return bd.gradientR, bd.gradientG, bd.gradientB, bd.gradientA
                end,
                function(r, g, b, a)
                    local bd = SelectedTBB()
                    if not bd then
                        return
                    end
                    bd.gradientR, bd.gradientG, bd.gradientB, bd.gradientA = r, g, b, a
                    RefreshTBB()
                end,
                true,
                20
            )
            Pix.Point(gradSwatch, "RIGHT", fillSwatch, "LEFT", -4, 0)

            -- Disable block on fill swatch when Auto mode
            local fillBlock = CreateFrame("Frame", nil, fillSwatch)
            fillBlock:SetAllPoints()
            fillBlock:SetFrameLevel(fillSwatch:GetFrameLevel() + 10)
            fillBlock:EnableMouse(true)
            fillBlock:SetScript("OnEnter", function()
                CludesUI.ShowWidgetTooltip(
                    fillSwatch,
                    CludesUI.DisabledTooltip("This option requires Fill Color to be set to Custom")
                )
            end)
            fillBlock:SetScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)

            -- Disable block on gradient swatch when gradient is off or auto mode
            local gradBlock = CreateFrame("Frame", nil, gradSwatch)
            gradBlock:SetAllPoints()
            gradBlock:SetFrameLevel(gradSwatch:GetFrameLevel() + 10)
            gradBlock:EnableMouse(true)
            gradBlock:SetScript("OnEnter", function()
                local bd = SelectedTBB()
                local isAuto = false
                local msg = isAuto and "Set Fill Color to a Custom option"
                    or "This option requires a gradient to be set"
                CludesUI.ShowWidgetTooltip(gradSwatch, CludesUI.DisabledTooltip(msg))
            end)
            gradBlock:SetScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)

            local function UpdateSwatchStates()
                local bd = SelectedTBB()
                local isAuto = false
                -- Blizzard Style keeps the flat atlas fill, so the gradient end colour is inert there.
                local noGrad = not bd or not bd.gradientEnabled or CludesUI.BlizzStyle.Get("cdmbars")
                -- Fill swatch: disabled in auto mode
                if isAuto then
                    fillSwatch:SetAlpha(0.3)
                    fillBlock:Show()
                else
                    fillSwatch:SetAlpha(1)
                    fillBlock:Hide()
                end
                -- Grad swatch: disabled in auto mode OR when no gradient
                if isAuto or noGrad then
                    gradSwatch:SetAlpha(0.3)
                    gradBlock:Show()
                else
                    gradSwatch:SetAlpha(1)
                    gradBlock:Hide()
                end
            end
            CludesUI.RegisterWidgetRefresh(function()
                updateFillSwatch()
                updateGradSwatch()
                UpdateSwatchStates()
            end)
            UpdateSwatchStates()
        end

        -- Border Texture dropdown (+ inline offset cog) | empty
        do
            local texValues, texOrder = CludesUI.GetBorderTextureDropdown()
            local tbbBsRow
            tbbBsRow, hgt = W:DualRow(
                hostFrame,
                posY,
                CludesUI.BlizzStyle.Gate("cdmbars", {
                    type = "dropdown",
                    text = "Border Texture",
                    values = texValues,
                    order = texOrder,
                    getValue = function()
                        local bd = SelectedTBB()
                        return bd and bd.borderTexture or "solid"
                    end,
                    setValue = function(v)
                        local bd = SelectedTBB()
                        if not bd then
                            return
                        end
                        bd.borderTexture = v
                        bd.borderTextureOffset = nil
                        bd.borderTextureOffsetY = nil
                        bd.borderTextureShiftX = nil
                        bd.borderTextureShiftY = nil
                        local _bcol, _bbehind = CludesUI.GetBorderStyleSelectDefaults(v)
                        bd.borderR = _bcol.r
                        bd.borderG = _bcol.g
                        bd.borderB = _bcol.b
                        bd.borderBehind = _bbehind
                        local defSz = CludesUI.GetBorderDefaultSize("resourcebars", v)
                        if defSz then
                            bd.borderSize = defSz
                        end
                        if bd.borderSizePx then
                            bd.borderSizePx = false
                        end
                        RefreshTBB()
                        CludesUI:RefreshPage(true)
                    end,
                }),
                -- Classic WoW UI: the slot sizes the vanilla frame instead.
                (CludesUI.BlizzStyle.Active("cdmbars") == "classic")
                        and CludesUI.BlizzStyle.ClassicBorderSizeCfg(function()
                            local bd = SelectedTBB()
                            return bd and bd.stockBorderScale
                        end, function(v)
                            local bd = SelectedTBB()
                            if not bd then
                                return
                            end
                            bd.stockBorderScale = v
                            RefreshTBB()
                        end)
                    or CludesUI.BlizzStyle.Gate(
                        "cdmbars",
                        CludesUI.BorderPxSliderCfg({
                            text = "Border Size",
                            getStep = function()
                                local bd = SelectedTBB()
                                return bd and bd.borderSize or 0
                            end,
                            setStep = function(step)
                                local bd = SelectedTBB()
                                if bd then
                                    bd.borderSize = step
                                end
                            end,
                            getTex = function()
                                local bd = SelectedTBB()
                                return bd and bd.borderTexture or "solid"
                            end,
                            getPx = function()
                                local bd = SelectedTBB()
                                return bd and bd.borderSizePx
                            end,
                            setPx = function(v)
                                local bd = SelectedTBB()
                                if bd then
                                    bd.borderSizePx = v
                                end
                            end,
                            apply = function()
                                RefreshTBB()
                            end,
                        })
                    )
            )
            posY = posY - hgt
            -- Width Offset | Height Offset: the textured border's outward offsets,
            -- present only while a textured style is selected (built on the
            -- prebuild pass too, so the y advance is identical).
            do
                local bd0 = SelectedTBB()
                local tex0 = bd0 and bd0.borderTexture or "solid"
                if tex0 ~= "" and tex0 ~= "solid" then
                    local ocfgL, ocfgR = CludesUI.BorderOffsetRowCfgs({
                        addonKey = "resourcebars",
                        getTex = function()
                            local bd = SelectedTBB()
                            return bd and bd.borderTexture or "solid"
                        end,
                        getStep = function()
                            local bd = SelectedTBB()
                            return bd and bd.borderSize or 0
                        end,
                        getSizeKey = function()
                            local bd = SelectedTBB()
                            return bd and bd.borderSize or 0
                        end,
                        getPx = function()
                            local bd = SelectedTBB()
                            return bd and bd.borderSizePx
                        end,
                        getX = function()
                            local bd = SelectedTBB()
                            return bd and bd.borderTextureOffset
                        end,
                        setX = function(v)
                            local bd = SelectedTBB()
                            if bd then
                                bd.borderTextureOffset = v
                            end
                        end,
                        getY = function()
                            local bd = SelectedTBB()
                            return bd and bd.borderTextureOffsetY
                        end,
                        setY = function(v)
                            local bd = SelectedTBB()
                            if bd then
                                bd.borderTextureOffsetY = v
                            end
                        end,
                        apply = function()
                            RefreshTBB()
                        end,
                    })
                    _, hgt = W:DualRow(
                        hostFrame,
                        posY,
                        CludesUI.BlizzStyle.Gate("cdmbars", ocfgL),
                        CludesUI.BlizzStyle.Gate("cdmbars", ocfgR)
                    )
                    posY = posY - hgt
                end
            end
            -- Inline border color swatch on Border Size (right region); none
            -- under Classic WoW UI, whose slider sizes the vanilla frame.
            if CludesUI.BlizzStyle.Active("cdmbars") ~= "classic" then
                local rgn = tbbBsRow._rightRegion
                local ctrl = rgn._control
                local borderSwatch, updateBorderSwatch = CludesUI.BuildColorSwatch(
                    rgn,
                    tbbBsRow:GetFrameLevel() + 3,
                    function()
                        local bd = SelectedTBB()
                        return (bd and bd.borderR or 0), (bd and bd.borderG or 0), (bd and bd.borderB or 0)
                    end,
                    function(r, g, b)
                        local bd = SelectedTBB()
                        if not bd then
                            return
                        end
                        bd.borderR, bd.borderG, bd.borderB = r, g, b
                        RefreshTBB()
                    end,
                    false,
                    20
                )
                Pix.Point(borderSwatch, "RIGHT", ctrl, "LEFT", -8, 0)
                CludesUI.RegisterWidgetRefresh(function()
                    updateBorderSwatch()
                end)
                CludesUI.BlizzStyle.BlockInline("cdmbars", borderSwatch)
            end
            do
                local rgn = tbbBsRow._leftRegion
                local cogBtn = CludesUI.BuildInlineCog(rgn, {
                    title = "Border Options",
                    rows = {
                        {
                            type = "slider",
                            label = "Shift X",
                            min = -10,
                            max = 10,
                            step = 1,
                            get = function()
                                local bd = SelectedTBB()
                                if not bd then
                                    return 0
                                end
                                local v = bd.borderTextureShiftX
                                if v then
                                    return v
                                end
                                local _, _, dsx = CludesUI.GetBorderDefaults(
                                    "resourcebars",
                                    bd.borderTexture or "solid",
                                    bd.borderSize or 0
                                )
                                return dsx
                            end,
                            set = function(v)
                                local bd = SelectedTBB()
                                if not bd then
                                    return
                                end
                                bd.borderTextureShiftX = v == 0 and nil or v
                                RefreshTBB()
                            end,
                        },
                        {
                            type = "slider",
                            label = "Shift Y",
                            min = -10,
                            max = 10,
                            step = 1,
                            get = function()
                                local bd = SelectedTBB()
                                if not bd then
                                    return 0
                                end
                                local v = bd.borderTextureShiftY
                                if v then
                                    return v
                                end
                                local _, _, _, dsy = CludesUI.GetBorderDefaults(
                                    "resourcebars",
                                    bd.borderTexture or "solid",
                                    bd.borderSize or 0
                                )
                                return dsy
                            end,
                            set = function(v)
                                local bd = SelectedTBB()
                                if not bd then
                                    return
                                end
                                bd.borderTextureShiftY = v == 0 and nil or v
                                RefreshTBB()
                            end,
                        },
                        {
                            type = "toggle",
                            label = "Show Behind",
                            get = function()
                                local bd = SelectedTBB()
                                return bd and bd.borderBehind or false
                            end,
                            set = function(v)
                                local bd = SelectedTBB()
                                if not bd then
                                    return
                                end
                                bd.borderBehind = v == false and nil or v
                                RefreshTBB()
                            end,
                        },
                    },
                })
                if cogBtn then
                    local function UpdateCogVis()
                        local bd = SelectedTBB()
                        local tex = bd and bd.borderTexture or "solid"
                        cogBtn:SetShown(tex ~= "solid" and not CludesUI.BlizzStyle.Get("cdmbars"))
                    end
                    CludesUI.RegisterWidgetRefresh(UpdateCogVis)
                    UpdateCogVis()
                end
            end
        end

        -----------------------------------------------------------------------
        --  EXTRAS
        -----------------------------------------------------------------------
        _, hgt = W:SectionHeader(hostFrame, "EXTRAS", posY)
        posY = posY - hgt

        -- Row 1: Pandemic Glow (dropdown + swatch + cog + sync) | Stack Based
        -- Bar (buff bars only; page rebuilds on selection change, so cd/utility
        -- bars get a blank slot). Stack Based Bar is inert until Max Stacks is
        -- enabled below.
        do
            -- Shared glow controls over the bar's pandemic keys (the Glows page's
            -- Tracked Buff Bar descriptor, resolving the selected bar).
            local GO = CludesUI.GlowOptions
            local tbbDesc = mod._CDM_TbbGlowDesc(SelectedTBB, function()
                RefreshTBB()
            end)

            local bd0 = SelectedTBB()
            local rightSlot
            if bd0 and bd0.trackType ~= "cooldown" then
                rightSlot = {
                    type = "toggle",
                    text = "Stack Based Bar",
                    tooltip = "Fill this bar from current stacks out of Max Stacks instead of remaining time (requires Enable Max Stacks below).",
                    getValue = function()
                        local bd = SelectedTBB()
                        return bd and bd.stackBasedBar
                    end,
                    setValue = function(v)
                        local bd = SelectedTBB()
                        if not bd then
                            return
                        end
                        bd.stackBasedBar = v and true or false
                        RefreshTBB()
                    end,
                }
            else
                rightSlot = { type = "label", text = "" }
            end

            -- WoW Forever: the same row is the Anti-Clip Glow (CUI_CDM_ForeverAntiClip.lua).
            local antiClip = mod.CDM_ANTI_CLIP
            local tbbPanRow
            tbbPanRow, hgt = W:DualRow(
                hostFrame,
                posY,
                GO.DropdownSpec(
                    tbbDesc,
                    antiClip and "Anti-Clip Glow" or "Pandemic Glow",
                    antiClip
                            and "Show a glow on the bar when casting the spell next, after your current cast or global cooldown, won't clip it"
                        or "Show a glow on the bar when the remaining duration is in the pandemic window (last 30%)"
                ),
                rightSlot
            )
            posY = posY - hgt
            GO.AttachInline(tbbPanRow._leftRegion, tbbDesc)

            -- Apply All
            if CludesUI.BuildSyncIcon and CludesUI.ApplyPandemicGlowToAll then
                CludesUI.BuildSyncIcon({
                    region = tbbPanRow._leftRegion,
                    tooltip = antiClip
                            and "Apply this glow's look to the Nameplates Pandemic Glow, all CDM bars, and other tracking bars. A surface that can't show a style uses its closest match."
                        or "Apply this pandemic glow to Nameplates, all CDM bars, and other tracking bars. A surface that can't show a style uses its closest match.",
                    isSynced = function()
                        local source = SelectedTBB()
                        if not source then
                            return true
                        end
                        return CludesUI.IsPandemicGlowSyncedToAll(
                            CludesUI.PandemicPayloadFromRectBar(source),
                            { skipTbbBar = source }
                        )
                    end,
                    onClick = function()
                        local source = SelectedTBB()
                        if not source then
                            return
                        end
                        CludesUI.ApplyPandemicGlowToAll(
                            CludesUI.PandemicPayloadFromRectBar(source),
                            { skipTbbBar = source }
                        )
                        RefreshTBB()
                    end,
                })
            end
        end

        -- Row 2: Enable Max Stacks (toggle + inline slider) | Ticks at Stacks (label + inline input)
        local function maxStacksOff()
            local bd = SelectedTBB()
            return not bd or not bd.stackThresholdMaxEnabled
        end
        local maxStacksRow
        maxStacksRow, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Enable Max Stacks",
            getValue = function()
                local bd = SelectedTBB()
                return bd and bd.stackThresholdMaxEnabled
            end,
            setValue = function(v)
                local bd = SelectedTBB()
                if not bd then
                    return
                end
                bd.stackThresholdMaxEnabled = v
                RefreshTBB()
                CludesUI:RefreshPage()
            end,
        }, {
            type = "label",
            text = "Ticks at Stacks",
            tooltip = "Comma separated stack counts to put a tick mark at. Type all to mark every stack.",
        })
        posY = posY - hgt
        -- Inline slider on Enable Max Stacks toggle (same as inline swatch positioning)
        do
            local rgn = maxStacksRow._leftRegion
            local ctrl = rgn._control
            local SL = CludesUI.SL or {}
            local trackFrame, valBox, _, slThumb = CludesUI.BuildSliderCore(
                rgn,
                90,
                4,
                14,
                36,
                26,
                13,
                SL.INPUT_A or 0.6,
                1,
                100,
                1,
                function()
                    local bd = SelectedTBB()
                    return bd and bd.stackThresholdMax or 10
                end,
                function(v)
                    local bd = SelectedTBB()
                    if bd then
                        bd.stackThresholdMax = v
                        RefreshTBB()
                    end
                end,
                true
            )
            Pix.Point(valBox, "RIGHT", ctrl, "LEFT", -6, 0)
            Pix.Point(trackFrame, "RIGHT", valBox, "LEFT", -8, 0)
            -- Disable block
            local block = CreateFrame("Frame", nil, trackFrame)
            block:SetPoint("TOPLEFT", trackFrame, "TOPLEFT", -4, 4)
            block:SetPoint("BOTTOMRIGHT", valBox, "BOTTOMRIGHT", 4, -4)
            block:SetFrameLevel(trackFrame:GetFrameLevel() + 10)
            block:EnableMouse(true)
            block:SetScript("OnEnter", function()
                CludesUI.ShowWidgetTooltip(trackFrame, CludesUI.DisabledTooltip("Max Stacks"))
            end)
            block:SetScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)
            local function UpdateMaxSliderState()
                local off = maxStacksOff()
                trackFrame:SetAlpha(off and 0.3 or 1)
                valBox:SetAlpha(off and 0.3 or 1)
                valBox:EnableMouse(not off)
                if slThumb then
                    slThumb._sliderDisabled = off
                end
                if off then
                    block:Show()
                else
                    block:Hide()
                end
            end
            CludesUI.RegisterWidgetRefresh(UpdateMaxSliderState)
            UpdateMaxSliderState()
        end
        -- Add "(Ex: 1,5,8)" suffix in smaller, dimmer text
        do
            local ticksLabel = maxStacksRow._rightRegion and maxStacksRow._rightRegion._label
            if ticksLabel then
                local suffix = maxStacksRow._rightRegion:CreateFontString(nil, "OVERLAY")
                suffix:SetFont(CludesUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF", 11, "")
                suffix:SetTextColor(1, 1, 1, 0.35)
                suffix:SetPoint("LEFT", ticksLabel, "RIGHT", 5, 0)
                suffix:SetText(CludesUI.L("(Ex: 1,5,8)"))
            end
        end
        -- Inline input on Ticks at Stacks (matches slider value box style)
        do
            local rgn = maxStacksRow._rightRegion
            local SIDE_PAD = 20
            local FONT = CludesUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF"
            local INPUT_W = 70
            local INPUT_H = 26

            local box = CreateFrame("EditBox", nil, rgn)
            Pix.Size(box, INPUT_W, INPUT_H)
            Pix.Point(box, "RIGHT", rgn, "RIGHT", -SIDE_PAD, 0)
            box:SetFrameLevel(rgn:GetFrameLevel() + 2)
            box:SetAutoFocus(false)
            box:SetJustifyH("CENTER")
            box:SetFont(FONT, 13, "")
            box:SetTextColor(
                CludesUI.TEXT_DIM_R or 0.75,
                CludesUI.TEXT_DIM_G or 0.75,
                CludesUI.TEXT_DIM_B or 0.75,
                CludesUI.TEXT_DIM_A or 1
            )
            -- Background matching slider input box
            local backdrop = box:CreateTexture(nil, "BACKGROUND")
            backdrop:SetAllPoints()
            backdrop:SetColorTexture(
                CludesUI.SL_INPUT_R or 0.08,
                CludesUI.SL_INPUT_G or 0.08,
                CludesUI.SL_INPUT_B or 0.08,
                (CludesUI.SL_INPUT_A or 0.5) + (CludesUI.MW_INPUT_ALPHA_BOOST or 0.15)
            )
            -- Border matching slider input box (rounded, as its value box is)
            CludesUI.MakeRoundedBorder(
                box,
                CludesUI.BORDER_R,
                CludesUI.BORDER_G,
                CludesUI.BORDER_B,
                CludesUI.SL_INPUT_BRD_A,
                backdrop
            )

            box:SetScript("OnEnterPressed", function(self)
                self:ClearFocus()
                local bd = SelectedTBB()
                if bd then
                    bd.stackThresholdTicks = self:GetText()
                    RefreshTBB()
                end
            end)
            box:SetScript("OnEscapePressed", function(self)
                self:ClearFocus()
                local bd = SelectedTBB()
                self:SetText(bd and bd.stackThresholdTicks or "")
            end)

            -- Inline swatch for tick mark color (left of the input box)
            local tickSwatch, updateTickSwatch = CludesUI.BuildColorSwatch(
                rgn,
                box:GetFrameLevel() + 1,
                function()
                    local bd = SelectedTBB()
                    if not bd then
                        return 1, 1, 1, 1
                    end
                    local a = bd.stackThresholdTickA
                    if a == nil then
                        a = 1
                    end
                    return bd.stackThresholdTickR or 1,
                        bd.stackThresholdTickG or 1,
                        bd.stackThresholdTickB or 1,
                        a
                end,
                function(r, g, b, a)
                    local bd = SelectedTBB()
                    if not bd then
                        return
                    end
                    bd.stackThresholdTickR, bd.stackThresholdTickG = r, g
                    bd.stackThresholdTickB, bd.stackThresholdTickA = b, a
                    RefreshTBB()
                end,
                true,
                20
            )
            Pix.Point(tickSwatch, "RIGHT", box, "LEFT", -8, 0)
            local tickBlock = CreateFrame("Frame", nil, tickSwatch)
            tickBlock:SetAllPoints()
            tickBlock:SetFrameLevel(tickSwatch:GetFrameLevel() + 10)
            tickBlock:EnableMouse(true)
            tickBlock:SetScript("OnEnter", function()
                CludesUI.ShowWidgetTooltip(tickSwatch, CludesUI.DisabledTooltip("Max Stacks"))
            end)
            tickBlock:SetScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)

            local function UpdateTicksInput()
                local bd = SelectedTBB()
                box:SetText(bd and bd.stackThresholdTicks or "")
                local off = maxStacksOff()
                box:SetAlpha(off and 0.3 or 1)
                box:EnableMouse(not off)
                if off then
                    tickSwatch:SetAlpha(0.3)
                    tickBlock:Show()
                else
                    tickSwatch:SetAlpha(1)
                    tickBlock:Hide()
                end
                if updateTickSwatch then
                    updateTickSwatch()
                end
            end
            CludesUI.RegisterWidgetRefresh(UpdateTicksInput)
            UpdateTicksInput()
        end

        -- Row 3: Enable Stack Threshold (toggle + inline swatch) | Stack Threshold (slider)
        local threshRow
        threshRow, hgt = W:DualRow(hostFrame, posY, {
            type = "toggle",
            text = "Enable Stack Threshold",
            tooltip = "This will change the color of your bar if you have more than your chosen number of stacks",
            getValue = function()
                local bd = SelectedTBB()
                return bd and bd.stackThresholdEnabled
            end,
            setValue = function(v)
                local bd = SelectedTBB()
                if not bd then
                    return
                end
                bd.stackThresholdEnabled = v
                RefreshTBB()
                CludesUI:RefreshPage()
            end,
        }, {
            type = "slider",
            text = "Stack Threshold",
            min = 0,
            max = 100,
            step = 1,
            disabled = function()
                local bd = SelectedTBB()
                if not bd or not bd.stackThresholdEnabled then
                    return true
                end
                return bd.stackThresholdMulti and true or false
            end,
            disabledTooltip = function()
                local bd = SelectedTBB()
                if bd and bd.stackThresholdEnabled and bd.stackThresholdMulti then
                    return StackThreshReplacesTip()
                end
                return CludesUI.DisabledTooltip("Stack Threshold")
            end,
            rawTooltip = true,
            getValue = function()
                local bd = SelectedTBB()
                return bd and bd.stackThreshold or 5
            end,
            setValue = function(v)
                local bd = SelectedTBB()
                if not bd then
                    return
                end
                bd.stackThreshold = v
                RefreshTBB()
            end,
        })
        posY = posY - hgt
        -- Inline swatch on Enable Stack Threshold toggle
        do
            local rgn = threshRow._leftRegion
            local ctrl = rgn._control
            -- Cog: opens the multi-threshold editor. Stays usable while multi is
            -- on, since it is the only way back out of it.
            CludesUI.BuildInlineCog(rgn, {
                show = function(self)
                    ShowStackThreshEditor({
                        getCfg = SelectedTBB,
                        refreshFn = RefreshTBB,
                        anchor = self,
                    })
                end,
                tip = StackThreshHelpTip(),
                disabled = function()
                    local bd = SelectedTBB()
                    return not (bd and bd.stackThresholdEnabled)
                end,
                disabledTooltip = "Stack Threshold",
            })

            local threshSwatch, updateThreshSwatch = CludesUI.BuildColorSwatch(
                rgn,
                threshRow:GetFrameLevel() + 3,
                function()
                    local bd = SelectedTBB()
                    if not bd then
                        return 0.8, 0.1, 0.1, 1
                    end
                    return bd.stackThresholdR or 0.8,
                        bd.stackThresholdG or 0.1,
                        bd.stackThresholdB or 0.1,
                        bd.stackThresholdA or 1
                end,
                function(r, g, b, a)
                    local bd = SelectedTBB()
                    if not bd then
                        return
                    end
                    bd.stackThresholdR, bd.stackThresholdG, bd.stackThresholdB, bd.stackThresholdA =
                        r, g, b, a
                    RefreshTBB()
                end,
                true,
                20
            )
            Pix.Point(threshSwatch, "RIGHT", rgn._lastInline or ctrl, "LEFT", -8, 0)
            rgn._lastInline = threshSwatch
            local threshBlock = CreateFrame("Frame", nil, threshSwatch)
            threshBlock:SetAllPoints()
            threshBlock:SetFrameLevel(threshSwatch:GetFrameLevel() + 10)
            threshBlock:EnableMouse(true)
            threshBlock:SetScript("OnEnter", function()
                local bd = SelectedTBB()
                if bd and bd.stackThresholdEnabled and bd.stackThresholdMulti then
                    CludesUI.ShowWidgetTooltip(threshSwatch, StackThreshReplacesTip())
                    return
                end
                CludesUI.ShowWidgetTooltip(threshSwatch, CludesUI.DisabledTooltip("Stack Threshold"))
            end)
            threshBlock:SetScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)

            local function UpdateThreshSwatchState()
                local bd = SelectedTBB()
                local enabled = bd and bd.stackThresholdEnabled
                -- The swatch edits the single threshold color, so multi masks it
                -- the same way it masks the slider.
                local off = not enabled or (bd.stackThresholdMulti and true or false)
                if off then
                    threshSwatch:SetAlpha(0.3)
                    threshBlock:Show()
                else
                    threshSwatch:SetAlpha(1)
                    threshBlock:Hide()
                end
            end
            CludesUI.RegisterWidgetRefresh(function()
                updateThreshSwatch()
                UpdateThreshSwatchState()
            end)
            UpdateThreshSwatchState()
        end

        -- Preview click-navigation map: preview element -> section + row.
        -- Resolved at click time by NavigateToSetting.
        hostFrame._tbbClickTargets = {
            barFill = { section = displayHeader, target = fillRow, slotSide = "left" },
            icon = { section = displayHeader, target = iconRow, slotSide = "left" },
            nameText = { section = layoutHeader, target = nameRow, slotSide = "left" },
            timerText = { section = layoutHeader, target = nameRow, slotSide = "right" },
            stacksText = { section = layoutHeader, target = stacksRow, slotSide = "left" },
        }

        -- Ensure bar frames exist before showing placeholders
        mod.BuildTrackedBuffBars()
        UpdateTBBPlaceholder()
        RefreshTBBPopout()
        return math.abs(posY)
    end

    return BuildBuffBarsPage, RefreshTBBPopout
end

-- Used by CUI_CooldownManager_Options.lua
mod.CDMO_InitBuffBarsPage = InitBuffBarsPage
