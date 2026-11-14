if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUI_Widgets_RowAddons.lua
--  Row add-ons: inline toggle, cog and button, the row-label and button
--  menus, the less-common expander, inline swatches, the section gates and
--  the cursor anchor row. Reads BuildCogPopup and BuildColorSwatch, so it
--  loads after CludesUI_Widgets_CogPopup.lua.
--  DEFERRED: body runs on first CludesUI:EnsureLoaded() call, not at load.
-------------------------------------------------------------------------------
local CludesUI = _G.CludesUI
CludesUI._deferredInits[#CludesUI._deferredInits + 1] = function()
    -- Options page pool (CludesUI_FramePool.lua): frames made here on a pool
    -- host are reset and dressed again by the next build instead of made anew;
    -- elsewhere this is CreateFrame.
    local CreateFrame = CludesUI._Pool.CreateFrame
    local Pix = CludesUI.PanelPP
    local RegisterWidgetRefresh = CludesUI.RegisterWidgetRefresh
    local MakeStyledButton = CludesUI.MakeStyledButton
    local WB_COLOURS = CludesUI.WB_COLOURS
    local ShowWidgetTooltip = CludesUI.ShowWidgetTooltip
    local HideWidgetTooltip = CludesUI.HideWidgetTooltip
    local ResolveDisabledTip = CludesUI.ResolveDisabledTip
    local BuildToggleControl = CludesUI.BuildToggleControl
    local BuildColorSwatch = CludesUI.BuildColorSwatch
    local BuildCogPopup = CludesUI.BuildCogPopup
    local BuildDropdownMenu = CludesUI.BuildDropdownMenu
    local WireDropdownScripts = CludesUI.WireDropdownScripts

    -- Inline toggle: a small toggle placed inline inside a DualRow half-region,
    -- chaining left of the control (slider/dropdown) like the sync icon / cog. Used
    -- to gate the row's control (e.g. enable/disable the duration text). The toggle
    -- itself is never disabled. opts: region, getValue, setValue, onToggle, sizeRatio.
    local function BuildInlineToggle(options)
        local regionFrame = options.region
        if not regionFrame then
            return nil
        end
        local toggle, _, tgSnap = BuildToggleControl(
            regionFrame,
            regionFrame:GetFrameLevel() + 5,
            options.getValue,
            function(val)
                if options.setValue then
                    options.setValue(val)
                end
                if options.onToggle then
                    options.onToggle(val)
                end
            end,
            { sizeRatio = options.sizeRatio or 0.8 }
        )
        toggle:ClearAllPoints()
        toggle:SetPoint("RIGHT", regionFrame._lastInline or regionFrame._control, "LEFT", -8, 0)
        regionFrame._lastInline = toggle
        RegisterWidgetRefresh(tgSnap)
        return toggle
    end

    -- Glyph buttons a page builds itself (the eye preview toggles) set their alpha
    -- through SetGlyphAlpha(btn, a) with the plain glyph values (0.15 disabled,
    -- 0.4 idle, 0.7 hovered). They show as the cogs' dots below do: 0.55 idle /
    -- 0.75 hovered, 0.15 disabled, and linearly between (the Raid & Party Frames
    -- eye's 0.6 while its preview is on).
    function CludesUI.SetGlyphAlpha(button, a)
        button._glyphA = a
        button:SetAlpha(a <= 0.15 and a or math.min(1, 0.55 + (a - 0.4) * 2 / 3))
    end

    -- Inline cogs draw a vertical ellipsis with an accent notification dot above
    -- it. The dot shows on a cog never opened once the user edits its setting, and
    -- stays until the panel closes or the cog is opened (an opened cog never shows
    -- it again), never while the cog or its setting is disabled; the edit that
    -- shows it pulses it. A cog is known by its module, page, section, row label
    -- and popup title (so a row repeated per unit or bar has one dot), hashed to
    -- five characters; the opened ones are one string, CludesUIDB.cogSeen (in
    -- no export; /cuiresethint clears it).
    -- Cog notice: every widget write reaches CludesUI._CogWriteNotice(frame)
    -- through CludesUI._NotifySettingWrite; it lights the dot, and the first
    -- change ever to a setting with a cog puts a tip above that cog
    -- (CludesUIDB.inlineCogTipSeen, cleared by /cuiresethint): Okay or a click
    -- on a cog dismisses it for good. Once a dot is up, a write to its setting
    -- costs one check.
    local CogDot = {
        -- Geometry in shares of the cog's height (30, a dropdown's): dots 4 across
        -- and 6.5 apart, the notification dot 7 across with its centre 8 left of
        -- and 3.5 above the top dot's.
        DOT = 4 / 30,
        STEP = 6.5 / 30,
        NOTE = 7 / 30,
        NX = 8 / 30,
        NY = 3.5 / 30,
        -- Ids: a rolling hash under the largest prime below 2^30, written as five
        -- characters of a 64-character set.
        MOD = 1073741789,
        CHARS = { string.byte("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_", 1, 64) },
        live = setmetatable({}, { __mode = "k" }), -- the cogs built, for Mark
        -- This panel session, emptied when the panel closes: the ids whose setting
        -- was edited, and the ids whose dot is up since an edit showed it.
        edited = {},
        up = {},
    }
    local cogTip, cogTipCog, cogTipInScroll, cogTipScrollHooked

    local function CogTipSeen()
        return CludesUIDB and CludesUIDB.inlineCogTipSeen
    end

    -- The cog being built: module, page, section, row label and popup title.
    function CogDot.Key(rgn, options)
        local row = rgn:GetParent()
        local contentFrame = row and row:GetParent()
        local sec = contentFrame and contentFrame._currentSection
        local conf, title = rgn._cfg, options.title
        local labelText = conf and conf.text or rgn._labelText
        return (CludesUI._buildingModule or CludesUI:GetActiveModule() or "")
            .. "\31"
            .. (CludesUI._buildingPage or CludesUI:GetActivePage() or "")
            .. "\31"
            .. (sec and sec._sectionName or "")
            .. "\31"
            .. (type(labelText) == "string" and labelText or "")
            .. "\31"
            .. (type(title) == "string" and title or "")
    end

    function CogDot.Id(s)
        local hgt, mod = 0, CogDot.MOD
        for idx = 1, #s do
            hgt = (hgt * 31 + s:byte(idx)) % mod
        end
        local c = CogDot.CHARS
        local a = hgt % 64
        hgt = (hgt - a) / 64
        local b = hgt % 64
        hgt = (hgt - b) / 64
        local d = hgt % 64
        hgt = (hgt - d) / 64
        local e = hgt % 64
        hgt = (hgt - e) / 64
        return string.char(c[a + 1], c[b + 1], c[d + 1], c[e + 1], c[hgt + 1])
    end

    -- The opened cogs as a set, read from the saved string once a session.
    function CogDot.Seen()
        local set = CogDot.set
        if set then
            return set
        end
        set = {}
        local str = CludesUIDB and CludesUIDB.cogSeen
        if type(str) == "string" then
            for idx = 1, #str - 4, 5 do
                set[str:sub(idx, idx + 4)] = true
            end
        end
        CogDot.set = set
        return set
    end

    -- A cog opened for the first time: its id joins the saved string, and every
    -- built cog with that id (the same row on another unit or bar) loses its dot.
    function CogDot.Mark(ident)
        local set = CogDot.Seen()
        if set[ident] then
            return
        end
        set[ident] = true
        if CludesUIDB then
            local str = CludesUIDB.cogSeen
            CludesUIDB.cogSeen = (type(str) == "string" and str or "") .. ident
        end
        for b in pairs(CogDot.live) do
            if b._cuiCogId == ident then
                b._cuiCogPulse:Stop()
                b._cuiCogNote:Hide()
            end
        end
    end

    -- Whole pixels from a share of the cog's height, taken of the rounded pixel
    -- height (the memo's key) so every cog of one pixel size gets the same dots:
    -- of the unrounded height, a share on a half pixel (the step and the
    -- notification dot's offsets at 30 pixels) rounds either way with the float
    -- error a cog's effective scale carries.
    function CogDot.Px(val)
        return math.floor(val + 0.5)
    end

    -- The dots in whole pixels on the cog's pixel layer: the middle one centred,
    -- the others a step above and below, the notification dot (and the pulse ring
    -- under it) up and left of the top one.
    function CogDot.Fit(L, k)
        local wid, hgt = L.parent:GetSize()
        local wp, hp = math.floor(wid * k + 0.5), math.floor(hgt * k + 0.5)
        if wp == L.wp and hp == L.hp then
            return
        end
        L.wp, L.hp = wp, hp
        local Px = CogDot.Px
        local d = math.max(2, Px(hp * CogDot.DOT))
        local step = math.max(d + 1, Px(hp * CogDot.STEP))
        local num = math.max(3, Px(hp * CogDot.NOTE))
        local posX, posY = math.floor((wp - d) / 2), math.floor((hp - d) / 2)
        local layer = L._frame
        for idx = 1, 3 do
            local t = L[idx]
            CludesUI.SetCircleArt(t, d)
            t:SetSize(d, d)
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", layer, "TOPLEFT", posX, (2 - idx) * step - posY)
        end
        -- Its outer edge reaches as far past the column's left edge as the same
        -- spot to the right would past its right edge, so the rounding mirrors.
        -- Kept inside the button, which a small cog's rounded sizes can leave.
        local reach = Px((d - num) / 2 + hp * CogDot.NX) + num - d
        local nx = math.max(0, posX - reach)
        local ny = math.max(0, Px(posY - step + (d - num) / 2 - hp * CogDot.NY))
        local note, ring = L.note, L.ring
        CludesUI.SetCircleArt(note, num)
        note:SetSize(num, num)
        note:ClearAllPoints()
        note:SetPoint("TOPLEFT", layer, "TOPLEFT", nx, -ny)
        CludesUI.SetCircleArt(ring, num)
        ring:SetSize(num, num)
        ring:ClearAllPoints()
        ring:SetPoint("CENTER", note, "CENTER")
    end

    -- The pulse: a ring of the dot's colour grows from it and fades, three times.
    function CogDot.PulseLoop(ag)
        local num = (ag._cuiLoops or 0) + 1
        ag._cuiLoops = num
        if num >= 3 then
            ag:Stop()
        end
    end

    function CogDot.Pulse(cog)
        local ag = cog._cuiCogPulse
        ag._cuiLoops = 0
        ag:Play()
    end

    -- An edit to the setting of a cog never opened: its dot shows here and on the
    -- cog's twins until the panel closes, and every dot this edit brings up on
    -- screen pulses.
    function CogDot.Edited(ident)
        if CogDot.Seen()[ident] then
            return
        end
        CogDot.edited[ident] = true
        local up
        for b in pairs(CogDot.live) do
            if b._cuiCogId == ident and b._cuiCogState then
                b._cuiCogState()
                if b._cuiCogNote:IsShown() and b:IsVisible() then
                    up = true
                    CogDot.Pulse(b)
                end
            end
        end
        CogDot.up[ident] = up
    end

    -- The panel closed (not hidden with the UI, which leaves it shown): this
    -- session's dots go.
    function CogDot.PanelClosed()
        if CludesUI:IsShown() or not next(CogDot.edited) then
            return
        end
        local edited = CogDot.edited
        for b in pairs(CogDot.live) do
            if edited[b._cuiCogId] then
                b._cuiCogPulse:Stop()
                b._cuiCogNote:Hide()
            end
        end
        wipe(edited)
        wipe(CogDot.up)
    end
    CludesUI:RegisterOnHide(CogDot.PanelClosed)

    local function HideCogTip()
        cogTipCog = nil
        if cogTip then
            cogTip:Hide()
        end
    end

    local function CogTipDone()
        HideCogTip()
        if CludesUIDB then
            CludesUIDB.inlineCogTipSeen = true
        end
    end

    -- A cog that hides (page switch, panel close, its page built again) takes its
    -- tip with it, unseen: the next change shows it again. A pulse stops with it.
    local function CogHidden(self)
        if self == cogTipCog then
            HideCogTip()
        end
        self._cuiCogPulse:Stop()
    end

    local function InScrollArea(f)
        local scrollFrame = CludesUI._scrollFrame
        while f do
            if f == scrollFrame then
                return true
            end
            f = f:GetParent()
        end
        return false
    end

    -- For a cog in the scrolled content, the tip shows only while the cog's
    -- centre is inside the scroll area: scrolled out it hides, back in it shows.
    local function CogTipScroll()
        if not (cogTipCog and cogTipInScroll) then
            return
        end
        local scrollFrame = CludesUI._scrollFrame
        local _, cy = cogTipCog:GetCenter()
        local topY, bottom = scrollFrame:GetTop(), scrollFrame:GetBottom()
        if cy and topY and bottom and cy <= topY and cy >= bottom then
            if not cogTip:IsShown() then
                CludesUI.ShowTipCallout(cogTip)
            end
        elseif cogTip:IsShown() then
            cogTip:Hide()
        end
    end

    local function ShowCogTip(cog)
        if cogTip and cogTipCog == cog and cogTip:IsShown() then
            return
        end
        if not cogTip then
            -- The panel tips' metrics (the Raid & Party Frames eye tip's), on the
            -- panel body: it rides the panel scale and hides with the panel.
            cogTip = CludesUI.BuildTipCallout(CludesUI._panelBody, {
                width = 250,
                arrow = "bottom",
                -- "icon": a third of the inline cogs wear the directions or resize glyph.
                text = CludesUI.L("This setting has more options.\nClick this icon to see them."),
                fontSize = 10,
                textTop = 12,
                textInset = 24,
                spacing = 4,
                bgAlpha = 0.95,
                btnW = 70,
                btnH = 22,
                btnBottom = 10,
                btnFontSize = 10,
                onOkay = CogTipDone,
            })
        end
        cogTipCog = cog
        cogTipInScroll = InScrollArea(cog)
        if cogTipInScroll and not cogTipScrollHooked then
            cogTipScrollHooked = true
            CludesUI._scrollFrame:HookScript("OnVerticalScroll", CogTipScroll)
        end
        cogTip:ClearAllPoints()
        cogTip:SetPoint("BOTTOM", cog, "TOP", 0, 14)
        if not cogTip:IsShown() then
            CludesUI.ShowTipCallout(cogTip)
        end
    end

    -- frame: the widget that wrote (or its region); the cog is the one its DualRow
    -- half (frame or one of its two parents) registered (a page the setter built
    -- again holds a new cog of the same id, which CogDot.Edited finds). A disabled
    -- cog is left alone; the tip goes to a visible one.
    function CludesUI._CogWriteNotice(widget)
        if type(widget) ~= "table" or CludesUI._prebuilding then
            return
        end
        local cog
        for _ = 1, 3 do
            cog = widget._cuiCog
            if cog or not widget.GetParent then
                break
            end
            widget = widget:GetParent()
            if not widget then
                return
            end
        end
        if not cog then
            return
        end
        local ident, off = cog._cuiCogId, cog._cuiCogOff
        if off and off() then
            -- The edit turned its own cog off: the one that turns it back on
            -- brings the dot up again, with its pulse.
            CogDot.up[ident] = nil
            return
        end
        if not CogDot.up[ident] then
            CogDot.Edited(ident)
        end
        if not CogTipSeen() and cog:IsVisible() then
            ShowCogTip(cog)
        end
    end

    -- Inline cog button on a DualRow half-region, left of its control (or of the last inline item). Returns cogBtn, showFn; nil during the search prebuild.
    -- opts: BuildCogPopup's own opts (title, rows, captureRegion, minWidth, ...) or show(btn) + optional isOpen(btn) for a custom popup; size (the height: 30, a
    --   dropdown's; the button is 0.8 as wide), gap (8), anchorTo,
    --   relPoint (the anchor's side the cog's right edge sits on, LEFT; a host that is not a DualRow half passes anchorTo = itself, relPoint = "RIGHT", gap = 0),
    --   chain (default true: anchors to and becomes region._lastInline), tip, disabled + disabledTooltip/rawTooltip/requireState (as ResolveDisabledTip; default: the host control's).
    -- Every inline cog draws the vertical ellipsis with its accent notification dot (CogDot above): white dots at 0.55, 0.75 hovered or while its popup is open,
    --   0.15 disabled (the button at 0.3). Disabled blocks the click and shows the requirement tooltip. A button that paints its own states, opts.paint(btn, off, hot),
    --   draws opts.icon bare instead, 26 square and with no dot (the unlock jump).
    -- A cog with a dot is the one its region's writes light (the cog notice above; the last such cog built on the region).
    local function BuildInlineCog(rgn, options)
        if CludesUI._prebuilding then
            return
        end
        -- A disabled cog with no tooltip of its own explains itself with its host control's requirement.
        local tipSrc = (options.disabled and not options.disabledTooltip) and rgn._cfg or options
        if options.disabled and not (tipSrc and tipSrc.disabledTooltip) and CludesUI.IsDevModeActive() then
            error("BuildInlineCog: disabled needs a disabledTooltip", 2)
        end
        local show = options.show or select(2, BuildCogPopup(options))
        local paint = options.paint
        local hgt = options.size or (paint and 26 or 30)
        local button = CreateFrame("Button", nil, rgn)
        button:SetSize(paint and hgt or math.floor(hgt * 0.8 + 0.5), hgt)
        Pix.Point(
            button,
            "RIGHT",
            options.anchorTo or (options.chain ~= false and rgn._lastInline) or rgn._control or rgn,
            options.relPoint or "LEFT",
            -(options.gap or 8),
            0
        )
        if options.chain ~= false then
            rgn._lastInline = button
        end
        button:SetFrameLevel(rgn:GetFrameLevel() + 5)
        local texture, L, note, ident, hostCfg
        if paint then
            texture = button:CreateTexture(nil, "OVERLAY")
            texture:SetTexture(options.icon)
            texture:SetAllPoints()
            button._icon = texture
        else
            -- The three dots, the notification dot and its pulse ring: white and
            -- accent art on a pixel layer, placed in whole pixels (CogDot.Fit).
            L = CludesUI.MakePixelLayer(button, CogDot.Fit)
            local layer = L._frame
            L[1] = layer:CreateTexture(nil, "ARTWORK")
            L[2] = layer:CreateTexture(nil, "ARTWORK")
            L[3] = layer:CreateTexture(nil, "ARTWORK")
            local ring = layer:CreateTexture(nil, "OVERLAY")
            note = layer:CreateTexture(nil, "OVERLAY", nil, 1)
            L.note, L.ring = note, ring
            local r, g, b = CludesUI.GetAccentColor()
            note:SetVertexColor(r, g, b, 1)
            ring:SetVertexColor(r, g, b, 1)
            ring:SetAlpha(0)
            -- Keyed by the textures: the page pool forgets the entries when it resets them.
            CludesUI.RegAccent({ type = "vertex", obj = note })
            CludesUI.RegAccent({ type = "vertex", obj = ring })
            local pulse = ring:CreateAnimationGroup()
            local grow = pulse:CreateAnimation("Scale")
            grow:SetScaleFrom(1, 1)
            grow:SetScaleTo(2.6, 2.6)
            grow:SetOrigin("CENTER", 0, 0)
            grow:SetDuration(0.9)
            grow:SetSmoothing("OUT")
            local fade = pulse:CreateAnimation("Alpha")
            fade:SetFromAlpha(0.7)
            fade:SetToAlpha(0)
            fade:SetDuration(0.9)
            fade:SetSmoothing("OUT")
            pulse:SetLooping("REPEAT")
            pulse:SetScript("OnLoop", CogDot.PulseLoop)
            L:Fit()
            ident = CogDot.Id(CogDot.Key(rgn, options))
            hostCfg = rgn._cfg
            button._cuiCogId, button._cuiCogNote, button._cuiCogPulse = ident, note, pulse
            CogDot.live[button] = true
            -- The cog notice: the region's writes light this cog.
            button._cuiCogOff = options.disabled
            rgn._cuiCog = button
            button:SetScript("OnHide", CogHidden)
        end

        local block
        if options.disabled then
            block = CreateFrame("Frame", nil, button)
            block:SetAllPoints()
            block:SetFrameLevel(button:GetFrameLevel() + 10)
            block:EnableMouse(true)
            block:SetScript("OnEnter", function()
                local tipText = tipSrc and ResolveDisabledTip(tipSrc)
                if tipText then
                    ShowWidgetTooltip(button, tipText)
                end
            end)
            block:SetScript("OnLeave", function()
                HideWidgetTooltip()
            end)
        end
        -- hover: the enter / leave scripts say which edge they are (a rect test at
        -- the moment of the event can disagree with the hit test on an edge);
        -- a refresh pass asks the rect.
        local function State(hover)
            local off = options.disabled and options.disabled()
            local popFrame = type(show) == "table" and show._popupFrame
            local open = (options.isOpen and options.isOpen(button))
                or (popFrame and popFrame:IsShown() and popFrame._owner == button)
            local hot = open
            if not hot then
                if hover == nil then
                    hot = button:IsMouseOver()
                else
                    hot = hover
                end
            end
            -- opts.paint(btn, off, hot) paints the states itself (the unlock jump).
            -- The dots: 0.55 idle, 0.75 hovered or open, 0.15 disabled through the
            -- button's 0.3. The notification dot once its setting was edited this
            -- panel session, until the cog is first opened, never while the cog or
            -- the setting it sits on is disabled.
            if paint then
                paint(button, off, hot)
            else
                button:SetAlpha(off and 0.3 or 1)
                local a = off and 0.5 or (hot and 0.75 or 0.55)
                L[1]:SetAlpha(a)
                L[2]:SetAlpha(a)
                L[3]:SetAlpha(a)
                local dot = CogDot.edited[ident] == true
                    and not (
                        off
                        or CogDot.Seen()[ident]
                        or (hostCfg and hostCfg.disabled and hostCfg.disabled())
                    )
                note:SetShown(dot)
                if not dot then
                    button._cuiCogPulse:Stop()
                end
            end
            if block then
                block:SetShown(off and true or false)
            end
        end
        button._cuiCogState = State
        -- opts.paint reads the accent (the unlock jump), so it repaints on accent changes.
        -- Keyed by the texture: the page pool forgets the entry when it resets it.
        if paint then
            CludesUI.RegAccent({
                type = "callback",
                obj = texture,
                fn = function()
                    State()
                end,
            })
        end

        button:SetScript("OnEnter", function(self)
            State(true)
            if options.tip then
                ShowWidgetTooltip(self, options.tip)
            end
        end)
        button:SetScript("OnLeave", function()
            State(false)
            if options.tip then
                HideWidgetTooltip()
            end
        end)
        button:SetScript("OnClick", function(self)
            -- A cog clicked while the cog tip is up: the tip has done its job.
            -- Opened once, its dot is gone for good.
            if not paint then
                if cogTipCog then
                    CogTipDone()
                end
                CogDot.Mark(ident)
            end
            show(self)
        end)
        State()
        -- A refresh re-reads the disabled states: the cog's own and, for the dot,
        -- its setting's.
        if options.disabled or (hostCfg and hostCfg.disabled) then
            RegisterWidgetRefresh(State)
        end
        return button, show
    end

    -- Inline text button on a DualRow half-region, left of its last inline item or
    -- control (or at the half's right edge when it has neither, e.g. a label half).
    -- opts: width (110), height (24), gap (8), chain (default true: becomes
    -- region._lastInline), tip (a string, or a function returning one: the hover
    -- tooltip while enabled), disabled + disabledTooltip/rawTooltip/requireState
    -- (as ResolveDisabledTip): greyed, click-blocked, without hover colours and
    -- explaining itself on hover while disabled, re-checked with the page's
    -- widgets. Returns the button; nil during the search prebuild.
    function CludesUI.BuildInlineButton(rgn, textValue, onClick, options)
        if CludesUI._prebuilding then
            return
        end
        options = options or {}
        local button = CreateFrame("Button", nil, rgn)
        Pix.Size(button, options.width or 110, options.height or 24)
        local anchor = (options.chain ~= false and rgn._lastInline) or rgn._control
        if anchor then
            Pix.Point(button, "RIGHT", anchor, "LEFT", -(options.gap or 8), 0)
        else
            Pix.Point(button, "RIGHT", rgn, "RIGHT", -20, 0)
        end
        if options.chain ~= false then
            rgn._lastInline = button
        end
        button:SetFrameLevel(rgn:GetFrameLevel() + 5)
        MakeStyledButton(button, textValue, 11, WB_COLOURS, onClick)
        local tipText, disabled = options.tip, options.disabled
        if not (tipText or disabled) then
            return button
        end
        -- The styled button's hover scripts paint its hover colours; these wrap
        -- them so a disabled button keeps its resting colours.
        local hoverOn, hoverOff = button:GetScript("OnEnter"), button:GetScript("OnLeave")
        -- A state with no text hides the other state's tooltip (a flip replays this).
        local function OnEnter(self)
            if disabled and disabled() then
                hoverOff(self)
                local t = ResolveDisabledTip(options)
                if t then
                    ShowWidgetTooltip(self, t)
                else
                    HideWidgetTooltip()
                end
                return
            end
            hoverOn(self)
            local t = tipText
            if type(t) == "function" then
                t = t()
            end
            if t then
                ShowWidgetTooltip(self, t)
            else
                HideWidgetTooltip()
            end
        end
        button:SetScript("OnEnter", OnEnter)
        button:SetScript("OnLeave", function(self)
            hoverOff(self)
            HideWidgetTooltip()
        end)
        if disabled then
            -- Motion scripts keep running while disabled, so hover explains the lock.
            button:SetMotionScriptsWhileDisabled(true)
            local shownOff
            local function State()
                local off = disabled() and true or false
                if off == shownOff then
                    return
                end
                local flipped = shownOff ~= nil
                shownOff = off
                button:SetEnabled(not off)
                button:SetAlpha(off and 0.35 or 1)
                -- A flip while it holds the mouse repaints and re-explains for the
                -- new state (a menu open over it keeps the focus instead).
                if flipped and GetMouseFoci()[1] == button then
                    OnEnter(button)
                end
            end
            State()
            RegisterWidgetRefresh(State)
        end
        return button
    end

    -- Opens Unlock Mode from an options row with the element `key` selected and
    -- its mover flashed once the movers have faded in: the sidebar entry's path
    -- (the active module and page become the return target the exit reopens; the
    -- panel stays shown, since the open animation reads its size and shrinks and
    -- hides it itself, and Spec Overrides stashes its editing session only while
    -- the panel still shows) plus the auto-select key and the flash flag the end
    -- of the open animation reads. In combat nothing changes and the red chat line
    -- explains. Returns whether the open was requested.
    function CludesUI.OpenUnlockModeAt(key)
        if InCombatLockdown() then
            CludesUI.PrintError("Cannot enter Layout Mode during combat.")
            return false
        end
        -- Installed by the unlock core's init, so a live check rather than a dead guard.
        if not CludesUI._openUnlockMode then
            return false
        end
        CludesUI._unlockReturnModule = CludesUI:GetActiveModule()
        CludesUI._unlockReturnPage = CludesUI:GetActivePage()
        CludesUI._unlockAutoSelectKey = key
        CludesUI._unlockAutoSelectFlash = true
        C_Timer.After(0, CludesUI._openUnlockMode)
        return true
    end

    -- "Move in Unlock Mode" inline button on a DualRow half-region: an inline cog
    -- (BuildInlineCog's placement, chain, alphas, tooltip and disabled block) that
    -- wears the unlocked-lock glyph and whose click is OpenUnlockModeAt(opts.key).
    -- opts: key (the unlock element to select: a string, or a function returning
    -- it at the click, for a page whose selector picks the element), tooltip
    -- ("Move in Unlock Mode"), disabled + disabledTooltip/rawTooltip/requireState,
    -- size, gap, anchorTo, relPoint, chain (as BuildInlineCog). Returns the
    -- button; nil during the search prebuild.
    -- The glyph in the accent: 70% at rest, full while hovered, 20% while
    -- disabled (owner 2026-10-23).
    local function UnlockJumpPaint(button, off, hot)
        button:SetAlpha(off and 0.2 or (hot and 1 or 0.7))
        local r, g, b = CludesUI.GetAccentColor()
        button._icon:SetVertexColor(r, g, b)
    end

    function CludesUI.BuildUnlockJump(rgn, options)
        if CludesUI._prebuilding then
            return
        end
        local key = options.key
        local button = BuildInlineCog(rgn, {
            icon = CludesUI.UNLOCK_ICON,
            tip = options.tooltip or "Move in Layout Mode",
            show = function()
                local k = key
                if type(k) == "function" then
                    k = k()
                end
                if k then
                    CludesUI.OpenUnlockModeAt(k)
                end
            end,
            disabled = options.disabled,
            disabledTooltip = options.disabledTooltip,
            rawTooltip = options.rawTooltip,
            requireState = options.requireState,
            size = options.size,
            gap = options.gap,
            anchorTo = options.anchorTo,
            relPoint = options.relPoint,
            chain = options.chain,
            paint = UnlockJumpPaint,
        })
        -- The glyph's art is square (30x30), so the cog icon's own fill of the
        -- button is its fit; drawn unsnapped, since it lands between texel sizes.
        local icon = button._icon
        if icon.SetSnapToPixelGrid then
            icon:SetSnapToPixelGrid(false)
            icon:SetTexelSnappingBias(0)
        end
        return button
    end

    -- "Move in Unlock Mode" on a section header (W:SectionHeader's frame): the
    -- same glyph button, right after the title. One per movable element, on the
    -- first section of that element's settings (owner 2026-10-21): a page whose
    -- selector picks the element (an action bar, a unit frame, a CDM bar) passes
    -- a key FUNCTION that reads the selection, so the click highlights that one.
    -- opts: key (string or function), tooltip, disabled + disabledTooltip/
    -- rawTooltip/requireState (the element's own enable, where it has one), size
    -- (20). Returns the button; nil during the search prebuild or without a
    -- titled header.
    function CludesUI.BuildSectionUnlockJump(heading, options)
        if CludesUI._prebuilding then
            return
        end
        local labelText = heading and heading._label
        if not labelText then
            return
        end
        local size = options.size or 20
        local button = CludesUI.BuildUnlockJump(heading, {
            key = options.key,
            tooltip = options.tooltip,
            disabled = options.disabled,
            disabledTooltip = options.disabledTooltip,
            rawTooltip = options.rawTooltip,
            requireState = options.requireState,
            size = size,
            chain = false,
            anchorTo = labelText,
            relPoint = "RIGHT",
            gap = 0,
        })
        button:ClearAllPoints()
        Pix.Point(button, "LEFT", labelText, "RIGHT", 3, 0)
        return button
    end

    -------------------------------------------------------------------------------
    --  Row-Label and Button Menus
    --  The standard dropdown list opened from something that is not a dropdown
    --  control: a DualRow half's own label (BuildRowLabelMenu) or a button
    --  (AttachButtonMenu). The list is built on first open, takes the standard
    --  open/close behaviour and closes when its button hides. A pick writes its
    --  caption into a hidden stand-in, never over the label or the button's text.
    -------------------------------------------------------------------------------
    local ROW_MENU_ARROW = "Interface\\AddOns\\CludesUI\\media\\icons\\cui-arrow-down3.png"
    -- WireDropdownScripts paints a dropdown button's border and background; these
    -- buttons keep their own look.
    local NO_PAINT = { SetColor = function() end, SetColorTexture = function() end }
    local function NoSelection()
        return nil
    end

    -- The accent, or a darker white when the accent itself is near white.
    local function RowMenuLitColor()
        local ac = CludesUI.CLUDES_GREEN
        if ac.r > 0.9 and ac.g > 0.9 and ac.b > 0.9 then
            return 0.72, 0.72, 0.72
        end
        return ac.r, ac.g, ac.b
    end

    -- A button over the half's label, with a chevron after the label: label and
    -- chevron white at rest, in the accent while hovered or while the list is open.
    -- opts: order, values, getValue(), setValue(v), itemDisabled(v) (nil, true or a
    --   tooltip string, as BuildDropdownMenu's disabledValuesFn), tooltip (on hover
    --   while the list is closed), menuWidth (170); optional locked() + lockTip() +
    --   rawLockTip (as ResolveDisabledTip's rawTooltip): while locked the chevron
    --   hides, clicks do nothing and hover explains the lock, re-checked with the
    --   page's widgets. Never touches region._lastInline or region._control.
    -- Returns the button; nil during the search prebuild.
    local function BuildRowLabelMenu(rgn, options)
        if CludesUI._prebuilding then
            return
        end
        local labelText = rgn._label
        if not labelText then
            return
        end
        local locked = options.locked
        local lockCfg = locked and { disabledTooltip = options.lockTip, rawTooltip = options.rawLockTip }
        local button = CreateFrame("Button", nil, rgn)
        button:SetFrameLevel(rgn:GetFrameLevel() + 12)
        local arrow = button:CreateTexture(nil, "ARTWORK")
        arrow:SetTexture(ROW_MENU_ARROW)
        arrow:SetSize(17, 17)
        arrow:SetPoint("LEFT", labelText, "LEFT", math.ceil(labelText:GetStringWidth()) + 6, -1)
        -- The label clamp (QueueLabelClamp) keeps room for it and moves it with a cut label.
        rgn._labelArrow = arrow
        button:SetPoint("TOPLEFT", labelText, "TOPLEFT", -4, 5)
        button:SetPoint("BOTTOMRIGHT", arrow, "BOTTOMRIGHT", 2, -2)
        local dropMenu
        local function Lit(enabled)
            if enabled then
                local r, g, b = RowMenuLitColor()
                arrow:SetVertexColor(r, g, b)
                labelText:SetTextColor(r, g, b)
            else
                arrow:SetVertexColor(1, 1, 1)
                labelText:SetTextColor(CludesUI.TEXT_WHITE_R, CludesUI.TEXT_WHITE_G, CludesUI.TEXT_WHITE_B)
            end
        end
        local function OnEnter()
            if locked and locked() then
                local tipText = ResolveDisabledTip(lockCfg)
                if tipText then
                    ShowWidgetTooltip(button, tipText)
                end
                return
            end
            Lit(true)
            if options.tooltip and not (dropMenu and dropMenu:IsShown()) then
                ShowWidgetTooltip(button, options.tooltip)
            end
        end
        local function OnLeave()
            if not (dropMenu and dropMenu:IsShown()) then
                Lit(false)
            end
            HideWidgetTooltip()
        end
        button:SetScript("OnEnter", OnEnter)
        button:SetScript("OnLeave", OnLeave)
        local proxyLbl = CludesUI.MakeFont(button, 12, nil, 1, 1, 1)
        proxyLbl:Hide()
        local function EnsureMenu()
            if dropMenu then
                return dropMenu
            end
            local m, _, refresh = BuildDropdownMenu(
                button,
                options.menuWidth or 170,
                options.order,
                options.values,
                options.getValue or NoSelection,
                options.setValue,
                proxyLbl,
                "regular",
                options.itemDisabled
            )
            dropMenu = m
            -- The wiring takes the button's hover scripts: its own run again after.
            WireDropdownScripts(
                button,
                proxyLbl,
                NO_PAINT,
                NO_PAINT,
                dropMenu,
                refresh,
                CludesUI.RD_DD_COLOURS,
                true
            )
            button:HookScript("OnEnter", OnEnter)
            button:HookScript("OnLeave", OnLeave)
            dropMenu:HookScript("OnShow", function()
                Lit(true)
            end)
            dropMenu:HookScript("OnHide", function()
                Lit(button:IsMouseOver())
            end)
            return dropMenu
        end
        button:SetScript("OnClick", function()
            if locked and locked() then
                return
            end
            HideWidgetTooltip()
            local m = EnsureMenu()
            if m:IsShown() then
                m:Hide()
            else
                m:Show()
            end
        end)
        button:HookScript("OnHide", function()
            if dropMenu then
                dropMenu:Hide()
            end
        end)
        Lit(false)
        if locked then
            -- Disabled while locked, still hovered to explain the lock.
            button:SetMotionScriptsWhileDisabled(true)
            local function SyncLock()
                local off = locked() and true or false
                arrow:SetShown(not off)
                button:SetEnabled(not off)
            end
            SyncLock()
            RegisterWidgetRefresh(SyncLock)
        end
        return button
    end

    -- The list hangs off the button, as wide as the button unless opts.width says
    -- otherwise; the button keeps its own hover look, held while the list shows.
    -- opts: width, order, values, getValue() (default: nothing selected),
    --   setValue(v), itemDisabled(v) (as BuildRowLabelMenu). Returns the toggle the
    --   button's click calls; nil during the search prebuild.
    local function AttachButtonMenu(button, options)
        if CludesUI._prebuilding then
            return
        end
        local enter, leave = button:GetScript("OnEnter"), button:GetScript("OnLeave")
        local proxyLbl = CludesUI.MakeFont(button, 12, nil, 1, 1, 1)
        proxyLbl:Hide()
        local dropMenu
        local function EnsureMenu()
            if dropMenu then
                return dropMenu
            end
            local m, _, refresh = BuildDropdownMenu(
                button,
                options.width or button:GetWidth(),
                options.order,
                options.values,
                options.getValue or NoSelection,
                options.setValue,
                proxyLbl,
                "regular",
                options.itemDisabled
            )
            dropMenu = m
            WireDropdownScripts(
                button,
                proxyLbl,
                NO_PAINT,
                NO_PAINT,
                dropMenu,
                refresh,
                CludesUI.RD_DD_COLOURS,
                true
            )
            if enter then
                button:HookScript("OnEnter", enter)
            end
            if leave then
                button:HookScript("OnLeave", function(self)
                    if not dropMenu:IsShown() then
                        leave(self)
                    end
                end)
                dropMenu:HookScript("OnHide", function()
                    if not button:IsMouseOver() then
                        leave(button)
                    end
                end)
            end
            return dropMenu
        end
        button:HookScript("OnHide", function()
            if dropMenu then
                dropMenu:Hide()
            end
        end)
        return function()
            local m = EnsureMenu()
            if m:IsShown() then
                m:Hide()
            else
                m:Show()
            end
        end
    end

    -------------------------------------------------------------------------------
    --  Less-Common Settings Expander
    --  Centralized collapse link for rarely-customized option rows. Page builders wrap those rows in:
    --      local expanded
    --      expanded, y = CludesUI.BuildLessCommonExpander(parent, y,
    --          "rfIndicators", "Show Less Common Indicator Options")
    --      if expanded then
    --          ... build the less-common rows ...
    --      end
    --      y = CludesUI.FinishLessCommonExpander(parent, y,
    --          "rfIndicators", "Show Less Common Indicator Options")
    --  Sections start collapsed; expansion is session-only per sectionKey (never saved). Clicking the link forces
    --  RefreshPage(true) to re-run the page builder -- the no-arg fast path only re-reads values and would never
    --  reveal the collapsed rows.
    -------------------------------------------------------------------------------
    local LESS_COMMON_ARROW_DOWN = "Interface\\AddOns\\CludesUI\\media\\icons\\cui-arrow-down3.png"
    local LESS_COMMON_ARROW_UP = "Interface\\AddOns\\CludesUI\\media\\icons\\cui-arrow-up3.png"

    -- Shared link renderer for both expander states. The link always sits at the BOTTOM of its section: collapsed it
    -- renders where the hidden rows would start (via BuildLessCommonExpander), expanded it renders below the
    -- revealed rows (via FinishLessCommonExpander). Expanded state flips it into the collapse form: up arrows and a
    -- "Hide ..." label -- the Hide key is derived from the ENGLISH label before localization so both variants are proper L() lookup keys.
    local function BuildLessCommonLink(hostFrame, posY, sectionKey, labelText, expanded)
        local ARROW_SZ, ARROW_GAP = 12, 6
        local button = CreateFrame("Button", nil, hostFrame)
        button:SetHeight(22)
        button:SetPoint("TOP", hostFrame, "TOP", 0, posY - 12)
        button:SetFrameLevel(hostFrame:GetFrameLevel() + 5)

        local arrowTex = expanded and LESS_COMMON_ARROW_UP or LESS_COMMON_ARROW_DOWN
        local textValue = expanded and (labelText:gsub("^Show", "Hide", 1)) or labelText

        local fontStr = CludesUI.MakeFont(button, 13, nil, 1, 1, 1)
        fontStr:SetPoint("LEFT", button, "LEFT", ARROW_SZ + ARROW_GAP, 0)
        fontStr:SetText(CludesUI.L(textValue))
        fontStr:SetAlpha(0.7)

        local leftArrow = button:CreateTexture(nil, "OVERLAY")
        leftArrow:SetSize(ARROW_SZ, ARROW_SZ)
        leftArrow:SetTexture(arrowTex)
        leftArrow:SetPoint("RIGHT", fontStr, "LEFT", -ARROW_GAP, 0)
        leftArrow:SetAlpha(0.7)

        local rightArrow = button:CreateTexture(nil, "OVERLAY")
        rightArrow:SetSize(ARROW_SZ, ARROW_SZ)
        rightArrow:SetTexture(arrowTex)
        rightArrow:SetPoint("LEFT", fontStr, "RIGHT", ARROW_GAP, 0)
        rightArrow:SetAlpha(0.7)

        button:SetWidth(math.max((fontStr:GetStringWidth() or 0) + 2 * (ARROW_SZ + ARROW_GAP) + 8, 120))

        local ACC = CludesUI.CLUDES_GREEN or { r = 0.30, g = 0.79, b = 0.94 }
        button:SetScript("OnEnter", function()
            fontStr:SetTextColor(ACC.r, ACC.g, ACC.b)
            fontStr:SetAlpha(1)
            leftArrow:SetVertexColor(ACC.r, ACC.g, ACC.b)
            leftArrow:SetAlpha(1)
            rightArrow:SetVertexColor(ACC.r, ACC.g, ACC.b)
            rightArrow:SetAlpha(1)
        end)
        button:SetScript("OnLeave", function()
            fontStr:SetTextColor(1, 1, 1)
            fontStr:SetAlpha(0.7)
            leftArrow:SetVertexColor(1, 1, 1)
            leftArrow:SetAlpha(0.7)
            rightArrow:SetVertexColor(1, 1, 1)
            rightArrow:SetAlpha(0.7)
        end)
        button:SetScript("OnClick", function()
            local sess = CludesUI._lessCommonExpanded
            if not sess then
                sess = {}
                CludesUI._lessCommonExpanded = sess
            end
            sess[sectionKey] = (not expanded) and true or nil
            CludesUI:RefreshPage(true)
        end)

        return posY - 40
    end

    local function BuildLessCommonExpander(hostFrame, posY, sectionKey, labelText)
        -- Hidden search pre-build: always build the wrapped rows so they register in the global search index; no link (the page is never shown).
        if CludesUI._prebuilding then
            return true, posY
        end
        -- This page reads the search flag: a search transition rebuilds it (SetLessCommonSearchActive).
        CludesUI._passReadSearchFlag = true
        -- Active search (either box): sections render force-expanded with NO link line at all; clearing the search collapses them back. Transient flag -- the session Show/Hide state below is untouched and restores afterwards (see SetLessCommonSearchActive).
        if CludesUI._lessCommonSearchActive then
            return true, posY
        end
        local sess = CludesUI._lessCommonExpanded
        if not sess then
            sess = {}
            CludesUI._lessCommonExpanded = sess
        end
        -- Expanded: render nothing here -- the caller builds the rows, then FinishLessCommonExpander places the "Hide ..." link below them.
        if sess[sectionKey] then
            return true, posY
        end
        return false, BuildLessCommonLink(hostFrame, posY, sectionKey, labelText, false)
    end

    -- Call after the wrapped rows (safe to call unconditionally: no-ops while the section is collapsed, during the search pre-build or during an active search).
    local function FinishLessCommonExpander(hostFrame, posY, sectionKey, labelText)
        if CludesUI._prebuilding then
            return posY
        end
        CludesUI._passReadSearchFlag = true
        if CludesUI._lessCommonSearchActive then
            return posY
        end
        local sess = CludesUI._lessCommonExpanded
        if not (sess and sess[sectionKey]) then
            return posY
        end
        return BuildLessCommonLink(hostFrame, posY, sectionKey, labelText, true)
    end

    -- Search-driven expansion (both the sidebar global box and the top-bar module box call this with query ~= ""). While active, every less-common section renders expanded with no link; on clear, sections fall back to their session Show/Hide state. Idempotent -- only transitions act, and only on the pages whose last build read the flag (the expanders above, Bar Glows): those go (or are marked for a rebuild), and the active one is rebuilt in place, unless a page switch is clearing the box (the page being left is rebuilt on its next visit).
    local function SetLessCommonSearchActive(isActive)
        isActive = isActive and true or false
        if (CludesUI._lessCommonSearchActive or false) == isActive then
            return
        end
        CludesUI._lessCommonSearchActive = isActive
        if CludesUI._InvalidateSearchSensitive() and not CludesUI._selectingPage then
            CludesUI:RefreshPage(true)
        end
    end

    -- A colour scale across a swatch: stops = { { r, g, b }, ... }, drawn left to
    -- right in equal steps over its fill (for a swatch that picks a scale, such as
    -- the meters' value gradient).
    local function PaintSwatchGradient(colorSwatch, stops)
        local steps = #stops - 1
        local wid = colorSwatch:GetWidth()
        for idx = 1, steps do
            local from, to = stops[idx], stops[idx + 1]
            local seg = colorSwatch:CreateTexture(nil, "ARTWORK", nil, 1)
            seg:SetPoint("TOPLEFT", colorSwatch, "TOPLEFT", wid * (idx - 1) / steps, 0)
            seg:SetPoint("BOTTOMRIGHT", colorSwatch, "BOTTOMLEFT", wid * idx / steps, 0)
            seg:SetColorTexture(1, 1, 1, 1)
            seg:SetGradient(
                "HORIZONTAL",
                CreateColor(from[1], from[2], from[3], 1),
                CreateColor(to[1], to[2], to[3], 1)
            )
        end
    end

    -------------------------------------------------------------------------------
    --  BuildInlineSwatches(region, swatches, opts)
    --  Inline form of the multiSwatch half: builds the same swatch list (tooltip, hasAlpha, getValue/setValue,
    --  onClick override, per-swatch disabled+disabledTooltip, refreshAlpha, gradient) to the LEFT of the region's
    --  control, so a slider (or any control half) can host its color swatches on the same row. Chains from
    --  region._lastInline: a slot's cog is built first and the swatches land left of it. opts.disabled/opts.disabledTooltip
    --  mirror the row-level disabled state of the multiSwatch form.
    --  opts.size: the swatch size (nil = 20, the inline swatch size; BuildColorSwatch's own 24 is a swatch half's).
    --  sc.gradient: colour stops shown across the swatch in place of its colour (PaintSwatchGradient).
    -------------------------------------------------------------------------------
    local function BuildInlineSwatches(regionFrame, swatches, options)
        -- Hidden search pre-build: swatches index nothing and the pre-built page is never shown, so none are built (its regions are stand-ins with no frame to build on).
        if CludesUI._prebuilding then
            return
        end
        options = options or {}
        local level = regionFrame:GetFrameLevel() + 3
        local anchorTo = regionFrame._lastInline or regionFrame._control
        for idx = #swatches, 1, -1 do
            local sc = swatches[idx]
            local colorSwatch, updateSwatch = BuildColorSwatch(
                regionFrame,
                level,
                sc.getValue,
                sc.setValue,
                sc.hasAlpha,
                options.size or 20
            )
            Pix.Point(colorSwatch, "RIGHT", anchorTo, "LEFT", -8, 0)
            anchorTo = colorSwatch
            regionFrame._lastInline = colorSwatch
            if sc.gradient then
                PaintSwatchGradient(colorSwatch, sc.gradient)
            end
            if sc.onClick then
                colorSwatch._eabOrigClick = colorSwatch:GetScript("OnClick")
                colorSwatch:SetScript("OnClick", sc.onClick)
            end
            local function SwatchEffectiveDisabled()
                if options.disabled and options.disabled() then
                    return true
                end
                if sc.disabled ~= nil then
                    if type(sc.disabled) == "function" then
                        return sc.disabled()
                    end
                    return sc.disabled
                end
                return false
            end
            if options.disabled or sc.disabled then
                local swatchBlock = CreateFrame("Frame", nil, colorSwatch)
                swatchBlock:SetAllPoints()
                swatchBlock:SetFrameLevel(colorSwatch:GetFrameLevel() + 10)
                swatchBlock:EnableMouse(true)
                swatchBlock:SetScript("OnEnter", function()
                    local source = (sc.disabledTooltip ~= nil) and sc or options
                    local tipText = ResolveDisabledTip(source)
                    if tipText then
                        ShowWidgetTooltip(colorSwatch, tipText)
                    end
                end)
                swatchBlock:SetScript("OnLeave", function()
                    HideWidgetTooltip()
                end)
                local function UpdateSwatchDisabled()
                    if SwatchEffectiveDisabled() then
                        colorSwatch:SetAlpha(0.3)
                        swatchBlock:Show()
                    else
                        colorSwatch:SetAlpha(1)
                        swatchBlock:Hide()
                    end
                end
                UpdateSwatchDisabled()
                RegisterWidgetRefresh(UpdateSwatchDisabled)
            end
            if sc.tooltip then
                colorSwatch:HookScript("OnEnter", function()
                    ShowWidgetTooltip(colorSwatch, sc.tooltip)
                end)
                colorSwatch:HookScript("OnLeave", function()
                    HideWidgetTooltip()
                end)
            end
            if sc.refreshAlpha then
                local _sw, _ra = colorSwatch, sc.refreshAlpha
                local function UpdateAlpha()
                    if SwatchEffectiveDisabled() then
                        return
                    end
                    _sw:SetAlpha(_ra())
                end
                UpdateAlpha()
                RegisterWidgetRefresh(UpdateAlpha)
            end
            RegisterWidgetRefresh(function()
                updateSwatch()
            end)
        end
    end
    CludesUI.BuildInlineSwatches = BuildInlineSwatches

    -------------------------------------------------------------------------------
    --  Hidden-While-Disabled Section Gate
    --  For sections whose master toggle HIDES the dependent rows instead of graying them: the page builder simply
    --  skips building those rows while the toggle is off, and the toggle's setValue is wrapped with this so flipping it re-runs the page builder to reveal/hide them:
    --      { type="toggle", text="Enable Top Name Bar",
    --        getValue=...,
    --        setValue=CludesUI.SectionToggleSetValue(function(v)
    --            SSet("tnbEnabled", v); ApplyAll()
    --        end) }
    -------------------------------------------------------------------------------
    local function SectionToggleSetValue(func)
        return function(val)
            func(val)
            CludesUI:RefreshPage(true)
        end
    end

    -------------------------------------------------------------------------------
    --  Dependent-Row Visibility
    --  Row-level version of the section gate: one setting's value hides entire dependent rows instead of graying
    --  them. The builder skips the dependent rows behind a plain predicate check, and the TRIGGER setting's setValue
    --  is wrapped with this so the page rebuilds only when the predicate actually flips -- ordinary value changes keep whatever refresh the inner setValue already does, with no rebuild flash:
    --      -- trigger dropdown:
    --      setValue = CludesUI.DependentSetValue(
    --          function() return SVal("healAbsorbTextMode", "none") ~= "none" end,
    --          function(v) SSet("healAbsorbTextMode", v); CludesUI:RefreshPage() end),
    --
    --      -- dependent row below (skip building while hidden):
    --      if SVal("healAbsorbTextMode", "none") ~= "none" then
    --          ... build the dependent row(s) ...
    --      end
    -------------------------------------------------------------------------------
    local function DependentSetValue(pred, func)
        return function(val)
            local before = pred() and true or false
            func(val)
            if (pred() and true or false) ~= before then
                CludesUI:RefreshPage(true)
            end
        end
    end

    CludesUI.BuildInlineToggle = BuildInlineToggle
    CludesUI.BuildInlineCog = BuildInlineCog
    CludesUI.BuildRowLabelMenu = BuildRowLabelMenu
    CludesUI.AttachButtonMenu = AttachButtonMenu
    CludesUI.BuildLessCommonExpander = BuildLessCommonExpander
    CludesUI.FinishLessCommonExpander = FinishLessCommonExpander
    CludesUI.SetLessCommonSearchActive = SetLessCommonSearchActive
    CludesUI.SectionToggleSetValue = SectionToggleSetValue
    CludesUI.DependentSetValue = DependentSetValue

    -------------------------------------------------------------------------------
    --  BuildCursorAnchorRow
    --  Shared "Anchor to Cursor" row used by CDM, Resource Bars, and any future section that supports cursor anchoring.
    --  opts:
    --    W           = widget factory (the W: table from options page)
    --    parent      = parent frame
    --    getData     = function() -> settings table with anchorTo, anchorPosition, anchorOffsetX, anchorOffsetY
    --    onApply     = function() -> rebuild/refresh after value change
    --    disabledFn  = (optional) function() -> true when the whole row is disabled
    --    disabledTip = (optional) tooltip string for disabled state
    --  Returns: row, height (same as W:DualRow)
    -------------------------------------------------------------------------------
    local function BuildCursorAnchorRow(options)
        local W = options.W
        local hostFrame = options.parent
        local getData = options.getData
        local onApply = options.onApply

        local row, hgt = W:DualRow(hostFrame, options.y, {
            type = "toggle",
            text = "Anchor to Cursor",
            disabled = options.disabledFn,
            disabledTooltip = options.disabledTip,
            getValue = function()
                return getData().anchorTo == "mouse"
            end,
            setValue = function(val)
                local old = getData().anchorTo
                local new = val and "mouse" or "none"
                getData().anchorTo = new
                -- Cursor anchor requires a reload to take effect cleanly (Blizzard viewer Layout fights icon positions on live switch).
                local changed = (old == "mouse") ~= (new == "mouse")
                if changed then
                    CludesUI:ShowConfirmPopup({
                        title = "Reload Required",
                        message = "Changing cursor anchor requires a UI reload to take effect.",
                        confirmText = "Reload Now",
                        cancelText = "Later",
                        reload = true,
                    })
                else
                    onApply()
                end
                CludesUI:RefreshPage(true)
            end,
        }, {
            type = "dropdown",
            text = "Cursor Position",
            values = { left = "Left", right = "Right", top = "Top", bottom = "Bottom" },
            order = { "left", "right", "top", "bottom" },
            disabled = function()
                if options.disabledFn and options.disabledFn() then
                    return true
                end
                return getData().anchorTo ~= "mouse"
            end,
            disabledTooltip = "Anchor to Cursor",
            getValue = function()
                return getData().anchorPosition or "right"
            end,
            setValue = function(val)
                getData().anchorPosition = val
                onApply()
            end,
        })

        -- "(Applies on Window Close)" subtitle
        do
            local suffix = row._leftRegion:CreateFontString(nil, "OVERLAY")
            suffix:SetFont(CludesUI.EXPRESSWAY, 11, "")
            suffix:SetTextColor(1, 1, 1, 0.35)
            suffix:SetText(CludesUI.L("(Applies on Window Close)"))
            local anchorLabel
            local regions = { row._leftRegion:GetRegions() }
            for idx = 1, #regions do
                local reg = regions[idx]
                if reg and reg.GetText and CludesUI.EnKey(reg:GetText()) == "Anchor to Cursor" then
                    anchorLabel = reg
                    break
                end
            end
            if anchorLabel then
                suffix:SetPoint("LEFT", anchorLabel, "RIGHT", 5, 0)
            else
                suffix:SetPoint("LEFT", row._leftRegion, "LEFT", 120, 0)
            end
        end

        -- Inline cog: X + Y offsets
        BuildInlineCog(row._rightRegion, {
            title = "Cursor Offset",
            rows = {
                {
                    type = "slider",
                    label = "X Offset",
                    min = -125,
                    max = 125,
                    step = 1,
                    get = function()
                        return getData().anchorOffsetX or 0
                    end,
                    set = function(val)
                        getData().anchorOffsetX = val
                        onApply()
                    end,
                },
                {
                    type = "slider",
                    label = "Y Offset",
                    min = -125,
                    max = 125,
                    step = 1,
                    get = function()
                        return getData().anchorOffsetY or 0
                    end,
                    set = function(val)
                        getData().anchorOffsetY = val
                        onApply()
                    end,
                },
            },
        })

        return row, hgt
    end
    CludesUI.BuildCursorAnchorRow = BuildCursorAnchorRow
end -- end deferred init
