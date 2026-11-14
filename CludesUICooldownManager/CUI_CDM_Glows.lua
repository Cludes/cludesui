if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_CDM_Glows.lua
--
--  Glow view, pandemic sync, StartNativeGlow / StopNativeGlow, cooldown glows,
--  the bar state tables and proc glows.
--  Reads the earlier CDM files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._internals
-- The main file or an earlier CDM file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local CDM_SHAPES, ECME, EffectiveBarAlpha, FC =
    Inner.CDM_SHAPES, Inner.ECME, Inner.EffectiveBarAlpha, Inner.FC
local _ecmeFC, _getFD = Inner._ecmeFC, Inner._getFD
local ResolveInfoSpellID = Inner.ResolveInfoSpellID

local StartNativeGlow, StopNativeGlow

local _inCombat = false
Inner.inCombatSetters[#Inner.inCombatSetters + 1] = function(val)
    _inCombat = val
end

-------------------------------------------------------------------------------
--  Native Glow System -- engines provided by shared CludesUI_Glows.lua
--  CDM keeps its own GLOW_STYLES (different scale values) and Start/Stop
--  wrappers that handle CDM-specific shape glow (icon masks/borders).
-------------------------------------------------------------------------------
local _G_Glows = CludesUI.Glows
-- CDM saved glow numbering (1 Pixel, 2 Shape, 3 Action Button, 4 Auto-Cast,
-- 5 GCD, 6 Modern, 7 Classic, 8 Blackout) as a view over the shared style table.
mod.GLOW_VIEW = _G_Glows.MakeView({ 1, 4, 2, 3, 5, 6, 7, 8 })
local GLOW_STYLES = mod.GLOW_VIEW.list
mod.GLOW_STYLES = GLOW_STYLES

-------------------------------------------------------------------------------
--  Cross-surface Pandemic Glow sync (CDM bars + Nameplates) -- BEST EFFORT
--  Glow styles are identified by NAME, never raw index: CDM, Nameplates and the shared
--  engine order their lists differently, so the same integer means a different style per
--  surface. Each surface advertises a different subset; an unrenderable style is coerced
--  to the nearest supported one and the COERCED value is stored, so dropdown name and preview always match what's displayed.
--    - CDM icon bars  : full set + "Blizzard Default" (-1 = Blizzard's own glow)
--    - Nameplate icons: same set, with "Blizzard Default" as the nameplates'
--      Blizzard Pandemic Border (CludesUI.Glows.PANDEMIC_BORDER, the same
--      Cooldown Manager pandemic art, drawn static), their default style
-------------------------------------------------------------------------------
local PG_BLIZZ_NAME = "Blizzard Default"
local PG_NP_BLIZZ = _G_Glows.PANDEMIC_BORDER

-- CDM icon-bar style index <-> canonical name
local function PG_CdmNameFromIndex(position)
    if position == -1 then
        return PG_BLIZZ_NAME
    end
    local e = GLOW_STYLES[position]
    return (e and e.name) or "Pixel Glow"
end
local function PG_CdmIndexFromName(name)
    if name == PG_BLIZZ_NAME then
        return -1
    end
    for i = 1, #GLOW_STYLES do
        if GLOW_STYLES[i].name == name then
            return i
        end
    end
    return 1 -- Pixel Glow
end

-- Nameplate style index <-> canonical name (Blizzard Default = Blizzard
-- Pandemic Border; anything unsupported coerces to Pixel)
local function PG_NameplateNameFromIndex(position)
    if position == PG_NP_BLIZZ then
        return PG_BLIZZ_NAME
    end
    local entries = CludesUI.NameplatePandemicGlowStyles
    local e = entries and entries[position]
    return (e and e.name) or "Pixel Glow"
end
local function PG_NameplateIndexFromName(name)
    if name == PG_BLIZZ_NAME then
        return PG_NP_BLIZZ
    end
    local entries = CludesUI.NameplatePandemicGlowStyles
    if name and entries then
        for i = 1, #entries do
            if entries[i].name == name then
                return i
            end
        end
    end
    return 1 -- Pixel Glow (anything unsupported)
end
-- The style a nameplate profile shows: the Nameplates' own view over its
-- saved keys (the 9.6 pick, else the older key), exported by Nameplates;
-- its default is Blizzard Pandemic Border.
local function PG_NameplateStyle(np)
    local styleOf = CludesUI.NameplatePandemicStyle
    return styleOf and styleOf(np) or PG_NP_BLIZZ
end

-- Tracked Buff Bars render as rectangles: Pixel Glow and Auto-Cast Shine only
-- (the texture styles stretch on a bar, see Glows.RECT_EXCLUDES). Anything
-- else, Blizzard Default included, coerces to Pixel.
local function PG_TbbIndexFromName(name)
    return (name == "Auto-Cast Shine") and 4 or 1
end
-- A TBB may STORE a non-renderable style (e.g. -1 default) but DISPLAYS it as Pixel; compare what's shown, not what's stored.
local function PG_TbbEffectiveStyle(dst)
    return (dst.pandemicGlowStyle == 4) and 4 or 1
end
mod.PG_TbbEffectiveStyle = PG_TbbEffectiveStyle

local function PG_GetNPProfile()
    if not CludesUIDB or not CludesUIDB.profiles then
        return nil
    end
    local pName = CludesUIDB.activeProfile or "Default"
    local prof = CludesUIDB.profiles[pName]
    return prof and prof.addons and prof.addons.CludesUINameplates
end

-- Write a canonical payload into a destination, coercing the style through the destination's own name->index resolver (so the stored index is renderable).
-- styleKey: where the destination keeps its style (Nameplates: pandemicGlowPick); default pandemicGlowStyle.
local function PG_Write(dst, payload, indexFromName, styleKey)
    dst.pandemicGlow = payload.on
    dst[styleKey or "pandemicGlowStyle"] = indexFromName(payload.styleName or "Pixel Glow")
    dst.pandemicGlowColor = payload.color and CopyTable(payload.color) or nil
    -- Color mode travels with the color (Default/Custom/Class); nil = Default.
    dst.pandemicGlowMode = payload.mode
    dst.pandemicGlowLines = payload.lines
    dst.pandemicGlowThickness = payload.thickness
    dst.pandemicGlowSpeed = payload.speed
    dst.pandemicGlowBackground = payload.background and true or nil
    dst.pandemicGlowBackgroundColor = payload.backgroundColor and CopyTable(payload.backgroundColor) or nil
end

-- True when dst already displays what PG_Write(dst, payload) would store (when both are off
-- nothing is shown, so leftover style/color is irrelevant). actualStyleFn lets a surface report
-- its EFFECTIVE (displayed) style when that differs from the raw stored value (e.g. rectangle TBBs); defaults to stored.
-- unsetMode: the color mode an unset key means there (Nameplates: Custom); defaults to Default.
local function PG_Matches(dst, payload, indexFromName, actualStyleFn, unsetMode)
    if (dst.pandemicGlow or false) ~= (payload.on or false) then
        return false
    end
    if not payload.on then
        return true
    end
    local actual = actualStyleFn and actualStyleFn(dst) or (dst.pandemicGlowStyle or 1)
    if actual ~= indexFromName(payload.styleName or "Pixel Glow") then
        return false
    end
    if (dst.pandemicGlowMode or unsetMode or "default") ~= (payload.mode or "default") then
        return false
    end
    local dc = dst.pandemicGlowColor or {}
    local pc = payload.color or {}
    if (dc.r or 1) ~= (pc.r or 1) or (dc.g or 1) ~= (pc.g or 1) or (dc.b or 0) ~= (pc.b or 0) then
        return false
    end
    if (dst.pandemicGlowLines or 8) ~= (payload.lines or 8) then
        return false
    end
    if (dst.pandemicGlowThickness or 2) ~= (payload.thickness or 2) then
        return false
    end
    if (dst.pandemicGlowSpeed or 4) ~= (payload.speed or 4) then
        return false
    end
    if (dst.pandemicGlowBackground == true) ~= (payload.background == true) then
        return false
    end
    if payload.background then
        local dc = dst.pandemicGlowBackgroundColor or {}
        local pc = payload.backgroundColor or {}
        if (dc.r or 0) ~= (pc.r or 0) or (dc.g or 0) ~= (pc.g or 0) or (dc.b or 0) ~= (pc.b or 0) then
            return false
        end
    end
    return true
end

-- Build a canonical payload from a CDM icon bar.
function CludesUI.PandemicPayloadFromCdmBar(edge)
    return {
        on = edge.pandemicGlow == true,
        styleName = PG_CdmNameFromIndex(edge.pandemicGlowStyle or 1),
        color = edge.pandemicGlowColor,
        mode = edge.pandemicGlowMode,
        lines = edge.pandemicGlowLines,
        thickness = edge.pandemicGlowThickness,
        speed = edge.pandemicGlowSpeed,
        background = edge.pandemicGlowBackground == true,
        backgroundColor = edge.pandemicGlowBackgroundColor,
    }
end

-- Payload from a rectangle bar (Tracked Buff Bar): rectangles only render Pixel/Auto-Cast, so
-- report the EFFECTIVE displayed style, not the raw stored one (which may be e.g. -1 "Blizzard Default", shown there as Pixel).
function CludesUI.PandemicPayloadFromRectBar(edge)
    return {
        on = edge.pandemicGlow == true,
        styleName = GLOW_STYLES[PG_TbbEffectiveStyle(edge)].name,
        color = edge.pandemicGlowColor,
        mode = edge.pandemicGlowMode,
        lines = edge.pandemicGlowLines,
        thickness = edge.pandemicGlowThickness,
        speed = edge.pandemicGlowSpeed,
        background = edge.pandemicGlowBackground == true,
        backgroundColor = edge.pandemicGlowBackgroundColor,
    }
end

-- Build a payload from the nameplate profile. An unset color mode is Custom
-- there (the swatch color the nameplate glow always drew).
function CludesUI.PandemicPayloadFromNameplate(np)
    return {
        on = np.pandemicGlow == true,
        styleName = PG_NameplateNameFromIndex(PG_NameplateStyle(np)),
        color = np.pandemicGlowColor,
        mode = np.pandemicGlowMode or "custom",
        lines = np.pandemicGlowLines,
        thickness = np.pandemicGlowThickness,
        speed = np.pandemicGlowSpeed,
        background = np.pandemicGlowBackground == true,
        backgroundColor = np.pandemicGlowBackgroundColor,
    }
end

-- Apply a canonical payload to all sync surfaces (CDM icon bars, Tracked Buff Bars,
-- Nameplates), best-effort. opts.skipCdmKey/opts.skipNameplates exclude the source surface; opts.skipTbbBar excludes one TBB (its source bar table).
function CludesUI.ApplyPandemicGlowToAll(payload, options)
    options = options or {}
    if not options.skipNameplates then
        local np = PG_GetNPProfile()
        if np and CludesUI.NameplatePandemicGlowStyles then
            PG_Write(np, payload, PG_NameplateIndexFromName, "pandemicGlowPick")
            -- Nameplates read an unset mode as Custom: Default is stored as itself.
            np.pandemicGlowMode = payload.mode or "default"
        end
    end
    local p = ECME.db and ECME.db.profile
    if p and p.cdmBars and p.cdmBars.bars then
        for _, b in ipairs(p.cdmBars.bars) do
            if b.key ~= options.skipCdmKey and not b.isGhostBar and b.barType ~= "custom_buff" then
                PG_Write(b, payload, PG_CdmIndexFromName)
            end
        end
    end
    -- Tracked Buff Bars (active spec) -- rectangles, so style coerces to Pixel/Auto-Cast.
    local tbb = mod.GetTrackedBuffBars and mod.GetTrackedBuffBars()
    if tbb and tbb.bars then
        for _, b in ipairs(tbb.bars) do
            if b ~= options.skipTbbBar then
                PG_Write(b, payload, PG_TbbIndexFromName)
            end
        end
    end
    if mod.BuildAllCDMBars then
        mod.BuildAllCDMBars()
    end
    if mod.BuildTrackedBuffBars then
        mod.BuildTrackedBuffBars()
    end
    if _G._CUNP_RefreshAllSettings then
        _G._CUNP_RefreshAllSettings()
    end
end

-- True when every (non-skipped) surface already matches the payload.
function CludesUI.IsPandemicGlowSyncedToAll(payload, options)
    options = options or {}
    if not options.skipNameplates then
        local np = PG_GetNPProfile()
        if
            np
            and CludesUI.NameplatePandemicGlowStyles
            and not PG_Matches(np, payload, PG_NameplateIndexFromName, PG_NameplateStyle, "custom")
        then
            return false
        end
    end
    local p = ECME.db and ECME.db.profile
    if p and p.cdmBars and p.cdmBars.bars then
        for _, b in ipairs(p.cdmBars.bars) do
            if
                b.key ~= options.skipCdmKey
                and not b.isGhostBar
                and b.barType ~= "custom_buff"
                and not PG_Matches(b, payload, PG_CdmIndexFromName)
            then
                return false
            end
        end
    end
    local tbb = mod.GetTrackedBuffBars and mod.GetTrackedBuffBars()
    if tbb and tbb.bars then
        for _, b in ipairs(tbb.bars) do
            if
                b ~= options.skipTbbBar
                and not PG_Matches(b, payload, PG_TbbIndexFromName, PG_TbbEffectiveStyle)
            then
                return false
            end
        end
    end
    return true
end

-- Show Glows Only in Combat (global). Bar Glows and the Tracking Bars gate
-- their own "Only In Combat" toggles at the decision site, which works because
-- a ticker re-evaluates them. This one gates the renderer: the proc glow and
-- the CD ready flush are pure edges with no re-assert, so a suppressed request
-- can only come back by being replayed from here.
-- overlay -> its last StartNativeGlow request, for live overlays only:
-- options preview overlays get none (see StartNativeGlow). Weak keys: a
-- record lives as long as its overlay, which its owner's frame data holds.
-- The rec.active filter keeps the sweep below short.
mod._cdmGlowRec = setmetatable({}, { __mode = "k" })

-- Cached toggle: StartNativeGlow tests it on every glow start, so it must not
-- walk the DB there. Re-read on apply/profile change, at world entry, and from
-- the option itself.
function mod.RefreshGlowCombatGate()
    local p = ECME and ECME.db and ECME.db.profile
    local enabled = (p and p.cdmBars and p.cdmBars.glowsOnlyInCombat) and true or false
    mod._cdmGlowOOCGate = enabled
    -- Sticky: once the gate has been on there may be suppressed glows left to
    -- release, so the sweep has to stay reachable after it goes off again.
    if enabled then
        mod._cdmGlowGateEverOn = true
    end
end

StartNativeGlow = function(overlayFrame, style, cr, cg, cb, options)
    if not overlayFrame then
        return
    end
    local styleIdx = tonumber(style) or 1
    if styleIdx < 1 or styleIdx > #GLOW_STYLES then
        styleIdx = 1
    end
    local record = GLOW_STYLES[styleIdx]

    _G_Glows.StopAllGlows(overlayFrame)

    -- Threshold glows pass the owning icon and its size explicitly so every
    -- style sizes exactly like the normal buff-glow path.
    local hostFrame = (options and options.owner) or overlayFrame:GetParent()

    -- Show Glows Only in Combat. Recorded only once the gate has ever been on
    -- this session, so a session that never switches it on pays one boolean
    -- here and nothing else. The record is what the combat sweep takes down
    -- and replays: the proc glow and CD ready glow are edge-driven, so a
    -- suppressed request can only ever come back by being replayed from it.
    -- Glows already lit at the very first enable of a session have no record
    -- until their own next edge; the option setter re-issues the bar and buff
    -- glows right away and everything is exact from the next login.
    -- Stored verbatim, pre-defaulting, so a nil colour stays nil. The owner and
    -- its resolved spellID ride along so the replay can tell a record that is
    -- still current from one whose pooled icon has since been handed a
    -- different spell (fc.spellID is our cached plain identity, never secret).
    -- Options previews opt out on their own overlay rather than through opts:
    -- three overlays serve the four preview call sites, and a non-nil opts
    -- flips the pixel-glow branch off the bar's settings. They get no record:
    -- the sweep never reads one, and an options page can hand a preview
    -- overlay out again for other uses, which a record keyed by it outlives.
    if mod._cdmGlowGateEverOn and not overlayFrame._cuiGlowPreview then
        local rec = mod._cdmGlowRec[overlayFrame]
        if not rec then
            rec = {}
            mod._cdmGlowRec[overlayFrame] = rec
        end
        local ownerFC = hostFrame and _ecmeFC[hostFrame]
        rec.style, rec.r, rec.g, rec.b, rec.opts = styleIdx, cr, cg, cb, options
        rec.owner, rec.sid = hostFrame, ownerFC and ownerFC.spellID or nil
        rec.active = true
        -- Suppressed overlays keep _glowActive = true: the buff ticker's
        -- active-glow integrity pass and the preset cd-state re-assert restart
        -- any glow whose overlay reads dark, so the truth would churn every
        -- tick for exactly the users who asked for less work out of combat.
        if mod._cdmGlowOOCGate and not _inCombat then
            rec.suppressed = true
            overlayFrame._glowActive = true
            overlayFrame:SetAlpha(0)
            return
        end
        rec.suppressed = false
    end

    if not hostFrame then
        return
    end
    local pW = (options and options.width) or hostFrame:GetWidth()
    local pH = (options and options.height) or hostFrame:GetHeight()
    if pW < 5 then
        pW = 36
    end
    if pH < 5 then
        pH = 36
    end
    local noColor = (cr == nil)
    if noColor then
        cr, cg, cb = 1.0, 0.788, 0.137
    end
    cr = cr or 1
    cg = cg or 1
    cb = cb or 1

    if record.shapeGlow then
        -- CDM-specific: read shape mask/border from the icon frame
        local icon = hostFrame
        local ifc2 = _ecmeFC[icon]
        local shape = (ifc2 and ifc2.shapeApplied) and (ifc2 and ifc2.shapeName) or nil
        local shapeMask = ifc2 and ifc2.shapeMask
        -- No custom shape (none/cropped) = sharp-cornered square: use the square glow texture so
        -- the pulse hugs the icon edges instead of filling a solid additive block (no live mask
        -- object here, so the texture alone defines the shape). Skip the shape border overlay -- the icon keeps its own border, so it would just add a stray line.
        local noShape = not shape
        if noShape then
            shape = "square"
            shapeMask = nil
        end
        local maskPath = CDM_SHAPES.masks[shape]
        local borderPath = (not noShape) and CDM_SHAPES.borders[shape] or nil
        _G_Glows.StartShapeGlow(overlayFrame, math.min(pW, pH), cr, cg, cb, 1.20, {
            maskPath = maskPath,
            borderPath = borderPath,
            shapeMask = shapeMask,
            -- Gated (threshold) glows only: ApplyMaskWith below can bind only the
            -- textures ON the wrapper, and this is the one engine that creates
            -- them on the anchor frame instead -- unmasked, its pulse showed
            -- below the stack threshold. The overlay is SetAllPoints on the icon,
            -- so anchoring there is identical geometry; ungated callers keep the
            -- icon parenting they have always had.
            anchorFrame = (options and options.maskWith) and overlayFrame or nil,
        })
    elseif record.procedural then
        -- Pixel Glow params. Pandemic glow and the buff ticker pass explicit opts; per-button
        -- glows (active-state, CD-ready, bar glows) pass none or only their gate masks, so
        -- resolve the owning bar's settings: a buff-family bar keeps them under buffGlow*
        -- (the Bars page writes those keys for buff bars), every other bar under pixelGlow*,
        -- defaulting for action-bar overlays and bars that never set the values.
        local N, th, period, bgR, bgG, bgB, bgA
        if options and (options.N or options.th or options.period or options.bg) then
            N = options.N or 8
            th = options.th or 2
            period = options.period or 4
            if options.bg then
                bgR, bgG, bgB, bgA =
                    options.bg.r or 0, options.bg.g or 0, options.bg.b or 0, options.bg.a or 1
            end
        else
            local pfc = _ecmeFC[hostFrame]
            local pbd = pfc and pfc.barKey and mod.GetBarData and mod.GetBarData(pfc.barKey)
            if pbd and mod.IsBarBuffFamily and mod.IsBarBuffFamily(pbd) then
                -- pixelGlow* second: a buff bar that only ever held the old keys keeps
                -- rendering exactly as before.
                N = pbd.buffGlowLines or pbd.pixelGlowLines or 8
                th = pbd.buffGlowThickness or pbd.pixelGlowThickness or 2
                period = pbd.buffGlowSpeed or pbd.pixelGlowSpeed or 4
                if pbd.buffGlowBackground then
                    bgR, bgG, bgB, bgA =
                        pbd.buffGlowBackgroundR or 0,
                        pbd.buffGlowBackgroundG or 0,
                        pbd.buffGlowBackgroundB or 0,
                        1
                elseif pbd.pixelGlowBackground then
                    bgR, bgG, bgB, bgA =
                        pbd.pixelGlowBackgroundR or 0,
                        pbd.pixelGlowBackgroundG or 0,
                        pbd.pixelGlowBackgroundB or 0,
                        1
                end
            else
                N = (pbd and pbd.pixelGlowLines) or 8
                th = (pbd and pbd.pixelGlowThickness) or 2
                period = (pbd and pbd.pixelGlowSpeed) or 4
                if pbd and pbd.pixelGlowBackground then
                    bgR, bgG, bgB, bgA =
                        pbd.pixelGlowBackgroundR or 0,
                        pbd.pixelGlowBackgroundG or 0,
                        pbd.pixelGlowBackgroundB or 0,
                        1
                end
            end
        end
        -- Options previews (opts.panel): draw the pixels the live glow shows.
        if options and options.panel then
            th = _G_Glows.PanelThickness(th)
        end
        local lineLen = math.floor((pW + pH) * (2 / N - 0.1))
        lineLen = math.min(lineLen, math.min(pW, pH))
        if lineLen < 1 then
            lineLen = 1
        end
        _G_Glows.StartProceduralAnts(
            overlayFrame,
            N,
            th,
            period,
            lineLen,
            cr,
            cg,
            cb,
            pW,
            pH,
            bgR,
            bgG,
            bgB,
            bgA
        )
    elseif record.buttonGlow then
        _G_Glows.StartButtonGlow(overlayFrame, pW, cr, cg, cb, nil, pH)
    elseif record.autocast then
        _G_Glows.StartAutoCastShine(overlayFrame, pW, cr, cg, cb, 1.0, pH)
    elseif record.solidFill then
        -- Clip to the shape mask only while a custom shape is applied, decided as
        -- in the Shape branch above: a removed shape leaves its mask object on the
        -- icon (emptied and hidden), which must not clip the fill. Without one, a
        -- CDM icon under Blizzard Style clips to the rounded mask its own art
        -- carries (nil under Classic WoW UI, whose icons are square).
        local ifc2 = _ecmeFC[hostFrame]
        local shapeMask = (ifc2 and ifc2.shapeApplied and ifc2.shapeName) and ifc2.shapeMask or nil
        if not shapeMask and ifc2 and mod.CdmBlizzIcons() then
            shapeMask = mod.CdmBlizzIconMask(hostFrame)
        end
        _G_Glows.StartSolidFill(
            overlayFrame,
            noColor and 0 or cr,
            noColor and 0 or cg,
            noColor and 0 or cb,
            { alpha = options and options.alpha, shapeMask = shapeMask }
        )
    else
        if noColor then
            cr, cg, cb = nil, nil, nil
        end
        _G_Glows.StartFlipBookGlow(overlayFrame, pW, record, cr, cg, cb, pH)
    end

    -- Threshold gating: bound every texture the style just created with the
    -- caller's mask (see ApplyMaskWith in CludesUI_Glows.lua).
    if options and options.maskWith and _G_Glows.ApplyMaskWith then
        _G_Glows.ApplyMaskWith(overlayFrame, options.maskWith)
    end
    -- Second gate mask (two-gate threshold glows). ApplyMaskWith dedupes on one
    -- key per region, so a second mask needs a key of its own and cannot go
    -- through the core helper. Data rather than a callback, so the combat replay
    -- below re-binds it on the textures that replay creates fresh.
    local mask2 = options and options.maskWith2
    if mask2 then
        for _, r in ipairs({ overlayFrame:GetRegions() }) do
            if r.AddMaskTexture and r._cuiTGMask2 ~= mask2 then
                r._cuiTGMask2 = mask2
                r:AddMaskTexture(mask2)
            end
        end
    end

    overlayFrame._glowActive = true
    overlayFrame:SetAlpha(1)
    -- NEVER Show()/Hide() -- the overlay is always shown (created in DecorateFrame).
    -- Toggling visibility on a child of a Blizzard viewer frame triggers Layout hooks and causes position cascades.
end

StopNativeGlow = function(overlayFrame)
    if not overlayFrame then
        return
    end
    _G_Glows.StopAllGlows(overlayFrame)
    overlayFrame._glowActive = false
    overlayFrame:SetAlpha(0)
    local rec = mod._cdmGlowRec[overlayFrame]
    if rec then
        rec.active = false
        rec.suppressed = false
    end
    -- No Hide() -- just alpha 0. Same reason as above.
end
mod.StartNativeGlow = StartNativeGlow
mod.StopNativeGlow = StopNativeGlow

-- Cooldown State Effect glow (CD Ready / On CD): Blackout renders on its own
-- frame BELOW frame.Cooldown (fd.blackoutOverlay, icon+12) instead of the
-- shared fd.glowOverlay (icon+16, ABOVE the cooldown widget), so the swipe and
-- countdown text stay visible on top of the fill; every other style keeps
-- using the shared overlay. Picks the overlay from the resolved style and
-- stops a glow still held by the other one, so a style change (Blackout to
-- Pixel or back) never leaves both lit. The active-state and proc glows own
-- the shared overlay while they run (fd._faActiveGlow: the Fake-Active
-- overlay's active glow, drawn on that overlay's own frame, holds it the same
-- way): a Blackout shows alongside them, any other style starts nothing and
-- returns nil, so the caller's memo stays off, and the refusal is recorded
-- (fd._cdGlowOwed) so the edge that ends that glow lights this one at once
-- (ns.CdGlowKick). Returns the overlay lit. alpha is the Blackout fill
-- opacity (nil = opaque); the other styles take no opts at all.
function mod.StartCdGlow(fd, style, cr, cg, cb, alpha)
    if not fd then
        return
    end
    local e = mod.GLOW_STYLES[style]
    local busy = fd._activeGlowOn or fd.procGlowActive or fd._faActiveGlow
    local overlayFrame, other, options
    if e and e.solidFill then
        -- The Blackout frame is made on the icon's first Blackout start (most
        -- icons never use one), on the icon the shared overlay sits on;
        -- DecorateFrame keeps its level through re-layouts.
        local bo = fd.blackoutOverlay
        if not bo and fd.glowOverlay then
            local icon = fd.glowOverlay:GetParent()
            bo = CreateFrame("Frame", nil, icon)
            bo:SetAllPoints(icon)
            bo:SetAlpha(0)
            bo:EnableMouse(false)
            bo:SetFrameLevel(icon:GetFrameLevel() + 12)
            fd.blackoutOverlay = bo
        end
        -- A fresh table per start: StartNativeGlow keeps opts by reference in
        -- its Show Glows Only in Combat record, which the replay restarts from.
        overlayFrame, options = bo, { alpha = alpha }
        if not busy then
            other = fd.glowOverlay
        end
    else
        overlayFrame, other = fd.glowOverlay, fd.blackoutOverlay
        if busy then
            overlayFrame = nil
            fd._cdGlowOwed = true
        end
    end
    if other and other._glowActive then
        StopNativeGlow(other)
    end
    if overlayFrame then
        StartNativeGlow(overlayFrame, style, cr, cg, cb, options)
    end
    return overlayFrame
end

-- Stops the CD-state glow regardless of which overlay it landed on. The
-- Blackout overlay is only stopped while it holds a glow: most icons never
-- use it. While the proc or active-state glow runs, the shared overlay is
-- theirs (a CD-state glow there was replaced, and is owed back or re-asserted
-- once they end), so only a Blackout can be the CD-state glow then: a
-- Blackout ending with its cooldown never takes the proc or active glow down
-- with it.
function mod.StopCdGlow(fd)
    if not fd then
        return
    end
    local go = fd.glowOverlay
    if go and not (fd.procGlowActive or fd._activeGlowOn) then
        StopNativeGlow(go)
    end
    local bo = fd.blackoutOverlay
    if bo and bo._glowActive then
        StopNativeGlow(bo)
    end
end

-- Combat edges for Show Glows Only in Combat. Entering combat replays what was
-- suppressed; leaving combat takes the running glows down but keeps their
-- records, so the next pull lights them again without waiting for their owners
-- to re-fire. The option, a profile apply and world entry call it after
-- re-reading the gate, so a change takes effect at once. Never having had the
-- gate on makes this two reads and a return for the whole session.
function mod.CDMGlowCombatSync()
    if not mod._cdmGlowOOCGate and not mod._cdmGlowGateEverOn then
        return
    end
    local show = _inCombat or not mod._cdmGlowOOCGate
    -- Replays are collected here and run after the traversal: StartNativeGlow
    -- writes into _cdmGlowRec, and inserting a key during pairs() is undefined
    -- in Lua 5.1. It only ever rewrites an existing key today, but that is not
    -- a property this loop should rest on.
    local queue = mod._cdmGlowSyncScratch
    if not queue then
        queue = {}
        mod._cdmGlowSyncScratch = queue
    end
    local num = 0
    for overlayFrame, rec in pairs(mod._cdmGlowRec) do
        if rec.active and not overlayFrame._cuiGlowPreview then
            if not show then
                if not rec.suppressed then
                    _G_Glows.StopAllGlows(overlayFrame)
                    overlayFrame:SetAlpha(0)
                    rec.suppressed = true
                    -- _glowActive deliberately stays true (see StartNativeGlow).
                end
            elseif rec.suppressed then
                num = num + 1
                queue[num] = overlayFrame
            end
        end
    end
    for i = 1, num do
        local overlayFrame = queue[i]
        queue[i] = nil
        local rec = mod._cdmGlowRec[overlayFrame]
        if rec and rec.suppressed then
            local fc = rec.owner and _ecmeFC[rec.owner]
            if rec.sid and fc and fc.spellID ~= rec.sid then
                -- Pooled onto a different spell while suppressed: drop the
                -- request instead of lighting the new spell in the old style.
                -- Only the active-state integrity pass and the preset cd-state
                -- re-assert read _glowActive, so clearing it wakes those two;
                -- every other owner keeps its own memo and re-decides on its
                -- own next edge.
                rec.active = false
                rec.suppressed = false
                overlayFrame._glowActive = false
            else
                StartNativeGlow(overlayFrame, rec.style, rec.r, rec.g, rec.b, rec.opts)
            end
        end
    end
end

-- Our bar frames (keyed by bar key)
local cdmBarFrames = {}
-- Icon frames per bar (keyed by bar key, array of icon frames)
local cdmBarIcons = {}
-- Fast barData lookup by key (rebuilt in BuildAllCDMBars, avoids linear scan per tick)
local barDataByKey = {}

-- Claim generation: bumped at the end of every CollectAndReanchor pass and at BuildAllCDMBars'
-- head, i.e. whenever the cdmBarIcons claim set can change. The proc-alert child map below rebuilds lazily against it.
mod._cdmClaimGen = 0
-- Resolution generation: bumped whenever spell resolution INPUTS change (SPELLS_CHANGED
-- talent/spec churn, live SPELL_OVERRIDE_UPDATED flips, rebuilds). cooldownID-keyed resolution memos key their validity on it.
mod._cdmResGen = 0

-- Shown-alpha for cd-state/fake-active restore paths: EffectiveBarAlpha, except 0 while the
-- icon's bar is visibility-hidden -- painting EffectiveBarAlpha directly would resurrect icons
-- on visibility-hidden bars (any cooldown/aura flip shows them until the next visibility pass).
-- Overflow-diverted frames follow the bar they are painted on (same rule as the fake-active engine's FrameBaseAlpha, which routes through here).
local function IconShownAlpha(fc, barInfo)
    local bk = fc and (fc._overflowLayoutBar or fc.barKey)
    local bf = bk and cdmBarFrames[bk]
    if bf and bf._visHidden then
        return 0
    end
    return EffectiveBarAlpha(barInfo or (bk and barDataByKey[bk]))
end
mod.IconShownAlpha = IconShownAlpha

-- Global accessor for cross-addon frame lookups
_G._CUCME_GetBarFrame = function(barId)
    return cdmBarFrames[barId]
end
-- Global accessor: apply a spec profile to the live bars (profile import). All consumers
-- read spell data from the global store, so this only needs to trigger a rebuild against the (now-active) spec.
_G._CUCME_LoadSpecProfile = function(specKey)
    mod.FullCDMRebuild("profile_import")
end
-- Global accessor: get the current spec key string (e.g. "250"), or nil if the spec API isn't ready yet.
_G._CUCME_GetCurrentSpecKey = function()
    return mod.GetActiveSpecKey()
end

-------------------------------------------------------------------------------
--  Proc Glow System: hooks Blizzard's SpellAlertManager to show proc glows
--  on our CDM icons when Blizzard fires ShowAlert/HideAlert on CDM children.
--  Custom bars use SPELL_ACTIVATION_OVERLAY_GLOW_SHOW/HIDE events instead.
-------------------------------------------------------------------------------
local PROC_GLOW_STYLE = 6 -- "Modern WoW Glow" flipbook

-- Reverse lookup: Blizzard CDM viewer frame name -> our bar key
local _blizzViewerToBarKey = {
    EssentialCooldownViewer = "cooldowns",
    UtilityCooldownViewer = "utility",
    BuffIconCooldownViewer = "buffs",
}

-- Walk up from a frame to find which Blizzard CDM viewer it belongs to; also handles reparented frames (hook system) via the _barKey field.
local function GetBarKeyForBlizzChild(widget)
    -- Fast path: barKey set by the hook system (external cache) or CDM frame
    local fc = _ecmeFC[widget]
    if (fc and fc.barKey) or widget._barKey then
        return (fc and fc.barKey) or widget._barKey, widget
    end
    local current = widget
    while current do
        local hostFrame = current:GetParent()
        if not hostFrame then
            return nil
        end
        -- Parent one of our CDM bar containers? (external cache or direct)
        local pfc = _ecmeFC[hostFrame]
        if (pfc and pfc.barKey) or hostFrame._barKey then
            return (pfc and pfc.barKey) or hostFrame._barKey, current
        end
        local name = hostFrame.GetName and hostFrame:GetName()
        if name and _blizzViewerToBarKey[name] then
            return _blizzViewerToBarKey[name], current
        end
        current = hostFrame
    end
    return nil
end

local ResolveBlizzChildSpellID -- forward-declare (defined below)

-- Find our icon mirroring a given Blizzard CDM child. In hook mode the icon IS the Blizzard
-- child (identity check); falls back to spellID + override matching for proc glows on transformed spells.
local function FindOurIconForBlizzChild(barId, blizzChild)
    -- O(1) common case: in hook mode our "icon" IS the claimed Blizzard child. Membership map
    -- (child -> claimed barKey) rebuilt lazily whenever the claim generation moves; between passes
    -- the claim set is stable. Weak keys so released viewer children never pin. A miss falls through to the scans below, so staleness can only cost the fast path, never invent a claim.
    local m = mod._cdmChildClaimMap
    if not m or m.gen ~= mod._cdmClaimGen then
        m = setmetatable({ gen = mod._cdmClaimGen }, { __mode = "k" })
        for bk, entries in pairs(cdmBarIcons) do
            for i = 1, #entries do
                m[entries[i]] = bk
            end
        end
        mod._cdmChildClaimMap = m
    end
    if m[blizzChild] == barId then
        return blizzChild
    end
    local icons = cdmBarIcons[barId]
    if not icons then
        return nil
    end
    for _, icon in ipairs(icons) do
        local iifc = _ecmeFC[icon]
        local bc = iifc and iifc.blizzChild
        if icon == blizzChild or bc == blizzChild then
            return icon
        end
    end
    -- Fallback: match by spellID (covers override spells like HST -> Storm Stream)
    local alertSid, alertBase = ResolveBlizzChildSpellID(blizzChild)
    if alertSid then
        for _, icon in ipairs(icons) do
            local ifc = _ecmeFC[icon]
            local isid = ifc and ifc.spellID
            -- Second compare: the alert child's cooldownInfo carries its BASE id, so an icon
            -- assigned the base of a transformed spell matches on a plain field compare -- no per-icon API translation.
            if isid == alertSid or (alertBase and isid == alertBase) then
                return icon
            end
        end
        -- Override mapping (base <-> override). Last resort: only reachable when the icon's assigned id and the alert's base id differ yet still override-resolve to the alert spell.
        for _, icon in ipairs(icons) do
            local ifc = _ecmeFC[icon]
            local iconSid = ifc and ifc.spellID
            if iconSid and C_SpellBook and C_SpellBook.FindSpellOverrideByID then
                local ovr = C_SpellBook.FindSpellOverrideByID(iconSid)
                if ovr and ovr == alertSid then
                    return icon
                end
            end
        end
    end
    return nil
end

-- Resolve spellID from a Blizzard CDM child (IsSpellOverlayed guard, proc glow matching).
-- Returns (resolvedSid, baseSid). cooldownID-keyed memo: the cdID -> spell mapping only moves
-- on resolution edges (talent churn, live override flips), all of which bump ns._cdmResGen and
-- drop the memo wholesale, so the per-alert API round-trip collapses to a hash hit. Stored false = resolved to nothing (distinct from never-resolved).
ResolveBlizzChildSpellID = function(blizzChild)
    local cdID = blizzChild.cooldownID
    if not cdID and blizzChild.cooldownInfo then
        cdID = blizzChild.cooldownInfo.cooldownID
    end
    if type(cdID) ~= "number" then
        return nil
    end
    local m = mod._cdidSidMemo
    if not m or m.gen ~= mod._cdmResGen then
        m = { gen = mod._cdmResGen }
        mod._cdidSidMemo = m
    end
    local hit = m[cdID]
    if hit ~= nil then
        if hit == false then
            return nil
        end
        return hit[1], hit[2]
    end
    local details = C_CooldownViewer
        and C_CooldownViewer.GetCooldownViewerCooldownInfo
        and C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
    if details then
        local spellRef = ResolveInfoSpellID(details)
        if spellRef then
            local record = { spellRef, details.spellID }
            m[cdID] = record
            return spellRef, details.spellID
        end
    end
    m[cdID] = false
    return nil
end

-- Unified glow color for a spell: r,g,b or nil for default. ss.glowColor "class" -> class color, "custom" -> ss.glowColorR/G/B.
local function ResolveGlowColor(ss)
    if not ss or not ss.glowColor then
        return nil
    end
    if ss.glowColor == "class" then
        local _, ct = UnitClass("player")
        if ct then
            local cc = RAID_CLASS_COLORS[ct]
            if cc then
                return cc.r, cc.g, cc.b
            end
        end
    elseif ss.glowColor == "custom" and ss.glowColorR ~= nil then
        return ss.glowColorR, ss.glowColorG or 0.788, ss.glowColorB or 0.137
    end
    return nil
end

mod.ResolveGlowColor = ResolveGlowColor

-- Show proc glow on one of our icons. Uses per-spell settings if available.
local function ShowProcGlow(icon, cr, cg, cb)
    if not icon then
        return
    end
    local fd = _getFD(icon)
    local glow = fd and fd.glowOverlay or icon._glowOverlay
    if not glow then
        return
    end
    if fd and fd.procGlowActive then
        return
    end

    local fc = _ecmeFC[icon]
    -- Force Shape Glow (style 2) for custom-shaped icons (any but none/cropped)
    local shapeName = (fc and fc.shapeApplied) and fc.shapeName or nil
    local isCustomShape = shapeName and shapeName ~= "none" and shapeName ~= "cropped"
    local style = isCustomShape and 2 or PROC_GLOW_STYLE
    local spellRef = fc and fc.spellID
    if spellRef then
        local bk = fc and fc.barKey
        local sd = bk and mod.GetBarSpellData(bk)
        -- Shared resolver: matches the stored key against the frame's FULL identity set
        -- (canon, resolvedSid, baseSpellID, linkedSpellIDs, GetBaseSpell) so a
        -- base-spell setting resolves on its talent "proc into a second ability"
        -- override form (e.g. Reap -> base 344862). assignedSpells-only matching misses
        -- this on default Essential/Utility bars, whose assignedSpells list is empty.
        local ss = mod.ResolveSpellSettings and mod.ResolveSpellSettings(icon, spellRef, sd, bk)
        if ss then
            -- Custom shapes are locked to Shape Glow: ignore the per-spell glow
            -- type (incl. "None"). The per-spell glow COLOR below still applies.
            if not isCustomShape then
                if ss.procGlow == 0 then
                    return
                end -- proc glow disabled
                if ss.procGlow and ss.procGlow > 0 then
                    style = ss.procGlow
                end
            end
            -- Unified glow color takes priority over per-type settings
            local ur, ug, ub = ResolveGlowColor(ss)
            if ur then
                cr, cg, cb = ur, ug, ub
            elseif ss.procGlowClassColor then
                local _, ct = UnitClass("player")
                if ct then
                    local cc = RAID_CLASS_COLORS[ct]
                    if cc then
                        cr, cg, cb = cc.r, cc.g, cc.b
                    end
                end
            elseif ss.procGlowR ~= nil then
                cr, cg, cb = ss.procGlowR, ss.procGlowG or 0.788, ss.procGlowB or 0.137
            end
        end
    end

    -- Stop active glow if running (proc takes priority). The CD-state memo MUST follow
    -- the VISUAL: leaving _cdStateGlowOn true makes later re-evaluations skip the
    -- restart ("already on"), so a consumed proc kills the Resource Aware glow until
    -- usability flips off and on again (e.g. Shadowburn + Fiendish Cruelty). Proc
    -- priority is enforced by ns.StartCdGlow, which starts no glow on the shared
    -- overlay while the proc runs. The replaced glow is owed: StopProcGlow lights
    -- it again (ns.CdGlowKick) once the proc ends.
    -- A Blackout CD-state glow sits on its own overlay (fd.blackoutOverlay), which
    -- the proc glow does not replace: it stays lit beside the proc and keeps its
    -- memo, so the memo-gated stop sites still take it down when its cooldown
    -- ends, proc or not.
    if glow._glowActive then
        StopNativeGlow(glow)
    end
    if fd then
        local bo = fd.blackoutOverlay
        if not (bo and bo._glowActive) then
            if fd._cdStateGlowOn or fd._presetCdGlowOn then
                fd._cdGlowOwed = true
            end
            fd._cdStateGlowOn = false
        end
    end
    StartNativeGlow(glow, style, cr, cg, cb)
    if fd then
        fd.procGlowActive = true
    end
end

local function StopProcGlow(icon)
    local fd = icon and _getFD(icon)
    if not icon or not (fd and fd.procGlowActive) then
        return
    end
    local glow = fd and fd.glowOverlay or icon._glowOverlay
    StopNativeGlow(glow)
    if fd then
        fd.procGlowActive = false
    end
    -- The proc stomped any CD-state glow on this shared overlay; re-evaluate on the next frame
    -- so the glow comes straight back instead of waiting for the next cooldown/power edge:
    -- this icon alone when a CD-state glow is owed to it (replaced or held back by the proc),
    -- else the watched Resource Aware set. Gated on _cdGlowOwed / _cdGlowBoundSid: only icons
    -- that actually ran a CD-state glow path carry them, so pure proc-glow users never wake
    -- the flush frame.
    if fd._cdGlowOwed then
        mod.CdGlowKick(icon)
    elseif fd._cdGlowBoundSid and mod.QueueCDGlowResourceCheck then
        mod.QueueCDGlowResourceCheck()
    end
end

-- Install hooks on ActionButtonSpellAlertManager (called once during init)
local _procGlowHooksInstalled = false
local function InstallProcGlowHooks()
    if _procGlowHooksInstalled then
        return
    end
    if not ActionButtonSpellAlertManager then
        return
    end

    hooksecurefunc(ActionButtonSpellAlertManager, "ShowAlert", function(_, widget)
        if not widget then
            return
        end
        local barId, cdmChild = GetBarKeyForBlizzChild(widget)
        if not barId or not cdmChild then
            return
        end

        -- Hide Blizzard's built-in SpellActivationAlert on the CDM child
        if cdmChild.SpellActivationAlert then
            cdmChild.SpellActivationAlert:SetAlpha(0)
            cdmChild.SpellActivationAlert:Hide()
        end

        -- Apply immediately: no defer needed, icon mapping is current from the last reanchor.
        local ourIcon = FindOurIconForBlizzChild(barId, cdmChild)
        if not ourIcon then
            return
        end
        ShowProcGlow(ourIcon)
        -- Force texture re-evaluation so override textures apply immediately
        FC(ourIcon).lastTex = nil
    end)

    hooksecurefunc(ActionButtonSpellAlertManager, "HideAlert", function(_, widget)
        if not widget then
            return
        end
        local barId, cdmChild = GetBarKeyForBlizzChild(widget)
        if not barId or not cdmChild then
            return
        end
        local ourIcon = FindOurIconForBlizzChild(barId, cdmChild)
        local fd = ourIcon and _getFD(ourIcon)
        if not ourIcon or not (fd and fd.procGlowActive) then
            return
        end

        -- Trust Blizzard's HideAlert: stop immediately. A re-fired ShowAlert during an internal refresh restarts the glow next frame.
        StopProcGlow(ourIcon)
        -- Force texture re-evaluation so the original texture restores
        FC(ourIcon).lastTex = nil
    end)

    _procGlowHooksInstalled = true
end

-- No-ops kept so existing call sites don't error: proc glows are fully hook-driven for every bar, and the ShowAlert hooks installed at file load catch Blizzard's login re-fire.
local function ScanExistingProcGlows() end
mod.ScanExistingProcGlows = ScanExistingProcGlows

local function OnProcGlowEvent() end
mod.OnProcGlowEvent = OnProcGlowEvent

-- Install at file-load time: Blizzard re-fires ShowAlert during PLAYER_LOGIN for active procs, and the hooks MUST precede that.
InstallProcGlowHooks()

Inner.barDataByKey, Inner.cdmBarFrames, Inner.cdmBarIcons = barDataByKey, cdmBarFrames, cdmBarIcons
Inner.IconShownAlpha, Inner.InstallProcGlowHooks = IconShownAlpha, InstallProcGlowHooks
Inner.OnProcGlowEvent, Inner.ShowProcGlow = OnProcGlowEvent, ShowProcGlow
Inner.StartNativeGlow, Inner.StopNativeGlow = StartNativeGlow, StopNativeGlow
Inner.broken = false
