if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_Nameplates_Overlays.lua
--
--  Lazily built overlays (glow, low health, near aggro, highlight, arrows,
--  focus), the threat percent text, the threat gap, hover and target overlay.
--  Reads the earlier nameplate files through ns and ns._npInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._npInternals
-- CludesUINameplates.lua or an earlier nameplate file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local pairs, type = pairs, type
local Pix = CludesUI.PP
local UnitIsUnit = UnitIsUnit
local UnitClass = UnitClass
local _, PLAYER_CLASS = UnitClass("player")

local defaultSet, GetFont, GetNPOutline = Inner.defaults, Inner.GetFont, Inner.GetNPOutline
local HP_BAR_SLOTS, SetFSFont = Inner.HP_BAR_SLOTS, Inner.SetFSFont
local GetHealthBarWidth = Inner.GetHealthBarWidth

local p
Inner.profileSetters[#Inner.profileSetters + 1] = function(val)
    p = val
end

-------------------------------------------------------------------------------
--  Lazy-creation helpers for target-only/focus-only UI objects: needed on 1 plate at a time,
--  so building them on every pooled plate wastes memory. Each Ensure* is idempotent.
-------------------------------------------------------------------------------
local GLOW_TEX = "Interface\\AddOns\\CludesUINameplates\\Media\\background.png"
local GLOW_MARGIN = 0.48
local GLOW_CORNER = 12
local GLOW_EXTEND = 6

local function EnsureGlow(backing)
    if backing.glow then
        return
    end
    backing.glowFrame = CreateFrame("Frame", nil, backing)
    backing.glowFrame:SetFrameStrata("BACKGROUND")
    backing.glowFrame:SetFrameLevel(1)
    backing.glowFrame:SetPoint("TOPLEFT", backing.health, "TOPLEFT", -GLOW_EXTEND, GLOW_EXTEND)
    backing.glowFrame:SetPoint("BOTTOMRIGHT", backing.health, "BOTTOMRIGHT", GLOW_EXTEND, -GLOW_EXTEND)
    -- Glow tint/opacity come from the target "Glow Color" setting; textures are collected so ApplyTarget can recolor them live.
    backing.glowTextures = {}
    local gc = mod.GetTargetGlowColor()
    local ga = mod.GetTargetGlowAlpha()
    local function MkTex()
        local t = backing.glowFrame:CreateTexture(nil, "BACKGROUND")
        t:SetTexture(GLOW_TEX)
        t:SetVertexColor(gc.r, gc.g, gc.b, ga)
        t:SetBlendMode("ADD")
        backing.glowTextures[#backing.glowTextures + 1] = t
        return t
    end
    backing.glowTL = MkTex()
    backing.glowTL:SetSize(GLOW_CORNER, GLOW_CORNER)
    backing.glowTL:SetPoint("TOPLEFT")
    backing.glowTL:SetTexCoord(0, GLOW_MARGIN, 0, GLOW_MARGIN)
    backing.glowTR = MkTex()
    backing.glowTR:SetSize(GLOW_CORNER, GLOW_CORNER)
    backing.glowTR:SetPoint("TOPRIGHT")
    backing.glowTR:SetTexCoord(1 - GLOW_MARGIN, 1, 0, GLOW_MARGIN)
    backing.glowBL = MkTex()
    backing.glowBL:SetSize(GLOW_CORNER, GLOW_CORNER)
    backing.glowBL:SetPoint("BOTTOMLEFT")
    backing.glowBL:SetTexCoord(0, GLOW_MARGIN, 1 - GLOW_MARGIN, 1)
    backing.glowBR = MkTex()
    backing.glowBR:SetSize(GLOW_CORNER, GLOW_CORNER)
    backing.glowBR:SetPoint("BOTTOMRIGHT")
    backing.glowBR:SetTexCoord(1 - GLOW_MARGIN, 1, 1 - GLOW_MARGIN, 1)
    backing.glowTop = MkTex()
    backing.glowTop:SetHeight(GLOW_CORNER)
    backing.glowTop:SetPoint("TOPLEFT", backing.glowTL, "TOPRIGHT")
    backing.glowTop:SetPoint("TOPRIGHT", backing.glowTR, "TOPLEFT")
    backing.glowTop:SetTexCoord(GLOW_MARGIN, 1 - GLOW_MARGIN, 0, GLOW_MARGIN)
    backing.glowBottom = MkTex()
    backing.glowBottom:SetHeight(GLOW_CORNER)
    backing.glowBottom:SetPoint("BOTTOMLEFT", backing.glowBL, "BOTTOMRIGHT")
    backing.glowBottom:SetPoint("BOTTOMRIGHT", backing.glowBR, "BOTTOMLEFT")
    backing.glowBottom:SetTexCoord(GLOW_MARGIN, 1 - GLOW_MARGIN, 1 - GLOW_MARGIN, 1)
    backing.glowLeft = MkTex()
    backing.glowLeft:SetWidth(GLOW_CORNER)
    backing.glowLeft:SetPoint("TOPLEFT", backing.glowTL, "BOTTOMLEFT")
    backing.glowLeft:SetPoint("BOTTOMLEFT", backing.glowBL, "TOPLEFT")
    backing.glowLeft:SetTexCoord(0, GLOW_MARGIN, GLOW_MARGIN, 1 - GLOW_MARGIN)
    backing.glowRight = MkTex()
    backing.glowRight:SetWidth(GLOW_CORNER)
    backing.glowRight:SetPoint("TOPRIGHT", backing.glowTR, "BOTTOMRIGHT")
    backing.glowRight:SetPoint("BOTTOMRIGHT", backing.glowBR, "TOPRIGHT")
    backing.glowRight:SetTexCoord(1 - GLOW_MARGIN, 1, GLOW_MARGIN, 1 - GLOW_MARGIN)
    -- Center fill: covers the gap between top/bottom edges inside the health bar
    backing.glowCenter = MkTex()
    backing.glowCenter:SetPoint("TOPLEFT", backing.glowLeft, "TOPRIGHT")
    backing.glowCenter:SetPoint("BOTTOMRIGHT", backing.glowRight, "BOTTOMLEFT")
    backing.glowCenter:SetTexCoord(GLOW_MARGIN, 1 - GLOW_MARGIN, GLOW_MARGIN, 1 - GLOW_MARGIN)
    backing.glow = backing.glowFrame
    backing.glowFrame:Hide()
end

-- Execute Pulse Glow (Extras, default off): red glow around the health bar pulsing while the
-- unit is inside the PLAYER'S execute window (health fraction below which their spec's execute
-- becomes usable; per-spec, talent-adjusted, table below). A no-execute spec disables the
-- feature outright: no frame/texture/animation/per-update work. Secret-value design: the
-- below-threshold gate is a C_CurveUtil color curve evaluated C-side by UnitHealthPercent,
-- feeding SetVertexColor (accepts secret components) directly, so Lua never branches on health.
-- The pulse is a looping C-side Alpha animation (no Lua ticks), so it renders identically inside
-- and outside restricted (secret) combat. Frame alpha (pulse) and texture vertex alpha (gate)
-- are separate channels that multiply, so they never fight. Cache lives in a do-block (no
-- main-chunk local slots, near-cap file).
do
    -- Execute windows by SPEC ID: requires = gate spell ids (none = no execute at all);
    -- base = health fraction once gated; talents = ids that RAISE the window (any one enough);
    -- talentPct = the raised fraction. A spec absent from this table has no execute; inert.
    -- Keyed by id, never by localized name.
    local EXEC = {
        [252] = { base = 0.35 }, -- Death Knight: Unholy only
        -- Hunter: Marksmanship always; Beast Mastery needs its gate talent; Survival has none.
        [253] = { requires = { 466930 }, base = 0.20 },
        [254] = { base = 0.20 },
        [63] = { base = 0.30 }, -- Mage: Fire only
        -- Monk/Rogue: DISABLED (entries removed, both absent from EXEC_CLASSES below). To
        -- restore: Monk gate 322113/base 0.15 all specs; Rogue (Assassination) gate 381798/base 0.35.
        -- Priest: all three specs.
        [256] = { base = 0.20, talents = { 392507 }, talentPct = 0.35 },
        [257] = { base = 0.20, talents = { 392507 }, talentPct = 0.35 },
        [258] = { base = 0.20, talents = { 392507 }, talentPct = 0.35 },
        -- Warlock: Affliction (Drain Soul gate) and Destruction (Shadowburn gate); Demonology none.
        [265] = { requires = { 388667 }, base = 0.20 },
        [267] = { requires = { 17877 }, base = 0.20 },
        -- Warrior: all three specs; either talent raises the window.
        [71] = { base = 0.20, talents = { 281001, 206315 }, talentPct = 0.35 },
        [72] = { base = 0.20, talents = { 281001, 206315 }, talentPct = 0.35 },
        [73] = { base = 0.20, talents = { 281001, 206315 }, talentPct = 0.35 },
        -- No entries for Demon Hunter, Druid, Evoker, Paladin or Shaman.
    }
    -- Classes with at least one execute spec; everyone else never registers the watcher (threshold
    -- stays nil all session, every entry point early-outs on one upvalue read). Must stay in step
    -- with EXEC -- a class listed here with no specs there registers a watcher for nothing.
    local EXEC_CLASSES = {
        DEATHKNIGHT = true,
        HUNTER = true,
        MAGE = true,
        PRIEST = true,
        WARLOCK = true,
        WARRIOR = true,
        -- MONK = true,
        -- ROGUE = true,
    }

    local threshold = nil -- current execute fraction; nil = no execute
    local lowCurve, curveAt -- cached curve + the threshold it was built for

    local function AnyKnown(ids)
        local scrollBar = C_SpellBook
        if not (scrollBar and scrollBar.IsSpellKnown) then
            return false
        end
        for index = 1, #ids do
            if scrollBar.IsSpellKnown(ids[index]) then
                return true
            end
        end
        return false
    end

    local function Resolve()
        local specID = CludesUI._specID
        if (not specID or specID == 0) and CludesUI._RefreshSpecID then
            CludesUI._RefreshSpecID()
            specID = CludesUI._specID
        end
        local def = specID and EXEC[specID]
        if not def then
            return nil
        end
        -- Gate first: an unmet requirement means no execute exists at all.
        if def.requires and not AnyKnown(def.requires) then
            return nil
        end
        local pct = def.base
        if def.talents and AnyKnown(def.talents) then
            if not pct or def.talentPct > pct then
                pct = def.talentPct
            end
        end
        return pct
    end

    --- The player's current execute-window fraction, or nil when this spec
    --- and talent build has no execute (feature fully disabled).
    function mod.GetExecuteThreshold()
        return threshold
    end

    function mod.GetLowHpGlowCurve()
        local t = threshold
        if not t then
            return nil
        end
        if lowCurve and curveAt == t then
            return lowCurve
        end
        if not (C_CurveUtil and C_CurveUtil.CreateColorCurve and UnitHealthPercent) then
            return nil
        end
        local curve = C_CurveUtil.CreateColorCurve()
        local EPSILON = 0.0001
        -- At or below the execute threshold -> red; above -> BLACK, which contributes
        -- nothing under the glow textures' ADD blend, so the glow disappears. Alpha
        -- stays 1 at every point and only RGB varies: curve alpha interpolation is
        -- deliberately never relied on. Rebuilt only when the threshold itself changes.
        curve:AddPoint(0.0, CreateColor(1, 0, 0, 1))
        curve:AddPoint(t, CreateColor(1, 0, 0, 1))
        curve:AddPoint(t + EPSILON, CreateColor(0, 0, 0, 1))
        curve:AddPoint(1.0, CreateColor(0, 0, 0, 1))
        lowCurve, curveAt = curve, t
        return curve
    end

    -- Spec + talent watcher, built ONLY for a class that can have an execute. Talents cannot
    -- change in combat, so these events cost nothing at runtime.
    do
        local _, cls = UnitClass("player")
        if EXEC_CLASSES[cls] then
            local watcher = CreateFrame("Frame")
            watcher:RegisterEvent("PLAYER_LOGIN")
            watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
            watcher:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
            watcher:RegisterEvent("TRAIT_CONFIG_UPDATED")
            watcher:RegisterEvent("PLAYER_TALENT_UPDATE")
            watcher:SetScript("OnEvent", function()
                local new = Resolve()
                if new == threshold then
                    return
                end
                threshold = new
                lowCurve, curveAt = nil, nil
                -- Re-apply per plate: the gate creates/tears down the whole effect, so
                -- gaining/losing an execute flips the glow with no settings change.
                if mod.plates and mod.ApplyLowHpGlow then
                    for _, backing in pairs(mod.plates) do
                        mod.ApplyLowHpGlow(backing)
                    end
                end
            end)
        end
    end
end

function mod.EnsureLowHpGlow(backing)
    if backing.lowHpGlowFrame then
        return
    end
    local frame = CreateFrame("Frame", nil, backing)
    frame:SetFrameStrata("BACKGROUND")
    frame:SetFrameLevel(1)
    frame:SetPoint("TOPLEFT", backing.health, "TOPLEFT", -GLOW_EXTEND, GLOW_EXTEND)
    frame:SetPoint("BOTTOMRIGHT", backing.health, "BOTTOMRIGHT", GLOW_EXTEND, -GLOW_EXTEND)
    backing.lowHpGlowFrame = frame
    local texs = {}
    backing.lowHpGlowTextures = texs
    local function MkTex()
        local t = frame:CreateTexture(nil, "BACKGROUND")
        -- Dedicated art (not the shared target-glow texture) so brightness can be tuned without touching the target glow.
        t:SetTexture("Interface\\AddOns\\CludesUINameplates\\Media\\execute-glow.png")
        t:SetVertexColor(0, 0, 0, 1) -- black = invisible under ADD blend until the first health eval
        t:SetBlendMode("ADD")
        texs[#texs + 1] = t
        return t
    end
    -- Same 9-slice layout as the target glow (EnsureGlow) so the two effects share one visual language.
    local tl = MkTex()
    tl:SetSize(GLOW_CORNER, GLOW_CORNER)
    tl:SetPoint("TOPLEFT")
    tl:SetTexCoord(0, GLOW_MARGIN, 0, GLOW_MARGIN)
    local tr = MkTex()
    tr:SetSize(GLOW_CORNER, GLOW_CORNER)
    tr:SetPoint("TOPRIGHT")
    tr:SetTexCoord(1 - GLOW_MARGIN, 1, 0, GLOW_MARGIN)
    local bl = MkTex()
    bl:SetSize(GLOW_CORNER, GLOW_CORNER)
    bl:SetPoint("BOTTOMLEFT")
    bl:SetTexCoord(0, GLOW_MARGIN, 1 - GLOW_MARGIN, 1)
    local br = MkTex()
    br:SetSize(GLOW_CORNER, GLOW_CORNER)
    br:SetPoint("BOTTOMRIGHT")
    br:SetTexCoord(1 - GLOW_MARGIN, 1, 1 - GLOW_MARGIN, 1)
    local topY = MkTex()
    topY:SetHeight(GLOW_CORNER)
    topY:SetPoint("TOPLEFT", tl, "TOPRIGHT")
    topY:SetPoint("TOPRIGHT", tr, "TOPLEFT")
    topY:SetTexCoord(GLOW_MARGIN, 1 - GLOW_MARGIN, 0, GLOW_MARGIN)
    local bot = MkTex()
    bot:SetHeight(GLOW_CORNER)
    bot:SetPoint("BOTTOMLEFT", bl, "BOTTOMRIGHT")
    bot:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
    bot:SetTexCoord(GLOW_MARGIN, 1 - GLOW_MARGIN, 1 - GLOW_MARGIN, 1)
    local lft = MkTex()
    lft:SetWidth(GLOW_CORNER)
    lft:SetPoint("TOPLEFT", tl, "BOTTOMLEFT")
    lft:SetPoint("BOTTOMLEFT", bl, "TOPLEFT")
    lft:SetTexCoord(0, GLOW_MARGIN, GLOW_MARGIN, 1 - GLOW_MARGIN)
    local rgt = MkTex()
    rgt:SetWidth(GLOW_CORNER)
    rgt:SetPoint("TOPRIGHT", tr, "BOTTOMRIGHT")
    rgt:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
    rgt:SetTexCoord(1 - GLOW_MARGIN, 1, GLOW_MARGIN, 1 - GLOW_MARGIN)
    local ctr = MkTex()
    ctr:SetPoint("TOPLEFT", lft, "TOPRIGHT")
    ctr:SetPoint("BOTTOMRIGHT", rgt, "BOTTOMLEFT")
    ctr:SetTexCoord(GLOW_MARGIN, 1 - GLOW_MARGIN, GLOW_MARGIN, 1 - GLOW_MARGIN)
    -- Pulse: C-side alpha loop on the frame; only advances while shown.
    local ag = frame:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.35)
    a:SetDuration(0.55)
    a:SetSmoothing("IN_OUT")
    backing.lowHpGlowPulse = ag
end

function mod.ApplyLowHpGlow(backing)
    -- Two hard gates: setting on AND spec/talents have an execute window. Failing either,
    -- nothing is created; the health-update eval short-circuits on a nil texture list.
    if not (p and p.lowHpGlow == true) or not mod.GetExecuteThreshold() then
        if backing.lowHpGlowFrame then
            backing.lowHpGlowPulse:Stop()
            backing.lowHpGlowFrame:Hide()
        end
        -- Own flag mirrors the frame's shown state (this function is its only
        -- toggler) so the per-tick health paint reads a field, not IsShown().
        backing._lowHpGlowOn = nil
        return
    end
    mod.EnsureLowHpGlow(backing)
    backing.lowHpGlowFrame:Show()
    backing._lowHpGlowOn = true
    if not backing.lowHpGlowPulse:IsPlaying() then
        backing.lowHpGlowPulse:Play()
    end
end

-- Near-aggro glow (Non-Tank Threat cog): the execute glow's exact 9-slice
-- visual -- same art, extend, corner geometry, ADD blend -- at STATIC
-- full-alpha red: no pulse animation and no health curve. Visibility alone is
-- the signal, driven from UpdateHealthColor's own Near Aggro color decision
-- (clean threat booleans, so it behaves identically in and out of restriction).
function mod.EnsureNearAggroGlow(backing)
    if backing.naGlowFrame then
        return
    end
    local frame = CreateFrame("Frame", nil, backing)
    frame:SetFrameStrata("BACKGROUND")
    frame:SetFrameLevel(1)
    frame:SetPoint("TOPLEFT", backing.health, "TOPLEFT", -GLOW_EXTEND, GLOW_EXTEND)
    frame:SetPoint("BOTTOMRIGHT", backing.health, "BOTTOMRIGHT", GLOW_EXTEND, -GLOW_EXTEND)
    frame:Hide()
    backing.naGlowFrame = frame
    local function MkTex()
        local t = frame:CreateTexture(nil, "BACKGROUND")
        t:SetTexture("Interface\\AddOns\\CludesUINameplates\\Media\\execute-glow.png")
        t:SetVertexColor(1, 0, 0, 1) -- static execute red, full alpha
        t:SetBlendMode("ADD")
        return t
    end
    local tl = MkTex()
    tl:SetSize(GLOW_CORNER, GLOW_CORNER)
    tl:SetPoint("TOPLEFT")
    tl:SetTexCoord(0, GLOW_MARGIN, 0, GLOW_MARGIN)
    local tr = MkTex()
    tr:SetSize(GLOW_CORNER, GLOW_CORNER)
    tr:SetPoint("TOPRIGHT")
    tr:SetTexCoord(1 - GLOW_MARGIN, 1, 0, GLOW_MARGIN)
    local bl = MkTex()
    bl:SetSize(GLOW_CORNER, GLOW_CORNER)
    bl:SetPoint("BOTTOMLEFT")
    bl:SetTexCoord(0, GLOW_MARGIN, 1 - GLOW_MARGIN, 1)
    local br = MkTex()
    br:SetSize(GLOW_CORNER, GLOW_CORNER)
    br:SetPoint("BOTTOMRIGHT")
    br:SetTexCoord(1 - GLOW_MARGIN, 1, 1 - GLOW_MARGIN, 1)
    local topY = MkTex()
    topY:SetHeight(GLOW_CORNER)
    topY:SetPoint("TOPLEFT", tl, "TOPRIGHT")
    topY:SetPoint("TOPRIGHT", tr, "TOPLEFT")
    topY:SetTexCoord(GLOW_MARGIN, 1 - GLOW_MARGIN, 0, GLOW_MARGIN)
    local bot = MkTex()
    bot:SetHeight(GLOW_CORNER)
    bot:SetPoint("BOTTOMLEFT", bl, "BOTTOMRIGHT")
    bot:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
    bot:SetTexCoord(GLOW_MARGIN, 1 - GLOW_MARGIN, 1 - GLOW_MARGIN, 1)
    local lft = MkTex()
    lft:SetWidth(GLOW_CORNER)
    lft:SetPoint("TOPLEFT", tl, "BOTTOMLEFT")
    lft:SetPoint("BOTTOMLEFT", bl, "TOPLEFT")
    lft:SetTexCoord(0, GLOW_MARGIN, GLOW_MARGIN, 1 - GLOW_MARGIN)
    local rgt = MkTex()
    rgt:SetWidth(GLOW_CORNER)
    rgt:SetPoint("TOPRIGHT", tr, "BOTTOMRIGHT")
    rgt:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
    rgt:SetTexCoord(1 - GLOW_MARGIN, 1, GLOW_MARGIN, 1 - GLOW_MARGIN)
    local ctr = MkTex()
    ctr:SetPoint("TOPLEFT", lft, "TOPRIGHT")
    ctr:SetPoint("BOTTOMRIGHT", rgt, "BOTTOMLEFT")
    ctr:SetTexCoord(GLOW_MARGIN, 1 - GLOW_MARGIN, GLOW_MARGIN, 1 - GLOW_MARGIN)
end

-- Highlight target style: translucent wash across the target's health bar. Lazy (only the
-- target ever shows it), kept SEPARATE from plate.highlight (mouseover) so the two never fight.
local function EnsureTargetHighlight(backing)
    if backing.targetHighlight then
        return
    end
    -- Blizzard Style: under the stock selection ring and deselected overlay
    -- (OVERLAY 4/5), still above the fill; the CUI and classic looks keep it on top.
    local t = backing.health:CreateTexture(nil, "OVERLAY", nil, mod.NP_Style() == "blizzard" and 0 or 5)
    t:SetAllPoints(backing.health)
    local c = mod.GetTargetHighlightColor()
    t:SetColorTexture(c.r, c.g, c.b, mod.GetTargetHighlightAlpha())
    t:Hide()
    backing.targetHighlight = t
    -- Blizzard Style: inside the stock bar shape like the fill.
    if backing._blizzBarMask then
        t:AddMaskTexture(backing._blizzBarMask)
        backing._blizzMaskedTarget = true
    end
    mod.NP_ApplyRounding(backing, "health")
end

-- Target arrow styles: key -> { l=left texture, r=right texture, w=drawn width at height 16
-- (scale 1), label }. All source art is 66px tall; w = round(nativeWidth * 11/36): 36->11,
-- 72->22, 90->28. Height always 16. Shared by enemy/friendly plates + options.
mod.TARGET_ARROW_DIR = "Interface\\AddOns\\CludesUINameplates\\Media\\Arrows\\"
mod.TARGET_ARROW_STYLES = {
    simple = { l = "arrow_left", r = "arrow_right", w = 11, label = "Simple Arrows" },
    double = { l = "arrow_leftx2", r = "arrow_rightx2", w = 22, label = "Double Arrows" },
    barbed = { l = "barbed-left", r = "barbed-right", w = 28, label = "Barbed" },
    bracket = { l = "bracket-left", r = "bracket-right", w = 22, label = "Bracket" },
    celestial = { l = "celestial-left", r = "celestial-right", w = 28, label = "Celestial" },
    classic = { l = "classic-left", r = "classic-right", w = 22, label = "Classic" },
    crystal = { l = "crystal-left", r = "crystal-right", w = 22, label = "Crystal" },
    curved = { l = "curved-left", r = "curved-right", w = 22, label = "Curved" },
    demon = { l = "demon-left", r = "demon-right", w = 28, label = "Demon" },
    diamond = { l = "diamond-left", r = "diamond-right", w = 28, label = "Diamond" },
    feathered = { l = "feathered-left", r = "feathered-right", w = 22, label = "Feathered" },
    halo = { l = "halo-left", r = "halo-right", w = 22, label = "Halo" },
    holyspear = { l = "holy-spear-left", r = "holy-spear-right", w = 28, label = "Holy Spear" },
    rune = { l = "rune-left", r = "rune-right", w = 22, label = "Rune" },
    split = { l = "split-left", r = "split-right", w = 22, label = "Split" },
    winged = { l = "winged-left", r = "winged-right", w = 28, label = "Winged" },
}
mod.TARGET_ARROW_ORDER = {
    "simple",
    "double",
    "winged",
    "feathered",
    "split",
    "celestial",
    "rune",
    "demon",
    "halo",
    "curved",
    "barbed",
    "holyspear",
    "bracket",
    "diamond",
    "crystal",
    "classic",
}

-- Resolve a profile to its arrow style table. targetArrowStyle is the current key; legacy profiles fall back to targetArrowDouble (then Simple).
function mod.ResolveTargetArrowStyle(prof)
    local key = prof and (prof.targetArrowStyle or (prof.targetArrowDouble and "double")) or nil
    return mod.TARGET_ARROW_STYLES[key] or mod.TARGET_ARROW_STYLES.simple
end

-- Target arrow tint: the player's class color when targetArrowClassColor is on, else the custom targetArrowColor (default white).
function mod.GetTargetArrowColor(prof)
    if prof and prof.targetArrowClassColor then
        local cc = RAID_CLASS_COLORS and RAID_CLASS_COLORS[PLAYER_CLASS]
        if cc then
            return cc.r, cc.g, cc.b
        end
        return 1, 1, 1
    end
    local c = prof and prof.targetArrowColor
    if c then
        return c.r, c.g, c.b
    end
    return 1, 1, 1
end

local function EnsureArrows(backing)
    if backing.leftArrow then
        return
    end
    local st = mod.ResolveTargetArrowStyle(p)
    local sc = (p and p.targetArrowScale) or 1.0
    local aw, ah = math.floor(st.w * sc + 0.5), math.floor(16 * sc + 0.5)
    -- Regions OF the health bar (the plate subtree is aspect-restricted and unmeasurable). NO
    -- creation anchors: single-point + size rects render DISPLACED inside the restricted tree,
    -- so the only sanctioned form is the fully-anchored TOP+BOTTOM scheme from
    -- PositionArrowsOutsideAuras (runs on every target apply, after Show()). An unanchored
    -- hidden texture has no rect and draws nothing, so the creation state is safe. Rendering
    -- outside the bar rect is fine (health SetClipsChildren(false)).
    local arrowParent = backing.health
    -- Aura containers carry UntrustedLayoutScriptExecution once they hold a group, and only
    -- aspect-bearing objects may anchor to them. Aspects cannot be gained later
    -- (SetParent/SetPoint inheritance is blocked), so arrows must be BORN inside a template
    -- holder to inherit its aspect; the containers file then anchors them to the side aura
    -- containers. Clients without the template keep the plain parent (no aspect needed).
    local success, holderFrame =
        pcall(CreateFrame, "Frame", nil, backing.health, "DisableUntrustedLayoutScriptsTemplate")
    if success and holderFrame then
        holderFrame:SetAllPoints(backing.health)
        holderFrame:SetFrameLevel(backing.health:GetFrameLevel())
        backing.arrowHost = holderFrame
        arrowParent = holderFrame
    end
    backing.leftArrow = arrowParent:CreateTexture(nil, "OVERLAY")
    backing.leftArrow:SetTexture(mod.TARGET_ARROW_DIR .. st.l .. ".png")
    backing.rightArrow = arrowParent:CreateTexture(nil, "OVERLAY")
    backing.rightArrow:SetTexture(mod.TARGET_ARROW_DIR .. st.r .. ".png")
    Pix.Size(backing.leftArrow, aw, ah)
    backing.leftArrow:Hide()
    Pix.Size(backing.rightArrow, aw, ah)
    backing.rightArrow:Hide()
end

-- Target/Focus overlay textures: stripe overlays live in the nameplates Media folder (resolved
-- by name); everything else resolves through the shared health-bar lookup (CUI + SharedMedia).
mod.OVERLAY_STRIPE_KEYS = {
    ["striped-v2"] = true,
    ["striped-wide-v2"] = true,
    ["stripes-medium"] = true,
    ["stripes-small-close"] = true,
    ["stripes-small-spread"] = true,
    ["striped-tiny"] = true,
}
function mod.ResolveOverlayTexPath(key)
    if not key or key == "none" then
        return nil
    end
    if mod.OVERLAY_STRIPE_KEYS[key] then
        return "Interface\\AddOns\\CludesUINameplates\\Media\\" .. key .. ".png"
    end
    if CludesUI.ResolveTexturePath then
        return CludesUI.ResolveTexturePath(mod.healthBarTextures, key, "Interface\\Buttons\\WHITE8x8")
    end
    return nil
end

-- Both overlays span the full bar width (anchored LEFT+RIGHT to the health bar) so the pattern
-- covers the whole bar and follows Health Bar Width changes. Fill and bg share identical
-- geometry so a stripe's diagonal stays continuous across the fill/background split; clip
-- frames window the filled vs empty portions. Stripes additionally CROP via texcoord to the
-- bar's share of the pattern's native 200px span (constant density up to 200 wide, wider bars
-- stretch the full pattern). Width comes from settings, never from measuring the plate subtree
-- (restricted regions forbid reads there).
local STRIPE_NATIVE_W = 200
local function ApplyOverlayGeometry(fillT, bgT, health, isStripe)
    fillT:ClearAllPoints()
    bgT:ClearAllPoints()
    fillT:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
    fillT:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", 0, 0)
    fillT:SetPoint("RIGHT", health, "RIGHT", 0, 0)
    bgT:SetPoint("TOPLEFT", health, "TOPLEFT", 0, 0)
    bgT:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", 0, 0)
    bgT:SetPoint("RIGHT", health, "RIGHT", 0, 0)
    local u = 1
    if isStripe then
        u = GetHealthBarWidth() / STRIPE_NATIVE_W
        if u > 1 then
            u = 1
        end
    end
    fillT:SetTexCoord(0, u, 0, 1)
    bgT:SetTexCoord(0, u, 0, 1)
end

-- Alpha for the empty (background) portion of an overlay. The "Full alpha on empty part of
-- bar" toggle matches the filled portion's opacity; else dimmed to 30% so fill reads as "more filled".
local function OverlayBgAlpha(fullFlag, fillAlpha)
    if fullFlag then
        return fillAlpha
    end
    return fillAlpha * 0.3
end

local function EnsureFocusOverlay(backing)
    if backing.focusClipFill then
        return
    end
    local overlayAlpha = (p and p.focusOverlayAlpha) or defaultSet.focusOverlayAlpha
    local overlayColor = (p and p.focusOverlayColor) or defaultSet.focusOverlayColor
    local STRIPE_TEX = "Interface\\AddOns\\CludesUINameplates\\Media\\striped-v2.png"
    local fillTex = backing.health:GetStatusBarTexture()
    backing.focusClipFill = CreateFrame("Frame", nil, backing.health)
    backing.focusClipFill:SetClipsChildren(true)
    -- Vertical bounds come from the health bar itself so the overlay never pixel-snaps 1px short; only the RIGHT edge tracks the fill.
    backing.focusClipFill:SetPoint("TOPLEFT", backing.health, "TOPLEFT", 0, 0)
    backing.focusClipFill:SetPoint("BOTTOMLEFT", backing.health, "BOTTOMLEFT", 0, 0)
    backing.focusClipFill:SetPoint("RIGHT", fillTex, "RIGHT", 0, 0)
    backing.focusClipFill:SetFrameLevel(backing.health:GetFrameLevel() + 1)
    backing.focusOverlayFill = backing.focusClipFill:CreateTexture(nil, "ARTWORK", nil, 2)
    -- Full bar height/width (anchored LEFT+RIGHT to health bar) so the diagonal pattern stays continuous across the split and snaps with the clip's edges.
    backing.focusOverlayFill:SetPoint("TOPLEFT", backing.health, "TOPLEFT", 0, 0)
    backing.focusOverlayFill:SetPoint("BOTTOMLEFT", backing.health, "BOTTOMLEFT", 0, 0)
    backing.focusOverlayFill:SetPoint("RIGHT", backing.health, "RIGHT", 0, 0)
    backing.focusOverlayFill:SetTexture(STRIPE_TEX)
    backing.focusOverlayFill:SetAlpha(overlayAlpha)
    backing.focusOverlayFill:SetVertexColor(overlayColor.r, overlayColor.g, overlayColor.b)
    backing.focusClipFill:Hide()
    backing.focusClipBg = CreateFrame("Frame", nil, backing.health)
    backing.focusClipBg:SetClipsChildren(true)
    backing.focusClipBg:SetPoint("TOPRIGHT", backing.health, "TOPRIGHT", 0, 0)
    backing.focusClipBg:SetPoint("BOTTOMRIGHT", backing.health, "BOTTOMRIGHT", 0, 0)
    backing.focusClipBg:SetPoint("LEFT", fillTex, "RIGHT", 0, 0)
    backing.focusClipBg:SetFrameLevel(backing.health:GetFrameLevel() + 1)
    backing.focusOverlayBg = backing.focusClipBg:CreateTexture(nil, "ARTWORK", nil, 1)
    backing.focusOverlayBg:SetPoint("TOPLEFT", backing.health, "TOPLEFT", 0, 0)
    backing.focusOverlayBg:SetPoint("BOTTOMLEFT", backing.health, "BOTTOMLEFT", 0, 0)
    backing.focusOverlayBg:SetPoint("RIGHT", backing.health, "RIGHT", 0, 0)
    backing.focusOverlayBg:SetTexture(STRIPE_TEX)
    backing.focusOverlayBg:SetAlpha(OverlayBgAlpha(p and p.focusOverlayFullBgAlpha, overlayAlpha))
    backing.focusOverlayBg:SetVertexColor(overlayColor.r, overlayColor.g, overlayColor.b)
    -- Creation-time texcoord for the STRIPE_TEX default; the state-gated apply re-runs it with the actual texture kind.
    ApplyOverlayGeometry(backing.focusOverlayFill, backing.focusOverlayBg, backing.health, true)
    backing.focusClipBg:Hide()
    -- Rounded corners: the new overlay joins the rounded body
    if backing._npRounded then
        mod.NP_ApplyRounding(backing, "health")
    end
end

mod.FOCUS_LETTER_ANCHORS = {
    CENTER = true,
    LEFT = true,
    RIGHT = true,
    TOP = true,
    BOTTOM = true,
    TOPLEFT = true,
    TOPRIGHT = true,
    BOTTOMLEFT = true,
    BOTTOMRIGHT = true,
}

function mod.GetFocusLetterAnchor(saved)
    local anchor = (saved and saved.focusLetterAnchor) or defaultSet.focusLetterAnchor
    return mod.FOCUS_LETTER_ANCHORS[anchor] and anchor or defaultSet.focusLetterAnchor
end

function mod.EnsureFocusLetter(backing)
    if backing.focusLetter then
        return
    end
    backing.focusLetter = backing.healthTextFrame:CreateFontString(nil, "OVERLAY")
    backing.focusLetter:SetJustifyH("CENTER")
    backing.focusLetter:SetJustifyV("MIDDLE")
    backing.focusLetter:Hide()
end

function mod.ApplyFocusLetter(backing, unitToken, saved)
    if saved.focusLetterEnabled == true and UnitIsUnit(unitToken, "focus") then
        mod.EnsureFocusLetter(backing)
        local size = saved.focusLetterSize or defaultSet.focusLetterSize
        local anchor = mod.GetFocusLetterAnchor(saved)
        local posX = saved.focusLetterX or defaultSet.focusLetterX
        local posY = saved.focusLetterY or defaultSet.focusLetterY
        local font = GetFont()
        local outline = GetNPOutline()
        if
            not backing._focusLetterShown
            or backing._focusLetterSize ~= size
            or backing._focusLetterAnchor ~= anchor
            or backing._focusLetterX ~= posX
            or backing._focusLetterY ~= posY
            or backing._focusLetterFont ~= font
            or backing._focusLetterOutline ~= outline
        then
            backing._focusLetterShown = true
            backing._focusLetterSize = size
            backing._focusLetterAnchor = anchor
            backing._focusLetterX = posX
            backing._focusLetterY = posY
            backing._focusLetterFont = font
            backing._focusLetterOutline = outline
            SetFSFont(backing.focusLetter, size, outline)
            backing.focusLetter:SetText("F")
            backing.focusLetter:ClearAllPoints()
            backing.focusLetter:SetPoint(anchor, backing.health, anchor, posX, posY)
            backing.focusLetter:SetTextColor(1, 1, 1, 1)
        end
        backing.focusLetter:Show()
    elseif backing.focusLetter then
        backing._focusLetterShown = nil
        backing.focusLetter:Hide()
    end
end

-------------------------------------------------------------------------------
--  Threat % text (WoW Forever only). ns._npTptOn = Forever and the profile
--  toggle, re-derived at login, by RefreshAllSettings and by RefreshThreatPct
--  (every setter of a threatPct key calls it), so UpdateHealthColor pays one
--  field read while it is off. The font string is made on first paint.
--  ns._npTgapOn is the Threat Gap mode on top of it (NP_PaintThreatGap).
-------------------------------------------------------------------------------
mod._npTptOn = false
mod._npTgapOn = false

function mod.NP_RefreshThreatPctFlag()
    mod._npTptOn = CludesUI.IS_FOREVER == true and p ~= nil and p.threatPctEnabled == true
    mod._npTgapOn = mod._npTptOn and p.threatPctMode == "gap"
end

function mod.EnsureThreatPctText(backing)
    if backing.threatPctText then
        return
    end
    backing.threatPctText = backing.healthTextFrame:CreateFontString(nil, "OVERLAY")
    backing.threatPctText:SetWordWrap(false)
    backing.threatPctText:Hide()
end

function mod.ApplyThreatPctPos(backing)
    mod.EnsureThreatPctText(backing)
    local saved = p or defaultSet
    local posKey = saved.threatPctPosition or defaultSet.threatPctPosition
    local slot = HP_BAR_SLOTS[(posKey == "RIGHT" and 1) or (posKey == "LEFT" and 2) or 3]
    local size = saved.threatPctSize or defaultSet.threatPctSize
    local xOff = saved.threatPctXOffset or defaultSet.threatPctXOffset
    local yOff = saved.threatPctYOffset or defaultSet.threatPctYOffset
    local font = GetFont()
    local outline = GetNPOutline()
    if
        backing._tptPos ~= posKey
        or backing._tptSize ~= size
        or backing._tptX ~= xOff
        or backing._tptY ~= yOff
        or backing._tptFont ~= font
        or backing._tptOutline ~= outline
    then
        backing._tptPos = posKey
        backing._tptSize = size
        backing._tptX = xOff
        backing._tptY = yOff
        backing._tptFont = font
        backing._tptOutline = outline
        SetFSFont(backing.threatPctText, size, outline)
        backing.threatPctText:ClearAllPoints()
        if slot.anchor == "CENTER" then
            backing.threatPctText:SetPoint("CENTER", backing.health, "CENTER", xOff, yOff)
        else
            Pix.Point(backing.threatPctText, slot.anchor, backing.health, slot.point, slot.xOff + xOff, yOff)
        end
        backing.threatPctText:SetJustifyH(slot.anchor)
    end
end

-- Percent and status are secret for nameplate units: the percent goes
-- straight to PaintThreatPct, never compared or stored. In Threat Gap mode
-- the target's plate is painted once per frame by the gap flush (gapNow),
-- the gap standing in for the percent while its values read plainly.
function mod.NP_UpdateThreatPct(backing, unitToken, gapNow)
    if mod._npTgapOn and backing._isTarget and not gapNow then
        mod.NP_RequestThreatGap(backing)
        return
    end
    local show = false
    if mod._npTptOn then
        local isTanking, status, pct = UnitDetailedThreatSituation("player", unitToken)
        if type(pct) == "number" then
            mod.ApplyThreatPctPos(backing)
            if not (mod._npTgapOn and backing._isTarget and mod.NP_PaintThreatGap(backing.threatPctText)) then
                CludesUI.PaintThreatPct(
                    backing.threatPctText,
                    pct,
                    status,
                    isTanking,
                    p.threatPctColorByThreat
                )
            end
            show = true
        end
    end
    if show ~= (backing._tptShown or false) then
        backing._tptShown = show or nil
        backing.threatPctText:SetShown(show)
    end
end

-------------------------------------------------------------------------------
--  Threat Gap (WoW Forever): the target's plate shows the flat threat between
--  you and the name you are measured against. Nameplate tokens read threat
--  values as secrets, so this reads through "target". Holding aggro: against
--  the next name on the table (group members and pets; your whole threat when
--  you are alone on it). Not holding it: against the holder, read directly when
--  they are in your group (the last holder's token is tried first, so a steady
--  fight costs one query), else from your percent of their threat. The colour
--  says who leads in raw threat. Returns false when a value reads secret, so
--  the caller paints the percent instead. The scan covers the group's own
--  tokens only, and the target plate's repaints run once per frame.
-------------------------------------------------------------------------------
do
    local RAID, PARTY = {}, { "pet" }
    for index = 1, 40 do
        RAID[#RAID + 1] = "raid" .. index
        RAID[#RAID + 1] = "raidpet" .. index
    end
    for index = 1, 4 do
        PARTY[#PARTY + 1] = "party" .. index
        PARTY[#PARTY + 1] = "partypet" .. index
    end
    local holderTok -- the group token that last held aggro on the target
    local flush, pending -- the once-per-frame repaint (built on first use) and its plate

    -- A frame's threat events collapse into one repaint after them: a hidden
    -- frame shown by the request, its OnUpdate hiding it before the paint.
    function mod.NP_RequestThreatGap(backing)
        pending = backing
        if not flush then
            flush = CreateFrame("Frame")
            flush:SetScript("OnUpdate", function(self)
                self:Hide()
                local pl = pending
                pending = nil
                if pl and pl.unit and pl._isTarget then
                    mod.NP_UpdateThreatPct(pl, pl.unit, true)
                end
            end)
        end
        flush:Show()
    end

    function mod.NP_PaintThreatGap(fontStr)
        local isTanking, _, _, rawPct, raw = UnitDetailedThreatSituation("player", "target")
        if
            issecretvalue(isTanking)
            or issecretvalue(rawPct)
            or issecretvalue(raw)
            or type(raw) ~= "number"
        then
            return false
        end
        local inRaid = IsInRaid()
        local entries = inRaid and RAID or PARTY
        -- The group's own tokens: raidN + raidpetN, or pet + partyN + partypetN.
        local num = GetNumGroupMembers()
        local last = inRaid and 2 * num or 1 + 2 * (num > 0 and num - 1 or 0)
        if last > #entries then
            last = #entries
        end
        local other
        if isTanking then
            other = 0
            for index = 1, last do
                local u = entries[index]
                if UnitExists(u) then
                    local me = UnitIsUnit(u, "player")
                    if issecretvalue(me) then
                        return false
                    end
                    if not me then
                        local _, _, _, _, region = UnitDetailedThreatSituation(u, "target")
                        if issecretvalue(region) then
                            return false
                        end
                        if region and region > other then
                            other = region
                        end
                    end
                end
            end
        else
            if holderTok then
                local t, _, _, _, region = UnitDetailedThreatSituation(holderTok, "target")
                if issecretvalue(t) or issecretvalue(region) then
                    return false
                end
                if t then
                    other = region
                end
            end
            if not other then
                holderTok = nil
                for index = 1, last do
                    local u = entries[index]
                    if UnitExists(u) then
                        local t, _, _, _, region = UnitDetailedThreatSituation(u, "target")
                        if issecretvalue(t) or issecretvalue(region) then
                            return false
                        end
                        if t then
                            holderTok, other = u, region
                            break
                        end
                    end
                end
            end
            if not other then
                if type(rawPct) ~= "number" or rawPct <= 0 then
                    return false
                end
                other = raw * 100 / rawPct
            end
        end
        local gap = raw - other
        local ahead = gap >= 0
        if not ahead then
            gap = -gap
        end
        local saved = p or defaultSet
        CludesUI.PaintThreatGap(
            fontStr,
            mod.AbbreviateNumbers(math.floor(gap + 0.5)),
            ahead,
            saved.threatPctColorByThreat,
            saved.threatGapAheadColor or defaultSet.threatGapAheadColor,
            saved.threatGapBehindColor or defaultSet.threatGapBehindColor
        )
        return true
    end
end

-- Options setters of every threatPct key: the flag, then layout and paint on
-- the live plates only (the layout memo compares every layout input).
function mod.RefreshThreatPct()
    mod.NP_RefreshThreatPctFlag()
    for _, backing in pairs(mod.plates) do
        if backing.unit and (mod._npTptOn or backing._tptShown) then
            mod.NP_UpdateThreatPct(backing, backing.unit)
        end
    end
end

mod.EnsureHoverOverlay = function(backing)
    if backing.hoverClipFill then
        return
    end
    local overlayAlpha = (p and p.hoverAlpha) or defaultSet.hoverAlpha
    local overlayColor = (p and p.hoverColor) or defaultSet.hoverColor
    local STRIPE_TEX = "Interface\\AddOns\\CludesUINameplates\\Media\\striped-v2.png"
    local fillTex = backing.health:GetStatusBarTexture()
    backing.hoverClipFill = CreateFrame("Frame", nil, backing.health)
    backing.hoverClipFill:SetClipsChildren(true)
    backing.hoverClipFill:SetPoint("TOPLEFT", backing.health, "TOPLEFT", 0, 0)
    backing.hoverClipFill:SetPoint("BOTTOMLEFT", backing.health, "BOTTOMLEFT", 0, 0)
    backing.hoverClipFill:SetPoint("RIGHT", fillTex, "RIGHT", 0, 0)
    backing.hoverClipFill:SetFrameLevel(backing.health:GetFrameLevel() + 1)
    backing.hoverOverlayFill = backing.hoverClipFill:CreateTexture(nil, "ARTWORK", nil, 2)
    backing.hoverOverlayFill:SetPoint("TOPLEFT", backing.health, "TOPLEFT", 0, 0)
    backing.hoverOverlayFill:SetPoint("BOTTOMLEFT", backing.health, "BOTTOMLEFT", 0, 0)
    backing.hoverOverlayFill:SetPoint("RIGHT", backing.health, "RIGHT", 0, 0)
    backing.hoverOverlayFill:SetTexture(STRIPE_TEX)
    backing.hoverOverlayFill:SetAlpha(overlayAlpha)
    backing.hoverOverlayFill:SetVertexColor(overlayColor.r, overlayColor.g, overlayColor.b)
    backing.hoverClipFill:Hide()
    backing.hoverClipBg = CreateFrame("Frame", nil, backing.health)
    backing.hoverClipBg:SetClipsChildren(true)
    backing.hoverClipBg:SetPoint("TOPRIGHT", backing.health, "TOPRIGHT", 0, 0)
    backing.hoverClipBg:SetPoint("BOTTOMRIGHT", backing.health, "BOTTOMRIGHT", 0, 0)
    backing.hoverClipBg:SetPoint("LEFT", fillTex, "RIGHT", 0, 0)
    backing.hoverClipBg:SetFrameLevel(backing.health:GetFrameLevel() + 1)
    backing.hoverOverlayBg = backing.hoverClipBg:CreateTexture(nil, "ARTWORK", nil, 1)
    backing.hoverOverlayBg:SetPoint("TOPLEFT", backing.health, "TOPLEFT", 0, 0)
    backing.hoverOverlayBg:SetPoint("BOTTOMLEFT", backing.health, "BOTTOMLEFT", 0, 0)
    backing.hoverOverlayBg:SetPoint("RIGHT", backing.health, "RIGHT", 0, 0)
    backing.hoverOverlayBg:SetTexture(STRIPE_TEX)
    backing.hoverOverlayBg:SetAlpha(OverlayBgAlpha(p and p.hoverOverlayFullBgAlpha, overlayAlpha))
    backing.hoverOverlayBg:SetVertexColor(overlayColor.r, overlayColor.g, overlayColor.b)
    -- Creation-time texcoord for the STRIPE_TEX default; the state-gated apply re-runs it with the actual texture kind.
    ApplyOverlayGeometry(backing.hoverOverlayFill, backing.hoverOverlayBg, backing.health, true)
    backing.hoverClipBg:Hide()
    -- Rounded corners: the new overlay joins the rounded body
    if backing._npRounded then
        mod.NP_ApplyRounding(backing, "health")
    end
end

mod.EnsureTargetOverlay = function(backing)
    if backing.targetClipFill then
        return
    end
    local overlayAlpha = (p and p.targetOverlayAlpha) or defaultSet.targetOverlayAlpha
    local overlayColor = (p and p.targetOverlayColor) or defaultSet.targetOverlayColor
    local STRIPE_TEX = "Interface\\AddOns\\CludesUINameplates\\Media\\striped-v2.png"
    local fillTex = backing.health:GetStatusBarTexture()
    backing.targetClipFill = CreateFrame("Frame", nil, backing.health)
    backing.targetClipFill:SetClipsChildren(true)
    -- Vertical bounds come from the health bar itself so the overlay never pixel-snaps 1px short; only the RIGHT edge tracks the fill.
    backing.targetClipFill:SetPoint("TOPLEFT", backing.health, "TOPLEFT", 0, 0)
    backing.targetClipFill:SetPoint("BOTTOMLEFT", backing.health, "BOTTOMLEFT", 0, 0)
    backing.targetClipFill:SetPoint("RIGHT", fillTex, "RIGHT", 0, 0)
    backing.targetClipFill:SetFrameLevel(backing.health:GetFrameLevel() + 1)
    backing.targetOverlayFill = backing.targetClipFill:CreateTexture(nil, "ARTWORK", nil, 2)
    -- Full bar height/width (anchored LEFT+RIGHT to health bar) so the diagonal pattern stays continuous across the split and snaps with the clip's edges.
    backing.targetOverlayFill:SetPoint("TOPLEFT", backing.health, "TOPLEFT", 0, 0)
    backing.targetOverlayFill:SetPoint("BOTTOMLEFT", backing.health, "BOTTOMLEFT", 0, 0)
    backing.targetOverlayFill:SetPoint("RIGHT", backing.health, "RIGHT", 0, 0)
    backing.targetOverlayFill:SetTexture(STRIPE_TEX)
    backing.targetOverlayFill:SetAlpha(overlayAlpha)
    backing.targetOverlayFill:SetVertexColor(overlayColor.r, overlayColor.g, overlayColor.b)
    backing.targetClipFill:Hide()
    backing.targetClipBg = CreateFrame("Frame", nil, backing.health)
    backing.targetClipBg:SetClipsChildren(true)
    backing.targetClipBg:SetPoint("TOPRIGHT", backing.health, "TOPRIGHT", 0, 0)
    backing.targetClipBg:SetPoint("BOTTOMRIGHT", backing.health, "BOTTOMRIGHT", 0, 0)
    backing.targetClipBg:SetPoint("LEFT", fillTex, "RIGHT", 0, 0)
    backing.targetClipBg:SetFrameLevel(backing.health:GetFrameLevel() + 1)
    backing.targetOverlayBg = backing.targetClipBg:CreateTexture(nil, "ARTWORK", nil, 1)
    backing.targetOverlayBg:SetPoint("TOPLEFT", backing.health, "TOPLEFT", 0, 0)
    backing.targetOverlayBg:SetPoint("BOTTOMLEFT", backing.health, "BOTTOMLEFT", 0, 0)
    backing.targetOverlayBg:SetPoint("RIGHT", backing.health, "RIGHT", 0, 0)
    backing.targetOverlayBg:SetTexture(STRIPE_TEX)
    backing.targetOverlayBg:SetAlpha(OverlayBgAlpha(p and p.targetOverlayFullBgAlpha, overlayAlpha))
    backing.targetOverlayBg:SetVertexColor(overlayColor.r, overlayColor.g, overlayColor.b)
    -- Creation-time texcoord for the STRIPE_TEX default; the state-gated apply re-runs it with the actual texture kind.
    ApplyOverlayGeometry(backing.targetOverlayFill, backing.targetOverlayBg, backing.health, true)
    backing.targetClipBg:Hide()
    -- Rounded corners: the new overlay joins the rounded body
    if backing._npRounded then
        mod.NP_ApplyRounding(backing, "health")
    end
end

-------------------------------------------------------------------------------
--  Color Casting Enemies: two tints over the health fill (the bar's own texture in each
--  color), Interruptible drawn above Uninterruptible so it wins once both were seen. The
--  plate remembers each kind as an alpha, folded C-side from the cast's interruptible flag
--  (SECRET in restricted combat): only ever passed to SetAlpha, never read in Lua.
-------------------------------------------------------------------------------
local CAST_INT_KEYS = {
    Normal = "castingIntNormal",
    Elite = "castingIntElite",
    MiniBoss = "castingIntMiniBoss",
    Boss = "castingIntBoss",
}
local CAST_UNINT_KEYS = {
    Normal = "castingUnintNormal",
    Elite = "castingUnintElite",
    MiniBoss = "castingUnintMiniBoss",
    Boss = "castingUnintBoss",
}

local function LayoutCastTint(t, fillTex, filePath)
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", fillTex, "TOPLEFT", 0, 0)
    t:SetPoint("BOTTOMRIGHT", fillTex, "BOTTOMRIGHT", 0, 0)
    t:SetTexture(filePath)
end

-- Anchors and texture follow the fill, which a health texture swap replaces.
function mod.NP_LayoutCastTints(backing)
    local fillTex = backing.health:GetStatusBarTexture()
    local key = (p and p.healthBarTexture) or defaultSet.healthBarTexture
    local filePath = CludesUI.ResolveTexturePath(mod.healthBarTextures, key, "Interface\\Buttons\\WHITE8x8")
    LayoutCastTint(backing.castTintUnint, fillTex, filePath)
    LayoutCastTint(backing.castTintInt, fillTex, filePath)
end

-- Bumped on settings changes (RefreshAllSettings, the options' RefreshAllPlates): each plate
-- repaints its tint colors once when its gen is stale.
local castTintGen = 0
function mod.NP_CastTintsDirty()
    castTintGen = castTintGen + 1
end

local function EnsureCastTints(backing)
    if backing.castTintInt then
        return
    end
    local health = backing.health
    backing.castTintUnint = health:CreateTexture(nil, "ARTWORK", nil, 1)
    backing.castTintInt = health:CreateTexture(nil, "ARTWORK", nil, 2)
    backing.castTintUnint:AddMaskTexture(backing._absorbMask)
    backing.castTintInt:AddMaskTexture(backing._absorbMask)
    backing.castTintUnint:Hide()
    backing.castTintInt:Hide()
    backing._castIntOn, backing._castUnintOn = false, false
    mod.NP_LayoutCastTints(backing)
    if backing._blizzBarMask then
        mod.NP_ApplyBlizzBarArt(backing)
    end
    if backing._npRounded then
        mod.NP_ApplyRounding(backing, "health")
    end
end

local function TierOn(keyList, tier)
    local val = p and p[keyList[tier]]
    if val == nil then
        val = defaultSet[keyList[tier]]
    end
    return val == true
end

-- tier: the mob type GetReactionColor marked (ns._reactionCastTier), nil to hide. lit: the unit
-- is plainly in combat (ns._reactionCastLit); else the colors darken like the bar's own
-- (Modify Out of Combat). fold: UpdateHealthColor folded the bar to Off-Tank Aggro (the answer
-- is SECRET); the tints take the same fold. Runs on every health color pass, so each setter
-- is change-checked, except while folded (secret colors, like the bar's own).
function mod.NP_ApplyCastTints(backing, tier, lit, fold)
    if tier == nil and not (p and p.castingEnemyColors) then
        -- Turned off: the plate forgets its casts, so its color passes stop calling here.
        backing._castSeen, backing._castIntA, backing._castUnintA = nil, nil, nil
    end
    local intOn = tier ~= nil and TierOn(CAST_INT_KEYS, tier)
    local unintOn = tier ~= nil and TierOn(CAST_UNINT_KEYS, tier)
    local ti, tu = backing.castTintInt, backing.castTintUnint
    if intOn or unintOn then
        if not ti then
            EnsureCastTints(backing)
            ti, tu = backing.castTintInt, backing.castTintUnint
            ti:SetAlpha(backing._castIntA or 0)
            tu:SetAlpha(backing._castUnintA or 0)
        end
        -- Folded: only the shown tints, each recomputed every pass (secret, uncached).
        -- A hidden one keeps a stale color; the gen reset below repaints it on the next
        -- plain pass.
        local folded = false
        if fold then
            local MaybeDarken = Inner.MaybeDarken
            local otc = Inner._C("offTankAggro")
            local success = true
            if intOn then
                local c = (p and p.castingIntColor) or defaultSet.castingIntColor
                local red, green, blue = MaybeDarken(c.r, c.g, c.b, lit)
                local okI
                okI, red, green, blue = mod.ComputeOffTankFold(backing.unit, red, green, blue, otc.r, otc.g, otc.b)
                if okI then
                    ti:SetVertexColor(red, green, blue)
                else
                    success = false
                end
            end
            if success and unintOn then
                local c = (p and p.castingUnintColor) or defaultSet.castingUnintColor
                local red, green, blue = MaybeDarken(c.r, c.g, c.b, lit)
                local okU
                okU, red, green, blue = mod.ComputeOffTankFold(backing.unit, red, green, blue, otc.r, otc.g, otc.b)
                if okU then
                    tu:SetVertexColor(red, green, blue)
                else
                    success = false
                end
            end
            -- Never cached: the next plain pass always repaints.
            backing._castTintGen = nil
            folded = success
        end
        if not folded and (backing._castTintGen ~= castTintGen or backing._castTintLit ~= lit) then
            backing._castTintGen, backing._castTintLit = castTintGen, lit
            local MaybeDarken = Inner.MaybeDarken
            local ic = (p and p.castingIntColor) or defaultSet.castingIntColor
            local uc = (p and p.castingUnintColor) or defaultSet.castingUnintColor
            ti:SetVertexColor(MaybeDarken(ic.r, ic.g, ic.b, lit))
            tu:SetVertexColor(MaybeDarken(uc.r, uc.g, uc.b, lit))
        end
    elseif not ti then
        return
    end
    if backing._castIntOn ~= intOn then
        backing._castIntOn = intOn
        ti:SetShown(intOn)
    end
    if backing._castUnintOn ~= unintOn then
        backing._castUnintOn = unintOn
        tu:SetShown(unintOn)
    end
end

-- A cast's start or interruptible flip (kickProtected: true = cannot be interrupted, maybe
-- SECRET). Each kind's alpha turns 1 once seen and stays 1 while the mob holds the plate;
-- the alphas change only here.
function mod.NP_NoteCastKind(backing, kickProtected)
    local eval = C_CurveUtil.EvaluateColorValueFromBoolean
    -- _castSeen: nil = not checked yet, false = a player (never tinted), true = noted.
    local seen = backing._castSeen
    if seen == false then
        return
    end
    local first = seen == nil
    if first then
        -- Never players (an enemy player's class color stays); checked once per unit.
        if UnitIsPlayer(backing.unit) then
            backing._castSeen = false
            return
        end
        backing._castSeen = true
        backing._castIntA, backing._castUnintA = 0, 0
    end
    backing._castIntA = eval(kickProtected, backing._castIntA, 1)
    backing._castUnintA = eval(kickProtected, 1, backing._castUnintA)
    if backing.castTintInt then
        backing.castTintInt:SetAlpha(backing._castIntA)
        backing.castTintUnint:SetAlpha(backing._castUnintA)
    end
    if first then
        backing:UpdateHealthColor()
    end
end

-- The plate's unit left (ClearUnit) or changed (the token swap): forget its casts.
function mod.NP_ResetCastKind(backing)
    backing._castSeen, backing._castIntA, backing._castUnintA = nil, nil, nil
    mod.NP_ApplyCastTints(backing, nil)
end

Inner.ApplyOverlayGeometry, Inner.EnsureArrows = ApplyOverlayGeometry, EnsureArrows
Inner.EnsureFocusOverlay, Inner.EnsureGlow = EnsureFocusOverlay, EnsureGlow
Inner.EnsureTargetHighlight, Inner.OverlayBgAlpha = EnsureTargetHighlight, OverlayBgAlpha
Inner.broken = false
