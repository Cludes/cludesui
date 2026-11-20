if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_RaidFrames_Stock.lua
--
--  Blizzard Style / Classic WoW UI on the raid frames: raid and party buttons
--  (party in its "Raid Frames" layout), Friendly Boss, Extra Frames, Pet
--  Frames and the options preview. The stock per-frame edge stands in for
--  the CludesUI border, the stock target and aggro highlights for the
--  CludesUI target and threat borders, and Classic draws the stock
--  health/power divider. Every other CludesUI feature is untouched.
--
--  Built only under a stock style (the latch, ns.RF_Style, is in the main
--  file): the CludesUI look never reaches any of this. Helpers take the
--  owner frame and `st`, the table that holds its state -- the FFD entry of a
--  raid or party button (never a key on the button itself), or the frame
--  itself for the frames on the Friendly Boss visuals (Friendly Boss, the
--  Beside Owner pets) and the preview. The one exception: the pet header's
--  buttons are made by the pet header, yet keep this state on the frame
--  like the rest of their Friendly Boss visuals. All paint is event-driven
--  through the callers' existing edges; nothing here ticks.
-------------------------------------------------------------------------------
local _, mod = ...
-- The options page pool's table (CludesUI_PixelPerfect.lua makes it; the
-- options addon fills it in place): read through this file local, never the
-- public slot.
local POOL = CludesUI._Pool

local WHITE = "Interface\\Buttons\\WHITE8X8"

-- Blizzard Style: the 12.1 CompactUnitFrame edge is its background showing
-- 1px round a health bar inset 1px each side, i.e. a 1px dark ring.
local BLIZZ_EDGE_R, BLIZZ_EDGE_G, BLIZZ_EDGE_B = 0.078, 0.078, 0.078 -- #141414
-- Classic WoW UI: the pre-10.0 two-tone lines straddling every edge, one
-- ring just outside the frame and one just inside, per side.
local CLASSIC_OUTER = {
    top = { 0.329, 0.322, 0.314 }, -- #545250
    bottom = { 0.031, 0.016, 0.031 }, -- #080408
    left = { 0.282, 0.275, 0.267 }, -- #484644
    right = { 0.282, 0.282, 0.282 }, -- #484848
}
local CLASSIC_INNER = {
    top = { 0.031, 0.016, 0.031 },
    bottom = { 0.329, 0.322, 0.314 },
    left = { 0.282, 0.282, 0.282 },
    right = { 0.282, 0.275, 0.267 },
}
-- Classic health/power divider: grey in the health bar's last row, black in
-- the power bar's first.
local DIV_GREY = { 0.329, 0.322, 0.314 }
local DIV_BLACK = { 0.031, 0.016, 0.031 }

-- Highlights. Blizzard Style: the 12.1 atlases (2px rims, sliced). Classic
-- WoW UI: the pre-10.0 highlight sheet, falling back to the atlases when the
-- file is not on this client.
local SEL_ATLAS, AGG_ATLAS = "RaidFrame-TargetFrame", "RaidFrame-AgroFrame"
local CLASSIC_HL = "Interface\\RaidFrame\\Raid-FrameHighlights"
local CLASSIC_SEL_TC = { 0.0078125, 0.5546875, 0.2890625, 0.5546875 }
local CLASSIC_AGG_TC = { 0.0078125, 0.5546875, 0.0078125, 0.2734375 }
local _classicHlOK -- probed once

local function PX(widget)
    local Pix = CludesUI.PP or CludesUI.PanelPP
    local es = widget:GetEffectiveScale()
    if not es or es <= 0 then
        es = 1
    end
    return ((Pix and Pix.perfect) or 1) / es
end

local function ColorSides(widget, cols)
    local Pix = CludesUI.PP or CludesUI.PanelPP
    local c = Pix and Pix.GetBorders(widget)
    if not c then
        return
    end
    -- Drop the ring's single stored colour: every re-snap (its own first
    -- frames, each loading screen and UI-scale change) repaints all four
    -- strips from it, which would flatten these per-side colours to black.
    c._bdColor = nil
    local t, b, l, region = cols.top, cols.bottom, cols.left, cols.right
    if c._top then
        c._top:SetVertexColor(t[1], t[2], t[3], 1)
    end
    if c._bottom then
        c._bottom:SetVertexColor(b[1], b[2], b[3], 1)
    end
    if c._left then
        c._left:SetVertexColor(l[1], l[2], l[3], 1)
    end
    if c._right then
        c._right:SetVertexColor(region[1], region[2], region[3], 1)
    end
end

-------------------------------------------------------------------------------
--  Build (once per owner, under a stock style)
-------------------------------------------------------------------------------
-- `power`: the owner's power StatusBar (ours), for the Classic divider.
function mod.RF_StockBuild(ownerFrame, stockStyle, powerBar)
    if stockStyle.stockEdge or not (mod.RF_Stock and mod.RF_Stock()) then
        return
    end
    local Pix = CludesUI.PP or CludesUI.PanelPP
    if not Pix then
        return
    end
    -- On the Buff / Debuff Manager preview's replica (a frame of the options
    -- page pool, CludesUI_FramePool.lua) these pieces are pooled with it and
    -- handed out again by its next build; on every other owner a plain new frame.
    local CreateFrame = POOL.CreateFrame
    local classicArt = mod.RF_Classic()
    -- The edge rides the CludesUI base border's level (+8): above the
    -- health, absorbs and dispel overlay, under the raised hover border and
    -- the text. Its own frame, because the stood-down border frame is hidden.
    local edgeTex = CreateFrame("Frame", nil, ownerFrame)
    edgeTex:SetAllPoints(ownerFrame)
    edgeTex:SetFrameLevel(ownerFrame:GetFrameLevel() + 8)
    edgeTex:EnableMouse(false)
    stockStyle.stockEdge = edgeTex
    if classicArt then
        Pix.CreateBorder(edgeTex, 0, 0, 0, 1, 1)
        ColorSides(edgeTex, CLASSIC_INNER)
        local outerFrame = CreateFrame("Frame", nil, edgeTex)
        outerFrame:EnableMouse(false)
        stockStyle.stockEdgeOuter = outerFrame
        Pix.CreateBorder(outerFrame, 0, 0, 0, 1, 1)
        ColorSides(outerFrame, CLASSIC_OUTER)
        if powerBar then
            local greyColor = powerBar:CreateTexture(nil, "OVERLAY", nil, 6)
            greyColor:SetTexture(WHITE)
            greyColor:SetVertexColor(DIV_GREY[1], DIV_GREY[2], DIV_GREY[3], 1)
            local blackColor = powerBar:CreateTexture(nil, "OVERLAY", nil, 6)
            blackColor:SetTexture(WHITE)
            blackColor:SetVertexColor(DIV_BLACK[1], DIV_BLACK[2], DIV_BLACK[3], 1)
            if Pix.DisablePixelSnap then
                Pix.DisablePixelSnap(greyColor)
                Pix.DisablePixelSnap(blackColor)
            end
            greyColor:Hide()
            blackColor:Hide()
            stockStyle.stockDiv = { greyColor, blackColor, powerBar }
        end
    else
        local red, green, blue = BLIZZ_EDGE_R, BLIZZ_EDGE_G, BLIZZ_EDGE_B
        local backdrop = _G.COMPACT_UNIT_FRAME_FRIENDLY_HEALTH_COLOR_BG
        if type(backdrop) == "table" and backdrop.GetRGB then
            red, green, blue = backdrop:GetRGB()
        end
        Pix.CreateBorder(edgeTex, red, green, blue, 1, 1)
    end
    -- Highlights: textures made on first need (login budget).
    local highlight = CreateFrame("Frame", nil, ownerFrame)
    highlight:SetAllPoints(ownerFrame)
    highlight:SetFrameLevel(ownerFrame:GetFrameLevel() + (mod.LVL_RAISE or 10))
    highlight:EnableMouse(false)
    stockStyle.stockHl = highlight
    mod.RF_StockSeat(stockStyle)
end

-- Re-seat the pieces that are sized in physical pixels (the Classic outer
-- ring and divider); every border restyle runs it.
function mod.RF_StockSeat(stockStyle)
    local edgeTex = stockStyle.stockEdge
    if not edgeTex then
        return
    end
    edgeTex:Show()
    local outerFrame = stockStyle.stockEdgeOuter
    if outerFrame then
        local pixel = PX(edgeTex)
        outerFrame:ClearAllPoints()
        outerFrame:SetPoint("TOPLEFT", edgeTex, "TOPLEFT", -pixel, pixel)
        outerFrame:SetPoint("BOTTOMRIGHT", edgeTex, "BOTTOMRIGHT", pixel, -pixel)
    end
end

-- Classic divider on the power bar's top edge (the caller shows it only
-- while the power bar is shown; its textures hide with the bar).
function mod.RF_StockDivider(stockStyle)
    local div = stockStyle.stockDiv
    if not div then
        return false
    end
    local greyColor, blackColor, powerBar = div[1], div[2], div[3]
    local pixel = PX(powerBar)
    greyColor:ClearAllPoints()
    greyColor:SetPoint("BOTTOMLEFT", powerBar, "TOPLEFT", 0, 0)
    greyColor:SetPoint("BOTTOMRIGHT", powerBar, "TOPRIGHT", 0, 0)
    greyColor:SetHeight(pixel)
    blackColor:ClearAllPoints()
    blackColor:SetPoint("TOPLEFT", powerBar, "TOPLEFT", 0, 0)
    blackColor:SetPoint("TOPRIGHT", powerBar, "TOPRIGHT", 0, 0)
    blackColor:SetHeight(pixel)
    greyColor:Show()
    blackColor:Show()
    return true
end

-------------------------------------------------------------------------------
--  Highlights
-------------------------------------------------------------------------------
local function ClassicHlOK()
    if _classicHlOK == nil then
        _classicHlOK = (GetFileIDFromPath and GetFileIDFromPath(CLASSIC_HL)) and true or false
    end
    return _classicHlOK
end

local function MakeHl(stockStyle, layer, atlas, tc)
    local texture = stockStyle.stockHl:CreateTexture(nil, layer)
    texture:SetAllPoints(stockStyle.stockHl)
    if mod.RF_Classic() and ClassicHlOK() then
        texture:SetTexture(CLASSIC_HL)
        texture:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
    else
        texture:SetAtlas(atlas)
    end
    texture:Hide()
    return texture
end

-- The stock selection ring (the target), memoised on st.
function mod.RF_StockTarget(stockStyle, on)
    if not stockStyle.stockHl then
        return
    end
    on = on and true or false
    if stockStyle._stSel == on then
        return
    end
    stockStyle._stSel = on
    local texture = stockStyle._stSelTex
    if not texture then
        if not on then
            return
        end
        -- Follows the frame's alpha (stock ignores it for the range fade,
        -- but this module also hides whole containers with alpha).
        texture = MakeHl(stockStyle, "OVERLAY", SEL_ATLAS, CLASSIC_SEL_TC)
        stockStyle._stSelTex = texture
    end
    texture:SetShown(on)
end

-- The stock aggro rim in the stock threat colour; `status` nil hides it.
-- Memoised on the status. Blizzard Style takes 12.1's own two colours
-- (gaining / high threat); Classic the pre-10.0 status colours.
function mod.RF_StockAggro(stockStyle, status)
    if not stockStyle.stockHl then
        return
    end
    if stockStyle._stAgg == status then
        return
    end
    stockStyle._stAgg = status
    local texture = stockStyle._stAggTex
    if not texture then
        if not status then
            return
        end
        texture = MakeHl(stockStyle, "ARTWORK", AGG_ATLAS, CLASSIC_AGG_TC)
        stockStyle._stAggTex = texture
    end
    if status then
        local red, green, blue
        -- The stock party frame (the Party Frames kit's Flash) colours its
        -- aggro by threat status too.
        if (mod.RF_Classic() or stockStyle.kit) and GetThreatStatusColor then
            red, green, blue = GetThreatStatusColor(status)
        else
            local c = (status == 3) and _G.HIGH_THREAT_COLOR or _G.GAINING_THREAT_COLOR
            if c and c.GetRGB then
                red, green, blue = c:GetRGB()
            elseif status == 3 then
                red, green, blue = 1, 0.271, 0.043 -- #FF450B
            else
                red, green, blue = 0.973, 0.710, 0 -- #F8B500
            end
        end
        texture:SetVertexColor(red, green, blue, 1)
        texture:Show()
    else
        texture:Hide()
    end
end

-- State recolour under a stock style: the stock ring for the target, and the
-- CludesUI hover border (stock has no hover) drawn solid in the user's
-- hover colour on the stood-down border frame `bf`. Its exact size counts only
-- while it was set against Solid (the texture drawn here).
local SOLID_S = { borderTexture = "solid" }
function mod.RF_StockHighlight(stockStyle, bf, cfg, hover, target)
    mod.RF_StockTarget(stockStyle, target)
    if hover then
        local color = cfg.hoverBorderColor
        local hs = cfg.hoverBorderSize or 1
        mod.ApplyHighlightBorder(
            bf,
            SOLID_S,
            hs,
            color and color.r or 1,
            color and color.g or 1,
            color and color.b or 1,
            cfg.hoverBorderAlpha or 1,
            CludesUI.BorderPx(cfg.hoverBorderSizePx, hs, "solid")
        )
    else
        mod.ApplyHighlightBorder(bf, SOLID_S, nil, 0, 0, 0, 0)
    end
end

-------------------------------------------------------------------------------
--  First-visit defaults (the Style page's onEnable and the enable-time
--  catch-up for a profile that arrives already switched). Once per profile
--  (stockRaidSeeded, one of the per-style slot stamps). Every texture is a
--  key in this module's own table pointing straight at the game file, so it
--  works without SharedMedia. A party setting the Party page keeps unsynced
--  (a stored party_ key) takes the same value.
-------------------------------------------------------------------------------
local function SeedBoth(profile, key, v)
    profile[key] = v
    if rawget(profile, "party_" .. key) ~= nil then
        profile["party_" .. key] = v
    end
end
function mod.RF_SeedStock(profile, styleKey)
    if not profile or profile.stockRaidSeeded then
        return
    end
    if styleKey ~= "blizzard" and styleKey ~= "classic" then
        return
    end
    profile.stockRaidSeeded = true
    local classicArt = styleKey == "classic"
    SeedBoth(profile, "healthBarTexture", classicArt and "blizzardRaid" or "blizzardRaidModern")
    -- Stock frames stack flush: the edges meet in one seam (the Party
    -- page's own spacing too, when it keeps one).
    profile.cellSpacing, profile.groupSpacing = 0, 0
    if rawget(profile, "partyCellSpacing") ~= nil then
        profile.partyCellSpacing = 0
    end
    -- The stock raid role art, and the stock absorb looks (Classic's with
    -- the opacity its dropdown pairs with it; each with the Blizzard Glow
    -- Line its pick sets: on for Default Blizz Frames, off for Classic's).
    SeedBoth(profile, "roleIconStyle", "classicCircle")
    SeedBoth(profile, "absorbStyle", classicArt and "blizzard" or "blizzardModern")
    SeedBoth(profile, "absorbGlowLine", not classicArt)
    if classicArt then
        SeedBoth(profile, "absorbOpacity", 90)
    end
    SeedBoth(profile, "healAbsorbStyle", classicArt and "blizzard" or "healBlizzModern")
end

-- A texture saved as the shared-media "Blizzard Raid Bar" before the native
-- key existed (the list now drops that copy as a duplicate) moves to the
-- native key once. Runs at every enable; a no-op once nothing matches.
local SM_RAID_BAR = "sm:Blizzard Raid Bar"
local SM_RAID_KEYS = { "healthBarTexture", "absorbStyle", "healAbsorbStyle", "maxHealthStyle" }
function mod.RF_MigrateSmRaidBar(profile)
    if not profile then
        return
    end
    for index = 1, #SM_RAID_KEYS do
        local k = SM_RAID_KEYS[index]
        if rawget(profile, k) == SM_RAID_BAR then
            profile[k] = "blizzardRaid"
        end
        if rawget(profile, "party_" .. k) == SM_RAID_BAR then
            profile["party_" .. k] = "blizzardRaid"
        end
    end
end

-------------------------------------------------------------------------------
--  Party Frames kit: the stock portrait party frame
--
--  Under a stock style the Party page's Frame Style can dress the party
--  buttons (self button included) as the stock portrait party frame: the
--  12.1 atlas frame under Blizzard Style, vanilla's UI-PartyFrame under
--  Classic WoW UI. Latched per session (ns.RF_PartyKit, main file). Every
--  CludesUI party feature stays: the kit host (our frame at the art's
--  rect) is what auras, indicators and the raid marker anchor to, the bar
--  texts sit on the kit's health bar, and name, role, leader and ready check
--  take the stock spots plus the user's offsets. State lives on `st` (the
--  button's FFD entry, or the preview frame itself) and on our own frames.
--
--  Geometry is the stock frame's own, in frame units from the box's top-left
--  (y grows DOWN in the rects; the spots are SetPoint-ready), scaled by the
--  Frame Scale. Blizzard Style draws the art under the bars (rounded masks,
--  bevel strips); Classic draws vanilla's art over them (plain rectangles).
-------------------------------------------------------------------------------
mod.RF_KITS = {
    blizzard = {
        boxW = 120,
        boxH = 53,
        bevel = true,
        host = { x = 1, y = 2, w = 120, h = 49 },
        art = { x = 1, y = 2, w = 120, h = 49, atlas = "UI-HUD-UnitFrame-Party-PortraitOn" },
        flash = { x = 1, y = 2, w = 114, h = 47, atlas = "ui-hud-unitframe-party-portraiton-incombat" },
        glow = { x = 1, y = 2, w = 120, h = 49, atlas = "ui-hud-unitframe-party-portraiton-status" },
        portrait = { x = 7, y = 6, w = 37, h = 37 },
        health = {
            x = 45,
            y = 19,
            w = 70,
            h = 10,
            mask = "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Health-Mask",
            mx = -29,
            my = 3,
            mw = 128,
            mh = 16,
        },
        power = {
            x = 41,
            y = 30,
            w = 74,
            h = 7,
            mask = "UI-HUD-UnitFrame-Party-PortraitOn-Bar-Mana-Mask",
            mx = -27,
            my = 4,
            mw = 128,
            mh = 16,
        },
        name = { p = "TOPLEFT", rel = "TOPLEFT", x = 46, y = -6, w = 57, jv = "TOP" },
        role = { p = "TOPRIGHT", rel = "TOPRIGHT", x = -5, y = -5 },
        lead = { p = "BOTTOM", rel = "TOP", x = -10, y = -6 },
        rc = { p = "CENTER", rel = "CENTER", x = 0, y = -2 },
        -- The stock aura row (box 48,43), from the host's top-left.
        auraRow = { x = 47, y = -41 },
    },
    classic = {
        boxW = 128,
        boxH = 53,
        artAbove = true,
        host = { x = 0, y = 3, w = 119, h = 48 },
        art = { x = 0, y = 2, w = 128, h = 64, file = "Interface\\TargetingFrame\\UI-PartyFrame" },
        flash = { x = -3, y = -2, w = 128, h = 64, file = "Interface\\TargetingFrame\\UI-PartyFrame-Flash" },
        glow = { x = -3, y = -2, w = 128, h = 64, file = "Interface\\TargetingFrame\\UI-PartyFrame-Flash" },
        back = { x = 45, y = 11, w = 72, h = 20 },
        portrait = { x = 7, y = 6, w = 37, h = 37 },
        health = { x = 47, y = 12, w = 70, h = 8 },
        power = { x = 47, y = 21, w = 70, h = 8 },
        -- Vanilla's name sits on the plaque's top rim (its BOTTOMLEFT 50,43
        -- of the 53-tall box); vanilla had no role icon, so the role takes
        -- the rim's right end and the name stops short of it.
        name = { p = "BOTTOMLEFT", rel = "TOPLEFT", x = 50, y = -10, w = 52, jv = "BOTTOM" },
        role = { p = "BOTTOMRIGHT", rel = "TOPLEFT", x = 117, y = -11 },
        lead = { p = "TOPLEFT", rel = "TOPLEFT", x = 0, y = 0 },
        rc = { p = "CENTER", rel = "CENTER", x = 0, y = 0 },
        -- Vanilla's aura row (box 48,32, under the mana bar), from the host.
        auraRow = { x = 48, y = -29 },
    },
}
-- The kit's target glow: the stock selection colour (not a user setting,
-- as the stock raid ring under Phase 1).
local KIT_SEL_R, KIT_SEL_G, KIT_SEL_B = 1, 0.973, 0.678 -- #FFF8AD
-- Defaults (user 2026-09-22): Frame Scale 120% (nil = this), and the gap
-- between frames (Frame Scale cog's Spacing; nil = this).
mod.RF_KIT_SCALE = 1.2
mod.RF_KIT_SPACING = 6

-- Scaled geometry, one table per (latched kit, scale). Unsnapped: callers and
-- the seat pass snap live (the kit pass re-seats when the pixel grid moves).
local _kitGeom = {}
local function ScaleRect(source, k)
    if not source then
        return nil
    end
    local region = {}
    for key, v in pairs(source) do
        if type(v) == "number" then
            region[key] = v * k
        else
            region[key] = v
        end
    end
    return region
end
function mod.RF_KitGeom(key)
    local kit = mod.RF_PartyKit()
    local K = kit and mod.RF_KITS[kit]
    if not K then
        return nil
    end
    key = tonumber(key) or mod.RF_KIT_SCALE
    if key < 0.5 then
        key = 0.5
    elseif key > 2 then
        key = 2
    end
    local g = _kitGeom[key]
    if g then
        return g
    end
    g = {
        key = kit,
        k = key,
        boxW = K.boxW * key,
        boxH = K.boxH * key,
        bevel = K.bevel,
        artAbove = K.artAbove,
    }
    g.host, g.art, g.flash, g.glow =
        ScaleRect(K.host, key), ScaleRect(K.art, key), ScaleRect(K.flash, key), ScaleRect(K.glow, key)
    g.back, g.portrait = ScaleRect(K.back, key), ScaleRect(K.portrait, key)
    g.health, g.power = ScaleRect(K.health, key), ScaleRect(K.power, key)
    g.name, g.role, g.lead, g.rc =
        ScaleRect(K.name, key), ScaleRect(K.role, key), ScaleRect(K.lead, key), ScaleRect(K.rc, key)
    g.auraRow = ScaleRect(K.auraRow, key)
    _kitGeom[key] = g
    return g
end

-- The kit's aura sizes (Party page, FRAME STYLE row: Debuff Size / Buff
-- Size, each with X/Y, and the buffs' Anchor): the stock frame's 15.
local KIT_DEBUFF_SIZE, KIT_BUFF_SIZE = 15, 15

-- The party settings the kit's layout decides, as the party settings view
-- reads them while the kit is latched: the neutral keys (main file), and the
-- debuff row under the frame (user 2026-09-22: debuffs below the frame,
-- flowing right from the stock aura row and wrapping down, dispellables in
-- the same row) at the kit's Debuff Size and X/Y, which Auto Resize scales
-- like any other icon. `p` = the profile (or the preview overlay) the view
-- reads; one table per scaled geometry, its size/offsets refreshed per call.
function mod.RF_KitViewKeys(profile)
    local g = profile and mod.RF_KitGeom(profile.partyKitScale)
    if not g then
        return nil
    end
    local v = g.view
    if not v then
        v = {}
        for key, val in pairs(mod.RF_KIT_NEUTRAL) do
            v[key] = val
        end
        v.debuffPosition = "topleft"
        v.debuffGrowDirection = "RIGHT"
        v.debuffWrapDirection = "DOWN"
        v.dispellableDebuffLocation = "same"
        g.view = v
    end
    local sc = mod._partyIndicatorScale or 1
    v.debuffSize = (profile.partyKitDebuffSize or KIT_DEBUFF_SIZE) * sc
    v.debuffOffsetX = g.auraRow.x + (profile.partyKitDebuffX or 0) * sc
    v.debuffOffsetY = g.auraRow.y + (profile.partyKitDebuffY or 0) * sc
    return v
end

-- Buff Manager under the kit (user 2026-09-22: buffs to the right of the
-- frame; the Frame Style row's Anchor puts them on its left, or above it --
-- always above with Horizontal Frames, where the next frame sits beside
-- it): every icon indicator joins ONE run just outside the frame (the first
-- icon indicator with spells is the run's root, the others ride it through
-- Anchor To). Beside the frame the icons run along its top edge and the
-- squares along its bottom edge; above it the icons run right from its
-- left end and the squares left from its right end.
-- Fixed-slot indicators (per-spell cells that never compact: mixed-colour
-- squares) go end to end at the start of their run and the compacting run
-- starts after them, so nothing shares a cell. Bars and effects keep the
-- user's placement. A VIEW over the live indicator tables: each proxy reads
-- its indicator live and shadows only placement (and the icons' size), so
-- the user's own settings are never touched and live edits still flow
-- through. Proxies are cached per indicator (stable identity for the Buff
-- Manager's metadata), weak both ways: Lua 5.1 has no ephemerons, and a
-- proxy holds its indicator.
local KIT_BUFF_GAP = 2
local _kitBmProxy = setmetatable({}, { __mode = "kv" })
local KIT_BM_MT = {
    __index = function(t, key)
        -- Anchor To is the view's own (nil on a run's root).
        if key == "anchorTo" then
            return rawget(t, "_kitAnchor")
        end
        return rawget(t, "_kitSrc")[key]
    end,
}
local function KitBmProxy(indicator)
    local p = _kitBmProxy[indicator]
    if not p then
        p = setmetatable({ _kitSrc = indicator }, KIT_BM_MT)
        _kitBmProxy[indicator] = p
    end
    return p
end
-- The run's position point and growth for `mode` ("RIGHT" | "LEFT" |
-- "ABOVE") and the indicator kind.
local function RunSpec(modeName, kindName)
    if modeName == "ABOVE" then
        if kindName == "icon" then
            return "TOPLEFT", "RIGHT"
        end
        return "TOPRIGHT", "LEFT"
    end
    return ((kindName == "icon") and "TOP" or "BOTTOM") .. modeName, modeName
end
-- `size` the element size, `lead` the reserved run length before it,
-- `ox`/`oy` the user's X/Y (all unscaled: the Buff Manager applies its own
-- Auto Resize scale to sizes and offsets alike). A run's first element sits
-- one gap outside the frame edge (a chain's first element lands INSIDE its
-- position corner, so its own size pushes it out); members only continue
-- the run.
local function PlaceRun(profile, modeName, kindName, first, size, ox, oy, lead)
    local anchorPoint, grow = RunSpec(modeName, kindName)
    profile.position, profile.growDirection = anchorPoint, grow
    if not first then
        profile.offsetX, profile.offsetY = 0, 0
        return
    end
    lead = lead or 0
    if modeName == "ABOVE" then
        profile.offsetX = ((grow == "LEFT") and -lead or lead) + ox
        profile.offsetY = size + KIT_BUFF_GAP + oy
    else
        local result = lead + size + KIT_BUFF_GAP
        profile.offsetX = ((modeName == "LEFT") and -result or result) + ox
        profile.offsetY = oy
    end
end
-- Where the kit's buff runs sit: "RIGHT" | "LEFT" | "ABOVE" (Horizontal
-- Frames always above: the next frame sits beside each one).
function mod.RF_KitBuffMode(prof)
    if not prof then
        return "RIGHT"
    end
    if prof.partyHorizontal then
        return "ABOVE"
    end
    local a = prof.partyKitBuffAnchor
    if a == "left" then
        return "LEFT"
    end
    if a == "above" then
        return "ABOVE"
    end
    return "RIGHT"
end
-- The kit's buff size (Frame Style row), unscaled.
function mod.RF_KitBuffSize(prof)
    return (prof and prof.partyKitBuffSize) or KIT_BUFF_SIZE
end
-- Height (unscaled) of the buff lines the kit stacks above a frame: the icon
-- line at Buff Size, then the squares' line above it, as RF_KitBmView last
-- saw the Buff Manager (one icon line until it has run).
function mod.RF_KitAboveUnits(s)
    local iconTex = mod._kitAboveIcon
    if iconTex == nil then
        return mod.RF_KitBuffSize(s) + KIT_BUFF_GAP
    end
    local hgt = iconTex and (mod.RF_KitBuffSize(s) + KIT_BUFF_GAP) or 0
    local sq = mod._kitAboveSq or 0
    if sq > 0 then
        hgt = hgt + sq + KIT_BUFF_GAP
    end
    return hgt
end
-- A change to that height re-spaces the party frames and re-seats the
-- Friendly Boss group once, after the pass that found it (the view is built
-- mid-reload and mid-creation); combat leaves it to the regen party pass.
function mod._KitAboveFlush()
    mod._kitAbovePending = nil
    if InCombatLockdown() then
        mod._partyKitDirtyInCombat = true
    elseif mod._LayoutPartyFrames then
        mod._LayoutPartyFrames()
    end
end
-- noPublish: the options preview's pass, which must not re-space the live frames.
function mod.RF_KitBmView(inds, noPublish)
    local result = {}
    local chainMode = mod.RFC_BmChainMode
    local prof = mod.db and mod.db.profile
    local modeName = mod.RF_KitBuffMode(prof)
    local buffSize = mod.RF_KitBuffSize(prof)
    local ox = (prof and prof.partyKitBuffX) or 0
    local oy = (prof and prof.partyKitBuffY) or 0
    -- Pre-pass: each fixed-slot indicator's lead, and each run's reserve.
    local leadIcon, leadSquare = 0, 0
    local leads
    local anyIcon, maxSq = false, 0
    for index = 1, #inds do
        local indicator = inds[index]
        local kindName = indicator.type or "icon"
        if indicator.enabled and indicator.spells and #indicator.spells > 0 then
            if kindName == "icon" then
                anyIcon = true
            elseif kindName == "square" and (indicator.size or 18) > maxSq then
                maxSq = indicator.size or 18
            end
        end
        if
            indicator.enabled
            and (kindName == "icon" or kindName == "square")
            and not (chainMode and chainMode(indicator) == "g")
        then
            local size = (kindName == "icon") and buffSize or (indicator.size or 18)
            local length = (indicator.spells and #indicator.spells or 0) * (size + (indicator.spacing or 0))
            leads = leads or {}
            if kindName == "icon" then
                leads[indicator] = leadIcon
                leadIcon = leadIcon + length
            else
                leads[indicator] = leadSquare
                leadSquare = leadSquare + length
            end
        end
    end
    -- Publish the lines above the frame (the frame spacing and the Friendly
    -- Boss attach reserve them); a change relays once, above only.
    if not noPublish and (anyIcon ~= mod._kitAboveIcon or maxSq ~= mod._kitAboveSq) then
        local was = mod.RF_KitAboveUnits(prof)
        mod._kitAboveIcon, mod._kitAboveSq = anyIcon, maxSq
        if modeName == "ABOVE" and mod.RF_KitAboveUnits(prof) ~= was and not mod._kitAbovePending then
            mod._kitAbovePending = true
            C_Timer.After(0, mod._KitAboveFlush)
        end
    end
    -- Above the frame both runs start on one line from opposite ends: the
    -- squares take the next line up so the two can never collide.
    local sqOy = oy
    if modeName == "ABOVE" and anyIcon then
        sqOy = oy + buffSize + KIT_BUFF_GAP
    end
    local iconRoot, squareRoot
    for index = 1, #inds do
        local indicator = inds[index]
        local kindName = indicator.type or "icon"
        local record = indicator
        if indicator.enabled and (kindName == "icon" or kindName == "square") then
            local p = KitBmProxy(indicator)
            -- Buff Size sets every buff icon; squares keep their own size.
            local size
            if kindName == "icon" then
                p.size = buffSize
                size = buffSize
            else
                p.size = nil
                size = indicator.size or 18
            end
            local reserve, root, runOy
            if kindName == "icon" then
                reserve, root, runOy = leadIcon, iconRoot, oy
            else
                reserve, root, runOy = leadSquare, squareRoot, sqOy
            end
            local chain = chainMode and chainMode(indicator) == "g"
            local hasSpells = indicator.spells and #indicator.spells > 0
            p._kitAnchor = nil
            -- Above the frame, wrapped lines stack upward, away from it.
            if modeName == "ABOVE" then
                p.wrapUp = true
            else
                p.wrapUp = nil
            end
            if not chain then
                -- Fixed slots: their own reserved cells at the run's start.
                PlaceRun(p, modeName, kindName, true, size, ox, runOy, leads and leads[indicator] or 0)
            elseif hasSpells and root and root.id ~= nil then
                PlaceRun(p, modeName, kindName, false)
                p._kitAnchor = root.id
            else
                PlaceRun(p, modeName, kindName, true, size, ox, runOy, reserve)
                if hasSpells and not root then
                    if kindName == "icon" then
                        iconRoot = indicator
                    else
                        squareRoot = indicator
                    end
                end
            end
            record = p
        end
        result[#result + 1] = record
    end
    return result
end

-- Party slot box + spacing, UNSNAPPED (callers snap). The kit's box is the
-- stock frame times its Frame Scale and keeps its own spacing (nil =
-- RF_KIT_SPACING); off the kit this is the Party page's Frame Width/Height/
-- Spacing, the box widened by an attached portrait. The 4th return is that
-- portrait's width: the bars' own width is the box width minus it.
function mod.RF_PartyDims(cfg)
    if mod.RF_PartyKit() then
        local g = mod.RF_KitGeom(cfg.partyKitScale)
        if g then
            local cs = cfg.partyKitSpacing or mod.RF_KIT_SPACING
            -- Buffs above stacked frames: the gap also holds the buff runs'
            -- lines, so they clear the frame above (scaled like the Buff
            -- Manager scales them).
            if not cfg.partyHorizontal and mod.RF_KitBuffMode(cfg) == "ABOVE" then
                local bm = (cfg.partyAutoResizeTrackedBuffs ~= false) and g.k or 1
                local by = cfg.partyKitBuffY or 0
                cs = cs + (mod.RF_KitAboveUnits(cfg) + ((by > 0) and by or 0)) * bm
            end
            return g.boxW, g.boxH, cs, 0
        end
    end
    local wid = cfg.partyFrameWidth or cfg.frameWidth or 125
    local hgt = cfg.partyFrameHeight or cfg.frameHeight or 60
    local res = mod.RF_PtReserve and mod.RF_PtReserve(cfg, hgt) or 0
    local spacing = cfg.partyCellSpacing or cfg.cellSpacing or 2
    if mod.RF_CompactOn(cfg, true) then
        spacing = mod.RF_OnePixel(true)
    end
    return wid + res, hgt, spacing, res
end

-- Friendly Boss "Show in Dungeons" beside the party container under the kit:
-- the side to use (true = before: left, or above for horizontal frames) and
-- the extra gap the kit's outside auras need there. Stacked frames carry
-- their buff run beside them, so the boss group takes the other side;
-- horizontal frames carry the buff run above and the debuff row below, so
-- the group clears whichever it sits against.
function mod.RF_KitAttach(cfg, before)
    local g = mod.RF_KitGeom(cfg.partyKitScale)
    if not g then
        return before, 0
    end
    if cfg.partyHorizontal then
        local over
        if before then
            local bm = (cfg.partyAutoResizeTrackedBuffs ~= false) and g.k or 1
            local by = cfg.partyKitBuffY or 0
            over = (mod.RF_KitAboveUnits(cfg) + ((by > 0) and by or 0)) * bm - g.host.y
        else
            -- Below: the Debuff Manager's lowest seat (base row, then its
            -- grid tiles), else one line of the debuff row.
            local low = mod._kitDmFloor
            if not low then
                local sc = mod._partyIndicatorScale or 1
                low = g.auraRow.y
                    + (cfg.partyKitDebuffY or 0) * sc
                    - (cfg.partyKitDebuffSize or KIT_DEBUFF_SIZE) * sc
            end
            over = g.host.y - low - g.boxH
        end
        return before, (over > 0) and over or 0
    end
    local modeName = mod.RF_KitBuffMode(cfg)
    if modeName == "RIGHT" and not before then
        return true, 0
    end
    if modeName == "LEFT" and before then
        return false, 0
    end
    return before, 0
end

-- Profiles: true when a profile under the running style would change the
-- latched party Frame Style (reload-gated, like the style itself).
function mod.RF_PartyKitChanged(profile)
    local wanted = profile and (profile.useClassicStyle or profile.useBlizzardStyle) and profile.partyFrameStyle == "party"
    return (mod.RF_PartyKit() and true or false) ~= (wanted and true or false)
end

local function Snap(v)
    local frame = mod.PixelSnap
    if frame then
        return frame(v)
    end
    return v
end

-- A kit spot: `spot` = { p, rel, x, y } (scaled), plus the user's offsets.
function mod.RF_KitSpot(spot, regionFrame, rel, ox, oy)
    regionFrame:ClearAllPoints()
    regionFrame:SetPoint(spot.p, rel, spot.rel, spot.x + (ox or 0), spot.y + (oy or 0))
end

-- The leader icon at its stock spot (it has no anchor closure of its own).
function mod.RF_KitLeader(stockStyle, cfg)
    local li, g = stockStyle.leaderIcon or stockStyle._leaderIcon, stockStyle.kitG
    if not (li and g and stockStyle.kitOwner) then
        return
    end
    mod.RF_KitSpot(g.lead, li, stockStyle.kitOwner, cfg and cfg.leaderIconOffsetX, cfg and cfg.leaderIconOffsetY)
end

local function Place(regionFrame, ownerFrame, region)
    if not (regionFrame and region) then
        return
    end
    regionFrame:ClearAllPoints()
    regionFrame:SetPoint("TOPLEFT", ownerFrame, "TOPLEFT", Snap(region.x), -Snap(region.y))
    regionFrame:SetSize(Snap(region.w), Snap(region.h))
end

local function SetArt(texture, a)
    if a.atlas then
        -- The retail art on every client (WoW Forever swaps the frame's
        -- atlas); sized by the seat pass, never useAtlasSize.
        CludesUI.StockAtlas(texture, a.atlas)
    else
        texture:SetTexture(a.file)
    end
end

-- Inner bevel on a Blizzard kit bar (the stock fill art bakes it in; our
-- fills are the user's own textures): black fading in from the top, the
-- bottom and both ends, inside the bar's rounded mask.
local SHADE_CLEAR = CreateColor(0, 0, 0, 0)
local SHADE_TOP = CreateColor(0, 0, 0, 0.55)
local SHADE_BOTTOM = CreateColor(0, 0, 0, 0.30)
local SHADE_END = CreateColor(0, 0, 0, 0.35)
local function MakeBevel(barFrame, mask)
    local sh = {}
    for index = 1, 4 do
        local t = barFrame:CreateTexture(nil, "OVERLAY", nil, -3)
        t:SetTexture(WHITE)
        local Pix = CludesUI.PP or CludesUI.PanelPP
        if Pix and Pix.DisablePixelSnap then
            Pix.DisablePixelSnap(t)
        end
        if mask then
            t:AddMaskTexture(mask)
        end
        sh[index] = t
    end
    -- VERTICAL runs bottom -> top, HORIZONTAL left -> right.
    sh[1]:SetGradient("VERTICAL", SHADE_CLEAR, SHADE_TOP)
    sh[2]:SetGradient("VERTICAL", SHADE_BOTTOM, SHADE_CLEAR)
    sh[3]:SetGradient("HORIZONTAL", SHADE_END, SHADE_CLEAR)
    sh[4]:SetGradient("HORIZONTAL", SHADE_CLEAR, SHADE_END)
    return sh
end
local function SeatBevel(sh, barFrame, hgt)
    if not sh then
        return
    end
    local topY, bottom, ends =
        math.max(2, math.floor(hgt * 0.2)),
        math.max(1, math.floor(hgt * 0.1)),
        math.max(2, math.floor(hgt * 0.15))
    sh[1]:ClearAllPoints()
    sh[1]:SetPoint("TOPLEFT", barFrame, "TOPLEFT", 0, 0)
    sh[1]:SetPoint("TOPRIGHT", barFrame, "TOPRIGHT", 0, 0)
    sh[1]:SetHeight(topY)
    sh[2]:ClearAllPoints()
    sh[2]:SetPoint("BOTTOMLEFT", barFrame, "BOTTOMLEFT", 0, 0)
    sh[2]:SetPoint("BOTTOMRIGHT", barFrame, "BOTTOMRIGHT", 0, 0)
    sh[2]:SetHeight(bottom)
    sh[3]:ClearAllPoints()
    sh[3]:SetPoint("TOPLEFT", barFrame, "TOPLEFT", 0, 0)
    sh[3]:SetPoint("BOTTOMLEFT", barFrame, "BOTTOMLEFT", 0, 0)
    sh[3]:SetWidth(ends)
    sh[4]:ClearAllPoints()
    sh[4]:SetPoint("TOPRIGHT", barFrame, "TOPRIGHT", 0, 0)
    sh[4]:SetPoint("BOTTOMRIGHT", barFrame, "BOTTOMRIGHT", 0, 0)
    sh[4]:SetWidth(ends)
end

local function SeatMask(mask, barFrame, region)
    if not mask then
        return
    end
    mask:ClearAllPoints()
    mask:SetPoint("TOPLEFT", barFrame, "TOPLEFT", region.mx, region.my)
    mask:SetSize(region.mw, region.mh)
end

-- Masks go on each fill OBJECT once (AddMaskTexture is additive); a texture
-- swap that replaces the object re-seats on the next pass.
local function SeatFillMasks(stockStyle)
    local hm = stockStyle.kitHMask
    if hm then
        local fillTex = stockStyle.kitHealth:GetStatusBarTexture()
        if fillTex and stockStyle._kitHFill ~= fillTex then
            local old = stockStyle._kitHFill
            if old then
                pcall(old.RemoveMaskTexture, old, hm)
            end
            fillTex:AddMaskTexture(hm)
            stockStyle._kitHFill = fillTex
        end
    end
    local pm, powerBar = stockStyle.kitPMask, stockStyle.kitPower
    if pm and powerBar then
        local fillTex = powerBar:GetStatusBarTexture()
        if fillTex and stockStyle._kitPFill ~= fillTex then
            local old = stockStyle._kitPFill
            if old then
                pcall(old.RemoveMaskTexture, old, pm)
            end
            fillTex:AddMaskTexture(pm)
            stockStyle._kitPFill = fillTex
        end
    end
end

local function SetLevel(widget, lvl)
    if widget and widget:GetFrameLevel() ~= lvl then
        widget:SetFrameLevel(lvl)
    end
end

-- Preview frames have no anchor closures: the kit pass places their
-- texts (with the settings they were painted with), role and ready check
-- itself (every refresh re-anchors them first).
local function PreviewSpots(frame, cfg, g)
    if frame._txL then
        mod.RF_TextLayout(frame, frame._txS)
    end
    if frame._roleIcon then
        mod.RF_KitSpot(g.role, frame._roleIcon, frame, cfg.roleIconOffsetX, cfg.roleIconOffsetY)
        if frame._roleIcon._roleText then
            frame._roleIcon._roleText:ClearAllPoints()
            frame._roleIcon._roleText:SetPoint(g.role.p, frame._roleIcon, g.role.p, 0, 0)
        end
    end
    if frame._readyCheck and frame.kitPortrait then
        mod.RF_KitSpot(g.rc, frame._readyCheck, frame.kitPortrait, cfg.readyCheckOffsetX, cfg.readyCheckOffsetY)
    end
end

local function Seat(ownerFrame, stockStyle, g)
    local health, powerBar = stockStyle.kitHealth, stockStyle.kitPower
    Place(stockStyle.kitHost, ownerFrame, g.host)
    Place(health, ownerFrame, g.health)
    Place(powerBar, ownerFrame, g.power)
    Place(stockStyle.kitArt, ownerFrame, g.art)
    Place(stockStyle._stAggTex, ownerFrame, g.flash)
    Place(stockStyle._kitHov, ownerFrame, g.glow)
    Place(stockStyle._kitSel, ownerFrame, g.glow)
    Place(stockStyle.kitPortrait, ownerFrame, g.portrait)
    Place(stockStyle.kitBack, ownerFrame, g.back)
    SeatMask(stockStyle.kitHMask, health, g.health)
    SeatMask(stockStyle.kitPMask, powerBar, g.power)
    SeatBevel(stockStyle.kitHShade, health, g.health.h)
    SeatBevel(stockStyle.kitPShade, powerBar, g.power.h)
end

-- Build once per owner (StyleButton for the header and self buttons, before
-- every anchor closure and the aura containers; CreatePreviewFrame for the
-- party preview). `health`/`power` are the owner's bars (ours), `bdr` its
-- stood-down border frame.
function mod.RF_KitBuild(ownerFrame, stockStyle, health, powerBar, bdr)
    if stockStyle.kit or not health then
        return
    end
    local kit = mod.RF_PartyKit()
    local K = kit and mod.RF_KITS[kit]
    if not K then
        return
    end
    local Pix = CludesUI.PP or CludesUI.PanelPP
    stockStyle.kit = kit
    stockStyle.kitOwner, stockStyle.kitHealth, stockStyle.kitPower = ownerFrame, health, powerBar
    -- Unlock mode's settings link for the party mover: the kit's size lives
    -- in Frame Scale (the Frame Width row is hidden). Latched per session.
    local map = CludesUI._ELEMENT_SETTINGS_MAP
    if map and not mod._kitUnlockLink then
        mod._kitUnlockLink = true
        map.RF_PartyFrames = {
            module = "CludesUIRaidFrames",
            page = "Party",
            sectionName = "FRAME STYLE",
            highlightText = "Frame Scale",
        }
    end
    -- Host: the visible party frame. Anchored to the owner only (never to a
    -- bar or an art piece): secure aura containers anchored to it make it
    -- protected in combat, and the bars must stay movable out of it.
    local owner = CreateFrame("Frame", nil, ownerFrame)
    owner:EnableMouse(false)
    stockStyle.kitHost = owner
    health._cuiKitRef = owner
    owner._cuiHealth = health
    -- The stood-down border frame follows the visible frame.
    if bdr then
        bdr:ClearAllPoints()
        bdr:SetAllPoints(owner)
    end

    -- Under the bars: portrait (+ the Blizzard art, Flash and glows; the
    -- vanilla plaque, Flash and glows under Classic).
    local underlay = CreateFrame("Frame", nil, ownerFrame)
    underlay:EnableMouse(false)
    stockStyle.kitUnder = underlay
    local portrait = underlay:CreateTexture(nil, "BACKGROUND", nil, 1)
    local pmask = underlay:CreateMaskTexture()
    pmask:SetAtlas("CircleMask")
    pmask:SetAllPoints(portrait)
    portrait:AddMaskTexture(pmask)
    stockStyle.kitPortrait = portrait
    local art, flash, hov, sel
    if K.artAbove then
        -- Classic: the Flash glows out from under the whole silhouette.
        flash = underlay:CreateTexture(nil, "BACKGROUND", nil, -4)
        hov = underlay:CreateTexture(nil, "BACKGROUND", nil, -3)
        sel = underlay:CreateTexture(nil, "BACKGROUND", nil, -2)
        local back = underlay:CreateTexture(nil, "BACKGROUND", nil, 2)
        back:SetColorTexture(0, 0, 0, 0.5)
        stockStyle.kitBack = back
        local over = CreateFrame("Frame", nil, ownerFrame)
        over:EnableMouse(false)
        stockStyle.kitOver = over
        art = over:CreateTexture(nil, "ARTWORK")
    else
        -- Blizzard: rim glows over the art, all under the bars.
        art = underlay:CreateTexture(nil, "ARTWORK", nil, 0)
        flash = underlay:CreateTexture(nil, "ARTWORK", nil, 1)
        hov = underlay:CreateTexture(nil, "ARTWORK", nil, 2)
        sel = underlay:CreateTexture(nil, "ARTWORK", nil, 3)
    end
    SetArt(art, K.art)
    SetArt(flash, K.flash)
    SetArt(hov, K.glow)
    SetArt(sel, K.glow)
    sel:SetVertexColor(KIT_SEL_R, KIT_SEL_G, KIT_SEL_B, 1)
    flash:Hide()
    hov:Hide()
    sel:Hide()
    if Pix and Pix.DisablePixelSnap then
        Pix.DisablePixelSnap(art)
        Pix.DisablePixelSnap(flash)
        Pix.DisablePixelSnap(hov)
        Pix.DisablePixelSnap(sel)
        Pix.DisablePixelSnap(portrait)
    end
    stockStyle.kitArt = art
    -- The stock aggro path (RF_PaintThreat -> RF_StockAggro) drives the
    -- Flash: stockHl marks stock highlights, the Flash is its aggro texture.
    stockStyle.stockHl = underlay
    stockStyle._stAggTex = flash
    stockStyle._kitHov, stockStyle._kitSel = hov, sel

    -- Blizzard: the stock rounded masks and bevel, on the bars themselves
    -- (the mana mask shapes the bar's own background too). The retail masks
    -- on every client, like the art (WoW Forever redrew these names).
    if K.health.mask then
        local hm = health:CreateMaskTexture()
        CludesUI.StockMask(hm, K.health.mask)
        stockStyle.kitHMask = hm
        if K.bevel then
            stockStyle.kitHShade = MakeBevel(health, hm)
        end
        if powerBar and K.power.mask then
            local pm = powerBar:CreateMaskTexture()
            CludesUI.StockMask(pm, K.power.mask)
            stockStyle.kitPMask = pm
            local pbg = stockStyle.powerBg or stockStyle._powerBg
            if pbg then
                pbg:AddMaskTexture(pm)
            end
            if K.bevel then
                stockStyle.kitPShade = MakeBevel(powerBar, pm)
            end
        end
    end
    mod.RF_ApplyPartyKit(ownerFrame, stockStyle, mod._scaledPartyProxy, nil, true)
end

-- The kit pass: portrait (when a unit is given), geometry (when the scale
-- changed, or `force`), frame levels and fill masks. A geometry write that
-- would touch a frame made protected in combat is deferred to combat end
-- (main file flush -> ReloadPartyFrames); the portrait is a plain paint on
-- our own texture and always runs.
function mod.RF_ApplyPartyKit(ownerFrame, stockStyle, cfg, unitToken, force)
    if not stockStyle.kit then
        return
    end
    if unitToken then
        mod.RF_KitPortrait(stockStyle, unitToken)
    end
    local g = mod.RF_KitGeom(cfg and cfg.partyKitScale)
    if not g then
        return
    end
    local health, powerBar, owner = stockStyle.kitHealth, stockStyle.kitPower, stockStyle.kitHost
    -- The pixel grid the seat pass snaps to joins the memo (a live UI-scale
    -- change re-seats on the next pass).
    local P = CludesUI.PP
    local es = ownerFrame:GetEffectiveScale()
    local pixel = ((P and P.perfect) or 0) / ((es and es > 0) and es or 1)
    local locked = InCombatLockdown()
        and (health:IsProtected() or owner:IsProtected() or (powerBar and powerBar:IsProtected()))
    if force or stockStyle.kitG ~= g or stockStyle.kitPx ~= pixel then
        if locked then
            mod._partyKitDirtyInCombat = true
        else
            Seat(ownerFrame, stockStyle, g)
            stockStyle.kitG, stockStyle.kitPx = g, pixel
            -- The spots scale with the frame: re-run what reads them.
            if stockStyle.AnchorTexts then
                stockStyle.AnchorTexts()
            end
            if stockStyle.AnchorRoleIcon then
                stockStyle.AnchorRoleIcon()
            end
            if stockStyle.AnchorReadyCheck then
                stockStyle.AnchorReadyCheck()
            end
            mod.RF_KitLeader(stockStyle, cfg)
            -- A preview frame is its own state (RF_KitBuild(f, f, ...)).
            if ownerFrame == stockStyle and cfg then
                PreviewSpots(ownerFrame, cfg, g)
            end
        end
    end
    -- Levels follow the owner (a party strata change rebuilds child levels):
    -- the bars at their creation offsets first, so the art keeps its place
    -- under (Blizzard) or over (Classic) them.
    local L = ownerFrame:GetFrameLevel()
    if health:GetFrameLevel() ~= L + 2 or (powerBar and powerBar:GetFrameLevel() ~= L + 3) then
        if locked then
            mod._partyKitDirtyInCombat = true
        else
            SetLevel(health, L + 2)
            SetLevel(powerBar, L + 3)
        end
    end
    SetLevel(stockStyle.kitUnder, L + 1)
    -- Classic art: over the bars and absorbs (health +3), tying only the
    -- absorb spark host, under the border (+8), text and auras.
    SetLevel(stockStyle.kitOver, L + 6)
    SeatFillMasks(stockStyle)
end

-- The stock portrait in the PORTRAIT section's Art Style (the portrait or
-- the class art; a model cannot take the socket's round mask), re-
-- desaturated after every paint (offline state is owned by the health-
-- background pass).
function mod.RF_KitPortrait(stockStyle, unitToken)
    local texture = stockStyle.kitPortrait
    if not texture then
        return
    end
    local p = mod._scaledPartyProxy
    if p and p.partyPortraitMode == "class" and mod.RF_PtClassArt then
        local _, classTok = UnitClass(unitToken)
        if issecretvalue(classTok) then
            classTok = nil
        end
        mod.RF_PtClassArt(texture, classTok or "WARRIOR", p.partyPortraitClassStyle or "modern")
    else
        texture:SetTexCoord(0, 1, 0, 1)
        SetPortraitTexture(texture, unitToken)
    end
    texture:SetDesaturated(stockStyle._kitDesat or false)
end

-- Options preview: the player's own portrait in the player's slot, the
-- class crest elsewhere (five copies of one face would read wrong); class
-- art per slot under that Art Style.
local CLASS_SHEET = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
function mod.RF_KitPreviewPortrait(frame, classToken, isPlayer, offline)
    local texture = frame.kitPortrait
    if not texture then
        return
    end
    local p = mod._scaledPartyProxy
    local tc = (not isPlayer) and classToken and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classToken]
    if p and p.partyPortraitMode == "class" and mod.RF_PtClassArt then
        local _, pct = UnitClass("player")
        mod.RF_PtClassArt(texture, classToken or pct or "WARRIOR", p.partyPortraitClassStyle or "modern")
    elseif tc then
        texture:SetTexture(CLASS_SHEET)
        texture:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
    else
        texture:SetTexCoord(0, 1, 0, 1)
        SetPortraitTexture(texture, "player")
    end
    texture:SetDesaturated(offline and true or false)
end

-- Hover and target: the art-tracing glow (stock has neither), hover in the
-- user's hover colour, target in the stock selection colour; target draws
-- over hover. The stood-down border frame stays clear.
function mod.RF_KitHighlight(stockStyle, bf, cfg, hover, target)
    local hov, sel = stockStyle._kitHov, stockStyle._kitSel
    if not hov then
        return
    end
    if hover then
        local color = cfg.hoverBorderColor
        hov:SetVertexColor(color and color.r or 1, color and color.g or 1, color and color.b or 1, cfg.hoverBorderAlpha or 1)
    end
    hov:SetShown(hover and true or false)
    sel:SetShown(target and true or false)
end
