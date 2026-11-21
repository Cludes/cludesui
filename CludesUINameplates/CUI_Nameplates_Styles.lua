if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CUI_Nameplates_Styles.lua
--
--  Stock styles (Blizzard and Classic art), the Forever level box, Blizzard
--  cast art, bar textures and the absorb style.
--  Reads the earlier nameplate files through ns and ns._npInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._npInternals
-- CludesUINameplates.lua or an earlier nameplate file failed to load.
if not Inner or Inner.broken then return end
Inner.broken = true

local pairs, ipairs, type = pairs, ipairs, type
local UnitIsUnit, UnitCanAttack = UnitIsUnit, UnitCanAttack
-- The core's table of the options page frame pool (CludesUI_PixelPerfect.lua
-- makes it, the options addon fills it): the builders the options preview shares
-- with the plates create through it, so a preview frame is handed back to the
-- preview's next build. A plate's parent is no pool host: a plain CreateFrame.
local Pool = CUI._Pool

local defaultSet = Inner.defaults

local p
Inner.profileSetters[#Inner.profileSetters + 1] = function(val) p = val end

-------------------------------------------------------------------------------
--  Stock styles (Global Settings > Style). Blizzard Style: the stock
--  nameplate atlases on our own plates -- bar fill + shadowed background,
--  target/focus selection ring, deselected overlay, and the stock cast bar
--  art (background, fills per cast kind, pip, interrupt shield). Classic WoW
--  UI: the flat vanilla plate -- the user's fill inside a fixed 1px black
--  edge on the health and cast bars, square full-art icons, the stock
--  dispel-type border on harmful auras; no ring, mask, panel or bevel. Every
--  CUI feature keeps working; the CUI borders and textures step aside.
--  Reload-gated per-profile flags, read only on build/restyle paths. Atlases
--  are validated once per session so a missing one leaves that piece on the
--  CUI look. ns fields (local cap).
-------------------------------------------------------------------------------
mod.NP_BLIZZ = {
    bar = "UI-HUD-CoolDownManager-Bar",
    barBg = "UI-HUD-CoolDownManager-Bar-BG",
    selected = "UI-HUD-Nameplates-Selected",
    deselected = "ui-hud-nameplates-deselected-overlay",
    castBg = "ui-castingbar-background",
    cast = "ui-castingbar-filling-standard",
    channel = "ui-castingbar-filling-channel",
    interrupted = "ui-castingbar-interrupted",
    castShieldFill = "ui-castingbar-uninterruptable",
    castPip = "ui-castingbar-pip",
    shield = "nameplates-InterruptShield",
    auraMask = "UI-HUD-CoolDownManager-Mask",
    auraRing = "UI-HUD-CoolDownManager-IconOverlay",
    -- WoW Forever variant only (atlases that client alone ships): its
    -- selection ring and the level box right of the bar.
    selYellow = "UI-HUD-CoolDownManager-Selected-yellow",
    lvlBg = "ui-hud-nameplates-levelindicator",
    lvlSel = "ui-hud-nameplates-levelindicator-rectangle-selected",
    lvlSkull = "ui-hud-nameplates-levelindicator-skull",
}
-- Classic WoW UI kit. debuffBorder: the stock debuff border for an untyped
-- debuff (the engine stamps the typed ones on the aura cells itself; our
-- hand-built icons wear this one). The rest is the vanilla nameplate border
-- art: a long window with a plate on one end (the level's on the health
-- border's right, the spell icon's on the cast border's left), drawn as
-- three pieces so the two plates keep their shape at any bar width while
-- the window between them stretches.
--
-- EVERY number below is in BAR-HEIGHT units: multiply by the bar's own
-- height. They come from measuring an in-game render of each file (the
-- copies the CDN serves differ from what the client draws, so the files
-- themselves cannot be trusted for this). The art's texcoords are its
-- opaque extent, `c1`/`c2` cut it at the window's two ends, `capL`/`capR`
-- are the pieces' widths and `reachL`/`reachR` how far the art reaches past
-- the bar. Each cap is a touch wider than its reach because the art's inner
-- rim overlaps the bar's edge, which is the vanilla look. Confirmed against
-- Blizzard's own Classic nameplate constants: the cast sheet's bar lands
-- exactly on their 20.75 / 3.5 insets in a 16-tall border.
mod.NP_CLASSIC = {
    debuffBorder = "ui-debuff-border-default-noicon",
    -- health reachL carries a +0.08 nudge over its measured 0.057: the plain
    -- end of the art is ROUNDED and our fill is a plain rectangle with no
    -- corner mask, so at the measured reach the fill's square top-left and
    -- bottom-left corners show past the curve. Pushing that end out covers
    -- them and still leaves the rim overlapping the bar's left edge. The
    -- plate end needs none of this: it is a filled box. (The cast sheet's
    -- plain end already reaches 0.26 and covers its own corners.)
    health = {
        file = "Interface\\Tooltips\\Nameplate-Border",
        l = 0.0049,
        r = 0.5261,
        t = 0.5065,
        b = 0.9610,
        c1 = 0.0195,
        c2 = 0.4137,
        capL = 0.187,
        capR = 1.440,
        reachL = 0.137,
        reachR = 1.310,
    },
    cast = {
        file = "Interface\\Tooltips\\Nameplate-Border-Castbar",
        l = 0.0081,
        r = 0.9919,
        t = 0.5065,
        b = 0.9610,
        c1 = 0.1710,
        c2 = 0.9609,
        capL = 2.086,
        capR = 0.390,
        reachL = 1.956,
        reachR = 0.260,
    },
    spark = "Interface\\CastingBar\\UI-CastingBar-Spark",
    shield = "Interface\\CastingBar\\UI-CastingBar-Small-Shield",
    skull = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull",
    top = 0.230,
    bottom = 0.229, -- the art's reach above and below the bar
    gap = 0.35, -- clear space between the two borders
    plateOffL = 0.924, -- the cast icon's centre, left of the cast bar's left edge
    plateOffR = 0.584, -- the level's centre, right of the health bar's right edge
    icon = 1.4, -- the cast icon's side, seated in its plate
    -- The level and the boss icon while their sliders sit at 0 ("follow the
    -- bar"): three quarters of what the bar's height would give, which
    -- overfilled the plate. The Level Size and Elite Icon Size sliders
    -- override each of them.
    levelFont = 0.75,
    levelIcon = 1,
    sparkSize = 3.2,
    sparkY = -0.1,
    shieldL = 2.0,
    shieldT = 1.1,
    shieldR = 1.3,
    shieldB = 1.3, -- the shield frame's reach past the cast bar
}
-- The cast icon's centre from the cast bar's LEFT, and the level's centre
-- from the health bar's RIGHT (both plates are centred on the bar's own
-- middle line).
function mod.NP_ClassicIconOffset(scale) return -mod.NP_CLASSIC.plateOffL * scale, 0 end
-- The level's and the elite icon's seat in the health border's plate: the
-- plate's own centre plus the user's own offsets. Their size scales with the
-- bar until the user sets one (0 = follow the bar).
function mod.NP_ClassicLevelOffset(scale)
    return mod.NP_CLASSIC.plateOffR * scale + ((p and p.classicLevelX) or 0), ((p and p.classicLevelY) or 0)
end
function mod.NP_ClassicSkullOffset(scale)
    return mod.NP_CLASSIC.plateOffR * scale + ((p and p.classicSkullX) or 0), ((p and p.classicSkullY) or 0)
end
function mod.NP_ClassicLevelSize(scale)
    local val = p and p.classicLevelSize
    if val and val > 0 then return val end
    return math.max(6, mod.NP_CLASSIC.levelFont * scale)
end
function mod.NP_ClassicSkullSize(scale)
    local val = p and p.classicSkullSize
    if val and val > 0 then return val end
    return mod.NP_CLASSIC.levelIcon * scale
end
-- The Classic WoW UI border's reach past the health bar's two ends, 0 on
-- every other style. The border is part of the bar as far as anything beside
-- it is concerned -- its level plate hangs well past the bar's right edge --
-- so the target arrows and every side-slot element clear this too. `k` =
-- the bar's height (nil = the enemy plates'; friendly plates pass theirs).
-- The WoW Forever variant's level box (right of the bar) is part of it the
-- same way, so its room comes back here too (ns.NP_Classic has just latched
-- the variant flag read here).
function mod.NP_ClassicBarReserve(scale)
    if not mod.NP_Classic() then return 0, mod._npForever and mod.NP_ForeverSide() or 0 end
    local C = mod.NP_CLASSIC
    scale = scale or (mod.GetHealthBarHeight and mod.GetHealthBarHeight()) or 0
    return C.health.reachL * scale, C.health.reachR * scale
end
-- WoW Forever's level box: 28 wide and 5 right of the bar (Blizzard's own
-- nameplate constants), 5 taller than it; its target and focus border
-- colours. The box art is nine-sliced with a 1-unit shadow outside its rim,
-- so at 5 taller its rim spans the bar's own rim (at Blizzard's 3 it sits a
-- unit below the bar's top rim).
mod.NP_FOREVER_LVL = { w = 28, gap = 5, pad = 5, font = 10, target = { 1, 1, 1 }, focus = { 1, 0.49, 0.039 } }
-- Whether the plates carry the box: the variant, less the profile's Show
-- Level Box opt-out (foreverHideLevelBox; nil = shown).
function mod.NP_ForeverBoxOn() return mod.NP_Forever() and not (p and p.foreverHideLevelBox) end
-- The room the box takes right of the bar (0 off the variant, and while the
-- box is off, so everything lays out as plain Blizzard Style).
function mod.NP_ForeverSide()
    if not mod.NP_ForeverBoxOn() then return 0 end
    local L = mod.NP_FOREVER_LVL
    return L.gap + L.w
end
-- One side of it ("left" | "right"), for the many places that gap a single
-- element off one edge of the bar.
function mod.NP_ClassicSide(side, key)
    local left, right = mod.NP_ClassicBarReserve(key)
    if side == "right" then return right end
    return left
end
-- The cast bar's layout under the health bar: its shift right, its width
-- over the footprint and its drop, so the two borders line up at their
-- outer edges (plate under plain end, plain end under plate) with a clear
-- gap between them. kh / kc are the two bars' heights.
function mod.NP_ClassicCastLayout(footprintW, kh, kc)
    local C = mod.NP_CLASSIC
    local lh, rh = C.health.reachL * kh, C.health.reachR * kh
    local lc, rc = C.cast.reachL * kc, C.cast.reachR * kc
    return lc - lh, footprintW + (lh + rh) - (lc + rc), -((C.bottom + C.gap) * kh + C.top * kc)
end
-- Three pieces of a sheet on `host` (its art cut at the window's two ends);
-- created once, seated by NP_SeatClassicBorder.
function mod.NP_ClassicBorderPieces(owner, sheet)
    local p = { sheet = sheet }
    for index = 1, 3 do
        local tex = owner:CreateTexture(nil, "OVERLAY", nil, 0)
        tex:SetTexture(sheet.file)
        tex:SetSnapToPixelGrid(false)
        tex:SetTexelSnappingBias(0)
        p[index] = tex
    end
    p[1]:SetTexCoord(sheet.l, sheet.c1, sheet.t, sheet.b)
    p[2]:SetTexCoord(sheet.c1, sheet.c2, sheet.t, sheet.b)
    p[3]:SetTexCoord(sheet.c2, sheet.r, sheet.t, sheet.b)
    return p
end
-- Seats the pieces round `bar` at k (the bar's height): both plates keep
-- the art's own proportion, the window stretches between them. Memoized;
-- every layout pass may call it.
function mod.NP_SeatClassicBorder(border, barFrame, scale)
    if border._k == scale and border._bar == barFrame then return end
    border._k, border._bar = scale, barFrame
    local C = mod.NP_CLASSIC
    local sheet = border.sheet
    local left, right = sheet.reachL * scale, sheet.reachR * scale
    local t, b = C.top * scale, C.bottom * scale
    for index = 1, 3 do
        border[index]:ClearAllPoints()
    end
    border[1]:SetPoint("TOPLEFT", barFrame, "TOPLEFT", -left, t)
    border[1]:SetPoint("BOTTOMLEFT", barFrame, "BOTTOMLEFT", -left, -b)
    border[1]:SetWidth(sheet.capL * scale)
    border[3]:SetPoint("TOPRIGHT", barFrame, "TOPRIGHT", right, t)
    border[3]:SetPoint("BOTTOMRIGHT", barFrame, "BOTTOMRIGHT", right, -b)
    border[3]:SetWidth(sheet.capR * scale)
    border[2]:SetPoint("TOPLEFT", border[1], "TOPRIGHT", 0, 0)
    border[2]:SetPoint("BOTTOMRIGHT", border[3], "BOTTOMLEFT", 0, 0)
end
-- The vanilla health border round a plate's health bar (enemy and friendly
-- plates alike) and, where the plate has a text frame, the unit's level in
-- the border's plate. The pieces ride a host above the fill, the absorbs
-- and the class icon and under the texts; a height change re-seats them.
function mod.NP_ApplyClassicHealthArt(backing, hgt)
    local health = backing and backing.health
    if not health then return end
    local C = mod.NP_CLASSIC
    local owner = backing._classicHealthHost
    if not owner then
        owner = CreateFrame("Frame", nil, health)
        owner:SetAllPoints(health)
        owner:EnableMouse(false)
        backing._classicHealthHost = owner
        backing._classicHealthArt = mod.NP_ClassicBorderPieces(owner, C.health)
    end
    owner:SetFrameLevel(health:GetFrameLevel() + 6)
    local k = hgt or health:GetHeight()
    mod.NP_SeatClassicBorder(backing._classicHealthArt, health, k)
    -- The art carries a level plate, so it must never render empty: a plate
    -- with no text frame of its own (the friendly plates) gets a host here,
    -- one level above the border art.
    local tf = backing.healthTextFrame
    if not tf then
        tf = backing._classicLevelHost
        if not tf then
            tf = CreateFrame("Frame", nil, health)
            tf:SetAllPoints(health)
            tf:EnableMouse(false)
            backing._classicLevelHost = tf
        end
        tf:SetFrameLevel(owner:GetFrameLevel() + 1)
    end
    local fontStr, sk = backing._classicLevel, backing._classicSkull
    if not fontStr then
        fontStr = tf:CreateFontString(nil, "OVERLAY")
        fontStr:SetJustifyH("CENTER")
        backing._classicLevel = fontStr
        sk = tf:CreateTexture(nil, "OVERLAY")
        sk:SetTexture(C.skull)
        sk:Hide()
        backing._classicSkull = sk
    end
    -- The user's nameplate font, outline and shadow, like every other text
    -- on the plate (and it guarantees a font before any SetText).
    mod.SetFSFont(fontStr, mod.NP_ClassicLevelSize(k))
    local lx, ly = mod.NP_ClassicLevelOffset(k)
    fontStr:ClearAllPoints()
    fontStr:SetPoint("CENTER", health, "RIGHT", lx, ly)
    local sx, sy = mod.NP_ClassicSkullOffset(k)
    local ss = mod.NP_ClassicSkullSize(k)
    sk:ClearAllPoints()
    sk:SetSize(ss, ss)
    sk:SetPoint("CENTER", health, "RIGHT", sx, sy)
    mod.NP_UpdateClassicLevel(backing)
end
-- The level in the health border's plate: the effective level in its
-- difficulty colour, the skull for a boss, "??" for a level the client keeps
-- secret. Every unit read is treated as possibly secret.
function mod.NP_UpdateClassicLevel(backing)
    local fontStr, sk = backing._classicLevel, backing._classicSkull
    if not fontStr then return end
    local unitToken = backing.unit
    if not unitToken or not UnitExists(unitToken) then
        fontStr:Hide()
        sk:Hide()
        return
    end
    local lvl = UnitEffectiveLevel(unitToken)
    local secret = issecretvalue and issecretvalue(lvl)
    if not secret and type(lvl) == "number" and lvl < 0 then
        fontStr:Hide()
        sk:Show()
        return
    end
    sk:Hide()
    fontStr:SetText(mod.GetUnitLevelText(unitToken))
    -- The stock yellow, and the difficulty colour only where difficulty means
    -- something: a unit you cannot attack is never colour-ranked.
    local red, green, blue = 1, 0.82, 0
    local canAttack = UnitCanAttack("player", unitToken)
    if issecretvalue and issecretvalue(canAttack) then canAttack = false end
    if canAttack and not secret and C_PlayerInfo and C_PlayerInfo.GetContentDifficultyCreatureForPlayer then
        local diff = C_PlayerInfo.GetContentDifficultyCreatureForPlayer(unitToken)
        if not (issecretvalue and issecretvalue(diff)) and GetDifficultyColor then
            local color = GetDifficultyColor(diff)
            if color then
                red, green, blue = color.r, color.g, color.b
            end
        end
    end
    fontStr:SetTextColor(red, green, blue, 1)
    fontStr:Show()
end
-- The vanilla cast border round a plate's cast bar, with the spell icon
-- lifted above it into its plate, the vanilla spark on the fill's edge and
-- the vanilla shield frame round the bar for an uninterruptible cast. The
-- pieces ride a host above the fill and the background; LayoutCastBar calls
-- this on every re-layout (memo in the seat, the per-height work behind
-- its own memo).
function mod.NP_ApplyClassicCastArt(backing, castH)
    local cast = backing and backing.cast
    if not cast then return end
    local C = mod.NP_CLASSIC
    local k = castH or cast:GetHeight()
    local owner = backing._classicCastHost
    if not owner then
        owner = CreateFrame("Frame", nil, cast)
        owner:SetAllPoints(cast)
        owner:EnableMouse(false)
        backing._classicCastHost = owner
        backing._classicCastArt = mod.NP_ClassicBorderPieces(owner, C.cast)
    end
    owner:SetFrameLevel(cast:GetFrameLevel() + 2)
    mod.NP_SeatClassicBorder(backing._classicCastArt, cast, k)
    -- The pool builds the cast bar BEFORE its icon frame, spark, shield and
    -- seam line, and lays the bar out in between, so the first pass through
    -- here has none of them. Stamping the memo then would claim this height
    -- as done and the art below would never be applied to any of them: wait
    -- until they all exist.
    if
        not (
            backing.castIconFrame
            and backing.castSpark
            and backing.castShield
            and backing.castShieldFrame
            and backing.castLeftBorder
        )
    then
        return
    end
    if backing._classicCastK == k then return end
    backing._classicCastK = k
    -- Above the border art AND above the health bar, as the pool intended:
    -- the cast bar is a plain child of the plate, so the host's own level
    -- alone would drop the icon below the health bar rather than lift it.
    backing.castIconFrame:SetFrameLevel(
        math.max(owner:GetFrameLevel() + 1, backing.health:GetFrameLevel() + 1)
    )
    mod.NP_ClassicSpark(backing, k)
    backing.castShield:SetTexture(C.shield)
    backing.castShieldFrame:ClearAllPoints()
    backing.castShieldFrame:SetPoint("TOPLEFT", cast, "TOPLEFT", -C.shieldL * k, C.shieldT * k)
    backing.castShieldFrame:SetPoint("BOTTOMRIGHT", cast, "BOTTOMRIGHT", C.shieldR * k, -C.shieldB * k)
    backing.castLeftBorder:Hide()
end
-- The vanilla spark: a square on the fill's leading edge, not a bar-tall
-- sliver. Every caller that sizes the spark for the CUI look routes here
-- under Classic WoW UI instead, so none of them can squash it back.
function mod.NP_ClassicSpark(backing, scale)
    local cast, spark = backing and backing.cast, backing and backing.castSpark
    if not (cast and spark) then return end
    local C = mod.NP_CLASSIC
    spark:SetTexture(C.spark)
    spark:SetSize(C.sparkSize * scale, C.sparkSize * scale)
    spark:ClearAllPoints()
    spark:SetPoint("CENTER", cast:GetStatusBarTexture(), "RIGHT", 0, C.sparkY * scale)
end
-- One chokepoint for "size the spark to this cast height": the square under
-- Classic WoW UI, the bar-tall sliver otherwise.
function mod.NP_SetSparkHeight(backing, castH)
    if mod.NP_Classic() then
        mod.NP_ClassicSpark(backing, castH)
        return
    end
    if backing and backing.castSpark then backing.castSpark:SetHeight(castH) end
end
mod._npAtlasMemo = {}
-- The style this module RENDERS this session -- "cui" | "blizzard" |
-- "classic" -- read from the profile once (first call with a profile present)
-- and latched: a live profile switch never flips the look under the one-time
-- art setup; the profile system prompts for a reload instead. Both flags set
-- resolves as classic.
function mod.NP_Style()
    local val = mod._npStyle
    if val == nil then
        if not p then return "cui" end
        val = (p.useClassicStyle and "classic") or (p.useBlizzardStyle and "blizzard") or "cui"
        mod._npStyle = val
        -- The WoW Forever variant of Blizzard Style, latched with it: the
        -- Forever client, Blizzard Style, and the sibling useForeverStyle
        -- flag set together with the Blizzard one.
        mod._npForever = val == "blizzard" and CUI.IS_FOREVER == true and p.useForeverStyle == true
    end
    return val
end
-- Stock-art mode: true for both stock styles (the geometry, gating and
-- chrome they share -- zoom 0 icons, no CUI icon borders, no custom border).
function mod.NP_Blizz() return mod.NP_Style() ~= "cui" end
function mod.NP_Classic() return mod.NP_Style() == "classic" end
-- WoW Forever variant: NP_Style() still reads "blizzard" (every stock site
-- stays as it is); this gates the Forever-only pieces. False off Forever.
function mod.NP_Forever()
    if mod._npStyle == nil then mod.NP_Style() end
    return mod._npForever == true
end
-- Stock kit frame art on a plain Texture (never a mask or a status bar
-- fill): the retail art on every client (CludesUI.StockAtlas), the
-- client's own under the WoW Forever variant. Each texture is painted once
-- per session.
function mod.NP_StockAtlas(texture, name)
    if mod.NP_Forever() then return texture:SetAtlas(name) end
    return CUI.StockAtlas(texture, name)
end
function mod.NP_AtlasOK(name)
    local memo = mod._npAtlasMemo
    local val = memo[name]
    if val == nil then
        val = (name and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)) and true
            or false
        memo[name] = val
    end
    return val
end
-- Inner shadow on the health bar: the stock fill art bakes this bevel in,
-- and under the style the fill is the user's own texture, so it is drawn
-- here: four regions of the bar at OVERLAY -3 (above the fill, under the
-- hash line, the overlays and the ring), created once, re-sized per pass.
mod._npShadeClear = CreateColor(0, 0, 0, 0)
mod._npShadeTop = CreateColor(0, 0, 0, 0.55)
mod._npShadeBottom = CreateColor(0, 0, 0, 0.30)
mod._npShadeEnd = CreateColor(0, 0, 0, 0.35)
function mod.NP_BlizzBarShadow(barFrame, hgt, mask)
    local sh = barFrame._blizzShadow
    if not sh then
        sh = {}
        barFrame._blizzShadow = sh
        for index = 1, 4 do
            local texture = barFrame:CreateTexture(nil, "OVERLAY", nil, -3)
            texture:SetTexture("Interface\\Buttons\\WHITE8X8")
            if texture.SetSnapToPixelGrid then
                texture:SetSnapToPixelGrid(false)
                texture:SetTexelSnappingBias(0)
            end
            sh[index] = texture
        end
        -- VERTICAL runs bottom -> top, HORIZONTAL left -> right.
        sh[1]:SetGradient("VERTICAL", mod._npShadeClear, mod._npShadeTop)
        sh[2]:SetGradient("VERTICAL", mod._npShadeBottom, mod._npShadeClear)
        sh[3]:SetGradient("HORIZONTAL", mod._npShadeEnd, mod._npShadeClear)
        sh[4]:SetGradient("HORIZONTAL", mod._npShadeClear, mod._npShadeEnd)
    end
    hgt = hgt or barFrame:GetHeight() or 10
    -- The strips hang off the bar's edges, so only the height sizes them:
    -- one compare per plate show once laid out (plates show constantly).
    if sh._h ~= hgt then
        sh._h = hgt
        local topY, bottom, ends =
            math.max(2, math.floor(hgt * 0.2)),
            math.max(1, math.floor(hgt * 0.1)),
            math.max(2, math.floor(hgt * 0.15))
        -- The bottom strip sits on the fill's bottom edge (ns.NP_SeatBarMask).
        local lift = mod.NP_Forever() and mod.NP_FOREVER_FILL_LIFT or 0
        sh[1]:ClearAllPoints()
        sh[1]:SetPoint("TOPLEFT", barFrame, "TOPLEFT", 0, 0)
        sh[1]:SetPoint("TOPRIGHT", barFrame, "TOPRIGHT", 0, 0)
        sh[1]:SetHeight(topY)
        sh[2]:ClearAllPoints()
        sh[2]:SetPoint("BOTTOMLEFT", barFrame, "BOTTOMLEFT", 0, lift)
        sh[2]:SetPoint("BOTTOMRIGHT", barFrame, "BOTTOMRIGHT", 0, lift)
        sh[2]:SetHeight(bottom)
        sh[3]:ClearAllPoints()
        sh[3]:SetPoint("TOPLEFT", barFrame, "TOPLEFT", 0, 0)
        sh[3]:SetPoint("BOTTOMLEFT", barFrame, "BOTTOMLEFT", 0, 0)
        sh[3]:SetWidth(ends)
        sh[4]:ClearAllPoints()
        sh[4]:SetPoint("TOPRIGHT", barFrame, "TOPRIGHT", 0, 0)
        sh[4]:SetPoint("BOTTOMRIGHT", barFrame, "BOTTOMRIGHT", 0, 0)
        sh[4]:SetWidth(ends)
        for index = 1, 4 do
            sh[index]:Show()
        end
    end
    -- Bar-shape mask, seated once per mask object.
    if mask and sh._mask ~= mask then
        for index = 1, 4 do
            if sh._mask then pcall(sh[index].RemoveMaskTexture, sh[index], sh._mask) end
            sh[index]:AddMaskTexture(mask)
        end
        sh._mask = mask
    end
end
-- The stock fill-footprint mask on a health bar: the whole bar, except under
-- the WoW Forever variant, whose background art's bottom rim reaches a unit
-- up over the bar's bottom edge (field-measured), so there the mask stops
-- that far up and the fill meets the rim. Shared with the options preview.
mod.NP_FOREVER_FILL_LIFT = 1
function mod.NP_SeatBarMask(mask, health)
    mask:ClearAllPoints()
    if mod.NP_Forever() then
        mask:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
        mask:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, mod.NP_FOREVER_FILL_LIFT)
    else
        mask:SetAllPoints(health)
    end
end
-- Health bar: the stock shadowed background hugging the bar the way the
-- stock plate anchors it, plus the bar's inner shadow. The fill keeps the
-- user's own Bar Texture (the stock fill art is pre-coloured and darkened
-- every colour rule), so colours, textures and opacity render as on the
-- CUI look.
function mod.NP_ApplyBlizzBarArt(backing)
    local health = backing.health
    local B = mod.NP_BLIZZ
    local backdrop = backing.healthBG
    if backdrop and not backing._blizzBarBg and mod.NP_AtlasOK(B.barBg) then
        backing._blizzBarBg = true
        backdrop:SetAtlas(B.barBg)
        backdrop:SetVertexColor(1, 1, 1, 1)
        backdrop:ClearAllPoints()
        backdrop:SetPoint("TOPLEFT", health, "TOPLEFT", -2, 3)
        backdrop:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 6, -6)
    end
    -- The stock fill art's own footprint (rounded, soft-edged, inside the
    -- background's rim) as a mask over the bar for the fill, the highlights
    -- and the shadow: the user's texture sits inside the rim exactly as the
    -- stock fill does instead of painting over it. Seated per texture object
    -- (a status bar texture path swap mints a new fill object).
    local mask = backing._blizzBarMask
    if not mask and mod.NP_AtlasOK(B.bar) then
        mask = health:CreateMaskTexture()
        mask:SetAtlas(B.bar)
        mod.NP_SeatBarMask(mask, health)
        backing._blizzBarMask = mask
    end
    if mask then
        local fillTex = health:GetStatusBarTexture()
        if fillTex and backing._blizzMaskedFill ~= fillTex then
            pcall(fillTex.RemoveMaskTexture, fillTex, mask)
            fillTex:AddMaskTexture(mask)
            backing._blizzMaskedFill = fillTex
        end
        if backing.highlight and not backing._blizzMaskedHover then
            backing.highlight:AddMaskTexture(mask)
            backing._blizzMaskedHover = true
        end
        if backing.targetHighlight and not backing._blizzMaskedTarget then
            backing.targetHighlight:AddMaskTexture(mask)
            backing._blizzMaskedTarget = true
        end
        if backing.castTintInt and not backing._blizzMaskedCastTints then
            backing.castTintInt:AddMaskTexture(mask)
            backing.castTintUnint:AddMaskTexture(mask)
            backing._blizzMaskedCastTints = true
        end
    end
    mod.NP_BlizzBarShadow(health, nil, mask)
end
-- Hand-built aura icons (the cast-lockout icon, the options preview mocks):
-- the stock nameplate aura item look -- the rounded mask over the icon art
-- and the ring overlay hung 6px by 5px past a 25px item, scaled to the
-- frame. Our own frames, so the state lives on them: one-time structure,
-- size-memoized ring geometry. The engine cells get the same look through
-- AuraKit's blizzRoundArt lane (CUI_Nameplates_AuraContainers BuildNPStyle).
function mod.NP_ApplyBlizzIconArt(widget, iconTex, wid, hgt)
    if not (widget and iconTex) then return end
    local B = mod.NP_BLIZZ
    if not (mod.NP_AtlasOK(B.auraMask) and mod.NP_AtlasOK(B.auraRing)) then return end
    local ring = widget._blizzIconRing
    if not ring then
        local mask = widget:CreateMaskTexture()
        mask:SetAtlas(B.auraMask)
        mask:SetAllPoints(widget)
        iconTex:AddMaskTexture(mask)
        widget._blizzIconMask = mask
        ring = widget:CreateTexture(nil, "OVERLAY", nil, 5)
        mod.NP_StockAtlas(ring, B.auraRing)
        ring:SetSnapToPixelGrid(false)
        ring:SetTexelSnappingBias(0)
        widget._blizzIconRing = ring
    end
    wid = wid or widget:GetWidth()
    hgt = hgt or widget:GetHeight()
    if widget._blizzIconW ~= wid or widget._blizzIconH ~= hgt then
        widget._blizzIconW, widget._blizzIconH = wid, hgt
        ring:ClearAllPoints()
        ring:SetPoint("TOPLEFT", widget, "TOPLEFT", -wid * 0.24, hgt * 0.2)
        ring:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", wid * 0.24, -hgt * 0.2)
    end
end
-- Hand-built harmful aura icons under Classic WoW UI (the cast-lockout icon,
-- the options preview mocks): the stock debuff border hung a sixth of the
-- icon past each edge, as the engine draws it round the aura cells, over the
-- square full-art icon. The border sits on a child frame two levels above
-- its host so it draws over the host's cooldown swipe (a child Cooldown
-- renders above every region of its parent). Our own frames, so the state
-- lives on them: one-time structure, size-memoized geometry. The engine
-- cells get theirs through AuraKit's blizzBorder lane
-- (CUI_Nameplates_AuraContainers BuildNPStyle).
function mod.NP_ApplyClassicIconArt(widget, wid, hgt)
    if not widget then return end
    local atlas = mod.NP_CLASSIC.debuffBorder
    if not mod.NP_AtlasOK(atlas) then return end
    local owner = widget._classicIconHost
    local border = widget._classicIconBorder
    if not border then
        owner = Pool.CreateFrame("Frame", nil, widget)
        owner:SetAllPoints(widget)
        owner:EnableMouse(false)
        border = owner:CreateTexture(nil, "OVERLAY", nil, 5)
        border:SetAtlas(atlas)
        border:SetSnapToPixelGrid(false)
        border:SetTexelSnappingBias(0)
        widget._classicIconHost = owner
        widget._classicIconBorder = border
    end
    -- Re-asserted each pass: the host follows any relevel of its frame.
    owner:SetFrameLevel(widget:GetFrameLevel() + 2)
    wid = wid or widget:GetWidth()
    hgt = hgt or widget:GetHeight()
    if widget._classicIconW ~= wid or widget._classicIconH ~= hgt then
        widget._classicIconW, widget._classicIconH = wid, hgt
        border:ClearAllPoints()
        border:SetPoint("TOPLEFT", widget, "TOPLEFT", -wid / 6, hgt / 6)
        border:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", wid / 6, -hgt / 6)
    end
end
-- Target / focus selection ring and the deselected overlay every other plate
-- carries. Called from the target/focus change paths (never per tick);
-- isTarget is passed by callers that already resolved it.
function mod.NP_ApplyBlizzSelection(backing, isTarget)
    local health = backing and backing.health
    if not health or not backing.unit then return end
    local B = mod.NP_BLIZZ
    local sel, desel = backing._blizzSelected, backing._blizzDeselected
    if not sel then
        local fv = mod.NP_Forever() and mod.NP_AtlasOK(B.selYellow)
        if not ((fv or mod.NP_AtlasOK(B.selected)) and mod.NP_AtlasOK(B.deselected)) then return end
        local backdrop = backing.healthBG or health
        sel = health:CreateTexture(nil, "OVERLAY", nil, 5)
        if fv then
            -- WoW Forever's ring: a thin yellow outline hung off the
            -- background art's corners, as that client's own plates.
            sel:SetAtlas(B.selYellow)
            sel:SetPoint("TOPLEFT", backdrop, "TOPLEFT", -3, 2)
            sel:SetPoint("BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", 0, 2)
        else
            sel:SetAtlas(B.selected)
            sel:SetPoint("TOPLEFT", backdrop, "TOPLEFT", -1, 1)
            sel:SetPoint("BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", -3, 3)
        end
        sel:Hide()
        backing._blizzSelected = sel
        desel = health:CreateTexture(nil, "OVERLAY", nil, 4)
        desel:SetAtlas(B.deselected)
        desel:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 1)
        desel:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, -1)
        backing._blizzDeselected = desel
    end
    if isTarget == nil then isTarget = UnitIsUnit(backing.unit, "target") end
    local isFocus = not isTarget and UnitIsUnit(backing.unit, "focus")
    -- State memo: a plate show with the same selection state repaints nothing.
    local status = (isTarget and "target") or (isFocus and "focus") or false
    if backing._blizzSelState == status then return end
    backing._blizzSelState = status
    -- WoW Forever: the level box's own border follows the same state.
    if backing._fvLevelBox then mod.NP_ForeverLevelSel(backing) end
    if isTarget or isFocus then
        local c
        if isTarget then
            c = NAMEPLATE_BORDER_TARGET_COLOR
        else
            c = NAMEPLATE_BORDER_FOCUS_TARGET_COLOR
        end
        if c and c.r then
            sel:SetVertexColor(c.r, c.g, c.b)
        elseif isTarget then
            sel:SetVertexColor(1, 1, 1)
        else
            sel:SetVertexColor(1, 0.8, 0)
        end
        sel:Show()
        desel:Hide()
    else
        sel:Hide()
        desel:Show()
    end
end

-------------------------------------------------------------------------------
--  WoW Forever variant of Blizzard Style (the Forever client only, latched by
--  ns.NP_Forever): the level box right of the health bar, as that client's
--  own plates draw it -- a bronze-rimmed box with the unit's level in its
--  difficulty colour, a skull for a boss, and a border while the unit is your
--  target or focus. Built only under the variant; every call site tests the
--  latch or the box, so the other looks never create or touch it.
-------------------------------------------------------------------------------
-- The level's font size: Blizzard's 10, smaller only in a box too short for it.
function mod.NP_ForeverLevelFont(boxH)
    return math.min(mod.NP_FOREVER_LVL.font, math.max(6, math.floor(boxH * 0.625 + 0.5)))
end
-- The box's frame on a health bar (one of our own frames): the rim, the
-- level text (no font yet: the caller sets one before any SetText), the
-- hidden skull and the hidden selection border (nil when the client lacks
-- its atlas). nil when the client lacks the box art. Shared with the options
-- preview; the caller sizes it.
function mod.NP_BuildForeverLevelBox(health)
    local B, L = mod.NP_BLIZZ, mod.NP_FOREVER_LVL
    if not mod.NP_AtlasOK(B.lvlBg) then return nil end
    local box = Pool.CreateFrame("Frame", nil, health)
    box:EnableMouse(false)
    box:SetFrameLevel(health:GetFrameLevel() + 6)
    -- As the stock plate hangs it: L.pad taller than the bar, 3 of it above.
    box:SetPoint("LEFT", health, "RIGHT", L.gap, 0.5)
    local backdrop = box:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAtlas(B.lvlBg)
    backdrop:SetAllPoints(box)
    local fontStr = box:CreateFontString(nil, "OVERLAY")
    fontStr:SetJustifyH("CENTER")
    fontStr:SetPoint("CENTER", box, "CENTER", 0, 0)
    box._fs = fontStr
    local sk = box:CreateTexture(nil, "OVERLAY")
    if mod.NP_AtlasOK(B.lvlSkull) then sk:SetAtlas(B.lvlSkull) end
    sk:SetPoint("CENTER", box, "CENTER", 0, 0)
    sk:Hide()
    box._skull = sk
    if mod.NP_AtlasOK(B.lvlSel) then
        -- Where the stock plate hangs it (3 past the box's top and 4 past its
        -- bottom, so 6 past the bar's each way), level with the bar's own
        -- selection ring.
        local sel = box:CreateTexture(nil, "OVERLAY", nil, 1)
        sel:SetAtlas(B.lvlSel)
        sel:SetPoint("TOPLEFT", box, "TOPLEFT", -3, 3)
        sel:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 3, -4)
        sel:Hide()
        box._sel = sel
    end
    return box
end
-- Builds the box once per plate, then sizes it to the bar's height `h` (nil
-- = the bar's own) and paints the plate's unit. Runs from the plate's border
-- pass and size changes. With Show Level Box off, a built box is parked
-- (hidden, off the field every box path tests) for a switch back.
function mod.NP_ApplyForeverLevelBox(backing, hgt)
    local health = backing and backing.health
    if not health then return end
    local box = backing._fvLevelBox
    if p and p.foreverHideLevelBox then
        if box then
            box:Hide()
            backing._fvLevelBox, backing._fvLevelBoxSpare = nil, box
        end
        return
    end
    local L = mod.NP_FOREVER_LVL
    if not box then
        box = backing._fvLevelBoxSpare or mod.NP_BuildForeverLevelBox(health)
        if not box then return end
        backing._fvLevelBox, backing._fvLevelBoxSpare = box, nil
        -- The selection state may already be set on this plate.
        mod.NP_ForeverLevelSel(backing)
    end
    box:SetFrameLevel(health:GetFrameLevel() + 6)
    local bh = (hgt or health:GetHeight()) + L.pad
    if box._h ~= bh then
        box._h = bh
        box:SetSize(L.w, bh)
        -- The stock skull size (the bar's height + 3).
        box._skull:SetSize(bh - 2, bh - 2)
    end
    -- The user's nameplate font and outline, like every other plate text
    -- (and it guarantees a font before any SetText).
    mod.SetFSFont(box._fs, mod.NP_ForeverLevelFont(bh))
    mod.NP_UpdateForeverLevel(backing)
end
-- The unit's level in the box: its difficulty colour against yours when you
-- can attack it, else the non-attackable gold; the skull for a level the
-- client hides (a boss). No box on a game object. Every unit read is treated
-- as possibly secret: a secret level is shown as it comes, in the gold.
function mod.NP_UpdateForeverLevel(backing)
    local box = backing._fvLevelBox
    if not box then return end
    local unitToken = backing.unit
    if not unitToken or not UnitExists(unitToken) then
        box:Hide()
        return
    end
    local off = UnitIsGameObject(unitToken)
    if issecretvalue and issecretvalue(off) then off = false end
    if off then
        box:Hide()
        return
    end
    local fontStr, sk = box._fs, box._skull
    local lvl = UnitEffectiveLevel(unitToken)
    local secret = issecretvalue and issecretvalue(lvl)
    if not secret and (type(lvl) ~= "number" or lvl <= 0) then
        fontStr:Hide()
        sk:Show()
    else
        sk:Hide()
        local red, green, blue
        if not secret then
            red, green, blue = CUI.GetLevelColor(unitToken, lvl)
        end
        if not red then
            red, green, blue = 1, 0.82, 0
        end
        fontStr:SetText(lvl)
        fontStr:SetTextColor(red, green, blue, 1)
        fontStr:Show()
    end
    box:Show()
end
-- The box's border for the plate's selection state (the one
-- ns.NP_ApplyBlizzSelection memoizes): white for the target, orange for the
-- focus, hidden otherwise.
function mod.NP_ForeverLevelSel(backing)
    local box = backing._fvLevelBox
    local sel = box and box._sel
    if not sel then return end
    local status, L = backing._blizzSelState, mod.NP_FOREVER_LVL
    local c = (status == "target" and L.target) or (status == "focus" and L.focus) or nil
    if c then
        sel:SetVertexColor(c[1], c[2], c[3])
        sel:Show()
    else
        sel:Hide()
    end
end
-- Every enemy plate's box, for a change in the player's own level or
-- faction (only attackable units are colour-ranked, and the friendly plates
-- never carry one).
function mod.NP_ForeverSweepLevels()
    for _, pl in pairs(mod.plates) do
        if pl._fvLevelBox then mod.NP_UpdateForeverLevel(pl) end
    end
end
-- Level edges the plates' own events do not carry: a unit's level and the
-- player's own (every difficulty colour moves with it); a unit's faction
-- rides the shared faction dispatch. Its frame is born in this main chunk,
-- so the events bill to this module, and is armed only while the variant's
-- box shows: enable arms it, and every full settings refresh re-checks it
-- (Show Level Box is per profile). Returns true when the state flipped.
if CUI.IS_FOREVER == true then mod._npFvLevelEv = CreateFrame("Frame") end
function mod.NP_ForeverWatchLevels()
    local frame = mod._npFvLevelEv
    if not frame then return false end
    local enabled = mod.NP_ForeverBoxOn()
    if enabled == (mod._npFvLevelArmed == true) then return false end
    mod._npFvLevelArmed = enabled
    if not enabled then
        frame:UnregisterAllEvents()
        return true
    end
    frame:RegisterEvent("UNIT_LEVEL")
    frame:RegisterEvent("PLAYER_LEVEL_CHANGED")
    if frame:GetScript("OnEvent") then return true end
    frame:SetScript("OnEvent", function(_, evt, unitToken)
        if evt == "PLAYER_LEVEL_CHANGED" then
            mod.NP_ForeverSweepLevels()
            return
        end
        -- The player's own UNIT_LEVEL arrives with PLAYER_LEVEL_CHANGED
        -- (one sweep for the pair).
        if not unitToken or unitToken == "player" then return end
        local pl = mod.plates[unitToken] or (mod.friendlyPlates and mod.friendlyPlates[unitToken])
        if pl and pl._fvLevelBox then mod.NP_UpdateForeverLevel(pl) end
    end)
    return true
end
-- Cast fill per cast kind ("cast" | "channel" | "interrupted"); one field test
-- when the style is off, memoized per plate.
function mod.NP_SetBlizzCastFill(backing, kind)
    if not backing._blizzCastArt then return end
    kind = kind or "cast"
    if backing._blizzCastKind == kind then return end
    local atlas = mod.NP_BLIZZ[kind]
    if not mod.NP_AtlasOK(atlas) then return end
    backing._blizzCastKind = kind
    backing.cast:GetStatusBarTexture():SetAtlas(atlas)
end
-- Cast bar: stock background, fills, pip and shield; the uninterruptible
-- overlay becomes the stock grey fill art (still shown through the same
-- SetAlphaFromBoolean gate).
function mod.NP_ApplyBlizzCastArt(backing)
    local cast = backing.cast
    local B = mod.NP_BLIZZ
    -- The fill object and the overlay art are seated once per plate (nothing
    -- else touches them under the style); every later show only follows the
    -- cast kind, memoized in NP_SetBlizzCastFill.
    if not backing._blizzCastArt then
        cast:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        backing._blizzCastArt = true
        backing._blizzCastKind = nil
        if backing.castBarOverlay then
            backing.castBarOverlay:SetTexture("Interface\\Buttons\\WHITE8x8")
            if mod.NP_AtlasOK(B.castShieldFill) then
                -- Bar textures (this fill and the background below) take
                -- the retail art under Blizzard Style, WoW Forever included.
                CUI.StockAtlas(backing.castBarOverlay, B.castShieldFill)
                -- The overlay is the grey fill art: the cast path paints it white.
                backing._blizzShieldFill = true
            end
        end
    end
    mod.NP_SetBlizzCastFill(backing, backing.isCasting and backing._blizzCastLastKind or "cast")
    if backing._blizzCastChrome then return end
    backing._blizzCastChrome = true
    if backing.castBG and mod.NP_AtlasOK(B.castBg) then
        CUI.StockAtlas(backing.castBG, B.castBg)
        backing.castBG:SetVertexColor(1, 1, 1, 1)
        backing.castBG:ClearAllPoints()
        backing.castBG:SetPoint("TOPLEFT", cast, "TOPLEFT", 1, 0)
        backing.castBG:SetPoint("BOTTOMRIGHT", cast, "BOTTOMRIGHT", -1, 0)
    end
    if backing.castSpark and mod.NP_AtlasOK(B.castPip) then
        backing.castSpark:SetAtlas(B.castPip)
        backing.castSpark:SetWidth(4)
    end
    if backing.castShield and mod.NP_AtlasOK(B.shield) then backing.castShield:SetAtlas(B.shield) end
    if backing.castLeftBorder then backing.castLeftBorder:Hide() end
    if backing.castIcon then backing.castIcon:SetTexCoord(0, 1, 0, 1) end
end

-- Health bar texture overlay tables (stored on ns to avoid local count pressure)
mod.healthBarTextures, mod.healthBarTextureNames, mod.healthBarTextureOrder =
    CUI.BuildBarTextureTables(true)
-- Extra entry, second in the list: the game's own bar fill, pointed at
-- directly so it needs no SharedMedia registration. Same file the meters'
-- "Blizzard" uses, which also means the shared appender drops the library's
-- identical entry instead of listing a second "Blizzard" further down. A
-- plain file path, so every consumer resolves it through ResolveTexturePath
-- with no special case. Both stock styles seed it.
-- (The client's own Classic nameplate draws UI-TargetingFrame-BarFill here
-- instead; swapping this one constant is all that would take.)
mod.NP_BLIZZ_BAR_TEX = "Interface\\TargetingFrame\\UI-StatusBar"
mod.healthBarTextures["blizzard"] = mod.NP_BLIZZ_BAR_TEX
mod.healthBarTextureNames["blizzard"] = "Blizzard"
table.insert(mod.healthBarTextureOrder, 2, "blizzard")
-- The one-time stock-style seed on the profile `p`: that fill on the health
-- and cast bars, once per profile. The dropdowns stay the user's afterwards.
-- Run by the Style page the moment either stock style is switched on, and at
-- enable for a profile that arrived already switched (an import, an older
-- build).
-- The keys the Style page keeps per style for this module (its SLOT_KEYS).
mod._npStyleSlotKeys =
    { "healthBarTexture", "castBarTexture", "castBgColor", "castBgAlpha", "castBarUninterruptible" }
-- The one-time Classic WoW UI cast seed: the vanilla plate's half-black
-- window behind the fill and a light grey for an uninterruptible cast, so
-- the grey fill reads against its background (the CludesUI look's dark
-- background and mid grey are nearly one tone on the classic bar fill).
-- Once per profile; the controls stay the user's afterwards.
mod._npClassicCastKeys = { "castBgColor", "castBgAlpha", "castBarUninterruptible" }
function mod.NP_SeedClassic(prof)
    if not prof or prof.classicCastSeeded then return end
    prof.classicCastSeeded = true
    prof.castBgColor = { r = 0, g = 0, b = 0 }
    prof.castBgAlpha = 0.5
    prof.castBarUninterruptible = { r = 0.7, g = 0.7, b = 0.7 }
end
function mod.NP_SeedStock(prof)
    if not prof or prof.stockBarTextureSeeded then return end
    prof.stockBarTextureSeeded = true
    prof.healthBarTexture = "blizzard"
    prof.castBarTexture = "blizzard"
end
-- The one-time WoW Forever seeds, each under its own stamp: the level box
-- shows the level, so the Left Text slot's Forever default ("level") steps
-- aside instead of showing it a second time (a level the user put anywhere
-- else stays), and the look's plates start without elite or rare marks (the
-- Elite/Rare Indicator box unchecked; the Quest Indicator keeps its own).
-- Once per profile; the settings are the user's afterwards. The Style page
-- keeps the keys in a Forever-only slot (p._foreverStyleSlots): the other
-- looks' values are banked on the way into the variant and come back on the
-- way out.
function mod.NP_SeedForever(prof)
    if not prof then return end
    if not prof.foreverLevelSlotSeeded then
        prof.foreverLevelSlotSeeded = true
        local val = prof.textSlotLeft
        if val == nil then val = defaultSet.textSlotLeft end
        if val == "level" then prof.textSlotLeft = "none" end
    end
    if not prof.foreverRareSeeded then
        prof.foreverRareSeeded = true
        prof.classificationHideRare = true
    end
end

local function NoTintFlag(saved, key)
    local val = saved and saved[key]
    if val == nil then val = defaultSet[key] end
    return val
end

local function ApplyHealthBarTexture(backing)
    local health = backing.health
    if not health then return end
    local texKey = (p and p.healthBarTexture) or defaultSet.healthBarTexture or "none"
    local filePath =
        CUI.ResolveTexturePath(mod.healthBarTextures, texKey, "Interface\\Buttons\\WHITE8x8")
    health:SetStatusBarTexture(filePath)
    -- A path swap mints a new fill object: the shield anchors follow it.
    if backing.absorb and backing._absFill ~= health:GetStatusBarTexture() then
        mod.NP_LayoutAbsorbBars(backing, health, backing._absEdge)
    end
    if backing.castTintInt then mod.NP_LayoutCastTints(backing) end
    -- Blizzard Style: the user's fill under the stock background art, plus
    -- the bar's inner shadow (re-sized here on every appearance pass). The
    -- classic plate is the bare fill inside its 1px edge (the border path).
    if mod.NP_Style() == "blizzard" then mod.NP_ApplyBlizzBarArt(backing) end
    mod.NP_ApplyRounding(backing, "health")
end
mod.ApplyHealthBarTexture = ApplyHealthBarTexture

-- Rounded corners (CludesUI_RoundedCorners.lua; nothing at radius 0, under
-- the stock styles, under a custom border style that cannot round, or while
-- Wrap Border Around Castbar is on, which greys Corner Radius out). The body
-- is listed texture by texture: glows and arrows on the health bar reach past
-- it and must stay unmasked. Re-run after every retexture (a path swap mints a
-- new fill object). The custom border frame is the shape while it is on.
-- part: "health" or "cast" for one bar, nil for both. cornersOnly: the cast
-- bar's show / hide under Join Cast Bar, which moves only the health bar's
-- bottom corners. The opts tables are reused (the kit reads them during the
-- call only).
local NO_ROOTS, HP_ROOTS, HP_TEX, CAST_TEX = {}, {}, {}, {}
local HP_OPTS = { roots = HP_ROOTS, textures = HP_TEX }
local CAST_OPTS = { roots = NO_ROOTS, textures = CAST_TEX }
function mod.NP_ApplyRounding(backing, part, cornersOnly)
    local health = backing.health
    if not health then return end
    local radius = (not mod.NP_Blizz() and p and p.cornerRadius) or 0
    if radius > 0 and mod.GetWrapBorderCastbar() then radius = 0 end
    local customOn = radius > 0 and mod.IsCustomBorderEnabled()
    local style = customOn and ((p and p.customBorderTexture) or defaultSet.customBorderTexture) or "solid"
    if not CUI.RoundedStyleOK(style) then radius = 0 end
    -- Join Cast Bar: while a cast shows, the health bar and the cast bar under
    -- it share one outline (the cast bar's show / hide re-rounds the health
    -- bar, see the cast visibility hook).
    local join = radius > 0 and p and p.cornerJoinCast or nil
    backing._npJoinCast = join
    -- Off: free on every spawn unless this plate was rounded before.
    if radius <= 0 then
        if backing._npRounded then
            backing._npRounded = nil
            CUI.RoundCorners(backing, 0)
            if backing.cast then CUI.RoundCorners(backing.cast, 0) end
        end
        return
    end
    backing._npRounded = true
    -- Basic draws Solid strips on the health bar; Custom draws its own style
    -- on its own frame, which ApplyBorder builds and rounds right after.
    local custom = customOn and backing._customBorder
    if part ~= "cast" and (custom or not customOn) then
        local shape = custom or health
        HP_OPTS.rect, HP_OPTS.border, HP_OPTS.style = shape, shape, style
        HP_OPTS.corners = p and p.cornerMask
        if join and backing.cast and backing.cast:IsShown() then
            HP_OPTS.corners = CUI.RoundedJoinCorners(HP_OPTS.corners)
        end
        local ab, fw = backing.absorb, backing.absorbForward
        HP_TEX[1], HP_TEX[2], HP_TEX[3] = health:GetStatusBarTexture(), backing.healthBG, backing.hashLine
        HP_TEX[4], HP_TEX[5] = backing.highlight, backing.targetHighlight
        HP_TEX[6] = ab and ab:GetStatusBarTexture()
        HP_TEX[7] = fw and fw:GetStatusBarTexture()
        -- Color Casting Enemies tints (built on first use, nil until then)
        HP_TEX[8], HP_TEX[9] = backing.castTintUnint, backing.castTintInt
        -- The Target, Focus and Hover Texture overlays: one texture in each of
        -- their clip frames (built on first use, nil until then)
        HP_ROOTS[1], HP_ROOTS[2] = backing.targetClipFill, backing.targetClipBg
        HP_ROOTS[3], HP_ROOTS[4] = backing.focusClipFill, backing.focusClipBg
        HP_ROOTS[5], HP_ROOTS[6] = backing.hoverClipFill, backing.hoverClipBg
        -- A cast show / hide moves the corners alone while every other input
        -- of the plate's last full pass still holds (radius, style, shape,
        -- each body texture and root): the kit then reshapes without walking
        -- the body. Anything else, or a pass the kit will not shorten, runs
        -- in full and records its inputs.
        local last = backing._npHpRound
        local same = cornersOnly
            and last
            and last.radius == radius
            and last.style == style
            and last.shape == shape
        if same then
            local lt, lr = last.tex, last.roots
            for index = 1, 9 do
                if lt[index] ~= HP_TEX[index] then
                    same = false
                    break
                end
            end
            if same then
                for index = 1, 6 do
                    if lr[index] ~= HP_ROOTS[index] then
                        same = false
                        break
                    end
                end
            end
        end
        if not (same and CUI.RoundedSetCorners(backing, HP_OPTS.corners)) then
            CUI.RoundCorners(backing, radius, HP_OPTS)
            if not last then
                last = { tex = {}, roots = {} }
                backing._npHpRound = last
            end
            last.radius, last.style, last.shape = radius, style, shape
            local lt, lr = last.tex, last.roots
            for index = 1, 9 do
                lt[index] = HP_TEX[index]
            end
            for index = 1, 6 do
                lr[index] = HP_ROOTS[index]
            end
        end
    end
    local cast = backing.cast
    if cast and part ~= "health" then
        CAST_OPTS.border, CAST_OPTS.corners = cast, p and p.cornerMask
        if join then
            local _, lower = CUI.RoundedJoinCorners(CAST_OPTS.corners)
            CAST_OPTS.corners = lower
        end
        CAST_TEX[1], CAST_TEX[2], CAST_TEX[3] =
            cast:GetStatusBarTexture(), backing.castBG, backing.castBarOverlay
        CUI.RoundCorners(cast, radius, CAST_OPTS)
    end
end

-- The Basic border's colour: its PP strips, plus the rounded ring that stands
-- in for them while Corner Radius is on (the strips are masked out then). A
-- hidden border still takes the colour, for its next show.
function mod.NP_BasicBorderColor(backing, red, green, blue, a)
    CUI.PP.SetBorderColor(backing.health, red, green, blue, a)
    if backing._npRounded then CUI.RoundedBorderColor(backing.health, red, green, blue, a) end
end

-- Cast bar texture: mirrors ApplyHealthBarTexture with the same texture set (CUI built-ins +
-- SharedMedia, appended into ns.healthBarTextures at options-build time). On ns (local cap).
function mod.ApplyCastBarTexture(backing)
    local cast = backing.cast
    if not cast then return end
    -- Blizzard Style: the stock cast bar art replaces the texture. The classic
    -- cast bar is the user's texture inside its 1px edge (ApplyCastBorder).
    if mod.NP_Style() == "blizzard" then
        mod.NP_ApplyBlizzCastArt(backing)
        return
    end
    local texKey = (p and p.castBarTexture) or defaultSet.castBarTexture or "none"
    local filePath =
        CUI.ResolveTexturePath(mod.healthBarTextures, texKey, "Interface\\Buttons\\WHITE8x8")
    cast:SetStatusBarTexture(filePath)
    -- The uninterruptible overlay is a flat WHITE8x8 (grey tint via SetAlphaFromBoolean) that
    -- would hide the fill texture; give it the same texture so the pattern shows through. The
    -- per-cast grey SetVertexColor is re-applied on every cast start, so this is safe.
    if backing.castBarOverlay then backing.castBarOverlay:SetTexture(filePath) end
    -- A path swap mints a new fill object: it joins the rounded body.
    if backing._npRounded then mod.NP_ApplyRounding(backing, "cast") end
end
-- Bar backgrounds, painted on every enemy appearance pass so a profile switch or
-- an override reaches live plates: the Background / Cast Background colours, and
-- Textured Background (Bar Texture / Cast Bar Texture cogs; off by default),
-- which puts the bar texture there tinted by that colour. While textured, a
-- background's own SetColorTexture tints the texture, so the colour rows' live
-- repaints keep it: paint these backgrounds only through SetColorTexture
-- (SetTexture / SetAtlas go around it). Blizzard Style draws its stock art there.
do
    local function PaintTinted(self, red, green, blue, a) self:SetVertexColor(red, green, blue, a) end
    -- A background's texture path in settings s (nil = flat); the options
    -- preview shares it.
    function mod.NP_TexBgPath(cfg, cast)
        if not (cfg and cfg[cast and "castTextureBg" or "healthTextureBg"]) then return nil end
        return CUI.ResolveTexturePath(
            mod.healthBarTextures,
            cfg[cast and "castBarTexture" or "healthBarTexture"] or "none",
            nil
        )
    end
    -- One paint of a background that is never swapped (the options preview).
    function mod.NP_TexBgPaint(texture, filePath, red, green, blue, a)
        if filePath then
            texture:SetTexture(filePath)
            texture:SetVertexColor(red, green, blue, a)
            texture._npTexBgPath = filePath
            return
        end
        if texture._npTexBgPath then
            texture._npTexBgPath = nil
            texture:SetVertexColor(1, 1, 1, 1)
        end
        texture:SetColorTexture(red, green, blue, a)
    end
    local function Paint(backdrop, filePath, color, a)
        if filePath then
            if backdrop._npTexBgPath ~= filePath then
                backdrop:SetTexture(filePath)
                backdrop._npTexBgPath = filePath
            end
            backdrop.SetColorTexture = PaintTinted
        elseif backdrop._npTexBgPath then
            backdrop._npTexBgPath = nil
            backdrop.SetColorTexture = nil
            backdrop:SetVertexColor(1, 1, 1, 1)
        end
        backdrop:SetColorTexture(color.r, color.g, color.b, a)
    end
    function mod.ApplyBarBackgrounds(backing)
        if mod.NP_Style() == "blizzard" then return end
        Paint(
            backing.healthBG,
            mod.NP_TexBgPath(p, false),
            (p and p.bgColor) or defaultSet.bgColor,
            (p and p.bgAlpha) or defaultSet.bgAlpha
        )
        Paint(
            backing.castBG,
            mod.NP_TexBgPath(p, true),
            (p and p.castBgColor) or defaultSet.castBgColor,
            (p and p.castBgAlpha) or defaultSet.castBgAlpha
        )
    end
end

function mod.ApplyAbsorbStyle(backing)
    local style = (p and p.absorbStyle) or defaultSet.absorbStyle
    -- blizzard/striped/clean live in NP_ABSORB_STYLE_TEX; the stripe keys
    -- (shared with the Focus Texture dropdown) resolve via ResolveOverlayTexPath.
    local texture = mod.NP_ABSORB_STYLE_TEX[style]
        or mod.ResolveOverlayTexPath(style)
        or mod.NP_ABSORB_STYLE_TEX.blizzard
    -- Opacity applies to every style. absorbAlpha (0-100) is the single source of truth
    -- once set (slider touched or style picked); until then, per-style defaults.
    local alpha = p and p.absorbAlpha
    if alpha then
        alpha = alpha / 100
    elseif style == "clean" then
        alpha = ((p and p.absorbCleanAlpha) or defaultSet.absorbCleanAlpha or 30) / 100
    else
        alpha = mod.NP_ABSORB_STYLE_ALPHA[style] or 0.8
    end
    -- Tint applies to every style EXCEPT Blizzard, which keeps its own coloring.
    local red, green, blue = 1, 1, 1
    if style ~= "blizzard" then
        local color = (p and p.absorbColor) or defaultSet.absorbColor
        -- Per-component default: a partial colour table would throw downstream.
        if color then
            red, green, blue = color.r or 1, color.g or 1, color.b or 1
        end
    end
    local mask = backing._absorbMask
    for _, barFrame in ipairs({ backing.absorb, backing.absorbForward }) do
        if barFrame then
            barFrame:SetStatusBarTexture(texture)
            barFrame:SetStatusBarColor(red, green, blue, alpha)
            local fillTex = barFrame:GetStatusBarTexture()
            if fillTex then
                fillTex:SetDrawLayer("ARTWORK", 1)
                if mask then fillTex:AddMaskTexture(mask) end
            end
        end
    end
    local mode = (p and p.absorbEdgeMode) or defaultSet.absorbEdgeMode
    if backing._absEdge ~= mode or backing._absFill ~= backing.health:GetStatusBarTexture() then
        mod.NP_LayoutAbsorbBars(backing, backing.health, mode)
        -- A shield already up repaints in its new placement (the forward
        -- bar's visibility is decided by the paint).
        if backing.unit and backing.MarkHealthDirty and not backing._absorbHidden then
            backing._absorbEdge = true
            backing:MarkHealthDirty()
        end
    end
    -- A new shield texture is a new fill object: it joins the rounded body.
    if backing._npRounded then mod.NP_ApplyRounding(backing, "health") end
end

-- Shield absorbs, drawn like the unit frames' and secret-safe: both bars take
-- the raw absorb over 0..maxHealth and two clip frames do the split visually,
-- so no Lua math ever touches a (possibly secret) absorb amount, and the
-- health bar keeps its own range (the shield never squeezes it).
--   _absMissClip: health fill edge -> bar's right end (the empty health).
--   _absCurClip:  bar's left end -> health fill edge (the filled health), or
--                 the whole bar in the edge placements.
--   absorbForward: in the missing clip, overlay placements only:
--     overlay        = fills right from the health edge, so it shows
--                      min(absorb, missing)
--     overlayReverse = fills right from the bar's left end, so it shows only
--                      what exceeds current health, past the health edge
--   absorb: in the filled clip, placed per absorbEdgeMode:
--     overlay        = fills left from the bar's right end; the clip shows
--                      only what exceeds empty health, over the health fill
--     overlayReverse = fills left from the health edge, over current health
--     right / left   = the whole shield from that end of the bar
-- Overlay Reverse thus draws the shield back over health, and a shield
-- larger than current health spans from the bar's left end instead of
-- losing its excess.
-- Shared with the options preview (owner is any table holding the bars).
function mod.NP_BuildAbsorbBars(ownerFrame, health, mask)
    local lvl = health:GetFrameLevel() + 1
    local curClip = Pool.CreateFrame("Frame", nil, health)
    curClip:SetClipsChildren(true)
    curClip:SetFrameLevel(lvl)
    local missClip = Pool.CreateFrame("Frame", nil, health)
    missClip:SetClipsChildren(true)
    missClip:SetFrameLevel(lvl)
    local fw = Pool.CreateFrame("StatusBar", nil, missClip)
    fw:SetReverseFill(false)
    local ab = Pool.CreateFrame("StatusBar", nil, curClip)
    for _, barFrame in ipairs({ ab, fw }) do
        barFrame:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        local fillTex = barFrame:GetStatusBarTexture()
        if fillTex and mask then fillTex:AddMaskTexture(mask) end
        barFrame:SetFrameLevel(lvl)
        barFrame:SetMinMaxValues(0, 1)
        barFrame:SetValue(0)
    end
    -- The clips carry the visibility (the bars inside stay shown): hidden,
    -- their fill-edge anchors cost nothing on a plate with no shield.
    curClip:Hide()
    missClip:Hide()
    ownerFrame._absCurClip, ownerFrame._absMissClip = curClip, missClip
    ownerFrame.absorb, ownerFrame.absorbForward = ab, fw
end

-- Seats every anchor for a placement. Anchors ride the health fill object,
-- and a health texture path swap mints a new one, so this also re-runs
-- whenever the fill changes (stamped _absFill). Never per paint.
function mod.NP_LayoutAbsorbBars(ownerFrame, health, mode)
    local fillTex = health:GetStatusBarTexture()
    local curClip, missClip = ownerFrame._absCurClip, ownerFrame._absMissClip
    local ab, fw = ownerFrame.absorb, ownerFrame.absorbForward
    local fromLeft = mode == "overlayReverse"
    missClip:ClearAllPoints()
    -- 1px into the fill seals the seam behind a forward bar that starts at
    -- the health edge; one from the bar's left end would double that pixel
    -- over the main bar.
    missClip:SetPoint("TOPLEFT", fillTex, "TOPRIGHT", fromLeft and 0 or -1, 0)
    missClip:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
    fw:ClearAllPoints()
    if fromLeft then
        fw:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
        fw:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", 0, 0)
    else
        fw:SetPoint("TOPLEFT", fillTex, "TOPRIGHT", 0, 0)
        fw:SetPoint("BOTTOMLEFT", fillTex, "BOTTOMRIGHT", 0, 0)
    end
    curClip:ClearAllPoints()
    ab:ClearAllPoints()
    if mode == "right" or mode == "left" then
        curClip:SetAllPoints(health)
    else
        curClip:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
        curClip:SetPoint("BOTTOMRIGHT", fillTex, "BOTTOMRIGHT", 0, 0)
    end
    if mode == "left" then
        ab:SetReverseFill(false)
        ab:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
        ab:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", 0, 0)
    elseif mode == "overlayReverse" then
        ab:SetReverseFill(true)
        ab:SetPoint("TOPRIGHT", fillTex, "TOPRIGHT", 0, 0)
        ab:SetPoint("BOTTOMRIGHT", fillTex, "BOTTOMRIGHT", 0, 0)
    else
        ab:SetReverseFill(true)
        ab:SetPoint("TOPRIGHT", health, "TOPRIGHT", 0, 0)
        ab:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
    end
    ownerFrame._absFwOn = mode == "overlay" or fromLeft
    if not ownerFrame._absFwOn then missClip:Hide() end
    ownerFrame._absEdge, ownerFrame._absFill = mode, fillTex
end

-- Both bars span the health bar so their textures render at bar scale.
function mod.NP_SizeAbsorbBars(ownerFrame, wid, hgt)
    ownerFrame.absorb:SetSize(wid, hgt)
    ownerFrame.absorbForward:SetSize(wid, hgt)
end

function mod.ApplyAbsorbStyleAll()
    -- Pooled plates pick the change up at their next spawn.
    mod._npAppearanceGen = (mod._npAppearanceGen or 0) + 1
    for _, backing in pairs(mod.plates) do
        mod.ApplyAbsorbStyle(backing)
    end
end

Inner.ApplyHealthBarTexture, Inner.NoTintFlag = ApplyHealthBarTexture, NoTintFlag
Inner.broken = false
