if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_ResourceBars_Style.lua
--
--  The bar texture tables and the chrome of the Blizzard Style and Classic
--  WoW UI looks: frames, separators and layers.
--  Reads the earlier Resource Bars files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._internals
-- CludesUIResourceBars.lua or an earlier Resource Bars file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local Pix = CludesUI.PP
local floor, min, max = math.floor, math.min, math.max

local ERB, ResolveBandConfig = Inner.ERB, Inner.ResolveBandConfig
local ResolveThresholdSpecEntry, DEFAULTS = Inner.ResolveThresholdSpecEntry, Inner.DEFAULTS

local health
Inner.healthBarSetters[#Inner.healthBarSetters + 1] = function(val)
    health = val
end
local primaryBar
Inner.primaryBarSetters[#Inner.primaryBarSetters + 1] = function(val)
    primaryBar = val
end
local secondaryFrame
Inner.secondaryFrameSetters[#Inner.secondaryFrameSetters + 1] = function(val)
    secondaryFrame = val
end
local cachedSecondary
Inner.cachedSecondarySetters[#Inner.cachedSecondarySetters + 1] = function(val)
    cachedSecondary = val
end

-------------------------------------------------------------------------------

-- Bar Textures (shared with options)
local CAST_BAR_TEXTURES, CAST_BAR_TEXTURE_NAMES, CAST_BAR_TEXTURE_ORDER = CludesUI.BuildBarTextureTables(true)
-- Cast-bar-only extra entry: Blizzard's own atlas fill, second in the list.
CAST_BAR_TEXTURES["blizzard"] = "ATLAS"
CAST_BAR_TEXTURE_NAMES["blizzard"] = "Blizzard"
table.insert(CAST_BAR_TEXTURE_ORDER, 2, "blizzard")
-- Expose for options
_G._CURB_CastBarTextures = CAST_BAR_TEXTURES
_G._CURB_CastBarTextureOrder = CAST_BAR_TEXTURE_ORDER
_G._CURB_CastBarTextureNames = CAST_BAR_TEXTURE_NAMES

-- Health/Power bar texture tables (shared with options dropdown)
local BAR_TEXTURES, BAR_TEXTURE_NAMES, BAR_TEXTURE_ORDER = CludesUI.BuildBarTextureTables(true)
_G._CURB_BarTextures = BAR_TEXTURES
_G._CURB_BarTextureOrder = BAR_TEXTURE_ORDER
_G._CURB_BarTextureNames = BAR_TEXTURE_NAMES

-- Append SharedMedia statusbar textures to both texture tables via the shared
-- CludesUI helper. Safe to call multiple times; dupes skipped inside it.
local function AppendSharedMediaTextures()
    if not CludesUI.AppendSharedMediaTextures then
        return
    end
    CludesUI.AppendSharedMediaTextures(CAST_BAR_TEXTURE_NAMES, CAST_BAR_TEXTURE_ORDER, nil, CAST_BAR_TEXTURES)
    CludesUI.AppendSharedMediaTextures(BAR_TEXTURE_NAMES, BAR_TEXTURE_ORDER, nil, BAR_TEXTURES)
end

-- Player Cast Bar
local SPARK_TEX = "Interface\\AddOns\\CludesUI\\media\\cast_spark.tga"
mod.SPARK_TEX = SPARK_TEX

-------------------------------------------------------------------------------
--  Blizzard Style cast bar (Global Settings > Style). The stock cast bar's
--  atlases on our own frame: every feature (timer, latency, ticks, pips, kick
--  hints) keeps working; only the art changes. Atlas names are validated once
--  per session (GetAtlasInfo) with a legacy spelling as fallback, so a missing
--  atlas degrades to the CUI look for that piece instead of a blank texture.
--  On ns.
-------------------------------------------------------------------------------
mod.ERB_CAST_BLIZZ = {
    bg = { "ui-castingbar-background", "UI-CastingBar-Background" },
    frame = { "ui-castingbar-frame", "UI-CastingBar-Frame" },
    textbox = { "ui-castingbar-textbox", "UI-CastingBar-TextBox" },
    cast = { "ui-castingbar-filling-standard", "UI-CastingBar-Fill" },
    channel = { "ui-castingbar-filling-channel", "UI-CastingBar-Fill" },
    spark = { "ui-castingbar-pip", "UI-CastingBar-Spark" },
}
mod._erbBlizzAtlasMemo = {}
-- The style the cast bar RENDERS this session: "cui" | "blizzard" |
-- "classic". Read from the profile once (first call with a profile present)
-- and latched for the session: a live profile switch never flips the look
-- under the one-time art setup; the profile system prompts for a reload
-- instead. Both flags set resolves to classic.
function mod.ERB_CastStyle()
    local val = mod._erbCastStyle
    if val == nil then
        local cb = ERB.db and ERB.db.profile and ERB.db.profile.castBar
        if not cb then
            return "cui"
        end
        val = (cb.useClassicStyle and "classic") or (cb.useBlizzardStyle and "blizzard") or "cui"
        mod._erbCastStyle = val
        -- The WoW Forever variant of Blizzard Style, latched with it.
        mod._erbFvCast = val == "blizzard" and CludesUI.IS_FOREVER == true and cb.useForeverStyle == true
    end
    return val
end
-- WoW Forever variant on the cast bar (false off Forever).
function mod.ERB_CastForever()
    if mod._erbCastStyle == nil then
        mod.ERB_CastStyle()
    end
    return mod._erbFvCast == true
end
-- Stock-art mode: true for both stock styles (the geometry, gating and
-- chrome they share: CUI border off, full icon art, art child frame).
function mod.ERB_CastBlizz()
    return mod.ERB_CastStyle() ~= "cui"
end
function mod.ERB_CastClassic()
    return mod.ERB_CastStyle() == "classic"
end
-- The one-time stock-style seed on the cast bar profile `cb`: the "Blizzard"
-- fill (the vanilla cast bar's own texture) as the bar texture, once per
-- profile; the dropdown stays the user's afterwards. Run by the Style page
-- on the switch to either stock style and at enable for a profile that
-- arrived already switched (an import, an older build).
-- The cast bar and bar keys the Style page keeps per style (its SLOT_KEYS).
mod._erbCastSlotKeys = { "texture" }
mod._erbBarsSlotKeys = {
    "general.barTexture",
    "splitTex",
    "health.barTexture",
    "primary.barTexture",
    "general.classicBorderAll",
    "general.classicBorderAllSepSize",
    "general.classicBorderAllSepR",
    "general.classicBorderAllSepG",
    "general.classicBorderAllSepB",
}
-- WoW Forever: the Swing Timer's texture rides the bars' slots.
if CludesUI.IS_FOREVER == true then
    mod._erbBarsSlotKeys[#mod._erbBarsSlotKeys + 1] = "swingTimer.texture"
end
function mod.ERB_SeedStockCast(cb)
    if not cb or cb.stockTextureSeeded then
        return
    end
    cb.stockTextureSeeded = true
    cb.texture = "blizzard"
end
-- Health and power each match the main texture (general.barTexture) or take
-- their own (the Texture cog's Health / Power Texture). An own key counts only
-- while splitTex is on, so a key left from an older split never comes back by
-- itself; the setter keeps splitTex on exactly while one bar has its own.
-- barKey = "health" or "primary"; tex = a texture key, or false to match the
-- main texture. Keys are stored false, not nil: profile sync copies only keys
-- that exist.
function mod.ERB_BarTexture(p, barId)
    return p.splitTex == true and p[barId].barTexture or nil
end
function mod.ERB_SetBarTexture(p, barId, tex)
    if tex and p.splitTex ~= true then
        p.health.barTexture, p.primary.barTexture = false, false
        p.splitTex = true
    end
    p[barId].barTexture = tex or false
    if not (p.health.barTexture or p.primary.barTexture) then
        p.splitTex = false
    end
end
-- Classic WoW UI on the health, power and class resource bars, once per
-- profile (the controls stay the user's afterwards): Border Around All on
-- when the shown bars already sit as one anchored stack, and "Plating" as
-- the bar texture (on the health and power keys too where a bar has its own
-- texture, and on WoW Forever's Swing Timer, under a stamp of its own). Run by
-- the Style page on the switch and at enable for a profile that arrives
-- already switched.
function mod.ERB_SeedStockBars(p, styleKey)
    local g = p and p.general
    if not g or styleKey ~= "classic" then
        return
    end
    if not g.borderAllSeeded then
        g.borderAllSeeded = true
        if mod.ERB_BarsAnchoredTight(p) then
            g.classicBorderAll = true
            -- One classic frame, one size: the lead bar's Border Size for all
            -- three, as the options toggle does.
            local s = mod.ERB_GroupLeadCfg(p).stockBorderScale
            p.health.stockBorderScale, p.primary.stockBorderScale, p.secondary.stockBorderScale = s, s, s
        end
    end
    local st = CludesUI.IS_FOREVER == true and p.swingTimer
    if st and not st.classicTextureSeeded then
        st.classicTextureSeeded = true
        st.texture = "plating"
    end
    if g.classicTextureSeeded then
        return
    end
    g.classicTextureSeeded = true
    g.barTexture = "plating"
    if mod.ERB_BarTexture(p, "health") then
        p.health.barTexture = "plating"
    end
    if mod.ERB_BarTexture(p, "primary") then
        p.primary.barTexture = "plating"
    end
end
-- The style the health, power and class resource bars render this session,
-- latched like the cast bar's. Blizzard Style: the personal resource
-- display's bar frame (the viewer's shadowed bar background, overhanging the
-- bar) in place of the CUI full-bar border. Classic WoW UI: the vanilla cast
-- bar frame round each bar instead. Fills, pips (with their own borders and
-- spacing), texts and every setting stay CUI under both.
function mod.ERB_BarsStyle()
    local val = mod._erbBarsStyle
    if val == nil then
        local p = ERB.db and ERB.db.profile
        if not p then
            return "cui"
        end
        val = (p.useClassicStyleBars and "classic") or (p.useBlizzardStyleBars and "blizzard") or "cui"
        mod._erbBarsStyle = val
    end
    return val
end
function mod.ERB_BarsBlizz()
    return mod.ERB_BarsStyle() ~= "cui"
end
function mod.ERB_BarsClassic()
    return mod.ERB_BarsStyle() == "classic"
end
mod.ERB_BLIZZ_BAR_BG = "UI-HUD-CoolDownManager-Bar-BG"
mod.ERB_BLIZZ_BAR_FILL = "UI-HUD-CoolDownManager-Bar"
-- Cast bar stock art on WoW Forever: a retail name the client swapped for its
-- own art draws from the retail sheet (CludesUI.StockAtlas) unless the WoW
-- Forever look renders, which keeps the client's frame and text box (its
-- cast bar background takes the retail art). Plain SetAtlas on every other
-- client.
function mod.ERB_StockAtlas(tex, name, ...)
    if mod.ERB_CastForever() then
        return tex:SetAtlas(name, ...)
    end
    return CludesUI.StockAtlas(tex, name, ...)
end
-------------------------------------------------------------------------------
--  Classic WoW UI: the vanilla cast bar frame and spark, plain files. The
--  frame is the shared nine-slice in CludesUI_ClassicArt.lua
--  (CludesUI.ClassicFrame): caps and rims at the sheet's own pixel size
--  round any bar, only the window stretching, so every bar wears the same
--  weight of frame; its opaque gold rim covers the bar's ends and bottom
--  edge, so it goes ABOVE the fill and reaches 14.5 left and right, 12 above
--  and 11 below the bar. Vanilla bars are plain rectangles: no mask, no bevel
--  strips, and the fill stays the user's texture and colours.
-------------------------------------------------------------------------------
mod.ERB_CLASSIC = {
    spark = "Interface\\CastingBar\\UI-CastingBar-Spark",
    barH = 13,
    -- The spark is a 32x32 additive square centred on the fill's leading
    -- edge, 2px above the bar's centre line, scaled with the bar's height.
    sparkSize = 32,
    sparkY = 2,
}
-- A health, power, class resource or cast bar's frame scale under Classic
-- WoW UI: the bar's own Border Size percentage (stockBorderScale, nil = the
-- shared default), which shrinks the whole vanilla frame (caps, rims and
-- their reach) together.
function mod.ERB_ClassicFrameK(conf)
    local CF = CludesUI.ClassicFrame
    if not CF then
        return 1
    end
    return CF.ScaleK(conf and conf.stockBorderScale)
end
-- The rim the vanilla frame draws OUTSIDE a bar's own rect, for size matching
-- (CUI_UnlockMode getMatchPad): extra width, extra height in the bar's units
-- (the frame's reach is fixed at a given scale k, so the bar's size does not
-- enter; a vertical bar turns it with the art).
function mod.ERB_ClassicMatchPad(wid, hgt, vertical, k)
    local CF = CludesUI.ClassicFrame
    if not CF then
        return 0, 0
    end
    return CF.Pad(k or 1, vertical)
end
-- Blizzard Style: the panel's opaque rim outside a health, power or class
-- resource bar, for the same size matching. The rim sits 1 left, 1 right,
-- 2 above (rim and the dark line under it) and 1 below; the soft outer edge
-- and the drop shadow stay out (a shadow is not the frame's edge), so a
-- matched bar's rim lines up with its target on both sides. A vertical bar
-- turns it a quarter turn with the art. Constant (no Border Size under the
-- style); nil when the client has no panel art to draw.
function mod.ERB_BlizzMatchPad(vertical)
    local art = mod._erbBlizzPanelArt
    if art == nil then
        art = (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(mod.ERB_BLIZZ_BAR_BG)) and true
            or false
        mod._erbBlizzPanelArt = art
    end
    if not art then
        return nil
    end
    if vertical then
        return 3, 2
    end
    return 2, 3
end
-- CludesUI look: what a bar's textured border draws OUTSIDE the bar, for
-- the same size matching, from the exact arguments the bar's renderer hands
-- ApplyBorderStyle (`c` = the bar's resolved settings). nil for a solid border
-- (drawn inside the bar) or none. Screen axes: the border does not turn with
-- a vertical bar.
function mod.ERB_EuiBorderPad(c)
    if not c then
        return nil
    end
    local bs = c.borderSize or 0
    local tex = c.borderTexture or "solid"
    return CludesUI.BorderMatchPad(
        bs,
        tex,
        c.borderTextureOffset,
        c.borderTextureOffsetY,
        c.borderTextureShiftX,
        c.borderTextureShiftY,
        "resourcebars",
        bs,
        CludesUI.BorderPx(c.borderSizePx, bs, tex),
        nil,
        c.borderA
    )
end
-- Separator companion art for a bar (`c` = its resolved settings), for the
-- opted-in separator and divider rows. The art comes only from the shared
-- companion registry (CludesUI.GetBorderCompanion): role "sepH" = the
-- horizontal strip (its line in the strip's top texels), "sepV" = the vertical
-- divider (line at its left edge). pick = the row's Separator Art value:
-- "match" / nil = the bar's own border style, else a border key; a style with
-- no companion art (Solid, Glow, Blizzard, SharedMedia...) falls back to the
-- Pixels art. Returns, as plain values (no table):
--   path  the art file
--   f     scale from the art's step-2 geometry to the edge the bar's border
--         draws: edge / 16 while the bar's own style has companion art and its
--         size is above 0 (edge = the exact Border Size x PP.mult, else
--         BORDER_EDGE_MAP[step], as ApplyBorderStyle draws it), else 1
--   size  the art's sepSize (strip thickness at f = 1)
--   exact true while f comes from an exact Border Size: that art is sized in
--         pixels at UIParent scale, so its owner re-places it on a UI scale
--         change through CludesUI.RegisterPxReapply (unregister otherwise)
-- Geometry in the bar's units, each value snapped with PP.SnapForES at the
-- host's effective scale: horizontal strip size x f tall, texcoord flipped
-- (0, 1, 1, 0) so the line sits at its bottom, strip bottom 2 x f below the
-- bar's bottom edge; vertical strip size x f wide, left edge 2 x f before the
-- gap midpoint, full bar height; cast divider size x f wide, leading edge
-- 2 x f over the icon side of the seam. Tint with the bar's border colour and
-- alpha. Anchor to the outer bar frame, never the clipped inner StatusBar.
-- Style/build time only.
function mod.ERB_SeparatorArt(c, pick, role)
    local tex = c and c.borderTexture or "solid"
    local key = (pick and pick ~= "match") and pick or tex
    local filePath = CludesUI.GetBorderCompanion(key, role)
    if not filePath then
        key = "pixels"
        filePath = CludesUI.GetBorderCompanion(key, role)
    end
    local size = CludesUI.GetBorderCompanion(key, "sepSize") or 16
    local bs = c and c.borderSize or 0
    if bs > 0 and CludesUI.GetBorderCompanion(tex, "sepSize") then
        local px = CludesUI.BorderPx(c.borderSizePx, bs, tex)
        if px then
            return filePath, math.max(1, floor(px + 0.5)) * Pix.mult / 16, size, true
        end
        local EM = CludesUI.BORDER_EDGE_MAP
        return filePath, (EM[bs] or EM[1]) / 16, size, false
    end
    return filePath, 1, size, false
end
-- True while a bar's border style is textured (not Solid, not empty): the only
-- state that shows its Border Options cog, so the separator and lift settings
-- in that cog count only then.
function mod.ERB_Textured(c)
    local t = c and c.borderTexture
    return (t and t ~= "" and t ~= "solid") and true or false
end
-- Separator pieces on one of our bars (Bottom Separator on the power, cast and
-- GCD bars; Separators on the class resource bar): a mouse-disabled host frame
-- of ours on the bar, created on first use, holding the bottom-edge line (hOn)
-- and one line per gap between pips or runes (slots / count = the layout
-- ERB.ApplyGapFills receives; isVertical / isReversed = the pip orientation).
-- level = the host's frame level (nil: the caller levels it). Nothing on: the
-- host hides and leaves the UI-scale re-place. Art, size and offsets are
-- ns.ERB_SeparatorArt's, the colour the bar's border colour and alpha. Build
-- paths only: nothing here runs per frame or per power tick.
do
    -- The options page pool's table (CludesUI_PixelPerfect.lua makes it; the
    -- options addon fills it in place), read through this block local and never
    -- through the public slot, so a slot written later cannot reach the live bars.
    local POOL = CludesUI._Pool
    function mod.ERB_Separators(bar, c, hOn, level, slots, total, isVertical, isReversed)
        local host = bar._erbSep
        local gaps = (slots and total and total > 1) and (total - 1) or 0
        if not hOn and gaps == 0 then
            if host and host:IsShown() then
                host:Hide()
                CludesUI.RegisterPxReapply(host, nil)
            end
            return
        end
        if not host then
            -- On an options preview (an options page pool host) the piece is
            -- pooled with the preview; on a live bar this is CreateFrame.
            host = POOL.CreateFrame("Frame", nil, bar)
            host:EnableMouse(false)
            bar._erbSep = host
        end
        mod.ERB_AnchorBorderHost(host, bar)
        if level then
            host:SetFrameLevel(level)
        end
        host._erbC, host._erbHOn = c, hOn and true or false
        if gaps > 0 then
            -- Gap midpoints along the pip layout's own axis (one reused table).
            local mids = host._erbMids
            if not mids then
                mids = {}
                host._erbMids = mids
            end
            for idx = 1, gaps do
                mids[idx] = (slots[idx].x1 + slots[idx + 1].x0) / 2
            end
        end
        host._erbVN, host._erbVert, host._erbRev =
            gaps, isVertical and true or false, isReversed and true or false
        host:Show()
        -- Art sized from an exact Border Size is pixels at UIParent scale: re-placed
        -- (no rebuild) when the pixel grid moves, only while it is.
        CludesUI.RegisterPxReapply(host, mod.ERB_SepPlace(host) and mod.ERB_SepPlace or nil)
    end
end -- POOL block
-- Places a separator host's pieces from its last build; also the UI-scale
-- re-place. Returns true while a shown piece is sized from an exact Border Size.
-- Horizontal line: the strip flipped so its line sits at its bottom, the strip
-- bottom 2 x f below the bar's bottom edge plus the Y Offset. Gap lines: the
-- vertical strip's left edge 2 x f before the gap midpoint, full bar height; a
-- vertical pip layout stacks its pips, so there the horizontal strip runs
-- across the bar with its top edge 2 x f above the midpoint.
function mod.ERB_SepPlace(host)
    local c = host._erbC
    if not c then
        return false
    end
    local es = host:GetEffectiveScale()
    local r, g, b, a = c.borderR or 0, c.borderG or 0, c.borderB or 0, c.borderA or 1
    local exact = false
    local hgt = host._erbH
    if host._erbHOn then
        local filePath, f, size, ex = mod.ERB_SeparatorArt(c, c.edgeSepArt, "sepH")
        if not hgt then
            hgt = host:CreateTexture(nil, "OVERLAY", nil, 7)
            Pix.DisablePixelSnap(hgt)
            host._erbH = hgt
        end
        local posY = Pix.SnapForES((c.edgeSepY or 0) - 2 * f, es)
        local _, _, leftX, right =
            mod.ERB_BorderExtents((not c.borderOnPips or mod.IsBarTypeSecondary()) and c or nil)
        hgt:SetTexture(filePath)
        hgt:SetTexCoord(0, 1, 1, 0)
        hgt:SetVertexColor(r, g, b, a)
        hgt:ClearAllPoints()
        hgt:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", -Pix.SnapForES(leftX, es), posY)
        hgt:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", Pix.SnapForES(right, es), posY)
        hgt:SetHeight(Pix.SnapForES(size * f, es))
        hgt:Show()
        exact = ex and true or false
    elseif hgt then
        hgt:Hide()
    end
    local num, pool = host._erbVN or 0, host._erbV
    if num > 0 then
        local vert, rev, mids = host._erbVert, host._erbRev, host._erbMids
        local filePath, f, size, ex = mod.ERB_SeparatorArt(c, c.edgeSepArt, vert and "sepH" or "sepV")
        if ex then
            exact = true
        end
        local th, lead = Pix.SnapForES(size * f, es), 2 * f
        if not pool then
            pool = {}
            host._erbV = pool
        end
        for idx = 1, num do
            local t = pool[idx]
            if not t then
                t = host:CreateTexture(nil, "OVERLAY", nil, 7)
                Pix.DisablePixelSnap(t)
                pool[idx] = t
            end
            t:SetTexture(filePath)
            t:SetTexCoord(0, 1, 0, 1)
            t:SetVertexColor(r, g, b, a)
            t:ClearAllPoints()
            if vert and rev then
                local off = Pix.SnapForES(mids[idx] + lead, es)
                t:SetPoint("TOPLEFT", host, "BOTTOMLEFT", 0, off)
                t:SetPoint("TOPRIGHT", host, "BOTTOMRIGHT", 0, off)
                t:SetHeight(th)
            elseif vert then
                local off = Pix.SnapForES(lead - mids[idx], es)
                t:SetPoint("TOPLEFT", host, "TOPLEFT", 0, off)
                t:SetPoint("TOPRIGHT", host, "TOPRIGHT", 0, off)
                t:SetHeight(th)
            else
                local off = Pix.SnapForES(mids[idx] - lead, es)
                t:SetPoint("TOPLEFT", host, "TOPLEFT", off, 0)
                t:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", off, 0)
                t:SetWidth(th)
            end
            t:Show()
        end
    end
    if pool then
        for idx = num + 1, #pool do
            pool[idx]:Hide()
        end
    end
    return exact
end
-- Separators on the class resource bar, from BuildBars' pip, rune and bar-type
-- branches: the bottom-edge line for every type, one line per gap for pips and
-- runes (bar types pass no slots). Only while the class style is textured and
-- our own bar draws: no stock style, no Blizzard Class Resource Art (its slot
-- sits at zero alpha and the pips stop painting). Bar Spacing and the gap
-- colour are read through the pip layout, never written. Level: slot + 7,
-- above the pips and the class borders (slot + 5, its strips + 6). With
-- threshold bands it also clears the band stack (secret pip renderer: band k
-- at slot + 1 + k, the reset bar one higher; the Ignore Pain bar's layers up
-- to slot + 2 + bands), capped under the count text (+15). Runes and the two
-- warrior charge powers draw no band frames and keep + 7, under the rune
-- countdown (+10) and the charge engine's count text.
function mod.ERB_ClassSeps(sp, slots, total, isVertical, isReversed)
    local f = secondaryFrame
    if not (sp.edgeSep and mod.ERB_Textured(sp) and not mod.ERB_BarsBlizz() and not mod._erbArtOn) then
        if f._erbSep then
            mod.ERB_Separators(f, sp, false)
        end
        return
    end
    local lvl = 7
    local pw = cachedSecondary.power
    if cachedSecondary.type ~= "runes" and pw ~= "WHIRLWIND_STACKS" and pw ~= "SWEEPING_STRIKES" then
        local bandOn, bands = ResolveBandConfig(sp, ResolveThresholdSpecEntry(sp))
        if bandOn then
            lvl = min(14, max(7, #bands + 3))
        end
    end
    mod.ERB_Separators(
        f,
        sp,
        sp.edgeSepH ~= false,
        f:GetFrameLevel() + lvl,
        (sp.edgeSepV ~= false) and slots or nil,
        total,
        isVertical,
        isReversed
    )
end
-- Bottom Separator on the power bar: only while the bar is enabled, its style
-- is textured and no stock style draws the bars. Levelled by
-- ns.ERB_PowerSepLayer.
function mod.ERB_PowerSep(pp)
    local pb = primaryBar
    if not pb then
        return
    end
    local on = pp.edgeSep and pp.enabled ~= false and mod.ERB_Textured(pp) and not mod.ERB_BarsBlizz()
    if not (on or pb._erbSep) then
        return
    end
    mod.ERB_Separators(pb, pp, on and true or false)
    mod.ERB_PowerSepLayer()
end
-- The power bar's separator host sits in its border's strata, above that
-- border's stack and above the class resource border's (so the line reads
-- through an extended border that wraps the class bar). Compare-only while
-- unchanged; nothing while the host is absent or hidden.
function mod.ERB_PowerSepLayer()
    local pb = primaryBar
    local host = pb and pb._erbSep
    if not (host and host:IsShown()) then
        return
    end
    local bf = pb._border._frame
    local strata = bf:GetFrameStrata()
    local lvl = bf:GetFrameLevel() + 2
    local cbf = secondaryFrame and secondaryFrame._barBorder and secondaryFrame._barBorder._frame
    if cbf and cbf:GetFrameStrata() == strata then
        lvl = max(lvl, cbf:GetFrameLevel() + 2)
    end
    if host:GetFrameStrata() ~= strata then
        host:SetFrameStrata(strata)
    end
    if host:GetFrameLevel() ~= lvl then
        host:SetFrameLevel(lvl)
    end
end
-- Draw Above GCD Bar: while on, with the GCD bar enabled and a textured power
-- style (no stock style), the power border rises over the GCD bar. Cover 18 is
-- the GCD frame's 15 + 3: above its fill and spark, under its own border at
-- 20. The border also moves into the GCD bar's strata when that ranks higher
-- (not with Show Behind, which keeps it under its own fill). The cover is
-- stamped on the bar (_erbGcdCover) so the Ebon Might lift keeps the higher of
-- the two. Called after the power ApplyBorder and at the end of ERB:ApplyAll
-- (its strata pass re-strata's the bar's children). Off puts the border's
-- strata back once; one compare when it was never on.
function mod.ERB_PowerLift(pp)
    local pb = primaryBar
    if not (pb and (pp.borderAboveGCD or pb._erbGcdCover or pb._erbLiftStrata)) then
        return
    end
    local bf = pb._border and pb._border._frame
    if not bf then
        return
    end
    local gb = ERB.db.profile.gcdBar
    local on = (pp.borderAboveGCD and gb and gb.enabled and mod.ERB_Textured(pp) and not mod.ERB_BarsBlizz())
            and true
        or false
    local strata = pb:GetFrameStrata()
    if on and not pp.borderBehind then
        local gs, sequence = gb.frameStrata or "MEDIUM", CludesUI.FRAME_STRATA_ORDER_FULL
        local gr, br = 0, 0
        for idx = 1, #sequence do
            if sequence[idx] == gs then
                gr = idx
            end
            if sequence[idx] == strata then
                br = idx
            end
        end
        if gr > br then
            strata = gs
        end
    end
    if bf:GetFrameStrata() ~= strata then
        bf:SetFrameStrata(strata)
        local edges = Pix.GetBorders(bf)
        if edges then
            edges:SetFrameStrata(strata)
        end
    end
    pb._erbLiftStrata = (strata ~= pb:GetFrameStrata()) or nil
    pb._erbGcdCover = on and 18 or nil
    if on then
        pb:RaiseBorderAbove(18, pp.borderBehind)
    end
end
-- Draw Above Other Bars: the class resource slot 5 levels above the highest
-- health / power / GCD border that shares its strata (the health and power
-- borders as this build levelled them, Draw Above GCD Bar included; the GCD
-- border at its fixed 15 + 5), else 10 as ever. Its border (+5 / -1), pips,
-- separators and count text overlay (+15) follow the slot, and so does the
-- Blizzard Class Resource Art host. Callers run it only while on, or once more
-- to go back to 10 (_erbRaised on our slot).
function mod.ERB_ClassRaise(sp)
    local f = secondaryFrame
    local wanted = 10
    if sp.raiseLevel then
        local strata, topY = f:GetFrameStrata(), 0
        local hb = health and health._border and health._border._frame
        if hb and hb:GetFrameStrata() == strata then
            topY = hb:GetFrameLevel()
        end
        local pbf = primaryBar and primaryBar._border and primaryBar._border._frame
        if pbf and pbf:GetFrameStrata() == strata then
            topY = max(topY, pbf:GetFrameLevel())
        end
        local gb = ERB.db.profile.gcdBar
        if gb and gb.enabled and (gb.frameStrata or "MEDIUM") == strata then
            topY = max(topY, 20)
        end
        wanted = max(10, topY + 5)
    end
    if f:GetFrameLevel() ~= wanted then
        f:SetFrameLevel(wanted)
    end
    f._erbRaised = sp.raiseLevel and true or nil
    if mod.ERB_BlizzArtLevel then
        mod.ERB_BlizzArtLevel(f)
    end
end
-- End of ERB:ApplyAll, after its strata pass: re-asserts the layering that
-- pass (it re-strata's every bar's children) could undo. Inert unless Draw
-- Above GCD Bar, Draw Above Other Bars or a power Bottom Separator is in use.
function mod.ERB_ReassertLayers()
    local p = ERB.db.profile
    if primaryBar then
        mod.ERB_PowerLift(_G._CURB_ResolvePowerCfg(p) or DEFAULTS.profile.primary)
    end
    local sp = _G._CURB_ResolveSecondaryCfg(p) or DEFAULTS.profile.secondary
    if secondaryFrame and (sp.raiseLevel or secondaryFrame._erbRaised) then
        mod.ERB_ClassRaise(sp)
    end
    mod.ERB_PowerSepLayer()
end
-- Background on individual pips: pip and rune resources whose pips carry their
-- own borders. Blizzard Style keeps its masked full-bar backdrop.
function mod.ERB_PipBgOn(sp, isBar)
    return (sp.pipBgOnPips and sp.borderOnPips and not isBar and mod.ERB_BarsStyle() ~= "blizzard") and true
        or false
end
-- Border Art Divider: the cast bar's icon/bar seam divider in the cast border
-- style's own vertical companion art: size x f wide, its leading edge 2 x f
-- over the icon side of the seam (the art mirrored for an icon on the right,
-- so its line stays on the seam), full icon height, the cast border's colour
-- and alpha as vertex colour. Returns true while sized from an exact Border
-- Size. tex = our divider texture, icon = the icon frame.
function mod.ERB_PlaceDividerArt(tex, icon, onRight, c)
    local filePath, f, size, exact = mod.ERB_SeparatorArt(c, "match", "sepV")
    local es = tex:GetParent():GetEffectiveScale()
    local lead = Pix.SnapForES(2 * f, es)
    tex:SetTexture(filePath)
    tex:ClearAllPoints()
    if onRight then
        tex:SetTexCoord(1, 0, 0, 1)
        tex:SetPoint("TOPRIGHT", icon, "TOPLEFT", lead, 0)
        tex:SetPoint("BOTTOMRIGHT", icon, "BOTTOMLEFT", lead, 0)
    else
        tex:SetTexCoord(0, 1, 0, 1)
        tex:SetPoint("TOPLEFT", icon, "TOPRIGHT", -lead, 0)
        tex:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", -lead, 0)
    end
    tex:SetWidth(Pix.SnapForES(size * f, es))
    tex:SetVertexColor(c.borderR or 0, c.borderG or 0, c.borderB or 0, c.borderA or 1)
    return exact and true or false
end
-- Switches a cast icon divider (live bar or preview) to the art while show (the
-- divider is drawn), Border Art Divider is on, no stock style (stock) and the
-- style has vertical companion art; returns true then, and the caller shows it.
-- Otherwise returns false for the caller's solid line, after one reset when
-- leaving the art: texcoords, the vertex colour back to white (SetColorTexture
-- keeps a stale one) and the UI-scale re-place dropped. Two compares while it
-- was never on. The state is kept on our own texture.
function mod.ERB_CastDividerArt(tex, show, icon, onRight, c, stock)
    if show and c.iconDividerArt and not stock and CludesUI.GetBorderCompanion(c.borderTexture, "sepV") then
        tex._erbArt, tex._erbIcon, tex._erbRight, tex._erbC = true, icon, onRight and true or false, c
        CludesUI.RegisterPxReapply(
            tex,
            mod.ERB_PlaceDividerArt(tex, icon, onRight, c) and mod.ERB_DividerReapply or nil
        )
        return true
    end
    if tex._erbArt then
        tex._erbArt, tex._erbIcon, tex._erbC = nil, nil, nil
        tex:SetTexCoord(0, 1, 0, 1)
        tex:SetVertexColor(1, 1, 1, 1)
        CludesUI.RegisterPxReapply(tex, nil)
    end
    return false
end
function mod.ERB_DividerReapply(tex)
    if tex._erbArt then
        mod.ERB_PlaceDividerArt(tex, tex._erbIcon, tex._erbRight, tex._erbC)
    end
end
-- Spell Text / Duration Text colour on a cast bar FontString of ours (live bar
-- and preview): written only while set off white, or once more to restore white
-- after an earlier tint, so an untouched profile never recolours the text.
function mod.ERB_CastTextColor(fontStr, r, g, b, a)
    r, g, b, a = r or 1, g or 1, b or 1, a or 1
    local tinted = (r ~= 1 or g ~= 1 or b ~= 1 or a ~= 1)
    if tinted or fontStr._erbTint then
        fontStr:SetTextColor(r, g, b, a)
        fontStr._erbTint = tinted or nil
    end
end
-- Every bar that declares a match pad, for the pad-change notifier at the end
-- of ERB:ApplyAll (the Swing Timer's key finds no element off WoW Forever).
mod._erbPadKeys =
    { "ERB_Health", "ERB_Power", "ERB_ClassResource", "ERB_CastBar", "ERB_GCDBar", "ERB_SwingTimer" }
-- Seat the vanilla frame on `tex` round `rect` for a bar `thick` px across
-- (its height; its width when vertical, where the art turns a quarter turn
-- counter-clockwise and the overhangs turn with it: the art's top, right,
-- bottom and left become left, top, right and bottom) at frame scale k (nil =
-- the sheet's own pixels). Memoized on the rect, scale and orientation;
-- every layout pass re-runs it.
function mod.ERB_SeatClassicChrome(tex, rect, thick, vertical, k)
    if not (tex and rect) then
        return
    end
    local CF = CludesUI.ClassicFrame
    if not CF then
        return
    end
    -- `tex` is the handle the callers own: the nine-slice pieces ride its
    -- parent on its layer, created once, and the handle itself draws nothing.
    local p = tex._classicPieces
    if not p then
        local layer, sub = tex:GetDrawLayer()
        p = CF.Create(tex:GetParent(), layer, sub)
        tex._classicPieces = p
        tex:Hide()
    end
    CF.Seat(p, rect, k or 1, vertical)
end
-- The vanilla frame round a health, power or class resource bar: one
-- texture on an art child of the host above the fill, the pips and their
-- inner bars (level +9, under the count text and rune countdown), anchored
-- round `rect` (the fill area; the host itself when nil). The thickness
-- comes from the caller's target size (the bar may still be animating to
-- it), else from the rect; a secret size leaves the last layout standing.
-- `vertical` is the caller's target orientation (the rect's own may still be
-- the previous one on the pass that flips it); nil reads it from the host.
-- `k` is the frame scale (ERB_ClassicFrameK; nil = full size).
do
    local POOL = CludesUI._Pool -- read as in ns.ERB_Separators' block
    function mod.ERB_ApplyClassicBarChrome(host, rect, fw, fh, vertical, k)
        if not host then
            return
        end
        rect = rect or host
        local af = host._classicArt
        if not af then
            -- On an options preview (an options page pool host) the art frame is
            -- pooled with the preview; on a live bar this is CreateFrame.
            af = POOL.CreateFrame("Frame", nil, host)
            af:EnableMouse(false)
            host._classicArt = af
            local tex = af:CreateTexture(nil, "OVERLAY", nil, 2)
            if tex.SetSnapToPixelGrid then
                tex:SetSnapToPixelGrid(false)
                tex:SetTexelSnappingBias(0)
            end
            af._tex = tex
        end
        af:ClearAllPoints()
        af:SetAllPoints(rect)
        af:SetFrameLevel(host:GetFrameLevel() + 9)
        -- A bar the "Border Around All" frame wears keeps its own art hidden.
        af:SetShown(not host._classicGrouped)
        if vertical == nil then
            vertical = host._blizzVertical
                or (rect.GetOrientation and rect:GetOrientation() == "VERTICAL")
                or false
        end
        local wid, hgt = fw or rect:GetWidth(), fh or rect:GetHeight()
        if issecretvalue and (issecretvalue(wid) or issecretvalue(hgt)) then
            return
        end
        mod.ERB_SeatClassicChrome(af._tex, rect, vertical and wid or hgt, vertical, k)
    end
end -- POOL block
-- The frame around a bar: one texture on the host under everything the bar
-- draws, anchored round `rect` (the fill area; the host itself when nil)
-- with the personal resource display's overhang for this atlas (2 left, 3
-- top, 6 right, 7 bottom: the rim plus its bottom-right shadow; the tracked
-- buff bars' tighter 2/2/4/7 lets the bar sit over the top and right rim).
-- The stock fill art's own footprint (rounded, soft-edged, inside the rim)
-- becomes a mask over `rect` for the bar's fill and backing, so the user's
-- texture sits inside the rim exactly as the stock fill does instead of
-- painting over it. `vertical` is the caller's target orientation (nil =
-- read from the host); `k` (the frame scale) is read by the classic kit
-- alone: this panel keeps its stock reach (the atlas slices, so its rims
-- stay 1px round the fill; a vertical bar's turned copy is a texcoord cut
-- and stretches).
function mod.ERB_ApplyBlizzBarChrome(host, rect, fw, fh, vertical, k)
    if not host then
        return
    end
    rect = rect or host
    -- Classic WoW UI takes the vanilla frame instead: no panel, mask or bevel.
    if mod.ERB_BarsClassic() then
        mod.ERB_ApplyClassicBarChrome(host, rect, fw, fh, vertical, k)
        return
    end
    local backdrop = host._blizzBarBg
    if not backdrop then
        backdrop = host:CreateTexture(nil, "BACKGROUND", nil, -2)
        if backdrop.SetSnapToPixelGrid then
            backdrop:SetSnapToPixelGrid(false)
            backdrop:SetTexelSnappingBias(0)
        end
        host._blizzBarBg = backdrop
        if C_Texture.GetAtlasInfo(mod.ERB_BLIZZ_BAR_FILL) then
            local mask = rect:CreateMaskTexture()
            mask:SetAtlas(mod.ERB_BLIZZ_BAR_FILL)
            mask:SetAllPoints(rect)
            host._blizzBarMask = mask
        end
    end
    -- A vertical bar (orientation option, or the class row's own flag) takes
    -- the panel turned on its side: the atlas is a wide strip, stretched into
    -- a column its rim would smear. The overhang turns with it (a 90-degree
    -- turn maps the art's top/right/bottom/left to left/top/right/bottom).
    -- The caller's target orientation wins (the rect's own may still be the
    -- previous one on the pass that flips it); nil reads it from the host.
    if vertical == nil then
        vertical = host._blizzVertical
            or (rect.GetOrientation and rect:GetOrientation() == "VERTICAL")
            or false
    end
    -- A bar the "Border Around All" panel holds keeps its own panel hidden.
    local grouped = host._classicGrouped
    if vertical then
        -- The turned panel, nine-sliced by hand like the group's (a turned
        -- copy is a texcoord cut, which stretches and slides its rims in
        -- under the fill): rims 1px round the fill at any size. Seated once
        -- per rect (fixed per bar); the pieces follow it.
        local pcs = host._blizzBar9
        local details = C_Texture.GetAtlasInfo(mod.ERB_BLIZZ_BAR_BG)
        if not pcs and details then
            pcs = {}
            for idx = 1, 9 do
                local t = host:CreateTexture(nil, "BACKGROUND", nil, -2)
                if t.SetSnapToPixelGrid then
                    t:SetSnapToPixelGrid(false)
                    t:SetTexelSnappingBias(0)
                end
                pcs[idx] = t
            end
            host._blizzBar9 = pcs
        end
        if pcs then
            if host._blizzBar9Rect ~= rect and details then
                host._blizzBar9Rect = rect
                mod.ERB_SeatBlizzPanel9(pcs, rect, true, details)
            end
            for idx = 1, 9 do
                pcs[idx]:SetShown(not grouped)
            end
            host._blizzBar9On = true
        end
        backdrop:Hide()
    else
        if host._blizzBar9On then
            host._blizzBar9On = nil
            local pcs = host._blizzBar9
            for idx = 1, 9 do
                pcs[idx]:Hide()
            end
        end
        mod.ERB_SeatBlizzBarBg(backdrop, false)
        backdrop:ClearAllPoints()
        backdrop:SetPoint("TOPLEFT", rect, "TOPLEFT", -2, 3)
        backdrop:SetPoint("BOTTOMRIGHT", rect, "BOTTOMRIGHT", 6, -7)
        backdrop:SetShown(not grouped)
    end
    mod.ERB_SeatBlizzMask(host)
    -- Health/power: the fill's own StatusBar carries the bevel (sized from the
    -- caller's target size: the bar may still be animating to it).
    if rect.GetStatusBarTexture then
        rect._blizzVertical = vertical and true or false
        mod.ERB_BlizzBarShadow(rect, host._blizzBarMask, fw, fh)
    end
end

Inner.AppendSharedMediaTextures, Inner.CAST_BAR_TEXTURES = AppendSharedMediaTextures, CAST_BAR_TEXTURES
Inner.SPARK_TEX = SPARK_TEX
Inner.broken = false
