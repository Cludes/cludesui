if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_ResourceBars_Options.lua - the Resource Bars module's settings.
--
--  Registers the module (pages: Class, Power and Health Bars; Cast Bar; GCD
--  Bar; Swing Timer on WoW Forever; Totem Bar) and holds what those pages
--  share: the live preview headers, the threshold band editor, the colour
--  list editor, the hash-mark cog and the Classic-style border rows. The
--  pages themselves are built in ResourceBars_Options\*.lua, which reach the
--  shared pieces through mod._CURB_OptEnv (set up at the end of the init).
-------------------------------------------------------------------------------
local mod = CludesUI._ModuleNS["CludesUIResourceBars"] -- published by the module when it loads
if not mod then
    return -- the module is disabled: no pages
end
local abs = math.abs

-- Page names: also the identity used by nav targets and saved state.
local PAGE_DISPLAY = "Class, Power and Health Bars"
local PAGE_CASTBAR = "Cast Bar"
local PAGE_GCD = "GCD Bar"
local PAGE_SWING = "Swing Timer" -- WoW Forever only (C_SwingTimer)
local PAGE_TOTEM = "Totem Bar"

-- WoW Forever labels two tabs differently ("Totem Bars" holds the Call Totem
-- Bar too); only the shown label changes.
if CludesUI.IS_FOREVER then
    CludesUI.TAB_LABEL_OVERRIDES[PAGE_DISPLAY] = "Main Resources"
    CludesUI.TAB_LABEL_OVERRIDES[PAGE_TOTEM] = "Totem Bars"
end

-------------------------------------------------------------------------------
--  Border rows under the stock styles
-------------------------------------------------------------------------------
local function StockStyle()
    return CludesUI.BlizzStyle.Active("resourcebars")
end

-- Classic WoW UI: a bar's Border Size slot sizes the vanilla frame round it
-- (stockBorderScale, a percent of the frame's full size; nil = the shared
-- default) instead of CludesUI's border; the colour swatch, offset cog and
-- style sync of that row stand down. The cast bar row does the same on its
-- own style key.
function mod.ERB_ClassicBorderRow()
    return StockStyle() == "classic"
end
-- "Border Around All" is offered under either stock style.
function mod.ERB_BorderAllRow()
    return StockStyle() ~= "cui"
end

local CLASSIC_SYNC_KEYS = { "health", "primary", "secondary" }
local CLASSIC_MATCH_KEYS = { "ERB_Health", "ERB_Power", "ERB_ClassResource" }

local function Profile()
    local db = _G._CURB_AceDB
    return db and db.profile
end

-- Writes one stockBorderScale to all three bars, then re-fits every bar's
-- Layout Mode size matches (they read the frame's reach).
local function ClassicScaleToAll(p, v)
    for _, key in ipairs(CLASSIC_SYNC_KEYS) do
        p[key].stockBorderScale = v
    end
end
local function RefitAll()
    for _, key in ipairs(CLASSIC_MATCH_KEYS) do
        CludesUI.ReapplyMatchPads(key)
    end
end

-- The Classic border size slider for one bar. matchKey is the bar's Layout
-- Mode element. While "Border Around All" is on the three bars share one
-- frame, so one size: any bar's slider writes all three.
function mod.ERB_ClassicBorderSizeCfg(cfgFn, offFn, offTip, rebuild, matchKey)
    return CludesUI.BlizzStyle.ClassicBorderSizeCfg(function()
        local c = cfgFn()
        return c and c.stockBorderScale
    end, function(v)
        local c = cfgFn()
        if not c then
            return
        end
        c.stockBorderScale = v
        local p = Profile()
        local together = p and mod.ERB_GroupSettingOn and mod.ERB_GroupSettingOn(p)
        if together then
            ClassicScaleToAll(p, v)
        end
        rebuild()
        if together then
            RefitAll()
        else
            CludesUI.ReapplyMatchPads(matchKey)
        end
        CludesUI:RefreshPage()
    end, { disabled = offFn, disabledTooltip = offTip })
end

-- The sync icon on a Classic border row: copies this bar's size to all three.
function mod.ERB_ClassicBorderSync(regionFrame, dbFn, key, refresh, flashFn)
    CludesUI.BuildSyncIcon({
        region = regionFrame,
        tooltip = "Apply Border Size to all Bars",
        onClick = function()
            local p = dbFn()
            if not p then
                return
            end
            ClassicScaleToAll(p, p[key].stockBorderScale)
            refresh()
            RefitAll()
            CludesUI:RefreshPage()
        end,
        isSynced = function()
            local p = dbFn()
            if not p then
                return false
            end
            local v = p[key].stockBorderScale
            for _, other in ipairs(CLASSIC_SYNC_KEYS) do
                if p[other].stockBorderScale ~= v then
                    return false
                end
            end
            return true
        end,
        flashTargets = flashFn,
    })
end

-------------------------------------------------------------------------------
--  Small shared helpers (also used by the page files)
-------------------------------------------------------------------------------
-- The exact border size (borderSizePx, see CludesUI.BorderPx) travels with
-- borderSize in the "apply to all" syncs. A value the target had is cleared
-- with false, never nil: nil does not carry through the mirror sync.
function mod.ERB_CopyBorderPx(target, source)
    local v = source.borderSizePx
    if v == nil and target.borderSizePx ~= nil then
        v = false
    end
    target.borderSizePx = v
end
-- Two bars agree when both are unset (nil or false) or hold the same value.
function mod.ERB_SameBorderPx(a, b)
    return (a.borderSizePx or false) == (b.borderSizePx or false)
end

-- The Separator Art dropdown (fresh tables each page build): "match" (the
-- bar's own style, see ns.ERB_SeparatorArt) first, then every built-in border
-- style that has a horizontal companion strip, so a new style with separator
-- art appears with no change here. withNone puts a "none" entry first.
function mod.ERB_SeparatorArtValues(withNone)
    local values, order = {}, {}
    if withNone then
        values.none = "None"
        order[1] = "none"
    end
    values.match = "Match Border"
    order[#order + 1] = "match"
    for _, style in ipairs(CludesUI._builtinBorderTextures) do
        if CludesUI.GetBorderCompanion(style.key, "sepH") then
            values[style.key] = style.name
            order[#order + 1] = style.key
        end
    end
    return values, order
end

-- Which of the three bars have a textured border, as "101" style flags. A
-- cross-bar border sync that changes it rebuilds the page (a section's Width
-- / Height Offset row exists only for a textured style); otherwise the quick
-- refresh keeps the sync icon's flash.
function mod.ERB_TexturedBars(p)
    local function Flag(bar)
        local style = bar and bar.borderTexture or "solid"
        return (style ~= "solid" and style ~= "") and "1" or "0"
    end
    return Flag(p.health) .. Flag(p.primary) .. Flag(p.secondary)
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    if not CludesUI or not CludesUI.RegisterModule then
        return
    end
    -- Options page pool (CludesUI_FramePool.lua): frames made here on a pool
    -- host are reset and dressed again by the next build instead of made anew;
    -- elsewhere this is CreateFrame. Captured once, never read through the
    -- public slot later.
    local CreateFrame = CludesUI._Pool.CreateFrame
    local PoolGen, PoolKeep = CludesUI._Pool.Gen, CludesUI._Pool.Keep
    local Pix = CludesUI.PanelPP
    local THR_BORDER_WHITE = { 1, 1, 1 } -- Threshold & Hash Lines buttons: default (unconfigured) border tint

    -- The module's saved profile (its database exists by the time a page builds).
    local function DB()
        local db = _G._CURB_AceDB
        return db and db.profile
    end

    -- Re-applies every bar from the saved settings.
    local function Refresh()
        if _G._CURB_Apply then
            _G._CURB_Apply()
        end
    end

    ---------------------------------------------------------------------------
    --  Eased value change: applyFn(v) each frame from the last value to the
    --  new one over ANIM_DURATION (ease-out). A new target for the same frame
    --  and key replaces the running one.
    ---------------------------------------------------------------------------
    local _animTimers = {} -- [frame][key] = ticker
    local ANIM_DURATION = 0.18
    local STEP = 0.016

    local function SmoothAnimate(widget, key, targetVal, applyFn)
        if not widget then
            return
        end
        local running = _animTimers[widget] or {}
        _animTimers[widget] = running
        if running[key] then
            running[key]:Cancel()
            running[key] = nil
        end
        local field = "_anim_" .. key
        local from = widget[field] or targetVal
        widget[field] = targetVal
        if math.abs(from - targetVal) < 0.001 then
            applyFn(targetVal)
            return
        end
        local elapsed, ticker = 0, nil
        local function Stop()
            ticker:Cancel()
            if running[key] == ticker then
                running[key] = nil
            end
        end
        -- A pooled frame dressed again mid-animation belongs to its new build:
        -- the animation stops and leaves it alone.
        local gen = PoolGen(widget)
        ticker = C_Timer.NewTicker(STEP, function()
            if PoolGen(widget) ~= gen then
                Stop()
                return
            end
            elapsed = elapsed + STEP
            local t = math.min(elapsed / ANIM_DURATION, 1)
            t = 1 - (1 - t) * (1 - t)
            applyFn(from + (targetVal - from) * t)
            if t >= 1 then
                Stop()
            end
        end)
        running[key] = ticker
    end

    -- Preview header state
    local _previewHeaderBuilder
    local _previewFrames = {}
    local _previewHintFS
    local _previewScale = 1
    local _previewBuilding = false -- true while _previewHeaderBuilder runs

    local function HasClassResource()
        local get = _G._CURB_GetSecondaryResource
        return get and get() ~= nil
    end
    local function HasPrimaryPower()
        local get = _G._CURB_GetPrimaryPowerType
        return get and get() ~= nil
    end

    local function IsPreviewHintDismissed()
        return CludesUIDB and CludesUIDB.previewHintDismissed
    end

    -- The preview hint is one font string shared by the bars and cast bar
    -- headers; each build moves it onto its own header. With page reuse each
    -- page keeps its own (pooled) header frame: a build starts with the hint
    -- off its header (the shared clear dropped it), and a header shown again
    -- from the cache takes the hint back from the other page's header.
    local _hintHdr = {} -- [page] = the header its preview last built on
    local _classHdrEmpty -- the bars header last built with nothing to show
    local function HintBuildStart(page, heading)
        _hintHdr[page] = heading
        local holder = PoolGen(heading) and _previewHintFS and _previewHintFS:GetParent()
        if holder and holder:GetParent() == heading then
            holder:Hide()
        end
    end
    local function RehomeHint(page)
        local holder = _previewHintFS and _previewHintFS:GetParent()
        local heading = _hintHdr[page]
        if not (holder and heading) then
            return
        end
        -- Find whether another page's header holds the hint now.
        local onHeader, elsewhere = holder:GetParent(), nil
        for other, otherHeading in pairs(_hintHdr) do
            if other ~= page then
                if otherHeading == heading then
                    return -- the pages share one header: nothing to move
                end
                if otherHeading == onHeader then
                    elsewhere = otherHeading
                end
            end
        end
        if elsewhere then
            holder:SetParent(heading)
            holder:SetFrameLevel(heading:GetFrameLevel() + 1)
            _previewHintFS:ClearAllPoints()
            _previewHintFS:SetPoint("BOTTOM", heading, "BOTTOM", 0, 20)
        elseif onHeader ~= heading then
            return
        end
        if holder:GetParent() == heading then
            holder:Show()
        end
    end

    local FONT_PATH = (CludesUI.GetFontPath("resourceBars"))
        or "Interface\\AddOns\\CludesUI\\media\\fonts\\Expressway.TTF"
    local SetPVFont = CludesUI.ApplyModuleFont
    local CONTENT_PAD = 45
    local SIDE_PAD = 20

    -- The health preview's fill when no custom colour is set: the player's
    -- class colour (fixed values, as the live bar uses).
    local CLASS_COLORS = {
        WARRIOR = { 0.78, 0.61, 0.43 },
        PALADIN = { 0.96, 0.55, 0.73 },
        HUNTER = { 0.67, 0.83, 0.45 },
        ROGUE = { 1.00, 0.96, 0.41 },
        PRIEST = { 1.00, 1.00, 1.00 },
        DEATHKNIGHT = { 0.77, 0.12, 0.23 },
        SHAMAN = { 0.00, 0.44, 0.87 },
        MAGE = { 0.25, 0.78, 0.92 },
        WARLOCK = { 0.53, 0.53, 0.93 },
        MONK = { 0.00, 1.00, 0.60 },
        DRUID = { 1.00, 0.49, 0.04 },
        DEMONHUNTER = { 0.64, 0.19, 0.79 },
        EVOKER = { 0.20, 0.58, 0.50 },
    }

    -- Dark Mode colours come from the per-profile palette (GetDarkModeFill /
    -- GetDarkModeBg). As on the live bars, the opacity sliders do not apply
    -- there (the background stays opaque).

    -- Preview textures snap to the preview container's own scale (the
    -- per-build _previewSnap), never to screen pixels, which can disagree
    -- with the preview grid.
    local UnsnapTex = CludesUI.PP.DisablePixelSnap
    local _previewSnap -- set by each preview build

    local _borderRefreshers = {} -- re-snap sizes when the scale changes

    -- A pixel-perfect border round hostFrame (the shared PP border; raw
    -- integer sizes, never scaled), as a small handle.
    local function MakePreviewBorder(hostFrame, r, g, b, a, size)
        local holder = CreateFrame("Frame", nil, hostFrame)
        holder:SetAllPoints(hostFrame)
        holder:SetFrameLevel(hostFrame:GetFrameLevel() + 2)
        local PP = CludesUI and CludesUI.PP
        if PP then
            PP.CreateBorder(holder, r, g, b, a or 1, size or 1, "BORDER", 7)
        end
        local handle = { _frame = holder, edges = (PP and PP.GetBorders(holder)) or {} }
        function handle.SetColor(_, cr, cg, cb, ca)
            if PP then
                PP.SetBorderColor(holder, cr, cg, cb, ca or 1)
            end
        end
        function handle.SetSize(_, px)
            if PP then
                PP.SetBorderSize(holder, px)
            end
        end
        function handle.SetShown(_, shown)
            if PP then
                if shown then
                    PP.ShowBorder(holder)
                else
                    PP.HideBorder(holder)
                end
            end
        end
        return handle
    end

    local _previewPipCount = 3 -- randomised on each visit
    local _previewBarFillPct = 65 -- randomised on each visit (30-80)
    local _headerBaseH = 0 -- the preview's height without the hint line (each build sets it)

    -- Power and Health previews have the live bar's shape (an outer frame
    -- with border and text over a StatusBar with fill and background), are
    -- built through the options pool and styled from the settings the live
    -- build reads. Always horizontal: the stack shows size and look, not
    -- placement or orientation.
    local PreviewBar = {}
    function PreviewBar.Build(hostFrame)
        local bar = CreateFrame("Frame", nil, hostFrame)
        local fill = CreateFrame("StatusBar", nil, bar)
        fill:SetAllPoints()
        fill:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        fill:SetMinMaxValues(0, 100)
        bar._sb = fill
        -- ns.ERB_SeatBlizzMask reads the fill through the host, as on a live bar.
        bar.GetStatusBarTexture = function()
            return fill:GetStatusBarTexture()
        end
        local backdrop = fill:CreateTexture(nil, "BACKGROUND")
        UnsnapTex(backdrop)
        bar._bg = backdrop
        bar._border = { _frame = CreateFrame("Frame", nil, bar) }
        -- Hash lines sit above the fill, as the live tick overlay does.
        local ticks = CreateFrame("Frame", nil, bar)
        ticks:SetAllPoints(fill)
        ticks:SetFrameLevel(fill:GetFrameLevel() + 1)
        bar._tickHost, bar._ticks = ticks, {}
        local textLayer = CreateFrame("Frame", nil, bar)
        textLayer:SetAllPoints(bar)
        textLayer:SetFrameLevel(bar:GetFrameLevel() + 10)
        bar._text = textLayer:CreateFontString(nil, "OVERLAY")
        return bar
    end

    -- A preview whose bar is off: dimmed like greyed controls, with its click
    -- overlays (hits, optional) hidden so nothing leads to those rows.
    function PreviewBar.Lock(widget, on, hits)
        widget:SetAlpha(on and 1 or 0.3)
        for _, hit in ipairs(hits or {}) do
            hit:SetShown(on)
        end
    end

    -- The click hint of the preview on screen: only while there is something
    -- to click, and only once it sits on this preview's header.
    function PreviewBar.HintFor(on, heading)
        -- A dismissed hint is left to its fade (DismissPreviewHint).
        if not _previewHintFS or IsPreviewHintDismissed() then
            return
        end
        local holder = _previewHintFS:GetParent()
        _previewHintFS:SetShown(on and holder and holder:GetParent() == heading or false)
    end

    -- Sizes the header for the preview (baseH) plus the hint, only when that
    -- changes by a physical pixel or more (the header snaps to pixels). Quiet,
    -- so the page moves down instead of scrolling under the header.
    function PreviewBar.SizeHeader(heading, baseH)
        _headerBaseH = baseH -- what the hint's dismiss fade sizes to
        local wanted = baseH + ((_previewHintFS and _previewHintFS:IsShown()) and 35 or 0)
        local scale = heading:GetEffectiveScale()
        local px = scale > 0 and (CludesUI.PP.perfect / scale) or 1
        if math.abs(heading:GetHeight() - wanted) >= px * 0.5 then
            CludesUI:SetContentHeaderHeightSilent(wanted)
        end
    end

    -- nil while a bar can show in the preview, else why not (the eye icon's
    -- tooltip, in the usual "This option requires X" form).
    local NEEDS_SPEC = {
        classResource = "This option needs a specialization with a class resource",
        power = "This option needs a specialization with a power bar",
    }
    function PreviewBar.Avail(p, key)
        local sp = p.secondary
        if key == "classResource" then
            if not sp.enabled then
                return CludesUI.DisabledTooltip("Class Resource")
            end
            if not HasClassResource() then
                return CludesUI.L(NEEDS_SPEC.classResource)
            end
        elseif key == "power" then
            if p.primary.enabled == false then
                return CludesUI.DisabledTooltip("Power Bar")
            end
            if not HasPrimaryPower() then
                return CludesUI.L(NEEDS_SPEC.power)
            end
            -- The druid per-form switch, as the live IsPowerBarHidden.
            if _G._CURB_BarHiddenByForm and _G._CURB_BarHiddenByForm(p.primary) then
                return CludesUI.L("This option is turned off for the current form")
            end
            -- Power hides while the class resource takes its place, as live.
            if sp.hidePowerIfResource and sp.enabled ~= false and HasClassResource() then
                return CludesUI.DisabledTooltip("Hide Power Bar if Resource", "disabled")
            end
        elseif key == "health" then
            if not p.health.enabled then
                return CludesUI.DisabledTooltip("Health Bar")
            end
        elseif key == "arcaneSoul" then
            if not (p.arcaneSoul and p.arcaneSoul.enabled) then
                return CludesUI.DisabledTooltip("Arcane Soul Helper")
            end
        end
        return nil
    end

    -- PreviewBar.Style, step by step. kind is "power" or "health"; c is
    -- p.primary or p.health.

    -- The border: Blizzard's bar chrome under the stock style, else ours
    -- (Extend Top / Bottom are power bar only, as live).
    local function StyleBorder(bar, c, isHealth, wid, hgt)
        local holder = bar._border._frame
        if mod.ERB_BarsBlizz() then
            holder:Hide()
            mod.ERB_ApplyBlizzBarChrome(bar, bar._sb, wid, hgt, false, mod.ERB_BarFrameK(c))
            return
        end
        local level = bar:GetFrameLevel()
        holder:SetFrameLevel(c.borderBehind and math.max(0, level - 1) or (level + 1))
        if isHealth then
            mod.ERB_AnchorBorderHost(holder, bar)
        else
            mod.ERB_AnchorBorderHost(holder, bar, mod.ERB_BorderExtents(c))
        end
        local size, style = c.borderSize or 0, c.borderTexture or "solid"
        CludesUI.ApplyBorderStyle(
            holder,
            size,
            c.borderR or 0,
            c.borderG or 0,
            c.borderB or 0,
            c.borderA or 1,
            style,
            c.borderTextureOffset,
            c.borderTextureOffsetY,
            c.borderTextureShiftX,
            c.borderTextureShiftY,
            "resourcebars",
            size,
            nil,
            CludesUI.BorderPx(c.borderSizePx, size, style)
        )
        holder:Show()
    end

    -- The base fill colour: custom, else class colour (health) or the power
    -- type's colour (power). Also returns that type colour (text uses it).
    local function BaseFill(c, isHealth, ptype)
        local typeColour
        if isHealth then
            local _, class = UnitClass("player")
            typeColour = CLASS_COLORS[class]
        else
            typeColour = ptype and _G._CURB_PowerColors and _G._CURB_PowerColors[ptype]
        end
        if c.customColored then
            return c.fillR, c.fillG, c.fillB, typeColour
        elseif typeColour then
            return typeColour[1], typeColour[2], typeColour[3], typeColour
        elseif isHealth then
            return 0.15, 0.75, 0.30, typeColour
        end
        return 1, 1, 1, typeColour
    end

    -- The threshold or band colour in force at pct (nil = the base colour),
    -- from the per-spec entry the live update resolves, against maxValue.
    -- Also returns the threshold entry (its Text Instead flag matters).
    local function AlertColour(c, isHealth, pct, maxValue)
        local spec = _G._CURB_ResolveThresholdSpecEntry and _G._CURB_ResolveThresholdSpecEntry(c) or nil
        local bandsOn, bands, bandMode, reversed
        if _G._CURB_ResolveBandConfig then
            bandsOn, bands, bandMode, reversed = _G._CURB_ResolveBandConfig(c, spec)
        end
        local th = (spec and spec.thresholdEnabled ~= false) and spec or nil
        if bandsOn and _G._CURB_FindCountBand then
            local at = bandMode == "value" and (maxValue * pct / 100) or pct
            local band = _G._CURB_FindCountBand(bands, at, reversed)
            if band then
                return spec, th, band.r or 1, band.g or 1, band.b or 1, band.a or 1
            end
        elseif th then
            -- Health colours at or below the threshold; power above it, or
            -- below it with Partial Only.
            local below = isHealth
            if not isHealth then
                below = th.thresholdPartialOnly
                if below == nil then
                    below = c.thresholdPartialOnly
                end
            end
            local limit = th.thresholdPct or c.thresholdPct or 30
            if (below and pct <= limit) or (not below and pct > limit) then
                return spec,
                    th,
                    th.thresholdR or c.thresholdR or 1,
                    th.thresholdG or c.thresholdG or 0.2,
                    th.thresholdB or c.thresholdB or 0.2,
                    1
            end
        end
        return spec, th
    end

    -- The background, with the bar texture behind it when "Bar Texture on
    -- Background" is on (and the fill is opaque).
    local function StyleBackground(bar, g, c, texKey)
        local backdrop = bar._bg
        backdrop:SetColorTexture(c.bgR or 0, c.bgG or 0, c.bgB or 0, c.bgA or 0.75)
        UnsnapTex(backdrop)
        if g.barTextureBg or backdrop._erbBgTex then
            local tex = g.barTextureBg
                and (c.fillOpacity or 100) >= 100
                and CludesUI.ResolveTexturePath(_G._CURB_BarTextures, texKey, nil)
            mod.ERB_BgTexture(backdrop, tex, c.bgR, c.bgG, c.bgB, c.bgA)
        end
        return backdrop
    end

    -- Hash lines: the spec entry's own, else the bar's (ns.ApplyHashLines'
    -- rule), inside the border, in physical pixels as live.
    local function StyleHashLines(bar, c, spec, wid, hgt, maxValue)
        local ticks = bar._ticks
        for i = 1, #ticks do
            ticks[i]:Hide()
        end
        local src = (spec and spec.hashValues and spec.hashValues ~= "") and spec
            or (c.hashEnabled and c)
            or nil
        if not src then
            return
        end
        local percent = (src.hashMode or "percent") == "percent"
        local PP = CludesUI.PP
        local lineW = (src.hashWidth or 1) * PP.mult
        -- A solid border's exact size is the inset.
        local inset = c.borderSize or 0
        local style = c.borderTexture
        if not style or style == "" or style == "solid" then
            inset = CludesUI.BorderPx(c.borderSizePx, inset, style) or inset
        end
        inset = math.min(inset * PP.mult, math.max(0, (hgt - 1) / 2))
        local n = 0
        for part in (src.hashValues or ""):gmatch("[^,]+") do
            local v = tonumber(part:match("^%s*(.-)%s*$"))
            local frac = v and v > 0 and v / (percent and 100 or maxValue)
            if frac and frac <= 1 then
                n = n + 1
                local tick = ticks[n]
                if not tick then
                    tick = bar._tickHost:CreateTexture(nil, "OVERLAY", nil, 7)
                    UnsnapTex(tick)
                    ticks[n] = tick
                end
                tick:SetColorTexture(
                    src.hashColorR or 1,
                    src.hashColorG or 1,
                    src.hashColorB or 1,
                    src.hashColorA or 0.7
                )
                tick:ClearAllPoints()
                tick:SetSize(lineW, hgt - inset * 2)
                tick:SetPoint(
                    "TOPLEFT",
                    bar._sb,
                    "TOPLEFT",
                    math.min(PP.Scale(wid * frac), wid - lineW),
                    -inset
                )
                tick:Show()
            end
        end
    end

    -- The bar's text in the live formats, from the made-up values.
    local HEALTH_TEXT = {
        both = function(cur, pct)
            return cur .. " | " .. pct .. "%"
        end,
        curhpshort = function(cur)
            return cur
        end,
        curmaxhp = function(cur, _, maxValue)
            return cur .. " / " .. mod.AbbreviateValue(maxValue, "maxHealth")
        end,
        perhpnosign = function(_, pct)
            return pct
        end,
        perhpnum = function(cur, pct)
            return pct .. "% | " .. cur
        end,
    }
    local function BarText(c, isHealth, fmt, pct, maxValue, ptype)
        local amount = math.floor(maxValue * pct / 100)
        if isHealth then
            local cur, pctText = mod.AbbreviateValue(amount, "health"), tostring(pct)
            local make = HEALTH_TEXT[fmt]
            return make and make(cur, pctText, maxValue) or (pctText .. "%")
        end
        local pctText = tostring(pct) .. ((c.showPercent == false) and "" or "%")
        local cur = mod.AbbreviateNumbers(amount)
        if fmt == "smart" then
            local asPercent = CludesUI.IsSmartPowerPercent and CludesUI.IsSmartPowerPercent(ptype)
            return asPercent and pctText or cur
        elseif fmt == "both" then
            return cur .. " | " .. pctText
        elseif fmt == "curmaxpp" then
            return cur .. " / " .. mod.AbbreviateNumbers(maxValue)
        elseif fmt == "perpp" then
            return pctText
        end
        return cur -- curpp, and anything else
    end

    function PreviewBar.Style(bar, p, c, kind)
        local g = p.general
        local isHealth = kind == "health"
        local wid = _previewSnap(c.width or 214)
        local hgt = _previewSnap(c.height or (isHealth and 16 or 14))
        bar:SetSize(wid, hgt)
        StyleBorder(bar, c, isHealth, wid, hgt)

        -- The bar's own texture counts only while splitTex is on, as live.
        local texKey = (p.splitTex == true and c.barTexture) or g.barTexture
        local fill = bar._sb
        fill:SetStatusBarTexture(
            CludesUI.ResolveTexturePath(
                _G._CURB_BarTextures,
                texKey or "none",
                "Interface\\Buttons\\WHITE8x8"
            )
        )
        if bar._blizzBarMask then
            mod.ERB_SeatBlizzMask(bar)
        end
        local fillTex = fill:GetStatusBarTexture()
        UnsnapTex(fillTex)

        local ptype = (not isHealth) and _G._CURB_GetPrimaryPowerType and _G._CURB_GetPrimaryPowerType()
        local fR, fG, fB, typeColour = BaseFill(c, isHealth, ptype)

        -- The player's real maximum (value-mode bands and hash lines); 500K
        -- health / 100 power when it reads secret or 0.
        local maxValue = isHealth and UnitHealthMax("player") or (ptype and UnitPowerMax("player", ptype))
        if not maxValue or (issecretvalue and issecretvalue(maxValue)) or maxValue <= 0 then
            maxValue = isHealth and 500000 or 100
        end
        -- The made-up fill; a threshold or band colours it when reached, as live.
        local pct = isHealth and (100 - math.floor(_previewBarFillPct / 3)) or _previewBarFillPct
        local spec, th, aR, aG, aB, aA = AlertColour(c, isHealth, pct, maxValue)
        local fmt = c.textFormat or "none"
        local textInstead = th and th.thresholdTextInstead and fmt ~= "none"

        -- Plain texture calls, not the live change-gated helpers: their memo
        -- would outlive a pool reset of this texture.
        if aR and not textInstead then
            fillTex:SetVertexColor(aR, aG, aB, aA)
        elseif c.gradientEnabled then
            fillTex:SetVertexColor(1, 1, 1, 1)
            fillTex:SetGradient(
                c.gradientDir or "HORIZONTAL",
                CreateColor(fR, fG, fB, 1),
                CreateColor(c.gradientR or 1, c.gradientG or 1, c.gradientB or 1, c.gradientA or 1)
            )
        else
            fillTex:SetVertexColor(fR, fG, fB, 1)
        end

        local backdrop = StyleBackground(bar, g, c, texKey)
        fill:SetValue(pct)
        -- Fill Opacity: a see-through fill with the background over the empty
        -- part only (as the class resource preview).
        local opacity = (c.fillOpacity or 100) / 100
        fillTex:SetAlpha(opacity)
        backdrop:ClearAllPoints()
        if opacity < 1 then
            backdrop:SetPoint("TOPLEFT", fillTex, "TOPRIGHT", 0, 0)
            backdrop:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, 0)
        else
            backdrop:SetAllPoints(fill)
        end

        StyleHashLines(bar, c, spec, wid, hgt, maxValue)
        mod.ERB_RoundBar(bar, c)

        local label = bar._text
        if fmt == "none" then
            label:Hide()
            return
        end
        SetPVFont(label, FONT_PATH, c.textSize or 11)
        label:ClearAllPoints()
        local anchor = c.textAnchor or "CENTER"
        label:SetPoint(anchor, bar, anchor, c.textXOffset or 0, c.textYOffset or 0)
        if aR and textInstead then
            label:SetTextColor(aR, aG, aB, aA)
        elseif c.textCustomColored == false and typeColour then
            label:SetTextColor(typeColour[1], typeColour[2], typeColour[3], 1)
        elseif c.textCustomColored == false then
            label:SetTextColor(1, 1, 1, 1)
        else
            label:SetTextColor(c.textFillR or 1, c.textFillG or 1, c.textFillB or 1, c.textFillA or 1)
        end
        label:SetText(BarText(c, isHealth, fmt, pct, maxValue, ptype))
        label:Show()
    end

    -- The pip count for the current spec: the resource's real maximum (Fury
    -- Whirlwind 4, Arms Sweeping Strikes 18, DK runes 6, Maelstrom Weapon
    -- 5/10, ...) so the preview matches the live bar; 5 when there is none.
    local function PreviewPipCount()
        local get = _G._CURB_GetSecondaryResource
        local info = get and get()
        if not info or info.type == "bar" then
            return 5
        end
        local most = info.max
        -- Talent-dependent maximums come from their live sources.
        if info.power == "SWEEPING_STRIKES" or info.power == "WHIRLWIND_STACKS" then
            local real = _G._EWC and _G._EWC.MaxApps(info.power)
            if real and real > 0 then
                most = real
            end
        elseif info.power == "MAELSTROM_WEAPON" and CludesUI and CludesUI.GetMaelstromWeapon then
            local _, real = CludesUI.GetMaelstromWeapon()
            if real and real > 0 then
                most = real
            end
        end
        if type(most) == "number" and most >= 2 and most <= 20 then
            return most
        end
        return 5
    end

    ---------------------------------------------------------------------------
    --  The bars preview, step by step (UpdatePreviewHeader puts them together)
    ---------------------------------------------------------------------------
    local WHITE = "Interface\\Buttons\\WHITE8x8"

    local UpdatePreviewHeader -- defined at the end of this section (the Arcane Soul retry calls it)

    -- The class resource's fill colour: dark mode, the per-spec resource
    -- colour (else the class colour), the class colour, or custom.
    local function ResourceColour(sp, classColour)
        local function Class()
            return classColour and classColour[1] or 0.95,
                classColour and classColour[2] or 0.90,
                classColour and classColour[3] or 0.60
        end
        if sp.darkTheme then
            return CludesUI.GetDarkModeFill()
        elseif sp.resourceColored then
            local get, resolve = _G._CURB_GetSecondaryResource, _G._CURB_ResolveSecondaryResourceColor
            local info = get and resolve and get()
            if info and info.power ~= nil then
                local r, g, b = resolve(info.power)
                if r then
                    return r, g, b
                end
            end
            return Class()
        elseif sp.classColored ~= false then
            return Class()
        end
        return sp.fillR, sp.fillG, sp.fillB -- classColored false: custom
    end

    -- A resource background colour: dark mode, a darker class tint (dim =
    -- 0.3 for the bar type, 0.5 for pips), or the custom background.
    local function ResourceBg(sp, r, g, b, dim)
        if sp.darkTheme then
            local dr, dg, db = CludesUI.GetDarkModeBg()
            return dr, dg, db, 1
        elseif sp.classColored then
            return r * dim, g * dim, b * dim, 0.5
        end
        return sp.bgR, sp.bgG, sp.bgB, sp.bgA
    end

    -- The bar texture behind a background (Textured Background), as live.
    local function TexturedBg(tex, p, sp, allowed, r, g, b, a)
        if not (p.general.barTextureBg or tex._erbBgTex) then
            return
        end
        local path = p.general.barTextureBg
            and allowed
            and (sp.fillOpacity or 100) >= 100
            and CludesUI.ResolveTexturePath(_G._CURB_BarTextures, p.general.barTexture, nil)
        mod.ERB_BgTexture(tex, path, r, g, b, a)
    end

    local function FillPath(p)
        local textures = _G._CURB_BarTextures or {}
        return textures[p.general.barTexture or "none"] or WHITE
    end

    -- The resource's own separators on its bottom edge (and between pips:
    -- slots), only on a textured style and not under a stock style.
    local function SeparatorsOn(sp)
        return sp.edgeSep and mod.ERB_Textured(sp) and not CludesUI.BlizzStyle.Get("resourcebars")
    end

    -- A bar-type class resource: one fill over one background, with hash lines.
    local function StyleResourceBar(pc, p, sp, height, r, g, b)
        local width = p.primary.width or 214
        pc:SetSize(width, height)
        local bg = pc._barBg
        if bg then
            bg:SetColorTexture(ResourceBg(sp, r, g, b, 0.3))
            UnsnapTex(bg)
            TexturedBg(bg, p, sp, true, ResourceBg(sp, r, g, b, 0.3))
        end
        local fill = pc._barFill
        if fill then
            fill:SetWidth(width * _previewBarFillPct / 100)
            fill:SetHeight(height)
            fill:SetTexture(FillPath(p))
            fill:SetVertexColor(r, g, b, 1)
            UnsnapTex(fill)
            fill:Show()
            -- Fill Opacity: a see-through fill and the background over the
            -- empty part only, as the live bar.
            local opacity = (sp.fillOpacity or 100) / 100
            fill:SetAlpha(opacity)
            if bg then
                bg:ClearAllPoints()
                if opacity < 1 then
                    bg:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, 0)
                    bg:SetPoint("BOTTOMRIGHT", pc, "BOTTOMRIGHT", 0, 0)
                else
                    bg:SetAllPoints(pc)
                end
            end
        end

        -- Hash lines: the threshold entry's, else the older tickValues; at
        -- the resource's real maximum (or percent).
        pc._previewTicks = pc._previewTicks or {}
        local ticks = pc._previewTicks
        for i = 1, #ticks do
            ticks[i]:Hide()
        end
        local entry = _G._CURB_ResolveThresholdSpecEntry and _G._CURB_ResolveThresholdSpecEntry(sp) or nil
        local list = (entry and entry.hashValues ~= "") and entry.hashValues or (sp.tickValues or "")
        local values = {}
        for part in list:gmatch("[^,]+") do
            local v = tonumber(part:match("^%s*(.-)%s*$"))
            if v and v > 0 then
                values[#values + 1] = v
            end
        end
        local get = _G._CURB_GetSecondaryResource
        local info = get and get()
        local most = (info and info.max) or 100
        local percent = entry and entry.hashMode == "percent"
        local PP = CludesUI and CludesUI.PP
        local onePx = PP and PP.Scale(1) or 1
        for i, v in ipairs(values) do
            local limit = percent and 100 or most
            if v <= limit then
                local tick = ticks[i]
                if not tick then
                    tick = pc:CreateTexture(nil, "OVERLAY", nil, 7)
                    tick:SetColorTexture(1, 1, 1, 1)
                    tick:SetSnapToPixelGrid(false)
                    tick:SetTexelSnappingBias(0)
                    ticks[i] = tick
                end
                local x = width * v / limit
                tick:ClearAllPoints()
                tick:SetSize(onePx, height)
                tick:SetPoint("TOPLEFT", pc, "TOPLEFT", PP and PP.Scale(x) or x, 0)
                tick:Show()
            end
        end

        -- A bar type has no gaps: only the bottom-edge separator, as live.
        local sepOn = SeparatorsOn(sp)
        mod.ERB_Separators(pc, sp, (sepOn and sp.edgeSepH ~= false) and true or false, pc:GetFrameLevel() + 5)
        -- ... and no pips: hide pips and gap fills from an earlier build.
        for _, pip in ipairs(_previewFrames.pips) do
            pip:Hide()
        end
        for _, gap in ipairs(pc._gapFills or {}) do
            gap:Hide()
        end
    end

    -- The pips' x and width, pixel-exact like the live bar (CalcPipGeometry,
    -- or the same arithmetic while that is not loaded yet).
    local function PipGeometry(pc, sp, count)
        local scale = pc:GetEffectiveScale()
        if scale <= 0 then
            scale = 1
        end
        local onePx = CludesUI.PP.perfect / scale -- one physical pixel in this frame's units
        local function Snap(v)
            return math.floor(v / onePx + 0.5) * onePx
        end
        local width, height = Snap(sp.pipWidth), Snap(sp.pipHeight)
        local calc = _G._CURB_CalcPipGeometry
        local slots = calc and calc(width, count, sp.pipSpacing or 1, pc)
        local xs, ws = {}, {}
        if slots then
            for i = 1, count do
                xs[i], ws[i] = slots[i].x0, slots[i].x1 - slots[i].x0
            end
        else
            local spacing = (sp.pipSpacing > 0) and math.max(onePx, Snap(sp.pipSpacing)) or 0
            local room = width - (count - 1) * spacing
            local base = math.floor(room / onePx / count) * onePx
            local wider = math.floor((room - base * count) / onePx + 0.5)
            local x = 0
            for i = 1, count do
                xs[i] = x
                ws[i] = base + (i <= wider and onePx or 0)
                x = x + ws[i] + spacing
            end
        end
        return width, height, xs, ws, slots
    end

    -- How the made-up fill meets the threshold or bands, as the live pips
    -- resolve them (Update.lua): "From" (>=) or "Up to" (<=, reverse),
    -- Partial Only ("From" only), bands, and Recolor Text Instead.
    local function PipAlert(sp, count)
        local entry = _G._CURB_ResolveThresholdSpecEntry and _G._CURB_ResolveThresholdSpecEntry(sp) or nil
        local find = _G._CURB_FindCountBand
        local bandsOn, bands, reversedBands
        if _G._CURB_ResolveBandConfig and find then
            local on, list, _, rev = _G._CURB_ResolveBandConfig(sp, entry)
            bandsOn, bands, reversedBands = on, list, rev
        end
        local enabled = entry and (entry.thresholdEnabled ~= false) or false
        local at = entry and entry.thresholdCount or sp.thresholdCount or 3
        -- Enhance Five Bar needs at least 7 (5 pips + overflow), as live.
        if enabled and sp.enhanceFiveBar and at < 7 then
            local info = _G._CURB_GetSecondaryResource and _G._CURB_GetSecondaryResource()
            if info and info.power == "MAELSTROM_WEAPON" then
                at = 7
            end
        end
        local function Pick(field)
            local v = entry and entry[field]
            if v == nil then
                v = sp[field]
            end
            return v
        end
        local partial, reverse = Pick("thresholdPartialOnly"), Pick("thresholdReverse")
        if reverse then
            partial = false
        end
        -- The random fill against a 5-pip preview, rescaled to this count (18
        -- Sweeping Strikes and so on).
        local filled = _previewPipCount
        if count ~= 5 then
            filled = math.max(1, math.min(count, math.floor(_previewPipCount / 5 * count + 0.5)))
        end
        local r = entry and entry.thresholdR or sp.thresholdR
        local g = entry and entry.thresholdG or sp.thresholdG
        local b = entry and entry.thresholdB or sp.thresholdB
        local active = enabled and ((reverse and filled <= at) or (not reverse and filled >= at))
        if bandsOn then
            local band = find(bands, filled, reversedBands)
            active = band ~= nil
            if band then
                r, g, b = band.r or 1, band.g or 1, band.b or 1
            end
        end
        -- Recolor Text Instead: the count text takes the colour, pips stay base.
        local textColour
        if entry and entry.thresholdTextInstead and sp.showText then
            if active then
                textColour = { r, g, b }
            end
            active = false
        end
        return {
            filled = filled,
            active = active,
            r = r,
            g = g,
            b = b,
            bands = bandsOn,
            partial = partial,
            at = at,
            textColour = textColour,
        }
    end

    local RUNE_SECONDS = { 2, 4, 6, 7, 9, 10 } -- made-up rune cooldowns, longer to the right

    -- One pip: place, background, fill, border, colour and (DK) its rune timer.
    local function StylePip(i, pip, pc, p, sp, geo, alert, r, g, b, pipBg, isDK)
        pip:SetSize(geo.ws[i], geo.height)
        pip:ClearAllPoints()
        pip:SetPoint("LEFT", pc, "LEFT", geo.xs[i], 0)

        if pipBg then
            pip._bg:SetColorTexture(mod.ERB.PipBgColor(sp, true))
        else
            pip._bg:SetColorTexture(ResourceBg(sp, r, g, b, 0.5))
        end
        UnsnapTex(pip._bg)
        TexturedBg(pip._bg, p, sp, not pipBg, ResourceBg(sp, r, g, b, 0.5))

        local fill = pip._fill
        fill:SetTexture(FillPath(p))
        if sp.useContinuousTexture and geo.width > 0 then
            fill:SetTexCoord(geo.xs[i] / geo.width, (geo.xs[i] + geo.ws[i]) / geo.width, 0, 1)
            pip._continuousPreview = true
        elseif pip._continuousPreview then
            fill:SetTexCoord(0, 1, 0, 1)
            pip._continuousPreview = nil
        end
        UnsnapTex(fill)

        if pip._border then
            pip._border:SetShown(false)
        end
        if sp.borderOnPips then
            if not pip._borderFrame then
                local holder = CreateFrame("Frame", nil, pip)
                holder:SetAllPoints(pip)
                pip._borderFrame = holder
            end
            local level = pip:GetFrameLevel()
            pip._borderFrame:SetFrameLevel(sp.borderBehind and math.max(0, level - 1) or (level + 2))
            local size, style = sp.borderSize or 1, sp.borderTexture or "solid"
            CludesUI.ApplyBorderStyle(
                pip._borderFrame,
                size,
                sp.borderR or 0,
                sp.borderG or 0,
                sp.borderB or 0,
                sp.borderA or 1,
                style,
                sp.borderTextureOffset,
                sp.borderTextureOffsetY,
                sp.borderTextureShiftX,
                sp.borderTextureShiftY,
                "resourcebars",
                size,
                nil,
                CludesUI.BorderPx(sp.borderSizePx, size, style)
            )
            pip._borderFrame:Show()
        elseif pip._borderFrame then
            pip._borderFrame:Hide()
        end

        local lit = i <= alert.filled
        if lit then
            -- Partial Only keeps the pips below the threshold at the base colour.
            if alert.active and not (not alert.bands and alert.partial and i < alert.at) then
                fill:SetVertexColor(alert.r, alert.g, alert.b, 1)
            else
                fill:SetVertexColor(r, g, b, 1)
            end
            fill:Show()
        else
            fill:Hide()
        end
        -- Fill Opacity: lit pips drop their background so the see-through
        -- fill shows what is behind (as live).
        local opacity = (sp.fillOpacity or 100) / 100
        fill:SetAlpha(opacity)
        pip._bg:SetAlpha((lit and (opacity < 1 or pipBg)) and 0 or 1)

        if isDK and sp.showText then
            if not pip._pvCdText then
                local layer = CreateFrame("Frame", nil, pip)
                layer:SetAllPoints(pip)
                layer:SetFrameLevel(pip:GetFrameLevel() + 3)
                local text = layer:CreateFontString(nil, "OVERLAY")
                text:SetTextColor(1, 1, 1, 0.9)
                pip._pvCdText = text
            end
            local text = pip._pvCdText
            SetPVFont(text, FONT_PATH, sp.textSize)
            text:ClearAllPoints()
            text:SetPoint("CENTER", pip, "CENTER", sp.textXOffset or 0, sp.textYOffset or 0)
            if lit then
                text:SetText("")
                text:Hide()
            else
                text:SetText(tostring(RUNE_SECONDS[i] or ""))
                text:Show()
            end
        elseif pip._pvCdText then
            pip._pvCdText:Hide()
        end
        pip:Show()
    end

    -- The optional colour in the gaps between pips (as live).
    local function GapFills(pc, sp, count, xs, ws)
        pc._gapFills = pc._gapFills or {}
        local fills = pc._gapFills
        local n = 0
        if sp.gapColorEnabled and count > 1 then
            for i = 1, count - 1 do
                local x = xs[i] + ws[i]
                local w = xs[i + 1] - x
                if w and w > 0 then
                    n = n + 1
                    local tex = fills[n]
                    if not tex then
                        tex = pc:CreateTexture(nil, "BACKGROUND", nil, 0)
                        UnsnapTex(tex)
                        fills[n] = tex
                    end
                    tex:SetColorTexture(sp.gapR or 0, sp.gapG or 0, sp.gapB or 0, sp.gapA or 1)
                    tex:ClearAllPoints()
                    tex:SetPoint("TOPLEFT", pc, "TOPLEFT", x, 0)
                    tex:SetPoint("BOTTOMLEFT", pc, "BOTTOMLEFT", x, 0)
                    tex:SetWidth(w)
                    tex:Show()
                end
            end
        end
        for i = n + 1, #fills do
            fills[i]:Hide()
        end
    end

    -- A pip-type class resource (always horizontal in the preview).
    local function StylePips(pc, p, sp, r, g, b, isDK)
        local count = PreviewPipCount()
        local width, height, xs, ws, slots = PipGeometry(pc, sp, count)
        pc:SetSize(width, height)
        local alert = PipAlert(sp, count)
        pc._pvShownCount = alert.filled -- the count text matches the lit pips
        pc._pvTextCol = alert.textColour
        local pipBg = mod.ERB_PipBgOn(sp, false) -- Background on individual pips, as live

        -- More pips than built so far (counts run 3-18): bare background and
        -- fill frames, which StylePip dresses.
        local pips = _previewFrames.pips
        for i = #pips + 1, count do
            local pip = CreateFrame("Frame", nil, pc)
            pip._bg = pip:CreateTexture(nil, "BACKGROUND")
            pip._bg:SetAllPoints()
            pip._fill = pip:CreateTexture(nil, "ARTWORK")
            pip._fill:SetAllPoints()
            pips[i] = pip
        end
        local geo = { width = width, height = height, xs = xs, ws = ws }
        for i = 1, math.min(count, #pips) do
            StylePip(i, pips[i], pc, p, sp, geo, alert, r, g, b, pipBg, isDK)
        end
        for i = count + 1, #pips do
            pips[i]:Hide()
        end
        GapFills(pc, sp, count, xs, ws)

        -- The bottom-edge separator and one per gap, as live.
        local sepOn = SeparatorsOn(sp)
        mod.ERB_Separators(
            pc,
            sp,
            (sepOn and sp.edgeSepH ~= false) and true or false,
            pc:GetFrameLevel() + 5,
            (sepOn and sp.edgeSepV ~= false) and slots or nil,
            count,
            false,
            false
        )
        -- Hide a bar type's fill and hash lines from an earlier build.
        if pc._barFill then
            pc._barFill:Hide()
        end
        for _, tick in ipairs(pc._previewTicks or {}) do
            tick:Hide()
        end
    end

    -- Blizzard Style kit on the preview row: the stock background art, its
    -- bar-shape mask on fill and background, and the inner bevel (on the
    -- container for a bar type, on an overlay above the pips otherwise, with
    -- the pips masked so the end pips round off with the frame).
    local function BlizzKit(pc, isBar)
        local art = pc._blizzBarBg
        if not art then
            art = pc:CreateTexture(nil, "BACKGROUND", nil, -2)
            if C_Texture.GetAtlasInfo("UI-HUD-CoolDownManager-Bar-BG") then
                art:SetAtlas("UI-HUD-CoolDownManager-Bar-BG")
            end
            UnsnapTex(art)
            pc._blizzBarBg = art
        end
        art:ClearAllPoints()
        art:SetPoint("TOPLEFT", pc, "TOPLEFT", -2, 3)
        art:SetPoint("BOTTOMRIGHT", pc, "BOTTOMRIGHT", 6, -7)
        art:Show()
        local mask = pc._blizzBarMask
        if not mask and C_Texture.GetAtlasInfo("UI-HUD-CoolDownManager-Bar") then
            mask = pc:CreateMaskTexture()
            mask:SetAtlas("UI-HUD-CoolDownManager-Bar")
            mask:SetAllPoints(pc)
            pc._blizzBarMask = mask
        end
        if pc._barFill and pc._blizzMaskedFill ~= pc._barFill then
            pc._barFill:AddMaskTexture(mask)
            pc._blizzMaskedFill = pc._barFill
        end
        if pc._barBg and pc._blizzMaskedBg ~= pc._barBg then
            pc._barBg:AddMaskTexture(mask)
            pc._blizzMaskedBg = pc._barBg
        end
        local shade = pc._blizzShadeFrame
        if isBar then
            mod.ERB_BlizzBarShadow(pc, mask)
            if shade then
                shade:Hide()
            end
            return
        end
        if pc._blizzShadow then
            for i = 1, 4 do
                pc._blizzShadow[i]:Hide()
            end
        end
        if not shade then
            shade = CreateFrame("Frame", nil, pc)
            shade:SetAllPoints(pc)
            pc._blizzShadeFrame = shade
        end
        shade:SetFrameLevel(pc:GetFrameLevel() + 8)
        shade:Show()
        mod.ERB_BlizzBarShadow(shade, mask)
        for _, pip in ipairs(_previewFrames.pips or {}) do
            mod.ERB_MaskTex(pip._bg, mask)
            mod.ERB_MaskTex(pip._fill, mask)
        end
    end

    -- The whole-row border: the stock frame under a stock style, none when
    -- the border sits on each pip, else ours (with Extend Top / Bottom).
    local function ResourceChrome(pc, sp, isBar)
        if not pc._barBorderFrame then
            local holder = CreateFrame("Frame", nil, pc)
            holder:SetAllPoints(pc)
            pc._barBorderFrame = holder
        end
        local holder = pc._barBorderFrame
        local level = pc:GetFrameLevel()
        holder:SetFrameLevel(sp.borderBehind and math.max(0, level - 1) or (level + 2))
        if CludesUI.BlizzStyle.Get("resourcebars") then
            holder:Hide()
            if mod.ERB_BarsClassic() then
                -- Classic WoW UI: the vanilla frame round the row; no mask, no bevel.
                mod.ERB_ApplyClassicBarChrome(pc, nil, nil, nil, nil, mod.ERB_BarFrameK(sp))
            else
                BlizzKit(pc, isBar)
            end
        elseif sp.borderOnPips and not isBar then
            holder:Hide()
        else
            mod.ERB_AnchorBorderHost(holder, pc, mod.ERB_BorderExtents(sp))
            local size, style = sp.borderSize or 1, sp.borderTexture or "solid"
            CludesUI.ApplyBorderStyle(
                holder,
                size,
                sp.borderR or 0,
                sp.borderG or 0,
                sp.borderB or 0,
                sp.borderA or 1,
                style,
                sp.borderTextureOffset,
                sp.borderTextureOffsetY,
                sp.borderTextureShiftX,
                sp.borderTextureShiftY,
                "resourcebars",
                size,
                nil,
                CludesUI.BorderPx(sp.borderSizePx, size, style)
            )
            holder:Show()
        end
    end

    -- Rounded corners, as the live class resource (ns.ERB_RoundSecondary): on
    -- the row, or on each pip when the border sits on the pips.
    local function RoundResource(pc, sp, isBar)
        local radius = (not mod.ERB_BarsBlizz() and sp.cornerRadius) or 0
        local style = sp.borderTexture or "solid"
        local onPips = sp.borderOnPips and not isBar
        if radius > 0 then
            CludesUI.RoundCorners(pc, radius, {
                style = style,
                border = not onPips and pc._barBorderFrame or nil,
                corners = sp.cornerMask,
            })
        else
            CludesUI.RoundCorners(pc, 0)
        end
        local pipRadius = onPips and radius or 0
        for _, pip in ipairs(_previewFrames.pips) do
            if pipRadius > 0 then
                CludesUI.RoundCorners(
                    pip,
                    pipRadius,
                    { style = style, border = pip._borderFrame, corners = sp.cornerMask }
                )
            else
                CludesUI.RoundCorners(pip, 0)
            end
        end
    end

    -- The full-row background behind pips (a bar type uses its own; Background
    -- on individual pips drops it, as live).
    local function PipRowBg(pc, sp, isBar)
        if isBar or mod.ERB_PipBgOn(sp, false) then
            if pc._pipBarBg then
                pc._pipBarBg:Hide()
            end
            return
        end
        if not pc._pipBarBg then
            pc._pipBarBg = pc:CreateTexture(nil, "BACKGROUND", nil, -1)
            UnsnapTex(pc._pipBarBg)
        end
        local bg = pc._pipBarBg
        bg:ClearAllPoints()
        bg:SetAllPoints(pc)
        bg:SetColorTexture(sp.barBgR or 0, sp.barBgG or 0, sp.barBgB or 0, sp.barBgA or 0.5)
        bg:Show()
        if pc._blizzBarMask then
            mod.ERB_MaskTex(bg, pc._blizzBarMask) -- Blizzard Style: the row's bar-shape mask
        end
    end

    -- The count on the row (a DK shows each rune's time on its pip instead):
    -- a percent for a bar type, the bare lit count for pips.
    local function CountText(pc, sp, isBar, isDK)
        local text = pc._countText
        if not (sp.showText and text and not isDK) then
            if text then
                text:Hide()
            end
            return
        end
        SetPVFont(text, FONT_PATH, sp.textSize)
        text:ClearAllPoints()
        local anchor = sp.textAnchor or "CENTER"
        text:SetPoint(anchor, pc, anchor, sp.textXOffset or 0, sp.textYOffset or 0)
        if isBar then
            text:SetText(tostring(_previewBarFillPct) .. ((sp.showPercent == false) and "" or "%"))
        else
            text:SetText(tostring(pc._pvShownCount or _previewPipCount))
        end
        local colour = (not isBar) and pc._pvTextCol
        if colour then
            text:SetTextColor(colour[1], colour[2], colour[3], 1)
        else
            text:SetTextColor(sp.textR or 1, sp.textG or 1, sp.textB or 1, 0.9) -- the live base colour
        end
        text:Show()
    end

    -- The class resource row, whole.
    local function StyleClassResource(pc, p, pvHidden, holder)
        local sp = p.secondary
        local isBar = mod.IsBarTypeSecondary()
        local _, class = UnitClass("player")
        local r, g, b = ResourceColour(sp, CLASS_COLORS[class])
        -- Its place in the stack (_pvY) is set by LayoutStack; scale stays 1.
        SmoothAnimate(pc, "scale", 1.0, function()
            pc:SetScale(pc["_anim_scale"] or 1.0)
            pc:ClearAllPoints()
            pc:SetPoint("CENTER", holder, "CENTER", 0, pc._pvY or 0)
        end)
        local isDK = class == "DEATHKNIGHT"
        if isBar then
            StyleResourceBar(pc, p, sp, sp.pipHeight, r, g, b)
        else
            StylePips(pc, p, sp, r, g, b, isDK)
        end
        ResourceChrome(pc, sp, isBar)
        RoundResource(pc, sp, isBar)
        PipRowBg(pc, sp, isBar)
        CountText(pc, sp, isBar, isDK)
        pc:SetShown(
            (not pvHidden.classResource and not PreviewBar.Avail(p, "classResource")) and true or false
        )
    end

    -- Arcane Soul sample: sized from its static text when the font changed (a
    -- font not loaded yet measures 0: the text size stands in, and it measures
    -- again 0.2s doubling, up to about 6s in all), then back to the replay.
    local function StyleArcaneSoul(frame, style)
        local size, changed = style(frame._fs)
        if changed then
            frame._asTries = 0
        end
        if changed or frame._asEstimated then
            local w, h = frame._fs:GetStringWidth(), frame._fs:GetStringHeight()
            frame._asEstimated = not (w > 0 and h > 0) or nil
            frame:SetSize(math.ceil(w > 0 and w or size * 5), math.ceil(h > 0 and h or size))
            local tries = frame._asTries or 0
            if frame._asEstimated and tries < 5 then
                frame._asTries = tries + 1
                local gen = PoolGen(frame)
                C_Timer.After(0.2 * 2 ^ tries, function()
                    if PoolGen(frame) == gen and frame:IsVisible() then
                        UpdatePreviewHeader()
                    end
                end)
            end
        end
        local tick = _G._CURB_ArcaneSoulDemoTick
        if tick then
            tick(frame)
        end
    end

    -- Stacks the shown bars top to bottom (Class Resource, Power, Health, the
    -- live default order; then Arcane Soul below a divider), each under its
    -- title, centred in the container; then sizes the header.
    local function LayoutStack(holder, rows, titles, showAS)
        local snap = _previewSnap or function(v)
            return v
        end
        local scale = (_previewScale and _previewScale > 0) and _previewScale or 1
        local titleH = (12 + 3) / scale -- a header-scale title line, in the bars' units
        local gap = snap(8)
        local total = 0
        for _, row in ipairs(rows) do
            total = total + titleH + row:GetHeight()
        end
        total = total + gap * math.max(0, #rows - 1)
        -- A one-pixel divider above Arcane Soul, as wide as the widest bar.
        local divider = _previewFrames.asDivider
        local dividerAt = (divider and holder and showAS and #rows > 1) and #rows or nil
        local dividerH, dividerW = 0, 0
        if dividerAt then
            dividerH = 1 / holder:GetEffectiveScale()
            total = total + dividerH + gap
            for i = 1, dividerAt - 1 do
                dividerW = math.max(dividerW, rows[i]:GetWidth())
            end
        end
        if divider then
            divider:SetShown(dividerAt and true or false)
        end
        -- Offsets from the container centre, bar edges on the preview grid.
        local y = snap(total / 2)
        for i, row in ipairs(rows) do
            if i == dividerAt then
                divider:ClearAllPoints()
                divider:SetSize(dividerW, dividerH)
                divider:SetPoint("TOP", holder, "CENTER", 0, y)
                y = snap(y - dividerH - gap)
            end
            local h = row:GetHeight()
            local top = snap(y - titleH)
            row._pvY = top - h / 2
            row:ClearAllPoints()
            row:SetPoint("CENTER", holder, "CENTER", 0, row._pvY)
            local title = titles[i]
            if title then
                title:ClearAllPoints()
                title:SetPoint("BOTTOMLEFT", row, "TOPLEFT", 0, 3)
                title:Show()
            end
            y = top - h - gap
        end

        -- At least 80px; otherwise 20px above and below the stack.
        local height = #rows > 0 and math.max(80, math.ceil((total + 40) * _previewScale)) or 0
        _headerBaseH = height
        if holder then
            holder:SetHeight(math.max(1, height) / _previewScale)
        end
        if _previewHintFS then
            if height == 0 then
                _previewHintFS:Hide()
            elseif
                not _previewBuilding
                and not IsPreviewHintDismissed()
                and not _previewHintFS:IsShown()
                and _previewHintFS:GetParent()
                and _previewHintFS:GetParent():GetParent() == _hintHdr[PAGE_DISPLAY]
            then
                _previewHintFS:Show()
            end
        end
        if not _previewBuilding then
            local hintH = (height > 0 and _previewHintFS and _previewHintFS:IsShown()) and 35 or 0
            CludesUI:UpdateContentHeaderHeight(height + hintH)
        end
    end

    function UpdatePreviewHeader()
        local p = DB()
        if not p then
            return
        end
        -- The section headers' eyes (session only; BarDisplayPage_Options.lua).
        local pvHidden = mod._erbPvHidden or {}
        local holder = _previewFrames.container
        local hasResource = HasClassResource()
        if not hasResource and _previewFrames.pipContainer then
            _previewFrames.pipContainer:Hide()
        end
        local pc = hasResource and _previewFrames.pipContainer
        if pc then
            StyleClassResource(pc, p, pvHidden, holder)
        end

        local pb, hb = _previewFrames.powerBar, _previewFrames.healthBar
        local showPower = pb and not pvHidden.power and not PreviewBar.Avail(p, "power")
        local showHealth = hb and not pvHidden.health and not PreviewBar.Avail(p, "health")
        if showPower then
            PreviewBar.Style(pb, p, p.primary, "power")
        end
        if showHealth then
            PreviewBar.Style(hb, p, p.health, "health")
        end
        if pb then
            pb:SetShown(showPower and true or false)
        end
        if hb then
            hb:SetShown(showHealth and true or false)
        end

        local as = _previewFrames.arcaneSoul
        local styleAS = _G._CURB_StyleArcaneSoulSample
        local showAS = as and styleAS and not pvHidden.arcaneSoul and not PreviewBar.Avail(p, "arcaneSoul")
        if showAS then
            StyleArcaneSoul(as, styleAS)
        end
        if as then
            as:SetShown(showAS and true or false)
        end

        local labels = _previewFrames.labels or {}
        local rows, titles = {}, {}
        local function Add(row, title)
            rows[#rows + 1] = row
            titles[#rows] = title
        end
        if pc and pc:IsShown() then
            Add(pc, labels.classResource)
        end
        if showPower then
            Add(pb, labels.power)
        end
        if showHealth then
            Add(hb, labels.health)
        end
        if showAS then
            Add(as, labels.arcaneSoul)
        end
        for _, title in pairs(labels) do
            title:Hide()
        end
        LayoutStack(holder, rows, titles, showAS)

        -- The section eyes follow (BarDisplayPage_Options.lua).
        for _, refresh in pairs(mod._erbPvEyes or {}) do
            refresh()
        end
    end

    -- Click-to-scroll overlays on the preview (CreateHitOverlay is set below).
    local CreateHitOverlay
    local _hitOverlays = {}

    -- The class resource row's frames: a bar type's background and fill, or
    -- one frame per pip (pipWidth is the whole row, split evenly; leftover
    -- pixels widen pips, never the spacing). UpdatePreviewHeader dresses them.
    local function BuildResourceRow(row, p, sp, class)
        local height = sp.pipHeight
        if mod.IsBarTypeSecondary() then
            -- Bar type (Devourer, Elemental Shaman): a texture clipped by width.
            row:SetSize(p.primary.width or 214, height)
            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            UnsnapTex(bg)
            row._barBg = bg
            local fill = row:CreateTexture(nil, "ARTWORK")
            fill:SetPoint("LEFT")
            fill:SetHeight(height)
            fill:SetTexture(FillPath(p))
            UnsnapTex(fill)
            row._barFill = fill
            return
        end
        local count = PreviewPipCount()
        local width, spacing = sp.pipWidth, sp.pipSpacing
        local base = math.floor((width - (count - 1) * spacing) / count)
        local extra = width - (count - 1) * spacing - base * count
        row:SetSize(width, height)
        local classColour = CLASS_COLORS[class]
        local x = 0
        for i = 1, count do
            local w = base + (i <= extra and 1 or 0)
            local pip = CreateFrame("Frame", nil, row)
            pip:SetSize(w, height)
            pip:SetPoint("LEFT", row, "LEFT", x, 0)
            x = x + w + spacing
            local bg = pip:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            if sp.darkTheme then
                local r, g, b = CludesUI.GetDarkModeBg()
                bg:SetColorTexture(r, g, b, 1)
            elseif sp.classColored then
                local r = classColour and classColour[1] or 0.95
                local g = classColour and classColour[2] or 0.90
                local b = classColour and classColour[3] or 0.60
                bg:SetColorTexture(r * 0.5, g * 0.5, b * 0.5, 0.5)
            else
                bg:SetColorTexture(sp.bgR, sp.bgG, sp.bgB, sp.bgA)
            end
            UnsnapTex(bg)
            pip._bg = bg
            local fill = pip:CreateTexture(nil, "ARTWORK")
            fill:SetAllPoints()
            fill:SetTexture(FillPath(p))
            fill:SetVertexColor(1, 1, 1, 1)
            UnsnapTex(fill)
            pip._fill = fill
            pip._border = MakePreviewBorder(pip, 0, 0, 0, 0, 0)
            pip._border:SetShown(false)
            _previewFrames.pips[i] = pip
        end
    end

    -- The count text over the class resource row.
    local function BuildCountText(row, sp)
        local layer = CreateFrame("Frame", nil, row)
        layer:SetAllPoints(row)
        layer:SetFrameLevel(row:GetFrameLevel() + 10)
        local text = layer:CreateFontString(nil, "OVERLAY")
        SetPVFont(text, FONT_PATH, sp.textSize)
        text:SetTextColor(1, 1, 1, 0.9)
        local anchor = sp.textAnchor or "CENTER"
        text:SetPoint(anchor, row, anchor, sp.textXOffset or 0, sp.textYOffset or 0)
        row._countText = text
    end

    -- Arcane Soul (retail Mages only, as its section): a sample that replays
    -- the live sequence, a divider above it, and a watcher that keeps the
    -- on-screen sample running while this header shows.
    local function BuildArcaneSoul(holder)
        local sample = CreateFrame("Frame", nil, holder)
        sample._fs = sample:CreateFontString(nil, "OVERLAY")
        sample._fs:SetPoint("CENTER", sample, "CENTER", 0, 0)
        sample._fs._asStamp = nil -- a reused font string is reset: style it again
        sample:SetSize(1, 1)
        if _G._CURB_ArcaneSoulDemoOnUpdate then
            sample:SetScript("OnUpdate", _G._CURB_ArcaneSoulDemoOnUpdate)
        end
        _previewFrames.arcaneSoul = sample

        local divider = holder:CreateTexture(nil, "ARTWORK")
        divider:SetColorTexture(1, 1, 1, 0.10)
        UnsnapTex(divider)
        divider:Hide()
        _previewFrames.asDivider = divider

        local demo = _G._CURB_ArcaneSoulScreenDemo
        if demo then
            local watch = CreateFrame("Frame", nil, holder)
            watch:SetSize(1, 1)
            watch:SetPoint("CENTER")
            watch:SetScript("OnShow", function(self)
                demo(self, true)
            end)
            watch:SetScript("OnHide", function(self)
                demo(self, false)
            end)
            if watch:IsVisible() then
                demo(watch, true)
            end
        end
    end

    -- Element titles at header scale (the hint's size), on a child frame so
    -- the header cache keeps them with the rest.
    local function BuildTitles(heading, holder)
        local layer = CreateFrame("Frame", nil, heading)
        layer:SetAllPoints(heading)
        layer:SetFrameLevel(holder:GetFrameLevel() + 1)
        local function Title(text)
            local fs = CludesUI.MakeFont(layer, 11, nil, 1, 1, 1)
            fs:SetAlpha(0.6)
            fs:SetText(text)
            fs:Hide()
            return fs
        end
        _previewFrames.labels = {
            classResource = Title(CludesUI.L("Class Resource")),
            power = Title(CludesUI.L("Power Bar")),
            health = Title(CludesUI.L("Health Bar")),
            arcaneSoul = _previewFrames.arcaneSoul and Title(CludesUI.L("Arcane Soul")) or nil,
        }
    end

    -- Click-to-scroll overlays on each element (and a padded one on the count text).
    local function BuildHitOverlays(holder, row)
        wipe(_hitOverlays)
        local level = holder:GetFrameLevel() + 20
        if row then
            CreateHitOverlay(row, "classResource", level)
        end
        CreateHitOverlay(_previewFrames.powerBar, "power", level)
        CreateHitOverlay(_previewFrames.healthBar, "health", level)
        if _previewFrames.arcaneSoul then
            CreateHitOverlay(_previewFrames.arcaneSoul, "arcaneSoul", level)
        end
        if row and row._countText then
            local pad = CreateFrame("Frame", nil, row)
            pad:SetPoint("TOPLEFT", row._countText, "TOPLEFT", -2, 2)
            pad:SetPoint("BOTTOMRIGHT", row._countText, "BOTTOMRIGHT", 2, -2)
            CreateHitOverlay(pad, "countText", level + 5)
        end
    end

    -- The "click elements" hint under the preview (kept across builds and
    -- pages: out of its header's pool). Returns the height it adds.
    local function PlaceHint(heading, height)
        if height <= 0 or IsPreviewHintDismissed() then
            if _previewHintFS then
                _previewHintFS:Hide()
            end
            return 0
        end
        if not _previewHintFS then
            local layer = PoolKeep(CreateFrame("Frame", nil, heading))
            layer:SetAllPoints(heading)
            _previewHintFS = CludesUI.MakeFont(layer, 11, nil, 1, 1, 1)
            _previewHintFS:SetAlpha(0.45)
            _previewHintFS:SetText(CludesUI.L("Click elements to scroll to and highlight their options"))
        end
        local layer = _previewHintFS:GetParent()
        layer:SetParent(heading)
        layer:SetFrameLevel(heading:GetFrameLevel() + 1) -- as a new one sits
        layer:Show()
        _previewHintFS:ClearAllPoints()
        _previewHintFS:SetPoint("BOTTOM", heading, "BOTTOM", 0, 20)
        _previewHintFS:Show()
        return 35
    end

    -- The bars page's header: builds the preview's frames, lets
    -- UpdatePreviewHeader dress and stack them, and returns the height.
    _previewHeaderBuilder = function(heading, hdrW)
        HintBuildStart(PAGE_DISPLAY, heading)
        _classHdrEmpty = PoolGen(heading) ~= nil
        local p = DB()
        if not p then
            return 0
        end
        _previewBuilding = true
        local _, class = UnitClass("player")

        local holder = CreateFrame("Frame", nil, heading)
        holder:SetSize(hdrW, 100)
        holder:SetPoint("CENTER", heading, "CENTER", 0, 0)
        _previewFrames.container = holder
        -- Scaled so pixel sizes match the real bars: the panel's effective
        -- scale against UIParent's.
        _previewScale = UIParent:GetEffectiveScale() / heading:GetEffectiveScale()
        holder:SetScale(_previewScale)
        _previewSnap = function(v)
            local s = holder:GetEffectiveScale()
            return math.floor(v * s + 0.5) / s
        end

        local sp = p.secondary
        local row = CreateFrame("Frame", nil, holder) -- the pips or the bar type
        row:SetPoint("CENTER", holder, "CENTER", 0, 0)
        _previewFrames.pipContainer = row
        _previewFrames.pips = {}
        BuildResourceRow(row, p, sp, class)
        BuildCountText(row, sp)

        -- Built for every spec (cheap, pooled); UpdatePreviewHeader shows what applies.
        _previewFrames.powerBar = PreviewBar.Build(holder)
        _previewFrames.healthBar = PreviewBar.Build(holder)
        _previewFrames.arcaneSoul, _previewFrames.asDivider = nil, nil
        if class == "MAGE" and not CludesUI.IS_FOREVER then
            BuildArcaneSoul(holder)
        end
        BuildTitles(heading, holder)

        UpdatePreviewHeader()
        BuildHitOverlays(holder, row)

        if _previewHintFS and not _previewHintFS:GetParent() then
            _previewHintFS = nil
        end
        -- The height UpdatePreviewHeader laid out (0: nothing to show).
        local height = _headerBaseH
        -- Built with nothing to show, or with no class resource (its row was
        -- built for none, so a later spec or form with one needs a new build).
        _classHdrEmpty = ((height == 0 or not HasClassResource()) and PoolGen(heading) ~= nil) or nil
        height = height + PlaceHint(heading, height)
        _previewBuilding = false
        return height
    end

    -- Re-applies the bars once a burst of changes settles (50ms).
    local _refreshTimer
    local function DebouncedRefresh()
        if _refreshTimer then
            _refreshTimer:Cancel()
        end
        _refreshTimer = C_Timer.NewTimer(0.05, function()
            _refreshTimer = nil
            Refresh()
        end)
    end

    -- Click-to-scroll: a click on a preview element scrolls to its section
    -- and glows the row that sets it (_clickMappings: key -> { section,
    -- target, slotSide }, filled by the bars page).
    local PlaySettingGlow -- made on first use: the widget helpers load with the panel
    local _clickMappings = {}

    local function NavigateToSetting(key)
        local m = _clickMappings[key]
        if not (m and m.section and m.target) then
            return
        end
        CludesUI.DismissPreviewHint(_previewHintFS, _headerBaseH, 35, 5)
        if not CludesUI._scrollFrame then
            return
        end
        local _, _, _, _, sectionY = m.section:GetPoint(1)
        if not sectionY then
            return
        end
        CludesUI.SmoothScrollTo(math.max(0, math.abs(sectionY) - 40))
        local target = m.target
        if m.slotSide then
            target = (m.slotSide == "left" and m.target._leftRegion or m.target._rightRegion) or target
        end
        PlaySettingGlow = PlaySettingGlow
            or CludesUI.MakeSettingGlow({
                color = CludesUI.CLUDES_GREEN,
                thickness = function()
                    return Pix.Scale(2)
                end,
                noSnap = true,
            })
        -- A row the page dressed again meanwhile shows another setting: no glow.
        local gen = PoolGen(target)
        C_Timer.After(0.15, function()
            if PoolGen(target) == gen then
                PlaySettingGlow(target)
            end
        end)
    end

    CreateHitOverlay = function(element, mappingKey, frameLevelOverride)
        local overlay = CludesUI.CreatePreviewHitOverlay(
            element,
            NavigateToSetting,
            mappingKey,
            false,
            frameLevelOverride
        )
        _hitOverlays[#_hitOverlays + 1] = overlay
        return overlay
    end

    -- At once (scale and offset changes animate).
    local function SmoothRefresh()
        Refresh()
        UpdatePreviewHeader()
    end
    -- After a change: the bars a moment later, the preview at once. The six
    -- names are what the page files call.
    local function RefreshAndPreview()
        DebouncedRefresh()
        UpdatePreviewHeader()
    end
    local RefreshClass, RefreshHealth, RefreshPower = RefreshAndPreview, RefreshAndPreview, RefreshAndPreview
    local RebuildClass, RebuildHealth, RebuildPower = RefreshAndPreview, RefreshAndPreview, RefreshAndPreview

    -- Hash line positions as typed: the numbers (0 and up), comma-joined.
    -- Shared by the bar hash cog and the Threshold & Hash Lines editor.
    -- exact: each token is read trimmed, as the bar parses it ("25 50" is
    -- not a position), instead of with its spaces dropped ("50 000" = 50000).
    local function SanitizePositions(str, exact)
        if not str or str == "" then
            return ""
        end
        local kept = {}
        for token in tostring(str):gmatch("[^,]+") do
            local v = tonumber(exact and token:match("^%s*(.-)%s*$") or (token:gsub("%s", "")))
            if v and v >= 0 then
                kept[#kept + 1] = tostring(v)
            end
        end
        return table.concat(kept, ", ")
    end

    -- The cog and popup for a bar's own hash lines (Health, Power). conf:
    -- parentRgn, getBarData, refreshFn, popupTitle, anchorTo. Returns the cog.
    local function BuildHashCog(conf)
        local Bar = conf.getBarData
        local after = conf.refreshFn or function() end
        local function Off()
            local c = Bar()
            return not (c and c.hashEnabled)
        end
        -- A row's get / set over one field of the bar's settings.
        local function Field(row, key, default, write)
            row.get = function()
                local c = Bar()
                return (c and c[key]) or default
            end
            row.set = function(v)
                local c = Bar()
                if c then
                    c[key] = write and write(v) or v
                    after()
                end
            end
            if key ~= "hashEnabled" then
                row.disabled = Off
                row.disabledTooltip = CludesUI.L("Enable hash lines first")
            end
            return row
        end
        local rows = {
            Field(
                {
                    type = "toggle",
                    label = CludesUI.L("Show Hash Lines"),
                    tooltip = CludesUI.L("Draw tick lines across the bar at positions you choose."),
                },
                "hashEnabled",
                false,
                function(v)
                    return v and true or false
                end
            ),
            Field(
                { type = "input", label = CludesUI.L("Positions"), inputWidth = 130, commitOnBlur = true },
                "hashValues",
                "",
                SanitizePositions
            ),
            Field({
                type = "segmented",
                label = CludesUI.L("Mode"),
                keys = { "percent", "value" },
                labels = { percent = "%", value = "Value" },
            }, "hashMode", "percent"),
            Field(
                { type = "slider", label = CludesUI.L("Thickness"), min = 1, max = 5, step = 1 },
                "hashWidth",
                1
            ),
            {
                type = "colorpicker",
                label = CludesUI.L("Color"),
                hasAlpha = true,
                disabled = Off,
                disabledTooltip = CludesUI.L("Enable hash lines first"),
                get = function()
                    local c = Bar()
                    if not c then
                        return 1, 1, 1, 0.7
                    end
                    return c.hashColorR or 1, c.hashColorG or 1, c.hashColorB or 1, c.hashColorA or 0.7
                end,
                set = function(r, g, b, a)
                    local c = Bar()
                    if c then
                        c.hashColorR, c.hashColorG, c.hashColorB, c.hashColorA = r, g, b, a
                        after()
                    end
                end,
            },
        }
        return CludesUI.BuildInlineCog(conf.parentRgn, {
            anchorTo = conf.anchorTo,
            tip = CludesUI.L("Hash Lines"),
            title = conf.popupTitle or CludesUI.L("Hash Lines"),
            bgAlpha = 1,
            frameStrata = "FULLSCREEN_DIALOG",
            frameLevel = 500,
            rows = rows,
        })
    end

    -- Druid only: one cog row per form, on while that form shows. field is the
    -- map of the forms switched off: "textDisabledForms" (text rows) or
    -- "barDisabledForms" (whole bars, and the WoW Forever swing timer), read
    -- by _CURB_TextHiddenByForm / _CURB_BarHiddenByForm. nil for any other class.
    local DRUID_FORMS = {
        { key = "mana", label = "Caster" },
        { key = "rage", label = "Bear" },
        { key = "energy", label = "Cat" },
        { key = "moonkin", label = "Moonkin" },
    }
    local function FormToggleRows(cfgFn, refreshFn, field)
        local _, class = UnitClass("player")
        if class ~= "DRUID" then
            return nil
        end
        local rows = {}
        for _, form in ipairs(DRUID_FORMS) do
            local key = form.key
            rows[#rows + 1] = {
                type = "toggle",
                label = form.label,
                get = function()
                    local c = cfgFn()
                    return not (c and c[field] and c[field][key])
                end,
                set = function(on)
                    local c = cfgFn()
                    if not c then
                        return
                    end
                    if on then
                        if c[field] then
                            c[field][key] = nil
                        end
                    else
                        c[field] = c[field] or {}
                        c[field][key] = true
                    end
                    refreshFn()
                end,
            }
        end
        return rows
    end

    -- The druid per-form cog on a row.
    local function AddFormDisableBtn(rgn, leftOf, cfgFn, refreshFn, field, title, tooltip)
        local rows = FormToggleRows(cfgFn, refreshFn, field or "textDisabledForms")
        if not rows then
            return
        end
        title = title or "Enable/Disable per Form"
        return CludesUI.BuildInlineCog(rgn, {
            anchorTo = leftOf,
            tip = tooltip or CludesUI.L(title),
            title = title,
            bgAlpha = 1,
            frameStrata = "FULLSCREEN_DIALOG",
            frameLevel = 500,
            rows = rows,
        })
    end
    -- The CludesUI.L literals keep both titles in the static locale key list
    -- (tools/extract-locale-keys.sh sees literal string arguments only).
    local function AddFormTextBtn(rgn, leftOf, cfgFn, refreshFn)
        return AddFormDisableBtn(
            rgn,
            leftOf,
            cfgFn,
            refreshFn,
            "textDisabledForms",
            "Enable/Disable per Form",
            CludesUI.L("Enable/Disable per Form")
        )
    end
    local function AddFormBarBtn(rgn, cfgFn, refreshFn)
        return AddFormDisableBtn(
            rgn,
            nil,
            cfgFn,
            refreshFn,
            "barDisabledForms",
            "Enable/Disable Bar per Form",
            CludesUI.L("Enable/Disable Bar per Form")
        )
    end

    ---------------------------------------------------------------------------
    --  Colour bands (opt-in): a popup per threshold entry, opened from its
    --  "Bands" button, editing entry.bands, an ordered list of colour stops
    --  { to = boundary, r, g, b, a }. `to` is a count for pip resources and a
    --  percent or value for bars. ShowBandEditor binds it to the calling bar
    --  on every open.
    ---------------------------------------------------------------------------
    local _bandCloseIcon = "Interface\\AddOns\\CludesUI\\media\\icons\\cui-close.png"
    local BAND_POPUP_W, BAND_ROW_H, BAND_PAD, BAND_GAP = 300, 26, 14, 10

    -- The tooltip shared by the Multi toggle and the Bands button.
    local BAND_HELP_TIP = "Color the bar by ranges instead of a single threshold.\n"
        .. "Up to (<=) / From (>=)\n"
        .. "Any remaning values outside the bands will use fill color.\n"
        .. "|cff888888Bars can use % or actual value; pip resources use counts.|r"
    local BAND_REPLACES_TIP = "Single threshold is off while Multi-band is on.\n"
    -- On the greyed percent / value control for Brewmaster stagger.
    local STAGGER_PCT_TIP = "Stagger value can only be percent based"

    -- The popup and what the open is bound to.
    local Band = {
        rows = {},
        default = { 1, 0.2, 0.2, 1 },
    }

    local function CurrentBandEntry()
        if not (Band.entryIdx and Band.getBar) then
            return nil
        end
        local bar = Band.getBar()
        return bar and bar.thresholdSpecs and bar.thresholdSpecs[Band.entryIdx]
    end
    -- The band of a row, if it still exists.
    local function RowBand(row)
        local entry = CurrentBandEntry()
        return entry and entry.bands and entry.bands[row._idx], entry
    end

    local function SortBands(bands)
        table.sort(bands, function(a, b)
            return (a.to or 0) < (b.to or 0)
        end)
    end

    local RefreshBandEditor -- set below
    -- After any change: the bar, then the popup.
    local function BandChanged(redraw)
        if Band.refresh then
            Band.refresh()
        end
        if redraw ~= false then
            RefreshBandEditor()
        end
    end

    -- A popup that closes on a click outside it (and outside the options
    -- panel and an open dropdown), on entering combat, and with the panel.
    -- opts (optional): update(popup) runs each frame instead of the outside
    -- check, held() true keeps the click-catcher from closing it, onHide(popup)
    -- runs as it hides.
    local function DismissablePopup(width, level, opts)
        opts = opts or {}
        local popup = CreateFrame("Frame", nil, CludesUI.OverlayParent())
        popup:SetFrameStrata("FULLSCREEN_DIALOG")
        popup:SetFrameLevel(level)
        popup:SetClampedToScreen(true)
        popup:EnableMouse(true)
        popup:SetScale(CludesUI.GetPopupScale())
        popup:Hide()
        Pix.Size(popup, width, 200)
        local bg = popup:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.062, 0.070, 0.082, 0.97)
        popup._brd = CludesUI.MakeRoundedBorder(popup, 1, 1, 1, 0.18, bg)

        local catcher = CreateFrame("Button", nil, popup)
        catcher:SetFrameStrata("FULLSCREEN_DIALOG")
        catcher:SetFrameLevel(popup:GetFrameLevel() - 1)
        catcher:SetAllPoints((CludesUI:GetMainFrame()) or UIParent)
        catcher:SetScript("OnClick", function()
            if not (opts.held and opts.held()) then
                popup:Hide()
            end
        end)
        catcher:Hide()
        popup:SetScript("OnEvent", function(self, event)
            if event == "PLAYER_REGEN_DISABLED" then
                self:Hide()
            end
        end)
        popup:SetScript("OnShow", function(self)
            catcher:Show()
            self:RegisterEvent("PLAYER_REGEN_DISABLED")
            self:SetScript("OnUpdate", opts.update or function(me)
                if not IsMouseButtonDown("LeftButton") then
                    return
                end
                local panel, menu = CludesUI._mainFrame, CludesUI._openDropdownMenu
                if
                    not me:IsMouseOver()
                    and not (panel and panel:IsMouseOver())
                    and not (menu and menu:IsShown() and menu:IsMouseOver())
                then
                    me:Hide()
                end
            end)
        end)
        popup:SetScript("OnHide", function(self)
            catcher:Hide()
            self:UnregisterEvent("PLAYER_REGEN_DISABLED")
            self:SetScript("OnUpdate", nil)
            if opts.onHide then
                opts.onHide(self)
            end
        end)
        CludesUI.TrackOverlay(popup)
        CludesUI.PadHint(popup, "nodepass")
        CludesUI.PadHint(catcher, "nodepass")
        CludesUI._popupFrames[#CludesUI._popupFrames + 1] = { popup = popup }
        CludesUI:RegisterOnHide(function()
            popup:Hide()
        end)
        CludesUI:RegisterOnCollapse(function(on)
            if on then
                popup:Hide()
            end
        end)
        return popup
    end

    -- A labelled row (label left, control right), as the detail pane's rows.
    local function BandHeaderRow(text)
        local row = CreateFrame("Frame", nil, Band.popup)
        row:SetFrameLevel(Band.popup:GetFrameLevel() + 3)
        Pix.Height(row, BAND_ROW_H)
        local label = CludesUI.MakeFont(row, 12, nil, 1, 1, 1)
        label:SetAlpha(0.6)
        label:SetPoint("LEFT", row, "LEFT", 0, 0)
        label:SetText(CludesUI.L(text))
        row._lbl = label
        return row
    end

    -- A two-way switch on a header row; isOn(key) and set(key) over the entry.
    local function BandSwitch(row, keys, labels, isOn, set, isDisabled)
        local seg, _, refresh = CludesUI.BuildSegmentedControl({
            parent = row,
            keys = keys,
            labels = labels,
            autoWidth = true,
            square = true,
            height = 22,
            getChecked = isOn,
            isDisabled = isDisabled,
            onToggle = function(key)
                local entry = CurrentBandEntry()
                if entry and set(entry, key) ~= false then
                    BandChanged()
                end
            end,
        })
        seg:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        return seg, refresh
    end

    local function BuildBandPopup()
        local popup = DismissablePopup(BAND_POPUP_W, 260)
        Band.popup = popup

        Band.title = CludesUI.MakeFont(popup, 13, nil, 1, 1, 1)
        Band.title:SetAlpha(0.6)
        Band.title:SetPoint("TOP", popup, "TOP", 0, -BAND_PAD)
        Band.title:SetText(CludesUI.L("Color Bands"))

        -- Values as: Amount / Percent (bars only; a count-based resource
        -- shows a hint instead). Brewmaster stagger is percent only.
        Band.modeRow = BandHeaderRow("Values as")
        local function IsPercent()
            local entry = CurrentBandEntry()
            return Band.lockPercent or not (entry and entry.bandMode == "value")
        end
        Band.modeSeg, Band.modeRefresh = BandSwitch(
            Band.modeRow,
            { "amount", "percent" },
            { amount = "Amount", percent = "Percent" },
            function(key)
                return (key == "percent") == IsPercent()
            end,
            function(entry, key)
                if Band.lockPercent then
                    return false
                end
                entry.bandMode = key == "percent" and "percent" or "value"
            end,
            function()
                return Band.lockPercent and true or false
            end
        )
        -- Its disabled-state tooltip (stagger).
        local why = CreateFrame("Frame", nil, Band.modeRow)
        why:SetAllPoints(Band.modeSeg)
        why:SetFrameLevel(Band.modeSeg:GetFrameLevel() + 5)
        why:EnableMouse(true)
        why:SetScript("OnEnter", function(self)
            CludesUI.ShowWidgetTooltip(self, CludesUI.L(STAGGER_PCT_TIP))
        end)
        why:SetScript("OnLeave", function()
            CludesUI.HideWidgetTooltip()
        end)
        why:Hide()
        Band.modeRow._staggerDis = why
        Band.modeHint = CludesUI.MakeFont(popup, 10, nil, 1, 1, 1)
        Band.modeHint:SetAlpha(0.4)

        -- Direction: Up to / From (always one of the two).
        Band.dirRow = BandHeaderRow("Direction")
        Band.dirSeg, Band.dirRefresh = BandSwitch(
            Band.dirRow,
            { "upto", "from" },
            { upto = "Up to", from = "From" },
            function(key)
                local entry = CurrentBandEntry()
                local from = entry and entry.bandReverse and true or false
                return (key == "from") == from
            end,
            function(entry, key)
                entry.bandReverse = key == "from"
            end
        )

        -- + Add Band: one past the last boundary, in the default colour.
        local add = CreateFrame("Button", nil, popup)
        Pix.Size(add, BAND_POPUP_W - BAND_PAD * 2, 26)
        add:SetFrameLevel(popup:GetFrameLevel() + 3)
        local bg = CludesUI.SolidTex(add, "BACKGROUND", 0.050, 0.058, 0.068, 0.92)
        bg:SetAllPoints()
        add._border = CludesUI.MakeRoundedBorder(add, 1, 1, 1, 0.4, bg)
        local label = CludesUI.MakeFont(add, 12, nil, 1, 1, 1)
        label:SetAlpha(0.5)
        label:SetPoint("CENTER")
        label:SetText(CludesUI.L("+ Add Band"))
        local function Hover(textAlpha, borderAlpha)
            label:SetAlpha(textAlpha)
            if add._border and add._border.SetColor then
                add._border:SetColor(1, 1, 1, borderAlpha)
            end
        end
        add:SetScript("OnEnter", function()
            Hover(0.7, 0.6)
        end)
        add:SetScript("OnLeave", function()
            Hover(0.5, 0.4)
        end)
        add:SetScript("OnClick", function()
            local entry = CurrentBandEntry()
            if not entry then
                return
            end
            entry.bands = entry.bands or {}
            local last = entry.bands[#entry.bands]
            local d = Band.default
            entry.bands[#entry.bands + 1] = {
                to = last and ((last.to or 0) + 1) or 1,
                r = d[1],
                g = d[2],
                b = d[3],
                a = d[4],
            }
            SortBands(entry.bands)
            BandChanged()
        end)
        Band.addBtn = add
    end

    -- The widgets of band row k, made on first need.
    local function EnsureBandRow(k)
        if Band.rows[k] then
            return Band.rows[k]
        end
        local row = {}
        local frame = CreateFrame("Frame", nil, Band.popup)
        frame:SetSize(BAND_POPUP_W - BAND_PAD * 2, BAND_ROW_H)
        frame:SetFrameLevel(Band.popup:GetFrameLevel() + 2)
        row.frame = frame

        local label = CludesUI.MakeFont(frame, 12, nil, 1, 1, 1)
        label:SetAlpha(0.6)
        label:SetPoint("LEFT", frame, "LEFT", 2, 0)
        label:SetText(CludesUI.L("Up to")) -- the band colours values up to `to`
        row.lbl = label

        local input = CreateFrame("EditBox", nil, frame)
        input:SetSize(54, 22)
        input:SetPoint("LEFT", label, "RIGHT", 6, 0)
        input:SetFrameLevel(frame:GetFrameLevel() + 2)
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

        -- Commits when the field loses focus (Enter clears focus); Escape
        -- marks the typed text to be thrown away.
        input:SetScript("OnEditFocusLost", function(self)
            if self._cancelCommit then
                self._cancelCommit = nil
                return
            end
            local band, entry = RowBand(row)
            if not band then
                return
            end
            local v = tonumber(self:GetText())
            if v then
                local top = Band.countBased and 100
                    or (
                        (not Band.lockPercent and entry.bandMode == "value") and 1000000
                        or (Band.percentMax or 100)
                    )
                band.to = math.max(1, math.min(top, math.floor(v + 0.5)))
                SortBands(entry.bands)
                BandChanged(false)
            end
            RefreshBandEditor()
        end)
        input:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
        end)
        input:SetScript("OnEscapePressed", function(self)
            self._cancelCommit = true
            self:ClearFocus()
            RefreshBandEditor()
        end)

        local swatch, snap = CludesUI.BuildColorSwatch(frame, frame:GetFrameLevel() + 3, function()
            local band = RowBand(row)
            local d = Band.default
            if not band then
                return d[1], d[2], d[3], d[4]
            end
            return band.r or d[1], band.g or d[2], band.b or d[3], band.a or d[4]
        end, function(r, g, b, a)
            local band = RowBand(row)
            if band then
                band.r, band.g, band.b, band.a = r, g, b, a
                BandChanged(false)
            end
        end, true, 19)
        swatch:SetPoint("LEFT", input, "RIGHT", 10, 0)
        row.swatch, row.swatchSnap = swatch, snap

        local remove = CreateFrame("Button", nil, frame)
        remove:SetSize(14, 14)
        remove:SetPoint("RIGHT", frame, "RIGHT", -2, 0)
        remove:SetFrameLevel(frame:GetFrameLevel() + 3)
        local icon = remove:CreateTexture(nil, "OVERLAY")
        icon:SetAllPoints()
        icon:SetTexture(_bandCloseIcon)
        icon:SetAlpha(0.4)
        remove:SetScript("OnEnter", function()
            icon:SetAlpha(0.9)
        end)
        remove:SetScript("OnLeave", function()
            icon:SetAlpha(0.4)
        end)
        remove:SetScript("OnClick", function()
            local band, entry = RowBand(row)
            if band then
                table.remove(entry.bands, row._idx)
                BandChanged()
            end
        end)
        row.delBtn = remove

        Band.rows[k] = row
        return row
    end

    -- Lays the popup out for the bound entry: the mode row (or hint), the
    -- direction row, one row per band, then + Add Band.
    RefreshBandEditor = function()
        local popup = Band.popup
        if not popup then
            return
        end
        local entry = CurrentBandEntry()
        if not entry then
            popup:Hide()
            return
        end
        entry.bands = entry.bands or {}

        local y = -(BAND_PAD + 24) -- below the title
        local function Place(row)
            row:ClearAllPoints()
            Pix.Point(row, "TOPLEFT", popup, "TOPLEFT", BAND_PAD, y)
            Pix.Point(row, "TOPRIGHT", popup, "TOPRIGHT", -BAND_PAD, y)
            row:Show()
            y = y - BAND_ROW_H - BAND_GAP
        end

        if Band.countBased then
            -- Boundaries are counts: no unit to pick.
            Band.modeRow:Hide()
            Band.modeHint:ClearAllPoints()
            Band.modeHint:SetPoint("TOPLEFT", popup, "TOPLEFT", BAND_PAD, y - 4)
            Band.modeHint:SetText(CludesUI.L("Boundaries are resource counts"))
            Band.modeHint:Show()
            y = y - 18 - BAND_GAP
        else
            Band.modeHint:Hide()
            if Band.modeRefresh then
                Band.modeRefresh()
            end
            -- Stagger: the unit is locked, so the control greys and explains why.
            if Band.modeRow._staggerDis then
                Band.modeRow._staggerDis:SetShown(Band.lockPercent and true or false)
            end
            if Band.modeRow._lbl then
                Band.modeRow._lbl:SetAlpha(Band.lockPercent and 0.3 or 0.6)
            end
            Place(Band.modeRow)
        end

        if Band.dirRefresh then
            Band.dirRefresh()
        end
        Place(Band.dirRow)
        -- The row label follows the direction: "From" (>=) or "Up to".
        local rowLabel = entry.bandReverse and CludesUI.L("From") or CludesUI.L("Up to")
        local count = #entry.bands
        for k = 1, count do
            local row = EnsureBandRow(k)
            row._idx = k
            row.lbl:SetText(rowLabel)
            row.frame:ClearAllPoints()
            Pix.Point(row.frame, "TOPLEFT", popup, "TOPLEFT", BAND_PAD, y)
            row.input:SetText(tostring(entry.bands[k].to or 1))
            if row.swatchSnap then
                row.swatchSnap()
            end
            row.frame:Show()
            y = y - BAND_ROW_H - 4
        end
        for k = count + 1, #Band.rows do
            if Band.rows[k] then
                Band.rows[k].frame:Hide()
            end
        end

        y = y - 4
        Band.addBtn:ClearAllPoints()
        Pix.Point(Band.addBtn, "TOPLEFT", popup, "TOPLEFT", BAND_PAD, y)
        y = y - 26
        Pix.Size(popup, BAND_POPUP_W, math.abs(y) + BAND_PAD)
        popup._brd:Fit()
    end

    -- params: getBarData, refreshFn, entryIdx, anchor, countBased,
    -- lockPercent (stagger), percentMax, defR/G/B/A (a new band's colour).
    local function ShowBandEditor(params)
        if not Band.popup then
            BuildBandPopup()
        end
        Band.getBar = params.getBarData
        Band.refresh = params.refreshFn
        Band.entryIdx = params.entryIdx
        Band.countBased = params.countBased and true or false
        Band.lockPercent = params.lockPercent and true or false
        Band.percentMax = params.percentMax
        Band.default = { params.defR or 1, params.defG or 0.2, params.defB or 0.2, params.defA or 1 }
        local entry = CurrentBandEntry()
        if entry then
            if Band.lockPercent then
                entry.bandMode = "percent" -- stagger: percent only
            end
            entry.bands = entry.bands or {}
            -- The first open seeds one band from the single threshold.
            if #entry.bands == 0 then
                local d = Band.default
                entry.bands[1] = {
                    to = Band.countBased and (entry.thresholdCount or 3) or (entry.thresholdPct or 30),
                    r = entry.thresholdR or d[1],
                    g = entry.thresholdG or d[2],
                    b = entry.thresholdB or d[3],
                    a = entry.thresholdA or d[4],
                }
            end
        end
        RefreshBandEditor()
        Band.popup:ClearAllPoints()
        Band.popup:SetPoint("TOP", params.anchor, "BOTTOM", 0, -4)
        Band.popup:Show()
    end

    ---------------------------------------------------------------------------
    --  Colour lists: per threshold entry, a list of { spellID, r, g, b, a } in
    --  entry[o.field] (per spec through the entry's specIDs). The list order
    --  is the priority (the first matching spell wins), so rows drag to
    --  reorder, like BuildCogPopup's 'reorder' row. Buff Colors and Spender
    --  Colors each make one. o = { field, title, addLabel } (both texts
    --  localized). Returns Show(params), params = { getBarData, refreshFn,
    --  entryIdx, anchor }; the popup is built on the first Show.
    ---------------------------------------------------------------------------
    local LIST_DEFAULT = { 0.2, 0.6, 1.0, 1 }

    local function MakeColorListEditor(o)
        local field = o.field
        local WIDTH, ROW_H = 320, 26
        local STEP = ROW_H + 4
        local FIRST_Y = -(BAND_PAD + 24) -- the first row, below the title
        local popup, addButton, insertLine
        local rows = {}
        local bound = {} -- entryIdx, getBar, refresh
        local drag = { row = nil, startY = nil, active = false }
        local Redraw, DragStep -- set below

        local function Entry()
            if not (bound.entryIdx and bound.getBar) then
                return nil
            end
            local bar = bound.getBar()
            return bar and bar.thresholdSpecs and bar.thresholdSpecs[bound.entryIdx]
        end
        local function List()
            local entry = Entry()
            return entry and entry[field]
        end
        local function Item(row)
            local list = List()
            return list and list[row._idx]
        end
        local function Changed()
            if bound.refresh then
                bound.refresh()
            end
        end

        local function Build()
            popup = DismissablePopup(WIDTH, 260, {
                -- While a grip is held: move and reorder, never close.
                update = function(self)
                    if drag.row then
                        DragStep()
                    elseif IsMouseButtonDown("LeftButton") then
                        local panel = CludesUI._mainFrame
                        if not self:IsMouseOver() and not (panel and panel:IsMouseOver()) then
                            self:Hide()
                        end
                    end
                end,
                held = function()
                    return drag.active
                end,
                -- Combat or the panel closing can land mid-drag: drop it (Show lays out again).
                onHide = function()
                    drag.row, drag.active = nil, false
                    insertLine:Hide()
                end,
            })

            -- The insertion line while dragging (accent, as the raid "Sort By" reorder).
            insertLine = popup:CreateTexture(nil, "OVERLAY", nil, 7)
            insertLine:SetHeight(2)
            local accent = CludesUI.CLUDES_GREEN
            insertLine:SetColorTexture(accent.r, accent.g, accent.b, 0.9)
            insertLine:Hide()

            local title = CludesUI.MakeFont(popup, 13, nil, 1, 1, 1)
            title:SetAlpha(0.7)
            title:SetPoint("TOP", popup, "TOP", 0, -BAND_PAD)
            title:SetText(o.title)
            local hint = CludesUI.MakeFont(popup, 10, nil, 1, 1, 1, 0.25)
            hint:SetPoint("TOPLEFT", popup, "TOPLEFT", 16, -BAND_PAD - 4)
            hint:SetText(CludesUI.L("Drag to Reorder"))

            addButton = CreateFrame("Button", nil, popup)
            Pix.Size(addButton, WIDTH - BAND_PAD * 2, 26)
            addButton:SetFrameLevel(popup:GetFrameLevel() + 3)
            local bg = CludesUI.SolidTex(addButton, "BACKGROUND", 0.050, 0.058, 0.068, 0.92)
            bg:SetAllPoints()
            addButton._border = CludesUI.MakeRoundedBorder(addButton, 1, 1, 1, 0.4, bg)
            local label = CludesUI.MakeFont(addButton, 12, nil, 1, 1, 1)
            label:SetAlpha(0.5)
            label:SetPoint("CENTER")
            label:SetText(o.addLabel)
            addButton:SetScript("OnEnter", function()
                label:SetAlpha(0.7)
                addButton._border:SetColor(1, 1, 1, 0.6)
            end)
            addButton:SetScript("OnLeave", function()
                label:SetAlpha(0.5)
                addButton._border:SetColor(1, 1, 1, 0.4)
            end)
            addButton:SetScript("OnClick", function()
                local entry = Entry()
                if not entry then
                    return
                end
                entry[field] = entry[field] or {}
                local d = LIST_DEFAULT
                entry[field][#entry[field] + 1] = { spellID = nil, r = d[1], g = d[2], b = d[3], a = d[4] }
                Changed()
                Redraw()
            end)
        end

        local function EnsureRow(k)
            if rows[k] then
                return rows[k]
            end
            local row = {}
            local frame = CreateFrame("Frame", nil, popup)
            frame:SetSize(WIDTH - BAND_PAD * 2, ROW_H)
            frame:SetFrameLevel(popup:GetFrameLevel() + 2)
            row.frame = frame

            local input = CreateFrame("EditBox", nil, frame)
            input:SetSize(58, 22)
            input:SetPoint("LEFT", frame, "LEFT", 16, 0)
            input:SetFrameLevel(frame:GetFrameLevel() + 2)
            input:SetAutoFocus(false)
            input:SetFont(CludesUI.GetFontPath("main") or "Fonts\\FRIZQT__.TTF", 12, "")
            input:SetTextColor(1, 1, 1, 0.75)
            input:SetJustifyH("CENTER")
            input:SetNumeric(true)
            input:SetMaxLetters(7)
            local inputBg = input:CreateTexture(nil, "BACKGROUND")
            inputBg:SetAllPoints()
            inputBg:SetColorTexture(0.12, 0.12, 0.12, 0.8)
            CludesUI.MakeRoundedBorder(input, 1, 1, 1, 0.08, inputBg)
            row.input = input

            -- The drag grip (order is priority).
            local grip = CreateFrame("Button", nil, frame)
            grip:SetSize(14, ROW_H)
            grip:SetPoint("LEFT", frame, "LEFT", 0, 0)
            grip:SetFrameLevel(frame:GetFrameLevel() + 4)
            local gripText = CludesUI.MakeFont(grip, 13, nil, 1, 1, 1, 0.25)
            gripText:SetPoint("CENTER")
            gripText:SetText("=")
            grip:SetScript("OnEnter", function()
                gripText:SetTextColor(1, 1, 1, 0.6)
            end)
            grip:SetScript("OnLeave", function()
                gripText:SetTextColor(1, 1, 1, 0.25)
            end)
            grip:SetScript("OnMouseDown", function(_, button)
                if button == "LeftButton" then
                    local _, y = GetCursorPosition()
                    drag.row, drag.startY, drag.active = row, y, false
                end
            end)
            row.grip = grip

            local name = CludesUI.MakeFont(frame, 11, nil, 1, 1, 1)
            name:SetAlpha(0.6)
            name:SetPoint("LEFT", input, "RIGHT", 8, 0)
            name:SetJustifyH("LEFT")
            name:SetWidth(150)
            name:SetWordWrap(false)
            row.nameFS = name
            function row.RefreshName()
                local item = Item(row)
                local id = item and item.spellID
                if id then
                    name:SetText(
                        C_Spell.GetSpellName(id)
                            or (CludesUI.COLOR_CODES.BAD .. CludesUI.L("Unknown ID") .. "|r")
                    )
                else
                    name:SetText(CludesUI.COLOR_CODES.DIM .. CludesUI.L("(enter Spell ID)") .. "|r")
                end
            end

            -- Commits when the field loses focus; Escape throws the typing away.
            input:SetScript("OnEditFocusLost", function(self)
                if self._cancelCommit then
                    self._cancelCommit = nil
                    return
                end
                local item = Item(row)
                if not item then
                    return
                end
                local v = tonumber(self:GetText())
                item.spellID = (v and v > 0) and v or nil
                row.RefreshName()
                Changed()
            end)
            input:SetScript("OnEnterPressed", function(self)
                self:ClearFocus()
            end)
            input:SetScript("OnEscapePressed", function(self)
                self._cancelCommit = true
                self:ClearFocus()
                Redraw()
            end)

            local swatch, snap = CludesUI.BuildColorSwatch(frame, frame:GetFrameLevel() + 3, function()
                local item = Item(row)
                local d = LIST_DEFAULT
                if not item then
                    return d[1], d[2], d[3], d[4]
                end
                return item.r or d[1], item.g or d[2], item.b or d[3], item.a or d[4]
            end, function(r, g, b, a)
                local item = Item(row)
                if item then
                    item.r, item.g, item.b, item.a = r, g, b, a
                    Changed()
                end
            end, true, 19)
            swatch:SetPoint("RIGHT", frame, "RIGHT", -24, 0)
            row.swatch, row.swatchSnap = swatch, snap

            local remove = CreateFrame("Button", nil, frame)
            remove:SetSize(14, 14)
            remove:SetPoint("RIGHT", frame, "RIGHT", -2, 0)
            remove:SetFrameLevel(frame:GetFrameLevel() + 3)
            local icon = remove:CreateTexture(nil, "OVERLAY")
            icon:SetAllPoints()
            icon:SetTexture(_bandCloseIcon)
            icon:SetAlpha(0.4)
            remove:SetScript("OnEnter", function()
                icon:SetAlpha(0.9)
            end)
            remove:SetScript("OnLeave", function()
                icon:SetAlpha(0.4)
            end)
            remove:SetScript("OnClick", function()
                local list = List()
                if list and list[row._idx] then
                    table.remove(list, row._idx)
                    Changed()
                    Redraw()
                end
            end)
            row.delBtn = remove

            rows[k] = row
            return row
        end

        Redraw = function()
            if not popup then
                return
            end
            local entry = Entry()
            if not entry then
                popup:Hide()
                return
            end
            entry[field] = entry[field] or {}
            local list = entry[field]
            local y = FIRST_Y
            for k = 1, #list do
                local row = EnsureRow(k)
                row._idx = k
                row.frame:ClearAllPoints()
                Pix.Point(row.frame, "TOPLEFT", popup, "TOPLEFT", BAND_PAD, y)
                row._baseY = y -- for the drag hit test
                row.frame:SetFrameLevel(popup:GetFrameLevel() + 2) -- a drag raised it
                row.frame:SetAlpha(1)
                row.input:SetText(list[k].spellID and tostring(list[k].spellID) or "")
                row.RefreshName()
                row.swatchSnap()
                row.frame:Show()
                y = y - ROW_H - 4
            end
            for k = #list + 1, #rows do
                if rows[k] then
                    rows[k].frame:Hide()
                end
            end
            y = y - 4
            addButton:ClearAllPoints()
            Pix.Point(addButton, "TOPLEFT", popup, "TOPLEFT", BAND_PAD, y)
            y = y - 26
            Pix.Size(popup, WIDTH, math.abs(y) + BAND_PAD)
            popup._brd:Fit()
        end

        -- Each frame while a grip is held: a click until the cursor moves 3px,
        -- then the row follows the cursor with an insertion line; on release
        -- the list is reordered (order = priority) and drawn again.
        DragStep = function()
            local row = drag.row
            if not row then
                return
            end
            local down = IsMouseButtonDown("LeftButton")
            local _, cursorY = GetCursorPosition()
            if not drag.active then
                if not down then
                    drag.row = nil -- released before moving: a click
                    return
                end
                if math.abs(cursorY - (drag.startY or cursorY)) < 3 then
                    return
                end
                drag.active = true
                row.frame:SetFrameLevel(popup:GetFrameLevel() + 20)
                row.frame:SetAlpha(0.85)
            end
            local list = List()
            local count = list and #list or 0
            local y = cursorY / popup:GetEffectiveScale()
            local top = popup:GetTop() or 0
            -- Where it would go among the rows that stay put.
            local at = count
            for i = 1, count do
                local other = rows[i]
                if other ~= row and other._baseY then
                    if y > top + other._baseY - ROW_H / 2 then
                        at = i
                        break
                    end
                    at = i + 1
                end
            end
            at = math.max(1, math.min(at, count + 1))
            if down then
                local lineY = (at <= 1) and (FIRST_Y + 2) or (FIRST_Y - (at - 1) * STEP + 2)
                insertLine:ClearAllPoints()
                insertLine:SetPoint("TOPLEFT", popup, "TOPLEFT", BAND_PAD, lineY)
                insertLine:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -BAND_PAD, lineY)
                insertLine:Show()
                row.frame:ClearAllPoints()
                row.frame:SetPoint("TOPLEFT", popup, "TOPLEFT", BAND_PAD, y - top)
                return
            end
            -- Dropped.
            local from = row._idx
            if from and from < at then
                at = at - 1
            end
            local to = math.max(1, math.min(at, count))
            insertLine:Hide()
            drag.row, drag.active = nil, false
            if list and from and from ~= to then
                table.insert(list, to, table.remove(list, from))
                Changed()
            end
            Redraw()
        end

        return function(params)
            if not popup then
                Build()
            end
            bound.getBar, bound.refresh, bound.entryIdx = params.getBarData, params.refreshFn, params.entryIdx
            local entry = Entry()
            if entry and not entry[field] then
                entry[field] = {}
            end
            Redraw()
            popup:ClearAllPoints()
            popup:SetPoint("TOP", params.anchor, "BOTTOM", 0, -4)
            popup:Show()
        end
    end

    local ShowBuffEditor = MakeColorListEditor({
        field = "buffColors",
        title = CludesUI.L("Buff Colors"),
        addLabel = CludesUI.L("+ Add Buff"),
    })
    local BUFF_HELP_TIP = "Recolor the bar while you have a buff. The first active buff in the list wins, so order = priority. Overrides threshold coloring while active.\n"
        .. "You must be tracking the buff in Blizzard CDM, added to CUI CDM, and this only works with CDM trackable buffs."

    local ShowSpenderEditor = MakeColorListEditor({
        field = "spenderColors",
        title = CludesUI.L("Spender Colors"),
        addLabel = CludesUI.L("+ Add Spender"),
    })
    local SPENDER_HELP_TIP = "Recolor the bar while a spell is castable (usable and off cooldown). The first castable spell in the list wins, so order = priority. Overrides threshold coloring while active; an active tracked buff from Buff Colors takes priority.\n"
        .. "For an ability that turns into another spell while active, enter the original spell's ID: its current form is checked."

    -- A small text button of the threshold settings (Bands, Buffs, Spenders):
    -- a dark fill that lightens on hover, with its tooltip. label is localized.
    local CARD_BG, CARD_BG_HOVER = { 0.12, 0.12, 0.12, 0.8 }, { 0.16, 0.16, 0.16, 0.9 }
    local function SkinCardButton(button, label, tipText)
        local bg = button:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(unpack(CARD_BG))
        button._border = CludesUI.MakeRoundedBorder(button, 1, 1, 1, 0.08, bg)
        local text = CludesUI.MakeFont(button, 12, nil, 1, 1, 1)
        text:SetAlpha(0.8)
        text:SetPoint("CENTER")
        text:SetText(label)
        button:SetScript("OnEnter", function(self)
            bg:SetColorTexture(unpack(CARD_BG_HOVER))
            CludesUI.ShowWidgetTooltip(self, tipText)
        end)
        button:SetScript("OnLeave", function()
            bg:SetColorTexture(unpack(CARD_BG))
            CludesUI.HideWidgetTooltip()
        end)
    end

    -- The threshold notice: an info badge in the Settings button's top-left
    -- naming every spec with a threshold set, so a spec's setup shows from a
    -- page that does not list it. The accent while none applies to the spec
    -- being played, orange while one does; the button's border takes the same
    -- tint. Click-through (as the Spec Overrides badge), so the button keeps
    -- its hover and click.
    local THR_NOTE_IDLE = {} -- the accent, filled in place by each update
    local THR_NOTE_ACTIVE = { 1, 0x8c / 255, 0x26 / 255, "ff8c26" }

    -- Returns the updater, which callers run again after an edit.
    local function AttachThresholdNotice(anchorBtn, getBarData)
        if not anchorBtn then
            return
        end
        local badge = CreateFrame("Frame", nil, anchorBtn)
        badge:SetSize(14, 14)
        badge:SetPoint("TOPLEFT", anchorBtn, "TOPLEFT", 2, -2)
        -- Under the button's disabled cover (level + 5), so a disabled bar dims it too.
        badge:SetFrameLevel(anchorBtn:GetFrameLevel() + 3)
        badge:SetMouseClickEnabled(false)
        local icon = badge:CreateTexture(nil, "OVERLAY")
        icon:SetAllPoints()
        if icon.SetSnapToPixelGrid then
            icon:SetSnapToPixelGrid(false)
            icon:SetTexelSnappingBias(0)
        end
        icon:SetTexture([[Interface\AddOns\CludesUI\media\icons\cui-info.png]])
        badge._color = THR_NOTE_IDLE
        local function Tint(alpha)
            local c = badge._color
            icon:SetVertexColor(c[1], c[2], c[3], alpha)
        end
        badge:SetScript("OnEnter", function(self)
            Tint(1)
            if self._tip and CludesUI.ShowWidgetTooltip then
                CludesUI.ShowWidgetTooltip(self, self._tip)
            end
        end)
        badge:SetScript("OnLeave", function()
            Tint(0.85)
            CludesUI.HideWidgetTooltip()
        end)
        badge:Hide()

        -- The button's own border in the same tint (white when nothing is
        -- set); its hover handlers read _borderTint, so the tint survives.
        local function BorderTint(rgb)
            anchorBtn._borderTint = rgb
            if anchorBtn._border and anchorBtn._border.SetColor then
                anchorBtn._border:SetColor(
                    rgb[1],
                    rgb[2],
                    rgb[3],
                    anchorBtn:IsMouseOver() and 0.3 or CludesUI.DD_BRD_A
                )
            end
        end

        local function Update()
            local r, g, b = CludesUI.GetAccentColor()
            THR_NOTE_IDLE[1], THR_NOTE_IDLE[2], THR_NOTE_IDLE[3] = r, g, b
            THR_NOTE_IDLE[4] = CludesUI.HexColor(r, g, b):sub(5)
            local list, applies = mod.ThresholdNoticeInfo(getBarData())
            if not list then
                if CludesUI.HideWidgetTooltip and badge:IsMouseOver() then
                    CludesUI.HideWidgetTooltip()
                end
                badge:Hide()
                BorderTint(THR_BORDER_WHITE)
                return
            end
            local c = applies and THR_NOTE_ACTIVE or THR_NOTE_IDLE
            badge._color = c
            Tint(badge:IsMouseOver() and 1 or 0.85)
            local lead = applies and CludesUI.L("Current Spec is affected by Threshold & Hash Lines.")
                or CludesUI.L("Current Spec is not affected by Threshold & Hash Lines.")
            local which = "|cff"
                .. c[4]
                .. CludesUI.L("Thresholds or hash lines configured for:")
                .. "|r "
                .. list
            badge._tip = "|cff" .. c[4] .. lead .. "|r\n\n" .. which
            badge:Show()
            BorderTint(c)
        end
        anchorBtn:HookScript("OnShow", Update)
        CludesUI.RegisterWidgetRefresh(Update)
        -- Keyed by the badge: the page pool forgets it when it resets the badge.
        CludesUI.RegAccent({ type = "callback", obj = badge, fn = Update })
        Update()
        return Update
    end

    -- Spec and talent watcher for the Threshold & Hash Lines editors. A spec or
    -- talent change moves which entry the resolver picks, so every open editor
    -- refreshes in place and keeps its selection. With no editor open a spec
    -- swap redraws the bars page; with one open the redraw waits for the last
    -- editor to close (a redraw would close it); an editor closed by leaving
    -- the page or closing the panel leaves the rebuild to the next visit. One
    -- event frame and one accent entry per session, made by the first editor
    -- build; the talent events are listened to only while an editor is open.
    local ThrWatchBuild, ThrEditorShown, ThrEditorHidden
    do
        local open = {} -- [editor page] = { refresh, repaint, gen } while shown
        local watch, stale, redrawQueued, refreshQueued
        local function OnBarsPage()
            return CludesUI:IsShown() and CludesUI:GetActivePage() == PAGE_DISPLAY
        end
        local function RedrawNow()
            if redrawQueued then
                redrawQueued = nil
                if OnBarsPage() then
                    CludesUI:RefreshPage(true)
                end
            end
        end
        -- One redraw per burst (a swap sends both spec events); a page build
        -- in between cancels it.
        local function QueueRedraw()
            if not redrawQueued and OnBarsPage() then
                redrawQueued = true
                C_Timer.After(0, RedrawNow)
            end
        end
        -- Calls fn(page, editor) on each open editor still dressed as it was
        -- (a pooled page dressed again since is over: it leaves the watcher).
        local function EachOpen(fn)
            for page, editor in pairs(open) do
                if PoolGen(page) == editor.gen then
                    fn(page, editor)
                else
                    ThrEditorHidden(page)
                end
            end
        end
        -- One in-place refresh per burst, a frame later (once the bars saw it).
        local function FlushRefresh()
            refreshQueued = nil
            EachOpen(function(_, editor)
                editor.refresh()
            end)
        end
        local function OnEvent(_, event)
            local swap = event == "PLAYER_SPECIALIZATION_CHANGED" or event == "ACTIVE_TALENT_GROUP_CHANGED"
            if next(open) then
                if swap then
                    stale = true
                end
                if not refreshQueued then
                    refreshQueued = true
                    C_Timer.After(0, FlushRefresh)
                end
            elseif swap then
                if OnBarsPage() then
                    QueueRedraw()
                else
                    -- Away from the page: its next visit builds it for the new spec.
                    CludesUI:InvalidateModulePageCache("CludesUIResourceBars")
                end
            end
        end
        -- Every editor build: makes the watcher once; the page building is current again.
        ThrWatchBuild = function()
            stale, redrawQueued = nil, nil
            if watch then
                return
            end
            watch = CreateFrame("Frame")
            watch:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
            watch:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
            watch:SetScript("OnEvent", OnEvent)
            -- The selection highlight follows the theme accent.
            CludesUI.RegAccent({
                type = "callback",
                fn = function()
                    EachOpen(function(_, editor)
                        editor.repaint()
                    end)
                end,
            })
        end
        ThrEditorShown = function(page, editor)
            if not next(open) then
                watch:RegisterEvent("TRAIT_CONFIG_UPDATED")
                watch:RegisterEvent("PLAYER_TALENT_UPDATE")
            end
            open[page] = editor
        end
        ThrEditorHidden = function(page)
            if not open[page] then
                return
            end
            open[page] = nil
            if next(open) then
                return
            end
            watch:UnregisterEvent("TRAIT_CONFIG_UPDATED")
            watch:UnregisterEvent("PLAYER_TALENT_UPDATE")
            if not stale then
                return
            end
            stale = nil
            if OnBarsPage() then
                QueueRedraw()
            elseif CludesUI:GetActivePage() == PAGE_DISPLAY then
                -- Closed with the panel: RefreshPage only marks a hidden
                -- panel, so its next open rebuilds the page.
                CludesUI:RefreshPage(true)
            else
                -- Left for another page or module: the next visit rebuilds it.
                CludesUI:InvalidateModulePageCache("CludesUIResourceBars")
            end
        end
    end

    -- Threshold & Hash Lines editor, shared by the class resource, power and health bar
    -- sections. The Settings button opens an in-page editor over the section: the bar's
    -- threshold entries in a list on the left, the selected entry's settings on the right.
    -- cfg fields (optional unless marked):
    --    parentRgn       -- (required) the DualRow right region that hosts the button
    --    getBarData      -- (required) fn() returns the bar table (p.secondary, p.primary, p.health)
    --    refreshFn       -- (required) fn() called after a setting change
    --    rebuildFn       -- (required) fn() called after a structural change (hash lines, talent gate, variants)
    --    swatchRefreshFn -- fn() called after a threshold color change (default refreshFn)
    --    disabledFn      -- fn() returns true while the bar is off; disabledTip names the bar for its tooltip
    --    pageParent / pageTopY / pageBotY -- (required) the section's page frame and its Y range (pageBotY is
    --                       a fn, read when the editor first opens); the editor covers that range
    --    pageBotExtra    -- px the editor also covers below pageBotY (a row the page appends after the section)
    --    defaultR/G/B/A  -- default threshold color (new entries, the swatch and the band editor)
    --    roleShortcuts   -- bool: the spec picker offers All Healers / All Tanks / All DPS
    --    newEntry        -- fn(ids, barData) returns a new entry (default: thresholdPct 30 at the default color)
    --    partialDefault  -- bool: a default new entry covering a spender power (mana, energy, focus) colors below value
    --    thresholdField  -- the entry key the threshold input edits (default "thresholdPct")
    --    thresholdLabel  -- threshold row label (default "Threshold"); threshMin / threshMax its bounds (1 / 99)
    --    thresholdCog    -- { title, minWidth, rows = fn(CurEntry, RedrawDetail) }: a cog beside the threshold
    --    hashModeDefault -- what a missing entry.hashMode means (default "percent")
    --    hashWidthMax    -- Hash Width slider max (default 5)
    --    hashValueHint   -- localized hash input hint while lines sit by value (default "(Ex: 50000)")
    --    showBuffs       -- bool: Buff Colors row
    --    showSpenders    -- bool: Spender Colors row; spenderTip / spenderToggleTip its button / toggle tooltips
    --    textInsteadTip  -- tooltip of the Recolor Text Instead Of Bar toggle
    --    barInput        -- { label, field, min, max, default, letters }: a bar-wide number row, shown for
    --                       the entries whose rules set barInput
    --    entryRules      -- fn(ent, rules, barData) adjusts the selected entry's rules (see RefreshDetail)
    -- Returns settingsBtn (the button frame).
    local function BuildThresholdSettingsButton(conf)
        local parentRgn = conf.parentRgn
        local THR_FIELD = conf.thresholdField or "thresholdPct"
        local HASH_NIL = conf.hashModeDefault or "percent"
        local ROW_GAP = 6

        local defR = conf.defaultR or 1
        local defG = conf.defaultG or 0.2
        local defB = conf.defaultB or 0.2
        local defA = conf.defaultA or 1
        local _playerClassFile = select(2, UnitClass("player"))

        local BTN_W, BTN_H = 140, 30
        local settingsBtn = CreateFrame("Button", nil, parentRgn)
        Pix.Size(settingsBtn, BTN_W, BTN_H)
        Pix.Point(settingsBtn, "RIGHT", parentRgn, "RIGHT", -20, 0)
        settingsBtn:SetFrameLevel(parentRgn:GetFrameLevel() + 2)
        local btnBg = CludesUI.SolidTex(
            settingsBtn,
            "BACKGROUND",
            CludesUI.DD_BG_R,
            CludesUI.DD_BG_G,
            CludesUI.DD_BG_B,
            CludesUI.DD_BG_A
        )
        btnBg:SetAllPoints()
        settingsBtn._border = CludesUI.MakeRoundedBorder(settingsBtn, 1, 1, 1, CludesUI.DD_BRD_A, btnBg)
        local btnLbl = CludesUI.MakeFont(settingsBtn, 13, nil, 1, 1, 1)
        btnLbl:SetAlpha(CludesUI.DD_TXT_A)
        btnLbl:SetPoint("CENTER")
        btnLbl:SetText(CludesUI.L("Settings"))
        settingsBtn:SetScript("OnEnter", function(self)
            btnBg:SetColorTexture(CludesUI.DD_BG_R, CludesUI.DD_BG_G, CludesUI.DD_BG_B, CludesUI.DD_BG_HA)
            if self._border and self._border.SetColor then
                local t = self._borderTint or THR_BORDER_WHITE
                self._border:SetColor(t[1], t[2], t[3], 0.3)
            end
        end)
        settingsBtn:SetScript("OnLeave", function(self)
            btnBg:SetColorTexture(CludesUI.DD_BG_R, CludesUI.DD_BG_G, CludesUI.DD_BG_B, CludesUI.DD_BG_A)
            if self._border and self._border.SetColor then
                local t = self._borderTint or THR_BORDER_WHITE
                self._border:SetColor(t[1], t[2], t[3], CludesUI.DD_BRD_A)
            end
        end)
        -- disabled overlay
        local btnDis = CreateFrame("Frame", nil, parentRgn)
        btnDis:SetAllPoints(settingsBtn)
        btnDis:SetFrameLevel(settingsBtn:GetFrameLevel() + 5)
        btnDis:EnableMouse(true)
        btnDis:SetScript("OnEnter", function()
            CludesUI.ShowWidgetTooltip(settingsBtn, CludesUI.DisabledTooltip(conf.disabledTip or "this bar"))
        end)
        btnDis:SetScript("OnLeave", function()
            CludesUI.HideWidgetTooltip()
        end)
        local function UpdateBtnDis()
            local off = conf.disabledFn and conf.disabledFn()
            if off then
                btnDis:Show()
                settingsBtn:SetAlpha(0.3)
                if parentRgn._label then
                    parentRgn._label:SetAlpha(0.3)
                end
            else
                btnDis:Hide()
                settingsBtn:SetAlpha(1)
                if parentRgn._label then
                    parentRgn._label:SetAlpha(1)
                end
            end
        end
        settingsBtn:HookScript("OnShow", UpdateBtnDis)
        CludesUI.RegisterWidgetRefresh(UpdateBtnDis)
        UpdateBtnDis()

        -- Threshold notice badge; re-run by both refreshers below (every entry edit, add,
        -- delete and spec change) and after a hash commit
        local UpdateNotice = AttachThresholdNotice(settingsBtn, conf.getBarData)

        ThrWatchBuild()

        -- Editor page (lazy)
        local thrPage
        local specContainer
        local contentHalfSize
        local scrollTo -- the entry list's ScrollTo (AttachSmoothScrollbar)
        local _entryFrames = {}
        local _tempSpecSel = {} -- transient dropdown selection
        local _specDDRefresh
        local _selectedIdx -- selected entry; drives the right pane
        local _roleSpecs -- [role shortcut key] = its spec IDs
        local rules = {} -- the selected entry's rules, filled by RefreshDetail
        local RefreshDetail, RefreshSpecEntries
        local function RedrawDetail()
            if RefreshDetail then
                RefreshDetail()
            end
        end

        -- Does any entry claim specID (0 = All Specs; it claims every spec)?
        -- With onlyAll, only an All Specs entry counts.
        local function Claimed(specID, onlyAll)
            local bar = conf.getBarData()
            for _, entry in ipairs(bar and bar.thresholdSpecs or {}) do
                for _, id in ipairs(entry.specIDs or {}) do
                    if id == 0 or (not onlyAll and id == specID) then
                        return true
                    end
                end
            end
            return false
        end
        local function IsSpecClaimed(specID)
            return Claimed(specID)
        end
        local function HasAllSpecsEntry()
            return Claimed(nil, true)
        end

        -- The shared spec list (WoW Forever: one row per class, no role
        -- shortcuts), with what the entries already claim locked.
        local function BuildSpecItems()
            local items
            items, _roleSpecs = CludesUI.SpecPickItems({
                roles = conf.roleShortcuts,
                lockedFn = IsSpecClaimed,
                allLockedFn = HasAllSpecsEntry,
            })
            return items
        end

        -- Whether ids covers the spec being played (WoW Forever: a spec of the class).
        local function CoversPlayer(ids)
            local index = C_SpecializationInfo.GetSpecialization()
            local current = index and C_SpecializationInfo.GetSpecializationInfo(index)
            if not (current or CludesUI.IS_FOREVER) then
                return false
            end
            for _, id in ipairs(ids) do
                if id == 0 or id == current or (CludesUI.IS_FOREVER and CludesUI.IsPlayerSpec(id)) then
                    return true
                end
            end
            return false
        end
        local SPENDER_POWER = { MANA = true, FOCUS = true, ENERGY = true }

        -- A new entry: threshold on at its defaults, no hash lines.
        local function NewEntry(ids, bar)
            if conf.newEntry then
                return conf.newEntry(ids, bar)
            end
            local entry = {
                specIDs = ids,
                thresholdEnabled = true,
                thresholdPct = 30,
                thresholdPartialOnly = false,
                thresholdR = defR,
                thresholdG = defG,
                thresholdB = defB,
                thresholdA = defA,
                hashValues = "",
                hashMode = "percent",
                hashWidth = 1,
                hashColorR = 1,
                hashColorG = 1,
                hashColorB = 1,
                hashColorA = 0.7,
            }
            -- The power bar's "colour below the value": on for a spender power
            -- (mana, focus, energy: warn when low), off for a builder (warn
            -- when high). Only for an entry covering the spec being played,
            -- whose power type can be read.
            if conf.partialDefault and CoversPlayer(ids) then
                local _, token = UnitPowerType("player")
                if SPENDER_POWER[token] then
                    entry.thresholdPartialOnly = true
                end
            end
            return entry
        end

        -- One entry row's background and accent bar for the selection, in
        -- the current theme accent (a colour kept from creation goes stale).
        local function PaintRow(f)
            local selected = f._entryIdx ~= nil and _selectedIdx == f._entryIdx
            local accent = CludesUI.CLUDES_GREEN
            f._selected = selected
            f._accent:SetShown(selected)
            f._accent:SetColorTexture(accent.r, accent.g, accent.b, 1)
            if selected then
                f._bg:SetColorTexture(accent.r, accent.g, accent.b, 0.10)
            else
                f._bg:SetColorTexture(1, 1, 1, 0.02)
            end
        end
        local function RepaintRows()
            for _, f in ipairs(_entryFrames) do
                if f:IsShown() then
                    PaintRow(f)
                end
            end
        end

        local function BuildFrame()
            local hostFrame = conf.pageParent
            local INNERPAD = 10
            local ROW_H = 50
            local botY = conf.pageBotY() - (conf.pageBotExtra or 0)

            thrPage = CreateFrame("Frame", nil, hostFrame)
            Pix.Point(thrPage, "TOPLEFT", hostFrame, "TOPLEFT", CONTENT_PAD, conf.pageTopY)
            Pix.Point(thrPage, "TOPRIGHT", hostFrame, "TOPRIGHT", -CONTENT_PAD, conf.pageTopY)
            Pix.Point(thrPage, "BOTTOMLEFT", hostFrame, "TOPLEFT", CONTENT_PAD, botY)
            -- The unlock-mode cycle can leave this lazily-built frame with an undefined rect, so capture the resolved anchors: ToggleFrame re-asserts them before every Show to force a rect recompute.
            local _thrPts = {}
            for p = 1, thrPage:GetNumPoints() do
                _thrPts[p] = { thrPage:GetPoint(p) }
            end
            thrPage._reanchor = function()
                thrPage:ClearAllPoints()
                for p = 1, #_thrPts do
                    thrPage:SetPoint(unpack(_thrPts[p]))
                end
            end
            thrPage:SetFrameLevel(hostFrame:GetFrameLevel() + 50)
            thrPage:EnableMouse(true)
            -- Joins the spec / talent watcher while shown. A value being typed in the pane commits
            -- first, so the refresh never writes the saved value over it.
            local paneBoxes = {} -- [edit box] = true, filled by MakeInput
            local ed = {
                refresh = function()
                    local f = GetCurrentKeyBoardFocus()
                    if f and paneBoxes[f] then
                        f:ClearFocus()
                    end
                    RefreshSpecEntries()
                    RefreshDetail()
                end,
                repaint = RepaintRows,
                gen = PoolGen(thrPage),
            }
            thrPage:SetScript("OnShow", function(self)
                ThrEditorShown(self, ed)
            end)
            thrPage:SetScript("OnHide", ThrEditorHidden)
            local obg = thrPage:CreateTexture(nil, "BACKGROUND")
            obg:SetAllPoints()
            obg:SetColorTexture(13 / 255, 17 / 255, 25 / 255, 1)
            -- 1px center divider in the global BORDER style
            local div = thrPage:CreateTexture(nil, "ARTWORK")
            div:SetColorTexture(CludesUI.BORDER_R, CludesUI.BORDER_G, CludesUI.BORDER_B, 0.05)
            div:SetWidth(1)
            div:SetPoint("TOP", thrPage, "TOP", 0, 0)
            div:SetPoint("BOTTOM", thrPage, "BOTTOM", 0, 0)

            local totalH = thrPage:GetHeight()
            contentHalfSize = math.floor(thrPage:GetWidth() / 2 - (SIDE_PAD * 2))
            local BUTTON_W, BUTTON_H = 80, 29
            local MEDIA = "Interface\\AddOns\\CludesUI\\media\\"
            local eg = CludesUI.CLUDES_GREEN

            -- Back: the styled button (bg / border / label hover), the arrow leading its label
            local backBtn = CreateFrame("Button", nil, thrPage)
            Pix.Size(backBtn, BUTTON_W, BUTTON_H)
            Pix.Point(backBtn, "TOPLEFT", thrPage, "TOPLEFT", SIDE_PAD, -INNERPAD)
            backBtn:SetFrameLevel(thrPage:GetFrameLevel() + 2)
            local _, _, backLbl = CludesUI.MakeStyledButton(backBtn, "", 12, {
                0.062,
                0.070,
                0.082,
                0.50,
                0.100,
                0.110,
                0.124,
                0.50,
                1,
                1,
                1,
                0.12,
                1,
                1,
                1,
                0.22,
                1,
                1,
                1,
                0.55,
                1,
                1,
                1,
                0.85,
            }, function()
                thrPage:Hide()
            end)
            local backIcon = backBtn:CreateTexture(nil, "ARTWORK")
            backIcon:SetSize(14, 14)
            Pix.Point(backIcon, "LEFT", backBtn, "LEFT", 10, 0)
            backIcon:SetTexture(MEDIA .. "icons\\cui-arrow-left.png")
            backIcon:SetVertexColor(eg.r, eg.g, eg.b)
            backIcon:SetAlpha(0.6)
            if backIcon.SetSnapToPixelGrid then
                backIcon:SetSnapToPixelGrid(false)
                backIcon:SetTexelSnappingBias(0)
            end
            backLbl:ClearAllPoints()
            Pix.Point(backLbl, "LEFT", backIcon, "RIGHT", 6, 0)
            backLbl:SetText(CludesUI.L("Back"))
            backBtn:HookScript("OnEnter", function()
                backIcon:SetAlpha(0.85)
            end)
            backBtn:HookScript("OnLeave", function()
                backIcon:SetAlpha(0.6)
            end)

            -- Spec-assignment chrome: the spec dropdown + Add Specs, right of Back
            do
                local ADD_W, GAP_L = 90, 10
                local DD_W = contentHalfSize - (INNERPAD * 2) - BUTTON_W - ADD_W
                local ddRow = CreateFrame("Frame", nil, backBtn)
                ddRow:SetSize(DD_W, BUTTON_H)
                ddRow:SetPoint("TOPLEFT", backBtn, "TOPRIGHT", 10, 0)
                ddRow:SetFrameLevel(thrPage:GetFrameLevel() + 2)

                -- Spec dropdown (checkbox multi-select with search)
                local specItems = BuildSpecItems()
                local specDDHost = CreateFrame("Frame", nil, ddRow)
                specDDHost:SetSize(DD_W, BUTTON_H)
                specDDHost:SetPoint("LEFT", ddRow, "LEFT", 0, 0)
                specDDHost:SetFrameLevel(ddRow:GetFrameLevel())

                local cbDD, cbDDRefresh -- forward decl for closure access
                cbDD, cbDDRefresh = CludesUI.BuildVisOptsCBDropdown(
                    specDDHost,
                    DD_W,
                    specDDHost:GetFrameLevel() + 2,
                    specItems,
                    function(key)
                        -- Role shortcuts never show as "checked"
                        if _roleSpecs[key] then
                            return false
                        end
                        -- WoW Forever class row: checked while every spec of the class is selected
                        local fvIDs = CludesUI.IS_FOREVER and CludesUI.ForeverClassSpecIDs(key)
                        if fvIDs then
                            for i = 1, #fvIDs do
                                if not _tempSpecSel[fvIDs[i]] then
                                    return false
                                end
                            end
                            return true
                        end
                        return _tempSpecSel[key] or false
                    end,
                    function(key, val)
                        -- Role shortcuts + All Specs: select, then close the dropdown
                        local roleSpecs = _roleSpecs[key]
                        if roleSpecs then
                            wipe(_tempSpecSel)
                            for _, spellRef in ipairs(roleSpecs) do
                                _tempSpecSel[spellRef] = true
                            end
                            cbDD:Click()
                            if cbDDRefresh then
                                cbDDRefresh()
                            end
                            return
                        end
                        if key == 0 then
                            wipe(_tempSpecSel)
                            _tempSpecSel[0] = true
                            cbDD:Click()
                            if cbDDRefresh then
                                cbDDRefresh()
                            end
                            return
                        end
                        -- WoW Forever class row: selects or clears every spec of the class
                        local fvIDs = CludesUI.IS_FOREVER and CludesUI.ForeverClassSpecIDs(key)
                        if fvIDs then
                            if val then
                                _tempSpecSel[0] = nil
                            end
                            for i = 1, #fvIDs do
                                _tempSpecSel[fvIDs[i]] = val and true or nil
                            end
                            if cbDDRefresh then
                                cbDDRefresh()
                            end
                            return
                        end
                        if val then
                            _tempSpecSel[0] = nil
                            _tempSpecSel[key] = true
                        else
                            _tempSpecSel[key] = nil
                        end
                        if cbDDRefresh then
                            cbDDRefresh()
                        end
                    end,
                    nil,
                    10,
                    true
                )
                Pix.Point(cbDD, "LEFT", specDDHost, "LEFT", 0, 0)
                -- Dropdown label font 11px instead of the default 13
                for _, rgn2 in ipairs({ cbDD:GetRegions() }) do
                    if rgn2.SetFont and rgn2.GetText then
                        local f, _, fl = rgn2:GetFont()
                        if f then
                            rgn2:SetFont(f, 11, fl or "")
                        end
                        break
                    end
                end

                -- Replace "None" with placeholder text on the dropdown label
                local _origRefresh = cbDDRefresh
                local function WrappedRefresh()
                    _origRefresh()
                    for _, rgn2 in ipairs({ cbDD:GetRegions() }) do
                        if rgn2.GetText and CludesUI.EnKey(rgn2:GetText()) == "None" then
                            rgn2:SetText(CludesUI.L("Select a Spec..."))
                            break
                        end
                    end
                end
                _specDDRefresh = WrappedRefresh
                WrappedRefresh()

                local addBtn = CreateFrame("Button", nil, ddRow)
                Pix.Size(addBtn, ADD_W, BUTTON_H)
                addBtn:SetPoint("LEFT", specDDHost, "RIGHT", GAP_L, 0)
                addBtn:SetFrameLevel(ddRow:GetFrameLevel() + 2)
                local _, _, addLbl = CludesUI.MakeStyledButton(addBtn, "", 11, {
                    0.050,
                    0.058,
                    0.068,
                    0.92,
                    0.050,
                    0.058,
                    0.068,
                    0.92,
                    1,
                    1,
                    1,
                    0.4,
                    1,
                    1,
                    1,
                    0.6,
                    1,
                    1,
                    1,
                    0.5,
                    1,
                    1,
                    1,
                    0.7,
                }, function()
                    local edge = conf.getBarData()
                    if not edge then
                        return
                    end
                    local ids = {}
                    if _tempSpecSel[0] then
                        ids[1] = 0
                    else
                        for spellRef in pairs(_tempSpecSel) do
                            if spellRef ~= 0 then
                                ids[#ids + 1] = spellRef
                            end
                        end
                    end
                    if #ids == 0 then
                        return
                    end
                    if not edge.thresholdSpecs then
                        edge.thresholdSpecs = {}
                    end
                    edge.thresholdSpecs[#edge.thresholdSpecs + 1] = NewEntry(ids, edge)
                    _selectedIdx = #edge.thresholdSpecs
                    wipe(_tempSpecSel)
                    WrappedRefresh()
                    RefreshSpecEntries(true)
                    RedrawDetail()
                    conf.refreshFn()
                end)
                addLbl:SetText(CludesUI.L("Add Specs"))
            end

            -- Scrollable entry container
            local specContainerH = totalH - (INNERPAD * 3) - BUTTON_H
            specContainer = CreateFrame("Frame", nil, backBtn)
            specContainer:SetFrameStrata("DIALOG")
            specContainer:SetFrameLevel(200)
            Pix.Point(specContainer, "TOPLEFT", thrPage, "TOPLEFT", SIDE_PAD, -ROW_H)
            Pix.Size(specContainer, contentHalfSize, specContainerH)

            local backdrop = specContainer:CreateTexture(nil, "BACKGROUND")
            backdrop:SetAllPoints()
            backdrop:SetColorTexture(0.062, 0.070, 0.082, 0.95)
            -- clip: list rows scrolled to an edge keep the round corners.
            CludesUI.MakeRoundedBorder(specContainer, 1, 1, 1, 0.15, backdrop, nil, true)

            local scrollFrame = CreateFrame("ScrollFrame", nil, specContainer)
            scrollFrame:SetPoint("TOPLEFT", specContainer, "TOPLEFT", 1, -2)
            scrollFrame:SetPoint("TOPRIGHT", specContainer, "TOPRIGHT", -1, -2)
            scrollFrame:SetPoint("BOTTOMRIGHT", specContainer, "BOTTOMRIGHT", -1, 1)
            scrollFrame:SetFrameLevel(specContainer:GetFrameLevel() + 1)

            local scrollChild = CreateFrame("Frame", nil, scrollFrame)
            scrollChild:SetWidth(contentHalfSize)
            scrollFrame:SetScrollChild(scrollChild)
            specContainer._scrollChild = scrollChild
            specContainer._scrollFrame = scrollFrame

            -- Thin scrollbar on the container edge, shown on overflow; while the list fits, the wheel
            -- scrolls the page, and Shift + wheel scales the panel as everywhere in it
            scrollTo = select(
                2,
                CludesUI.AttachSmoothScrollbar(scrollFrame, {
                    child = scrollChild,
                    trackParent = specContainer,
                    panelWheel = true,
                    passWheel = true,
                    step = 30,
                    width = 4,
                    thumbMin = 20,
                    rightInset = 3,
                    topInset = 4,
                    level = 10,
                    trackAlpha = 0.04,
                    thumbAlpha = 0.15,
                })
            )

            -- Right detail pane: config for the selected entry
            local detailC = CreateFrame("Frame", nil, thrPage)
            detailC:SetFrameStrata("DIALOG")
            detailC:SetFrameLevel(200)
            -- The right side has no header row, so it starts at the top
            Pix.Point(detailC, "TOPRIGHT", thrPage, "TOPRIGHT", -SIDE_PAD, -INNERPAD)
            Pix.Size(detailC, contentHalfSize, specContainerH + (ROW_H - INNERPAD))
            local dBg = detailC:CreateTexture(nil, "BACKGROUND")
            dBg:SetAllPoints()
            dBg:SetColorTexture(0.062, 0.070, 0.082, 0.95)
            CludesUI.MakeRoundedBorder(detailC, 1, 1, 1, 0.15, dBg)
            detailC:EnableMouse(true)

            local DPAD = 16
            local DLVL = detailC:GetFrameLevel() + 2
            local ROWH = 26
            local ROWGAP = 12
            local MEDIAF = CludesUI.GetFontPath("main") or "Fonts\\FRIZQT__.TTF"

            -- Shown when nothing is selected
            local dPlaceholder = CludesUI.MakeFont(detailC, 13, nil, 1, 1, 1)
            dPlaceholder:SetAlpha(0.4)
            dPlaceholder:SetPoint("CENTER")
            dPlaceholder:SetText(CludesUI.L("Select or add an entry"))

            -- The live currently-selected entry, or nil
            local function CurEntry()
                local edge = conf.getBarData()
                if not edge or not edge.thresholdSpecs then
                    return nil
                end
                return _selectedIdx and edge.thresholdSpecs[_selectedIdx] or nil
            end

            local _allRows = {}
            -- Labeled row frame, registered for the layout pass
            local function DRow(labelText, hgt)
                local rf = CreateFrame("Frame", nil, detailC)
                rf:SetFrameLevel(DLVL)
                rf._rawH = hgt or ROWH
                Pix.Height(rf, rf._rawH)
                if labelText then
                    local labelFS = CludesUI.MakeFont(rf, 13, nil, 1, 1, 1)
                    labelFS:SetAlpha(0.6)
                    labelFS:SetPoint("LEFT", rf, "LEFT", 0, 0)
                    labelFS:SetText(CludesUI.L(labelText))
                    rf._lbl = labelFS
                end
                _allRows[#_allRows + 1] = rf
                return rf
            end

            -- Value edit boxes (hash / threshold)
            local function MakeInput(rowParent, wid, numeric)
                local ib = CreateFrame("EditBox", nil, rowParent)
                paneBoxes[ib] = true
                Pix.Size(ib, wid, 22)
                ib:SetFrameLevel(rowParent:GetFrameLevel() + 3)
                ib:SetAutoFocus(false)
                ib:SetFont(MEDIAF, 12, "")
                ib:SetTextColor(1, 1, 1, 0.75)
                ib:SetJustifyH("CENTER")
                if numeric then
                    ib:SetNumeric(true)
                end
                local ibg = ib:CreateTexture(nil, "BACKGROUND")
                ibg:SetAllPoints()
                ibg:SetColorTexture(0.12, 0.12, 0.12, 0.8)
                CludesUI.MakeRoundedBorder(ib, 1, 1, 1, 0.08, ibg)
                return ib
            end

            -- Greys a row's controls and explains why (tooltip in blocker._tip), shown by RefreshDetail
            local function MakeBlocker(row, fromRgn, toRgn, inset, lvl)
                local blocker = CreateFrame("Frame", nil, row)
                blocker:SetPoint("TOPLEFT", fromRgn, "TOPLEFT", -inset, 3)
                blocker:SetPoint("BOTTOMRIGHT", toRgn, "BOTTOMRIGHT", 3, -3)
                blocker:SetFrameLevel(row:GetFrameLevel() + lvl)
                blocker:EnableMouse(true)
                local tex = blocker:CreateTexture(nil, "OVERLAY")
                tex:SetAllPoints()
                tex:SetColorTexture(0.062, 0.070, 0.082, 0.7)
                blocker:SetScript("OnEnter", function(self)
                    CludesUI.ShowWidgetTooltip(self, self._tip)
                end)
                blocker:SetScript("OnLeave", function()
                    CludesUI.HideWidgetTooltip()
                end)
                blocker:Hide()
                return blocker
            end

            -- Row: Talent gate (single-spec entries only)
            local talentRow = DRow("Talent", ROWH)
            talentRow._talentValues = { _menuOpts = { searchable = true, parent = thrPage } }
            talentRow._talentOrder = {}
            local talentDD = CludesUI.BuildDropdownControl(
                talentRow,
                170,
                talentRow:GetFrameLevel() + 2,
                talentRow._talentValues,
                talentRow._talentOrder,
                function()
                    local ent = CurEntry()
                    if not ent then
                        return 0
                    end
                    return ent.talentSpellID or 0
                end,
                function(key)
                    local ent = CurEntry()
                    if not ent then
                        return
                    end
                    if key == 0 then
                        ent.talentSpellID = nil
                        ent.talentName = nil
                    else
                        ent.talentSpellID = key
                        ent.talentName = talentRow._talentValues[key]
                    end
                    conf.rebuildFn()
                    if talentRow._talentDD and talentRow._talentDD._refreshLabel then
                        talentRow._talentDD._refreshLabel()
                    end
                    -- Relabel + re-dim duplicate entries live
                    RefreshSpecEntries()
                end,
                function(key)
                    local ent = CurEntry()
                    if not ent then
                        return false
                    end
                    local edge = conf.getBarData()
                    if not edge or not edge.thresholdSpecs then
                        return false
                    end
                    local wantGate = (key ~= 0) and key or nil
                    for i, other in ipairs(edge.thresholdSpecs) do
                        if i ~= _selectedIdx then
                            local og = other.talentSpellID
                            local sameGate = (wantGate == nil and og == nil)
                                or (wantGate ~= nil and og == wantGate)
                            if sameGate and mod.SpecsConflict(ent.specIDs, other.specIDs) then
                                return CludesUI.L("Already used by another card for this spec")
                            end
                        end
                    end
                    return false
                end
            )
            talentDD:SetHeight(22)
            talentDD:SetPoint("RIGHT", talentRow, "RIGHT", 0, 0)
            talentRow._talentDD = talentDD
            -- Keep the menu above the cog popups
            talentDD:HookScript("OnClick", function()
                local m = talentDD._ddMenu
                if m then
                    m:SetFrameStrata("TOOLTIP")
                end
            end)
            talentDD:HookScript("OnHide", function()
                talentDD._invalidateMenu()
            end)
            -- Greys the picker for a spec of a class the player is not playing (its talents are not in the loadout)
            local talentDis = CreateFrame("Frame", nil, talentRow)
            talentDis:SetPoint("TOPLEFT", talentDD, "TOPLEFT", 0, 0)
            talentDis:SetPoint("BOTTOMRIGHT", talentDD, "BOTTOMRIGHT", 0, 0)
            talentDis:SetFrameLevel(talentDD:GetFrameLevel() + 10)
            talentDis:EnableMouse(true)
            local talentDisTex = talentDis:CreateTexture(nil, "OVERLAY")
            talentDisTex:SetAllPoints()
            talentDisTex:SetColorTexture(0.062, 0.070, 0.082, 0.6)
            talentDis:SetScript("OnEnter", function()
                CludesUI.ShowWidgetTooltip(
                    talentDis,
                    CludesUI.L("Talent gating is only available while playing this spec's class")
                )
            end)
            talentDis:SetScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)
            talentDis:Hide()
            talentRow._dis = talentDis

            -- Row: Hash values ("Hash at X" + hint + input + swatch + style cog)
            local hashRow = DRow(nil, ROWH)
            local hashLbl = CludesUI.MakeFont(hashRow, 13, nil, 1, 1, 1)
            hashLbl:SetAlpha(0.6)
            hashLbl:SetPoint("LEFT", hashRow, "LEFT", 0, 0)
            hashRow._lbl2 = hashLbl
            local hashModeRow = {
                type = "toggle",
                label = "Position by percent",
                get = function()
                    local ent = CurEntry()
                    return ((ent and ent.hashMode) or HASH_NIL) == "percent"
                end,
                set = function(v)
                    local ent = CurEntry()
                    if not ent then
                        return
                    end
                    ent.hashMode = v and "percent" or "value"
                    conf.rebuildFn()
                    RedrawDetail()
                end,
            }
            if conf.entryRules then
                -- Pip resources place their lines by stack count
                hashModeRow.disabled = function()
                    return rules.pips
                end
                hashModeRow.disabledTooltip = "Bar-type resources only (pips use stack counts)"
            end
            -- Style cog, pinned inside the row's right edge
            local hashCogBtn = CludesUI.BuildInlineCog(hashRow, {
                title = "Hash Line Style",
                bgAlpha = 1,
                frameStrata = "FULLSCREEN_DIALOG",
                frameLevel = 500,
                rows = {
                    hashModeRow,
                    {
                        type = "slider",
                        label = "Hash Width",
                        min = 1,
                        max = conf.hashWidthMax or 5,
                        step = 1,
                        get = function()
                            local ent = CurEntry()
                            return ent and ent.hashWidth or 1
                        end,
                        set = function(v)
                            local ent = CurEntry()
                            if ent then
                                ent.hashWidth = v
                                conf.rebuildFn()
                            end
                        end,
                    },
                },
                size = 20,
                anchorTo = hashRow,
                relPoint = "RIGHT",
                gap = 0,
            })
            local hashSwatch, hashSwatchSnap = CludesUI.BuildColorSwatch(
                hashRow,
                hashRow:GetFrameLevel() + 4,
                function()
                    local ent = CurEntry()
                    if not ent then
                        return 1, 1, 1, 0.7
                    end
                    return ent.hashColorR or 1,
                        ent.hashColorG or 1,
                        ent.hashColorB or 1,
                        ent.hashColorA or 0.7
                end,
                function(r, g, b, a)
                    local ent = CurEntry()
                    if not ent then
                        return
                    end
                    ent.hashColorR, ent.hashColorG, ent.hashColorB, ent.hashColorA = r, g, b, a
                    conf.rebuildFn()
                end,
                true,
                19
            )
            hashSwatch:SetPoint("RIGHT", hashCogBtn, "LEFT", -8, 0)
            local hashInput = MakeInput(hashRow, 120, false)
            hashInput:SetPoint("RIGHT", hashSwatch, "LEFT", -8, 0)
            local hashHint = CludesUI.MakeFont(hashRow, 10, nil, 1, 1, 1)
            hashHint:SetAlpha(0.35)
            hashHint:SetPoint("RIGHT", hashInput, "LEFT", -8, 0)
            hashRow._hint = hashHint
            hashInput:SetScript("OnEditFocusLost", function(self)
                if self._cancelCommit then
                    self._cancelCommit = nil
                    return
                end
                local ent = CurEntry()
                if not ent then
                    return
                end
                -- Only the numeric positions are kept, so text that draws no line never counts as configured
                ent.hashValues = SanitizePositions(self:GetText(), true)
                self:SetText(ent.hashValues)
                conf.rebuildFn()
                UpdateNotice()
            end)
            hashInput:SetScript("OnEnterPressed", function(self)
                self:ClearFocus()
            end)
            hashInput:SetScript("OnEscapePressed", function(self)
                self._cancelCommit = true
                local ent = CurEntry()
                self:SetText(ent and ent.hashValues or "")
                self:ClearFocus()
            end)

            -- Row: Threshold (enable toggle + input + swatch [+ cog])
            local threshRow = DRow(conf.thresholdLabel or "Threshold", ROWH)
            local threshCogBtn
            local tc = conf.thresholdCog
            if tc then
                threshCogBtn = CludesUI.BuildInlineCog(threshRow, {
                    title = tc.title,
                    bgAlpha = 1,
                    frameStrata = "FULLSCREEN_DIALOG",
                    frameLevel = 500,
                    minWidth = tc.minWidth,
                    rows = tc.rows(CurEntry, RedrawDetail),
                    size = 20,
                    anchorTo = threshRow,
                    relPoint = "RIGHT",
                    gap = 0,
                })
            end
            local threshEnable, _, threshEnableSnap = CludesUI.BuildToggleControl(
                threshRow,
                DLVL + 4,
                function()
                    local ent = CurEntry()
                    if not ent then
                        return false
                    end
                    if ent.thresholdEnabled == nil then
                        return true
                    end
                    return ent.thresholdEnabled
                end,
                function(v)
                    local ent = CurEntry()
                    if not ent then
                        return
                    end
                    ent.thresholdEnabled = v
                    conf.refreshFn()
                    RedrawDetail()
                end,
                { sizeRatio = 0.95 }
            )
            -- The entry's own color, else the bar-wide one the bar falls back to
            local threshSwatch, threshSwatchSnap = CludesUI.BuildColorSwatch(
                threshRow,
                threshRow:GetFrameLevel() + 4,
                function()
                    local ent = CurEntry()
                    if not ent then
                        return defR, defG, defB, defA
                    end
                    local edge = conf.getBarData()
                    return ent.thresholdR or edge.thresholdR or defR,
                        ent.thresholdG or edge.thresholdG or defG,
                        ent.thresholdB or edge.thresholdB or defB,
                        ent.thresholdA or edge.thresholdA or defA
                end,
                function(r, g, b, a)
                    local ent = CurEntry()
                    if not ent then
                        return
                    end
                    ent.thresholdR, ent.thresholdG, ent.thresholdB, ent.thresholdA = r, g, b, a
                    if conf.swatchRefreshFn then
                        conf.swatchRefreshFn()
                    else
                        conf.refreshFn()
                    end
                end,
                true,
                19
            )
            if threshCogBtn then
                threshSwatch:SetPoint("RIGHT", threshCogBtn, "LEFT", -8, 0)
            else
                threshSwatch:SetPoint("RIGHT", threshRow, "RIGHT", 0, 0)
            end
            local threshInput = MakeInput(threshRow, 50, true)
            threshInput:SetPoint("RIGHT", threshSwatch, "LEFT", -8, 0)
            threshEnable:SetPoint("RIGHT", threshInput, "LEFT", -8, 0)
            -- Bounds and default come from the selected entry's rules
            threshInput:SetScript("OnEditFocusLost", function(self)
                if self._cancelCommit then
                    self._cancelCommit = nil
                    return
                end
                local ent = CurEntry()
                if not ent then
                    return
                end
                local val = tonumber(self:GetText())
                if not val then
                    self:SetText(tostring(ent[THR_FIELD] or rules.thrDef))
                    return
                end
                val = math.max(rules.thrMin, math.min(rules.thrMax, math.floor(val + 0.5)))
                self:SetText(tostring(val))
                ent[THR_FIELD] = val
                conf.refreshFn()
            end)
            threshInput:SetScript("OnEnterPressed", function(self)
                self:ClearFocus()
            end)
            threshInput:SetScript("OnEscapePressed", function(self)
                self._cancelCommit = true
                local ent = CurEntry()
                self:SetText(tostring((ent and ent[THR_FIELD]) or rules.thrDef))
                self:ClearFocus()
            end)
            -- The entry's note on its bounds (rules.thrTip), if any
            threshInput:SetScript("OnEnter", function(self)
                if self._tip then
                    CludesUI.ShowWidgetTooltip(self, self._tip)
                end
            end)
            threshInput:SetScript("OnLeave", function(self)
                if self._tip then
                    CludesUI.HideWidgetTooltip()
                end
            end)
            -- Greys the threshold input + swatch (label kept) while the threshold is off or replaced by multi-band
            local threshDis = CreateFrame("Frame", nil, threshRow)
            threshDis:SetPoint("TOPLEFT", threshInput, "TOPLEFT", -2, 3)
            threshDis:SetPoint("BOTTOMRIGHT", threshSwatch, "BOTTOMRIGHT", 3, -3)
            threshDis:SetFrameLevel(threshRow:GetFrameLevel() + 6)
            threshDis:EnableMouse(true)
            local threshDisTex = threshDis:CreateTexture(nil, "OVERLAY")
            threshDisTex:SetAllPoints()
            threshDisTex:SetColorTexture(0.062, 0.070, 0.082, 0.7)
            threshDis:SetScript("OnEnter", function()
                local tipText = (threshRow._disTip == "MULTI") and BAND_REPLACES_TIP
                    or CludesUI.DisabledTooltip("Threshold Color")
                CludesUI.ShowWidgetTooltip(threshDis, tipText)
            end)
            threshDis:SetScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)

            -- Row: Multi-band (toggle + Bands editor button)
            local multiRow = DRow("Multi-band Coloring", ROWH)
            local bandsBtn = CreateFrame("Button", nil, multiRow)
            Pix.Size(bandsBtn, 60, 22)
            bandsBtn:SetPoint("RIGHT", multiRow, "RIGHT", 0, 0)
            bandsBtn:SetFrameLevel(multiRow:GetFrameLevel() + 4)
            SkinCardButton(bandsBtn, CludesUI.L("Bands"), BAND_HELP_TIP)
            bandsBtn:SetScript("OnClick", function(self)
                if not CurEntry() then
                    return
                end
                ShowBandEditor({
                    getBarData = conf.getBarData,
                    refreshFn = conf.refreshFn,
                    entryIdx = _selectedIdx,
                    anchor = self,
                    countBased = rules.pips,
                    lockPercent = rules.bandPctCap ~= nil,
                    percentMax = rules.bandPctCap,
                    defR = defR,
                    defG = defG,
                    defB = defB,
                    defA = defA,
                })
            end)
            local multiToggle, _, multiSnap = CludesUI.BuildToggleControl(multiRow, DLVL + 4, function()
                local ent = CurEntry()
                return ent and ent.multiBandEnabled or false
            end, function(v)
                local ent = CurEntry()
                if not ent then
                    return
                end
                ent.multiBandEnabled = v
                conf.refreshFn()
                RedrawDetail()
            end, { sizeRatio = 0.95 })
            multiToggle:SetPoint("RIGHT", bandsBtn, "LEFT", -10, 0)
            multiToggle:HookScript("OnEnter", function(self)
                CludesUI.ShowWidgetTooltip(self, BAND_HELP_TIP)
            end)
            multiToggle:HookScript("OnLeave", function()
                CludesUI.HideWidgetTooltip()
            end)
            -- Covers the toggle + Bands button when multi-band cannot apply (rules.multiBlock)
            local multiDis = MakeBlocker(multiRow, multiToggle, bandsBtn, 3, 8)

            -- Row: Buff colors (toggle + Buffs editor button). First active buff wins and overrides threshold coloring.
            local buffRow, buffSnap
            if conf.showBuffs then
                buffRow = DRow("Buff Colors", ROWH)
                local buffsBtn = CreateFrame("Button", nil, buffRow)
                Pix.Size(buffsBtn, 60, 22)
                buffsBtn:SetPoint("RIGHT", buffRow, "RIGHT", 0, 0)
                buffsBtn:SetFrameLevel(buffRow:GetFrameLevel() + 4)
                SkinCardButton(buffsBtn, CludesUI.L("Buffs"), BUFF_HELP_TIP)
                buffsBtn:SetScript("OnClick", function(self)
                    if not CurEntry() then
                        return
                    end
                    ShowBuffEditor({
                        getBarData = conf.getBarData,
                        refreshFn = conf.refreshFn,
                        entryIdx = _selectedIdx,
                        anchor = self,
                    })
                end)
                local buffToggle
                buffToggle, _, buffSnap = CludesUI.BuildToggleControl(buffRow, DLVL + 4, function()
                    local ent = CurEntry()
                    return ent and ent.buffColorEnabled or false
                end, function(v)
                    local ent = CurEntry()
                    if not ent then
                        return
                    end
                    ent.buffColorEnabled = v
                    conf.refreshFn()
                end, { sizeRatio = 0.95 })
                buffToggle:SetPoint("RIGHT", buffsBtn, "LEFT", -10, 0)
                buffToggle:HookScript("OnEnter", function(self)
                    CludesUI.ShowWidgetTooltip(self, BUFF_HELP_TIP)
                end)
                buffToggle:HookScript("OnLeave", function()
                    CludesUI.HideWidgetTooltip()
                end)
            end

            -- Row: Spender colors (toggle + Spenders editor button). First castable spell wins.
            local spenderRow, spenderSnap
            if conf.showSpenders then
                local spTip = conf.spenderTip or SPENDER_HELP_TIP
                local spToggleTip = conf.spenderToggleTip or spTip
                spenderRow = DRow("Spender Colors", ROWH)
                local spBtn = CreateFrame("Button", nil, spenderRow)
                Pix.Size(spBtn, 60, 22)
                spBtn:SetPoint("RIGHT", spenderRow, "RIGHT", 0, 0)
                spBtn:SetFrameLevel(spenderRow:GetFrameLevel() + 4)
                SkinCardButton(spBtn, CludesUI.L("Spenders"), spTip)
                spBtn:SetScript("OnClick", function(self)
                    if not CurEntry() then
                        return
                    end
                    ShowSpenderEditor({
                        getBarData = conf.getBarData,
                        refreshFn = conf.refreshFn,
                        entryIdx = _selectedIdx,
                        anchor = self,
                    })
                end)
                local spToggle
                spToggle, _, spenderSnap = CludesUI.BuildToggleControl(spenderRow, DLVL + 4, function()
                    local ent = CurEntry()
                    return ent and ent.spenderColorEnabled or false
                end, function(v)
                    local ent = CurEntry()
                    if not ent then
                        return
                    end
                    ent.spenderColorEnabled = v
                    conf.refreshFn()
                end, { sizeRatio = 0.95 })
                spToggle:SetPoint("RIGHT", spBtn, "LEFT", -10, 0)
                spToggle:HookScript("OnEnter", function(self)
                    CludesUI.ShowWidgetTooltip(self, spToggleTip)
                end)
                spToggle:HookScript("OnLeave", function()
                    CludesUI.HideWidgetTooltip()
                end)
            end

            -- Row: Recolor text instead of bar (per entry)
            local textInsteadRow = DRow("Recolor Text Instead Of Bar", ROWH)
            local textInsteadToggle, _, textInsteadSnap = CludesUI.BuildToggleControl(
                textInsteadRow,
                DLVL + 4,
                function()
                    local ent = CurEntry()
                    return ent and ent.thresholdTextInstead or false
                end,
                function(v)
                    local ent = CurEntry()
                    if ent then
                        ent.thresholdTextInstead = v
                        conf.refreshFn()
                    end
                end,
                { sizeRatio = 0.95 }
            )
            textInsteadToggle:SetPoint("RIGHT", textInsteadRow, "RIGHT", 0, 0)
            if conf.textInsteadTip then
                textInsteadToggle:HookScript("OnEnter", function(self)
                    CludesUI.ShowWidgetTooltip(self, conf.textInsteadTip)
                end)
                textInsteadToggle:HookScript("OnLeave", function()
                    CludesUI.HideWidgetTooltip()
                end)
            end
            -- Covers the row when recoloring the text can have no effect (rules.textBlock)
            local textInsteadDis = MakeBlocker(textInsteadRow, textInsteadRow, textInsteadToggle, 2, 6)

            -- Row: a bar-wide number (cfg.barInput), placed only for the entries whose rules ask for it
            local barRow, barSnap
            local bi = conf.barInput
            if bi then
                barRow = DRow(bi.label, ROWH)
                local barInput = MakeInput(barRow, 50, true)
                barInput:SetPoint("RIGHT", barRow, "RIGHT", 0, 0)
                if bi.letters then
                    barInput:SetMaxLetters(bi.letters)
                end
                barSnap = function()
                    local edge = conf.getBarData()
                    barInput:SetText(tostring((edge and edge[bi.field]) or bi.default))
                end
                barInput:SetScript("OnEditFocusLost", function(self)
                    if self._cancelCommit then
                        self._cancelCommit = nil
                        return
                    end
                    local edge = conf.getBarData()
                    if not edge then
                        return
                    end
                    local v = tonumber(self:GetText())
                    if v then
                        edge[bi.field] = math.max(bi.min, math.min(bi.max, math.floor(v + 0.5)))
                        conf.refreshFn()
                    end
                    barSnap()
                end)
                barInput:SetScript("OnEnterPressed", function(self)
                    self:ClearFocus()
                end)
                barInput:SetScript("OnEscapePressed", function(self)
                    self._cancelCommit = true
                    self:ClearFocus()
                    barSnap()
                end)
            end

            -- RefreshDetail: repaint the pane for the selected entry
            RefreshDetail = function()
                UpdateNotice()
                local ent = CurEntry()
                if not ent then
                    for _, rf in ipairs(_allRows) do
                        rf:Hide()
                    end
                    dPlaceholder:Show()
                    return
                end
                dPlaceholder:Hide()

                -- The entry's rules: the bar's defaults, then cfg.entryRules adjusts them per entry.
                --   thrMin / thrMax / thrDef -- threshold bounds and the default value
                --   thrLabel / thrTip -- threshold row label (nil keeps the static one) and input note
                --   pips       -- entry counts stacks: hash lines by stack, band boundaries as counts
                --   hideHash   -- no hash row for this entry
                --   bandPctCap -- the band editor is percent only, up to this value
                --   multiBlock / textBlock -- why multi-band / text recoloring cannot apply (nil = it can)
                --   barInput   -- show the cfg.barInput row
                local r = rules
                r.thrMin, r.thrMax, r.thrDef = conf.threshMin or 1, conf.threshMax or 99, 30
                r.thrLabel, r.thrTip, r.pips, r.hideHash = nil, nil, false, false
                r.bandPctCap, r.multiBlock, r.textBlock, r.barInput = nil, nil, nil, false
                if conf.entryRules then
                    conf.entryRules(ent, r, conf.getBarData())
                end

                -- Talent gate is single-spec only
                local ids = ent.specIDs
                local allowTalent = (ids and #ids == 1 and ids[1] ~= 0) and true or false

                -- Refill talent options from the active loadout plus the entry's saved gate, even if off-spec/off-loadout
                if allowTalent then
                    local loadoutTalents = (mod.GetLoadoutTalents()) or {}
                    local vals, ord = talentRow._talentValues, talentRow._talentOrder
                    wipe(ord)
                    for k in pairs(vals) do
                        if k ~= "_menuOpts" then
                            vals[k] = nil
                        end
                    end
                    vals[0] = CludesUI.L("No talent")
                    ord[#ord + 1] = 0
                    for _, t in ipairs(loadoutTalents) do
                        if vals[t.spellID] == nil then
                            ord[#ord + 1] = t.spellID
                        end
                        vals[t.spellID] = t.name
                    end
                    if ent.talentSpellID and vals[ent.talentSpellID] == nil then
                        vals[ent.talentSpellID] = ent.talentName
                            or C_Spell.GetSpellName(ent.talentSpellID)
                            or ("Spell " .. ent.talentSpellID)
                        ord[#ord + 1] = ent.talentSpellID
                    end
                    if talentDD._invalidateMenu then
                        talentDD._invalidateMenu()
                    end
                    if talentDD._refreshLabel then
                        talentDD._refreshLabel()
                    end

                    -- Talents come from the player's own loadout, so block the picker for other classes' specs
                    local talentClassOK = true
                    if GetSpecializationInfoByID then
                        local _, _, _, _, _, class = GetSpecializationInfoByID(ids[1])
                        talentClassOK = (class == _playerClassFile)
                    elseif CludesUI.IS_FOREVER then
                        talentClassOK = (CludesUI.SpecClassOf(ids[1]) == _playerClassFile)
                    end
                    talentRow._dis:SetShown(not talentClassOK)
                end

                -- Hash row text: pip resources place lines by stack count
                local hashWord, hintText
                if r.pips then
                    hashWord, hintText = CludesUI.L("Stack"), CludesUI.L("(Ex: 2,4)")
                else
                    local isPct = (ent.hashMode or HASH_NIL) == "percent"
                    hashWord = isPct and CludesUI.L("Percent") or CludesUI.L("Value")
                    hintText = isPct and CludesUI.L("(Ex: 25,50,75)")
                        or conf.hashValueHint
                        or CludesUI.L("(Ex: 50000)")
                end
                hashRow._lbl2:SetText(CludesUI.Lf("Hash at %1$s", hashWord))
                hashRow._hint:SetText(hintText)
                hashInput:SetText(ent.hashValues or "")

                threshInput:SetText(tostring(ent[THR_FIELD] or r.thrDef))
                threshInput._tip = r.thrTip
                if r.thrLabel then
                    threshRow._lbl:SetText(r.thrLabel)
                end

                hashSwatchSnap()
                threshEnableSnap()
                threshSwatchSnap()
                multiSnap()
                textInsteadSnap()
                if buffSnap then
                    buffSnap()
                end
                if spenderSnap then
                    spenderSnap()
                end
                if barSnap then
                    barSnap()
                end

                -- Single threshold and multi-band are independent toggles; multi wins over single when both are on.
                local entEnabled = ent.thresholdEnabled
                if entEnabled == nil then
                    entEnabled = true
                end
                local multiOn = (ent.multiBandEnabled and not r.multiBlock) and true or false
                if r.multiBlock then
                    multiToggle:SetAlpha(0.35)
                    multiToggle:SetEnabled(false)
                    bandsBtn:SetAlpha(0.35)
                    bandsBtn:SetEnabled(false)
                    multiRow._lbl:SetAlpha(0.3)
                    multiDis._tip = r.multiBlock
                    multiDis:Show()
                else
                    multiToggle:SetAlpha(1)
                    multiToggle:SetEnabled(true)
                    bandsBtn:SetAlpha(multiOn and 1 or 0.35)
                    bandsBtn:SetEnabled(multiOn)
                    multiRow._lbl:SetAlpha(0.6)
                    multiDis:Hide()
                end
                if multiOn then
                    threshRow._disTip = "MULTI"
                    threshDis:Show()
                elseif not entEnabled then
                    threshRow._disTip = nil
                    threshDis:Show()
                else
                    threshDis:Hide()
                end
                textInsteadDis._tip = r.textBlock
                textInsteadDis:SetShown(r.textBlock ~= nil)
                textInsteadRow._lbl:SetAlpha(r.textBlock and 0.3 or 0.6)

                -- Layout pass: place visible rows top-to-bottom
                for _, rf in ipairs(_allRows) do
                    rf:Hide()
                end
                local yy = -DPAD
                local function place(rf)
                    rf:ClearAllPoints()
                    Pix.Point(rf, "TOPLEFT", detailC, "TOPLEFT", DPAD, yy)
                    Pix.Point(rf, "TOPRIGHT", detailC, "TOPRIGHT", -DPAD, yy)
                    rf:Show()
                    yy = yy - (rf._rawH or ROWH) - ROWGAP
                end
                if allowTalent then
                    place(talentRow)
                end
                if not r.hideHash then
                    place(hashRow)
                end
                place(threshRow)
                place(multiRow)
                if buffRow then
                    place(buffRow)
                end
                if spenderRow then
                    place(spenderRow)
                end
                place(textInsteadRow)
                if barRow and r.barInput then
                    place(barRow)
                end
            end
            thrPage:Hide()
        end -- BuildFrame

        -- BuildFrame runs lazily on the first ToggleFrame open, not here

        -- Build/Refresh dynamic entry frames
        RefreshSpecEntries = function(scrollToSel)
            UpdateNotice()
            if not specContainer then
                return
            end
            local edge = conf.getBarData()
            if not edge then
                return
            end
            if not edge.thresholdSpecs then
                edge.thresholdSpecs = {}
            end
            local entries = edge.thresholdSpecs

            -- The entry the resolver actually picks in-game right now; seeds the default selection so it opens pre-selected
            local activeIdx
            do
                local resolved = _G._CURB_ResolveThresholdSpecEntry(edge)
                if resolved then
                    for i = 1, #entries do
                        if entries[i] == resolved then
                            activeIdx = i
                            break
                        end
                    end
                end
            end

            -- Resolve/clamp the selection: active entry, else the first
            if #entries == 0 then
                _selectedIdx = nil
            else
                if _selectedIdx and _selectedIdx > #entries then
                    _selectedIdx = #entries
                end
                if not _selectedIdx or _selectedIdx < 1 then
                    _selectedIdx = activeIdx or 1
                end
            end

            local scrollChild = specContainer._scrollChild
            local curY = 0
            local ENTRY_W = contentHalfSize - 6
            local ENTRY_H = 32

            for i = 1, #_entryFrames do
                if _entryFrames[i] then
                    _entryFrames[i]:Hide()
                end
            end

            for position, record in ipairs(entries) do
                local ef = _entryFrames[position]
                if not ef then
                    ef = CreateFrame("Button", nil, scrollChild)
                    ef:SetFrameLevel(thrPage:GetFrameLevel() + 2)
                    ef:RegisterForClicks("LeftButtonUp")
                    _entryFrames[position] = ef

                    local entBg = ef:CreateTexture(nil, "BACKGROUND")
                    entBg:SetAllPoints()
                    entBg:SetColorTexture(1, 1, 1, 0.02)
                    ef._bg = entBg

                    -- Selection accent: left theme-accent bar
                    local accent = ef:CreateTexture(nil, "ARTWORK")
                    accent:SetPoint("TOPLEFT", ef, "TOPLEFT", 0, 0)
                    accent:SetPoint("BOTTOMLEFT", ef, "BOTTOMLEFT", 0, 0)
                    accent:SetWidth(3)
                    accent:Hide()
                    ef._accent = accent

                    local delBtn = CreateFrame("Button", nil, ef)
                    delBtn:SetSize(14, 14)
                    delBtn:SetPoint("RIGHT", ef, "RIGHT", -8, 0)
                    delBtn:SetFrameLevel(ef:GetFrameLevel() + 3)
                    local delIcon = delBtn:CreateTexture(nil, "OVERLAY")
                    delIcon:SetAllPoints()
                    delIcon:SetTexture(_bandCloseIcon)
                    delIcon:SetAlpha(0.4)
                    delBtn:SetScript("OnEnter", function()
                        delIcon:SetAlpha(0.9)
                    end)
                    delBtn:SetScript("OnLeave", function()
                        delIcon:SetAlpha(0.4)
                    end)
                    delBtn:SetScript("OnClick", function()
                        local bd2 = conf.getBarData()
                        if not (bd2 and ef._entryIdx) then
                            return
                        end
                        table.remove(bd2.thresholdSpecs, ef._entryIdx)
                        local num = #bd2.thresholdSpecs
                        if num == 0 then
                            _selectedIdx = nil
                        elseif _selectedIdx and _selectedIdx > num then
                            _selectedIdx = num
                        end
                        _specDDRefresh()
                        RefreshSpecEntries()
                        RedrawDetail()
                        conf.refreshFn()
                    end)
                    ef._delBtn = delBtn

                    -- Add-variant duplicates this entry as a talent-gated sibling for the same spec; sits left of the delete X
                    local varBtn = CreateFrame("Button", nil, ef)
                    Pix.Size(varBtn, 84, 20)
                    varBtn:SetPoint("RIGHT", delBtn, "LEFT", -10, 0)
                    varBtn:SetFrameLevel(ef:GetFrameLevel() + 3)
                    local varBg = varBtn:CreateTexture(nil, "BACKGROUND")
                    varBg:SetAllPoints()
                    varBg:SetColorTexture(0.12, 0.12, 0.12, 0.8)
                    varBtn._border = CludesUI.MakeRoundedBorder(varBtn, 1, 1, 1, 0.08, varBg)
                    local varLbl = CludesUI.MakeFont(varBtn, 11, nil, 1, 1, 1)
                    varLbl:SetText(CludesUI.L("Add Variant"))
                    varLbl:SetAlpha(0.65)
                    varLbl:SetPoint("CENTER")
                    varBtn:SetScript("OnEnter", function(self)
                        varBg:SetColorTexture(0.16, 0.16, 0.16, 0.9)
                        varLbl:SetAlpha(0.9)
                        CludesUI.ShowWidgetTooltip(self, CludesUI.L("Add a talent variant of this entry"))
                    end)
                    varBtn:SetScript("OnLeave", function()
                        varBg:SetColorTexture(0.12, 0.12, 0.12, 0.8)
                        varLbl:SetAlpha(0.65)
                        CludesUI.HideWidgetTooltip()
                    end)
                    varBtn:SetScript("OnClick", function()
                        if not ef._entryIdx then
                            return
                        end
                        local bd2 = conf.getBarData()
                        if not bd2 then
                            return
                        end
                        local specs = bd2.thresholdSpecs
                        local source = specs and specs[ef._entryIdx]
                        if not source then
                            return
                        end
                        local copy = CludesUI.Lite.DeepCopy(source)
                        copy.talentSpellID = nil
                        copy.talentName = nil
                        table.insert(specs, ef._entryIdx + 1, copy)
                        _selectedIdx = ef._entryIdx + 1
                        RefreshSpecEntries()
                        RedrawDetail()
                        conf.rebuildFn()
                    end)
                    ef._varBtn = varBtn

                    -- Spec/talent group label (class-colored)
                    local specLbl = CludesUI.MakeFont(ef, 14, nil, 1, 1, 1)
                    specLbl:SetAlpha(0.85)
                    specLbl:SetPoint("LEFT", ef, "LEFT", 12, 0)
                    specLbl:SetPoint("RIGHT", varBtn, "LEFT", -8, 0)
                    specLbl:SetJustifyH("LEFT")
                    specLbl:SetWordWrap(false)
                    ef._specLbl = specLbl

                    -- Whole row selects this entry: repaint + refresh the detail pane with no list rebuild, so the scroll never jumps
                    ef:SetScript("OnClick", function(self)
                        if not self._entryIdx then
                            return
                        end
                        _selectedIdx = self._entryIdx
                        RepaintRows()
                        RedrawDetail()
                    end)
                    ef:SetScript("OnEnter", function(self)
                        if not self._selected then
                            self._bg:SetColorTexture(1, 1, 1, 0.06)
                        end
                    end)
                    ef:SetScript("OnLeave", function(self)
                        if not self._selected then
                            self._bg:SetColorTexture(1, 1, 1, 0.02)
                        end
                    end)
                end -- end entry frame creation

                ef._entryIdx = position
                ef:SetSize(ENTRY_W, ENTRY_H)
                ef:ClearAllPoints()
                ef:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, curY)
                ef._yOffset = -curY

                -- Class-color the label from the first specID (entries with no specIDs read "Unknown", in white)
                ef._specLbl:SetText(mod.EntryLabel(record))
                local class
                local firstSID = record.specIDs and record.specIDs[1]
                if firstSID == 0 then
                    class = _playerClassFile
                elseif firstSID and GetSpecializationInfoByID then
                    local _, _, _, _, _, castFrame = GetSpecializationInfoByID(firstSID)
                    class = castFrame
                elseif firstSID and CludesUI.IS_FOREVER then
                    class = CludesUI.SpecClassOf(firstSID)
                end
                local cc = class and CLASS_COLORS[class]
                if cc then
                    ef._specLbl:SetTextColor(cc[1], cc[2], cc[3], 1)
                else
                    ef._specLbl:SetTextColor(1, 1, 1, 1)
                end

                -- Talent variants are single-spec only: "All Specs"/multi-spec entries span specs, so a talent gate is meaningless. Hide "Add Variant" there and strip any stale gate.
                local ids = record.specIDs
                local allowTalent = (ids and #ids == 1 and ids[1] ~= 0) and true or false
                ef._varBtn:SetShown(allowTalent)
                if not allowTalent and record.talentSpellID then
                    record.talentSpellID = nil
                    record.talentName = nil
                    conf.rebuildFn()
                end

                -- Selection highlight; duplicates the resolver can never reach are shadow-dimmed
                PaintRow(ef)
                ef:SetAlpha(mod._CURB_IsThresholdCardShadowed(entries, position) and 0.45 or 1)

                ef:Show()
                curY = curY - ENTRY_H - ROW_GAP
            end

            local contentH = math.abs(curY) + SIDE_PAD
            scrollChild:SetSize(contentHalfSize, math.max(1, contentH))

            -- Scroll the list to the selected row (on open / add); else keep the offset, pulled back in when a shorter list leaves it past the end (the thumb follows)
            if scrollToSel and _selectedIdx and _entryFrames[_selectedIdx] then
                scrollTo((_entryFrames[_selectedIdx]._yOffset or 0) - 8)
            else
                scrollTo(specContainer._scrollFrame:GetVerticalScroll())
            end
        end

        local function ToggleFrame()
            if not conf.getBarData() then
                return
            end
            if not thrPage then
                BuildFrame()
            end
            if thrPage:IsShown() then
                -- Unlock cycle: forces a correct redraw
                if thrPage:GetLeft() ~= nil then
                    thrPage:Hide()
                    return
                end
                thrPage:Hide()
            end
            wipe(_tempSpecSel)
            _specDDRefresh()
            -- Re-pick the resolver's active entry each open, then scroll to it
            _selectedIdx = nil
            RefreshSpecEntries(true)
            RefreshDetail()
            thrPage._reanchor()
            thrPage:Show()
        end

        settingsBtn:SetScript("OnClick", function()
            ToggleFrame()
        end)
        -- Close on page switch or main panel close. Hidden inside its page's own
        -- hide, the editor may get no OnHide of its own (the engine's cascade
        -- order decides), so it also leaves the spec / talent watcher here (a
        -- second call does nothing).
        settingsBtn:HookScript("OnHide", function()
            if thrPage and thrPage:IsShown() then
                thrPage:Hide()
            end
            if thrPage then
                ThrEditorHidden(thrPage)
            end
        end)

        return settingsBtn
    end -- BuildThresholdSettingsButton

    -- Unlock Mode page
    local function BuildUnlockPage(pageName, hostFrame, yOffset)
        local W = CludesUI.Widgets
        local posY = yOffset
        local _, hgt

        CludesUI:ClearContentHeader()

        _, hgt = W:SectionHeader(hostFrame, "POSITIONING", posY)
        posY = posY - hgt

        _, hgt = W:Toggle(hostFrame, "Unlock Elements", posY, function()
            return CludesUI._unlockModeActive or false
        end, function(v)
            if CludesUI and CludesUI.ToggleUnlockMode then
                CludesUI:ToggleUnlockMode()
            end
        end, nil, "Opens the shared Layout Mode to reposition and scale elements")
        posY = posY - hgt

        _, hgt = W:Spacer(hostFrame, posY, 12)
        posY = posY - hgt

        _, hgt = W:SectionHeader(hostFrame, "RESET", posY)
        posY = posY - hgt

        _, hgt = W:Toggle(hostFrame, "Reset Positions", posY, function()
            return false
        end, function()
            local p = DB()
            if not p then
                return
            end
            p.health.offsetX = 0
            p.health.offsetY = -64
            p.health.unlockPos = nil
            p.primary.offsetX = 0
            p.primary.offsetY = -52
            p.primary.unlockPos = nil
            p.secondary.offsetX = 0
            p.secondary.offsetY = -38
            p.secondary.unlockPos = nil
            p.secondary.countTextUnlockPos = nil
            p.castBar.unlockPos = nil
            p.castBar.anchorX = 0
            p.castBar.anchorY = -50
            p.gcdBar.unlockPos = nil
            p.gcdBar.anchorX = 0
            p.gcdBar.anchorY = -78
            Refresh()
        end, nil, "Click to reset all element positions to defaults")
        posY = posY - hgt

        return math.abs(posY)
    end

    -- Cast Bar preview state
    local _castBarPreviewFill = 0.65
    local _castBarPreviewFrames = {}
    local _castBarPreviewScale = 1

    -- Shuffled spell icon pool for cast bar preview (same spells as nameplates)
    local _castBarIconPool = { 136197, 236802, 135808, 136116, 135735, 136048, 135812, 136075 }
    local _castBarIconIdx = 0
    local function ShuffleCastBarIcons()
        _castBarIconIdx = 0
        for i = #_castBarIconPool, 2, -1 do
            local jdx = math.random(i)
            _castBarIconPool[i], _castBarIconPool[jdx] = _castBarIconPool[jdx], _castBarIconPool[i]
        end
    end
    local function NextCastBarIcon()
        _castBarIconIdx = _castBarIconIdx + 1
        if _castBarIconIdx > #_castBarIconPool then
            _castBarIconIdx = 1
        end
        return _castBarIconPool[_castBarIconIdx]
    end

    -- Rows the Blizzard kit replaces but the classic cast bar leaves to the
    -- user (its background colour and opacity): gated only while Blizzard
    -- Style renders, live under Classic WoW UI. Returns cfg for inline use.
    function mod.ERB_CastBlizzOnlyGate(conf)
        if CludesUI.BlizzStyle.Active("castbar") == "blizzard" then
            return CludesUI.BlizzStyle.Gate("castbar", conf)
        end
        return conf
    end
    -- Blizzard Style chrome on the preview mock, mirroring the live bar's
    -- ns.ERB_ApplyBlizzCastChrome: the stock frame art round the bar and,
    -- with Spell Text on, the stock text box under it with the spell name
    -- inside; Classic WoW UI seats the vanilla frame instead (no text box).
    -- Regions are created once; off the style both hide. On ns (no new
    -- upvalue for the updater below).
    function mod.ERB_CastPreviewBlizzChrome(popFrame, cb, barW, blizz)
        if not blizz then
            if popFrame.blizzFrame then
                popFrame.blizzFrame:Hide()
            end
            if popFrame.blizzTextBox then
                popFrame.blizzTextBox:Hide()
            end
            return
        end
        if not popFrame.blizzFrame then
            local af = CreateFrame("Frame", nil, popFrame.container)
            af:SetAllPoints(popFrame.container)
            af:SetFrameLevel(popFrame.container:GetFrameLevel() + 6)
            popFrame.blizzArt = af
            local fr = af:CreateTexture(nil, "OVERLAY", nil, 2)
            if fr.SetSnapToPixelGrid then
                fr:SetSnapToPixelGrid(false)
                fr:SetTexelSnappingBias(0)
            end
            popFrame.blizzFrame = fr
            local tb = popFrame.barFrame:CreateTexture(nil, "BACKGROUND", nil, -1)
            if tb.SetSnapToPixelGrid then
                tb:SetSnapToPixelGrid(false)
                tb:SetTexelSnappingBias(0)
            end
            popFrame.blizzTextBox = tb
        end
        local fr, tb = popFrame.blizzFrame, popFrame.blizzTextBox
        if mod.ERB_CastClassic() then
            -- Classic WoW UI: the vanilla frame round the whole container
            -- (bar plus icon, the live seat); the spell name stays on the bar.
            mod.ERB_SeatClassicChrome(fr, popFrame.container, cb.height, false, mod.ERB_ClassicFrameK(cb))
            tb:Hide()
            return
        end
        local frameAtlas = mod.ERB_BlizzAtlas("frame")
        if frameAtlas then
            mod.ERB_StockAtlas(fr, frameAtlas)
            fr:ClearAllPoints()
            fr:SetPoint("TOPLEFT", popFrame.barFrame, "TOPLEFT", -2, 2)
            fr:SetPoint("BOTTOMRIGHT", popFrame.barFrame, "BOTTOMRIGHT", 2, -2)
            fr:Show()
        else
            fr:Hide()
        end
        local boxAtlas = cb.showSpellText and mod.ERB_BlizzAtlas("textbox")
        if boxAtlas then
            mod.ERB_StockAtlas(tb, boxAtlas)
            tb:ClearAllPoints()
            tb:SetPoint("TOPLEFT", popFrame.barFrame, "BOTTOMLEFT", 0, 3)
            tb:SetPoint("BOTTOMRIGHT", popFrame.barFrame, "BOTTOMRIGHT", 0, -13)
            tb:Show()
            local nameText = popFrame.spellText
            local side = cb.spellTextSide or "left"
            local posX, posY = cb.spellTextX or 0, cb.spellTextY or 0
            nameText:ClearAllPoints()
            if side == "right" then
                nameText:SetJustifyH("RIGHT")
                nameText:SetPoint("RIGHT", tb, "RIGHT", -8 + posX, posY)
            elseif side == "center" then
                nameText:SetJustifyH("CENTER")
                nameText:SetPoint("CENTER", tb, "CENTER", posX, posY)
            else
                nameText:SetJustifyH("LEFT")
                nameText:SetPoint("LEFT", tb, "LEFT", 8 + posX, posY)
            end
            nameText:SetWidth(math.max(10, (barW or cb.width or 220) - 16))
        else
            tb:Hide()
        end
    end

    local function UpdateCastBarPreview()
        local p = DB()
        if not p then
            return
        end
        local cb = p.castBar
        local popFrame = _castBarPreviewFrames

        if not popFrame.bar then
            return
        end
        -- Blizzard Style (latched per session, like the live bar): the stock
        -- art on the same mock -- the icon spanning the text box, no CUI
        -- border, stock background, fill and pip, frame art and the spell
        -- name inside the text box. Everything else stays the CUI mock.
        local blizz = (mod.ERB_CastBlizz and mod.ERB_CastBlizz()) or false
        -- classic = Classic WoW UI (the vanilla frame and spark round the
        -- user's fill); blizzKit = the 12.1 kit (stock background, fill, pip
        -- and text box). Shared stock-mode geometry stays on blizz.
        local classic = (mod.ERB_CastClassic and mod.ERB_CastClassic()) or false
        local blizzKit = blizz and not classic

        -- Snap helper: round to the preview container's physical pixel grid
        local cScale = popFrame.container:GetEffectiveScale()
        if cScale <= 0 then
            cScale = 1
        end
        local onePx = CludesUI.PP.perfect / cScale
        local function Snap(val)
            return math.floor(val / onePx + 0.5) * onePx
        end

        local wid, hgt = Snap(cb.width), Snap(cb.height)
        local bs = cb.borderSize

        -- Container size: icon (hxh) + bar (only when icon shown)
        local hasIcon = cb.showIcon ~= false and not mod.ERB_CastIconPortrait(cb)
        local iconFree = mod.ERB_CastIconFree(cb)
        local iconW = (hasIcon and not iconFree) and Snap(blizz and mod.ERB_CastIconW(cb) or hgt) or 0
        popFrame.container:SetSize(wid + iconW, hgt)

        -- Scale down to fit when the cast bar is wider than the panel
        local PAD = CludesUI.CONTENT_PAD
        local heading = popFrame.container:GetParent()
        local availW = (heading:GetWidth() - PAD * 2) / _castBarPreviewScale
        local fitScale = 1
        if (wid + iconW) > availW and (wid + iconW) > 0 and availW > 0 then
            fitScale = availW / (wid + iconW)
        end
        popFrame.container:SetScale(_castBarPreviewScale * fitScale)

        popFrame.container:ClearAllPoints()
        popFrame.container:SetPoint("CENTER", heading, "CENTER", 0, 0)
        -- Dimmed while the bar is off, like the page's greyed controls; no
        -- click then leads to those rows.
        local cbOn = cb.enabled and true or false
        PreviewBar.Lock(popFrame.container, cbOn, popFrame.hits)
        PreviewBar.HintFor(cbOn, heading)
        -- Bar frame (sits beside the icon; iconOnRight puts the icon on the right)
        local iconOnRight = hasIcon and cb.iconOnRight
        popFrame.barFrame:SetSize(wid, hgt)
        popFrame.barFrame:ClearAllPoints()
        popFrame.barFrame:SetPoint("LEFT", popFrame.container, "LEFT", iconOnRight and 0 or iconW, 0)

        -- Background
        local texKey = cb.texture
        -- Textured Background: back to the plain background before a branch repaints it.
        if popFrame.bg._erbBgTex then
            mod.ERB_BgTexture(popFrame.bg, nil)
        end
        if blizzKit then
            -- The retail background under WoW Forever too, as live.
            local bgAtlas = mod.ERB_BlizzAtlas("bg")
            if bgAtlas then
                CludesUI.StockAtlas(popFrame.bg, bgAtlas)
            else
                popFrame.bg:SetTexture(nil)
                popFrame.bg:SetColorTexture(0, 0, 0, 0.7)
            end
            popFrame.bg:ClearAllPoints()
            popFrame.bg:SetPoint("TOPLEFT", popFrame.barFrame, "TOPLEFT", -1, 1)
            popFrame.bg:SetPoint("BOTTOMRIGHT", popFrame.barFrame, "BOTTOMRIGHT", 1, -1)
        elseif texKey == "blizzard" then
            -- As live: Classic WoW UI takes the retail background on WoW Forever.
            if classic then
                mod.ERB_StockAtlas(popFrame.bg, "UI-CastingBar-Background", true)
            else
                popFrame.bg:SetAtlas("UI-CastingBar-Background", true)
            end
            popFrame.bg:ClearAllPoints()
            popFrame.bg:SetAllPoints(popFrame.barFrame)
        else
            popFrame.bg:SetTexture(nil)
            popFrame.bg:SetColorTexture(cb.bgR, cb.bgG, cb.bgB, cb.bgA)
            -- Textured Background: flat while Fill Color is below 100, as live.
            if cb.textureBg and (cb.fillOpacity or 100) >= 100 then
                mod.ERB_BgTexture(
                    popFrame.bg,
                    CludesUI.ResolveTexturePath(_G._CURB_CastBarTextures, texKey, nil),
                    cb.bgR,
                    cb.bgG,
                    cb.bgB,
                    cb.bgA
                )
            end
            popFrame.bg:ClearAllPoints()
            popFrame.bg:SetAllPoints(popFrame.barFrame)
        end

        -- Border wraps container (bar + icon) - PP or textured via ApplyBorderStyle
        if popFrame.container._border then
            popFrame.container._border:SetFrameLevel(
                cb.borderBehind and math.max(0, popFrame.container:GetFrameLevel() - 1)
                    or (popFrame.container:GetFrameLevel() + 5)
            )
            local pbs = blizz and 0 or (cb.borderSize or 0)
            local pbpx = (not blizz) and CludesUI.BorderPx(cb.borderSizePx, pbs, cb.borderTexture or "solid")
                or nil
            -- Extend Top / Extend Bottom, as the live bar draws them (none under a stock style).
            mod.ERB_AnchorBorderHost(
                popFrame.container._border,
                popFrame.container,
                mod.ERB_BorderExtents((not blizz) and cb or nil)
            )
            CludesUI.ApplyBorderStyle(
                popFrame.container._border,
                pbs,
                cb.borderR or 0,
                cb.borderG or 0,
                cb.borderB or 0,
                cb.borderA or 1,
                cb.borderTexture or "solid",
                cb.borderTextureOffset,
                cb.borderTextureOffsetY,
                cb.borderTextureShiftX,
                cb.borderTextureShiftY,
                "resourcebars",
                pbs,
                nil,
                pbpx
            )
        end
        -- Bottom Separator, as the live bar draws it (none under a stock style or a Solid border).
        mod.ERB_Separators(
            popFrame.container,
            cb,
            (cb.edgeSep and not blizz and mod.ERB_Textured(cb)) and true or false,
            popFrame.container:GetFrameLevel() + 7
        )

        -- Status bar: full bar frame, no inset
        popFrame.bar:ClearAllPoints()
        popFrame.bar:SetAllPoints(popFrame.barFrame)
        popFrame.bar:SetValue(_castBarPreviewFill)

        -- Bar texture
        local texLookup = _G._CURB_CastBarTextures or {}
        local texPath = texLookup[texKey]
        if blizzKit then
            popFrame.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
            popFrame.bar:GetStatusBarTexture():SetAtlas(mod.ERB_BlizzAtlas("cast") or "UI-CastingBar-Fill")
        elseif texKey == "blizzard" then
            popFrame.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
            popFrame.bar:GetStatusBarTexture():SetAtlas("UI-CastingBar-Fill", true)
        elseif texPath then
            popFrame.bar:SetStatusBarTexture(texPath)
        else
            popFrame.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        end

        -- Bar color / gradient
        local fillTex = popFrame.bar:GetStatusBarTexture()
        local fR, fG, fB, fA = cb.fillR, cb.fillG, cb.fillB, 1
        if cb.classColored == true then
            local _, castFrame = UnitClass("player")
            local cc = castFrame and RAID_CLASS_COLORS and RAID_CLASS_COLORS[castFrame]
            if cc then
                fR, fG, fB = cc.r, cc.g, cc.b
            end
        end
        local fillOp = (cb.fillOpacity or 100) / 100
        if blizzKit then
            -- The stock fill art is pre-coloured; the live bar skips its colour pass too.
            fillTex:SetVertexColor(1, 1, 1, 1)
        elseif cb.gradientEnabled then
            local dir = cb.gradientDir or "HORIZONTAL"
            fillTex:SetGradient(
                dir,
                CreateColor(fR, fG, fB, fA * fillOp),
                CreateColor(cb.gradientR, cb.gradientG, cb.gradientB, cb.gradientA * fillOp)
            )
        else
            fillTex:SetVertexColor(fR, fG, fB, fA * fillOp)
        end
        -- Mirror the live bar's Fill Opacity bg behavior: below 100 the bg covers only the empty portion so the translucent fill shows what's behind the bar; at 100 it spans the whole bar frame.
        if texKey ~= "blizzard" and not blizzKit then
            popFrame.bg:ClearAllPoints()
            if (cb.fillOpacity or 100) < 100 then
                popFrame.bg:SetPoint("TOPLEFT", fillTex, "TOPRIGHT", 0, 0)
                popFrame.bg:SetPoint("BOTTOMRIGHT", popFrame.barFrame, "BOTTOMRIGHT", 0, 0)
            else
                popFrame.bg:SetAllPoints(popFrame.barFrame)
            end
        end

        -- Spark: under the style the stock pip replaces the spark art (once,
        -- drawn plain; the CUI spark art is additive).
        if blizzKit and not popFrame.blizzSpark then
            local pip = mod.ERB_BlizzAtlas("spark")
            if pip then
                popFrame.blizzSpark = true
                popFrame.spark:SetAtlas(pip)
                popFrame.spark:SetBlendMode("BLEND")
            end
        end
        -- Classic WoW UI: the vanilla spark file (additive, like the CUI art) once.
        -- It stands taller than the bar and draws over the frame art
        -- (container +6) as live does, so it moves to its own host above it.
        if classic and not popFrame.classicSpark then
            popFrame.classicSpark = true
            popFrame.spark:SetTexture(mod.ERB_CLASSIC.spark)
            local host = CreateFrame("Frame", nil, popFrame.barFrame)
            host:SetAllPoints(popFrame.bar)
            host:SetFrameLevel(popFrame.container:GetFrameLevel() + 8)
            popFrame.spark:SetParent(host)
        end
        if cb.showSpark then
            -- The vanilla spark is a square scaled with the bar, centred a
            -- little above the bar's centre line (the live bar's numbers).
            local sparkY = 0
            if classic then
                local C = mod.ERB_CLASSIC
                local ss = C.sparkSize * hgt / C.barH
                popFrame.spark:SetSize(ss, ss)
                sparkY = C.sparkY * hgt / C.barH
            else
                popFrame.spark:SetSize(8, hgt)
            end
            popFrame.spark:ClearAllPoints()
            popFrame.spark:SetPoint("CENTER", fillTex, "RIGHT", 0, sparkY)
            popFrame.spark:Show()
        else
            popFrame.spark:Hide()
        end

        -- Icon: left or right side of container, full size
        do
            -- Under the style the icon also spans the text box (the live
            -- bar's ns.ERB_CastIconW) and shows the full spell art.
            local iSize = Snap(blizz and mod.ERB_CastIconW(cb) or hgt)
            popFrame.iconFrame:SetSize(iSize, iSize)
            if popFrame.icon then
                if blizz then
                    popFrame.icon:SetTexCoord(0, 1, 0, 1)
                else
                    popFrame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                end
            end
            -- Classic WoW UI keeps the icon under the frame art (container
            -- +6), inside the frame's window beside the bar, as live does.
            if classic then
                popFrame.iconFrame:SetFrameLevel(popFrame.container:GetFrameLevel() + 1)
            end
            popFrame.iconFrame:ClearAllPoints()
            if iconOnRight then
                popFrame.iconFrame:SetPoint("TOPRIGHT", popFrame.container, "TOPRIGHT", 0, 0)
            else
                popFrame.iconFrame:SetPoint("TOPLEFT", popFrame.container, "TOPLEFT", 0, 0)
            end
            mod.ERB_LayoutFreeCastIcon(popFrame.iconFrame, popFrame.container, cb, iconFree)
            if hasIcon then
                popFrame.iconFrame:Show()
            else
                popFrame.iconFrame:Hide()
            end
        end

        -- Icon/bar seam divider preview: mirrors the live cast bar's onePixel
        -- math (PP.perfect / effective scale), NOT the widget-local Snap()
        -- helper above -- the border itself already renders through that same
        -- shared PP system (ApplyBorderStyle -> SnapBorderTextures), so the
        -- divider has to match it, not the panel's own pixel grid.
        if popFrame.iconDivider then
            -- Border Art Divider, as the live bar draws it.
            local showDivider = hasIcon and not iconFree and cb.showIconDivider
            if
                mod.ERB_CastDividerArt(
                    popFrame.iconDivider,
                    showDivider,
                    popFrame.iconFrame,
                    iconOnRight,
                    cb,
                    blizz
                )
            then
                popFrame.iconDivider:Show()
            elseif showDivider then
                local PPp = CludesUI.PP
                local des = popFrame.container:GetEffectiveScale()
                local onePixel = (PPp and des > 0) and (PPp.perfect / des) or 1
                local dbs = cb.borderSize or 1
                -- Same rule as the live divider: an exact SOLID size drives it, textured keeps the step.
                local dtex = cb.borderTexture
                if not blizz and (not dtex or dtex == "" or dtex == "solid") then
                    dbs = CludesUI.BorderPx(cb.borderSizePx, cb.borderSize or 0, dtex) or dbs
                end
                popFrame.iconDivider:ClearAllPoints()
                popFrame.iconDivider:SetWidth(math.max(onePixel, math.floor(dbs + 0.5) * onePixel))
                if iconOnRight then
                    popFrame.iconDivider:SetPoint("TOPRIGHT", popFrame.iconFrame, "TOPLEFT", 0, 0)
                    popFrame.iconDivider:SetPoint("BOTTOMRIGHT", popFrame.iconFrame, "BOTTOMLEFT", 0, 0)
                else
                    popFrame.iconDivider:SetPoint("TOPLEFT", popFrame.iconFrame, "TOPRIGHT", 0, 0)
                    popFrame.iconDivider:SetPoint("BOTTOMLEFT", popFrame.iconFrame, "BOTTOMRIGHT", 0, 0)
                end
                popFrame.iconDivider:SetColorTexture(
                    cb.borderR or 0,
                    cb.borderG or 0,
                    cb.borderB or 0,
                    cb.borderA or 1
                )
                popFrame.iconDivider:Show()
            else
                popFrame.iconDivider:Hide()
            end
        end

        -- Cast text side-aware layout (mirrors the live cast bar)
        local cbTimerW = (cb.timerSize or 11) * 2.2
        local cbDurSide = cb.timerSide or "right"
        local cbSpellSide = cb.spellTextSide or "left"
        local cbBarW = popFrame.bar:GetWidth() or 0
        -- Timer / duration text
        if cb.showTimer then
            SetPVFont(popFrame.timerText, FONT_PATH, cb.timerSize or 11)
            local pt, xb, jh = mod.GetCastTextAnchor(cbDurSide, false, cbTimerW)
            popFrame.timerText:ClearAllPoints()
            popFrame.timerText:SetJustifyH(jh)
            popFrame.timerText:SetPoint(pt, popFrame.bar, pt, xb + (cb.timerX or 0), cb.timerY or 0)
            -- Preview total cast time is 3.0s; mirror the live "elapsed / total" mode.
            if cb.showTotalDuration then
                popFrame.timerText:SetText(string.format("%.1f / %.1f", 3.0 * _castBarPreviewFill, 3.0))
            else
                popFrame.timerText:SetText(string.format("%.1f", 3.0 * (1 - _castBarPreviewFill)))
            end
            popFrame.timerText:Show()
            mod.ERB_CastTextColor(popFrame.timerText, cb.timerR, cb.timerG, cb.timerB, cb.timerA)
        else
            popFrame.timerText:Hide()
        end

        -- Spell name text
        if cb.showSpellText then
            SetPVFont(popFrame.spellText, FONT_PATH, cb.spellTextSize or 11)
            if blizzKit and mod.ERB_BlizzAtlas("textbox") then
                -- Placed inside the stock text box by the chrome pass below.
            else
                local pt, xb, jh =
                    mod.GetCastTextAnchor(cbSpellSide, cb.showTimer and cbDurSide == cbSpellSide, cbTimerW)
                popFrame.spellText:ClearAllPoints()
                popFrame.spellText:SetJustifyH(jh)
                popFrame.spellText:SetPoint(
                    pt,
                    popFrame.bar,
                    pt,
                    xb + (cb.spellTextX or 0),
                    cb.spellTextY or 0
                )
                if cbSpellSide == "center" then
                    popFrame.spellText:SetWidth(cbBarW - 8 - (cb.showTimer and 2 * cbTimerW or 0))
                elseif cbBarW > 0 then
                    popFrame.spellText:SetWidth(cbBarW - 8 - (cb.showTimer and cbTimerW or 0))
                end
            end
            popFrame.spellText:SetText(CludesUI.L("Spell Name"))
            popFrame.spellText:Show()
            mod.ERB_CastTextColor(
                popFrame.spellText,
                cb.spellTextR,
                cb.spellTextG,
                cb.spellTextB,
                cb.spellTextA
            )
        else
            popFrame.spellText:Hide()
        end
        -- Blizzard Style chrome: frame art, and the text box with the spell name in it.
        mod.ERB_CastPreviewBlizzChrome(popFrame, cb, cbBarW, blizz)
        -- Re-flow so a live JustifyH change takes effect on already-rendered text.
        mod.ReflowFontString(popFrame.timerText)
        mod.ReflowFontString(popFrame.spellText)

        -- Update header height: 80px preview + optional hint text
        PreviewBar.SizeHeader(heading, 80)
    end

    local _castBarPreviewBuilder = function(heading, hdrW)
        HintBuildStart(PAGE_CASTBAR, heading)
        local p = DB()
        if not p then
            return 0
        end
        local cb = p.castBar

        local previewScale = UIParent:GetEffectiveScale() / heading:GetEffectiveScale()
        _castBarPreviewScale = previewScale

        local boxHolder = CreateFrame("Frame", nil, heading)
        boxHolder:SetPoint("CENTER", heading, "CENTER", 0, 0)

        -- Snap helper: round to the preview container's physical pixel grid (use previewScale for initial snap; adjusted below if we scale-to-fit)
        local cScale = UIParent:GetEffectiveScale()
        if cScale <= 0 then
            cScale = 1
        end
        local onePx = CludesUI.PP.perfect / cScale
        local function Snap(val)
            return math.floor(val / onePx + 0.5) * onePx
        end

        local wid, hgt = Snap(cb.width), Snap(cb.height)
        local hasIcon = cb.showIcon ~= false and not mod.ERB_CastIconPortrait(cb)
        local iconW = hasIcon and Snap(hgt) or 0

        -- Scale down to fit when the cast bar is wider than the panel
        local PAD = CludesUI.CONTENT_PAD
        local availW = (hdrW - PAD * 2) / previewScale
        local fitScale = 1
        if (wid + iconW) > availW and (wid + iconW) > 0 and availW > 0 then
            fitScale = availW / (wid + iconW)
        end
        boxHolder:SetScale(previewScale * fitScale)

        boxHolder:SetSize(wid + iconW, hgt)

        -- Bar frame (holds bg, status bar)
        local barFrame = CreateFrame("Frame", nil, boxHolder)
        barFrame:SetSize(wid, hgt)
        barFrame:SetPoint("LEFT", boxHolder, "LEFT", iconW, 0)
        -- Fresh mocks: the style chrome memos (frame art, text box and the
        -- spark swaps) belong to the previous build's frames; drop them so
        -- the next update re-creates the chrome on these.
        local popFrame = _castBarPreviewFrames
        if popFrame.blizzArt then
            popFrame.blizzArt:Hide()
        end
        if popFrame.blizzTextBox then
            popFrame.blizzTextBox:Hide()
        end
        popFrame.blizzArt, popFrame.blizzFrame, popFrame.blizzTextBox, popFrame.blizzSpark, popFrame.classicSpark =
            nil, nil, nil, nil, nil
        popFrame.barFrame = barFrame
        popFrame.container = boxHolder

        -- Border: dedicated child frame covering bar + icon (PP or textured)
        local bdrFrame = CreateFrame("Frame", nil, boxHolder)
        bdrFrame:SetAllPoints(boxHolder)
        bdrFrame:SetFrameLevel(boxHolder:GetFrameLevel() + 5)
        boxHolder._border = bdrFrame
        mod.ERB_AnchorBorderHost(
            bdrFrame,
            boxHolder,
            mod.ERB_BorderExtents((not mod.ERB_CastBlizz()) and cb or nil)
        )
        CludesUI.ApplyBorderStyle(
            bdrFrame,
            cb.borderSize or 0,
            cb.borderR or 0,
            cb.borderG or 0,
            cb.borderB or 0,
            cb.borderA or 1,
            cb.borderTexture or "solid",
            cb.borderTextureOffset,
            cb.borderTextureOffsetY,
            cb.borderTextureShiftX,
            cb.borderTextureShiftY,
            "resourcebars",
            cb.borderSize or 0,
            nil,
            CludesUI.BorderPx(cb.borderSizePx, cb.borderSize or 0, cb.borderTexture or "solid")
        )
        -- Bottom Separator, as the live bar draws it.
        mod.ERB_Separators(
            boxHolder,
            cb,
            (cb.edgeSep and not mod.ERB_CastBlizz() and mod.ERB_Textured(cb)) and true or false,
            boxHolder:GetFrameLevel() + 7
        )

        -- Background (full bar area, no inset)
        local backdrop = barFrame:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        local texKey = cb.texture
        if texKey == "blizzard" then
            if mod.ERB_CastClassic() then
                mod.ERB_StockAtlas(backdrop, "UI-CastingBar-Background", true)
            else
                backdrop:SetAtlas("UI-CastingBar-Background", true)
            end
        else
            backdrop:SetColorTexture(cb.bgR, cb.bgG, cb.bgB, cb.bgA)
            -- Textured Background, as live (never under the Blizzard Style kit).
            if
                cb.textureBg
                and (cb.fillOpacity or 100) >= 100
                and not (mod.ERB_CastBlizz() and not mod.ERB_CastClassic())
            then
                mod.ERB_BgTexture(
                    backdrop,
                    CludesUI.ResolveTexturePath(_G._CURB_CastBarTextures, texKey, nil),
                    cb.bgR,
                    cb.bgG,
                    cb.bgB,
                    cb.bgA
                )
            end
        end
        _castBarPreviewFrames.bg = backdrop

        -- Status bar (full bar area, no inset)
        local bar = CreateFrame("StatusBar", nil, barFrame)
        bar:SetAllPoints()
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(_castBarPreviewFill)

        local texLookup = _G._CURB_CastBarTextures or {}
        local texPath = texLookup[texKey]
        if texKey == "blizzard" then
            bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
            bar:GetStatusBarTexture():SetAtlas("UI-CastingBar-Fill", true)
        elseif texPath then
            bar:SetStatusBarTexture(texPath)
        else
            bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        end

        local fillTex = bar:GetStatusBarTexture()
        if cb.gradientEnabled then
            local dir = cb.gradientDir or "HORIZONTAL"
            fillTex:SetGradient(
                dir,
                CreateColor(cb.fillR, cb.fillG, cb.fillB, 1),
                CreateColor(cb.gradientR, cb.gradientG, cb.gradientB, cb.gradientA)
            )
        else
            fillTex:SetVertexColor(cb.fillR, cb.fillG, cb.fillB, 1)
        end
        _castBarPreviewFrames.bar = bar

        -- Spark
        local spark = bar:CreateTexture(nil, "OVERLAY", nil, 1)
        spark:SetTexture("Interface\\AddOns\\CludesUI\\media\\cast_spark.tga")
        spark:SetBlendMode("ADD")
        spark:SetSize(8, hgt)
        spark:SetPoint("CENTER", fillTex, "RIGHT", 0, 0)
        if not cb.showSpark then
            spark:Hide()
        end
        _castBarPreviewFrames.spark = spark

        -- Icon: left side of container, full size
        local iconFrame = CreateFrame("Frame", nil, boxHolder)
        local icon = iconFrame:CreateTexture(nil, "ARTWORK")
        icon:SetAllPoints()
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:SetTexture(NextCastBarIcon())
        local iSize = Snap(hgt)
        iconFrame:SetSize(iSize, iSize)
        iconFrame:SetPoint("TOPLEFT", boxHolder, "TOPLEFT", 0, 0)
        if not hasIcon then
            iconFrame:Hide()
        end
        _castBarPreviewFrames.iconFrame = iconFrame
        _castBarPreviewFrames.icon = icon

        -- Icon/bar seam divider (mirrors the live cast bar's "Show Icon
        -- Divider"): parented to bdrFrame, same reasoning as the live one --
        -- a texture on container itself would sit below the icon/bar child
        -- frames regardless of draw layer.
        local iconDivider = bdrFrame:CreateTexture(nil, "OVERLAY", nil, 7)
        iconDivider:Hide()
        _castBarPreviewFrames.iconDivider = iconDivider

        -- Texts ride an overlay above everything the mock draws (border +5,
        -- style frame art +6, icon +7, spark host +8), as the live bar keeps
        -- its texts; their anchors stay on the bar.
        local textFrame = CreateFrame("Frame", nil, barFrame)
        textFrame:SetAllPoints(bar)
        textFrame:SetFrameLevel(boxHolder:GetFrameLevel() + 9)

        -- Timer text
        local timerText = textFrame:CreateFontString(nil, "OVERLAY")
        SetPVFont(timerText, FONT_PATH, cb.timerSize or 11)
        timerText:SetPoint("RIGHT", bar, "RIGHT", -4 + (cb.timerX or 0), cb.timerY or 0)
        timerText:SetJustifyH("RIGHT")
        if cb.showTimer then
            if cb.showTotalDuration then
                timerText:SetText(string.format("%.1f / %.1f", 3.0 * _castBarPreviewFill, 3.0))
            else
                timerText:SetText(string.format("%.1f", 3.0 * (1 - _castBarPreviewFill)))
            end
        else
            timerText:Hide()
        end
        mod.ERB_CastTextColor(timerText, cb.timerR, cb.timerG, cb.timerB, cb.timerA)
        _castBarPreviewFrames.timerText = timerText

        -- Spell name text
        local spellText = textFrame:CreateFontString(nil, "OVERLAY")
        SetPVFont(spellText, FONT_PATH, cb.spellTextSize or 11)
        spellText:SetPoint("LEFT", bar, "LEFT", 4 + (cb.spellTextX or 0), cb.spellTextY or 0)
        spellText:SetJustifyH("LEFT")
        if cb.showSpellText then
            spellText:SetText(CludesUI.L("Spell Name"))
        else
            spellText:Hide()
        end
        mod.ERB_CastTextColor(spellText, cb.spellTextR, cb.spellTextG, cb.spellTextB, cb.spellTextA)
        _castBarPreviewFrames.spellText = spellText

        -- Create hit overlays for preview click-to-scroll (kept for the
        -- bar-off state: dimmed, no clicks)
        wipe(_hitOverlays)
        local hits = {}
        popFrame.hits = hits
        local overlayLevel = boxHolder:GetFrameLevel() + 20
        hits[#hits + 1] = CreateHitOverlay(barFrame, "castBar", overlayLevel)
        hits[#hits + 1] = CreateHitOverlay(iconFrame, "castIcon", overlayLevel + 5)
        if cb.showTimer then
            local ttHit = CreateFrame("Frame", nil, bar)
            ttHit:SetPoint("TOPLEFT", timerText, "TOPLEFT", -2, 2)
            ttHit:SetPoint("BOTTOMRIGHT", timerText, "BOTTOMRIGHT", 2, -2)
            hits[#hits + 1] = CreateHitOverlay(ttHit, "castTimer", overlayLevel + 5)
        end
        if cb.showSpellText then
            local stHit = CreateFrame("Frame", nil, bar)
            stHit:SetPoint("TOPLEFT", spellText, "TOPLEFT", -2, 2)
            stHit:SetPoint("BOTTOMRIGHT", spellText, "BOTTOMRIGHT", 2, -2)
            hits[#hits + 1] = CreateHitOverlay(stHit, "castSpellText", overlayLevel + 5)
        end
        PreviewBar.Lock(boxHolder, cb.enabled and true or false, hits)

        -- Hint text: made even while the bar is off, shown only while it is on
        -- (nothing to click otherwise), so switching the bar on can show it.
        local TOTAL_H = 80
        _headerBaseH = TOTAL_H
        local hintShown = not IsPreviewHintDismissed()
        if hintShown then
            if not _previewHintFS then
                -- Held across builds and pages (module state): out of its header's pool.
                local hintHost = PoolKeep(CreateFrame("Frame", nil, heading))
                hintHost:SetAllPoints(heading)
                _previewHintFS = CludesUI.MakeFont(hintHost, 11, nil, 1, 1, 1)
                _previewHintFS:SetAlpha(0.45)
                _previewHintFS:SetText(CludesUI.L("Click elements to scroll to and highlight their options"))
            end
            -- The host is kept across builds: one level above the header, as a new one sits.
            local host = _previewHintFS:GetParent()
            host:SetParent(heading)
            host:SetFrameLevel(heading:GetFrameLevel() + 1)
            host:Show()
            _previewHintFS:ClearAllPoints()
            _previewHintFS:SetPoint("BOTTOM", heading, "BOTTOM", 0, 20)
            _previewHintFS:SetShown(cb.enabled and true or false)
            if cb.enabled then
                TOTAL_H = TOTAL_H + 35
            end
        elseif _previewHintFS then
            _previewHintFS:Hide()
        end

        return TOTAL_H
    end

    -- Textured Background: the Texture Settings cog row, one per bar kind, shared
    -- by the module pages and Global Settings > Textures. apply: the page's own
    -- refresh after a write.
    local TEXBG_KINDS = {
        bars = {
            tbl = "general",
            key = "barTextureBg",
            tex = "barTexture",
            need = "This option requires a Texture other than None.",
        },
        cast = {
            tbl = "castBar",
            key = "textureBg",
            tex = "texture",
            blizz = true,
            need = "This option requires a Bar Texture other than None or Blizzard.",
        },
        gcd = {
            tbl = "gcdBar",
            key = "textureBg",
            tex = "texture",
            need = "This option requires a Bar Texture other than None.",
        },
    }
    local function TexBgRowCfg(kind, apply)
        local k = TEXBG_KINDS[kind]
        return {
            type = "toggle",
            label = "Textured Background",
            tooltip = "Draws the bar texture on the background too.",
            disabled = function()
                local p = DB()
                local t = p and p[k.tbl]
                if not t then
                    return true
                end
                -- Split textures: the health and power bars may carry their own.
                if kind == "bars" and p.splitTex == true then
                    return false
                end
                local tx = t[k.tex] or "none"
                return tx == "none" or (k.blizz == true and tx == "blizzard")
            end,
            disabledTooltip = k.need,
            get = function()
                local p = DB()
                local t = p and p[k.tbl]
                return (t and t[k.key]) or false
            end,
            set = function(v)
                local p = DB()
                local t = p and p[k.tbl]
                if not t then
                    return
                end
                t[k.key] = v and true or false
                apply()
            end,
        }
    end

    -- Shared helpers for the section and page builders under ResourceBars_Options\
    -- (loaded before this file, read when a page builds). Preview state stays
    -- here; the pages write it through the two setters.
    mod._CURB_OptEnv = {
        TexBgRowCfg = TexBgRowCfg,
        DB = DB,
        PP = Pix,
        Refresh = Refresh,
        SmoothRefresh = SmoothRefresh,
        RefreshHealth = RefreshHealth,
        RebuildHealth = RebuildHealth,
        AddFormBarBtn = AddFormBarBtn,
        AddFormTextBtn = AddFormTextBtn,
        FormToggleRows = FormToggleRows,
        BuildHashCog = BuildHashCog,
        BuildThresholdSettingsButton = BuildThresholdSettingsButton,
        -- The threshold editor's popups (the headless scenarios open them too).
        ShowBandEditor = ShowBandEditor,
        ShowBuffEditor = ShowBuffEditor,
        ShowSpenderEditor = ShowSpenderEditor,
        RefreshPower = RefreshPower,
        RebuildPower = RebuildPower,
        RefreshClass = RefreshClass,
        RebuildClass = RebuildClass,
        BAND_REPLACES_TIP = BAND_REPLACES_TIP,
        STAGGER_PCT_TIP = STAGGER_PCT_TIP,
        CLASS_COLORS = CLASS_COLORS,
        _clickMappings = _clickMappings,
        _previewHeaderBuilder = _previewHeaderBuilder,
        CLASSIC_SYNC_KEYS = CLASSIC_SYNC_KEYS,
        CLASSIC_MATCH_KEYS = CLASSIC_MATCH_KEYS,
        ShuffleCastBarIcons = ShuffleCastBarIcons,
        UpdateCastBarPreview = UpdateCastBarPreview,
        _castBarPreviewBuilder = _castBarPreviewBuilder,
        UpdatePreviewHeader = UpdatePreviewHeader,
        PreviewAvail = PreviewBar.Avail,
        SetDisplayPreviewValues = function(pipCount, fillPct)
            _previewPipCount = pipCount
            _previewBarFillPct = fillPct
        end,
        SetCastBarPreviewFill = function(v)
            _castBarPreviewFill = v
        end,
    }

    -- GCD Bar preview: one static mock of the bar at a random fill, styled
    -- from p.gcdBar the way BuildGCDBar paints the live bar. Always
    -- horizontal like the bar stack preview (Horizontal (Left) keeps its
    -- fill direction); a vertical bar shows at its configured size laid flat.
    do
        local environ = mod._CURB_OptEnv
        local GCD_PREVIEW_H = 80

        -- The shared preview hint on a GCD or Totem Bar header build, as the
        -- Cast Bar header places it. Returns the height it adds.
        -- Made even while the preview is off (shown only while on), so
        -- switching the bar on can show it.
        local function PlaceHint(heading, on)
            if IsPreviewHintDismissed() then
                if _previewHintFS then
                    _previewHintFS:Hide()
                end
                return 0
            end
            if not _previewHintFS then
                -- Held across builds and pages (module state): out of its header's pool.
                local hintHost = PoolKeep(CreateFrame("Frame", nil, heading))
                hintHost:SetAllPoints(heading)
                _previewHintFS = CludesUI.MakeFont(hintHost, 11, nil, 1, 1, 1)
                _previewHintFS:SetAlpha(0.45)
                _previewHintFS:SetText(CludesUI.L("Click elements to scroll to and highlight their options"))
            end
            local host = _previewHintFS:GetParent()
            host:SetParent(heading)
            host:SetFrameLevel(heading:GetFrameLevel() + 1)
            host:Show()
            _previewHintFS:ClearAllPoints()
            _previewHintFS:SetPoint("BOTTOM", heading, "BOTTOM", 0, 20)
            _previewHintFS:SetShown(on and true or false)
            return on and 35 or 0
        end

        local gcdFill = 0.6
        local popFrame = {}

        -- building: the header build itself (it returns the height); any
        -- other update resizes the shown header for the hint.
        local function UpdateGCDPreview(building)
            local p = DB()
            if not (p and popFrame.bar) then
                return
            end
            local g = p.gcdBar
            local boxHolder = popFrame.container
            local heading = boxHolder:GetParent()

            -- Scale down to fit when the bar is wider than the panel; snap on
            -- the grid of that final scale.
            local rawW = g.width or 220
            local PAD = CludesUI.CONTENT_PAD
            local availW = ((popFrame.hdrW or heading:GetWidth()) - PAD * 2) / popFrame.scale
            local fitScale = 1
            if rawW > availW and rawW > 0 and availW > 0 then
                fitScale = availW / rawW
            end
            boxHolder:SetScale(popFrame.scale * fitScale)
            local cScale = boxHolder:GetEffectiveScale()
            if cScale <= 0 then
                cScale = 1
            end
            local onePx = CludesUI.PP.perfect / cScale
            local function Snap(val)
                return math.floor(val / onePx + 0.5) * onePx
            end
            local wid, hgt = Snap(rawW), Snap(g.height or 12)
            boxHolder:SetSize(wid, hgt)
            boxHolder:ClearAllPoints()
            boxHolder:SetPoint("CENTER", heading, "CENTER", 0, 0)
            local on = g.enabled and true or false
            PreviewBar.Lock(boxHolder, on, popFrame.hits)
            if not building then
                PreviewBar.HintFor(on, heading)
                PreviewBar.SizeHeader(heading, GCD_PREVIEW_H)
            end

            -- Border + Bottom Separator, as BuildGCDBar
            local bdr = popFrame.border
            local bs = g.borderSize or 0
            bdr:SetFrameLevel(
                g.borderBehind and math.max(0, boxHolder:GetFrameLevel() - 1)
                    or (boxHolder:GetFrameLevel() + 5)
            )
            mod.ERB_AnchorBorderHost(bdr, boxHolder, mod.ERB_BorderExtents(g))
            CludesUI.ApplyBorderStyle(
                bdr,
                bs,
                g.borderR or 0,
                g.borderG or 0,
                g.borderB or 0,
                g.borderA or 1,
                g.borderTexture or "solid",
                g.borderTextureOffset,
                g.borderTextureOffsetY,
                g.borderTextureShiftX,
                g.borderTextureShiftY,
                "resourcebars",
                bs,
                nil,
                CludesUI.BorderPx(g.borderSizePx, bs, g.borderTexture or "solid")
            )
            mod.ERB_Separators(
                boxHolder,
                g,
                (g.edgeSep and mod.ERB_Textured(g)) and true or false,
                boxHolder:GetFrameLevel() + 7
            )

            -- Texture + background (Textured Background included)
            local bar, backdrop = popFrame.bar, popFrame.bg
            -- The live fill inset inside a border: one physical pixel, on this grid.
            local inset = bs > 0 and onePx or 0
            bar:ClearAllPoints()
            bar:SetPoint("TOPLEFT", boxHolder, "TOPLEFT", inset, -inset)
            bar:SetPoint("BOTTOMRIGHT", boxHolder, "BOTTOMRIGHT", -inset, inset)
            bar:SetStatusBarTexture(
                CludesUI.ResolveTexturePath(_G._CURB_BarTextures, g.texture, "Interface\\Buttons\\WHITE8x8")
            )
            backdrop:SetTexture(nil)
            backdrop:SetColorTexture(g.bgR, g.bgG, g.bgB, g.bgA)
            if g.textureBg or backdrop._erbBgTex then
                mod.ERB_BgTexture(
                    backdrop,
                    g.textureBg and CludesUI.ResolveTexturePath(_G._CURB_BarTextures, g.texture, nil),
                    g.bgR,
                    g.bgG,
                    g.bgB,
                    g.bgA
                )
            end

            local leftward = g.orientation == "HORIZONTAL_LEFT"
            bar:SetReverseFill(leftward)
            bar:SetValue(gcdFill)

            -- Fill color / gradient
            local fillTex = bar:GetStatusBarTexture()
            local fR, fG, fB, fA = g.fillR, g.fillG, g.fillB, g.fillA or 1
            if g.classColored then
                local _, castFrame = UnitClass("player")
                local cc = castFrame and CLASS_COLORS[castFrame]
                if cc then
                    fR, fG, fB = cc[1], cc[2], cc[3]
                end
            end
            if g.gradientEnabled then
                fillTex:SetGradient(
                    g.gradientDir or "HORIZONTAL",
                    CreateColor(fR, fG, fB, fA),
                    CreateColor(g.gradientR, g.gradientG, g.gradientB, g.gradientA or 1)
                )
            else
                fillTex:SetVertexColor(fR, fG, fB, fA)
            end

            -- Spark on the fill's leading edge
            local spark = popFrame.spark
            if g.showSpark then
                spark:SetSize(8, hgt)
                spark:ClearAllPoints()
                spark:SetPoint("CENTER", fillTex, leftward and "LEFT" or "RIGHT", 0, 0)
                spark:Show()
            else
                spark:Hide()
            end
        end

        environ.UpdateGCDPreview = UpdateGCDPreview
        environ.SetGCDPreviewFill = function(v)
            gcdFill = v
        end

        environ._gcdPreviewBuilder = function(heading, hdrW)
            HintBuildStart(PAGE_GCD, heading)
            local p = DB()
            if not p then
                return 0
            end

            -- Pixel sizes match the live bar: the panel's scale against UIParent's.
            popFrame.scale = UIParent:GetEffectiveScale() / heading:GetEffectiveScale()

            local boxHolder = CreateFrame("Frame", nil, heading)
            boxHolder:SetPoint("CENTER", heading, "CENTER", 0, 0)
            boxHolder:SetScale(popFrame.scale)
            popFrame.container = boxHolder

            local backdrop = boxHolder:CreateTexture(nil, "BACKGROUND")
            backdrop:SetAllPoints()
            popFrame.bg = backdrop

            local bar = CreateFrame("StatusBar", nil, boxHolder)
            bar:SetMinMaxValues(0, 1)
            bar:SetOrientation("HORIZONTAL")
            bar:SetRotatesTexture(false)
            bar:SetFrameLevel(boxHolder:GetFrameLevel() + 1)
            popFrame.bar = bar

            local spark = bar:CreateTexture(nil, "OVERLAY", nil, 1)
            spark:SetTexture(mod.SPARK_TEX or "Interface\\AddOns\\CludesUI\\media\\cast_spark.tga")
            spark:SetBlendMode("ADD")
            popFrame.spark = spark

            local bdrFrame = CreateFrame("Frame", nil, boxHolder)
            bdrFrame:SetAllPoints(boxHolder)
            popFrame.border = bdrFrame

            wipe(_hitOverlays)
            popFrame.hits = { CreateHitOverlay(boxHolder, "gcdBar", boxHolder:GetFrameLevel() + 20) }

            -- Width is known only once hdr is laid out: fit against hdrW for this pass.
            popFrame.hdrW = hdrW
            UpdateGCDPreview(true)
            popFrame.hdrW = nil

            _headerBaseH = GCD_PREVIEW_H
            return GCD_PREVIEW_H + PlaceHint(heading, p.gcdBar.enabled)
        end

        environ.RestoreGCDPreview = function()
            gcdFill = math.random(30, 85) / 100
            -- Header shown again from the cache: take the hint back before the update sizes it.
            if not IsPreviewHintDismissed() then
                RehomeHint(PAGE_GCD)
            end
            UpdateGCDPreview()
        end

        -- Totem Bar preview: sample icons in the Totem Bar layout (Icon Size,
        -- Spacing, Orientation, border, timer), static like the Cast Bar's.
        -- WoW Forever shamans with the Call Totem Bar on get its six buttons
        -- as a second group below. No swipe: the timers stand still.
        -- Header height: at least TOTEM_PREVIEW_H, the stack plus TOTEM_PREVIEW_VPAD, at most TOTEM_PREVIEW_MAXH.
        local TOTEM_PREVIEW_H, TOTEM_PREVIEW_VPAD, TOTEM_PREVIEW_MAXH = 80, 40, 260
        local TOTEM_ICONS = {
            { tex = "Interface\\Icons\\Spell_Nature_StoneSkinTotem", timer = "24" },
            { tex = "Interface\\Icons\\Spell_Fire_SearingTotem", timer = "11" },
            { tex = "Interface\\Icons\\Spell_Nature_ManaRegenTotem", timer = "52" },
            { tex = "Interface\\Icons\\Spell_Nature_Windfury", timer = "7" },
        }
        local CALL_ICONS = {
            { tex = "Interface\\Icons\\Spell_Shaman_DropAll_01" },
            { tex = "Interface\\Icons\\Spell_Nature_StoneSkinTotem" },
            { tex = "Interface\\Icons\\Spell_Fire_SearingTotem", timer = "5" },
            { tex = "Interface\\Icons\\Spell_Nature_ManaRegenTotem" },
            { tex = "Interface\\Icons\\Spell_Nature_Windfury", timer = "18" },
            { tex = "Interface\\Icons\\Spell_Shaman_TotemRecall" },
        }
        -- Each group: key (profile table), icons, zoom (the live crop), map
        -- keys for the hit overlays.
        local TOTEM_GROUPS = {
            {
                key = "totemBar",
                icons = TOTEM_ICONS,
                zoom = 0.055,
                mapIcon = "totemIcon",
                mapTimer = "totemTimer",
            },
            {
                key = "callTotemBar",
                icons = CALL_ICONS,
                zoom = 0.08,
                mapIcon = "callTotemIcon",
                mapTimer = "callTotemTimer",
            },
        }
        local tp = { groups = {} }

        -- The Call Totem Bar group shows where its section does, while it is on.
        local function CallTotemShown(p)
            local c = p and p.callTotemBar
            return mod.ERB_HasCallTotemSection() and c and c.enabled == true
        end

        -- building: the header build itself (it returns the height); any
        -- other update resizes the shown header.
        -- Something in the Totem preview takes a click (a group that is on).
        local function TotemPreviewClickable()
            for _, grp in ipairs(tp.groups) do
                if grp.on then
                    return true
                end
            end
            return false
        end

        local function UpdateTotemPreview(building)
            local p = DB()
            local boxHolder = tp.container
            if not (p and boxHolder) then
                return
            end
            local heading = boxHolder:GetParent()

            -- Group sizes in live units first: the fit scale (and with it the
            -- pixel grid) is known only once the whole stack is measured.
            -- The Call Totem Bar group, built wherever its section is, shows
            -- while that bar is on.
            local GAP = 10
            local totalW, totalH, isShown = 0, 0, 0
            for gi, grp in ipairs(tp.groups) do
                local t = p[TOTEM_GROUPS[gi].key]
                if gi == 2 and not CallTotemShown(p) then
                    t = nil
                end
                grp.t = nil
                if t then
                    local num = #grp.icons
                    local len = num * (t.iconSize or 30) + (num - 1) * (t.spacing or 2)
                    local across = t.iconSize or 30
                    local vertical = t.orientation == "VERTICAL"
                    totalW = math.max(totalW, vertical and across or len)
                    totalH = totalH + (vertical and len or across) + (isShown > 0 and GAP or 0)
                    isShown = isShown + 1
                    grp.t = t
                end
            end

            -- The header grows with the stack (a column, two groups) up to
            -- TOTEM_PREVIEW_MAXH; past that, or past the panel width, it scales down.
            local PAD = CludesUI.CONTENT_PAD
            local availW = ((tp.hdrW or heading:GetWidth()) - PAD * 2) / tp.scale
            local availH = (TOTEM_PREVIEW_MAXH - TOTEM_PREVIEW_VPAD) / tp.scale
            local fit = 1
            if totalW > availW and availW > 0 then
                fit = availW / totalW
            end
            if totalH * fit > availH and availH > 0 then
                fit = availH / totalH
            end
            boxHolder:SetScale(tp.scale * fit)
            tp.baseH = math.max(TOTEM_PREVIEW_H, math.ceil(totalH * tp.scale * fit) + TOTEM_PREVIEW_VPAD)

            local cScale = boxHolder:GetEffectiveScale()
            if cScale <= 0 then
                cScale = 1
            end
            local onePx = CludesUI.PP.perfect / cScale
            local function Snap(val)
                return math.floor(val / onePx + 0.5) * onePx
            end

            local snapW, topY = 0, 0
            for gi, grp in ipairs(tp.groups) do
                local t = grp.t
                grp.frame:SetShown(t ~= nil)
                if not t then
                    grp.on = false
                    for _, hit in ipairs(grp.iconHits) do
                        hit:Hide()
                    end
                    for _, hit in ipairs(grp.timerHits) do
                        hit:Hide()
                    end
                else
                    local size = Snap(t.iconSize or 30)
                    -- A set gap keeps at least one physical pixel when the stack is fitted down.
                    local spacing = (t.spacing or 2) > 0 and math.max(onePx, Snap(t.spacing or 2)) or 0
                    local vertical = t.orientation == "VERTICAL"
                    local num = #grp.icons
                    local len = num * size + (num - 1) * spacing
                    local gw, gh = len, size
                    if vertical then
                        gw, gh = size, len
                    end
                    grp.frame:SetSize(gw, gh)
                    grp.frame:ClearAllPoints()
                    grp.frame:SetPoint("TOP", boxHolder, "TOP", 0, -topY)
                    topY = topY + gh + GAP
                    snapW = math.max(snapW, gw)
                    local bs = t.borderSize or 0
                    local texKey = t.borderTexture or "solid"
                    local showTimer = t.showTimer ~= false
                    -- The active totem bar shows only for the player's own class, as live.
                    local on = true
                    if gi == 1 then
                        local ec = t.enabledClasses
                        local _, castFrame = UnitClass("player")
                        on = (ec and castFrame and ec[castFrame]) and true or false
                    end
                    grp.on = on
                    for i, ic in ipairs(grp.icons) do
                        ic:SetSize(size, size)
                        ic:ClearAllPoints()
                        local off = (i - 1) * (size + spacing)
                        if vertical then
                            ic:SetPoint("TOP", grp.frame, "TOP", 0, -off)
                        else
                            ic:SetPoint("LEFT", grp.frame, "LEFT", off, 0)
                        end
                        -- "Show Behind": +3 in front of the icon, level-1 behind it, as live.
                        local bdr = ic._border
                        bdr:SetFrameLevel(
                            t.borderBehind and math.max(0, ic:GetFrameLevel() - 1) or (ic:GetFrameLevel() + 3)
                        )
                        CludesUI.ApplyBorderStyle(
                            bdr,
                            bs,
                            t.borderR or 0,
                            t.borderG or 0,
                            t.borderB or 0,
                            t.borderA or 1,
                            texKey,
                            t.borderTextureOffset,
                            t.borderTextureOffsetY,
                            t.borderTextureShiftX,
                            t.borderTextureShiftY,
                            "resourcebars",
                            bs,
                            nil,
                            CludesUI.BorderPx(t.borderSizePx, bs, texKey)
                        )
                        local fontStr = ic._timer
                        if fontStr then
                            if showTimer then
                                SetPVFont(fontStr, FONT_PATH, t.timerSize or 11, "resourceBars")
                                fontStr:Show()
                            else
                                fontStr:Hide()
                            end
                        end
                    end
                    PreviewBar.Lock(grp.frame, on, grp.iconHits)
                    for _, hit in ipairs(grp.timerHits) do
                        hit:SetShown(on and showTimer)
                    end
                end
            end
            boxHolder:SetSize(math.max(1, snapW), math.max(1, topY - GAP))
            boxHolder:ClearAllPoints()
            boxHolder:SetPoint("CENTER", heading, "CENTER", 0, 0)

            _headerBaseH = tp.baseH
            if not building then
                PreviewBar.HintFor(TotemPreviewClickable(), heading)
                PreviewBar.SizeHeader(heading, tp.baseH)
            end
        end

        environ.UpdateTotemPreview = UpdateTotemPreview

        environ._totemPreviewBuilder = function(heading, hdrW)
            HintBuildStart(PAGE_TOTEM, heading)
            local p = DB()
            if not p then
                return 0
            end

            -- Pixel sizes match the live bar: the panel's scale against UIParent's.
            tp.scale = UIParent:GetEffectiveScale() / heading:GetEffectiveScale()

            local boxHolder = CreateFrame("Frame", nil, heading)
            boxHolder:SetPoint("CENTER", heading, "CENTER", 0, 0)
            boxHolder:SetScale(tp.scale)
            tp.container = boxHolder

            wipe(_hitOverlays)
            wipe(tp.groups)
            local overlayLevel = boxHolder:GetFrameLevel() + 20
            -- The Call Totem Bar group is built wherever its section is
            -- (UpdateTotemPreview shows it while that bar is on).
            local nGroups = mod.ERB_HasCallTotemSection() and 2 or 1
            for gi = 1, nGroups do
                local def = TOTEM_GROUPS[gi]
                local widget = CreateFrame("Frame", nil, boxHolder)
                widget:Show()
                local grp = { frame = widget, icons = {}, timerHits = {} }
                tp.groups[gi] = grp
                grp.iconHits = { CreateHitOverlay(widget, def.mapIcon, overlayLevel) }
                for i, d in ipairs(def.icons) do
                    local ic = CreateFrame("Frame", nil, widget)
                    local tex = ic:CreateTexture(nil, "ARTWORK")
                    tex:SetAllPoints()
                    tex:SetTexture(d.tex)
                    tex:SetTexCoord(def.zoom, 1 - def.zoom, def.zoom, 1 - def.zoom)
                    ic._border = CreateFrame("Frame", nil, ic)
                    ic._border:SetAllPoints(ic)
                    if d.timer then
                        -- The live timer is the cooldown's countdown number: white, centred.
                        local tf = CreateFrame("Frame", nil, ic)
                        tf:SetAllPoints(ic)
                        tf:SetFrameLevel(ic:GetFrameLevel() + 5)
                        local fontStr = tf:CreateFontString(nil, "OVERLAY")
                        SetPVFont(fontStr, FONT_PATH, 11, "resourceBars")
                        fontStr:SetPoint("CENTER", ic, "CENTER", 0, 0)
                        fontStr:SetTextColor(1, 1, 1, 1)
                        fontStr:SetText(d.timer)
                        ic._timer = fontStr
                        -- Every timer leads to the timer settings, above the icon overlay.
                        local hit = CreateFrame("Frame", nil, widget)
                        hit:SetPoint("TOPLEFT", fontStr, "TOPLEFT", -2, 2)
                        hit:SetPoint("BOTTOMRIGHT", fontStr, "BOTTOMRIGHT", 2, -2)
                        CreateHitOverlay(hit, def.mapTimer, overlayLevel + 5)
                        grp.timerHits[#grp.timerHits + 1] = hit
                    end
                    grp.icons[i] = ic
                end
            end

            -- Width is known only once hdr is laid out: fit against hdrW for this pass.
            tp.hdrW = hdrW
            UpdateTotemPreview(true)
            tp.hdrW = nil

            return tp.baseH + PlaceHint(heading, TotemPreviewClickable())
        end

        environ.RestoreTotemPreview = function()
            -- Header shown again from the cache: take the hint back before the update sizes it.
            if not IsPreviewHintDismissed() then
                RehomeHint(PAGE_TOTEM)
            end
            UpdateTotemPreview()
        end
    end

    -- Register the module
    CludesUI:RegisterModule("CludesUIResourceBars", {
        title = "Resource Bars",
        description = "Custom class resource, health, and mana bar display.",
        pages = C_SwingTimer and { PAGE_DISPLAY, PAGE_CASTBAR, PAGE_GCD, PAGE_SWING, PAGE_TOTEM }
            or { PAGE_DISPLAY, PAGE_CASTBAR, PAGE_GCD, PAGE_TOTEM },
        buildPage = function(pageName, hostFrame, yOffset)
            if pageName == PAGE_DISPLAY then
                return mod.ERB_BuildBarDisplayPage(pageName, hostFrame, yOffset)
            elseif pageName == PAGE_CASTBAR then
                return mod.ERB_BuildCastBarPage(pageName, hostFrame, yOffset)
            elseif pageName == PAGE_GCD then
                return mod.ERB_BuildGCDBarPage(pageName, hostFrame, yOffset)
            elseif pageName == PAGE_SWING then
                return mod.ERB_BuildSwingTimerPage(pageName, hostFrame, yOffset)
            elseif pageName == PAGE_TOTEM then
                return mod.ERB_BuildTotemBarPage(pageName, hostFrame, yOffset)
            end
        end,
        getHeaderBuilder = function(pageName)
            if pageName == PAGE_DISPLAY then
                return _previewHeaderBuilder
            elseif pageName == PAGE_CASTBAR then
                return _castBarPreviewBuilder
            elseif pageName == PAGE_GCD then
                return mod._CURB_OptEnv._gcdPreviewBuilder
            elseif pageName == PAGE_TOTEM then
                return mod._CURB_OptEnv._totemPreviewBuilder
            end
            return nil
        end,
        onPageCacheRestore = function(pageName)
            if pageName == PAGE_DISPLAY then
                -- A kept header that built with nothing to show (no class
                -- resource) is built again on every visit, as an empty header
                -- is never cached without page reuse (its spec rows included;
                -- the build draws its own preview values).
                if _classHdrEmpty then
                    CludesUI:RefreshPage(true)
                    return
                end
                -- Randomize preview values when switching TO this tab
                local minPips = math.floor(5 * 0.50 + 0.5)
                local maxPips = math.floor(5 * 0.75 + 0.5)
                _previewPipCount = math.random(minPips, maxPips)
                _previewBarFillPct = math.random(30, 80)
                UpdatePreviewHeader()
                -- Refresh hint visibility never recreate here, just show/hide
                local dismissed = IsPreviewHintDismissed()
                if _previewHintFS then
                    if dismissed then
                        _previewHintFS:Hide()
                    else
                        RehomeHint(PAGE_DISPLAY)
                        _previewHintFS:SetAlpha(0.45)
                        _previewHintFS:Show()
                        if _previewHintFS:GetParent() then
                            _previewHintFS:GetParent():Show()
                        end
                    end
                end
                -- Set correct header height based on current hint state
                if _headerBaseH > 0 then
                    CludesUI:SetContentHeaderHeightSilent(_headerBaseH + (dismissed and 0 or 35))
                end
            elseif pageName == PAGE_CASTBAR then
                -- Randomize cast bar preview fill each time the tab is opened
                _castBarPreviewFill = math.random(30, 85) / 100
                -- Before the preview update: it sizes the header for the hint.
                if not IsPreviewHintDismissed() then
                    RehomeHint(PAGE_CASTBAR)
                end
                UpdateCastBarPreview()
            elseif pageName == PAGE_GCD then
                mod._CURB_OptEnv.RestoreGCDPreview()
            elseif pageName == PAGE_TOTEM then
                mod._CURB_OptEnv.RestoreTotemPreview()
            end
        end,
        onReset = function()
            if _G._CURB_AceDB then
                _G._CURB_AceDB:ResetProfile()
            end
            Refresh()
        end,
    })

    SLASH_ERBOPT1 = "/crbopt"
    SlashCmdList.ERBOPT = function()
        if InCombatLockdown and InCombatLockdown() then
            return
        end
        CludesUI:ShowModule("CludesUIResourceBars")
    end
end)
-- LoadOnDemand: this addon loads after PLAYER_LOGIN, so the event above will never fire; run the init now.
if IsLoggedIn() then
    initFrame:GetScript("OnEvent")(initFrame)
end
