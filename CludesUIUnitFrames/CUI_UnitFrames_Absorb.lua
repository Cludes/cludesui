if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CUI_UnitFrames_Absorb.lua
--
--  Absorb and heal absorb styles, heal prediction, the Blizzard glow line,
--  the strip bar layout and CreateAbsorbBar, published through I for the
--  files that load after this one. Reads the main file through ns and
--  ns._internals; db is set through I.dbSetters.
-------------------------------------------------------------------------------
local _, mod = ...

local issecretvalue = issecretvalue
local Pix = CUI.PP

local Inner = mod._internals
local GetSettingsForUnit, UnsnapTex = Inner.GetSettingsForUnit, Inner.UnsnapTex
local healthBarTextures, AbbreviateNumbers = Inner.healthBarTextures, Inner.AbbreviateNumbers
local saved
Inner.dbSetters[#Inner.dbSetters + 1] = function(val) saved = val end

-- Shield texture. DO NOT change this path; it is the one that resolves.
local ABSORB_SHIELD_TEX = "Interface\\AddOns\\CludesUIUnitFrames\\Media\\shield.tga"

-- Absorb bar style textures (the shared catalogue in CludesUI.lua, also
-- read by the Resource Bars health bar) and alpha values.
local ABSORB_STYLE_TEX = CUI.ABSORB_STYLE_TEX
local ABSORB_STYLE_ALPHA = {
    striped = 0.8,
    stripedReversed = 0.8,
    clean = 0.3,
    blizzard = 0.8,
}
-- Tiled styles (one set for the live shield and heal-absorb bars and the
-- options preview) and the Absorb Style / Heal Absorb Style dropdown data
-- read by the Main Frames rows and the Textures page tile, all from the
-- shared catalogue. Readers copy the names and orders first: the
-- SharedMedia tail is appended into the copies.
mod.ABSORB_TILED_STYLES = CUI.ABSORB_TILED_STYLES
mod.ABSORB_STYLE_NAMES = CUI.ABSORB_STYLE_NAMES
mod.ABSORB_STYLE_ORDER = CUI.ABSORB_STYLE_ORDER
mod.HEAL_ABSORB_STYLE_ORDER = CUI.HEAL_ABSORB_STYLE_ORDER

-- Absorb-style key -> texture path. Built-ins come from ABSORB_STYLE_TEX; "sm:"
-- SharedMedia keys (shared with the Bar Texture dropdown, appended into
-- healthBarTextures by AppendSharedMediaTextures) fall through to the health-bar
-- lookup. Shared by the live render and the options preview so an SM key paints identically.
function mod.ResolveAbsorbStyleTex(style, fallback)
    return ABSORB_STYLE_TEX[style]
        or (CUI.ResolveTexturePath(healthBarTextures, style, fallback))
        or fallback
end

-- Effective absorb opacity: per-unit absorbOpacity once set, else legacy behavior
-- (clean uses absorbCleanAlpha, other styles a fixed 0.8). Read-time fallback, no migration.
local function GetAbsorbOpacity(style, prefs)
    if prefs and prefs.absorbOpacity then return prefs.absorbOpacity / 100 end
    if style == "clean" and prefs then return (prefs.absorbCleanAlpha or 30) / 100 end
    return ABSORB_STYLE_ALPHA[style] or 0.8
end

local function ApplyAbsorbStyle(absorbBar, style, prefs)
    if not absorbBar then return end
    local texture = mod.ResolveAbsorbStyleTex(style, ABSORB_SHIELD_TEX)
    local alpha = GetAbsorbOpacity(style, prefs)
    local ac = (prefs and prefs.absorbColor) or { r = 1, g = 1, b = 1 }
    -- Repeating tiles vs stretch (striped3 stays a stretch texture).
    local tiled = mod.ABSORB_TILED_STYLES[style] == true
    local mask = absorbBar._absorbMask
    absorbBar:SetStatusBarTexture(texture)
    -- Per-component default: a partial colour table would throw here.
    absorbBar:SetStatusBarColor(ac.r or 1, ac.g or 1, ac.b or 1, alpha)
    local fillTex = absorbBar:GetStatusBarTexture()
    if fillTex then
        fillTex:SetDrawLayer("ARTWORK", 1)
        fillTex:SetHorizTile(tiled)
        fillTex:SetVertTile(tiled)
        if mask then fillTex:AddMaskTexture(mask) end
    end
    -- New fill object + tiling state: re-derive rotation (stretch styles rotate
    -- on a vertical bar, tiled ones must not).
    mod.ApplyFillRotation(absorbBar)
    local fillW = absorbBar._forward
    if fillW then
        fillW:SetStatusBarTexture(texture)
        fillW:SetStatusBarColor(ac.r, ac.g, ac.b, alpha)
        local fwFill = fillW:GetStatusBarTexture()
        if fwFill then
            fwFill:SetDrawLayer("ARTWORK", 1)
            fwFill:SetHorizTile(tiled)
            fwFill:SetVertTile(tiled)
            if mask then fwFill:AddMaskTexture(mask) end
        end
        mod.ApplyFillRotation(fillW)
    end
    -- New fill object: the glow lines that ride it re-seat (built only once
    -- the Blizzard Glow Line was turned on).
    if absorbBar._glow then mod.UF_AbsorbGlowAnchor(absorbBar) end
end

-- Read-only stand-ins for unset settings and lookups the absorb painter makes
-- on every event, so a paint builds no table and runs no pattern match.
local COLOR_WHITE = { r = 1, g = 1, b = 1 }
local DEF_HEAL_ABSORB_COLOR = { r = 0.8, g = 0.15, b = 0.15 }
local DEF_HEAL_ABSORB_BAR_COLOR = { r = 200 / 255, g = 29 / 255, b = 29 / 255 }
-- Absorb Short text gate zone -> the frame's text field for that zone.
local GATE_ZONE_TEXT = { left = "LeftText", right = "RightText", center = "CenterText", extra = "ExtraText" }
-- Unit token -> boss frame unit; each token is matched once.
local IS_BOSS_UNIT = setmetatable({}, {
    __index = function(tbl, unitToken)
        local isBoss = unitToken:match("^boss") ~= nil
        tbl[unitToken] = isBoss
        return isBoss
    end,
})

-- Heal absorb styling (mirrors the raid frames Absorbs section). Defaults are
-- clean white8x8, red, 0.65 alpha.
local function ApplyHealAbsorbStyle(haBar, style, prefs)
    if not haBar then return end
    local texture = mod.ResolveAbsorbStyleTex(style, "Interface\\Buttons\\WHITE8X8")
    local alpha = ((prefs and prefs.healAbsorbOpacity) or 65) / 100
    local hc = (prefs and prefs.healAbsorbColor) or { r = 0.8, g = 0.15, b = 0.15 }
    -- The "Large Outlined Stripes" styles are pre-colored; render them untinted.
    if style == "largeOutlinedStripes" or style == "largeOutlinedStripesR" then
        hc = { r = 1, g = 1, b = 1 }
    end
    local tiled = mod.ABSORB_TILED_STYLES[style] == true
    local mask = haBar._absorbMask
    haBar:SetStatusBarTexture(texture)
    haBar:SetStatusBarColor(hc.r or 0.8, hc.g or 0.15, hc.b or 0.15, alpha)
    local fillTex = haBar:GetStatusBarTexture()
    if fillTex then
        fillTex:SetDrawLayer("ARTWORK", 2)
        fillTex:SetHorizTile(tiled)
        fillTex:SetVertTile(tiled)
        if mask then fillTex:AddMaskTexture(mask) end
    end
    mod.ApplyFillRotation(haBar)
end

-- Two-segment absorb rendering via dynamic clip frames, works with secret-valued
-- absorbs: the value can't be split in Lua (min/subtract on secrets is blocked), so
-- STATUSBAR CLIPPING does the math visually. curClip bounds hpBar.LEFT->healthTexture.RIGHT
-- (dynamic); missClip bounds healthTexture.RIGHT->hpBar.RIGHT (dynamic). The shield
-- fills RIGHTWARD first (into missing health) and only backfills into the filled
-- portion once absorb exceeds missing health.
--   forward bar (primary): child of missClip, forward fill, TOPLEFT at
--     healthTexture.TOPRIGHT, width = hpBar width. Fills rightward by
--     (absorbAmt/maxHealth)*hpWidth; missClip cuts past hpBar.RIGHT, so visible width
--     is exactly min(absorb, missing).
--   backfill bar (overflow): child of curClip, reverse fill, TOPRIGHT at hpBar.TOPRIGHT,
--     width = hpBar width. Fills leftward from hpBar.RIGHT; curClip cuts past
--     healthTexture.RIGHT, so visible width is exactly max(0, absorb-missing) -- only
--     shows on overflow.
-- Both bars get the raw (secret-safe) absorbAmt via SetValue; no Lua arithmetic on it
-- ever happens. Wired into oUF via HealthPrediction.Override so oUF keeps event
-- registration (UNIT_HEALTH, UNIT_ABSORB_AMOUNT_CHANGED, ...) and enable/disable.

-- Re-anchor existing absorb bars for the current fill state (reverse + axis).
-- Called from the live-update path on a reverse/vertical fill toggle.
-- `settingsOverride` lets the creation path pass the settings table it already
-- holds, for frames whose ._cuiUnit is not resolvable yet.
local function UpdateAbsorbBarReverseFill(widget, reversed, settingsOverride)
    if not widget or not widget.HealthPrediction then return end
    local absorbBar = widget.HealthPrediction.damageAbsorb
    if not absorbBar then return end
    local fillW = absorbBar._forward
    local nowClip = absorbBar._curClip
    local missClip = absorbBar._missClip
    local healthBar = absorbBar._hpBar
    if not (fillW and nowClip and missClip and healthBar) then return end
    local healthTex = healthBar:GetStatusBarTexture()
    if not healthTex then return end

    absorbBar._isReversed = reversed and true or false

    -- Placement (mirrors the raid frames Absorbs section):
    --   overlay = backfill into the filled health from the HP edge (default)
    --   right   = full bar, fill from the frame's right edge
    --   left    = full bar, fill from the frame's left edge
    local cfg = settingsOverride or GetSettingsForUnit(widget._cuiUnit)
    local absorbStyle = (cfg and cfg.absorbEdgeMode) or "overlay"
    local healMode = (cfg and cfg.healAbsorbEdgeMode) or "overlay"
    -- Overshield "From Left" (overlay placement only): the excess grows from
    -- the bar's ORIGIN edge (left; right when reverse-filled; bottom/top on
    -- the vertical axis) instead of hanging off the fill edge. Mechanism:
    -- the Overlay Reverse fill-texture anchors with the OPPOSITE fill
    -- direction -- the bar's origin end sits one bar-length before the fill
    -- edge, so the clip shows exactly the absorb exceeding missing health,
    -- emerging from the frame's origin edge. nil overshieldMode falls back
    -- to the legacy showOvershield boolean (saved toggles keep meaning).
    local osm = cfg and cfg.overshieldMode
    if osm == nil then osm = (cfg and cfg.showOvershield == false) and "never" or "always" end
    local osFromLeft = osm == "fromleft"
    -- Overlay Reverse (Full): Overlay Reverse, plus the forward bar filling
    -- from the bar's ORIGIN edge, so the missing-health clip shows the absorb
    -- exceeding current health past the fill edge instead of losing it. Its
    -- clip starts exactly at the fill edge: the 1px seal into the fill would
    -- double that pixel over the backfill.
    local orFull = absorbStyle == "overlayReverseFull"

    -- Vertical fill: the whole HP cluster rotates with the health bar. Every anchor
    -- below is the horizontal layout with its axis swapped -- the health fill's RIGHT
    -- edge (the "HP edge" shields/heal absorb hang off) becomes its TOP edge, reverse
    -- fill flips it to BOTTOM. Edge modes keep their key names: "right" = far edge of
    -- the fill axis (top when vertical), "left" = near edge (bottom when vertical).
    local isVert = (cfg and cfg.healthVerticalFill) and true or false
    absorbBar._isVert = isVert
    local healAbsorb = absorbBar._healAbsorb
    local healCut = absorbBar._healClip
    -- Indexed, not ipairs: ha can be nil and ipairs would stop at the hole.
    local axisBars = { absorbBar, fillW, healAbsorb }
    for index = 1, 3 do
        local barFrame = axisBars[index]
        if barFrame then
            barFrame:SetOrientation(isVert and "VERTICAL" or "HORIZONTAL")
            mod.ApplyFillRotation(barFrame) -- rotate stretch styles only
        end
    end

    nowClip:ClearAllPoints()
    missClip:ClearAllPoints()
    absorbBar:ClearAllPoints()
    fillW:ClearAllPoints()

    if isVert then
        -- missClip + forward bar use the overlay layout (from the origin edge in
        -- Overlay Reverse (Full)); in the other modes the backfill shows the
        -- absorb and the Override hides fw.
        if reversed then
            missClip:SetPoint("TOPLEFT", healthTex, "BOTTOMLEFT", 0, orFull and 0 or 1)
            missClip:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
            fillW:SetReverseFill(true)
            if orFull then
                fillW:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
                fillW:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
            else
                fillW:SetPoint("TOPLEFT", healthTex, "BOTTOMLEFT", 0, 0)
                fillW:SetPoint("TOPRIGHT", healthTex, "BOTTOMRIGHT", 0, 0)
            end
        else
            missClip:SetPoint("BOTTOMLEFT", healthTex, "TOPLEFT", 0, orFull and 0 or -1)
            missClip:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
            fillW:SetReverseFill(false)
            if orFull then
                fillW:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 0, 0)
                fillW:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
            else
                fillW:SetPoint("BOTTOMLEFT", healthTex, "TOPLEFT", 0, 0)
                fillW:SetPoint("BOTTOMRIGHT", healthTex, "TOPRIGHT", 0, 0)
            end
        end

        -- Shield absorb placement.
        if absorbStyle == "right" or absorbStyle == "left" then
            nowClip:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
            nowClip:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
            if absorbStyle == "left" then
                absorbBar:SetReverseFill(false)
                absorbBar:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 0, 0)
                absorbBar:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
            else
                absorbBar:SetReverseFill(true)
                absorbBar:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
                absorbBar:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
            end
        elseif absorbStyle == "overlayReverse" or orFull then
            -- Overlay Reverse: the WHOLE absorb fills from the health fill's
            -- leading edge back INTO the fill; the filled-region clip masks
            -- any excess past empty, so shields larger than current health
            -- never escape the fill (fw hidden by the Override, like the edge
            -- modes; Full draws that excess through fw instead).
            -- Axis-swapped for vertical, mirrored for reversed fill.
            if reversed then
                nowClip:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
                nowClip:SetPoint("BOTTOMRIGHT", healthTex, "BOTTOMRIGHT", 0, 0)
                absorbBar:SetReverseFill(false)
                absorbBar:SetPoint("BOTTOMLEFT", healthTex, "BOTTOMLEFT", 0, 0)
                absorbBar:SetPoint("BOTTOMRIGHT", healthTex, "BOTTOMRIGHT", 0, 0)
            else
                nowClip:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 0, 0)
                nowClip:SetPoint("TOPRIGHT", healthTex, "TOPRIGHT", 0, 0)
                absorbBar:SetReverseFill(true)
                absorbBar:SetPoint("TOPLEFT", healthTex, "TOPLEFT", 0, 0)
                absorbBar:SetPoint("TOPRIGHT", healthTex, "TOPRIGHT", 0, 0)
            end
        elseif reversed then
            nowClip:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
            nowClip:SetPoint("BOTTOMRIGHT", healthTex, "BOTTOMRIGHT", 0, 0)
            if osFromLeft then
                absorbBar:SetReverseFill(true)
                absorbBar:SetPoint("BOTTOMLEFT", healthTex, "BOTTOMLEFT", 0, 0)
                absorbBar:SetPoint("BOTTOMRIGHT", healthTex, "BOTTOMRIGHT", 0, 0)
            else
                absorbBar:SetReverseFill(false)
                absorbBar:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 0, 0)
                absorbBar:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
            end
        else
            nowClip:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 0, 0)
            nowClip:SetPoint("TOPRIGHT", healthTex, "TOPRIGHT", 0, 0)
            if osFromLeft then
                absorbBar:SetReverseFill(false)
                absorbBar:SetPoint("TOPLEFT", healthTex, "TOPLEFT", 0, 0)
                absorbBar:SetPoint("TOPRIGHT", healthTex, "TOPRIGHT", 0, 0)
            else
                absorbBar:SetReverseFill(true)
                absorbBar:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
                absorbBar:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
            end
        end

        -- Heal absorb placement (own clip frame, same rules).
        if healCut then
            healCut:ClearAllPoints()
            if healMode == "right" or healMode == "left" then
                healCut:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
                healCut:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
            elseif reversed then
                healCut:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
                healCut:SetPoint("BOTTOMRIGHT", healthTex, "BOTTOMRIGHT", 0, 0)
            else
                healCut:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 0, 0)
                healCut:SetPoint("TOPRIGHT", healthTex, "TOPRIGHT", 0, 0)
            end
        end
        if healAbsorb then
            healAbsorb:ClearAllPoints()
            if healMode == "right" then
                healAbsorb:SetReverseFill(true)
                healAbsorb:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
                healAbsorb:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
            elseif healMode == "left" then
                healAbsorb:SetReverseFill(false)
                healAbsorb:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 0, 0)
                healAbsorb:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
            elseif reversed then
                healAbsorb:SetReverseFill(false)
                healAbsorb:SetPoint("BOTTOMLEFT", healthTex, "BOTTOMLEFT", 0, 0)
                healAbsorb:SetPoint("BOTTOMRIGHT", healthTex, "BOTTOMRIGHT", 0, 0)
            else
                healAbsorb:SetReverseFill(true)
                healAbsorb:SetPoint("TOPLEFT", healthTex, "TOPLEFT", 0, 0)
                healAbsorb:SetPoint("TOPRIGHT", healthTex, "TOPRIGHT", 0, 0)
            end
        end
        if absorbBar._predOn then
            mod.UF_AnchorHealPred(absorbBar)
            mod.UF_HealPredLayout(absorbBar)
        end
        return
    end

    -- missClip + forward bar use the overlay layout (from the origin edge in
    -- Overlay Reverse (Full)); in the other modes the backfill shows the
    -- absorb and the Override hides fw.
    if reversed then
        missClip:SetPoint("TOPRIGHT", healthTex, "TOPLEFT", orFull and 0 or 1, 0)
        missClip:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 0, 0)
        fillW:SetReverseFill(true)
        if orFull then
            fillW:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
            fillW:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
        else
            fillW:SetPoint("TOPRIGHT", healthTex, "TOPLEFT", 0, 0)
            fillW:SetPoint("BOTTOMRIGHT", healthTex, "BOTTOMLEFT", 0, 0)
        end
    else
        missClip:SetPoint("TOPLEFT", healthTex, "TOPRIGHT", orFull and 0 or -1, 0)
        missClip:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
        fillW:SetReverseFill(false)
        if orFull then
            fillW:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
            fillW:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 0, 0)
        else
            fillW:SetPoint("TOPLEFT", healthTex, "TOPRIGHT", 0, 0)
            fillW:SetPoint("BOTTOMLEFT", healthTex, "BOTTOMRIGHT", 0, 0)
        end
    end

    -- Shield absorb placement
    if absorbStyle == "right" or absorbStyle == "left" then
        -- Full bar: clip covers the whole health bar, backfill anchors to the
        -- chosen frame edge (absolute, independent of reverse fill).
        nowClip:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
        nowClip:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
        if absorbStyle == "left" then
            absorbBar:SetReverseFill(false)
            absorbBar:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
            absorbBar:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 0, 0)
        else
            absorbBar:SetReverseFill(true)
            absorbBar:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
            absorbBar:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
        end
    elseif absorbStyle == "overlayReverse" or orFull then
        -- Overlay Reverse: the WHOLE absorb fills from the health fill's
        -- leading edge back INTO the fill; the filled-region clip masks any
        -- excess past empty (fw hidden by the Override, like the edge modes;
        -- Full draws that excess through fw instead).
        if reversed then
            nowClip:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
            nowClip:SetPoint("BOTTOMLEFT", healthTex, "BOTTOMLEFT", 0, 0)
            absorbBar:SetReverseFill(false)
            absorbBar:SetPoint("TOPLEFT", healthTex, "TOPLEFT", 0, 0)
            absorbBar:SetPoint("BOTTOMLEFT", healthTex, "BOTTOMLEFT", 0, 0)
        else
            nowClip:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
            nowClip:SetPoint("BOTTOMRIGHT", healthTex, "BOTTOMRIGHT", 0, 0)
            absorbBar:SetReverseFill(true)
            absorbBar:SetPoint("TOPRIGHT", healthTex, "TOPRIGHT", 0, 0)
            absorbBar:SetPoint("BOTTOMRIGHT", healthTex, "BOTTOMRIGHT", 0, 0)
        end
    elseif reversed then
        nowClip:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
        nowClip:SetPoint("BOTTOMLEFT", healthTex, "BOTTOMLEFT", 0, 0)
        if osFromLeft then
            absorbBar:SetReverseFill(true)
            absorbBar:SetPoint("TOPLEFT", healthTex, "TOPLEFT", 0, 0)
            absorbBar:SetPoint("BOTTOMLEFT", healthTex, "BOTTOMLEFT", 0, 0)
        else
            absorbBar:SetReverseFill(false)
            absorbBar:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
            absorbBar:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 0, 0)
        end
    else
        nowClip:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
        nowClip:SetPoint("BOTTOMRIGHT", healthTex, "BOTTOMRIGHT", 0, 0)
        if osFromLeft then
            absorbBar:SetReverseFill(false)
            absorbBar:SetPoint("TOPRIGHT", healthTex, "TOPRIGHT", 0, 0)
            absorbBar:SetPoint("BOTTOMRIGHT", healthTex, "BOTTOMRIGHT", 0, 0)
        else
            absorbBar:SetReverseFill(true)
            absorbBar:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
            absorbBar:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
        end
    end

    -- Heal absorb placement, independent of shield absorb. It has its OWN clip
    -- frame (ab._healClip) so right/left span the full bar (filled + missing
    -- health) while overlay stays clipped to filled health.
    if healCut then
        healCut:ClearAllPoints()
        if healMode == "right" or healMode == "left" then
            healCut:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
            healCut:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
        elseif reversed then
            healCut:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
            healCut:SetPoint("BOTTOMLEFT", healthTex, "BOTTOMLEFT", 0, 0)
        else
            healCut:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
            healCut:SetPoint("BOTTOMRIGHT", healthTex, "BOTTOMRIGHT", 0, 0)
        end
    end
    if healAbsorb then
        healAbsorb:ClearAllPoints()
        if healMode == "right" then
            healAbsorb:SetReverseFill(true)
            healAbsorb:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
            healAbsorb:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
        elseif healMode == "left" then
            healAbsorb:SetReverseFill(false)
            healAbsorb:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
            healAbsorb:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 0, 0)
        else
            -- Overlay: eat into the filled health from the HP edge, mirrored for
            -- reverse-filled health bars.
            healAbsorb:SetReverseFill(not reversed)
            if reversed then
                healAbsorb:SetPoint("TOPLEFT", healthTex, "TOPLEFT", 0, 0)
                healAbsorb:SetPoint("BOTTOMLEFT", healthTex, "BOTTOMLEFT", 0, 0)
            else
                healAbsorb:SetPoint("TOPRIGHT", healthTex, "TOPRIGHT", 0, 0)
                healAbsorb:SetPoint("BOTTOMRIGHT", healthTex, "BOTTOMRIGHT", 0, 0)
            end
        end
    end
    if absorbBar._predOn then
        mod.UF_AnchorHealPred(absorbBar)
        mod.UF_HealPredLayout(absorbBar)
    end
end

-------------------------------------------------------------------------------
--  Heal Prediction (opt-in per unit, s.healPrediction; player, target and
--  focus): incoming heals drawn past the health fill as two segments, the
--  player's own heals first, then everyone else's. Both are StatusBars fed by
--  a heal prediction calculator (secret-safe: values only reach SetValue).
--  Cost: off builds nothing and leaves the engine's opt-in "healpred" channel
--  off the frame, so no event or repaint reaches it. On, that channel
--  registers UNIT_HEAL_PREDICTION for the one unit (plus the vehicle for the
--  player) and joins its max-health and heal-absorb routes; the engine's
--  same-frame stamp collapses bursts (one trailing next-frame paint settles a
--  deduped repeat), and a paint is one calculator fill, the range and two
--  SetValue calls.
--  No current-health input: the calculator clamps to MAXIMUM health, the
--  segments ride the health fill's edge by anchor, and a clip cuts them at the
--  bar's end -- Overheal 0: the missing-health clip; Overheal > 0: a holder
--  outside the frame's bar clip that clips at the end plus the allowance.
--  Style (texture, colors, opacity, Overheal) is applied by UF_HealPredApply
--  from the spawn and settings reload paths, size by the health bar's
--  OnSizeChanged; never per paint.
--  On ns: this chunk sits at the Lua 5.1 local ceiling.
-------------------------------------------------------------------------------
mod.UF_HEAL_PRED_MY = { r = 102 / 255, g = 243 / 255, b = 102 / 255 }
mod.UF_HEAL_PRED_OTHER = { r = 40 / 255, g = 170 / 255, b = 40 / 255 }
mod.UF_HEAL_PRED_UNITS = { player = true, target = true, focus = true }

-- Anchors both segments at the health fill's leading edge, in the fill
-- direction (reverse and vertical fill included), the others' segment
-- starting where the player's ends.
function mod.UF_AnchorHealPred(absorbBar)
    local my, other = absorbBar._predMy, absorbBar._predOther
    local healthTex = absorbBar._hpBar and absorbBar._hpBar:GetStatusBarTexture()
    if not (my and healthTex) then return end
    local myTex = my:GetStatusBarTexture()
    local isVert, isRev = absorbBar._isVert and true or false, absorbBar._isReversed and true or false
    for index = 1, 2 do
        local barFrame = (index == 1) and my or other
        barFrame:SetOrientation(isVert and "VERTICAL" or "HORIZONTAL")
        mod.ApplyFillRotation(barFrame)
        barFrame:SetReverseFill(isRev)
        barFrame:ClearAllPoints()
    end
    local a1, b1, a2, b2
    if isVert then
        if isRev then
            a1, b1, a2, b2 = "TOPLEFT", "BOTTOMLEFT", "TOPRIGHT", "BOTTOMRIGHT"
        else
            a1, b1, a2, b2 = "BOTTOMLEFT", "TOPLEFT", "BOTTOMRIGHT", "TOPRIGHT"
        end
    elseif isRev then
        a1, b1, a2, b2 = "TOPRIGHT", "TOPLEFT", "BOTTOMRIGHT", "BOTTOMLEFT"
    else
        a1, b1, a2, b2 = "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT"
    end
    my:SetPoint(a1, healthTex, b1, 0, 0)
    my:SetPoint(a2, healthTex, b2, 0, 0)
    other:SetPoint(a1, myTex, b1, 0, 0)
    other:SetPoint(a2, myTex, b2, 0, 0)
end

function mod.UF_NewHealPredBar(absorbBar)
    local barFrame = CreateFrame("StatusBar", nil, absorbBar._missClip)
    barFrame:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    local fillTex = barFrame:GetStatusBarTexture()
    if fillTex and absorbBar._absorbMask then fillTex:AddMaskTexture(absorbBar._absorbMask) end
    barFrame:SetMinMaxValues(0, 1)
    barFrame:SetValue(0)
    barFrame:SetFrameLevel(absorbBar._hpBar:GetFrameLevel() + 1)
    barFrame:Hide()
    return barFrame
end

-- Seats the segment fills' masks: the health-bar-bounds edge mask and, under
-- Blizzard Style, the stock bar shape (ab._blizzMaskOn, stamped by the art
-- pass). Both apply only while the segments sit inside the bar (Overheal 0).
-- A texture swap makes new fills, so this runs after every swap, parent
-- change and art pass.
function mod.UF_HealPredMasks(absorbBar)
    local inside = (absorbBar._predOver or 0) == 0
    local edge = absorbBar._absorbMask
    local shape = absorbBar._hpBar._blizzMask
    for index = 1, 2 do
        local barFrame = (index == 1) and absorbBar._predMy or absorbBar._predOther
        local fillTex = barFrame:GetStatusBarTexture()
        if fillTex then
            if edge then
                pcall(fillTex.RemoveMaskTexture, fillTex, edge)
                if inside then fillTex:AddMaskTexture(edge) end
            end
            if shape then
                pcall(fillTex.RemoveMaskTexture, fillTex, shape)
                if inside and absorbBar._blizzMaskOn then fillTex:AddMaskTexture(shape) end
            end
        end
    end
end

-- Size and the Overheal holder: both follow the health bar's size and fill
-- axis. Runs from the style pass, the absorb re-anchor pass and the health
-- bar's OnSizeChanged.
function mod.UF_HealPredLayout(absorbBar)
    local health = absorbBar._hpBar
    local wid, hgt = health:GetWidth(), health:GetHeight()
    absorbBar._predMy:SetSize(wid, hgt)
    absorbBar._predOther:SetSize(wid, hgt)
    local over = absorbBar._predOver or 0
    local holderFrame = absorbBar._predHolder
    if over > 0 and holderFrame then
        local ext = (absorbBar._isVert and hgt or wid) * over / 100
        local left, right, top, bottom = 0, 0, 0, 0
        if absorbBar._isVert then
            if absorbBar._isReversed then
                bottom = -ext
            else
                top = ext
            end
        elseif absorbBar._isReversed then
            left = -ext
        else
            right = ext
        end
        holderFrame:ClearAllPoints()
        holderFrame:SetPoint("TOPLEFT", health, "TOPLEFT", left, top)
        holderFrame:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", right, bottom)
    end
end

-- The healpred channel's painter: values only, no style work.
function mod.UF_PaintHealPred(widget, unitToken)
    local absorbBar = widget.HealthPrediction.damageAbsorb
    if not absorbBar._predOn then return end
    local calculator = absorbBar._predCalc
    UnitGetDetailedHealPrediction(unitToken, "player", calculator)
    local _, myHeals, others = calculator:GetIncomingHeals()
    local healthMax = UnitHealthMax(unitToken) or 0
    local my, other = absorbBar._predMy, absorbBar._predOther
    my:SetMinMaxValues(0, healthMax)
    other:SetMinMaxValues(0, healthMax)
    my:SetValue(myHeals)
    other:SetValue(others)
end
mod.Engine.SetPainter("healpred", mod.UF_PaintHealPred)

-- Style pass + channel sync for one frame (unitKey = its settings key).
-- Idempotent; runs at spawn and on every settings reload, after the health
-- texture is applied. Off tears down to hidden bars and no channel.
function mod.UF_HealPredApply(widget, unitKey, cfg)
    local healthEnd = widget.HealthPrediction
    local absorbBar = healthEnd and healthEnd.damageAbsorb
    if not (absorbBar and absorbBar._missClip) then return end
    local enabled = mod.UF_HEAL_PRED_UNITS[unitKey]
            and cfg
            and cfg.healPrediction == true
            and CreateUnitHealPredictionCalculator
            and UnitGetDetailedHealPrediction
            and true
        or false
    if not enabled then
        if absorbBar._predOn then
            absorbBar._predOn = false
            absorbBar._predMy:Hide()
            absorbBar._predOther:Hide()
            mod.Engine.SetChannelOn(widget, "healpred", false)
        end
        return
    end
    local health = absorbBar._hpBar
    if not absorbBar._predMy then
        absorbBar._predMy = mod.UF_NewHealPredBar(absorbBar)
        absorbBar._predOther = mod.UF_NewHealPredBar(absorbBar)
        local calculator = CreateUnitHealPredictionCalculator()
        -- Every clamp reads maximum health, never current health, so the clip
        -- does the missing-health cut and no health event is needed; heal
        -- absorbs reduce the drawn heal (their own event is routed).
        local modes = Enum and Enum.UnitIncomingHealClampMode
        if calculator.SetIncomingHealClampMode and modes then
            calculator:SetIncomingHealClampMode(modes.MaximumHealth)
        end
        local haClamp = Enum and Enum.UnitHealAbsorbClampMode
        if calculator.SetHealAbsorbClampMode and haClamp then
            calculator:SetHealAbsorbClampMode(haClamp.MaximumHealth)
        end
        local haMode = Enum and Enum.UnitHealAbsorbMode
        if calculator.SetHealAbsorbMode and haMode then
            calculator:SetHealAbsorbMode(haMode.ReducedByIncomingHeals)
        end
        absorbBar._predCalc = calculator
        -- Our own health bar; returns at once while the option is off.
        health:HookScript("OnSizeChanged", function()
            if absorbBar._predOn then mod.UF_HealPredLayout(absorbBar) end
        end)
    end
    local my, other = absorbBar._predMy, absorbBar._predOther
    -- Texture (s.healPredTexture): "health" (default) follows the frame's own
    -- health bar, read off its fill so every texture path (per frame, profile,
    -- donor, Blizzard Style) matches; "flat" is a plain fill; anything else is a
    -- health-bar texture key. A swap makes new fill objects, so the others'
    -- anchor, fill rotation and the masks are re-seated after it.
    local texKey = cfg.healPredTexture or "health"
    local filePath
    if texKey == "health" then
        local hFill = health:GetStatusBarTexture()
        filePath = hFill and hFill:GetTexture()
    elseif texKey ~= "flat" then
        filePath = CUI.ResolveTexturePath(healthBarTextures, texKey, nil)
    end
    filePath = filePath or "Interface\\Buttons\\WHITE8X8"
    local retex = absorbBar._predTexPath ~= filePath
    if retex then
        absorbBar._predTexPath = filePath
        for index = 1, 2 do
            local barFrame = (index == 1) and my or other
            barFrame:SetStatusBarTexture(filePath)
            local fillTex = barFrame:GetStatusBarTexture()
            if fillTex then UnsnapTex(fillTex) end
        end
    end
    -- While off, the re-anchor pass skips the bars, so turning on re-seats
    -- them for the current fill axis.
    if retex or not absorbBar._predOn then mod.UF_AnchorHealPred(absorbBar) end
    -- Overheal: how far past full health the bars may run (0 = stop at the
    -- end). The health bar sits inside the frame's bar clip, so running past
    -- its end takes a holder outside it, parented to the unit frame; the masks
    -- come off there. Layout places the holder.
    local over = tonumber(cfg.healPredOverheal) or 0
    local relayout = (not absorbBar._predOn) or absorbBar._predOver ~= over
    if retex or absorbBar._predOver ~= over then
        absorbBar._predOver = over
        local hostFrame = absorbBar._missClip
        if over > 0 then
            local holderFrame = absorbBar._predHolder
            if not holderFrame then
                holderFrame = CreateFrame("Frame", nil, widget)
                holderFrame:SetClipsChildren(true)
                absorbBar._predHolder = holderFrame
            end
            holderFrame:SetFrameLevel(health:GetFrameLevel() + 1)
            hostFrame = holderFrame
        end
        for index = 1, 2 do
            local barFrame = (index == 1) and other or my
            barFrame:SetParent(hostFrame)
            barFrame:SetFrameLevel(health:GetFrameLevel() + index)
        end
        mod.UF_HealPredMasks(absorbBar)
    end
    local alpha = (cfg.healPredOpacity or 60) / 100
    local mc = cfg.healPredColor or mod.UF_HEAL_PRED_MY
    local oc = cfg.healPredOtherColor or mod.UF_HEAL_PRED_OTHER
    my:SetStatusBarColor(mc.r, mc.g, mc.b, alpha)
    other:SetStatusBarColor(oc.r, oc.g, oc.b, alpha)
    -- While on, the re-anchor pass and the size hook keep the layout current.
    if relayout then mod.UF_HealPredLayout(absorbBar) end
    my:Show()
    other:Show()
    absorbBar._predOn = true
    mod.Engine.SetChannelOn(widget, "healpred", true)
    if widget:IsShown() then mod.UF_PaintHealPred(widget, widget._cuiUnit) end
end

-------------------------------------------------------------------------------
--  Max Health Style (opt-in per unit, s.maxHealthStyle; player, target and
--  focus, where Blizzard's own frames draw max health loss, and boss frames
--  through Target's): the part of the maximum a debuff took, as a styled
--  overlay on the health bar's far end (Raid Frames parity; the look is
--  CludesUI.ApplyMaxHealthStyle). Only loss is drawn. Off builds nothing;
--  on, the opt-in "maxhp" channel repaints it on the unit's max health events.
-------------------------------------------------------------------------------
mod.UF_MAXHP_UNITS = { player = true, target = true, focus = true }

-- Texture, tint, opacity and the black backing; shared with the options preview.
function mod.UF_ApplyMaxHealthStyle(barFrame, style, cfg, mask)
    local fillTex = CUI.ApplyMaxHealthStyle(barFrame, style, cfg, mod.ResolveAbsorbStyleTex)
    if fillTex then
        if mask then
            pcall(fillTex.RemoveMaskTexture, fillTex, mask)
            fillTex:AddMaskTexture(mask)
        end
        -- A retexture can replace the fill object: re-seat the backing on it.
        local backdrop = barFrame._bg
        if backdrop then
            backdrop:SetColorTexture(0, 0, 0, ((cfg and cfg.maxHealthBgOpacity) or 100) / 100)
            backdrop:ClearAllPoints()
            backdrop:SetAllPoints(fillTex)
        end
    end
end

-- The loss sits at the bar's far end, on whichever fill axis the health bar uses.
function mod.UF_OrientMaxHealth(barFrame, reversed, isVert)
    barFrame:SetOrientation(isVert and "VERTICAL" or "HORIZONTAL")
    barFrame:SetReverseFill(not reversed)
    mod.ApplyFillRotation(barFrame)
end

-- The maxhp channel's painter. The API returns a plain fraction of the maximum
-- (never secret, never nil); only loss is drawn, as on Blizzard's frames.
function mod.UF_PaintMaxHp(widget, unitToken)
    local healthEnd = widget.HealthPrediction
    local absorbBar = healthEnd and healthEnd.damageAbsorb
    local barFrame = absorbBar and absorbBar._maxHp
    if not (barFrame and absorbBar._maxHpOn) then return end
    local pct = GetUnitTotalModifiedMaxHealthPercent(unitToken)
    if pct > 0 then
        barFrame:SetValue(math.min(pct, 1))
        barFrame:Show()
    else
        barFrame:Hide()
    end
end
mod.Engine.SetPainter("maxhp", mod.UF_PaintMaxHp)

-- Style pass + channel sync for one frame (unitKey = its unit token); runs at
-- spawn and on every settings reload, after the absorb bars' fill axis is set.
function mod.UF_MaxHpApply(widget, unitKey)
    local healthEnd = widget.HealthPrediction
    local absorbBar = healthEnd and healthEnd.damageAbsorb
    if not (absorbBar and absorbBar._hpBar and saved) then return end
    local s
    if IS_BOSS_UNIT[unitKey] then
        local b = saved.profile.boss
        if not (b and b.showAbsorbs == false) then s = saved.profile.target end
    elseif mod.UF_MAXHP_UNITS[unitKey] then
        s = GetSettingsForUnit(unitKey)
    end
    local style = (s and s.maxHealthStyle) or "none"
    local barFrame = absorbBar._maxHp
    if style == "none" then
        if absorbBar._maxHpOn then
            absorbBar._maxHpOn = false
            barFrame:Hide()
            mod.Engine.SetChannelOn(widget, "maxhp", false)
        end
        return
    end
    if not barFrame then
        barFrame = CreateFrame("StatusBar", nil, absorbBar._hpBar)
        barFrame:SetAllPoints(absorbBar._hpBar)
        barFrame:SetFrameLevel(absorbBar._hpBar:GetFrameLevel() + 2)
        barFrame:SetMinMaxValues(0, 1)
        barFrame._bg = barFrame:CreateTexture(nil, "ARTWORK", nil, 2)
        barFrame:Hide()
        absorbBar._maxHp = barFrame
    end
    mod.UF_ApplyMaxHealthStyle(barFrame, style, s, absorbBar._absorbMask)
    mod.UF_OrientMaxHealth(barFrame, absorbBar._isReversed, absorbBar._isVert)
    if not absorbBar._maxHpOn then
        absorbBar._maxHpOn = true
        mod.Engine.SetChannelOn(widget, "maxhp", true)
    end
    mod.UF_PaintMaxHp(widget, widget._cuiUnit or unitKey)
end

-------------------------------------------------------------------------------
--  Blizzard Glow Line (opt-in per unit, s.absorbGlowLine; player, target and
--  focus, and boss frames through the Target styling they draw absorbs with).
--  A soft line on the shield's edge next to current health. Placement
--  (g.ge), resolved by the settings pass:
--    1 = Overlay: the current-health seam, moving to the overshield's inner
--        edge while overshielding (the bar's far end with Show Overshield Never);
--    2 = Overlay with Show Overshield From Left: the seam, moving to the
--        from-left overshield's edge;
--    3 = Overlay Reverse: the shield's inner end, which always meets health;
--    5 = the far-edge placement (From Right Edge; From Left Edge on a reverse
--        fill): the shield's inner end, only while it reaches current health.
--  The origin-edge placement and a vertical fill draw nothing.
--  Cost: off builds nothing and the absorb painter pays one field test. The
--  host, gate bar, lines and the clamp calculator are built on first enable.
--  On, the seam line self-gates off the secret absorb through its gate bar,
--  and the overshield boolean (the calculator's Missing Health clamp) flips
--  the lines through their host frames' boolean alpha. Placements that read
--  it join the opt-in "absglow" channel (the unit's health changes), and the
--  flip returns at once while no shield is up. Anchors and art are set by
--  the settings pass and after a retexture, never per paint.
--  On ns: this chunk sits at the Lua 5.1 local ceiling.
-------------------------------------------------------------------------------
mod.UF_GLOW_LINE_ART = CUI.AbsorbGlow.art
mod.UF_GlowLineWidth = CUI.AbsorbGlow.Width

-- Leader Indicator Icon Style art (leaderIndicatorStyle), shared with the
-- options preview.
mod.UF_LEADER_ART = {
    blizzard = {
        leader = "Interface\\GroupFrame\\UI-Group-LeaderIcon",
        assist = "Interface\\GroupFrame\\UI-Group-AssistantIcon",
    },
    pixels = {
        leader = "Interface\\AddOns\\CludesUI\\media\\icons\\roles\\pixels-leader.tga",
        assist = "Interface\\AddOns\\CludesUI\\media\\icons\\roles\\pixels-assist.tga",
    },
}
-- Elite/Rare Indicator Pixels Dragon art (eliteIndicatorStyle "pixelsDragon"),
-- keyed by classification plus "player" for player targets. The art wraps a
-- circle 120 texels across on its 512 canvas, so the texture spans the
-- portrait's size times 512/120, centred on it.
mod.UF_ELITE_DRAGON_ART = {
    worldboss = "Interface\\AddOns\\CludesUI\\media\\portraits\\pixels_dragon_boss.tga",
    elite = "Interface\\AddOns\\CludesUI\\media\\portraits\\pixels_dragon_elite.tga",
    rareelite = "Interface\\AddOns\\CludesUI\\media\\portraits\\pixels_dragon_rare.tga",
    rare = "Interface\\AddOns\\CludesUI\\media\\portraits\\pixels_dragon_rare.tga",
    player = "Interface\\AddOns\\CludesUI\\media\\portraits\\pixels_dragon_player.tga",
}
mod.UF_ELITE_DRAGON_SCALE = 512 / 120

mod.UF_BuildAbsorbGlow = CUI.AbsorbGlow.Build
mod.UF_AbsorbGlowAnchor = CUI.AbsorbGlow.Anchor
mod.UF_AbsorbGlowFlip = CUI.AbsorbGlow.Flip
mod.UF_PaintAbsorbGlow = CUI.AbsorbGlow.Paint

-- The absglow channel's painter: the flip alone, and only while a shield is
-- up (without one there is nothing to flip; the absorb paint that cleared
-- it already did).
mod.Engine.SetPainter("absglow", function(widget, unitToken)
    local healthEnd = widget.HealthPrediction
    local absorbBar = healthEnd and healthEnd.damageAbsorb
    if absorbBar and absorbBar._glowOn and widget._absActive then
        mod.UF_AbsorbGlowFlip(absorbBar, unitToken)
    end
end)

-- Settings pass for one frame (spawn and every reload), after the absorb
-- re-anchor pass so the fill direction and axis are current. Resolves on/off
-- and the placement, builds on first enable, and re-seats art and anchors
-- only when one of their inputs (placement, overshield anchor, fill
-- direction, art) changed; a change repaints the frame at once.
function mod.UF_AbsorbGlowApply(widget, unitToken)
    local healthEnd = widget.HealthPrediction
    local absorbBar = healthEnd and healthEnd.damageAbsorb
    if not (absorbBar and absorbBar._forward) then return end
    local s
    if unitToken and unitToken:match("^boss") then
        if not (saved.profile.boss and saved.profile.boss.showAbsorbs == false) then
            s = saved.profile.target
        end
    else
        s = GetSettingsForUnit(unitToken)
    end
    local enabled = s
        and s.absorbGlowLine == true
        and (s.showPlayerAbsorb or "none") ~= "none"
        and not absorbBar._isVert
    local rev = absorbBar._isReversed and true or false
    local ge, anc
    if enabled then
        local em = s.absorbEdgeMode or "overlay"
        if em == "overlay" then
            local osm = s.overshieldMode
            if osm == nil then osm = (s.showOvershield == false) and "never" or "always" end
            ge = (osm == "fromleft") and 2 or 1
            anc = (osm == "never") and 0 or ge
        elseif em == "overlayReverse" or em == "overlayReverseFull" then
            ge, anc = 3, 0
        elseif em == (rev and "left" or "right") then
            ge, anc = 5, 0
        else
            enabled = false
        end
    end
    if not enabled then
        if absorbBar._glowOn then
            absorbBar._glowOn = false
            absorbBar._glow.host:Hide()
            mod.Engine.SetChannelOn(widget, "absglow", false)
        end
        return
    end
    local g = absorbBar._glow or mod.UF_BuildAbsorbGlow(absorbBar)
    local art = mod.UF_GLOW_LINE_ART[s.absorbGlowLineTexture] or mod.UF_GLOW_LINE_ART.blizzard
    local changed = not absorbBar._glowOn
    if g.ge ~= ge or g.anc ~= anc or g.rev ~= rev then
        g.ge, g.anc, g.rev = ge, anc, rev
        mod.UF_AbsorbGlowAnchor(absorbBar)
        if ge == 3 then g.edgeHost:SetAlpha(1) end
        if ge <= 2 then
            g.bfHost:Show()
        else
            g.bfHost:Hide()
        end
        changed = true
    end
    if g.art ~= art then
        g.art = art
        g.edge:SetTexture(art[1])
        g.edge:SetBlendMode(art[2])
        g.bf:SetTexture(art[1])
        g.bf:SetBlendMode(art[2])
        g.szH = nil
        changed = true
    end
    if not changed then return end
    absorbBar._glowOn = true
    g.host:Show()
    mod.Engine.SetChannelOn(widget, "absglow", ge ~= 3 and g.calc ~= nil)
    if widget:IsShown() and widget._cuiUnit and healthEnd.Override then
        healthEnd.Override(widget, "ForceUpdate", widget._cuiUnit)
    end
end

-- Absorb / Heal Absorb strip-bar position resolvers + layout (mirrors Raid
-- Frames). On ns so the options-panel preview can reuse the layout.
mod.UF_GetAbsorbBarPos = function(cfg) return (cfg and cfg.absorbBarPosition) or "none" end
mod.UF_GetHealAbsorbBarPos = function(cfg) return (cfg and cfg.healAbsorbBarPosition) or "none" end

-- Anchor/orient a strip bar (Absorb Bar or Heal Absorb Bar). "above*" sit on top
-- of the health bar; "top*"/"bottom*" sit inside at the matching edge, drawn just
-- above the absorb texture; "aboveAbsorb"/"belowAbsorb" (heal bar only) sit flush
-- against the Absorb Bar, derived from its POSITION (not its live visibility, so
-- they never shift). "*Right" fills from the right edge. `absorbLevel` is the
-- absorb-overlay frame level (inside strips render at +1).
mod.UF_ApplyStripBarLayout = function(
    stripeBar,
    health,
    position,
    height,
    absorbLevel,
    absorbPlace,
    absorbHeight
)
    if not stripeBar or not health then return end
    stripeBar:ClearAllPoints()
    stripeBar:SetHeight(Pix.Scale(height or 4))
    local insideLevel = (absorbLevel or (health:GetFrameLevel() + 1)) + 1
    if position == "aboveAbsorb" then
        absorbPlace = absorbPlace or "none"
        local leftPoint, rightPoint, yOff = "TOPLEFT", "TOPRIGHT", 0
        if absorbPlace == "aboveRight" or absorbPlace == "aboveLeft" then
            yOff = Pix.Scale(absorbHeight or 4)
        elseif absorbPlace == "bottomRight" or absorbPlace == "bottomLeft" then
            leftPoint, rightPoint = "BOTTOMLEFT", "BOTTOMRIGHT"
            yOff = Pix.Scale(absorbHeight or 4)
        end
        stripeBar:SetReverseFill(
            absorbPlace ~= "aboveLeft" and absorbPlace ~= "topLeft" and absorbPlace ~= "bottomLeft"
        )
        stripeBar:SetPoint("BOTTOMLEFT", health, leftPoint, 0, yOff)
        stripeBar:SetPoint("BOTTOMRIGHT", health, rightPoint, 0, yOff)
        stripeBar:SetFrameLevel(insideLevel)
    elseif position == "belowAbsorb" then
        absorbPlace = absorbPlace or "none"
        if absorbPlace == "bottomRight" or absorbPlace == "bottomLeft" then
            stripeBar:SetReverseFill(absorbPlace == "bottomRight")
            stripeBar:SetPoint("TOPLEFT", health, "BOTTOMLEFT", 0, 0)
            stripeBar:SetPoint("TOPRIGHT", health, "BOTTOMRIGHT", 0, 0)
            stripeBar:SetFrameLevel(insideLevel)
            return
        end
        local yOff = 0
        if absorbPlace == "topRight" or absorbPlace == "topLeft" then yOff = -Pix.Scale(absorbHeight or 4) end
        stripeBar:SetReverseFill(absorbPlace ~= "aboveLeft" and absorbPlace ~= "topLeft")
        stripeBar:SetPoint("TOPLEFT", health, "TOPLEFT", 0, yOff)
        stripeBar:SetPoint("TOPRIGHT", health, "TOPRIGHT", 0, yOff)
        stripeBar:SetFrameLevel(insideLevel)
    elseif position == "topRight" or position == "topLeft" then
        stripeBar:SetReverseFill(position == "topRight")
        stripeBar:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
        stripeBar:SetPoint("TOPRIGHT", health, "TOPRIGHT", 0, 0)
        stripeBar:SetFrameLevel(insideLevel)
    elseif position == "bottomRight" or position == "bottomLeft" then
        stripeBar:SetReverseFill(position == "bottomRight")
        stripeBar:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", 0, 0)
        stripeBar:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
        stripeBar:SetFrameLevel(insideLevel)
    else
        stripeBar:SetReverseFill(position == "aboveRight")
        stripeBar:SetPoint("BOTTOMLEFT", health, "TOPLEFT", 0, 0)
        stripeBar:SetPoint("BOTTOMRIGHT", health, "TOPRIGHT", 0, 0)
        stripeBar:SetFrameLevel(health:GetFrameLevel() + 3)
    end
end

-- Armed-frames absorb belt (mirror of the Raid Frames one): covers the ONE
-- absorb transition with no event at all -- an aura-granted shield expiring
-- on its TIMER on an unhit, topped unit (VDH Infernal Strike field class).
-- One shared 0.5s ticker exists only while some hosted frame is armed; each
-- sweep repaints only stale-painted armed frames and cancels itself when the
-- set empties. Zero event registrations, zero cost with no shields up.
do
    local armed = {}
    local belt
    function mod.UF_AbArm(widget)
        widget._absActive = true
        armed[widget] = true
        if not belt and C_Timer then
            belt = C_Timer.NewTicker(0.5, function()
                local nowTime = GetTime()
                local any = false
                for frame in pairs(armed) do
                    any = true
                    if (nowTime - (frame._absPaintAt or 0)) > 0.45 then
                        local health = frame.HealthPrediction
                        local shade = health and health.Override
                        if shade then shade(frame, "CUI_AbsorbBelt", frame._cuiUnit) end
                    end
                end
                if not any then
                    belt:Cancel()
                    belt = nil
                end
            end)
        end
    end
    function mod.UF_AbDisarm(widget)
        -- Armed -> clear is the moment a shield ended; if it ended with no
        -- absorb event (the timer-expiry class this belt exists for), any
        -- long-form Absorb text zone is showing the dead amount. One text
        -- recompose here keeps those zones honest WITHOUT the text channel
        -- riding UNIT_AURA. No-op frames early-return on their zone list.
        if widget._absActive and mod.UF_PaintText then
            mod.UF_PaintText(widget, widget._cuiUnit, "CUI_AbsorbEnd")
        end
        widget._absActive = false
        armed[widget] = nil
    end
end

local function CreateAbsorbBar(widget, unitToken, prefs)
    if not widget.Health then return end

    local healthBar = widget.Health

    -- Mask texture: constrains absorb rendering to exact health bar bounds at the
    -- GPU level, preventing the subpixel bleed where absorb textures extend 1px
    -- outside the health bar at some frame positions.
    local absorbMask = healthBar:CreateMaskTexture()
    absorbMask:SetAllPoints(healthBar)
    absorbMask:SetTexture("Interface\\Buttons\\WHITE8X8")

    -- Reverse fill: when health fills right-to-left, mirror all absorb anchors.
    local reversed = prefs.healthReverseFill and true or false

    -- Current HP clip: bounds the backfill bar to the filled health area.
    local nowClip = CreateFrame("Frame", nil, healthBar)
    if reversed then
        nowClip:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
        nowClip:SetPoint("BOTTOMLEFT", healthBar:GetStatusBarTexture(), "BOTTOMLEFT", 0, 0)
    else
        nowClip:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
        nowClip:SetPoint("BOTTOMRIGHT", healthBar:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
    end
    nowClip:SetClipsChildren(true)

    -- Missing HP clip: bounds the forward bar to the empty health area.
    local missClip = CreateFrame("Frame", nil, healthBar)
    if reversed then
        missClip:SetPoint("TOPRIGHT", healthBar:GetStatusBarTexture(), "TOPLEFT", 1, 0)
        missClip:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 0, 0)
    else
        missClip:SetPoint("TOPLEFT", healthBar:GetStatusBarTexture(), "TOPRIGHT", -1, 0)
        missClip:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
    end
    missClip:SetClipsChildren(true)

    -- Backfill bar (overflow): grows into filled health from the edge.
    local backFill = CreateFrame("StatusBar", nil, nowClip)
    backFill:SetStatusBarTexture(ABSORB_SHIELD_TEX)
    local bfFill = backFill:GetStatusBarTexture()
    if bfFill then
        bfFill:SetDrawLayer("ARTWORK", 1)
        bfFill:AddMaskTexture(absorbMask)
    end
    backFill:SetStatusBarColor(1, 1, 1, 0.8)
    backFill:SetReverseFill(not reversed)
    if reversed then
        backFill:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
        backFill:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 0, 0)
    else
        backFill:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
        backFill:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
    end
    backFill:SetWidth(healthBar:GetWidth())
    backFill:SetHeight(healthBar:GetHeight())
    backFill:SetFrameLevel(healthBar:GetFrameLevel() + 1)
    backFill:Hide()

    -- Forward bar (primary): grows into missing health from the HP edge.
    local frontBar = CreateFrame("StatusBar", nil, missClip)
    frontBar:SetStatusBarTexture(ABSORB_SHIELD_TEX)
    local fwFill = frontBar:GetStatusBarTexture()
    if fwFill then
        fwFill:SetDrawLayer("ARTWORK", 1)
        fwFill:AddMaskTexture(absorbMask)
    end
    frontBar:SetStatusBarColor(1, 1, 1, 0.8)
    frontBar:SetReverseFill(reversed)
    if reversed then
        frontBar:SetPoint("TOPRIGHT", healthBar:GetStatusBarTexture(), "TOPLEFT", 0, 0)
        frontBar:SetPoint("BOTTOMRIGHT", healthBar:GetStatusBarTexture(), "BOTTOMLEFT", 0, 0)
    else
        frontBar:SetPoint("TOPLEFT", healthBar:GetStatusBarTexture(), "TOPRIGHT", 0, 0)
        frontBar:SetPoint("BOTTOMLEFT", healthBar:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
    end
    frontBar:SetWidth(healthBar:GetWidth())
    frontBar:SetHeight(healthBar:GetHeight())
    frontBar:SetFrameLevel(healthBar:GetFrameLevel() + 1)
    frontBar:Hide()

    -- Heal absorb bar: overlays filled-health in red, reverse-filling from the health
    -- texture edge inward. Has its OWN clip frame (not the shield's curClip) so
    -- placement is independent: overlay clips to filled health, right/left span the
    -- FULL bar. Bounds set per healAbsorbEdgeMode in UpdateAbsorbBarReverseFill.
    local healCut = CreateFrame("Frame", nil, healthBar)
    if reversed then
        healCut:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
        healCut:SetPoint("BOTTOMLEFT", healthBar:GetStatusBarTexture(), "BOTTOMLEFT", 0, 0)
    else
        healCut:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
        healCut:SetPoint("BOTTOMRIGHT", healthBar:GetStatusBarTexture(), "BOTTOMRIGHT", 0, 0)
    end
    healCut:SetClipsChildren(true)
    local healAbsorbFill = CreateFrame("StatusBar", nil, healCut)
    healAbsorbFill:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    healAbsorbFill._absorbMask = absorbMask
    local haFill = healAbsorbFill:GetStatusBarTexture()
    if haFill then
        haFill:SetDrawLayer("ARTWORK", 2)
        haFill:AddMaskTexture(absorbMask)
    end
    healAbsorbFill:SetStatusBarColor(0.8, 0.15, 0.15, 0.65)
    healAbsorbFill:SetReverseFill(not reversed)
    if reversed then
        healAbsorbFill:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 0)
        healAbsorbFill:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMLEFT", 0, 0)
    else
        healAbsorbFill:SetPoint("TOPRIGHT", healthBar, "TOPRIGHT", 0, 0)
        healAbsorbFill:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
    end
    healAbsorbFill:SetWidth(healthBar:GetWidth())
    healAbsorbFill:SetHeight(healthBar:GetHeight())
    healAbsorbFill:SetFrameLevel(healthBar:GetFrameLevel() + 1)
    healAbsorbFill:Hide()

    -- Black backing behind the heal-absorb texture (opacity via healAbsorbBgOpacity),
    -- drawn UNDER the fill (ARTWORK sublevel 1 < fill's 2), masked and anchored to the
    -- fill texture by the first paint, so it tracks the secret heal-absorb amount.
    local haBg = healAbsorbFill:CreateTexture(nil, "ARTWORK", nil, 1)
    haBg:SetColorTexture(0, 0, 0, 0.15)
    if absorbMask then haBg:AddMaskTexture(absorbMask) end
    haBg:Hide()
    healAbsorbFill._bg = haBg

    -- Absorb Bar + Heal Absorb Bar: separate strips (mirrors Raid Frames) at a
    -- configurable position, parented to the frame so "above" positions can sit
    -- outside the health bar. Created hidden; the Override drives them.
    local absorbTopBar = CreateFrame("StatusBar", nil, widget)
    absorbTopBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    absorbTopBar:SetStatusBarColor(1, 1, 1, 1)
    absorbTopBar:SetReverseFill(true)
    absorbTopBar:SetPoint("BOTTOMLEFT", healthBar, "TOPLEFT", 0, 0)
    absorbTopBar:SetPoint("BOTTOMRIGHT", healthBar, "TOPRIGHT", 0, 0)
    absorbTopBar:SetHeight(4)
    absorbTopBar:SetFrameLevel(healthBar:GetFrameLevel() + 3)
    absorbTopBar:Hide()

    local healAbsorbTopBar = CreateFrame("StatusBar", nil, widget)
    healAbsorbTopBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    healAbsorbTopBar:SetStatusBarColor(200 / 255, 29 / 255, 29 / 255, 1)
    healAbsorbTopBar:SetReverseFill(true)
    healAbsorbTopBar:SetPoint("BOTTOMLEFT", healthBar, "TOPLEFT", 0, 0)
    healAbsorbTopBar:SetPoint("BOTTOMRIGHT", healthBar, "TOPRIGHT", 0, 0)
    healAbsorbTopBar:SetHeight(4)
    healAbsorbTopBar:SetFrameLevel(healthBar:GetFrameLevel() + 3)
    healAbsorbTopBar:Hide()

    -- Attach extras to the backfill (main) bar so anything referencing
    -- HealthPrediction.damageAbsorb can hide/show both segments together.
    backFill._forward = frontBar
    backFill._healAbsorb = healAbsorbFill
    backFill._topBar = absorbTopBar
    backFill._healTopBar = healAbsorbTopBar
    backFill._hpBar = healthBar
    backFill._curClip = nowClip
    backFill._healClip = healCut
    backFill._missClip = missClip
    backFill._absorbMask = absorbMask
    backFill._isReversed = reversed

    -- Raise the power bar above the absorb overlay.
    local power = widget and widget.Power
    if power then power:SetFrameLevel(math.max(power:GetFrameLevel(), healthBar:GetFrameLevel() + 2)) end

    backFill:HookScript("OnHide", function()
        frontBar:Hide()
        healAbsorbFill:Hide()
    end)

    -- Named local so profilers attribute this hot painter (it traced as the
    -- "(anonymous) :5228" row); assigned into HealthPrediction below.
    local UF_AbsorbOverride
    UF_AbsorbOverride = function(self, evt, updUnit)
        if self._cuiUnit ~= updUnit then return end

        -- Arm on the dedicated absorb events (plainly observable even
        -- while values are secret). Value-only health chatter is not
        -- delivered to this channel at all (engine list); max changes
        -- repaint ONLY while a shield/heal-absorb is known active --
        -- with no absorb, a range change moves nothing visible.
        -- Repoints, ForceUpdate and the belt always paint and re-derive
        -- the flag below. Mirror of the RF gate.
        if evt == "UNIT_ABSORB_AMOUNT_CHANGED" or evt == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" then
            mod.UF_AbArm(self)
        elseif evt == "UNIT_MAXHEALTH" and not self._absActive then
            return
        end

        -- Drive the "Absorb Short" health-text gate(s): feed the raw absorb so the
        -- clip reveals/collapses, AND refresh the text in LOCKSTEP so it never
        -- flashes a stale "0" (oUF tags update on a throttled cycle, lagging the
        -- synchronous clip reveal by a frame). Runs before the bar-style early
        -- return so it works with the absorb BAR disabled. The gate must move on
        -- EVERY update, not only absorb events: volatile units (target/focus/boss/
        -- pet) get re-pointed with no absorb event at all (target switch, OnShow,
        -- ForceUpdate), and a dying unit drops its shield without one either -- the
        -- TAG re-evaluates on those paths and lands on "0", so a gate still held
        -- open by the PREVIOUS unit's shield would leave a stuck "0". Max-health
        -- events skip the text refresh (absorb text only changes on an absorb event,
        -- which does its own lockstep SetText). Secret-safe: absorb only reaches SetValue
        -- and AbbreviateNumbers, never a zero comparison. Each gate feeds its own
        -- source: shield gates use total absorbs, heal gates (g._cuiHealGate) total
        -- heal absorbs, fetched lazily once.
        local shieldAmt, healAmt
        if self._absGate then
            local syncText = (evt ~= "UNIT_MAXHEALTH")
            for zone, g in pairs(self._absGate) do
                if g:IsShown() then
                    local amt
                    if g._cuiHealGate then
                        if not healAmt then
                            healAmt = (UnitGetTotalHealAbsorbs and UnitGetTotalHealAbsorbs(updUnit)) or 0
                        end
                        amt = healAmt
                    else
                        if not shieldAmt then
                            shieldAmt = (UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(updUnit)) or 0
                        end
                        amt = shieldAmt
                    end
                    g:SetValue(amt)
                    if syncText then
                        local field = GATE_ZONE_TEXT[zone]
                        local fontStr = field and self[field]
                        if fontStr then
                            local conf = _G._CUI_AbbrevDecimalCfg
                            fontStr:SetText(
                                conf and AbbreviateNumbers(amt, conf) or mod.AbbreviateValue(amt, "absorb")
                            )
                        end
                    end
                end
            end
        end

        local element = self.HealthPrediction
        local absorbBar = element.damageAbsorb
        if not absorbBar then return end
        local fillW = absorbBar._forward
        local health = absorbBar._hpBar
        if not health then return end

        -- Heal absorb renders independently of shield absorb: shield "none" hides
        -- only the shield segments, and the whole update is skipped only when BOTH
        -- are off, so unit events can't re-Show() bars ReloadFrames hid. (Heal
        -- Absorb Style defaults to "clean", so it shows even with shield "none".)
        local cfg = GetSettingsForUnit(updUnit)
        -- Boss frames have no absorb settings of their own: render with the TARGET
        -- frame's styling (donor convention), behind "Show on Boss Frames" in the
        -- absorb cog (nil = enabled).
        local bossAbsorbOff
        if updUnit and IS_BOSS_UNIT[updUnit] then
            bossAbsorbOff = saved.profile.boss and saved.profile.boss.showAbsorbs == false
            cfg = saved.profile.target or cfg
        end
        local healAbsorb = absorbBar._healAbsorb
        local overBar = absorbBar._topBar
        local healOverBar = absorbBar._healTopBar
        local barPos = mod.UF_GetAbsorbBarPos(cfg)
        local barOn = overBar and barPos ~= "none"
        local healBarPos = mod.UF_GetHealAbsorbBarPos(cfg)
        local healBarOn = healOverBar and healBarPos ~= "none"
        local shieldOff = cfg and (not cfg.showPlayerAbsorb or cfg.showPlayerAbsorb == "none")
        local healOff = (((cfg and cfg.healAbsorbStyle) or "clean") == "none")
        if bossAbsorbOff or (shieldOff and healOff and not barOn and not healBarOn) then
            absorbBar:Hide()
            if fillW then fillW:Hide() end
            if healAbsorb then healAbsorb:Hide() end
            if overBar then overBar:Hide() end
            if healOverBar then healOverBar:Hide() end
            -- Nothing draws a shield here, but the arm/disarm derivation still
            -- runs (as below): an absorb event armed this frame above, and a
            -- frame that never disarms keeps the 0.5s belt repainting it for the
            -- session, its long-form Absorb text never getting the expiry recompose.
            self._absPaintAt = GetTime()
            local a = shieldAmt or (UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(updUnit)) or 0
            local hgt = healAmt or (UnitGetTotalHealAbsorbs and UnitGetTotalHealAbsorbs(updUnit)) or 0
            if
                (issecretvalue and (issecretvalue(a) or issecretvalue(hgt)))
                or (a or 0) > 0
                or (hgt or 0) > 0
            then
                if not self._absActive then mod.UF_AbArm(self) end
            else
                mod.UF_AbDisarm(self)
            end
            return
        end

        -- Direct pair, matching PaintHealth's scale: the health bar runs raw
        -- UnitHealthMax, and every absorb sink below is a StatusBar with a
        -- (0, maxHealth) range that clamps oversized shields visually, so a
        -- detailed-prediction calculator adds fetches without changing a pixel.
        -- The gate block above may have fetched the shield total already.
        local healthMax = UnitHealthMax(updUnit) or 0
        local absorbAmt = shieldAmt or (UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(updUnit)) or 0

        -- Lean-flag derivation + belt stamp (mirror of Raid Frames): a
        -- fresh PLAIN all-zero read disarms the head gate; secret reads
        -- keep it armed (fail-open to today's always-paint in combat).
        self._absPaintAt = GetTime()
        local haAmtD = healAmt or (UnitGetTotalHealAbsorbs and UnitGetTotalHealAbsorbs(updUnit)) or 0
        local isSecD = issecretvalue
        if
            (isSecD and (isSecD(absorbAmt) or isSecD(haAmtD)))
            or (absorbAmt or 0) > 0
            or (haAmtD or 0) > 0
        then
            if not self._absActive then mod.UF_AbArm(self) end
        else
            mod.UF_AbDisarm(self)
        end

        local hpW, hpH = health:GetWidth(), health:GetHeight()
        -- Identical-state short-circuit (RF's memo, ported): chatter
        -- events with unchanged values skip the whole paint below.
        -- Identity/settings paints bypass the skip; any secret input
        -- fails open to painting and poisons the memo for the next plain
        -- pass (exactly the RF contract). The 0.5s belt honors the memo
        -- like RF's does: it exists for the no-event timer expiry, and
        -- that edge reads a CHANGED amount (memo miss) -- the arm/disarm
        -- derivation and the paint stamp above already ran, so a belt
        -- pass over unchanged plain values has nothing left to move.
        if isSecD and (isSecD(absorbAmt) or isSecD(healthMax) or isSecD(haAmtD)) then
            absorbBar._mAbs = nil
        elseif
            evt ~= "ForceUpdate"
            and evt ~= "Resettle"
            and absorbBar._mAbs == absorbAmt
            and absorbBar._mHeal == haAmtD
            and absorbBar._mMax == healthMax
            and absorbBar._mW == hpW
            and absorbBar._mH == hpH
        then
            return
        else
            absorbBar._mAbs, absorbBar._mHeal, absorbBar._mMax = absorbAmt, haAmtD, healthMax
            absorbBar._mW, absorbBar._mH = hpW, hpH
        end
        -- Bars track the health-bar size; size-gated (sizes never secret).
        if absorbBar._szW ~= hpW or absorbBar._szH ~= hpH then
            absorbBar._szW = hpW
            absorbBar._szH = hpH
            absorbBar:SetWidth(hpW)
            absorbBar:SetHeight(hpH)
            if fillW then
                fillW:SetWidth(hpW)
                fillW:SetHeight(hpH)
            end
        end

        -- Strip bars (mirrors Raid Frames): independent of the overlay styles.
        if overBar then
            if barOn then
                local bc = (cfg and cfg.absorbBarColor) or COLOR_WHITE
                local bh = (cfg and cfg.absorbBarHeight) or 4
                -- Re-layout only on position/height change (no SetPoint churn).
                if overBar._lpPos ~= barPos or overBar._lpH ~= bh then
                    overBar._lpPos = barPos
                    overBar._lpH = bh
                    mod.UF_ApplyStripBarLayout(overBar, health, barPos, bh, absorbBar:GetFrameLevel())
                end
                overBar:SetStatusBarColor(bc.r, bc.g, bc.b, bc.a or 1)
                overBar:SetMinMaxValues(0, healthMax)
                overBar:SetValue(absorbAmt)
                overBar:Show()
            else
                overBar:Hide()
            end
        end
        if healOverBar then
            if healBarOn then
                local hbc = (cfg and cfg.healAbsorbBarColor) or DEF_HEAL_ABSORB_BAR_COLOR
                local hbh = (cfg and cfg.healAbsorbBarHeight) or 4
                local abh = (cfg and cfg.absorbBarHeight) or 4
                -- Re-layout only when its or the Absorb Bar's position/height changes.
                if
                    healOverBar._lpPos ~= healBarPos
                    or healOverBar._lpH ~= hbh
                    or healOverBar._lpAP ~= barPos
                    or healOverBar._lpAH ~= abh
                then
                    healOverBar._lpPos = healBarPos
                    healOverBar._lpH = hbh
                    healOverBar._lpAP = barPos
                    healOverBar._lpAH = abh
                    mod.UF_ApplyStripBarLayout(
                        healOverBar,
                        health,
                        healBarPos,
                        hbh,
                        absorbBar:GetFrameLevel(),
                        barPos,
                        abh
                    )
                end
                healOverBar:SetStatusBarColor(hbc.r, hbc.g, hbc.b, hbc.a or 1)
                healOverBar:SetMinMaxValues(0, healthMax)
                healOverBar:SetValue(haAmtD)
                healOverBar:Show()
            else
                healOverBar:Hide()
            end
        end

        -- Re-anchor when placement settings change. Key starts nil, so this also
        -- applies the saved placement on the first update. Fill AXIS belongs in the
        -- key too: the settings-apply path already re-anchors on a Vertical Fill
        -- toggle, but this keeps it self-healing if the axis changes another way.
        local absorbStyle = (cfg and cfg.absorbEdgeMode) or "overlay"
        -- Overshield mode (three-way; nil falls back to the legacy
        -- showOvershield boolean). Joins the edge key: "fromleft"
        -- re-anchors the backfill in UpdateAbsorbBarReverseFill.
        local osMode = cfg and cfg.overshieldMode
        if osMode == nil then osMode = (cfg and cfg.showOvershield == false) and "never" or "always" end
        -- Component compares instead of a concatenated key: same change
        -- detection, zero string allocation on the per-event path. Fields
        -- start nil, so the first update always anchors.
        local healEdgeMode = (cfg and cfg.healAbsorbEdgeMode) or "overlay"
        local vertFill = (cfg and cfg.healthVerticalFill) and true or false
        if
            absorbBar._ekAbs ~= absorbStyle
            or absorbBar._ekHeal ~= healEdgeMode
            or absorbBar._ekVert ~= vertFill
            or absorbBar._ekOs ~= osMode
        then
            absorbBar._ekAbs, absorbBar._ekHeal = absorbStyle, healEdgeMode
            absorbBar._ekVert, absorbBar._ekOs = vertFill, osMode
            UpdateAbsorbBarReverseFill(self, absorbBar._isReversed)
        end

        -- Shield (damage) absorb segments render only when enabled; style
        -- "none" hides them and falls through to the independent heal absorb.
        if shieldOff then
            absorbBar:Hide()
            if fillW then fillW:Hide() end
        else
            -- Re-apply the absorb style only when the setting changes, never on
            -- every health event: SetStatusBarTexture per update flashes the
            -- bar visible even at zero absorb. Opacity/color edits re-apply via
            -- ReloadFrames' direct call.
            local absStyle = cfg and cfg.showPlayerAbsorb
            if absStyle and absStyle ~= "none" and absorbBar._lastAbsStyle ~= absStyle then
                absorbBar._lastAbsStyle = absStyle
                ApplyAbsorbStyle(absorbBar, absStyle, cfg)
            end

            -- Show Overshield (three-way, resolved above as osMode):
            -- "never" (overlay mode only) feeds backfill 0 so only empty
            -- health fills, while the forward bar still caps at the right
            -- edge; "always"/"fromleft" draw the excess (placement decided
            -- by the anchor pass). Right/left edge modes draw the WHOLE
            -- absorb through ab (fw hidden below) and are untouched.
            local abValue = absorbAmt
            if osMode == "never" and absorbStyle == "overlay" then abValue = 0 end

            -- Both bars get the raw absorb value and the normal maxHealth; the clip
            -- frames do "min(absorb,curHealth)" and "max(0,absorb-curHealth)"
            -- visually, so no Lua arithmetic touches the (possibly secret) absorb.
            absorbBar:SetMinMaxValues(0, healthMax)
            absorbBar:SetValue(abValue)
            absorbBar:Show()

            if fillW then
                fillW:SetMinMaxValues(0, healthMax)
                fillW:SetValue(absorbAmt)
                fillW:Show()
                -- Edge modes and Overlay Reverse: the backfill shows the
                -- absorb, so the forward bar is not needed (Overlay Reverse
                -- (Full) draws its excess through it).
                if absorbStyle ~= "overlay" and absorbStyle ~= "overlayReverseFull" then fillW:Hide() end
            end
            -- Blizzard Glow Line (opt-in; see ns.UF_AbsorbGlowApply).
            if absorbBar._glowOn then mod.UF_PaintAbsorbGlow(absorbBar, updUnit, absorbAmt, hpH) end
        end

        -- Heal absorb: overlay eating into filled health. The value can be a secret
        -- number in 12.0+, so never compare it in Lua. Feed it directly to
        -- StatusBar:SetValue and let the bar render zero width when the value is 0.
        if healAbsorb then
            local haStyle = (cfg and cfg.healAbsorbStyle) or "clean"
            if haStyle == "none" then
                healAbsorb:Hide()
            else
                -- Re-style only when one of the style's inputs changes
                -- (component compares: no key string per paint).
                local hc = (cfg and cfg.healAbsorbColor) or DEF_HEAL_ABSORB_COLOR
                local hcR, hcG, hcB = hc.r or 0.8, hc.g or 0.15, hc.b or 0.15
                local haOp = (cfg and cfg.healAbsorbOpacity) or 65
                local healthBg = healAbsorb._bg
                if
                    healAbsorb._hsStyle ~= haStyle
                    or healAbsorb._hsOp ~= haOp
                    or healAbsorb._hsR ~= hcR
                    or healAbsorb._hsG ~= hcG
                    or healAbsorb._hsB ~= hcB
                then
                    healAbsorb._hsStyle, healAbsorb._hsOp = haStyle, haOp
                    healAbsorb._hsR, healAbsorb._hsG, healAbsorb._hsB = hcR, hcG, hcB
                    ApplyHealAbsorbStyle(healAbsorb, haStyle, cfg)
                    -- After the retexture, re-seat the backing's fill anchor.
                    if healthBg then healthBg._fillAnchored = nil end
                end
                -- Sized with the health bar, size-gated like the shield bars.
                if healAbsorb._szW ~= hpW or healAbsorb._szH ~= hpH then
                    healAbsorb._szW = hpW
                    healAbsorb._szH = hpH
                    healAbsorb:SetWidth(hpW)
                    healAbsorb:SetHeight(hpH)
                end
                healAbsorb:SetMinMaxValues(0, healthMax)
                healAbsorb:SetValue(haAmtD)
                healAbsorb:Show()
                -- Black backing under the fill: its opacity is written when it
                -- changes, and it anchors to the fill texture once (that region
                -- follows the fill through every SetValue).
                if healthBg then
                    local bgA = ((cfg and cfg.healAbsorbBgOpacity) or 15) / 100
                    if healthBg._bgA ~= bgA then
                        healthBg._bgA = bgA
                        healthBg:SetColorTexture(0, 0, 0, bgA)
                    end
                    if not healthBg._fillAnchored then
                        healthBg._fillAnchored = true
                        healthBg:SetAllPoints(healAbsorb:GetStatusBarTexture())
                    end
                    healthBg:Show()
                end
            end
        end
    end
    widget.HealthPrediction = {
        damageAbsorb = backFill,
        Override = UF_AbsorbOverride,
    }

    -- The anchors above are the horizontal layout; hand the cluster to the shared
    -- re-anchor pass so a vertical-fill frame starts correct without waiting for
    -- the first settings apply. `settings` is passed through because frame._cuiUnit is
    -- not resolvable this early on every frame.
    UpdateAbsorbBarReverseFill(widget, reversed, prefs)

    return backFill
end

Inner.ApplyAbsorbStyle, Inner.UpdateAbsorbBarReverseFill = ApplyAbsorbStyle, UpdateAbsorbBarReverseFill
Inner.CreateAbsorbBar = CreateAbsorbBar
