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

    -- The popout (made once): dark box, title on top, hint at the foot.
    local function GetTBBPopout()
        if _tbbPopout then
            return _tbbPopout
        end
        local box = CreateFrame("Frame", nil, UIParent)
        box:SetFrameStrata("FULLSCREEN_DIALOG")
        box:SetFrameLevel(10)
        box:SetClampedToScreen(true)
        box:Hide()
        local backdrop = box:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(0, 0, 0, 0.9)
        local function Line(size, point, y, alpha)
            local fs = box:CreateFontString(nil, "OVERLAY")
            fs:SetFont(FONT_PATH, size, GetCDMOptOutline())
            fs:SetPoint(point, box, point, 0, y)
            fs:SetTextColor(1, 1, 1, alpha)
            return fs
        end
        box._title = Line(13, "TOP", -7, 0.9)
        box._hint = Line(10, "BOTTOM", 7, 0.4)
        _tbbPopout = box
        return box
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
        if button then
            return button
        end
        button = CreateFrame("Button", nil, wrap)
        local green = CludesUI.CLUDES_GREEN
        button._brd = Pix.CreateBorder(button, green.r, green.g, green.b, 1, 2, "OVERLAY", 7)
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
        return button
    end

    local function HideTBBPvNav(wrap)
        for _, b in pairs(wrap._pvNav or {}) do
            b:Hide()
        end
    end

    -- A text overlay hugs where the glyphs draw: the string's own size (at least
    -- 14 square) anchored by its justification, as a FontString is wider than
    -- its string, so its CENTER is not where the glyphs are.
    local TEXT_NAV_SIDE = { RIGHT = { "RIGHT", 2 }, CENTER = { "CENTER", 0 }, LEFT = { "LEFT", -2 } }
    local function FitToText(button, text)
        button:SetSize(
            math.max(14, (text:GetStringWidth() or 0) + 6),
            math.max(14, (text:GetStringHeight() or 0) + 6)
        )
        local side = TEXT_NAV_SIDE[text.GetJustifyH and text:GetJustifyH() or "LEFT"] or TEXT_NAV_SIDE.LEFT
        button:SetPoint(side[1], text, side[1], side[2], 0)
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
        local function Overlay(key, elem, isText)
            if
                not (elem and elem.IsShown and elem:IsShown()) or (isText and (elem:GetText() or "") == "")
            then
                return
            end
            local button = TBBPvNavButton(wrap, key)
            button:ClearAllPoints()
            if isText then
                FitToText(button, elem)
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
        Overlay("barFill", wrap._bar, false)
        Overlay("icon", wrap._icon, false)
        Overlay("nameText", wrap._nameText, true)
        Overlay("timerText", wrap._timerText, true)
        Overlay("stacksText", wrap._stacksText, true)
    end

    -- A bar's icon: its popular preset's, else its spell's.
    local function ConfIcon(conf)
        if conf.popularKey and mod.TBB_POPULAR_BUFFS then
            for _, entry in ipairs(mod.TBB_POPULAR_BUFFS) do
                if entry.key == conf.popularKey then
                    return entry.icon
                end
            end
        end
        if conf.spellID and conf.spellID > 0 then
            local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(conf.spellID)
            return info and info.iconID
        end
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
        -- Live bars show their stacks from the tick; the preview follows the setting.
        local stacks = wrap._stacksText
        if stacks then
            local on = (conf.stacksPosition or "center") ~= "none"
            if on then
                stacks:SetText("3")
            end
            stacks:SetShown(on)
        end
        local unassigned = (not conf.spellID or conf.spellID == 0) and not conf.glowBased
        -- The name as the live build resolves it; a custom name is the player's
        -- own text, shown as typed and never translated.
        local nameText = wrap._nameText
        if nameText and nameText:IsShown() then
            local name = conf.name
            if (not name or name == "" or name == "New Bar") and conf.spellID and conf.spellID > 0 then
                local details = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(conf.spellID)
                name = (details and details.name) or name
            end
            if unassigned then
                name = ""
            end
            nameText:SetText(mod.TBBCustomName(conf) or CludesUI.L(name or ""))
        end
        local icon = wrap._icon
        if icon and icon:IsShown() and icon._tex then
            icon._tex:SetTexture(ConfIcon(conf) or 134400) -- the question mark with no buff yet
        end
        -- Unassigned: all the bar's content dims under a black layer with a centred
        -- hint, above the text overlay (+6) and border (+5), below the click overlays (+30).
        if not wrap._pvDarkFrame then
            local dark = CreateFrame("Frame", nil, wrap)
            dark:SetAllPoints(wrap)
            local tex = dark:CreateTexture(nil, "ARTWORK")
            tex:SetAllPoints()
            tex:SetColorTexture(0, 0, 0, 0.6)
            local hint = dark:CreateFontString(nil, "OVERLAY")
            hint:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            hint:SetTextColor(1, 1, 1, 1)
            hint:SetJustifyH("CENTER")
            hint:SetText(CludesUI.L("Choose a buff from the bar menu"))
            wrap._pvDarkFrame, wrap._pvHint = dark, hint
        end
        wrap._pvDarkFrame:SetFrameLevel(wrap:GetFrameLevel() + 20)
        wrap._pvHint:ClearAllPoints()
        wrap._pvHint:SetPoint("CENTER", scrollBar, "CENTER", 0, 0)
        wrap._pvDarkFrame:SetShown(unassigned)
    end

    -- A text's position as drawn (prefix name / timer / stacks): the stored one,
    -- else an older bar's default; name text never draws on a vertical bar.
    local function ConfTextPos(conf, prefix)
        if prefix == "name" and conf.verticalOrientation then
            return "none"
        end
        local stored = conf[prefix .. "Position"]
        if stored then
            return stored
        end
        if prefix == "name" then
            return (conf.showName ~= false) and "left" or "none"
        elseif prefix == "timer" then
            return conf.showTimer and "right" or "none"
        end
        return "center"
    end
    -- Headroom for the texts anchored above or below the bar (outside its bounds).
    local function TBBPvTextPad(conf, side)
        local tallest = 0
        for _, prefix in ipairs({ "timer", "stacks", "name" }) do
            if ConfTextPos(conf, prefix) == side then
                tallest = math.max(tallest, conf[prefix .. "Size"] or 11)
            end
        end
        return tallest > 0 and (tallest + 8) or 0
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

    -- A preview bar's layers after its strata lift, as the live bars stack them:
    -- [field] = { offset, from the bar fill (true) or the base level }.
    local PREVIEW_LAYERS = {
        { "_gradClip", 1, true },
        { "_chargeHashFillClip", 1, true },
        { "_sparkOverlay", 3, true },
        { "_tickOverlay", 4, true },
        { "_chargeHashOverlay", 5, true },
        -- base+6 matches the live-bar reassert: keeps the border above the tick
        -- overlay (fill+4 = base+5), which wins ties via lazy creation.
        { "_barBorder", 6, false },
        { "_pandemicGlowOverlay", 7, false },
        { "_textOverlay", 7, true },
    }
    -- The apply path pins a wrap to the bar's own strata (cfg.strata, MEDIUM
    -- default): lift it into the popout's after each apply and set its child
    -- levels again (a parent strata change resets them). Skipped while it is
    -- already there, level included (else a bar whose own strata is the
    -- popout's would dodge the lift).
    local function LiftPreviewBar(wrap, base)
        if wrap:GetFrameStrata() == "FULLSCREEN_DIALOG" and wrap:GetFrameLevel() == base then
            return
        end
        wrap:SetFrameStrata("FULLSCREEN_DIALOG")
        wrap:SetFrameLevel(base)
        local fill = wrap._bar
        if fill then
            fill:SetFrameLevel(base + 1)
        end
        for _, layer in ipairs(PREVIEW_LAYERS) do
            local frame, fromFill = wrap[layer[1]], layer[3]
            if frame and (fill or not fromFill) then
                frame:SetFrameLevel((fromFill and fill:GetFrameLevel() or base) + layer[2])
            end
            -- The threshold shades sit between the clips and the spark (fill+2).
            if layer[1] == "_chargeHashFillClip" and wrap._threshOverlays and fill then
                for i = 1, #wrap._threshOverlays do
                    local shade = wrap._threshOverlays[i]
                    if shade then
                        shade:SetFrameLevel(fill:GetFrameLevel() + 2)
                    end
                end
            end
        end
    end

    -- Width-gated geometry (charge hash lines, threshold ticks) is skipped while a
    -- bar's fill has no size; live bars redraw it from the timer tick, previews
    -- have none, so they redraw it when the size resolves.
    local function DrawSizedParts(wrap, fill, conf, withHash)
        if withHash and mod.ApplyTBBChargeHashLines then
            mod.ApplyTBBChargeHashLines(wrap, conf, mod.GetTBBMaxCharges and mod.GetTBBMaxCharges(conf))
        end
        if mod.ApplyTBBTickMarks then
            mod.ApplyTBBTickMarks(fill, conf, wrap._threshTicks, conf.verticalOrientation, wrap._tickOverlay)
            wrap._ticksDirty = nil
        end
    end
    local function PreviewBar(oc, num)
        local wrap = _tbbPopoutBars[num]
        if wrap then
            return wrap
        end
        wrap = mod.CreateTBBBarFrame(oc, "Pv" .. num)
        _tbbPopoutBars[num] = wrap
        if wrap._bar then
            wrap._bar:SetScript("OnSizeChanged", function(fill)
                if wrap._pvCfg then
                    DrawSizedParts(wrap, fill, wrap._pvCfg, true)
                end
            end)
        end
        return wrap
    end

    -- What the popout shows: the selected group's members, or the selected bar.
    local function PopoutEntries()
        local barList = (mod.GetTrackedBuffBars() or {}).bars or {}
        local entries = {}
        if _tbbSelectedGroup then
            for i, c in ipairs(barList) do
                if mod.TBBBarGroupID(c) == _tbbSelectedGroup then
                    entries[#entries + 1] = { idx = i, cfg = c }
                end
            end
            return entries, "group"
        end
        local c = barList[_tbbSelectedBar]
        if c then
            entries[1] = { idx = _tbbSelectedBar, cfg = c }
        end
        return entries, "bar"
    end

    -- Where the first bar sits and how the rest chain on it, as the live bars do.
    local CHAIN = {
        UP = { "BOTTOM", "TOP", 0, 1 },
        RIGHT = { "LEFT", "RIGHT", 1, 0 },
        LEFT = { "RIGHT", "LEFT", -1, 0 },
        DOWN = { "TOP", "BOTTOM", 0, -1 },
    }

    local function RefreshTBBPopout()
        if not TBBPreviewAllowed() then
            HideTBBPopout()
            return
        end
        local entries, mode = PopoutEntries()
        if #entries == 0 then
            HideTBBPopout()
            return
        end
        local oc = GetTBBPopout()
        local grouped = mode == "group"

        -- Each preview bar through the LIVE bar code, then the preview dressing.
        for num, entry in ipairs(entries) do
            local wrap = PreviewBar(oc, num)
            wrap._pvCfg = entry.cfg
            mod.ApplyTBBBarSettings(wrap, entry.cfg)
            LiftPreviewBar(wrap, oc:GetFrameLevel() + 20)
            DressTBBPopoutBar(wrap, entry.cfg)
            -- A reused pool bar is already sized, so its OnSizeChanged may never
            -- fire: take the deferred tick pass here (the apply drew hash lines).
            local fill = wrap._bar
            if wrap._ticksDirty and fill and fill:GetWidth() > 0 and mod.ApplyTBBTickMarks then
                DrawSizedParts(wrap, fill, entry.cfg, false)
            end
            wrap:Show()
        end
        for num = #entries + 1, #_tbbPopoutBars do
            local wrap = _tbbPopoutBars[num]
            if wrap then
                HideTBBPvNav(wrap)
                wrap:Hide()
            end
        end

        -- Size: one bar alone, or the group chained with its grow and spacing.
        local PAD_IN, TITLE_H = 20, 25
        local growDir, spacing = "DOWN", 2
        if grouped then
            growDir = (mod.TBBGroupGrow(_tbbSelectedGroup) or "DOWN"):upper()
            spacing = mod.TBBGroupSpacing(_tbbSelectedGroup) or 2
        end
        local across = grouped and (growDir == "LEFT" or growDir == "RIGHT")
        local totalW, totalH = 0, 0
        local topPad, botPad = 0, 0
        for num, entry in ipairs(entries) do
            local wrap = _tbbPopoutBars[num]
            local w, h = wrap:GetWidth(), wrap:GetHeight()
            local gap = num > 1 and spacing or 0
            if not grouped then
                totalW, totalH = w, h
            elseif across then
                totalW, totalH = totalW + w + gap, math.max(totalH, h)
            else
                totalW, totalH = math.max(totalW, w), totalH + h + gap
            end
            topPad = math.max(topPad, TBBPvTextPad(entry.cfg, "top"))
            botPad = math.max(botPad, TBBPvTextPad(entry.cfg, "bottom"))
        end

        -- The foot hint: element clicks in bar mode (until dismissed), bar clicks in a group.
        local hintH = 18
        if grouped then
            oc._hint:SetText(CludesUI.L("Click a bar to edit it"))
            oc._hint:Show()
        elseif not (CludesUIDB and CludesUIDB.previewHintDismissed) then
            oc._hint:SetText(CludesUI.L("Click elements to scroll to and highlight their options"))
            oc._hint:Show()
        else
            oc._hint:Hide()
            hintH = 0
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
        local chain = CHAIN[growDir] or CHAIN.DOWN
        local prev
        for num = 1, #entries do
            local wrap = _tbbPopoutBars[num]
            wrap:ClearAllPoints()
            if num > 1 then
                wrap:SetPoint(chain[1], prev, chain[2], chain[3] * spacing, chain[4] * spacing)
            elseif grouped and growDir == "UP" then
                wrap:SetPoint(
                    "BOTTOMLEFT",
                    oc,
                    "BOTTOMLEFT",
                    Px((ocW - wrap:GetWidth()) / 2),
                    Px(PAD_IN + botPad + hintH)
                )
            elseif grouped and growDir == "RIGHT" then
                wrap:SetPoint("TOPLEFT", oc, "TOPLEFT", Px(PAD_IN), firstY)
            elseif grouped and growDir == "LEFT" then
                wrap:SetPoint("TOPRIGHT", oc, "TOPRIGHT", -Px(PAD_IN), firstY)
            else
                -- Centred bars sit on a whole-pixel left edge too.
                wrap:SetPoint("TOPLEFT", oc, "TOPLEFT", Px((ocW - wrap:GetWidth()) / 2), firstY)
            end
            prev = wrap
            UpdateTBBPvNav(wrap, mode, entries[num].idx)
        end

        local title = CludesUI.L("Preview")
        if grouped then
            local name = (mod.TBBGroupName and mod.TBBGroupName(_tbbSelectedGroup))
                or (CludesUI.L("Group") .. " " .. _tbbSelectedGroup)
            title = name .. " " .. title
        end
        oc._title:SetText(title)

        -- Dock to the left edge of the options panel, vertically centered, its
        -- corner nudged onto a whole pixel (the panel may sit anywhere).
        oc:ClearAllPoints()
        oc:Show()
        local scrollFrame = CludesUI._scrollFrame
        if not scrollFrame then
            oc:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            return
        end
        local dy = oc:GetHeight() / 2
        oc:SetPoint("TOPRIGHT", scrollFrame, "LEFT", 0, dy)
        local right, topY = oc:GetRight(), oc:GetTop()
        if right and topY then
            oc:SetPoint("TOPRIGHT", scrollFrame, "LEFT", Px(right) - right, dy + Px(topY) - topY)
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

    -- A popup line of text in the CDM options font.
    local function PopupText(parent, size, r, g, b, a, text, layer)
        local fs = parent:CreateFontString(nil, layer or "OVERLAY")
        fs:SetFont(FONT_PATH, size, GetCDMOptOutline())
        fs:SetTextColor(r, g, b, a)
        fs:SetText(text)
        return fs
    end
    -- A labelled number box (digits only, a grey example while empty) under anchor.
    local function NumberField(dialog, label, example, maxLetters, anchor, relPoint, x, y)
        local caption = PopupText(dialog, 11, 0.7, 0.7, 0.7, 1, CludesUI.L(label))
        caption:SetPoint("TOPLEFT", anchor, relPoint, x, y)
        local box = CreateFrame("EditBox", nil, dialog)
        box:SetSize(180, 28)
        box:SetPoint("TOPLEFT", caption, "BOTTOMLEFT", 0, -4)
        box:SetAutoFocus(false)
        box:SetNumeric(true)
        box:SetMaxLetters(maxLetters)
        box:SetFont(FONT_PATH, 13, GetCDMOptOutline())
        box:SetTextColor(1, 1, 1, 0.9)
        box:SetJustifyH("LEFT")
        local bg = box:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.060, 0.049, 0.037, 1)
        CludesUI.MakeRoundedBorder(box, 1, 1, 1, 0.12, bg)
        local hint = PopupText(box, 12, 0.5, 0.5, 0.5, 0.5, CludesUI.L(example), "ARTWORK")
        hint:SetPoint("LEFT", box, "LEFT", 4, 0)
        box:SetScript("OnTextChanged", function(self)
            hint:SetShown(self:GetText() == "")
        end)
        return box
    end
    -- A small popup button (Add, Cancel): its fill and border, its label lighting on hover.
    local function PopupButton(dialog, text, point, x, fill, border, labelColour)
        local button = CreateFrame("Button", nil, dialog)
        button:SetSize(80, 28)
        button:SetPoint(point, dialog, "BOTTOM", x, 16)
        local bg = button:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(unpack(fill))
        CludesUI.MakeRoundedBorder(button, border[1], border[2], border[3], border[4], bg)
        local label = PopupText(
            button,
            12,
            labelColour[1],
            labelColour[2],
            labelColour[3],
            labelColour[4],
            CludesUI.L(text)
        )
        label:SetPoint("CENTER")
        button:SetScript("OnEnter", function()
            label:SetTextColor(1, 1, 1, 1)
        end)
        button:SetScript("OnLeave", function()
            label:SetTextColor(unpack(labelColour))
        end)
        return button
    end

    -- The "Custom Buff ID" popup (made once): a dimmed screen, Spell ID and
    -- Duration boxes, a status line, Add and Cancel; Escape closes it.
    local CUSTOM_POPUP = "CUI_TBB_CustomBuffPopup"
    local function CustomBuffPopup()
        local dialog = _G[CUSTOM_POPUP]
        if dialog then
            return dialog
        end
        local dimmer = CreateFrame("Frame", CUSTOM_POPUP .. "Dimmer", UIParent)
        dimmer:SetFrameStrata("FULLSCREEN_DIALOG")
        dimmer:SetAllPoints(UIParent)
        dimmer:EnableMouse(true)
        dimmer:Hide()
        local shade = dimmer:CreateTexture(nil, "BACKGROUND")
        shade:SetAllPoints()
        shade:SetColorTexture(0, 0, 0, 0.25)

        dialog = CreateFrame("Frame", CUSTOM_POPUP, dimmer)
        dialog:SetSize(320, 210)
        dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
        dialog:SetFrameStrata("FULLSCREEN_DIALOG")
        dialog:SetFrameLevel(dimmer:GetFrameLevel() + 10)
        dialog:EnableMouse(true)
        local bg = dialog:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.062, 0.070, 0.082, 1)
        CludesUI.MakeRoundedBorder(dialog, 1, 1, 1, 0.15, bg)
        PopupText(dialog, 14, 1, 1, 1, 1, CludesUI.L("Custom Buff ID")):SetPoint("TOP", dialog, "TOP", 0, -18)

        dialog._sidBox = NumberField(dialog, "Spell ID", "e.g. 12345", 7, dialog, "TOPLEFT", 24, -52)
        dialog._durBox =
            NumberField(dialog, "Duration (seconds)", "e.g. 30", 5, dialog._sidBox, "BOTTOMLEFT", 0, -12)
        local status = PopupText(dialog, 11, 1, 0.3, 0.3, 1, "")
        status:SetPoint("TOP", dialog._durBox, "BOTTOM", 0, -6)
        dialog._status = status

        local ar, ag, ab = CludesUI.GetAccentColor()
        dialog._addBtn = PopupButton(
            dialog,
            "Add",
            "BOTTOMRIGHT",
            -4,
            { ar, ag, ab, 0.15 },
            { ar, ag, ab, 0.3 },
            { ar, ag, ab, 0.9 }
        )
        local cancel = PopupButton(
            dialog,
            "Cancel",
            "BOTTOMLEFT",
            4,
            { 0.12, 0.12, 0.12, 0.5 },
            { 1, 1, 1, 0.10 },
            { 0.7, 0.7, 0.7, 0.8 }
        )
        local function Close()
            dimmer:Hide()
        end
        cancel:SetScript("OnClick", Close)
        dialog._cancelBtn = cancel
        dialog._sidBox:SetScript("OnEscapePressed", Close)
        dialog._durBox:SetScript("OnEscapePressed", Close)
        dialog._dimmer = dimmer
        _G[CUSTOM_POPUP] = dialog
        return dialog
    end

    -- Show the "Custom Buff ID" popup with Spell ID + Duration fields: Add
    -- needs a known spell and a duration (a short-lived note says what is wrong).
    local function ShowCustomBuffIDPopup(anchor, barCfg, onChanged)
        local dialog = CustomBuffPopup()
        local currentID = (barCfg.spellID and barCfg.spellID > 0 and not barCfg.popularKey) and barCfg.spellID
            or nil
        dialog._sidBox:SetText(currentID and tostring(currentID) or "")
        dialog._durBox:SetText(barCfg.customDuration and tostring(barCfg.customDuration) or "")
        dialog._status:SetText("")

        local function SetStatus(textValue)
            dialog._status:SetText(CludesUI.L(textValue))
            dialog._status:SetTextColor(1, 0.3, 0.3, 1)
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
                return SetStatus("Enter a valid spell ID")
            end
            spellRef = math.floor(spellRef)
            if not C_Spell.GetSpellName(spellRef) then
                return SetStatus("Unknown spell ID")
            end
            if not dur or dur <= 0 then
                return SetStatus("Enter a duration in seconds")
            end
            dialog._dimmer:Hide()
            barCfg.spellID = spellRef
            barCfg.spellIDs, barCfg.popularKey, barCfg.glowBased, barCfg.trackType = nil, nil, nil, nil
            barCfg.customDuration = math.floor(dur)
            -- A typed id has no live frame to read its base from: the stale base
            -- goes, and MatchFrameToConfig heals it once the spell is talented.
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

    -- A picked buff or cooldown keeps tracking after a hero-talent override is
    -- dropped: the BASE spell id of its cooldown entry is stored when it differs.
    -- Roll the Bones: one tracked slot cycles through exclusive outcome buffs,
    -- listed only in the raw linkedSpellIDs; the row reads as whichever outcome
    -- was up at pick time, so the whole family becomes the want-set, keyed on
    -- the stable base (buff picks only).
    local RTB_BASE_SPELL_ID = 1214909
    local function TakeBaseSpell(barCfg, sp, allowFamily)
        barCfg.baseSpellID = nil
        if not (sp.cdID and C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCooldownInfo) then
            return
        end
        local details = C_CooldownViewer.GetCooldownViewerCooldownInfo(sp.cdID)
        local isSec = issecretvalue
        local base = details and details.spellID
        if base and allowFamily and isSec and isSec(base) then
            base = nil
        end
        if base and base > 0 and base ~= sp.spellID then
            barCfg.baseSpellID = base
        end
        if not (allowFamily and base == RTB_BASE_SPELL_ID and type(details.linkedSpellIDs) == "table") then
            return
        end
        local ids = {}
        for _, id in ipairs(details.linkedSpellIDs) do
            if type(id) == "number" and not (isSec and isSec(id)) and id > 0 then
                ids[#ids + 1] = id
            end
        end
        if #ids >= 2 then
            barCfg.spellIDs, barCfg.spellID, barCfg.baseSpellID = ids, base, nil
            local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(base)
            if name and name ~= "" then
                barCfg.name = name
            end
        end
    end

    local function ShowTBBSpellPicker(anchor, barCfg, onChanged)
        if _tbbSpellPickerMenu then
            _tbbSpellPickerMenu:Hide()
        end
        -- No early bail on empty lists: the picker still shows the presets and Custom Buff ID.
        local trackedBars = mod.GetTrackedBarSpells and mod.GetTrackedBarSpells(true) or {}
        local popular = mod.TBB_POPULAR_BUFFS or {}
        local hlA = CludesUI.DD_ITEM_HL_A or 0.08
        local DIM = {
            CludesUI.TEXT_DIM_R or 0.7,
            CludesUI.TEXT_DIM_G or 0.7,
            CludesUI.TEXT_DIM_B or 0.7,
            CludesUI.TEXT_DIM_A or 0.85,
        }
        local BRIGHT = { 1, 1, 1, 1 }
        local menuW, ITEM_H, MAX_H = 240, 26, 340

        -- One picker frame for the session, dressed again on every open.
        local dropMenu = PoolKept(mod, "tbbSpellPicker", "Frame", UIParent)
        dropMenu:SetFrameStrata("FULLSCREEN_DIALOG")
        dropMenu:SetFrameLevel(300)
        dropMenu:SetClampedToScreen(true)
        dropMenu:SetSize(menuW, 10)
        local backdrop = dropMenu:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(
            CludesUI.DD_BG_R or 0.075,
            CludesUI.DD_BG_G or 0.113,
            CludesUI.DD_BG_B or 0.141,
            CludesUI.DD_BG_HA or 0.98
        )
        CludesUI.MakeRoundedBorder(dropMenu, 1, 1, 1, CludesUI.DD_BRD_A or 0.20, backdrop, nil, true)
        local inner = CreateFrame("Frame", nil, dropMenu)
        inner:SetWidth(menuW)
        inner:SetPoint("TOPLEFT")
        local mH = 4

        local function Row(height)
            local item = CreateFrame("Button", nil, inner)
            item:SetHeight(height)
            item:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
            item:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
            item:SetFrameLevel(dropMenu:GetFrameLevel() + 2)
            mH = mH + height
            return item
        end
        local function Divider()
            local div = inner:CreateTexture(nil, "ARTWORK")
            div:SetHeight(1)
            div:SetColorTexture(1, 1, 1, 0.10)
            div:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH - 4)
            div:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH - 4)
            mH = mH + 9
        end
        local function Heading(text)
            local fs = inner:CreateFontString(nil, "OVERLAY")
            fs:SetFont(FONT_PATH, 10, GetCDMOptOutline())
            fs:SetTextColor(1, 1, 1, 0.5)
            fs:SetPoint("TOPLEFT", inner, "TOPLEFT", 10, -mH - 5)
            fs:SetText(CludesUI.L(text))
            mH = mH + 20
        end
        -- A pick: the bar takes it, the bars rebuild, the page follows.
        local function Picked(apply)
            return function()
                dropMenu:Hide()
                apply()
                Refresh()
                mod.BuildTrackedBuffBars()
                if onChanged then
                    onChanged()
                end
            end
        end

        -- "Custom Buff ID" at the top.
        do
            local selected = barCfg.spellID
                and barCfg.spellID > 0
                and not barCfg.popularKey
                and not barCfg.spellIDs
                and barCfg.trackType ~= "cooldown"
            local rest = selected and BRIGHT or DIM
            local item = Row(ITEM_H)
            local highlight = item:CreateTexture(nil, "ARTWORK", nil, -1)
            highlight:SetAllPoints()
            highlight:SetColorTexture(1, 1, 1, 0)
            local label = item:CreateFontString(nil, "OVERLAY")
            label:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            label:SetPoint("LEFT", 10, 0)
            label:SetJustifyH("LEFT")
            label:SetText(CludesUI.L("Custom Buff ID"))
            label:SetTextColor(unpack(rest))
            item:SetScript("OnEnter", function()
                label:SetTextColor(1, 1, 1, 1)
                highlight:SetColorTexture(1, 1, 1, hlA)
            end)
            item:SetScript("OnLeave", function()
                label:SetTextColor(unpack(rest))
                highlight:SetColorTexture(1, 1, 1, 0)
            end)
            item:SetScript("OnClick", function()
                dropMenu:Hide()
                ShowCustomBuffIDPopup(anchor, barCfg, onChanged)
            end)
        end
        Divider()

        -- A choice row: name and icon (right). Selected rows are lit; one already
        -- on another bar is greyed with a tip and cannot be picked; an untalented
        -- one stays pickable, desaturated, with a hint.
        local function ChoiceRow(text, icon, selected, usedOnBar, notLearned, onPick)
            local item = Row(ITEM_H)
            local ico = item:CreateTexture(nil, "ARTWORK")
            ico:SetSize(ITEM_H - 4, ITEM_H - 4)
            ico:SetPoint("RIGHT", item, "RIGHT", -6, 0)
            if icon then
                ico:SetTexture(icon)
            end
            ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            local rest = selected and BRIGHT or DIM
            local label = item:CreateFontString(nil, "OVERLAY")
            label:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            label:SetPoint("LEFT", 8, 0)
            label:SetPoint("RIGHT", ico, "LEFT", -4, 0)
            label:SetJustifyH("LEFT")
            label:SetWordWrap(false)
            label:SetMaxLines(1)
            label:SetText(CludesUI.L(text))
            label:SetTextColor(unpack(rest))
            local restHl = selected and 0.12 or 0
            local highlight = item:CreateTexture(nil, "ARTWORK", nil, -1)
            highlight:SetAllPoints()
            highlight:SetColorTexture(1, 1, 1, restHl)
            if usedOnBar and not selected then
                label:SetTextColor(DIM[1], DIM[2], DIM[3], DIM[4] * 0.4)
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
                return
            end
            if notLearned then
                ico:SetDesaturated(true)
                ico:SetAlpha(0.5)
            end
            item:SetScript("OnEnter", function()
                label:SetTextColor(1, 1, 1, 1)
                highlight:SetColorTexture(1, 1, 1, hlA)
                if notLearned then
                    CludesUI.ShowWidgetTooltip(item, CludesUI.L("Not currently talented"))
                end
            end)
            item:SetScript("OnLeave", function()
                label:SetTextColor(unpack(rest))
                highlight:SetColorTexture(1, 1, 1, restHl)
                if notLearned then
                    CludesUI.HideWidgetTooltip()
                end
            end)
            item:SetScript("OnClick", function()
                if notLearned then
                    CludesUI.HideWidgetTooltip()
                end
                onPick()
            end)
        end

        -- Popular presets for the class. tbbOnly presets (e.g. debuff-driven
        -- Bloodlust) carry a sentinel class that hides them from the cooldown and
        -- utility item picker; here they always show.
        local _, class = UnitClass("player")
        local presets = 0
        for _, record in ipairs(popular) do
            if record.tbbOnly or not record.class or record.class == class then
                presets = presets + 1
                ChoiceRow(
                    record.name,
                    record.icon,
                    barCfg.popularKey == record.key,
                    nil,
                    false,
                    Picked(function()
                        barCfg.popularKey = record.key
                        barCfg.spellIDs = record.spellIDs
                        barCfg.glowBased = record.glowBased or nil
                        barCfg.customDuration = record.customDuration
                        barCfg.spellID = record.spellIDs and record.spellIDs[1] or 0
                        barCfg.baseSpellID, barCfg.trackType = nil, nil
                        barCfg.name = record.name
                        barCfg.customName = nil
                    end)
                )
            end
        end

        -- Buffs: always shown (even with nothing tracked) so the Missing Spells
        -- prompt stays reachable. Its divider closes the preset rows, so with none
        -- (WoW Forever has no presets) the one above already separates Custom Buff ID.
        if presets > 0 then
            Divider()
        end
        Heading("Buffs")
        -- Every spell here came from the BuffBarCooldownViewer, so it is tracked by
        -- definition. A family bar (Roll the Bones) is selected by its base id or
        -- any member, since the row reads as the active outcome while one is up.
        local asBuff = not barCfg.popularKey and barCfg.trackType ~= "cooldown"
        for _, sp in ipairs(trackedBars) do
            local selected = asBuff and barCfg.spellID and barCfg.spellID > 0 and barCfg.spellID == sp.spellID
            if not selected and asBuff and barCfg.spellIDs then
                selected = tContains(barCfg.spellIDs, sp.spellID)
            end
            local used = mod.SpellUsedOnAnyOtherTBB and mod.SpellUsedOnAnyOtherTBB(sp.spellID, nil)
            ChoiceRow(
                sp.name,
                sp.icon,
                selected,
                used,
                sp.isKnown == false,
                Picked(function()
                    barCfg.spellID = sp.spellID
                    barCfg.spellIDs, barCfg.popularKey, barCfg.glowBased, barCfg.customDuration =
                        nil, nil, nil, nil
                    barCfg.trackType = nil
                    barCfg.name = sp.name
                    barCfg.customName = nil
                    TakeBaseSpell(barCfg, sp, true)
                end)
            )
        end

        -- "Missing Spells?" (centred, accent): closes the options and opens
        -- Blizzard's CDM, at the end of Buffs as the way to add more.
        do
            local item = Row(38)
            local text = item:CreateFontString(nil, "OVERLAY")
            text:SetFont(FONT_PATH, 11, GetCDMOptOutline())
            text:SetAllPoints()
            text:SetJustifyH("CENTER")
            text:SetJustifyV("MIDDLE")
            local function Accented()
                local r, g, b = CludesUI.GetAccentColor()
                text:SetTextColor(r, g, b, 1)
            end
            Accented()
            text:SetText(
                CludesUI.L("Missing Spells? Add as") .. "\n" .. CludesUI.L("Tracking Bar in Blizz CDM")
            )
            item:SetScript("OnEnter", function()
                text:SetTextColor(1, 1, 1, 1)
            end)
            item:SetScript("OnLeave", Accented)
            item:SetScript("OnClick", function()
                dropMenu:Hide()
                if mod.OpenBlizzardCDMTab then
                    mod.OpenBlizzardCDMTab(true)
                end
            end)
        end

        -- Cooldowns: a spell COOLDOWN to track instead of a buff (trackType
        -- "cooldown"), from the Essential + Utility pools and the settings catalog;
        -- only when there are any. Greyed only for another COOLDOWN bar: a buff
        -- bar for the same spell never blocks it.
        local cdSpells = mod.GetCDMSpellsForBar and mod.GetCDMSpellsForBar("cooldowns") or {}
        if #cdSpells > 0 then
            Divider()
            Heading("Cooldowns")
            for _, sp in ipairs(cdSpells) do
                local selected = barCfg.trackType == "cooldown"
                    and not barCfg.popularKey
                    and not barCfg.spellIDs
                    and barCfg.spellID
                    and barCfg.spellID > 0
                    and barCfg.spellID == sp.spellID
                local used = mod.SpellUsedOnAnyOtherTBB
                    and mod.SpellUsedOnAnyOtherTBB(sp.spellID, nil, "cooldown")
                ChoiceRow(
                    sp.name,
                    sp.icon,
                    selected,
                    used,
                    sp.isKnown == false,
                    Picked(function()
                        barCfg.spellID = sp.spellID
                        barCfg.spellIDs, barCfg.popularKey, barCfg.glowBased, barCfg.customDuration =
                            nil, nil, nil, nil
                        barCfg.trackType = "cooldown"
                        barCfg.name = sp.name
                        barCfg.customName = nil
                        TakeBaseSpell(barCfg, sp, false)
                    end)
                )
            end
        end

        -- Tall lists scroll (wheel, 30 a notch).
        local totalH = mH + 4
        inner:SetHeight(totalH)
        if totalH > MAX_H then
            dropMenu:SetHeight(MAX_H)
            local scroll = CreateFrame("ScrollFrame", nil, dropMenu)
            scroll:SetPoint("TOPLEFT", 0, -1)
            scroll:SetPoint("BOTTOMRIGHT", 0, 1)
            scroll:SetFrameLevel(dropMenu:GetFrameLevel() + 1)
            scroll:EnableMouseWheel(true)
            scroll:SetScrollChild(inner)
            inner:SetWidth(menuW)
            local pos, maxScroll = 0, totalH - MAX_H
            scroll:SetScript("OnMouseWheel", function(_, delta)
                pos = math.max(0, math.min(maxScroll, pos - delta * 30))
                scroll:SetVerticalScroll(pos)
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
        return _stGetCfg and _stGetCfg() or nil
    end
    -- The bar being edited, its threshold list and entry idx of it (each nil when absent).
    local function ThresholdEntry(idx)
        local conf = CurrentStackThreshCfg()
        local entries = conf and conf.stackThresholds
        return conf, entries, entries and entries[idx]
    end
    -- An edit reaches the bar through the caller's refresh.
    local function ThresholdsChanged()
        if _stRefreshFn then
            _stRefreshFn()
        end
    end

    local function SortStackThresholds(entries)
        table.sort(entries, function(a, b)
            return (a.value or 0) < (b.value or 0)
        end)
    end

    -- The editor while shown: a screen-wide catcher under it takes a click
    -- outside (as does any press off it, the panel and an open dropdown list),
    -- and entering combat closes it.
    local function WireDismiss(clickCatcher)
        stPopup:SetScript("OnEvent", function(self, evt)
            if evt == "PLAYER_REGEN_DISABLED" then
                self:Hide()
            end
        end)
        stPopup:SetScript("OnShow", function(self)
            clickCatcher:Show()
            self:RegisterEvent("PLAYER_REGEN_DISABLED")
            self:SetScript("OnUpdate", function(p)
                if not IsMouseButtonDown("LeftButton") then
                    return
                end
                local panel, list = CludesUI._mainFrame, CludesUI._openDropdownMenu
                if
                    not p:IsMouseOver()
                    and not (panel and panel:IsMouseOver())
                    and not (list and list:IsShown() and list:IsMouseOver())
                then
                    p:Hide()
                end
            end)
        end)
        stPopup:SetScript("OnHide", function(self)
            clickCatcher:Hide()
            self:UnregisterEvent("PLAYER_REGEN_DISABLED")
            self:SetScript("OnUpdate", nil)
        end)
    end

    -- "Use Multiple Thresholds" (label left, toggle right), as the band editor has it.
    local function BuildMultiRow()
        _stMultiRow = CreateFrame("Frame", nil, stPopup)
        _stMultiRow:SetFrameLevel(stPopup:GetFrameLevel() + 3)
        Pix.Height(_stMultiRow, ST_ROW_H)
        local label = CludesUI.MakeFont(_stMultiRow, 12, nil, 1, 1, 1)
        label:SetAlpha(0.6)
        label:SetPoint("LEFT", _stMultiRow, "LEFT", 0, 0)
        label:SetText(CludesUI.L("Use Multiple Thresholds"))
        local toggle, _
        toggle, _, _stMultiSnap = CludesUI.BuildToggleControl(
            _stMultiRow,
            _stMultiRow:GetFrameLevel() + 3,
            function()
                local conf = CurrentStackThreshCfg()
                return conf and conf.stackThresholdMulti
            end,
            function(v)
                local conf = CurrentStackThreshCfg()
                if conf then
                    conf.stackThresholdMulti = v and true or false
                    ThresholdsChanged()
                    RefreshStackThreshEditor()
                    CludesUI:RefreshPage()
                end
            end,
            { sizeRatio = 0.95 }
        )
        toggle:SetPoint("RIGHT", _stMultiRow, "RIGHT", 0, 0)
        local hover = CreateFrame("Frame", nil, _stMultiRow)
        hover:SetAllPoints(label)
        hover:EnableMouse(true)
        hover:SetScript("OnEnter", function(self)
            CludesUI.ShowWidgetTooltip(self, StackThreshHelpTip())
        end)
        hover:SetScript("OnLeave", function()
            CludesUI.HideWidgetTooltip()
        end)
    end

    -- "+ Add Threshold": a new stop one above the last (5 for the first), up to the cap.
    local function BuildAddButton()
        _stAddBtn = CreateFrame("Button", nil, stPopup)
        Pix.Size(_stAddBtn, ST_POPUP_W - ST_PAD * 2, 26)
        _stAddBtn:SetFrameLevel(stPopup:GetFrameLevel() + 3)
        local bg = CludesUI.SolidTex(_stAddBtn, "BACKGROUND", 0.050, 0.058, 0.068, 0.92)
        bg:SetAllPoints()
        _stAddBtn._border = CludesUI.MakeRoundedBorder(_stAddBtn, 1, 1, 1, 0.4, bg)
        _stAddLbl = CludesUI.MakeFont(_stAddBtn, 12, nil, 1, 1, 1)
        _stAddLbl:SetAlpha(0.5)
        _stAddLbl:SetPoint("CENTER")
        _stAddLbl:SetText(CludesUI.L("+ Add Threshold"))
        local function Lit(self, on)
            _stAddLbl:SetAlpha(on and 0.7 or 0.5)
            if self._border and self._border.SetColor then
                self._border:SetColor(1, 1, 1, on and 0.6 or 0.4)
            end
        end
        _stAddBtn:SetScript("OnEnter", function(self)
            local _, entries = ThresholdEntry()
            if entries and #entries >= STACK_THRESH_MAX then
                CludesUI.ShowWidgetTooltip(self, StackThreshAtCapTip())
                return
            end
            Lit(self, true)
        end)
        _stAddBtn:SetScript("OnLeave", function(self)
            CludesUI.HideWidgetTooltip()
            Lit(self, false)
        end)
        _stAddBtn:SetScript("OnClick", function()
            local conf = CurrentStackThreshCfg()
            if not conf then
                return
            end
            conf.stackThresholds = conf.stackThresholds or {}
            local entries = conf.stackThresholds
            if #entries >= STACK_THRESH_MAX then
                return
            end
            local last = entries[#entries]
            local value = last and math.min(100, (last.value or 0) + 1) or 5
            entries[#entries + 1] = { value = value, r = ST_DEF_R, g = ST_DEF_G, b = ST_DEF_B, a = ST_DEF_A }
            SortStackThresholds(entries)
            ThresholdsChanged()
            RefreshStackThreshEditor()
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
        WireDismiss(clickCatcher)

        local title = CludesUI.MakeFont(stPopup, 13, nil, 1, 1, 1)
        title:SetAlpha(0.6)
        title:SetPoint("TOP", stPopup, "TOP", 0, -ST_PAD)
        title:SetText(CludesUI.L("Stack Thresholds"))
        BuildMultiRow()
        BuildAddButton()
    end

    -- Threshold row k, made on first use: "At" <count> <colour> and delete. A
    -- count commits on focus loss (Enter clears focus; Escape throws the typing
    -- away), clamped as the single-threshold slider is (0-100), and re-sorts.
    local function EnsureStackThreshRow(k)
        if _stRows[k] then
            return _stRows[k]
        end
        local row = {}
        local rf = CreateFrame("Frame", nil, stPopup)
        rf:SetSize(ST_POPUP_W - ST_PAD * 2, ST_ROW_H)
        rf:SetFrameLevel(stPopup:GetFrameLevel() + 2)
        row.frame = rf
        local label = CludesUI.MakeFont(rf, 12, nil, 1, 1, 1)
        label:SetAlpha(0.6)
        label:SetPoint("LEFT", rf, "LEFT", 2, 0)
        label:SetText(CludesUI.L("At"))
        row.lbl = label

        local input = CreateFrame("EditBox", nil, rf)
        input:SetSize(54, 22)
        input:SetPoint("LEFT", label, "RIGHT", 6, 0)
        input:SetFrameLevel(rf:GetFrameLevel() + 2)
        input:SetAutoFocus(false)
        input:SetFontObject(GameFontHighlightSmall)
        input:SetFont(CludesUI.GetFontPath("main") or "Fonts\\FRIZQT__.TTF", 12, "")
        input:SetTextColor(1, 1, 1, 0.75)
        input:SetJustifyH("CENTER")
        input:SetNumeric(true)
        local inputBg = input:CreateTexture(nil, "BACKGROUND")
        inputBg:SetAllPoints()
        inputBg:SetColorTexture(0.12, 0.12, 0.12, 0.8)
        CludesUI.MakeRoundedBorder(input, 1, 1, 1, 0.08, inputBg)
        row.input = input
        input:SetScript("OnEditFocusLost", function(self)
            if self._cancelCommit then
                self._cancelCommit = nil
                return
            end
            local _, entries, ent = ThresholdEntry(row._idx)
            if not ent then
                return
            end
            local value = tonumber(self:GetText())
            if value then
                ent.value = math.max(0, math.min(100, math.floor(value + 0.5)))
                SortStackThresholds(entries)
                ThresholdsChanged()
            end
            RefreshStackThreshEditor()
        end)
        input:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
        end)
        input:SetScript("OnEscapePressed", function(self)
            self._cancelCommit = true
            self:ClearFocus()
            RefreshStackThreshEditor()
        end)

        local swatch, swatchSnap = CludesUI.BuildColorSwatch(rf, rf:GetFrameLevel() + 3, function()
            local _, _, ent = ThresholdEntry(row._idx)
            if not ent then
                return ST_DEF_R, ST_DEF_G, ST_DEF_B, ST_DEF_A
            end
            return ent.r or ST_DEF_R, ent.g or ST_DEF_G, ent.b or ST_DEF_B, ent.a or ST_DEF_A
        end, function(r, g, b, a)
            local _, _, ent = ThresholdEntry(row._idx)
            if ent then
                ent.r, ent.g, ent.b, ent.a = r, g, b, a
                ThresholdsChanged()
            end
        end, true, 19)
        swatch:SetPoint("LEFT", input, "RIGHT", 10, 0)
        row.swatch, row.swatchSnap = swatch, swatchSnap

        -- Delete. Emptying the list also turns multi off: an empty list would
        -- quietly fall back to the single threshold while the toggle still read on.
        local del = CreateFrame("Button", nil, rf)
        del:SetSize(14, 14)
        del:SetPoint("RIGHT", rf, "RIGHT", -2, 0)
        del:SetFrameLevel(rf:GetFrameLevel() + 3)
        local icon = del:CreateTexture(nil, "OVERLAY")
        icon:SetAllPoints()
        icon:SetTexture(_stCloseIcon)
        icon:SetAlpha(0.4)
        del:SetScript("OnEnter", function()
            icon:SetAlpha(0.9)
        end)
        del:SetScript("OnLeave", function()
            icon:SetAlpha(0.4)
        end)
        del:SetScript("OnClick", function()
            local conf, entries, ent = ThresholdEntry(row._idx)
            if not ent then
                return
            end
            table.remove(entries, row._idx)
            if #entries == 0 and conf.stackThresholdMulti then
                conf.stackThresholdMulti = false
                CludesUI:RefreshPage()
            end
            ThresholdsChanged()
            RefreshStackThreshEditor()
        end)
        row.delBtn = del
        _stRows[k] = row
        return row
    end

    -- Lays the editor out: the multi row under the title, one row per stop,
    -- then Add (dimmed at the cap); the popup fits its height.
    RefreshStackThreshEditor = function()
        if not stPopup then
            return
        end
        local conf = CurrentStackThreshCfg()
        if not conf then
            stPopup:Hide()
            return
        end
        conf.stackThresholds = conf.stackThresholds or {}
        local entries = conf.stackThresholds
        local y = -(ST_PAD + 24)
        _stMultiRow:ClearAllPoints()
        Pix.Point(_stMultiRow, "TOPLEFT", stPopup, "TOPLEFT", ST_PAD, y)
        Pix.Point(_stMultiRow, "TOPRIGHT", stPopup, "TOPRIGHT", -ST_PAD, y)
        _stMultiRow:Show()
        if _stMultiSnap then
            _stMultiSnap()
        end
        y = y - ST_ROW_H - ST_GAP
        for k, entry in ipairs(entries) do
            local row = EnsureStackThreshRow(k)
            row._idx = k
            row.frame:ClearAllPoints()
            Pix.Point(row.frame, "TOPLEFT", stPopup, "TOPLEFT", ST_PAD, y)
            row.input:SetText(tostring(entry.value or 5))
            if row.swatchSnap then
                row.swatchSnap()
            end
            row.frame:Show()
            y = y - ST_ROW_H - 4
        end
        for k = #entries + 1, #_stRows do
            if _stRows[k] then
                _stRows[k].frame:Hide()
            end
        end
        y = y - 4
        _stAddBtn:ClearAllPoints()
        Pix.Point(_stAddBtn, "TOPLEFT", stPopup, "TOPLEFT", ST_PAD, y)
        local atCap = #entries >= STACK_THRESH_MAX
        _stAddBtn:SetEnabled(not atCap)
        _stAddBtn:SetAlpha(atCap and 0.35 or 1)
        y = y - 26
        Pix.Size(stPopup, ST_POPUP_W, math.abs(y) + ST_PAD)
        stPopup._brd:Fit()
    end

    -- params = { getCfg, refreshFn, anchor }. The first open seeds the list
    -- from the single threshold; that is inert until multi is on, so opening and
    -- closing the editor changes nothing on the bar.
    local function ShowStackThreshEditor(params)
        if not stPopup then
            BuildStackThreshPopup()
        end
        _stGetCfg, _stRefreshFn = params.getCfg, params.refreshFn
        local conf = CurrentStackThreshCfg()
        if conf then
            conf.stackThresholds = conf.stackThresholds or {}
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
            local bars = mod.GetTrackedBuffBars().bars
            return (_tbbSelectedBar >= 1 and _tbbSelectedBar <= #bars) and bars[_tbbSelectedBar] or nil
        end

        local function SelectedTBBSupportsChargeHash()
            local bd = SelectedTBB()
            return bd and mod.GetTBBMaxCharges and mod.GetTBBMaxCharges(bd) ~= nil
        end

        -- The group selection must still exist (a group dissolves with its last bar).
        -- A bar-less GLOBAL group stays selectable: the Currently Editing menu lists
        -- it on every spec so its shared settings stay editable, and its local id
        -- lives on through its globalKey link (every GROUP MODE section is keyed by
        -- group, and the previews guard an empty member list).
        if _tbbSelectedGroup then
            local live = tContains(mod.TBBGroupIDsInUse(), _tbbSelectedGroup)
                or (mod.TBBGroupGlobalKey and mod.TBBGroupGlobalKey(_tbbSelectedGroup))
            if not live then
                _tbbSelectedGroup = nil
            end
        end

        -- What the preview mirrors and a new preset copies: the selected bar, or the
        -- selected group's style source (its anchor bar).
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
        --  CLICK NAVIGATION (preview elements -> option rows). The map lives on
        --  hostFrame._tbbClickTargets (filled by the bar-mode build below) and is
        --  read at click time, so a header rebuild never holds stale rows.
        -------------------------------------------------------------------
        local PlaySettingGlow = CludesUI.MakeSettingGlow({ color = CludesUI.CLUDES_GREEN })

        -- Scrolls to the row (a click also dismisses the preview hint for good)
        -- and glows it, or its slot's region, a moment later, unless a rebuild has
        -- dressed that row again for another setting by then.
        local function NavigateToSetting(key)
            local m = hostFrame._tbbClickTargets and hostFrame._tbbClickTargets[key]
            if not (m and m.section and m.target) then
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
                glowTarget = (m.slotSide == "left" and m.target._leftRegion or m.target._rightRegion)
                    or glowTarget
            end
            local gen = PoolGen(glowTarget)
            C_Timer.After(0.15, function()
                if PoolGen(glowTarget) == gen then
                    PlaySettingGlow(glowTarget)
                end
            end)
        end

        -- An edit's refresh, coalesced over 50ms: settings, live bars, preview, placeholders.
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
        -- The spec-change watcher outside uses this build's refresh, so a spec swap
        -- with the page open rebuilds the dropdown and preview.
        _tbbRefreshFn = RefreshTBB

        -- Drag-and-drop move into another group (or out to independent). Joining a
        -- group takes its current look, as a freshly added bar does; the moved bar
        -- is selected.
        local function MoveBarToGroup(idx, groupId)
            local conf = mod.GetTrackedBuffBars().bars[idx]
            if not conf or mod.TBBBarGroupID(conf) == groupId then
                return
            end
            mod.TBBSetBarGroup(conf, groupId)
            local source = groupId ~= 0 and mod.TBBGroupStyleSource(groupId)
            if source and source ~= conf then
                mod.CopyTBBStyle(source, conf)
            end
            _tbbSelectedBar, _tbbSelectedGroup = idx, nil
            mod.BuildTrackedBuffBars()
            CludesUI:RefreshPage(true)
        end

        -- Drag-and-drop reorder inside the bar's own group: no style copy, the
        -- editing context stays (a selected bar follows its config to its new
        -- index) and the menu opens again on the fresh button for the next move.
        local function ReorderBarInGroup(idx, place)
            local bars = mod.GetTrackedBuffBars().bars
            local sel = not _tbbSelectedGroup and bars[_tbbSelectedBar] or nil
            mod.MoveTrackedBuffBarInGroup(idx, place)
            for jdx, c in ipairs(bars) do
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
            local DD_H, ddW = 34, 350
            -- The shared dropdown look: fill (and hovered), border (and hovered),
            -- label alpha (and hovered), item highlight and selected tints.
            local DDS = CludesUI.DD_STYLE
            local mBgR, mBgG, mBgB, mBgA, mBgHA = DDS.BG_R, DDS.BG_G, DDS.BG_B, DDS.BG_A, DDS.BG_HA
            local mBrdA, mBrdHA = DDS.BRD_A, DDS.BRD_HA or 0.30
            local mTxtA, mTxtHA = DDS.TXT_A, DDS.TXT_HA or 1
            local hlA, selA = DDS.ITEM_HL_A, DDS.ITEM_SEL_A
            local tDimR, tDimG = CludesUI.TEXT_DIM_R or 0.7, CludesUI.TEXT_DIM_G or 0.7
            local tDimB, tDimA = CludesUI.TEXT_DIM_B or 0.7, CludesUI.TEXT_DIM_A or 0.85
            local ITEM_H, ICON_SZ = 26, 14
            local MEDIA = "Interface\\AddOns\\CludesUI\\media\\"

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

            -- What is being edited: the group and its bar count, else the bar (its
            -- spell's name unless a preset, with its group), else a prompt. The bar
            -- count is read live: this header is reused across SetContentHeader
            -- refreshes (a spec change) without a page rebuild.
            local function EditingLabel()
                if _tbbSelectedGroup then
                    local num = mod.TBBGroupedCount(_tbbSelectedGroup)
                    return GroupLabel(_tbbSelectedGroup)
                        .. "  -  "
                        .. num
                        .. " "
                        .. CludesUI.L(num == 1 and "Bar" or "Bars")
                end
                local bd = SelectedTBB()
                if not bd then
                    local live = mod.GetTrackedBuffBars().bars
                    return CludesUI.L((not live or #live == 0) and "No Bars - Click to Add" or "Select a bar")
                end
                local label = (bd.name and CludesUI.L(bd.name)) or "Bar"
                if not bd.popularKey and bd.spellID and bd.spellID > 0 then
                    local details = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(bd.spellID)
                    label = (details and details.name) or label
                end
                local groupId = mod.TBBBarGroupID and mod.TBBBarGroupID(bd) or 0
                if groupId ~= 0 then
                    label = label .. "  (" .. GroupLabel(groupId) .. ")"
                end
                return label
            end
            local function UpdateDDLabel()
                ddLbl:SetText(EditingLabel())
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
                -- One sound menu frame for the session, dressed again on every open,
                -- above the bar menu it opens from (300), which stays open underneath.
                local sm = PoolKept(mod, "tbbSoundMenu", "Frame", UIParent)
                sm:SetFrameStrata("FULLSCREEN_DIALOG")
                sm:SetFrameLevel(320)
                sm:SetClampedToScreen(true)
                sm:EnableMouse(true)
                sm:SetSize(240, 8 + ITEM_H * 2)
                local smBg = sm:CreateTexture(nil, "BACKGROUND")
                smBg:SetAllPoints()
                smBg:SetColorTexture(mBgR, mBgG, mBgB, mBgHA)
                CludesUI.MakeRoundedBorder(sm, 1, 1, 1, mBrdA, smBg, nil, true)
                -- A fixed spot, as the CDM icon menu sits under its icon: beside the
                -- clicked row, just outside the bar menu, so it covers no other bar.
                sm:SetPoint("TOPLEFT", anchorRow, "TOPRIGHT", 4, 0)
                local ar, ag, ab = CludesUI.GetAccentColor()
                local nameList = mod.FOCUSKICK_SOUND_NAMES or {}
                local flyouts = {}

                -- The sound list flying out of a row (search, scroll, preview
                -- speaker), as the CDM icon menu's flyouts: the CDM options font at
                -- 11, the speaker atlas in its own colour, above both menus.
                local function Flyout(row, get, set, val)
                    local values, sequence = CludesUI.BuildSoundDropdownValues(
                        mod.FOCUSKICK_SOUND_PATHS,
                        nameList,
                        mod.FOCUSKICK_SOUND_ORDER
                    )
                    values._menuOpts.anchor = "RIGHT"
                    values._menuOpts.labelFont = { FONT_PATH, 11, GetCDMOptOutline() }
                    values._menuOpts.iconNativeColor = true
                    local fly, _, refresh =
                        CludesUI.BuildDropdownMenu(row, 200, sequence, values, get, set, val, "regular")
                    -- BuildDropdownMenu makes it at FULLSCREEN_DIALOG 200, under both menus.
                    fly:SetFrameStrata(sm:GetFrameStrata())
                    fly:SetFrameLevel(sm:GetFrameLevel() + 30)
                    fly._refresh = refresh
                    return fly
                end

                -- One audio row (Audio on Buff Gain / Loss): its label (accent while
                -- a sound is set), the sound's name and an arrow; hovering or
                -- clicking opens its list and closes the other.
                local function SoundRow(i, label, field)
                    local row = CreateFrame("Button", nil, sm)
                    row:SetHeight(ITEM_H)
                    row:SetPoint("TOPLEFT", sm, "TOPLEFT", 1, -4 - (i - 1) * ITEM_H)
                    row:SetPoint("TOPRIGHT", sm, "TOPRIGHT", -1, -4 - (i - 1) * ITEM_H)
                    row:SetFrameLevel(sm:GetFrameLevel() + 2)
                    local labelFS = row:CreateFontString(nil, "OVERLAY")
                    labelFS:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                    labelFS:SetPoint("LEFT", row, "LEFT", 10, 0)
                    labelFS:SetText(CludesUI.L(label))
                    local pointer = row:CreateTexture(nil, "ARTWORK")
                    pointer:SetSize(10, 10)
                    pointer:SetPoint("RIGHT", row, "RIGHT", -8, 0)
                    pointer:SetTexture(MEDIA .. "icons\\right-arrow.png")
                    pointer:SetAlpha(0.7)
                    local val = row:CreateFontString(nil, "OVERLAY")
                    val:SetFont(FONT_PATH, 10, GetCDMOptOutline())
                    val:SetPoint("LEFT", labelFS, "RIGHT", 8, 0)
                    val:SetPoint("RIGHT", pointer, "LEFT", -6, 0)
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
                    local function Paint()
                        local key = conf[field]
                        if key and key ~= "none" then
                            labelFS:SetTextColor(ar, ag, ab, 1)
                        else
                            labelFS:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                        end
                        val:SetText(nameList[Get()] or Get())
                    end
                    Paint()
                    -- A sound set flips the 0-cost gate live and hooks the bar frames
                    -- already out of the pool, so the next edge plays without a
                    -- reload; the bar row's speaker follows (dimmed with no sound).
                    local function Set(v)
                        conf[field] = (v ~= "none" and v) or nil
                        if conf[field] then
                            mod._cdmAnyBuffSound = true
                            if mod.EnsureTBBSoundHooks then
                                mod.EnsureTBBSoundHooks()
                            end
                        end
                        Paint()
                        if anchorRow._sndPaint then
                            anchorRow._sndPaint()
                        end
                    end
                    local function ShowFlyout()
                        highlight:SetAlpha(hlA)
                        for key, fly in pairs(flyouts) do
                            if key ~= field then
                                fly:Hide()
                            end
                        end
                        flyouts[field] = flyouts[field] or Flyout(row, Get, Set, val)
                        local fly = flyouts[field]
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
                SoundRow(1, "Audio on Buff Gain", "buffActiveSoundKey")
                SoundRow(2, "Audio on Buff Loss", "buffLostSoundKey")

                -- Closes on a press off it and its lists; the bar menu underneath
                -- asks OverAny before dismissing itself on a click.
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

                -- Drag-and-drop: a bar row dragged onto another group's section (or
                -- the independent one) moves there; a zone holds every row of a
                -- section, so the whole section takes the drop. Inside the bar's own
                -- group the drop reorders instead, at the gap a green line marks. The
                -- drag flag exists before any OnUpdate reads it.
                local dropZones = {} -- { gid, label, frames = {rows...}, rows = {{frame, idx}...}, head, tail }
                local dragState = { idx = nil, name = nil }
                dropMenu._dragActive = false

                local function HoveredZone()
                    for _, zone in ipairs(dropZones) do
                        for _, f in ipairs(zone.frames) do
                            if f and f:IsMouseOver() then
                                return zone, f
                            end
                        end
                    end
                end

                -- Over a row of the dragged bar's own group: its new place among the
                -- members and the gap to mark (the header: before the first bar; the
                -- add row: after the last; a bar row: the half the cursor is in).
                -- nil when the drop would leave the order as it is.
                local function ReorderTarget(zone, over)
                    local rowList = zone and zone.rows
                    if not (rowList and over and dragState.idx) then
                        return nil
                    end
                    local from, gap
                    for k, r in ipairs(rowList) do
                        if r.idx == dragState.idx then
                            from = k
                        end
                        if r.frame == over then
                            local _, cy = GetCursorPosition()
                            local mid = (over:GetTop() + over:GetBottom()) / 2
                            gap = (cy / over:GetEffectiveScale() > mid) and k or k + 1
                        end
                    end
                    if over == zone.head then
                        gap = 1
                    elseif over == zone.tail then
                        gap = #rowList + 1
                    end
                    if not (from and gap) or gap == from or gap == from + 1 then
                        return nil
                    end
                    return (gap > from) and gap - 1 or gap, gap
                end

                local insLine = inner:CreateTexture(nil, "OVERLAY", nil, 7)
                insLine:SetHeight(2)
                local green = CludesUI.CLUDES_GREEN
                insLine:SetColorTexture(green.r, green.g, green.b, 0.9)
                insLine:Hide()
                local function ShowInsLine(rowList, gap)
                    local r = rowList[gap] or rowList[#rowList]
                    local edge = rowList[gap] and "TOP" or "BOTTOM"
                    insLine:ClearAllPoints()
                    insLine:SetPoint("LEFT", r.frame, edge .. "LEFT", 18, 0)
                    insLine:SetPoint("RIGHT", r.frame, edge .. "RIGHT", -8, 0)
                    insLine:Show()
                end

                -- The ghost under the cursor names the bar, and where it would go:
                -- accent while the drop would reorder or move it ("bar  >  group").
                local dragGhost
                local function GhostText(text, accent)
                    dragGhost._lbl:SetText(text or "")
                    if accent then
                        dragGhost._lbl:SetTextColor(ar, ag, ab, 1)
                    else
                        dragGhost._lbl:SetTextColor(1, 1, 1, 0.8)
                    end
                end
                local function GhostUpdate()
                    local cx, cy = GetCursorPosition()
                    local sc = UIParent:GetEffectiveScale()
                    dragGhost:ClearAllPoints()
                    dragGhost:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", cx / sc + 14, cy / sc - 22)
                    local zone, over = HoveredZone()
                    local place, gap = ReorderTarget(zone, over)
                    if place then
                        ShowInsLine(zone.rows, gap)
                        return GhostText(dragState.name, true)
                    end
                    insLine:Hide()
                    if zone and dragState.idx then
                        local bars = mod.GetTrackedBuffBars().bars
                        local dragged = bars and bars[dragState.idx]
                        if dragged and mod.TBBBarGroupID(dragged) ~= zone.gid then
                            return GhostText(dragState.name .. "  >  " .. zone.label, true)
                        end
                    end
                    GhostText(dragState.name, false)
                end
                -- One ghost frame for the session, dressed again by the first drag of each open.
                local function EnsureGhost()
                    if dragGhost then
                        return dragGhost
                    end
                    dragGhost = PoolKept(mod, "tbbDragGhost", "Frame", UIParent)
                    dragGhost:SetFrameStrata("TOOLTIP")
                    dragGhost:SetFrameLevel(500)
                    dragGhost:SetSize(10, 20)
                    local label = dragGhost:CreateFontString(nil, "OVERLAY")
                    label:SetFont(FONT_PATH, 11, GetCDMOptOutline())
                    label:SetPoint("BOTTOMLEFT", dragGhost, "BOTTOMLEFT", 0, 0)
                    dragGhost._lbl = label
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
                    local tex = b.spellID
                        and b.spellID > 0
                        and C_Spell
                        and C_Spell.GetSpellTexture
                        and C_Spell.GetSpellTexture(b.spellID)
                    return tex or 134400
                end
                -- A bar's menu name: its spell's (unless a popular preset), else its
                -- own name, else "Bar N"; an unassigned bar says so.
                local function BarDisplayName(b, idx, unassigned)
                    local name = (b.name and CludesUI.L(b.name)) or CludesUI.Lf("Bar %d", idx)
                    if not b.popularKey and b.spellID and b.spellID > 0 then
                        local details = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(b.spellID)
                        name = (details and details.name) or name
                    end
                    if unassigned then
                        name = name .. "  (" .. CludesUI.L("no buff assigned") .. ")"
                    end
                    return name
                end

                -- A full-width menu row at the running height mH.
                local function MenuRow(height)
                    local item = CreateFrame("Button", nil, inner)
                    item:SetHeight(height)
                    item:SetPoint("TOPLEFT", inner, "TOPLEFT", 1, -mH)
                    item:SetPoint("TOPRIGHT", inner, "TOPRIGHT", -1, -mH)
                    item:SetFrameLevel(dropMenu:GetFrameLevel() + 2)
                    return item
                end
                local function MenuFont(parent, size)
                    local fs = parent:CreateFontString(nil, "OVERLAY")
                    fs:SetFont(FONT_PATH, size, GetCDMOptOutline())
                    return fs
                end
                -- The row's white highlight, shown at alpha.
                local function RowHighlight(item, alpha)
                    local highlight = item:CreateTexture(nil, "ARTWORK")
                    highlight:SetAllPoints()
                    highlight:SetColorTexture(1, 1, 1, 1)
                    highlight:SetAlpha(alpha)
                    return highlight
                end
                -- A small X button at the row's right edge.
                local function CloseButton(item, alpha)
                    local button = CreateFrame("Button", nil, item)
                    button:SetSize(ICON_SZ, ICON_SZ)
                    button:SetPoint("RIGHT", item, "RIGHT", -8, 0)
                    button:SetFrameLevel(item:GetFrameLevel() + 2)
                    local icon = button:CreateTexture(nil, "OVERLAY")
                    icon:SetSize(ICON_SZ, ICON_SZ)
                    icon:SetPoint("CENTER")
                    if icon.SetSnapToPixelGrid then
                        icon:SetSnapToPixelGrid(false)
                        icon:SetTexelSnappingBias(0)
                    end
                    icon:SetTexture(MEDIA .. "icons\\cui-close.png")
                    button:SetAlpha(alpha)
                    return button
                end
                -- Sections after the first start 4 lower.
                local function SectionGap()
                    if mH > 4 then
                        mH = mH + 4
                    end
                end

                local function AddHeaderRow(textValue)
                    SectionGap()
                    local label = MenuFont(inner, 10)
                    label:SetTextColor(1, 1, 1, 0.9)
                    label:SetPoint("TOPLEFT", inner, "TOPLEFT", 10, -mH - 5)
                    label:SetText(textValue)
                    mH = mH + 20
                end

                -- Group header: clickable, selects the GROUP as editing context (group
                -- settings replace per-bar sections). gkey (optional) = group's globalKey,
                -- adds the GLOBAL tag + a delete button that removes it for every spec (with confirmation).
                local function AddGroupHeaderRow(groupId, gkey)
                    SectionGap()
                    local item = MenuRow(22)
                    local label = MenuFont(item, 10)
                    label:SetTextColor(1, 1, 1, 0.9)
                    label:SetPoint("LEFT", item, "LEFT", 10, 0)
                    local name = (mod.TBBGroupName and mod.TBBGroupName(groupId))
                        or (CludesUI.L("GROUP") .. " " .. groupId)
                    label:SetText(name)
                    if gkey then
                        local tag = MenuFont(item, 9)
                        tag:SetTextColor(ar, ag, ab, 0.9)
                        tag:SetPoint("LEFT", label, "RIGHT", 6, 0)
                        tag:SetText(CludesUI.L("GLOBAL"))
                    end
                    local edit = MenuFont(item, 10)
                    edit:SetTextColor(ar, ag, ab, 0.85)
                    edit:SetText(CludesUI.L("Edit Group"))
                    if gkey then
                        local del = CloseButton(item, 0.6)
                        del:SetScript("OnEnter", function()
                            del:SetAlpha(1)
                            CludesUI.ShowWidgetTooltip(
                                del,
                                CludesUI.L("Delete this global group for all specs")
                            )
                        end)
                        del:SetScript("OnLeave", function()
                            del:SetAlpha(0.6)
                            CludesUI.HideWidgetTooltip()
                        end)
                        del:SetScript("OnClick", function()
                            dropMenu:Hide()
                            CludesUI:ShowConfirmPopup({
                                title = "Delete Global Group",
                                message = CludesUI.Lf(
                                    'Delete "%1$s" for ALL specs? Bars keep their current positions.',
                                    name
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
                        edit:SetPoint("RIGHT", del, "LEFT", -8, 0)
                    else
                        edit:SetPoint("RIGHT", item, "RIGHT", -10, 0)
                    end
                    local rest = (_tbbSelectedGroup == groupId) and selA or 0
                    local highlight = RowHighlight(item, rest)
                    item:SetScript("OnEnter", function()
                        label:SetTextColor(1, 1, 1, 1)
                        edit:SetTextColor(1, 1, 1, 0.9)
                        highlight:SetAlpha(hlA)
                    end)
                    item:SetScript("OnLeave", function()
                        label:SetTextColor(1, 1, 1, 0.9)
                        edit:SetTextColor(ar, ag, ab, 0.85)
                        highlight:SetAlpha(rest)
                    end)
                    item:SetScript("OnClick", function()
                        dropMenu:Hide()
                        _tbbSelectedGroup = groupId
                        CludesUI:RefreshPage(true)
                    end)
                    mH = mH + 22
                    return item
                end

                -- A bar row: its icon (click: change the buff), name, the speaker
                -- (bars that can cue a sound) and delete. Click selects it (no buff
                -- yet: opens the picker), right-click its sound menu, drag moves it.
                local function AddBarItem(idx, b, indent)
                    local item = MenuRow(ITEM_H)
                    local unassigned = (not b.spellID or b.spellID == 0) and not b.glowBased
                    local icon = item:CreateTexture(nil, "OVERLAY")
                    icon:SetSize(ITEM_H - 8, ITEM_H - 8)
                    icon:SetPoint("LEFT", item, "LEFT", 10 + (indent or 0), 0)
                    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    icon:SetTexture(BarIconID(b))
                    if unassigned then
                        icon:SetDesaturated(true)
                        icon:SetAlpha(0.35)
                    end

                    -- The icon changes this bar's buff (a green border shows it).
                    local iconBtn = CreateFrame("Button", nil, item)
                    iconBtn:SetAllPoints(icon)
                    iconBtn:SetFrameLevel(item:GetFrameLevel() + 3)
                    local green = CludesUI.CLUDES_GREEN
                    local ring = Pix.CreateBorder(iconBtn, green.r, green.g, green.b, 1, 1, "OVERLAY", 7)
                    if ring then
                        ring:Hide()
                    end
                    iconBtn:SetScript("OnEnter", function()
                        if ring then
                            ring:Show()
                        end
                        CludesUI.ShowWidgetTooltip(iconBtn, CludesUI.L("Change buff"))
                    end)
                    iconBtn:SetScript("OnLeave", function()
                        if ring then
                            ring:Hide()
                        end
                        CludesUI.HideWidgetTooltip()
                    end)
                    iconBtn:SetScript("OnClick", function()
                        dropMenu:Hide()
                        OpenBuffPickerForBar(idx)
                    end)

                    local label = MenuFont(item, 11)
                    label:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                    label:SetJustifyH("LEFT")
                    label:SetWordWrap(false)
                    label:SetMaxLines(1)
                    label:SetPoint("LEFT", icon, "RIGHT", 6, 0)
                    local name = BarDisplayName(b, idx, unassigned)
                    label:SetText(name)
                    local function RestHighlight()
                        return idx == _tbbSelectedBar and selA or 0
                    end
                    local highlight = RowHighlight(item, RestHighlight())
                    local del = CloseButton(item, 0.75)
                    label:SetPoint("RIGHT", del, "LEFT", -4, 0)
                    local function Lit()
                        label:SetTextColor(1, 1, 1, 1)
                        highlight:SetAlpha(hlA)
                    end
                    local function Rest()
                        label:SetTextColor(tDimR, tDimG, tDimB, tDimA)
                        highlight:SetAlpha(RestHighlight())
                    end

                    -- Only a bar that can cue gets the sound menu: on a row right-click and
                    -- on the speaker button, dimmed ("Add Audio Effect") while the bar has
                    -- no Audio on Buff Gain/Loss sound and full ("Edit Audio Effect") once
                    -- it has one. The sound menu repaints it through item._sndPaint.
                    local soundable = BarTakesSound(b)
                    if soundable then
                        local speaker = CreateFrame("Button", nil, item)
                        speaker:SetSize(ICON_SZ, ICON_SZ)
                        speaker:SetPoint("RIGHT", del, "LEFT", -6, 0)
                        speaker:SetFrameLevel(item:GetFrameLevel() + 2)
                        local glyph = speaker:CreateTexture(nil, "OVERLAY")
                        glyph:SetAllPoints()
                        glyph:SetAtlas(CludesUI.SOUND_ICON_ATLAS)
                        local function HasSound()
                            local gain, loss = b.buffActiveSoundKey, b.buffLostSoundKey
                            return (gain and gain ~= "none") or (loss and loss ~= "none")
                        end
                        local function RestAlpha()
                            return HasSound() and 0.8 or 0.3
                        end
                        item._sndPaint = function()
                            if not speaker:IsMouseOver() then
                                speaker:SetAlpha(RestAlpha())
                            end
                        end
                        speaker:SetAlpha(RestAlpha())
                        speaker:SetScript("OnEnter", function(self)
                            self:SetAlpha(1)
                            Lit()
                            CludesUI.ShowWidgetTooltip(
                                self,
                                HasSound() and CludesUI.L("Edit Audio Effect")
                                    or CludesUI.L("Add Audio Effect")
                            )
                        end)
                        speaker:SetScript("OnLeave", function(self)
                            CludesUI.HideWidgetTooltip()
                            self:SetAlpha(RestAlpha())
                            if not item:IsMouseOver() then
                                Rest()
                            end
                        end)
                        -- The bar menu stays open underneath, as with the row right-click.
                        speaker:SetScript("OnClick", function()
                            OpenBarSoundMenu(idx, item)
                        end)
                        label:SetPoint("RIGHT", speaker, "LEFT", -4, 0)
                    end

                    del:SetScript("OnEnter", function()
                        del:SetAlpha(1)
                        Lit()
                    end)
                    del:SetScript("OnLeave", function()
                        if item:IsMouseOver() then
                            return
                        end
                        del:SetAlpha(0.75)
                        Rest()
                    end)
                    del:SetScript("OnClick", function()
                        dropMenu:Hide()
                        CludesUI:ShowConfirmPopup({
                            title = "Delete Bar",
                            message = CludesUI.Lf('Delete "%1$s"?', name),
                            confirmText = "Delete",
                            cancelText = "Cancel",
                            onConfirm = function()
                                mod.RemoveTrackedBuffBar(idx)
                                CludesUI:RefreshPage(true)
                            end,
                        })
                    end)
                    item:SetScript("OnEnter", function()
                        Lit()
                        del:SetAlpha(1)
                    end)
                    item:SetScript("OnLeave", function()
                        Rest()
                        del:SetAlpha(0.75)
                    end)
                    item:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                    item:SetScript("OnClick", function(_, mouseButton)
                        if mouseButton == "RightButton" then
                            -- The bar menu stays open underneath, like the CDM icon menu.
                            if soundable then
                                OpenBarSoundMenu(idx, item)
                            end
                            return
                        end
                        dropMenu:Hide()
                        if unassigned then
                            OpenBuffPickerForBar(idx) -- no buff yet: straight to the picker
                        else
                            _tbbSelectedBar = idx
                            _tbbSelectedGroup = nil
                            CludesUI:RefreshPage(true)
                        end
                    end)

                    -- Drag to move between groups or reorder within one (the zone under
                    -- the cursor at release takes the drop).
                    item:RegisterForDrag("LeftButton")
                    item:SetScript("OnDragStart", function()
                        dropMenu._dragActive = true
                        dragState.idx, dragState.name = idx, name
                        local ghost = EnsureGhost()
                        ghost._lbl:SetText(name)
                        ghost._lbl:SetTextColor(1, 1, 1, 0.8)
                        ghost:Show()
                        ghost:SetScript("OnUpdate", GhostUpdate)
                    end)
                    item:SetScript("OnDragStop", function()
                        local moveIdx = dragState.idx
                        local zone, over = HoveredZone()
                        local place = ReorderTarget(zone, over)
                        StopDrag()
                        if moveIdx and place then
                            dropMenu:Hide()
                            ReorderBarInGroup(moveIdx, place)
                        elseif moveIdx and zone then
                            MoveBarToGroup(moveIdx, zone.gid)
                        end
                    end)
                    mH = mH + ITEM_H
                    return item
                end

                local function AddActionItem(textValue, indent, onClick)
                    local item = MenuRow(ITEM_H)
                    local label = MenuFont(item, 11)
                    label:SetPoint("LEFT", item, "LEFT", 10 + (indent or 0), 0)
                    label:SetJustifyH("LEFT")
                    label:SetText(textValue)
                    label:SetTextColor(ar, ag, ab, 0.85)
                    local highlight = RowHighlight(item, 0)
                    item:SetScript("OnEnter", function()
                        label:SetTextColor(1, 1, 1, 1)
                        highlight:SetAlpha(hlA)
                    end)
                    item:SetScript("OnLeave", function()
                        label:SetTextColor(ar, ag, ab, 0.85)
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
                local function AddToGroupItem(gid)
                    return AddActionItem(CludesUI.L("+ Add Bar to Group"), 8, function()
                        SelectNewBar(mod.AddTrackedBuffBar(gid))
                    end)
                end
                local function GroupZone(gid)
                    local zone = {
                        gid = gid,
                        label = (mod.TBBGroupName and mod.TBBGroupName(gid))
                            or (CludesUI.L("Group") .. " " .. gid),
                        frames = {},
                    }
                    dropZones[#dropZones + 1] = zone
                    return zone
                end

                -- Grouped bars, one section per group (each section doubles as a drop zone for bar drags).
                local renderedGlobal = {}
                for _, groupId in ipairs(mod.TBBGroupIDsInUse and mod.TBBGroupIDsInUse() or {}) do
                    local gkey = mod.TBBGroupGlobalKey and mod.TBBGroupGlobalKey(groupId) or nil
                    if gkey then
                        renderedGlobal[gkey] = true
                    end
                    local zone = GroupZone(groupId)
                    zone.rows = {}
                    zone.head = AddGroupHeaderRow(groupId, gkey)
                    zone.frames[1] = zone.head
                    for idx, b in ipairs(t.bars) do
                        if mod.TBBBarGroupID(b) == groupId then
                            local row = AddBarItem(idx, b, 8)
                            zone.frames[#zone.frames + 1] = row
                            zone.rows[#zone.rows + 1] = { frame = row, idx = idx }
                        end
                    end
                    zone.tail = AddToGroupItem(groupId)
                    zone.frames[#zone.frames + 1] = zone.tail
                end

                -- Global groups with no bars on this spec are always listed so any spec can
                -- assign/drag bars into them; selecting one edits its shared settings (a normal drop zone).
                for _, gkey in ipairs(mod.TBBGlobalGroupKeys and mod.TBBGlobalGroupKeys() or {}) do
                    local lgid = not renderedGlobal[gkey] and mod.TBBEnsureLocalGroupForGlobal(gkey)
                    if lgid then
                        local zone = GroupZone(lgid)
                        zone.frames[1] = AddGroupHeaderRow(lgid, gkey)
                        zone.frames[2] = AddToGroupItem(lgid)
                    end
                end

                -- Independent bars (the section is the "make independent" zone).
                local indepZone = { gid = 0, label = CludesUI.L("Independent"), frames = {} }
                dropZones[#dropZones + 1] = indepZone
                local independent, anySoundable = {}, false
                for idx, b in ipairs(t.bars) do
                    if mod.TBBBarGroupID(b) == 0 then
                        independent[#independent + 1] = idx
                    end
                    anySoundable = anySoundable or BarTakesSound(b)
                end
                if #independent > 0 then
                    AddHeaderRow(CludesUI.L("INDEPENDENT BARS"))
                    for _, idx in ipairs(independent) do
                        indepZone.frames[#indepZone.frames + 1] = AddBarItem(idx, t.bars[idx], 8)
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

                -- Hints: dragging (with more than one bar) and, while any bar can
                -- take a sound, the row right-click (Audio on Buff Gain / Loss).
                local function Hint(text)
                    local fs = MenuFont(inner, 10)
                    fs:SetTextColor(1, 1, 1, 0.35)
                    fs:SetPoint("TOP", inner, "TOP", 0, -mH - 4)
                    fs:SetText(CludesUI.L(text))
                    mH = mH + 20
                end
                if #t.bars > 1 then
                    Hint("Drag a bar to reorder it or move it into another group")
                end
                if anySoundable then
                    Hint("Right-click a bar to set its sounds")
                end

                -- A tall menu scrolls (wheel, 30 a notch) within MENU_MAX_H.
                local totalH = mH + 4
                inner:SetHeight(totalH)
                if totalH > MENU_MAX_H then
                    dropMenu:SetHeight(MENU_MAX_H)
                    local scroll = CreateFrame("ScrollFrame", nil, dropMenu)
                    scroll:SetPoint("TOPLEFT", 0, -1)
                    scroll:SetPoint("BOTTOMRIGHT", 0, 1)
                    scroll:SetFrameLevel(dropMenu:GetFrameLevel() + 1)
                    scroll:EnableMouseWheel(true)
                    scroll:SetScrollChild(inner)
                    local pos, maxScroll = 0, totalH - MENU_MAX_H
                    scroll:SetScript("OnMouseWheel", function(_, delta)
                        pos = math.max(0, math.min(maxScroll, pos - delta * 30))
                        scroll:SetVerticalScroll(pos)
                    end)
                else
                    dropMenu:SetHeight(totalH)
                end
                -- A press outside closes it, except mid-drag (a drag leaves the menu
                -- with the button held) and in the row's sound menu or its lists.
                dropMenu:SetScript("OnUpdate", function(m)
                    if m._dragActive then
                        return
                    end
                    local sound = ddBtn._tbbSndMenu
                    if sound and sound:IsShown() and sound._overAny and sound._overAny() then
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

            -- The button lights while hovered or while its menu is open.
            local function Lit(on)
                ddLbl:SetAlpha(on and mTxtHA or mTxtA)
                ddBrd:SetColor(1, 1, 1, on and mBrdHA or mBrdA)
                ddBg:SetColorTexture(mBgR, mBgG, mBgB, on and mBgHA or mBgA)
            end
            local function HideMenus()
                if ddMenu then
                    ddMenu:Hide()
                end
                if ddBtn._tbbSndMenu then
                    ddBtn._tbbSndMenu:Hide()
                end
            end
            ddBtn:SetScript("OnEnter", function()
                Lit(true)
            end)
            ddBtn:SetScript("OnLeave", function()
                if not (ddMenu and ddMenu:IsShown()) then
                    Lit(false)
                end
            end)
            ddBtn:SetScript("OnClick", function()
                -- An open buff picker (e.g. from "+ Add Bar to Group") yields to this menu.
                if _tbbSpellPickerMenu and _tbbSpellPickerMenu:IsShown() then
                    _tbbSpellPickerMenu:Hide()
                end
                if ddMenu and ddMenu:IsShown() then
                    ddMenu:Hide()
                else
                    BuildDDMenu()
                end
            end)
            ddBtn:HookScript("OnHide", HideMenus)

            -- The label follows in-place refreshes (a group rename commits without a page rebuild).
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
            -- "Remove Bar from All Specs" (the inverse); dimmed unless a preset/custom-buff
            -- bar is selected. WoW Forever runs a class on one spec: nowhere to copy to.
            local broadcastSel = (not _tbbSelectedGroup) and SelectedTBB() or nil
            local canBroadcast = not CludesUI.IS_FOREVER
                    and mod.IsTrackedBuffBarBroadcastable
                    and mod.IsTrackedBuffBarBroadcastable(broadcastSel)
                or false
            local isBroadcast = canBroadcast
                    and mod.IsTrackedBuffBarBroadcast
                    and mod.IsTrackedBuffBarBroadcast(broadcastSel)
                or false
            local EGc = CludesUI.CLUDES_GREEN
            local PADc = CludesUI.CONTENT_PAD or 10
            local CARD_H, CARD_GAP, CARD_ICON = 60, 12, 24
            local cardTotalW = hostFrame:GetWidth() - PADc * 2
            local CARD_W = math.floor((cardTotalW - CARD_GAP * 2) / 3)
            posY = posY - 10
            local cardRow = CreateFrame("Frame", nil, hostFrame)
            Pix.Size(cardRow, cardTotalW, CARD_H)
            Pix.Point(cardRow, "TOPLEFT", hostFrame, "TOPLEFT", PADc, posY)

            -- A card: accent top edge, icon, title and one-line description; hover
            -- lifts it. disabledTip: dimmed, and the tip says why.
            local function MakeActionCard(slot, icon, title, desc, onClick, disabledTip)
                local card = CreateFrame("Button", nil, cardRow)
                Pix.Size(card, CARD_W, CARD_H)
                Pix.Point(card, "TOPLEFT", cardRow, "TOPLEFT", (CARD_W + CARD_GAP) * slot, 0)
                card:SetFrameLevel(cardRow:GetFrameLevel() + 2)
                local frameArt = CludesUI.MakeRoundedCard(card, 0.12, 0.50, 2)
                frameArt.accent:SetColorTexture(EGc.r, EGc.g, EGc.b, 0.6)
                local glyph = card:CreateTexture(nil, "ARTWORK")
                glyph:SetSize(CARD_ICON, CARD_ICON)
                Pix.Point(glyph, "LEFT", card, "LEFT", 18, 0)
                glyph:SetTexture("Interface\\AddOns\\CludesUI\\media\\icons\\" .. icon)
                glyph:SetVertexColor(EGc.r, EGc.g, EGc.b)
                glyph:SetAlpha(0.6)
                if glyph.SetSnapToPixelGrid then
                    glyph:SetSnapToPixelGrid(false)
                    glyph:SetTexelSnappingBias(0)
                end
                local function Line(size, alpha, text, anchor, relPoint, x, y)
                    local fs = CludesUI.MakeFont(card, size, nil, 1, 1, 1, alpha)
                    Pix.Point(fs, "TOPLEFT", anchor, relPoint, x, y)
                    Pix.Point(fs, "RIGHT", card, "RIGHT", -10, 0)
                    fs:SetJustifyH("LEFT")
                    fs:SetWordWrap(false)
                    fs:SetText(CludesUI.L(text))
                    return fs
                end
                local titleFs = Line(12, 0.9, title, glyph, "TOPRIGHT", 14, 1)
                Line(10, 0.35, desc, titleFs, "BOTTOMLEFT", 0, -4)
                if disabledTip then
                    card:SetAlpha(0.45)
                    card:SetScript("OnEnter", function()
                        CludesUI.ShowWidgetTooltip(card, disabledTip)
                    end)
                    card:SetScript("OnLeave", function()
                        CludesUI.HideWidgetTooltip()
                    end)
                    return card
                end
                local function Lift(on)
                    if on then
                        frameArt.bg:SetColorTexture(0.100, 0.110, 0.124, 0.50)
                    else
                        frameArt.bg:SetColorTexture(0.062, 0.070, 0.082, 0.50)
                    end
                    frameArt:SetColor(1, 1, 1, on and 0.22 or 0.12)
                    titleFs:SetAlpha(on and 1 or 0.9)
                    glyph:SetAlpha(on and 0.85 or 0.6)
                end
                card:SetScript("OnEnter", function()
                    Lift(true)
                end)
                card:SetScript("OnLeave", function()
                    Lift(false)
                end)
                card:SetScript("OnClick", onClick)
                return card
            end

            MakeActionCard(
                0,
                "power.png",
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
            MakeActionCard(1, "cui-open.png", "Open Blizzard CDM", "Manage your tracked bars.", function()
                if mod.OpenBlizzardCDMTab then
                    mod.OpenBlizzardCDMTab(true)
                end
            end)

            -- Add to (or remove from) every other spec, after a confirm naming the bar.
            local function Broadcast()
                local sel = SelectedTBB()
                if _tbbSelectedGroup or not mod.IsTrackedBuffBarBroadcastable(sel) then
                    return
                end
                local name = sel.name or "Bar"
                if (not sel.popularKey or sel.popularKey == "") and sel.spellID and sel.spellID > 0 then
                    local details = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(sel.spellID)
                    name = (details and details.name) or name
                end
                local removing = mod.IsTrackedBuffBarBroadcast and mod.IsTrackedBuffBarBroadcast(sel)
                local step = removing and mod.RemoveBarFromAllSpecs or mod.AddBarToAllSpecs
                CludesUI:ShowConfirmPopup({
                    title = removing and "Remove Bar from All Specs" or "Add Bar to All Specs",
                    message = removing
                            and CludesUI.Lf(
                                'Remove "%1$s" from every other spec? The bar in this spec is kept.',
                                name
                            )
                        or CludesUI.Lf(
                            'Add "%1$s" to every spec? It will be copied to each of your specs that doesn\'t already have it.',
                            name
                        ),
                    confirmText = removing and "Remove from All" or "Add to All Specs",
                    cancelText = "Cancel",
                    onConfirm = function()
                        if step then
                            step(_tbbSelectedBar)
                        end
                        CludesUI:RefreshPage(true)
                    end,
                })
            end
            local whyNot
            if not canBroadcast then
                if CludesUI.IS_FOREVER then
                    whyNot = "WoW Forever has no other specs to copy this bar to"
                elseif _tbbSelectedGroup then
                    whyNot = "Select a bar to broadcast it to other specs"
                else
                    whyNot = "Only preset or custom buff bars can be added to all specs"
                end
            end
            MakeActionCard(
                2,
                "sync.png",
                isBroadcast and "Remove Bar from All Specs" or "Add Bar to All Specs",
                "Copy this bar to every spec.",
                Broadcast,
                whyNot
            )
            posY = posY - CARD_H - 12

            -- Preset Style panel (styled like Profiles & Presets "Active Profile"): pick a
            -- saved style preset and apply it to the selected bar/group, or save the current
            -- style as one. Presets are profile-wide; new bars resolve one by association at creation.
            -- Its buttons: the wide-button look with the dropdown's white border (and hovered).
            local PROF_BTN_COLOURS = {}
            do
                local wc = CludesUI.WB_COLOURS
                for i = 1, 24 do
                    PROF_BTN_COLOURS[i] = wc[i]
                end
                PROF_BTN_COLOURS[9], PROF_BTN_COLOURS[10], PROF_BTN_COLOURS[11] = 1, 1, 1
                PROF_BTN_COLOURS[12] = CludesUI.DD_BRD_A
                PROF_BTN_COLOURS[13], PROF_BTN_COLOURS[14], PROF_BTN_COLOURS[15] = 1, 1, 1
                PROF_BTN_COLOURS[16] = CludesUI.DD_BRD_HA or 0.30
            end
            local LABEL_H, CTRL_H = 16, 30
            local PAD_X, PAD_Y = 24, 20
            local GAP_DD, GAP_BTN = 30, 14
            local PR_ROW_H = PAD_Y + LABEL_H + 4 + CTRL_H + PAD_Y
            local innerW = cardTotalW - PAD_X * 2
            local DD_W = math.floor(innerW * 0.30)
            local BTN_W = math.floor((innerW - DD_W - GAP_DD - GAP_BTN * 2) / 3)

            local prRow = CreateFrame("Frame", nil, hostFrame)
            Pix.Size(prRow, cardTotalW, PR_ROW_H)
            Pix.Point(prRow, "TOPLEFT", hostFrame, "TOPLEFT", PADc, posY)
            CludesUI.MakeRoundedCard(prRow, 0.10, 0.50)
            -- "Preset Style" in the accent, as "Active Profile" is.
            local prLbl = CludesUI.MakeFont(prRow, 12, nil, EGc.r, EGc.g, EGc.b, 0.7)
            Pix.Point(prLbl, "TOPLEFT", prRow, "TOPLEFT", PAD_X, -PAD_Y)
            prLbl:SetText(CludesUI.L("Preset Style"))
            prLbl:SetJustifyH("LEFT")

            -- Live reads: the label, menu and apply buttons all pull from the current
            -- list, so saves, renames and deletes never go stale. The saved pick, else
            -- the first preset.
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
                local name = SelectedPresetName()
                return name and mod.FindTBBStylePreset and mod.FindTBBStylePreset(name) or nil
            end

            -- The preset dropdown: its own button and menu (the standard look) so each
            -- row can carry rename and delete, as the "Active Profile" dropdown does.
            local aS = CludesUI.RD_DD_COLOURS
            local prDD = CreateFrame("Button", nil, prRow)
            Pix.Size(prDD, DD_W, CTRL_H)
            prDD:SetFrameLevel(prRow:GetFrameLevel() + 2)
            local prDDBg = prDD:CreateTexture(nil, "BACKGROUND")
            prDDBg:SetAllPoints()
            prDDBg:SetColorTexture(CludesUI.DD_BG_R, CludesUI.DD_BG_G, CludesUI.DD_BG_B, CludesUI.DD_BG_A)
            local prDDBrd = CludesUI.MakeRoundedBorder(prDD, 1, 1, 1, CludesUI.DD_BRD_A, prDDBg)
            -- The resting alpha rides the text colour, the channel the hover paint
            -- writes, so a hover and leave land back on it.
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

            -- One preset menu frame for the session, dressed again by every page build
            -- (its rows pooled under it), at the button's scale; a press off it and
            -- the button closes it.
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
                self:SetScale(prDD:GetEffectiveScale() / UIParent:GetEffectiveScale())
                self:SetScript("OnUpdate", function(m)
                    local pressed = IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")
                    if pressed and not prDD:IsMouseOver() and not m:IsMouseOver() then
                        m:Hide()
                    end
                end)
            end)

            local X_SZ = 14
            local prItems = {}

            -- A small icon button on a preset row (delete, rename), resting dim.
            local function RowIconButton(row, icon, anchor, relPoint, x)
                local button = CreateFrame("Button", nil, row)
                button:SetSize(X_SZ, X_SZ)
                button:SetPoint("RIGHT", anchor, relPoint, x, 0)
                button:SetFrameLevel(row:GetFrameLevel() + 2)
                local tex = button:CreateTexture(nil, "OVERLAY")
                tex:SetAllPoints()
                if tex.SetSnapToPixelGrid then
                    tex:SetSnapToPixelGrid(false)
                    tex:SetTexelSnappingBias(0)
                end
                tex:SetTexture("Interface\\AddOns\\CludesUI\\media\\icons\\" .. icon)
                button:SetAlpha(0.4)
                return button
            end

            -- One preset row, made once and reused: its name, delete and rename.
            -- Hovering the row or either button lights the row and both buttons.
            local function MakePresetRow()
                local row = CreateFrame("Button", nil, prMenu)
                row:SetHeight(26)
                row:SetFrameLevel(prMenu:GetFrameLevel() + 1)
                local label = row:CreateFontString(nil, "OVERLAY")
                label:SetFont(FONT_PATH, 13, GetCDMOptOutline())
                label:SetPoint("LEFT", row, "LEFT", 10, 0)
                label:SetPoint("RIGHT", row, "RIGHT", -(X_SZ * 2 + 26), 0)
                label:SetJustifyH("LEFT")
                label:SetWordWrap(false)
                label:SetMaxLines(1)
                label:SetTextColor(1, 1, 1, CludesUI.TEXT_DIM_A)
                row._lbl = label
                local highlight = row:CreateTexture(nil, "ARTWORK")
                highlight:SetAllPoints()
                highlight:SetColorTexture(1, 1, 1, 1)
                highlight:SetAlpha(0)
                row._hl = highlight
                local del = RowIconButton(row, "cui-close.png", row, "RIGHT", -8)
                local rename = RowIconButton(row, "cui-edit.png", del, "LEFT", -4)
                row._xBtn, row._editBtn = del, rename

                local function OverButton()
                    return del:IsMouseOver() or rename:IsMouseOver()
                end
                local function Lit()
                    label:SetTextColor(1, 1, 1, 1)
                    highlight:SetAlpha(CludesUI.DD_ITEM_HL_A)
                    del:SetAlpha(0.8)
                    rename:SetAlpha(0.8)
                end
                local function Rest()
                    label:SetTextColor(1, 1, 1, CludesUI.TEXT_DIM_A)
                    highlight:SetAlpha(row._isSel and CludesUI.DD_ITEM_SEL_A or 0)
                    del:SetAlpha(0.4)
                    rename:SetAlpha(0.4)
                end
                row:SetScript("OnEnter", function()
                    if not row._isEmpty then
                        Lit()
                    end
                end)
                row:SetScript("OnLeave", function()
                    if not row._isEmpty and not OverButton() then
                        Rest()
                    end
                end)
                for button, tip in pairs({ [del] = "Delete", [rename] = "Rename" }) do
                    button:SetScript("OnEnter", function(self)
                        Lit()
                        self:SetAlpha(1)
                        CludesUI.ShowWidgetTooltip(self, CludesUI.L(tip))
                    end)
                    button:SetScript("OnLeave", function(self)
                        if row:IsMouseOver() or OverButton() then
                            self:SetAlpha(0.8)
                        else
                            Rest()
                        end
                        CludesUI.HideWidgetTooltip()
                    end)
                end
                return row
            end

            local function DeletePreset(name)
                prMenu:Hide()
                CludesUI:ShowConfirmPopup({
                    title = CludesUI.L("Delete Preset"),
                    message = CludesUI.Lf('Delete "%1$s"?', name),
                    confirmText = CludesUI.L("Delete"),
                    cancelText = CludesUI.L("Cancel"),
                    onConfirm = function()
                        if mod.DeleteTBBStylePreset then
                            mod.DeleteTBBStylePreset(name)
                        end
                        CludesUI:RefreshPage(true)
                    end,
                })
            end
            -- A new name must be new: an empty or unchanged one does nothing, a taken one says so.
            local function RenamePreset(name)
                prMenu:Hide()
                CludesUI:ShowInputPopup({
                    title = CludesUI.L("Rename Preset"),
                    message = CludesUI.Lf('Enter a new name for "%1$s":', name),
                    placeholder = name,
                    confirmText = CludesUI.L("Rename"),
                    cancelText = CludesUI.L("Cancel"),
                    onConfirm = function(newName)
                        newName = newName and strtrim(newName) or ""
                        if newName == "" or newName == name then
                            return
                        end
                        if mod.FindTBBStylePreset and mod.FindTBBStylePreset(newName) then
                            CludesUI.PrintError(CludesUI.Lf('A preset named "%1$s" already exists.', newName))
                            return
                        end
                        if mod.RenameTBBStylePreset then
                            mod.RenameTBBStylePreset(name, newName)
                        end
                        CludesUI:RefreshPage(true)
                    end,
                })
            end

            -- Dresses a row for a saved preset (pick, delete, rename), or with
            -- none saved as the one dim row that only closes the menu.
            local function DressPresetRow(row, preset, selName)
                local empty = preset == nil
                row._isEmpty = empty
                row._isSel = not empty and preset.name == selName
                row._lbl:SetText(empty and CludesUI.L("No Saved Presets") or preset.name)
                row._lbl:SetTextColor(1, 1, 1, empty and 0.35 or CludesUI.TEXT_DIM_A)
                row._hl:SetAlpha(row._isSel and CludesUI.DD_ITEM_SEL_A or 0)
                for _, button in ipairs({ row._xBtn, row._editBtn }) do
                    button:SetShown(not empty)
                    if not empty then
                        button:SetAlpha(0.4)
                    end
                end
                if empty then
                    row:SetScript("OnClick", function()
                        prMenu:Hide()
                    end)
                    return
                end
                local name = preset.name
                row:SetScript("OnClick", function()
                    prMenu:Hide()
                    local p = DB()
                    if p then
                        p.tbbSelectedStylePreset = name
                    end
                    UpdatePrDDLabel()
                end)
                row._xBtn:SetScript("OnClick", function()
                    DeletePreset(name)
                end)
                row._editBtn:SetScript("OnClick", function()
                    RenamePreset(name)
                end)
            end

            local function RebuildPresetMenu()
                for _, row in ipairs(prItems) do
                    row:Hide()
                end
                local presets = (mod.GetTBBStylePresets and mod.GetTBBStylePresets()) or {}
                local selName = SelectedPresetName()
                local mH = 4
                for i = 1, math.max(#presets, 1) do
                    prItems[i] = prItems[i] or MakePresetRow()
                    local row = prItems[i]
                    row:SetPoint("TOPLEFT", prMenu, "TOPLEFT", 1, -mH)
                    row:SetPoint("TOPRIGHT", prMenu, "TOPRIGHT", -1, -mH)
                    DressPresetRow(row, presets[i], selName)
                    row:Show()
                    mH = mH + 26
                end
                prMenu:SetHeight(mH + 4)
            end

            -- The dropdown's paint from the shared colour set: resting, or hovered
            -- (also while its menu is open).
            local function PrPaint(hovered)
                local o = hovered and 4 or 0
                prDDLbl:SetTextColor(aS[17 + o], aS[18 + o], aS[19 + o], aS[20 + o])
                prDDBrd:SetColor(aS[9 + o], aS[10 + o], aS[11 + o], aS[12 + o])
                prDDBg:SetColorTexture(aS[1 + o], aS[2 + o], aS[3 + o], aS[4 + o])
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
                PrPaint(true)
            end)
            prDD:SetScript("OnLeave", function()
                if not prMenu:IsShown() then
                    PrPaint(false)
                end
            end)
            prDD:HookScript("OnHide", function()
                prMenu:Hide()
            end)
            prMenu:HookScript("OnShow", function()
                PrPaint(true)
            end)
            prMenu:SetScript("OnHide", function(self)
                self:SetScript("OnUpdate", nil)
                PrPaint(prDD:IsMouseOver() and true or false)
            end)

            -- A button with a dim label above, as the profile row's "Assign to Spec" /
            -- "New Profile" columns; slot 0-2 right of the dropdown.
            local function PresetBtn(text, slot, buttonText, tooltip, onClick)
                local label = CludesUI.MakeFont(prRow, 12, nil, 1, 1, 1, 0.45)
                Pix.Point(label, "LEFT", prLbl, "LEFT", DD_W + GAP_DD + (BTN_W + GAP_BTN) * slot, 0)
                label:SetText(CludesUI.L(text))
                label:SetJustifyH("LEFT")
                local button = CreateFrame("Button", nil, prRow)
                Pix.Size(button, BTN_W, CTRL_H)
                Pix.Point(button, "TOPLEFT", label, "BOTTOMLEFT", 0, -6)
                button:SetFrameLevel(prRow:GetFrameLevel() + 2)
                CludesUI.MakeStyledButton(button, buttonText, 11, PROF_BTN_COLOURS, onClick)
                button:HookScript("OnEnter", function()
                    CludesUI.ShowWidgetTooltip(button, tooltip)
                end)
                button:HookScript("OnLeave", function()
                    CludesUI.HideWidgetTooltip()
                end)
                return button
            end
            local function Applied()
                RefreshTBB()
                CludesUI:RefreshPage()
            end
            PresetBtn(
                "Apply to Bar",
                0,
                "Apply to Bar",
                "Apply the selected preset's style to this bar.",
                function()
                    local preset = SelectedPreset()
                    local sel = preset and not _tbbSelectedGroup and SelectedTBB()
                    if sel then
                        mod.ApplyTBBStylePresetToCfg(preset, sel)
                        Applied()
                    end
                end
            )
            -- The selected group, or the selected bar's (nothing for an independent bar).
            PresetBtn(
                "Apply to Group",
                1,
                "Apply to Group",
                "Apply the selected preset's style to every bar in this group.",
                function()
                    local preset = SelectedPreset()
                    if not preset then
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
                    for _, c in ipairs(mod.GetTrackedBuffBars().bars or {}) do
                        if mod.TBBBarGroupID(c) == groupId then
                            mod.ApplyTBBStylePresetToCfg(preset, c)
                        end
                    end
                    Applied()
                end
            )
            -- Save New Preset: the edited style under a name (blank: the next free
            -- "Preset N"), which becomes the selected preset.
            PresetBtn(
                "New Preset",
                2,
                "Save New Preset",
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
                        onConfirm = function(name)
                            if not name or name == "" then
                                name = UniqueTBBPresetName()
                            end
                            if mod.SaveTBBStylePreset and mod.SaveTBBStylePreset(name, source) then
                                local p = DB()
                                if p then
                                    p.tbbSelectedStylePreset = name
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
            -- A group layout edit: rebuild the bars, repaint the popout (the soft
            -- page refresh takes the fast path past it) and refresh the page.
            local function GroupLayoutChanged()
                mod.BuildTrackedBuffBars()
                RefreshTBBPopout()
                CludesUI:RefreshPage()
            end
            local function GlobalKey()
                return mod.TBBGroupGlobalKey and mod.TBBGroupGlobalKey(groupId)
            end
            local function GlobalEntry()
                local gk = GlobalKey()
                return gk and mod.TBBGlobalGroup and mod.TBBGlobalGroup(gk) or nil
            end

            heading, hgt = W:SectionHeader(hostFrame, "GROUP SETTINGS", posY)
            posY = posY - hgt
            -- The group's mover: a global group's TBBG_ element, else its anchor
            -- bar's (nil while no member is enabled: the click then does nothing).
            CludesUI.BuildSectionUnlockJump(heading, {
                key = function()
                    local gk = GlobalKey()
                    if gk then
                        return "TBBG_" .. gk
                    end
                    local anchor = mod.TBBGroupAnchorIndex(groupId)
                    return anchor and ("TBB_" .. anchor) or nil
                end,
            })

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
                    GroupLayoutChanged()
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
                    GroupLayoutChanged()
                end,
            })
            posY = posY - hgt

            -- Group Name (blank = the default "Group N") | Auto-Add
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
                    -- Soft refresh: the "Currently Editing:" label picks up the new name now.
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

            -- Global Group | Shift Elements If No Bars (+ Extra Y Offset cog,
            -- the Resource Bars "Shift Elements if No Resource" twin).
            local shiftRow
            shiftRow, hgt = W:DualRow(hostFrame, posY, {
                type = "toggle",
                text = "Global Group",
                tooltip = "Share this group's name, layout, and position across all specs.",
                getValue = function()
                    return (mod.TBBGroupGlobalKey and GlobalKey() ~= nil) or false
                end,
                setValue = function(v)
                    if mod.TBBSetGroupGlobal then
                        mod.TBBSetGroupGlobal(groupId, v)
                        mod.BuildTrackedBuffBars()
                        CludesUI:RefreshPage(true)
                    end
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
                    if e then
                        e.shiftNoBar = (v == "Up" or v == "Down") and v or nil
                        mod.BuildTrackedBuffBars()
                        CludesUI:RefreshPage()
                    end
                end,
            })
            posY = posY - hgt
            if not CludesUI._prebuilding then
                CludesUI.BuildInlineCog(shiftRow._rightRegion, {
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
                                -- The build tail's cascade fires only when the shift
                                -- direction flips, which a magnitude edit never does:
                                -- cascade here so the slider applies live (the
                                -- deferred batch coalesces a drag).
                                local gk = GlobalKey()
                                if gk and CludesUI.PropagateAnchorChain then
                                    CludesUI.PropagateAnchorChain("TBBG_" .. gk)
                                end
                            end,
                        },
                    },
                })
            end

            -- The bar frames exist before the placeholders show.
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

        -- SharedMedia textures join the runtime tables (for bar rendering), then
        -- the texture dropdown reads them, each row drawn in its texture.
        CludesUI.AppendSharedMediaTextures(
            mod.TBB_TEXTURE_NAMES or {},
            mod.TBB_TEXTURE_ORDER or {},
            nil,
            mod.TBB_TEXTURES
        )
        local texValues, texOrder = {}, {}
        do
            local names, lookup = mod.TBB_TEXTURE_NAMES or {}, mod.TBB_TEXTURES or {}
            for _, key in ipairs(mod.TBB_TEXTURE_ORDER or {}) do
                if key ~= "---" then
                    texValues[key] = names[key] or key
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

        -- The bar's group id (0 = independent) and each other member of it.
        local function GroupOf(bd)
            return bd and mod.TBBBarGroupID(bd) or 0
        end
        local function EachGroupMate(bd, fn)
            local groupId = GroupOf(bd)
            if groupId == 0 then
                return
            end
            for _, b in ipairs(mod.GetTrackedBuffBars().bars or {}) do
                if b ~= bd and mod.TBBBarGroupID(b) == groupId then
                    fn(b)
                end
            end
        end
        -- The mover and match-lock owner: a grouped bar's group (a global group's
        -- TBBG_ element, else the group anchor's), since only the anchor keeps one.
        local function MoverKey(bd)
            local groupId = GroupOf(bd)
            if groupId ~= 0 then
                local gk = mod.TBBGroupGlobalKey and mod.TBBGroupGlobalKey(groupId)
                if gk then
                    return "TBBG_" .. gk
                end
                local anchor = mod.TBBGroupAnchorIndex(groupId)
                if anchor then
                    return "TBB_" .. anchor
                end
            end
            return "TBB_" .. _tbbSelectedBar
        end

        -------------------------------------------------------------------
        --  BAR LAYOUT
        -------------------------------------------------------------------
        local layoutHeader
        layoutHeader, hgt = W:SectionHeader(hostFrame, "BAR LAYOUT", posY)
        posY = posY - hgt
        CludesUI.BuildSectionUnlockJump(layoutHeader, {
            key = function()
                return MoverKey(SelectedTBB())
            end,
        })

        -- Height | Width. The whole group shares one size, so a grouped member takes
        -- the group ANCHOR's match-lock: size-matched, every member's slider is
        -- disabled (the match wins) instead of silently fighting it.
        local lockKey = "TBB_" .. _tbbSelectedBar
        do
            local groupId = GroupOf(SelectedTBB())
            local anchor = groupId ~= 0 and mod.TBBGroupAnchorIndex(groupId)
            if anchor then
                lockKey = "TBB_" .. anchor
            end
        end
        -- A size slider; grouped bars share the size, so it writes the group.
        -- The popout is repainted here: RefreshPage() takes the fast widget path,
        -- which never re-runs the page tail that repaints it.
        local function SizeSlider(text, key, default)
            local dis, tip, raw = CludesUI.MatchGuard(lockKey, text)
            return {
                type = "slider",
                text = text,
                min = 1,
                max = 800,
                step = 1,
                disabled = dis,
                disabledTooltip = tip,
                rawTooltip = raw,
                getValue = function()
                    local bd = SelectedTBB()
                    return bd and bd[key] or default
                end,
                setValue = function(v)
                    local bd = SelectedTBB()
                    if not bd then
                        return
                    end
                    bd[key] = v
                    EachGroupMate(bd, function(b)
                        b[key] = v
                    end)
                    mod.BuildTrackedBuffBars()
                    RefreshTBBPopout()
                    CludesUI:RefreshPage()
                end,
            }
        end
        local sizeRow
        sizeRow, hgt =
            W:DualRow(hostFrame, posY, SizeSlider("Height", "height", 24), SizeSlider("Width", "width", 270))
        posY = posY - hgt

        -- Sync icons: Apply Height / Width to every bar of the SAME orientation
        -- ("height" is the short side of a horizontal bar but the long side of a
        -- vertical one, so a copy across orientations would be nonsense).
        if CludesUI.BuildSyncIcon then
            local sel = SelectedTBB()
            local orientWord = (sel and sel.verticalOrientation) and "Vertical" or "Horizontal"
            local function Alike(a, b)
                return (a.verticalOrientation and true or false) == (b.verticalOrientation and true or false)
            end
            local function SizeSync(region, text, key, default)
                CludesUI.BuildSyncIcon({
                    region = region,
                    tooltip = "Apply " .. text .. " to all " .. orientWord .. " Bars",
                    isSynced = function()
                        local bd = SelectedTBB()
                        if not bd then
                            return false
                        end
                        local val = bd[key] or default
                        for _, b in ipairs(mod.GetTrackedBuffBars().bars or {}) do
                            if Alike(bd, b) and (b[key] or default) ~= val then
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
                        local val = bd[key] or default
                        for _, b in ipairs(mod.GetTrackedBuffBars().bars or {}) do
                            if Alike(bd, b) then
                                b[key] = val
                            end
                        end
                        RefreshTBB()
                        CludesUI:RefreshPage()
                    end,
                })
            end
            SizeSync(sizeRow._leftRegion, "Height", "height", 24)
            SizeSync(sizeRow._rightRegion, "Width", "width", 270)
        end

        -- Vertical Orientation | Bar Texture. A flip swaps the stored width and
        -- height (they stay the drawn size) and flips the whole group, which stays
        -- orientation-uniform (its shared size reads one way), turning its grow
        -- direction with it so side by side stays side by side (DOWN<->RIGHT, UP<->LEFT).
        local function FlipOrientation(v)
            local bd = SelectedTBB()
            if not bd then
                return
            end
            local function Flip(c)
                c.width, c.height = (c.height or 24), (c.width or 270)
                c.verticalOrientation = v
            end
            Flip(bd)
            local groupId = GroupOf(bd)
            if groupId ~= 0 then
                EachGroupMate(bd, function(b)
                    if (b.verticalOrientation and true or false) ~= (v and true or false) then
                        Flip(b)
                    end
                end)
                local turn = v and { DOWN = "RIGHT", UP = "LEFT" } or { RIGHT = "DOWN", LEFT = "UP" }
                local grow = turn[mod.TBBGroupGrow(groupId)]
                if grow then
                    mod.TBBSetGroupGrow(groupId, grow)
                end
            end
            RefreshTBB()
            -- Full rebuild: the sync tooltips follow the orientation.
            CludesUI:RefreshPage(true)
        end
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
                setValue = FlipOrientation,
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
                    if bd then
                        bd.texture = v
                        RefreshTBB()
                    end
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
        local VERTICAL_NAME_TIP = "Horizontal Orientation (name text is not shown on vertical bars)"

        -- A text's position (prefix name / timer / stacks): the stored one, else
        -- what a bar saved before positions draws (name on the left unless hidden,
        -- the timer on the right when shown, stacks in the centre).
        local function TextPosition(bd, prefix)
            local stored = bd[prefix .. "Position"]
            if stored then
                return stored
            end
            if prefix == "name" then
                return (bd.showName ~= false) and "left" or "none"
            elseif prefix == "timer" then
                return bd.showTimer and "right" or "none"
            end
            return "center"
        end
        -- Where it actually draws: name text never draws on a vertical bar.
        local function DrawnPosition(bd, prefix)
            if prefix == "name" and bd.verticalOrientation then
                return "none"
            end
            return TextPosition(bd, prefix)
        end

        -- When a text claims a position, any other text drawn there moves to None,
        -- so labels never overlap (a vertical bar's stored name slot evicts nothing).
        local function EvictTBBTextConflicts(bd, changedKey, newPos)
            if newPos == "none" then
                return
            end
            for _, prefix in ipairs({ "name", "timer", "stacks" }) do
                local key = prefix .. "Position"
                if key ~= changedKey and DrawnPosition(bd, prefix) == newPos then
                    bd[key] = "none"
                    if prefix == "name" then
                        bd.showName = false
                    elseif prefix == "timer" then
                        bd.showTimer = false
                    end
                end
            end
        end

        local TEXT_LABELS = { name = "Name Text", timer = "Duration Text", stacks = "Stacks Text" }
        -- A text's colour swatch on its row, dimmed (with why) while the text is
        -- off, or for name text on a vertical bar.
        local function AddTBBTextSwatch(row, regionFrame, prefix)
            local function GetColor()
                local bd = SelectedTBB()
                if not bd then
                    return 1, 1, 1, 0.9
                end
                local function Channel(c, default)
                    local v = bd[prefix .. "Text" .. c]
                    if v == nil then
                        return default
                    end
                    return v
                end
                return Channel("R", 1), Channel("G", 1), Channel("B", 1), Channel("A", 0.9)
            end
            local swatch, updateSwatch = CludesUI.BuildColorSwatch(
                regionFrame,
                row:GetFrameLevel() + 3,
                GetColor,
                function(r, g, b, a)
                    local bd = SelectedTBB()
                    if bd then
                        bd[prefix .. "TextR"], bd[prefix .. "TextG"] = r, g
                        bd[prefix .. "TextB"], bd[prefix .. "TextA"] = b, a
                        RefreshTBB()
                    end
                end,
                true,
                20
            )
            Pix.Point(swatch, "RIGHT", regionFrame._lastInline or regionFrame._control, "LEFT", -8, 0)
            regionFrame._lastInline = swatch

            local block = CreateFrame("Frame", nil, swatch)
            block:SetAllPoints()
            block:SetFrameLevel(swatch:GetFrameLevel() + 10)
            block:EnableMouse(true)
            block:SetScript("OnEnter", function()
                local bd = SelectedTBB()
                local tip = (prefix == "name" and bd and bd.verticalOrientation) and VERTICAL_NAME_TIP
                    or ("This option requires a " .. TEXT_LABELS[prefix] .. " position other than None")
                CludesUI.ShowWidgetTooltip(swatch, CludesUI.DisabledTooltip(tip))
            end)
            block:SetScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)
            local function Dim()
                local bd = SelectedTBB()
                local on = bd ~= nil and DrawnPosition(bd, prefix) ~= "none"
                swatch:SetAlpha(on and 1 or 0.3)
                block:SetShown(not on)
            end
            CludesUI.RegisterWidgetRefresh(function()
                updateSwatch()
                Dim()
            end)
            Dim()
        end

        -- A text's position dropdown; name and timer keep their older show flags in step.
        local function PositionDropdown(text, prefix, default, showKey)
            local key = prefix .. "Position"
            return {
                type = "dropdown",
                text = text,
                values = TBB_POS_VALUES,
                order = TBB_POS_ORDER,
                getValue = function()
                    local bd = SelectedTBB()
                    return bd and TextPosition(bd, prefix) or default
                end,
                setValue = function(v)
                    local bd = SelectedTBB()
                    if not bd then
                        return
                    end
                    EvictTBBTextConflicts(bd, key, v)
                    bd[key] = v
                    if showKey then
                        bd[showKey] = (v ~= "none")
                    end
                    RefreshTBB()
                    CludesUI:RefreshPage()
                end,
            }
        end

        local nameCfg = PositionDropdown("Name Text", "name", "left", "showName")
        nameCfg.disabled = function()
            local bd = SelectedTBB()
            return bd and bd.verticalOrientation and true or false
        end
        nameCfg.disabledTooltip = VERTICAL_NAME_TIP
        local nameRow
        nameRow, hgt = W:DualRow(
            hostFrame,
            posY,
            nameCfg,
            PositionDropdown("Duration Text", "timer", "right", "showTimer")
        )
        posY = posY - hgt

        -- Cog rows over the selected bar: a slider (default when unset) and a
        -- toggle stored as true or nil. extra: more fields for the row.
        local function BarSlider(label, key, min, max, default, extra)
            local row = {
                type = "slider",
                label = label,
                min = min,
                max = max,
                step = 1,
                get = function()
                    local bd = SelectedTBB()
                    return bd and bd[key] or default
                end,
                set = function(v)
                    local bd = SelectedTBB()
                    if bd then
                        bd[key] = v
                        RefreshTBB()
                    end
                end,
            }
            for k, v in pairs(extra or {}) do
                row[k] = v
            end
            return row
        end
        local function BarToggle(label, key, tooltip)
            return {
                type = "toggle",
                label = label,
                tooltip = tooltip,
                get = function()
                    local bd = SelectedTBB()
                    return bd and bd[key] == true
                end,
                set = function(v)
                    local bd = SelectedTBB()
                    if bd then
                        bd[key] = v or nil
                        RefreshTBB()
                    end
                end,
            }
        end
        -- A text is off (its cog dims) while it draws nowhere.
        local function TextOff(prefix)
            local bd = SelectedTBB()
            return not bd or DrawnPosition(bd, prefix) == "none"
        end
        -- Apply this bar's text position to every bar (the older show flag follows).
        local function PositionSync(region, text, prefix, showKey)
            CludesUI.BuildSyncIcon({
                region = region,
                tooltip = "Apply " .. text .. " to all Bars",
                isSynced = function()
                    local bd = SelectedTBB()
                    if not bd then
                        return false
                    end
                    local place = TextPosition(bd, prefix)
                    for _, b in ipairs(mod.GetTrackedBuffBars().bars or {}) do
                        if TextPosition(b, prefix) ~= place then
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
                    local place = TextPosition(bd, prefix)
                    for _, b in ipairs(mod.GetTrackedBuffBars().bars or {}) do
                        b[prefix .. "Position"] = place
                        if showKey then
                            b[showKey] = (place ~= "none")
                        end
                    end
                    RefreshTBB()
                    CludesUI:RefreshPage()
                end,
            })
        end

        -- Name Text's cog: custom name, size, wrap and offsets; then its swatch and sync.
        CludesUI.BuildInlineCog(nameRow._leftRegion, {
            title = "Name Text Settings",
            disabled = function()
                return TextOff("name")
            end,
            disabledTooltip = function()
                local bd = SelectedTBB()
                if bd and bd.verticalOrientation then
                    return VERTICAL_NAME_TIP
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
                        if bd then
                            textValue = strtrim(textValue or "")
                            bd.customName = textValue ~= "" and textValue or nil
                            RefreshTBB()
                        end
                    end,
                },
                BarSlider("Text Size", "nameSize", 8, 24, 11),
                BarToggle("Text Wrap", "nameWrap"),
                BarSlider("X Offset", "nameX", -100, 100, 0),
                BarSlider("Y Offset", "nameY", -100, 100, 0),
            },
        })
        AddTBBTextSwatch(nameRow, nameRow._leftRegion, "name")
        PositionSync(nameRow._leftRegion, "Name Text", "name", "showName")

        -- Duration Text's cog: size, decimals below a threshold (the engine draws
        -- the tenths, see CludesUICdmTbbDecimals.lua) and offsets; swatch and sync.
        CludesUI.BuildInlineCog(nameRow._rightRegion, {
            title = "Duration Text Settings",
            rows = {
                BarSlider("Timer Size", "timerSize", 8, 24, 11),
                BarToggle(
                    "Decimals",
                    "timerDecimals",
                    "Cannot work for pet/totem summon bars (Call Dreadstalkers, etc.) -- they expose no readable timer."
                ),
                BarSlider("Decimal Threshold", "timerDecimalThreshold", 1, 120, 5, {
                    disabled = function()
                        local bd = SelectedTBB()
                        return not (bd and bd.timerDecimals)
                    end,
                    disabledTooltip = "Decimals enabled",
                }),
                BarSlider("X Offset", "timerX", -100, 100, 0),
                BarSlider("Y Offset", "timerY", -100, 100, 0),
            },
            disabled = function()
                return TextOff("timer")
            end,
            disabledTooltip = "This option requires a Duration Text position other than None",
        })
        AddTBBTextSwatch(nameRow, nameRow._rightRegion, "timer")
        PositionSync(nameRow._rightRegion, "Duration Text", "timer", "showTimer")

        -- Stacks Text (dropdown + cog: size and offsets) | Bar Strata (a grouped
        -- bar's whole group shares one).
        local stacksRow
        stacksRow, hgt = W:DualRow(hostFrame, posY, PositionDropdown("Stacks Text", "stacks", "center"), {
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
                EachGroupMate(bd, function(b)
                    b.strata = v
                end)
                RefreshTBB()
            end,
        })
        posY = posY - hgt
        CludesUI.BuildInlineCog(stacksRow._leftRegion, {
            title = "Stacks Text Settings",
            disabled = function()
                local bd = SelectedTBB()
                return bd and TextPosition(bd, "stacks") == "none"
            end,
            disabledTooltip = "This option requires a Stacks Text position other than None",
            rows = {
                BarSlider("Size", "stacksSize", 6, 24, 11),
                BarSlider("X Offset", "stacksX", -250, 250, 0),
                BarSlider("Y Offset", "stacksY", -250, 250, 0),
            },
        })
        AddTBBTextSwatch(stacksRow, stacksRow._leftRegion, "stacks")
        PositionSync(stacksRow._leftRegion, "Stacks Text", "stacks")

        -- Whether the selected bar tracks a cooldown, and one with charges.
        local function CooldownBar()
            local bd = SelectedTBB()
            return bd and bd.trackType == "cooldown" and bd or nil
        end
        local function ChargeBar()
            return CooldownBar() and SelectedTBBSupportsChargeHash() or false
        end
        local NOT_COOLDOWN_TIP = "This option requires a cooldown-tracking bar"
        local NO_CHARGES_TIP = "This option is only available for abilities with multiple charges"

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
                if bd then
                    bd.reverseFill = v
                    RefreshTBB()
                end
            end,
        }, {
            type = "toggle",
            text = "Fill Up",
            tooltip = "Fills the bar as the cooldown recovers instead of draining it as the cooldown runs down.",
            -- Charge Hash Lines drives its own recovery bar, which already fills
            -- upward, so Fill Up can do nothing there. Tested the way the Charge
            -- Hash Lines toggle tests it: the stored flag alone is not enough,
            -- since chargeHashLines rides in TBB_STYLE_KEYS and a style copy or
            -- preset can set it on a single-charge spell, where the hash fill
            -- never runs.
            disabled = function()
                local bd = CooldownBar()
                return not bd or (bd.chargeHashLines == true and SelectedTBBSupportsChargeHash())
            end,
            -- rawTooltip: these are whole sentences, not "This option requires <text>".
            rawTooltip = true,
            disabledTooltip = function()
                return CooldownBar() and "Charge Hash Lines already fills as charges recover"
                    or NOT_COOLDOWN_TIP
            end,
            getValue = function()
                local bd = SelectedTBB()
                return bd and bd.fillUp == true
            end,
            setValue = function(v)
                local bd = SelectedTBB()
                if bd then
                    bd.fillUp = v and true or nil
                    RefreshTBB()
                end
            end,
        })
        posY = posY - hgt

        -- Charge Hash Lines (+ cog) | Smooth Bars. The hash count and orientation
        -- follow the spell's max charges; Smooth Bars is profile-wide, not per bar
        -- or spec.
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
                return not ChargeBar()
            end,
            disabledTooltip = function()
                return CooldownBar() and NO_CHARGES_TIP or NOT_COOLDOWN_TIP
            end,
            getValue = function()
                local bd = SelectedTBB()
                return bd and bd.chargeHashLines == true and SelectedTBBSupportsChargeHash()
            end,
            setValue = function(v)
                local bd = SelectedTBB()
                if not bd or (v and not SelectedTBBSupportsChargeHash()) then
                    return
                end
                bd.chargeHashLines = v and true or nil
                RefreshTBB()
                CludesUI:RefreshPage()
            end,
        }, {
            -- A stand-in the checkbox list below takes the place of.
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
        CludesUI.BuildInlineCog(chargeHashRow._leftRegion, {
            title = "Charge Hash Line Settings",
            disabled = function()
                local bd = ChargeBar() and SelectedTBB()
                return not bd or bd.chargeHashLines ~= true
            end,
            disabledTooltip = function()
                if not CooldownBar() then
                    return NOT_COOLDOWN_TIP
                end
                return ChargeBar() and "Enable Charge Hash Lines first" or NO_CHARGES_TIP
            end,
            rawTooltip = true,
            rows = {
                BarSlider("Line Width", "chargeHashLineWidth", 1, 10, 2),
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
                        return bd.chargeHashLineR or 0,
                            bd.chargeHashLineG or 0,
                            bd.chargeHashLineB or 0,
                            a == nil and 1 or a
                    end,
                    set = function(r, g, b, a)
                        local bd = SelectedTBB()
                        if bd then
                            bd.chargeHashLineR, bd.chargeHashLineG = r, g
                            bd.chargeHashLineB, bd.chargeHashLineA = b, a
                            RefreshTBB()
                        end
                    end,
                },
                BarToggle(
                    "Partial Charge Shade",
                    "chargeHashShade",
                    "Darkens the section of the bar that is still recharging the next charge."
                ),
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
                        if bd then
                            bd.chargeHashShadeAlpha = (v or 50) / 100
                            RefreshTBB()
                        end
                    end,
                },
            },
        })

        -- Smooth Bars: a checkbox list per bar type (buffs smooth by default).
        do
            local rgn = chargeHashRow._rightRegion
            if rgn._control then
                rgn._control:Hide()
            end
            local function Smooth()
                return mod.GetTBBSmoothSettings and mod.GetTBBSmoothSettings()
            end
            local dd, refresh = CludesUI.BuildVisOptsCBDropdown(
                rgn,
                210,
                rgn:GetFrameLevel() + 2,
                SMOOTH_ITEMS,
                function(k)
                    local s = Smooth()
                    if not s or s[k] == nil then
                        return SMOOTH_DEFAULT[k]
                    end
                    return s[k] == true
                end,
                function(k, v)
                    local s = Smooth()
                    if s then
                        s[k] = v and true or false
                    end
                end
            )
            Pix.Point(dd, "RIGHT", rgn, "RIGHT", -20, 0)
            rgn._control = dd
            rgn._lastInline = nil
            CludesUI.RegisterWidgetRefresh(refresh)
        end

        -------------------------------------------------------------------
        --  DISPLAY
        -------------------------------------------------------------------
        local displayHeader
        displayHeader, hgt = W:SectionHeader(hostFrame, "DISPLAY", posY)
        posY = posY - hgt
        posY = CludesUI.BlizzStyle.Note(hostFrame, posY, "cdmbars")

        -- A bar field write that refreshes the bars.
        local function SetBar(key)
            return function(v)
                local bd = SelectedTBB()
                if bd then
                    bd[key] = v
                    RefreshTBB()
                end
            end
        end

        -- Visibility: one control, the shared axis list plus the TBB-only Hide When
        -- Inactive row (single-lane, so it rides in as an extraItem). No mouseover for
        -- CDM-family bars; "Only In Combat" is the In Combat axis. Show Icon sits in
        -- the slot the Visibility Options dropdown left.
        local _, tbbVisH = CludesUI.BuildVisibilityRow(W, hostFrame, posY, {
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
                    -- nil means ON everywhere this is read, so no plain truthiness test.
                    get = function()
                        local bd = SelectedTBB()
                        return bd and bd.hideWhenInactive ~= false
                    end,
                    -- No refresh here: the row fires onOptionChanged after every write.
                    set = function(v)
                        local bd = SelectedTBB()
                        if bd then
                            bd.hideWhenInactive = v
                        end
                    end,
                },
            },
        }, {
            type = "dropdown",
            text = "Show Icon",
            values = { none = "None", left = "Left (Top)", right = "Right (Bottom)" },
            order = { "none", "left", "right" },
            getValue = function()
                local bd = SelectedTBB()
                return bd and bd.iconDisplay or "none"
            end,
            setValue = SetBar("iconDisplay"),
        })
        posY = posY - tbbVisH

        -- Opacity | Background Color
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
                if bd then
                    bd.opacity = v / 100
                    RefreshTBB()
                end
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
                        if bd then
                            bd.bgR, bd.bgG, bd.bgB, bd.bgA = r, g, b, a
                            RefreshTBB()
                        end
                    end,
                }),
            },
        })
        posY = posY - hgt

        -- Fill Color (Custom Color or a gradient direction, + fill and gradient end
        -- swatches) | Show Spark. A legacy "auto" reads as Custom (no migration).
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
                    if not (bd and bd.gradientEnabled) then
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
                    bd.gradientEnabled = v ~= "none"
                    if v ~= "none" then
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
                setValue = SetBar("showSpark"),
            }
        )
        posY = posY - hgt
        do
            local rgn = fillRow._leftRegion
            -- Right, by the dropdown: the fill colour (no bar: the class colour).
            local fillSwatch, updateFill = CludesUI.BuildColorSwatch(
                rgn,
                fillRow:GetFrameLevel() + 3,
                function()
                    local bd = SelectedTBB()
                    if not bd then
                        local _, class = UnitClass("player")
                        local cc = RAID_CLASS_COLORS[class]
                        return cc and cc.r or 1, cc and cc.g or 0.70, cc and cc.b or 0, 1
                    end
                    return bd.fillR, bd.fillG, bd.fillB, bd.fillA
                end,
                function(r, g, b, a)
                    local bd = SelectedTBB()
                    if bd then
                        bd.fillColorMode = "custom"
                        bd.fillR, bd.fillG, bd.fillB, bd.fillA = r, g, b, a
                        RefreshTBB()
                    end
                end,
                true,
                20
            )
            Pix.Point(fillSwatch, "RIGHT", rgn._control, "LEFT", -8, 0)
            -- Left of it: the gradient end colour, dimmed while there is no gradient
            -- (or under Blizzard Style, which keeps the flat atlas fill).
            local gradSwatch, updateGrad = CludesUI.BuildColorSwatch(
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
                    if bd then
                        bd.gradientR, bd.gradientG, bd.gradientB, bd.gradientA = r, g, b, a
                        RefreshTBB()
                    end
                end,
                true,
                20
            )
            Pix.Point(gradSwatch, "RIGHT", fillSwatch, "LEFT", -4, 0)
            local gradBlock = CreateFrame("Frame", nil, gradSwatch)
            gradBlock:SetAllPoints()
            gradBlock:SetFrameLevel(gradSwatch:GetFrameLevel() + 10)
            gradBlock:EnableMouse(true)
            gradBlock:SetScript("OnEnter", function()
                CludesUI.ShowWidgetTooltip(
                    gradSwatch,
                    CludesUI.DisabledTooltip("This option requires a gradient to be set")
                )
            end)
            gradBlock:SetScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)
            local function Dim()
                local bd = SelectedTBB()
                local off = not bd or not bd.gradientEnabled or CludesUI.BlizzStyle.Get("cdmbars")
                gradSwatch:SetAlpha(off and 0.3 or 1)
                gradBlock:SetShown(off and true or false)
            end
            CludesUI.RegisterWidgetRefresh(function()
                updateFill()
                updateGrad()
                Dim()
            end)
            Dim()
        end

        -- A bar field as read (nil when unset), its write with no follow-up, and
        -- the border's style and size step.
        local function BarRaw(key)
            return function()
                local bd = SelectedTBB()
                return bd and bd[key]
            end
        end
        local function BarStore(key)
            return function(v)
                local bd = SelectedTBB()
                if bd then
                    bd[key] = v
                end
            end
        end
        local function BorderTex()
            local bd = SelectedTBB()
            return bd and bd.borderTexture or "solid"
        end
        local function BorderStep()
            local bd = SelectedTBB()
            return bd and bd.borderSize or 0
        end
        local function Repaint()
            RefreshTBB()
        end

        -- A new border style starts from that style's own colour, layering and
        -- size, with no leftover offsets, shifts or exact pixels.
        local function PickBorderStyle(v)
            local bd = SelectedTBB()
            if not bd then
                return
            end
            bd.borderTexture = v
            bd.borderTextureOffset, bd.borderTextureOffsetY = nil, nil
            bd.borderTextureShiftX, bd.borderTextureShiftY = nil, nil
            local colour, behind = CludesUI.GetBorderStyleSelectDefaults(v)
            bd.borderR, bd.borderG, bd.borderB = colour.r, colour.g, colour.b
            bd.borderBehind = behind
            bd.borderSize = CludesUI.GetBorderDefaultSize("resourcebars", v) or bd.borderSize
            if bd.borderSizePx then
                bd.borderSizePx = false
            end
            RefreshTBB()
            CludesUI:RefreshPage(true)
        end

        -- A Shift slider of the border cog: the stored shift, else the style's
        -- default (which = the GetBorderDefaults return it reads). Every value is
        -- stored, 0 included, so a 0 holds against a non-zero style default.
        local function ShiftRow(label, key, which)
            return {
                type = "slider",
                label = label,
                min = -10,
                max = 10,
                step = 1,
                get = function()
                    local bd = SelectedTBB()
                    if not bd then
                        return 0
                    end
                    if bd[key] then
                        return bd[key]
                    end
                    return (
                        select(
                            which,
                            CludesUI.GetBorderDefaults(
                                "resourcebars",
                                bd.borderTexture or "solid",
                                bd.borderSize or 0
                            )
                        )
                    )
                end,
                set = function(v)
                    local bd = SelectedTBB()
                    if bd then
                        bd[key] = v
                        RefreshTBB()
                    end
                end,
            }
        end

        -- Border Texture (+ options cog, textured styles only) | Border Size (+
        -- colour swatch). Under Classic WoW UI the size slot scales the vanilla
        -- frame instead and has no swatch. A textured style adds its Width |
        -- Height Offset row (built on the prebuild pass too: the y advance matches).
        do
            local classic = CludesUI.BlizzStyle.Active("cdmbars") == "classic"
            local values, order = CludesUI.GetBorderTextureDropdown()
            local sizeCfg
            if classic then
                sizeCfg = CludesUI.BlizzStyle.ClassicBorderSizeCfg(BarRaw("stockBorderScale"), function(v)
                    local bd = SelectedTBB()
                    if bd then
                        bd.stockBorderScale = v
                        RefreshTBB()
                    end
                end)
            else
                sizeCfg = CludesUI.BlizzStyle.Gate(
                    "cdmbars",
                    CludesUI.BorderPxSliderCfg({
                        text = "Border Size",
                        getStep = BorderStep,
                        setStep = BarStore("borderSize"),
                        getTex = BorderTex,
                        getPx = BarRaw("borderSizePx"),
                        setPx = BarStore("borderSizePx"),
                        apply = Repaint,
                    })
                )
            end
            local borderRow
            borderRow, hgt = W:DualRow(
                hostFrame,
                posY,
                CludesUI.BlizzStyle.Gate("cdmbars", {
                    type = "dropdown",
                    text = "Border Texture",
                    values = values,
                    order = order,
                    getValue = BorderTex,
                    setValue = PickBorderStyle,
                }),
                sizeCfg
            )
            posY = posY - hgt

            local tex = BorderTex()
            if tex ~= "" and tex ~= "solid" then
                local left, right = CludesUI.BorderOffsetRowCfgs({
                    addonKey = "resourcebars",
                    getTex = BorderTex,
                    getStep = BorderStep,
                    getSizeKey = BorderStep,
                    getPx = BarRaw("borderSizePx"),
                    getX = BarRaw("borderTextureOffset"),
                    setX = BarStore("borderTextureOffset"),
                    getY = BarRaw("borderTextureOffsetY"),
                    setY = BarStore("borderTextureOffsetY"),
                    apply = Repaint,
                })
                _, hgt = W:DualRow(
                    hostFrame,
                    posY,
                    CludesUI.BlizzStyle.Gate("cdmbars", left),
                    CludesUI.BlizzStyle.Gate("cdmbars", right)
                )
                posY = posY - hgt
            end

            if not classic then
                local rgn = borderRow._rightRegion
                local swatch, refresh = CludesUI.BuildColorSwatch(
                    rgn,
                    borderRow:GetFrameLevel() + 3,
                    function()
                        local bd = SelectedTBB()
                        return (bd and bd.borderR or 0), (bd and bd.borderG or 0), (bd and bd.borderB or 0)
                    end,
                    function(r, g, b)
                        local bd = SelectedTBB()
                        if bd then
                            bd.borderR, bd.borderG, bd.borderB = r, g, b
                            RefreshTBB()
                        end
                    end,
                    false,
                    20
                )
                Pix.Point(swatch, "RIGHT", rgn._control, "LEFT", -8, 0)
                CludesUI.RegisterWidgetRefresh(function()
                    refresh()
                end)
                CludesUI.BlizzStyle.BlockInline("cdmbars", swatch)
            end

            local cog = CludesUI.BuildInlineCog(borderRow._leftRegion, {
                title = "Border Options",
                rows = {
                    ShiftRow("Shift X", "borderTextureShiftX", 3),
                    ShiftRow("Shift Y", "borderTextureShiftY", 4),
                    {
                        type = "toggle",
                        label = "Show Behind",
                        get = function()
                            local bd = SelectedTBB()
                            return bd and bd.borderBehind or false
                        end,
                        set = function(v)
                            local bd = SelectedTBB()
                            if bd then
                                bd.borderBehind = v
                                RefreshTBB()
                            end
                        end,
                    },
                },
            })
            if cog then
                local function CogShown()
                    cog:SetShown(BorderTex() ~= "solid" and not CludesUI.BlizzStyle.Get("cdmbars"))
                end
                CludesUI.RegisterWidgetRefresh(CogShown)
                CogShown()
            end
        end

        -----------------------------------------------------------------------
        --  EXTRAS
        -----------------------------------------------------------------------
        _, hgt = W:SectionHeader(hostFrame, "EXTRAS", posY)
        posY = posY - hgt

        -- An overlay over target (or the span from target to corner) that takes
        -- the mouse and says why while its controls are off; tip may be a function.
        local function OffBlock(target, tip, corner)
            local block = CreateFrame("Frame", nil, target)
            if corner then
                block:SetPoint("TOPLEFT", target, "TOPLEFT", -4, 4)
                block:SetPoint("BOTTOMRIGHT", corner, "BOTTOMRIGHT", 4, -4)
            else
                block:SetAllPoints()
            end
            block:SetFrameLevel(target:GetFrameLevel() + 10)
            block:EnableMouse(true)
            block:SetScript("OnEnter", function()
                CludesUI.ShowWidgetTooltip(target, type(tip) == "function" and tip() or tip)
            end)
            block:SetScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)
            return block
        end
        local MAX_STACKS_TIP = CludesUI.DisabledTooltip("Max Stacks")

        -- Pandemic Glow (shared glow controls + Apply All) | Stack Based Bar. The
        -- glow reads the bar's pandemic keys through the Glows page's Tracked Buff
        -- Bar descriptor. Stack Based Bar is for buff bars only (the page rebuilds
        -- on a selection change, so a cooldown bar gets a blank slot) and does
        -- nothing until Max Stacks is on below. On WoW Forever the row is the
        -- Anti-Clip Glow (CUI_CDM_ForeverAntiClip.lua).
        do
            local GO = CludesUI.GlowOptions
            local glowDesc = mod._CDM_TbbGlowDesc(SelectedTBB, function()
                RefreshTBB()
            end)
            local sel = SelectedTBB()
            local stackSlot = { type = "label", text = "" }
            if sel and sel.trackType ~= "cooldown" then
                stackSlot = {
                    type = "toggle",
                    text = "Stack Based Bar",
                    tooltip = "Fill this bar from current stacks out of Max Stacks instead of remaining time (requires Enable Max Stacks below).",
                    getValue = function()
                        local bd = SelectedTBB()
                        return bd and bd.stackBasedBar
                    end,
                    setValue = function(v)
                        local bd = SelectedTBB()
                        if bd then
                            bd.stackBasedBar = v and true or false
                            RefreshTBB()
                        end
                    end,
                }
            end
            local antiClip = mod.CDM_ANTI_CLIP
            local glowRow
            glowRow, hgt = W:DualRow(
                hostFrame,
                posY,
                GO.DropdownSpec(
                    glowDesc,
                    antiClip and "Anti-Clip Glow" or "Pandemic Glow",
                    antiClip
                            and "Show a glow on the bar when casting the spell next, after your current cast or global cooldown, won't clip it"
                        or "Show a glow on the bar when the remaining duration is in the pandemic window (last 30%)"
                ),
                stackSlot
            )
            posY = posY - hgt
            GO.AttachInline(glowRow._leftRegion, glowDesc)
            if CludesUI.BuildSyncIcon and CludesUI.ApplyPandemicGlowToAll then
                local function Payload(source)
                    return CludesUI.PandemicPayloadFromRectBar(source), { skipTbbBar = source }
                end
                CludesUI.BuildSyncIcon({
                    region = glowRow._leftRegion,
                    tooltip = antiClip
                            and "Apply this glow's look to the Nameplates Pandemic Glow, all CDM bars, and other tracking bars. A surface that can't show a style uses its closest match."
                        or "Apply this pandemic glow to Nameplates, all CDM bars, and other tracking bars. A surface that can't show a style uses its closest match.",
                    isSynced = function()
                        local source = SelectedTBB()
                        return not source or CludesUI.IsPandemicGlowSyncedToAll(Payload(source))
                    end,
                    onClick = function()
                        local source = SelectedTBB()
                        if source then
                            CludesUI.ApplyPandemicGlowToAll(Payload(source))
                            RefreshTBB()
                        end
                    end,
                })
            end
        end

        -- Enable Max Stacks (+ inline slider) | Ticks at Stacks (+ swatch and
        -- input); both insets dim while Max Stacks is off.
        local function MaxStacksOff()
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
                if bd then
                    bd.stackThresholdMaxEnabled = v
                    RefreshTBB()
                    CludesUI:RefreshPage()
                end
            end,
        }, {
            type = "label",
            text = "Ticks at Stacks",
            tooltip = "Comma separated stack counts to put a tick mark at. Type all to mark every stack.",
        })
        posY = posY - hgt
        do
            local rgn = maxStacksRow._leftRegion
            local SL = CludesUI.SL or {}
            local track, valueBox, _, thumb = CludesUI.BuildSliderCore(
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
            Pix.Point(valueBox, "RIGHT", rgn._control, "LEFT", -6, 0)
            Pix.Point(track, "RIGHT", valueBox, "LEFT", -8, 0)
            local block = OffBlock(track, MAX_STACKS_TIP, valueBox)
            local function Dim()
                local off = MaxStacksOff()
                track:SetAlpha(off and 0.3 or 1)
                valueBox:SetAlpha(off and 0.3 or 1)
                valueBox:EnableMouse(not off)
                if thumb then
                    thumb._sliderDisabled = off
                end
                block:SetShown(off)
            end
            CludesUI.RegisterWidgetRefresh(Dim)
            Dim()
        end
        do
            local rgn = maxStacksRow._rightRegion
            local FONT = CludesUI.EXPRESSWAY or "Fonts\\FRIZQT__.TTF"
            -- "(Ex: 1,5,8)" after the label, smaller and dimmer.
            if rgn and rgn._label then
                local example = rgn:CreateFontString(nil, "OVERLAY")
                example:SetFont(FONT, 11, "")
                example:SetTextColor(1, 1, 1, 0.35)
                example:SetPoint("LEFT", rgn._label, "RIGHT", 5, 0)
                example:SetText(CludesUI.L("(Ex: 1,5,8)"))
            end
            -- The tick list input, styled as a slider's value box; Enter saves, Escape puts back.
            local box = CreateFrame("EditBox", nil, rgn)
            Pix.Size(box, 70, 26)
            Pix.Point(box, "RIGHT", rgn, "RIGHT", -20, 0)
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
            local backdrop = box:CreateTexture(nil, "BACKGROUND")
            backdrop:SetAllPoints()
            backdrop:SetColorTexture(
                CludesUI.SL_INPUT_R or 0.08,
                CludesUI.SL_INPUT_G or 0.08,
                CludesUI.SL_INPUT_B or 0.08,
                (CludesUI.SL_INPUT_A or 0.5) + (CludesUI.MW_INPUT_ALPHA_BOOST or 0.15)
            )
            CludesUI.MakeRoundedBorder(
                box,
                CludesUI.BORDER_R,
                CludesUI.BORDER_G,
                CludesUI.BORDER_B,
                CludesUI.SL_INPUT_BRD_A,
                backdrop
            )
            local function Saved()
                local bd = SelectedTBB()
                return bd and bd.stackThresholdTicks or ""
            end
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
                self:SetText(Saved())
            end)

            -- The tick mark colour, left of the input.
            local swatch, updateSwatch = CludesUI.BuildColorSwatch(rgn, box:GetFrameLevel() + 1, function()
                local bd = SelectedTBB()
                if not bd then
                    return 1, 1, 1, 1
                end
                local a = bd.stackThresholdTickA
                return bd.stackThresholdTickR or 1,
                    bd.stackThresholdTickG or 1,
                    bd.stackThresholdTickB or 1,
                    a == nil and 1 or a
            end, function(r, g, b, a)
                local bd = SelectedTBB()
                if bd then
                    bd.stackThresholdTickR, bd.stackThresholdTickG = r, g
                    bd.stackThresholdTickB, bd.stackThresholdTickA = b, a
                    RefreshTBB()
                end
            end, true, 20)
            Pix.Point(swatch, "RIGHT", box, "LEFT", -8, 0)
            local block = OffBlock(swatch, MAX_STACKS_TIP)
            local function Dim()
                box:SetText(Saved())
                local off = MaxStacksOff()
                box:SetAlpha(off and 0.3 or 1)
                box:EnableMouse(not off)
                swatch:SetAlpha(off and 0.3 or 1)
                block:SetShown(off)
                if updateSwatch then
                    updateSwatch()
                end
            end
            CludesUI.RegisterWidgetRefresh(Dim)
            Dim()
        end

        -- Enable Stack Threshold (+ editor cog and swatch) | Stack Threshold.
        -- Several thresholds (multi) replace the single one: they mask its
        -- slider and colour; the cog stays usable, as the only way back out.
        local function MultiThresholds()
            local bd = SelectedTBB()
            return bd and bd.stackThresholdEnabled and bd.stackThresholdMulti and true or false
        end
        local function ThresholdOff()
            local bd = SelectedTBB()
            return not (bd and bd.stackThresholdEnabled) or MultiThresholds()
        end
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
                if bd then
                    bd.stackThresholdEnabled = v
                    RefreshTBB()
                    CludesUI:RefreshPage()
                end
            end,
        }, {
            type = "slider",
            text = "Stack Threshold",
            min = 0,
            max = 100,
            step = 1,
            disabled = ThresholdOff,
            disabledTooltip = function()
                return MultiThresholds() and StackThreshReplacesTip()
                    or CludesUI.DisabledTooltip("Stack Threshold")
            end,
            rawTooltip = true,
            getValue = function()
                local bd = SelectedTBB()
                return bd and bd.stackThreshold or 5
            end,
            setValue = function(v)
                local bd = SelectedTBB()
                if bd then
                    bd.stackThreshold = v
                    RefreshTBB()
                end
            end,
        })
        posY = posY - hgt
        do
            local rgn = threshRow._leftRegion
            local ctrl = rgn._control
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
            local swatch, updateSwatch = CludesUI.BuildColorSwatch(
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
                    if bd then
                        bd.stackThresholdR, bd.stackThresholdG, bd.stackThresholdB, bd.stackThresholdA =
                            r, g, b, a
                        RefreshTBB()
                    end
                end,
                true,
                20
            )
            Pix.Point(swatch, "RIGHT", rgn._lastInline or ctrl, "LEFT", -8, 0)
            rgn._lastInline = swatch
            local block = OffBlock(swatch, function()
                return MultiThresholds() and StackThreshReplacesTip()
                    or CludesUI.DisabledTooltip("Stack Threshold")
            end)
            local function Dim()
                local off = ThresholdOff()
                swatch:SetAlpha(off and 0.3 or 1)
                block:SetShown(off)
            end
            CludesUI.RegisterWidgetRefresh(function()
                updateSwatch()
                Dim()
            end)
            Dim()
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
