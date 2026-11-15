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

    -- Forward decls for preview click-to-scroll
    local CreateHitOverlay
    local _hitOverlays = {}

    -- Preview Header Builder
    _previewHeaderBuilder = function(heading, hdrW)
        HintBuildStart(PAGE_DISPLAY, heading)
        _classHdrEmpty = PoolGen(heading) ~= nil
        local p = DB()
        if not p then
            return 0
        end
        _previewBuilding = true
        local _, class = UnitClass("player")

        local boxHolder = CreateFrame("Frame", nil, heading)
        boxHolder:SetSize(hdrW, 100)
        boxHolder:SetPoint("CENTER", heading, "CENTER", 0, 0)
        _previewFrames.container = boxHolder

        -- Scale the preview so pixel sizes match real bars on screen: compensate the panel's effective scale against UIParent's.
        local previewScale = UIParent:GetEffectiveScale() / heading:GetEffectiveScale()
        _previewScale = previewScale
        boxHolder:SetScale(previewScale)

        _previewSnap = function(val)
            local s = boxHolder:GetEffectiveScale()
            return math.floor(val * s + 0.5) / s
        end

        local sp = p.secondary
        local pipH = sp.pipHeight
        local isBar = mod.IsBarTypeSecondary()

        local pipC = CreateFrame("Frame", nil, boxHolder) -- hosts either pips or the bar preview
        _previewFrames.pipContainer = pipC
        _previewFrames.pips = {}

        if isBar then
            -- Bar-type preview (Devourer, Elemental Shaman)
            local totalW = p.primary.width or 214
            pipC:SetSize(totalW, pipH)
            pipC:SetPoint("CENTER", boxHolder, "CENTER", 0, 0)

            local backdrop = pipC:CreateTexture(nil, "BACKGROUND")
            backdrop:SetAllPoints()
            UnsnapTex(backdrop)
            pipC._barBg = backdrop

            -- Fill: status-bar style via texture + width clipping
            local fill = pipC:CreateTexture(nil, "ARTWORK")
            fill:SetPoint("LEFT")
            fill:SetHeight(pipH)
            local texKey = p.general.barTexture or "none"
            local texLookup = _G._CURB_BarTextures or {}
            local texPath = texLookup[texKey]
            if texPath then
                fill:SetTexture(texPath)
            else
                fill:SetTexture("Interface\\Buttons\\WHITE8x8")
            end
            UnsnapTex(fill)
            pipC._barFill = fill
        else
            -- pipWidth is the TOTAL bar width, divided evenly across pips; remainder pixels go into pip widths, never spacing.
            local numPips = PreviewPipCount()
            local totalW = sp.pipWidth
            local pipSp = sp.pipSpacing
            local baseW = math.floor((totalW - (numPips - 1) * pipSp) / numPips)
            local remainder = totalW - (numPips - 1) * pipSp - baseW * numPips

            local pipX = {}
            local cursor = 0
            for i = 1, numPips do
                pipX[i] = cursor
                cursor = cursor + baseW + (i <= remainder and 1 or 0) + pipSp
            end
            pipC:SetSize(totalW, pipH)
            pipC:SetPoint("CENTER", boxHolder, "CENTER", 0, 0)

            for i = 1, numPips do
                local pip = CreateFrame("Frame", nil, pipC)
                local thisPipW = baseW + (i <= remainder and 1 or 0)
                pip:SetSize(thisPipW, pipH)
                pip:SetPoint("LEFT", pipC, "LEFT", pipX[i], 0)
                local backdrop = pip:CreateTexture(nil, "BACKGROUND")
                backdrop:SetAllPoints()
                if sp.darkTheme then
                    local _dbr, _dbg, _dbb = CludesUI.GetDarkModeBg()
                    backdrop:SetColorTexture(_dbr, _dbg, _dbb, 1)
                elseif sp.classColored then
                    local cc = CLASS_COLORS[class]
                    local cr, cg, cb = cc and cc[1] or 0.95, cc and cc[2] or 0.90, cc and cc[3] or 0.60
                    backdrop:SetColorTexture(cr * 0.5, cg * 0.5, cb * 0.5, 0.5)
                else
                    backdrop:SetColorTexture(sp.bgR, sp.bgG, sp.bgB, sp.bgA)
                end
                UnsnapTex(backdrop)
                pip._bg = backdrop
                local fill = pip:CreateTexture(nil, "ARTWORK")
                fill:SetAllPoints()
                local texKey = p.general.barTexture or "none"
                local texLookup = _G._CURB_BarTextures or {}
                local texPath = texLookup[texKey]
                if texPath then
                    fill:SetTexture(texPath)
                else
                    fill:SetTexture("Interface\\Buttons\\WHITE8x8")
                end
                fill:SetVertexColor(1, 1, 1, 1)
                UnsnapTex(fill)
                pip._fill = fill
                pip._border = MakePreviewBorder(pip, 0, 0, 0, 0, 0)
                pip._border:SetShown(false)
                _previewFrames.pips[i] = pip
            end
        end

        local countTextOverlay = CreateFrame("Frame", nil, pipC)
        countTextOverlay:SetAllPoints(pipC)
        countTextOverlay:SetFrameLevel(pipC:GetFrameLevel() + 10)
        local countText = countTextOverlay:CreateFontString(nil, "OVERLAY")
        SetPVFont(countText, FONT_PATH, sp.textSize)
        countText:SetTextColor(1, 1, 1, 0.9)
        do
            local _pvTA = sp.textAnchor or "CENTER"
            countText:SetPoint(_pvTA, pipC, _pvTA, sp.textXOffset or 0, sp.textYOffset or 0)
        end
        pipC._countText = countText

        -- Built for every spec (cheap, pooled); UpdatePreviewHeader shows what applies.
        _previewFrames.powerBar = PreviewBar.Build(boxHolder)
        _previewFrames.healthBar = PreviewBar.Build(boxHolder)
        -- Arcane Soul: its section exists for retail Mages only, so does its
        -- element. The element replays the live sequence (the eye hides only
        -- it); the watcher keeps the on-screen sample running while this
        -- header shows.
        _previewFrames.arcaneSoul, _previewFrames.asDivider = nil, nil
        if class == "MAGE" and not CludesUI.IS_FOREVER then
            local asf = CreateFrame("Frame", nil, boxHolder)
            asf._fs = asf:CreateFontString(nil, "OVERLAY")
            asf._fs:SetPoint("CENTER", asf, "CENTER", 0, 0)
            asf._fs._asStamp = nil -- a reused font string is reset: style it again
            asf:SetSize(1, 1)
            if _G._CURB_ArcaneSoulDemoOnUpdate then
                asf:SetScript("OnUpdate", _G._CURB_ArcaneSoulDemoOnUpdate)
            end
            _previewFrames.arcaneSoul = asf

            local div = boxHolder:CreateTexture(nil, "ARTWORK")
            div:SetColorTexture(1, 1, 1, 0.10)
            UnsnapTex(div)
            div:Hide()
            _previewFrames.asDivider = div

            local screenDemo = _G._CURB_ArcaneSoulScreenDemo
            if screenDemo then
                local watch = CreateFrame("Frame", nil, boxHolder)
                watch:SetSize(1, 1)
                watch:SetPoint("CENTER")
                watch:SetScript("OnShow", function(self)
                    screenDemo(self, true)
                end)
                watch:SetScript("OnHide", function(self)
                    screenDemo(self, false)
                end)
                if watch:IsVisible() then
                    screenDemo(watch, true)
                end
            end
        end
        -- Element titles at header scale (the hint's size), on a child frame so
        -- the header cache stashes them with the rest.
        do
            local lblHost = CreateFrame("Frame", nil, heading)
            lblHost:SetAllPoints(heading)
            lblHost:SetFrameLevel(boxHolder:GetFrameLevel() + 1)
            local function Title(textValue)
                local fontStr = CludesUI.MakeFont(lblHost, 11, nil, 1, 1, 1)
                fontStr:SetAlpha(0.6)
                fontStr:SetText(textValue)
                fontStr:Hide()
                return fontStr
            end
            _previewFrames.labels = {
                classResource = Title(CludesUI.L("Class Resource")),
                power = Title(CludesUI.L("Power Bar")),
                health = Title(CludesUI.L("Health Bar")),
                arcaneSoul = _previewFrames.arcaneSoul and Title(CludesUI.L("Arcane Soul")) or nil,
            }
        end

        UpdatePreviewHeader()

        -- Hit overlays for preview click-to-scroll
        wipe(_hitOverlays)
        local overlayLevel = boxHolder:GetFrameLevel() + 20
        if pipC then
            CreateHitOverlay(pipC, "classResource", overlayLevel)
        end
        CreateHitOverlay(_previewFrames.powerBar, "power", overlayLevel)
        CreateHitOverlay(_previewFrames.healthBar, "health", overlayLevel)
        if _previewFrames.arcaneSoul then
            CreateHitOverlay(_previewFrames.arcaneSoul, "arcaneSoul", overlayLevel)
        end
        if pipC and pipC._countText then
            -- Padded frame around the text for easier clicking
            local ctHit = CreateFrame("Frame", nil, pipC)
            ctHit:SetPoint("TOPLEFT", pipC._countText, "TOPLEFT", -2, 2)
            ctHit:SetPoint("BOTTOMRIGHT", pipC._countText, "BOTTOMRIGHT", 2, -2)
            CreateHitOverlay(ctHit, "countText", overlayLevel + 5)
        end

        if _previewHintFS and not _previewHintFS:GetParent() then
            _previewHintFS = nil
        end

        -- Preview area height from the stack UpdatePreviewHeader laid out (0: nothing to show)
        local TOTAL_H = _headerBaseH
        local hintShown = TOTAL_H > 0 and not IsPreviewHintDismissed()
        -- Built with nothing to show, or without a class resource (its row was
        -- built for none, so a later spec or form with one needs a new build).
        _classHdrEmpty = ((TOTAL_H == 0 or not HasClassResource()) and PoolGen(heading) ~= nil) or nil
        if hintShown then
            if not _previewHintFS then
                -- Thin non-clipping child frame so the cache system stashes/restores it properly on page switch.
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
            _previewHintFS:Show()
            TOTAL_H = TOTAL_H + 35
        elseif _previewHintFS then
            _previewHintFS:Hide()
        end

        _previewBuilding = false
        return TOTAL_H
    end

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

    -- Preview click-to-scroll infrastructure
    local PlaySettingGlow -- made on first click: Widgets helpers load with the panel
    local _clickMappings = {} -- populated in BuildBarDisplayPage

    local function NavigateToSetting(key)
        local m = _clickMappings[key]
        if not m or not m.section or not m.target then
            return
        end

        CludesUI.DismissPreviewHint(_previewHintFS, _headerBaseH, 35, 5)

        local sf = CludesUI._scrollFrame
        if not sf then
            return
        end
        local _, _, _, _, headerY = m.section:GetPoint(1)
        if not headerY then
            return
        end
        local scrollPos = math.max(0, math.abs(headerY) - 40)
        CludesUI.SmoothScrollTo(scrollPos)
        local glowTarget = m.target
        if m.slotSide and m.target then
            local regionFrame = (m.slotSide == "left") and m.target._leftRegion or m.target._rightRegion
            if regionFrame then
                glowTarget = regionFrame
            end
        end
        PlaySettingGlow = PlaySettingGlow
            or CludesUI.MakeSettingGlow({
                color = CludesUI.CLUDES_GREEN,
                thickness = function()
                    return Pix.Scale(2)
                end,
                noSnap = true,
            })
        -- A row the page dressed again meanwhile (a rebuild) shows another setting now: no glow.
        local gen = PoolGen(glowTarget)
        C_Timer.After(0.15, function()
            if PoolGen(glowTarget) ~= gen then
                return
            end
            PlaySettingGlow(glowTarget)
        end)
    end

    CreateHitOverlay = function(element, mappingKey, frameLevelOverride)
        local button = CludesUI.CreatePreviewHitOverlay(
            element,
            NavigateToSetting,
            mappingKey,
            false,
            frameLevelOverride
        )
        _hitOverlays[#_hitOverlays + 1] = button
        return button
    end

    -- Non-debounced: smooth animation of scale/offset changes
    local function SmoothRefresh()
        Refresh()
        UpdatePreviewHeader()
    end

    local function RefreshClass()
        DebouncedRefresh()
        UpdatePreviewHeader()
    end
    local function RefreshHealth()
        DebouncedRefresh()
        UpdatePreviewHeader()
    end
    local function RefreshPower()
        DebouncedRefresh()
        UpdatePreviewHeader()
    end
    local function RebuildClass()
        DebouncedRefresh()
        UpdatePreviewHeader()
    end
    local function RebuildHealth()
        DebouncedRefresh()
        UpdatePreviewHeader()
    end
    local function RebuildPower()
        DebouncedRefresh()
        UpdatePreviewHeader()
    end

    -- Hash line positions as typed: keeps the numeric tokens (0 and up), comma-joined. Shared by
    -- the bar-wide hash cog and the Threshold & Hash Lines editor's entry field. exact: each token
    -- is read trimmed, as the bar parses it ("25 50" is no position), instead of with its spaces
    -- dropped ("50 000" = 50000).
    local function SanitizePositions(str, exact)
        if not str or str == "" then
            return ""
        end
        local result = {}
        for token in tostring(str):gmatch("[^,]+") do
            local num = tonumber(exact and token:match("^%s*(.-)%s*$") or (token:gsub("%s", "")))
            if num and num >= 0 then
                result[#result + 1] = tostring(num)
            end
        end
        return table.concat(result, ", ")
    end

    -- Cog + popup for simple per-bar hash lines (Health/Power). cfg = { parentRgn, getBarData, refreshFn, popupTitle, anchorTo }; returns cogBtn.
    local function BuildHashCog(conf)
        local getBarData = conf.getBarData
        local refreshFn = conf.refreshFn or function() end

        local function HashOff()
            local c = getBarData()
            return not (c and c.hashEnabled)
        end

        local DIS_TIP = CludesUI.L("Enable hash lines first")
        local rowList = {
            {
                type = "toggle",
                label = CludesUI.L("Show Hash Lines"),
                tooltip = CludesUI.L("Draw tick lines across the bar at positions you choose."),
                get = function()
                    local c = getBarData()
                    return c and c.hashEnabled or false
                end,
                set = function(v)
                    local c = getBarData()
                    if not c then
                        return
                    end
                    c.hashEnabled = v and true or false
                    refreshFn()
                end,
            },
            {
                type = "input",
                label = CludesUI.L("Positions"),
                inputWidth = 130,
                commitOnBlur = true,
                disabled = HashOff,
                disabledTooltip = DIS_TIP,
                get = function()
                    local c = getBarData()
                    return c and c.hashValues or ""
                end,
                set = function(v)
                    local c = getBarData()
                    if not c then
                        return
                    end
                    c.hashValues = SanitizePositions(v)
                    refreshFn()
                end,
            },
            {
                type = "segmented",
                label = CludesUI.L("Mode"),
                disabled = HashOff,
                disabledTooltip = DIS_TIP,
                keys = { "percent", "value" },
                labels = { percent = "%", value = "Value" },
                get = function()
                    local c = getBarData()
                    return (c and c.hashMode) or "percent"
                end,
                set = function(k)
                    local c = getBarData()
                    if not c then
                        return
                    end
                    c.hashMode = k
                    refreshFn()
                end,
            },
            {
                type = "slider",
                label = CludesUI.L("Thickness"),
                min = 1,
                max = 5,
                step = 1,
                disabled = HashOff,
                disabledTooltip = DIS_TIP,
                get = function()
                    local c = getBarData()
                    return c and c.hashWidth or 1
                end,
                set = function(v)
                    local c = getBarData()
                    if not c then
                        return
                    end
                    c.hashWidth = v
                    refreshFn()
                end,
            },
            {
                type = "colorpicker",
                label = CludesUI.L("Color"),
                hasAlpha = true,
                disabled = HashOff,
                disabledTooltip = DIS_TIP,
                get = function()
                    local c = getBarData()
                    if not c then
                        return 1, 1, 1, 0.7
                    end
                    return c.hashColorR or 1, c.hashColorG or 1, c.hashColorB or 1, c.hashColorA or 0.7
                end,
                set = function(r, g, b, a)
                    local c = getBarData()
                    if not c then
                        return
                    end
                    c.hashColorR, c.hashColorG, c.hashColorB, c.hashColorA = r, g, b, a
                    refreshFn()
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
            rows = rowList,
        })
    end

    -- Druid-only per-form toggles, as cog rows (nil for any other class): a row
    -- is on while that form shows; `field` is the map of the forms switched off,
    -- "textDisabledForms" (text rows) or "barDisabledForms" (whole bars, and the
    -- WoW Forever swing timer), read by _CURB_TextHiddenByForm / _CURB_BarHiddenByForm.
    local function FormToggleRows(cfgFn, refreshFn, field)
        local _, class = UnitClass("player")
        if class ~= "DRUID" then
            return nil
        end
        local FORMS = {
            { key = "mana", label = "Caster" },
            { key = "rage", label = "Bear" },
            { key = "energy", label = "Cat" },
            { key = "moonkin", label = "Moonkin" },
        }
        local rowList = {}
        for _, f in ipairs(FORMS) do
            local key = f.key
            rowList[#rowList + 1] = {
                type = "toggle",
                label = f.label,
                get = function()
                    local c = cfgFn()
                    return not (c and c[field] and c[field][key])
                end,
                set = function(v)
                    local c = cfgFn()
                    if not c then
                        return
                    end
                    if v then
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
        return rowList
    end

    -- Druid-only per-form popup button. `field` picks the map the toggles write: "textDisabledForms" (text rows) or "barDisabledForms" (whole-bar rows).
    local function AddFormDisableBtn(rgn, leftOf, cfgFn, refreshFn, field, title, tooltip)
        field = field or "textDisabledForms"
        local rowList = FormToggleRows(cfgFn, refreshFn, field)
        if not rowList then
            return
        end
        title = title or "Enable/Disable per Form"
        tooltip = tooltip or CludesUI.L(title)
        local button = CludesUI.BuildInlineCog(rgn, {
            anchorTo = leftOf,
            tip = tooltip,
            title = title,
            bgAlpha = 1,
            frameStrata = "FULLSCREEN_DIALOG",
            frameLevel = 500,
            rows = rowList,
        })
        return button
    end
    -- The L() literals keep both popup titles in the static locale key list: .tools/extract-locale-keys.sh only sees literal string arguments.
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

    -- Multi-band threshold editor (opt-in): popup opened per threshold-spec entry from
    -- its "Bands" button, editing entry.bands -- an ordered list of { to=<boundary>, r,g,b,a }
    -- color stops. `to` is a resource count for pip resources, or a percent/value for bars.
    -- ShowBandEditor() rebinds it to the calling bar each time it opens.
    local _bandCloseIcon = "Interface\\AddOns\\CludesUI\\media\\icons\\cui-close.png"
    local bandPopup
    local _bandRows = {}
    local _bandEntryIdx
    local _bandGetBarData, _bandRefreshFn, _bandCountBased
    local _bandLockPercent, _bandPercentMax -- Brewmaster stagger: force percent, cap 500
    local _bandDefR, _bandDefG, _bandDefB, _bandDefA = 1, 0.2, 0.2, 1
    local _bandModeRow, _bandModeSeg, _bandModeSegRefresh, _bandModeHint, _bandAddBtn, _bandTitleFS
    local _bandReverseRow, _bandReverseSeg, _bandReverseSegRefresh
    local BAND_POPUP_W = 300
    local BAND_ROW_H = 26
    local BAND_PAD = 14
    local BAND_GAP = 10
    local RefreshBandEditor -- forward decl

    -- Shared explainer tooltip: Multi toggle + Bands button
    local BAND_HELP_TIP = "Color the bar by ranges instead of a single threshold.\n"
        .. "Up to (<=) / From (>=)\n"
        .. "Any remaning values outside the bands will use fill color.\n"
        .. "|cff888888Bars can use % or actual value; pip resources use counts.|r"

    local BAND_REPLACES_TIP = "Single threshold is off while Multi-band is on.\n"

    -- Shown on the greyed percent/value control for Brewmaster stagger
    local STAGGER_PCT_TIP = "Stagger value can only be percent based"

    local function CurrentBandEntry()
        if not _bandEntryIdx or not _bandGetBarData then
            return nil
        end
        local edge = _bandGetBarData()
        if not edge or not edge.thresholdSpecs then
            return nil
        end
        return edge.thresholdSpecs[_bandEntryIdx]
    end

    local function SortBands(bands)
        table.sort(bands, function(a, b)
            return (a.to or 0) < (b.to or 0)
        end)
    end

    local function BuildBandPopup()
        bandPopup = CreateFrame("Frame", nil, CludesUI.OverlayParent())
        bandPopup:SetFrameStrata("FULLSCREEN_DIALOG")
        bandPopup:SetFrameLevel(260)
        bandPopup:SetClampedToScreen(true)
        bandPopup:EnableMouse(true)
        bandPopup:SetScale(CludesUI.GetPopupScale())
        bandPopup:Hide()
        Pix.Size(bandPopup, BAND_POPUP_W, 200)

        local backdrop = bandPopup:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(0.062, 0.070, 0.082, 0.97)
        bandPopup._brd = CludesUI.MakeRoundedBorder(bandPopup, 1, 1, 1, 0.18, backdrop)

        local clickCatcher = CreateFrame("Button", nil, bandPopup)
        clickCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
        clickCatcher:SetFrameLevel(bandPopup:GetFrameLevel() - 1)
        clickCatcher:SetAllPoints((CludesUI:GetMainFrame()) or UIParent)
        clickCatcher:SetScript("OnClick", function()
            bandPopup:Hide()
        end)
        clickCatcher:Hide()
        -- Close on entering combat
        bandPopup:SetScript("OnEvent", function(self, evt)
            if evt == "PLAYER_REGEN_DISABLED" then
                self:Hide()
            end
        end)
        bandPopup:SetScript("OnShow", function(self)
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
        bandPopup:SetScript("OnHide", function(self)
            clickCatcher:Hide()
            self:UnregisterEvent("PLAYER_REGEN_DISABLED")
            self:SetScript("OnUpdate", nil)
        end)
        CludesUI.TrackOverlay(bandPopup)
        CludesUI.PadHint(bandPopup, "nodepass")
        CludesUI.PadHint(clickCatcher, "nodepass")
        CludesUI._popupFrames[#CludesUI._popupFrames + 1] = { popup = bandPopup }
        CludesUI:RegisterOnHide(function()
            bandPopup:Hide()
        end)
        CludesUI:RegisterOnCollapse(function(on)
            if on then
                bandPopup:Hide()
            end
        end)

        _bandTitleFS = CludesUI.MakeFont(bandPopup, 13, nil, 1, 1, 1)
        _bandTitleFS:SetAlpha(0.6)
        _bandTitleFS:SetPoint("TOP", bandPopup, "TOP", 0, -BAND_PAD)
        _bandTitleFS:SetText(CludesUI.L("Color Bands"))

        -- Labeled row (label left, control right), matching the detail-pane rows
        local function HeaderRow(labelText)
            local rf = CreateFrame("Frame", nil, bandPopup)
            rf:SetFrameLevel(bandPopup:GetFrameLevel() + 3)
            Pix.Height(rf, BAND_ROW_H)
            local labelFS = CludesUI.MakeFont(rf, 12, nil, 1, 1, 1)
            labelFS:SetAlpha(0.6)
            labelFS:SetPoint("LEFT", rf, "LEFT", 0, 0)
            labelFS:SetText(CludesUI.L(labelText))
            rf._lbl = labelFS
            return rf
        end

        local _ -- the switches' unused second return (never the global)
        -- Value units segmented switch (Amount / Percent), bar-type only; count-based shows a hint instead.
        _bandModeRow = HeaderRow("Values as")
        _bandModeSeg, _, _bandModeSegRefresh = CludesUI.BuildSegmentedControl({
            parent = _bandModeRow,
            keys = { "amount", "percent" },
            labels = { amount = "Amount", percent = "Percent" },
            autoWidth = true,
            square = true,
            height = 22,
            getChecked = function(key)
                local ent = CurrentBandEntry()
                local isPercent = _bandLockPercent or not (ent and ent.bandMode == "value")
                if key == "percent" then
                    return isPercent
                else
                    return not isPercent
                end
            end,
            isDisabled = function()
                return _bandLockPercent and true or false
            end,
            onToggle = function(key)
                if _bandLockPercent then
                    return
                end
                local ent = CurrentBandEntry()
                if not ent then
                    return
                end
                ent.bandMode = (key == "percent") and "percent" or "value"
                if _bandRefreshFn then
                    _bandRefreshFn()
                end
                RefreshBandEditor()
            end,
        })
        _bandModeSeg:SetPoint("RIGHT", _bandModeRow, "RIGHT", 0, 0)
        -- Disabled-state tooltip: Brewmaster stagger is percent-only
        local _bandModeDis = CreateFrame("Frame", nil, _bandModeRow)
        _bandModeDis:SetAllPoints(_bandModeSeg)
        _bandModeDis:SetFrameLevel(_bandModeSeg:GetFrameLevel() + 5)
        _bandModeDis:EnableMouse(true)
        _bandModeDis:SetScript("OnEnter", function(self)
            CludesUI.ShowWidgetTooltip(self, CludesUI.L(STAGGER_PCT_TIP))
        end)
        _bandModeDis:SetScript("OnLeave", function()
            CludesUI.HideWidgetTooltip()
        end)
        _bandModeDis:Hide()
        _bandModeRow._staggerDis = _bandModeDis
        _bandModeHint = CludesUI.MakeFont(bandPopup, 10, nil, 1, 1, 1)
        _bandModeHint:SetAlpha(0.4)

        -- Direction segmented switch (always one of two values)
        _bandReverseRow = HeaderRow("Direction")
        _bandReverseSeg, _, _bandReverseSegRefresh = CludesUI.BuildSegmentedControl({
            parent = _bandReverseRow,
            keys = { "upto", "from" },
            labels = { upto = "Up to", from = "From" },
            autoWidth = true,
            square = true,
            height = 22,
            getChecked = function(key)
                local ent = CurrentBandEntry()
                local reverse = ent and ent.bandReverse and true or false
                if key == "from" then
                    return reverse
                else
                    return not reverse
                end
            end,
            onToggle = function(key)
                local ent = CurrentBandEntry()
                if not ent then
                    return
                end
                ent.bandReverse = (key == "from")
                if _bandRefreshFn then
                    _bandRefreshFn()
                end
                RefreshBandEditor()
            end,
        })
        _bandReverseSeg:SetPoint("RIGHT", _bandReverseRow, "RIGHT", 0, 0)

        -- Add Band button
        _bandAddBtn = CreateFrame("Button", nil, bandPopup)
        Pix.Size(_bandAddBtn, BAND_POPUP_W - BAND_PAD * 2, 26)
        _bandAddBtn:SetFrameLevel(bandPopup:GetFrameLevel() + 3)
        local abg = CludesUI.SolidTex(_bandAddBtn, "BACKGROUND", 0.050, 0.058, 0.068, 0.92)
        abg:SetAllPoints()
        _bandAddBtn._border = CludesUI.MakeRoundedBorder(_bandAddBtn, 1, 1, 1, 0.4, abg)
        local albl = CludesUI.MakeFont(_bandAddBtn, 12, nil, 1, 1, 1)
        albl:SetAlpha(0.5)
        albl:SetPoint("CENTER")
        albl:SetText(CludesUI.L("+ Add Band"))
        _bandAddBtn:SetScript("OnEnter", function()
            albl:SetAlpha(0.7)
            if _bandAddBtn._border and _bandAddBtn._border.SetColor then
                _bandAddBtn._border:SetColor(1, 1, 1, 0.6)
            end
        end)
        _bandAddBtn:SetScript("OnLeave", function()
            albl:SetAlpha(0.5)
            if _bandAddBtn._border and _bandAddBtn._border.SetColor then
                _bandAddBtn._border:SetColor(1, 1, 1, 0.4)
            end
        end)
        _bandAddBtn:SetScript("OnClick", function()
            local ent = CurrentBandEntry()
            if not ent then
                return
            end
            if not ent.bands then
                ent.bands = {}
            end
            local last = ent.bands[#ent.bands]
            local nextTo = last and ((last.to or 0) + 1) or 1
            ent.bands[#ent.bands + 1] =
                { to = nextTo, r = _bandDefR, g = _bandDefG, b = _bandDefB, a = _bandDefA }
            SortBands(ent.bands)
            if _bandRefreshFn then
                _bandRefreshFn()
            end
            RefreshBandEditor()
        end)
    end

    -- Lazily create the widgets for band row k; returns the row table
    local function EnsureBandRow(k)
        local row = _bandRows[k]
        if row then
            return row
        end
        row = {}
        local rf = CreateFrame("Frame", nil, bandPopup)
        rf:SetSize(BAND_POPUP_W - BAND_PAD * 2, BAND_ROW_H)
        rf:SetFrameLevel(bandPopup:GetFrameLevel() + 2)
        row.frame = rf

        local labelFS = CludesUI.MakeFont(rf, 12, nil, 1, 1, 1)
        labelFS:SetAlpha(0.6)
        labelFS:SetPoint("LEFT", rf, "LEFT", 2, 0)
        labelFS:SetText(CludesUI.L("Up to")) -- band colors values up to `to`
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

        -- Commit on focus loss. Enter clears focus -> triggers this; Escape sets _cancelCommit so leaving the field discards the typed text.
        local function CommitInput(self)
            if self._cancelCommit then
                self._cancelCommit = nil
                return
            end
            local ent = CurrentBandEntry()
            local band = ent and ent.bands and ent.bands[row._idx]
            if not band then
                return
            end
            local val = tonumber(self:GetText())
            if val then
                local pctMax = _bandPercentMax or 100
                local hi = _bandCountBased and 100
                    or ((not _bandLockPercent and ent.bandMode == "value") and 1000000 or pctMax)
                val = math.max(1, math.min(hi, math.floor(val + 0.5)))
                band.to = val
                SortBands(ent.bands)
                if _bandRefreshFn then
                    _bandRefreshFn()
                end
            end
            RefreshBandEditor()
        end
        input:SetScript("OnEditFocusLost", CommitInput)
        input:SetScript("OnEnterPressed", function(self)
            self:ClearFocus()
        end)
        input:SetScript("OnEscapePressed", function(self)
            self._cancelCommit = true
            self:ClearFocus()
            RefreshBandEditor()
        end)

        local colorSwatch, swatchSnap = CludesUI.BuildColorSwatch(rf, rf:GetFrameLevel() + 3, function()
            local ent = CurrentBandEntry()
            local band = ent and ent.bands and ent.bands[row._idx]
            if not band then
                return _bandDefR, _bandDefG, _bandDefB, _bandDefA
            end
            return band.r or _bandDefR, band.g or _bandDefG, band.b or _bandDefB, band.a or _bandDefA
        end, function(r, g, b, a)
            local ent = CurrentBandEntry()
            local band = ent and ent.bands and ent.bands[row._idx]
            if band then
                band.r, band.g, band.b, band.a = r, g, b, a
                if _bandRefreshFn then
                    _bandRefreshFn()
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
        delIcon:SetTexture(_bandCloseIcon)
        delIcon:SetAlpha(0.4)
        delBtn:SetScript("OnEnter", function()
            delIcon:SetAlpha(0.9)
        end)
        delBtn:SetScript("OnLeave", function()
            delIcon:SetAlpha(0.4)
        end)
        delBtn:SetScript("OnClick", function()
            local ent = CurrentBandEntry()
            if ent and ent.bands and ent.bands[row._idx] then
                table.remove(ent.bands, row._idx)
                if _bandRefreshFn then
                    _bandRefreshFn()
                end
                RefreshBandEditor()
            end
        end)
        row.delBtn = delBtn

        _bandRows[k] = row
        return row
    end

    RefreshBandEditor = function()
        if not bandPopup then
            return
        end
        local ent = CurrentBandEntry()
        if not ent then
            bandPopup:Hide()
            return
        end
        if not ent.bands then
            ent.bands = {}
        end

        local curY = -(BAND_PAD + 24) -- below the title

        local function placeRow(rf)
            rf:ClearAllPoints()
            Pix.Point(rf, "TOPLEFT", bandPopup, "TOPLEFT", BAND_PAD, curY)
            Pix.Point(rf, "TOPRIGHT", bandPopup, "TOPRIGHT", -BAND_PAD, curY)
            rf:Show()
            curY = curY - BAND_ROW_H - BAND_GAP
        end

        -- Mode row (bar-type) or a hint (count-based: boundaries are counts)
        if _bandCountBased then
            _bandModeRow:Hide()
            _bandModeHint:ClearAllPoints()
            _bandModeHint:SetPoint("TOPLEFT", bandPopup, "TOPLEFT", BAND_PAD, curY - 4)
            _bandModeHint:SetText(CludesUI.L("Boundaries are resource counts"))
            _bandModeHint:Show()
            curY = curY - 18 - BAND_GAP
        else
            _bandModeHint:Hide()
            if _bandModeSegRefresh then
                _bandModeSegRefresh()
            end
            -- Brewmaster stagger: percent locked, so grey the control + tooltip
            if _bandModeRow._staggerDis then
                _bandModeRow._staggerDis:SetShown(_bandLockPercent and true or false)
            end
            if _bandModeRow._lbl then
                _bandModeRow._lbl:SetAlpha(_bandLockPercent and 0.3 or 0.6)
            end
            placeRow(_bandModeRow)
        end

        -- Row label follows direction: "From" (>=) when reverse, else "Up to"
        local reverse = ent.bandReverse and true or false

        if _bandReverseSegRefresh then
            _bandReverseSegRefresh()
        end
        placeRow(_bandReverseRow)
        local rowLabel = reverse and CludesUI.L("From") or CludesUI.L("Up to")
        local num = #ent.bands
        for k = 1, num do
            local row = EnsureBandRow(k)
            row._idx = k
            row.lbl:SetText(rowLabel)
            row.frame:ClearAllPoints()
            Pix.Point(row.frame, "TOPLEFT", bandPopup, "TOPLEFT", BAND_PAD, curY)
            row.input:SetText(tostring(ent.bands[k].to or 1))
            if row.swatchSnap then
                row.swatchSnap()
            end
            row.frame:Show()
            curY = curY - BAND_ROW_H - 4
        end
        for k = num + 1, #_bandRows do
            if _bandRows[k] then
                _bandRows[k].frame:Hide()
            end
        end

        curY = curY - 4
        _bandAddBtn:ClearAllPoints()
        Pix.Point(_bandAddBtn, "TOPLEFT", bandPopup, "TOPLEFT", BAND_PAD, curY)
        curY = curY - 26

        local totalH = math.abs(curY) + BAND_PAD
        Pix.Size(bandPopup, BAND_POPUP_W, totalH)
        bandPopup._brd:Fit()
    end

    -- params = { getBarData, refreshFn, entryIdx, anchor, countBased, defR/G/B/A }
    local function ShowBandEditor(params)
        if not bandPopup then
            BuildBandPopup()
        end
        _bandGetBarData = params.getBarData
        _bandRefreshFn = params.refreshFn
        _bandEntryIdx = params.entryIdx
        _bandCountBased = params.countBased and true or false
        _bandLockPercent = params.lockPercent and true or false
        _bandPercentMax = params.percentMax
        _bandDefR = params.defR or 1
        _bandDefG = params.defG or 0.2
        _bandDefB = params.defB or 0.2
        _bandDefA = params.defA or 1
        local ent = CurrentBandEntry()
        if ent then
            if _bandLockPercent then
                ent.bandMode = "percent"
            end -- stagger: percent-only
            if not ent.bands then
                ent.bands = {}
            end
            -- First open seeds a starter band from the single threshold
            if #ent.bands == 0 then
                local seedTo = _bandCountBased and (ent.thresholdCount or 3) or (ent.thresholdPct or 30)
                ent.bands[1] = {
                    to = seedTo,
                    r = ent.thresholdR or _bandDefR,
                    g = ent.thresholdG or _bandDefG,
                    b = ent.thresholdB or _bandDefB,
                    a = ent.thresholdA or _bandDefA,
                }
            end
        end
        RefreshBandEditor()
        bandPopup:ClearAllPoints()
        bandPopup:SetPoint("TOP", params.anchor, "BOTTOM", 0, -4)
        bandPopup:Show()
    end

    -- Colour list editor: a per-threshold-entry list of { spellID, r,g,b,a } stored in
    -- entry[o.field] (per-spec via the entry's specIDs). List order = priority: the first
    -- matching spell wins, and rows drag to reorder like BuildCogPopup's 'reorder' row.
    -- Buff Colors and Spender Colors each build one. o = { field, title, addLabel }
    -- (title/addLabel already localized). Returns Show(params), params =
    -- { getBarData, refreshFn, entryIdx, anchor }; the popup is built on first Show.
    local function MakeColorListEditor(o)
        local field = o.field
        local POPUP_W, ROW_H = 320, 26
        local STEP = ROW_H + 4
        local dialog, addBtn, insLine
        local rowList = {}
        local entryIdx, getBarData, refreshFn
        local drag = { row = nil, startY = nil, active = false }
        local Refresh, DragTick -- forward decls

        local function CurrentEntry()
            if not entryIdx or not getBarData then
                return nil
            end
            local edge = getBarData()
            if not edge or not edge.thresholdSpecs then
                return nil
            end
            return edge.thresholdSpecs[entryIdx]
        end

        -- The list item a row edits, or nil
        local function RowItem(row)
            local ent = CurrentEntry()
            local list = ent and ent[field]
            return list and list[row._idx]
        end

        local function OnPopupUpdate(pp)
            if drag.row then
                DragTick()
                return
            end -- dragging: move/reorder, never dismiss
            if IsMouseButtonDown("LeftButton") then
                local mf = CludesUI._mainFrame
                if not pp:IsMouseOver() and not (mf and mf:IsMouseOver()) then
                    pp:Hide()
                end
            end
        end

        local function Build()
            dialog = CreateFrame("Frame", nil, CludesUI.OverlayParent())
            dialog:SetFrameStrata("FULLSCREEN_DIALOG")
            dialog:SetFrameLevel(260)
            dialog:SetClampedToScreen(true)
            dialog:EnableMouse(true)
            dialog:SetScale(CludesUI.GetPopupScale())
            dialog:Hide()
            Pix.Size(dialog, POPUP_W, 200)
            local backdrop = dialog:CreateTexture(nil, "BACKGROUND")
            backdrop:SetAllPoints()
            backdrop:SetColorTexture(0.062, 0.070, 0.082, 0.97)
            dialog._brd = CludesUI.MakeRoundedBorder(dialog, 1, 1, 1, 0.18, backdrop)

            -- Insertion line shown while dragging a row; theme accent, matches the raid "Sort By" reorder line
            insLine = dialog:CreateTexture(nil, "OVERLAY", nil, 7)
            insLine:SetHeight(2)
            local eg = CludesUI.CLUDES_GREEN
            insLine:SetColorTexture(eg.r, eg.g, eg.b, 0.9)
            insLine:Hide()

            local clickCatcher = CreateFrame("Button", nil, dialog)
            clickCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
            clickCatcher:SetFrameLevel(dialog:GetFrameLevel() - 1)
            clickCatcher:SetAllPoints((CludesUI:GetMainFrame()) or UIParent)
            clickCatcher:SetScript("OnClick", function()
                if drag.active then
                    return
                end
                dialog:Hide()
            end)
            clickCatcher:Hide()
            -- Close on entering combat (the event is registered only while shown)
            dialog:SetScript("OnEvent", function(self)
                self:Hide()
            end)
            dialog:SetScript("OnShow", function(self)
                clickCatcher:Show()
                self:RegisterEvent("PLAYER_REGEN_DISABLED")
                self:SetScript("OnUpdate", OnPopupUpdate)
            end)
            dialog:SetScript("OnHide", function(self)
                clickCatcher:Hide()
                self:UnregisterEvent("PLAYER_REGEN_DISABLED")
                self:SetScript("OnUpdate", nil)
                -- A combat or panel close can land mid-drag: drop it (Show re-lays the rows)
                drag.row = nil
                drag.active = false
                insLine:Hide()
            end)
            CludesUI.TrackOverlay(dialog)
            CludesUI.PadHint(dialog, "nodepass")
            CludesUI.PadHint(clickCatcher, "nodepass")
            CludesUI._popupFrames[#CludesUI._popupFrames + 1] = { popup = dialog }
            CludesUI:RegisterOnHide(function()
                dialog:Hide()
            end)
            CludesUI:RegisterOnCollapse(function(on)
                if on then
                    dialog:Hide()
                end
            end)

            local titleFS = CludesUI.MakeFont(dialog, 13, nil, 1, 1, 1)
            titleFS:SetAlpha(0.7)
            titleFS:SetPoint("TOP", dialog, "TOP", 0, -BAND_PAD)
            titleFS:SetText(o.title)
            local hintFS = CludesUI.MakeFont(dialog, 10, nil, 1, 1, 1, 0.25)
            hintFS:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -BAND_PAD - 4)
            hintFS:SetText(CludesUI.L("Drag to Reorder"))

            addBtn = CreateFrame("Button", nil, dialog)
            Pix.Size(addBtn, POPUP_W - BAND_PAD * 2, 26)
            addBtn:SetFrameLevel(dialog:GetFrameLevel() + 3)
            local abg = CludesUI.SolidTex(addBtn, "BACKGROUND", 0.050, 0.058, 0.068, 0.92)
            abg:SetAllPoints()
            addBtn._border = CludesUI.MakeRoundedBorder(addBtn, 1, 1, 1, 0.4, abg)
            local albl = CludesUI.MakeFont(addBtn, 12, nil, 1, 1, 1)
            albl:SetAlpha(0.5)
            albl:SetPoint("CENTER")
            albl:SetText(o.addLabel)
            addBtn:SetScript("OnEnter", function()
                albl:SetAlpha(0.7)
                addBtn._border:SetColor(1, 1, 1, 0.6)
            end)
            addBtn:SetScript("OnLeave", function()
                albl:SetAlpha(0.5)
                addBtn._border:SetColor(1, 1, 1, 0.4)
            end)
            addBtn:SetScript("OnClick", function()
                local ent = CurrentEntry()
                if not ent then
                    return
                end
                if not ent[field] then
                    ent[field] = {}
                end
                ent[field][#ent[field] + 1] = { spellID = nil, r = 0.2, g = 0.6, b = 1.0, a = 1 }
                if refreshFn then
                    refreshFn()
                end
                Refresh()
            end)
        end

        local function EnsureRow(k)
            local row = rowList[k]
            if row then
                return row
            end
            row = {}
            local rf = CreateFrame("Frame", nil, dialog)
            rf:SetSize(POPUP_W - BAND_PAD * 2, ROW_H)
            rf:SetFrameLevel(dialog:GetFrameLevel() + 2)
            row.frame = rf

            local input = CreateFrame("EditBox", nil, rf)
            input:SetSize(58, 22)
            input:SetPoint("LEFT", rf, "LEFT", 16, 0)
            input:SetFrameLevel(rf:GetFrameLevel() + 2)
            input:SetAutoFocus(false)
            input:SetFont(CludesUI.GetFontPath("main") or "Fonts\\FRIZQT__.TTF", 12, "")
            input:SetTextColor(1, 1, 1, 0.75)
            input:SetJustifyH("CENTER")
            input:SetNumeric(true)
            input:SetMaxLetters(7)
            local inBg = input:CreateTexture(nil, "BACKGROUND")
            inBg:SetAllPoints()
            inBg:SetColorTexture(0.12, 0.12, 0.12, 0.8)
            CludesUI.MakeRoundedBorder(input, 1, 1, 1, 0.08, inBg)
            row.input = input

            -- Drag grip: list order = priority, so rows are draggable
            local grip = CreateFrame("Button", nil, rf)
            grip:SetSize(14, ROW_H)
            grip:SetPoint("LEFT", rf, "LEFT", 0, 0)
            grip:SetFrameLevel(rf:GetFrameLevel() + 4)
            local gripFS = CludesUI.MakeFont(grip, 13, nil, 1, 1, 1, 0.25)
            gripFS:SetPoint("CENTER")
            gripFS:SetText("=")
            grip:SetScript("OnEnter", function()
                gripFS:SetTextColor(1, 1, 1, 0.6)
            end)
            grip:SetScript("OnLeave", function()
                gripFS:SetTextColor(1, 1, 1, 0.25)
            end)
            grip:SetScript("OnMouseDown", function(self, b)
                if b ~= "LeftButton" then
                    return
                end
                local _, cy = GetCursorPosition()
                drag.row = row
                drag.startY = cy
                drag.active = false
            end)
            row.grip = grip

            local nameFS = CludesUI.MakeFont(rf, 11, nil, 1, 1, 1)
            nameFS:SetAlpha(0.6)
            nameFS:SetPoint("LEFT", input, "RIGHT", 8, 0)
            nameFS:SetJustifyH("LEFT")
            nameFS:SetWidth(150)
            nameFS:SetWordWrap(false)
            row.nameFS = nameFS

            local function RefreshName()
                local e = RowItem(row)
                local ident = e and e.spellID
                if ident then
                    nameFS:SetText(
                        C_Spell.GetSpellName(ident)
                            or (CludesUI.COLOR_CODES.BAD .. CludesUI.L("Unknown ID") .. "|r")
                    )
                else
                    nameFS:SetText(CludesUI.COLOR_CODES.DIM .. CludesUI.L("(enter Spell ID)") .. "|r")
                end
            end
            row.RefreshName = RefreshName

            local function CommitInput(self)
                if self._cancelCommit then
                    self._cancelCommit = nil
                    return
                end
                local e = RowItem(row)
                if not e then
                    return
                end
                local val = tonumber(self:GetText())
                e.spellID = (val and val > 0) and val or nil
                RefreshName()
                if refreshFn then
                    refreshFn()
                end
            end
            input:SetScript("OnEditFocusLost", CommitInput)
            input:SetScript("OnEnterPressed", function(self)
                self:ClearFocus()
            end)
            input:SetScript("OnEscapePressed", function(self)
                self._cancelCommit = true
                self:ClearFocus()
                Refresh()
            end)

            local colorSwatch, swatchSnap = CludesUI.BuildColorSwatch(rf, rf:GetFrameLevel() + 3, function()
                local e = RowItem(row)
                if not e then
                    return 0.2, 0.6, 1.0, 1
                end
                return e.r or 0.2, e.g or 0.6, e.b or 1.0, e.a or 1
            end, function(r, g, b, a)
                local e = RowItem(row)
                if e then
                    e.r, e.g, e.b, e.a = r, g, b, a
                    if refreshFn then
                        refreshFn()
                    end
                end
            end, true, 19)
            colorSwatch:SetPoint("RIGHT", rf, "RIGHT", -24, 0)
            row.swatch = colorSwatch
            row.swatchSnap = swatchSnap

            local delBtn = CreateFrame("Button", nil, rf)
            delBtn:SetSize(14, 14)
            delBtn:SetPoint("RIGHT", rf, "RIGHT", -2, 0)
            delBtn:SetFrameLevel(rf:GetFrameLevel() + 3)
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
                local ent = CurrentEntry()
                if ent and ent[field] and ent[field][row._idx] then
                    table.remove(ent[field], row._idx)
                    if refreshFn then
                        refreshFn()
                    end
                    Refresh()
                end
            end)
            row.delBtn = delBtn

            rowList[k] = row
            return row
        end

        Refresh = function()
            if not dialog then
                return
            end
            local ent = CurrentEntry()
            if not ent then
                dialog:Hide()
                return
            end
            if not ent[field] then
                ent[field] = {}
            end
            local list = ent[field]
            local curY = -(BAND_PAD + 24)
            local num = #list
            for k = 1, num do
                local row = EnsureRow(k)
                row._idx = k
                row.frame:ClearAllPoints()
                Pix.Point(row.frame, "TOPLEFT", dialog, "TOPLEFT", BAND_PAD, curY)
                row._baseY = curY -- for the drag-reorder hit test
                row.frame:SetFrameLevel(dialog:GetFrameLevel() + 2) -- reset after a drag raised it
                row.frame:SetAlpha(1)
                row.input:SetText(list[k].spellID and tostring(list[k].spellID) or "")
                row.RefreshName()
                row.swatchSnap()
                row.frame:Show()
                curY = curY - ROW_H - 4
            end
            for k = num + 1, #rowList do
                if rowList[k] then
                    rowList[k].frame:Hide()
                end
            end
            curY = curY - 4
            addBtn:ClearAllPoints()
            Pix.Point(addBtn, "TOPLEFT", dialog, "TOPLEFT", BAND_PAD, curY)
            curY = curY - 26
            Pix.Size(dialog, POPUP_W, math.abs(curY) + BAND_PAD)
            dialog._brd:Fit()
        end

        -- Runs each frame from the popup's OnUpdate while a grip is held: separates click from
        -- drag, moves the row under the cursor with an insertion line, and on release reorders
        -- the list (order = priority) and re-renders.
        DragTick = function()
            local d = drag
            local row = d.row
            if not row then
                return
            end
            local down = IsMouseButtonDown("LeftButton")
            local _, cy = GetCursorPosition()
            if not d.active then
                if not down then
                    d.row = nil
                    return
                end -- released before threshold = a click
                if math.abs(cy - (d.startY or cy)) < 3 then
                    return
                end
                d.active = true
                row.frame:SetFrameLevel(dialog:GetFrameLevel() + 20)
                row.frame:SetAlpha(0.85)
            end
            local ent = CurrentEntry()
            local list = ent and ent[field]
            local num = list and #list or 0
            local sc = dialog:GetEffectiveScale()
            local cY = cy / sc
            local mT = dialog:GetTop() or 0
            -- Insertion index among the STATIC (non-dragged) rows
            local iI = num
            for ri = 1, num do
                local r2 = rowList[ri]
                if r2 ~= row and r2._baseY then
                    local rm = mT + r2._baseY - ROW_H / 2
                    if cY > rm then
                        iI = ri
                        break
                    end
                    iI = ri + 1
                end
            end
            iI = math.max(1, math.min(iI, num + 1))
            if down then
                local firstY = -(BAND_PAD + 24)
                local lnY = (iI <= 1) and (firstY + 2) or (firstY - (iI - 1) * STEP + 2)
                insLine:ClearAllPoints()
                insLine:SetPoint("TOPLEFT", dialog, "TOPLEFT", BAND_PAD, lnY)
                insLine:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -BAND_PAD, lnY)
                insLine:Show()
                row.frame:ClearAllPoints()
                row.frame:SetPoint("TOPLEFT", dialog, "TOPLEFT", BAND_PAD, cY - mT)
            else
                -- Dropped: reorder the list + re-render
                local from = row._idx
                if from and from < iI then
                    iI = iI - 1
                end
                local to = math.max(1, math.min(iI, num))
                insLine:Hide()
                d.row = nil
                d.active = false
                if list and from and from ~= to then
                    local mv = table.remove(list, from)
                    table.insert(list, to, mv)
                    if refreshFn then
                        refreshFn()
                    end
                end
                Refresh()
            end
        end

        return function(params)
            if not dialog then
                Build()
            end
            getBarData = params.getBarData
            refreshFn = params.refreshFn
            entryIdx = params.entryIdx
            local ent = CurrentEntry()
            if ent and not ent[field] then
                ent[field] = {}
            end
            Refresh()
            dialog:ClearAllPoints()
            dialog:SetPoint("TOP", params.anchor, "BOTTOM", 0, -4)
            dialog:Show()
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

    -- Skins a small text button of the threshold settings (Bands, Buffs, Spenders):
    -- a dark fill that lightens on hover, tip on hover. label comes localized.
    local function SkinCardButton(button, label, tipText)
        local backdrop = button:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(0.12, 0.12, 0.12, 0.8)
        button._border = CludesUI.MakeRoundedBorder(button, 1, 1, 1, 0.08, backdrop)
        local labelFS = CludesUI.MakeFont(button, 12, nil, 1, 1, 1)
        labelFS:SetAlpha(0.8)
        labelFS:SetPoint("CENTER")
        labelFS:SetText(label)
        button:SetScript("OnEnter", function(self)
            backdrop:SetColorTexture(0.16, 0.16, 0.16, 0.9)
            CludesUI.ShowWidgetTooltip(self, tipText)
        end)
        button:SetScript("OnLeave", function()
            backdrop:SetColorTexture(0.12, 0.12, 0.12, 0.8)
            CludesUI.HideWidgetTooltip()
        end)
    end

    -- Threshold notice badge: an info bubble in the Settings button's top-left corner
    -- naming every spec that has a threshold configured, so a spec's setup stays visible
    -- from a page that doesn't list it. The accent while none of them applies to the spec
    -- being played, orange while one does. Motion-only and click-through (same recipe as the
    -- Spec Overrides badge) so the button keeps its own hover and click.
    local THR_NOTE_IDLE = {} -- the accent, filled in place by each Update
    local THR_NOTE_ACTIVE = { 1, 0x8c / 255, 0x26 / 255, "ff8c26" }
    -- getBarData: fn() -> bar table. Returns the updater so callers can re-run it after an edit.
    local function AttachThresholdNotice(anchorBtn, getBarData)
        if not anchorBtn then
            return
        end
        local badge = CreateFrame("Frame", nil, anchorBtn)
        badge:SetSize(14, 14)
        badge:SetPoint("TOPLEFT", anchorBtn, "TOPLEFT", 2, -2)
        -- Below the button's disabled overlay (level + 5), so a disabled bar dims and
        -- covers the badge along with everything else on the button.
        badge:SetFrameLevel(anchorBtn:GetFrameLevel() + 3)
        badge:SetMouseClickEnabled(false)
        local ico = badge:CreateTexture(nil, "OVERLAY")
        ico:SetAllPoints()
        if ico.SetSnapToPixelGrid then
            ico:SetSnapToPixelGrid(false)
            ico:SetTexelSnappingBias(0)
        end
        ico:SetTexture([[Interface\AddOns\CludesUI\media\icons\cui-info.png]])
        badge._color = THR_NOTE_IDLE
        badge:SetScript("OnEnter", function(self)
            local c = self._color
            ico:SetVertexColor(c[1], c[2], c[3], 1)
            if self._tip and CludesUI.ShowWidgetTooltip then
                CludesUI.ShowWidgetTooltip(self, self._tip)
            end
        end)
        badge:SetScript("OnLeave", function(self)
            local c = self._color
            ico:SetVertexColor(c[1], c[2], c[3], 0.85)
            CludesUI.HideWidgetTooltip()
        end)
        badge:Hide()

        -- Recolors the button's own border to match (white when nothing is configured); its
        -- OnEnter/OnLeave read anchorBtn._borderTint instead of hardcoding white, so the tint
        -- survives hover. Alpha still follows the existing hover/idle levels.
        local function ApplyBorderTint(rgb)
            anchorBtn._borderTint = rgb
            if anchorBtn._border and anchorBtn._border.SetColor then
                local a = anchorBtn:IsMouseOver() and 0.3 or CludesUI.DD_BRD_A
                anchorBtn._border:SetColor(rgb[1], rgb[2], rgb[3], a)
            end
        end

        local function Update()
            local ar, ag, ab = CludesUI.GetAccentColor()
            THR_NOTE_IDLE[1], THR_NOTE_IDLE[2], THR_NOTE_IDLE[3] = ar, ag, ab
            THR_NOTE_IDLE[4] = CludesUI.HexColor(ar, ag, ab):sub(5)
            local list, isActive = mod.ThresholdNoticeInfo(getBarData())
            if not list then
                if CludesUI.HideWidgetTooltip and badge:IsMouseOver() then
                    CludesUI.HideWidgetTooltip()
                end
                badge:Hide()
                ApplyBorderTint(THR_BORDER_WHITE)
                return
            end
            local c = isActive and THR_NOTE_ACTIVE or THR_NOTE_IDLE
            badge._color = c
            ico:SetVertexColor(c[1], c[2], c[3], badge:IsMouseOver() and 1 or 0.85)
            local tipText = "|cff"
                .. c[4]
                .. CludesUI.L("Thresholds or hash lines configured for:")
                .. "|r "
                .. list
            local lead = isActive and CludesUI.L("Current Spec is affected by Threshold & Hash Lines.")
                or CludesUI.L("Current Spec is not affected by Threshold & Hash Lines.")
            badge._tip = "|cff" .. c[4] .. lead .. "|r\n\n" .. tipText
            badge:Show()
            ApplyBorderTint(c)
        end
        anchorBtn:HookScript("OnShow", Update)
        CludesUI.RegisterWidgetRefresh(Update)
        -- Keyed by the badge: the page pool forgets the entry when it resets it.
        CludesUI.RegAccent({
            type = "callback",
            obj = badge,
            fn = function()
                Update()
            end,
        })
        Update()
        return Update
    end

    -- Spec / talent watcher for the Threshold & Hash Lines editors. A spec or talent change
    -- moves which entry the resolver picks and changes the loadout talents, so every open
    -- editor refreshes in place and keeps its selection. A spec swap with no editor open
    -- redraws the Display page instead; with one open, that redraw waits until the last
    -- editor closes (a redraw would close it); an editor closed by leaving the page or
    -- closing the panel leaves the rebuild to the page's next visit. One event frame and
    -- one accent entry per session, made by the first editor build; the talent events are
    -- registered only while an editor is open.
    local ThrWatchBuild, ThrEditorShown, ThrEditorHidden
    do
        local isShown = {} -- [editor page] = { refresh, repaint }, while that page is shown
        local watch, stale, redraw, refreshQueued
        local function OnDisplayPage()
            return CludesUI:IsShown() and CludesUI:GetActivePage() == PAGE_DISPLAY
        end
        local function RedrawNow()
            if not redraw then
                return
            end
            redraw = nil
            if OnDisplayPage() then
                CludesUI:RefreshPage(true)
            end
        end
        -- One redraw per burst (a spec swap fires both spec events); a page build in between cancels it
        local function RedrawDisplay()
            if redraw or not OnDisplayPage() then
                return
            end
            redraw = true
            C_Timer.After(0, RedrawNow)
        end
        -- One in-place refresh per burst, a frame later, once the bars have seen the change.
        -- An editor whose page the options page pool dressed again since is over: it
        -- leaves the watcher instead of painting widgets that now show something else.
        local function FlushRefresh()
            refreshQueued = nil
            for page, ed in pairs(isShown) do
                if PoolGen(page) == ed.gen then
                    ed.refresh()
                else
                    ThrEditorHidden(page)
                end
            end
        end
        local function OnEvent(_, evt)
            local specSwap = evt == "PLAYER_SPECIALIZATION_CHANGED" or evt == "ACTIVE_TALENT_GROUP_CHANGED"
            if next(isShown) then
                if specSwap then
                    stale = true
                end
                if not refreshQueued then
                    refreshQueued = true
                    C_Timer.After(0, FlushRefresh)
                end
            elseif specSwap then
                if OnDisplayPage() then
                    RedrawDisplay()
                else
                    -- Away from the page (another page or module, or the panel
                    -- closed): its next visit builds it for the new spec.
                    CludesUI:InvalidateModulePageCache("CludesUIResourceBars")
                end
            end
        end
        -- Every editor build: makes the watcher once; the page being built is current again
        ThrWatchBuild = function()
            stale, redraw = nil, nil
            if watch then
                return
            end
            watch = CreateFrame("Frame")
            watch:RegisterUnitEvent("PLAYER_SPECIALIZATION_CHANGED", "player")
            watch:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
            watch:SetScript("OnEvent", OnEvent)
            -- The selection highlight follows the live theme accent
            CludesUI.RegAccent({
                type = "callback",
                fn = function()
                    for page, ed in pairs(isShown) do
                        if PoolGen(page) == ed.gen then
                            ed.repaint()
                        else
                            ThrEditorHidden(page)
                        end
                    end
                end,
            })
        end
        ThrEditorShown = function(page, ed)
            if not next(isShown) then
                watch:RegisterEvent("TRAIT_CONFIG_UPDATED")
                watch:RegisterEvent("PLAYER_TALENT_UPDATE")
            end
            isShown[page] = ed
        end
        ThrEditorHidden = function(page)
            if not isShown[page] then
                return
            end
            isShown[page] = nil
            if next(isShown) then
                return
            end
            watch:UnregisterEvent("TRAIT_CONFIG_UPDATED")
            watch:UnregisterEvent("PLAYER_TALENT_UPDATE")
            if stale then
                stale = nil
                if OnDisplayPage() then
                    RedrawDisplay()
                elseif CludesUI:GetActivePage() == PAGE_DISPLAY then
                    -- Closed with the panel: RefreshPage only flags a hidden panel, so its next open rebuilds the page
                    CludesUI:RefreshPage(true)
                else
                    -- Left for another page or module (the panel is open): drop the page's build so the next visit rebuilds it
                    CludesUI:InvalidateModulePageCache("CludesUIResourceBars")
                end
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

        -- True when an existing entry already claims specID
        local function IsSpecClaimed(specID)
            local edge = conf.getBarData()
            if not edge or not edge.thresholdSpecs then
                return false
            end
            for _, record in ipairs(edge.thresholdSpecs) do
                if record.specIDs then
                    for _, spellRef in ipairs(record.specIDs) do
                        if spellRef == 0 then
                            return true
                        end -- All Specs claims everything
                        if spellRef == specID then
                            return true
                        end
                    end
                end
            end
            return false
        end
        local function HasAllSpecsEntry()
            local edge = conf.getBarData()
            if not edge or not edge.thresholdSpecs then
                return false
            end
            for _, record in ipairs(edge.thresholdSpecs) do
                if record.specIDs then
                    for _, spellRef in ipairs(record.specIDs) do
                        if spellRef == 0 then
                            return true
                        end
                    end
                end
            end
            return false
        end

        -- The shared spec list (WoW Forever: one row per class, no role
        -- shortcuts), locked by what the existing entries claim.
        local function BuildSpecItems()
            local itemList
            itemList, _roleSpecs = CludesUI.SpecPickItems({
                roles = conf.roleShortcuts,
                lockedFn = IsSpecClaimed,
                allLockedFn = HasAllSpecsEntry,
            })
            return itemList
        end

        -- A fresh entry: hash row empty, threshold on at its defaults
        local function NewEntry(ids, edge)
            if conf.newEntry then
                return conf.newEntry(ids, edge)
            end
            local newEntry = {
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
            -- Default for the power bar's "Threshold color below value": spenders (mana/energy/focus)
            -- start ON (warn when low), builders (rage/runic/fury) OFF (warn when high). Only when
            -- the entry covers the current spec, the one whose power type we can read.
            if conf.partialDefault then
                local curIdx = C_SpecializationInfo.GetSpecialization()
                local curSpecID = curIdx and C_SpecializationInfo.GetSpecializationInfo(curIdx)
                -- WoW Forever: the entry covers the player when it names a spec of the class.
                if curSpecID or CludesUI.IS_FOREVER then
                    for _, spellRef in ipairs(ids) do
                        if
                            spellRef == 0
                            or spellRef == curSpecID
                            or (CludesUI.IS_FOREVER and CludesUI.IsPlayerSpec(spellRef))
                        then
                            local _, token = UnitPowerType("player")
                            if token == "MANA" or token == "FOCUS" or token == "ENERGY" then
                                newEntry.thresholdPartialOnly = true
                            end
                            break
                        end
                    end
                end
            end
            return newEntry
        end

        -- Paints one row's bg/accent for the current selection state
        local function PaintRow(f)
            local sel = (f._entryIdx ~= nil) and (_selectedIdx == f._entryIdx)
            local eg = CludesUI.CLUDES_GREEN
            f._selected = sel
            f._accent:SetShown(sel)
            -- Re-apply the live theme accent each paint; the creation-time color goes stale after a theme change
            f._accent:SetColorTexture(eg.r, eg.g, eg.b, 1)
            if sel then
                f._bg:SetColorTexture(eg.r, eg.g, eg.b, 0.10)
            else
                f._bg:SetColorTexture(1, 1, 1, 0.02)
            end
        end
        local function RepaintRows()
            for i = 1, #_entryFrames do
                local f = _entryFrames[i]
                if f and f:IsShown() then
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
