if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_Nameplates_ClassPower.lua
--
--  Class power on the target plate.
--  Reads the earlier nameplate files through ns and ns._npInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._npInternals
-- CludesUINameplates.lua or an earlier nameplate file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local type = type
local Pix = CludesUI.PP
local UnitHealthMax = UnitHealthMax
local C_UnitAuras = C_UnitAuras
local UnitIsUnit = UnitIsUnit
local Enum = Enum
local _, PLAYER_CLASS = UnitClass("player")

local defaultSet, GetClassPowerClassColors = Inner.defaults, Inner.GetClassPowerClassColors
local GetClassPowerCustomColor = Inner.GetClassPowerCustomColor
local GetShowClassPower, SetClassPowerTopPush = Inner.GetShowClassPower, Inner.SetClassPowerTopPush

local p
Inner.profileSetters[#Inner.profileSetters + 1] = function(val)
    p = val
end

-- Assigned below; Layout holds the forward declaration its own readers use.
local GetClassPowerTopPush
-- Name and Cast keep a copy of classPowerType and add a setter to
-- I.classPowerTypeSetters.
local SetClassPowerType = Inner.SetClassPowerType

-------------------------------------------------------------------------------
--  Class Power Display (combo points, holy power, chi, etc.). Zero cost when disabled: no
--  events registered, no frames created. When on, a single watcher handles player
--  UNIT_POWER_UPDATE and shows pips only on the current target's nameplate.
-------------------------------------------------------------------------------
local classPowerWatcher
local classPowerWatcherFrame -- created on first enable, reused after every disable
local classPowerType -- Enum.PowerType value for the player's class resource, or nil
local classPowerMax = 0 -- max pips for the resource
local classPowerFormReq -- required GetShapeshiftFormID() value, or nil if no form check needed
local CP_PIP_W, CP_PIP_H, CP_PIP_GAP = 8, 3, 2 -- pip geometry

-- Optional pip shapes. Rectangle (default) and square are plain boxes (no mask); the rest are
-- carved from a square fill by a portrait-set mask with a matching border texture (same shape
-- art as the Cooldown Manager). On ns (cap).
mod.CP_SHAPE = {
    WHITE = "Interface\\Buttons\\WHITE8X8",
    MASKS = {
        circle = "Interface\\AddOns\\CludesUI\\media\\portraits\\circle_mask.tga",
        diamond = "Interface\\AddOns\\CludesUI\\media\\portraits\\diamond_mask.tga",
        hexagon = "Interface\\AddOns\\CludesUI\\media\\portraits\\hexagon_mask.tga",
        shield = "Interface\\AddOns\\CludesUI\\media\\portraits\\shield_mask.tga",
    },
    BORDERS = {
        circle = "Interface\\AddOns\\CludesUI\\media\\portraits\\circle_border.tga",
        diamond = "Interface\\AddOns\\CludesUI\\media\\portraits\\diamond_border.tga",
        hexagon = "Interface\\AddOns\\CludesUI\\media\\portraits\\hexagon_border.tga",
        shield = "Interface\\AddOns\\CludesUI\\media\\portraits\\shield_border.tga",
    },
    -- Shapes drawn on a 1:1 (square) footprint instead of the wide pip rectangle.
    SQUARE = { square = true, circle = true, diamond = true, hexagon = true, shield = true },
}

-- Resource-icon shapes: real Blizzard atlas art instead of a tinted shape. On ns.
mod.CP_ICON_SHAPE = {
    rune = true,
    holypower = true,
    shard = true,
    combo = true,
    chi = true,
    arcane = true,
    essence = true,
}
-- Single-atlas resources have no distinct empty art, so dim their empty pips.
mod.CP_ICON_DIM_EMPTY = { arcane = true }
mod.CP_RUNE_SPEC = { [250] = "Blood", [251] = "Frost", [252] = "Unholy" }
-- Icon kind for a shape ("rune", "holypower", "essence", etc.), or nil if geometric.
function mod.GetPipIconKind(shape)
    return mod.CP_ICON_SHAPE[shape] and shape or nil
end
-- Atlas for a pip of the given icon kind, filled (active) or empty (background).
function mod.GetPipIconAtlas(kind, filled, index)
    if kind == "shard" then
        return filled and "Warlock-ReadyShard" or "Warlock-EmptyShard"
    elseif kind == "rune" then
        if not filled then
            return "DK-Rune-CD"
        end
        local specInfo = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization()
        local specID = specInfo and C_SpecializationInfo.GetSpecializationInfo(specInfo)
        return "DK-" .. (mod.CP_RUNE_SPEC[specID or 0] or "Blood") .. "-Rune-Ready"
    elseif kind == "combo" then
        return filled and "uf-roguecp-icon-red" or "uf-roguecp-bg"
    elseif kind == "chi" then
        return filled and "uf-chi-icon" or "uf-chi-bg"
    elseif kind == "arcane" then
        return "Mage-ArcaneCharge" -- one atlas for both states; empty is dimmed by the caller
    elseif kind == "essence" then
        return filled and "UF-Essence-Icon-Active" or "UF-Essence-BG"
    end
    return nil
end

-- Class/power color from the CUI global system. Bar-type keys (_BAR suffix)
-- return the power color; class resources return resource color > class color.
local CP_DEFAULT_COLOR = { 1.00, 0.84, 0.30 }
local function GetClassPipColor(class, powerKey)
    if CludesUI then
        if powerKey then
            local alias = powerKey:match("^(.+)_BAR$")
            local key = alias or powerKey
            local c = CludesUI.GetPowerColor(key)
            if c then
                return { c.r, c.g, c.b }
            end
        end
        local rc = CludesUI.GetResourceColor(class)
        if rc then
            return { rc.r, rc.g, rc.b }
        end
        local cc = CludesUI.GetClassColor(class)
        if cc then
            return { cc.r, cc.g, cc.b }
        end
    end
    return CP_DEFAULT_COLOR
end

-- Map class { powerType, maxPips (fallback) }; entries can be simple { type, max } or spec-keyed { [specID] = { type, max } }.
local CLASS_POWER_MAP = {
    ROGUE = { Enum.PowerType.ComboPoints, 5 },
    DRUID = {
        [103] = { Enum.PowerType.ComboPoints, 5 }, -- Feral (always)
        [105] = { Enum.PowerType.ComboPoints, 5 },
    }, -- Resto (cat form only)
    PALADIN = { Enum.PowerType.HolyPower, 5 },
    MONK = { [268] = { "BREWMASTER_STAGGER", 1 }, [269] = { Enum.PowerType.Chi, 5 } },
    WARLOCK = { Enum.PowerType.SoulShards, 5 },
    MAGE = {
        [62] = { Enum.PowerType.ArcaneCharges, 4 }, -- Arcane
        [64] = { "ICICLES", 5 },
    }, -- Frost
    EVOKER = { Enum.PowerType.Essence, 5 },
    DEMONHUNTER = {
        [581] = { "SOUL_FRAGMENTS_VENGEANCE", 6 },
        [1480] = { "SOUL_FRAGMENTS_DEVOURER", 50 },
    },
    SHAMAN = { [263] = { "MAELSTROM_WEAPON", 10 } }, -- Enhancement only
    PRIEST = { [258] = { "INSANITY_BAR", 100 } }, -- Shadow only
    HUNTER = { [255] = { "TIP_OF_THE_SPEAR", 3 } }, -- Survival only
    WARRIOR = {
        [72] = { "WHIRLWIND_STACKS", 4 }, -- Fury
        [71] = { "SWEEPING_STRIKES", 18 },
    }, -- Arms (12.1 cap: 12 + 6 Broad Strokes)
    DEATHKNIGHT = {
        [250] = { Enum.PowerType.Runes, 6 },
        [251] = { Enum.PowerType.Runes, 6 },
        [252] = { Enum.PowerType.Runes, 6 },
    },
}

-- Apply the configured shape + optional border to one pip (and its bg). rectangle/square: plain
-- box, no mask, border = one solid box behind the pip. Other shapes: carve fill+bg with a mask,
-- frame with the matching border texture. Idempotent. bSize is pip-local (pixel-snapped) units.
function mod.ApplyPipShape(backing, pip, shape, borderOn, bc, bSize)
    local backdrop = pip._bg
    -- Icon shapes draw real atlas art (set in the render): drop mask, borders, and the dark bg.
    if mod.CP_ICON_SHAPE[shape] then
        if pip._shapeMask then
            pcall(pip.RemoveMaskTexture, pip, pip._shapeMask)
            if backdrop then
                pcall(backdrop.RemoveMaskTexture, backdrop, pip._shapeMask)
            end
            pip._shapeMask:Hide()
        end
        if pip._border then
            pip._border:Hide()
        end
        if pip._borderBox then
            pip._borderBox:Hide()
        end
        if backdrop then
            backdrop:Hide()
        end
        return
    end
    local maskPath = mod.CP_SHAPE.MASKS[shape]
    if maskPath then
        if not pip._shapeMask then
            pip._shapeMask = backing:CreateMaskTexture()
        end
        local m = pip._shapeMask
        m:SetTexture(maskPath, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m:ClearAllPoints()
        m:SetAllPoints(pip)
        m:Show()
        pcall(pip.RemoveMaskTexture, pip, m)
        pip:AddMaskTexture(m)
        if backdrop then
            pcall(backdrop.RemoveMaskTexture, backdrop, m)
            backdrop:AddMaskTexture(m)
        end
    elseif pip._shapeMask then
        pcall(pip.RemoveMaskTexture, pip, pip._shapeMask)
        if backdrop then
            pcall(backdrop.RemoveMaskTexture, backdrop, pip._shapeMask)
        end
        pip._shapeMask:Hide()
    end

    local borderPath = mod.CP_SHAPE.BORDERS[shape]
    if borderOn and borderPath then
        -- Masked shapes: matching outline texture, sized to the pip.
        if not pip._border then
            pip._border = backing:CreateTexture(nil, "OVERLAY", nil, 4)
        end
        local b = pip._border
        b:SetTexture(borderPath)
        b:SetVertexColor(bc.r, bc.g, bc.b, bc.a or 1)
        b:ClearAllPoints()
        b:SetAllPoints(pip)
        b:Show()
        if pip._borderBox then
            pip._borderBox:Hide()
        end
    elseif borderOn then
        -- Boxy shapes (rectangle/square): one solid box behind the pip, poking out bSize on
        -- every side as a uniform outline. A single texture rounds as one piece, staying crisp.
        if pip._border then
            pip._border:Hide()
        end
        if not pip._borderBox then
            pip._borderBox = backing:CreateTexture(nil, "OVERLAY", nil, 1)
            pip._borderBox:SetTexture(mod.CP_SHAPE.WHITE)
        end
        local box = pip._borderBox
        box:SetVertexColor(bc.r, bc.g, bc.b, bc.a or 1)
        box:ClearAllPoints()
        box:SetPoint("TOPLEFT", pip, "TOPLEFT", -bSize, bSize)
        box:SetPoint("BOTTOMRIGHT", pip, "BOTTOMRIGHT", bSize, -bSize)
        box:Show()
    else
        if pip._border then
            pip._border:Hide()
        end
        if pip._borderBox then
            pip._borderBox:Hide()
        end
    end
end

-- Hide a pip's shape decorations (textured border + solid border box).
function mod.HidePipDecor(pip)
    if pip._border then
        pip._border:Hide()
    end
    if pip._borderBox then
        pip._borderBox:Hide()
    end
end

-- Lazy-create pip textures on a plate (done once, then reused via show/hide)
local function EnsureClassPowerPips(backing)
    if backing._cpPips then
        return
    end
    backing._cpPips = {}
    local maxPossible = 10 -- safe upper bound (Maelstrom Weapon = 10)
    for i = 1, maxPossible do
        local backdrop = backing:CreateTexture(nil, "OVERLAY", nil, 2)
        backdrop:SetTexture(mod.CP_SHAPE.WHITE)
        backdrop:SetVertexColor(0.082, 0.082, 0.082, 1)
        backdrop:Hide()
        local pip = backing:CreateTexture(nil, "OVERLAY", nil, 3)
        pip:SetTexture(mod.CP_SHAPE.WHITE)
        pip:SetVertexColor(1, 1, 1, 1)
        Pix.Size(pip, CP_PIP_W, CP_PIP_H)
        pip:Hide()
        pip._bg = backdrop
        backing._cpPips[i] = pip
    end
end

-- Lazy-create a single StatusBar for bar-type class resources (e.g. stagger)
local function EnsureClassPowerBar(backing)
    if backing._cpBar then
        return
    end
    local bar = CreateFrame("StatusBar", nil, backing)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    bar:SetFrameLevel(backing:GetFrameLevel() + 5)
    bar:Hide()
    -- Background texture behind the bar
    local backdrop = bar:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    backdrop:SetColorTexture(0.082, 0.082, 0.082, 1)
    bar._bg = backdrop
    backing._cpBar = bar
end

-- Update pip display on a plate (or hide if plate is nil)
local function UpdateClassPowerOnPlate(backing)
    if not backing or not backing._cpPips then
        return
    end
    if not classPowerType or (classPowerFormReq and GetShapeshiftFormID() ~= classPowerFormReq) then
        for i = 1, #backing._cpPips do
            backing._cpPips[i]:Hide()
            if backing._cpPips[i]._bg then
                backing._cpPips[i]._bg:Hide()
            end
        end
        if backing._cpBar then
            backing._cpBar:Hide()
        end
        if _G._EWC then
            _G._EWC.Gate("np")
        end
        return
    end

    local cpScale = mod.GetClassPowerScale()
    local cpYOff = mod.GetClassPowerYOffset()
    local cpXOff = mod.GetClassPowerXOffset()
    local cpPos = mod.GetClassPowerPos()
    local bgCol = mod.GetClassPowerBgColor()

    -- Determine anchor: top or bottom of health bar, with cast bar avoidance
    local anchorPoint, anchorRelPoint, anchor, yDir
    if cpPos == "top" then
        anchorPoint = "BOTTOM"
        anchorRelPoint = "TOP"
        anchor = backing.health
        yDir = 1
    else
        if backing.isCasting and backing.cast:IsShown() then
            anchorPoint = "TOP"
            anchorRelPoint = "BOTTOM"
            anchor = backing.cast
            yDir = -1
        else
            anchorPoint = "TOP"
            anchorRelPoint = "BOTTOM"
            anchor = backing.health
            yDir = -1
        end
    end

    -- Bar-type resource (Brewmaster Stagger): single StatusBar instead of pips
    if classPowerType == "BREWMASTER_STAGGER" then
        -- Hide all pips
        for i = 1, #backing._cpPips do
            backing._cpPips[i]:Hide()
            if backing._cpPips[i]._bg then
                backing._cpPips[i]._bg:Hide()
            end
            if backing._cpPips[i]._secretBar then
                backing._cpPips[i]._secretBar:Hide()
            end
        end
        EnsureClassPowerBar(backing)
        local bar = backing._cpBar
        local staggerCur = UnitStagger("player")
        local staggerMax = UnitHealthMax("player")
        local isSecretVal = issecretvalue and (issecretvalue(staggerCur) or issecretvalue(staggerMax))
        if not staggerCur then
            staggerCur = 0
        end
        if not staggerMax or staggerMax <= 0 then
            staggerMax = 1
        end

        local scaledW = CP_PIP_W * cpScale * 6 -- bar width: ~6 pips wide
        local scaledH = CP_PIP_H * cpScale
        bar:ClearAllPoints()
        bar:SetSize(scaledW, scaledH)
        bar:SetPoint(anchorPoint, anchor, anchorRelPoint, cpXOff, yDir * cpYOff)
        bar:SetMinMaxValues(0, staggerMax)
        bar:SetValue(staggerCur)

        -- Stagger color thresholds: green < 30%, yellow 30-60%, red > 60%
        if isSecretVal then
            -- Secret value: can't compare, use class color
            local cpColor = GetClassPipColor(PLAYER_CLASS)
            if not GetClassPowerClassColors() then
                local cc = GetClassPowerCustomColor()
                cpColor = { cc.r, cc.g, cc.b }
            end
            bar:SetStatusBarColor(cpColor[1], cpColor[2], cpColor[3], 1)
        else
            local pct = staggerCur / staggerMax
            if pct >= 0.6 then
                bar:SetStatusBarColor(1.0, 0.2, 0.2, 1) -- red (heavy)
            elseif pct >= 0.3 then
                bar:SetStatusBarColor(1.0, 0.85, 0.2, 1) -- yellow (moderate)
            else
                bar:SetStatusBarColor(0.2, 0.8, 0.2, 1) -- green (light)
            end
        end

        bar._bg:SetColorTexture(bgCol.r, bgCol.g, bgCol.b, bgCol.a)
        bar:Show()
        return
    end

    -- Bar-type resource (Shadow Priest Insanity): single StatusBar
    if classPowerType == "INSANITY_BAR" then
        for i = 1, #backing._cpPips do
            backing._cpPips[i]:Hide()
            if backing._cpPips[i]._bg then
                backing._cpPips[i]._bg:Hide()
            end
            if backing._cpPips[i]._secretBar then
                backing._cpPips[i]._secretBar:Hide()
            end
        end
        EnsureClassPowerBar(backing)
        local bar = backing._cpBar
        local current = UnitPower("player", 13) or 0 -- Enum.PowerType.Insanity = 13
        local maxI = UnitPowerMax("player", 13) or 100
        if issecretvalue and issecretvalue(maxI) then
            maxI = 100
        end
        if not maxI or maxI <= 0 then
            maxI = 100
        end

        local scaledW = CP_PIP_W * cpScale * 6
        local scaledH = CP_PIP_H * cpScale
        bar:ClearAllPoints()
        bar:SetSize(scaledW, scaledH)
        bar:SetPoint(anchorPoint, anchor, anchorRelPoint, cpXOff, yDir * cpYOff)
        bar:SetMinMaxValues(0, maxI)
        bar:SetValue(current)

        local cpColor = GetClassPipColor(PLAYER_CLASS, "INSANITY_BAR")
        if not GetClassPowerClassColors() then
            local cc = GetClassPowerCustomColor()
            cpColor = { cc.r, cc.g, cc.b }
        end
        bar:SetStatusBarColor(cpColor[1], cpColor[2], cpColor[3], 1)

        bar._bg:SetColorTexture(bgCol.r, bgCol.g, bgCol.b, bgCol.a)
        bar:Show()
        return
    end

    -- Bar-type resource (Hunter Focus for BM/MM): single StatusBar
    if classPowerType == "FOCUS_BAR" then
        for i = 1, #backing._cpPips do
            backing._cpPips[i]:Hide()
            if backing._cpPips[i]._bg then
                backing._cpPips[i]._bg:Hide()
            end
            if backing._cpPips[i]._secretBar then
                backing._cpPips[i]._secretBar:Hide()
            end
        end
        EnsureClassPowerBar(backing)
        local bar = backing._cpBar
        local current = UnitPower("player", 2) or 0 -- Enum.PowerType.Focus = 2
        local maxF = UnitPowerMax("player", 2) or 100
        if issecretvalue and issecretvalue(maxF) then
            maxF = 100
        end
        if not maxF or maxF <= 0 then
            maxF = 100
        end

        local scaledW = CP_PIP_W * cpScale * 6
        local scaledH = CP_PIP_H * cpScale
        bar:ClearAllPoints()
        bar:SetSize(scaledW, scaledH)
        bar:SetPoint(anchorPoint, anchor, anchorRelPoint, cpXOff, yDir * cpYOff)
        bar:SetMinMaxValues(0, maxF)
        bar:SetValue(current)

        local cpColor = GetClassPipColor(PLAYER_CLASS, "FOCUS_BAR")
        if not GetClassPowerClassColors() then
            local cc = GetClassPowerCustomColor()
            cpColor = { cc.r, cc.g, cc.b }
        end
        bar:SetStatusBarColor(cpColor[1], cpColor[2], cpColor[3], 1)

        bar._bg:SetColorTexture(bgCol.r, bgCol.g, bgCol.b, bgCol.a)
        bar:Show()
        return
    end

    -- Bar-type resource (Devourer soul fragments): single StatusBar
    if classPowerType == "SOUL_FRAGMENTS_DEVOURER" then
        for i = 1, #backing._cpPips do
            backing._cpPips[i]:Hide()
            if backing._cpPips[i]._bg then
                backing._cpPips[i]._bg:Hide()
            end
            if backing._cpPips[i]._secretBar then
                backing._cpPips[i]._secretBar:Hide()
            end
        end
        EnsureClassPowerBar(backing)
        local bar = backing._cpBar
        local current, maxC = 0, 50
        if CludesUI and CludesUI.GetSoulFragments then
            current, maxC = CludesUI.GetSoulFragments()
            if not maxC or maxC <= 0 then
                maxC = 50
            end
        end

        local scaledW = CP_PIP_W * cpScale * 6
        local scaledH = CP_PIP_H * cpScale
        bar:ClearAllPoints()
        bar:SetSize(scaledW, scaledH)
        bar:SetPoint(anchorPoint, anchor, anchorRelPoint, cpXOff, yDir * cpYOff)
        bar:SetMinMaxValues(0, maxC)
        bar:SetValue(current or 0)

        local cpColor = GetClassPipColor(PLAYER_CLASS)
        if not GetClassPowerClassColors() then
            local cc = GetClassPowerCustomColor()
            cpColor = { cc.r, cc.g, cc.b }
        end
        bar:SetStatusBarColor(cpColor[1], cpColor[2], cpColor[3], 1)

        bar._bg:SetColorTexture(bgCol.r, bgCol.g, bgCol.b, bgCol.a)
        bar:Show()
        return
    end

    -- Hide bar if switching from bar-type to pip-type
    if backing._cpBar then
        backing._cpBar:Hide()
    end

    local current, maxP
    local isSecret = false
    local npEngine = false
    if classPowerType == "SOUL_FRAGMENTS_VENGEANCE" then
        current = C_Spell and C_Spell.GetSpellCastCount and C_Spell.GetSpellCastCount(228477) or 0
        maxP = 6
        isSecret = true
    elseif classPowerType == "MAELSTROM_WEAPON" then
        current, maxP = CludesUI.GetMaelstromWeapon()
    elseif classPowerType == "TIP_OF_THE_SPEAR" then
        current, maxP = CludesUI.GetTipOfTheSpear()
    elseif classPowerType == "WHIRLWIND_STACKS" or classPowerType == "SWEEPING_STRIKES" then
        -- Engine-slot display only (the cast-count simulator is retired):
        -- shared geometry below sizes the overlay, the pre-loop handoff
        -- positions it. Shaped/icon pip styles render the rectangle overlay
        -- for these two powers. Until the deferred build lands, Arm queues
        -- it and the row shows empty.
        if _G._EWC and _G._EWC.EngineOn("np", classPowerType) then
            npEngine = true
            current, maxP = 0, _G._EWC.MaxApps(classPowerType)
        else
            if _G._EWC and mod._WCNP_Arm then
                mod._WCNP_Arm(classPowerType)
            end
            for i = 1, #backing._cpPips do
                backing._cpPips[i]:Hide()
                if backing._cpPips[i]._bg then
                    backing._cpPips[i]._bg:Hide()
                end
            end
            return
        end
    elseif classPowerType == "ICICLES" then
        local total = 0
        if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
            local aura = C_UnitAuras.GetPlayerAuraBySpellID(205473)
            if aura then
                total = aura.applications or aura.charges or 0
                if total > 5 then
                    total = 5
                end
            end
        end
        current, maxP = total, 5
    else
        -- Forever combo points belong to the target, and UnitPower still reports
        -- the previous target's count at the moment PLAYER_TARGET_CHANGED fires
        -- (measured on 1.60.1: up=3 while gcp=0 on the swap), with no later power
        -- event to correct it. Blizzard's own ComboFrame reads GetComboPoints.
        if
            CludesUI.IS_FOREVER == true
            and classPowerType == Enum.PowerType.ComboPoints
            and GetComboPoints
        then
            current = GetComboPoints("player", "target") or 0
        else
            current = UnitPower("player", classPowerType) or 0
        end
        maxP = UnitPowerMax("player", classPowerType) or classPowerMax
        if maxP <= 0 then
            maxP = classPowerMax
        end
        -- Runes: UnitPower doesn't return ready-rune count; iterate cooldowns
        if classPowerType == Enum.PowerType.Runes then
            current = 0
            for i = 1, maxP do
                local _, _, ready = GetRuneCooldown(i)
                if ready then
                    current = current + 1
                end
            end
        end
    end
    -- The resource kind alone does not decide this: which values the client
    -- classifies depends on the client, and combo points come back secret on
    -- Forever. The pip fill below compares against cur, which raises on one.
    if not isSecret and issecretvalue and issecretvalue(current) then
        isSecret = true
    end
    if maxP <= 0 then
        for i = 1, #backing._cpPips do
            backing._cpPips[i]:Hide()
            if backing._cpPips[i]._bg then
                backing._cpPips[i]._bg:Hide()
            end
        end
        return
    end

    -- Lock pip width/height/gap to exact physical pixel multiples in the PLATE'S local coords
    -- (pips are parented to the plate, so its effective scale decides screen pixels). PP.Scale
    -- snaps to UIParent's grid, wrong here: nameplates have their own scale stack.
    local cpShape = mod.GetClassPowerShape()
    local cpBorderOn = mod.GetClassPowerBorder()
    local cpBorderCol = mod.GetClassPowerBorderColor()
    -- isSecret (DH Vengeance partial fill) keeps a plain rectangle: its StatusBar
    -- overlay can't follow a shape mask cleanly.
    if isSecret then
        cpShape = "rectangle"
    end
    -- Icon shapes (rune/holypower/shard) draw real Blizzard art.
    local iconKind = mod.GetPipIconKind(cpShape)
    local squareShape = mod.CP_SHAPE.SQUARE[cpShape] or (iconKind ~= nil)
    local plateES = backing:GetEffectiveScale()
    local onePx = (plateES and plateES > 0) and (Pix.perfect / plateES) or Pix.mult or 1
    local pipWPx = math.floor((CP_PIP_W * cpScale) / onePx + 0.5)
    -- Non-rectangle shapes render on a square footprint (1:1).
    local pipHPx = squareShape and pipWPx or math.floor((CP_PIP_H * cpScale) / onePx + 0.5)
    local pipGapPx = math.floor((mod.GetClassPowerGap() * cpScale) / onePx + 0.5)
    local borderPx = cpBorderOn and (mod.GetClassPowerBorderSize() * onePx) or 0
    local scaledW = pipWPx * onePx
    local scaledH = pipHPx * onePx
    local scaledGap = pipGapPx * onePx
    local stride = scaledW + scaledGap
    local groupW = maxP * scaledW + (maxP - 1) * scaledGap
    local halfGroup = math.floor((groupW / 2) / onePx + 0.5) * onePx

    local cpColor = CP_DEFAULT_COLOR
    if GetClassPowerClassColors() then
        cpColor = GetClassPipColor(PLAYER_CLASS)
    else
        local cc = GetClassPowerCustomColor()
        cpColor = { cc.r, cc.g, cc.b }
    end

    local emptyCol = mod.GetClassPowerEmptyColor()

    local leftAnchor = (anchorPoint == "BOTTOM") and "BOTTOMLEFT" or "TOPLEFT"

    -- Engine-owned warrior charge fill: size and anchor the shared overlay
    -- from the same math the pips would use, hand over the resolved color,
    -- park the legacy pips, and stop before any value work.
    if npEngine and mod._WCNP_Attach then
        mod._WCNP_Attach(
            anchor,
            anchorRelPoint,
            leftAnchor,
            cpXOff - halfGroup,
            yDir * cpYOff,
            groupW,
            scaledH,
            scaledW,
            scaledGap,
            plateES,
            cpColor,
            emptyCol,
            bgCol,
            classPowerType
        )
        for i = 1, #backing._cpPips do
            local pip = backing._cpPips[i]
            pip:Hide()
            if pip._bg then
                pip._bg:Hide()
            end
            if pip._secretBar then
                pip._secretBar:Hide()
            end
            mod.HidePipDecor(pip)
        end
        if backing._cpBar then
            backing._cpBar:Hide()
        end
        return
    end

    for i = 1, #backing._cpPips do
        local pip = backing._cpPips[i]
        if i <= maxP then
            pip:ClearAllPoints()
            pip:SetSize(scaledW, scaledH)
            -- (i-1)*stride is an exact integer multiple of physical pixels, so every pip lands on the same grid.
            local pipLeftX = (i - 1) * stride - halfGroup + cpXOff
            pip:SetPoint(leftAnchor, anchor, anchorRelPoint, pipLeftX, yDir * cpYOff)

            -- Background texture behind each pip
            local backdrop = pip._bg
            if backdrop then
                backdrop:ClearAllPoints()
                backdrop:SetAllPoints(pip)
                -- Reset from any prior icon socket; holy power re-sets these below.
                backdrop:SetTexture(mod.CP_SHAPE.WHITE)
                backdrop:SetTexCoord(0, 1, 0, 1)
                backdrop:SetDesaturated(false)
                backdrop:SetVertexColor(bgCol.r, bgCol.g, bgCol.b, bgCol.a)
                backdrop:Show()
            end

            -- Shape mask + optional border (size/anchor final by now). Skipped entirely on the
            -- untouched default (plain rectangle, no border, no prior shape decor) so users who
            -- never enable a shape pay nothing; a pip that ever had a mask/border keeps those
            -- fields so it still routes through ApplyPipShape to clean up when reverted.
            if cpShape ~= "rectangle" or cpBorderOn or pip._shapeMask or pip._border or pip._borderBox then
                mod.ApplyPipShape(backing, pip, cpShape, cpBorderOn, cpBorderCol, borderPx)
            end

            if isSecret then
                if not pip._secretBar then
                    local scrollBar = CreateFrame("StatusBar", nil, backing)
                    scrollBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
                    scrollBar:SetFrameLevel(backing:GetFrameLevel() + 5)
                    pip._secretBar = scrollBar
                end
                local scrollBar = pip._secretBar
                scrollBar:ClearAllPoints()
                scrollBar:SetAllPoints(pip)
                scrollBar:SetMinMaxValues(i - 1, i)
                scrollBar:SetValue(current)
                scrollBar:SetStatusBarColor(cpColor[1], cpColor[2], cpColor[3], 1)
                scrollBar:Show()
                pip:SetTexture(mod.CP_SHAPE.WHITE)
                pip:SetTexCoord(0, 1, 0, 1)
                pip:SetVertexColor(emptyCol.r, emptyCol.g, emptyCol.b, emptyCol.a)
                pip:Show()
            else
                if pip._secretBar then
                    pip._secretBar:Hide()
                end
                if iconKind == "holypower" then
                    -- Desaturated socket as the background, lit rune on top when filled. Point 5 reuses point 4 mirrored.
                    local num = (i - 1) % 5 + 1
                    local flip = (num == 5)
                    local position = flip and 4 or num
                    if backdrop then
                        backdrop:SetAtlas("nameplates-holypower" .. position .. "-off")
                        backdrop:SetDesaturated(true)
                        if flip then
                            backdrop:SetTexCoord(1, 0, 0, 1)
                        end
                        backdrop:SetVertexColor(1, 1, 1, bgCol.a)
                        backdrop:Show()
                    end
                    if i <= current then
                        pip:SetAtlas("nameplates-holypower" .. position .. "-on")
                        if flip then
                            pip:SetTexCoord(1, 0, 0, 1)
                        end
                        pip:SetVertexColor(1, 1, 1, 1)
                        pip:Show()
                    else
                        pip:Hide()
                    end
                elseif iconKind then
                    -- Real resource art: the atlas defines the look, no tint.
                    pip:SetAtlas(mod.GetPipIconAtlas(iconKind, i <= current, i))
                    if (i > current) and mod.CP_ICON_DIM_EMPTY[iconKind] then
                        pip:SetVertexColor(0.35, 0.35, 0.35, 1) -- dim single-atlas empties
                    else
                        pip:SetVertexColor(1, 1, 1, 1)
                    end
                    pip:Show()
                else
                    pip:SetTexture(mod.CP_SHAPE.WHITE)
                    pip:SetTexCoord(0, 1, 0, 1)
                    if i <= current then
                        pip:SetVertexColor(cpColor[1], cpColor[2], cpColor[3], 1)
                    else
                        pip:SetVertexColor(emptyCol.r, emptyCol.g, emptyCol.b, emptyCol.a)
                    end
                    pip:Show()
                end
            end
        else
            pip:Hide()
            if pip._bg then
                pip._bg:Hide()
            end
            if pip._secretBar then
                pip._secretBar:Hide()
            end
            mod.HidePipDecor(pip)
        end
    end
end

local function HideClassPowerOnPlate(backing)
    if not backing or not backing._cpPips then
        return
    end
    for i = 1, #backing._cpPips do
        backing._cpPips[i]:Hide()
        if backing._cpPips[i]._bg then
            backing._cpPips[i]._bg:Hide()
        end
        if backing._cpPips[i]._secretBar then
            backing._cpPips[i]._secretBar:Hide()
        end
        mod.HidePipDecor(backing._cpPips[i])
    end
    if backing._cpBar then
        backing._cpBar:Hide()
    end
    -- Park the engine-slot overlay with the pips (target lost, form-hidden,
    -- watcher teardown all route through here).
    if _G._EWC then
        _G._EWC.Gate("np")
    end
end

-- Engine-slot warrior charge overlay on the target plate (see
-- CUI_ResourceBars_WarriorCharges.lua; guarded on _G._EWC so a disabled
-- ResourceBars addon leaves the simulator pips in charge). The proxy is
-- UIParent-parented and ANCHORED onto plate regions: anchor-derived geometry
-- needs no rect reads, so it stays legal in combat where the plate subtree
-- is unmeasurable. Sizes convert plate-local pixels into proxy units via the
-- two effective scales. Everything is change-gated on the proxy's own
-- fields, so the 10 Hz class-power poll pays a handful of compares while
-- nothing moves.

-- Arm: queue the deferred container build with belt colors (the handoff's
-- Recolor stash wins once armed). Runs per poll tick until built: Sync
-- early-outs on queued/built/latched-error, so it stays a few field tests.
mod._WCNP_Arm = function(powerKey)
    local ewc = _G._EWC
    if not ewc then
        return
    end
    local o = mod._wcnpOpts
    if not o then
        o = { texPath = "Interface\\Buttons\\WHITE8x8", ori = "HORIZONTAL", manualAttach = true, sep = {} }
        mod._wcnpOpts = o
    end
    if GetClassPowerClassColors() then
        local c = GetClassPipColor(PLAYER_CLASS) or CP_DEFAULT_COLOR
        o.r, o.g, o.b = c[1], c[2], c[3]
    else
        local cc = GetClassPowerCustomColor()
        o.r, o.g, o.b = cc.r, cc.g, cc.b
    end
    o.a = 1
    ewc.Sync("np", ewc.GetProxy("np"), powerKey, o)
end

mod._WCNP_Attach = function(
    anchor,
    anchorRelPoint,
    leftAnchor,
    xOff,
    yOff,
    groupW,
    scaledH,
    cellW,
    gapW,
    plateES,
    cpColor,
    emptyCol,
    bgCol,
    powerKey
)
    local ewc = _G._EWC
    if not ewc then
        return
    end
    local o = mod._wcnpOpts
    if not o then
        mod._WCNP_Arm(powerKey)
        o = mod._wcnpOpts
        if not o then
            return
        end
    end
    local p = ewc.GetProxy("np")
    local pES = p:GetEffectiveScale()
    local k = (pES and pES > 0 and plateES) and (plateES / pES) or 1
    local wid, hgt = groupW * k, scaledH * k
    local dirty = not p:IsShown() or p._npPK ~= powerKey
    -- Geometry gate: reposition only when the layout actually moved (anchor
    -- frame swap on cast-bar avoidance, offsets, scale, cap changes).
    if
        p._npAF ~= anchor
        or p._npLA ~= leftAnchor
        or p._npRP ~= anchorRelPoint
        or p._npX ~= xOff
        or p._npY ~= yOff
        or p._npW ~= wid
        or p._npH ~= hgt
    then
        p._npAF, p._npLA, p._npRP = anchor, leftAnchor, anchorRelPoint
        p._npX, p._npY, p._npW, p._npH = xOff, yOff, wid, hgt
        p:SetSize(wid, hgt)
        p:ClearAllPoints()
        -- SetPoint offsets apply in the POSITIONED frame's own scale: convert
        -- the plate-local offsets too.
        p:SetPoint(leftAnchor, anchor, anchorRelPoint, xOff * k, yOff * k)
        dirty = true
    end
    -- Style gate: separator/empty/fill colors from the live settings.
    if
        p._npSR ~= bgCol.r
        or p._npSG ~= bgCol.g
        or p._npSB ~= bgCol.b
        or p._npSA ~= bgCol.a
        or p._npER ~= emptyCol.r
        or p._npEG ~= emptyCol.g
        or p._npEB ~= emptyCol.b
        or p._npEA ~= emptyCol.a
        or p._npCR ~= cpColor[1]
        or p._npCG ~= cpColor[2]
        or p._npCB ~= cpColor[3]
    then
        p._npSR, p._npSG, p._npSB, p._npSA = bgCol.r, bgCol.g, bgCol.b, bgCol.a
        p._npER, p._npEG, p._npEB, p._npEA = emptyCol.r, emptyCol.g, emptyCol.b, emptyCol.a
        p._npCR, p._npCG, p._npCB = cpColor[1], cpColor[2], cpColor[3]
        dirty = true
    end
    if dirty then
        p._npPK = powerKey
        o.r, o.g, o.b, o.a = cpColor[1], cpColor[2], cpColor[3], 1
        local s = o.sep
        s.r, s.g, s.b, s.a = bgCol.r, bgCol.g, bgCol.b, bgCol.a
        s.w = gapW * k
        s.cellW = cellW * k
        s.gap = gapW * k
        s.pad = 0
        s.stretch = nil
        local e = s.empty
        if not e then
            e = {}
            s.empty = e
        end
        e.r, e.g, e.b, e.a = emptyCol.r, emptyCol.g, emptyCol.b, emptyCol.a
        s.emptyInset = 0
        ewc.Sync("np", p, powerKey, o)
    end
    ewc.Recolor("np", powerKey, cpColor[1], cpColor[2], cpColor[3], 1)
end

-- Return the extra Y offset that elements above the health bar need to clear
-- the class power pips (when pips are on top and visible on this plate).
GetClassPowerTopPush = function(backing)
    if not GetShowClassPower() or not classPowerType then
        return 0
    end
    if mod.GetClassPowerPos() ~= "top" then
        return 0
    end
    if not backing or not backing.unit or not UnitIsUnit(backing.unit, "target") then
        return 0
    end
    local cpScale = mod.GetClassPowerScale()
    local cpYOff = mod.GetClassPowerYOffset()
    -- Square-footprint shapes are taller than the flat rectangle pip.
    local hgt = mod.CP_SHAPE.SQUARE[mod.GetClassPowerShape()] and CP_PIP_W or CP_PIP_H
    return hgt * cpScale + cpYOff
end
SetClassPowerTopPush(GetClassPowerTopPush)

-- Find the target plate and update pips
local function RefreshClassPower()
    -- Form check (e.g. Druid combo points only in cat form)
    if classPowerFormReq and GetShapeshiftFormID() ~= classPowerFormReq then
        -- Only need to hide pips on the target plate (others never have them)
        if mod._cachedTargetPlate then
            HideClassPowerOnPlate(mod._cachedTargetPlate)
        end
        return
    end
    -- PERF: only the target plate shows class power; skip iterating all plates
    if
        mod._cachedTargetPlate
        and mod._cachedTargetPlate.unit
        and UnitIsUnit(mod._cachedTargetPlate.unit, "target")
    then
        EnsureClassPowerPips(mod._cachedTargetPlate)
        UpdateClassPowerOnPlate(mod._cachedTargetPlate)
    end
end

-- Full refresh including repositioning of elements above the health bar.
-- Called on target change and settings change (not on every power tick).
local function RefreshClassPowerFull()
    -- Form check (e.g. Druid combo points only in cat form)
    local formHidden = classPowerFormReq and GetShapeshiftFormID() ~= classPowerFormReq
    -- PERF: only the target plate shows pips; only it needs reposition for cpPush
    local tp = mod._cachedTargetPlate
    if tp and tp.unit then
        if not formHidden and UnitIsUnit(tp.unit, "target") then
            EnsureClassPowerPips(tp)
            UpdateClassPowerOnPlate(tp)
        else
            HideClassPowerOnPlate(tp)
        end
        tp:RefreshNamePosition()
        tp:UpdateRaidIcon()
    end
end

-- Forward declarations for mutual recursion on spec change
local DisableClassPowerWatcher
local ApplyClassPowerSetting

-- Enable/disable the class power watcher
local function EnableClassPowerWatcher()
    if classPowerWatcher then
        return
    end -- already active
    local details = CLASS_POWER_MAP[PLAYER_CLASS]
    -- Vanilla content has no specializations, so the spec-keyed entries above never
    -- resolve on Forever, and the flat ones name resources that client does not
    -- have. This is the whole set that exists there.
    if CludesUI.IS_FOREVER == true then
        details = (PLAYER_CLASS == "ROGUE" or PLAYER_CLASS == "DRUID") and { Enum.PowerType.ComboPoints, 5 }
            or nil
    end
    if not details then
        return
    end -- class has no trackable resource

    -- Resolve spec-specific entries: if info has numeric specID keys, look up current spec
    if details[1] == nil then
        local specInfo = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization()
        local specID = specInfo and C_SpecializationInfo.GetSpecializationInfo(specInfo)
        details = specID and details[specID]
        if not details then
            return
        end -- current spec has no trackable resource
    end

    classPowerType = details[1]
    SetClassPowerType(classPowerType)
    classPowerMax = details[2]
    -- Druid Resto: cat form required. Feral always shows. On Forever there are no
    -- specs to tell them apart and combo points are cat-only for every druid.
    if CludesUI.IS_FOREVER == true then
        classPowerFormReq = (PLAYER_CLASS == "DRUID") and (DRUID_CAT_FORM or 1) or nil
    else
        local specIdx = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization()
        local isResto = (PLAYER_CLASS == "DRUID" and specIdx == 4)
        classPowerFormReq = isResto and (DRUID_CAT_FORM or 1) or nil
    end
    -- Every spec change and setting toggle runs Disable + Enable: the one frame is
    -- reused, since WoW never frees a frame.
    classPowerWatcherFrame = classPowerWatcherFrame or CreateFrame("Frame")
    classPowerWatcher = classPowerWatcherFrame
    classPowerWatcher:Show() -- Disable hides it; OnUpdate needs it shown

    -- String-type resources (custom-tracked): use OnUpdate poll + events
    if type(classPowerType) == "string" then
        local elapsed = 0
        classPowerWatcher:SetScript("OnUpdate", function(_, dt)
            elapsed = elapsed + dt
            if elapsed < 0.1 then
                return
            end
            elapsed = 0
            RefreshClassPower()
        end)
        classPowerWatcher:RegisterUnitEvent("UNIT_AURA", "player")
        classPowerWatcher:RegisterEvent("PLAYER_TARGET_CHANGED")
        classPowerWatcher:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        -- Manual tracker events (Whirlwind, Bladestorm/Unhinged)
        -- so tracking works even without CludesUIResourceBars loaded.
        classPowerWatcher:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        classPowerWatcher:RegisterEvent("PLAYER_DEAD")
        classPowerWatcher:RegisterEvent("PLAYER_ALIVE")
        classPowerWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
        -- Stagger max is based on player health, so track health changes too
        if classPowerType == "BREWMASTER_STAGGER" then
            classPowerWatcher:RegisterUnitEvent("UNIT_HEALTH", "player")
            classPowerWatcher:RegisterUnitEvent("UNIT_MAXHEALTH", "player")
        end
        classPowerWatcher:SetScript("OnEvent", function(_, evt, ...)
            if evt == "PLAYER_SPECIALIZATION_CHANGED" then
                -- The event carries a unit and is delivered for GROUP MEMBERS too, so
                -- without this filter a raid full of spec swaps rebuilds the watcher
                -- (and every pip on the personal plate) over and over for nothing.
                local specUnit = ...
                if specUnit ~= "player" then
                    return
                end
                -- Spec changed: tear down and rebuild (spec may no longer have this resource)
                DisableClassPowerWatcher()
                ApplyClassPowerSetting()
            elseif evt == "PLAYER_TARGET_CHANGED" then
                RefreshClassPowerFull()
            elseif evt == "PLAYER_REGEN_ENABLED" then
                RefreshClassPower()
            else
                RefreshClassPower()
            end
        end)
    else
        classPowerWatcher:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
        classPowerWatcher:RegisterUnitEvent("UNIT_MAXPOWER", "player")
        classPowerWatcher:RegisterEvent("PLAYER_TARGET_CHANGED")
        classPowerWatcher:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        if classPowerFormReq then
            classPowerWatcher:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
        end
        -- WoW Forever: combo points moving to a new target keep their count, so no
        -- power event fires; the light refresh below repaints the target plate.
        if CludesUI.IS_FOREVER == true and classPowerType == Enum.PowerType.ComboPoints then
            classPowerWatcher:RegisterEvent("COMBO_TARGET_CHANGED")
        end
        -- Runes need their own event for per-rune cooldown changes
        if classPowerType == Enum.PowerType.Runes then
            classPowerWatcher:RegisterEvent("RUNE_POWER_UPDATE")
        end
        classPowerWatcher:SetScript("OnEvent", function(_, evt, unitToken)
            if evt == "PLAYER_SPECIALIZATION_CHANGED" then
                -- Group members' spec events land here too; see the filter note in the
                -- string-resource branch above.
                if unitToken ~= "player" then
                    return
                end
                DisableClassPowerWatcher()
                ApplyClassPowerSetting()
            elseif evt == "PLAYER_TARGET_CHANGED" or evt == "UPDATE_SHAPESHIFT_FORM" then
                RefreshClassPowerFull()
            else
                RefreshClassPower()
            end
        end)
    end
    RefreshClassPowerFull()
end

DisableClassPowerWatcher = function()
    if not classPowerWatcher then
        return
    end
    classPowerWatcher:UnregisterAllEvents()
    classPowerWatcher:SetScript("OnEvent", nil)
    classPowerWatcher:SetScript("OnUpdate", nil)
    classPowerWatcher:Hide()
    classPowerWatcher = nil
    classPowerFormReq = nil
    -- PERF: only target plate had pips; only it needs cleanup
    local tp = mod._cachedTargetPlate
    if tp then
        HideClassPowerOnPlate(tp)
        if tp.unit then
            tp:RefreshNamePosition()
            tp:UpdateRaidIcon()
        end
    end
end

-- Called at startup and when the setting changes
ApplyClassPowerSetting = function()
    if GetShowClassPower() then
        EnableClassPowerWatcher()
    else
        DisableClassPowerWatcher()
    end
end
mod.ApplyClassPowerSetting = ApplyClassPowerSetting
mod.RefreshClassPower = RefreshClassPowerFull
local function DarkenColor(r, g, b, factor)
    factor = factor or 0.60
    return r * factor, g * factor, b * factor
end
-- Out-of-combat darkening, gated by "Modify Out of Combat". On (default): enemies
-- confirmed in combat (clean boolean) keep full colour, out-of-combat/secret states darken --
-- or, with "Change Color", take the flat Out of Combat Color rather than dimming.
local function MaybeDarken(r, g, b, inCombat)
    local enabled = (p and p.darkenEnemiesOOC)
    if enabled == nil then
        enabled = defaultSet.darkenEnemiesOOC
    end
    if not enabled then
        return r, g, b
    end
    if type(inCombat) == "boolean" and inCombat then
        return r, g, b
    end
    local recolor = (p and p.darkenOOCRecolor)
    if recolor == nil then
        recolor = defaultSet.darkenOOCRecolor
    end
    if recolor then
        local c = (p and p.darkenOOCColor) or defaultSet.darkenOOCColor
        return c.r, c.g, c.b
    end
    return DarkenColor(r, g, b)
end

Inner.ApplyClassPowerSetting, Inner.EnsureClassPowerPips = ApplyClassPowerSetting, EnsureClassPowerPips
Inner.GetClassPowerTopPush, Inner.HideClassPowerOnPlate = GetClassPowerTopPush, HideClassPowerOnPlate
Inner.MaybeDarken, Inner.UpdateClassPowerOnPlate = MaybeDarken, UpdateClassPowerOnPlate
Inner.broken = false
