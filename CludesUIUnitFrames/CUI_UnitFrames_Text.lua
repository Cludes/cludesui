if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_UnitFrames_Text.lua
--
--  ns.Colors and the engine painters, smart power percent, text decimals,
--  tags, nicknames and zone formatters. Publishes through I; loads before
--  Layout and Power, which re-import from it. db is set through I.dbSetters.
-------------------------------------------------------------------------------
local addonName, mod = ...

local GetSpecialization = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization)
    or GetSpecialization
local string_format = string.format
local issecretvalue = issecretvalue

local Inner = mod._internals
local frameList, AbbreviateNumbers = Inner.frames, Inner.AbbreviateNumbers
local UF_SecretSafeHealthColor = Inner.UF_SecretSafeHealthColor
local saved
Inner.dbSetters[#Inner.dbSetters + 1] = function(val)
    saved = val
end

-------------------------------------------------------------------------------
--  Engine painters (oUF extraction). ns.Colors carries the exact color table
--  the shared color chains read through frame.colors: same value sources and
--  shapes as before, so every existing color decision lands on identical
--  numbers. Class entries are overwritten by the suite palette sync (the same
--  flow that used to write the library's table); reaction entries by the
--  module's own reaction sync. Published as CludesUI._UFColors so the
--  parent's color chokepoint can reach it.
-------------------------------------------------------------------------------
do
    local CreateColor = _G.CreateColor
    local colors = {
        health = CreateColor(49 / 255, 207 / 255, 37 / 255),
        disconnected = CreateColor(0.6, 0.6, 0.6),
        tapped = CreateColor(0.6, 0.6, 0.6),
        class = {},
        reaction = {},
        threat = {},
        power = {},
    }
    for token, c in pairs(RAID_CLASS_COLORS) do
        colors.class[token] = CreateColor(c.r, c.g, c.b)
    end
    for position, c in pairs(FACTION_BAR_COLORS) do
        colors.reaction[position] = CreateColor(c.r, c.g, c.b)
    end
    for i = 0, 3 do
        colors.threat[i] = CreateColor(GetThreatStatusColor(i))
    end
    -- Both key forms land: Blizzard's table carries string tokens plus numeric
    -- aliases, and the painter looks up number-first, token-second.
    for tagKey, c in pairs(PowerBarColor) do
        if type(c) == "table" and c.r then
            colors.power[tagKey] = CreateColor(c.r, c.g, c.b)
        end
    end
    -- Dispel colors keyed by the game's dispel-type indices (the aura rows'
    -- type overlay reads these through a step curve). Blizzard's shared color
    -- objects are referenced directly; Enrage has no stock color.
    colors.dispel = {
        [0] = _G.DEBUFF_TYPE_NONE_COLOR,
        [1] = _G.DEBUFF_TYPE_MAGIC_COLOR,
        [2] = _G.DEBUFF_TYPE_CURSE_COLOR,
        [3] = _G.DEBUFF_TYPE_DISEASE_COLOR,
        [4] = _G.DEBUFF_TYPE_POISON_COLOR,
        [9] = CreateColor(243 / 255, 95 / 255, 245 / 255),
        [11] = _G.DEBUFF_TYPE_BLEED_COLOR,
    }
    mod.Colors = colors
    CludesUI._UFColors = colors

    -- Health value pass: min/max plus current (offline paints a full bar, the
    -- behavior users already see), native interpolation via the bar's own
    -- .smoothing, then the shared secret-safe color chain.
    local function PaintHealth(widget, unitToken, evt)
        local part = widget.Health
        if not part or not unitToken then
            return
        end
        -- A UNIT_HEALTH delivery for this token proves the unit exists (the
        -- tracker only routes real unit events under that name); the identity
        -- and forced paths still pay the probe.
        if evt ~= "UNIT_HEALTH" and not UnitExists(unitToken) then
            return
        end
        -- Engine.ElementOn, inlined on this per-tick path.
        local off = widget._cuiElementsOff
        if off and off.Health then
            return
        end
        -- Bar bounds ride the max-health/identity events (Blizzard's own
        -- contract); a pure UNIT_HEALTH value tick pushes only the value.
        if evt ~= "UNIT_HEALTH" or not part._maxSet then
            part._maxSet = true
            part:SetMinMaxValues(0, UnitHealthMax(unitToken))
        end
        -- A corpse fires no further UNIT_HEALTH, so the death tick's paint is the
        -- last one the bar gets: zero it from the dead flag (a plain boolean in
        -- restricted content, where the value is secret) instead of the value,
        -- and without the interpolation, which otherwise eases toward zero and
        -- leaves a sliver standing on a bar that gets no further ticks.
        -- UnitIsDead, not UnitIsDeadOrGhost: a ghost is at full health, and
        -- Blizzard's own bar reads it the same way (CompactUnitFrame_UpdateHealthColor).
        if not UnitIsConnected(unitToken) then
            part:SetValue(UnitHealthMax(unitToken), part.smoothing)
        elseif UnitIsDead(unitToken) then
            part:SetValue(0)
        else
            part:SetValue(UnitHealth(unitToken), part.smoothing)
        end
        -- Color inputs (class/reaction/dark/disconnect/tap) change via their
        -- own events or identity repaints -- a pure health tick re-runs the
        -- color chain only for modes whose color follows health/combat state
        -- per tick (dynamic curve, threat). The color* flags are
        -- never set by this engine; the dynamic modes live in PostUpdateColor
        -- (ns.UF_DynamicHealthColor) behind the unit's healthColorMode, so that
        -- setting is the gate that keeps a dynamic bar tracking every tick.
        local unitKey = part._cuiUnitKey
        local unitColorMode = unitKey and saved.profile[unitKey]
        unitColorMode = unitColorMode and unitColorMode.healthColorMode
        if
            evt ~= "UNIT_HEALTH"
            or part.colorSmooth
            or part.colorThreat
            or (unitColorMode and unitColorMode ~= "none")
        then
            UF_SecretSafeHealthColor(widget, evt, unitToken)
        end
    end
    mod.Engine.SetPainter("health", PaintHealth)

    -- Power value pass: display-power resolution first (the player bar's
    -- spec-override hook publishes the resolved type for the text formatters),
    -- then min/max/value with offline painting full, then the base power-type
    -- color with the bar's own PostUpdateColor/PostUpdate layered on top in
    -- the same order as before.
    local function PaintPower(widget, unitToken, evt)
        local part = widget.Power
        if not part or not unitToken or not UnitExists(unitToken) then
            return
        end
        if not mod.Engine.ElementOn(widget, "Power") then
            return
        end
        local ptype
        if part.displayAltPower and part.GetDisplayPower then
            ptype = part:GetDisplayPower(unitToken)
        end
        part.displayType = ptype
        local powerNum, ptoken
        if ptype then
            powerNum = ptype
        else
            powerNum, ptoken = UnitPowerType(unitToken)
        end
        -- The resolved type for the value pass below, and its token in the
        -- power events' payload form for the engine's event filter. A secret
        -- type stashes nothing (no filter; the value pass paints in full).
        if issecretvalue(powerNum) then
            part._cuiPNum, part._cuiPTok = nil, nil
        else
            part._cuiPNum = powerNum
            part._cuiPTok = (not issecretvalue(ptoken) and ptoken) or CludesUI.POWER_ENUM_TO_KEY[powerNum]
        end
        if part._manaRegenSpark then
            CludesUI.ManaRegenSpark.SetMana("uf", not issecretvalue(powerNum) and powerNum == Enum.PowerType.Mana)
        end
        local max = UnitPowerMax(unitToken, powerNum)
        part:SetMinMaxValues(0, max)
        local current
        if UnitIsConnected(unitToken) then
            current = UnitPower(unitToken, powerNum)
            part:SetValue(current, part.smoothing)
        else
            current = max
            part:SetValue(max, part.smoothing)
        end
        if part.colorPower then
            local color = mod.Colors.power[powerNum] or (ptoken and mod.Colors.power[ptoken])
            if color then
                part:SetStatusBarColor(color:GetRGB())
            end
        end
        if part.PostUpdateColor then
            part:PostUpdateColor(unitToken)
        end
        if part.PostUpdate then
            part:PostUpdate(unitToken, current, 0, max)
        end
    end
    mod.Engine.SetPainter("power", PaintPower)

    -- Power value pass (the player's powerval channel, UNIT_POWER_FREQUENT):
    -- the bar value and the text zones that read power, nothing else. Bounds,
    -- colours, the gray-out, the display-type override and the regen spark's
    -- mana flag follow the power type, the unit or the settings, never the
    -- value, and stay on the full pass (UNIT_POWER_UPDATE, UNIT_MAXPOWER,
    -- UNIT_DISPLAYPOWER and every identity repaint), which also refreshes the
    -- stashed type. The cost prediction segment is anchored to the fill edge
    -- and moves with SetValue. With no readable stashed type the full pass
    -- runs instead.
    mod.Engine.SetValuePainter(function(widget, unitToken)
        local part = widget.Power
        if not part or not unitToken or not UnitExists(unitToken) then
            return
        end
        if not mod.Engine.ElementOn(widget, "Power") then
            return
        end
        local powerNum = part._cuiPNum
        if powerNum == nil then
            PaintPower(widget, unitToken, "UNIT_POWER_FREQUENT")
        elseif UnitIsConnected(unitToken) then
            part:SetValue(UnitPower(unitToken, powerNum), part.smoothing)
        end
        mod.UF_PaintPowerText(widget, unitToken)
    end)

    -- Absorbs: the HealthPrediction Override was always our own complete
    -- painter (bars, clips, text gates); the engine simply becomes its event
    -- source. Identity repaints arrive as pseudo-events, which the Override
    -- already treats as gate-refresh triggers.
    local function PaintAbsorb(widget, unitToken, evt)
        if not mod.Engine.ElementOn(widget, "HealthPrediction") then
            return
        end
        local hp = widget.HealthPrediction
        if hp and hp.Override then
            hp.Override(widget, evt or "ForceUpdate", unitToken)
        end
    end
    mod.Engine.SetPainter("absorb", PaintAbsorb)
end

-- The global master reads and sets every frame's effective Dark Mode choice.
do
    local UNITS = { "player", "target", "focus", "targettarget", "focustarget", "pet", "boss" }
    CludesUI.RegisterDarkModeToggle({
        id = "unitFrames",
        isOn = function()
            if not (saved and saved.profile) then
                return false
            end
            for _, tagKey in ipairs(UNITS) do
                if not mod.UF_DarkThemeOn(saved.profile[tagKey]) then
                    return false
                end
            end
            return true
        end,
        setOn = function(on)
            if not (saved and saved.profile) then
                return
            end
            saved.profile.darkTheme = on
            for _, tagKey in ipairs(UNITS) do
                local cfg = saved.profile[tagKey]
                if cfg then
                    cfg.darkTheme = on
                end
            end
            if mod.ReloadFrames then
                mod.ReloadFrames()
            end
        end,
    })
end

-- Smart power text: percent for healers/prot pally/arcane mage, numeric for the rest.
-- Shared by the oUF tag and the resource bars renderer. `displayedPowerType` (optional
-- Enum.PowerType) is the power the caller's bar actually shows; for form/spec-shifting
-- classes (Druid, Monk) the decision MUST follow the displayed power, not UnitPowerType --
-- a Balance druid's UnitPowerType is Astral Power even while the bar shows Mana, so the
-- mana number would render raw instead of percent otherwise.
-- WoW Forever offers no Smart Text (it chooses by spec, and Forever has no specs):
-- a "smart" saved there reads as the value (CludesUI.PowerTextFormat).
local function CUI_IsSmartPowerPercent(displayedPowerType)
    if CludesUI.IS_FOREVER then
        return false
    end
    local _, classFile = UnitClass("player")
    if not classFile then
        return false
    end
    -- Druid/Monk shift displayed power with form/spec: percent only while the bar shows
    -- Mana (Druid caster/Tree/travel + Mistweaver); raw otherwise (Cat=Energy, Bear=Rage,
    -- Moonkin=Astral, WW/BRM=Energy, incl. Restoration weaving Cat/Bear). Prefer the
    -- caller-supplied displayed power, else the live primary power type.
    if classFile == "DRUID" or classFile == "MONK" then
        local pt = displayedPowerType or UnitPowerType("player")
        return pt == Enum.PowerType.Mana
    end
    if classFile == "PRIEST" or classFile == "SHAMAN" then
        return true
    end
    -- Paladin: Holy and Protection (mana-based specs).
    if classFile == "PALADIN" then
        local specInfo = GetSpecialization()
        return specInfo == 1 or specInfo == 2 -- Holy, Protection
    end
    -- Mage: only Arcane
    if classFile == "MAGE" then
        local specInfo = GetSpecialization()
        return specInfo == 1 -- Arcane
    end
    -- Evoker: only Preservation
    if classFile == "EVOKER" then
        local specInfo = GetSpecialization()
        return specInfo == 2 -- Preservation
    end
    return false
end
mod.CUI_IsSmartPowerPercent = CUI_IsSmartPowerPercent
CludesUI.IsSmartPowerPercent = CUI_IsSmartPowerPercent

-- Show Decimal on Text (global): AbbreviateNumbers config emitting one decimal per
-- magnitude band (240500 -> "240.5k", 2405000 -> "2.4m"). AbbreviateNumbers runs in
-- Blizzard's secure context, so a secret value plus this config stays secret-safe
-- (like the no-config call on secret health/power). Tags read these _G flags:
--   _G._CUI_AbbrevDecimalCfg = this table when on, nil when off
--   _G._CUI_TextDecimals     = true/false, selects "%.1f" vs "%d" for percents
--   _G._CUI_PctTrim          = { curve, cfg } trimming the percent, nil when off
-- Per band: significandDivisor = breakpoint / d, fractionDivisor = d (d = 10 for
-- one decimal, 100 for two). Ten-thousand-grouping locales (koKR/zhCN/zhTW) take
-- the shared number engine's thousand/wan/yi units instead of k/m/b, so these
-- frames read the same as Damage Meters and the gold bar on those clients.
local function DecimalAbbrevConfig(skinData, shortHealth)
    local g = CludesUI.NumberAbbrevGlyphs()
    if g then
        return {
            breakpointData = {
                {
                    breakpoint = 1e8,
                    abbreviation = g[3],
                    significandDivisor = 1e8 / skinData,
                    fractionDivisor = skinData,
                    abbreviationIsGlobal = false,
                },
                {
                    breakpoint = 1e4,
                    abbreviation = g[2],
                    significandDivisor = 1e4 / skinData,
                    fractionDivisor = skinData,
                    abbreviationIsGlobal = false,
                },
                {
                    breakpoint = 1e3,
                    abbreviation = g[1],
                    significandDivisor = 1e3 / skinData,
                    fractionDivisor = skinData,
                    abbreviationIsGlobal = false,
                },
            },
        }
    end
    return {
        breakpointData = {
            {
                breakpoint = 1e9,
                abbreviation = shortHealth and "B" or "b",
                significandDivisor = 1e9 / skinData,
                fractionDivisor = skinData,
                abbreviationIsGlobal = false,
            },
            {
                breakpoint = 1e6,
                abbreviation = shortHealth and "M" or "m",
                significandDivisor = 1e6 / skinData,
                fractionDivisor = skinData,
                abbreviationIsGlobal = false,
            },
            {
                breakpoint = 1e3,
                abbreviation = shortHealth and "K" or "k",
                significandDivisor = 1e3 / skinData,
                fractionDivisor = skinData,
                abbreviationIsGlobal = false,
            },
        },
    }
end
-- WoW Forever: nothing under 10,000 abbreviates, so the k band starts there and
-- the thousand band goes (the shared engine's trim, CludesUI_NumberFormat.lua).
if CludesUI.IS_FOREVER then
    local bands = DecimalAbbrevConfig
    DecimalAbbrevConfig = function(skinData, shortHealth)
        local conf = bands(skinData, shortHealth)
        if not shortHealth then
            conf.breakpointData = CludesUI.ForeverAbbrevTiers(conf.breakpointData)
        end
        return conf
    end
end

-- Health, max health and absorb values without a decimal config: the global
-- Number Format for valueType (CludesUI_NumberFormat.lua).
mod.AbbreviateValue = CludesUI.AbbreviateValue
CludesUI.RegisterNumberFormatCallback(function()
    mod.RefreshAllUnitNames()
end)

-- Health Short always abbreviates from 1,000 with one decimal.
function mod.AbbreviateShortHealth(hp)
    if not mod._shortHealthAbbrevConfig then
        mod._shortHealthAbbrevConfig = DecimalAbbrevConfig(10, true)
    end
    return AbbreviateNumbers(hp, mod._shortHealthAbbrevConfig)
end
-- "Hide Trailing Zeros": AbbreviateNumbers drops a zero fraction ("100") but keeps a
-- real one ("99.5"), which "%.1f" cannot do and a SECRET percent forbids doing with
-- Lua string ops. It TRUNCATES though, so a fractional significandDivisor reads a tenth
-- low (0.1 renders 33.3 as "33.2"); the curve scales instead, handing over whole
-- tenths/hundredths, +0.5 so truncation lands where "%.1f" would have rounded.
local function MakePctTrim(scale, fractionDivisor)
    local curve = C_CurveUtil.CreateCurve()
    curve:SetType(Enum.LuaCurveType.Linear)
    curve:AddPoint(0.0, 0.5)
    curve:AddPoint(1.0, scale + 0.5)
    return {
        curve = curve,
        cfg = {
            breakpointData = {
                {
                    breakpoint = 0,
                    abbreviation = "",
                    significandDivisor = 1,
                    fractionDivisor = fractionDivisor,
                    abbreviationIsGlobal = false,
                },
            },
        },
    }
end
mod._pctTrim = MakePctTrim(1000, 10)
mod._pctTrim2 = MakePctTrim(10000, 100)
function mod.ApplyTextDecimalGlobals()
    if saved and saved.profile and saved.profile.showDecimalOnText then
        -- Built on first use, not at file load: a standalone build reads the Language
        -- override at its own ADDON_LOADED, after this file. The locale is fixed per session.
        if not mod._decimalAbbrevConfig then
            mod._decimalAbbrevConfig = DecimalAbbrevConfig(10)
            -- Two-decimal variant for boss frames ("Show 2 for Boss"): 240.55k / 2.45m.
            mod._decimalAbbrevConfig2 = DecimalAbbrevConfig(100)
        end
        _G._CUI_TextDecimals = true
        -- "Only Show for % Health": decimal on PERCENT, health/absorb VALUES whole --
        -- withhold the abbreviate configs (values follow the Number Format, ns.AbbreviateValue)
        -- while _CUI_TextDecimals stays true for percents.
        local percentOnly = saved.profile.showDecimalPercentOnly
        _G._CUI_AbbrevDecimalCfg = mod._decimalAbbrevConfig
        if percentOnly then
            _G._CUI_AbbrevDecimalCfg = nil
        end
        -- Percent-only, so "Only Show for % Health" never withholds these.
        local trimZeros = saved.profile.showDecimalTrimZeros
        _G._CUI_PctTrim = trimZeros and mod._pctTrim or nil
        -- Boss frames get a second decimal place. Tags use the 1-decimal path
        -- for non-boss units when the flag is set, and ignore it when nil.
        if saved.profile.showDecimalBoss2 ~= false then
            _G._CUI_BossExtraDecimal = true
            _G._CUI_AbbrevDecimalCfg2 = mod._decimalAbbrevConfig2
            if percentOnly then
                _G._CUI_AbbrevDecimalCfg2 = nil
            end
            _G._CUI_PctTrim2 = trimZeros and mod._pctTrim2 or nil
        else
            _G._CUI_BossExtraDecimal = false
            _G._CUI_AbbrevDecimalCfg2 = nil
            _G._CUI_PctTrim2 = nil
        end
    else
        _G._CUI_TextDecimals = false
        _G._CUI_AbbrevDecimalCfg = nil
        _G._CUI_BossExtraDecimal = false
        _G._CUI_AbbrevDecimalCfg2 = nil
        _G._CUI_PctTrim = nil
        _G._CUI_PctTrim2 = nil
    end
end

-- Shared text-piece functions consumed by the zone formatter table below.
local TagFns = {}

-- unit token -> is a boss token, filled on first sight (the frames use a handful
-- of fixed tokens), so the text pieces never slice the token per paint.
local IS_BOSS_UNIT = setmetatable({}, {
    __index = function(tbl, unitToken)
        local val = string.sub(unitToken, 1, 4) == "boss"
        tbl[unitToken] = val
        return val
    end,
})

do
    -- Abbreviated health for the curhpshort / healthshort / maxhpshort tags.
    -- status: an offline, dead or ghost unit reads OFFLINE / DEAD. Only the
    -- current value takes it, so Health # / Max # names the status once
    -- ("DEAD / 150 K"). shortHealth (healthshort): always one decimal with an
    -- uppercase K/M/B (ns.AbbreviateShortHealth), whatever the decimal options say.
    -- valueType: the Number Format type without a decimal config; boss frames
    -- read "bossHealth" instead.
    local function MakeAbbrevHP(getHP, status, shortHealth, valueType)
        return function(unitToken)
            if not unitToken or not UnitExists(unitToken) then
                return ""
            end
            if status then
                if not UnitIsConnected(unitToken) then
                    return CludesUI.L("OFFLINE")
                end
                if UnitIsDeadOrGhost(unitToken) then
                    return CludesUI.L("DEAD")
                end
            end
            local hp = getHP(unitToken) or 0
            if shortHealth then
                return mod.AbbreviateShortHealth(hp)
            end
            local conf = _G._CUI_AbbrevDecimalCfg
            local boss = IS_BOSS_UNIT[unitToken]
            -- Boss frames use the 2-decimal config when "Show 2 for Boss" is on.
            if _G._CUI_BossExtraDecimal and boss then
                conf = _G._CUI_AbbrevDecimalCfg2
            end
            if conf then
                return AbbreviateNumbers(hp, conf)
            end
            return mod.AbbreviateValue(hp, boss and "bossHealth" or valueType)
        end
    end

    TagFns.curhpshort = MakeAbbrevHP(UnitHealth, true, nil, "health")
    TagFns.healthshort = MakeAbbrevHP(UnitHealth, true, true)
    TagFns.maxhpshort = MakeAbbrevHP(UnitHealthMax, nil, nil, "maxHealth")
end

do
    -- Health percent under the decimal options. "Hide Trailing Zeros" reads the percent
    -- through a scaling curve so AbbreviateNumbers can drop the zero "%.1f" would pad.
    local function PercentHP(unitToken)
        -- Predicted percent (incoming heals) can outlive the unit: a corpse fires no
        -- further UNIT_HEALTH and the text channel never hears UNIT_HEAL_PREDICTION.
        -- Corpses only, like Blizzard's health paths: a ghost is at full health, and
        -- the neighbouring DEAD zone is the piece that speaks for dead-or-ghost.
        if UnitIsDead(unitToken) then
            return "0"
        end
        local boss = _G._CUI_BossExtraDecimal and IS_BOSS_UNIT[unitToken]
        local trim = _G._CUI_PctTrim
        if boss then
            trim = _G._CUI_PctTrim2
        end
        if trim then
            local scaled = UnitHealthPercent(unitToken, true, trim.curve)
            if not scaled then
                return "0"
            end
            return AbbreviateNumbers(scaled, trim.cfg)
        end
        local pct = UnitHealthPercent(unitToken, true, CurveConstants.ScaleTo100)
        if not pct then
            return "0"
        end
        if boss then
            return string_format("%.2f", pct)
        end
        return string_format(_G._CUI_TextDecimals and "%.1f" or "%d", pct)
    end

    TagFns.perhp = PercentHP
    TagFns.perhpnosign = function(unitToken)
        if not unitToken or not UnitExists(unitToken) then
            return ""
        end
        if not UnitIsConnected(unitToken) then
            return CludesUI.L("OFFLINE")
        end
        if UnitIsDeadOrGhost(unitToken) then
            return CludesUI.L("DEAD")
        end
        return PercentHP(unitToken)
    end
end

-- Resolved power type per unit. Updated by the GetDisplayPower override so the
-- power text matches the power bar when powerTypeOverride is active (e.g.
-- Balance Druid showing Mana instead of Astral Power).
_G._CUI_ResolvedPowerType = _G._CUI_ResolvedPowerType or {}

local PLAYER_POWER_DEFAULT = {
    PRIEST = { [3] = 0 }, -- Shadow: default to Mana
    MONK = { [2] = 0 }, -- Mistweaver: default to Mana
}
local PLAYER_POWER_ALT = {
    DRUID = { [1] = 0, [2] = 0, [3] = 0, [4] = 0 }, -- All druid specs -> Mana
    PRIEST = { [3] = nil }, -- Shadow alt -> Insanity (UnitPowerType)
    SHAMAN = { [1] = 0 }, -- Elemental -> Mana
}

-- Forced display power type for the player (number = Enum.PowerType, nil =
-- UnitPowerType decides). Shared by the bar's GetDisplayPower, the color
-- resolver and the options preview so all three agree.
function CludesUI.GetPlayerPowerOverride()
    if not (saved and saved.profile) then
        return nil
    end
    local _, classFile = UnitClass("player")
    -- WoW Forever has no retail specs, so the spec tables below never apply
    -- there: only the druid "Power Type: Mana" choice, under its own string key.
    if CludesUI.IS_FOREVER then
        if classFile ~= "DRUID" then
            return nil
        end
        local shade = saved.profile.player and saved.profile.player.powerTypeOverride
        return (shade and shade.foreverDruid) and 0 or nil
    end
    local classDef = PLAYER_POWER_DEFAULT[classFile]
    local classAlt = PLAYER_POWER_ALT[classFile]
    if not (classDef or classAlt) then
        return nil
    end
    local specInfo = GetSpecialization and GetSpecialization()
    if not specInfo then
        return nil
    end
    -- powerTypeOverride is keyed by SPEC ID, never the GetSpecialization() index:
    -- the set is profile-wide, so an index key collides across classes (slot 3 is
    -- Guardian, Shadow AND Augmentation). classAlt/classDef stay index-keyed --
    -- they are nested per class already, so they cannot collide. Resource Bars may
    -- be disabled, hence the direct fallback.
    local spellRef = (_G._CURB_ResolveSpecIDCached and _G._CURB_ResolveSpecIDCached())
        or (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo(specInfo))
        or nil
    local shade = saved.profile.player and saved.profile.player.powerTypeOverride
    local choice = spellRef and shade and shade[spellRef]
    if choice == "astral" then
        -- Balance "Astral Power", saved only under its spec
        -- ID: Cat and Bear Form (form IDs 1 and 5) keep their own power, every
        -- other form shows Astral Power.
        local frame = GetShapeshiftFormID()
        if frame ~= 1 and frame ~= 5 then
            return Enum.PowerType.LunarPower
        end
        return nil
    elseif choice and classAlt then
        return classAlt[specInfo]
    elseif classDef and classDef[specInfo] ~= nil then
        return classDef[specInfo]
    end
    return nil
end

-- (The perpp/curpp/absorb piece functions live in the zone-formatter block
-- below; they read the _CUI_ globals above.)

-- Effective level (scaling-aware), "??" when unknowable (skull bosses). A
-- SECRET level is returned RAW -- display-safe as a %s arg through
-- SetFormattedText, never compared/formatted in Lua (same rule as the secret
-- name in the target-name piece).
TagFns.level = function(unit)
    if not unit or not UnitExists(unit) then
        return ""
    end
    local l = UnitEffectiveLevel(unit)
    if UnitIsWildBattlePet(unit) or UnitIsBattlePetCompanion(unit) then
        l = UnitBattlePetLevel(unit)
    end
    if l and issecretvalue and issecretvalue(l) then
        return l
    end
    if not l or l <= 0 then
        -- Forever: a hidden player level the PvP feature knows.
        return CludesUI.KnownHiddenLevel and CludesUI.KnownHiddenLevel(unit) or "??"
    end
    return l
end

-- Class/reaction color for a unit's NAME, enemy-aware: players (and AI party members)
-- get class color; NPCs use reaction color (hostile red, neutral yellow, friendly
-- green, tap-denied gray). Custom Enemy Colors override is honored via oUF.colors.reaction.
-- Returns r,g,b (0-1) or nil (caller's own default); secret-safe for uninspectable units.
-- On ns for the local cap; shared by ApplyClassColor and cui-tgtname so "Name > Target"
-- colors like the unit frame name.
mod.ResolveUnitNameColor = function(unitToken)
    if not unitToken then
        return nil
    end
    if UnitIsPlayer(unitToken) or (UnitInPartyIsAI and UnitInPartyIsAI(unitToken)) then
        local _, classKey = UnitClass(unitToken)
        if not issecretvalue(classKey) and classKey then
            -- The suite's Class Colors (custom colors, Class Color Darken), as the health bar.
            local color = CludesUI.GetClassColor(classKey)
            if color then
                return color.r, color.g, color.b
            end
        end
        return nil
    end
    if UnitExists(unitToken) then
        if UnitIsTapDenied and UnitIsTapDenied(unitToken) then
            return 0.6, 0.6, 0.6
        end
        local reactionId = UnitReaction(unitToken, "player")
        if reactionId and not issecretvalue(reactionId) then
            local color = (mod.Colors and mod.Colors.reaction and mod.Colors.reaction[reactionId])
                or FACTION_BAR_COLORS[reactionId]
            if color then
                return color.r, color.g, color.b
            end
        end
    end
    return nil
end

-- Shared secret-class-color recovery for identity-restricted units (ToT, focus-target):
-- the user's custom color for a matching group member, else Blizzard's shade. Used by
-- ResolveBgClassColor and ApplyClassColor; ResolveUnitNameColor does NOT use this, since
-- its result also feeds the [cui-tgtcol] hex-escape tag, which cannot format secret
-- channels itself (that tag takes a secret hex from GenerateHexColor on its own and
-- hands it to SetFormattedText untouched).
-- Returns ok, r, g, b -- ok is a PLAIN boolean, r/g/b may be SECRET, only safe as setter args.
local function ResolveRestrictedClassColor(unitToken, classKey)
    local success, red, green, blue = CludesUI.GetClassColorForRestrictedUnit(unitToken, classKey)
    if success then
        return true, red, green, blue
    end
    if C_ClassColor and C_ClassColor.GetClassColor then
        local color = C_ClassColor.GetClassColor(classKey)
        if color then
            return true, color.r, color.g, color.b
        end
    end
    return false
end

-- Background class-color source, enemy-aware. UnitClass() reports WARRIOR for NPCs
-- rather than nil, so a bare lookup paints every mob Warrior tan. Players (and AI
-- party members) keep CludesUI.GetClassColor (custom colors + Class Color Darken
-- baked in); NPCs fall through to the reaction color, matching the unit name, the
-- border and the custom Enemy Colors override. On ns for the local cap.
-- Returns ok, r, g, b -- ok is a PLAIN boolean, r/g/b may be SECRET numbers on an
-- identity-restricted unit (ToT/focus-target): callers must branch on ok, never on
-- the truthiness of r, and may only ever hand r/g/b to a setter like SetColorTexture.
mod.ResolveBgClassColor = function(classUnit)
    if not classUnit then
        return false
    end
    if UnitIsPlayer(classUnit) or (UnitInPartyIsAI and UnitInPartyIsAI(classUnit)) then
        local _, classTok = UnitClass(classUnit)
        if issecretvalue(classTok) then
            return ResolveRestrictedClassColor(classUnit, classTok)
        end
        local cc = classTok and CludesUI.GetClassColor(classTok)
        if cc then
            return true, cc.r, cc.g, cc.b
        end
        return false
    end
    local red, green, blue = mod.ResolveUnitNameColor(classUnit)
    return red ~= nil, red, green, blue
end

-- External nickname providers key us by this addon name. Suite = "CludesUI" (the
-- registered brand) so one provider checkbox controls every CUI module; standalone =
-- our renamed folder name, which always contains "Standalone" (rename-immune token).
-- On ns for the Lua 5.1 200-local ceiling.
mod.EXT_NICK = CludesUI.EXT_NICK
mod.NICK_ADDON = addonName:find("Standalone") and addonName or mod.EXT_NICK.addon

-- Resolve a unit's display name through MethodInternal's authoritative surface
-- choice for known Method players, then the normal provider order: NSAPI ->
-- TimelineReminders -> LiquidAPI -> CustomNames, then the raw unit name. Each
-- external call is pcall-wrapped so a misbehaving API can never break names.
--
-- SECRET-SAFE: an enemy unit's UnitName is secret in protected content and any Lua op
-- on it (==, .., format) throws. Nicknames only apply to your own group, so: non-players
-- short-circuit to the raw name; name-keyed providers (NSAPI, LiquidAPI) are skipped
-- when the name is secret; TimelineReminders is UNIT-keyed (GetNickname(unit)), safe to
-- consult regardless (result still re-validated as a clean string). The final return
-- may be the raw (possibly secret) name -- display-safe since oUF feeds tag returns to
-- SetFormattedText as a %s arg without inspecting them.
function mod.ResolveUnitNickname(unitToken)
    local name, surname = UnitName(unitToken)
    if not name then
        return ""
    end
    -- Nicknames are player-only; NPCs (bosses, etc.) keep their name.
    if not UnitIsPlayer(unitToken) then
        return name
    end
    local nameSecret = issecretvalue and issecretvalue(name)
    local display
    -- MethodInternal's surface choice is authoritative for known Method players,
    -- including Character Name (which deliberately equals the raw name). It sits
    -- ahead of the CUI master toggle so the MethodInternal-owned setting works on
    -- its selected surface; unknown players continue through CUI's normal chain.
    if EasyNicknameAPI and EasyNicknameAPI.GetNicknameForUnitForSurface then
        local success, dn, handled =
            pcall(EasyNicknameAPI.GetNicknameForUnitForSurface, unitToken, "unitFrames")
        if success and handled == true then
            if type(dn) == "string" and not (issecretvalue and issecretvalue(dn)) and dn ~= "" then
                return dn
            end
            return CludesUI.WithSurname(name, surname)
        end
    end
    -- Master toggle (Unit Frames > main frames > Display, default OFF): when off,
    -- skip the remaining provider lookups and show the raw unit name (display-safe;
    -- with the surname on WoW Forever).
    if not (saved and saved.profile and saved.profile.showNicknames) then
        return CludesUI.WithSurname(name, surname)
    end
    -- CludesUI's own nicknames (Raid Lead > Nicknames), set and synced with the guild.
    if not nameSecret and CludesUI.GetNickname then
        local own = CludesUI.GetNickname(name)
        if own then
            return own
        end
    end
    if not nameSecret and NSAPI and NSAPI.GetName then
        local success, dn = pcall(NSAPI.GetName, NSAPI, name, mod.EXT_NICK.nsKey)
        if
            success
            and type(dn) == "string"
            and not (issecretvalue and issecretvalue(dn))
            and dn ~= ""
            and dn ~= name
        then
            display = dn
        end
    end
    if not display then
        local TR = TimelineReminders
        if TR and TR.GetNickname and TR.HasNickname and TR.NicknamesEnabledForAddOn then
            local okGate, enabled = pcall(TR.NicknamesEnabledForAddOn, TR, mod.NICK_ADDON)
            if okGate and enabled then
                local okHas, has = pcall(TR.HasNickname, TR, unitToken)
                if okHas and has then
                    local success, dn = pcall(TR.GetNickname, TR, unitToken)
                    if
                        success
                        and type(dn) == "string"
                        and not (issecretvalue and issecretvalue(dn))
                        and dn ~= ""
                    then
                        display = dn
                    end
                end
            end
        end
    end
    local liquidFn = not display and not nameSecret and LiquidAPI and LiquidAPI[mod.EXT_NICK.liquidFn]
    if liquidFn then
        local success, dn = pcall(liquidFn, name)
        if success and type(dn) == "string" and not (issecretvalue and issecretvalue(dn)) and dn ~= "" then
            display = dn
        end
    end
    -- CustomNames (LibStub library): UnitName returns the custom name, or the raw
    -- name when none is set, so dn ~= name keeps the WithSurname path.
    if not display and not nameSecret and mod._customNames then
        local success, dn = pcall(mod._customNames.UnitName, unitToken)
        if
            success
            and type(dn) == "string"
            and not (issecretvalue and issecretvalue(dn))
            and dn ~= ""
            and dn ~= name
        then
            display = dn
        end
    end
    if display then
        return display
    end
    return CludesUI.WithSurname(name, surname)
end

-- Nickname-aware replacement for the stock [name] tag (see ContentToTag). Returns
-- the nickname when one applies, else the raw unit name.
TagFns.name = function(unitToken)
    -- Truncation is width-based (per-slot Width % clamp), never character-based:
    -- FontString width boxes ellipsize in the renderer, which also works on SECRET
    -- enemy names Lua cannot measure or substring.
    return mod.ResolveUnitNickname(unitToken)
end

-- Live name refresh: repaint every frame's text zones so added/removed
-- nicknames (or a flipped provider checkbox) apply without a /reload. Fired by
-- the provider callbacks below; cheap (a handful of frames).
function mod.RefreshAllUnitNames()
    for _, frame in pairs(frameList) do
        if type(frame) == "table" and frame._cuiTextZones then
            mod.UF_PaintText(frame, frame._cuiUnit)
        end
    end
end
-- Name text only re-renders on name events or via the refresh above, so a raw
-- db restore (Spec Overrides apply, profile swap) needs this exported.
_G._CUUF_RefreshUnitNames = mod.RefreshAllUnitNames

-- Cold-login text repaint: on a first (uncached) login a fontstring can hold the
-- correct string yet render blank until /reload, since it only repaints on a text
-- CHANGE and repainting sets the same string (a no-op). Force a "" -> value
-- transition on every zone fontstring shortly after login, repeated since timing
-- varies; the zone repaint restores the real strings synchronously, no flicker.
do
    local function ForceTextRepaint()
        for _, frame in pairs(frameList) do
            -- The painter refuses an empty token, so a frame between units must
            -- not be blanked here either -- it would never get the value back.
            if type(frame) == "table" and frame._cuiTextZones and frame._cuiUnit and UnitExists(frame._cuiUnit) then
                local zoneList = frame._cuiTextZones
                for i = 1, #zoneList do
                    local fontStr = zoneList[i].fs
                    if fontStr and fontStr.SetText then
                        fontStr:SetText("")
                    end
                end
                if #zoneList > 0 then
                    mod.UF_PaintText(frame, frame._cuiUnit)
                end
            end
        end
    end

    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        for _, delay in ipairs({ 0.25, 1, 3 }) do
            C_Timer.After(delay, ForceTextRepaint)
        end
    end)
end

-- Provider callbacks. MethodInternal and CustomNames use the addon-loaded callback; NSAPI and
-- TimelineReminders retry on PLAYER_LOGIN/PLAYER_ENTERING_WORLD. Registrant key MUST
-- be "CludesUIUnitFrames", not "CludesUI": Raid Frames owns that key and
-- CallbackHandler keys registrations by it, so reuse would clobber one module. The
-- provider CHECKBOX key stays shared (ns.NICK_ADDON/"CUI") so one toggle drives raid AND unit frames.
do
    local function RefreshNames()
        if mod.RefreshAllUnitNames then
            mod.RefreshAllUnitNames()
        end
    end
    local function RegisterMethodInternal()
        if mod._methodInternalSurfaceNickHooked then
            return
        end
        if EasyNicknameAPI and EasyNicknameAPI.RegisterCallback then
            EasyNicknameAPI.RegisterCallback("SurfaceNicknamesChanged", RefreshNames, "CludesUIUnitFrames")
            mod._methodInternalSurfaceNickHooked = true
        end
    end
    local function RegisterNSRT()
        if mod._nsrtNickHooked then
            return true
        end
        if NSAPI and NSAPI.RegisterCallback then
            NSAPI.RegisterCallback("CludesUIUnitFrames", "NSRT_NICKNAME_UPDATED", RefreshNames)
            NSAPI.RegisterCallback("CludesUIUnitFrames", mod.EXT_NICK.nsToggle, RefreshNames)
            mod._nsrtNickHooked = true
            return true
        end
        return false
    end
    local function RegisterTR()
        if mod._trNickHooked then
            return true
        end
        local TR = TimelineReminders
        if TR and TR.RegisterCallback then
            TR.RegisterCallback(
                "CludesUIUnitFrames",
                "TimelineReminders_NicknameToggle",
                function(_, _, addOnName)
                    if addOnName == mod.NICK_ADDON then
                        RefreshNames()
                    end
                end
            )
            TR.RegisterCallback("CludesUIUnitFrames", "TimelineReminders_NicknameUpdate", function()
                RefreshNames()
            end)
            mod._trNickHooked = true
            return true
        end
        return false
    end
    if not (RegisterNSRT() and RegisterTR()) then
        local nf = CreateFrame("Frame")
        nf:RegisterEvent("PLAYER_LOGIN")
        nf:RegisterEvent("PLAYER_ENTERING_WORLD")
        nf:SetScript("OnEvent", function(self, evt)
            local a = RegisterNSRT()
            local b = RegisterTR()
            if (a and b) or evt == "PLAYER_ENTERING_WORLD" then
                self:UnregisterAllEvents()
            end
        end)
    end
    EventUtil.ContinueOnAddOnLoaded("MethodInternal", RegisterMethodInternal)
    -- CustomNames fires one callback per character, so a BattleTag rename or an
    -- import arrives as a burst: repaint once on the next frame. Nothing waits for
    -- it unless it is installed and enabled for this character.
    if C_AddOns.IsAddOnLoaded("CustomNames") or C_AddOns.IsAddOnLoadable("CustomNames") then
        EventUtil.ContinueOnAddOnLoaded("CustomNames", function()
            local CN = LibStub("CustomNames", true)
            if not (CN and CN.UnitName and CN.RegisterCallback) or mod._customNames then
                return
            end
            mod._customNames = CN
            local pending
            local function Flush()
                pending = nil
                RefreshNames()
            end
            local function QueueRefresh()
                if pending then
                    return
                end
                pending = true
                C_Timer.After(0, Flush)
            end
            CN.RegisterCallback("CludesUIUnitFrames", "Name_Added", QueueRefresh)
            CN.RegisterCallback("CludesUIUnitFrames", "Name_Update", QueueRefresh)
            CN.RegisterCallback("CludesUIUnitFrames", "Name_Removed", QueueRefresh)
            RefreshNames()
        end)
    end
end

-- "Name > Target" is built from FOUR tags so the (possibly SECRET) target name is never
-- compared/concatenated/formatted in Lua -- oUF joins tag returns via SetFormattedText,
-- where the name is only a %s display arg. ContentToTag maps "nametotarget" to
-- "[name][cui-tgtsep(...)][cui-tgtcol][cui-tgtname]": [name] = unit's own name (stock
-- oUF tag); [cui-tgtsep] = indicator shown only when the unit has a target (per-slot
-- separator/color ride in tag ARGS, see BuildTgtSepTag; no args = " > "); [cui-tgtcol] =
-- target's class/reaction COLOR escape (no name involved); [cui-tgtname] = target's name,
-- returned RAW. The colour escape precedes the raw name and runs to end of string, so
-- the target name colours IDENTICALLY to the ToT frame name (both via
-- ns.ResolveUnitNameColor) -- works for a SECRET name only because colour and name are
-- SEPARATE tags joined by SetFormattedText, never touched together in Lua.
--
-- PLAYER_TARGET_CHANGED is unitless in oUF (refreshes every frame), covering the player
-- frame's target; UNIT_TARGET covers target/focus frames' own target.

-- Separator/indicator between the names, shown only when the unit has a target. Plain
-- literal plus color escapes; no secret is touched. Args: sepHex = separator string,
-- hex-encoded per byte (safe inside tag brackets), rendered space-padded like " > ";
-- colorSpec = "class" for the TARGET's class/reaction color (same resolver as the
-- target name), else a fixed "rrggbb" hex, closed with |r so a missing [cui-tgtcol]
-- can't inherit it. Decoded separators/escapes are cached: fires on every target
-- change, must not allocate after warmup.
-- (The separator between "Name > Target" is built per-zone by
-- ns.MakeTgtSepPiece in the formatter block below; it closes over the decoded
-- separator and color mode from settings and recolors class-mode per call.)

-- The target's class/reaction colour escape (e.g. "|cffc41f3b"), or "". Uses
-- ns.ResolveUnitNameColor, the SAME resolver ApplyClassColor uses for the Target
-- of Target name. No unit NAME is touched, so it is fully secret-safe.
TagFns.tgtcol = function(unitToken)
    local tunit = unitToken and (unitToken .. "target")
    if not tunit or not UnitExists(tunit) then
        return ""
    end
    local red, green, blue = mod.ResolveUnitNameColor(tunit)
    if not red then
        -- Secret class token (identity-restricted target, e.g. a boss's own
        -- target): GenerateHexColor's result may itself be secret, but still
        -- renders correctly through SetFormattedText's arg lane -- don't reject it.
        if UnitIsPlayer(tunit) and C_ClassColor and C_ClassColor.GetClassColor then
            local _, classKey = UnitClass(tunit)
            if issecretvalue(classKey) then
                local cc = C_ClassColor.GetClassColor(classKey)
                if cc and cc.GenerateHexColor then
                    local success, hex = pcall(cc.GenerateHexColor, cc)
                    if success and type(hex) == "string" then
                        return "|c" .. hex
                    end
                end
            end
        end
        -- Still nothing usable: the plain reaction colour instead of "".
        local reactionId = UnitReaction(tunit, "player")
        if reactionId and not issecretvalue(reactionId) then
            local color = (mod.Colors and mod.Colors.reaction and mod.Colors.reaction[reactionId])
                or FACTION_BAR_COLORS[reactionId]
            if color then
                red, green, blue = color.r, color.g, color.b
            end
        end
    end
    if not red then
        return ""
    end
    return string.format(
        "|cff%02x%02x%02x",
        math.floor(red * 255 + 0.5),
        math.floor(green * 255 + 0.5),
        math.floor(blue * 255 + 0.5)
    )
end

-- The unit's target NAME (nickname-aware via ResolveUnitNickname; otherwise the
-- raw, possibly secret name -- display-safe via SetFormattedText, never
-- inspected). Colour comes from [cui-tgtcol] in front of it.
TagFns.tgtname = function(unitToken)
    local tunit = unitToken and (unitToken .. "target")
    if not tunit or not UnitExists(tunit) then
        return ""
    end
    return mod.ResolveUnitNickname(tunit)
end

-------------------------------------------------------------------------------
--  Text pieces + zone formatters (oUF extraction). Each options content key
--  maps to a format string plus piece functions; the engine's text painter
--  renders a zone with SetFormattedText(fmt, piece1(u), piece2(u), ...).
--  Secret rule: name/level/target-name pieces may return RAW secret values by
--  design; they are never concatenated or inspected in Lua -- the format-arg
--  lane is the only thing that touches them, exactly as the tag engine did,
--  so restricted-content rendering is unchanged.
-------------------------------------------------------------------------------
do
    local scrollFrame = string.format
    local P = {}
    mod.TextPieces = P

    -- Function-registered tag methods are shared directly: one body, no drift.
    P.curhpshort = TagFns.curhpshort
    P.healthshort = TagFns.healthshort
    P.maxhpshort = TagFns.maxhpshort
    P.perhp = TagFns.perhp
    P.perhpnosign = TagFns.perhpnosign
    P.level = TagFns.level
    -- Level in Blizzard's difficulty colors (Level Difficulty Color). A secret
    -- level passes through raw and uncolored, same rule as P.level.
    P.levelcol = function(unit)
        local l = TagFns.level(unit)
        if issecretvalue(l) or l == "" then
            return l
        end
        local red, green, blue = CludesUI.GetLevelColor(unit, (l == "??") and -1 or l)
        return CludesUI.ColorText(l, red, green, blue)
    end
    -- Same, with friendly units in their difficulty color too (Include Friendly).
    P.levelcolall = function(unit)
        local l = TagFns.level(unit)
        if issecretvalue(l) or l == "" then
            return l
        end
        local red, green, blue = CludesUI.GetLevelColor(unit, (l == "??") and -1 or l, true)
        return CludesUI.ColorText(l, red, green, blue)
    end
    P.name = TagFns.name
    P.tgtcol = TagFns.tgtcol
    P.tgtname = TagFns.tgtname

    -- String-compiled tag methods get real equivalents (same logic, same
    -- _CUI_ globals; the compiled strings stay registered only while the tag
    -- engine still runs).
    P.perpp = function(unit)
        local powerKind = _G._CUI_ResolvedPowerType[unit] or UnitPowerType(unit)
        return scrollFrame("%d", UnitPowerPercent(unit, powerKind, true, CurveConstants.ScaleTo100))
    end
    P.curpp = function(unit)
        local powerKind = _G._CUI_ResolvedPowerType[unit] or UnitPowerType(unit)
        return AbbreviateNumbers(UnitPower(unit, powerKind))
    end
    P.maxpp = function(unit)
        local powerKind = _G._CUI_ResolvedPowerType[unit] or UnitPowerType(unit)
        return AbbreviateNumbers(UnitPowerMax(unit, powerKind))
    end
    -- Full numbers for the custom text tags ([hp], [hp:max], [pp], [pp:max]).
    -- %d formats a secret value like P.perpp does; [hp] names the status as
    -- curhpshort does.
    P.curhp = function(unit)
        if not unit or not UnitExists(unit) then
            return ""
        end
        if not UnitIsConnected(unit) then
            return CludesUI.L("OFFLINE")
        end
        if UnitIsDeadOrGhost(unit) then
            return CludesUI.L("DEAD")
        end
        return scrollFrame("%d", UnitHealth(unit) or 0)
    end
    P.maxhp = function(unit)
        if not unit or not UnitExists(unit) then
            return ""
        end
        return scrollFrame("%d", UnitHealthMax(unit) or 0)
    end
    P.curppfull = function(unit)
        local powerKind = _G._CUI_ResolvedPowerType[unit] or UnitPowerType(unit)
        return scrollFrame("%d", UnitPower(unit, powerKind))
    end
    P.maxppfull = function(unit)
        local powerKind = _G._CUI_ResolvedPowerType[unit] or UnitPowerType(unit)
        return scrollFrame("%d", UnitPowerMax(unit, powerKind))
    end
    P.absorb = function(unit)
        if not unit or not UnitExists(unit) then
            return ""
        end
        return scrollFrame("%s", C_StringUtil.TruncateWhenZero(UnitGetTotalAbsorbs(unit) or 0))
    end
    -- An absorb amount abbreviated: Show Decimal on Health Text's table while it
    -- is on, else the Number Format.
    local function AbbrevAbsorb(val)
        local conf = _G._CUI_AbbrevDecimalCfg
        return conf and AbbreviateNumbers(val, conf) or mod.AbbreviateValue(val, "absorb")
    end
    P.absorbshort = function(unit)
        if not unit or not UnitExists(unit) then
            return ""
        end
        return AbbrevAbsorb(UnitGetTotalAbsorbs(unit) or 0)
    end
    P.healabsorb = function(unit)
        if not unit or not UnitExists(unit) then
            return ""
        end
        return scrollFrame("%s", C_StringUtil.TruncateWhenZero(UnitGetTotalHealAbsorbs(unit) or 0))
    end
    P.healabsorbshort = function(unit)
        if not unit or not UnitExists(unit) then
            return ""
        end
        return AbbrevAbsorb(UnitGetTotalHealAbsorbs(unit) or 0)
    end
    -- [absorb:abr], [healabsorb:abr]: empty at zero like the full tags. The presets
    -- above keep "0" because ApplyAbsorbGate clips their whole zone instead.
    local IsZeroValue = CludesUI.IsZeroValue
    local function AbsorbShortTag(get)
        return function(unit)
            if not unit or not UnitExists(unit) then
                return ""
            end
            local val = get(unit) or 0
            if IsZeroValue(val) then
                return ""
            end
            return AbbrevAbsorb(val)
        end
    end
    P.absorbshorttag = AbsorbShortTag(UnitGetTotalAbsorbs)
    P.healabsorbshorttag = AbsorbShortTag(UnitGetTotalHealAbsorbs)
    P.group = function(unit)
        if not IsInRaid() then
            return ""
        end
        local position = UnitInRaid(unit)
        if position then
            local _, _, subgroup = GetRaidRosterInfo(position)
            return subgroup or ""
        end
        return ""
    end

    -- Separator piece for "Name > Target": resolved from settings at apply
    -- time (re-applied whenever settings change, like everything else on the
    -- page), closing over the decoded separator and its color mode. Class
    -- mode recolors per call so the indicator tracks the target's reaction.
    -- literal (optional): an already padded string drawn in place of the
    -- separator in the same Indicator Color (the Target content's prefix).
    function mod.MakeTgtSepPiece(prefixText, prefs, literal)
        local sep = literal
        if not sep then
            sep = prefs[prefixText .. "TargetSep"]
            if type(sep) ~= "string" or sep == "" then
                sep = ">"
            end
            sep = " " .. sep .. " "
        end
        if prefs[prefixText .. "TargetSepClassColor"] then
            return function(unit)
                if not (unit and UnitExists(unit .. "target")) then
                    return ""
                end
                local red, green, blue = mod.ResolveUnitNameColor(unit .. "target")
                if red then
                    return scrollFrame(
                        "|cff%02x%02x%02x%s|r",
                        math.floor(red * 255 + 0.5),
                        math.floor(green * 255 + 0.5),
                        math.floor(blue * 255 + 0.5),
                        sep
                    )
                end
                return sep
            end
        end
        local color = prefs[prefixText .. "TargetSepColor"]
        local esc
        if type(color) == "table" then
            esc = CludesUI.HexColor(color.r or 1, color.g or 1, color.b or 1)
        else
            esc = CludesUI.COLOR_CODES.WHITE
        end
        local colored = esc .. sep .. "|r"
        return function(unit)
            if not (unit and UnitExists(unit .. "target")) then
                return ""
            end
            return colored
        end
    end

    -- Content key -> zone definition. Mirrors ContentToTag's output shapes
    -- one-for-one so rendered text is byte-identical.
    local ZONE_STATIC = {
        name = { "%s", "name" },
        levelname = { "%s | %s", "level", "name" },
        namelevel = { "%s | %s", "name", "level" },
        level = { "%s", "level" },
        both = { "%s | %s%%", "curhpshort", "perhp" },
        bothdash = { "%s - %s%%", "curhpshort", "perhp" },
        perhpnum = { "%s%% | %s", "perhp", "curhpshort" },
        perhpnumdash = { "%s%% - %s", "perhp", "curhpshort" },
        curhpshort = { "%s", "curhpshort" },
        healthshort = { "%s", "healthshort" },
        curmaxhp = { "%s / %s", "curhpshort", "maxhpshort" },
        perhp = { "%s%%", "perhp" },
        perhpnosign = { "%s", "perhpnosign" },
        perpp = { "%s%%", "perpp" },
        curpp = { "%s", "curpp" },
        curmaxpp = { "%s / %s", "curpp", "maxpp" },
        curhp_curpp = { "%s | %s", "curhpshort", "curpp" },
        perhp_perpp = { "%s%% | %s%%", "perhp", "perpp" },
        absorb = { "%s", "absorb" },
        absorbshort = { "%s", "absorbshort" },
        healabsorb = { "%s", "healabsorb" },
        healabsorbshort = { "%s", "healabsorbshort" },
        group = { "%s", "group" },
    }
    -- Identity-only zones: their pieces read name/level, which change only on
    -- identity edges (UNIT_NAME_UPDATE, UNIT_LEVEL, repoints, provider
    -- callbacks) -- Blizzard paints names on UNIT_NAME_UPDATE alone. Not
    -- listed: nametotarget (target names churn) and group (repainted by the
    -- roster pass at the end of this block).
    local ZONE_IDENTITY = { name = true, levelname = true, namelevel = true, level = true }
    -- Value-class events and the value each one moves. A value event repaints
    -- only the zones that read that value (a static zone none of them); anything
    -- else (identity events, ForceUpdate, UnitChanged, Poll, PEW, nil) repaints
    -- every zone. Resettle follows a max-health change; the two absorb-end
    -- events cover either absorb kind.
    local VALUE_CLASS = {
        UNIT_HEALTH = "hp",
        UNIT_MAXHEALTH = "hp",
        UNIT_MAX_HEALTH_MODIFIERS_CHANGED = "hp",
        Resettle = "hp",
        UNIT_POWER_UPDATE = "pp",
        UNIT_MAXPOWER = "pp",
        UNIT_DISPLAYPOWER = "pp",
        UNIT_ABSORB_AMOUNT_CHANGED = "abs",
        UNIT_HEAL_ABSORB_AMOUNT_CHANGED = "habs",
        CUI_AbsorbEnd = "absany",
        CUI_AbsorbBelt = "absany",
        UNIT_TARGET = "tgt",
    }
    -- What each piece reads: "hp" health, "pp" power, "abs" / "habs" the two
    -- absorb amounts, "id" name or level only (identity events repaint those),
    -- "roster" the raid group number (the roster pass repaints it). A piece not
    -- listed (the target pieces and separators, the Name Format twins) makes
    -- its zone repaint on every value event.
    local PIECE_READS = {
        [P.perhp] = "hp",
        [P.perhpnosign] = "hp",
        [P.curhpshort] = "hp",
        [P.healthshort] = "hp",
        [P.maxhpshort] = "hp",
        [P.curhp] = "hp",
        [P.maxhp] = "hp",
        [P.perpp] = "pp",
        [P.curpp] = "pp",
        [P.maxpp] = "pp",
        [P.curppfull] = "pp",
        [P.maxppfull] = "pp",
        [P.absorb] = "abs",
        [P.absorbshort] = "abs",
        [P.healabsorb] = "habs",
        [P.healabsorbshort] = "habs",
        [P.absorbshorttag] = "abs",
        [P.healabsorbshorttag] = "habs",
        [P.name] = "id",
        [P.level] = "id",
        [P.levelcol] = "id",
        [P.levelcolall] = "id",
        [P.group] = "roster",
    }
    -- The tags' Name Format modifiers ([name:abbr]): they shape the plain name,
    -- whatever the slot's own Name Format says. [name:last] and [target:last]
    -- show nothing for your own unit while your name is your first name alone
    -- (OwnSurnameHidden: WoW Forever, Blizzard's My Surname off).
    local function Shaped(piece, modeName, ofTarget)
        if modeName ~= "last" then
            return function(unitToken)
                return CludesUI.ShortName(piece(unitToken), modeName)
            end
        end
        return function(unitToken)
            if CludesUI.OwnSurnameHidden(ofTarget and unitToken and (unitToken .. "target") or unitToken) then
                return ""
            end
            return CludesUI.ShortName(piece(unitToken), modeName)
        end
    end
    for _, modeName in ipairs({ "first", "last", "abbr" }) do
        P["name" .. modeName] = Shaped(P.name, modeName)
        P["tgt" .. modeName] = Shaped(P.tgtname, modeName, true)
        PIECE_READS[P["name" .. modeName]] = "id"
    end

    -- Custom content: the slot's own format string (<prefix>CustomFormat),
    -- parsed by CludesUI.TextTags against this binding of the unit schema.
    -- Options, preview and the width estimate read the same catalog.
    local TAG_CATALOG = CludesUI.TextTags.Bind(CludesUI.TextTags.UNIT, {
        ["hp"] = P.curhp,
        ["hp:abr"] = P.curhpshort,
        ["hp:max"] = P.maxhp,
        ["hp:max:abr"] = P.maxhpshort,
        ["hp:pct"] = P.perhp,
        ["pp"] = P.curppfull,
        ["pp:abr"] = P.curpp,
        ["pp:max"] = P.maxppfull,
        ["pp:max:abr"] = P.maxpp,
        ["pp:pct"] = P.perpp,
        ["absorb"] = P.absorb,
        ["absorb:abr"] = P.absorbshorttag,
        ["healabsorb"] = P.healabsorb,
        ["healabsorb:abr"] = P.healabsorbshorttag,
        ["name"] = P.name,
        ["name:first"] = P.namefirst,
        ["name:last"] = P.namelast,
        ["name:abbr"] = P.nameabbr,
        ["target"] = P.tgtname,
        ["target:first"] = P.tgtfirst,
        ["target:last"] = P.tgtlast,
        ["target:abbr"] = P.tgtabbr,
        ["level"] = P.level,
        ["group"] = P.group,
    })
    mod.UF_TextTags = TAG_CATALOG

    --- Resolves a content key to (fmt, piecesArray, static) for a zone, or nil
    --- for "none"/unknown. nametotarget builds its settings-closure separator.
    function mod.ContentToZone(contentFrame, prefixText, prefs)
        if contentFrame == "custom" then
            local parsed = CludesUI.TextTags.Parse(TAG_CATALOG, prefs and prefs[prefixText .. "CustomFormat"])
            if not parsed then
                return nil
            end
            local keyList, map, pieceList = parsed.keys, TAG_CATALOG.map, {}
            local lvlCol = prefs.levelDifficultyColor
            for i = 1, #keyList do
                local tagKey = keyList[i]
                if tagKey == "level" and lvlCol then
                    pieceList[i] = prefs.levelDifficultyColorFriendly and P.levelcolall or P.levelcol
                else
                    pieceList[i] = map[tagKey]
                end
            end
            -- Static (identity repaints only) unless a tag reads a value.
            local static = true
            for classFile in pairs(parsed.reads) do
                if classFile ~= "id" then
                    static = nil
                    break
                end
            end
            return parsed.fmt, pieceList, static
        end
        if contentFrame == "nametotarget" then
            return "%s%s%s%s", { P.name, mod.MakeTgtSepPiece(prefixText, prefs), P.tgtcol, P.tgtname }
        end
        -- Target: the unit's target name alone, after the slot's Prefix
        -- (nil = "T:", "" = none) in the Indicator Color. The target's colour
        -- escape rides only while the slot is Class Colored; otherwise the
        -- name keeps the slot colour. Every piece is "" without a target.
        if contentFrame == "targetname" then
            local pieceList = {}
            local pre = prefs[prefixText .. "TargetPrefix"]
            if type(pre) ~= "string" then
                pre = "T:"
            end
            if pre ~= "" then
                pieceList[1] = mod.MakeTgtSepPiece(prefixText, prefs, pre .. " ")
            end
            if prefs[prefixText .. "ClassColor"] then
                pieceList[#pieceList + 1] = P.tgtcol
            end
            pieceList[#pieceList + 1] = P.tgtname
            return string.rep("%s", #pieceList), pieceList
        end
        local def = ZONE_STATIC[contentFrame]
        if not def then
            return nil
        end
        local pieceList = {}
        local lvlCol = prefs and prefs.levelDifficultyColor
        for i = 2, #def do
            local tagKey = def[i]
            if tagKey == "level" and lvlCol then
                tagKey = prefs.levelDifficultyColorFriendly and "levelcolall" or "levelcol"
            end
            pieceList[#pieceList + 1] = P[tagKey]
        end
        return def[1], pieceList, ZONE_IDENTITY[contentFrame] or nil
    end

    -- Name Format: a slot set to one (<prefix>NameFormat) gets short-name twins
    -- of its name pieces when the zone is applied, so the painter and every
    -- unset slot run as before. Level, separator and colour pieces stay; Name >
    -- Target shortens both names. ShortName passes a secret name through whole
    -- and caches the short forms, so a zone repainted on every health tick
    -- builds no strings. A mode's twins are made the first time a slot uses it.
    -- Each twin asks CludesUI.UnitNameFormat for the unit whose name it
    -- shows (WoW Forever: First / Last Name leave a non-player's name whole).
    do
        local short, unitMode = CludesUI.ShortName, CludesUI.UnitNameFormat
        local nameFn, tgtFn = P.name, P.tgtname
        local twinsByMode = {}
        local base = mod.ContentToZone
        function mod.ContentToZone(contentFrame, prefixText, prefs)
            local fmt, pieceList, static = base(contentFrame, prefixText, prefs)
            local modeName = fmt and prefs and prefs[prefixText .. "NameFormat"]
            if modeName and CludesUI.IsNameFormat(modeName) then
                local twins = twinsByMode[modeName]
                if not twins then
                    twins = {
                        [nameFn] = function(unit)
                            return short(nameFn(unit), unitMode(modeName, unit))
                        end,
                        [tgtFn] = function(unit)
                            return short(tgtFn(unit), unitMode(modeName, unit and (unit .. "target")))
                        end,
                    }
                    twinsByMode[modeName] = twins
                end
                for i = 1, #pieceList do
                    pieceList[i] = twins[pieceList[i]] or pieceList[i]
                end
            end
            return fmt, pieceList, static
        end
    end

    -- The text painter: renders the frame's zones. Piece returns route through
    -- a scratch table + unpack (tables carry secrets fine; nothing inspects
    -- them). A value event repaints only the zones that read its value (a
    -- health tick leaves power text and name/level zones alone), each at most
    -- once per hardware frame: the engine does not collapse this channel, since
    -- a health paint must not swallow a power repaint landing in the same frame.
    local scratch = {}
    local GetTime = GetTime
    local function PaintText(widget, unitToken, evt)
        local zoneList = widget._cuiTextZones
        if not zoneList then
            return
        end
        -- An empty token renders every zone blank, and a boss frame outlives the
        -- gap: the unit watch is a 0.2s poll, so the frame is still shown while
        -- its slot sits between units. Same probe the health painter pays.
        if not (unitToken and UnitExists(unitToken)) then
            return
        end
        -- Faction flip: slot colour is set by ApplyClassColor, never by the
        -- pieces below, so recolour first (the health bar recolours on this
        -- same event); the render then refreshes any target-colour piece.
        if evt == "UNIT_FACTION" and mod.UF_RecolorTexts then
            mod.UF_RecolorTexts(widget, unitToken)
        end
        local classFile = evt ~= nil and VALUE_CLASS[evt]
        local nowTime = GetTime()
        for i = 1, #zoneList do
            local z = zoneList[i]
            if not classFile or (not z.static and (z.any or z[classFile]) and z.at ~= nowTime) then
                z.at = nowTime
                local pieceList = z.pieces
                local num = #pieceList
                for k = 1, num do
                    scratch[k] = pieceList[k](unitToken)
                end
                z.fs:SetFormattedText(z.fmt, unpack(scratch, 1, num))
            end
        end
    end
    mod.UF_PaintText = PaintText
    mod.Engine.SetPainter("text", PaintText)

    -- Power-only text repaint for the power value pass: renders just the
    -- zones whose pieces read the unit's power (flagged when the zone is set).
    function mod.UF_PaintPowerText(widget, unitToken)
        local zoneList = widget._cuiTextZones
        if not zoneList then
            return
        end
        for i = 1, #zoneList do
            local z = zoneList[i]
            if z.power then
                local pieceList = z.pieces
                local num = #pieceList
                for k = 1, num do
                    scratch[k] = pieceList[k](unitToken)
                end
                z.fs:SetFormattedText(z.fmt, unpack(scratch, 1, num))
            end
        end
    end

    -- The roster pass (end of this block): hidden, and with no event until
    -- MarkReads stamps the first zone that reads the roster.
    local rosterEv = CreateFrame("Frame")
    rosterEv:Hide()

    -- Stamps a new zone with the values its pieces read (PIECE_READS): one
    -- field per value class for PaintText's filter, any = an unlisted piece,
    -- power for the power value pass and roster for the roster pass.
    local function MarkReads(z)
        local pieceList = z.pieces
        for i = 1, #pieceList do
            local region = PIECE_READS[pieceList[i]]
            if region == nil then
                z.any = true
            elseif region ~= "id" then
                z[region] = true
            end
        end
        if z.abs or z.habs then
            z.absany = true
        end
        z.power = z.pp
        if z.roster then
            rosterEv:RegisterEvent("GROUP_ROSTER_UPDATE")
        end
        return z
    end

    --- Registers/updates one text zone on a frame: resolves the content key
    --- and stores the def the text painter renders. nil/none content removes
    --- the zone (the position code hides the fontstring separately, as
    --- before). Zones are keyed by fontstring; re-apply replaces in place.
    function mod.SetTextZone(widget, fontStr, contentFrame, prefixText, prefs)
        local zoneList = widget._cuiTextZones
        if not zoneList then
            zoneList = {}
            widget._cuiTextZones = zoneList
        end
        local fmt, pieceList, static
        if contentFrame then
            fmt, pieceList, static = mod.ContentToZone(contentFrame, prefixText, prefs)
        end
        for i = #zoneList, 1, -1 do
            if zoneList[i].fs == fontStr then
                table.remove(zoneList, i)
            end
        end
        if fmt then
            zoneList[#zoneList + 1] = MarkReads({ fs = fontStr, fmt = fmt, pieces = pieceList, static = static })
        else
            fontStr:SetText("")
        end
        -- A power text zone added or removed can switch the player's power
        -- value channel, and a hidden power bar's element (UF_PowerElementSync).
        mod.UF_PowerElementSync(widget)
    end

    --- Raw-zone variant for callers that assemble their own format (the power
    --- percent text's curpp/perpp/smart combinations). nil fmt removes.
    function mod.SetTextZoneRaw(widget, fontStr, fmt, pieceList)
        local zoneList = widget._cuiTextZones
        if not zoneList then
            zoneList = {}
            widget._cuiTextZones = zoneList
        end
        for i = #zoneList, 1, -1 do
            if zoneList[i].fs == fontStr then
                table.remove(zoneList, i)
            end
        end
        if fmt then
            zoneList[#zoneList + 1] = MarkReads({ fs = fontStr, fmt = fmt, pieces = pieceList })
        else
            fontStr:SetText("")
        end
        mod.UF_PowerElementSync(widget)
    end

    -- A raid subgroup move fires only GROUP_ROSTER_UPDATE: no unit event and
    -- no value tick. A burst of them shows the frame once; on the next frame it
    -- hides itself and repaints only the zones that read the roster (a frame
    -- without a unit stays as PaintText leaves it). With no such zone left the
    -- event goes, and MarkReads registers it again.
    rosterEv:SetScript("OnEvent", function(self)
        self:Show()
    end)
    rosterEv:SetScript("OnUpdate", function(self)
        self:Hide()
        local kept = false
        for _, frame in pairs(frameList) do
            local zoneList = type(frame) == "table" and frame._cuiTextZones
            if zoneList then
                local unitToken = frame._cuiUnit
                local live = unitToken and UnitExists(unitToken)
                for i = 1, #zoneList do
                    local z = zoneList[i]
                    if z.roster then
                        kept = true
                        if live then
                            local pieceList = z.pieces
                            local num = #pieceList
                            for k = 1, num do
                                scratch[k] = pieceList[k](unitToken)
                            end
                            z.fs:SetFormattedText(z.fmt, unpack(scratch, 1, num))
                        end
                    end
                end
            end
        end
        if not kept then
            self:UnregisterEvent("GROUP_ROSTER_UPDATE")
        end
    end)
end

Inner.CUI_IsSmartPowerPercent, Inner.ResolveRestrictedClassColor =
    CUI_IsSmartPowerPercent, ResolveRestrictedClassColor
Inner.PLAYER_POWER_DEFAULT, Inner.PLAYER_POWER_ALT = PLAYER_POWER_DEFAULT, PLAYER_POWER_ALT
